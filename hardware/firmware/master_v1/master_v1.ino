/*
 * Unisync - Master Firmware v5.0
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
#define WEBSOCKETS_MAX_DATA_SIZE 4096
#include <WebSocketsServer.h>
#include <ArduinoJson.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "freertos/queue.h"

/* ================================================================
 * PINS
 * ================================================================ */
#define TOUCH1_PIN    19
#define TOUCH2_PIN    20
#define RELAY1_PIN    17
#define RELAY2_PIN    21
#define RS485_DE_PIN  23
#define BUS_RX_PIN    4
#define BUS_TX_PIN    5

/* ================================================================
 * WIFI AP
 * ================================================================ */
#define AP_SSID   "Unisync"
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
#define MISSED_MAX        5
#define BUS_RESP_MS       20
#define LISTEN_WINDOW_MS  50
#define LISTEN_INTERVAL_MS 1000
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
#define CMD_IDENTIFY      0x30
#define CMD_OTA_BEGIN     0x40
#define CMD_OTA_CHUNK     0x41
#define CMD_OTA_END       0x42
#define CMD_OTA_ACK       0x43
#define CMD_BUS_QUIET     0x44
#define CMD_ANNOUNCE      0x50
#define CMD_WELCOME       0x51
#define CMD_REJECT        0x52
#define CMD_CHALLENGE     0x54  /* M->E: uid[4] + challenge[4] */
#define CMD_RESPONSE      0x55  /* E->M: uid[4] + crc32[4] */
#define CMD_FACTORY_RESET 0x60
#define CMD_ERROR         0xF0

/* Secret key - must match extension firmware exactly */
static const uint8_t SECRET_KEY[16] = {0x55, 0x6E, 0x69, 0x73, 0x79, 0x6E, 0x63, 0x53, 0x77, 0x69, 0x74, 0x63, 0x68, 0x4B, 0x65, 0x79};

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
typedef enum { EXT_EMPTY=0, EXT_ONLINE, EXT_OFFLINE } ext_state_t;

typedef struct {
    uint8_t     address;
    uint8_t     uid[4];
    char        name[24];
    ext_state_t state;
    bool        relay1;
    bool        relay2;
    uint8_t     missed;
    uint32_t    last_seen_ms;
    uint32_t    last_relay1_cmd_ms;  /* rate limiting */
    uint32_t    last_relay2_cmd_ms;
    bool        polled_once;         /* for boot overlay */
} extension_t;

/* Pending challenge tracking */
#define MAX_CHALLENGES 5
typedef struct {
    uint8_t  uid[4];
    uint8_t  challenge[4];
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
static int          ota_progress    = 0;   /* 0-100 percent */
static String       ota_status      = "";

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

static uint32_t compute_expected_response(const uint8_t *challenge,
                                          const uint8_t *uid) {
    uint8_t buf[24];
    for (int i=0; i<16; i++) buf[i]    = SECRET_KEY[i];
    for (int i=0; i<4;  i++) buf[16+i] = challenge[i];
    for (int i=0; i<4;  i++) buf[20+i] = uid[i];
    return crc32_compute(buf, 24);
}

/* ================================================================
 * RS-485
 * ================================================================ */
static void bus_send(uint8_t dst, uint8_t cmd,
                     const uint8_t *payload, uint8_t len) {
    uint8_t frame[40];
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
    if (s.length() > 0) { strncpy(name, s.c_str(), nlen-1); name[nlen-1]=' '; }
    else snprintf(name, nlen, "Switch");
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
    strncpy(name, s.c_str(), nlen-1); name[nlen-1]=' ';
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

/* ================================================================
 * RELAY STATE NVS
 * ================================================================ */
static void relay_state_save(void) {
    prefs.begin("relay_state",false);
    prefs.putBool("m_r1",master_relay1);
    prefs.putBool("m_r2",master_relay2);
    prefs.end();
}

static void relay_state_load(void) {
    prefs.begin("relay_state",true);
    master_relay1=prefs.getBool("m_r1",false);
    master_relay2=prefs.getBool("m_r2",false);
    prefs.end();
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
    /* Generate pseudo-random challenge using uid + millis */
    uint32_t now = millis();
    uint8_t  challenge[4];
    challenge[0] = (now >> 24) ^ uid[0] ^ uid[3];
    challenge[1] = (now >> 16) ^ uid[1] ^ uid[2];
    challenge[2] = (now >>  8) ^ uid[2] ^ uid[1];
    challenge[3] = (now)       ^ uid[3] ^ uid[0];

    /* Store challenge for verification */
    for (int i=0; i<MAX_CHALLENGES; i++) {
        if (!challenges[i].active) {
            memcpy(challenges[i].uid,       uid,       4);
            memcpy(challenges[i].challenge, challenge, 4);
            challenges[i].sent_ms = millis();
            challenges[i].active  = true;
            break;
        }
    }

    uint8_t frame[40];
    frame[0]=SOF; frame[1]=ADDR_UNASSIGNED; frame[2]=ADDR_MASTER;
    frame[3]=CMD_CHALLENGE; frame[4]=8;
    frame[5]=uid[0]; frame[6]=uid[1]; frame[7]=uid[2]; frame[8]=uid[3];
    frame[9]=challenge[0]; frame[10]=challenge[1];
    frame[11]=challenge[2]; frame[12]=challenge[3];
    frame[13]=crc8(&frame[1], 12);
    digitalWrite(RS485_DE_PIN, HIGH);
    BusSerial.write(frame, 14);
    BusSerial.flush();
    digitalWrite(RS485_DE_PIN, LOW);
    Serial.printf("[SEC] Challenge sent to %02X%02X%02X%02X\n",
                  uid[0],uid[1],uid[2],uid[3]);
}

/* Verify challenge response and return true if valid */
static bool verify_response(const uint8_t *uid, const uint8_t *resp_crc32) {
    uint32_t received = ((uint32_t)resp_crc32[0]<<24)|
                        ((uint32_t)resp_crc32[1]<<16)|
                        ((uint32_t)resp_crc32[2]<<8) |
                        ((uint32_t)resp_crc32[3]);
    for (int i=0; i<MAX_CHALLENGES; i++) {
        if (!challenges[i].active) continue;
        if (memcmp(challenges[i].uid, uid, 4) != 0) continue;
        /* Challenge expires after 5 seconds */
        if ((millis()-challenges[i].sent_ms) > 5000) {
            challenges[i].active = false; continue;
        }
        uint32_t expected = compute_expected_response(challenges[i].challenge, uid);
        challenges[i].active = false; /* consume challenge */
        if (received == expected) {
            Serial.printf("[SEC] Auth OK %02X%02X%02X%02X\n",
                          uid[0],uid[1],uid[2],uid[3]);
            return true;
        } else {
            Serial.printf("[SEC] Auth FAIL %02X%02X%02X%02X\n",
                          uid[0],uid[1],uid[2],uid[3]);
            return false;
        }
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
    if (plen<8) return;
    if (frame[5+plen]!=crc8(&frame[1],4+plen)) return;

    const uint8_t *uid      = &frame[5];
    const uint8_t *resp_crc = &frame[9];

    if (!verify_response(uid, resp_crc)) {
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
                        pos=0; elen=0; break;
                    }
                }
            }
        } else { vTaskDelay(pdMS_TO_TICKS(1)); }
    }
}

/* ================================================================
 * POLL ONE EXTENSION
 * ================================================================ */
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

    extensions[i].missed=0;
    extensions[i].last_seen_ms=millis();
    extensions[i].polled_once=true;
    bool was_offline=(extensions[i].state==EXT_OFFLINE);
    if (was_offline) extensions[i].state=EXT_ONLINE;

    bool changed=was_offline;
    if (resp[3]==CMD_STATE_RESP&&resp[4]>=3) {
        uint8_t flags=resp[5],evts=resp[7];
        bool r1=(flags>>0)&0x01, r2=(flags>>1)&0x01;
        if (r1!=extensions[i].relay1||r2!=extensions[i].relay2) {
            extensions[i].relay1=r1; extensions[i].relay2=r2; changed=true;
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
            digitalWrite(RELAY1_PIN,s?HIGH:LOW);
            relay_state_save();
            Serial.printf("[TOUCH] CH1 -> %s\n",s?"ON":"OFF");
            notify_ui();
        }
        if (t2&&!last_t2) {
            xSemaphoreTake(state_mutex,portMAX_DELAY);
            master_relay2=!master_relay2; bool s=master_relay2;
            xSemaphoreGive(state_mutex);
            digitalWrite(RELAY2_PIN,s?HIGH:LOW);
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
            digitalWrite(cmd.channel==1?RELAY1_PIN:RELAY2_PIN,cmd.state?HIGH:LOW);
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

        /* Immediate extension relay commands */
        relay_cmd_t cmd;
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

        /* Poll registered extensions */
        if ((now-last_poll)>=POLL_MS) {
            last_poll=now;
            for (int i=0;i<MAX_EXTENSIONS;i++) poll_extension(i);
            check_boot_complete();
        }

        /* Listen window for ANNOUNCE frames */
        if ((now-last_listen)>=LISTEN_INTERVAL_MS) {
            last_listen=now;
            run_listen_window();

            /* Also run during active scan */
            if (scan_active&&millis()<scan_end_ms) {
                run_listen_window();
            } else if (scan_active&&millis()>=scan_end_ms) {
                scan_active=false;
                if (pending_count()>0) notify_ui();
            }
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
    char       snap_mname[24]; strncpy(snap_mname, master_name, sizeof(snap_mname));
    String     snap_order    = switch_order;
    extension_t snap_ext[MAX_EXTENSIONS];
    memcpy(snap_ext, extensions, sizeof(extensions));
    pending_ext_t snap_pend[MAX_PENDING];
    memcpy(snap_pend, pending_queue, sizeof(pending_queue));
    xSemaphoreGive(state_mutex);

    /* Now build JSON without holding mutex */
    StaticJsonDocument<6144> doc;
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
            sw["online"]=(snap_ext[slot].state==EXT_ONLINE);
        }
    }

    /* Add any switches not yet in order (new extensions) */
    for(int i=0;i<MAX_EXTENSIONS;i++) {
        if(extensions[i].state==EXT_EMPTY) continue;
        for(int ch=1;ch<=2;ch++) {
            snprintf(sw_id,sizeof(sw_id),"ext%d_%d",i,ch);
            if(effective_order.indexOf(sw_id)<0) {
                JsonObject sw=switches.createNestedObject();
                sw["id"]=sw_id;
                xSemaphoreGive(state_mutex);
                nvs_load_switch_name(sw_id,sw_name,sizeof(sw_name));
                xSemaphoreTake(state_mutex,portMAX_DELAY);
                if(String(sw_name)=="Switch") {
                    snprintf(sw_name,sizeof(sw_name),"Switch %d",ch+(i*2)+2);
                }
                sw["name"]=sw_name;
                sw["device_name"]=master_name;
                sw["color"]=SLOT_COLORS[i+1<6?i+1:5];
                sw["channel"]=ch;
                sw["state"]=(ch==1)?extensions[i].relay1:extensions[i].relay2;
                sw["online"]=(extensions[i].state==EXT_ONLINE);
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

    /* Offline slots for replace option */
    JsonArray offline_slots=doc.createNestedArray("offline_slots");
    for(int i=0;i<MAX_EXTENSIONS;i++) {
        if(snap_ext[i].state!=EXT_OFFLINE) continue;
        JsonObject os=offline_slots.createNestedObject();
        os["slot"]=i;
        os["name"]=("Slot "+String(i+1));
    }

    String out; serializeJson(doc,out); return out;
}

/* ================================================================
 * TASK: WEB (priority 1)
 * ================================================================ */
static void task_web(void *arg) {
    for (;;) {
        server.handleClient();
        wss.loop();
        uint8_t sig;
        if (xQueueReceive(ws_notify_queue,&sig,0)==pdTRUE) {
            while (xQueueReceive(ws_notify_queue,&sig,0)==pdTRUE);
            String json=build_state_json();
            wss.broadcastTXT(json);
        }
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

/* ================================================================
 * HTML UI
 * ================================================================ */
static const char SETTINGS_HTML[] PROGMEM = R"SHTML(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Unisync Settings</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
     background:#0f0f1a;color:#eee;min-height:100vh;padding:16px}
.back{color:#00d4ff;font-size:13px;text-decoration:none;display:inline-block;margin-bottom:20px}
h1{color:#eee;font-size:20px;margin-bottom:4px}
.sub{color:#555;font-size:12px;margin-bottom:24px}
.card{background:#1a1a2e;border-radius:14px;padding:20px;
      margin-bottom:16px;border:1px solid #2a2a4a}
.card h2{font-size:14px;color:#00d4ff;margin-bottom:4px}
.card p{font-size:12px;color:#666;margin-bottom:16px;line-height:1.5}
.file-zone{border:2px dashed #2a2a4a;border-radius:10px;padding:20px;
           text-align:center;cursor:pointer;margin-bottom:12px}
.file-zone.has-file{border-color:#4eff4e}
.file-name{font-size:12px;color:#888;margin-top:6px}
.btn{width:100%;padding:12px;border:none;border-radius:10px;
     font-size:14px;font-weight:700;cursor:pointer;background:#00d4ff;color:#000}
.btn:disabled{background:#2a2a4a;color:#555;cursor:not-allowed}
.progress-wrap{display:none;margin-top:12px}
.progress-bar{height:6px;background:#2a2a4a;border-radius:3px;overflow:hidden}
.progress-fill{height:100%;background:#00d4ff;width:0%;
               transition:width 0.3s;border-radius:3px}
.status{font-size:12px;color:#888;margin-top:8px;text-align:center}
.ok{color:#4eff4e}
.err{color:#ff4e4e}
.info-row{display:flex;justify-content:space-between;
          padding:8px 0;border-bottom:1px solid #2a2a4a;font-size:13px}
.info-row:last-child{border:none}
.info-lbl{color:#666}
.info-val{color:#eee;font-family:monospace;font-size:12px}
</style>
</head>
<body>
<a class="back" href="/">&#8592; Back</a>
<h1>Settings</h1>
<div class="sub" id="sub">Loading...</div>

<div class="card">
  <h2>Device Info</h2>
  <div id="info">Loading...</div>
</div>

<div class="card">
  <h2>Master Firmware Update</h2>
  <p>Upload a compiled .bin firmware file to update over the air.
     Device restarts automatically after a successful update.</p>
  <div class="file-zone" id="drop-zone"
       onclick="document.getElementById('fw').click()">
    Tap to select firmware .bin
    <div class="file-name" id="fname">No file selected</div>
  </div>
  <input type="file" id="fw" accept=".bin" style="display:none"
         onchange="fileSelected(this)"/>
  <button class="btn" id="ubtn" disabled onclick="startOTA()">
    Upload Firmware
  </button>
  <div class="progress-wrap" id="pwrap">
    <div class="progress-bar">
      <div class="progress-fill" id="pfill"></div>
    </div>
    <div class="status" id="ostatus">Preparing...</div>
  </div>
</div>

<script>
var selFile=null;

function uptime(s){
  if(s<60)return s+'s';
  if(s<3600)return Math.floor(s/60)+'m '+s%60+'s';
  return Math.floor(s/3600)+'h '+Math.floor((s%3600)/60)+'m';
}

function row(lbl,val){
  return '<div class="info-row"><span class="info-lbl">'+lbl+
         '</span><span class="info-val">'+val+'</span></div>';
}

function loadInfo(){
  var xhr=new XMLHttpRequest();
  xhr.open('GET','/api/info',true);
  xhr.onload=function(){
    var d=JSON.parse(xhr.responseText);
    document.getElementById('sub').textContent=
      '192.168.4.1 | Uptime: '+uptime(d.uptime);
    document.getElementById('info').innerHTML=
      row('Firmware','v5.0')+
      row('Free Heap',d.free_heap+' bytes')+
      row('Master UID',d.uid)+
      row('IP Address','192.168.4.1');
  };
  xhr.send();
}

function fileSelected(input){
  if(!input.files.length) return;
  selFile=input.files[0];
  document.getElementById('fname').textContent=
    selFile.name+' ('+Math.round(selFile.size/1024)+' KB)';
  document.getElementById('drop-zone').classList.add('has-file');
  document.getElementById('ubtn').disabled=false;
}

function startOTA(){
  if(!selFile) return;
  var btn=document.getElementById('ubtn');
  btn.disabled=true;
  btn.textContent='Uploading...';
  document.getElementById('pwrap').style.display='block';

  var xhr=new XMLHttpRequest();
  xhr.open('POST','/api/ota/master',true);

  xhr.upload.onprogress=function(e){
    if(e.lengthComputable){
      var pct=Math.round(e.loaded/e.total*100);
      document.getElementById('pfill').style.width=pct+'%';
      document.getElementById('ostatus').textContent='Uploading: '+pct+'%';
    }
  };

  xhr.onload=function(){
    if(xhr.status===200){
      document.getElementById('pfill').style.width='100%';
      document.getElementById('ostatus').innerHTML=
        '<span class="ok">Done! Restarting...</span>';
      setTimeout(function(){
        document.getElementById('ostatus').innerHTML=
          '<span class="ok">Restarted. <a href="/" style="color:#00d4ff">Go back</a></span>';
      },8000);
    } else {
      document.getElementById('ostatus').innerHTML=
        '<span class="err">Failed: '+xhr.responseText+'</span>';
      btn.disabled=false; btn.textContent='Upload Firmware';
    }
  };

  xhr.onerror=function(){
    document.getElementById('ostatus').innerHTML=
      '<span class="ok">Restarting... <a href="/" style="color:#00d4ff">Go back in 10s</a></span>';
  };

  var fd=new FormData();
  fd.append('firmware',selFile);
  xhr.send(fd);
}

loadInfo();
</script>
</body>
</html>
)SHTML";

static const char HTML[] PROGMEM = R"rawhtml(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Unisync</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
     background:#0f0f1a;color:#eee;min-height:100vh;padding:16px}
.topbar{display:flex;align-items:center;justify-content:space-between;margin-bottom:20px}
.title-row{display:flex;align-items:center;gap:10px}
h1{color:#eee;font-size:20px;font-weight:600;cursor:pointer}
h1:hover{color:#00d4ff}
.sub{color:#555;font-size:11px;display:flex;align-items:center;gap:6px;margin-top:2px}
.dot{width:7px;height:7px;border-radius:50%;background:#333;transition:background 0.3s}
.dot.on{background:#4eff4e}
.topbar-btns{display:flex;gap:8px}
.top-btn{background:#1a1a2e;border:1px solid #2a2a4a;color:#aaa;
         padding:7px 12px;border-radius:8px;font-size:12px;cursor:pointer}
.top-btn.active{border-color:#00d4ff;color:#00d4ff}
.top-btn.scan.scanning{border-color:#ffd700;color:#ffd700;animation:pulse 1s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:0.5}}
/* Switch grid */
.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.sw-card{background:#1a1a2e;border-radius:14px;padding:16px;
         border:1px solid #2a2a4a;border-left:4px solid #444;
         transition:opacity 0.3s;position:relative}
.sw-card.offline{opacity:0.4}
.sw-card.reorder-mode{border-style:dashed}
.sw-top{display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:12px}
.sw-names{flex:1}
.sw-name{font-size:14px;font-weight:600;line-height:1.2}
.sw-device{font-size:10px;color:#555;margin-top:2px}
.sw-menu-btn{background:none;border:none;color:#555;font-size:16px;
             cursor:pointer;padding:2px 6px;border-radius:4px;line-height:1}
.sw-menu-btn:hover{background:#2a2a4a;color:#eee}
.sw-dropdown{position:absolute;right:12px;top:36px;background:#1e1e38;
             border:1px solid #2a2a4a;border-radius:10px;min-width:140px;
             z-index:10;overflow:hidden;display:none}
.sw-dropdown.show{display:block}
.sw-dropdown-item{padding:9px 14px;font-size:12px;cursor:pointer;color:#eee}
.sw-dropdown-item:hover{background:#2a2a4a}
.toggle{width:100%;padding:11px;border:none;border-radius:8px;
        font-size:14px;font-weight:700;cursor:pointer;transition:all 0.15s;
        position:relative}
.toggle.on{background:#00d4ff;color:#000;box-shadow:0 0 10px rgba(0,212,255,0.25)}
.toggle.off{background:#111128;color:#555;border:1px solid #2a2a4a}
.toggle:active{transform:scale(0.96)}
.toggle:disabled{cursor:not-allowed}
.toggle .spinner{display:none;width:14px;height:14px;border:2px solid rgba(0,0,0,0.3);
                 border-top-color:#000;border-radius:50%;
                 animation:spin 0.6s linear infinite;margin:0 auto}
.toggle.loading .spinner{display:block}
.toggle.loading .lbl{display:none}
@keyframes spin{to{transform:rotate(360deg)}}
/* Move buttons */
.move-btns{display:grid;grid-template-columns:1fr 1fr 1fr;
           grid-template-rows:1fr 1fr 1fr;gap:4px;margin-top:10px}
.move-btn{background:#1e1e38;border:1px solid #2a2a4a;color:#888;
          padding:6px;border-radius:6px;font-size:12px;cursor:pointer;
          text-align:center}
.move-btn:hover{background:#2a2a4a;color:#eee}
.move-btn.blank{background:none;border:none;pointer-events:none}
/* Empty state */
.empty{color:#444;font-size:13px;text-align:center;padding:30px;
       border:1px dashed #2a2a4a;border-radius:14px;grid-column:1/-1}
/* Boot overlay */
.boot-overlay{display:none;position:fixed;inset:0;
              background:rgba(10,10,26,0.85);backdrop-filter:blur(8px);
              z-index:200;align-items:center;justify-content:center;flex-direction:column;gap:16px}
.boot-overlay.show{display:flex}
.boot-spinner{width:40px;height:40px;border:3px solid #2a2a4a;
              border-top-color:#00d4ff;border-radius:50%;animation:spin 0.8s linear infinite}
.boot-text{color:#888;font-size:14px;text-align:center}
/* Modals */
.overlay{display:none;position:fixed;inset:0;background:rgba(0,0,0,0.8);
         z-index:100;align-items:center;justify-content:center;padding:16px}
.overlay.show{display:flex}
.modal{background:#1a1a2e;border-radius:18px;padding:24px;width:100%;
       max-width:420px;border:1px solid #2a2a4a;max-height:80vh;overflow-y:auto}
.modal h2{color:#00d4ff;font-size:17px;margin-bottom:6px}
.modal .subtitle{color:#666;font-size:12px;margin-bottom:18px}
.ext-item{background:#111128;border-radius:12px;padding:14px;margin-bottom:10px;border:1px solid #2a2a4a}
.ext-uid{font-family:monospace;font-size:10px;color:#444;margin-bottom:10px}
.sw-inputs{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:10px}
.sw-inputs label{font-size:11px;color:#666;margin-bottom:4px;display:block}
.ext-item input,.ext-item select{width:100%;padding:9px;background:#1a1a2e;
  border:1px solid #2a2a4a;border-radius:8px;color:#eee;font-size:13px;outline:none}
.ext-item input:focus,.ext-item select:focus{border-color:#00d4ff}
.ext-actions{display:flex;gap:8px;margin-top:10px}
.btn{padding:9px 14px;border:none;border-radius:8px;font-size:13px;font-weight:700;cursor:pointer}
.btn.primary{background:#00d4ff;color:#000}
.btn.ghost{background:#2a2a4a;color:#aaa}
.btn.danger{background:#2a0a0a;color:#ff4e4e;border:1px solid #ff4e4e}
.modal-close{display:flex;justify-content:flex-end;margin-top:14px}
.input-modal{background:#1a1a2e;border-radius:18px;padding:24px;
             width:100%;max-width:340px;border:1px solid #2a2a4a}
.input-modal h2{color:#00d4ff;font-size:16px;margin-bottom:14px}
.input-modal input{width:100%;padding:11px;background:#111128;
  border:1px solid #2a2a4a;border-radius:10px;color:#eee;font-size:15px;
  margin-bottom:14px;outline:none}
.input-modal input:focus{border-color:#00d4ff}
.btn-row{display:flex;gap:10px}
</style>
</head>
<body>

<!-- Boot overlay -->
<div class="boot-overlay" id="boot-overlay">
  <div class="boot-spinner"></div>
  <div class="boot-text">Connecting to switches...<br>
    <span style="font-size:11px;color:#444;margin-top:4px;display:block">Please wait</span>
  </div>
</div>

<!-- Batch assignment modal -->
<div class="overlay" id="batch-overlay">
  <div class="modal">
    <h2>New Extensions Found</h2>
    <div class="subtitle" id="batch-subtitle"></div>
    <div id="batch-list"></div>
    <div class="modal-close">
      <button class="btn ghost" onclick="closeBatchModal()">Done</button>
    </div>
  </div>
</div>

<!-- Rename modal (switch or master) -->
<div class="overlay" id="rename-overlay">
  <div class="input-modal">
    <h2 id="rename-title">Rename</h2>
    <input id="rename-input" type="text" maxlength="23"/>
    <div class="btn-row">
      <button class="btn ghost" onclick="closeRenameModal()">Cancel</button>
      <button class="btn primary" onclick="submitRename()">Save</button>
    </div>
  </div>
</div>

<div class="topbar">
  <div>
    <div class="title-row">
      <h1 id="master-title" onclick="renameMaster()">Master 1</h1>
    </div>
    <div class="sub">
      <div class="dot" id="dot"></div>
      <span id="sub">Connecting...</span>
    </div>
  </div>
  <div class="topbar-btns">
    <button class="top-btn scan" id="scan-btn" onclick="startScan()">Scan</button>
    <a href="/settings" class="top-btn" style="text-decoration:none">Settings</a>
    <button class="top-btn" id="reorder-btn" onclick="toggleReorder()">Reorder</button>
    <button class="top-btn" id="save-btn" style="display:none;border-color:#4eff4e;color:#4eff4e"
            onclick="saveOrder()">Save</button>
    <button class="top-btn" id="cancel-btn" style="display:none"
            onclick="cancelReorder()">Cancel</button>
  </div>
</div>

<div class="grid" id="grid"></div>

<script>
let ws, reconnTimer=null;
let switchData=[], pendingData=[], offlineSlots=[];
let reorderMode=false, reorderList=[], originalOrder=[];
let renameTarget=null, renameType=null;
let pendingToggles={};
let activeMenuId=null;

/* close menus on outside click */
document.addEventListener('click',e=>{
  if(!e.target.closest('.sw-card')){
    document.querySelectorAll('.sw-dropdown.show')
      .forEach(d=>d.classList.remove('show'));
    activeMenuId=null;
  }
});

function uptime(s){
  if(s<60)return s+'s';
  if(s<3600)return Math.floor(s/60)+'m '+s%60+'s';
  return Math.floor(s/3600)+'h '+Math.floor((s%3600)/60)+'m';
}

function renderGrid(){
  const list=reorderMode?reorderList:switchData;
  let html='';
  if(!list.length){
    html='<div class="empty">No switches yet.<br>'+
         '<span style="font-size:11px;color:#333;margin-top:4px;display:block">'+
         'Tap Scan to find extensions.</span></div>';
  }
  list.forEach((sw,idx)=>{
    if(!sw||!sw.id||!sw.name) return;  /* guard against truncated frames */
    const off=!sw.online;
    const menuId='menu-'+sw.id;
    const btnId='btn-'+sw.id;
    const moveHtml=reorderMode?`
      <div class="move-btns">
        <div class="move-btn blank"></div>
        <div class="move-btn" onclick="moveUp(${idx})">&#8593;</div>
        <div class="move-btn blank"></div>
        <div class="move-btn" onclick="moveLeft(${idx})">&#8592;</div>
        <div class="move-btn blank"></div>
        <div class="move-btn" onclick="moveRight(${idx})">&#8594;</div>
        <div class="move-btn blank"></div>
        <div class="move-btn" onclick="moveDown(${idx})">&#8595;</div>
        <div class="move-btn blank"></div>
      </div>`:'';
    html+=`<div class="sw-card${off?' offline':''}${reorderMode?' reorder-mode':''}"
               style="border-left-color:${sw.color||'#444'}">
      <div class="sw-top">
        <div class="sw-names">
          <div class="sw-name">${sw.name}</div>
          <div class="sw-device">${sw.device_name||''}</div>
        </div>
        ${reorderMode?'':`
        <button class="sw-menu-btn" onclick="toggleSwMenu('${sw.id}',event)">&#8942;</button>
        <div class="sw-dropdown" id="${menuId}">
          <div class="sw-dropdown-item" onclick="renameSwitch('${sw.id}','${sw.name.replace(/'/g,"\'")}')">Rename</div>
        </div>`}
      </div>
      <button class="toggle ${sw.state?'on':'off'}" id="${btnId}"
              ${off||reorderMode?'disabled':''} onclick="toggle('${sw.id}')">
        <span class="lbl">${sw.state?'ON':'OFF'}</span>
        <div class="spinner"></div>
      </button>
      ${moveHtml}
    </div>`;
  });
  document.getElementById('grid').innerHTML=html;
}

function toggle(id){
  const btn=document.getElementById('btn-'+id);
  if(!btn||btn.disabled) return;
  const isOn=btn.classList.contains('on');
  btn.classList.remove('on','off'); btn.classList.add(isOn?'off':'on','loading');
  btn.querySelector('.lbl').textContent=isOn?'OFF':'ON';
  btn.disabled=true;
  const timer=setTimeout(()=>{
    btn.classList.remove('loading');
    btn.classList.remove(isOn?'off':'on');
    btn.classList.add(isOn?'on':'off');
    btn.querySelector('.lbl').textContent=isOn?'ON':'OFF';
    btn.disabled=false;
    delete pendingToggles[id];
  },1000);
  pendingToggles[id]={timer,expected:!isOn};
  fetch('/api/relay?id='+id+'&ch='+id.split('_')[1],{method:'POST'}).catch(()=>{
    clearTimeout(timer);
    btn.classList.remove('loading');
    btn.classList.remove(isOn?'off':'on');
    btn.classList.add(isOn?'on':'off');
    btn.querySelector('.lbl').textContent=isOn?'ON':'OFF';
    btn.disabled=false;
    delete pendingToggles[id];
  });
}

function confirmToggle(id,actual){
  if(!pendingToggles[id]) return;
  clearTimeout(pendingToggles[id].timer);
  const btn=document.getElementById('btn-'+id);
  if(btn){
    btn.classList.remove('loading','on','off');
    btn.classList.add(actual?'on':'off');
    btn.querySelector('.lbl').textContent=actual?'ON':'OFF';
    btn.disabled=false;
  }
  delete pendingToggles[id];
}

/* -- Reorder -- */
function toggleReorder(){
  reorderMode=true;
  reorderList=[...switchData];
  originalOrder=[...switchData];
  document.getElementById('reorder-btn').style.display='none';
  document.getElementById('save-btn').style.display='';
  document.getElementById('cancel-btn').style.display='';
  renderGrid();
}

function cancelReorder(){
  reorderMode=false;
  reorderList=[];
  document.getElementById('reorder-btn').style.display='';
  document.getElementById('save-btn').style.display='none';
  document.getElementById('cancel-btn').style.display='none';
  renderGrid();
}

function swap(arr,a,b){
  if(a<0||b<0||a>=arr.length||b>=arr.length) return false;
  [arr[a],arr[b]]=[arr[b],arr[a]]; return true;
}

function moveUp(idx){ if(swap(reorderList,idx,idx-2)) renderGrid(); }
function moveDown(idx){ if(swap(reorderList,idx,idx+2)) renderGrid(); }
function moveLeft(idx){ if(swap(reorderList,idx,idx-1)) renderGrid(); }
function moveRight(idx){ if(swap(reorderList,idx,idx+1)) renderGrid(); }

async function saveOrder(){
  const order=reorderList.map(s=>s.id).join(',');
  await fetch('/api/switch/reorder',{
    method:'POST',
    headers:{'Content-Type':'text/plain'},
    body:order
  });
  reorderMode=false;
  document.getElementById('reorder-btn').style.display='';
  document.getElementById('save-btn').style.display='none';
  document.getElementById('cancel-btn').style.display='none';
}

/* -- Menu -- */
function toggleSwMenu(id,e){
  e.stopPropagation();
  const d=document.getElementById('menu-'+id);
  const was=d.classList.contains('show');
  document.querySelectorAll('.sw-dropdown.show').forEach(x=>x.classList.remove('show'));
  if(!was){d.classList.add('show');activeMenuId=id;}
  else activeMenuId=null;
}

/* -- Rename -- */
function renameMaster(){
  renameTarget=null; renameType='master';
  document.getElementById('rename-title').textContent='Rename Master';
  document.getElementById('rename-input').value=
    document.getElementById('master-title').textContent;
  document.getElementById('rename-overlay').classList.add('show');
  setTimeout(()=>document.getElementById('rename-input').focus(),100);
}

function renameSwitch(id,current){
  document.querySelectorAll('.sw-dropdown.show').forEach(d=>d.classList.remove('show'));
  renameTarget=id; renameType='switch';
  document.getElementById('rename-title').textContent='Rename Switch';
  document.getElementById('rename-input').value=current;
  document.getElementById('rename-overlay').classList.add('show');
  setTimeout(()=>document.getElementById('rename-input').focus(),100);
}

function closeRenameModal(){
  document.getElementById('rename-overlay').classList.remove('show');
  renameTarget=null; renameType=null;
}

async function submitRename(){
  const name=document.getElementById('rename-input').value.trim();
  if(!name) return;
  if(renameType==='master'){
    await fetch('/api/master/rename?name='+encodeURIComponent(name),{method:'POST'});
    document.getElementById('master-title').textContent=name;
  } else {
    await fetch('/api/switch/rename?id='+renameTarget+'&name='+encodeURIComponent(name),{method:'POST'});
  }
  closeRenameModal();
}

/* -- Scan -- */
async function startScan(){
  await fetch('/api/scan',{method:'POST'});
}

/* -- Batch modal -- */
function openBatchModal(){
  const list=document.getElementById('batch-list');
  document.getElementById('batch-subtitle').textContent=
    pendingData.length+' new extension'+(pendingData.length>1?'s':'')+' found';
  list.innerHTML=pendingData.map((p,i)=>{
    const opts=offlineSlots.map(s=>
      `<option value="replace:${s.slot}">Replace Slot ${s.slot+1}</option>`
    ).join('');
    return `<div class="ext-item">
      <div class="ext-uid">ID: ${p.uid}</div>
      <div class="sw-inputs">
        <div>
          <label>Switch 1 name</label>
          <input id="sw1-${p.uid}" type="text" placeholder="e.g. Bed Light" maxlength="23"/>
        </div>
        <div>
          <label>Switch 2 name</label>
          <input id="sw2-${p.uid}" type="text" placeholder="e.g. Bed Fan" maxlength="23"/>
        </div>
      </div>
      <select id="action-${p.uid}">
        <option value="new">Add as new</option>
        ${opts}
      </select>
      <div class="ext-actions">
        <button class="btn danger" onclick="ignoreExt('${p.uid}')">Ignore</button>
        <button class="btn primary" onclick="assignExt('${p.uid}')">Add</button>
      </div>
    </div>`;
  }).join('');
  document.getElementById('batch-overlay').classList.add('show');
}

function closeBatchModal(){
  document.getElementById('batch-overlay').classList.remove('show');
}

async function assignExt(uid){
  const sw1=document.getElementById('sw1-'+uid).value.trim()||'Switch';
  const sw2=document.getElementById('sw2-'+uid).value.trim()||'Switch';
  const action=document.getElementById('action-'+uid).value;
  let slot=-1;
  if(action.startsWith('replace:')){
    slot=parseInt(action.split(':')[1]);
    if(!confirm('Replace offline slot '+(slot+1)+'?')) return;
    await fetch('/api/replace?uid='+uid+'&slot='+slot,{method:'POST'});
  } else {
    const r=await fetch('/api/assign?uid='+uid,{method:'POST'});
    const d=await r.json();
    slot=d.slot!==undefined?d.slot:-1;
  }
  /* Save switch names */
  if(slot>=0){
    await fetch('/api/switch/rename?id=ext'+slot+'_1&name='+encodeURIComponent(sw1),{method:'POST'});
    await fetch('/api/switch/rename?id=ext'+slot+'_2&name='+encodeURIComponent(sw2),{method:'POST'});
  }
  pendingData=pendingData.filter(p=>p.uid!==uid);
  if(pendingData.length===0) closeBatchModal();
  else openBatchModal();
}

async function ignoreExt(uid){
  await fetch('/api/reject?uid='+uid,{method:'POST'});
  pendingData=pendingData.filter(p=>p.uid!==uid);
  if(pendingData.length===0) closeBatchModal();
  else openBatchModal();
}

/* -- Render -- */
function render(d){
  /* Boot overlay */
  document.getElementById('boot-overlay')
    .classList.toggle('show',!d.boot_complete);

  document.getElementById('sub').textContent=
    '192.168.4.1 | '+uptime(d.uptime);
  document.getElementById('master-title').textContent=d.master_name||'Master 1';

  /* Scan button */
  document.getElementById('scan-btn')
    .classList.toggle('scanning',!!d.scan_active);

  switchData=d.switches||[];
  pendingData=d.pending||[];
  offlineSlots=d.offline_slots||[];

  /* Confirm pending toggles */
  switchData.forEach(sw=>{
    confirmToggle(sw.id, sw.state);
  });

  if(!reorderMode) renderGrid();

  /* Batch modal */
  const bo=document.getElementById('batch-overlay');
  if(pendingData.length>0&&!bo.classList.contains('show')) openBatchModal();
  else if(pendingData.length===0) bo.classList.remove('show');
}

/* -- WebSocket -- */
function connect(){
  if(reconnTimer){clearTimeout(reconnTimer);reconnTimer=null;}
  ws=new WebSocket('ws://192.168.4.1:81');
  ws.onopen=()=>{
    document.getElementById('dot').classList.add('on');
    document.getElementById('boot-overlay').classList.add('show');
  };
  ws.onmessage=e=>{
    try{
      const d=JSON.parse(e.data);
      render(d);
    }catch(err){
      console.error('Render error:',err);
      console.log('Raw data:',e.data.substring(0,200));
    }
  };
  ws.onclose=()=>{
    document.getElementById('dot').classList.remove('on');
    reconnTimer=setTimeout(connect,2000);
  };
  ws.onerror=()=>ws.close();
}
connect();
</script>
</body>
</html>
)rawhtml";

/* ================================================================
 * WEB ROUTES
 * ================================================================ */
static void setup_web(void) {
    server.on("/", HTTP_GET, [](){
        server.send_P(200,"text/html",HTML);
    });

    /* Relay toggle - immediate, with rate limiting */
    server.on("/api/relay", HTTP_POST, [](){
        String id=server.arg("id");
        int ch=server.arg("ch").toInt();
        uint32_t now=millis();

        /* id format: "master_1" or "master_2" */
        if (id.startsWith("master")&&(ch==1||ch==2)) {
            relay_cmd_t cmd; cmd.target=-1; cmd.channel=ch;
            xSemaphoreTake(state_mutex,portMAX_DELAY);
            cmd.state=(ch==1)?!master_relay1:!master_relay2;
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
                xSemaphoreTake(state_mutex,portMAX_DELAY);
                cmd.state=(ch==1)?!extensions[slot].relay1:!extensions[slot].relay2;
                xSemaphoreGive(state_mutex);
                xQueueSend(ext_relay_queue,&cmd,0);
                server.send(200,"application/json","{\"ok\":true}"); return;
            }
        }
        server.send(404,"application/json","{\"ok\":false}");
    });

    /* Assign new extension */
    server.on("/api/assign", HTTP_POST, [](){
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
        e->address=new_addr; e->state=EXT_ONLINE; e->missed=0;
        e->relay1=false; e->relay2=false;
        e->last_seen_ms=millis(); e->polled_once=true;
        if (name.length()>0) {
            strncpy(e->name,name.c_str(),sizeof(e->name)-1);
            e->name[sizeof(e->name)-1]='\0';
        }
        char slot_name[24]; strncpy(slot_name,e->name,sizeof(slot_name));
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
        xSemaphoreGive(state_mutex);
        nvs_remove(uid);
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Rename individual switch */
    server.on("/api/switch/rename", HTTP_POST, [](){
        String id   = server.arg("id");
        String name = server.arg("name");
        if (id.length()==0||name.length()==0) {
            server.send(400,"application/json","{\"ok\":false}"); return; }
        nvs_save_switch_name(id.c_str(), name.c_str());
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Rename master */
    server.on("/api/master/rename", HTTP_POST, [](){
        String name = server.arg("name");
        if (name.length()==0) {
            server.send(400,"application/json","{\"ok\":false}"); return; }
        xSemaphoreTake(state_mutex,portMAX_DELAY);
        strncpy(master_name,name.c_str(),sizeof(master_name)-1);
        master_name[sizeof(master_name)-1]=' ';
        xSemaphoreGive(state_mutex);
        nvs_save_master_name(name.c_str());
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Save switch order - single call after all moves done */
    server.on("/api/switch/reorder", HTTP_POST, [](){
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
    /* Settings page */
    /* Settings page */
    server.on("/settings", HTTP_GET, [](){
        server.send_P(200, "text/html", SETTINGS_HTML);
    });

    /* Device info API */
    server.on("/api/info", HTTP_GET, [](){
        char uid_str[20];
        snprintf(uid_str, sizeof(uid_str), "%02X%02X%02X%02X",
                 master_uid[0], master_uid[1], master_uid[2], master_uid[3]);
        StaticJsonDocument<256> doc;
        doc["uptime"]    = millis()/1000;
        doc["free_heap"] = ESP.getFreeHeap();
        doc["uid"]       = uid_str;
        String out; serializeJson(doc, out);
        server.send(200, "application/json", out);
    });

    /* OTA firmware upload */
    server.on("/api/ota/master", HTTP_POST,
        [](){
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
                Serial.printf("[OTA] Start: %s\n", upload.filename.c_str());
                ota_in_progress = true;
                if (!Update.begin(UPDATE_SIZE_UNKNOWN)) {
                    Serial.printf("[OTA] Begin failed: %s\n", Update.errorString());
                }
            } else if (upload.status == UPLOAD_FILE_WRITE) {
                if (Update.write(upload.buf, upload.currentSize) != upload.currentSize) {
                    Serial.printf("[OTA] Write failed: %s\n", Update.errorString());
                }
            } else if (upload.status == UPLOAD_FILE_END) {
                if (Update.end(true)) {
                    Serial.printf("[OTA] Complete: %u bytes\n", upload.totalSize);
                } else {
                    Serial.printf("[OTA] End failed: %s\n", Update.errorString());
                }
            }
        }
    );

        /* Manual scan trigger */
    server.on("/api/scan", HTTP_POST, [](){
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
            Serial.printf("[WS] Client #%u connected\n",num);
            String json=build_state_json();
            wss.sendTXT(num,json);
        } else if (type==WStype_DISCONNECTED) {
            Serial.printf("[WS] Client #%u disconnected\n",num);
        }
    });

    server.begin();
    wss.begin();
    Serial.println("[HTTP] Server on port 80, WebSocket on port 81");
}

/* ================================================================
 * SETUP
 * ================================================================ */
void setup() {
    Serial.begin(115200);
    // while (!Serial) delay(10);
    delay(500);
    Serial.println("\n[MASTER] Unisync v5.0 - booting");

    pinMode(RELAY1_PIN,   OUTPUT); digitalWrite(RELAY1_PIN,   LOW);
    pinMode(RELAY2_PIN,   OUTPUT); digitalWrite(RELAY2_PIN,   LOW);
    pinMode(RS485_DE_PIN, OUTPUT); digitalWrite(RS485_DE_PIN, LOW);
    pinMode(TOUCH1_PIN,   INPUT);
    pinMode(TOUCH2_PIN,   INPUT);

    BusSerial.begin(UART_BAUD, SERIAL_8N1, BUS_RX_PIN, BUS_TX_PIN);

    relay_state_load();
    digitalWrite(RELAY1_PIN, master_relay1?HIGH:LOW);
    digitalWrite(RELAY2_PIN, master_relay2?HIGH:LOW);
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
        snprintf(extensions[i].name,sizeof(extensions[i].name),"Slot-%d",i+1);
    }
    for (int i=0;i<MAX_PENDING;i++)    pending_queue[i].active=false;
    for (int i=0;i<MAX_CHALLENGES;i++) challenges[i].active=false;

    prefs.begin("ext_map",false); prefs.end();
    nvs_restore_all();

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

    WiFi.mode(WIFI_AP);
    WiFi.softAPConfig(AP_IP,AP_GW,AP_SUBNET);
    WiFi.softAP(AP_SSID,AP_PASS);
    Serial.printf("[WIFI] AP: %s  IP: %s\n",AP_SSID,AP_IP.toString().c_str());

    /* Get master UID from MAC - must be after WiFi init */
    uint8_t mac[6]; WiFi.macAddress(mac);
    master_uid[0]=mac[2]; master_uid[1]=mac[3];
    master_uid[2]=mac[4]; master_uid[3]=mac[5];
    Serial.printf("[MASTER] UID=%02X%02X%02X%02X\n",
                  master_uid[0],master_uid[1],master_uid[2],master_uid[3]);

    setup_web();

    xTaskCreate(task_touch,"touch",2048,NULL,3,NULL);
    xTaskCreate(task_bus,  "bus",  4096,NULL,2,NULL);
    xTaskCreate(task_web,  "web",  8192,NULL,1,NULL);

    Serial.println("[MASTER] Ready - connect to Unisync -> 192.168.4.1");
}

void loop() {
    vTaskDelay(pdMS_TO_TICKS(1000));
}
