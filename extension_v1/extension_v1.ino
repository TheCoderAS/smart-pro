/*
 * Smart Switch — Extension Firmware v2.1
 * Target: STM8S103F3P6 via sduino
 *
 * Confirmed working pins:
 *   PA3  — Touch 1
 *   PA2  — Touch 2
 *   PD4  — Relay 1
 *   PC3  — Relay 2
 *   PB5  — Onboard LED (heartbeat)
 *   PD5  — UART1 TX → MAX485 DI (hardware fixed)
 *   PD6  — UART1 RX → MAX485 RO (hardware fixed)
 *   PD3  — MAX485 DE/RE
 */

#define RELAY1   PD4
#define RELAY2   PC3
#define LED      PB5
#define TOUCH1   PA3
#define TOUCH2   PA2
#define DE_RE    PD3

/* ═══════════════════════════════════════════════════════════════
 * PROTOCOL
 * ═══════════════════════════════════════════════════════════════ */
#define UART_BAUD        250000
#define SOF              0xAA
#define ADDR_MASTER      0x00
#define ADDR_UNASSIGNED  0xFE
#define ADDR_BCAST       0xFF

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

/* ═══════════════════════════════════════════════════════════════
 * EEPROM — STM8 data EEPROM at 0x4000
 * ═══════════════════════════════════════════════════════════════ */
#define EEPROM_MAGIC_ADDR  0x4000
#define EEPROM_ADDR_ADDR   0x4001
#define EEPROM_MAGIC_VAL   0xA5

/* ═══════════════════════════════════════════════════════════════
 * STATE
 * ═══════════════════════════════════════════════════════════════ */
static uint8_t  slot_address = ADDR_UNASSIGNED;
static bool     relay1_state = false;
static bool     relay2_state = false;

/* Touch event ring buffer — max 16 events */
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

static bool last_t1 = false;
static bool last_t2 = false;

/* RX frame accumulator */
static uint8_t rx_buf[40];
static uint8_t rx_pos  = 0;
static uint8_t rx_elen = 0;

/* ═══════════════════════════════════════════════════════════════
 * CRC-8 (poly 0x07)
 * ═══════════════════════════════════════════════════════════════ */
static uint8_t crc8(uint8_t *data, uint8_t len) {
    uint8_t crc = 0x00;
    while (len--) {
        crc ^= *data++;
        for (uint8_t i = 0; i < 8; i++)
            crc = (crc & 0x80) ? (crc << 1) ^ 0x07 : crc << 1;
    }
    return crc;
}

/* ═══════════════════════════════════════════════════════════════
 * EEPROM
 * ═══════════════════════════════════════════════════════════════ */
static void eeprom_unlock(void) {
    FLASH->DUKR = 0xAE;
    FLASH->DUKR = 0x56;
    while (!(FLASH->IAPSR & 0x08));
}

static void eeprom_lock(void) {
    FLASH->IAPSR &= ~0x08;
}

static uint8_t eeprom_read(uint16_t addr) {
    return *((volatile uint8_t *)addr);
}

static void eeprom_write(uint16_t addr, uint8_t val) {
    eeprom_unlock();
    *((volatile uint8_t *)addr) = val;
    while (!(FLASH->IAPSR & 0x04));
    eeprom_lock();
}

static void load_address(void) {
    if (eeprom_read(EEPROM_MAGIC_ADDR) == EEPROM_MAGIC_VAL)
        slot_address = eeprom_read(EEPROM_ADDR_ADDR);
    else
        slot_address = ADDR_UNASSIGNED;
}

static void save_address(uint8_t addr) {
    eeprom_write(EEPROM_ADDR_ADDR,  addr);
    eeprom_write(EEPROM_MAGIC_ADDR, EEPROM_MAGIC_VAL);
    slot_address = addr;
}

/* ═══════════════════════════════════════════════════════════════
 * CHIP UID — 4 bytes from STM8 factory area at 0x4865
 * ═══════════════════════════════════════════════════════════════ */
static void get_uid(uint8_t *uid) {
    uid[0] = *((volatile uint8_t *)0x4865);
    uid[1] = *((volatile uint8_t *)0x4866);
    uid[2] = *((volatile uint8_t *)0x4867);
    uid[3] = *((volatile uint8_t *)0x4868);
}

/* ═══════════════════════════════════════════════════════════════
 * RS-485 TX
 * ═══════════════════════════════════════════════════════════════ */
static void rs485_send(uint8_t *frame, uint8_t len) {
    digitalWrite(DE_RE, HIGH);
    delayMicroseconds(10);
    for (uint8_t i = 0; i < len; i++) {
        Serial_write(frame[i]);
    }
    /* Wait for TX complete flag */
    while (!(UART1->SR & UART1_SR_TC));
    delayMicroseconds(10);
    digitalWrite(DE_RE, LOW);
}

/* ═══════════════════════════════════════════════════════════════
 * SEND FRAME
 * ═══════════════════════════════════════════════════════════════ */
static void send_frame(uint8_t dst, uint8_t cmd,
                       uint8_t *payload, uint8_t plen) {
    uint8_t frame[38];
    frame[0] = SOF;
    frame[1] = dst;
    frame[2] = slot_address;
    frame[3] = cmd;
    frame[4] = plen;
    for (uint8_t i = 0; i < plen; i++) frame[5 + i] = payload[i];
    frame[5 + plen] = crc8(&frame[1], 4 + plen);
    rs485_send(frame, 6 + plen);
}

/* ═══════════════════════════════════════════════════════════════
 * EVENT BUFFER
 * ═══════════════════════════════════════════════════════════════ */
static void push_event(uint8_t channel, uint8_t state) {
    event_buf[event_head].channel = channel;
    event_buf[event_head].state   = state;
    event_buf[event_head].ts_ms   = millis();
    event_head = (event_head + 1) % EVENT_BUF_SIZE;
    if (event_count < EVENT_BUF_SIZE) {
        event_count++;
    } else {
        /* Oldest dropped */
        event_tail = (event_tail + 1) % EVENT_BUF_SIZE;
    }
}

static void drain_events(uint8_t count) {
    for (uint8_t i = 0; i < count && event_count > 0; i++) {
        event_tail = (event_tail + 1) % EVENT_BUF_SIZE;
        event_count--;
    }
}

/* ═══════════════════════════════════════════════════════════════
 * RELAY CONTROL
 * ═══════════════════════════════════════════════════════════════ */
static void set_relay1(bool state) {
    relay1_state = state;
    digitalWrite(RELAY1, state ? HIGH : LOW);
}

static void set_relay2(bool state) {
    relay2_state = state;
    digitalWrite(RELAY2, state ? HIGH : LOW);
}

/* ═══════════════════════════════════════════════════════════════
 * TOUCH — fires relay immediately, queues event for master
 * ═══════════════════════════════════════════════════════════════ */
static void handle_touch(void) {
    bool t1 = (digitalRead(TOUCH1) == HIGH);
    bool t2 = (digitalRead(TOUCH2) == HIGH);

    if (t1 && !last_t1) {
        set_relay1(!relay1_state);
        push_event(1, relay1_state ? 1 : 0);
    }
    if (t2 && !last_t2) {
        set_relay2(!relay2_state);
        push_event(2, relay2_state ? 1 : 0);
    }

    last_t1 = t1;
    last_t2 = t2;
}

/* ═══════════════════════════════════════════════════════════════
 * SEND STATE_RESP
 * ═══════════════════════════════════════════════════════════════ */
static void send_state_resp(void) {
    uint8_t payload[3 + 5 * 5]; /* max 5 events inline */
    uint8_t plen = 0;

    uint8_t flags = 0;
    if (relay1_state)   flags |= 0x01;
    if (relay2_state)   flags |= 0x02;
    if (event_count > 0) flags |= 0x04;

    payload[plen++] = flags;
    payload[plen++] = 25;         /* temp — not available on STM8S103 */
    payload[plen++] = event_count;

    /* Append up to 5 events */
    uint8_t tail = event_tail;
    uint8_t cnt  = event_count < 5 ? event_count : 5;
    for (uint8_t i = 0; i < cnt; i++) {
        uint32_t ts = event_buf[tail].ts_ms;
        payload[plen++] = event_buf[tail].channel;
        payload[plen++] = event_buf[tail].state;
        payload[plen++] = (ts >> 16) & 0xFF;
        payload[plen++] = (ts >>  8) & 0xFF;
        payload[plen++] = (ts)       & 0xFF;
        tail = (tail + 1) % EVENT_BUF_SIZE;
    }

    send_frame(ADDR_MASTER, CMD_STATE_RESP, payload, plen);
}

/* ═══════════════════════════════════════════════════════════════
 * PROCESS FRAME
 * ═══════════════════════════════════════════════════════════════ */
static void process_frame(uint8_t *frame, uint8_t len) {
    uint8_t dst  = frame[1];
    uint8_t cmd  = frame[3];
    uint8_t plen = frame[4];
    uint8_t *payload = &frame[5];

    /* CRC check */
    if (frame[5 + plen] != crc8(&frame[1], 4 + plen)) return;

    /* Is this frame for us? */
    bool for_me = (dst == slot_address) ||
                  (dst == ADDR_BCAST)   ||
                  (dst == ADDR_UNASSIGNED &&
                   slot_address == ADDR_UNASSIGNED);
    if (!for_me) return;

    uint8_t uid[4];
    uint8_t buf[8];
    uint32_t uptime_s;

    switch (cmd) {

    case CMD_PING:
        uptime_s    = millis() / 1000;
        buf[0]      = 1; buf[1] = 1; /* fw v1.1 */
        buf[2]      = (uptime_s >> 24) & 0xFF;
        buf[3]      = (uptime_s >> 16) & 0xFF;
        buf[4]      = (uptime_s >>  8) & 0xFF;
        buf[5]      = (uptime_s)       & 0xFF;
        send_frame(ADDR_MASTER, CMD_PONG, buf, 6);
        break;

    case CMD_ENUM_REQ:
        /* Respond if:
         *   a) We are unaddressed (broadcast discovery), OR
         *   b) This ENUM_REQ was sent directly to our address (master querying our UID)
         * For broadcast (dst=0xFF) only respond if unaddressed to avoid collision.
         * For unicast (dst=our address) always respond regardless of address state. */
        if (dst == ADDR_BCAST && slot_address != ADDR_UNASSIGNED) break;
        get_uid(uid);
        if (dst == ADDR_BCAST) {
            /* Random backoff 0–50ms to avoid collision with other unaddressed extensions */
            delay(uid[3] % 50);
        }
        buf[0] = uid[0]; buf[1] = uid[1];
        buf[2] = uid[2]; buf[3] = uid[3];
        buf[4] = 0x01; /* device type: extension */
        send_frame(ADDR_MASTER, CMD_ENUM_RESP, buf, 5);
        break;

    case CMD_SET_ADDR:
        if (plen < 5) break;
        get_uid(uid);
        /* Verify UID matches */
        if (payload[0] != uid[0] || payload[1] != uid[1] ||
            payload[2] != uid[2] || payload[3] != uid[3]) break;
        save_address(payload[4]);
        /* Confirm with PONG on new address */
        uptime_s = millis() / 1000;
        buf[0]   = 1; buf[1] = 1;
        buf[2]   = (uptime_s >> 24) & 0xFF;
        buf[3]   = (uptime_s >> 16) & 0xFF;
        buf[4]   = (uptime_s >>  8) & 0xFF;
        buf[5]   = (uptime_s)       & 0xFF;
        send_frame(ADDR_MASTER, CMD_PONG, buf, 6);
        break;

    case CMD_GET_STATE:
        send_state_resp();
        break;

    case CMD_SET_RELAY:
        if (plen < 1) break;
        set_relay1((payload[0] & 0x01) != 0);
        set_relay2((payload[0] & 0x02) != 0);
        send_state_resp();
        break;

    case CMD_DRAIN_EVENTS:
        if (plen < 1) break;
        drain_events(payload[0]);
        break;

    case CMD_IDENTIFY:
        /* Blink all LEDs for duration seconds */
        {
            uint8_t secs   = (plen > 0) ? payload[0] : 3;
            uint8_t blinks = secs * 4;
            for (uint8_t b = 0; b < blinks; b++) {
                digitalWrite(LED,    HIGH);
                digitalWrite(RELAY1, HIGH);
                digitalWrite(RELAY2, HIGH);
                delay(125);
                digitalWrite(LED,    LOW);
                digitalWrite(RELAY1, LOW);
                digitalWrite(RELAY2, LOW);
                delay(125);
            }
        }
        break;

    default:
        buf[0] = cmd;
        buf[1] = 0x01; /* unknown command */
        send_frame(ADDR_MASTER, CMD_ERROR, buf, 2);
        break;
    }
}

/* ═══════════════════════════════════════════════════════════════
 * BUS RX — non-blocking, called every loop iteration
 * ═══════════════════════════════════════════════════════════════ */
static void bus_rx_tick(void) {
    while (Serial_available()) {
        uint8_t b = (uint8_t)Serial_read();
        if (rx_pos == 0) {
            if (b == SOF) rx_buf[rx_pos++] = b;
        } else {
            if (rx_pos >= sizeof(rx_buf)) { rx_pos = 0; rx_elen = 0; return; }
            rx_buf[rx_pos++] = b;
            if (rx_pos == 5) rx_elen = 6 + rx_buf[4];
            if (rx_elen > 0 && rx_pos >= rx_elen) {
                process_frame(rx_buf, rx_pos);
                rx_pos  = 0;
                rx_elen = 0;
            }
        }
    }
}

/* ═══════════════════════════════════════════════════════════════
 * STARTUP BLINK
 * 5 blinks = unaddressed (new extension)
 * 2 blinks = has stored address
 * ═══════════════════════════════════════════════════════════════ */
static void startup_blink(void) {
    uint8_t blinks = (slot_address == ADDR_UNASSIGNED) ? 5 : 2;
    for (uint8_t i = 0; i < blinks; i++) {
        digitalWrite(LED,    HIGH);
        digitalWrite(RELAY1, HIGH);
        digitalWrite(RELAY2, HIGH);
        delay(200);
        digitalWrite(LED,    LOW);
        digitalWrite(RELAY1, LOW);
        digitalWrite(RELAY2, LOW);
        delay(200);
    }
}

/* ═══════════════════════════════════════════════════════════════
 * SETUP
 * ═══════════════════════════════════════════════════════════════ */
void setup() {
    pinMode(RELAY1, OUTPUT); digitalWrite(RELAY1, LOW);
    pinMode(RELAY2, OUTPUT); digitalWrite(RELAY2, LOW);
    pinMode(LED,    OUTPUT); digitalWrite(LED,    LOW);
    pinMode(DE_RE,  OUTPUT); digitalWrite(DE_RE,  LOW); /* RX mode */
    pinMode(TOUCH1, INPUT);
    pinMode(TOUCH2, INPUT);

    Serial_begin(UART_BAUD);

    load_address();
    startup_blink();
}

/* ═══════════════════════════════════════════════════════════════
 * LOOP
 * ═══════════════════════════════════════════════════════════════ */
void loop() {
    static unsigned long last_blink = 0;
    static bool hb = false;

    /* 1. Touch — immediate relay action, no waiting */
    handle_touch();

    /* 2. Bus RX — process any incoming frames */
    bus_rx_tick();

    /* 3. Heartbeat blink every 500ms */
    if (millis() - last_blink >= 500) {
        last_blink = millis();
        hb = !hb;
        digitalWrite(LED, hb ? HIGH : LOW);
    }
}
