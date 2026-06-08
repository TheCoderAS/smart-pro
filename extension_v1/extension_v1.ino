/*
 * Smart Modular Switch System
 * Extension Firmware — STM8S103F3
 * Demo: Relay and LED share same pin (PD4, PC3)
 * Builtin LED on PB5 blinks at 500ms as heartbeat
 */

/* ─── Config ─────────────────────────────────────────────────── */
#define UART_BAUD        250000
#define ADDR_UNASSIGNED  0xFE
#define ADDR_MASTER      0x00
#define EEPROM_ADDR_SLOT 0x4000
#define EEPROM_MAGIC     0x4001
#define EEPROM_MAGIC_VAL 0xA5

/* ─── Arduino pins ───────────────────────────────────────────── */
#define RELAY1_PIN       13      /* PD4 — also LED CH1 in demo */
#define RELAY2_PIN       5     /* PC3 — also LED CH2 in demo */
#define TOUCH1_PIN       11      /* PD2 */
#define TOUCH2_PIN       12      /* PD3 */
#define BUILTIN_LED      3      /* PB5 — heartbeat */

/* ─── Frame constants ────────────────────────────────────────── */
#define SOF              0xAA

/* ─── Commands ───────────────────────────────────────────────── */
#define CMD_PING         0x00
#define CMD_PONG         0x01
#define CMD_ENUM_REQ     0x10
#define CMD_ENUM_RESP    0x11
#define CMD_SET_ADDR     0x12
#define CMD_SET_RELAY    0x20
#define CMD_GET_STATE    0x21
#define CMD_STATE_RESP   0x22
#define CMD_DRAIN_EVENTS 0x23
#define CMD_IDENTIFY     0x30
#define CMD_ERROR        0xF0

/* ─── Event queue ────────────────────────────────────────────── */
#define EVENT_QUEUE_SIZE 16

typedef struct {
    uint8_t  channel;
    uint8_t  new_state;
    uint16_t timestamp;
} touch_event_t;

static touch_event_t    event_queue[EVENT_QUEUE_SIZE];
static volatile uint8_t event_head     = 0;
static volatile uint8_t event_tail     = 0;
static volatile uint8_t events_pending = 0;

/* ─── State ──────────────────────────────────────────────────── */
static uint8_t           slot_address  = ADDR_UNASSIGNED;
static volatile uint8_t  relay1_state  = 0;
static volatile uint8_t  relay2_state  = 0;
static volatile uint32_t led1_off_ms   = 0;
static volatile uint32_t led2_off_ms   = 0;

/* ─── Heartbeat ──────────────────────────────────────────────── */
static uint32_t heartbeat_ms = 0;
static uint8_t  heartbeat_state = 0;

/* ─── UART RX ring buffer ────────────────────────────────────── */
#define RX_BUF_SIZE 40
static uint8_t rx_buf[RX_BUF_SIZE];
static uint8_t rx_head = 0;
static uint8_t rx_tail = 0;

/* ─── Frame parser ───────────────────────────────────────────── */
static uint8_t parse_buf[40];
static uint8_t parse_pos = 0;

/* ═══════════════════════════════════════════════════════════════
 * EEPROM
 * ═══════════════════════════════════════════════════════════════ */
static uint8_t eeprom_read(uint16_t addr) {
    return *((volatile uint8_t *)addr);
}

static void eeprom_write(uint16_t addr, uint8_t val) {
    FLASH->DUKR = 0xAE;
    FLASH->DUKR = 0x56;
    while (!(FLASH->IAPSR & 0x08));
    *((volatile uint8_t *)addr) = val;
    while (!(FLASH->IAPSR & 0x04));
    FLASH->IAPSR &= ~0x08;
}

/* ═══════════════════════════════════════════════════════════════
 * Chip UID
 * ═══════════════════════════════════════════════════════════════ */
static void get_uid(uint8_t *uid4) {
    volatile uint8_t *uid = (volatile uint8_t *)0x4865;
    uid4[0] = uid[0]; uid4[1] = uid[1];
    uid4[2] = uid[2]; uid4[3] = uid[3];
}

/* ═══════════════════════════════════════════════════════════════
 * CRC-8
 * ═══════════════════════════════════════════════════════════════ */
static uint8_t crc8(uint8_t *data, uint8_t len) {
    uint8_t crc = 0x00;
    while (len--) {
        crc ^= *data++;
        uint8_t i;
        for (i = 0; i < 8; i++)
            crc = (crc & 0x80) ? (crc << 1) ^ 0x07 : crc << 1;
    }
    return crc;
}

/* ═══════════════════════════════════════════════════════════════
 * Relay — direct register write, safe from ISR
 * ═══════════════════════════════════════════════════════════════ */
static void relay_set_direct(uint8_t ch, uint8_t state) {
    if (ch == 1) {
        relay1_state = state;
        if (state) GPIOD->ODR |=  (1 << 4);
        else       GPIOD->ODR &= ~(1 << 4);
    } else {
        relay2_state = state;
        if (state) GPIOC->ODR |=  (1 << 3);
        else       GPIOC->ODR &= ~(1 << 3);
    }
}

/* ═══════════════════════════════════════════════════════════════
 * Queue touch event
 * ═══════════════════════════════════════════════════════════════ */
static void queue_event(uint8_t ch, uint8_t state) {
    uint8_t next = (event_head + 1) % EVENT_QUEUE_SIZE;
    if (next == event_tail) {
        event_tail = (event_tail + 1) % EVENT_QUEUE_SIZE;
    }
    event_queue[event_head].channel   = ch;
    event_queue[event_head].new_state = state;
    event_queue[event_head].timestamp = (uint16_t)(millis() & 0xFFFF);
    event_head = (event_head + 1) % EVENT_QUEUE_SIZE;
    events_pending = 1;
}

/* ═══════════════════════════════════════════════════════════════
 * Touch ISRs — relay toggles here, no loop() involvement
 * ═══════════════════════════════════════════════════════════════ */
static void touch1_isr(void) {
    uint8_t new_state = !relay1_state;
    relay_set_direct(1, new_state);
    led1_off_ms = millis() + 1000;
    queue_event(1, new_state);
}

static void touch2_isr(void) {
    uint8_t new_state = !relay2_state;
    relay_set_direct(2, new_state);
    led2_off_ms = millis() + 1000;
    queue_event(2, new_state);
}

/* ═══════════════════════════════════════════════════════════════
 * LED timer — relay/LED pin turns off after 1s on touch
 * Only turns off if relay was toggled OFF — if relay is ON,
 * pin stays high regardless
 * ═══════════════════════════════════════════════════════════════ */
static void led_update(void) {
    if (led1_off_ms > 0 && millis() >= led1_off_ms) {
        led1_off_ms = 0;
        /* Only pull low if relay is currently OFF */
        if (!relay1_state) digitalWrite(RELAY1_PIN, LOW);
    }
    if (led2_off_ms > 0 && millis() >= led2_off_ms) {
        led2_off_ms = 0;
        if (!relay2_state) digitalWrite(RELAY2_PIN, LOW);
    }
}

/* ═══════════════════════════════════════════════════════════════
 * Heartbeat — blinks builtin LED every 500ms
 * Confirms loop() is running
 * ═══════════════════════════════════════════════════════════════ */
static void heartbeat_update(void) {
    if (millis() - heartbeat_ms >= 500) {
        heartbeat_ms = millis();
        heartbeat_state = !heartbeat_state;
        digitalWrite(BUILTIN_LED, heartbeat_state);
    }
}

/* ═══════════════════════════════════════════════════════════════
 * UART TX
 * ═══════════════════════════════════════════════════════════════ */
static void uart_send_frame(uint8_t dst, uint8_t cmd,
                             uint8_t *payload, uint8_t len) {
    uint8_t frame[38];
    uint8_t i;
    frame[0] = SOF;
    frame[1] = dst;
    frame[2] = slot_address;
    frame[3] = cmd;
    frame[4] = len;
    for (i = 0; i < len; i++) frame[5 + i] = payload[i];
    frame[5 + len] = crc8(&frame[1], 4 + len);
    for (i = 0; i < 6 + len; i++) Serial_write(frame[i]);
}

/* ═══════════════════════════════════════════════════════════════
 * Random delay — collision avoidance
 * ═══════════════════════════════════════════════════════════════ */
static void random_delay_50ms(void) {
    uint8_t uid[4];
    get_uid(uid);
    uint8_t wait_ms = (uid[0] ^ uid[1] ^ uid[2] ^ uid[3]) % 50;
    delay(wait_ms);
}

/* ═══════════════════════════════════════════════════════════════
 * STATE_RESP
 * ═══════════════════════════════════════════════════════════════ */
static void send_state_resp(void) {
    uint8_t payload[35];
    uint8_t event_count = 0;
    uint8_t tail = event_tail;
    uint8_t i;

    while (tail != event_head && event_count < 5) {
        tail = (tail + 1) % EVENT_QUEUE_SIZE;
        event_count++;
    }

    payload[0] = (relay1_state & 0x01)
               | ((relay2_state & 0x01) << 1)
               | (events_pending ? 0x04 : 0x00);
    payload[1] = 25;
    payload[2] = event_count;

    tail = event_tail;
    for (i = 0; i < event_count; i++) {
        uint8_t idx = (tail + i) % EVENT_QUEUE_SIZE;
        payload[3 + i*5 + 0] = event_queue[idx].channel;
        payload[3 + i*5 + 1] = event_queue[idx].new_state;
        payload[3 + i*5 + 2] = (event_queue[idx].timestamp >> 8) & 0xFF;
        payload[3 + i*5 + 3] =  event_queue[idx].timestamp & 0xFF;
        payload[3 + i*5 + 4] = 0;
    }
    uart_send_frame(ADDR_MASTER, CMD_STATE_RESP, payload,
                    3 + event_count * 5);
}

/* ═══════════════════════════════════════════════════════════════
 * Frame processor
 * All locals at top — SDCC C89 requirement
 * ═══════════════════════════════════════════════════════════════ */
static void process_frame(uint8_t *f) {
    uint8_t dst         = f[1];
    uint8_t cmd         = f[3];
    uint8_t len         = f[4];
    uint8_t uid[4];
    uint8_t new_addr;
    uint8_t drain_count;
    uint8_t pong_buf[6] = {0x01, 0x00, 0x00, 0x00, 0x00, 0x00};
    uint8_t err_buf[2];
    uint8_t blink_i;

    if (dst != slot_address && dst != 0xFF && dst != ADDR_UNASSIGNED) return;
    if (f[5 + len] != crc8(&f[1], 4 + len)) return;

    switch (cmd) {

        case CMD_PING:
            uart_send_frame(ADDR_MASTER, CMD_PONG, pong_buf, 6);
            break;

        case CMD_ENUM_REQ:
            if (slot_address != ADDR_UNASSIGNED) break;
            random_delay_50ms();
            get_uid(uid);
            uart_send_frame(ADDR_MASTER, CMD_ENUM_RESP, uid, 4);
            break;

        case CMD_SET_ADDR:
            if (len < 5) break;
            get_uid(uid);
            if (f[5] != uid[0] || f[6] != uid[1] ||
                f[7] != uid[2] || f[8] != uid[3]) break;
            new_addr = f[9];
            if (new_addr < 0x01 || new_addr > 0x05) break;
            eeprom_write(EEPROM_ADDR_SLOT, new_addr);
            eeprom_write(EEPROM_MAGIC,     EEPROM_MAGIC_VAL);
            slot_address = new_addr;
            uart_send_frame(ADDR_MASTER, CMD_PONG, pong_buf, 6);
            break;

        case CMD_GET_STATE:
            send_state_resp();
            break;

        case CMD_SET_RELAY:
            if (len >= 1) {
                relay_set_direct(1, (f[5] >> 0) & 0x01);
                relay_set_direct(2, (f[5] >> 1) & 0x01);
            }
            break;

        case CMD_DRAIN_EVENTS:
            if (len >= 1) {
                drain_count = f[5];
                while (drain_count--) {
                    if (event_tail != event_head)
                        event_tail = (event_tail + 1) % EVENT_QUEUE_SIZE;
                }
                if (event_tail == event_head) events_pending = 0;
            }
            break;

        case CMD_IDENTIFY:
            for (blink_i = 0; blink_i < 3; blink_i++) {
                digitalWrite(RELAY1_PIN, HIGH);
                digitalWrite(RELAY2_PIN, HIGH);
                delay(200);
                digitalWrite(RELAY1_PIN, relay1_state);
                digitalWrite(RELAY2_PIN, relay2_state);
                delay(200);
            }
            break;

        default:
            err_buf[0] = cmd;
            err_buf[1] = 0x01;
            uart_send_frame(ADDR_MASTER, CMD_ERROR, err_buf, 2);
            break;
    }
}

/* ═══════════════════════════════════════════════════════════════
 * UART parser
 * ═══════════════════════════════════════════════════════════════ */
static void uart_parse(void) {
    while (Serial_available()) {
        uint8_t b    = Serial_read();
        uint8_t next = (rx_head + 1) % RX_BUF_SIZE;
        if (next != rx_tail) { rx_buf[rx_head] = b; rx_head = next; }
    }

    while (rx_tail != rx_head) {
        uint8_t b = rx_buf[rx_tail];
        rx_tail = (rx_tail + 1) % RX_BUF_SIZE;

        if (parse_pos == 0) {
            if (b == SOF) parse_buf[parse_pos++] = b;
        } else {
            parse_buf[parse_pos++] = b;
            if (parse_pos >= 5) {
                uint8_t expected = 6 + parse_buf[4];
                if (parse_pos >= expected) {
                    process_frame(parse_buf);
                    parse_pos = 0;
                }
            }
            if (parse_pos >= sizeof(parse_buf)) parse_pos = 0;
        }
    }
}

/* ═══════════════════════════════════════════════════════════════
 * setup / loop
 * ═══════════════════════════════════════════════════════════════ */
void setup() {
    uint8_t blinks;
    uint8_t i;

    pinMode(RELAY1_PIN,  OUTPUT); digitalWrite(RELAY1_PIN,  LOW);
    pinMode(RELAY2_PIN,  OUTPUT); digitalWrite(RELAY2_PIN,  LOW);
    pinMode(TOUCH1_PIN,  INPUT);
    pinMode(TOUCH2_PIN,  INPUT);
    pinMode(BUILTIN_LED, OUTPUT); digitalWrite(BUILTIN_LED, LOW);

    Serial_begin(UART_BAUD);

    attachInterrupt(TOUCH1_PIN, touch1_isr, RISING);
    attachInterrupt(TOUCH2_PIN, touch2_isr, RISING);

    if (eeprom_read(EEPROM_MAGIC) == EEPROM_MAGIC_VAL)
        slot_address = eeprom_read(EEPROM_ADDR_SLOT);
    else
        slot_address = ADDR_UNASSIGNED;

    /* Startup blink on relay/LED pins — 2 = addressed, 5 = unaddressed */
    blinks = (slot_address != ADDR_UNASSIGNED) ? 2 : 5;
    for (i = 0; i < blinks; i++) {
        digitalWrite(RELAY1_PIN, HIGH);
        digitalWrite(RELAY2_PIN, HIGH);
        delay(150);
        digitalWrite(RELAY1_PIN, LOW);
        digitalWrite(RELAY2_PIN, LOW);
        delay(150);
    }
}

void loop() {
    uart_parse();
    led_update();
    heartbeat_update();
}
