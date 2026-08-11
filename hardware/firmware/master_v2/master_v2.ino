/*
 * Unisync - Master Firmware v11.29.0
 * ESP32-C6 Beetle v1.1
 *
 * Architecture:
 *   - Registered extensions: master polls (GET_STATE every 200ms)
 *   - Unregistered extensions: self-announce (ANNOUNCE every ~2s)
 *   - Master listens for ANNOUNCE in dedicated window every 1s
 *   - WebSocket push on every state change
 *   - Boot overlay until first poll cycle complete
 *   - Batch modal for multiple unregistered extensions
 *   - H5: Only one master per bus
 *
 * Pins:
 *   GPIO4  - RS485 RX  GPIO5  - RS485 TX
 *   GPIO16 - Relay 1   GPIO17 - Relay 2
 *   GPIO19 - Touch 1   GPIO20 - Touch 2
 *   GPIO23 - RS485 DE/RE
 */

#include "Arduino.h"
#include "HardwareSerial.h"
#include "WiFi.h"
#include "WebServer.h"
#include "Preferences.h"
#include "Update.h"
#include <LittleFS.h>
#include <HTTPClient.h>
#include "esp_ota_ops.h"
#include "esp_partition.h"
#include "mbedtls/sha256.h"
/* NimBLE rather than the Bluedroid stack: same functionality, roughly
 * 100-150 KB smaller. Install "NimBLE-Arduino" from the Library Manager. */
#include <NimBLEDevice.h>

/* Single source of truth for the master version. Referenced by the boot
 * banner and served over /api/info; never duplicate it in the UI. */
#define MASTER_FW_VERSION  "11.29.0"
#define WEBSOCKETS_MAX_DATA_SIZE 16384
#include <WebSocketsServer.h>
#include <ArduinoJson.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "freertos/queue.h"
#include "esp_now.h"
#include "esp_mac.h"
#include "esp_wifi.h"
#include "driver/gpio.h"

/* Placed directly after the includes on purpose: the Arduino build
 * generates function prototypes and inserts them above the first
 * function in the sketch. A type used in a prototype must therefore
 * be declared before that point, or every SHA-256 function fails to
 * compile with "sha256_t was not declared in this scope".
 */
/* ================================================================
 * SHA-256 and HMAC-SHA-256
 * Compact implementation shared byte-for-byte by the master and the
 * extension so both sides can never disagree. Replaces CRC32, which is
 * linear and therefore forgeable from a handful of observed pairs.
 * ================================================================ */
typedef struct {
    uint32_t st[8];
    uint32_t len;
    uint8_t  buf[64];
    uint8_t  n;
} sha256_t;

static const uint32_t SHA_K[64] = {
0x428a2f98UL,0x71374491UL,0xb5c0fbcfUL,0xe9b5dba5UL,0x3956c25bUL,0x59f111f1UL,
0x923f82a4UL,0xab1c5ed5UL,0xd807aa98UL,0x12835b01UL,0x243185beUL,0x550c7dc3UL,
0x72be5d74UL,0x80deb1feUL,0x9bdc06a7UL,0xc19bf174UL,0xe49b69c1UL,0xefbe4786UL,
0x0fc19dc6UL,0x240ca1ccUL,0x2de92c6fUL,0x4a7484aaUL,0x5cb0a9dcUL,0x76f988daUL,
0x983e5152UL,0xa831c66dUL,0xb00327c8UL,0xbf597fc7UL,0xc6e00bf3UL,0xd5a79147UL,
0x06ca6351UL,0x14292967UL,0x27b70a85UL,0x2e1b2138UL,0x4d2c6dfcUL,0x53380d13UL,
0x650a7354UL,0x766a0abbUL,0x81c2c92eUL,0x92722c85UL,0xa2bfe8a1UL,0xa81a664bUL,
0xc24b8b70UL,0xc76c51a3UL,0xd192e819UL,0xd6990624UL,0xf40e3585UL,0x106aa070UL,
0x19a4c116UL,0x1e376c08UL,0x2748774cUL,0x34b0bcb5UL,0x391c0cb3UL,0x4ed8aa4aUL,
0x5b9cca4fUL,0x682e6ff3UL,0x748f82eeUL,0x78a5636fUL,0x84c87814UL,0x8cc70208UL,
0x90befffaUL,0xa4506cebUL,0xbef9a3f7UL,0xc67178f2UL };

#define SHA_ROR(x,n) (((x)>>(n))|((x)<<(32-(n))))

static void sha256_block(sha256_t *c, const uint8_t *p) {
    uint32_t w[64], a,b,cc,d,e,f,g,h,t1,t2;
    for (int i=0;i<16;i++)
        w[i]=((uint32_t)p[i*4]<<24)|((uint32_t)p[i*4+1]<<16)|
             ((uint32_t)p[i*4+2]<<8)|(uint32_t)p[i*4+3];
    for (int i=16;i<64;i++) {
        uint32_t s0=SHA_ROR(w[i-15],7)^SHA_ROR(w[i-15],18)^(w[i-15]>>3);
        uint32_t s1=SHA_ROR(w[i-2],17)^SHA_ROR(w[i-2],19)^(w[i-2]>>10);
        w[i]=w[i-16]+s0+w[i-7]+s1;
    }
    a=c->st[0];b=c->st[1];cc=c->st[2];d=c->st[3];
    e=c->st[4];f=c->st[5];g=c->st[6];h=c->st[7];
    for (int i=0;i<64;i++) {
        uint32_t S1=SHA_ROR(e,6)^SHA_ROR(e,11)^SHA_ROR(e,25);
        uint32_t ch=(e&f)^((~e)&g);
        t1=h+S1+ch+SHA_K[i]+w[i];
        uint32_t S0=SHA_ROR(a,2)^SHA_ROR(a,13)^SHA_ROR(a,22);
        uint32_t mj=(a&b)^(a&cc)^(b&cc);
        t2=S0+mj;
        h=g;g=f;f=e;e=d+t1;d=cc;cc=b;b=a;a=t1+t2;
    }
    c->st[0]+=a;c->st[1]+=b;c->st[2]+=cc;c->st[3]+=d;
    c->st[4]+=e;c->st[5]+=f;c->st[6]+=g;c->st[7]+=h;
}

static void sha256_init(sha256_t *c) {
    c->st[0]=0x6a09e667UL;c->st[1]=0xbb67ae85UL;c->st[2]=0x3c6ef372UL;
    c->st[3]=0xa54ff53aUL;c->st[4]=0x510e527fUL;c->st[5]=0x9b05688cUL;
    c->st[6]=0x1f83d9abUL;c->st[7]=0x5be0cd19UL;
    c->len=0;c->n=0;
}

static void sha256_update(sha256_t *c, const uint8_t *p, uint32_t n) {
    c->len += n;
    while (n--) {
        c->buf[c->n++]=*p++;
        if (c->n==64) { sha256_block(c,c->buf); c->n=0; }
    }
}

static void sha256_final(sha256_t *c, uint8_t *out) {
    uint32_t bits = c->len * 8;
    c->buf[c->n++]=0x80;
    if (c->n>56) { while(c->n<64) c->buf[c->n++]=0; sha256_block(c,c->buf); c->n=0; }
    while (c->n<56) c->buf[c->n++]=0;
    c->buf[56]=0;c->buf[57]=0;c->buf[58]=0;c->buf[59]=0;
    c->buf[60]=(bits>>24)&0xFF;c->buf[61]=(bits>>16)&0xFF;
    c->buf[62]=(bits>>8)&0xFF; c->buf[63]=bits&0xFF;
    sha256_block(c,c->buf);
    for (int i=0;i<8;i++) {
        out[i*4]  =(c->st[i]>>24)&0xFF; out[i*4+1]=(c->st[i]>>16)&0xFF;
        out[i*4+2]=(c->st[i]>>8)&0xFF;  out[i*4+3]=c->st[i]&0xFF;
    }
}

/* HMAC-SHA-256 with a 16-byte key. */
/* HMAC-SHA256 with an explicit key length.
 *
 * Everything on the device that predates this used 16-byte keys, and the
 * wrapper below keeps that exact behaviour for all of them. The BLE
 * per-command proof is the one place the key is longer: it is keyed on the
 * 32-character session token. */
static void hmac_sha256_k(const uint8_t *key, uint32_t klen,
                          const uint8_t *msg, uint32_t mlen, uint8_t *out32) {
    uint8_t k_ipad[64], k_opad[64], inner[32];
    sha256_t c;
    for (uint32_t i=0;i<64;i++) {
        uint8_t kb = (i<klen) ? key[i] : 0;
        k_ipad[i]=kb^0x36; k_opad[i]=kb^0x5c;
    }
    sha256_init(&c); sha256_update(&c,k_ipad,64);
    sha256_update(&c,msg,mlen); sha256_final(&c,inner);
    sha256_init(&c); sha256_update(&c,k_opad,64);
    sha256_update(&c,inner,32); sha256_final(&c,out32);
}

/* 16-byte keys: device keys, the mesh tag, pin wrapping, recovery. */
static void hmac_sha256(const uint8_t *key, const uint8_t *msg, uint32_t mlen,
                        uint8_t *out32) {
    hmac_sha256_k(key, 16, msg, mlen, out32);
}

/* Constant-time compare: an early exit leaks how many bytes matched. */
static bool ct_equal(const uint8_t *a, const uint8_t *b, uint8_t n) {
    uint8_t d=0;
    while (n--) d |= (uint8_t)(*a++ ^ *b++);
    return d==0;
}


/* ================================================================
 * PINS
 * ================================================================ */
#define TOUCH1_PIN    19
#define TOUCH2_PIN    20
#define RELAY1_PIN    17
#define RELAY2_PIN    21
#define RS485_DE_PIN  23

/* Factory reset button. GPIO9 is the BOOT pin on most ESP32-C6 boards and
 * is free after startup; production hardware needs a dedicated momentary
 * switch to ground on this pin.
 *
 * It is a strapping pin: held LOW during power-up the chip enters download
 * mode instead of running. So the button must not be held while power is
 * applied -- press it while the device is already running. */
#define RESET_BTN_PIN     9
#define RESET_HOLD_MS     9000UL
#define BUS_RX_PIN    4
#define BUS_TX_PIN    5

/* ================================================================
 * WIFI AP
 * ================================================================ */
#define AP_SSID    "Unisync"
#define AP_CHANNEL 1   /* Fixed channel -- ALL masters must use same channel for ESP-NOW */
#define AP_PASS   "12345678"
#define AP_IP     IPAddress(192,168,4,1)
#define AP_GW     IPAddress(192,168,4,1)
#define AP_SUBNET IPAddress(255,255,255,0)

/* ================================================================
 * PROTOCOL
 * ================================================================ */
#define UART_BAUD         250000
#define MAX_EXTENSIONS    5
#define POLL_MS           200
/* Presence (UX story, Epic 2). A "check-in" is one second of bus polling,
 * not a single 200 ms poll -- one dropped frame on a shared RS-485 bus is
 * noise, not an outage. Offline is declared after three missed check-ins. */
#define CHECKIN_MS        1000UL
#define CHECKIN_MISSES    3
#define MISSED_MAX        ((int)((CHECKIN_MS/POLL_MS)*CHECKIN_MISSES))  /* 15 polls = 3 s */
/* Coming back is not instant: an extension that has dropped only returns to
 * the dashboard after a solid minute of presence. Until then it reports as
 * "intermittent" so its switches don't blink in and out. */
#define PRESENCE_SETTLE_MS 60000UL
/* How long a drop is remembered. Two drops inside the window mark the board
 * intermittent while it is down, rather than plainly offline. */
#define PRESENCE_FLAP_MS   600000UL
/* Restore pushes are spaced this far apart, per channel, so a whole house
 * coming back after an outage doesn't slam every relay closed at once. */
#define RESTORE_STAGGER_MS 40UL
#define BUS_RESP_MS       20
#define LISTEN_WINDOW_MS  30
#define LISTEN_INTERVAL_MS 200
#define OFFLINE_TIMEOUT_MS 5000  /* boot grace period */

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
#define CMD_GET_INFO      0x24
#define CMD_INFO_RESP     0x25
#define CMD_IDENTIFY      0x30
#define CMD_OTA_BEGIN     0x40
#define CMD_OTA_CHUNK     0x41
#define CMD_OTA_END       0x42
#define CMD_OTA_ACK       0x43
#define CMD_BUS_QUIET     0x44
#define CMD_ANNOUNCE      0x50
#define CMD_WELCOME       0x51
#define CMD_REJECT        0x52
#define CMD_CHALLENGE     0x54  /* M->E: uid[4] + nonce[8] */
#define CMD_RESPONSE      0x55  /* E->M: uid[4] + hmac[8] */
#define CMD_FACTORY_RESET 0x60
#define CMD_ERROR         0xF0

/* Secret key - must match extension firmware exactly */

/* ================================================================
 * MESH CONFIG
 * ================================================================ */
/* 16 supports a 10-master mesh (9 peers each) with headroom. Costs about
 * 10 KB of SRAM; raise together with the mesh-status JSON buffer below. */
#define MAX_MESH_MASTERS   16     /* OTA-updatable */
#define MESH_GOSSIP_MS     500   /* state broadcast interval */
/* Mesh presence reuses the extension pattern (three missed check-ins), but a
 * mesh check-in is four gossip intervals: ESP-NOW shares the air with Wi-Fi
 * and loses frames the wired bus never does. 3 x 2 s = 6 s to declare a peer
 * offline. */
#define MESH_CHECKIN_MS    2000UL
#define MESH_PEER_TIMEOUT  (MESH_CHECKIN_MS * CHECKIN_MISSES)
#define MESH_PIN_VALID_MS  300000 /* PIN expires after 5 minutes */

/* Mesh packet types */
#define MESH_PKT_STATE     0x01  /* broadcast local switch states */
#define MESH_PKT_RELAY_CMD 0x02  /* relay command for another master */
#define MESH_PKT_RELAY_ACK 0x03  /* relay command result */
#define MESH_PKT_JOIN_REQ  0x04  /* new master wants to join */
#define MESH_PKT_JOIN_ACK  0x05  /* accept + send mesh credentials */
#define MESH_PKT_JOIN_REJ  0x06  /* reject (wrong PIN) */
#define MESH_PKT_LEAVE     0x07  /* master leaving mesh */
#define MESH_PKT_PING      0x08  /* keepalive */
#define MESH_PKT_PASS_CHG  0x09  /* password change broadcast */
#define MESH_PKT_CONFIG    0x0A
#define MESH_PKT_KICK      0x0B
#define MESH_PKT_KICK_ACK  0x0C  /* config command: rename/reorder */
#define MESH_PKT_RECFAIL   0x0D  /* recovery backoff, shared across the mesh */

/* ================================================================
 * RELAY RATE LIMITING
 * ================================================================ */
#define RELAY_RATE_LIMIT_MS  200  /* min ms between UI relay commands per channel */

/* ================================================================
 * DEVICE COLOR PALETTE
 * slot 0=master, 1-5=ext slots
 * ================================================================ */
static const char *SLOT_COLORS[] = {
    "#00d4ff",  /* 0 master  - cyan   */
    "#ffd700",  /* 1 ext 0   - yellow */
    "#ff6b6b",  /* 2 ext 1   - coral  */
    "#6bff6b",  /* 3 ext 2   - green  */
    "#ff9f43",  /* 4 ext 3   - orange */
    "#a29bfe"   /* 5 ext 4   - purple */
};

/* ================================================================
 * DATA TYPES
 * ================================================================ */
/* Bus liveness. This drives polling and command routing and is NOT what the
 * app sees -- see presence_t below. */
typedef enum { EXT_EMPTY=0, EXT_ONLINE, EXT_OFFLINE } ext_state_t;

/* What apps see. Deliberately a separate layer from bus liveness: a board can
 * be answering the bus (so we keep polling and controlling it) while still
 * reporting "intermittent" because it hasn't been solid for a minute yet. */
typedef enum { PRES_OFFLINE=0, PRES_ONLINE, PRES_INTERMITTENT } presence_t;

static const char *presence_str(presence_t p) {
    switch (p) {
        case PRES_ONLINE:       return "online";
        case PRES_INTERMITTENT: return "intermittent";
        default:                return "offline";
    }
}

/* Mesh switch state (for gossip) */
typedef struct {
    char     id[16];
    char     name[24];
    char     color[8];
    bool     state;
    bool     online;
    bool     restore; /* per-switch restore policy, gossiped so a peer's
                       * card can show and change it like a local one */
    uint8_t  ch;      /* relay channel (1 or 2) */
} mesh_switch_t;

/* Mesh peer (remote master) */
typedef struct {
    uint8_t       uid[4];
    uint8_t       mac[6];
    char          name[24];
    bool          online;          /* link liveness -- routing, not UI */
    uint32_t      last_seen_ms;
    /* Presence debounce, mirroring extension_t below. */
    uint32_t      settle_until_ms; /* 0 = settled; else back but not solid yet */
    uint32_t      last_drop_ms;
    uint8_t       drops;
    mesh_switch_t switches[12];
    uint8_t       switch_count;
    uint8_t       fw[3];          /* peer's master firmware version */
    int8_t        rssi;           /* how well we hear it -- pull proximity */
    uint32_t      fw_fail_until;  /* per-peer cooldown after a failed pull */
} mesh_peer_t;

/* ESP-NOW packet header */
typedef struct {
    uint8_t  type;        /* MESH_PKT_* */
    uint8_t  src_uid[4];  /* sender master UID */
    uint8_t  seq;         /* sequence number, wraps */
} __attribute__((packed)) mesh_hdr_t;

/* State broadcast packet */
typedef struct {
    mesh_hdr_t hdr;
    char       master_name[24];
    uint8_t    switch_count;
    /* followed by switch_count * mesh_switch_t */
} __attribute__((packed)) mesh_state_pkt_t;

/* Relay command packet */
typedef struct {
    mesh_hdr_t hdr;
    uint8_t    dst_uid[4];  /* target master */
    char       switch_id[16];
    uint8_t    channel;
    bool       state;
    uint8_t    req_id;      /* for matching ACK */
} __attribute__((packed)) mesh_relay_cmd_t;

/* Relay ACK packet */
typedef struct {
    mesh_hdr_t hdr;
    uint8_t    req_id;
    bool       success;
} __attribute__((packed)) mesh_relay_ack_t;

/* Join request packet */
typedef struct {
    mesh_hdr_t hdr;
    uint8_t    pin[6];      /* 6-digit PIN as bytes */
} __attribute__((packed)) mesh_join_req_t;

/* Join ACK packet */
typedef struct {
    mesh_hdr_t hdr;
    uint8_t    mesh_id[16]; /* shared mesh secret */
} __attribute__((packed)) mesh_join_ack_t;

typedef struct {
    uint8_t     address;
    uint8_t     uid[4];
    char        name[24];
    ext_state_t state;
    bool        relay1;
    bool        relay2;
    uint8_t     missed;
    uint32_t    last_seen_ms;
    /* Presence debounce. Zero means "never dropped" -- a freshly adopted
     * board appears on the dashboard at once; only a *return* has to serve
     * the settle window. */
    uint32_t    settle_until_ms;
    uint32_t    last_drop_ms;
    uint8_t     drops;               /* drops inside PRESENCE_FLAP_MS */
    uint32_t    last_relay1_cmd_ms;  /* rate limiting */
    uint32_t    last_relay2_cmd_ms;
    bool        polled_once;         /* for boot overlay */
    uint8_t     hw_type;             /* 0 = not learned yet, 0xFF = unprovisioned */
    uint8_t     hw_rev;
    uint8_t     fw_ver[3];           /* major, minor, patch */
    uint8_t     ota_fails;           /* consecutive failed update attempts */
    uint8_t     ota_fail_ver[3];     /* which version those failures were for */
    uint32_t    ota_next_try_ms;     /* backoff gate */
} extension_t;

/* ---- Presence ---------------------------------------------------------
 * One rule, applied to extensions and to mesh peers alike. Callers pass the
 * raw liveness flag plus the debounce fields; the result is what apps see.
 *
 *   down  + flapping recently  -> intermittent (diagnostic, not a plain outage)
 *   down                       -> offline
 *   up    + inside settle win  -> intermittent (back, but not trusted yet)
 *   up                         -> online
 *
 * Millis comparisons are signed differences so a 49-day rollover can't strand
 * a board in the wrong state. */
static presence_t presence_of(bool up, uint32_t settle_until_ms,
                              uint32_t last_drop_ms, uint8_t drops,
                              uint32_t now) {
    if (!up) {
        bool recent = last_drop_ms && (now - last_drop_ms) < PRESENCE_FLAP_MS;
        return (drops >= 2 && recent) ? PRES_INTERMITTENT : PRES_OFFLINE;
    }
    if (settle_until_ms && (int32_t)(now - settle_until_ms) < 0)
        return PRES_INTERMITTENT;
    return PRES_ONLINE;
}

/* Bookkeeping for a transition, shared by both presence users. `up` is the
 * new liveness. Returns nothing; the caller owns the mutex. */
static void presence_note_drop(uint32_t *settle_until_ms,
                               uint32_t *last_drop_ms, uint8_t *drops,
                               uint32_t now) {
    if (*last_drop_ms && (now - *last_drop_ms) >= PRESENCE_FLAP_MS) *drops = 0;
    if (*drops < 255) (*drops)++;
    *last_drop_ms = now ? now : 1;
    *settle_until_ms = 0;
}

/* `last_drop_ms` of 0 means this thing has no history of leaving -- a
 * first-ever appearance (fresh adoption, a master joining the mesh). Those
 * show up immediately; the settle window exists for a *return*. */
static void presence_note_return(uint32_t *settle_until_ms,
                                 uint32_t last_drop_ms, uint32_t now) {
    if (!last_drop_ms) { *settle_until_ms = 0; return; }
    uint32_t until = now + PRESENCE_SETTLE_MS;
    *settle_until_ms = until ? until : 1;   /* 0 is reserved for "settled" */
}

/* Called on every successful check-in: retires the settle window once it has
 * elapsed, and forgets an old flap run. */
static void presence_tick_up(uint32_t *settle_until_ms,
                             uint32_t *last_drop_ms, uint8_t *drops,
                             uint32_t now) {
    if (*settle_until_ms && (int32_t)(now - *settle_until_ms) >= 0)
        *settle_until_ms = 0;
    if (*last_drop_ms && (now - *last_drop_ms) >= PRESENCE_FLAP_MS) {
        *last_drop_ms = 0;
        *drops = 0;
    }
}

/* Seconds since this thing was last heard from. 0 while it is being heard
 * from right now, and 0 during a post-welcome grace window (last_seen_ms is
 * parked in the future there). */
static uint32_t seconds_since(uint32_t last_seen_ms, uint32_t now) {
    if (last_seen_ms == 0) return 0;
    if ((int32_t)(now - last_seen_ms) < 0) return 0;
    return (now - last_seen_ms) / 1000UL;
}

static presence_t ext_presence(const extension_t *e, uint32_t now) {
    if (e->state == EXT_EMPTY) return PRES_OFFLINE;
    return presence_of(e->state == EXT_ONLINE, e->settle_until_ms,
                       e->last_drop_ms, e->drops, now);
}

static presence_t peer_presence(const mesh_peer_t *p, uint32_t now) {
    return presence_of(p->online, p->settle_until_ms,
                       p->last_drop_ms, p->drops, now);
}

/* One of this master's switches, as gossip puts it on the air. Declared up
 * here with the other types rather than beside mesh_gossip: Arduino
 * generates prototypes for every function in the sketch and injects them
 * ahead of the first function definition, so any type named in a signature
 * has to exist by then. See the forward-declaration block below. */
#define MESH_MTU        242   /* 250 minus the auth tag mesh_send appends */
#define GOSSIP_SW_MAX   2     /* switches per window packet */
#define MAX_LOCAL_SW    (2 + 2 * MAX_EXTENSIONS)

typedef struct {
    char    id[16];
    char    name[24];
    uint8_t slot_color;   /* index into SLOT_COLORS */
    bool    state;
    bool    online;
    bool    restore;
    uint8_t ch;
} local_sw_t;

/* Pending challenge tracking */
#define MAX_CHALLENGES 5
typedef struct {
    uint8_t  uid[4];
    uint8_t  nonce[8];
    uint32_t sent_ms;
    bool     active;
} pending_challenge_t;

/* Pending (unregistered) extensions queue */
#define MAX_PENDING 5
typedef struct {
    uint8_t  uid[4];
    uint32_t first_seen_ms;
    bool     active;
} pending_ext_t;

typedef struct {
    int     target;   /* -1=master, 0-4=extension slot */
    uint8_t channel;
    bool    state;
} relay_cmd_t;

typedef struct {
    uint8_t uid[4];
    uint8_t addr;
    bool    relay1;
    bool    relay2;
} welcome_cmd_t;

/* ================================================================
 * SHARED STATE
 * ================================================================ */
static extension_t  extensions[MAX_EXTENSIONS];
static pending_ext_t pending_queue[MAX_PENDING];
static bool         master_relay1 = false;
static bool         master_relay2 = false;
static uint32_t     last_relay1_cmd_ms = 0;
static uint32_t     last_relay2_cmd_ms = 0;
static bool         boot_complete  = false;  /* boot overlay flag */
static bool              scan_active    = false;
static uint32_t          scan_end_ms    = 0;
static pending_challenge_t challenges[MAX_CHALLENGES];
static char         master_name[24] = "Master 1";
static String       switch_order   = "";  /* comma-separated switch IDs */
static bool         ota_in_progress = false;
static int          ota_progress    = 0;
static String       ota_status      = "";

/* ================================================================
 * FIRMWARE LIBRARY
 * Each master keeps the newest image it has seen for every extension
 * type on LittleFS plus a manifest describing them, then reconciles its
 * extensions toward that manifest at its own pace. A unit plugged in
 * months later converges on the next pass with no operator action.
 * ================================================================ */
#define FW_DESC_MAGIC     "UNISYNC1"
#define FW_MANIFEST_PATH  "/fw/manifest.json"
#define FW_MAX_TYPES      8
#define FW_MAX_IMAGE      (12 * 1024)
#define RECONCILE_MS      30000UL
#define OTA_MAX_FAILS     3
#define OTA_BACKOFF_MS    120000UL

typedef struct {
    uint8_t  type;
    uint8_t  ver[3];
    uint32_t size;
    uint32_t crc;
    uint8_t  secver;
    uint8_t  sig[32];      /* HMAC-SHA256 over the image */
} fw_entry_t;

/* ---- master firmware convergence ----
 * Every master advertises its version. A master running an older build
 * pulls the image straight off the highest-versioned peer over HTTP and
 * applies it. 1.1 MB is far too large for ESP-NOW, but the peer is already
 * an access point on our channel, so a plain HTTP GET moves it reliably
 * and resumably. Runs forever until the whole mesh agrees. */
#define MASTER_SYNC_MS      60000UL
#define MASTER_PULL_BACKOFF 300000UL
#define MASTER_PULL_JITTER  20000UL
#define MASTER_PEER_COOLDOWN 600000UL  /* per-source penalty after a failure */

static bool     master_pull_active = false;   /* this node is downloading  */
static bool     master_serve_busy  = false;   /* this node is uploading    */
static uint32_t master_pull_gate   = 0;       /* backoff after a failure   */
static uint8_t  master_fw[3]       = {0,0,0}; /* our own version, parsed   */

/* ================================================================
 * ACCESS CONTROL
 * Until now every endpoint was open: anyone who joined the WiFi could
 * switch relays, unpair switches or push firmware. Sessions are held in
 * RAM only, so a reboot logs everyone out, which is the safe default.
 * ================================================================ */
/* ONE CREDENTIAL PER MODE
 * Standalone: the password printed on the label joins the Wi-Fi AND logs
 * in to the API -- they are the same string, so there is nothing to claim
 * and no second secret to manage.
 * In a mesh: the mesh password replaces it entirely for both jobs.
 *
 * The password is stored in clear because SoftAP needs the literal
 * string; hashing it separately would protect nothing. Comparison is
 * still constant time. */
#define AUTH_TOKEN_LEN     33          /* 32 hex chars + NUL */
#define PASS_MIN_LEN       8
#define AP_APPLY_DELAY_MS  400         /* let the HTTP reply drain first */
#define AUTH_MAX_FAILS     5
#define AUTH_LOCKOUT_MS    300000UL    /* 5 min after 5 bad passwords */
#define RATE_WINDOW_MS     10000UL
#define RATE_MAX_REQS      40          /* per client per window */

static uint8_t        auth_fails      = 0;
static uint32_t       auth_lock_until = 0;

/* BLE RECOVERY
 * A master has no USB and no debug header in production, and its own
 * Wi-Fi password is the thing being recovered -- so recovery cannot go
 * over Wi-Fi. BLE is the only channel that survives a lost credential.
 *
 * The recovery key never crosses the air. The phone proves it knows the
 * key by answering a challenge; only then is a new password issued. */
#define BLE_SVC_UUID   "556e6973-796e-6320-5265-636f76657231"
#define BLE_CHAL_UUID  "556e6973-796e-6320-5265-636f76657232"
#define BLE_RESP_UUID  "556e6973-796e-6320-5265-636f76657233"
#define BLE_RESULT_UUID "556e6973-796e-6320-5265-636f76657234"
/* Control transport. BLE is the second way in: when the phone has no
 * cellular and needs the home Wi-Fi for internet, it can still reach the
 * nearest master over BLE instead of leaving that network. Control and
 * state only -- firmware upload stays on Wi-Fi, where the throughput is. */
#define BLE_REQ_UUID   "556e6973-796e-6320-5265-636f76657235"
#define BLE_RSP_UUID   "556e6973-796e-6320-5265-636f76657236"
#define BLE_STATE_UUID "556e6973-796e-6320-5265-636f76657237"
#define BLE_SNONCE_UUID "556e6973-796e-6320-5265-636f76657238"
#define BLE_CHUNK      160          /* fits the default MTU with headroom */
#define BLE_REQ_MAX    512
#define BLE_STATE_MIN_MS 150   /* floor between state pushes, deferred not dropped */

/* A BLE connection is a scarce resource: NimBLE stops advertising while
 * one is open, so a client that connects and never leaves makes the
 * master invisible to everyone, the owner included, without needing any
 * credential. Three defences: keep advertising, drop clients that never
 * authenticate, and drop authenticated clients that go idle. */
#define BLE_MAX_CONN      3
#define BLE_AUTH_GRACE_MS 15000UL     /* prove yourself within 15 s */
#define BLE_MAX_UNAUTH    1           /* only one unproven client at a time */

/* Manufacturer data in the advertisement, so the app can find masters
 * without knowing their UIDs in advance and can tell which mesh each one
 * belongs to before connecting.
 *   [0..1] company id, little endian
 *   [2]    format version
 *   [3..4] mesh id, 0000 when standalone
 *   [5]    flags: bit0 in a mesh, bit1 provisioned, bit2 client connected
 * 0xFFFF is the reserved "not assigned" company id. Replace it if Unisync
 * registers one with the Bluetooth SIG. */
#define BLE_COMPANY_ID 0xFFFF
#define BLE_MFG_VER    0x01
/* Recovery backoff: two seconds, doubling per rejection, capped. The
 * schedule lives here rather than in the app, and every rejection carries
 * the remaining wait so the app only renders a countdown it was given. */
#define REC_BACKOFF_BASE_S 2
#define REC_BACKOFF_MAX_S  300

static NimBLECharacteristic *ble_chal_char   = nullptr;
static NimBLECharacteristic *ble_result_char = nullptr;
static uint8_t  ble_nonce[8]      = {0};
/* Rejection count and the moment the next attempt is allowed. Synchronised
 * across the mesh, because the story requires one recovery gate for the
 * whole home -- hopping to another master must continue the same countdown
 * rather than resetting it. */
static uint8_t  rec_fails         = 0;
static uint32_t rec_next_ms       = 0;
static bool     ble_recover_ready = false;   /* apply from task_web */
static char     ble_new_pass[64]  = {0};
static NimBLECharacteristic *ble_rsp_char   = nullptr;
static NimBLECharacteristic *ble_state_char = nullptr;
static char     ble_req_buf[BLE_REQ_MAX];
static uint16_t ble_req_len     = 0;
static bool     ble_req_ready   = false;
typedef struct {
    uint16_t handle;
    bool     used;
    bool     authed;
    uint32_t opened_ms;
    uint32_t last_ms;
    uint32_t last_counter;   /* replay guard: must strictly increase */
    uint8_t  snonce[8];      /* this connection's session nonce */
} ble_conn_t;
static ble_conn_t   ble_conns[BLE_MAX_CONN];
static uint8_t      ble_conn_count = 0;
static NimBLEServer *ble_server    = nullptr;
static uint16_t     ble_req_handle = 0xFFFF;
static NimBLECharacteristic *ble_snonce_char = nullptr;
static uint8_t      ble_snonce[8] = {0};
static bool     ble_connected   = false;

/* Deferred credential change: reply first, then restart the AP, so the
 * caller learns the outcome instead of inferring it from a dropped
 * connection. */
static bool     ap_change_pending = false;
static uint32_t ap_change_at_ms   = 0;

typedef struct {
    uint32_t ip;
    uint32_t window_start;
    uint16_t count;
} rate_bucket_t;
static rate_bucket_t rate_buckets[8];


/* Root key for bus authentication. Each extension is provisioned with
 * HMAC(root_key, its uid), so the master derives any device's key from
 * its UID and needs no key database. Extracting one extension exposes
 * only that extension. */
/* Written once at first boot and never regenerated. These are the values
 * printed on the card in the box, so the card stays true for the life of
 * the device -- a factory reset or a BLE recovery returns to them rather
 * than inventing something the customer has no record of. */
static char     factory_pass[64]   = {0};
static uint8_t  recovery_key[16]   = {0};
static bool     factory_set        = false;

static char     device_pass[64] = {0};   /* standalone credential, in use now */
static char     unique_ssid[32] = {0};   /* standalone SSID, kept for AP restarts */
/* Mesh-scoped keys, created with the mesh and carried to joiners inside
 * the PIN-wrapped join payload. mesh_auth_key stays fixed for the life of
 * the mesh (it is the mesh's identity); the session key is derived from
 * the mesh password, so changing the password revokes every token. */
static uint8_t  mesh_auth_key[16] = {0};
static bool     mesh_auth_set     = false;
static uint32_t cred_version      = 0;
static char     mesh_join_pin[7]  = {0};  /* PIN we are joining with */
static bool     cred_stale        = false;  /* we missed a change, re-add me */
static volatile bool kick_acked   = false;  /* target confirmed deletion */

static uint8_t  root_key[16] = {0};
static bool     root_key_set = false;
static uint8_t  fw_key[16]   = {0};
static bool     fw_key_set   = false;

static bool     upload_authed  = false;   /* set at UPLOAD_FILE_START */
static void     pin_wrap(const char *pin, const uint8_t *uid4,
                         const uint8_t *nonce8, uint8_t *buf, uint16_t n);
static void     ble_new_session_nonce(void);
static bool     ble_proof_ok(JsonDocument &req);
static void     ble_notify_chunked(NimBLECharacteristic *ch, const String &s);
static void     ble_handle_request(const char *json);
static bool     ble_set_relay_by_id(const char *id, bool st);
static void     ble_killall(void);
static uint16_t ble_mesh_id(void);
static void     ble_update_adv_data(void);
static void     ble_reap_connections(void);
static void     factory_reset(void);
static void     reset_button_tick(void);
static void     ble_recovery_begin(void);
static void     ble_recovery_apply(void);
static void     mesh_broadcast_pass_change(void);
static bool     mesh_send(const uint8_t *mac, const void *data, size_t len);
static void     mesh_broadcast(const void *data, size_t len);
static int      mesh_verify(const uint8_t *data, int len);
static bool     fs_ready       = false;
static uint32_t last_reconcile = 0;

/* ---- mesh firmware distribution: binary channel, not JSON ----
 * JSON packets always begin with '{' (0x7B), so a 0xFB first byte is an
 * unambiguous discriminator and the existing JSON path is untouched. */
#define FWPKT_MAGIC     0xFB
#define FWPKT_OFFER     0x01
#define FWPKT_REQ       0x02
#define FWPKT_CHUNK     0x03
#define FWPKT_DONE      0x04
#define FWPKT_HDR       49   /* 16 + secver + 32-byte signature */
#define FWPKT_DATA      184          /* 49 + 184 + 8 tag = 241, under 250 */
#define FWRX_TIMEOUT_MS 800

static bool     fwrx_active  = false;
static uint8_t  fwrx_type    = 0;
static uint8_t  fwrx_ver[3]  = {0,0,0};
static uint32_t fwrx_size    = 0;
static uint32_t fwrx_crc     = 0;
static uint16_t fwrx_total   = 0;
static uint16_t fwrx_next    = 0;
static uint8_t *fwrx_buf     = nullptr;
static uint8_t  fwrx_src[6]  = {0};
static uint8_t  fwrx_sec     = 0;
static uint8_t  fwrx_sig[32] = {0};
static uint32_t fwrx_last_ms = 0;

/* Forward declarations. The firmware-library and mesh-distribution
 * routines are defined near the bottom but referenced from the ESP-NOW
 * callback and the bus task far above; Arduino's auto-prototype pass is
 * not reliable enough to depend on here. */
static void     ext_reset_identity(extension_t *e);
/* Presence and gossip. Both name types defined above but *below* the first
 * function definition in the sketch, so without these the auto-generated
 * prototypes land before the typedefs and fail to parse. */
static const char *presence_str(presence_t p);
static presence_t presence_of(bool up, uint32_t settle_until_ms,
                              uint32_t last_drop_ms, uint8_t drops,
                              uint32_t now);
static presence_t ext_presence(const extension_t *e, uint32_t now);
static presence_t peer_presence(const mesh_peer_t *p, uint32_t now);
static uint8_t  gossip_collect(local_sw_t *out);
static void     gossip_add_switch(JsonArray arr, const local_sw_t *s);
static void     gossip_emit(JsonDocument &doc, const char *what);
static bool     switch_id_valid(const String &id);
static void     nvs_load_switch_name(const char *id, char *name, int nlen);
static void     relay_state_save(void);
static void     relay_state_save_now(void);
static bool     nvs_load_restore(const char *id);
static void     nvs_save_restore(const char *id, bool restore);
static void     master_ver_parse(const char *s, uint8_t *v);
static void     task_fwsync(void *arg);
static void     hmac_sha256(const uint8_t *key, const uint8_t *msg,
                            uint32_t mlen, uint8_t *out32);
static bool     ct_equal(const uint8_t *a, const uint8_t *b, uint8_t n);
static void     sha256_hex(const char *in, const char *salt, char *out65);
static void     rand_hex(char *out, int hex_chars);
static bool     safe_equal(const char *a, const char *b, size_t n);
static bool     rate_ok(void);
static const char *active_pass(void);
static void     session_key(uint8_t *out16);
static void     make_token(char *out);
static bool     token_valid(const String &tok);
static bool     auth_valid(void);
static bool     auth_ok(void);
static uint32_t master_image_size(void);
static void     master_fw_sync(void);
static uint32_t fw_crc32(const uint8_t *d, uint32_t n);
static bool     fw_ver_newer(const uint8_t *a, const uint8_t *b);
static bool     fw_parse_desc(const uint8_t *img, uint32_t len,
                              uint8_t *type, uint8_t *ver);
static bool     fw_lookup(uint8_t type, fw_entry_t *out);
static bool     fw_store(uint8_t type, const uint8_t *ver,
                         const uint8_t *img, uint32_t len,
                         uint8_t secver, const uint8_t *sig);
static uint32_t fw_load(uint8_t type, uint8_t *buf, uint32_t max);
static void     fw_reconcile(void);
static void     fw_mesh_offer(uint8_t type, const uint8_t *ver,
                              uint32_t size, uint32_t crc,
                              uint8_t secver, const uint8_t *sig);
static void     fw_mesh_rx(const uint8_t *src, const uint8_t *d, int len);
static void     fw_mesh_tick(void);
static bool     ext_ota_send(uint8_t addr, const uint8_t *fw, uint32_t fw_len,
                             uint8_t type, const uint8_t *ver,
                             uint8_t secver, const uint8_t *sig);

/* Extension OTA -- buffer entire firmware in heap before sending */
#define EXT_OTA_CHUNK_SIZE   32
#define EXT_OTA_MAX_SIZE     (12 * 1024)
static uint8_t     *ext_ota_buf     = nullptr;
static uint32_t     ext_ota_total   = 0;
static uint8_t      ext_ota_addr    = 0;

/* Mesh state */
static mesh_peer_t  mesh_peers[MAX_MESH_MASTERS];
static uint8_t      mesh_id[16]    = {0};  /* shared mesh secret */
static volatile bool mesh_active   = false; /* read from multiple tasks */
static uint8_t      mesh_seq       = 0;
static uint32_t     last_gossip_ms = 0;
static char         mesh_name[32]  = "Unisync"; /* mesh SSID name - write protected by single-writer pattern */
static char         mesh_pass[64]  = "12345678"; /* mesh WiFi password */
/* Master display order -- UID strings comma-separated, mesh-wide shared */
static char         master_order_str[MAX_MESH_MASTERS * 10] = {0};
/* Deferred softAP reconfiguration -- set from ESP-NOW callback, applied in loop() */
static volatile bool mesh_cfg_pending      = false;
static char          mesh_cfg_pending_name[32] = {0};
static char          mesh_cfg_pending_pass[64] = {0};

/* Mesh PIN (for inviting new masters) */
static char         mesh_pin[7]    = {0};  /* 6 digits + null */
static uint32_t     mesh_pin_ms    = 0;    /* when PIN was generated */
static bool         mesh_pin_valid = false;

/* Pending relay ACK tracking */

/* Master UID (from ESP32 MAC) */
static uint8_t master_uid[4] = {0};

static SemaphoreHandle_t state_mutex;
static QueueHandle_t     master_relay_queue;
static QueueHandle_t     ext_relay_queue;
static QueueHandle_t     ws_notify_queue;
static QueueHandle_t     welcome_queue;

/* ================================================================
 * OBJECTS
 * ================================================================ */
static HardwareSerial   BusSerial(1);
static WebServer        server(80);
static WebSocketsServer wss(81);
static Preferences      prefs;

/* ================================================================
 * CRC-8
 * ================================================================ */
static uint8_t crc8(const uint8_t *d, uint8_t len) {
    uint8_t crc = 0;
    while (len--) {
        crc ^= *d++;
        for (int i=0; i<8; i++)
            crc = (crc & 0x80) ? (crc<<1)^0x07 : crc<<1;
    }
    return crc;
}

static uint32_t crc32_compute(const uint8_t *data, uint8_t len) {
    uint32_t crc = 0xFFFFFFFF;
    while (len--) {
        crc ^= *data++;
        for (int i=0; i<8; i++)
            crc = (crc & 1) ? (crc>>1)^0xEDB88320 : crc>>1;
    }
    return crc ^ 0xFFFFFFFF;
}


/* ================================================================
 * RS-485
 * ================================================================ */
static void bus_send(uint8_t dst, uint8_t cmd,
                     const uint8_t *payload, uint8_t len) {
    uint8_t frame[56];
    frame[0]=SOF; frame[1]=dst; frame[2]=ADDR_MASTER;
    frame[3]=cmd; frame[4]=len;
    for (int i=0; i<len; i++) frame[5+i]=payload[i];
    frame[5+len]=crc8(&frame[1], 4+len);
    digitalWrite(RS485_DE_PIN, HIGH);
    BusSerial.write(frame, 6+len);
    BusSerial.flush();
    digitalWrite(RS485_DE_PIN, LOW);
}

static uint8_t bus_recv(uint8_t *buf, uint8_t max_len,
                        uint32_t timeout_ms) {
    uint32_t start=millis(); uint8_t pos=0, elen=0;
    while ((millis()-start)<timeout_ms) {
        if (BusSerial.available()) {
            uint8_t b=BusSerial.read();
            if (pos==0) { if (b==SOF) buf[pos++]=b; }
            else {
                if (pos>=max_len) return 0;
                buf[pos++]=b;
                if (pos==5) elen=6+buf[4];
                if (elen>0&&pos>=elen) return pos;
            }
        } else { vTaskDelay(pdMS_TO_TICKS(1)); }
    }
    return 0;
}

static void flush_rx(void) {
    while (BusSerial.available()) BusSerial.read();
    vTaskDelay(pdMS_TO_TICKS(2));
}

/* ================================================================
 * NOTIFY UI
 * ================================================================ */
static void notify_ui(void) {
    uint8_t sig=1;
    xQueueSend(ws_notify_queue, &sig, 0);
}

/* ================================================================
 * MESH CORE
 * ================================================================ */

/* Find or create peer slot by UID */
static int mesh_find_peer(const uint8_t *uid) {
    /* An empty slot holds uid 00000000, so a sender claiming that UID
     * would match one and be treated as enrolled. Skip empty slots. */
    if (!uid[0] && !uid[1] && !uid[2] && !uid[3]) return -1;
    for (int i=0; i<MAX_MESH_MASTERS; i++) {
        if (mesh_peers[i].last_seen_ms == 0 &&
            !mesh_peers[i].uid[0] && !mesh_peers[i].uid[1] &&
            !mesh_peers[i].uid[2] && !mesh_peers[i].uid[3]) continue;
        if (memcmp(mesh_peers[i].uid, uid, 4)==0) return i;
    }
    return -1;
}

static int mesh_alloc_peer(const uint8_t *uid, const uint8_t *mac) {
    /* Find existing */
    int idx = mesh_find_peer(uid);
    if (idx >= 0) return idx;
    /* Find empty slot */
    for (int i=0; i<MAX_MESH_MASTERS; i++) {
        if (mesh_peers[i].last_seen_ms==0 &&
            memcmp(mesh_peers[i].uid, "    ", 4)==0) {
            memcpy(mesh_peers[i].uid, uid, 4);
            memcpy(mesh_peers[i].mac, mac, 6);
            return i;
        }
    }
    /* Table full: reclaim whichever peer has been offline longest. Slots
     * were previously held for ever -- a peer that was decommissioned kept
     * its entry, and a neighbour we genuinely needed as an update source
     * could never be admitted. */
    int      victim = -1;
    uint32_t oldest = 0;
    for (int i=0; i<MAX_MESH_MASTERS; i++) {
        if (mesh_peers[i].online) continue;
        uint32_t age = millis() - mesh_peers[i].last_seen_ms;
        if (age >= oldest) { oldest = age; victim = i; }
    }
    if (victim >= 0) {
        Serial.printf("[MESH] table full, reclaiming slot %d (%s, offline %us)\n",
                      victim, mesh_peers[victim].name, oldest/1000);
        memset(&mesh_peers[victim], 0, sizeof(mesh_peer_t));
        memcpy(mesh_peers[victim].uid, uid, 4);
        memcpy(mesh_peers[victim].mac, mac, 6);
        return victim;
    }
    return -1; /* every slot is an online peer */
}

/* Send ESP-NOW packet to a peer MAC */
/* Every mesh packet carries an 8-byte tag over its body.
 *
 * ESP-NOW's own encryption cannot be used here: encrypted peers are
 * capped well below MAX_MESH_MASTERS, and broadcast -- which is exactly
 * where join and discovery live -- cannot be encrypted at all. Tagging at
 * the application layer has no peer cap and covers broadcast.
 *
 * Before a mesh exists there is no key, so packets go out untagged and a
 * receiver with no key accepts them. That is only the pre-join state. */
#define MESH_TAG_LEN 8

/* The join payload carries the credential that controls the whole house,
 * over an unencrypted broadcast medium. Wrap it with a key derived from
 * the PIN, which is already out of band, single use and rate limited.
 * Same routine both directions -- XOR keystream is its own inverse. */
static void pin_wrap(const char *pin, const uint8_t *uid4,
                     const uint8_t *nonce8, uint8_t *buf, uint16_t n) {
    uint8_t seed[12], key[32], ks[32];
    memcpy(seed, uid4, 4);
    memcpy(seed + 4, nonce8, 8);
    /* hmac_sha256 always reads sixteen key bytes. mesh_pin is a seven-byte
     * buffer, so passing it straight in read nine bytes of whatever globals
     * followed it -- deterministic within one build, and different in the
     * next, which would have made a join between two firmware versions fail
     * in a way nobody could explain. Pad explicitly instead. */
    uint8_t pk[16] = {0};
    for (int i = 0; i < 16 && pin[i]; i++) pk[i] = (uint8_t)pin[i];
    hmac_sha256(pk, seed, sizeof(seed), key);
    for (uint16_t off = 0; off < n; off += 32) {
        uint8_t ctr[36];
        memcpy(ctr, key, 32);
        ctr[32]=(off>>24)&0xFF; ctr[33]=(off>>16)&0xFF;
        ctr[34]=(off>>8)&0xFF;  ctr[35]=off&0xFF;
        hmac_sha256(key, ctr, sizeof(ctr), ks);
        for (uint16_t k = 0; k < 32 && off + k < n; k++)
            buf[off + k] ^= ks[k];
    }
}

/* Push the current mesh password and name to every peer. The packet is
 * tagged with mesh_auth_key, which peers still hold, so a member can
 * change the password without needing the old one -- that is what makes
 * recovery possible without walking to every switch. */
static void mesh_broadcast_pass_change(void) {
    if (!mesh_active) return;
    StaticJsonDocument<256> doc;
    char self_uid[12];
    snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
             master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
    doc["type"] = MESH_PKT_PASS_CHG;
    doc["uid"]  = self_uid;
    doc["pass"] = mesh_pass;
    doc["name"] = mesh_name;
    doc["cv"]   = cred_version;
    String payload; serializeJson(doc,payload);
    mesh_broadcast(payload.c_str(), payload.length()+1);
    Serial.println("[MESH] password change broadcast to peers");
}

static bool mesh_send(const uint8_t *mac, const void *data, size_t len) {
    if (!mesh_active) return false;
    if (!mesh_auth_set) {
        /* Before a mesh exists there is no key to tag with; the join
         * exchange is authenticated by the PIN instead. */
        esp_err_t r0 = esp_now_send(mac, (const uint8_t*)data, len);
        return (r0 == ESP_OK);
    }
    if (len + MESH_TAG_LEN > 250) {
        /* Sending it untagged would be worse than not sending it: the peer
         * drops untagged packets, so the caller would believe it succeeded
         * while nothing arrived. Say so instead. */
        Serial.printf("[MESH] packet %u bytes exceeds the ESP-NOW limit, not sent\n",
                      (unsigned)len);
        return false;
    }
    uint8_t buf[250];
    memcpy(buf, data, len);
    uint8_t mac32[32];
    hmac_sha256(mesh_auth_key, (const uint8_t*)data, len, mac32);
    memcpy(buf + len, mac32, MESH_TAG_LEN);
    esp_err_t r = esp_now_send(mac, buf, len + MESH_TAG_LEN);
    return (r == ESP_OK);
}

/* Strip and check the tag. Returns the body length, or -1 to drop. */
static int mesh_verify(const uint8_t *data, int len) {
    if (!mesh_auth_set) return len;          /* no mesh yet */
    if (len <= MESH_TAG_LEN) return -1;
    int body = len - MESH_TAG_LEN;
    uint8_t mac32[32];
    hmac_sha256(mesh_auth_key, data, body, mac32);
    if (!ct_equal(mac32, data + body, MESH_TAG_LEN)) return -1;
    return body;
}

/* Broadcast to all known mesh peers.
 *
 * Through mesh_send, so the packet carries the auth tag. It used to call
 * esp_now_send directly and therefore went out untagged -- and mesh_recv_cb
 * drops every untagged packet that is not a join, so gossip, config relays,
 * password changes and kicks were all thrown away by their recipients. */
static void mesh_broadcast(const void *data, size_t len) {
    if (!mesh_active) return;
    uint8_t broadcast_mac[6] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
    mesh_send(broadcast_mac, data, len);
}

/* ---- Gossip ------------------------------------------------------------
 * ESP-NOW carries at most 250 bytes, and mesh_send spends 8 of them on the
 * auth tag. A master's full switch list does not come close to fitting: even
 * a bare two-channel master with no extensions serialised to well over 250,
 * so esp_now_send rejected every gossip packet outright and no peer ever saw
 * another peer's switches.
 *
 * State is therefore gossiped incrementally, in packets that fit:
 *
 *   header  {"type":1,"uid":..,"nm":..,"fw":..,"cv":..,"t":<count>}
 *   window  {"type":1,"uid":..,"t":<count>,"sw":[ up to two switches ]}
 *
 * Receivers merge switch entries by id, so windows may arrive in any order
 * and a lost packet costs one round rather than a corrupted list. Changed
 * switches jump the queue: a wall touch propagates on the next tick instead
 * of waiting for the sweep to come round. The periodic sweep continues
 * underneath so a master that joins or reboots converges on its own.
 *
 * Keys inside "sw" are one character because the budget is genuinely that
 * tight -- a 23-character switch name is 29 bytes of the ~95 an entry costs.
 */
/* What we last put on the air, so a change can be spotted without asking
 * every consumer to tell us. */
static bool     gossip_shadow_valid = false;
static uint8_t  gossip_shadow_count = 0;
static char     gossip_shadow_id[MAX_LOCAL_SW][16];
static bool     gossip_shadow_state[MAX_LOCAL_SW];
static bool     gossip_shadow_online[MAX_LOCAL_SW];
static uint8_t  gossip_cursor = 0;    /* 0 = header, then switch windows */

/* Snapshot this master's switches. Reads NVS, so it must not run with the
 * state mutex held; it takes and releases the mutex itself. */
static uint8_t gossip_collect(local_sw_t *out) {
    uint8_t n = 0;
    char sw_name[24];

    xSemaphoreTake(state_mutex, portMAX_DELAY);
    bool r1 = master_relay1, r2 = master_relay2;
    xSemaphoreGive(state_mutex);

    for (int ch = 1; ch <= 2; ch++) {
        local_sw_t *s = &out[n++];
        snprintf(s->id, sizeof(s->id), "master_%d", ch);
        nvs_load_switch_name(s->id, sw_name, sizeof(sw_name));
        if (!strcmp(sw_name, "Switch")) snprintf(sw_name, sizeof(sw_name), "Switch %d", ch);
        strncpy(s->name, sw_name, sizeof(s->name)-1); s->name[sizeof(s->name)-1] = 0;
        s->slot_color = 0;
        s->state   = (ch == 1) ? r1 : r2;
        s->online  = true;
        s->restore = nvs_load_restore(s->id);
        s->ch      = ch;
    }

    uint32_t now_ms = millis();
    for (int i = 0; i < MAX_EXTENSIONS; i++) {
        xSemaphoreTake(state_mutex, portMAX_DELAY);
        bool empty = (extensions[i].state == EXT_EMPTY);
        bool er1 = extensions[i].relay1, er2 = extensions[i].relay2;
        bool eon = (ext_presence(&extensions[i], now_ms) == PRES_ONLINE);
        xSemaphoreGive(state_mutex);
        if (empty) continue;
        for (int ch = 1; ch <= 2; ch++) {
            local_sw_t *s = &out[n++];
            snprintf(s->id, sizeof(s->id), "ext%d_%d", i, ch);
            nvs_load_switch_name(s->id, sw_name, sizeof(sw_name));
            if (!strcmp(sw_name, "Switch"))
                snprintf(sw_name, sizeof(sw_name), "Switch %d", ch + i*2 + 2);
            strncpy(s->name, sw_name, sizeof(s->name)-1); s->name[sizeof(s->name)-1] = 0;
            s->slot_color = (i + 1 < 6) ? (i + 1) : 5;
            s->state   = (ch == 1) ? er1 : er2;
            s->online  = eon;
            s->restore = nvs_load_restore(s->id);
            s->ch      = ch;
        }
    }
    return n;
}

/* Serialise and send one packet, dropping optional fields until it fits.
 * Silently oversized packets are what broke gossip in the first place, so
 * anything still too large after trimming is logged rather than dropped. */
static void gossip_emit(JsonDocument &doc, const char *what) {
    String payload;
    serializeJson(doc, payload);
    if (payload.length() + 1 > MESH_MTU && doc.containsKey("o")) {
        doc.remove("o");            /* master order re-broadcasts on change */
        payload = "";
        serializeJson(doc, payload);
    }
    if (payload.length() + 1 > MESH_MTU) {
        Serial.printf("[MESH] %s packet %u bytes, over the %u limit -- dropped\n",
                      what, (unsigned)payload.length()+1, (unsigned)MESH_MTU);
        return;
    }
    mesh_broadcast(payload.c_str(), payload.length()+1);
}

static void gossip_add_switch(JsonArray arr, const local_sw_t *s) {
    JsonObject o = arr.createNestedObject();
    o["d"] = s->id;
    o["n"] = s->name;
    o["c"] = SLOT_COLORS[s->slot_color];
    o["s"] = s->state;
    o["o"] = s->online;
    o["r"] = s->restore;
    o["h"] = s->ch;
}

/* Build and broadcast local state to all peers */
static void mesh_gossip(void) {
    if (!mesh_active) return;
    /* The radio is torn down during a firmware pull; transmitting into a
     * de-initialised ESP-NOW just logs "esp now not init!" every cycle. */
    if (master_pull_active) return;

    /* Static, not stack: mesh_gossip runs on task_bus, which has 4 KB. */
    static local_sw_t sw[MAX_LOCAL_SW];
    uint8_t n = gossip_collect(sw);

    char uid_str[12];
    snprintf(uid_str, sizeof(uid_str), "%02X%02X%02X%02X",
             master_uid[0], master_uid[1], master_uid[2], master_uid[3]);

    /* A changed switch list length invalidates the shadow wholesale: the
     * indices no longer line up, and peers need a fresh sweep anyway. */
    if (gossip_shadow_valid && gossip_shadow_count != n) gossip_shadow_valid = false;

    /* Anything that changed since the last packet goes out first. */
    int changed[MAX_LOCAL_SW]; int nchanged = 0;
    if (gossip_shadow_valid) {
        for (int i = 0; i < n && nchanged < GOSSIP_SW_MAX; i++) {
            if (strcmp(gossip_shadow_id[i], sw[i].id) != 0 ||
                gossip_shadow_state[i]  != sw[i].state ||
                gossip_shadow_online[i] != sw[i].online)
                changed[nchanged++] = i;
        }
    }

    if (nchanged > 0) {
        StaticJsonDocument<MESH_MTU + 64> doc;
        doc["type"] = MESH_PKT_STATE;
        doc["uid"]  = uid_str;
        doc["t"]    = n;
        JsonArray a = doc.createNestedArray("sw");
        for (int i = 0; i < nchanged; i++) {
            gossip_add_switch(a, &sw[changed[i]]);
            gossip_shadow_state[changed[i]]  = sw[changed[i]].state;
            gossip_shadow_online[changed[i]] = sw[changed[i]].online;
            strncpy(gossip_shadow_id[changed[i]], sw[changed[i]].id, 15);
            gossip_shadow_id[changed[i]][15] = 0;
        }
        gossip_emit(doc, "delta");
        return;
    }

    /* Otherwise advance the periodic sweep: header, then switch windows. */
    if (gossip_cursor == 0) {
        StaticJsonDocument<MESH_MTU + 64> doc;
        doc["type"] = MESH_PKT_STATE;
        doc["uid"]  = uid_str;
        doc["nm"]   = master_name;
        doc["fw"]   = MASTER_FW_VERSION;
        doc["cv"]   = cred_version;
        doc["t"]    = n;
        doc["o"]    = master_order_str;   /* dropped by gossip_emit if tight */
        gossip_emit(doc, "header");
        gossip_cursor = 1;
        return;
    }

    uint8_t first = (uint8_t)((gossip_cursor - 1) * GOSSIP_SW_MAX);
    if (first >= n) { gossip_cursor = 0; return; }

    StaticJsonDocument<MESH_MTU + 64> doc;
    doc["type"] = MESH_PKT_STATE;
    doc["uid"]  = uid_str;
    doc["t"]    = n;
    JsonArray a = doc.createNestedArray("sw");
    for (uint8_t i = first; i < n && i < first + GOSSIP_SW_MAX; i++) {
        gossip_add_switch(a, &sw[i]);
        gossip_shadow_state[i]  = sw[i].state;
        gossip_shadow_online[i] = sw[i].online;
        strncpy(gossip_shadow_id[i], sw[i].id, 15);
        gossip_shadow_id[i][15] = 0;
    }
    gossip_emit(doc, "window");

    gossip_cursor++;
    if ((uint8_t)((gossip_cursor - 1) * GOSSIP_SW_MAX) >= n) {
        /* Swept the whole list -- the shadow is now a complete picture. */
        gossip_shadow_count = n;
        gossip_shadow_valid = true;
        gossip_cursor = 0;
    }
}

/* Generate 6-digit mesh PIN */
static void mesh_generate_pin(void) {
    uint32_t r = esp_random();
    snprintf(mesh_pin, sizeof(mesh_pin), "%06u", r % 1000000);
    mesh_pin_ms    = millis();
    mesh_pin_valid = true;
    /* Not logged: the serial console is not a trusted channel and the PIN
     * is the only thing standing between an outsider and mesh membership. */
    Serial.println("[MESH] PIN generated (shown in the app only)");
}

/* Verify incoming PIN */
static bool mesh_verify_pin(const char *pin) {
    if (!mesh_pin_valid) return false;
    if ((millis()-mesh_pin_ms) > MESH_PIN_VALID_MS) {
        mesh_pin_valid = false;
        return false;
    }
    /* Six digits is a million values; without a limit that is minutes of
     * online guessing. Lock out after a handful of wrong attempts. */
    static uint8_t  pin_fails = 0;
    static uint32_t pin_lock  = 0;
    if (pin_lock && (int32_t)(millis() - pin_lock) < 0) return false;

    bool ok = safe_equal(pin, mesh_pin, 6);
    if (!ok) {
        if (++pin_fails >= AUTH_MAX_FAILS) {
            pin_lock  = millis() + AUTH_LOCKOUT_MS;
            pin_fails = 0;
            mesh_pin_valid = false;   /* burn it, force a fresh one */
            Serial.println("[MESH] too many bad PINs, invalidated");
        }
        return false;
    }
    pin_fails = 0;
    if (ok) mesh_pin_valid = false; /* consume PIN */
    return ok;
}

/* ESP-NOW receive callback */
static void mesh_recv_cb(const esp_now_recv_info_t *info,
                         const uint8_t *data, int len) {
    if (len < 2) return;
    /* Authenticate before parsing anything, so nothing downstream sees
     * attacker input.
     *
     * JOIN_REQ is the one exception, and it has to be: a master asking to
     * join has no mesh key yet -- the join is what delivers it -- so it
     * cannot possibly tag the request. That message is authenticated by
     * the PIN instead, which is out of band, single use and rate limited.
     * Everything else must carry a valid tag. */
    { int body = mesh_verify(data, len);
      if (body < 0) {
          bool is_join = false;
          if (data[0] == '{') {
              StaticJsonDocument<192> probe;
              if (deserializeJson(probe, data, len) == DeserializationError::Ok)
                  is_join = ((uint8_t)(probe["type"] | 0) == MESH_PKT_JOIN_REQ);
          }
          bool is_kick_ack = false;
          if (!is_join && data[0] == '{') {
              StaticJsonDocument<192> probe2;
              if (deserializeJson(probe2, data, len) == DeserializationError::Ok)
                  is_kick_ack = ((uint8_t)(probe2["type"] | 0) == MESH_PKT_KICK_ACK);
          }
          /* A master that has just deleted its credentials cannot tag its
           * acknowledgment. It carries no authority -- it only confirms a
           * removal we initiated. */
          if (!is_join && !is_kick_ack) return;
      } else {
          len = body;
      }
    }

    /* Binary firmware packets share the ESP-NOW channel with the JSON
     * protocol. JSON always starts with '{' (0x7B), so a 0xFB first byte
     * is unambiguous and the JSON path below is untouched. */
    if (data[0] == FWPKT_MAGIC) { fw_mesh_rx(info->src_addr, data, len); return; }

    /* Parse packet to get type */
    StaticJsonDocument<1024> doc;
    if (deserializeJson(doc, data, len) != DeserializationError::Ok) return;

    uint8_t type = doc["type"] | 0;

    /* When not in mesh, only allow JOIN_ACK and JOIN_REJ.
     * All other packets (gossip, relay, ping) are ignored.
     * JOIN_ACK is what transitions mesh_active from false to true. */
    if (!mesh_active &&
        type != MESH_PKT_JOIN_ACK &&
        type != MESH_PKT_JOIN_REJ) return;
    const char *uid_str = doc["uid"] | "";

    /* Parse sender UID */
    uint8_t src_uid[4] = {0};
    if (strlen(uid_str)==8) {
        src_uid[0]=strtoul(String(uid_str).substring(0,2).c_str(),NULL,16);
        src_uid[1]=strtoul(String(uid_str).substring(2,4).c_str(),NULL,16);
        src_uid[2]=strtoul(String(uid_str).substring(4,6).c_str(),NULL,16);
        src_uid[3]=strtoul(String(uid_str).substring(6,8).c_str(),NULL,16);
    }

    /* Ignore own packets */
    if (memcmp(src_uid, master_uid, 4)==0) return;

    if (type == MESH_PKT_STATE) {
        /* Only peers admitted through the PIN-authenticated join are
         * accepted. Previously any device that emitted one well-formed
         * state packet enrolled itself, which made the PIN decorative and
         * opened the firmware-distribution path to outsiders. */
        int idx = mesh_find_peer(src_uid);
        if (idx < 0) return;   /* unknown sender, ignore */

        /* Ensure this peer is registered as ESP-NOW peer with AP MAC.
         * Re-register on every gossip in case peer rebooted or was lost.
         * mesh_active checked at top of recv_cb so we never reach here if left. */
        if (master_pull_active) return;   /* ESP-NOW is down during a pull */
    if (!esp_now_is_peer_exist(info->src_addr)) {
            esp_now_peer_info_t gpi={};
            memcpy(gpi.peer_addr, info->src_addr, 6);
            gpi.channel=AP_CHANNEL; gpi.encrypt=false;
            gpi.ifidx=WIFI_IF_AP;
            esp_err_t padd = esp_now_add_peer(&gpi);
            Serial.printf("[MESH] Re-registered peer %02X%02X%02X%02X%02X%02X err=%d\n",
                info->src_addr[0],info->src_addr[1],info->src_addr[2],
                info->src_addr[3],info->src_addr[4],info->src_addr[5],padd);
        }

        xSemaphoreTake(state_mutex, portMAX_DELAY);
        if (!mesh_peers[idx].online)
            presence_note_return(&mesh_peers[idx].settle_until_ms,
                                 mesh_peers[idx].last_drop_ms, millis());
        mesh_peers[idx].online       = true;
        mesh_peers[idx].last_seen_ms = millis();
        /* If a peer reports a newer credential version we missed a change
         * while offline. Credentials are never sent outside the PIN-wrapped
         * join, so this cannot self-heal: flag it and let the user remove
         * and re-add this master. */
        { uint32_t pv = doc["cv"] | 0;
          if (pv > cred_version && !cred_stale) {
              cred_stale = true;
              Serial.println("[MESH] credentials out of date -- remove and re-add this master");
              notify_ui();
          } }
        /* ESP-NOW carries far further than a usable TCP association, so a
         * peer we can hear is not necessarily a peer we can download 1.1 MB
         * from. Keep the signal level and prefer close peers when pulling. */
        if (info->rx_ctrl) mesh_peers[idx].rssi = info->rx_ctrl->rssi;
        memcpy(mesh_peers[idx].mac, info->src_addr, 6);

        /* Gossip arrives in pieces (see mesh_gossip): a header packet with
         * the peer's identity, and window/delta packets carrying switches.
         * Only overwrite what a packet actually carries -- taking a default
         * for an absent key would blank the peer's name on every window. */
        if (doc.containsKey("nm")) {
            const char *pname = doc["nm"] | "Master";
            strncpy(mesh_peers[idx].name, pname, sizeof(mesh_peers[idx].name)-1);
            mesh_peers[idx].name[sizeof(mesh_peers[idx].name)-1] = 0;
        }
        if (doc.containsKey("fw"))
            master_ver_parse(doc["fw"] | "0.0.0", mesh_peers[idx].fw);
        /* Sync master_order from gossip if peer has a non-empty one */
        const char *peer_order = doc["o"] | "";
        if (strlen(peer_order) > strlen(master_order_str)) {
            /* Peer has more entries -- use theirs as it's more complete */
            strncpy(master_order_str, peer_order, sizeof(master_order_str)-1);
            mesh_nvs_save();
        }

        /* The peer's switch count. A change means its extension list moved,
         * so the merged list is rebuilt from the coming windows rather than
         * left holding entries for switches that no longer exist. */
        uint8_t total = (uint8_t)(doc["t"] | 0);
        if (total > 12) total = 12;
        if (total && mesh_peers[idx].switch_count > total)
            mesh_peers[idx].switch_count = 0;

        /* Merge by id, so windows may arrive in any order and a lost packet
         * costs one sweep rather than a scrambled list. */
        JsonArray sw = doc["sw"];
        for (JsonObject s : sw) {
            const char *sid = s["d"] | "";
            if (!sid[0]) continue;
            int j = -1;
            for (int k = 0; k < mesh_peers[idx].switch_count; k++)
                if (!strcmp(mesh_peers[idx].switches[k].id, sid)) { j = k; break; }
            if (j < 0) {
                if (mesh_peers[idx].switch_count >= 12) continue;
                j = mesh_peers[idx].switch_count++;
            }
            mesh_switch_t *ms = &mesh_peers[idx].switches[j];
            strncpy(ms->id,   sid,             sizeof(ms->id)-1);   ms->id[sizeof(ms->id)-1]=0;
            strncpy(ms->name, s["n"] | "",     sizeof(ms->name)-1); ms->name[sizeof(ms->name)-1]=0;
            strncpy(ms->color,s["c"] | "#444", sizeof(ms->color)-1);ms->color[sizeof(ms->color)-1]=0;
            ms->state   = s["s"] | false;
            ms->online  = s["o"] | false;
            ms->restore = s["r"] | false;
            ms->ch      = s["h"] | 1;
        }
        xSemaphoreGive(state_mutex);
        notify_ui();

    } else if (type == MESH_PKT_RELAY_CMD) {
        /* Relay command for one of OUR switches */
        const char *dst_uid_str = doc["dst_uid"] | "";
        uint8_t dst_uid[4]={0};
        if (strlen(dst_uid_str)==8) {
            dst_uid[0]=strtoul(String(dst_uid_str).substring(0,2).c_str(),NULL,16);
            dst_uid[1]=strtoul(String(dst_uid_str).substring(2,4).c_str(),NULL,16);
            dst_uid[2]=strtoul(String(dst_uid_str).substring(4,6).c_str(),NULL,16);
            dst_uid[3]=strtoul(String(dst_uid_str).substring(6,8).c_str(),NULL,16);
        }
        if (memcmp(dst_uid, master_uid, 4)!=0) return; /* not for us */

        const char *sw_id  = doc["sw_id"] | "";
        int         ch     = doc["ch"]    | 0;
        bool        state  = doc["state"] | false;
        uint8_t     req_id = doc["req_id"]| 0;

        /* Wildcard: kill all switches on this master */
        if (strcmp(sw_id,"*")==0) {
            /* Update state immediately before notify_ui() */
            xSemaphoreTake(state_mutex,portMAX_DELAY);
            master_relay1 = false;
            master_relay2 = false;
            for (int i=0;i<MAX_EXTENSIONS;i++) {
                if (extensions[i].state==EXT_EMPTY) continue;
                extensions[i].relay1 = false;
                extensions[i].relay2 = false;
                relay_cmd_t e1; e1.target=i; e1.channel=1; e1.state=false;
                relay_cmd_t e2; e2.target=i; e2.channel=2; e2.state=false;
                xQueueSend(ext_relay_queue,&e1,0);
                xQueueSend(ext_relay_queue,&e2,0);
            }
            xSemaphoreGive(state_mutex);
            relay_cmd_t k1; k1.target=-1; k1.channel=1; k1.state=false;
            relay_cmd_t k2; k2.target=-1; k2.channel=2; k2.state=false;
            xQueueSend(master_relay_queue,&k1,0);
            xQueueSend(master_relay_queue,&k2,0);
            /* Persist, like the local kill-all does. Last commanded state
             * is what the restore policy reads at boot; leaving it stale
             * would bring a killed house back lit. */
            relay_state_save_now();
            Serial.println("[MESH] Kill all (remote)");
            notify_ui();
            return;
        }

        /* Execute locally */
        relay_cmd_t cmd;
        if (strncmp(sw_id, "master", 6)==0) {
            cmd.target  = -1;
            cmd.channel = ch;
            cmd.state   = state;
            xQueueSend(master_relay_queue, &cmd, 0);
        } else if (sw_id[0]=='e') {
            int us   = String(sw_id).indexOf('_');
            int slot = String(sw_id).substring(3,us).toInt();
            cmd.target  = slot;
            cmd.channel = ch;
            cmd.state   = state;
            xQueueSend(ext_relay_queue, &cmd, 0);
        }

        /* Send ACK back */
        StaticJsonDocument<384> ack; /* name(31)+pass(63)+mesh_id(32)+uid(8)+overhead */
        ack["type"]   = MESH_PKT_RELAY_ACK;
        ack["uid"]    = String(uid_str[0])?uid_str:"";
        ack["req_id"] = req_id;
        ack["ok"]     = true;
        String ack_str; serializeJson(ack, ack_str);
        mesh_send(info->src_addr, ack_str.c_str(), ack_str.length()+1);

    } else if (type == MESH_PKT_RELAY_ACK) {
        /* Fire-and-forget relay -- ACK received but ignored.
         * State confirmed via next gossip broadcast. */

    } else if (type == MESH_PKT_JOIN_REQ) {
        /* New master wants to join our mesh */
        Serial.println("[MESH] JOIN_REQ received");
        /* Only genuine provisioned hardware may join. The joiner proves it
         * by echoing a checksum of the keys it holds; a device without
         * them cannot produce it. */
        {
            const char *pv = doc["pv"] | "";
            uint8_t want[32];
            uint8_t both[32];
            memcpy(both, root_key, 16); memcpy(both+16, fw_key, 16);
            hmac_sha256(both, (const uint8_t*)"unisync-prov-v1", 15, want);
            char wh[17];
            for (int k=0;k<8;k++) snprintf(wh+k*2,3,"%02x",want[k]);
            wh[16]=0;
            if (!root_key_set || !fw_key_set || strlen(pv)!=16 ||
                !safe_equal(wh, pv, 16)) {
                Serial.println("[MESH] JOIN_REQ rejected: joiner not provisioned");
                return;
            }
        }
        if (!mesh_active) {
            Serial.println("[MESH] JOIN_REQ rejected: not in mesh. Create mesh first.");
            /* Send reject so Master 2 knows why */
            StaticJsonDocument<64> rej;
            char self_uid[12];
            snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                     master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
            rej["type"]   = MESH_PKT_JOIN_REJ;
            rej["uid"]    = self_uid;
            rej["reason"] = "not_in_mesh";
            String rej_str; serializeJson(rej,rej_str);
            /* Register sender so we can reply */
            esp_now_peer_info_t pi={};
            memcpy(pi.peer_addr,info->src_addr,6);
            pi.channel=AP_CHANNEL; pi.encrypt=false;
    pi.ifidx=WIFI_IF_AP;
            if(!esp_now_is_peer_exist(pi.peer_addr)) esp_now_add_peer(&pi);
            esp_now_send(info->src_addr,(const uint8_t*)rej_str.c_str(),rej_str.length()+1);
            return;
        }
        const char *pin = doc["pin"] | "";
        Serial.printf("[MESH] Verifying PIN: '%s' against '%s'\n", pin, mesh_pin);
        if (mesh_verify_pin(pin)) {
            /* Send mesh credentials */
            StaticJsonDocument<384> ack; /* name(31)+pass(63)+mesh_id(32)+uid(8)+overhead */
            char mid_hex[33];
            for (int i=0;i<16;i++) snprintf(mid_hex+i*2, 3, "%02X", mesh_id[i]);
            mid_hex[32]='\0';
            ack["type"]      = MESH_PKT_JOIN_ACK;
            char self_uid[12];
            snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                     master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
            ack["uid"]          = self_uid;
            ack["mesh_id"]      = mid_hex;
            ack["mesh_name"]    = mesh_name;
            /* Credentials travel wrapped, not in clear. The joiner knows
             * the PIN; a listener does not. */
            {
                uint8_t nonce[8];
                for (int k=0;k<8;k+=4){ uint32_t r=esp_random();
                    nonce[k]=r&0xFF; nonce[k+1]=(r>>8)&0xFF;
                    nonce[k+2]=(r>>16)&0xFF; nonce[k+3]=(r>>24)&0xFF; }
                uint8_t sec[80]; uint16_t n=0;
                uint8_t plen = (uint8_t)strlen(mesh_pass);
                sec[n++] = plen;
                memcpy(sec+n, mesh_pass, plen); n += plen;
                memcpy(sec+n, mesh_auth_key, 16); n += 16;
                sec[n++] = (cred_version>>8)&0xFF;
                sec[n++] = cred_version&0xFF;
                pin_wrap(mesh_pin, src_uid, nonce, sec, n);
                char nh[17], sh[161];
                for (int k=0;k<8;k++)  snprintf(nh+k*2,3,"%02X",nonce[k]);
                for (int k=0;k<n;k++)  snprintf(sh+k*2,3,"%02X",sec[k]);
                nh[16]=0; sh[n*2]=0;
                ack["n"]   = nh;
                ack["sec"] = sh;
            }
            ack["master_order"] = master_order_str;
            String ack_str; serializeJson(ack, ack_str);
            /* Register sender as ESP-NOW peer first */
            esp_now_peer_info_t pi={};
            memcpy(pi.peer_addr, info->src_addr, 6);
            pi.channel=AP_CHANNEL; pi.encrypt=false;
    pi.ifidx=WIFI_IF_AP;
            if(!esp_now_is_peer_exist(pi.peer_addr)) esp_now_add_peer(&pi);
            /* Small delay to let peer registration complete */
            vTaskDelay(pdMS_TO_TICKS(10));
            esp_err_t send_err = esp_now_send(info->src_addr,
                (const uint8_t*)ack_str.c_str(), ack_str.length()+1);
            /* Add new master UID to order */
            char new_uid_str[12];
            snprintf(new_uid_str,sizeof(new_uid_str),"%02X%02X%02X%02X",
                     src_uid[0],src_uid[1],src_uid[2],src_uid[3]);
            master_order_add(new_uid_str);
            /* Also ensure self is in order */
            char self_uid2[12];
            snprintf(self_uid2,sizeof(self_uid2),"%02X%02X%02X%02X",
                     master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
            master_order_add(self_uid2);
            mesh_nvs_save();
            Serial.printf("[MESH] JOIN_ACK send result: %d\n", send_err);
            Serial.printf("[MESH] JOIN_ACK sent to %02X:%02X:%02X:%02X:%02X:%02X\n",
                info->src_addr[0],info->src_addr[1],info->src_addr[2],
                info->src_addr[3],info->src_addr[4],info->src_addr[5]);
        } else {
            StaticJsonDocument<64> rej;
            rej["type"] = MESH_PKT_JOIN_REJ;
            char self_uid[12];
            snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                     master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
            rej["uid"] = self_uid;
            String rej_str; serializeJson(rej, rej_str);
            esp_now_peer_info_t pi={};
            memcpy(pi.peer_addr, info->src_addr, 6);
            pi.channel=AP_CHANNEL; pi.encrypt=false;
    pi.ifidx=WIFI_IF_AP;
            esp_now_add_peer(&pi);
            mesh_send(info->src_addr, rej_str.c_str(), rej_str.length()+1);
            Serial.println("[MESH] JOIN rejected - wrong PIN");
        }

    } else if (type == MESH_PKT_JOIN_ACK) {
        /* We received mesh credentials - we are the joining master */
        Serial.println("[MESH] JOIN_ACK received - joining mesh");
        const char *mid_hex = doc["mesh_id"] | "";
        if (strlen(mid_hex)==32) {
            for (int i=0;i<16;i++) {
                char byte_str[3]={mid_hex[i*2],mid_hex[i*2+1],0};
                mesh_id[i]=(uint8_t)strtoul(byte_str,NULL,16);
            }
            /* Store mesh name, password, and master order from ACK */
            const char *mn = doc["mesh_name"] | "Unisync";
            strncpy(mesh_name, mn, sizeof(mesh_name)-1);
            /* Unwrap the credential payload with our own PIN. If the PIN
             * is wrong the bytes are garbage and the join is abandoned,
             * rather than half-joining with a broken password. */
            {
                const char *nh = doc["n"]   | "";
                const char *sh = doc["sec"] | "";
                uint16_t n = strlen(sh) / 2;
                if (strlen(nh) != 16 || n == 0 || n > 80) {
                    Serial.println("[MESH] JOIN_ACK malformed, ignoring");
                    return;
                }
                uint8_t nonce[8], sec[80];
                for (int k=0;k<8;k++){ char b[3]={nh[k*2],nh[k*2+1],0};
                    nonce[k]=(uint8_t)strtoul(b,NULL,16); }
                for (int k=0;k<n;k++){ char b[3]={sh[k*2],sh[k*2+1],0};
                    sec[k]=(uint8_t)strtoul(b,NULL,16); }
                pin_wrap(mesh_join_pin, master_uid, nonce, sec, n);

                uint8_t plen = sec[0];
                if (plen == 0 || plen > 63 || (uint16_t)(1+plen+18) > n) {
                    Serial.println("[MESH] JOIN_ACK unwrap failed -- wrong PIN?");
                    return;
                }
                memcpy(mesh_pass, sec+1, plen); mesh_pass[plen]=0;
                memcpy(mesh_auth_key, sec+1+plen, 16);
                mesh_auth_set = true;
                cred_version  = ((uint32_t)sec[1+plen+16]<<8) | sec[1+plen+17];
                prefs.begin("mesh", false);
                prefs.putString("mesh_pass", mesh_pass);
                prefs.putBytes("authkey", mesh_auth_key, 16);
                prefs.putUInt("credver", cred_version);
                prefs.end();
                Serial.println("[MESH] credentials unwrapped and stored");
                ble_update_adv_data();
            }
            const char *mo = doc["master_order"] | "";
            strncpy(master_order_str, mo, sizeof(master_order_str)-1);
            /* Add self to master_order if not already there */
            char self_uid_str[12];
            snprintf(self_uid_str,sizeof(self_uid_str),"%02X%02X%02X%02X",
                     master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
            master_order_add(self_uid_str);
            mesh_active = true;
            /* Register sender as peer */
            esp_now_peer_info_t pi={};
            memcpy(pi.peer_addr, info->src_addr, 6);
            pi.channel=AP_CHANNEL; pi.encrypt=false;
            pi.ifidx=WIFI_IF_AP;
            if (!esp_now_is_peer_exist(pi.peer_addr))
                esp_now_add_peer(&pi);
            mesh_nvs_save();
            Serial.printf("[MESH] Joined mesh: %s\n", mesh_name);
            /* Switch to mesh-name SSID */
            WiFi.softAPdisconnect(false);
            delay(100);
            WiFi.softAP(mesh_name, mesh_pass, AP_CHANNEL);
            Serial.printf("[WIFI] Switched to mesh SSID: %s\n", mesh_name);
            notify_ui();
        }

    } else if (type == MESH_PKT_JOIN_REJ) {
        /* Our join request was rejected */
        const char *reason = doc["reason"] | "wrong_pin";
        Serial.printf("[MESH] JOIN_REJ: %s\n", reason);
        /* UI will show timeout error - nothing more to do */

    } else if (type == MESH_PKT_KICK_ACK) {
        const char *who = doc["uid"] | "";
        Serial.printf("[MESH] %s confirmed it deleted its mesh credentials\n", who);
        kick_acked = true;

    } else if (type == MESH_PKT_KICK) {
        /* Another master is removing us. The packet is tagged with
         * mesh_auth_key, so only a genuine member can send it.
         *
         * Mesh credentials are wiped BEFORE the restart, deliberately: a
         * departing master must not keep anything that would let it
         * rejoin or listen. Note this only binds a cooperating device --
         * see the note in the security audit about a unit that is powered
         * off during the kick, or sold. */
        const char *tgt = doc["target"] | "";
        char self_uid[12];
        snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                 master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
        if (strcmp(tgt, self_uid) != 0) {
            /* Not us: drop the departing master from our own table. */
            uint8_t tu[4];
            if (strlen(tgt)==8) {
                for (int k=0;k<4;k++){ char b[3]={tgt[k*2],tgt[k*2+1],0};
                    tu[k]=(uint8_t)strtoul(b,NULL,16); }
                int idx = mesh_find_peer(tu);
                if (idx >= 0) {
                    Serial.printf("[MESH] peer %s removed from the mesh\n", tgt);
                    if (esp_now_is_peer_exist(mesh_peers[idx].mac))
                        esp_now_del_peer(mesh_peers[idx].mac);
                    memset(&mesh_peers[idx], 0, sizeof(mesh_peer_t));
                    master_order_remove(tgt);
                    notify_ui();
                }
            }
            return;
        }
        Serial.println("[MESH] we have been removed from the mesh -- reverting to standalone");
        /* Delete first, acknowledge second, reboot last. The acknowledgment
         * is what lets the remover report success honestly, and deleting
         * before rebooting means a failed reboot never leaves this device
         * holding both identities. */
        mesh_nvs_clear();
        {
            StaticJsonDocument<96> ack;
            ack["type"] = MESH_PKT_KICK_ACK;
            ack["uid"]  = self_uid;
            String out; serializeJson(ack, out);
            /* mesh_nvs_clear() dropped our key, so this goes out untagged;
             * the remover accepts KICK_ACK on that basis alone. */
            mesh_broadcast(out.c_str(), out.length()+1);
        }
        delay(300);
        ESP.restart();

    } else if (type == MESH_PKT_LEAVE) {
        /* Peer leaving mesh -- fully deregister it */
        int idx = mesh_find_peer(src_uid);
        if (idx >= 0) {
            Serial.printf("[MESH] Peer left mesh: %s\n", mesh_peers[idx].name);
            /* Remove ESP-NOW peer registration */
            if (esp_now_is_peer_exist(mesh_peers[idx].mac))
                esp_now_del_peer(mesh_peers[idx].mac);
            /* Clear peer slot completely */
            xSemaphoreTake(state_mutex, portMAX_DELAY);
            memset(&mesh_peers[idx], 0, sizeof(mesh_peer_t));
            xSemaphoreGive(state_mutex);
            /* Persist updated peer list */
            mesh_nvs_save();
            notify_ui();
            /* Remove from master_order */
            char leave_uid_str[12];
            snprintf(leave_uid_str,sizeof(leave_uid_str),"%02X%02X%02X%02X",
                     src_uid[0],src_uid[1],src_uid[2],src_uid[3]);
            master_order_remove(leave_uid_str);
            mesh_nvs_save();
            /* Broadcast updated order to remaining peers */
            mesh_send_config("reorder_masters", "", nullptr, master_order_str, -1);
            Serial.println("[MESH] Peer deregistered and removed from NVS");
        }

    } else if (type == MESH_PKT_PING) {
        /* Just update last_seen */
        int idx = mesh_find_peer(src_uid);
        if (idx >= 0) {
            xSemaphoreTake(state_mutex, portMAX_DELAY);
            mesh_peers[idx].last_seen_ms = millis();
            if (!mesh_peers[idx].online)
                presence_note_return(&mesh_peers[idx].settle_until_ms,
                                     mesh_peers[idx].last_drop_ms, millis());
            mesh_peers[idx].online = true;
            xSemaphoreGive(state_mutex);
        }

    } else if (type == MESH_PKT_CONFIG) {
        /* Config command: rename master, rename switch, reorder switches, reorder masters */
        const char *cmd        = doc["cmd"] | "";
        const char *target_uid = doc["target_uid"] | "";
        const char *name       = doc["name"] | "";
        const char *order      = doc["order"] | "";
        int         slot       = doc["slot"] | -1;

        /* Reorder masters -- mesh-wide, applies on all nodes */
        if (strcmp(cmd, "reorder_masters") == 0 && strlen(order) > 0) {
            strncpy(master_order_str, order, sizeof(master_order_str)-1);
            mesh_nvs_save();
            Serial.printf("[MESH] Master order updated: %s\n", master_order_str);
            notify_ui();

        /* Rename master -- only apply if this is the target */
        } else if (strcmp(cmd, "rename_master") == 0 && strlen(name) > 0) {
            char self_uid[12];
            snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                     master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
            if (strcmp(target_uid, self_uid) == 0) {
                nvs_save_master_name(name);
                strncpy(master_name, name, sizeof(master_name)-1);
                Serial.printf("[MESH] Master renamed: %s\n", master_name);
                notify_ui();
            }

        /* Rename switch -- only apply if this is the target */
        } else if (strcmp(cmd, "rename_switch") == 0 &&
                   strlen(name) > 0 && slot >= 0 && slot < MAX_EXTENSIONS) {
            char self_uid[12];
            snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                     master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
            if (strcmp(target_uid, self_uid) == 0) {
                xSemaphoreTake(state_mutex, portMAX_DELAY);
                if (extensions[slot].state != EXT_EMPTY) {
                    strncpy(extensions[slot].name, name, sizeof(extensions[slot].name)-1);
                    uint8_t uid[4]; memcpy(uid, extensions[slot].uid, 4);
                    xSemaphoreGive(state_mutex);
                    nvs_save(uid, slot, name);
                    Serial.printf("[MESH] Switch slot%d renamed: %s\n", slot+1, name);
                    notify_ui();
                } else {
                    xSemaphoreGive(state_mutex);
                }
            }

        /* Restore policy -- only apply if this is the target. `name` holds
         * the switch id, `slot` the 0/1 policy. */
        } else if (strcmp(cmd, "set_restore") == 0 && strlen(name) > 0) {
            char self_uid[12];
            snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                     master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
            if (strcmp(target_uid, self_uid) == 0 && switch_id_valid(String(name))) {
                nvs_save_restore(name, slot != 0);
                Serial.printf("[MESH] %s restore policy -> %s\n",
                              name, slot ? "restore" : "start off");
                notify_ui();
            }

        /* Reorder switches -- only apply if this is the target */
        } else if (strcmp(cmd, "reorder_switches") == 0 && strlen(order) > 0) {
            char self_uid[12];
            snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                     master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
            if (strcmp(target_uid, self_uid) == 0) {
                nvs_save_switch_order(order);
                switch_order = String(order);
                Serial.printf("[MESH] Switch order updated: %s\n", order);
                notify_ui();
            }
        }

    } else if (type == MESH_PKT_RECFAIL) {
        /* One recovery gate for the whole home: a rejection anywhere in the
         * mesh advances everyone's backoff, so hopping to another master
         * continues the same countdown instead of resetting it. Only ever
         * moves the gate later, never earlier -- except an explicit reset
         * after a successful recovery. */
        uint8_t f = (uint8_t)(doc["f"] | 0);
        uint32_t w = (uint32_t)(doc["w"] | 0);
        if (f == 0) {
            rec_fails   = 0;
            rec_next_ms = 0;
        } else if (f >= rec_fails) {
            rec_fails = f;
            uint32_t until = millis() + w * 1000UL;
            if (!rec_next_ms || (int32_t)(until - rec_next_ms) > 0)
                rec_next_ms = until ? until : 1;
        }

    } else if (type == MESH_PKT_PASS_CHG) {
        /* Name/password change -- always apply, packet always has both */
        const char *new_pass = doc["pass"] | "";
        const char *new_name = doc["name"] | "";
        if (strlen(new_pass) >= 8 && strlen(new_name) > 0) {
            strncpy(mesh_name, new_name, sizeof(mesh_name)-1);
            strncpy(mesh_pass, new_pass, sizeof(mesh_pass)-1);
            mesh_nvs_save();
            Serial.printf("[MESH] Config updated: %s\n", mesh_name);
            /* Defer softAP call to loop() -- calling WiFi driver from
             * ESP-NOW callback causes partial AP state / ghost SSID */
            strncpy(mesh_cfg_pending_name, mesh_name, sizeof(mesh_cfg_pending_name)-1);
            strncpy(mesh_cfg_pending_pass, mesh_pass, sizeof(mesh_cfg_pending_pass)-1);
            mesh_cfg_pending = true;
        }
    }
}

/* Initialize ESP-NOW mesh */
static void mesh_init(void) {
    delay(200); /* Wait for AP to fully start before ESP-NOW init */
    if (esp_now_init() != ESP_OK) {
        Serial.println("[MESH] ESP-NOW init failed");
        return;
    }
    esp_now_register_recv_cb(mesh_recv_cb);

    Serial.printf("[MESH] ESP-NOW init OK. WiFi channel: %d\n",
                  WiFi.channel());
    uint8_t ap_mac[6]; esp_read_mac(ap_mac, ESP_MAC_WIFI_SOFTAP);
    Serial.printf("[MESH] My AP MAC (use for peer reg): %02X:%02X:%02X:%02X:%02X:%02X\n",
        ap_mac[0],ap_mac[1],ap_mac[2],ap_mac[3],ap_mac[4],ap_mac[5]);

    /* Add broadcast peer */
    esp_now_peer_info_t pi={};
    uint8_t bcast[6]={0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
    memcpy(pi.peer_addr, bcast, 6);
    pi.channel=AP_CHANNEL; pi.encrypt=false;
    pi.ifidx=WIFI_IF_AP;
    esp_now_add_peer(&pi);

    /* Re-add saved peers from NVS */
    for (int i=0;i<MAX_MESH_MASTERS;i++) {
        bool has_mac = false;
        for (int j=0;j<6;j++) if (mesh_peers[i].mac[j]) { has_mac=true; break; }
        if (!has_mac) continue;
        Serial.printf("[MESH] NVS peer[%d] MAC: %02X:%02X:%02X:%02X:%02X:%02X\n", i,
            mesh_peers[i].mac[0],mesh_peers[i].mac[1],mesh_peers[i].mac[2],
            mesh_peers[i].mac[3],mesh_peers[i].mac[4],mesh_peers[i].mac[5]);
        if (esp_now_is_peer_exist(mesh_peers[i].mac))
            esp_now_del_peer(mesh_peers[i].mac);
        esp_now_peer_info_t p={};
        memcpy(p.peer_addr, mesh_peers[i].mac, 6);
        p.channel=AP_CHANNEL; p.encrypt=false;
        p.ifidx=WIFI_IF_AP;
        esp_err_t padd = esp_now_add_peer(&p);
        Serial.printf("[MESH] NVS peer add: %d\n", padd);
    }
    Serial.println("[MESH] ESP-NOW initialized");
}

/* Send relay command to a remote master via mesh */
static bool mesh_relay_remote(const uint8_t *dst_uid, const uint8_t *dst_mac,
                               const char *sw_id, int ch, bool state) {
    StaticJsonDocument<256> doc;
    char self_uid[12];
    snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
             master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
    char dst_uid_str[12];
    snprintf(dst_uid_str,sizeof(dst_uid_str),"%02X%02X%02X%02X",
             dst_uid[0],dst_uid[1],dst_uid[2],dst_uid[3]);
    doc["type"]    = MESH_PKT_RELAY_CMD;
    doc["uid"]     = self_uid;
    doc["dst_uid"] = dst_uid_str;
    doc["sw_id"]   = sw_id;
    doc["ch"]      = ch;
    doc["state"]   = state;
    String payload; serializeJson(doc, payload);

    /* Fire and forget -- no ACK wait.
     * State confirmed via next gossip broadcast (500ms).
     * Blocking the web task for ACK causes 500 errors. */
    /* Through mesh_send so the packet is tagged. Sent raw, it was dropped
     * by the peer's tag check and the command silently never landed. */
    bool ok = mesh_send(dst_mac, payload.c_str(), payload.length()+1);
    Serial.printf("[MESH] relay_remote to %s sw=%s ch=%d state=%d ok=%d\n",
                  dst_uid_str, sw_id, ch, state, ok ? 1 : 0);
    return ok;
}

/* Parse an 8-hex-char uid. False if it isn't one. */
static bool mesh_uid_parse(const char *s, uint8_t *out4) {
    if (!s || strlen(s) != 8) return false;
    for (int i = 0; i < 4; i++) {
        char b[3] = { s[i*2], s[i*2+1], 0 };
        char *end = nullptr;
        long v = strtol(b, &end, 16);
        if (end != b + 2) return false;
        out4[i] = (uint8_t)v;
    }
    return true;
}

/* Turn everything off on every peer as well as here.
 *
 * "All off" is one command, and in a mesh it means the whole house -- the
 * story puts whole-mesh control behind Bluetooth as well as Wi-Fi, and a
 * kill-all that stops at the master you happen to be talking to is exactly
 * the kind of half-result that makes people distrust the button. */
static void mesh_killall_peers(void) {
    if (!mesh_active) return;
    char self_uid[12];
    snprintf(self_uid, sizeof(self_uid), "%02X%02X%02X%02X",
             master_uid[0], master_uid[1], master_uid[2], master_uid[3]);
    StaticJsonDocument<128> doc;
    doc["type"]  = MESH_PKT_RELAY_CMD;
    doc["uid"]   = self_uid;
    doc["sw_id"] = "*";
    doc["ch"]    = 0;
    doc["state"] = false;
    for (int i = 0; i < MAX_MESH_MASTERS; i++) {
        if (!mesh_peers[i].online) continue;
        char puid[12];
        snprintf(puid, sizeof(puid), "%02X%02X%02X%02X",
                 mesh_peers[i].uid[0], mesh_peers[i].uid[1],
                 mesh_peers[i].uid[2], mesh_peers[i].uid[3]);
        doc["dst_uid"] = puid;
        String payload; serializeJson(doc, payload);
        mesh_send(mesh_peers[i].mac, payload.c_str(), payload.length()+1);
    }
}

/* Drive one switch on a peer to an explicit state, and reflect it in the
 * local cache so the next state push doesn't show the old value for the
 * half-second until gossip corrects it. False if the peer is unknown. */
static bool mesh_relay_set(const uint8_t *peer_uid, const char *sw_id,
                           int ch, bool state) {
    int idx = mesh_find_peer(peer_uid);
    if (idx < 0) return false;
    bool ok = mesh_relay_remote(peer_uid, mesh_peers[idx].mac, sw_id, ch, state);
    xSemaphoreTake(state_mutex, portMAX_DELAY);
    for (int i = 0; i < mesh_peers[idx].switch_count; i++) {
        if (!strcmp(mesh_peers[idx].switches[i].id, sw_id)) {
            mesh_peers[idx].switches[i].state = state;
            break;
        }
    }
    xSemaphoreGive(state_mutex);
    notify_ui();
    return ok;
}

/* Check peer timeouts */
static void mesh_check_timeouts(void) {
    if (!mesh_active) return;
    uint32_t now = millis();
    xSemaphoreTake(state_mutex, portMAX_DELAY);
    for (int i=0;i<MAX_MESH_MASTERS;i++) {
        if (!mesh_peers[i].online) continue;
        if ((now - mesh_peers[i].last_seen_ms) > MESH_PEER_TIMEOUT) {
            mesh_peers[i].online = false;
            presence_note_drop(&mesh_peers[i].settle_until_ms,
                               &mesh_peers[i].last_drop_ms,
                               &mesh_peers[i].drops, now);
            Serial.printf("[MESH] Peer offline: %s\n", mesh_peers[i].name);
            xSemaphoreGive(state_mutex);
            notify_ui();
            xSemaphoreTake(state_mutex, portMAX_DELAY);
            continue;
        }
        /* A returning peer's card only goes green after a solid minute; that
         * moment has to push a state update of its own. */
        uint32_t before = mesh_peers[i].settle_until_ms;
        presence_tick_up(&mesh_peers[i].settle_until_ms,
                         &mesh_peers[i].last_drop_ms,
                         &mesh_peers[i].drops, now);
        if (before && mesh_peers[i].settle_until_ms == 0) {
            xSemaphoreGive(state_mutex);
            notify_ui();
            xSemaphoreTake(state_mutex, portMAX_DELAY);
        }
    }
    xSemaphoreGive(state_mutex);
}

/* ================================================================
 * NVS
 * ================================================================ */
static void nvs_uid_key(const uint8_t *uid, char *key, int klen) {
    snprintf(key, klen, "%02X%02X%02X%02X",
             uid[0],uid[1],uid[2],uid[3]);
}

static int nvs_load_slot(const uint8_t *uid) {
    char key[12]; nvs_uid_key(uid,key,sizeof(key));
    prefs.begin("ext_map",true);
    int s=prefs.getInt(key,-1);
    prefs.end(); return s;
}

static void nvs_load_name(const uint8_t *uid, char *name, int nlen) {
    char key[12]; nvs_uid_key(uid,key,sizeof(key));
    char nkey[16]; snprintf(nkey,sizeof(nkey),"n%s",key);
    prefs.begin("ext_map",true);
    String s=prefs.getString(nkey,"Switch");
    prefs.end();
    strncpy(name,s.c_str(),nlen-1); name[nlen-1]='\0';
}

static void nvs_save(const uint8_t *uid, int slot, const char *name) {
    char key[12]; nvs_uid_key(uid,key,sizeof(key));
    char nkey[16]; snprintf(nkey,sizeof(nkey),"n%s",key);
    prefs.begin("ext_map",false);
    prefs.putInt(key,slot);
    prefs.putString(nkey,name);
    String index=prefs.getString("uid_index","");
    String us=String(key);
    if (index.indexOf(us)<0) {
        if (index.length()>0) index+=",";
        index+=us; prefs.putString("uid_index",index);
    }
    prefs.end();
}

static void nvs_remove(const uint8_t *uid) {
    char key[12]; nvs_uid_key(uid,key,sizeof(key));
    char nkey[16]; snprintf(nkey,sizeof(nkey),"n%s",key);
    prefs.begin("ext_map",false);
    prefs.remove(key); prefs.remove(nkey);
    String index=prefs.getString("uid_index","");
    String us=String(key);
    int idx=index.indexOf(us);
    if (idx>=0) {
        if (idx>0&&index[idx-1]==',') index.remove(idx-1,us.length()+1);
        else if (idx+(int)us.length()<(int)index.length()) index.remove(idx,us.length()+1);
        else index.remove(idx,us.length());
        prefs.putString("uid_index",index);
    }
    prefs.end();
}

static void nvs_restore_all(void) {
    prefs.begin("ext_map",true);
    String index=prefs.getString("uid_index","");
    prefs.end();
    if (index.length()==0) return;
    int start=0;
    while (start<(int)index.length()) {
        int comma=index.indexOf(',',start);
        String us=(comma<0)?index.substring(start):index.substring(start,comma);
        start=(comma<0)?index.length():comma+1;
        if (us.length()!=8) continue;
        uint8_t uid[4];
        uid[0]=strtoul(us.substring(0,2).c_str(),NULL,16);
        uid[1]=strtoul(us.substring(2,4).c_str(),NULL,16);
        uid[2]=strtoul(us.substring(4,6).c_str(),NULL,16);
        uid[3]=strtoul(us.substring(6,8).c_str(),NULL,16);
        int slot=nvs_load_slot(uid);
        if (slot<0||slot>=MAX_EXTENSIONS) continue;
        char name[24]; nvs_load_name(uid,name,sizeof(name));
        extension_t *e=&extensions[slot];
        memcpy(e->uid,uid,4);
        ext_reset_identity(e);
        e->address=(uint8_t)(slot+1);
        e->state=EXT_OFFLINE;
        e->missed=0; e->relay1=false; e->relay2=false;
        e->last_seen_ms=0; e->polled_once=false;
        strncpy(e->name,name,sizeof(e->name)-1);
        e->name[sizeof(e->name)-1]='\0';
        Serial.printf("[NVS] Restored: %s -> slot%d addr=0x%02X\n",
                      name,slot+1,e->address);
    }
}

/* ================================================================
 * SWITCH NAMES + ORDER + MASTER NAME NVS
 * ================================================================ */

/* Switch ID format: "master_1", "master_2", "ext0_1", "ext0_2" etc */
static void switch_id(char *buf, int buflen, int slot, int ch) {
    if (slot < 0) snprintf(buf, buflen, "master_%d", ch);
    else          snprintf(buf, buflen, "ext%d_%d", slot, ch);
}

static void nvs_save_switch_name(const char *id, const char *name) {
    char key[20]; snprintf(key, sizeof(key), "sw:%s", id);
    prefs.begin("sw_names", false);
    prefs.putString(key, name);
    prefs.end();
}

static void nvs_load_switch_name(const char *id, char *name, int nlen) {
    char key[20]; snprintf(key, sizeof(key), "sw:%s", id);
    prefs.begin("sw_names", true);
    String s = prefs.getString(key, "");
    prefs.end();
    if (s.length() > 0) { strncpy(name, s.c_str(), nlen-1); name[nlen-1]='\0'; }
    else snprintf(name, nlen, "Switch");
}

/* Per-switch restore policy: true = restore last state after a power cut,
 * false = always start off. The default is FALSE on purpose -- the story
 * says the house comes back dark unless the owner opted that one switch in.
 * Stored in "sw_names" so a factory reset wipes policies with the names. */
static bool nvs_load_restore(const char *id) {
    char key[20]; snprintf(key, sizeof(key), "rs:%s", id);
    prefs.begin("sw_names", true);
    bool v = prefs.getBool(key, false);
    prefs.end();
    return v;
}

static void nvs_save_restore(const char *id, bool restore) {
    char key[20]; snprintf(key, sizeof(key), "rs:%s", id);
    prefs.begin("sw_names", false);
    prefs.putBool(key, restore);
    prefs.end();
}

/* True for "master_1", "master_2", and "extN_1"/"extN_2" naming a slot that
 * actually holds a board. Keeps a typo from silently creating an NVS key
 * that nothing will ever read back. */
static bool switch_id_valid(const String &id) {
    if (id == "master_1" || id == "master_2") return true;
    if (!id.startsWith("ext")) return false;
    int us = id.indexOf('_');
    if (us < 4) return false;
    int slot = id.substring(3, us).toInt();
    int ch   = id.substring(us + 1).toInt();
    if (slot < 0 || slot >= MAX_EXTENSIONS) return false;
    if (ch != 1 && ch != 2) return false;
    return extensions[slot].state != EXT_EMPTY;
}

/* Spaces restore pushes out. Shared by the master's own two channels and by
 * every extension channel, so the stagger holds across the whole board and
 * not just within one device. */
static uint32_t restore_last_ms = 0;
static void restore_stagger(void) {
    uint32_t since = millis() - restore_last_ms;
    if (since < RESTORE_STAGGER_MS) delay(RESTORE_STAGGER_MS - since);
    restore_last_ms = millis();
}

static void nvs_save_master_name(const char *name) {
    prefs.begin("sw_names", false);
    prefs.putString("master_name", name);
    prefs.end();
}

static void nvs_load_master_name(char *name, int nlen) {
    prefs.begin("sw_names", true);
    String s = prefs.getString("master_name", "Master 1");
    prefs.end();
    strncpy(name, s.c_str(), nlen-1); name[nlen-1]='\0';
}

static void nvs_save_switch_order(const String &order) {
    prefs.begin("sw_names", false);
    prefs.putString("sw_order", order);
    prefs.end();
}

static String nvs_load_switch_order(void) {
    prefs.begin("sw_names", true);
    String s = prefs.getString("sw_order", "");
    prefs.end();
    return s;
}

/* Everything a slot accumulates that is keyed by slot rather than by board:
 * switch names, restore policies and last relay states. The registry entry
 * is keyed by uid and cleared separately by nvs_remove.
 *
 * Removing an extension has to clear all of it. The story is explicit that
 * a removed board's names and settings are forgotten, and that a board
 * reappearing on the bus is adopted as new with default names -- but a slot
 * is reused by whatever board lands in it next, so leftovers were inherited
 * by a completely different device: someone else's names, and a relay that
 * switches on at boot because the previous occupant was on. */
static void nvs_forget_slot(int slot) {
    char id[16], key[20];
    for (int ch = 1; ch <= 2; ch++) {
        switch_id(id, sizeof(id), slot, ch);
        snprintf(key, sizeof(key), "sw:%s", id);
        prefs.begin("sw_names", false);
        prefs.remove(key);
        snprintf(key, sizeof(key), "rs:%s", id);
        prefs.remove(key);
        prefs.end();
    }
    char k1[8], k2[8];
    snprintf(k1, sizeof(k1), "e%d_r1", slot);
    snprintf(k2, sizeof(k2), "e%d_r2", slot);
    prefs.begin("relay_state", false);
    prefs.remove(k1);
    prefs.remove(k2);
    prefs.end();

    /* Drop the slot's ids from the saved order too, so a reused slot does
     * not inherit the previous board's position. */
    String order = nvs_load_switch_order();
    if (order.length() == 0) return;
    String rebuilt;
    int start = 0;
    while (start < (int)order.length()) {
        int comma = order.indexOf(',', start);
        String tok = (comma < 0) ? order.substring(start)
                                 : order.substring(start, comma);
        start = (comma < 0) ? order.length() : comma + 1;
        if (tok.length() == 0) continue;
        bool mine = false;
        for (int ch = 1; ch <= 2 && !mine; ch++) {
            switch_id(id, sizeof(id), slot, ch);
            mine = (tok == id);
        }
        if (mine) continue;
        if (rebuilt.length()) rebuilt += ",";
        rebuilt += tok;
    }
    if (rebuilt != order) nvs_save_switch_order(rebuilt);
}

/* ================================================================
 * MESH NVS
 * ================================================================ */
/* Add a UID to master_order if not already present */
static void master_order_add(const char *uid) {
    if (!uid || strlen(uid) == 0) return;
    if (strstr(master_order_str, uid)) return; /* already in list */
    if (strlen(master_order_str) > 0)
        strncat(master_order_str, ",", sizeof(master_order_str)-strlen(master_order_str)-1);
    strncat(master_order_str, uid, sizeof(master_order_str)-strlen(master_order_str)-1);
}

/* Remove a UID from master_order */
static void master_order_remove(const char *uid) {
    if (!uid || strlen(uid)==0) return;
    char tmp[sizeof(master_order_str)] = {0};
    char buf[sizeof(master_order_str)];
    strncpy(buf, master_order_str, sizeof(buf)-1);
    char *tok = strtok(buf, ",");
    bool first = true;
    while (tok) {
        if (strcmp(tok, uid) != 0) {
            if (!first) strncat(tmp, ",", sizeof(tmp)-strlen(tmp)-1);
            strncat(tmp, tok, sizeof(tmp)-strlen(tmp)-1);
            first = false;
        }
        tok = strtok(NULL, ",");
    }
    strncpy(master_order_str, tmp, sizeof(master_order_str)-1);
}

static void mesh_nvs_save(void) {
    prefs.begin("mesh", false);
    prefs.putBytes("mesh_id", mesh_id, 16);
    prefs.putBool("active", mesh_active);
    prefs.putString("mesh_name", mesh_name);
    prefs.putString("mesh_pass", mesh_pass);
    prefs.putString("master_order", master_order_str);
    uint8_t peer_count = 0;
    for (int i=0; i<MAX_MESH_MASTERS; i++)
        if (mesh_peers[i].last_seen_ms > 0 ||
            memcmp(mesh_peers[i].uid,"    ",4)!=0)
            peer_count++;
    prefs.putUChar("peer_count", peer_count);
    for (int i=0,j=0; i<MAX_MESH_MASTERS; i++) {
        bool has_uid=false;
        for(int k=0;k<4;k++) if(mesh_peers[i].uid[k]) {has_uid=true;break;}
        if(!has_uid) continue;
        char key[12];
        snprintf(key,sizeof(key),"pm%d",j);
        prefs.putBytes(key,mesh_peers[i].mac,6);
        snprintf(key,sizeof(key),"pu%d",j);
        prefs.putBytes(key,mesh_peers[i].uid,4);
        j++;
    }
    prefs.end();
}

static void mesh_nvs_load(void) {
    prefs.begin("mesh",true);
    mesh_active = prefs.getBool("active",false);
    if (mesh_active) {
        prefs.getBytes("mesh_id",mesh_id,16);
        String mn = prefs.getString("mesh_name","Unisync");
        strncpy(mesh_name, mn.c_str(), sizeof(mesh_name)-1);
        String mp = prefs.getString("mesh_pass","12345678");
        strncpy(mesh_pass, mp.c_str(), sizeof(mesh_pass)-1);
        String mo = prefs.getString("master_order","");
        strncpy(master_order_str, mo.c_str(), sizeof(master_order_str)-1);
        uint8_t pc = prefs.getUChar("peer_count",0);
        for (int i=0;i<pc&&i<MAX_MESH_MASTERS;i++) {
            char key[12];
            snprintf(key,sizeof(key),"pm%d",i);
            prefs.getBytes(key,mesh_peers[i].mac,6);
            snprintf(key,sizeof(key),"pu%d",i);
            prefs.getBytes(key,mesh_peers[i].uid,4);
            /* Set last_seen to now so peer doesn't immediately timeout.
             * Will be corrected by first gossip or marked offline after
             * MESH_PEER_TIMEOUT if peer never responds. */
            mesh_peers[i].last_seen_ms = millis();
            mesh_peers[i].online = false; /* not confirmed online yet */
        }
    }
    prefs.end();
    if (mesh_active) Serial.println("[MESH] Credentials restored");
}

static void mesh_nvs_clear(void) {
    /* Remove all registered ESP-NOW peers */
    for (int i=0;i<MAX_MESH_MASTERS;i++) {
        bool has_mac=false;
        for (int j=0;j<6;j++) if (mesh_peers[i].mac[j]) { has_mac=true; break; }
        if (has_mac && esp_now_is_peer_exist(mesh_peers[i].mac))
            esp_now_del_peer(mesh_peers[i].mac);
    }
    prefs.begin("mesh",false); prefs.clear(); prefs.end();
    memset(mesh_id,0,16);
    memset(mesh_peers,0,sizeof(mesh_peers));
    mesh_active=false;
    strncpy(mesh_name,"Unisync",sizeof(mesh_name)-1);
    /* Leaving reverts to this device's own credential: its SSID and the
         * password on its label. The mesh keys are cleared so a stale copy
         * cannot authenticate anything. */
        memset(mesh_auth_key, 0, sizeof(mesh_auth_key));
        mesh_auth_set = false;
        cred_version  = 0;
        cred_stale    = false;
        prefs.begin("mesh", false);
        prefs.remove("authkey"); prefs.remove("credver"); prefs.remove("mesh_pass");
        prefs.end();
        strncpy(mesh_pass,"12345678",sizeof(mesh_pass)-1);
        ble_update_adv_data();
}

/* ================================================================
 * RELAY STATE NVS
 * ================================================================ */
/* Every toggle used to write NVS inline. The tech story asks for these
 * writes to be debounced -- written shortly after the last toggle in a
 * burst, not on every one -- to limit flash wear, and a wall switch being
 * flipped repeatedly is exactly the burst it means. The in-RAM state is
 * already authoritative for everything that reads it; only the flash write
 * waits. Same treatment the extension firmware got. */
#define RELAY_NVS_DEBOUNCE_MS 3000UL
static bool     relay_nvs_dirty    = false;
static uint32_t relay_nvs_dirty_ms = 0;

static void relay_state_flush(void) {
    prefs.begin("relay_state",false);
    prefs.putBool("m_r1",master_relay1);
    prefs.putBool("m_r2",master_relay2);
    /* Save extension relay states */
    xSemaphoreTake(state_mutex,portMAX_DELAY);
    for (int i=0;i<MAX_EXTENSIONS;i++) {
        char k1[8],k2[8];
        snprintf(k1,sizeof(k1),"e%d_r1",i);
        snprintf(k2,sizeof(k2),"e%d_r2",i);
        prefs.putBool(k1,extensions[i].relay1);
        prefs.putBool(k2,extensions[i].relay2);
    }
    xSemaphoreGive(state_mutex);
    prefs.end();
    relay_nvs_dirty = false;
}

/* Mark the saved state stale; the bus task commits it once the flipping
 * stops. */
static void relay_state_save(void) {
    relay_nvs_dirty    = true;
    relay_nvs_dirty_ms = millis();
}

/* Commit now, cancelling any pending debounce. For the deliberate
 * everything-off and for credential changes, where losing the write to a
 * power cut would be worse than a flash write. */
static void relay_state_save_now(void) {
    relay_state_flush();
}

/* Called from the bus loop. Never writes during an OTA: the flash driver
 * is busy with the image and a page write there is not worth the risk. */
static void relay_state_tick(void) {
    if (!relay_nvs_dirty || ota_in_progress) return;
    if ((millis() - relay_nvs_dirty_ms) < RELAY_NVS_DEBOUNCE_MS) return;
    relay_state_flush();
}

/* Applies each channel's restore policy to the state just read from NVS.
 * Channels set to "always start off" are zeroed here, which is what makes
 * the rest of the boot path safe by construction: everything downstream (the
 * master's own GPIO writes, the first-poll push to each extension) works from
 * these values, so a restore can only ever take a channel from off to on --
 * never the reverse -- and a "start off" channel is never pushed at all.
 *
 * `slot` is -1 for the master's own board. */
static void apply_restore_policy(int slot, bool *r1, bool *r2) {
    char id[16];
    switch_id(id,sizeof(id),slot,1); if (!nvs_load_restore(id)) *r1=false;
    switch_id(id,sizeof(id),slot,2); if (!nvs_load_restore(id)) *r2=false;
}

/* ================================================================
 * SLOT HELPERS
 * ================================================================ */
static int find_slot_by_addr(uint8_t addr) {
    for (int i=0;i<MAX_EXTENSIONS;i++)
        if (extensions[i].state!=EXT_EMPTY&&extensions[i].address==addr) return i;
    return -1;
}

static int find_slot_by_uid(const uint8_t *uid) {
    for (int i=0;i<MAX_EXTENSIONS;i++)
        if (extensions[i].state!=EXT_EMPTY&&memcmp(extensions[i].uid,uid,4)==0) return i;
    return -1;
}

static int find_empty_slot(void) {
    for (int i=0;i<MAX_EXTENSIONS;i++)
        if (extensions[i].state==EXT_EMPTY) return i;
    return -1;
}

static uint8_t next_free_addr(void) {
    for (uint8_t a=1;a<=MAX_EXTENSIONS;a++) {
        bool taken=false;
        for (int i=0;i<MAX_EXTENSIONS;i++) {
            if (extensions[i].state==EXT_EMPTY) continue;
            if (extensions[i].address==a) { taken=true; break; }
            if (extensions[i].address==ADDR_UNASSIGNED&&(uint8_t)(i+1)==a) { taken=true; break; }
        }
        if (!taken) return a;
    }
    return ADDR_UNASSIGNED;
}

/* ================================================================
 * PENDING QUEUE
 * ================================================================ */
static bool pending_uid_exists(const uint8_t *uid) {
    for (int i=0;i<MAX_PENDING;i++)
        if (pending_queue[i].active&&memcmp(pending_queue[i].uid,uid,4)==0) return true;
    return false;
}

static void pending_add(const uint8_t *uid) {
    if (pending_uid_exists(uid)) return;
    for (int i=0;i<MAX_PENDING;i++) {
        if (!pending_queue[i].active) {
            memcpy(pending_queue[i].uid,uid,4);
            pending_queue[i].first_seen_ms=millis();
            pending_queue[i].active=true;
            Serial.printf("[PEND] New ext UID=%02X%02X%02X%02X\n",
                          uid[0],uid[1],uid[2],uid[3]);
            return;
        }
    }
    Serial.println("[PEND] Queue full");
}

static void pending_remove(const uint8_t *uid) {
    for (int i=0;i<MAX_PENDING;i++)
        if (pending_queue[i].active&&memcmp(pending_queue[i].uid,uid,4)==0) {
            pending_queue[i].active=false; return;
        }
}

static int pending_count(void) {
    int c=0;
    for (int i=0;i<MAX_PENDING;i++) if (pending_queue[i].active) c++;
    return c;
}

/* ================================================================
 * SEND WELCOME
 * ================================================================ */
/* Send challenge to extension before welcoming */
static void send_challenge(const uint8_t *uid) {
    int i = -1;
    for (int k=0;k<MAX_PENDING;k++) if (!challenges[k].active) { i=k; break; }
    if (i < 0) return;

    /* A real nonce. The old challenge was millis() XOR uid, and millis()
     * restarts at zero, so challenges repeated after every power cut and a
     * recorded exchange could simply be replayed. */
    uint8_t nonce[8];
    for (int k=0;k<8;k+=4) {
        uint32_t r = esp_random();
        nonce[k]=r&0xFF; nonce[k+1]=(r>>8)&0xFF;
        nonce[k+2]=(r>>16)&0xFF; nonce[k+3]=(r>>24)&0xFF;
    }
    memcpy(challenges[i].uid, uid, 4);
    memcpy(challenges[i].nonce, nonce, 8);
    challenges[i].active  = true;
    challenges[i].sent_ms = millis();

    uint8_t payload[12];
    memcpy(payload, uid, 4);
    memcpy(payload+4, nonce, 8);
    bus_send(ADDR_BCAST, CMD_CHALLENGE, payload, 12);
}

/* Verify challenge response and return true if valid */
static bool verify_response(const uint8_t *uid, const uint8_t *resp_mac) {
    for (int i=0; i<MAX_CHALLENGES; i++) {
        if (!challenges[i].active) continue;
        if (memcmp(challenges[i].uid, uid, 4) != 0) continue;
        if ((millis()-challenges[i].sent_ms) > 5000) {
            challenges[i].active = false; continue;
        }
        challenges[i].active = false;          /* single use */

        if (!root_key_set) {
            Serial.println("[SEC] no root key provisioned, refusing");
            return false;
        }
        /* Derive this device's key from its UID, then check the MAC it
         * returned over our nonce. Replaces CRC32, which was forgeable. */
        uint8_t devkey[32], msg[12], want[32];
        hmac_sha256(root_key, uid, 4, devkey);
        memcpy(msg, challenges[i].nonce, 8);
        memcpy(msg+8, uid, 4);
        hmac_sha256(devkey, msg, 12, want);

        if (ct_equal(want, resp_mac, 8)) {
            Serial.printf("[SEC] Auth OK %02X%02X%02X%02X\n",
                          uid[0],uid[1],uid[2],uid[3]);
            return true;
        }
        Serial.printf("[SEC] Auth FAIL %02X%02X%02X%02X\n",
                      uid[0],uid[1],uid[2],uid[3]);
        return false;
    }
    Serial.printf("[SEC] No challenge found for %02X%02X%02X%02X\n",
                  uid[0],uid[1],uid[2],uid[3]);
    return false;
}

static void send_welcome(const uint8_t *uid, uint8_t addr,
                         bool r1, bool r2) {
    uint8_t payload[10];
    payload[0]=uid[0]; payload[1]=uid[1];
    payload[2]=uid[2]; payload[3]=uid[3];
    payload[4]=addr;
    payload[5]=(r1?0x01:0x00)|(r2?0x02:0x00);
    payload[6]=master_uid[0]; payload[7]=master_uid[1];
    payload[8]=master_uid[2]; payload[9]=master_uid[3];
    /* Send to ADDR_UNASSIGNED - extension listens on 0xFE when unregistered */
    uint8_t frame[40];
    frame[0]=SOF; frame[1]=ADDR_UNASSIGNED; frame[2]=ADDR_MASTER;
    frame[3]=CMD_WELCOME; frame[4]=10;
    for (int i=0;i<10;i++) frame[5+i]=payload[i];
    frame[15]=crc8(&frame[1],14);
    digitalWrite(RS485_DE_PIN,HIGH);
    BusSerial.write(frame,16);
    BusSerial.flush();
    digitalWrite(RS485_DE_PIN,LOW);
}

static void send_reject(const uint8_t *uid) {
    uint8_t frame[40];
    frame[0]=SOF; frame[1]=ADDR_UNASSIGNED; frame[2]=ADDR_MASTER;
    frame[3]=CMD_REJECT; frame[4]=4;
    frame[5]=uid[0]; frame[6]=uid[1]; frame[7]=uid[2]; frame[8]=uid[3];
    frame[9]=crc8(&frame[1],8);
    digitalWrite(RS485_DE_PIN,HIGH);
    BusSerial.write(frame,10);
    BusSerial.flush();
    digitalWrite(RS485_DE_PIN,LOW);
}

/* ================================================================
 * HANDLE ANNOUNCE FRAME
 * ================================================================ */
static void handle_announce(const uint8_t *frame) {
    uint8_t plen=frame[4];
    if (plen<5) return;
    if (frame[5+plen]!=crc8(&frame[1],4+plen)) return;

    const uint8_t *uid=&frame[5];

    /* Always challenge first - no WELCOME without auth */
    /* Check if we already have an active challenge for this UID */
    bool has_challenge=false;
    for (int i=0;i<MAX_CHALLENGES;i++) {
        if (challenges[i].active&&memcmp(challenges[i].uid,uid,4)==0) {
            has_challenge=true; break;
        }
    }
    /* Send new challenge if none pending */
    if (!has_challenge) send_challenge(uid);
}

/* Called when CMD_RESPONSE received - verify and complete registration */
static void handle_response(const uint8_t *frame) {
    uint8_t plen=frame[4];
    if (plen<12) return;
    if (frame[5+plen]!=crc8(&frame[1],4+plen)) return;

    const uint8_t *uid      = &frame[5];
    const uint8_t *resp_mac = &frame[9];

    if (!verify_response(uid, resp_mac)) {
        /* Auth failed - send reject */
        send_reject(uid);
        Serial.printf("[SEC] REJECT invalid response from %02X%02X%02X%02X\n",
                      uid[0],uid[1],uid[2],uid[3]);
        return;
    }

    /* Auth passed - now process registration */
    /* Check if already registered in RAM */
    int existing=find_slot_by_uid(uid);
    if (existing>=0) {
        uint8_t addr=extensions[existing].address;
        send_welcome(uid,addr,
                    extensions[existing].relay1,
                    extensions[existing].relay2);
        xSemaphoreTake(state_mutex,portMAX_DELAY);
        extensions[existing].polled_once=true;
        /* A board that had gone offline and re-announced is a *return*, so it
         * serves the settle window like any other; one that never left keeps
         * whatever presence it already had. */
        if (extensions[existing].state==EXT_OFFLINE)
            presence_note_return(&extensions[existing].settle_until_ms,
                                 extensions[existing].last_drop_ms,millis());
        extensions[existing].state=EXT_ONLINE;
        extensions[existing].missed=0;
        /* Grace period: wait 1s before polling to let extension save state */
        extensions[existing].last_seen_ms=millis()+1000;
        xSemaphoreGive(state_mutex);
        Serial.printf("[SEC] Auth OK - re-welcoming %s\n",
                      extensions[existing].name);
        notify_ui();
        return;
    }

    /* Check NVS */
    int saved_slot=nvs_load_slot(uid);
    if (saved_slot>=0&&saved_slot<MAX_EXTENSIONS) {
        uint8_t new_addr=(uint8_t)(saved_slot+1);
        char saved_name[24]; nvs_load_name(uid,saved_name,sizeof(saved_name));
        xSemaphoreTake(state_mutex,portMAX_DELAY);
        extension_t *e=&extensions[saved_slot];
        memcpy(e->uid,uid,4);
        ext_reset_identity(e);
        e->address=new_addr;
        e->state=EXT_ONLINE;
        e->missed=0;
        e->last_seen_ms=millis();
        e->polled_once=true;
        strncpy(e->name,saved_name,sizeof(e->name)-1);
        xSemaphoreGive(state_mutex);
        send_welcome(uid,new_addr,
                    extensions[saved_slot].relay1,
                    extensions[saved_slot].relay2);
        Serial.printf("[SEC] Auth OK - restored %s slot=%d\n",
                      saved_name,saved_slot+1);
        notify_ui();
        return;
    }

    /* Brand new verified extension - add to pending queue */
    xSemaphoreTake(state_mutex,portMAX_DELAY);
    pending_add(uid);
    xSemaphoreGive(state_mutex);
    Serial.printf("[SEC] Auth OK - new ext %02X%02X%02X%02X awaiting assign\n",
                  uid[0],uid[1],uid[2],uid[3]);
    notify_ui();
}

/* ================================================================
 * LISTEN WINDOW - reads ANNOUNCE frames
 * ================================================================ */
static void run_listen_window(void) {
    uint8_t resp[40];
    uint32_t start=millis();
    while ((millis()-start)<LISTEN_WINDOW_MS) {
        if (BusSerial.available()) {
            uint8_t buf[40]; uint8_t pos=0,elen=0;
            uint32_t t=millis();
            while ((millis()-t)<10) {
                if (!BusSerial.available()) { vTaskDelay(pdMS_TO_TICKS(1)); continue; }
                uint8_t b=BusSerial.read();
                if (pos==0) { if (b==SOF) buf[pos++]=b; }
                else {
                    if (pos>=sizeof(buf)) { pos=0; elen=0; break; }
                    buf[pos++]=b;
                    if (pos==5) elen=6+buf[4];
                    if (elen>0&&pos>=elen) {
                        if (buf[3]==CMD_ANNOUNCE)  handle_announce(buf);
                        if (buf[3]==CMD_RESPONSE)  handle_response(buf);
                        pos=0; elen=0;
                        /* continue reading - may be more frames */
                    }
                }
            }
        } else { vTaskDelay(pdMS_TO_TICKS(1)); }
    }
}

/* ================================================================
 * POLL ONE EXTENSION
 * ================================================================ */
/* Ask an extension what it is. Runs once after it comes online, and
 * again after an update so the new version is picked up. Cheap: one
 * frame, and only while hw_type is unknown. */
static void ext_query_info(int i) {
    xSemaphoreTake(state_mutex, portMAX_DELAY);
    bool need = (extensions[i].state == EXT_ONLINE) &&
                (extensions[i].hw_type == 0);
    uint8_t addr = extensions[i].address;
    xSemaphoreGive(state_mutex);
    if (!need || addr == ADDR_UNASSIGNED) return;

    flush_rx();
    bus_send(addr, CMD_GET_INFO, NULL, 0);
    uint8_t resp[40];
    uint8_t n = bus_recv(resp, sizeof(resp), BUS_RESP_MS);
    if (n < 6) return;
    uint8_t plen = resp[4];
    if (resp[3] != CMD_INFO_RESP || plen < 5) return;
    if (resp[5 + plen] != crc8(&resp[1], 4 + plen)) return;

    xSemaphoreTake(state_mutex, portMAX_DELAY);
    extensions[i].hw_type   = resp[5];
    extensions[i].hw_rev    = resp[6];
    extensions[i].fw_ver[0] = resp[7];
    extensions[i].fw_ver[1] = resp[8];
    extensions[i].fw_ver[2] = resp[9];
    xSemaphoreGive(state_mutex);
    Serial.printf("[EXT] 0x%02X type=%u rev=%u fw=v%u.%u.%u\n",
                  addr, resp[5], resp[6], resp[7], resp[8], resp[9]);
    notify_ui();
}

/* Wipe everything learned about whatever used to occupy a slot.
 * Identity is a property of the device, not the slot: if a different
 * extension is paired into a slot, a stale hw_type/fw_ver would make the
 * master believe the newcomer is already up to date and it would never be
 * offered an update. A stale ota_fails would blacklist it outright. */
static void ext_reset_identity(extension_t *e) {
    /* Every caller means "this slot now holds a different board, or none":
     * fresh adoption, slot replace, NVS restore, removal, boot init. A board
     * with no history is present from the moment it answers -- the settle
     * window is for a *return*, not a first appearance. */
    e->settle_until_ms = 0;
    e->last_drop_ms    = 0;
    e->drops           = 0;
    e->hw_type = 0;
    e->hw_rev  = 0;
    e->fw_ver[0] = e->fw_ver[1] = e->fw_ver[2] = 0;
    e->ota_fails = 0;
    e->ota_fail_ver[0] = e->ota_fail_ver[1] = e->ota_fail_ver[2] = 0;
    e->ota_next_try_ms = 0;
}

static void poll_extension(int i) {
    xSemaphoreTake(state_mutex,portMAX_DELAY);
    if (extensions[i].state==EXT_EMPTY) { xSemaphoreGive(state_mutex); return; }
    uint8_t addr=extensions[i].address;
    if (addr==ADDR_UNASSIGNED) { xSemaphoreGive(state_mutex); return; }
    xSemaphoreGive(state_mutex);

    uint8_t resp[40]; uint8_t resp_len,plen;
    /* Check grace period - skip poll if extension was just welcomed */
    xSemaphoreTake(state_mutex,portMAX_DELAY);
    if (extensions[i].last_seen_ms > millis()) {
        xSemaphoreGive(state_mutex); return;
    }
    xSemaphoreGive(state_mutex);

    flush_rx();
    bus_send(addr,CMD_GET_STATE,NULL,0);
    resp_len=bus_recv(resp,sizeof(resp),BUS_RESP_MS);

    xSemaphoreTake(state_mutex,portMAX_DELAY);
    if (resp_len==0) {
        extensions[i].missed++;
        if (extensions[i].missed>=MISSED_MAX&&extensions[i].state==EXT_ONLINE) {
            extensions[i].state=EXT_OFFLINE;
            presence_note_drop(&extensions[i].settle_until_ms,
                               &extensions[i].last_drop_ms,
                               &extensions[i].drops, millis());
            Serial.printf("[OFFLINE] %s\n",extensions[i].name);
            xSemaphoreGive(state_mutex); notify_ui(); return;
        }
        xSemaphoreGive(state_mutex); return;
    }

    plen=resp[4];
    if (resp[5+plen]!=crc8(&resp[1],4+plen)||resp[2]!=addr) {
        extensions[i].missed++;
        xSemaphoreGive(state_mutex); return;
    }

    bool was_first_poll=!extensions[i].polled_once;
    /* Coming back from OFFLINE may mean it rebooted into new firmware,
     * so drop the cached identity and re-learn it. */
    if (extensions[i].state==EXT_OFFLINE) extensions[i].hw_type=0;
    extensions[i].missed=0;
    extensions[i].last_seen_ms=millis();
    extensions[i].polled_once=true;
    bool was_offline=(extensions[i].state==EXT_OFFLINE);
    bool was_settling=(extensions[i].settle_until_ms!=0);
    if (was_offline) {
        extensions[i].state=EXT_ONLINE;
        /* Back on the bus, but its switches stay off the dashboard until it
         * has been solid for a minute. */
        presence_note_return(&extensions[i].settle_until_ms,
                             extensions[i].last_drop_ms, millis());
    } else {
        presence_tick_up(&extensions[i].settle_until_ms,
                         &extensions[i].last_drop_ms,
                         &extensions[i].drops, millis());
    }
    /* The settle window expiring is a visible event -- it is what puts the
     * switches back on the dashboard -- so it has to push, not wait for the
     * next unrelated change. */
    bool settled_now=(was_settling && extensions[i].settle_until_ms==0);

    bool changed=was_offline||settled_now;
    if (resp[3]==CMD_STATE_RESP&&resp[4]>=3) {
        uint8_t flags=resp[5],evts=resp[7];
        bool r1=(flags>>0)&0x01, r2=(flags>>1)&0x01;
        if (was_first_poll) {
            /* First successful poll -- a registered extension boots with
             * both relays off. Only restore-enabled channels carry a saved
             * ON here (apply_restore_policy zeroed the rest), so this push can
             * only ever go off -> on, and a board whose channels are all
             * "start off" is never written to at all.
             *
             * One frame per channel, spaced by the restore stagger, so a
             * whole house coming back doesn't close every relay at once. */
            bool want_r1=extensions[i].relay1;
            bool want_r2=extensions[i].relay2;
            if (want_r1!=r1 || want_r2!=r2) {
                xSemaphoreGive(state_mutex);
                /* Walk the board to the wanted state one channel at a time,
                 * leaving the other channel where it is, so each closing
                 * relay is separated by the stagger interval. A channel that
                 * already matches costs no frame at all -- which is the
                 * common case for "always start off", since the board boots
                 * off and apply_restore_policy zeroed its wanted state. */
                if (want_r1!=r1) {
                    uint8_t mask=(want_r1?0x01:0x00)|(r2?0x02:0x00);
                    restore_stagger();
                    bus_send(addr, CMD_SET_RELAY, &mask, 1);
                    bus_recv(resp, sizeof(resp), BUS_RESP_MS);
                }
                if (want_r2!=r2) {
                    uint8_t mask=(want_r1?0x01:0x00)|(want_r2?0x02:0x00);
                    restore_stagger();
                    bus_send(addr, CMD_SET_RELAY, &mask, 1);
                    bus_recv(resp, sizeof(resp), BUS_RESP_MS);
                }
                xSemaphoreTake(state_mutex, portMAX_DELAY);
                extensions[i].relay1=want_r1;
                extensions[i].relay2=want_r2;
                Serial.printf("[RELAY] Restored ext%d: CH1=%s CH2=%s\n",
                              i, want_r1?"ON":"OFF", want_r2?"ON":"OFF");
            }
            changed=true;
        } else if (r1!=extensions[i].relay1||r2!=extensions[i].relay2) {
            extensions[i].relay1=r1; extensions[i].relay2=r2; changed=true;
            /* Persist updated extension relay state to master NVS */
            xSemaphoreGive(state_mutex);
            relay_state_save();
            xSemaphoreTake(state_mutex,portMAX_DELAY);
        }
        if (evts>0) {
            uint8_t drain[1]={evts};
            xSemaphoreGive(state_mutex);
            bus_send(addr,CMD_DRAIN_EVENTS,drain,1);
            if (changed) notify_ui();
            if (was_offline) Serial.printf("[ONLINE] %s\n",extensions[i].name);
            return;
        }
    }
    xSemaphoreGive(state_mutex);
    if (changed) notify_ui();
    if (was_offline) Serial.printf("[ONLINE] %s\n",extensions[i].name);
}

/* ================================================================
 * CHECK BOOT COMPLETE
 * ================================================================ */
static uint32_t boot_start_ms = 0;

static void check_boot_complete(void) {
    if (boot_complete) return;
    bool all_polled=true;
    xSemaphoreTake(state_mutex,portMAX_DELAY);
    for (int i=0;i<MAX_EXTENSIONS;i++) {
        if (extensions[i].state==EXT_EMPTY) continue;
        if (!extensions[i].polled_once) { all_polled=false; break; }
    }
    xSemaphoreGive(state_mutex);
    /* Complete if all polled OR 5 second timeout reached */
    if (all_polled || (millis()-boot_start_ms)>5000) {
        boot_complete=true;
        Serial.println("[BOOT] Boot complete - overlay dismissed");
        notify_ui();
    }
}

/* ================================================================
 * TASK: TOUCH (priority 3)
 * ================================================================ */
static void task_touch(void *arg) {
    bool last_t1=false, last_t2=false;
    for (;;) {
        bool t1=digitalRead(TOUCH1_PIN);
        bool t2=digitalRead(TOUCH2_PIN);
        if (t1&&!last_t1) {
            xSemaphoreTake(state_mutex,portMAX_DELAY);
            master_relay1=!master_relay1; bool s=master_relay1;
            xSemaphoreGive(state_mutex);
            digitalWrite(RELAY1_PIN,s?LOW:HIGH); /* active LOW */
            relay_state_save();
            Serial.printf("[TOUCH] CH1 -> %s\n",s?"ON":"OFF");
            notify_ui();
        }
        if (t2&&!last_t2) {
            xSemaphoreTake(state_mutex,portMAX_DELAY);
            master_relay2=!master_relay2; bool s=master_relay2;
            xSemaphoreGive(state_mutex);
            digitalWrite(RELAY2_PIN,s?LOW:HIGH); /* active LOW */
            relay_state_save();
            Serial.printf("[TOUCH] CH2 -> %s\n",s?"ON":"OFF");
            notify_ui();
        }
        last_t1=t1; last_t2=t2;

        relay_cmd_t cmd;
        while (xQueueReceive(master_relay_queue,&cmd,0)==pdTRUE) {
            xSemaphoreTake(state_mutex,portMAX_DELAY);
            if (cmd.channel==1) master_relay1=cmd.state;
            else                master_relay2=cmd.state;
            xSemaphoreGive(state_mutex);
            digitalWrite(cmd.channel==1?RELAY1_PIN:RELAY2_PIN,cmd.state?LOW:HIGH);
            relay_state_save(); notify_ui();
        }
        vTaskDelay(pdMS_TO_TICKS(20));
    }
}

/* ================================================================
 * TASK: BUS (priority 2)
 * ================================================================ */
static void task_bus(void *arg) {
    uint32_t last_poll=0, last_listen=0;

    /* Boot grace period - 2s before marking anything OFFLINE */
    vTaskDelay(pdMS_TO_TICKS(500));

    for (;;) {
        uint32_t now=millis();

        /* Immediate extension relay commands -- skip during OTA */
        relay_cmd_t cmd;
        if (!ota_in_progress)
        while (xQueueReceive(ext_relay_queue,&cmd,0)==pdTRUE) {
            if (cmd.target>=0&&cmd.target<MAX_EXTENSIONS) {
                xSemaphoreTake(state_mutex,portMAX_DELAY);
                if (extensions[cmd.target].state==EXT_ONLINE) {
                    uint8_t addr=extensions[cmd.target].address;
                    bool r1=extensions[cmd.target].relay1;
                    bool r2=extensions[cmd.target].relay2;
                    if (cmd.channel==1) r1=cmd.state;
                    else                r2=cmd.state;
                    extensions[cmd.target].relay1=r1;
                    extensions[cmd.target].relay2=r2;
                    uint8_t mask=(r1?0x01:0)|(r2?0x02:0);
                    xSemaphoreGive(state_mutex);
                    uint8_t payload[1]={mask};
                    /* Send immediately - don't wait for poll */
                    flush_rx();
                    bus_send(addr,CMD_SET_RELAY,payload,1);
                    uint8_t resp[40];
                    bus_recv(resp,sizeof(resp),BUS_RESP_MS);
                    notify_ui();
                } else { xSemaphoreGive(state_mutex); }
            }
        }

        relay_state_tick();   /* commit any debounced relay-state write */

        /* Poll registered extensions -- skip during OTA */
        if ((now-last_poll)>=POLL_MS) {
            last_poll=now;
            if (!ota_in_progress) {
                for (int i=0;i<MAX_EXTENSIONS;i++) {
                    poll_extension(i);
                    ext_query_info(i);
                }
                check_boot_complete();
            }
        }

        /* Listen window for ANNOUNCE frames -- skip during OTA */
        if (!ota_in_progress && (now-last_listen)>=LISTEN_INTERVAL_MS) {
            last_listen=now;
            /* Process any pending relay commands before blocking on listen */
            relay_cmd_t pre_cmd;
            while (xQueueReceive(ext_relay_queue,&pre_cmd,0)==pdTRUE) {
                if (pre_cmd.target>=0&&pre_cmd.target<MAX_EXTENSIONS) {
                    xSemaphoreTake(state_mutex,portMAX_DELAY);
                    if (extensions[pre_cmd.target].state==EXT_ONLINE) {
                        uint8_t addr=extensions[pre_cmd.target].address;
                        bool r1=extensions[pre_cmd.target].relay1;
                        bool r2=extensions[pre_cmd.target].relay2;
                        if (pre_cmd.channel==1) r1=pre_cmd.state;
                        else                    r2=pre_cmd.state;
                        extensions[pre_cmd.target].relay1=r1;
                        extensions[pre_cmd.target].relay2=r2;
                        uint8_t mask=(r1?0x01:0)|(r2?0x02:0);
                        xSemaphoreGive(state_mutex);
                        uint8_t payload[1]={mask};
                        flush_rx();
                        bus_send(addr,CMD_SET_RELAY,payload,1);
                        uint8_t resp[40];
                        bus_recv(resp,sizeof(resp),BUS_RESP_MS);
                        notify_ui();
                    } else { xSemaphoreGive(state_mutex); }
                }
            }
            run_listen_window();

            /* Also run during active scan */
            if (scan_active&&millis()<scan_end_ms) {
                run_listen_window();
            } else if (scan_active&&millis()>=scan_end_ms) {
                scan_active=false;
                if (pending_count()>0) notify_ui();
            }
        }

        /* Firmware: keep a stalled mesh transfer moving, then converge
         * extensions toward the manifest. Never while an OTA is running. */
        fw_mesh_tick();
        if (!ota_in_progress && (now - last_reconcile) >= RECONCILE_MS) {
            last_reconcile = now;
            fw_reconcile();
        }

        /* BLE requests are assembled on the BLE task but executed here:
         * relay queues, NVS writes and JSON building do not belong on
         * that stack. */
        if (ble_req_ready) {
            ble_req_ready = false;
            ble_handle_request(ble_req_buf);
        }

        /* Reclaim BLE slots held by squatters or stale clients. */
        static uint32_t last_reap = 0;
        if (millis() - last_reap >= 2000) { last_reap = millis(); ble_reap_connections(); }

        reset_button_tick();
        ble_recovery_apply();

        /* Apply a deferred credential change once the HTTP reply has gone
         * out. Doing it inline would cut the connection before the caller
         * could read the result. */
        if (ap_change_pending && (int32_t)(millis() - ap_change_at_ms) >= 0) {
            ap_change_pending = false;
            const char *ssid = mesh_active ? mesh_name : unique_ssid;
            Serial.printf("[AUTH] restarting AP %s with new password\n", ssid);
            WiFi.softAPdisconnect(true);
            vTaskDelay(pdMS_TO_TICKS(100));
            WiFi.softAP(ssid, active_pass(), AP_CHANNEL);
        }

        /* Expire old pending and stale challenges */
        xSemaphoreTake(state_mutex,portMAX_DELAY);
        for (int i=0;i<MAX_PENDING;i++) {
            if (pending_queue[i].active&&
                (millis()-pending_queue[i].first_seen_ms)>300000)
                pending_queue[i].active=false;
        }
        for (int i=0;i<MAX_CHALLENGES;i++) {
            if (challenges[i].active&&
                (millis()-challenges[i].sent_ms)>5000)
                challenges[i].active=false;
        }
        xSemaphoreGive(state_mutex);

        /* Mesh gossip and peer timeout check */
        if (mesh_active && (millis()-last_gossip_ms)>=MESH_GOSSIP_MS) {
            last_gossip_ms = millis();
            mesh_gossip();
            mesh_check_timeouts();
        }

        /* Apply deferred WiFi AP reconfiguration from mesh_recv_cb.
         * softAP must NOT be called from ESP-NOW callback context --
         * doing so causes partial AP state and ghost SSIDs. */
        if (mesh_cfg_pending) {
            mesh_cfg_pending = false;
            WiFi.softAPdisconnect(true);
            delay(100);
            WiFi.softAP(mesh_cfg_pending_name, mesh_cfg_pending_pass, AP_CHANNEL);
            Serial.printf("[WIFI] AP reconfigured (deferred): %s\n",
                          mesh_cfg_pending_name);
            notify_ui();
        }

        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

/* ================================================================
 * STATE JSON
 * ================================================================ */
/* Build ordered list of switch IDs */
static String build_default_order(void) {
    String order = "";
    /* master first */
    order += "master_1,master_2";
    for (int i=0;i<MAX_EXTENSIONS;i++) {
        if (extensions[i].state==EXT_EMPTY) continue;
        char id1[16],id2[16];
        snprintf(id1,sizeof(id1),"ext%d_1",i);
        snprintf(id2,sizeof(id2),"ext%d_2",i);
        order += ","; order += id1;
        order += ","; order += id2;
    }
    return order;
}

static String build_state_json(void) {
    /* Snapshot all state under mutex first */
    xSemaphoreTake(state_mutex,portMAX_DELAY);
    bool       snap_boot     = boot_complete;
    bool       snap_scan     = scan_active;
    bool       snap_r1       = master_relay1;
    bool       snap_r2       = master_relay2;
    char       snap_mname[24]; strncpy(snap_mname, master_name, sizeof(snap_mname)-1); snap_mname[23]='\0';
    String     snap_order    = switch_order;
    extension_t snap_ext[MAX_EXTENSIONS];
    memcpy(snap_ext, extensions, sizeof(extensions));
    pending_ext_t snap_pend[MAX_PENDING];
    memcpy(snap_pend, pending_queue, sizeof(pending_queue));
    xSemaphoreGive(state_mutex);

    /* Now build JSON without holding mutex */
    /* Heap, not stack. task_web is created with an 8192-byte stack and this
     * function already parks a 6 KB document plus a full extension snapshot
     * on it -- there was almost nothing left, and the presence fields added
     * below would have tipped it over. */
    DynamicJsonDocument doc(8192);
    uint32_t now_ms = millis();
    doc["uptime"]=millis()/1000;
    doc["boot_complete"]=snap_boot;
    doc["master_name"]=snap_mname;
    doc["scan_active"]=snap_scan;

    /* Build effective order using snapshot */
    String effective_order;
    if (snap_order.length()>0) {
        effective_order = snap_order;
    } else {
        effective_order = "master_1,master_2";
        for(int i=0;i<MAX_EXTENSIONS;i++) {
            if(snap_ext[i].state==EXT_EMPTY) continue;
            char id1[16],id2[16];
            snprintf(id1,sizeof(id1),"ext%d_1",i);
            snprintf(id2,sizeof(id2),"ext%d_2",i);
            effective_order+=","; effective_order+=id1;
            effective_order+=","; effective_order+=id2;
        }
    }

    /* Build switch lookup map */
    /* Master switches */
    char sw_name[24];
    char sw_id[16];

    JsonArray switches=doc.createNestedArray("switches");

    /* Parse order and emit switches in order */
    String ord = effective_order;
    int start=0;
    while(start<(int)ord.length()) {
        int comma=ord.indexOf(',',start);
        String id=(comma<0)?ord.substring(start):ord.substring(start,comma);
        start=(comma<0)?ord.length():comma+1;
        if(id.length()==0) continue;

        JsonObject sw=switches.createNestedObject();
        sw["id"]=id;

        if(id.startsWith("master_")) {
            int ch=id.substring(7).toInt();
            nvs_load_switch_name(id.c_str(),sw_name,sizeof(sw_name));
            if(String(sw_name)=="Switch") {
                snprintf(sw_name,sizeof(sw_name),"Switch %d",ch);
            }
            sw["name"]=sw_name;
            sw["color"]=SLOT_COLORS[0];
            sw["channel"]=ch;
            sw["state"]=(ch==1)?snap_r1:snap_r2;
            sw["online"]=true;
            /* Per-switch restore policy travels in the state stream so every
             * connected phone updates together (story Epic 2). */
            sw["restore"]=nvs_load_restore(id.c_str());
        } else if(id.startsWith("ext")) {
            /* parse extN_ch */
            int us=id.indexOf('_');
            if(us<0) continue;
            int slot=id.substring(3,us).toInt();
            int ch=id.substring(us+1).toInt();
            if(slot<0||slot>=MAX_EXTENSIONS) continue;
            if(extensions[slot].state==EXT_EMPTY) continue;
            nvs_load_switch_name(id.c_str(),sw_name,sizeof(sw_name));
            if(String(sw_name)=="Switch") {
                snprintf(sw_name,sizeof(sw_name),"Switch %d",ch+(slot*2)+2);
            }
            sw["name"]=sw_name;
            sw["color"]=SLOT_COLORS[slot+1<6?slot+1:5];
            sw["channel"]=ch;
            sw["state"]=(ch==1)?snap_ext[slot].relay1:snap_ext[slot].relay2;
            sw["online"]=(ext_presence(&snap_ext[slot],now_ms)==PRES_ONLINE);
            sw["restore"]=nvs_load_restore(id.c_str());
        }
    }

    /* Add any switches not yet in order (new extensions) -- use snapshot */
    for(int i=0;i<MAX_EXTENSIONS;i++) {
        if(snap_ext[i].state==EXT_EMPTY) continue;
        for(int ch=1;ch<=2;ch++) {
            snprintf(sw_id,sizeof(sw_id),"ext%d_%d",i,ch);
            if(effective_order.indexOf(sw_id)<0) {
                JsonObject sw=switches.createNestedObject();
                sw["id"]=sw_id;
                /* nvs_load_switch_name reads flash -- safe without mutex
                 * since we use snap_ext for state, not live extensions[] */
                nvs_load_switch_name(sw_id,sw_name,sizeof(sw_name));
                if(String(sw_name)=="Switch") {
                    snprintf(sw_name,sizeof(sw_name),"Switch %d",ch+(i*2)+2);
                }
                sw["name"]=sw_name;
                sw["device_name"]=snap_mname;
                sw["color"]=SLOT_COLORS[i+1<6?i+1:5];
                sw["channel"]=ch;
                sw["state"]=(ch==1)?snap_ext[i].relay1:snap_ext[i].relay2;
                sw["online"]=(ext_presence(&snap_ext[i],now_ms)==PRES_ONLINE);
                sw["restore"]=nvs_load_restore(sw_id);
            }
        }
    }

    /* Pending queue */
    JsonArray pending=doc.createNestedArray("pending");
    for(int i=0;i<MAX_PENDING;i++) {
        if(!snap_pend[i].active) continue;
        JsonObject p=pending.createNestedObject();
        char uid_str[12];
        snprintf(uid_str,sizeof(uid_str),"%02X%02X%02X%02X",
                 snap_pend[i].uid[0],snap_pend[i].uid[1],
                 snap_pend[i].uid[2],snap_pend[i].uid[3]);
        p["uid"]=uid_str;
    }

    /* Extension presence travels in the state stream, not just in the
     * /api/extensions poll: the story requires apps to learn presence from
     * the master rather than infer it from their own failures, and the
     * extension list has to show offline/intermittent + last-seen the moment
     * it changes. `last_seen` is seconds ago -- the master has no clock. */
    JsonArray exts=doc.createNestedArray("extensions");
    for(int i=0;i<MAX_EXTENSIONS;i++) {
        if(snap_ext[i].state==EXT_EMPTY) continue;
        JsonObject ex=exts.createNestedObject();
        presence_t pr=ext_presence(&snap_ext[i],now_ms);
        ex["slot"]=i;
        ex["name"]=snap_ext[i].name;
        ex["online"]=(pr==PRES_ONLINE);
        ex["presence"]=presence_str(pr);
        ex["last_seen"]=seconds_since(snap_ext[i].last_seen_ms,now_ms);
    }

    /* Offline slots for replace option */
    JsonArray offline_slots=doc.createNestedArray("offline_slots");
    for(int i=0;i<MAX_EXTENSIONS;i++) {
        if(snap_ext[i].state!=EXT_OFFLINE) continue;
        JsonObject os=offline_slots.createNestedObject();
        os["slot"]=i;
        os["name"]=("Slot "+String(i+1));
    }

    /* Mesh peers */
    doc["mesh_active"]  = mesh_active;
    doc["mesh_name"]   = mesh_name;
    doc["master_order"] = master_order_str;
    char self_uid_str[12];
    snprintf(self_uid_str,sizeof(self_uid_str),"%02X%02X%02X%02X",
             master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
    doc["self_uid"] = self_uid_str;

    JsonArray peers = doc.createNestedArray("mesh_peers");
    xSemaphoreTake(state_mutex, portMAX_DELAY);
    for (int i=0;i<MAX_MESH_MASTERS;i++) {
        bool has_uid=false;
        for(int k=0;k<4;k++) if(mesh_peers[i].uid[k]) {has_uid=true;break;}
        if (!has_uid) continue;
        JsonObject p = peers.createNestedObject();
        char puid[12];
        snprintf(puid,sizeof(puid),"%02X%02X%02X%02X",
                 mesh_peers[i].uid[0],mesh_peers[i].uid[1],
                 mesh_peers[i].uid[2],mesh_peers[i].uid[3]);
        presence_t ppr = peer_presence(&mesh_peers[i], now_ms);
        p["uid"]       = puid;
        p["name"]      = mesh_peers[i].name;
        /* Same debounce as extensions, so a master card doesn't flap. */
        p["online"]    = (ppr == PRES_ONLINE);
        p["presence"]  = presence_str(ppr);
        p["last_seen"] = seconds_since(mesh_peers[i].last_seen_ms, now_ms);
        JsonArray psw = p.createNestedArray("switches");
        for (int j=0;j<mesh_peers[i].switch_count;j++) {
            /* A window packet can be lost mid-sweep, leaving a slot the
             * peer has announced but not yet described. Don't render it. */
            if (!mesh_peers[i].switches[j].id[0]) continue;
            JsonObject s = psw.createNestedObject();
            s["id"]     = mesh_peers[i].switches[j].id;
            s["name"]   = mesh_peers[i].switches[j].name;
            s["color"]  = mesh_peers[i].switches[j].color;
            s["state"]  = mesh_peers[i].switches[j].state;
            s["online"] = mesh_peers[i].switches[j].online;
            s["restore"] = mesh_peers[i].switches[j].restore;
            s["ch"]     = mesh_peers[i].switches[j].ch;
        }
    }
    xSemaphoreGive(state_mutex);

    String out; serializeJson(doc,out); return out;
}

/* ================================================================
 * TASK: WEB (priority 1)
 * ================================================================ */
static void task_web(void *arg) {
    for (;;) {
        server.handleClient();
        wss.loop();
        static uint32_t last_ble_push  = 0;
        static bool     ble_state_dirty = false;

        uint8_t sig;
        if (xQueueReceive(ws_notify_queue,&sig,0)==pdTRUE) {
            while (xQueueReceive(ws_notify_queue,&sig,0)==pdTRUE);
            String json=build_state_json();
            wss.broadcastTXT(json);
            /* Mark the BLE client as needing an update rather than pushing
             * immediately. A full state document is several chunks, so one
             * push per relay toggle saturates the link. */
            ble_state_dirty = true;
        }

        /* Send the pending update as soon as the rate window allows.
         * Rate limiting must DEFER, never DISCARD -- dropping the push
         * left the app showing stale state until some later change
         * happened to fall outside the window. */
        if (ble_connected && ble_state_dirty &&
            (millis() - last_ble_push) >= BLE_STATE_MIN_MS) {
            ble_state_dirty = false;
            last_ble_push   = millis();
            ble_notify_chunked(ble_state_char, build_state_json());
        }

        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

/* The served web UI has been removed. The Flutter app is the only client,
 * and every endpoint below returns JSON. This reclaimed roughly 70 KB of
 * source plus the page handlers and their string tables. */

/* ================================================================
 * WEB ROUTES
 * ================================================================ */
/* Send a CONFIG command -- to all peers if target_uid is empty, else direct */
static void mesh_send_config(const char *cmd, const char *target_uid,
                              const char *name, const char *order, int slot) {
    StaticJsonDocument<256> doc;
    char self_uid[12];
    snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
             master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
    doc["type"]       = MESH_PKT_CONFIG;
    doc["uid"]        = self_uid;
    doc["cmd"]        = cmd;
    doc["target_uid"] = target_uid ? target_uid : "";
    doc["name"]       = name  ? name  : "";
    doc["order"]      = order ? order : "";
    doc["slot"]       = slot;
    String payload; serializeJson(doc, payload);
    if (target_uid && strlen(target_uid) > 0) {
        /* Send directly to target peer */
        uint8_t peer_uid[4];
        for (int i=0;i<4;i++) {
            char b[3]={target_uid[i*2],target_uid[i*2+1],0};
            peer_uid[i]=(uint8_t)strtoul(b,NULL,16);
        }
        int idx = mesh_find_peer(peer_uid);
        if (idx >= 0)
            mesh_send(mesh_peers[idx].mac, payload.c_str(), payload.length()+1);
    } else {
        /* Broadcast to all peers */
        mesh_broadcast(payload.c_str(), payload.length()+1);
    }
}

static void setup_web(void) {
    /* Relay toggle - immediate, with rate limiting */
    /* Kill all switches on this master */
    server.on("/api/relay/killall", HTTP_POST, [](){
        if (!auth_ok()) return;
        /* Update master relay state immediately under mutex so
         * notify_ui() snapshot reflects the new OFF state */
        xSemaphoreTake(state_mutex,portMAX_DELAY);
        master_relay1 = false;
        master_relay2 = false;
        /* Turn off all registered extension relays */
        for (int i=0;i<MAX_EXTENSIONS;i++) {
            if (extensions[i].state==EXT_EMPTY) continue;
            extensions[i].relay1 = false;
            extensions[i].relay2 = false;
            relay_cmd_t ec1; ec1.target=i; ec1.channel=1; ec1.state=false;
            relay_cmd_t ec2; ec2.target=i; ec2.channel=2; ec2.state=false;
            xQueueSend(ext_relay_queue,&ec1,0);
            xQueueSend(ext_relay_queue,&ec2,0);
        }
        xSemaphoreGive(state_mutex);
        /* Queue GPIO relay commands for master relays */
        relay_cmd_t cmd1; cmd1.target=-1; cmd1.channel=1; cmd1.state=false;
        relay_cmd_t cmd2; cmd2.target=-1; cmd2.channel=2; cmd2.state=false;
        xQueueSend(master_relay_queue,&cmd1,0);
        xQueueSend(master_relay_queue,&cmd2,0);
        /* One command, the whole house. */
        mesh_killall_peers();
        notify_ui();
        relay_state_save_now(); /* persist all-off state */
        Serial.println("[RELAY] Kill all");
        server.send(200,"application/json","{\"ok\":true}");
    });

    server.on("/api/relay", HTTP_POST, [](){
        if (!auth_ok()) return;
        String id=server.arg("id");
        int ch=server.arg("ch").toInt();
        uint32_t now=millis();

        /* id format: "master_1" or "master_2" */
        if (id.startsWith("master")&&(ch==1||ch==2)) {
            relay_cmd_t cmd; cmd.target=-1; cmd.channel=ch;
            String stateArg=server.arg("state");
            xSemaphoreTake(state_mutex,portMAX_DELAY);
            if (stateArg=="0")      cmd.state=false;
            else if (stateArg=="1") cmd.state=true;
            else cmd.state=(ch==1)?!master_relay1:!master_relay2; /* toggle if no state arg */
            xSemaphoreGive(state_mutex);
            xQueueSend(master_relay_queue,&cmd,0);
            server.send(200,"application/json","{\"ok\":true}"); return;
        }
        if (id.startsWith("ext")) {
            /* id: "ext0_1" -> slot=0, ch parsed from arg */
            int us=id.indexOf('_'); 
            int slot=(us>0)?id.substring(3,us).toInt():id.substring(3).toInt();
            if (slot>=0&&slot<MAX_EXTENSIONS) {
                relay_cmd_t cmd; cmd.target=slot; cmd.channel=ch;
                String extSt=server.arg("state");
                xSemaphoreTake(state_mutex,portMAX_DELAY);
                if (extSt=="0")      cmd.state=false;
                else if (extSt=="1") cmd.state=true;
                else cmd.state=(ch==1)?!extensions[slot].relay1:!extensions[slot].relay2;
                /* Update in-memory state before persisting */
                if (ch==1) extensions[slot].relay1=cmd.state;
                else       extensions[slot].relay2=cmd.state;
                xSemaphoreGive(state_mutex);
                xQueueSend(ext_relay_queue,&cmd,0);
                relay_state_save(); /* persist to NVS */
                server.send(200,"application/json","{\"ok\":true}"); return;
            }
        }
        server.send(404,"application/json","{\"ok\":false}");
    });

    /* Assign new extension */
    server.on("/api/assign", HTTP_POST, [](){
        if (!auth_ok()) return;
        String uid_str=server.arg("uid");
        String name=server.arg("name");
        if (name.length()==0) name="Switch";
        uint8_t uid[4];
        uid[0]=strtoul(uid_str.substring(0,2).c_str(),NULL,16);
        uid[1]=strtoul(uid_str.substring(2,4).c_str(),NULL,16);
        uid[2]=strtoul(uid_str.substring(4,6).c_str(),NULL,16);
        uid[3]=strtoul(uid_str.substring(6,8).c_str(),NULL,16);

        xSemaphoreTake(state_mutex,portMAX_DELAY);
        int slot=find_empty_slot();
        if (slot<0) { xSemaphoreGive(state_mutex);
            server.send(400,"application/json","{\"error\":\"no slots\"}"); return; }
        uint8_t new_addr=next_free_addr();
        extension_t *e=&extensions[slot];
        memcpy(e->uid,uid,4);
        ext_reset_identity(e);
        e->address=new_addr; e->state=EXT_ONLINE; e->missed=0;
        e->relay1=false; e->relay2=false;
        e->last_seen_ms=millis(); e->polled_once=true;
        strncpy(e->name,name.c_str(),sizeof(e->name)-1);
        e->name[sizeof(e->name)-1]='\0';
        pending_remove(uid);
        xSemaphoreGive(state_mutex);

        nvs_save(uid,slot,"Switch");
        send_welcome(uid,new_addr,false,false);
        /* Grace period: 1s before polling so extension can save EEPROM */
        xSemaphoreTake(state_mutex,portMAX_DELAY);
        extensions[slot].last_seen_ms = millis() + 1000;
        extensions[slot].missed = 0;
        xSemaphoreGive(state_mutex);
        Serial.printf("[ASSIGN] slot%d addr=0x%02X\n", slot+1, new_addr);
        notify_ui();
        String resp="{\"ok\":true,\"slot\":"+String(slot)+"}";
        server.send(200,"application/json",resp);
    });

    /* Replace offline slot */
    server.on("/api/replace", HTTP_POST, [](){
        if (!auth_ok()) return;
        String uid_str=server.arg("uid");
        int slot=server.arg("slot").toInt();
        String name=server.arg("name");
        if (slot<0||slot>=MAX_EXTENSIONS) {
            server.send(400,"application/json","{\"error\":\"bad slot\"}"); return; }

        uint8_t new_uid[4];
        new_uid[0]=strtoul(uid_str.substring(0,2).c_str(),NULL,16);
        new_uid[1]=strtoul(uid_str.substring(2,4).c_str(),NULL,16);
        new_uid[2]=strtoul(uid_str.substring(4,6).c_str(),NULL,16);
        new_uid[3]=strtoul(uid_str.substring(6,8).c_str(),NULL,16);

        xSemaphoreTake(state_mutex,portMAX_DELAY);
        if (extensions[slot].state!=EXT_OFFLINE) {
            xSemaphoreGive(state_mutex);
            server.send(400,"application/json","{\"ok\":false}"); return; }
        uint8_t old_uid[4]; memcpy(old_uid,extensions[slot].uid,4);
        uint8_t new_addr=(uint8_t)(slot+1);
        extension_t *e=&extensions[slot];
        memcpy(e->uid,new_uid,4);
        ext_reset_identity(e);
        e->address=new_addr; e->state=EXT_ONLINE; e->missed=0;
        e->relay1=false; e->relay2=false;
        e->last_seen_ms=millis(); e->polled_once=true;
        if (name.length()>0) {
            strncpy(e->name,name.c_str(),sizeof(e->name)-1);
            e->name[sizeof(e->name)-1]='\0';
        }
        char slot_name[24]; strncpy(slot_name,e->name,sizeof(slot_name)-1); slot_name[23]='\0';
        pending_remove(new_uid);
        xSemaphoreGive(state_mutex);

        nvs_remove(old_uid);
        nvs_save(new_uid,slot,slot_name);
        welcome_cmd_t wcmd2;
        memcpy(wcmd2.uid,new_uid,4);
        wcmd2.addr=new_addr; wcmd2.relay1=false; wcmd2.relay2=false;
        xQueueSend(welcome_queue,&wcmd2,0);
        Serial.printf("[REPLACE] slot%d: %s\n",slot+1,slot_name);
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Reject/ignore pending extension */
    server.on("/api/reject", HTTP_POST, [](){
        if (!auth_ok()) return;
        String uid_str=server.arg("uid");
        uint8_t uid[4];
        uid[0]=strtoul(uid_str.substring(0,2).c_str(),NULL,16);
        uid[1]=strtoul(uid_str.substring(2,4).c_str(),NULL,16);
        uid[2]=strtoul(uid_str.substring(4,6).c_str(),NULL,16);
        uid[3]=strtoul(uid_str.substring(6,8).c_str(),NULL,16);
        xSemaphoreTake(state_mutex,portMAX_DELAY);
        pending_remove(uid);
        xSemaphoreGive(state_mutex);
        send_reject(uid);
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Rename extension */
    server.on("/api/rename", HTTP_POST, [](){
        if (!auth_ok()) return;
        int slot=server.arg("slot").toInt();
        String name=server.arg("name");
        if (slot<0||slot>=MAX_EXTENSIONS||name.length()==0) {
            server.send(400,"application/json","{\"ok\":false}"); return; }
        xSemaphoreTake(state_mutex,portMAX_DELAY);
        if (extensions[slot].state==EXT_EMPTY) {
            xSemaphoreGive(state_mutex);
            server.send(400,"application/json","{\"ok\":false}"); return; }
        strncpy(extensions[slot].name,name.c_str(),sizeof(extensions[slot].name)-1);
        extensions[slot].name[sizeof(extensions[slot].name)-1]='\0';
        uint8_t uid[4]; memcpy(uid,extensions[slot].uid,4);
        xSemaphoreGive(state_mutex);
        nvs_save(uid,slot,name.c_str());
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Remove extension */
    server.on("/api/remove", HTTP_POST, [](){
        if (!auth_ok()) return;
        int slot=server.arg("slot").toInt();
        if (slot<0||slot>=MAX_EXTENSIONS) {
            server.send(400,"application/json","{\"error\":\"bad slot\"}"); return; }
        xSemaphoreTake(state_mutex,portMAX_DELAY);
        if (extensions[slot].state==EXT_EMPTY) {
            xSemaphoreGive(state_mutex);
            server.send(400,"application/json","{\"ok\":false}"); return; }
        uint8_t uid[4]; memcpy(uid,extensions[slot].uid,4);
        extensions[slot].state=EXT_EMPTY;
        extensions[slot].address=ADDR_UNASSIGNED;
        memset(extensions[slot].uid,0,4);
        ext_reset_identity(&extensions[slot]);
        xSemaphoreGive(state_mutex);
        nvs_remove(uid);
        nvs_forget_slot(slot);
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Rename individual switch */
    server.on("/api/switch/rename", HTTP_POST, [](){
        if (!auth_ok()) return;
        String id   = server.arg("id");
        String name = server.arg("name");
        if (id.length()==0||name.length()==0) {
            server.send(400,"application/json","{\"ok\":false}"); return; }
        nvs_save_switch_name(id.c_str(), name.c_str());
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Per-switch restore policy: "restore last state" vs "always start off".
     * Lives in the same menu as rename, and the same endpoint shape. */
    server.on("/api/switch/restore", HTTP_POST, [](){
        if (!auth_ok()) return;
        String id = server.arg("id");
        String rs = server.arg("restore");
        if (id.length()==0 || rs.length()==0) {
            server.send(400,"application/json",
                "{\"error\":\"id and restore are required\"}"); return; }
        if (!switch_id_valid(id)) {
            server.send(400,"application/json",
                "{\"error\":\"unknown switch\"}"); return; }
        bool on = (rs=="1"||rs=="true"||rs=="on");
        nvs_save_restore(id.c_str(), on);
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Rename master */
    server.on("/api/master/rename", HTTP_POST, [](){
        if (!auth_ok()) return;
        String name = server.arg("name");
        if (name.length()==0) {
            server.send(400,"application/json","{\"ok\":false}"); return; }
        xSemaphoreTake(state_mutex,portMAX_DELAY);
        strncpy(master_name,name.c_str(),sizeof(master_name)-1);
        master_name[sizeof(master_name)-1]='\0';
        xSemaphoreGive(state_mutex);
        nvs_save_master_name(name.c_str());
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Save switch order - single call after all moves done */
    server.on("/api/switch/reorder", HTTP_POST, [](){
        if (!auth_ok()) return;
        String body = server.arg("plain");
        if (body.length()==0) {
            server.send(400,"application/json","{\"ok\":false}"); return; }
        /* Body is plain comma-separated switch IDs */
        xSemaphoreTake(state_mutex,portMAX_DELAY);
        switch_order = body;
        xSemaphoreGive(state_mutex);
        nvs_save_switch_order(body);
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* -- OTA Upload -- */
    /* Device info API */
    server.on("/api/info", HTTP_GET, [](){
        char uid_str[20];
        snprintf(uid_str, sizeof(uid_str), "%02X%02X%02X%02X",
                 master_uid[0], master_uid[1], master_uid[2], master_uid[3]);
        /* 384, not 256: ssid (up to 31 chars) and uid are copied into the
         * document, and an overflow here truncates the JSON silently. */
        StaticJsonDocument<384> doc;
        doc["uptime"]    = millis()/1000;
        doc["free_heap"] = ESP.getFreeHeap();
        doc["uid"]       = uid_str;
        doc["fw"]        = MASTER_FW_VERSION;
        /* So the UI knows whether to present a login before doing anything
         * else. /api/info is deliberately open; it exposes no secrets. */
        doc["auth"]      = true;   /* a credential is always set */
        /* The app needs the network name for its "connect to X" copy and
         * caches it per UID so a rename self-heals. It must come from the
         * master: reading the phone's SSID would need location permission
         * (UX stories v5.1 Epic 6). */
        doc["ssid"]      = mesh_active ? mesh_name : unique_ssid;
        /* Stable mesh identity for the app's switcher/vault. Survives a
         * mesh rename; 0 = standalone (Epic 7 Tech Story). */
        doc["mesh"]      = mesh_active;
        doc["mesh_id"]   = mesh_active ? ble_mesh_id() : 0;
        String out; serializeJson(doc, out);
        server.send(200, "application/json", out);
    });

    /* OTA firmware upload */
    server.on("/api/ota/master", HTTP_POST,
        [](){
            /* Re-check rather than trust the flag: upload_authed is a
             * global and survives between requests, so a stale true from an
             * earlier authenticated upload must not carry over. */
            if (!upload_authed || !auth_valid()) {
                upload_authed = false;
                server.send(401, "application/json", F("{\"error\":\"login required\"}"));
                return;
            }
            if (Update.hasError()) {
                server.send(500, "text/plain", Update.errorString());
                Serial.printf("[OTA] Failed: %s\n", Update.errorString());
            } else {
                server.send(200, "text/plain", "OK");
                Serial.println("[OTA] Success - restarting");
                delay(500);
                ESP.restart();
            }
            ota_in_progress = false;
        },
        [](){
            HTTPUpload &upload = server.upload();
            if (upload.status == UPLOAD_FILE_START) {
                /* Refuse before a single byte reaches the OTA partition:
                 * the write happens during upload, so checking in the
                 * completion handler would be far too late. */
                upload_authed = auth_valid();
                if (!upload_authed) {
                    Serial.println("[OTA] unauthenticated upload rejected");
                    return;
                }
                Serial.printf("[OTA] Start: %s\n", upload.filename.c_str());
                ota_in_progress = true;
                if (!Update.begin(UPDATE_SIZE_UNKNOWN)) {
                    Serial.printf("[OTA] Begin failed: %s\n", Update.errorString());
                }
            } else if (upload.status == UPLOAD_FILE_WRITE) {
                if (!upload_authed) return;
                if (Update.write(upload.buf, upload.currentSize) != upload.currentSize) {
                    Serial.printf("[OTA] Write failed: %s\n", Update.errorString());
                }
            } else if (upload.status == UPLOAD_FILE_END) {
                if (Update.end(true)) {
                    Serial.printf("[OTA] Complete: %u bytes\n", upload.totalSize);
                } else {
                    Serial.printf("[OTA] End failed: %s\n", Update.errorString());
                }

            } else if (upload.status == UPLOAD_FILE_ABORTED) {
                /* Client dropped mid-upload: the completion handler never runs.
                 * Roll back the Update session, otherwise it stays open and the
                 * next OTA attempt fails with "Update already running", and
                 * ota_in_progress stays set which permanently pauses task_bus. */
                Update.abort();
                ota_in_progress = false;
                Serial.println("[OTA] Upload aborted, update rolled back");
            }
        }
    );

        /* -- Extensions API -- */
    server.on("/api/extensions", HTTP_GET, [](){
        if (!auth_ok()) return;
        StaticJsonDocument<1536> doc;
        JsonArray arr = doc.createNestedArray("extensions");
        uint32_t now_ms = millis();
        xSemaphoreTake(state_mutex, portMAX_DELAY);
        for (int i=0; i<MAX_EXTENSIONS; i++) {
            if (extensions[i].state == EXT_EMPTY) continue;
            JsonObject e = arr.createNestedObject();
            presence_t pr = ext_presence(&extensions[i], now_ms);
            e["slot"]   = i;
            e["addr"]   = extensions[i].address;
            /* "online" is presence, not bus liveness: a board that has just
             * come back is still settling and must not put its switches back
             * on the dashboard yet. */
            e["online"] = (pr == PRES_ONLINE);
            e["presence"]  = presence_str(pr);
            e["last_seen"] = seconds_since(extensions[i].last_seen_ms, now_ms);
            e["type"]   = extensions[i].hw_type;
            e["rev"]    = extensions[i].hw_rev;
            char vbuf[16];
            snprintf(vbuf, sizeof(vbuf), "%u.%u.%u",
                     extensions[i].fw_ver[0], extensions[i].fw_ver[1],
                     extensions[i].fw_ver[2]);
            e["fw"]     = vbuf;
            e["fails"]  = extensions[i].ota_fails;
            e["stuck"]  = (extensions[i].ota_fails >= OTA_MAX_FAILS);
            fw_entry_t av;
            if (extensions[i].hw_type && extensions[i].hw_type != 0xFF &&
                fw_lookup(extensions[i].hw_type, &av) &&
                fw_ver_newer(av.ver, extensions[i].fw_ver)) {
                char abuf[16];
                snprintf(abuf, sizeof(abuf), "%u.%u.%u",
                         av.ver[0], av.ver[1], av.ver[2]);
                e["avail"] = abuf;
            }
            /* Load switch names from NVS -- same as UI uses */
            char sw1[24], sw2[24];
            char id1[16], id2[16];
            snprintf(id1, sizeof(id1), "ext%d_1", i);
            snprintf(id2, sizeof(id2), "ext%d_2", i);
            nvs_load_switch_name(id1, sw1, sizeof(sw1));
            nvs_load_switch_name(id2, sw2, sizeof(sw2));
            /* Use extension device name + switch names */
            e["name"]  = extensions[i].name;
            e["sw1"]   = (String(sw1) == "Switch") ?
                         ("Switch " + String(i*2+3)) : String(sw1);
            e["sw2"]   = (String(sw2) == "Switch") ?
                         ("Switch " + String(i*2+4)) : String(sw2);
        }
        xSemaphoreGive(state_mutex);
        String out; serializeJson(doc, out);
        server.send(200, "application/json", out);
    });

    /* Serve the image this master is running, so a peer on an older
     * version can pull it. Only ever our own running partition, which is
     * by definition an image that booted successfully on real hardware. */
    server.on("/api/ota/image", HTTP_GET, [](){
        /* Peer masters hold no session, so this endpoint is authorised by
         * the shared mesh password rather than a login. Without it the
         * complete firmware was downloadable by anyone on the network. */
        if (!rate_ok()) { server.send(429, "text/plain", "slow down"); return; }
        if (!mesh_active || server.arg("k") != String(mesh_pass)) {
            server.send(403, "text/plain", "forbidden");
            return;
        }
        if (master_serve_busy || master_pull_active) {
            server.send(503, "text/plain", "busy");
            return;
        }
        const esp_partition_t *part = esp_ota_get_running_partition();
        uint32_t size = master_image_size();
        if (!part || size == 0) {
            server.send(500, "text/plain", "no image");
            return;
        }
        master_serve_busy = true;
        Serial.printf("[MFW] serving %u bytes to %s\n",
                      size, server.client().remoteIP().toString().c_str());

        server.setContentLength(size);
        server.send(200, "application/octet-stream", "");

        static uint8_t buf[1024];
        uint32_t sent = 0;
        while (sent < size && server.client().connected()) {
            uint32_t n = size - sent;
            if (n > sizeof(buf)) n = sizeof(buf);
            if (esp_partition_read(part, sent, buf, n) != ESP_OK) break;
            if (server.client().write(buf, n) != n) break;
            sent += n;
        }
        server.client().stop();
        master_serve_busy = false;
        Serial.printf("[MFW] sent %u/%u bytes\n", sent, size);
    });

    /* Provision the root and firmware keys. Accepted unauthenticated only
     * while unset, i.e. on the production jig; afterwards a login is
     * required and the keys can never be read back. */
    server.on("/api/provision", HTTP_POST, [](){
        if ((root_key_set || fw_key_set) && !auth_ok()) return;
        String rk = server.arg("root");
        String fk = server.arg("fw");
        if (rk.length()!=32 || fk.length()!=32) {
            server.send(400, "application/json",
                        F("{\"error\":\"need 32 hex chars each\"}"));
            return;
        }
        auto unhex=[](const String &s, uint8_t *out){
            for (int i=0;i<16;i++)
                out[i]=(uint8_t)strtoul(s.substring(i*2,i*2+2).c_str(),NULL,16);
        };
        unhex(rk, root_key); unhex(fk, fw_key);
        prefs.begin("keys", false);
        prefs.putBytes("root", root_key, sizeof(root_key));
        prefs.putBytes("fw",   fw_key,   sizeof(fw_key));
        prefs.end();
        root_key_set = fw_key_set = true;
        Serial.println("[SEC] keys provisioned");
        server.send(200, "application/json", F("{\"ok\":true}"));
    });

    /* -- Authentication -- */
    server.on("/api/login", HTTP_POST, [](){
        if (!rate_ok()) {
            server.send(429, "application/json", F("{\"error\":\"too many requests\"}"));
            return;
        }
        if (auth_lock_until && (int32_t)(millis() - auth_lock_until) < 0) {
            server.send(423, "application/json",
                        F("{\"error\":\"locked, try again later\"}"));
            return;
        }
        String pw = server.arg("password");
        const char *want = active_pass();
        if (pw.length() != strlen(want) ||
            !safe_equal(want, pw.c_str(), strlen(want))) {
            if (++auth_fails >= AUTH_MAX_FAILS) {
                auth_lock_until = millis() + AUTH_LOCKOUT_MS;
                auth_fails = 0;
                Serial.println("[AUTH] too many failures, locked out");
            }
            server.send(401, "application/json", F("{\"error\":\"wrong password\"}"));
            return;
        }
        auth_fails = 0;
        char tok[AUTH_TOKEN_LEN];
        make_token(tok);
        StaticJsonDocument<128> d;
        d["token"] = tok;
        d["mesh"]  = mesh_active;
        String out; serializeJson(d, out);
        server.send(200, "application/json", out);
    });
;

    /* Tokens are stateless, so there is nothing to forget server side.
     * The client discards its copy; changing the password revokes all. */
    server.on("/api/logout", HTTP_POST, [](){
        server.send(200, "application/json", F("{\"ok\":true}"));
    });
;

    /* Set or change the owner password. Allowed unauthenticated only while
     * none is set, i.e. during commissioning. */
    /* Changes the one credential in force: the mesh password when meshed,
     * this device's password otherwise. It is both the Wi-Fi and the API
     * secret, so the AP must restart -- but only after the reply has been
     * sent, so the caller sees the outcome rather than a dropped socket. */
    server.on("/api/password", HTTP_POST, [](){
        if (!auth_ok()) return;
        String pw = server.arg("password");
        if (pw.length() < PASS_MIN_LEN) {
            server.send(400, "application/json",
                        F("{\"error\":\"minimum 8 characters\"}"));
            return;
        }
        if (mesh_active) {
            strncpy(mesh_pass, pw.c_str(), sizeof(mesh_pass)-1);
            mesh_pass[sizeof(mesh_pass)-1] = 0;
            cred_version++;
            prefs.begin("mesh", false);
            prefs.putString("mesh_pass", mesh_pass);
            prefs.putUInt("credver", cred_version);
            prefs.end();
            mesh_broadcast_pass_change();
        } else {
            strncpy(device_pass, pw.c_str(), sizeof(device_pass)-1);
            device_pass[sizeof(device_pass)-1] = 0;
            prefs.begin("auth", false); prefs.putString("appw", device_pass); prefs.end();
        }
        StaticJsonDocument<192> d;
        d["ok"]    = true;
        d["scope"] = mesh_active ? "mesh" : "device";
        d["note"]  = "reconnect with the new password";
        String out; serializeJson(d, out);
        server.send(200, "application/json", out);

        /* Reply is queued; apply once it has drained. */
        ap_change_pending = true;
        ap_change_at_ms   = millis() + AP_APPLY_DELAY_MS;
        Serial.println("[AUTH] credential changed, AP restarts shortly");
    });
;

;

        /* -- Firmware library -- */
    server.on("/api/fw/list", HTTP_GET, [](){
        if (!auth_ok()) return;
        StaticJsonDocument<1024> doc;
        JsonArray arr = doc.createNestedArray("images");
        doc["fs"] = fs_ready;
        if (fs_ready) {
            File f = LittleFS.open(FW_MANIFEST_PATH, "r");
            if (f) {
                StaticJsonDocument<1024> man;
                if (deserializeJson(man, f) == DeserializationError::Ok) {
                    for (JsonObject e : man["images"].as<JsonArray>()) {
                        JsonObject o = arr.createNestedObject();
                        o["type"] = e["type"];
                        o["size"] = e["size"];
                        char vb[16];
                        snprintf(vb, sizeof(vb), "%u.%u.%u",
                                 (uint8_t)(e["ver"][0] | 0),
                                 (uint8_t)(e["ver"][1] | 0),
                                 (uint8_t)(e["ver"][2] | 0));
                        o["ver"] = vb;
                    }
                }
                f.close();
            }
        }
        String out; serializeJson(doc, out);
        server.send(200, "application/json", out);
    });

    /* Upload an image into the library. Type and version are read from
     * the descriptor inside the image, never typed by the operator.
     * ?mesh=1 also offers it to every peer master. */
    server.on("/api/fw/upload", HTTP_POST,
        [](){
            /* Re-check rather than trust the flag: upload_authed is a
             * global and survives between requests, so a stale true from an
             * earlier authenticated upload must not carry over. */
            if (!upload_authed || !auth_valid()) {
                upload_authed = false;
                server.send(401, "application/json", F("{\"error\":\"login required\"}"));
                return;
            }
            if (!fs_ready) {
                server.send(500, "application/json",
                            F("{\"error\":\"no filesystem\"}"));
                return;
            }
            if (!ext_ota_buf || ext_ota_total == 0) {
                server.send(400, "application/json", F("{\"error\":\"no data\"}"));
                return;
            }
            uint8_t type = 0, ver[3] = {0,0,0};
            if (!fw_parse_desc(ext_ota_buf, ext_ota_total, &type, ver)) {
                free(ext_ota_buf); ext_ota_buf = nullptr; ext_ota_total = 0;
                server.send(400, "application/json",
                            F("{\"error\":\"not a Unisync extension image\"}"));
                return;
            }
            String sighex = server.arg("sig");
            uint8_t secver = (uint8_t)server.arg("sec").toInt();
            if (sighex.length() != 64) {
                free(ext_ota_buf); ext_ota_buf = nullptr; ext_ota_total = 0;
                server.send(400, "application/json",
                            F("{\"error\":\"missing signature\"}"));
                return;
            }
            uint8_t sig[32];
            for (int k=0;k<32;k++)
                sig[k]=(uint8_t)strtoul(sighex.substring(k*2,k*2+2).c_str(),NULL,16);
            bool ok = fw_store(type, ver, ext_ota_buf, ext_ota_total, secver, sig);
            uint32_t crc  = fw_crc32(ext_ota_buf, ext_ota_total);
            uint32_t size = ext_ota_total;
            free(ext_ota_buf); ext_ota_buf = nullptr; ext_ota_total = 0;
            if (!ok) {
                server.send(500, "application/json",
                            F("{\"error\":\"store failed\"}"));
                return;
            }
            if (server.arg("mesh") == "1") fw_mesh_offer(type, ver, size, crc, secver, sig);
            StaticJsonDocument<192> d;
            d["ok"] = true; d["type"] = type; d["size"] = size;
            char vb[16]; snprintf(vb, sizeof(vb), "%u.%u.%u", ver[0], ver[1], ver[2]);
            d["ver"] = vb;
            String out; serializeJson(d, out);
            server.send(200, "application/json", out);
            notify_ui();
        },
        [](){
            HTTPUpload &upload = server.upload();
            if (upload.status == UPLOAD_FILE_START) {
                upload_authed = auth_valid();
                if (!upload_authed) return;
                ext_ota_total = 0;
                if (ext_ota_buf) { free(ext_ota_buf); ext_ota_buf = nullptr; }
                ext_ota_buf = (uint8_t*)malloc(EXT_OTA_MAX_SIZE);
                if (!ext_ota_buf) Serial.println("[FW] malloc failed");
            } else if (upload.status == UPLOAD_FILE_WRITE) {
                if (!upload_authed || !ext_ota_buf) return;
                if (ext_ota_total + upload.currentSize > EXT_OTA_MAX_SIZE) {
                    free(ext_ota_buf); ext_ota_buf = nullptr;
                    Serial.println("[FW] image too large");
                    return;
                }
                memcpy(ext_ota_buf + ext_ota_total, upload.buf, upload.currentSize);
                ext_ota_total += upload.currentSize;
            } else if (upload.status == UPLOAD_FILE_ABORTED) {
                if (ext_ota_buf) { free(ext_ota_buf); ext_ota_buf = nullptr; }
                ext_ota_total = 0;
                upload_authed = false;
                Serial.println("[FW] upload aborted, buffer released");
            }
        }
    );

        /* -- Extension OTA -- */
    server.on("/api/ota/extension", HTTP_POST,
        [](){
            /* Re-check rather than trust the flag: upload_authed is a
             * global and survives between requests, so a stale true from an
             * earlier authenticated upload must not carry over. */
            if (!upload_authed || !auth_valid()) {
                upload_authed = false;
                server.send(401, "application/json", F("{\"error\":\"login required\"}"));
                return;
            }
            if (ext_ota_buf == nullptr || ext_ota_total == 0) {
                server.send(400, "application/json", "{\"error\":\"no data\"}");
                return;
            }
            Serial.printf("[EXT-OTA] Sending %u bytes to addr=0x%02X\n",
                          ext_ota_total, ext_ota_addr);
            ota_in_progress = true;
            vTaskDelay(pdMS_TO_TICKS(300));  /* let task_bus finish current poll */
            uint8_t utype = 0, uver[3] = {0,0,0};
            if (!fw_parse_desc(ext_ota_buf, ext_ota_total, &utype, uver)) {
                free(ext_ota_buf); ext_ota_buf = nullptr; ext_ota_total = 0;
                ota_in_progress = false;
                server.send(400, "application/json",
                            F("{\"error\":\"image has no Unisync descriptor\"}"));
                return;
            }
            /* Manual push still requires a valid signature: read it from
             * the library entry for this type rather than trusting the
             * upload, so an unsigned image can never be forced through. */
            fw_entry_t le;
            if (!fw_lookup(utype, &le) || le.size != ext_ota_total) {
                free(ext_ota_buf); ext_ota_buf = nullptr; ext_ota_total = 0;
                ota_in_progress = false;
                server.send(400, "application/json",
                            F("{\"error\":\"image not in signed library\"}"));
                return;
            }
            bool ok = ext_ota_send(ext_ota_addr, ext_ota_buf, ext_ota_total,
                                   utype, uver, le.secver, le.sig);
            free(ext_ota_buf); ext_ota_buf = nullptr; ext_ota_total = 0;
            ota_in_progress = false;
            if (ok) {
                server.send(200, "application/json", "{\"ok\":true}");
            } else {
                server.send(500, "application/json", "{\"error\":\"OTA failed\"}");
            }
        },
        [](){
            HTTPUpload &upload = server.upload();
            if (upload.status == UPLOAD_FILE_START) {
                /* Get target address from ?addr=X */
                upload_authed = auth_valid();
                if (!upload_authed) return;
                ext_ota_addr  = (uint8_t)server.arg("addr").toInt();
                ext_ota_total = 0;
                if (ext_ota_buf) { free(ext_ota_buf); ext_ota_buf = nullptr; }
                ext_ota_buf = (uint8_t*)malloc(EXT_OTA_MAX_SIZE);
                if (!ext_ota_buf) {
                    Serial.println("[EXT-OTA] malloc failed");
                    return;
                }
                Serial.printf("[EXT-OTA] Receiving firmware for addr=0x%02X\n", ext_ota_addr);

            } else if (upload.status == UPLOAD_FILE_WRITE) {
                if (!upload_authed || !ext_ota_buf) return;
                if (ext_ota_total + upload.currentSize > EXT_OTA_MAX_SIZE) {
                    Serial.println("[EXT-OTA] Firmware too large");
                    free(ext_ota_buf); ext_ota_buf = nullptr; return;
                }
                memcpy(ext_ota_buf + ext_ota_total, upload.buf, upload.currentSize);
                ext_ota_total += upload.currentSize;

            } else if (upload.status == UPLOAD_FILE_END) {
                Serial.printf("[EXT-OTA] Received %u bytes\n", ext_ota_total);

            } else if (upload.status == UPLOAD_FILE_ABORTED) {
                /* Client dropped mid-upload: the completion handler never runs,
                 * so release the buffer here or we leak 10KB per abort. */
                if (ext_ota_buf) { free(ext_ota_buf); ext_ota_buf = nullptr; }
                ext_ota_total   = 0;
                ota_in_progress = false;
                Serial.println("[EXT-OTA] Upload aborted, buffer released");
            }
        }
    );

        /* -- Mesh API -- */

    /* Generate PIN to invite new master */
    server.on("/api/mesh/invite", HTTP_POST, [](){
        if (!auth_ok()) return;
        mesh_generate_pin();
        /* Use AP MAC -- in WIFI_AP_STA mode AP MAC = STA MAC + 1.
         * Peers must target AP MAC when sending via WIFI_IF_AP interface. */
        uint8_t mac[6];
        esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
        char mac_str[18];
        snprintf(mac_str,sizeof(mac_str),"%02X%02X%02X%02X%02X%02X",
                 mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]);
        StaticJsonDocument<128> doc;
        doc["pin"]        = mesh_pin;
        doc["expires_ms"] = MESH_PIN_VALID_MS;
        doc["mac"]        = mac_str;
        char uid_str[12];
        snprintf(uid_str,sizeof(uid_str),"%02X%02X%02X%02X",
                 master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
        doc["uid"] = uid_str;
        String out; serializeJson(doc,out);
        server.send(200,"application/json",out);
    });

    /* Join mesh: Master 2 receives PIN + Master 1 MAC from user.
     * Registers Master 1 as ESP-NOW peer using the known MAC,
     * then sends JOIN_REQ directly via ESP-NOW. Master 1 verifies
     * PIN and sends mesh credentials back via ESP-NOW. */
    server.on("/api/mesh/join", HTTP_POST, [](){
        if (!auth_ok()) return;
        if (mesh_active) {
            server.send(400,"application/json","{\"error\":\"already in mesh\"}");
            return;
        }
        /* Mesh membership requires our keys, not just a PIN. Without this
         * an unprovisioned or cloned master could join with a stolen PIN
         * and drive relays on every other master in the house. */
        if (!root_key_set || !fw_key_set) {
            server.send(403,"application/json",
                "{\"error\":\"not provisioned, cannot join a mesh\"}");
            return;
        }
        String pin     = server.arg("pin");
        String mac_str = server.arg("mac");
        if (pin.length()!=6 || mac_str.length()!=12) {
            server.send(400,"application/json",
                "{\"error\":\"pin must be 6 digits, mac must be 12 hex chars\"}");
            return;
        }
        /* Parse Master 1 MAC */
        uint8_t peer_mac[6];
        for (int i=0;i<6;i++) {
            char b[3]={mac_str[i*2],mac_str[i*2+1],0};
            peer_mac[i]=(uint8_t)strtoul(b,NULL,16);
        }
        /* Register Master 1 as ESP-NOW peer */
        if (esp_now_is_peer_exist(peer_mac)) {
            /* Remove and re-add to ensure channel is correct */
            esp_now_del_peer(peer_mac);
        }
        esp_now_peer_info_t pi={};
        memcpy(pi.peer_addr, peer_mac, 6);
        pi.channel  = AP_CHANNEL;
        pi.encrypt  = false;
        pi.ifidx    = WIFI_IF_AP; /* Use AP interface in AP_STA mode */
        esp_err_t peer_err = esp_now_add_peer(&pi);
        Serial.printf("[MESH] Peer add result: %d (%s)\n",
                      peer_err, peer_err==ESP_OK?"OK":"FAIL");
        if (peer_err != ESP_OK) {
            server.send(500,"application/json","{\"error\":\"peer registration failed\"}");
            return;
        }
        /* Send JOIN_REQ directly to Master 1 via ESP-NOW (not broadcast) */
        StaticJsonDocument<192> doc;
        char self_uid[12];
        snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                 master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
        doc["type"] = MESH_PKT_JOIN_REQ;
        doc["uid"]  = self_uid;
        doc["pin"]  = pin.c_str();
        /* Proof we hold the product keys. Not the keys themselves -- a
         * checksum over both, which only genuine provisioned hardware can
         * produce, and which reveals nothing if captured. */
        {
            uint8_t both[32], mac[32];
            memcpy(both, root_key, 16); memcpy(both+16, fw_key, 16);
            hmac_sha256(both, (const uint8_t*)"unisync-prov-v1", 15, mac);
            char pv[17];
            for (int k=0;k<8;k++) snprintf(pv+k*2,3,"%02x",mac[k]);
            pv[16]=0;
            doc["pv"] = pv;
        }
        String payload; serializeJson(doc,payload);
        uint8_t my_ap_mac[6]; esp_read_mac(my_ap_mac, ESP_MAC_WIFI_SOFTAP);
        Serial.printf("[MESH] JOIN_REQ: my AP MAC=%02X%02X%02X%02X%02X%02X\n",
                      my_ap_mac[0],my_ap_mac[1],my_ap_mac[2],
                      my_ap_mac[3],my_ap_mac[4],my_ap_mac[5]);
        Serial.printf("[MESH] JOIN_REQ: sending to %s on channel %d\n",
                      mac_str.c_str(), AP_CHANNEL);
        esp_err_t send_r = esp_now_send(peer_mac,
                           (const uint8_t*)payload.c_str(),payload.length()+1);
        Serial.printf("[MESH] JOIN_REQ: esp_now_send=%d (%s)\n",
                      send_r, send_r==ESP_OK?"OK":"FAIL");
        /* Response arrives async via mesh_recv_cb JOIN_ACK handler */
        server.send(200,"application/json","{\"ok\":true,\"status\":\"pending\"}");
    });

    

    /* Create a new mesh (first master) */
    server.on("/api/mesh/create", HTTP_POST, [](){
        if (!auth_ok()) return;
        if (mesh_active) {
            server.send(400,"application/json","{\"error\":\"already in mesh\"}");
            return;
        }
        /* Get mesh name from request, default to "Unisync" */
        String name = server.arg("name");
        name.trim();
        if (name.length() == 0) name = "Unisync";
        if (name.length() > 31) name = name.substring(0,31);
        /* The mesh password is the user's to choose (UX stories v5.1
         * Epic 7): it becomes the Wi-Fi key AND the login for the whole
         * home, and the guided transition tells them to rejoin with it.
         * Generating it here and only printing it to serial locked the
         * owner out of their own network -- the AP came back on an SSID
         * whose password nobody knew, recoverable only over BLE.
         * Same rules as /api/mesh/passwd: >=8 chars, clamp at 63. */
        String pass = server.arg("pass");
        pass.trim();
        if (pass.length() < 8) {
            server.send(400,"application/json",
                "{\"error\":\"Mesh password must be at least 8 characters\"}");
            return;
        }
        if (pass.length() > 63) pass = pass.substring(0,63);
        {
            strncpy(mesh_pass, pass.c_str(), sizeof(mesh_pass)-1);
            mesh_pass[sizeof(mesh_pass)-1] = 0;
            for (int k = 0; k < 16; k += 4) {
                uint32_t r = esp_random();
                mesh_auth_key[k]=r&0xFF;     mesh_auth_key[k+1]=(r>>8)&0xFF;
                mesh_auth_key[k+2]=(r>>16)&0xFF; mesh_auth_key[k+3]=(r>>24)&0xFF;
            }
            mesh_auth_set = true;
            cred_version  = 1;
            prefs.begin("mesh", false);
            prefs.putString("mesh_pass", mesh_pass);
            prefs.putBytes("authkey", mesh_auth_key, 16);
            prefs.putUInt("credver", cred_version);
            prefs.end();
            Serial.println("[MESH] created with the supplied password");
            ble_update_adv_data();
        }
        strncpy(mesh_name, name.c_str(), sizeof(mesh_name)-1);
        /* Generate random mesh ID */
        for (int i=0;i<16;i++) mesh_id[i]=(uint8_t)(esp_random()&0xFF);
        mesh_active = true;
        /* Init master_order with self */
        char self_uid4[12];
        snprintf(self_uid4,sizeof(self_uid4),"%02X%02X%02X%02X",
                 master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
        master_order_add(self_uid4);
        mesh_nvs_save();
        Serial.printf("[MESH] New mesh created: %s\n", mesh_name);
        /* Switch to mesh-name SSID */
        WiFi.softAPdisconnect(false);
        delay(100);
        WiFi.softAP(mesh_name, mesh_pass, AP_CHANNEL);
        Serial.printf("[WIFI] Switched to mesh SSID: %s\n", mesh_name);
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Leave mesh */
    /* Remove another master from the mesh. The target wipes its mesh
     * credentials and restarts standalone; the mesh itself is unchanged --
     * name, password and keys all stay as they were, so nobody else is
     * logged out and no peer is stranded. */
    server.on("/api/mesh/kick", HTTP_POST, [](){
        if (!auth_ok()) return;
        if (!mesh_active) {
            server.send(400,"application/json","{\"error\":\"not in mesh\"}");
            return;
        }
        String tgt = server.arg("uid");
        char self_uid[12];
        snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                 master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
        if (tgt.length()!=8) {
            server.send(400,"application/json","{\"error\":\"uid must be 8 hex chars\"}");
            return;
        }
        if (tgt.equalsIgnoreCase(self_uid)) {
            server.send(400,"application/json",
                "{\"error\":\"use /api/mesh/leave to remove this master\"}");
            return;
        }
        uint8_t tu[4];
        for (int k=0;k<4;k++){ char b[3]={tgt[k*2],tgt[k*2+1],0};
            tu[k]=(uint8_t)strtoul(b,NULL,16); }
        int idx = mesh_find_peer(tu);
        if (idx < 0) {
            server.send(404,"application/json","{\"error\":\"not a member\"}");
            return;
        }
        /* Refuse an offline target. It would never hear the kick, so it
         * would keep the mesh credentials and rejoin when powered on --
         * the app would have shown a removal that did not happen. Enforced
         * here rather than left to the app. */
        if (!mesh_peers[idx].online) {
            server.send(409,"application/json",
                "{\"error\":\"master is offline; power it on and try again\"}");
            return;
        }

        /* Arm before sending: a fast acknowledgment must not be cleared
         * by a reset that happens after the broadcast. */
        kick_acked = false;

        StaticJsonDocument<128> doc;
        doc["type"]   = MESH_PKT_KICK;
        doc["uid"]    = self_uid;
        doc["target"] = tgt.c_str();
        String payload; serializeJson(doc,payload);
        mesh_broadcast(payload.c_str(), payload.length()+1);
        /* Wait for the target to confirm it deleted its credentials before
         * reporting success. Without this the app would show a removal
         * that may not have happened. */
        uint32_t t0 = millis();
        while (!kick_acked && (millis() - t0) < 3000) {
            server.handleClient();
            vTaskDelay(pdMS_TO_TICKS(20));
        }
        if (!kick_acked) {
            Serial.printf("[MESH] %s never confirmed deletion\n", tgt.c_str());
            server.send(504,"application/json",
                "{\"error\":\"master did not confirm removal; try again\"}");
            return;
        }
        /* Confirmed: now drop it locally. */
        if (esp_now_is_peer_exist(mesh_peers[idx].mac))
            esp_now_del_peer(mesh_peers[idx].mac);
        memset(&mesh_peers[idx], 0, sizeof(mesh_peer_t));
        master_order_remove(tgt.c_str());
        notify_ui();
        Serial.printf("[MESH] kicked %s, deletion confirmed\n", tgt.c_str());
        server.send(200,"application/json","{\"ok\":true}");
    });

    server.on("/api/mesh/leave", HTTP_POST, [](){
        if (!auth_ok()) return;
        if (!mesh_active) {
            server.send(400,"application/json","{\"error\":\"not in mesh\"}");
            return;
        }
        /* Notify peers */
        StaticJsonDocument<64> doc;
        char self_uid[12];
        snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                 master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
        doc["type"] = MESH_PKT_LEAVE;
        doc["uid"]  = self_uid;
        String payload; serializeJson(doc,payload);
        mesh_broadcast(payload.c_str(),payload.length()+1);
        delay(100);
        /* Remove self from master_order before clearing */
        {
            char self_uid3[12];
            snprintf(self_uid3,sizeof(self_uid3),"%02X%02X%02X%02X",
                     master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
            master_order_remove(self_uid3);
        }
        mesh_nvs_clear();
        /* Switch back to unique SSID   master is now standalone again */
        {
            uint8_t tmac[6];
            esp_read_mac(tmac, ESP_MAC_WIFI_STA);
                    snprintf(unique_ssid, sizeof(unique_ssid), "Unisync-%02X%02X",
                     tmac[4], tmac[5]);
            WiFi.softAPdisconnect(false);
            delay(100);
            /* Never start an open access point. If the credential is somehow
     * missing, fall back to the factory value rather than broadcasting
     * an unprotected network. */
    if (strlen(device_pass) < PASS_MIN_LEN) {
        Serial.println("[AUTH] device password missing at AP start -- using factory value");
        strncpy(device_pass, factory_pass, sizeof(device_pass)-1);
        device_pass[sizeof(device_pass)-1] = 0;
    }
    WiFi.softAP(unique_ssid, device_pass, AP_CHANNEL);
            Serial.printf("[WIFI] Reverted to unique SSID: %s\n", unique_ssid);
        }
        strncpy(mesh_name, "Unisync", sizeof(mesh_name)-1);
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Cross-master relay command */
    server.on("/api/mesh/relay", HTTP_POST, [](){
        if (!auth_ok()) return;
        String peer_uid_str = server.arg("peer_uid");
        String sw_id        = server.arg("sw_id");
        int    ch           = server.arg("ch").toInt();

        /* Validate ch - if 0 or undefined, derive from sw_id suffix */
        if (ch < 1 || ch > 2) {
            /* sw_id format: "master_1", "ext0_2" etc - last char is channel */
            String sw_id_str = sw_id;
            if (sw_id_str.length() > 0) {
                char last = sw_id_str[sw_id_str.length()-1];
                if (last == '1') ch = 1;
                else if (last == '2') ch = 2;
                else ch = 1; /* default */
            }
            Serial.printf("[MESH] ch was invalid, derived ch=%d from sw_id=%s\n",
                          ch, sw_id.c_str());
        }

        /* Wildcard sw_id="*" means kill all on target peer */
        if (sw_id == "*") {
            if (peer_uid_str.length()!=8) {
                server.send(400,"application/json","{\"error\":\"bad uid\"}");
                return;
            }
            uint8_t peer_uid[4];
            peer_uid[0]=strtoul(peer_uid_str.substring(0,2).c_str(),NULL,16);
            peer_uid[1]=strtoul(peer_uid_str.substring(2,4).c_str(),NULL,16);
            peer_uid[2]=strtoul(peer_uid_str.substring(4,6).c_str(),NULL,16);
            peer_uid[3]=strtoul(peer_uid_str.substring(6,8).c_str(),NULL,16);
            int idx = mesh_find_peer(peer_uid);
            if (idx<0) {
                server.send(404,"application/json","{\"error\":\"peer not found\"}");
                return;
            }
            /* Send killall relay command to peer */
            StaticJsonDocument<128> doc;
            char self_uid[12];
            snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                     master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
            doc["type"]    = MESH_PKT_RELAY_CMD;
            doc["uid"]     = self_uid;
            doc["sw_id"]   = "*";
            doc["ch"]      = 0;
            doc["state"]   = false;
            String payload; serializeJson(doc,payload);
            mesh_send(mesh_peers[idx].mac, payload.c_str(), payload.length()+1);
            server.send(200,"application/json","{\"ok\":true}");
            return;
        }

        if (peer_uid_str.length()!=8) {
            server.send(400,"application/json","{\"error\":\"bad uid\"}");
            return;
        }

        uint8_t peer_uid[4];
        peer_uid[0]=strtoul(peer_uid_str.substring(0,2).c_str(),NULL,16);
        peer_uid[1]=strtoul(peer_uid_str.substring(2,4).c_str(),NULL,16);
        peer_uid[2]=strtoul(peer_uid_str.substring(4,6).c_str(),NULL,16);
        peer_uid[3]=strtoul(peer_uid_str.substring(6,8).c_str(),NULL,16);

        /* Find peer */
        int idx = mesh_find_peer(peer_uid);
        if (idx<0) {
            server.send(404,"application/json","{\"error\":\"peer not found\"}");
            return;
        }

        /* Get current state and toggle */
        bool cur_state = false;
        xSemaphoreTake(state_mutex,portMAX_DELAY);
        for (int i=0;i<mesh_peers[idx].switch_count;i++) {
            if (strcmp(mesh_peers[idx].switches[i].id,sw_id.c_str())==0) {
                cur_state = mesh_peers[idx].switches[i].state;
                break;
            }
        }
        xSemaphoreGive(state_mutex);

        /* An explicit state when the caller sends one. Toggling was the
         * only option before, which meant an optimistic UI and a retry
         * could land on opposite values. */
        String want = server.arg("state");
        bool new_state = want.length()
            ? (want == "1" || want == "true" || want == "on")
            : !cur_state;
        bool ok = mesh_relay_remote(peer_uid, mesh_peers[idx].mac,
                                    sw_id.c_str(), ch, new_state);

        /* Optimistically update local cache regardless of send result.
         * Gossip will correct state if relay actually failed. */
        xSemaphoreTake(state_mutex,portMAX_DELAY);
        for (int i=0;i<mesh_peers[idx].switch_count;i++) {
            if (strcmp(mesh_peers[idx].switches[i].id,sw_id.c_str())==0) {
                mesh_peers[idx].switches[i].state = new_state;
                break;
            }
        }
        xSemaphoreGive(state_mutex);

        if (ok) {
            notify_ui();
            server.send(200,"application/json","{\"ok\":true}");
        } else {
            /* Send failed -- still return 200 with warning so UI doesn't error */
            Serial.println("[MESH] relay send failed");
            notify_ui();
            server.send(200,"application/json","{\"ok\":false,\"warn\":\"send failed\"}");
        }
    });

    /* Change mesh WiFi password -- propagates to all mesh peers */
    server.on("/api/mesh/passwd", HTTP_POST, [](){
        if (!auth_ok()) return;
        if (!mesh_active) {
            server.send(400,"application/json","{\"error\":\"not in mesh\"}");
            return;
        }
        String old_pass = server.arg("old");
        String pass     = server.arg("pass");
        String name     = server.arg("name");
        pass.trim(); old_pass.trim();
        /* Verify old password */
        if (old_pass != String(mesh_pass)) {
            server.send(403,"application/json",
                "{\"error\":\"Current password is incorrect\"}");
            return;
        }
        if (pass.length() < 8) {
            server.send(400,"application/json",
                "{\"error\":\"New password must be at least 8 characters\"}");
            return;
        }
        if (pass.length() > 63) pass = pass.substring(0,63);
        if (name.length() > 0 && name.length() <= 31)
            strncpy(mesh_name, name.c_str(), sizeof(mesh_name)-1);
        strncpy(mesh_pass, pass.c_str(), sizeof(mesh_pass)-1);
        mesh_nvs_save();
        /* Broadcast password change to all peers */
        StaticJsonDocument<256> doc; /* passwd bcast: name+pass+uid+seq */
        char self_uid[12];
        snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                 master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
        doc["type"] = MESH_PKT_PASS_CHG;
        doc["uid"]  = self_uid;
        doc["pass"] = mesh_pass;   /* always current password */
        doc["name"] = mesh_name;   /* always current name from NVS/state */
        String payload; serializeJson(doc,payload);
        mesh_broadcast(payload.c_str(), payload.length()+1);
        Serial.printf("[MESH] Password change broadcast: %s\n", mesh_name);
        /* Apply locally */
        WiFi.softAPdisconnect(false);
        delay(100);
        WiFi.softAP(mesh_name, mesh_pass, AP_CHANNEL);
        Serial.printf("[WIFI] AP restarted: %s\n", mesh_name);
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Rename mesh */
    server.on("/api/mesh/rename", HTTP_POST, [](){
        if (!auth_ok()) return;
        if (!mesh_active) {
            server.send(400,"application/json","{\"error\":\"not in mesh\"}");
            return;
        }
        String name = server.arg("name");
        name.trim();
        if (name.length()==0) {
            server.send(400,"application/json","{\"error\":\"name required\"}");
            return;
        }
        if (name.length()>31) name=name.substring(0,31);
        strncpy(mesh_name, name.c_str(), sizeof(mesh_name)-1);
        mesh_nvs_save();
        /* Broadcast new name to all peers -- they switch SSID simultaneously */
        {
            StaticJsonDocument<256> bcast; /* name+pass+uid+seq */
            char self_uid[12];
            snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                     master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
            bcast["type"] = MESH_PKT_PASS_CHG; /* carries both name+pass */
            bcast["uid"]  = self_uid;
            bcast["name"] = mesh_name;
            bcast["pass"] = mesh_pass;
            String bpayload; serializeJson(bcast, bpayload);
            mesh_broadcast(bpayload.c_str(), bpayload.length()+1);
            Serial.printf("[MESH] Rename broadcast: %s\n", mesh_name);
        }
        /* No delay needed -- broadcast is queued by esp_now_send synchronously */
        WiFi.softAPdisconnect(false);
        delay(100);
        WiFi.softAP(mesh_name, mesh_pass, AP_CHANNEL);
        Serial.printf("[WIFI] SSID changed to: %s\n", mesh_name);
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Mesh config proxy -- rename/reorder masters and peer switches */
    server.on("/api/mesh/config", HTTP_POST, [](){
        if (!auth_ok()) return;
        if (!mesh_active) {
            server.send(400,"application/json","{\"error\":\"not in mesh\"}");
            return;
        }
        String cmd        = server.arg("cmd");
        String target_uid = server.arg("target_uid");
        String name       = server.arg("name");
        String order      = server.arg("order");
        int    slot       = server.arg("slot").toInt();

        char self_uid[12];
        snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                 master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
        bool is_self = (target_uid == String(self_uid));

        if (cmd == "reorder_masters") {
            /* Mesh-wide -- apply locally and broadcast to all */
            strncpy(master_order_str, order.c_str(), sizeof(master_order_str)-1);
            mesh_nvs_save();
            mesh_send_config("reorder_masters", "", nullptr, order.c_str(), -1);
            notify_ui();

        } else if (cmd == "rename_master") {
            if (is_self) {
                /* Apply locally */
                nvs_save_master_name(name.c_str());
                strncpy(master_name, name.c_str(), sizeof(master_name)-1);
                notify_ui();
            } else {
                /* Proxy to target peer */
                mesh_send_config("rename_master", target_uid.c_str(),
                                 name.c_str(), nullptr, -1);
            }

        } else if (cmd == "rename_switch") {
            if (is_self) {
                /* Apply locally */
                xSemaphoreTake(state_mutex, portMAX_DELAY);
                if (slot >= 0 && slot < MAX_EXTENSIONS &&
                    extensions[slot].state != EXT_EMPTY) {
                    strncpy(extensions[slot].name, name.c_str(),
                            sizeof(extensions[slot].name)-1);
                    uint8_t uid[4]; memcpy(uid, extensions[slot].uid, 4);
                    xSemaphoreGive(state_mutex);
                    nvs_save(uid, slot, name.c_str());
                } else { xSemaphoreGive(state_mutex); }
                notify_ui();
            } else {
                mesh_send_config("rename_switch", target_uid.c_str(),
                                 name.c_str(), nullptr, slot);
            }

        } else if (cmd == "reorder_switches") {
            if (is_self) {
                nvs_save_switch_order(order.c_str());
                switch_order = order;
                notify_ui();
            } else {
                mesh_send_config("reorder_switches", target_uid.c_str(),
                                 nullptr, order.c_str(), -1);
            }

        } else if (cmd == "set_restore") {
            /* "name" carries the switch id and "slot" the policy (0/1), so
             * this rides the existing config packet unchanged -- peers on
             * older firmware simply ignore a command they don't know. */
            if (is_self) {
                if (switch_id_valid(name)) {
                    nvs_save_restore(name.c_str(), slot != 0);
                    notify_ui();
                }
            } else {
                mesh_send_config("set_restore", target_uid.c_str(),
                                 name.c_str(), nullptr, slot);
            }
        }

        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Mesh status */
    server.on("/api/mesh/status", HTTP_GET, [](){
        if (!auth_ok()) return;
        /* Heap: 16 members with uid, name, presence, last-seen and firmware
         * no longer fit in a stack document task_web can afford. */
        DynamicJsonDocument doc(4096);
        doc["active"]    = mesh_active;
        doc["mesh_name"] = mesh_name;
        doc["pin_valid"] = mesh_pin_valid;
        if (mesh_pin_valid) doc["pin"] = mesh_pin;
        /* Counted on presence, so the number matches the green cards in
         * the list below rather than disagreeing with them for a minute. */
        int online_count = 0;
        for (int i=0;i<MAX_MESH_MASTERS;i++)
            if (peer_presence(&mesh_peers[i], millis()) == PRES_ONLINE)
                online_count++;
        doc["peer_count"] = online_count;
        /* Version of every node, so convergence is visible in the UI. */
        doc["fw"] = MASTER_FW_VERSION;
        doc["syncing"] = master_pull_active || master_serve_busy;
        doc["cred_stale"] = cred_stale;
        /* Every member, not just the reachable ones. The Mesh details screen
         * lists offline masters too (with a last-seen time and Remove
         * greyed out) -- a master that vanishes from the list is exactly the
         * flapping the story rules out. */
        JsonArray pv = doc.createNestedArray("peers");
        uint32_t now_ms = millis();
        for (int i=0;i<MAX_MESH_MASTERS;i++) {
            bool has_uid=false;
            for (int k=0;k<4;k++) if (mesh_peers[i].uid[k]) { has_uid=true; break; }
            if (!has_uid) continue;
            JsonObject o = pv.createNestedObject();
            char puid[12];
            snprintf(puid,sizeof(puid),"%02X%02X%02X%02X",
                     mesh_peers[i].uid[0],mesh_peers[i].uid[1],
                     mesh_peers[i].uid[2],mesh_peers[i].uid[3]);
            presence_t ppr = peer_presence(&mesh_peers[i], now_ms);
            o["uid"]  = puid;
            o["name"] = mesh_peers[i].name;
            o["online"]    = (ppr == PRES_ONLINE);
            o["presence"]  = presence_str(ppr);
            o["last_seen"] = seconds_since(mesh_peers[i].last_seen_ms, now_ms);
            char vb[16];
            snprintf(vb,sizeof(vb),"%u.%u.%u",
                     mesh_peers[i].fw[0],mesh_peers[i].fw[1],mesh_peers[i].fw[2]);
            o["fw"] = vb;
        }
        String out; serializeJson(doc,out);
        server.send(200,"application/json",out);
    });

    /* Manual scan trigger */
    server.on("/api/scan", HTTP_POST, [](){
        if (!auth_ok()) return;
        xSemaphoreTake(state_mutex,portMAX_DELAY);
        scan_active=true;
        scan_end_ms=millis()+5000;
        xSemaphoreGive(state_mutex);
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* WebSocket */
    wss.onEvent([](uint8_t num, WStype_t type,
                   uint8_t *payload, size_t length){
        if (type==WStype_CONNECTED) {
            /* The socket both streams state and accepts commands, so an
             * unauthenticated client is equivalent to an open API. The
             * token is passed as ?t= on the websocket URL. */
            {
                String url = String((char*)payload);
                int k = url.indexOf("t=");
                String tok = "";
                if (k >= 0) {
                    tok = url.substring(k+2);
                    int amp = tok.indexOf('&');
                    if (amp > 0) tok = tok.substring(0, amp);
                }
                if (!token_valid(tok)) {
                    Serial.printf("[WS] Client #%u rejected, no session\n",num);
                    wss.disconnect(num);
                    return;
                }
            }
            Serial.printf("[WS] Client #%u connected\n",num);
            /* Signal notify queue -- state sent from task_web on next iteration.
             * Do NOT call build_state_json() here -- NVS reads inside a
             * WebSocket callback cause send timeout before client receives data. */
            notify_ui();
        } else if (type==WStype_DISCONNECTED) {
            Serial.printf("[WS] Client #%u disconnected\n",num);
        }
    });

    /* Suppress favicon 404 */
    server.on("/favicon.ico", HTTP_GET, [](){
        server.send(204,"image/x-icon","");
    });

    /* WebServer discards every header it was not told to keep, so without
     * this server.header("X-Auth") is always empty and every authenticated
     * request would be rejected. Fails closed, but the product stops
     * working -- must be registered before begin(). */
    {
        const char *keep[] = { "X-Auth" };
        server.collectHeaders(keep, 1);
    }

    server.begin();
    wss.begin();
    Serial.println("[HTTP] Server on port 80, WebSocket on port 81");
}

/* ================================================================
 * SETUP
 * ================================================================ */

/* ================================================================
 * ACCESS CONTROL HELPERS
 * ================================================================ */
static void sha256_hex(const char *in, const char *salt, char *out65) {
    mbedtls_sha256_context ctx;
    uint8_t d[32];
    mbedtls_sha256_init(&ctx);
    mbedtls_sha256_starts(&ctx, 0);
    mbedtls_sha256_update(&ctx, (const uint8_t *)salt, strlen(salt));
    mbedtls_sha256_update(&ctx, (const uint8_t *)in,   strlen(in));
    mbedtls_sha256_finish(&ctx, d);
    mbedtls_sha256_free(&ctx);
    for (int i = 0; i < 32; i++) sprintf(out65 + i*2, "%02x", d[i]);
    out65[64] = 0;
}

/* Writes exactly hex_chars characters plus a terminator.
 *
 * The previous version used sprintf("%08x") in steps of 8, but sprintf
 * also writes a NUL -- so the final call wrote 9 bytes. For a length that
 * is not a multiple of 8 (12, as used for passwords) that ran 4 bytes
 * past the caller's buffer and smashed the stack. Emit nibbles directly
 * so the write is exactly bounded whatever the length. */
static void rand_hex(char *out, int hex_chars) {
    static const char H[] = "0123456789abcdef";
    uint32_t r = 0;
    for (int i = 0; i < hex_chars; i++) {
        if ((i & 7) == 0) r = esp_random();
        out[i] = H[(r >> ((i & 7) * 4)) & 0x0F];
    }
    out[hex_chars] = 0;
}

/* Constant-time compare: a byte-by-byte early exit leaks how much of a
 * token was correct, which is enough to recover one a byte at a time. */
static bool safe_equal(const char *a, const char *b, size_t n) {
    uint8_t diff = 0;
    for (size_t i = 0; i < n; i++) diff |= (uint8_t)(a[i] ^ b[i]);
    return diff == 0;
}


/* Too many requests from one client in a short window. Relays are
 * mechanical and have a finite cycle life, so a flood is a hardware
 * destruction path, not just noise. */
static bool rate_ok(void) {
    uint32_t ip  = (uint32_t)server.client().remoteIP();
    uint32_t now = millis();
    rate_bucket_t *slot = NULL, *oldest = &rate_buckets[0];
    for (unsigned i = 0; i < sizeof(rate_buckets)/sizeof(rate_buckets[0]); i++) {
        if (rate_buckets[i].ip == ip) { slot = &rate_buckets[i]; break; }
        if (rate_buckets[i].window_start < oldest->window_start)
            oldest = &rate_buckets[i];
    }
    if (!slot) { slot = oldest; slot->ip = ip; slot->window_start = now; slot->count = 0; }
    if (now - slot->window_start > RATE_WINDOW_MS) {
        slot->window_start = now; slot->count = 0;
    }
    if (++slot->count > RATE_MAX_REQS) return false;
    return true;
}

/* Gate for every endpoint that changes something or leaks firmware.
 * Sends its own error response and returns false when it refuses. */
/* The credential in force right now: mesh password when meshed, device
 * password otherwise. One place decides, so nothing can disagree. */
static const char *active_pass(void) {
    return mesh_active ? mesh_pass : device_pass;
}

/* Session key is DERIVED from the active credential, so changing the
 * password rotates it automatically and every outstanding token dies.
 * That is the only revocation mechanism -- tokens do not expire. */
static void session_key(uint8_t *out16) {
    uint8_t mac[32];
    const char *p = active_pass();
    hmac_sha256((const uint8_t *)"unisync-session-v1",
                (const uint8_t *)p, strlen(p), mac);
    memcpy(out16, mac, 16);
}

/* Stateless token: nonce plus a MAC over it. Any master holding the same
 * credential validates a token it never issued, so roaming between
 * masters in a mesh needs no re-login, and a reboot logs nobody out. */
static void make_token(char *out) {
    uint8_t nonce[8], key[16], mac[32];
    for (int i = 0; i < 8; i += 4) {
        uint32_t r = esp_random();
        nonce[i]=r&0xFF; nonce[i+1]=(r>>8)&0xFF;
        nonce[i+2]=(r>>16)&0xFF; nonce[i+3]=(r>>24)&0xFF;
    }
    session_key(key);
    hmac_sha256(key, nonce, 8, mac);
    for (int i = 0; i < 8; i++)  sprintf(out + i*2,      "%02x", nonce[i]);
    for (int i = 0; i < 8; i++)  sprintf(out + 16 + i*2, "%02x", mac[i]);
    out[32] = 0;
}

static bool token_valid(const String &tok) {
    if (tok.length() != AUTH_TOKEN_LEN - 1) return false;
    uint8_t nonce[8], given[8], key[16], mac[32];
    for (int i = 0; i < 8; i++) {
        nonce[i] = (uint8_t)strtoul(tok.substring(i*2, i*2+2).c_str(), NULL, 16);
        given[i] = (uint8_t)strtoul(tok.substring(16+i*2, 16+i*2+2).c_str(), NULL, 16);
    }
    session_key(key);
    hmac_sha256(key, nonce, 8, mac);
    return ct_equal(mac, given, 8);
}

static bool auth_valid(void) {
    String tok = server.hasHeader("X-Auth") ? server.header("X-Auth")
                                            : server.arg("t");
    return token_valid(tok);
}

/* Responding gate for normal handlers. */
static bool auth_ok(void) {
    if (!rate_ok()) {
        server.send(429, "application/json", F("{\"error\":\"too many requests\"}"));
        return false;
    }
    if (auth_valid()) return true;
    server.send(401, "application/json", F("{\"error\":\"login required\"}"));
    return false;
}

/* ================================================================
 * FIRMWARE LIBRARY HELPERS
 * ================================================================ */
static uint32_t fw_crc32(const uint8_t *d, uint32_t n) {
    uint32_t c = 0xFFFFFFFF;
    while (n--) {
        c ^= *d++;
        for (int i = 0; i < 8; i++)
            c = (c & 1) ? (c >> 1) ^ 0xEDB88320UL : c >> 1;
    }
    return c ^ 0xFFFFFFFF;
}

/* true if a is strictly newer than b. Never equal, never older -- an
 * update must be an upgrade, or two masters holding different builds
 * would push an extension back and forth forever. */
static bool fw_ver_newer(const uint8_t *a, const uint8_t *b) {
    if (a[0] != b[0]) return a[0] > b[0];
    if (a[1] != b[1]) return a[1] > b[1];
    return a[2] > b[2];
}

/* Locate the descriptor the extension firmware embeds in its own image
 * and read the target type and version straight out of it, so the
 * operator never has to declare them by hand. */
static bool fw_parse_desc(const uint8_t *img, uint32_t len,
                          uint8_t *type, uint8_t *ver) {
    if (len < 16) return false;
    for (uint32_t i = 0; i + 16 <= len; i++) {
        if (memcmp(img + i, FW_DESC_MAGIC, 8) == 0) {
            *type  = img[i + 8];
            ver[0] = img[i + 10];
            ver[1] = img[i + 11];
            ver[2] = img[i + 12];
            return true;
        }
    }
    return false;
}

static String fw_path(uint8_t type) { return String("/fw/t") + String(type) + ".bin"; }

static bool fw_lookup(uint8_t type, fw_entry_t *out) {
    if (!fs_ready) return false;
    File f = LittleFS.open(FW_MANIFEST_PATH, "r");
    if (!f) return false;
    StaticJsonDocument<1024> doc;
    DeserializationError err = deserializeJson(doc, f);
    f.close();
    if (err) return false;
    for (JsonObject e : doc["images"].as<JsonArray>()) {
        if ((uint8_t)(e["type"] | 0) != type) continue;
        out->type   = type;
        out->ver[0] = e["ver"][0] | 0;
        out->ver[1] = e["ver"][1] | 0;
        out->ver[2] = e["ver"][2] | 0;
        /* Read as uint32_t explicitly. The "| 0" default deduces int, and a
         * CRC above 0x7FFFFFFF does not fit an int, so half of all images
         * would read back as 0 and be judged corrupt. */
        out->size   = e["size"].as<uint32_t>();
        out->crc    = e["crc"].as<uint32_t>();
        out->secver = e["sec"] | 0;
        const char *sg = e["sig"] | "";
        if (strlen(sg) != 64) return false;      /* unsigned image, refuse */
        for (int k=0;k<32;k++)
            out->sig[k]=(uint8_t)strtoul(String(sg).substring(k*2,k*2+2).c_str(),NULL,16);
        return out->size > 0;
    }
    return false;
}

/* Store an image and record it in the manifest. The manifest is only
 * updated after the image file is fully written and read back clean, so
 * a truncated write can never be handed to an extension. */
static bool fw_store(uint8_t type, const uint8_t *ver,
                     const uint8_t *img, uint32_t len,
                     uint8_t secver, const uint8_t *sig) {
    if (!fs_ready || len == 0 || len > FW_MAX_IMAGE) return false;
    /* Defence in depth: the extension is the authority, but refusing an
     * unsigned image here stops it being stored or gossiped onward. */
    if (!fw_key_set) { Serial.println("[FW] no firmware key, refusing"); return false; }
    uint8_t want[32];
    hmac_sha256(fw_key, img, len, want);
    if (!ct_equal(want, sig, 32)) {
        Serial.println("[FW] signature INVALID, image rejected");
        return false;
    }

    String path = fw_path(type);
    File f = LittleFS.open(path, "w");
    if (!f) { Serial.println("[FW] open for write failed"); return false; }
    uint32_t written = f.write(img, len);
    f.close();
    if (written != len) { Serial.println("[FW] short write"); return false; }

    uint32_t crc = fw_crc32(img, len);

    StaticJsonDocument<1024> doc;
    File m = LittleFS.open(FW_MANIFEST_PATH, "r");
    if (m) { deserializeJson(doc, m); m.close(); }
    if (!doc.containsKey("images")) doc.createNestedArray("images");

    JsonArray arr = doc["images"].as<JsonArray>();
    JsonObject tgt;
    bool found = false;
    for (JsonObject e : arr) {
        if ((uint8_t)(e["type"] | 0) == type) { tgt = e; found = true; break; }
    }
    if (!found) {
        if (arr.size() >= FW_MAX_TYPES) { Serial.println("[FW] manifest full"); return false; }
        tgt = arr.createNestedObject();
    }
    tgt["type"] = type;
    tgt["size"] = len;
    tgt["crc"]  = crc;
    tgt["sec"]  = secver;
    { char hx[65];
      for (int k=0;k<32;k++) sprintf(hx+k*2, "%02x", sig[k]);
      hx[64]=0; tgt["sig"] = hx; }
    JsonArray v = tgt.containsKey("ver") ? tgt["ver"].as<JsonArray>()
                                         : tgt.createNestedArray("ver");
    v.clear();
    v.add(ver[0]); v.add(ver[1]); v.add(ver[2]);

    m = LittleFS.open(FW_MANIFEST_PATH, "w");
    if (!m) { Serial.println("[FW] manifest open failed"); return false; }
    serializeJson(doc, m);
    m.close();

    Serial.printf("[FW] stored type=%u v%u.%u.%u %u bytes crc=0x%08X\n",
                  type, ver[0], ver[1], ver[2], len, crc);
    return true;
}

/* "11.9.2" -> {11,9,2} */
static void master_ver_parse(const char *s, uint8_t *v) {
    v[0] = v[1] = v[2] = 0;
    if (!s) return;
    int a = 0, b = 0, d = 0;
    if (sscanf(s, "%d.%d.%d", &a, &b, &d) >= 2) {
        v[0] = (uint8_t)a; v[1] = (uint8_t)b; v[2] = (uint8_t)d;
    }
}

/* Length of the application image actually running, walked out of the ESP
 * image header. The partition is far larger than the image, and serving
 * the trailing erased space would fail validation on the receiver. */
static uint32_t master_image_size(void) {
    const esp_partition_t *p = esp_ota_get_running_partition();
    if (!p) return 0;

    uint8_t hdr[24];
    if (esp_partition_read(p, 0, hdr, sizeof(hdr)) != ESP_OK) return 0;
    if (hdr[0] != 0xE9) return 0;                 /* not an ESP image */

    uint8_t  segments     = hdr[1];
    uint8_t  hash_present = hdr[23];
    uint32_t off          = sizeof(hdr);

    for (uint8_t i = 0; i < segments; i++) {
        uint8_t sh[8];
        if (esp_partition_read(p, off, sh, sizeof(sh)) != ESP_OK) return 0;
        uint32_t seg_len = (uint32_t)sh[4]        | ((uint32_t)sh[5] << 8)
                         | ((uint32_t)sh[6] << 16) | ((uint32_t)sh[7] << 24);
        if (seg_len > p->size) return 0;          /* corrupt header */
        off += 8 + seg_len;
        if (off > p->size) return 0;
    }
    off += 1;                    /* checksum byte */
    off  = (off + 15) & ~15u;    /* padded to 16 bytes */
    if (hash_present) off += 32; /* SHA-256 */
    return (off <= p->size) ? off : 0;
}

/* Read an image back into a caller-supplied buffer. */
static uint32_t fw_load(uint8_t type, uint8_t *buf, uint32_t max) {
    if (!fs_ready) return 0;
    File f = LittleFS.open(fw_path(type), "r");
    if (!f) return 0;
    uint32_t n = f.size();
    if (n == 0 || n > max) { f.close(); return 0; }
    uint32_t got = f.read(buf, n);
    f.close();
    return (got == n) ? n : 0;
}

static bool ext_ota_cmd(uint8_t addr, uint8_t cmd,
                         const uint8_t *payload, uint8_t plen,
                         uint32_t timeout_ms) {
    flush_rx();                       /* discard stale bytes before ACK read */
    bus_send(addr, cmd, payload, plen);
    uint8_t buf[16];
    uint8_t n = bus_recv(buf, sizeof(buf), timeout_ms);
    if (n < 6) {
        Serial.printf("[EXT-OTA] No ACK (cmd=0x%02X, got %d bytes)\n", cmd, n);
        if (n > 0) {
            Serial.print("[EXT-OTA] Raw: ");
            for (int i=0; i<n; i++) Serial.printf("%02X ", buf[i]);
            Serial.println();
        }
        return false;
    }
    if (buf[3] != CMD_OTA_ACK) {
        Serial.printf("[EXT-OTA] Wrong cmd: 0x%02X\n", buf[3]);
        return false;
    }
    if (buf[5] != 0x00) {
        Serial.printf("[EXT-OTA] ACK error: 0x%02X\n", buf[5]);
        return false;
    }
    return true;
}

static bool ext_ota_send(uint8_t addr, const uint8_t *fw, uint32_t fw_len,
                         uint8_t type, const uint8_t *ver,
                         uint8_t secver, const uint8_t *sig) {
    uint32_t crc = fw_crc32(fw, fw_len);
    Serial.printf("[EXT-OTA] type=%u v%u.%u.%u size=%u crc=0x%08X\n",
                  type, ver[0], ver[1], ver[2], fw_len, crc);

    /* OTA_BEGIN: size[4] crc[4] type[1] ver[3].
     * The extension rejects a type mismatch here, before any flash is
     * touched, so a wrong image costs one frame instead of a brick. */
    /* size[4] crc[4] type[1] ver[3] secver[1] hmac[32] */
    uint8_t payload[45];
    payload[0]=(fw_len>>24)&0xFF; payload[1]=(fw_len>>16)&0xFF;
    payload[2]=(fw_len>>8)&0xFF;  payload[3]=fw_len&0xFF;
    payload[4]=(crc>>24)&0xFF;    payload[5]=(crc>>16)&0xFF;
    payload[6]=(crc>>8)&0xFF;     payload[7]=crc&0xFF;
    payload[8]=type;
    payload[9]=ver[0]; payload[10]=ver[1]; payload[11]=ver[2];
    payload[12]=secver;
    memcpy(&payload[13], sig, 32);
    if (!ext_ota_cmd(addr, CMD_OTA_BEGIN, payload, 45, 1000)) return false;
    Serial.println("[EXT-OTA] BEGIN ok");
    vTaskDelay(pdMS_TO_TICKS(100)); /* give extension time to enter OTA mode */

    /* Send chunks */
    uint32_t offset = 0; uint16_t chunk_idx = 0;
    while (offset < fw_len) {
        uint8_t chunk[2 + EXT_OTA_CHUNK_SIZE];
        uint8_t len = (fw_len - offset) >= EXT_OTA_CHUNK_SIZE ?
                       EXT_OTA_CHUNK_SIZE : (fw_len - offset);
        chunk[0] = (chunk_idx >> 8) & 0xFF;
        chunk[1] = chunk_idx & 0xFF;
        memcpy(&chunk[2], fw + offset, len);
        bool acked = false;
        for (int attempt = 0; attempt < 3 && !acked; attempt++) {
            acked = ext_ota_cmd(addr, CMD_OTA_CHUNK, chunk, 2+len, 1000);
            if (!acked) {
                Serial.printf("[EXT-OTA] CHUNK %u retry %d\n", chunk_idx, attempt+1);
                vTaskDelay(pdMS_TO_TICKS(50));
            }
        }
        if (!acked) {
            Serial.printf("[EXT-OTA] CHUNK %u failed after 3 tries\n", chunk_idx);
            return false;
        }
        offset += len; chunk_idx++;
        if (chunk_idx % 10 == 0)
            Serial.printf("[EXT-OTA] %u/%u bytes\n", offset, fw_len);
        vTaskDelay(pdMS_TO_TICKS(5));  /* yield; ACK already gates us */
    }
    Serial.println("[EXT-OTA] All chunks sent");

    /* OTA_END */
    if (!ext_ota_cmd(addr, CMD_OTA_END, nullptr, 0, 3000)) return false;
    Serial.println("[EXT-OTA] END ok -- extension rebooting");
    return true;
}

/* ================================================================
 * MASTER FIRMWARE CONVERGENCE
 * Pull the running image off whichever online peer reports the highest
 * version, apply it, reboot. Retried on a backoff until the mesh agrees,
 * so it converges regardless of which masters were reachable when.
 * ================================================================ */
/* Bring our own access point back after a pull. Re-issuing softAP() is
 * required: setting the mode alone does not restart it with our SSID. */
static void master_restore_ap(void) {
    WiFi.disconnect(true, true);
    WiFi.mode(WIFI_AP);
    vTaskDelay(pdMS_TO_TICKS(100));
    /* Bring back the AP this master actually owns. Hard-coding the mesh
     * credentials is only safe while this is reached exclusively from the
     * mesh pull path -- a standalone master would otherwise reappear on an
     * SSID it was never part of, with a password its owner does not know.
     * Latent today (a standalone master has no peers to pull from and
     * returns early), but it costs nothing to be correct here. */
    const char *ap_ssid = mesh_active ? mesh_name : unique_ssid;
    WiFi.softAP(ap_ssid, active_pass(), AP_CHANNEL);
    vTaskDelay(pdMS_TO_TICKS(200));
    /* WiFi.disconnect(true,true) resets the driver, which takes ESP-NOW
     * with it. On the success path we reboot immediately so it hardly
     * matters, but after a FAILED pull this node keeps running -- without
     * this it would stay silently outside the mesh until someone power
     * cycled it, and would never retry the update. */
    if (mesh_active) {
        esp_now_deinit();
        mesh_init();
        Serial.println("[MFW] mesh radio reinitialised");
    }
    Serial.printf("[MFW] access point restored: %s\n", ap_ssid);
}

static void master_fw_sync(void) {
    if (!mesh_active || master_pull_active || master_serve_busy) return;
    if (ota_in_progress) return;                      /* bus OTA running   */
    if (master_pull_gate && (int32_t)(millis() - master_pull_gate) < 0) return;

    /* Highest version wins; among equals, the one we hear best wins.
     * A distant master holding the newest build may be perfectly audible
     * over ESP-NOW yet impossible to download from, so once a nearer peer
     * has caught up we must prefer it -- otherwise the update never
     * propagates past the edge of the mesh. Peers that just failed are
     * skipped so a bad link cannot monopolise every attempt. */
    int      best = -1;
    uint8_t  best_ver[3] = { master_fw[0], master_fw[1], master_fw[2] };
    int8_t   best_rssi = -128;
    uint8_t  mac[6];
    uint32_t now_ms = millis();
    xSemaphoreTake(state_mutex, portMAX_DELAY);
    for (int i = 0; i < MAX_MESH_MASTERS; i++) {
        if (!mesh_peers[i].online) continue;
        if (mesh_peers[i].fw_fail_until &&
            (int32_t)(now_ms - mesh_peers[i].fw_fail_until) < 0) continue;
        bool newer = fw_ver_newer(mesh_peers[i].fw, best_ver);
        bool equal = (best >= 0) &&
                     mesh_peers[i].fw[0] == best_ver[0] &&
                     mesh_peers[i].fw[1] == best_ver[1] &&
                     mesh_peers[i].fw[2] == best_ver[2];
        if (!newer && !(equal && mesh_peers[i].rssi > best_rssi)) continue;
        best = i;
        best_ver[0] = mesh_peers[i].fw[0];
        best_ver[1] = mesh_peers[i].fw[1];
        best_ver[2] = mesh_peers[i].fw[2];
        best_rssi   = mesh_peers[i].rssi;
        memcpy(mac, mesh_peers[i].mac, 6);
    }
    xSemaphoreGive(state_mutex);
    if (best < 0) return;                             /* already newest    */

    Serial.printf("[MFW] peer v%u.%u.%u rssi=%d, we run v%u.%u.%u -- pulling\n",
                  best_ver[0], best_ver[1], best_ver[2], best_rssi,
                  master_fw[0], master_fw[1], master_fw[2]);

    /* Spread the herd: several masters will spot the same peer at once and
     * it can only serve one at a time. */
    vTaskDelay(pdMS_TO_TICKS(esp_random() % MASTER_PULL_JITTER));

    master_pull_active = true;
    master_pull_gate   = millis() + MASTER_PULL_BACKOFF;

    /* Drop our own AP for the duration of the pull.
     *
     * Every master serves its SoftAP on 192.168.4.1/24, so in AP_STA mode
     * the STA interface lands on the same subnet as our own AP and lwIP
     * resolves the peer's gateway -- also 192.168.4.1 -- to our local AP
     * interface. The request never leaves the device and HTTPClient
     * returns -1. Running STA-only removes the collision.
     *
     * Our clients drop for the duration; on success we reboot into the new
     * image anyway, and on failure the AP is restored below. */
    WiFi.softAPdisconnect(true);
    WiFi.mode(WIFI_STA);
    vTaskDelay(pdMS_TO_TICKS(200));
    /* All masters in a mesh share one SSID, so the BSSID selects the peer. */
    WiFi.begin(mesh_name, mesh_pass, AP_CHANNEL, mac);

    uint32_t t0 = millis();
    while (WiFi.status() != WL_CONNECTED && (millis() - t0) < 20000)
        vTaskDelay(pdMS_TO_TICKS(200));

    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("[MFW] could not join peer AP -- trying another next time");
        master_restore_ap();
        xSemaphoreTake(state_mutex, portMAX_DELAY);
        mesh_peers[best].fw_fail_until = millis() + MASTER_PEER_COOLDOWN;
        xSemaphoreGive(state_mutex);
        /* Association failed, not a download failure: come back quickly and
         * pick a different source rather than idling the full backoff. */
        master_pull_gate   = millis() + MASTER_SYNC_MS;
        master_pull_active = false;
        return;
    }
    Serial.printf("[MFW] joined peer, gateway %s\n",
                  WiFi.gatewayIP().toString().c_str());

    bool ok = false;
    {
        HTTPClient http;
        String url = "http://" + WiFi.gatewayIP().toString() +
                     "/api/ota/image?k=" + String(mesh_pass);
        http.setTimeout(20000);
        if (http.begin(url)) {
            int code = http.GET();
            int len  = http.getSize();
            if (code == 200 && len > 0) {
                Serial.printf("[MFW] downloading %d bytes\n", len);
                if (Update.begin((size_t)len)) {
                    size_t written = Update.writeStream(http.getStream());
                    if (written == (size_t)len && Update.end(true)) {
                        ok = true;
                    } else {
                        Serial.printf("[MFW] apply failed: %s\n",
                                      Update.errorString());
                        Update.abort();
                    }
                } else {
                    Serial.printf("[MFW] no space: %s\n", Update.errorString());
                }
            } else {
                Serial.printf("[MFW] GET failed code=%d len=%d\n", code, len);
            }
            http.end();
        }
    }

    master_restore_ap();
    master_pull_active = false;

    if (ok) {
        Serial.println("[MFW] image applied -- restarting");
        vTaskDelay(pdMS_TO_TICKS(500));
        ESP.restart();
    }
    xSemaphoreTake(state_mutex, portMAX_DELAY);
    mesh_peers[best].fw_fail_until = millis() + MASTER_PEER_COOLDOWN;
    xSemaphoreGive(state_mutex);
    Serial.println("[MFW] pull failed, will try another source");
}

/* ================================================================
 * RECONCILIATION
 * Converge every online extension toward the manifest. Runs from the bus
 * task so it can never overlap a poll, one extension at a time because
 * the RS-485 bus is shared and half duplex.
 * ================================================================ */
static void fw_reconcile(void) {
    if (!fs_ready || ota_in_progress) return;
    if (master_pull_active || master_serve_busy) return;  /* radio/CPU busy */

    for (int i = 0; i < MAX_EXTENSIONS; i++) {
        xSemaphoreTake(state_mutex, portMAX_DELAY);
        bool     ready = (extensions[i].state == EXT_ONLINE);
        uint8_t  addr  = extensions[i].address;
        uint8_t  type  = extensions[i].hw_type;
        uint8_t  cur[3] = { extensions[i].fw_ver[0],
                            extensions[i].fw_ver[1],
                            extensions[i].fw_ver[2] };
        uint8_t  fails = extensions[i].ota_fails;
        uint32_t gate  = extensions[i].ota_next_try_ms;
        xSemaphoreGive(state_mutex);

        if (!ready) continue;
        if (type == 0 || type == 0xFF) continue;      /* identity not known */

        fw_entry_t e;
        if (!fw_lookup(type, &e)) continue;
        if (!fw_ver_newer(e.ver, cur)) continue;      /* upgrades only */

        /* The retry budget belongs to a specific image, not to the device.
         * A newer build in the library is a different attempt and deserves
         * a fresh budget -- otherwise three failures against one bad image
         * would lock that switch out of every future update, permanently
         * and silently. */
        xSemaphoreTake(state_mutex, portMAX_DELAY);
        bool same_image = (extensions[i].ota_fail_ver[0] == e.ver[0] &&
                           extensions[i].ota_fail_ver[1] == e.ver[1] &&
                           extensions[i].ota_fail_ver[2] == e.ver[2]);
        if (!same_image && extensions[i].ota_fails) {
            extensions[i].ota_fails       = 0;
            extensions[i].ota_next_try_ms = 0;
            fails = 0; gate = 0;
            Serial.printf("[FW] ext 0x%02X: new version available, retrying\n", addr);
        }
        xSemaphoreGive(state_mutex);

        if (fails >= OTA_MAX_FAILS) continue;         /* given up on THIS image */
        if (gate && (int32_t)(millis() - gate) < 0) continue;

        uint8_t *img = (uint8_t *)malloc(e.size);
        if (!img) { Serial.println("[FW] reconcile: out of memory"); return; }
        uint32_t n = fw_load(type, img, e.size);
        if (n != e.size || fw_crc32(img, n) != e.crc) {
            Serial.printf("[FW] stored image for type %u is corrupt, ignoring\n", type);
            free(img);
            continue;
        }

        Serial.printf("[FW] updating ext 0x%02X type=%u v%u.%u.%u -> v%u.%u.%u\n",
                      addr, type, cur[0], cur[1], cur[2], e.ver[0], e.ver[1], e.ver[2]);

        ota_in_progress = true;
        vTaskDelay(pdMS_TO_TICKS(200));
        bool ok = ext_ota_send(addr, img, n, type, e.ver, e.secver, e.sig);
        ota_in_progress = false;
        free(img);

        xSemaphoreTake(state_mutex, portMAX_DELAY);
        if (ok) {
            extensions[i].ota_fails       = 0;
            extensions[i].ota_next_try_ms = 0;
            /* Version is re-learned from CMD_GET_INFO once it re-registers. */
            extensions[i].hw_type         = type;
        } else {
            extensions[i].ota_fails++;
            extensions[i].ota_fail_ver[0] = e.ver[0];
            extensions[i].ota_fail_ver[1] = e.ver[1];
            extensions[i].ota_fail_ver[2] = e.ver[2];
            extensions[i].ota_next_try_ms = millis() + OTA_BACKOFF_MS;
            Serial.printf("[FW] ext 0x%02X update failed (%u/%u)\n",
                          addr, extensions[i].ota_fails, OTA_MAX_FAILS);
        }
        xSemaphoreGive(state_mutex);
        notify_ui();
        return;   /* one extension per pass; bus stays responsive */
    }
}

/* ================================================================
 * MESH FIRMWARE DISTRIBUTION
 * Stop-and-wait, receiver driven: the peer asks for the chunk it wants
 * next, so delivery is inherently ordered and a lost packet costs one
 * retry instead of the whole transfer.
 * ================================================================ */
static void fw_pkt_hdr(uint8_t *p, uint8_t sub, uint8_t type,
                       const uint8_t *ver, uint16_t idx, uint16_t total,
                       uint32_t size, uint32_t crc,
                       uint8_t secver, const uint8_t *sig) {
    p[0]=FWPKT_MAGIC; p[1]=sub; p[2]=type;
    p[3]=ver[0]; p[4]=ver[1]; p[5]=ver[2];
    p[6]=idx & 0xFF;    p[7]=(idx >> 8) & 0xFF;
    p[8]=total & 0xFF;  p[9]=(total >> 8) & 0xFF;
    p[10]=size & 0xFF;  p[11]=(size >> 8) & 0xFF;
    p[12]=crc & 0xFF;        p[13]=(crc >> 8) & 0xFF;
    p[14]=(crc >> 16) & 0xFF; p[15]=(crc >> 24) & 0xFF;
    p[16]=secver;
    for (int i=0;i<32;i++) p[17+i] = sig ? sig[i] : 0;
}

/* Offer an image to every known peer. They pull what they want. */
static void fw_mesh_offer(uint8_t type, const uint8_t *ver,
                          uint32_t size, uint32_t crc,
                          uint8_t secver, const uint8_t *sig) {
    if (!mesh_active) return;
    uint16_t total = (size + FWPKT_DATA - 1) / FWPKT_DATA;
    uint8_t pkt[FWPKT_HDR];
    fw_pkt_hdr(pkt, FWPKT_OFFER, type, ver, 0, total, size, crc, secver, sig);
    int sent = 0;
    xSemaphoreTake(state_mutex, portMAX_DELAY);
    for (int i = 0; i < MAX_MESH_MASTERS; i++) {
        if (!mesh_peers[i].online) continue;
        uint8_t mac[6]; memcpy(mac, mesh_peers[i].mac, 6);
        xSemaphoreGive(state_mutex);
        mesh_send(mac, pkt, sizeof(pkt));
        sent++;
        xSemaphoreTake(state_mutex, portMAX_DELAY);
    }
    xSemaphoreGive(state_mutex);
    Serial.printf("[FW-MESH] offered type=%u v%u.%u.%u to %d peer(s)\n",
                  type, ver[0], ver[1], ver[2], sent);
}

static void fwrx_abort(const char *why) {
    if (fwrx_buf) { free(fwrx_buf); fwrx_buf = nullptr; }
    fwrx_active = false;
    Serial.printf("[FW-MESH] receive aborted: %s\n", why);
}

static void fw_mesh_rx(const uint8_t *src, const uint8_t *d, int len) {
    if (!mesh_active || len < FWPKT_HDR) return;
    /* Firmware may only arrive from an enrolled peer. Without this any
     * transmitter in range could offer an image and have it propagate to
     * every master and every switch. */
    bool known = false;
    xSemaphoreTake(state_mutex, portMAX_DELAY);
    for (int i = 0; i < MAX_MESH_MASTERS; i++)
        if (mesh_peers[i].online && memcmp(mesh_peers[i].mac, src, 6) == 0) {
            known = true; break;
        }
    xSemaphoreGive(state_mutex);
    if (!known) return;

    uint8_t  sub   = d[1];
    uint8_t  type  = d[2];
    uint8_t  ver[3]= { d[3], d[4], d[5] };
    uint16_t idx   = (uint16_t)d[6] | ((uint16_t)d[7] << 8);
    uint16_t total = (uint16_t)d[8] | ((uint16_t)d[9] << 8);
    uint32_t size  = (uint32_t)d[10] | ((uint32_t)d[11] << 8);
    uint32_t crc   = (uint32_t)d[12] | ((uint32_t)d[13] << 8)
                   | ((uint32_t)d[14] << 16) | ((uint32_t)d[15] << 24);
    uint8_t  secv  = d[16];
    const uint8_t *sigp = &d[17];

    if (sub == FWPKT_OFFER) {
        if (fwrx_active) return;                       /* already busy */
        if (size == 0 || size > FW_MAX_IMAGE) return;
        fw_entry_t have;
        if (fw_lookup(type, &have) && !fw_ver_newer(ver, have.ver)) return;
        fwrx_buf = (uint8_t *)malloc(size);
        if (!fwrx_buf) { Serial.println("[FW-MESH] no heap for offer"); return; }
        fwrx_active = true; fwrx_type = type;
        fwrx_ver[0]=ver[0]; fwrx_ver[1]=ver[1]; fwrx_ver[2]=ver[2];
        fwrx_size = size; fwrx_crc = crc; fwrx_total = total; fwrx_next = 0;
        fwrx_sec = secv; memcpy(fwrx_sig, sigp, 32);
        memcpy(fwrx_src, src, 6);
        fwrx_last_ms = millis();
        Serial.printf("[FW-MESH] accepting type=%u v%u.%u.%u %u bytes\n",
                      type, ver[0], ver[1], ver[2], size);
        uint8_t req[FWPKT_HDR];
        fw_pkt_hdr(req, FWPKT_REQ, type, ver, 0, total, size, crc, 0, NULL);
        mesh_send(fwrx_src, req, sizeof(req));
        return;
    }

    if (sub == FWPKT_REQ) {
        /* We are the origin: serve the requested chunk from our copy. */
        fw_entry_t e;
        if (!fw_lookup(type, &e)) return;
        if (e.ver[0]!=ver[0] || e.ver[1]!=ver[1] || e.ver[2]!=ver[2]) return;
        uint32_t off = (uint32_t)idx * FWPKT_DATA;
        if (off >= e.size) return;
        uint32_t n = e.size - off;
        if (n > FWPKT_DATA) n = FWPKT_DATA;

        File f = LittleFS.open(fw_path(type), "r");
        if (!f) return;
        if (!f.seek(off)) { f.close(); return; }
        uint8_t pkt[FWPKT_HDR + FWPKT_DATA];
        uint16_t tot = (e.size + FWPKT_DATA - 1) / FWPKT_DATA;
        fw_pkt_hdr(pkt, FWPKT_CHUNK, type, e.ver, idx, tot, e.size, e.crc,
                   e.secver, e.sig);
        uint32_t got = f.read(pkt + FWPKT_HDR, n);
        f.close();
        if (got != n) return;
        mesh_send(src, pkt, FWPKT_HDR + n);
        return;
    }

    if (sub == FWPKT_CHUNK) {
        if (!fwrx_active || memcmp(src, fwrx_src, 6) != 0) return;
        if (type != fwrx_type || idx != fwrx_next) return;   /* out of order */
        uint32_t off = (uint32_t)idx * FWPKT_DATA;
        uint32_t n   = (uint32_t)len - FWPKT_HDR;
        if (off + n > fwrx_size) { fwrx_abort("overrun"); return; }
        memcpy(fwrx_buf + off, d + FWPKT_HDR, n);
        fwrx_next++;
        fwrx_last_ms = millis();

        if (off + n >= fwrx_size) {
            if (fw_crc32(fwrx_buf, fwrx_size) != fwrx_crc) {
                fwrx_abort("CRC mismatch");
                return;
            }
            bool ok = fw_store(fwrx_type, fwrx_ver, fwrx_buf, fwrx_size,
                               fwrx_sec, fwrx_sig);
            uint8_t done[FWPKT_HDR];
            fw_pkt_hdr(done, FWPKT_DONE, fwrx_type, fwrx_ver, 0,
                       fwrx_total, fwrx_size, fwrx_crc, 0, NULL);
            mesh_send(fwrx_src, done, sizeof(done));
            free(fwrx_buf); fwrx_buf = nullptr; fwrx_active = false;
            Serial.printf("[FW-MESH] image received and %s\n",
                          ok ? "stored" : "REJECTED by storage");
            notify_ui();
            return;
        }
        uint8_t req[FWPKT_HDR];
        fw_pkt_hdr(req, FWPKT_REQ, fwrx_type, fwrx_ver, fwrx_next,
                   fwrx_total, fwrx_size, fwrx_crc, 0, NULL);
        mesh_send(fwrx_src, req, sizeof(req));
        return;
    }

    if (sub == FWPKT_DONE) {
        Serial.printf("[FW-MESH] peer confirmed type=%u v%u.%u.%u\n",
                      type, ver[0], ver[1], ver[2]);
        return;
    }
}

/* Re-ask if a chunk goes missing; give up rather than hang forever. */
static void fw_mesh_tick(void) {
    if (!fwrx_active) return;
    if ((millis() - fwrx_last_ms) < FWRX_TIMEOUT_MS) return;
    static uint8_t stalls = 0;
    if (++stalls > 10) { stalls = 0; fwrx_abort("peer stopped responding"); return; }
    uint8_t req[FWPKT_HDR];
    fw_pkt_hdr(req, FWPKT_REQ, fwrx_type, fwrx_ver, fwrx_next,
               fwrx_total, fwrx_size, fwrx_crc, 0, NULL);
    mesh_send(fwrx_src, req, sizeof(req));
    fwrx_last_ms = millis();
}

/* Master firmware convergence runs on its own task: a pull holds the CPU
 * for up to a minute while WiFi associates and 1.1 MB transfers, and doing
 * that inside the bus task would drop every extension offline. */
static void task_fwsync(void *arg) {
    vTaskDelay(pdMS_TO_TICKS(20000));      /* let the mesh settle first */
    for (;;) {
        master_fw_sync();
        vTaskDelay(pdMS_TO_TICKS(MASTER_SYNC_MS));
    }
}

/* ================================================================
 * BLE RECOVERY SERVICE
 * ================================================================ */
/* The nonce is per connection, not global. It used to be one shared
 * buffer regenerated on every onConnect, so a second phone connecting
 * silently invalidated the first phone's proofs; the first would re-read
 * the nonce, restart its counter at 1, and then be rejected by the replay
 * guard as stale -- two clients permanently broke each other, even though
 * the firmware allows three and the spec requires concurrent control. */
static void ble_fill_nonce(uint8_t *dst) {
    for (int i = 0; i < 8; i += 4) {
        uint32_t r = esp_random();
        dst[i]=r&0xFF; dst[i+1]=(r>>8)&0xFF;
        dst[i+2]=(r>>16)&0xFF; dst[i+3]=(r>>24)&0xFF;
    }
}

/* Index of the connection owning a handle, or -1. */
static int ble_conn_index(uint16_t handle) {
    for (int i = 0; i < BLE_MAX_CONN; i++)
        if (ble_conns[i].used && ble_conns[i].handle == handle) return i;
    return -1;
}

/* Placeholder only: each reader is served its own nonce by BleSNonceCB. */
static void ble_new_session_nonce(void) {
    ble_fill_nonce(ble_snonce);
    if (ble_snonce_char) ble_snonce_char->setValue(ble_snonce, 8);
}

static void ble_new_nonce(void) {
    for (int i = 0; i < 8; i += 4) {
        uint32_t r = esp_random();
        ble_nonce[i]=r&0xFF; ble_nonce[i+1]=(r>>8)&0xFF;
        ble_nonce[i+2]=(r>>16)&0xFF; ble_nonce[i+3]=(r>>24)&0xFF;
    }
    if (ble_chal_char) ble_chal_char->setValue(ble_nonce, 8);
}

/* Keystream from the recovery key and the challenge nonce. XOR is its own
 * inverse, so one routine both wraps and unwraps.
 *
 * This is what keeps the new whole-home password off the air in the clear.
 * The old flow had the *master* choose the password and notify it back
 * unencrypted over an open link -- anyone in radio range with a sniffer got
 * the key to the house. */
static void rkey_wrap(const uint8_t *rkey, const uint8_t *nonce8,
                      uint8_t *buf, uint16_t n) {
    uint8_t key[32], ks[32];
    hmac_sha256(rkey, nonce8, 8, key);
    for (uint16_t off = 0; off < n; off += 32) {
        uint8_t ctr[36];
        memcpy(ctr, key, 32);
        ctr[32]=(off>>24)&0xFF; ctr[33]=(off>>16)&0xFF;
        ctr[34]=(off>>8)&0xFF;  ctr[35]=off&0xFF;
        hmac_sha256(key, ctr, sizeof(ctr), ks);
        for (uint16_t k = 0; k < 32 && off + k < n; k++)
            buf[off + k] ^= ks[k];
    }
}

/* Seconds still to wait, 0 when an attempt is allowed now. */
static uint32_t rec_wait_s(void) {
    if (!rec_next_ms) return 0;
    int32_t left = (int32_t)(rec_next_ms - millis());
    if (left <= 0) return 0;
    return (uint32_t)((left + 999) / 1000);
}

static void rec_broadcast_gate(void) {
    if (!mesh_active) return;
    char self_uid[12];
    snprintf(self_uid, sizeof(self_uid), "%02X%02X%02X%02X",
             master_uid[0], master_uid[1], master_uid[2], master_uid[3]);
    StaticJsonDocument<128> doc;
    doc["type"] = MESH_PKT_RECFAIL;
    doc["uid"]  = self_uid;
    doc["f"]    = rec_fails;
    doc["w"]    = rec_wait_s();
    String payload; serializeJson(doc, payload);
    mesh_broadcast(payload.c_str(), payload.length() + 1);
}

/* One rejection: advance the schedule and tell the rest of the mesh. */
static void rec_note_failure(void) {
    if (rec_fails < 16) rec_fails++;
    uint32_t wait_s = REC_BACKOFF_BASE_S;
    for (uint8_t i = 1; i < rec_fails && wait_s < REC_BACKOFF_MAX_S; i++)
        wait_s *= 2;
    if (wait_s > REC_BACKOFF_MAX_S) wait_s = REC_BACKOFF_MAX_S;
    rec_next_ms = millis() + wait_s * 1000UL;
    rec_broadcast_gate();
}

static void rec_clear_gate(void) {
    rec_fails   = 0;
    rec_next_ms = 0;
    rec_broadcast_gate();
}

/* The verdict, as the app reads it. Explicit accept/reject replaced the
 * old silent timeout: the recovery key's entropy plus a device-enforced
 * doubling backoff is what makes a straight answer safe to give. */
static void rec_reply(bool ok, const char *why) {
    StaticJsonDocument<128> doc;
    doc["v"]  = 2;
    doc["ok"] = ok;
    if (ok) {
        /* The master decides the scope, never the app: it is the one that
         * knows whether it is meshed. */
        doc["scope"] = mesh_active ? "mesh" : "device";
    } else {
        doc["wait"] = rec_wait_s();
        if (why) doc["err"] = why;
    }
    String out; serializeJson(doc, out);
    if (ble_result_char) {
        ble_result_char->setValue((uint8_t *)out.c_str(), out.length());
        ble_result_char->notify();
    }
}

class BleRespCB : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic *ch, NimBLEConnInfo &info) override {
        /* Runs on the BLE task. Do the cheap checks here, hand the actual
         * credential change to task_web -- NVS writes and an AP restart do
         * not belong on this stack.
         *
         * Request (v2), written in one go:
         *   [0]      version, 0x02
         *   [1]      password length, 8..63
         *   [2..9]   HMAC-SHA256(recovery_key, nonce8 || ver || len || wrapped)[0..7]
         *   [10..]   the new password, wrapped with rkey_wrap
         *
         * The app chooses the password and it never crosses in the clear;
         * the proof authenticates the whole request, so neither the key nor
         * the password can be lifted from a recorded exchange. */
        NimBLEAttValue av = ch->getValue();
        const uint8_t *req = av.data();
        uint16_t rlen = av.length();

        if (!factory_set) { rec_reply(false, "not provisioned"); return; }

        /* The gate is enforced here, whatever the client believes. */
        if (rec_wait_s() > 0) { rec_reply(false, "too soon"); return; }

        if (rlen < 10 + 8 || req[0] != 0x02) {
            rec_note_failure();
            rec_reply(false, "malformed");
            ble_new_nonce();
            return;
        }
        uint8_t plen = req[1];
        if (plen < PASS_MIN_LEN || plen > 63 || (uint16_t)(10 + plen) != rlen) {
            rec_note_failure();
            rec_reply(false, "malformed");
            ble_new_nonce();
            return;
        }

        /* Proof covers the wrapped password too, so a recorded request
         * cannot be replayed with a different one grafted on. */
        uint8_t msg[8 + 2 + 64];
        memcpy(msg, ble_nonce, 8);
        msg[8] = req[0];
        msg[9] = req[1];
        memcpy(msg + 10, req + 10, plen);
        uint8_t want[32];
        hmac_sha256(recovery_key, msg, 10 + plen, want);
        if (!ct_equal(want, req + 2, 8)) {
            rec_note_failure();
            rec_reply(false, "wrong recovery key");
            ble_new_nonce();
            return;
        }

        uint8_t clear[64];
        memcpy(clear, req + 10, plen);
        rkey_wrap(recovery_key, ble_nonce, clear, plen);
        memcpy(ble_new_pass, clear, plen);
        ble_new_pass[plen] = 0;
        memset(clear, 0, sizeof(clear));
        memset(msg, 0, sizeof(msg));

        rec_clear_gate();
        rec_reply(true, nullptr);
        ble_recover_ready = true;
        ble_new_nonce();
    }
};

/* Serves the calling connection its own nonce. Without this the single
 * stored characteristic value would hand every client whichever nonce was
 * generated last. */
class BleSNonceCB : public NimBLECharacteristicCallbacks {
    void onRead(NimBLECharacteristic *ch, NimBLEConnInfo &info) override {
        int idx = ble_conn_index(info.getConnHandle());
        if (idx >= 0) ch->setValue(ble_conns[idx].snonce, 8);
        else          ch->setValue(ble_snonce, 8);
    }
};

class BleChalCB : public NimBLECharacteristicCallbacks {
    void onRead(NimBLECharacteristic *ch, NimBLEConnInfo &info) override {
        ch->setValue(ble_nonce, 8);
    }
};

/* The result characteristic now carries a verdict, not a credential -- the
 * password travels the other way, wrapped, and is chosen by the app. It is
 * still cleared on every connect and disconnect: a stale "accepted" left
 * readable would tell the next person in radio range that a recovery just
 * succeeded, and there is no reason to hand that out. */
static void ble_clear_recovery_result(void) {
    if (ble_result_char) ble_result_char->setValue((uint8_t *)"", 0);
    /* Deliberately does NOT touch ble_new_pass: task_web consumes it in
     * ble_recovery_apply(), which can run after the client has gone.
     * Wiping it here would apply an empty password to the whole home.
     * That buffer is zeroed in ble_recovery_apply() once it is spent. */
}

/* Same effect as POST /api/relay, driven from the BLE transport.
 * Mirrors the HTTP handler's semantics deliberately: id "master_1" or
 * "ext<slot>_<ch>", state applied, queued to the same task. */
static bool ble_set_relay_by_id(const char *id_c, bool st) {
    String id(id_c);
    int us = id.indexOf('_');
    if (us <= 0) {
        Serial.printf("[BLE] id '%s' has no '_<channel>' suffix\n", id_c);
        return false;
    }
    int ch = id.substring(us+1).toInt();
    if (ch != 1 && ch != 2) {
        Serial.printf("[BLE] id '%s' channel must be 1 or 2\n", id_c);
        return false;
    }

    if (id.startsWith("master")) {
        relay_cmd_t cmd; cmd.target = -1; cmd.channel = ch; cmd.state = st;
        xQueueSend(master_relay_queue, &cmd, 0);
        return true;
    }
    if (id.startsWith("ext")) {
        int slot = id.substring(3, us).toInt();
        if (slot < 0 || slot >= MAX_EXTENSIONS) {
            Serial.printf("[BLE] slot %d out of range\n", slot);
            return false;
        }
        relay_cmd_t cmd; cmd.target = slot; cmd.channel = ch; cmd.state = st;
        xSemaphoreTake(state_mutex, portMAX_DELAY);
        if (ch == 1) extensions[slot].relay1 = st;
        else         extensions[slot].relay2 = st;
        xSemaphoreGive(state_mutex);
        xQueueSend(ext_relay_queue, &cmd, 0);
        relay_state_save();
        notify_ui();
        return true;
    }
    Serial.printf("[BLE] id '%s' is neither master nor ext\n", id_c);
    return false;
}

static void ble_killall(void) {
    xSemaphoreTake(state_mutex, portMAX_DELAY);
    master_relay1 = false;
    master_relay2 = false;
    for (int i = 0; i < MAX_EXTENSIONS; i++) {
        if (extensions[i].state == EXT_EMPTY) continue;
        extensions[i].relay1 = false;
        extensions[i].relay2 = false;
        relay_cmd_t e1; e1.target=i; e1.channel=1; e1.state=false;
        relay_cmd_t e2; e2.target=i; e2.channel=2; e2.state=false;
        xQueueSend(ext_relay_queue, &e1, 0);
        xQueueSend(ext_relay_queue, &e2, 0);
    }
    xSemaphoreGive(state_mutex);
    relay_cmd_t m1; m1.target=-1; m1.channel=1; m1.state=false;
    relay_cmd_t m2; m2.target=-1; m2.channel=2; m2.state=false;
    xQueueSend(master_relay_queue, &m1, 0);
    xQueueSend(master_relay_queue, &m2, 0);
    mesh_killall_peers();
    relay_state_save();
    notify_ui();
}

/* Notifications are capped by the negotiated MTU, and a state document is
 * larger than that, so responses go out in numbered chunks:
 *   byte 0 = index, byte 1 = total, rest = payload.
 * The app reassembles in order and parses once index == total-1. */
static void ble_notify_chunked(NimBLECharacteristic *ch, const String &s) {
    if (!ch || !ble_connected) {
        Serial.println("[BLE] notify skipped: no client");
        return;
    }
    uint16_t n = s.length();
    uint8_t total = (uint8_t)((n + BLE_CHUNK - 1) / BLE_CHUNK);
    if (total == 0) total = 1;
    for (uint8_t i = 0; i < total; i++) {
        uint16_t off = (uint16_t)i * BLE_CHUNK;
        uint16_t len = (n - off > BLE_CHUNK) ? BLE_CHUNK : (n - off);
        uint8_t pkt[BLE_CHUNK + 2];
        pkt[0] = i; pkt[1] = total;
        memcpy(pkt + 2, s.c_str() + off, len);
        ch->setValue(pkt, len + 2);
        ch->notify();
        if (total > 1) vTaskDelay(pdMS_TO_TICKS(4));  /* pace multi-chunk only */
    }
}

/* Per-command proof.
 *
 * There is no login over Bluetooth -- the password must never cross this
 * link -- and the raw token must not either, because the link is open to
 * anyone in range and a recorded command would otherwise yield a token
 * that works everywhere, for ever.
 *
 * Instead the app proves it holds a token without sending it:
 *     n = the token's nonce half        (16 hex)
 *     k = a counter, strictly increasing per connection
 *     p = HMAC(token, session_nonce || counter)[0..7]   (16 hex)
 *
 * The master rebuilds the token from n -- it can, because the session key
 * is derived from the active password -- and recomputes the proof. The
 * per-connection session nonce stops a proof being replayed on another
 * connection; the counter stops it being replayed on this one.
 */
static bool ble_proof_ok(JsonDocument &req) {
    const char *nh = req["n"] | "";
    const char *ph = req["p"] | "";
    uint32_t ctr   = req["k"] | 0;
    if (strlen(nh) != 16 || strlen(ph) != 16 || ctr == 0) return false;

    uint8_t nonce_t[8], given[8];
    for (int i = 0; i < 8; i++) {
        char b[3] = { nh[i*2], nh[i*2+1], 0 };
        nonce_t[i] = (uint8_t)strtoul(b, NULL, 16);
        char d[3] = { ph[i*2], ph[i*2+1], 0 };
        given[i]   = (uint8_t)strtoul(d, NULL, 16);
    }

    /* Rebuild the token this proof claims to come from. */
    uint8_t key[16], mac[32];
    session_key(key);
    hmac_sha256(key, nonce_t, 8, mac);
    char token[AUTH_TOKEN_LEN];
    for (int i = 0; i < 8; i++) sprintf(token + i*2,      "%02x", nonce_t[i]);
    for (int i = 0; i < 8; i++) sprintf(token + 16 + i*2, "%02x", mac[i]);
    token[32] = 0;

    /* Expected proof over THIS connection's nonce and the counter. An
     * unknown handle is rejected outright: previously the replay-guard
     * loop simply fell through and returned true, skipping the counter
     * check whenever the connection table and handle disagreed. */
    int ci = ble_conn_index(ble_req_handle);
    if (ci < 0) {
        Serial.println("[BLE] request from an untracked connection, rejected");
        return false;
    }
    uint8_t msg[12];
    memcpy(msg, ble_conns[ci].snonce, 8);
    msg[8]=(ctr>>24)&0xFF; msg[9]=(ctr>>16)&0xFF;
    msg[10]=(ctr>>8)&0xFF; msg[11]=ctr&0xFF;
    /* Keyed on the WHOLE token, all 32 characters.
     *
     * This used to go through the 16-byte hmac_sha256, which keyed on
     * token[0..15] only -- and those sixteen characters are exactly the
     * "n" field the client puts in the clear in every request. So the
     * proof was keyed on a value any listener already had: one sniffed
     * command was enough to forge every other. It also meant no client
     * keying on the full token could ever produce a matching proof, which
     * is why every command was rejected.
     *
     * Cross-check vector, so a future change to either side can be caught
     * by hand rather than on a bench:
     *   token   "bfbece9ae12517af0011223344556677"  (ASCII, all 32 chars)
     *   snonce  01 02 03 04 05 06 07 08
     *   counter 1
     *   p       f4b103710e27fad8
     * Keying on the first 16 characters instead gives 538baec92863dcd5,
     * which is what this produced before. */
    uint8_t want[32];
    hmac_sha256_k((const uint8_t *)token, AUTH_TOKEN_LEN - 1,
                  msg, sizeof(msg), want);
    if (!ct_equal(want, given, 8)) return false;

    /* Replay guard for this connection. */
    if (ctr <= ble_conns[ci].last_counter) {
        Serial.printf("[BLE] replayed counter %lu, rejected\n",
                      (unsigned long)ctr);
        return false;
    }
    ble_conns[ci].last_counter = ctr;
    ble_conns[ci].authed = true;
    return true;
}

/* Control commands. Deliberately a small set: switching, listing and
 * state. Firmware upload is not here and will not be -- 1.4 MB over BLE
 * is hours, and the Wi-Fi path already works. */
static void ble_handle_request(const char *json) {
    StaticJsonDocument<384> req;
    DeserializationError perr = deserializeJson(req, json);
    if (perr) {
        Serial.printf("[BLE] JSON parse failed: %s\n", perr.c_str());
        return;
    }
    const char *cmd = req["c"] | "";
    Serial.printf("[BLE] cmd='%s' ctr=%lu\n", cmd,
                  (unsigned long)(req["k"] | 0));

    /* Heap: the "exts" reply now carries presence and last-seen per slot on
     * top of names, versions and available images, and this runs on the BLE
     * task's stack. */
    DynamicJsonDocument res(3072);

    /* There is no login here, by design: the password must never cross
     * Bluetooth. Every command carries a proof of a token obtained over
     * Wi-Fi instead. */
    if (!ble_proof_ok(req)) {
        Serial.println("[BLE] proof rejected");
        res["err"] = "invalid proof";
        String out; serializeJson(res, out);
        ble_notify_chunked(ble_rsp_char, out);
        return;
    }

    if (!strcmp(cmd, "relay")) {
        const char *id = req["id"] | "";
        bool st = req["s"] | false;
        /* "Bluetooth mode controls the whole mesh": an optional peer uid
         * sends the command on over the mesh instead of driving a local
         * relay. Without it the app could only ever reach the one master
         * its radio happened to be talking to. */
        const char *puid = req["uid"] | "";
        bool r;
        if (puid[0]) {
            uint8_t peer_uid[4];
            char self_uid[12];
            snprintf(self_uid, sizeof(self_uid), "%02X%02X%02X%02X",
                     master_uid[0], master_uid[1], master_uid[2], master_uid[3]);
            if (!strcmp(puid, self_uid)) {
                r = ble_set_relay_by_id(id, st);
            } else if (!mesh_active) {
                res["err"] = "not in mesh";
                r = false;
            } else if (!mesh_uid_parse(puid, peer_uid)) {
                res["err"] = "bad uid";
                r = false;
            } else {
                int ch = 1;
                const char *us = strrchr(id, '_');
                if (us && (us[1] == '1' || us[1] == '2')) ch = us[1] - '0';
                r = mesh_relay_set(peer_uid, id, ch, st);
                if (!r && !res.containsKey("err")) res["err"] = "peer not found";
            }
        } else {
            r = ble_set_relay_by_id(id, st);
        }
        Serial.printf("[BLE] relay uid='%s' id='%s' state=%d -> %s\n",
                      puid, id, st ? 1 : 0, r ? "ok" : "REJECTED");
        res["ok"] = r;
    } else if (!strcmp(cmd, "killall")) {
        ble_killall();
        res["ok"] = true;
    } else if (!strcmp(cmd, "state")) {
        String s = build_state_json();
        ble_notify_chunked(ble_rsp_char, s);
        return;
    } else if (!strcmp(cmd, "exts")) {
        /* Same shape as GET /api/extensions so the app has one model
         * regardless of transport. "avail" reflects only what is already
         * in THIS master's library -- an image the app has downloaded but
         * not yet uploaded is invisible here, so the app decides what is
         * available by comparing its own manifest against "fw". */
        JsonArray a = res.createNestedArray("extensions");
        uint32_t now_ms = millis();
        xSemaphoreTake(state_mutex, portMAX_DELAY);
        for (int i = 0; i < MAX_EXTENSIONS; i++) {
            if (extensions[i].state == EXT_EMPTY) continue;
            JsonObject o = a.createNestedObject();
            presence_t pr = ext_presence(&extensions[i], now_ms);
            o["slot"]   = i;
            o["addr"]   = extensions[i].address;
            o["online"] = (pr == PRES_ONLINE);
            o["presence"]  = presence_str(pr);
            o["last_seen"] = seconds_since(extensions[i].last_seen_ms, now_ms);
            o["type"]   = extensions[i].hw_type;
            o["rev"]    = extensions[i].hw_rev;
            o["name"]   = extensions[i].name;
            o["fails"]  = extensions[i].ota_fails;
            o["stuck"]  = (extensions[i].ota_fails >= OTA_MAX_FAILS);
            char vb[16];
            snprintf(vb,sizeof(vb),"%u.%u.%u",extensions[i].fw_ver[0],
                     extensions[i].fw_ver[1],extensions[i].fw_ver[2]);
            o["fw"] = vb;
            char id1[16], id2[16], n1[24], n2[24];
            snprintf(id1,sizeof(id1),"ext%d_1",i);
            snprintf(id2,sizeof(id2),"ext%d_2",i);
            nvs_load_switch_name(id1,n1,sizeof(n1));
            nvs_load_switch_name(id2,n2,sizeof(n2));
            o["sw1"] = n1;
            o["sw2"] = n2;
            fw_entry_t av;
            if (extensions[i].hw_type && extensions[i].hw_type != 0xFF &&
                fw_lookup(extensions[i].hw_type, &av) &&
                fw_ver_newer(av.ver, extensions[i].fw_ver)) {
                char ab[16];
                snprintf(ab,sizeof(ab),"%u.%u.%u",av.ver[0],av.ver[1],av.ver[2]);
                o["avail"] = ab;
            }
        }
        xSemaphoreGive(state_mutex);
    } else if (!strcmp(cmd, "rename_ext")) {
        /* Rename an extension device (the slot), not its switches. */
        int slot = req["slot"] | -1;
        const char *nm = req["name"] | "";
        if (slot < 0 || slot >= MAX_EXTENSIONS || !nm[0]) {
            res["err"] = "bad slot or name";
        } else {
            uint8_t uid[4]; bool okr = false;
            xSemaphoreTake(state_mutex, portMAX_DELAY);
            if (extensions[slot].state != EXT_EMPTY) {
                strncpy(extensions[slot].name, nm, sizeof(extensions[slot].name)-1);
                extensions[slot].name[sizeof(extensions[slot].name)-1] = 0;
                memcpy(uid, extensions[slot].uid, 4);
                okr = true;
            }
            xSemaphoreGive(state_mutex);
            if (okr) { nvs_save(uid, slot, nm); notify_ui(); res["ok"] = true; }
            else       res["err"] = "empty slot";
        }
    } else if (!strcmp(cmd, "rename_sw")) {
        /* Rename one switch, e.g. id "ext0_1" or "master_2". */
        const char *id = req["id"]   | "";
        const char *nm = req["name"] | "";
        if (!id[0] || !nm[0]) { res["err"] = "bad id or name"; }
        else {
            nvs_save_switch_name(id, nm);
            notify_ui();
            res["ok"] = true;
        }
    } else if (!strcmp(cmd, "set_restore")) {
        /* Per-switch restore policy, same shape as rename_sw. Bluetooth is
         * a full control path, so the setting is reachable there too. */
        const char *id = req["id"] | "";
        if (!id[0] || !switch_id_valid(String(id))) { res["err"] = "bad id"; }
        else {
            nvs_save_restore(id, req["restore"] | false);
            notify_ui();
            res["ok"] = true;
        }
    } else if (!strcmp(cmd, "rename_master")) {
        const char *nm = req["name"] | "";
        if (!nm[0]) { res["err"] = "bad name"; }
        else {
            xSemaphoreTake(state_mutex, portMAX_DELAY);
            strncpy(master_name, nm, sizeof(master_name)-1);
            master_name[sizeof(master_name)-1] = 0;
            xSemaphoreGive(state_mutex);
            nvs_save_master_name(nm);
            notify_ui();
            res["ok"] = true;
        }
    } else if (!strcmp(cmd, "reorder")) {
        /* Body is the same comma-separated switch id list the HTTP
         * endpoint takes. */
        const char *ord = req["order"] | "";
        if (!ord[0]) { res["err"] = "empty order"; }
        else {
            xSemaphoreTake(state_mutex, portMAX_DELAY);
            switch_order = String(ord);
            xSemaphoreGive(state_mutex);
            nvs_save_switch_order(switch_order);
            notify_ui();
            Serial.printf("[BLE] switch order updated\n");
            res["ok"] = true;
        }
    } else if (!strcmp(cmd, "fwlist")) {
        /* What is already staged on THIS master. The app compares this
         * against its own cache to decide whether an upload is still
         * needed before it prompts the user to switch to Wi-Fi. */
        res["fs"]     = fs_ready;
        res["master"] = MASTER_FW_VERSION;
        JsonArray a = res.createNestedArray("images");
        if (fs_ready) {
            File f = LittleFS.open(FW_MANIFEST_PATH, "r");
            if (f) {
                StaticJsonDocument<1024> man;
                if (deserializeJson(man, f) == DeserializationError::Ok) {
                    for (JsonObject e : man["images"].as<JsonArray>()) {
                        JsonObject o = a.createNestedObject();
                        o["type"] = e["type"];
                        o["size"] = e["size"];
                        char vb[16];
                        snprintf(vb,sizeof(vb),"%u.%u.%u",
                                 (uint8_t)(e["ver"][0] | 0),
                                 (uint8_t)(e["ver"][1] | 0),
                                 (uint8_t)(e["ver"][2] | 0));
                        o["ver"] = vb;
                    }
                }
                f.close();
            }
        }
    } else if (!strcmp(cmd, "mesh")) {
        res["active"]    = mesh_active;
        res["mesh_name"] = mesh_name;
        res["fw"]        = MASTER_FW_VERSION;
        int online = 0;
        for (int i=0;i<MAX_MESH_MASTERS;i++) if (mesh_peers[i].online) online++;
        res["peer_count"] = online;
    } else {
        Serial.printf("[BLE] unknown command '%s'\n", cmd);
        res["err"] = "unknown command";
    }
    String out; serializeJson(res, out);
    ble_notify_chunked(ble_rsp_char, out);
}

class BleReqCB : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic *ch, NimBLEConnInfo &info) override {
        /* Read NimBLEAttValue directly. Assigning it to an Arduino String
         * loses the buffer and yields length 0, which looked exactly like
         * "the app sent nothing". */
        ble_req_handle = info.getConnHandle();
        for (int i = 0; i < BLE_MAX_CONN; i++)
            if (ble_conns[i].used && ble_conns[i].handle == ble_req_handle)
                ble_conns[i].last_ms = millis();

        NimBLEAttValue av = ch->getValue();
        const uint8_t *v = av.data();
        uint16_t vlen     = av.length();
        Serial.printf("[BLE] write %u bytes:", vlen);
        for (uint16_t i = 0; i < vlen && i < 16; i++)
            Serial.printf(" %02X", v[i]);
        Serial.println();
        if (vlen == 0) return;

        /* Accept both framings. A payload starting with '{' is plain JSON
         * sent in one write -- the common case, and what a client that
         * ignores the chunk header produces. Anything else is treated as
         * [index][total][payload]. Guessing wrong used to fail silently. */
        if (v[0] == '{') {
            uint16_t len = vlen;
            if (len >= BLE_REQ_MAX) { Serial.println("[BLE] request too long"); return; }
            memcpy(ble_req_buf, v, len);
            ble_req_buf[len] = 0;
            ble_req_len = len;
            Serial.printf("[BLE] unframed request: %s\n", ble_req_buf);
            ble_req_ready = true;
            return;
        }

        if (vlen < 2) { Serial.println("[BLE] short frame ignored"); return; }
        uint8_t idx = v[0], total = v[1];
        if (total == 0) { Serial.println("[BLE] bad chunk total"); return; }
        if (idx == 0) ble_req_len = 0;
        uint16_t len = vlen - 2;
        if (ble_req_len + len >= BLE_REQ_MAX) {
            Serial.println("[BLE] request overflow, dropped");
            ble_req_len = 0; return;
        }
        memcpy(ble_req_buf + ble_req_len, v + 2, len);
        ble_req_len += len;
        Serial.printf("[BLE] chunk %u/%u, %u bytes buffered\n",
                      idx + 1, total, ble_req_len);
        if (idx + 1 >= total) {
            ble_req_buf[ble_req_len] = 0;
            Serial.printf("[BLE] request complete: %s\n", ble_req_buf);
            ble_req_ready = true;    /* handled off this task */
        }
    }
};

class BleSrvCB : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer *s, NimBLEConnInfo &info) override {
        uint16_t h = info.getConnHandle();

        /* A connection cannot be refused on credentials -- the link is up
         * before the client has sent anything, and recovery must stay
         * reachable to someone with no credentials at all. What we can do
         * is stop unproven clients occupying more than one slot, so a
         * squatter can never lock the owner out. */
        uint8_t unauth = 0;
        for (int i = 0; i < BLE_MAX_CONN; i++)
            if (ble_conns[i].used && !ble_conns[i].authed) unauth++;
        if (unauth >= BLE_MAX_UNAUTH) {
            Serial.printf("[BLE] refusing handle %u: an unproven client already holds a slot\n", h);
            s->disconnect(h);
            return;
        }

        for (int i = 0; i < BLE_MAX_CONN; i++) {
            if (ble_conns[i].used) continue;
            ble_conns[i].used      = true;
            ble_conns[i].authed    = false;
            ble_conns[i].handle    = h;
            ble_conns[i].opened_ms = millis();
            ble_conns[i].last_ms   = millis();
            ble_conns[i].last_counter = 0;
            ble_fill_nonce(ble_conns[i].snonce);
            /* Publish it. The client reads this characteristic to learn the
             * nonce, and the read is served from the stored value -- the
             * onRead callback refreshes it for the *next* reader, not this
             * one. Filling the slot without also storing the value left the
             * app proving against whatever was there before while
             * ble_proof_ok checked against this connection's nonce, so every
             * command was rejected. ble_new_nonce() sets its characteristic
             * eagerly for exactly this reason; this one didn't. */
            if (ble_snonce_char) ble_snonce_char->setValue(ble_conns[i].snonce, 8);
            ble_conn_count++;
            break;
        }
        ble_connected = (ble_conn_count > 0);
        /* The nonce for this connection was generated as its slot was
         * claimed above; other clients' nonces are untouched. */
        /* A new client never inherits a previous client's recovery result. */
        ble_clear_recovery_result();
        Serial.printf("[BLE] client connected (handle %u), %u open\n",
                      h, ble_conn_count);
        ble_update_adv_data();
        /* Keep advertising while slots remain. Without this one client --
         * hostile or merely forgotten -- hides the master from everyone. */
        if (ble_conn_count < BLE_MAX_CONN) NimBLEDevice::startAdvertising();
        /* Ask for a larger MTU so a state document needs fewer chunks.
         * The phone may refuse; chunking copes either way. */
        s->setDataLen(info.getConnHandle(), 251);
        /* Default intervals are tuned for battery sensors and make every
         * round trip feel sluggish. Ask for 15-30 ms; the phone may refuse
         * or negotiate something else, which is fine. */
        s->updateConnParams(info.getConnHandle(), 12, 24, 0, 400);
    }
    void onDisconnect(NimBLEServer *s, NimBLEConnInfo &info, int reason) override {
        uint16_t h = info.getConnHandle();
        for (int i = 0; i < BLE_MAX_CONN; i++) {
            if (ble_conns[i].used && ble_conns[i].handle == h) {
                ble_conns[i].used = false;
                if (ble_conn_count) ble_conn_count--;
                break;
            }
        }
        ble_connected = (ble_conn_count > 0);
        ble_req_len   = 0;
        /* The delivered password dies with the connection that asked for
         * it; it must not sit readable for the next person in range. */
        ble_clear_recovery_result();
        Serial.printf("[BLE] client disconnected (reason %d), %u open\n",
                      reason, ble_conn_count);
        ble_update_adv_data();
        /* Keep advertising so the phone can hop to whichever master is
         * nearest as the user moves, without any manual step. */
        NimBLEDevice::startAdvertising();
    }
    void onMTUChange(uint16_t mtu, NimBLEConnInfo &info) override {
        Serial.printf("[BLE] MTU now %u\n", mtu);
    }
};

/* A stable identifier for the mesh, derived from mesh_auth_key: fixed for
 * the life of the mesh, identical on every member, and unaffected by the
 * user renaming the mesh or changing its password. Standalone masters
 * report 0000. */
static uint16_t ble_mesh_id(void) {
    if (!mesh_active || !mesh_auth_set) return 0;
    uint8_t mac[32];
    hmac_sha256(mesh_auth_key, (const uint8_t *)"unisync-meshid-v1", 17, mac);
    uint16_t id = ((uint16_t)mac[0] << 8) | mac[1];
    return id ? id : 1;            /* never collide with "standalone" */
}

/* Rebuilt whenever mesh membership or connection state changes, so a
 * scanning app always sees current information. */
static void ble_update_adv_data(void) {
    NimBLEAdvertising *adv = NimBLEDevice::getAdvertising();
    uint16_t mid = ble_mesh_id();
    uint8_t mfg[6];
    mfg[0] = BLE_COMPANY_ID & 0xFF;
    mfg[1] = (BLE_COMPANY_ID >> 8) & 0xFF;
    mfg[2] = BLE_MFG_VER;
    mfg[3] = (mid >> 8) & 0xFF;
    mfg[4] = mid & 0xFF;
    mfg[5] = (mesh_active ? 0x01 : 0)
           | ((root_key_set && fw_key_set) ? 0x02 : 0)
           | (ble_connected ? 0x04 : 0);

    char name[24];
    snprintf(name, sizeof(name), "U%02X%02X%02X%02X",
             master_uid[0], master_uid[1], master_uid[2], master_uid[3]);

    NimBLEAdvertisementData ad;
    ad.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
    ad.setName(name);
    ad.setManufacturerData(std::string((char *)mfg, sizeof(mfg)));
    adv->setAdvertisementData(ad);
}

/* Free slots held by clients that never authenticated, or that
 * authenticated and then went quiet. Runs from task_web. Without this a
 * single squatter can occupy a connection for ever. */
static void ble_reap_connections(void) {
    if (!ble_server) return;
    uint32_t now = millis();
    for (int i = 0; i < BLE_MAX_CONN; i++) {
        if (!ble_conns[i].used) continue;
        /* Authenticated clients are never reaped -- a phone sitting idle
         * on a bedside table is a normal state, not an attack. */
        bool drop = false;
        const char *why = "";
        if (!ble_conns[i].authed &&
            (now - ble_conns[i].opened_ms) > BLE_AUTH_GRACE_MS) {
            drop = true; why = "never authenticated";
        }
        if (drop) {
            Serial.printf("[BLE] dropping handle %u: %s\n",
                          ble_conns[i].handle, why);
            ble_server->disconnect(ble_conns[i].handle);
        }
    }
}

static void ble_recovery_begin(void) {
    char name[24];
    snprintf(name, sizeof(name), "U%02X%02X%02X%02X",
             master_uid[0], master_uid[1], master_uid[2], master_uid[3]);
    NimBLEDevice::init(name);
    NimBLEServer *srv = NimBLEDevice::createServer();
    ble_server = srv;
    srv->setCallbacks(new BleSrvCB());
    NimBLEService *svc = srv->createService(BLE_SVC_UUID);

    ble_chal_char = svc->createCharacteristic(
        BLE_CHAL_UUID, NIMBLE_PROPERTY::READ);
    ble_chal_char->setCallbacks(new BleChalCB());

    NimBLECharacteristic *resp = svc->createCharacteristic(
        BLE_RESP_UUID, NIMBLE_PROPERTY::WRITE);
    resp->setCallbacks(new BleRespCB());

    /* NimBLE adds the notify descriptor itself; no BLE2902 needed. */
    ble_result_char = svc->createCharacteristic(
        BLE_RESULT_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);

    /* Control transport on the same service, so one connection serves both
     * recovery and everyday switching. */
    NimBLECharacteristic *req = svc->createCharacteristic(
        BLE_REQ_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
    req->setCallbacks(new BleReqCB());

    ble_rsp_char = svc->createCharacteristic(
        BLE_RSP_UUID, NIMBLE_PROPERTY::NOTIFY);
    ble_state_char = svc->createCharacteristic(
        BLE_STATE_UUID, NIMBLE_PROPERTY::NOTIFY);

    /* Fresh per connection; the app reads it and binds every proof to it. */
    ble_snonce_char = svc->createCharacteristic(
        BLE_SNONCE_UUID, NIMBLE_PROPERTY::READ);
    /* Each reader gets its OWN connection's nonce, not one shared value. */
    ble_snonce_char->setCallbacks(new BleSNonceCB());
    ble_new_session_nonce();

    ble_new_nonce();
    svc->start();

    /* A legacy advertising packet holds 31 bytes. Flags take 3, the name
     * takes 2+9, and a 128-bit service UUID takes 2+16 -- 32 in total, so
     * putting the UUID in the main packet overflows it and nothing is
     * advertised at all. Keep the name in the advertisement and move the
     * UUID into the scan response, which gets its own 31 bytes. */
    NimBLEAdvertising *adv = NimBLEDevice::getAdvertising();
    ble_update_adv_data();

    NimBLEAdvertisementData scanRsp;
    scanRsp.setCompleteServices(NimBLEUUID(BLE_SVC_UUID));
    adv->setScanResponseData(scanRsp);
    adv->enableScanResponse(true);

    bool started = NimBLEDevice::startAdvertising();
    Serial.printf("[BLE] control + recovery advertising as %s mesh=%04X : %s\n",
                  name, ble_mesh_id(), started ? "OK" : "FAILED");
}

/* Called from task_web: performs the change the BLE callback authorised. */
static void ble_recovery_apply(void) {
    if (!ble_recover_ready) return;
    ble_recover_ready = false;

    if (mesh_active) {
        strncpy(mesh_pass, ble_new_pass, sizeof(mesh_pass)-1);
        mesh_pass[sizeof(mesh_pass)-1] = 0;
        cred_version++;
        prefs.begin("mesh", false);
        prefs.putString("mesh_pass", mesh_pass);
        prefs.putUInt("credver", cred_version);
        prefs.end();
        mesh_broadcast_pass_change();
        Serial.println("[BLE] mesh password recovered and pushed to peers");
    } else {
        strncpy(device_pass, ble_new_pass, sizeof(device_pass)-1);
        device_pass[sizeof(device_pass)-1] = 0;
        prefs.begin("auth", false); prefs.putString("appw", device_pass); prefs.end();
        Serial.println("[BLE] device password set from recovery");
    }
    ap_change_pending = true;
    ap_change_at_ms   = millis() + AP_APPLY_DELAY_MS;
    /* Spent: don't leave the new whole-home password sitting in RAM. */
    memset(ble_new_pass, 0, sizeof(ble_new_pass));
}

/* Read the UID from the factory-burned eFuse MAC. Must run before
 * anything that prints or advertises it -- the card block used to print
 * U00000000 because it ran first. */
static void uid_from_efuse(void) {
    uint8_t base_mac[6];
    esp_read_mac(base_mac, ESP_MAC_WIFI_STA);
    master_uid[0]=base_mac[2]; master_uid[1]=base_mac[3];
    master_uid[2]=base_mac[4]; master_uid[3]=base_mac[5];
}

/* Wipe everything the owner configured and restart.
 *
 * Deliberately NOT cleared: the "factory" namespace, which holds the
 * password and recovery key printed on the card in the box, and the
 * "keys" namespace, which holds the product keys needed to pair
 * extensions. Regenerating either would make the customer's card wrong
 * for the life of the device.
 *
 * Cleared: device password override, mesh membership and keys, switch
 * names and ordering, the extension registry, and saved relay states. */
static void factory_reset(void) {
    Serial.println("\n[RESET] ************************************************");
    Serial.println("[RESET] Factory reset: erasing all configuration");
    Serial.println("[RESET] Card password and recovery key are preserved");
    Serial.println("[RESET] ************************************************\n");

    /* These are the actual namespace names used elsewhere in this file.
     * Getting one wrong fails silently -- Preferences happily clears a
     * namespace that was never used. */
    const char *wipe[] = { "auth", "mesh", "ext_map", "relay_state", "sw_names" };
    for (unsigned i = 0; i < sizeof(wipe)/sizeof(wipe[0]); i++) {
        prefs.begin(wipe[i], false);
        prefs.clear();
        prefs.end();
    }
    delay(300);
    ESP.restart();
}

/* Held for RESET_HOLD_MS while the device is running. No login required:
 * a reset is exactly what someone reaches for when they cannot log in.
 * LED feedback so a long hold reads as progress rather than a dead button. */
static void reset_button_tick(void) {
    static uint32_t held_since = 0;
    static bool     announced  = false;

    if (digitalRead(RESET_BTN_PIN) == LOW) {
        if (!held_since) { held_since = millis(); announced = false; }
        uint32_t held = millis() - held_since;
        if (held > 2000 && !announced) {
            announced = true;
            Serial.printf("[RESET] hold for %lu more seconds to factory reset\n",
                          (RESET_HOLD_MS - held) / 1000);
        }
        /* Blink faster the closer it gets, so the user can see it working. */
        if (held > 2000) {
            uint32_t period = (held > RESET_HOLD_MS - 2000) ? 100 : 400;
            digitalWrite(RELAY1_PIN, ((millis() / period) & 1) ? HIGH : LOW);
        }
        if (held >= RESET_HOLD_MS) factory_reset();
    } else if (held_since) {
        held_since = 0;
        if (announced) Serial.println("[RESET] released, cancelled");
        digitalWrite(RELAY1_PIN, master_relay1 ? LOW : HIGH);
    }
}

void setup() {
    Serial.begin(115200);
    // while (!Serial) delay(10);
    delay(500);
    Serial.println("\n[MASTER] Unisync v" MASTER_FW_VERSION " - booting");

    /* Configure relay pins with pull-down before anything else
     * prevents GPIO float causing relay to fire during boot     */
    gpio_config_t relay_cfg = {};
    relay_cfg.pin_bit_mask = (1ULL<<RELAY1_PIN)|(1ULL<<RELAY2_PIN);
    relay_cfg.mode         = GPIO_MODE_OUTPUT;
    relay_cfg.pull_down_en = GPIO_PULLDOWN_ENABLE;
    relay_cfg.pull_up_en   = GPIO_PULLUP_DISABLE;
    relay_cfg.intr_type    = GPIO_INTR_DISABLE;
    gpio_config(&relay_cfg);
    gpio_set_level((gpio_num_t)RELAY1_PIN, 1); /* HIGH = relay OFF (active LOW) */
    gpio_set_level((gpio_num_t)RELAY2_PIN, 1);

    /* Credentials must be loaded BEFORE any radio starts. The access point
     * takes its password from device_pass, and starting it first brought
     * the AP up with an empty string -- an OPEN network on every boot. */
    uid_from_efuse();

    prefs.begin("mesh", true);
    {
        size_t n = prefs.getBytes("authkey", mesh_auth_key, 16);
        mesh_auth_set = (n == 16);
        cred_version  = prefs.getUInt("credver", 0);
    }
    prefs.end();

    /* The card values are read first: after a factory reset the device
     * password must go back to what the card says, not to something new.
     * Regenerating it would make the printed card wrong for ever. */
    prefs.begin("factory", true);
    String card_pw = prefs.getString("pass", "");
    prefs.end();

    prefs.begin("auth", false);
    {
        String ap = prefs.getString("appw", "");
        if (ap.length() < PASS_MIN_LEN) {
            if (card_pw.length() >= PASS_MIN_LEN) {
                ap = card_pw;                       /* restored after reset */
                Serial.println("[AUTH] password restored to the card value");
            } else {
                char gen[13];
                rand_hex(gen, 12);
                ap = String(gen);                   /* genuinely first boot */
            }
            prefs.putString("appw", ap);
        }
        /* Standalone AP password only. mesh_pass is SHARED across a mesh
         * so a phone roams between masters and so a master-OTA pull can
         * associate with a peer; overwriting it per device would split the
         * mesh. Change the mesh password through /api/mesh/passwd. */
        strncpy(device_pass, ap.c_str(), sizeof(device_pass)-1);
        device_pass[sizeof(device_pass)-1] = 0;
    }
    prefs.end();

    /* Factory namespace: written once, never regenerated, never cleared by
     * a reset. These two values are what the card in the box says, so the
     * card remains accurate for the life of the device. */
    prefs.begin("factory", false);
    {
        String fp = prefs.getString("pass", "");
        size_t  n = prefs.getBytes("rkey", recovery_key, 16);
        if (fp.length() < PASS_MIN_LEN || n != 16) {
            fp = String(device_pass);
            for (int i = 0; i < 16; i += 4) {
                uint32_t r = esp_random();
                recovery_key[i]=r&0xFF; recovery_key[i+1]=(r>>8)&0xFF;
                recovery_key[i+2]=(r>>16)&0xFF; recovery_key[i+3]=(r>>24)&0xFF;
            }
            prefs.putString("pass", fp);
            prefs.putBytes("rkey", recovery_key, 16);
            char rk[33];
            for (int i=0;i<16;i++) sprintf(rk+i*2, "%02x", recovery_key[i]);
            rk[32]=0;
            Serial.printf("\n[CARD] **************************************************\n");
            Serial.printf("[CARD] Model        : U%02X%02X%02X%02X\n",
                          master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
            Serial.printf("[CARD] Password     : %s\n", fp.c_str());
            Serial.printf("[CARD] Recovery key : %s\n", rk);
            Serial.printf("[CARD] Print these on the card. Shown once, never again.\n");
            Serial.printf("[CARD] **************************************************\n\n");
        }
        strncpy(factory_pass, fp.c_str(), sizeof(factory_pass)-1);
        factory_pass[sizeof(factory_pass)-1] = 0;
        factory_set = true;
    }
    prefs.end();
    /* There is never an unclaimed window: the credential is set before the
     * device ever boots for a user, so /api/password always needs auth. */

    prefs.begin("keys", true);
    {
        size_t n1 = prefs.getBytes("root", root_key, sizeof(root_key));
        size_t n2 = prefs.getBytes("fw",   fw_key,   sizeof(fw_key));
        root_key_set = (n1 == sizeof(root_key));
        fw_key_set   = (n2 == sizeof(fw_key));
    }
    prefs.end();
    if (mesh_active && !mesh_auth_set) {
        Serial.println("[MESH] ****************************************************");
        Serial.println("[MESH] This mesh was formed before packet authentication");
        Serial.println("[MESH] existed, so it has no auth key. Mesh packets are");
        Serial.println("[MESH] NOT authenticated and the app cannot identify this");
        Serial.println("[MESH] mesh (it advertises 0000).");
        Serial.println("[MESH] Fix: leave the mesh on every master, then create");
        Serial.println("[MESH] and re-join it. The key cannot be derived locally");
        Serial.println("[MESH] because every master must hold the same one.");
        Serial.println("[MESH] ****************************************************");
    }
    if (!root_key_set)
        Serial.println("[SEC] no root key -- extensions cannot pair until provisioned");
    if (!fw_key_set)
        Serial.println("[SEC] no firmware key -- images cannot be verified");


    pinMode(RELAY1_PIN,   OUTPUT); digitalWrite(RELAY1_PIN,   HIGH); /* active LOW */
    pinMode(RELAY2_PIN,   OUTPUT); digitalWrite(RELAY2_PIN,   HIGH); /* active LOW */
    pinMode(RS485_DE_PIN, OUTPUT); digitalWrite(RS485_DE_PIN, LOW);
    pinMode(TOUCH1_PIN,   INPUT);
    pinMode(TOUCH2_PIN,   INPUT);

    BusSerial.begin(UART_BAUD, SERIAL_8N1, BUS_RX_PIN, BUS_TX_PIN);

    /* Load master relay state (extension states loaded after nvs_restore_all) */
    prefs.begin("relay_state",true);
    master_relay1=prefs.getBool("m_r1",false);
    master_relay2=prefs.getBool("m_r2",false);
    prefs.end();
    /* Nothing energizes unless the owner opted that channel into restore. */
    apply_restore_policy(-1, &master_relay1, &master_relay2);
    /* Both pins are already HIGH (off) from the pinMode block above, so these
     * writes can only close a relay, never open one. Staggered so a whole
     * house coming back doesn't switch everything in the same millisecond. */
    if (master_relay1) { restore_stagger(); digitalWrite(RELAY1_PIN, LOW); }
    if (master_relay2) { restore_stagger(); digitalWrite(RELAY2_PIN, LOW); }
    Serial.printf("[RELAY] Restored: CH1=%s CH2=%s\n",
                  master_relay1?"ON":"OFF", master_relay2?"ON":"OFF");

    for (int i=0;i<MAX_EXTENSIONS;i++) {
        extensions[i].state=EXT_EMPTY;
        extensions[i].address=ADDR_UNASSIGNED;
        extensions[i].missed=0; extensions[i].relay1=false;
        extensions[i].relay2=false; extensions[i].last_seen_ms=0;
        extensions[i].polled_once=false;
        extensions[i].last_relay1_cmd_ms=0;
        extensions[i].last_relay2_cmd_ms=0;
        memset(extensions[i].uid,0,4);
        ext_reset_identity(&extensions[i]);
        snprintf(extensions[i].name,sizeof(extensions[i].name),"Slot-%d",i+1);
    }
    for (int i=0;i<MAX_PENDING;i++)    pending_queue[i].active=false;
    for (int i=0;i<MAX_CHALLENGES;i++) challenges[i].active=false;

    prefs.begin("ext_map",false); prefs.end();
    nvs_restore_all();
    /* Load extension relay states AFTER extensions are initialized */
    { prefs.begin("relay_state",true);
      for (int i=0;i<MAX_EXTENSIONS;i++) {
          char k1[8],k2[8];
          snprintf(k1,sizeof(k1),"e%d_r1",i);
          snprintf(k2,sizeof(k2),"e%d_r2",i);
          extensions[i].relay1=prefs.getBool(k1,false);
          extensions[i].relay2=prefs.getBool(k2,false);
      }
      prefs.end();
      /* Registered extensions boot with their relays off and are pushed
       * state on their first poll. Zeroing "start off" channels here means
       * those channels are never pushed at all. */
      for (int i=0;i<MAX_EXTENSIONS;i++)
          apply_restore_policy(i, &extensions[i].relay1, &extensions[i].relay2);
    }

    /* Load master name and switch order */
    nvs_load_master_name(master_name, sizeof(master_name));
    switch_order = nvs_load_switch_order();
    Serial.printf("[MASTER] Name: %s\n", master_name);

    boot_start_ms = millis();

    /* If no extensions in NVS, boot is immediately complete */
    bool has_extensions=false;
    for (int i=0;i<MAX_EXTENSIONS;i++)
        if (extensions[i].state!=EXT_EMPTY) { has_extensions=true; break; }
    if (!has_extensions) boot_complete=true;

    state_mutex=xSemaphoreCreateMutex();
    master_relay_queue=xQueueCreate(16,sizeof(relay_cmd_t));
    ext_relay_queue=xQueueCreate(16,sizeof(relay_cmd_t));
    ws_notify_queue=xQueueCreate(8,sizeof(uint8_t));
    welcome_queue=xQueueCreate(8,sizeof(welcome_cmd_t));

    /* WIFI_AP_STA required for ESP-NOW to work alongside AP mode.
     * Pure WIFI_AP mode breaks ESP-NOW receive on ESP32-C6. */
    /* Load mesh credentials BEFORE WiFi init so mesh_active is
     * correct when choosing SSID (shared vs unique) */
    mesh_nvs_load();

    /* Explicitly tear down any previous WiFi state from before RST.
     * Without this, the old AP SSID keeps broadcasting during boot. */
    WiFi.disconnect(true);
    WiFi.softAPdisconnect(true);
    WiFi.mode(WIFI_OFF);
    delay(100);

    WiFi.mode(WIFI_AP_STA);
    WiFi.softAPConfig(AP_IP,AP_GW,AP_SUBNET);
    WiFi.setAutoReconnect(false);
    /* When not in mesh: broadcast unique SSID so user can identify this master.
     * Once in mesh: only broadcast "Unisync" (shared SSID for auto-connect). */
    if (!mesh_active) {
        /* Use efuse base MAC for unique SSID -- available before WiFi init */
            uint8_t tmac[6];
        esp_read_mac(tmac, ESP_MAC_WIFI_STA);
        snprintf(unique_ssid, sizeof(unique_ssid), "Unisync-%02X%02X",
                 tmac[4], tmac[5]);
        /* Never start an open access point. If the credential is somehow
     * missing, fall back to the factory value rather than broadcasting
     * an unprotected network. */
    if (strlen(device_pass) < PASS_MIN_LEN) {
        Serial.println("[AUTH] device password missing at AP start -- using factory value");
        strncpy(device_pass, factory_pass, sizeof(device_pass)-1);
        device_pass[sizeof(device_pass)-1] = 0;
    }
    WiFi.softAP(unique_ssid, device_pass, AP_CHANNEL);
        Serial.printf("[WIFI] AP (unique): %s\n", unique_ssid);
    } else {
        /* Use mesh name as SSID -- all masters in same mesh share this SSID */
        WiFi.softAP(mesh_name, mesh_pass, AP_CHANNEL);
        Serial.printf("[WIFI] AP (mesh): %s\n", mesh_name);
    }
    Serial.printf("[WIFI] IP: %s\n", AP_IP.toString().c_str());

    /* (UID already read at the top of setup -- see uid_from_efuse.) */
    /* Get master UID from factory-burned efuse MAC.
     * esp_read_mac() reads the base MAC from efuse   guaranteed unique
     * per chip from factory, does not depend on WiFi init order.
     * Use bytes 2-5 (skip OUI bytes 0-1 which are Espressif OUI = same on all) */
    uid_from_efuse();
    Serial.printf("[MASTER] UID=%02X%02X%02X%02X\n",
                  master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
    {
        uint8_t ap_mac[6]; esp_read_mac(ap_mac, ESP_MAC_WIFI_SOFTAP);
        Serial.printf("[MASTER] STA MAC: %02X:%02X:%02X:%02X:%02X:%02X\n",
            master_uid[0],master_uid[1],master_uid[2],master_uid[3],
            ap_mac[4]-1,ap_mac[5]-1);
        Serial.printf("[MASTER] AP  MAC: %02X:%02X:%02X:%02X:%02X:%02X\n",
            ap_mac[0],ap_mac[1],ap_mac[2],ap_mac[3],ap_mac[4],ap_mac[5]);
        Serial.println("[MASTER] Use AP MAC for mesh peer registration");
    }

    setup_web();

    /* Init mesh ESP-NOW - must be after WiFi */
    mesh_init();

    xTaskCreate(task_fwsync,"fwsync",8192,NULL,1,NULL);
    xTaskCreate(task_touch,"touch",2048,NULL,3,NULL);
    xTaskCreate(task_bus,  "bus",  4096,NULL,2,NULL);
    xTaskCreate(task_web,  "web",  8192,NULL,1,NULL);

    /* Mount without formatting first, so a first boot and a genuinely
     * broken partition produce different messages. The esp_littlefs
     * component logs its own errors on a failed mount; those are
     * expected once, on a partition that has never been formatted. */
    /* A shipped default of "12345678" made every other control useless.
     * Generate a unique one on first boot and print it once for the
     * installer; it is stored and reused from then on. */
    master_ver_parse(MASTER_FW_VERSION, master_fw);
    Serial.printf("[MFW] running image v%u.%u.%u, %u bytes\n",
                  master_fw[0], master_fw[1], master_fw[2], master_image_size());

    if (LittleFS.begin(false)) {
        fs_ready = true;
    } else {
        Serial.println("[FW] no filesystem yet, formatting (normal on first boot)");
        if (LittleFS.begin(true)) fs_ready = true;
    }
    if (fs_ready) {
        if (!LittleFS.exists("/fw")) LittleFS.mkdir("/fw");
        Serial.printf("[FW] filesystem ready (%u KB free)\n",
                      (LittleFS.totalBytes() - LittleFS.usedBytes()) / 1024);
    } else {
        Serial.println("[FW] filesystem UNUSABLE -- firmware library disabled");
    }
    pinMode(RESET_BTN_PIN, INPUT_PULLUP);
    ble_recovery_begin();
    Serial.println("[MASTER] Ready - connect to Unisync -> 192.168.4.1");
}

void loop() {
    vTaskDelay(pdMS_TO_TICKS(1000));
}
