/*
 * Unisync - Extension Firmware v4.6
 * STM32G030F6P6 (TSSOP-20) -- Arduino IDE + STM32duino + LL drivers
 *
 * Build settings:
 *   Board:           Generic STM32G0 series / Generic G030F6Px
 *   Optimize:        Smallest (-Os) with LTO
 *   C Runtime:       Newlib Nano
 *   Upload:          STM32CubeProgrammer (SWD)
 *
 * Pin assignments (schematic Rev 1.1):
 *   PA_0  - RS485_DE   (MAX3485 DE/RE# -- HIGH=TX, LOW=RX)
 *   PA_1  - RELAY1_DRV (S8050 NPN -- HIGH=ON, LOW=OFF)
 *   PA_2  - RELAY2_DRV (S8050 NPN -- HIGH=ON, LOW=OFF)
 *   PA_3  - TOUCH1_IRQ (TTP223 -- HIGH on touch)
 *   PA_4  - TOUCH2_IRQ (TTP223 -- HIGH on touch)
 *   PA_5  - LED1       (green -- mirrors relay1)
 *   PA_6  - LED2       (green -- mirrors relay2)
 *   PA_7  - LED3       (green -- heartbeat)
 *   PA_9  - RS485_TX   (USART1 TX)
 *   PA_10 - RS485_RX   (USART1 RX)
 */

#include "Arduino.h"   /* millis(), delay() only */

/* ================================================================
 * GPIO BIT-BANG MACROS (replaces digitalWrite/pinMode)
 * All pins on GPIOA -- direct register writes, zero overhead
 * ================================================================ */
#define PIN_SET(pin)    (GPIOA->BSRR = (1u << (pin)))
#define PIN_CLR(pin)    (GPIOA->BRR  = (1u << (pin)))
#define PIN_READ(pin)   ((GPIOA->IDR  >> (pin)) & 1u)

/* Pin numbers (bit positions in GPIOA) */
#define PIN_RS485_DE   0
#define PIN_RELAY1     1
#define PIN_RELAY2     2
#define PIN_TOUCH1     3
#define PIN_TOUCH2     4
#define PIN_LED1       5
#define PIN_LED2       6
#define PIN_LED3       7
/* PA9=TX, PA10=RX handled by USART1 alternate function */

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
 * STM32G030F6P6: 32KB flash, 2KB pages
 * Use last page (0x08007800 - 0x08007FFF) for NVS
 * Page must be erased before write (erase sets all bytes to 0xFF)
 * Write 8 bytes (double-word) at a time
 * ================================================================ */
#define NVS_PAGE_ADDR   0x08007800UL  /* last 2KB page */
#define NVS_PAGE_SIZE   2048

/* NVS byte offsets */
#define NVS_MAGIC       0   /* 1 byte: 0xA5 */
#define NVS_ADDR        1   /* 1 byte: bus address */
#define NVS_RELAY       2   /* 1 byte: bit0=relay1, bit1=relay2 */
#define NVS_MUID0       3   /* 4 bytes: master UID */
#define NVS_MUID1       4
#define NVS_MUID2       5
#define NVS_MUID3       6
#define NVS_MAGIC_VAL   0xA5  /* registered to master */
#define NVS_RELAY_MAGIC 0x5A  /* standalone relay state only */

/* Shadow RAM copy of NVS page (2KB is too large -- use only first 8 bytes) */
static uint8_t nvs_shadow[8];

static void nvs_flush(void) {
    if (READ_BIT(FLASH->CR, FLASH_CR_LOCK)) {
        WRITE_REG(FLASH->KEYR, 0x45670123UL);
        WRITE_REG(FLASH->KEYR, 0xCDEF89ABUL);
    }
    WRITE_REG(FLASH->SR, 0xFFFFFFFF);
    MODIFY_REG(FLASH->CR, FLASH_CR_PNB, (15u << FLASH_CR_PNB_Pos));
    SET_BIT(FLASH->CR, FLASH_CR_PER);
    SET_BIT(FLASH->CR, FLASH_CR_STRT);
    uint32_t t = millis();
    while (READ_BIT(FLASH->SR, FLASH_SR_BSY1) && (millis()-t) < 500);
    CLEAR_BIT(FLASH->CR, FLASH_CR_PER);
    WRITE_REG(FLASH->SR, FLASH_SR_EOP);
    SET_BIT(FLASH->CR, FLASH_CR_PG);
    volatile uint32_t *dst = (volatile uint32_t *)NVS_PAGE_ADDR;
    uint32_t w0, w1;
    w0 = *(uint32_t*)&nvs_shadow[0];
    w1 = *(uint32_t*)&nvs_shadow[4];
    dst[0] = w0; __ISB(); dst[1] = w1;
    t = millis();
    while (READ_BIT(FLASH->SR, FLASH_SR_BSY1) && (millis()-t) < 500);
    CLEAR_BIT(FLASH->CR, FLASH_CR_PG);
    WRITE_REG(FLASH->SR, FLASH_SR_EOP);
    SET_BIT(FLASH->CR, FLASH_CR_LOCK);
}

/* ================================================================
 * USART1 LL DRIVER (PA_9=TX, PA_10=RX, 250000 baud)
 * ================================================================ */
static void usart1_init(void) {
    /* Enable USART1, SYSCFG, GPIOA clocks */
    RCC->APBENR2 |= RCC_APBENR2_USART1EN | RCC_APBENR2_SYSCFGEN;
    RCC->IOPENR  |= RCC_IOPENR_GPIOAEN;
    /* SYSCFG remap -- required for USART1 on G030 */
    SYSCFG->CFGR1 |= SYSCFG_CFGR1_PA11_RMP | SYSCFG_CFGR1_PA12_RMP;
    /* PA9 = AF1 TX: high speed, push-pull */
    GPIOA->MODER   = (GPIOA->MODER   & ~(3u<<18)) | (2u<<18);
    GPIOA->AFR[1]  = (GPIOA->AFR[1]  & ~(15u<<4)) | (1u<<4);
    GPIOA->OSPEEDR = (GPIOA->OSPEEDR & ~(3u<<18)) | (3u<<18);
    GPIOA->OTYPER &= ~(1u<<9);
    /* PA10 = AF1 RX: pull-up */
    GPIOA->MODER  = (GPIOA->MODER  & ~(3u<<20)) | (2u<<20);
    GPIOA->AFR[1] = (GPIOA->AFR[1] & ~(15u<<8)) | (1u<<8);
    GPIOA->PUPDR  = (GPIOA->PUPDR  & ~(3u<<20)) | (1u<<20);
    /* USART1: 8N1, 250000 baud, TX+RX enabled */
    USART1->CR1  = 0;
    USART1->CR2  = 0;
    USART1->CR3  = 0;
    USART1->PRESC = 0;
    USART1->BRR  = (64000000UL / 250000UL);
    USART1->CR1  = USART_CR1_TE | USART_CR1_RE | USART_CR1_UE;
    uint32_t t   = millis();
    while (!(USART1->ISR & USART_ISR_TEACK) && (millis()-t) < 100);
    while (!(USART1->ISR & USART_ISR_REACK) && (millis()-t) < 100);
}

static void usart1_write_byte(uint8_t b) {
    while (!(USART1->ISR & USART_ISR_TXE_TXFNF));
    USART1->TDR = b;
}

static void usart1_wait_tc(void) {
    while (!(USART1->ISR & USART_ISR_TC));
}

static bool usart1_available(void) {
    if (USART1->ISR & USART_ISR_ORE) USART1->ICR = USART_ICR_ORECF;
    return (USART1->ISR & USART_ISR_RXNE_RXFNE) != 0;
}

static uint8_t usart1_read_byte(void) {
    return USART1->RDR & 0xFF;
}

/* ================================================================
 * GPIO INIT (replaces pinMode/digitalWrite)
 * ================================================================ */
static void gpio_init(void) {
    RCC->IOPENR |= RCC_IOPENR_GPIOAEN;
    /* Relay HIGH before output (active LOW = OFF) */
    GPIOA->BSRR = (1u<<1)|(1u<<2);
    GPIOA->BRR  = (1u<<0)|(1u<<5)|(1u<<6)|(1u<<7);
    /* PA0,1,2,5,6,7=output PA3,4=input no-pull */
    GPIOA->MODER = (GPIOA->MODER
        & ~((3u<<0)|(3u<<2)|(3u<<4)|(3u<<6)|(3u<<8)|(3u<<10)|(3u<<12)|(3u<<14)))
        |  ((1u<<0)|(1u<<2)|(1u<<4)|(1u<<10)|(1u<<12)|(1u<<14));
    GPIOA->PUPDR = (GPIOA->PUPDR & ~((3u<<6)|(3u<<8)));
}

/* ================================================================
 * CHIP UID (96-bit at 0x1FFF7590, use bytes 8-11)
 * Cached at startup -- UID never changes, no need to re-read flash
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
static uint8_t crc8(uint8_t *d, uint8_t n) {
    uint8_t c=0;
    while(n--){c^=*d++;for(uint8_t i=8;i--;)c=c&0x80?(c<<1)^7:c<<1;}
    return c;
}

/* ================================================================
 * CRC32 -- uses STM32G030 hardware CRC unit (CRC-32/MPEG-2 poly)
 * Reset unit, feed data word by word, read result.
 * Saves ~200 bytes vs software loop.
 * ================================================================ */
static uint32_t crc32_compute(const uint8_t *d, uint8_t n) {
    uint32_t c=0xFFFFFFFF;
    while(n--){c^=*d++;for(uint8_t i=8;i--;)c=c&1?(c>>1)^0xEDB88320UL:c>>1;}
    return c^0xFFFFFFFF;
}

static uint32_t compute_response(const uint8_t *ch) {
    uint8_t b[24];
    for(uint8_t i=0;i<16;i++) b[i]=SECRET_KEY[i];
    for(uint8_t i=0;i<4;i++){b[16+i]=ch[i];b[20+i]=device_uid[i];}
    return crc32_compute(b,24);
}

/* ================================================================
 * PSEUDO-RANDOM
 * ================================================================ */

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

#define EVENT_BUF_SIZE 8
typedef struct {
    uint8_t channel;
    uint8_t state;
} touch_event_t;

static touch_event_t event_buf[EVENT_BUF_SIZE];
static uint8_t       event_head  = 0;
static uint8_t       event_tail  = 0;
static uint8_t       event_count = 0;

static bool     last_t1         = false;
static bool     last_t2         = false;
static uint32_t last_poll_ms    = 0;

static uint8_t  rx_buf[25];
static uint8_t  rx_pos          = 0;
static uint8_t  rx_elen         = 0;

static uint32_t last_announce_ms  = 0;
static uint32_t announce_interval = 2000;

/* ================================================================
 * BREATH TICK -- TIM17 hardware PWM on PA7
 * Registered: 32 * 125ms = 4s cycle
 * Unregistered: 32 * 31ms = ~1s cycle
 * ================================================================ */
/* breath computed inline */

static void tim17_pwm_init(void) {
    RCC->APBENR2 |= RCC_APBENR2_TIM17EN;
    /* PA7 = AF5 (TIM17_CH1) push-pull */
    GPIOA->MODER  = (GPIOA->MODER  & ~(3u<<14)) | (2u<<14);
    GPIOA->AFR[0] = (GPIOA->AFR[0] & ~(15u<<28)) | (5u<<28);
    TIM17->PSC   = 0;
    TIM17->ARR   = 255;
    TIM17->CCR1  = 0;
    TIM17->CCMR1 = (6u << TIM_CCMR1_OC1M_Pos) | TIM_CCMR1_OC1PE;
    TIM17->CCER  = TIM_CCER_CC1E;
    TIM17->BDTR  = TIM_BDTR_MOE;
    TIM17->CR1   = TIM_CR1_CEN;
}

static void breath_tick(void) {
    static uint32_t last_ms = 0;
    static uint8_t  step    = 0;
    uint32_t interval = (mode == MODE_REGISTERED) ? 125 : 31;
    if ((millis() - last_ms) < interval) return;
    last_ms = millis();
    uint8_t s = step & 0x1F;
    TIM17->CCR1 = (s < 16) ? (uint32_t)(s << 4) : (uint32_t)((31 - s) << 4);
    step++;
}




/* ================================================================
 * PERSISTENCE
 * ================================================================ */
static void load_state(void) {
    volatile uint8_t *p=(volatile uint8_t*)NVS_PAGE_ADDR;
    for(uint8_t i=0;i<8;i++) nvs_shadow[i]=p[i];
    relay1_state=(nvs_shadow[NVS_RELAY]&0x01)!=0;
    relay2_state=(nvs_shadow[NVS_RELAY]&0x02)!=0;
    if (nvs_shadow[NVS_MAGIC]==NVS_MAGIC_VAL) {
        slot_address=nvs_shadow[NVS_ADDR];
        master_uid[0]=nvs_shadow[NVS_MUID0]; master_uid[1]=nvs_shadow[NVS_MUID1];
        master_uid[2]=nvs_shadow[NVS_MUID2]; master_uid[3]=nvs_shadow[NVS_MUID3];
        mode=MODE_REGISTERED;
    } else {
        mode=MODE_UNREGISTERED; slot_address=ADDR_UNASSIGNED;
    }
}

static void save_registration(uint8_t addr, uint8_t *m_uid) {
    nvs_shadow[NVS_ADDR]  = addr;
    nvs_shadow[NVS_MUID0] = m_uid[0];
    nvs_shadow[NVS_MUID1] = m_uid[1];
    nvs_shadow[NVS_MUID2] = m_uid[2];
    nvs_shadow[NVS_MUID3] = m_uid[3];
    nvs_shadow[NVS_MAGIC] = NVS_MAGIC_VAL;
    /* Also persist current relay state at registration time */
    nvs_shadow[NVS_RELAY] = (relay1_state ? 0x01 : 0x00) |
                             (relay2_state ? 0x02 : 0x00);
    nvs_flush();
}

static void save_relay_state(void) {
    nvs_shadow[NVS_RELAY] = (relay1_state ? 0x01 : 0x00) |
                             (relay2_state ? 0x02 : 0x00);
    nvs_shadow[NVS_MAGIC] = NVS_RELAY_MAGIC; /* standalone -- not registered */
    nvs_flush();
}

static void wipe_registration(void) {
    for(uint8_t i=0;i<8;i++) nvs_shadow[i]=0;
    nvs_flush();
}

/* ================================================================
 * RS-485 TRANSPORT
 * ================================================================ */
static void rs485_send(uint8_t *frame, uint8_t len) {
    PIN_SET(PIN_RS485_DE);
    __NOP(); __NOP(); __NOP(); __NOP(); /* ~250ns guard */
    for (uint8_t i = 0; i < len; i++) usart1_write_byte(frame[i]);
    usart1_wait_tc();
    __NOP(); __NOP(); __NOP(); __NOP();
    PIN_CLR(PIN_RS485_DE);
    /* MAX3485 RX enable guard + flush echo bytes */
    __NOP(); __NOP(); __NOP(); __NOP();
    if (USART1->ISR & USART_ISR_ORE) USART1->ICR = USART_ICR_ORECF;
    if (USART1->ISR & USART_ISR_RXNE_RXFNE) (void)USART1->RDR;
    rx_pos = 0; rx_elen = 0;
}

static void send_frame(uint8_t dst, uint8_t cmd,
                       uint8_t *payload, uint8_t plen) {
    uint8_t frame[30];
    frame[0] = SOF;
    frame[1] = dst;
    frame[2] = slot_address;
    frame[3] = cmd;
    frame[4] = plen;
    for(uint8_t _i=0;_i<plen;_i++) frame[5+_i]=payload[_i];
    frame[5 + plen] = crc8(&frame[1], 4 + plen);
    rs485_send(frame, 6 + plen);
}

/* ================================================================
 * RELAY CONTROL (active HIGH -- S8050 NPN)
 * ================================================================ */
static void set_relay1(bool s) {
    relay1_state = s;
    if (s) { PIN_CLR(PIN_RELAY1); PIN_SET(PIN_LED1); }
    else   { PIN_SET(PIN_RELAY1); PIN_CLR(PIN_LED1); }
}

static void set_relay2(bool s) {
    relay2_state = s;
    if (s) { PIN_CLR(PIN_RELAY2); PIN_SET(PIN_LED2); }
    else   { PIN_SET(PIN_RELAY2); PIN_CLR(PIN_LED2); }
}

/* ================================================================
 * SELF-UNREGISTER
 * ================================================================ */
static void self_unregister(void) {
    relay1_state = false; relay2_state = false;
    set_relay1(false); set_relay2(false);
    wipe_registration();
    slot_address      = ADDR_UNASSIGNED;
    mode              = MODE_UNREGISTERED;
    announce_interval = 2000;
    last_announce_ms  = 0;
}

/* ================================================================
 * TOUCH EVENT BUFFER
 * ================================================================ */
static void push_event(uint8_t ch, uint8_t s) {
    event_buf[event_head].channel = ch;
    event_buf[event_head].state   = s;
    event_head = (event_head + 1) & 7;
    if (event_count < EVENT_BUF_SIZE) event_count++;
    else event_tail = (event_tail + 1) & 7;
}


/* ================================================================
 * TOUCH HANDLER
 * ================================================================ */
static void handle_touch(void) {
    bool t1 = PIN_READ(PIN_TOUCH1);
    bool t2 = PIN_READ(PIN_TOUCH2);
    if (t1 && !last_t1) {
        set_relay1(!relay1_state);
        push_event(1, relay1_state ? 1 : 0);
        if (mode != MODE_REGISTERED) save_relay_state();
    }
    if (t2 && !last_t2) {
        set_relay2(!relay2_state);
        push_event(2, relay2_state ? 1 : 0);
        if (mode != MODE_REGISTERED) save_relay_state();
    }
    last_t1 = t1;
    last_t2 = t2;
}

/* ================================================================
 * ANNOUNCE
 * ================================================================ */
static void send_announce(void) {
    uint8_t payload[5];
    payload[0]=device_uid[0]; payload[1]=device_uid[1];
    payload[2]=device_uid[2]; payload[3]=device_uid[3];
    payload[4]=(relay1_state?0x01:0x00)|(relay2_state?0x02:0x00)|(event_count?0x04:0x00);
    /* send with src=ADDR_UNASSIGNED */
    uint8_t saved=slot_address; slot_address=ADDR_UNASSIGNED;
    send_frame(ADDR_MASTER, CMD_ANNOUNCE, payload, 5);
    slot_address=saved;
}

/* ================================================================
 * STATE RESPONSE
 * ================================================================ */
static void send_state_resp(void) {
    uint8_t payload[3 + 5*2];
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
        payload[plen++] = event_buf[tail].channel;
        payload[plen++] = event_buf[tail].state;
        tail = (tail + 1) & 7;
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
    uint8_t *uid = device_uid;
    uint8_t  buf[8];

    if (frame[5 + plen] != crc8(&frame[1], 4 + plen)) return;

    /* UID-addressed commands */
    if (cmd == CMD_WELCOME) {
        if (plen < 10) return;
        if (p[0]!=uid[0]||p[1]!=uid[1]||p[2]!=uid[2]||p[3]!=uid[3]) return;
        if (mode==MODE_REGISTERED &&
            (master_uid[0]||master_uid[1]||master_uid[2]||master_uid[3])) {
            if (p[6]!=master_uid[0]||p[7]!=master_uid[1]||
                p[8]!=master_uid[2]||p[9]!=master_uid[3])
                { send_frame(ADDR_MASTER,CMD_ERROR,uid,4); return; }
        }
        uint8_t new_addr = p[4];
        bool    new_r1   = (p[5] & 0x01) != 0;
        bool    new_r2   = (p[5] & 0x02) != 0;
        uint8_t m_uid[4] = {p[6],p[7],p[8],p[9]};
        save_registration(new_addr, m_uid);
        slot_address = new_addr;
        master_uid[0]=m_uid[0];master_uid[1]=m_uid[1];
        master_uid[2]=m_uid[2];master_uid[3]=m_uid[3];
        mode = MODE_REGISTERED;
        set_relay1(new_r1);
        set_relay2(new_r2);
        buf[0]=1; buf[1]=0;
        send_frame(ADDR_MASTER, CMD_PONG, buf, 2);
        last_poll_ms      = millis();
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
        uint8_t pl[8] = {uid[0],uid[1],uid[2],uid[3],
            (resp>>24)&0xFF,(resp>>16)&0xFF,(resp>>8)&0xFF,resp&0xFF};
        uint8_t saved=slot_address; slot_address=ADDR_UNASSIGNED;
        send_frame(ADDR_MASTER, CMD_RESPONSE, pl, 8);
        slot_address=saved;
        return;
    }

    /* Bus-address commands */
    bool for_me = (dst == slot_address) || (dst == ADDR_BCAST);
    if (!for_me) return;

    switch (cmd) {

    case CMD_PING:
        buf[0]=1; buf[1]=0;
        send_frame(ADDR_MASTER,CMD_PONG,buf,2);
        break;

    case CMD_GET_STATE:
        last_poll_ms  = millis();
            send_state_resp();
        break;

    case CMD_SET_RELAY:
        if (plen < 1) break;
        set_relay1((p[0] & 0x01) != 0);
        set_relay2((p[0] & 0x02) != 0);
        send_state_resp();
        break;

    case CMD_DRAIN_EVENTS:
        if (plen>=1) { uint8_t _n=p[0];
          while(_n-->0&&event_count>0){event_tail=(event_tail+1)&7;event_count--;} }
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
            if (rx_pos >= 25) { rx_pos=0; rx_elen=0; return; }
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
 * LED BLINK HELPER + STARTUP BLINK
 * ================================================================ */


/* ================================================================
 * SETUP
 * ================================================================ */
void setup() {
    gpio_init();
    tim17_pwm_init();
    usart1_init();
    /* Seed random from UID */
    uid_init();
    load_state();
    /* Boot relay state:
     * Registered to a real master --> boot OFF, master restores on first poll
     * Standalone (no master_uid)  --> restore from NVS */
    { bool has_master = (master_uid[0]||master_uid[1]||
                         master_uid[2]||master_uid[3]);
      if (mode == MODE_REGISTERED && has_master) {
          relay1_state = false; relay2_state = false;
          set_relay1(false); set_relay2(false);
      } else {
          set_relay1(relay1_state);
          set_relay2(relay2_state);
      }
    }
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
            announce_interval = 2000 + (device_uid[3] & 0xFF);
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

    /* Hardware PWM breathing on LED3 */
    breath_tick();
}
