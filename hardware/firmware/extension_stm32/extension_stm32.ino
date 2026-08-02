/*
 * Unisync - Extension Firmware v4.4
 * STM32G030F6P6 -- Arduino IDE + STM32duino + LL drivers
 *
 * Build settings:
 *   Board:           Generic STM32G0 series / Generic G030F6Px
 *   Optimize:        Smallest (-Os) with LTO
 *   C Runtime:       Newlib Nano
 *   Upload:          STM32CubeProgrammer (SWD)
 *
 * Pin assignments (breakout board -- PA9/PA10 remapped to PA11/PA12):
 *   PA0  - TOUCH1      (TTP223 -- HIGH on touch)
 *   PA1  - TOUCH2      (TTP223 -- HIGH on touch)
 *   PA2  - RS485_TX    (USART1 TX -- AF1)
 *   PA3  - RS485_RX    (USART1 RX -- AF1)
 *   PA4  - RS485_DE    (MAX3485 DE/RE# -- HIGH=TX, LOW=RX)
 *   PA5  - LED1        (active LOW -- ON when switch OFF, OFF when switch ON)
 *   PA6  - LED2        (active LOW -- ON when switch OFF, OFF when switch ON)
 *   PA7  - LED3        (TIM17_CH1 AF5 -- hardware PWM breathing heartbeat)
 *   PA11 - RELAY1_DRV  (S8050 NPN -- HIGH=ON, LOW=OFF)
 *   PA12 - RELAY2_DRV  (S8050 NPN -- HIGH=ON, LOW=OFF)
 *   PA13 - SWDIO
 *   PA14 - SWDCLK + BOOT0 pulldown
 */

#include "Arduino.h"
#include <stm32g0xx_ll_usart.h>
#include <stm32g0xx_ll_gpio.h>
#include <stm32g0xx_ll_bus.h>
#include <stm32g0xx_ll_tim.h>

/* ================================================================
 * GPIO MACROS
 * ================================================================ */
#define PIN_SET(pin)    (GPIOA->BSRR = (1u << (pin)))
#define PIN_CLR(pin)    (GPIOA->BRR  = (1u << (pin)))
#define PIN_READ(pin)   ((GPIOA->IDR  >> (pin)) & 1u)

#define PIN_TOUCH1     0
#define PIN_TOUCH2     1
/* PA2/PA3 = USART1 TX/RX via SYSCFG remap */
#define PIN_RS485_DE   4
#define PIN_LED1       5   /* active LOW */
#define PIN_LED2       6   /* active LOW */
/* PA7 = TIM17_CH1 PWM -- controlled via timer, not PIN_SET/CLR */
#define PIN_RELAY1     11
#define PIN_RELAY2     12

/* ================================================================
 * PROTOCOL
 * ================================================================ */
#define UART_BAUD         250000
#define SOF               0xAA
#define ADDR_MASTER       0x00
#define ADDR_UNASSIGNED   0xFE
#define ADDR_BCAST        0xFF

#define CMD_PING          0x00
#define CMD_PONG          0x01
#define CMD_SET_RELAY     0x20
#define CMD_GET_STATE     0x21
#define CMD_STATE_RESP    0x22
#define CMD_DRAIN_EVENTS  0x23
#define CMD_IDENTIFY      0x30
#define CMD_OTA_BEGIN     0x40
#define CMD_OTA_CHUNK     0x41
#define CMD_OTA_END       0x42
#define CMD_OTA_ACK       0x43
#define CMD_BUS_QUIET     0x44
#define CMD_ERROR         0xF0
#define CMD_ANNOUNCE      0x50
#define CMD_WELCOME       0x51
#define CMD_REJECT        0x52
#define CMD_CHALLENGE     0x54
#define CMD_RESPONSE      0x55

static const uint8_t SECRET_KEY[16] = {
    0x55,0x6E,0x69,0x73,0x79,0x6E,0x63,0x53,
    0x77,0x69,0x74,0x63,0x68,0x4B,0x65,0x79
};

/* ================================================================
 * FLASH EEPROM EMULATION
 * ================================================================ */
#define NVS_PAGE_ADDR   0x08007800UL
#define NVS_PAGE_SIZE   2048

#define NVS_MAGIC       0
#define NVS_ADDR        1
#define NVS_RELAY       2
#define NVS_MUID0       3
#define NVS_MUID1       4
#define NVS_MUID2       5
#define NVS_MUID3       6
#define NVS_MAGIC_VAL   0xA5

static uint8_t nvs_shadow[8];

static void nvs_load(void) {
    volatile uint8_t *p = (volatile uint8_t *)NVS_PAGE_ADDR;
    for (uint8_t i = 0; i < 8; i++) nvs_shadow[i] = p[i];
}

static void nvs_flush(void) {
    if (READ_BIT(FLASH->CR, FLASH_CR_LOCK)) {
        WRITE_REG(FLASH->KEYR, 0x45670123UL);
        WRITE_REG(FLASH->KEYR, 0xCDEF89ABUL);
    }
    MODIFY_REG(FLASH->CR, FLASH_CR_PNB,
               (((NVS_PAGE_ADDR - FLASH_BASE) / NVS_PAGE_SIZE) << FLASH_CR_PNB_Pos));
    SET_BIT(FLASH->CR, FLASH_CR_PER);
    SET_BIT(FLASH->CR, FLASH_CR_STRT);
    while (READ_BIT(FLASH->SR, FLASH_SR_BSY1));
    CLEAR_BIT(FLASH->CR, FLASH_CR_PER);
    SET_BIT(FLASH->CR, FLASH_CR_PG);
    volatile uint32_t *dst = (volatile uint32_t *)NVS_PAGE_ADDR;
    uint32_t w0, w1;
    memcpy(&w0, &nvs_shadow[0], 4);
    memcpy(&w1, &nvs_shadow[4], 4);
    dst[0] = w0; dst[1] = w1;
    while (READ_BIT(FLASH->SR, FLASH_SR_BSY1));
    CLEAR_BIT(FLASH->CR, FLASH_CR_PG);
    SET_BIT(FLASH->CR, FLASH_CR_LOCK);
}

/* ================================================================
 * TIM17 HARDWARE PWM -- PA7 (AF5) -- breathing heartbeat
 *
 * TIM17 is a 16-bit timer. Config:
 *   ARR  = 255  (8-bit resolution, ~47kHz @ 12MHz)
 *   CCR1 = 0-255 (duty cycle)
 *   PA7 in AF5 mode = TIM17_CH1
 *
 * Breathing: 32-step sine table, updated every 30ms from loop()
 * No blocking, no ISR needed -- pure hardware PWM output
 * ================================================================ */

/* Sine-based brightness table (32 steps, 0-255, one breath cycle) */
static const uint8_t BREATH_TABLE[32] = {
      2,   4,  10,  20,  34,  51,  71,  93,
    115, 137, 157, 175, 190, 202, 210, 215,
    217, 215, 210, 202, 190, 175, 157, 137,
    115,  93,  71,  51,  34,  20,  10,   4
};

static void tim17_pwm_init(void) {
    /* Enable TIM17 and GPIOA clocks */
    SET_BIT(RCC->APBENR2, RCC_APBENR2_TIM17EN);
    LL_IOP_GRP1_EnableClock(LL_IOP_GRP1_PERIPH_GPIOA);

    /* PA7 = TIM17_CH1 (AF5) */
    LL_GPIO_SetPinMode(GPIOA,      LL_GPIO_PIN_7, LL_GPIO_MODE_ALTERNATE);
    LL_GPIO_SetAFPin_0_7(GPIOA,    LL_GPIO_PIN_7, LL_GPIO_AF_5);
    LL_GPIO_SetPinSpeed(GPIOA,     LL_GPIO_PIN_7, LL_GPIO_SPEED_FREQ_LOW);
    LL_GPIO_SetPinOutputType(GPIOA,LL_GPIO_PIN_7, LL_GPIO_OUTPUT_PUSHPULL);

    /* Configure TIM17: prescaler=0, ARR=255, PWM mode 1 */
    TIM17->PSC  = 0;
    TIM17->ARR  = 255;
    TIM17->CCR1 = 0;
    /* PWM mode 1 on CH1, preload enable */
    TIM17->CCMR1 = (6u << TIM_CCMR1_OC1M_Pos) | TIM_CCMR1_OC1PE;
    /* Enable CH1 output, active high */
    TIM17->CCER  = TIM_CCER_CC1E;
    /* Enable main output (required for advanced timers) */
    TIM17->BDTR  = TIM_BDTR_MOE;
    /* Start timer */
    TIM17->CR1   = TIM_CR1_CEN;
}

/* Call from loop() -- non-blocking, updates PWM duty every 30ms */
static void breath_tick(void) {
    static uint32_t last_ms  = 0;
    static uint8_t  step     = 0;
    static bool     identify = false;
    static uint8_t  id_count = 0;

    if (identify) {
        /* Fast full-on/off blink for identify command */
        if ((millis() - last_ms) >= 125) {
            last_ms = millis();
            TIM17->CCR1 = (id_count & 1) ? 255 : 0;
            if (++id_count >= 8) { identify = false; id_count = 0; }
        }
        return;
    }

    if ((millis() - last_ms) < 30) return;
    last_ms = millis();

    if (mode == MODE_REGISTERED) {
        /* Slow breathing: full cycle = 32 steps * 30ms = ~1s */
        TIM17->CCR1 = BREATH_TABLE[step & 0x1F];
        step++;
    } else {
        /* Fast breathing when unregistered: skip every other step */
        TIM17->CCR1 = BREATH_TABLE[step & 0x1F];
        step += 2;
    }
}

/* Call once to trigger identify blink */
static void breath_identify(void) {
    /* handled inside breath_tick via static state */
    TIM17->CCR1 = 0;
}

/* ================================================================
 * USART1 LL DRIVER
 * PA11=TX, PA12=RX via SYSCFG remap (PA9/PA10 not exposed on board)
 * ================================================================ */
static void usart1_init(void) {
    LL_APB2_GRP1_EnableClock(LL_APB2_GRP1_PERIPH_USART1);
    LL_APB2_GRP1_EnableClock(LL_APB2_GRP1_PERIPH_SYSCFG);
    LL_IOP_GRP1_EnableClock(LL_IOP_GRP1_PERIPH_GPIOA);

    /* Remap PA11/PA12 to USART1 TX/RX */
    SYSCFG->CFGR1 |= SYSCFG_CFGR1_PA11_RMP | SYSCFG_CFGR1_PA12_RMP;

    /* PA11 = TX (AF1 after remap), PA12 = RX (AF1 after remap) */
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_11, LL_GPIO_MODE_ALTERNATE);
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_12, LL_GPIO_MODE_ALTERNATE);
    LL_GPIO_SetAFPin_8_15(GPIOA, LL_GPIO_PIN_11, LL_GPIO_AF_1);
    LL_GPIO_SetAFPin_8_15(GPIOA, LL_GPIO_PIN_12, LL_GPIO_AF_1);
    LL_GPIO_SetPinSpeed(GPIOA,      LL_GPIO_PIN_11, LL_GPIO_SPEED_FREQ_HIGH);
    LL_GPIO_SetPinOutputType(GPIOA, LL_GPIO_PIN_11, LL_GPIO_OUTPUT_PUSHPULL);
    LL_GPIO_SetPinPull(GPIOA,       LL_GPIO_PIN_12, LL_GPIO_PULL_UP);

    LL_USART_SetBaudRate(USART1, SystemCoreClock, LL_USART_PRESCALER_DIV1,
                         LL_USART_OVERSAMPLING_16, UART_BAUD);
    LL_USART_SetDataWidth(USART1,      LL_USART_DATAWIDTH_8B);
    LL_USART_SetStopBitsLength(USART1, LL_USART_STOPBITS_1);
    LL_USART_SetParity(USART1,         LL_USART_PARITY_NONE);
    LL_USART_SetTransferDirection(USART1, LL_USART_DIRECTION_TX_RX);
    LL_USART_Enable(USART1);
    while (!LL_USART_IsActiveFlag_TEACK(USART1) ||
           !LL_USART_IsActiveFlag_REACK(USART1));
}

static void usart1_write_byte(uint8_t b) {
    while (!LL_USART_IsActiveFlag_TXE(USART1));
    LL_USART_TransmitData8(USART1, b);
}

static void usart1_wait_tc(void) {
    while (!LL_USART_IsActiveFlag_TC(USART1));
}

static bool usart1_available(void) {
    return LL_USART_IsActiveFlag_RXNE(USART1);
}

static uint8_t usart1_read_byte(void) {
    return LL_USART_ReceiveData8(USART1);
}

/* ================================================================
 * GPIO INIT
 * ================================================================ */
static void gpio_init(void) {
    LL_IOP_GRP1_EnableClock(LL_IOP_GRP1_PERIPH_GPIOA);

    /* Outputs: RS485_DE(PA4), LED1(PA5), LED2(PA6), RELAY1(PA11), RELAY2(PA12) */
    /* PA7 configured separately by tim17_pwm_init() */
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_4,  LL_GPIO_MODE_OUTPUT);
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_5,  LL_GPIO_MODE_OUTPUT);
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_6,  LL_GPIO_MODE_OUTPUT);
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_11, LL_GPIO_MODE_OUTPUT);
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_12, LL_GPIO_MODE_OUTPUT);

    /* Inputs: TOUCH1(PA0), TOUCH2(PA1) */
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_0, LL_GPIO_MODE_INPUT);
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_1, LL_GPIO_MODE_INPUT);
    LL_GPIO_SetPinPull(GPIOA, LL_GPIO_PIN_0, LL_GPIO_PULL_NO);
    LL_GPIO_SetPinPull(GPIOA, LL_GPIO_PIN_1, LL_GPIO_PULL_NO);

    /* All outputs LOW -- relays OFF, DE in RX mode */
    /* LED1/LED2 active LOW so LOW = LED ON -- set HIGH to turn OFF at boot */
    GPIOA->BRR  = LL_GPIO_PIN_4 | LL_GPIO_PIN_11 | LL_GPIO_PIN_12;
    GPIOA->BSRR = LL_GPIO_PIN_5 | LL_GPIO_PIN_6;  /* LEDs OFF at boot */
}

/* ================================================================
 * CHIP UID
 * ================================================================ */
static uint8_t device_uid[4] = {0};

static void uid_init(void) {
    uint32_t w = ((volatile uint32_t *)0x1FFF7590UL)[2];
    device_uid[0] = (w >> 24) & 0xFF;
    device_uid[1] = (w >> 16) & 0xFF;
    device_uid[2] = (w >>  8) & 0xFF;
    device_uid[3] = (w)       & 0xFF;
}

/* ================================================================
 * CRC-8
 * ================================================================ */
static uint8_t crc8(uint8_t *data, uint8_t len) {
    uint8_t crc = 0x00;
    while (len--) {
        crc ^= *data++;
        for (uint8_t i = 0; i < 8; i++)
            crc = (crc & 0x80) ? (crc << 1) ^ 0x07 : crc << 1;
    }
    return crc;
}

/* ================================================================
 * HW CRC32
 * ================================================================ */
static void hw_crc_init(void) {
    SET_BIT(RCC->AHBENR, RCC_AHBENR_CRCEN);
}

static uint32_t crc32_compute(const uint8_t *data, uint8_t len) {
    CRC->CR = CRC_CR_RESET;
    volatile uint8_t *dr8 = (volatile uint8_t *)&CRC->DR;
    while (len--) *dr8 = *data++;
    return CRC->DR;
}

static uint32_t compute_response(const uint8_t *challenge) {
    uint8_t buf[24];
    for (uint8_t i = 0; i < 16; i++) buf[i]    = SECRET_KEY[i];
    for (uint8_t i = 0; i < 4;  i++) buf[16+i] = challenge[i];
    for (uint8_t i = 0; i < 4;  i++) buf[20+i] = device_uid[i];
    return crc32_compute(buf, 24);
}

/* ================================================================
 * PSEUDO-RANDOM
 * ================================================================ */
static uint32_t rand_seed = 0;
static uint16_t pseudo_rand(uint16_t max) {
    rand_seed = rand_seed * 1664525UL + 1013904223UL;
    return (uint16_t)((rand_seed >> 16) % max);
}

/* ================================================================
 * STATE
 * ================================================================ */
#define ORPHAN_TIMEOUT_MS  30000UL

typedef enum {
    MODE_UNREGISTERED = 0,
    MODE_REGISTERED,
    MODE_OTA,
    MODE_QUIET
} ext_mode_t;

static ext_mode_t mode          = MODE_UNREGISTERED;
static uint8_t    slot_address  = ADDR_UNASSIGNED;
static uint8_t    master_uid[4] = {0};
static bool       relay1_state  = false;
static bool       relay2_state  = false;

#define EVENT_BUF_SIZE 16
typedef struct {
    uint8_t  channel;
    uint8_t  state;
    uint32_t ts_ms;
} touch_event_t;

static touch_event_t event_buf[EVENT_BUF_SIZE];
static uint8_t       event_head  = 0;
static uint8_t       event_tail  = 0;
static uint8_t       event_count = 0;

static bool     last_t1         = false;
static bool     last_t2         = false;
static uint32_t last_poll_ms    = 0;
static bool     poll_received   = false;

static uint8_t  rx_buf[40];
static uint8_t  rx_pos          = 0;
static uint8_t  rx_elen         = 0;

static uint32_t last_announce_ms  = 0;
static uint32_t announce_interval = 2000;

/* ================================================================
 * PERSISTENCE
 * ================================================================ */
static void load_state(void) {
    nvs_load();
    if (nvs_shadow[NVS_MAGIC] != NVS_MAGIC_VAL) {
        mode         = MODE_UNREGISTERED;
        slot_address = ADDR_UNASSIGNED;
        return;
    }
    slot_address  = nvs_shadow[NVS_ADDR];
    master_uid[0] = nvs_shadow[NVS_MUID0];
    master_uid[1] = nvs_shadow[NVS_MUID1];
    master_uid[2] = nvs_shadow[NVS_MUID2];
    master_uid[3] = nvs_shadow[NVS_MUID3];
    relay1_state  = (nvs_shadow[NVS_RELAY] & 0x01) != 0;
    relay2_state  = (nvs_shadow[NVS_RELAY] & 0x02) != 0;
    mode          = MODE_REGISTERED;
}

static void save_registration(uint8_t addr, uint8_t *m_uid) {
    nvs_shadow[NVS_ADDR]  = addr;
    nvs_shadow[NVS_MUID0] = m_uid[0];
    nvs_shadow[NVS_MUID1] = m_uid[1];
    nvs_shadow[NVS_MUID2] = m_uid[2];
    nvs_shadow[NVS_MUID3] = m_uid[3];
    nvs_shadow[NVS_MAGIC] = NVS_MAGIC_VAL;
    nvs_shadow[NVS_RELAY] = (relay1_state ? 0x01 : 0x00) |
                             (relay2_state ? 0x02 : 0x00);
    nvs_flush();
}

static void wipe_registration(void) {
    memset(nvs_shadow, 0, sizeof(nvs_shadow));
    nvs_flush();
}

/* ================================================================
 * RS-485 TRANSPORT
 * ================================================================ */
static void rs485_send(uint8_t *frame, uint8_t len) {
    PIN_SET(PIN_RS485_DE);
    __NOP(); __NOP(); __NOP(); __NOP();
    for (uint8_t i = 0; i < len; i++) usart1_write_byte(frame[i]);
    usart1_wait_tc();
    __NOP(); __NOP(); __NOP(); __NOP();
    PIN_CLR(PIN_RS485_DE);
}

static void send_frame(uint8_t dst, uint8_t cmd,
                       uint8_t *payload, uint8_t plen) {
    uint8_t frame[40];
    frame[0] = SOF;
    frame[1] = dst;
    frame[2] = slot_address;
    frame[3] = cmd;
    frame[4] = plen;
    memcpy(&frame[5], payload, plen);
    frame[5 + plen] = crc8(&frame[1], 4 + plen);
    rs485_send(frame, 6 + plen);
}

/* ================================================================
 * RELAY + LED CONTROL
 * LED1/LED2 are active LOW:
 *   Switch ON  -> relay HIGH, LED LOW  (LED off)
 *   Switch OFF -> relay LOW,  LED HIGH (LED on)
 * ================================================================ */
static void set_relay1(bool s) {
    relay1_state = s;
    if (s) { PIN_SET(PIN_RELAY1); PIN_CLR(PIN_LED1); }  /* relay ON,  LED off */
    else   { PIN_CLR(PIN_RELAY1); PIN_SET(PIN_LED1); }  /* relay OFF, LED on  */
}

static void set_relay2(bool s) {
    relay2_state = s;
    if (s) { PIN_SET(PIN_RELAY2); PIN_CLR(PIN_LED2); }
    else   { PIN_CLR(PIN_RELAY2); PIN_SET(PIN_LED2); }
}

/* ================================================================
 * SELF-UNREGISTER
 * ================================================================ */
static void self_unregister(void) {
    relay1_state = false; relay2_state = false;
    PIN_CLR(PIN_RELAY1); PIN_CLR(PIN_RELAY2);
    PIN_SET(PIN_LED1);   PIN_SET(PIN_LED2);   /* LEDs on (active LOW) */
    wipe_registration();
    slot_address      = ADDR_UNASSIGNED;
    mode              = MODE_UNREGISTERED;
    poll_received     = false;
    announce_interval = 2000;
    last_announce_ms  = 0;
}

/* ================================================================
 * TOUCH EVENT BUFFER
 * ================================================================ */
static void push_event(uint8_t ch, uint8_t s) {
    event_buf[event_head].channel = ch;
    event_buf[event_head].state   = s;
    event_buf[event_head].ts_ms   = millis();
    event_head = (event_head + 1) % EVENT_BUF_SIZE;
    if (event_count < EVENT_BUF_SIZE) event_count++;
    else event_tail = (event_tail + 1) % EVENT_BUF_SIZE;
}

static void drain_events(uint8_t count) {
    for (uint8_t i = 0; i < count && event_count > 0; i++) {
        event_tail = (event_tail + 1) % EVENT_BUF_SIZE;
        event_count--;
    }
}

/* ================================================================
 * TOUCH HANDLER
 * ================================================================ */
static void handle_touch(void) {
    bool t1 = PIN_READ(PIN_TOUCH1);
    bool t2 = PIN_READ(PIN_TOUCH2);
    if (t1 && !last_t1) { set_relay1(!relay1_state); push_event(1, relay1_state?1:0); }
    if (t2 && !last_t2) { set_relay2(!relay2_state); push_event(2, relay2_state?1:0); }
    last_t1 = t1;
    last_t2 = t2;
}

/* ================================================================
 * ANNOUNCE
 * ================================================================ */
static void send_announce(void) {
    uint8_t *uid = device_uid;
    uint8_t frame[11];
    frame[0]  = SOF;
    frame[1]  = ADDR_MASTER;
    frame[2]  = ADDR_UNASSIGNED;
    frame[3]  = CMD_ANNOUNCE;
    frame[4]  = 5;
    frame[5]  = uid[0]; frame[6] = uid[1];
    frame[7]  = uid[2]; frame[8] = uid[3];
    frame[9]  = (relay1_state ? 0x01 : 0x00) |
                (relay2_state ? 0x02 : 0x00) |
                (event_count  ? 0x04 : 0x00);
    frame[10] = crc8(&frame[1], 9);
    rs485_send(frame, 11);
}

/* ================================================================
 * STATE RESPONSE
 * ================================================================ */
static void send_state_resp(void) {
    uint8_t payload[3 + 5*5];
    uint8_t plen = 0;
    uint8_t flags = 0;
    if (relay1_state)  flags |= 0x01;
    if (relay2_state)  flags |= 0x02;
    if (event_count>0) flags |= 0x04;
    payload[plen++] = flags;
    payload[plen++] = 25;
    payload[plen++] = event_count;
    uint8_t tail = event_tail;
    uint8_t cnt  = event_count < 5 ? event_count : 5;
    for (uint8_t ei = 0; ei < cnt; ei++) {
        uint32_t ts  = event_buf[tail].ts_ms;
        payload[plen++] = event_buf[tail].channel;
        payload[plen++] = event_buf[tail].state;
        payload[plen++] = (ts >> 16) & 0xFF;
        payload[plen++] = (ts >>  8) & 0xFF;
        payload[plen++] = (ts)       & 0xFF;
        tail = (tail + 1) % EVENT_BUF_SIZE;
    }
    send_frame(ADDR_MASTER, CMD_STATE_RESP, payload, plen);
}

/* ================================================================
 * PROCESS FRAME
 * ================================================================ */
static void process_frame(uint8_t *frame, uint8_t len) {
    uint8_t  dst  = frame[1];
    uint8_t  cmd  = frame[3];
    uint8_t  plen = frame[4];
    uint8_t *p    = &frame[5];
    uint8_t *uid  = device_uid;
    uint8_t  buf[8];
    uint32_t uptime_s;

    if (frame[5 + plen] != crc8(&frame[1], 4 + plen)) return;

    /* UID-addressed commands */
    if (cmd == CMD_WELCOME) {
        if (plen < 10) return;
        if (p[0]!=uid[0]||p[1]!=uid[1]||p[2]!=uid[2]||p[3]!=uid[3]) return;
        if (mode == MODE_REGISTERED) {
            bool stored_valid =
                (master_uid[0]!=0xA5||master_uid[1]!=0xA5||
                 master_uid[2]!=0xA5||master_uid[3]!=0xA5) &&
                (master_uid[0]!=0x00||master_uid[1]!=0x00||
                 master_uid[2]!=0x00||master_uid[3]!=0x00);
            if (stored_valid) {
                bool same = (p[6]==master_uid[0]&&p[7]==master_uid[1]&&
                             p[8]==master_uid[2]&&p[9]==master_uid[3]);
                if (!same) { send_frame(ADDR_MASTER,CMD_ERROR,uid,4); return; }
            }
        }
        uint8_t new_addr = p[4];
        bool    new_r1   = (p[5] & 0x01) != 0;
        bool    new_r2   = (p[5] & 0x02) != 0;
        uint8_t m_uid[4] = {p[6],p[7],p[8],p[9]};
        save_registration(new_addr, m_uid);
        slot_address = new_addr;
        memcpy(master_uid, m_uid, 4);
        mode = MODE_REGISTERED;
        set_relay1(new_r1);
        set_relay2(new_r2);
        uptime_s = millis() / 1000;
        buf[0]=1; buf[1]=0;
        buf[2]=(uptime_s>>24)&0xFF; buf[3]=(uptime_s>>16)&0xFF;
        buf[4]=(uptime_s>> 8)&0xFF; buf[5]=(uptime_s)    &0xFF;
        send_frame(ADDR_MASTER, CMD_PONG, buf, 6);
        last_poll_ms      = millis();
        poll_received     = false;
        last_announce_ms  = millis() + 30000UL;
        announce_interval = 2000;
        return;
    }

    if (cmd == CMD_REJECT) {
        if (plen < 4) return;
        if (p[0]!=uid[0]||p[1]!=uid[1]||p[2]!=uid[2]||p[3]!=uid[3]) return;
        announce_interval = 10000;
        return;
    }

    if (cmd == CMD_CHALLENGE) {
        if (plen < 8) return;
        if (p[0]!=uid[0]||p[1]!=uid[1]||p[2]!=uid[2]||p[3]!=uid[3]) return;
        uint32_t resp = compute_response(&p[4]);
        uint8_t payload[8];
        payload[0]=uid[0]; payload[1]=uid[1];
        payload[2]=uid[2]; payload[3]=uid[3];
        payload[4]=(resp>>24)&0xFF; payload[5]=(resp>>16)&0xFF;
        payload[6]=(resp>> 8)&0xFF; payload[7]=(resp)    &0xFF;
        uint8_t fr[14];
        fr[0]=SOF; fr[1]=ADDR_MASTER; fr[2]=ADDR_UNASSIGNED;
        fr[3]=CMD_RESPONSE; fr[4]=8;
        memcpy(&fr[5], payload, 8);
        fr[13]=crc8(&fr[1],12);
        rs485_send(fr,14);
        return;
    }

    /* Bus-address commands */
    bool for_me = (dst == slot_address) || (dst == ADDR_BCAST);
    if (!for_me) return;

    switch (cmd) {

    case CMD_PING:
        uptime_s = millis() / 1000;
        buf[0]=1; buf[1]=0;
        buf[2]=(uptime_s>>24)&0xFF; buf[3]=(uptime_s>>16)&0xFF;
        buf[4]=(uptime_s>> 8)&0xFF; buf[5]=(uptime_s)    &0xFF;
        send_frame(ADDR_MASTER, CMD_PONG, buf, 6);
        break;

    case CMD_GET_STATE:
        last_poll_ms  = millis();
        poll_received = true;
        send_state_resp();
        break;

    case CMD_SET_RELAY:
        if (plen < 1) break;
        set_relay1((p[0] & 0x01) != 0);
        set_relay2((p[0] & 0x02) != 0);
        send_state_resp();
        break;

    case CMD_DRAIN_EVENTS:
        if (plen < 1) break;
        drain_events(p[0]);
        break;

    case CMD_IDENTIFY:
        breath_identify();
        break;

    case CMD_BUS_QUIET:
        mode = MODE_QUIET;
        break;

    case CMD_OTA_BEGIN:
        mode   = MODE_OTA;
        buf[0] = 0x00;
        send_frame(ADDR_MASTER, CMD_OTA_ACK, buf, 1);
        break;

    case CMD_OTA_END:
        buf[0] = 0x00;
        send_frame(ADDR_MASTER, CMD_OTA_ACK, buf, 1);
        mode = MODE_REGISTERED;
        break;

    default:
        buf[0]=cmd; buf[1]=0x01;
        send_frame(ADDR_MASTER, CMD_ERROR, buf, 2);
        break;
    }
}

/* ================================================================
 * BUS RX (non-blocking)
 * ================================================================ */
static void bus_rx_tick(void) {
    while (usart1_available()) {
        uint8_t b = usart1_read_byte();
        if (rx_pos == 0) {
            if (b == SOF) rx_buf[rx_pos++] = b;
        } else {
            if (rx_pos >= sizeof(rx_buf)) { rx_pos=0; rx_elen=0; return; }
            rx_buf[rx_pos++] = b;
            if (rx_pos == 5) rx_elen = 6 + rx_buf[4];
            if (rx_elen > 0 && rx_pos >= rx_elen) {
                process_frame(rx_buf, rx_pos);
                rx_pos=0; rx_elen=0;
            }
        }
    }
}

/* ================================================================
 * SETUP
 * ================================================================ */
void setup() {
    gpio_init();
    tim17_pwm_init();  /* must be after gpio_init -- PA7 taken by timer */
    usart1_init();
    hw_crc_init();
    uid_init();
    rand_seed = ((uint32_t)device_uid[0]<<24)|((uint32_t)device_uid[1]<<16)|
                ((uint32_t)device_uid[2]<< 8)|(uint32_t)device_uid[3];
    load_state();
    /* Apply restored relay states + correct LED state */
    set_relay1(relay1_state);
    set_relay2(relay2_state);
    last_poll_ms = millis();
}

/* ================================================================
 * LOOP
 * ================================================================ */
void loop() {
    handle_touch();

    if (mode != MODE_OTA) bus_rx_tick();

    switch (mode) {
    case MODE_UNREGISTERED:
        if ((millis() - last_announce_ms) >= announce_interval) {
            last_announce_ms  = millis();
            announce_interval = 2000 + pseudo_rand(500);
            send_announce();
        }
        break;
    case MODE_REGISTERED:
        if ((millis() - last_poll_ms) > ORPHAN_TIMEOUT_MS &&
             millis() > ORPHAN_TIMEOUT_MS) {
            self_unregister();
        }
        break;
    case MODE_OTA:
        break;
    case MODE_QUIET:
        bus_rx_tick();
        break;
    }

    /* Non-blocking hardware PWM breathing on LED3 */
    breath_tick();
}
