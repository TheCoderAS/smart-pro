/*
 * Unisync - Master Firmware v6.2
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
#define WEBSOCKETS_MAX_DATA_SIZE 16384
#include <WebSocketsServer.h>
#include <ArduinoJson.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "freertos/queue.h"
#include "esp_now.h"
#include "esp_wifi.h"
#include "driver/gpio.h"
#include "html_content.h"

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
 * MESH CONFIG
 * ================================================================ */
#define MAX_MESH_MASTERS   8     /* OTA-updatable */
#define MESH_GOSSIP_MS     500   /* state broadcast interval */
#define MESH_PEER_TIMEOUT  3000  /* ms before peer marked offline */
#define MESH_PIN_VALID_MS  60000 /* PIN expires after 60s */

/* Mesh packet types */
#define MESH_PKT_STATE     0x01  /* broadcast local switch states */
#define MESH_PKT_RELAY_CMD 0x02  /* relay command for another master */
#define MESH_PKT_RELAY_ACK 0x03  /* relay command result */
#define MESH_PKT_JOIN_REQ  0x04  /* new master wants to join */
#define MESH_PKT_JOIN_ACK  0x05  /* accept + send mesh credentials */
#define MESH_PKT_JOIN_REJ  0x06  /* reject (wrong PIN) */
#define MESH_PKT_LEAVE     0x07  /* master leaving mesh */
#define MESH_PKT_PING      0x08  /* keepalive */

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

/* Mesh switch state (for gossip) */
typedef struct {
    char     id[16];
    char     name[24];
    char     color[8];
    bool     state;
    bool     online;
} mesh_switch_t;

/* Mesh peer (remote master) */
typedef struct {
    uint8_t       uid[4];
    uint8_t       mac[6];
    char          name[24];
    bool          online;
    uint32_t      last_seen_ms;
    mesh_switch_t switches[12];
    uint8_t       switch_count;
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
static int          ota_progress    = 0;
static String       ota_status      = "";

/* Mesh state */
static mesh_peer_t  mesh_peers[MAX_MESH_MASTERS];
static uint8_t      mesh_id[16]    = {0};  /* shared mesh secret */
static bool         mesh_active    = false;
static uint8_t      mesh_seq       = 0;
static uint32_t     last_gossip_ms = 0;

/* Mesh PIN (for inviting new masters) */
static char         mesh_pin[7]    = {0};  /* 6 digits + null */
static uint32_t     mesh_pin_ms    = 0;    /* when PIN was generated */
static bool         mesh_pin_valid = false;

/* Pending relay ACK tracking */
static uint8_t      pending_relay_req_id = 0;
static bool         pending_relay_ack    = false;
static SemaphoreHandle_t relay_ack_sem;

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
 * MESH CORE
 * ================================================================ */

/* Find or create peer slot by UID */
static int mesh_find_peer(const uint8_t *uid) {
    for (int i=0; i<MAX_MESH_MASTERS; i++)
        if (memcmp(mesh_peers[i].uid, uid, 4)==0) return i;
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
    return -1; /* mesh full */
}

/* Send ESP-NOW packet to a peer MAC */
static bool mesh_send(const uint8_t *mac, const void *data, size_t len) {
    if (!mesh_active) return false;
    esp_err_t r = esp_now_send(mac, (const uint8_t*)data, len);
    return (r == ESP_OK);
}

/* Broadcast to all known mesh peers */
static void mesh_broadcast(const void *data, size_t len) {
    if (!mesh_active) return;
    uint8_t broadcast_mac[6] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
    esp_now_send(broadcast_mac, (const uint8_t*)data, len);
}

/* Build and broadcast local state to all peers */
static void mesh_gossip(void) {
    if (!mesh_active) return;

    /* Build state packet */
    StaticJsonDocument<1024> doc;
    doc["type"]   = MESH_PKT_STATE;
    doc["name"]   = master_name;

    xSemaphoreTake(state_mutex, portMAX_DELAY);
    /* Snapshot local switches */
    String ord = switch_order.length()>0 ? switch_order : "";
    if (ord.length()==0) {
        ord = "master_1,master_2";
        for (int i=0;i<MAX_EXTENSIONS;i++) {
            if (extensions[i].state==EXT_EMPTY) continue;
            char a[16],b[16];
            snprintf(a,sizeof(a),"ext%d_1",i);
            snprintf(b,sizeof(b),"ext%d_2",i);
            ord+=","; ord+=a; ord+=","; ord+=b;
        }
    }
    bool r1=master_relay1, r2=master_relay2;
    xSemaphoreGive(state_mutex);

    JsonArray sw = doc.createNestedArray("switches");

    /* Add master switches */
    char sw_name[24];
    JsonObject s1=sw.createNestedObject();
    s1["id"]="master_1"; s1["ch"]=1;
    nvs_load_switch_name("master_1",sw_name,sizeof(sw_name));
    s1["name"]=(String(sw_name)=="Switch")?"Switch 1":sw_name;
    s1["color"]=SLOT_COLORS[0]; s1["state"]=r1; s1["online"]=true;

    JsonObject s2=sw.createNestedObject();
    s2["id"]="master_2"; s2["ch"]=2;
    nvs_load_switch_name("master_2",sw_name,sizeof(sw_name));
    s2["name"]=(String(sw_name)=="Switch")?"Switch 2":sw_name;
    s2["color"]=SLOT_COLORS[0]; s2["state"]=r2; s2["online"]=true;

    /* Add extension switches */
    xSemaphoreTake(state_mutex, portMAX_DELAY);
    for (int i=0;i<MAX_EXTENSIONS;i++) {
        if (extensions[i].state==EXT_EMPTY) continue;
        for (int ch=1;ch<=2;ch++) {
            char id[16]; snprintf(id,sizeof(id),"ext%d_%d",i,ch);
            nvs_load_switch_name(id,sw_name,sizeof(sw_name));
            JsonObject s=sw.createNestedObject();
            s["id"]=id; s["ch"]=ch;
            s["name"]=(String(sw_name)=="Switch")?
                      ("Switch "+String(ch+i*2+2)):sw_name;
            s["color"]=SLOT_COLORS[i+1<6?i+1:5];
            s["state"]=(ch==1)?extensions[i].relay1:extensions[i].relay2;
            s["online"]=(extensions[i].state==EXT_ONLINE);
        }
    }
    xSemaphoreGive(state_mutex);

    /* Add src_uid */
    char uid_str[12];
    snprintf(uid_str,sizeof(uid_str),"%02X%02X%02X%02X",
             master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
    doc["uid"] = uid_str;

    String payload; serializeJson(doc, payload);
    mesh_broadcast(payload.c_str(), payload.length()+1);
}

/* Generate 6-digit mesh PIN */
static void mesh_generate_pin(void) {
    uint32_t r = esp_random();
    snprintf(mesh_pin, sizeof(mesh_pin), "%06u", r % 1000000);
    mesh_pin_ms    = millis();
    mesh_pin_valid = true;
    Serial.printf("[MESH] PIN generated: %s\n", mesh_pin);
}

/* Verify incoming PIN */
static bool mesh_verify_pin(const char *pin) {
    if (!mesh_pin_valid) return false;
    if ((millis()-mesh_pin_ms) > MESH_PIN_VALID_MS) {
        mesh_pin_valid = false;
        return false;
    }
    bool ok = (strncmp(pin, mesh_pin, 6)==0);
    if (ok) mesh_pin_valid = false; /* consume PIN */
    return ok;
}

/* ESP-NOW receive callback */
static void mesh_recv_cb(const esp_now_recv_info_t *info,
                         const uint8_t *data, int len) {
    if (len < 2) return;

    /* Try to parse as JSON (state broadcast) */
    StaticJsonDocument<1024> doc;
    DeserializationError err = deserializeJson(doc, data, len);
    if (err) return;

    uint8_t type = doc["type"] | 0;
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
        /* State gossip from a peer */
        int idx = mesh_alloc_peer(src_uid, info->src_addr);
        if (idx < 0) return; /* mesh full */

        xSemaphoreTake(state_mutex, portMAX_DELAY);
        mesh_peers[idx].online       = true;
        mesh_peers[idx].last_seen_ms = millis();
        const char *pname = doc["name"] | "Master";
        strncpy(mesh_peers[idx].name, pname, sizeof(mesh_peers[idx].name)-1);
        memcpy(mesh_peers[idx].mac, info->src_addr, 6);

        JsonArray sw = doc["switches"];
        mesh_peers[idx].switch_count = 0;
        for (JsonObject s : sw) {
            int i = mesh_peers[idx].switch_count;
            if (i >= 12) break;
            strncpy(mesh_peers[idx].switches[i].id,
                    s["id"]|"", sizeof(mesh_peers[idx].switches[i].id)-1);
            strncpy(mesh_peers[idx].switches[i].name,
                    s["name"]|"", sizeof(mesh_peers[idx].switches[i].name)-1);
            strncpy(mesh_peers[idx].switches[i].color,
                    s["color"]|"#444", sizeof(mesh_peers[idx].switches[i].color)-1);
            mesh_peers[idx].switches[i].state  = s["state"]|false;
            mesh_peers[idx].switches[i].online = s["online"]|false;
            mesh_peers[idx].switch_count++;
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
        StaticJsonDocument<128> ack;
        ack["type"]   = MESH_PKT_RELAY_ACK;
        ack["uid"]    = String(uid_str[0])?uid_str:"";
        ack["req_id"] = req_id;
        ack["ok"]     = true;
        String ack_str; serializeJson(ack, ack_str);
        mesh_send(info->src_addr, ack_str.c_str(), ack_str.length()+1);

    } else if (type == MESH_PKT_RELAY_ACK) {
        uint8_t req_id = doc["req_id"] | 0;
        if (req_id == pending_relay_req_id) {
            pending_relay_ack = true;
            xSemaphoreGive(relay_ack_sem);
        }

    } else if (type == MESH_PKT_JOIN_REQ) {
        /* New master wants to join our mesh */
        if (!mesh_active) return;
        const char *pin = doc["pin"] | "";
        if (mesh_verify_pin(pin)) {
            /* Send mesh credentials */
            StaticJsonDocument<128> ack;
            char mid_hex[33];
            for (int i=0;i<16;i++) sprintf(mid_hex+i*2,"%02X",mesh_id[i]);
            mid_hex[32]=' ';
            ack["type"]    = MESH_PKT_JOIN_ACK;
            char self_uid[12];
            snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                     master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
            ack["uid"]     = self_uid;
            ack["mesh_id"] = mid_hex;
            String ack_str; serializeJson(ack, ack_str);
            /* Register sender as ESP-NOW peer first */
            esp_now_peer_info_t pi={};
            memcpy(pi.peer_addr, info->src_addr, 6);
            pi.channel=0; pi.encrypt=false;
            esp_now_add_peer(&pi);
            mesh_send(info->src_addr, ack_str.c_str(), ack_str.length()+1);
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
            pi.channel=0; pi.encrypt=false;
            esp_now_add_peer(&pi);
            mesh_send(info->src_addr, rej_str.c_str(), rej_str.length()+1);
            Serial.println("[MESH] JOIN rejected - wrong PIN");
        }

    } else if (type == MESH_PKT_JOIN_ACK) {
        /* We received mesh credentials - we are the joining master */
        const char *mid_hex = doc["mesh_id"] | "";
        if (strlen(mid_hex)==32) {
            for (int i=0;i<16;i++) {
                char byte_str[3]={mid_hex[i*2],mid_hex[i*2+1],0};
                mesh_id[i]=(uint8_t)strtoul(byte_str,NULL,16);
            }
            mesh_active = true;
            /* Register sender as peer */
            esp_now_peer_info_t pi={};
            memcpy(pi.peer_addr, info->src_addr, 6);
            pi.channel=0; pi.encrypt=false;
            if (!esp_now_is_peer_exist(pi.peer_addr))
                esp_now_add_peer(&pi);
            mesh_nvs_save();
            Serial.println("[MESH] Joined mesh successfully");
            notify_ui();
        }

    } else if (type == MESH_PKT_LEAVE) {
        /* Peer leaving - mark offline */
        int idx = mesh_find_peer(src_uid);
        if (idx >= 0) {
            xSemaphoreTake(state_mutex, portMAX_DELAY);
            mesh_peers[idx].online = false;
            xSemaphoreGive(state_mutex);
            notify_ui();
        }

    } else if (type == MESH_PKT_PING) {
        /* Just update last_seen */
        int idx = mesh_find_peer(src_uid);
        if (idx >= 0) {
            xSemaphoreTake(state_mutex, portMAX_DELAY);
            mesh_peers[idx].last_seen_ms = millis();
            mesh_peers[idx].online = true;
            xSemaphoreGive(state_mutex);
        }
    }
}

/* Initialize ESP-NOW mesh */
static void mesh_init(void) {
    if (esp_now_init() != ESP_OK) {
        Serial.println("[MESH] ESP-NOW init failed");
        return;
    }
    esp_now_register_recv_cb(mesh_recv_cb);

    /* Add broadcast peer */
    esp_now_peer_info_t pi={};
    uint8_t bcast[6]={0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
    memcpy(pi.peer_addr, bcast, 6);
    pi.channel=0; pi.encrypt=false;
    esp_now_add_peer(&pi);

    /* Re-add saved peers */
    for (int i=0;i<MAX_MESH_MASTERS;i++) {
        bool has_mac = false;
        for (int j=0;j<6;j++) if (mesh_peers[i].mac[j]) { has_mac=true; break; }
        if (!has_mac) continue;
        if (!esp_now_is_peer_exist(mesh_peers[i].mac)) {
            esp_now_peer_info_t p={};
            memcpy(p.peer_addr, mesh_peers[i].mac, 6);
            p.channel=0; p.encrypt=false;
            esp_now_add_peer(&p);
        }
    }
    Serial.println("[MESH] ESP-NOW initialized");
}

/* Send relay command to a remote master via mesh */
static bool mesh_relay_remote(const uint8_t *dst_uid, const uint8_t *dst_mac,
                               const char *sw_id, int ch, bool state) {
    pending_relay_req_id = (++mesh_seq);
    pending_relay_ack    = false;

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
    doc["req_id"]  = pending_relay_req_id;
    String payload; serializeJson(doc, payload);

    if (!mesh_send(dst_mac, payload.c_str(), payload.length()+1)) return false;

    /* Wait for ACK up to 500ms */
    return (xSemaphoreTake(relay_ack_sem, pdMS_TO_TICKS(500))==pdTRUE);
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
            Serial.printf("[MESH] Peer offline: %s\n", mesh_peers[i].name);
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
 * MESH NVS
 * ================================================================ */
static void mesh_nvs_save(void) {
    prefs.begin("mesh", false);
    prefs.putBytes("mesh_id", mesh_id, 16);
    prefs.putBool("active", mesh_active);
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
        uint8_t pc = prefs.getUChar("peer_count",0);
        for (int i=0;i<pc&&i<MAX_MESH_MASTERS;i++) {
            char key[12];
            snprintf(key,sizeof(key),"pm%d",i);
            prefs.getBytes(key,mesh_peers[i].mac,6);
            snprintf(key,sizeof(key),"pu%d",i);
            prefs.getBytes(key,mesh_peers[i].uid,4);
        }
    }
    prefs.end();
    if (mesh_active) Serial.println("[MESH] Credentials restored");
}

static void mesh_nvs_clear(void) {
    prefs.begin("mesh",false); prefs.clear(); prefs.end();
    memset(mesh_id,0,16);
    memset(mesh_peers,0,sizeof(mesh_peers));
    mesh_active=false;
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

        /* Listen window for ANNOUNCE frames
         * Drain relay commands first so UI stays responsive */
        if ((now-last_listen)>=LISTEN_INTERVAL_MS) {
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

    /* Mesh peers */
    doc["mesh_active"] = mesh_active;
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
        p["uid"]    = puid;
        p["name"]   = mesh_peers[i].name;
        p["online"] = mesh_peers[i].online;
        JsonArray psw = p.createNestedArray("switches");
        for (int j=0;j<mesh_peers[i].switch_count;j++) {
            JsonObject s = psw.createNestedObject();
            s["id"]     = mesh_peers[i].switches[j].id;
            s["name"]   = mesh_peers[i].switches[j].name;
            s["color"]  = mesh_peers[i].switches[j].color;
            s["state"]  = mesh_peers[i].switches[j].state;
            s["online"] = mesh_peers[i].switches[j].online;
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
/* SETTINGS_HTML defined in html_content.h */

/* HTML defined in html_content.h */

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

        /* -- Mesh API -- */

    /* Generate PIN to invite new master */
    server.on("/api/mesh/invite", HTTP_POST, [](){
        mesh_generate_pin();
        StaticJsonDocument<64> doc;
        doc["pin"]        = mesh_pin;
        doc["expires_ms"] = MESH_PIN_VALID_MS;
        String out; serializeJson(doc,out);
        server.send(200,"application/json",out);
    });

    /* New master: submit PIN to join a mesh */
    server.on("/api/mesh/join", HTTP_POST, [](){
        String pin = server.arg("pin");
        if (pin.length()!=6) {
            server.send(400,"application/json","{\"error\":\"invalid pin\"}");
            return;
        }
        if (mesh_active) {
            server.send(400,"application/json","{\"error\":\"already in mesh\"}");
            return;
        }
        /* Generate a unique mesh_id for first-time if not set */
        if (!mesh_active) {
            /* Broadcast join request to all ESP-NOW peers */
            StaticJsonDocument<128> doc;
            char self_uid[12];
            snprintf(self_uid,sizeof(self_uid),"%02X%02X%02X%02X",
                     master_uid[0],master_uid[1],master_uid[2],master_uid[3]);
            doc["type"] = MESH_PKT_JOIN_REQ;
            doc["uid"]  = self_uid;
            doc["pin"]  = pin.c_str();
            String payload; serializeJson(doc,payload);
            mesh_broadcast(payload.c_str(),payload.length()+1);
            /* Response comes async via mesh_recv_cb */
            server.send(200,"application/json","{\"ok\":true,\"status\":\"pending\"}");
        }
    });

    /* Create a new mesh (first master) */
    server.on("/api/mesh/create", HTTP_POST, [](){
        if (mesh_active) {
            server.send(400,"application/json","{\"error\":\"already in mesh\"}");
            return;
        }
        /* Generate random mesh ID */
        for (int i=0;i<16;i++) mesh_id[i]=(uint8_t)(esp_random()&0xFF);
        mesh_active = true;
        mesh_nvs_save();
        Serial.println("[MESH] New mesh created");
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Leave mesh */
    server.on("/api/mesh/leave", HTTP_POST, [](){
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
        mesh_nvs_clear();
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
    });

    /* Cross-master relay command */
    server.on("/api/mesh/relay", HTTP_POST, [](){
        String peer_uid_str = server.arg("peer_uid");
        String sw_id        = server.arg("sw_id");
        int    ch           = server.arg("ch").toInt();

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

        bool new_state = !cur_state;
        bool ok = mesh_relay_remote(peer_uid, mesh_peers[idx].mac,
                                    sw_id.c_str(), ch, new_state);

        if (ok) {
            /* Optimistically update local cache */
            xSemaphoreTake(state_mutex,portMAX_DELAY);
            for (int i=0;i<mesh_peers[idx].switch_count;i++) {
                if (strcmp(mesh_peers[idx].switches[i].id,sw_id.c_str())==0) {
                    mesh_peers[idx].switches[i].state = new_state;
                    break;
                }
            }
            xSemaphoreGive(state_mutex);
            notify_ui();
            server.send(200,"application/json","{\"ok\":true}");
        } else {
            server.send(500,"application/json","{\"error\":\"relay failed\"}");
        }
    });

    /* Mesh status */
    server.on("/api/mesh/status", HTTP_GET, [](){
        StaticJsonDocument<512> doc;
        doc["active"] = mesh_active;
        doc["pin_valid"] = mesh_pin_valid;
        if (mesh_pin_valid) doc["pin"] = mesh_pin;
        int online_count = 0;
        for (int i=0;i<MAX_MESH_MASTERS;i++)
            if (mesh_peers[i].online) online_count++;
        doc["peer_count"] = online_count;
        String out; serializeJson(doc,out);
        server.send(200,"application/json",out);
    });

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
    Serial.println("\n[MASTER] Unisync v6.2 - booting");

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

    pinMode(RELAY1_PIN,   OUTPUT); digitalWrite(RELAY1_PIN,   HIGH); /* active LOW */
    pinMode(RELAY2_PIN,   OUTPUT); digitalWrite(RELAY2_PIN,   HIGH); /* active LOW */
    pinMode(RS485_DE_PIN, OUTPUT); digitalWrite(RS485_DE_PIN, LOW);
    pinMode(TOUCH1_PIN,   INPUT);
    pinMode(TOUCH2_PIN,   INPUT);

    BusSerial.begin(UART_BAUD, SERIAL_8N1, BUS_RX_PIN, BUS_TX_PIN);

    relay_state_load();
    digitalWrite(RELAY1_PIN, master_relay1?LOW:HIGH);
    digitalWrite(RELAY2_PIN, master_relay2?LOW:HIGH);
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

    /* Init mesh - must be after WiFi */
    relay_ack_sem = xSemaphoreCreateBinary();
    mesh_nvs_load();
    mesh_init();

    xTaskCreate(task_touch,"touch",2048,NULL,3,NULL);
    xTaskCreate(task_bus,  "bus",  4096,NULL,2,NULL);
    xTaskCreate(task_web,  "web",  8192,NULL,1,NULL);

    Serial.println("[MASTER] Ready - connect to Unisync -> 192.168.4.1");
}

void loop() {
    vTaskDelay(pdMS_TO_TICKS(1000));
}
