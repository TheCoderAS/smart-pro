/*
 * Unisync - Extension Firmware v3.0
 * STM8S103F3P6 via sduino
 *
 * Architecture:
 *   REGISTERED   -> wait for master poll, respond to GET_STATE
 *   UNREGISTERED -> broadcast ANNOUNCE every 2s + random stagger
 *
 * Pins:
 *   PA3  - Touch 1
 *   PA2  - Touch 2
 *   PD4  - Relay 1
 *   PC3  - Relay 2
 *   PB5  - Onboard LED (heartbeat)
 *   PD5  - UART1 TX -> MAX485 DI (fixed)
 *   PD6  - UART1 RX -> MAX485 RO (fixed)
 *   PD3  - MAX485 DE/RE
 */

/* ================================================================
 * PIN DEFINITIONS
 * ================================================================ */
#define RELAY1   PD4
#define RELAY2   PC3
#define LED      PB5
#define TOUCH1   PA3
#define TOUCH2   PA2
#define DE_RE    PD3

/* ================================================================
 * PROTOCOL
 * ================================================================ */
#define UART_BAUD         250000
#define SOF               0xAA
#define ADDR_MASTER       0x00
#define ADDR_UNASSIGNED   0xFE
#define ADDR_BCAST        0xFF

/* Commands - existing */
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

/* Commands - new hybrid architecture */
#define CMD_ANNOUNCE      0x50  /* E->M: uid[4] + flags */
#define CMD_WELCOME       0x51  /* M->E: uid[4] + address + relay1 + relay2 + master_uid[4] */
#define CMD_REJECT        0x52  /* M->E: uid[4] */
#define CMD_CHALLENGE     0x54  /* M->E: uid[4] + challenge[4] */
#define CMD_RESPONSE      0x55  /* E->M: uid[4] + crc32[4] */

/* Secret key - must match master firmware exactly */
static const uint8_t SECRET_KEY[16] = {0x55, 0x6E, 0x69, 0x73, 0x79, 0x6E, 0x63, 0x53, 0x77, 0x69, 0x74, 0x63, 0x68, 0x4B, 0x65, 0x79};

/* ================================================================
 * EEPROM ADDRESSES (STM8 data EEPROM at 0x4000)
 * ================================================================ */
#define EEPROM_MAGIC_ADDR     0x4000  /* 0xA5 = valid */
#define EEPROM_ADDR_ADDR      0x4001  /* assigned bus address */
#define EEPROM_RELAY_ADDR     0x4002  /* bit0=relay1, bit1=relay2 */
#define EEPROM_MASTER_UID     0x4003  /* master UID bytes 0-3 (H5: one master only) */
#define EEPROM_MAGIC_VAL      0xA5

/* ================================================================
 * STATE
 * ================================================================ */
#define ORPHAN_TIMEOUT_MS  30000  /* 30s no poll -> self unregister */

typedef enum {
    MODE_UNREGISTERED = 0,  /* announce every 2s */
    MODE_REGISTERED,        /* respond to master polls */
    MODE_OTA,               /* OTA in progress - touch only */
    MODE_QUIET              /* BUS_QUIET received during OTA */
} ext_mode_t;

static ext_mode_t mode         = MODE_UNREGISTERED;
static uint8_t    slot_address = ADDR_UNASSIGNED;
static uint8_t    master_uid[4] = {0};
static bool       relay1_state = false;
static bool       relay2_state = false;

/* Touch event ring buffer */
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
static uint32_t last_poll_ms  = 0;
static bool     poll_received = false;

/* RX accumulator */
static uint8_t rx_buf[40];
static uint8_t rx_pos  = 0;
static uint8_t rx_elen = 0;

/* Announce timing */
static uint32_t last_announce_ms = 0;
static uint32_t announce_interval = 2000;  /* ms, randomized per cycle */

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

/* CRC32 for challenge-response security */
static uint32_t crc32_compute(const uint8_t *data, uint8_t len) {
    uint32_t crc = 0xFFFFFFFF;
    while (len--) {
        crc ^= *data++;
        for (uint8_t i = 0; i < 8; i++)
            crc = (crc & 1) ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
    return crc ^ 0xFFFFFFFF;
}

/* Compute challenge response: CRC32(secret_key + challenge[4] + uid[4]) */
static uint32_t compute_response(const uint8_t *challenge, const uint8_t *uid) {
    uint8_t buf[24];
    uint8_t i;
    for (i=0; i<16; i++) buf[i]    = SECRET_KEY[i];
    for (i=0; i<4;  i++) buf[16+i] = challenge[i];
    for (i=0; i<4;  i++) buf[20+i] = uid[i];
    return crc32_compute(buf, 24);
}

/* ================================================================
 * EEPROM
 * ================================================================ */
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

/* ================================================================
 * CHIP UID
 * ================================================================ */
static void get_uid(uint8_t *uid) {
    uid[0] = *((volatile uint8_t *)0x4865);
    uid[1] = *((volatile uint8_t *)0x4866);
    uid[2] = *((volatile uint8_t *)0x4867);
    uid[3] = *((volatile uint8_t *)0x4868);
}

/* ================================================================
 * EEPROM PERSISTENCE
 * ================================================================ */
static void load_state(void) {
    if (eeprom_read(EEPROM_MAGIC_ADDR) != EEPROM_MAGIC_VAL) {
        mode         = MODE_UNREGISTERED;
        slot_address = ADDR_UNASSIGNED;
        return;
    }
    slot_address  = eeprom_read(EEPROM_ADDR_ADDR);
    master_uid[0] = eeprom_read(EEPROM_MASTER_UID + 0);
    master_uid[1] = eeprom_read(EEPROM_MASTER_UID + 1);
    master_uid[2] = eeprom_read(EEPROM_MASTER_UID + 2);
    master_uid[3] = eeprom_read(EEPROM_MASTER_UID + 3);
    uint8_t relay = eeprom_read(EEPROM_RELAY_ADDR);
    relay1_state  = (relay & 0x01) != 0;
    relay2_state  = (relay & 0x02) != 0;
    mode          = MODE_REGISTERED;
}

static void self_unregister(void) {
    /* Turn relays OFF and clear saved state */
    relay1_state = false;
    relay2_state = false;
    digitalWrite(RELAY1, HIGH);  /* active LOW - HIGH = OFF */
    digitalWrite(RELAY2, HIGH);
    eeprom_write(EEPROM_RELAY_ADDR, 0x00);
    /* Wipe EEPROM - extension becomes unregistered */
    eeprom_write(EEPROM_MAGIC_ADDR,     0x00);
    eeprom_write(EEPROM_ADDR_ADDR,      0x00);
    eeprom_write(EEPROM_MASTER_UID + 0, 0x00);
    eeprom_write(EEPROM_MASTER_UID + 1, 0x00);
    eeprom_write(EEPROM_MASTER_UID + 2, 0x00);
    eeprom_write(EEPROM_MASTER_UID + 3, 0x00);
    slot_address    = ADDR_UNASSIGNED;
    mode            = MODE_UNREGISTERED;
    poll_received   = false;
    announce_interval = 2000;  /* self-unregistered - announce every 2s */
    last_announce_ms  = 0;     /* announce immediately */
    /* Visual indicator - 5 rapid blinks */
    for (uint8_t i = 0; i < 5; i++) {
        digitalWrite(LED, HIGH); delay(100);
        digitalWrite(LED, LOW);  delay(100);
    }
}

static void save_registration(uint8_t addr, uint8_t *m_uid) {
    eeprom_write(EEPROM_ADDR_ADDR,      addr);
    eeprom_write(EEPROM_MASTER_UID + 0, m_uid[0]);
    eeprom_write(EEPROM_MASTER_UID + 1, m_uid[1]);
    eeprom_write(EEPROM_MASTER_UID + 2, m_uid[2]);
    eeprom_write(EEPROM_MASTER_UID + 3, m_uid[3]);
    eeprom_write(EEPROM_MAGIC_ADDR,     EEPROM_MAGIC_VAL);
    /* Verify */
    if (eeprom_read(EEPROM_MAGIC_ADDR) != EEPROM_MAGIC_VAL) {
        delay(10);
        eeprom_write(EEPROM_ADDR_ADDR,      addr);
        eeprom_write(EEPROM_MASTER_UID + 0, m_uid[0]);
        eeprom_write(EEPROM_MASTER_UID + 1, m_uid[1]);
        eeprom_write(EEPROM_MASTER_UID + 2, m_uid[2]);
        eeprom_write(EEPROM_MASTER_UID + 3, m_uid[3]);
        eeprom_write(EEPROM_MAGIC_ADDR,     EEPROM_MAGIC_VAL);
    }
}

static void save_relay_state(void) {
    uint8_t val = 0;
    if (relay1_state) val |= 0x01;
    if (relay2_state) val |= 0x02;
    eeprom_write(EEPROM_RELAY_ADDR, val);
}

/* ================================================================
 * RS-485
 * ================================================================ */
static void rs485_send(uint8_t *frame, uint8_t len) {
    digitalWrite(DE_RE, HIGH);
    delayMicroseconds(10);
    for (uint8_t i = 0; i < len; i++) Serial_write(frame[i]);
    while (!(UART1->SR & UART1_SR_TC));
    delayMicroseconds(10);
    digitalWrite(DE_RE, LOW);
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
    frame[5+plen] = crc8(&frame[1], 4+plen);
    rs485_send(frame, 6+plen);
}

/* ================================================================
 * RELAY CONTROL
 * ================================================================ */
static void set_relay1(bool s) {
    relay1_state = s;
    digitalWrite(RELAY1, s ? LOW : HIGH);  /* active LOW relay */
    save_relay_state();
}

static void set_relay2(bool s) {
    relay2_state = s;
    digitalWrite(RELAY2, s ? LOW : HIGH);  /* active LOW relay */
    save_relay_state();
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
 * TOUCH HANDLER - always active regardless of mode
 * ================================================================ */
static void handle_touch(void) {
    bool t1 = (digitalRead(TOUCH1) == HIGH);
    bool t2 = (digitalRead(TOUCH2) == HIGH);
    if (t1 && !last_t1) { set_relay1(!relay1_state); push_event(1, relay1_state?1:0); }
    if (t2 && !last_t2) { set_relay2(!relay2_state); push_event(2, relay2_state?1:0); }
    last_t1 = t1;
    last_t2 = t2;
}

/* ================================================================
 * ANNOUNCE (unregistered mode)
 * ================================================================ */
static void send_announce(void) {
    uint8_t uid[4]; get_uid(uid);
    uint8_t payload[5];
    payload[0] = uid[0]; payload[1] = uid[1];
    payload[2] = uid[2]; payload[3] = uid[3];
    payload[4] = (relay1_state ? 0x01 : 0x00) |
                 (relay2_state ? 0x02 : 0x00) |
                 (event_count  ? 0x04 : 0x00);
    /* SRC=0xFE for unregistered */
    uint8_t frame[40];
    frame[0] = SOF;
    frame[1] = ADDR_MASTER;
    frame[2] = ADDR_UNASSIGNED;
    frame[3] = CMD_ANNOUNCE;
    frame[4] = 5;
    for (uint8_t i = 0; i < 5; i++) frame[5+i] = payload[i];
    frame[10] = crc8(&frame[1], 9);
    rs485_send(frame, 11);
}

/* ================================================================
 * STATE RESPONSE (registered mode)
 * ================================================================ */
static void send_state_resp(void) {
    uint8_t payload[3 + 5*5];
    uint8_t plen = 0;
    uint8_t flags = 0;
    if (relay1_state)  flags |= 0x01;
    if (relay2_state)  flags |= 0x02;
    if (event_count>0) flags |= 0x04;
    payload[plen++] = flags;
    payload[plen++] = 25;  /* temp placeholder */
    payload[plen++] = event_count;
    { uint8_t tail = event_tail;
      uint8_t cnt  = event_count < 5 ? event_count : 5;
      uint8_t ei;
      for (ei = 0; ei < cnt; ei++) {
        uint32_t ts = event_buf[tail].ts_ms;
        payload[plen++] = event_buf[tail].channel;
        payload[plen++] = event_buf[tail].state;
        payload[plen++] = (ts >> 16) & 0xFF;
        payload[plen++] = (ts >>  8) & 0xFF;
        payload[plen++] = (ts)       & 0xFF;
        tail = (tail + 1) % EVENT_BUF_SIZE;
      }
    }
    send_frame(ADDR_MASTER, CMD_STATE_RESP, payload, plen);
}

/* ================================================================
 * PROCESS INCOMING FRAME
 * ================================================================ */
static void process_frame(uint8_t *frame, uint8_t len) {
    uint8_t dst  = frame[1];
    uint8_t cmd  = frame[3];
    uint8_t plen = frame[4];
    uint8_t *p   = &frame[5];
    uint8_t uid[4]; get_uid(uid);
    uint8_t buf[8];
    uint32_t uptime_s;

    if (frame[5+plen] != crc8(&frame[1], 4+plen)) return;

    /* WELCOME and REJECT use UID addressing, not bus address */
    if (cmd == CMD_WELCOME) {
        if (plen < 10) return;
        /* Verify UID matches us */
        if (p[0]!=uid[0]||p[1]!=uid[1]||p[2]!=uid[2]||p[3]!=uid[3]) return;
        /* H5: check if already registered to a different master
         * Only enforce if stored master_uid is non-zero (valid)
         * A5A5A5A5 is uninitialized EEPROM pattern - ignore it  */
        if (mode == MODE_REGISTERED) {
            bool stored_valid = (master_uid[0]!=0xA5 || master_uid[1]!=0xA5 ||
                                 master_uid[2]!=0xA5 || master_uid[3]!=0xA5) &&
                                (master_uid[0]!=0x00 || master_uid[1]!=0x00 ||
                                 master_uid[2]!=0x00 || master_uid[3]!=0x00);
            if (stored_valid) {
                bool same_master = (p[6]==master_uid[0] && p[7]==master_uid[1] &&
                                    p[8]==master_uid[2] && p[9]==master_uid[3]);
                if (!same_master) {
                    send_frame(ADDR_MASTER, CMD_ERROR, uid, 4);
                    return;
                }
            }
        }
        uint8_t new_addr  = p[4];
        bool    new_r1    = p[5] & 0x01;
        bool    new_r2    = p[5] & 0x02;
        uint8_t m_uid[4]  = {p[6], p[7], p[8], p[9]};
        /* Save registration */
        save_registration(new_addr, m_uid);
        slot_address  = new_addr;
        master_uid[0] = m_uid[0]; master_uid[1] = m_uid[1];
        master_uid[2] = m_uid[2]; master_uid[3] = m_uid[3];
        mode = MODE_REGISTERED;
        /* Restore relay states from master */
        set_relay1(new_r1);
        set_relay2(new_r2);
        /* Confirm with PONG */
        uptime_s = millis() / 1000;
        buf[0]=1; buf[1]=0;
        buf[2]=(uptime_s>>24)&0xFF; buf[3]=(uptime_s>>16)&0xFF;
        buf[4]=(uptime_s>>8)&0xFF;  buf[5]=(uptime_s)&0xFF;
        send_frame(ADDR_MASTER, CMD_PONG, buf, 6);
        /* Reset orphan timer - we just got welcomed, start fresh */
        last_poll_ms  = millis(); /* reset orphan timer on welcome */
        poll_received = false;
        /* Stop announcing immediately - master will poll us now */
        last_announce_ms = millis() + 30000;
        announce_interval = 2000;

        /* Visual confirmation - 2 quick blinks */
        digitalWrite(LED, LOW); delay(100); digitalWrite(LED, HIGH); delay(100);
        digitalWrite(LED, LOW); delay(100); digitalWrite(LED, HIGH); delay(100);
        return;
    }

    if (cmd == CMD_REJECT) {
        if (plen < 4) return;
        if (p[0]!=uid[0]||p[1]!=uid[1]||p[2]!=uid[2]||p[3]!=uid[3]) return;
        /* Back off to 10s announce interval */
        announce_interval = 10000;
        return;
    }

    if (cmd == CMD_CHALLENGE) {
        /* Master is challenging us before WELCOME
         * payload: uid[4] + challenge[4]                          */
        if (plen < 8) return;
        if (p[0]!=uid[0]||p[1]!=uid[1]||p[2]!=uid[2]||p[3]!=uid[3]) return;
        uint8_t *challenge = &p[4];
        uint32_t resp = compute_response(challenge, uid);
        uint8_t payload[8];
        payload[0]=uid[0]; payload[1]=uid[1];
        payload[2]=uid[2]; payload[3]=uid[3];
        payload[4]=(resp>>24)&0xFF;
        payload[5]=(resp>>16)&0xFF;
        payload[6]=(resp>>8) &0xFF;
        payload[7]=(resp)    &0xFF;
        /* Send RESPONSE from unregistered address */
        uint8_t frame[40];
        frame[0]=SOF; frame[1]=ADDR_MASTER; frame[2]=ADDR_UNASSIGNED;
        frame[3]=CMD_RESPONSE; frame[4]=8;
        memcpy(&frame[5], payload, 8);
        frame[13]=crc8(&frame[1],12);
        rs485_send(frame,14);
        return;
    }

    /* All other commands require correct bus address */
    bool for_me = (dst == slot_address) || (dst == ADDR_BCAST);
    if (!for_me) return;

    /* H5: verify master UID for registered extensions */
    /* (master UID check would go here with auth in future) */

    switch (cmd) {

    case CMD_PING:
        uptime_s = millis() / 1000;
        buf[0]=1; buf[1]=0;
        buf[2]=(uptime_s>>24)&0xFF; buf[3]=(uptime_s>>16)&0xFF;
        buf[4]=(uptime_s>>8)&0xFF;  buf[5]=(uptime_s)&0xFF;
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
        { uint8_t b2, bmax=(plen>0?p[0]:3)*4;
          for (b2=0; b2<bmax; b2++) {
            digitalWrite(LED, HIGH); delay(125);
            digitalWrite(LED, LOW);  delay(125);
          }
        }
        break;

    case CMD_BUS_QUIET:
        /* OTA about to start - suppress announces */
        mode = MODE_QUIET;
        break;

    case CMD_OTA_BEGIN:
        mode = MODE_OTA;
        /* ACK */
        buf[0] = 0x00;
        send_frame(ADDR_MASTER, CMD_OTA_ACK, buf, 1);
        break;

    case CMD_OTA_END:
        /* Verify and commit - simplified for now */
        buf[0] = 0x00;
        send_frame(ADDR_MASTER, CMD_OTA_ACK, buf, 1);
        /* Resume normal mode */
        mode = MODE_REGISTERED;
        break;

    default:
        buf[0]=cmd; buf[1]=0x01;
        send_frame(ADDR_MASTER, CMD_ERROR, buf, 2);
        break;
    }
}

/* ================================================================
 * BUS RX - non-blocking
 * ================================================================ */
static void bus_rx_tick(void) {
    while (Serial_available()) {
        uint8_t b = (uint8_t)Serial_read();
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
 * PSEUDO-RANDOM from UID (no stdlib on STM8)
 * ================================================================ */
static uint32_t rand_seed = 0;
static uint16_t pseudo_rand(uint16_t max) {
    rand_seed = rand_seed * 1664525 + 1013904223;
    return (uint16_t)((rand_seed >> 16) % max);
}

/* ================================================================
 * STARTUP BLINK
 * ================================================================ */
static void startup_blink(void) {
    uint8_t blinks = (mode == MODE_UNREGISTERED) ? 5 : 2;
    uint8_t b;
    for (b=0; b<blinks; b++) {
        digitalWrite(LED, HIGH); delay(200);
        digitalWrite(LED, LOW);  delay(200);
    }
}

/* ================================================================
 * SETUP
 * ================================================================ */
void setup() {
    pinMode(RELAY1, OUTPUT); digitalWrite(RELAY1, HIGH);  /* HIGH = relay OFF */
    pinMode(RELAY2, OUTPUT); digitalWrite(RELAY2, HIGH);  /* HIGH = relay OFF */
    pinMode(LED,    OUTPUT); digitalWrite(LED,    LOW);
    pinMode(DE_RE,  OUTPUT); digitalWrite(DE_RE,  LOW);
    pinMode(TOUCH1, INPUT);
    pinMode(TOUCH2, INPUT);

    Serial_begin(UART_BAUD);

    /* Seed random with UID */
    uint8_t uid[4]; get_uid(uid);
    rand_seed = ((uint32_t)uid[0]<<24)|((uint32_t)uid[1]<<16)|
                ((uint32_t)uid[2]<<8)|(uint32_t)uid[3];

    load_state();

    /* Apply restored relay states to GPIO (active LOW) */
    digitalWrite(RELAY1, relay1_state ? LOW : HIGH);
    digitalWrite(RELAY2, relay2_state ? LOW : HIGH);

    last_poll_ms = millis(); /* start orphan timer from boot */
    startup_blink();
}

/* ================================================================
 * LOOP
 * ================================================================ */
void loop() {
    static uint32_t last_hb = 0;
    static bool hb = false;

    /* Touch always works regardless of mode */
    handle_touch();

    /* Bus RX always active */
    if (mode != MODE_OTA) {
        bus_rx_tick();
    }

    /* Mode-specific behavior */
    switch (mode) {

    case MODE_UNREGISTERED:
        /* Announce every 2s + random 0-500ms stagger */
        if ((millis() - last_announce_ms) >= announce_interval) {
            last_announce_ms = millis();
            announce_interval = 2000 + pseudo_rand(500);
            send_announce();
        }
        break;

    case MODE_REGISTERED:
        /* Check for orphan condition:
         * Case 1: Never received a poll since boot (master doesn't know us)
         * Case 2: Was receiving polls but stopped (master removed/replaced)
         * Both cases: self unregister after ORPHAN_TIMEOUT_MS             */
        if ((millis() - last_poll_ms) > ORPHAN_TIMEOUT_MS &&
            millis() > ORPHAN_TIMEOUT_MS) {
            self_unregister();
        }
        break;

    case MODE_OTA:
        /* Only touch works - bus_rx_tick skipped above */
        /* OTA frames handled elsewhere */
        break;

    case MODE_QUIET:
        /* Suppress announces - master is doing OTA on another extension */
        bus_rx_tick(); /* Still listen for OTA_END or resume */
        break;
    }

    /* Heartbeat LED:
     * Registered   -> 250ms ON, 4750ms OFF (5s period, brief pulse)
     * Unregistered -> 200ms ON, 200ms OFF (rapid blink)               */
    if (mode == MODE_REGISTERED) {
        /* OFF for 4750ms, then ON for 250ms */
        if (hb && (millis() - last_hb) >= 250) {
            last_hb = millis(); hb = false;
            digitalWrite(LED, HIGH);    /* OFF for 4750ms */
        } else if (!hb && (millis() - last_hb) >= 4750) {
            last_hb = millis(); hb = true;
            digitalWrite(LED, LOW);   /* ON for 250ms */
        }
    } else {
        if ((millis() - last_hb) >= 200) {
            last_hb = millis(); hb = !hb;
            digitalWrite(LED, hb ? LOW : HIGH);
        }
    }
}
