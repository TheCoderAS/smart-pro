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
#define RELAY1_PIN    16
#define RELAY2_PIN    17
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
#define MISSED_MAX        3
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
#define CMD_ERROR         0xF0

/* ================================================================
 * RELAY RATE LIMITING
 * ================================================================ */
#define RELAY_RATE_LIMIT_MS  500  /* min ms between UI relay commands per channel */

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
static bool         scan_active    = false;  /* manual scan in progress */
static uint32_t     scan_end_ms    = 0;

/* Master UID (from ESP32 MAC) */
static uint8_t master_uid[4] = {0};

static SemaphoreHandle_t state_mutex;
static QueueHandle_t     master_relay_queue;
static QueueHandle_t     ext_relay_queue;
static QueueHandle_t     ws_notify_queue;

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

    /* Check if already registered in RAM */
    int existing=find_slot_by_uid(uid);
    if (existing>=0) {
        /* Known extension - re-welcome if OFFLINE */
        if (extensions[existing].state==EXT_OFFLINE) {
            uint8_t addr=extensions[existing].address;
            send_welcome(uid,addr,
                        extensions[existing].relay1,
                        extensions[existing].relay2);
            Serial.printf("[ANNOUNCE] Re-welcoming %s addr=0x%02X\n",
                          extensions[existing].name,addr);
        }
        return;
    }

    /* Check NVS */
    int saved_slot=nvs_load_slot(uid);
    if (saved_slot>=0&&saved_slot<MAX_EXTENSIONS) {
        /* Known UID - restore to saved slot */
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
        Serial.printf("[ANNOUNCE] Welcomed back: %s slot=%d addr=0x%02X\n",
                      saved_name,saved_slot+1,new_addr);
        notify_ui();
        return;
    }

    /* Brand new - add to pending queue */
    xSemaphoreTake(state_mutex,portMAX_DELAY);
    pending_add(uid);
    xSemaphoreGive(state_mutex);
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
                        if (buf[3]==CMD_ANNOUNCE) handle_announce(buf);
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
static void check_boot_complete(void) {
    if (boot_complete) return;
    bool all_polled=true;
    xSemaphoreTake(state_mutex,portMAX_DELAY);
    for (int i=0;i<MAX_EXTENSIONS;i++) {
        if (extensions[i].state==EXT_EMPTY) continue;
        if (!extensions[i].polled_once) { all_polled=false; break; }
    }
    xSemaphoreGive(state_mutex);
    if (all_polled) {
        boot_complete=true;
        Serial.println("[BOOT] All extensions polled - overlay dismissed");
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

        /* Expire pending entries older than 5 minutes */
        xSemaphoreTake(state_mutex,portMAX_DELAY);
        for (int i=0;i<MAX_PENDING;i++) {
            if (pending_queue[i].active&&
                (millis()-pending_queue[i].first_seen_ms)>300000) {
                pending_queue[i].active=false;
            }
        }
        xSemaphoreGive(state_mutex);

        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

/* ================================================================
 * STATE JSON
 * ================================================================ */
static String build_state_json(void) {
    xSemaphoreTake(state_mutex,portMAX_DELAY);
    StaticJsonDocument<3072> doc;
    doc["uptime"]=millis()/1000;
    doc["boot_complete"]=boot_complete;

    JsonObject master=doc.createNestedObject("master");
    master["relay1"]=master_relay1;
    master["relay2"]=master_relay2;

    JsonArray exts=doc.createNestedArray("extensions");
    for (int i=0;i<MAX_EXTENSIONS;i++) {
        if (extensions[i].state==EXT_EMPTY) continue;
        JsonObject e=exts.createNestedObject();
        char uid_str[12];
        snprintf(uid_str,sizeof(uid_str),"%02X%02X%02X%02X",
                 extensions[i].uid[0],extensions[i].uid[1],
                 extensions[i].uid[2],extensions[i].uid[3]);
        e["id"]="ext"+String(i);
        e["slot"]=i;
        e["name"]=extensions[i].name;
        e["state"]=(extensions[i].state==EXT_ONLINE)?"online":"offline";
        e["relay1"]=extensions[i].relay1;
        e["relay2"]=extensions[i].relay2;
        e["uid"]=uid_str;
    }

    /* Pending queue */
    JsonArray pending=doc.createNestedArray("pending");
    for (int i=0;i<MAX_PENDING;i++) {
        if (!pending_queue[i].active) continue;
        JsonObject p=pending.createNestedObject();
        char uid_str[12];
        snprintf(uid_str,sizeof(uid_str),"%02X%02X%02X%02X",
                 pending_queue[i].uid[0],pending_queue[i].uid[1],
                 pending_queue[i].uid[2],pending_queue[i].uid[3]);
        p["uid"]=uid_str;
    }

    /* Offline slots (for replace option) */
    JsonArray offline_slots=doc.createNestedArray("offline_slots");
    for (int i=0;i<MAX_EXTENSIONS;i++) {
        if (extensions[i].state!=EXT_OFFLINE) continue;
        JsonObject os=offline_slots.createNestedObject();
        os["slot"]=i;
        os["name"]=extensions[i].name;
    }

    doc["scan_active"]=scan_active;

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
h1{color:#00d4ff;font-size:22px;margin-bottom:4px}
.sub{color:#666;font-size:12px;margin-bottom:16px;
     display:flex;align-items:center;gap:8px}
.dot{width:8px;height:8px;border-radius:50%;background:#444;transition:background 0.3s}
.dot.on{background:#4eff4e}
.topbar{display:flex;align-items:center;justify-content:space-between;margin-bottom:20px}
.scan-btn{background:#1a1a2e;border:1px solid #2a2a4a;color:#00d4ff;
          padding:8px 14px;border-radius:8px;font-size:12px;cursor:pointer;
          display:flex;align-items:center;gap:6px}
.scan-btn:active{transform:scale(0.96)}
.scan-btn.scanning{border-color:#ffd700;color:#ffd700;animation:pulse 1s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:0.5}}
.card{background:#1a1a2e;border-radius:14px;padding:18px;
      margin-bottom:16px;border:1px solid #2a2a4a;transition:opacity 0.3s;
      position:relative}
.card.offline{opacity:0.4}
.card-header{display:flex;align-items:center;
             justify-content:space-between;margin-bottom:16px}
.card-title{font-size:16px;font-weight:600}
.card-menu{display:flex;align-items:center;gap:8px}
.badge{font-size:10px;padding:3px 10px;border-radius:20px;font-weight:700}
.badge.online{background:#0a2a0a;color:#4eff4e;border:1px solid #4eff4e}
.badge.offline{background:#2a0a0a;color:#ff4e4e;border:1px solid #ff4e4e}
.badge.master{background:#0a2a3a;color:#00d4ff;border:1px solid #00d4ff}
.menu-btn{background:none;border:none;color:#666;font-size:18px;
          cursor:pointer;padding:4px 8px;border-radius:6px;line-height:1}
.menu-btn:hover{background:#2a2a4a;color:#eee}
.dropdown{position:absolute;right:16px;top:52px;background:#1e1e38;
          border:1px solid #2a2a4a;border-radius:10px;min-width:160px;
          z-index:10;overflow:hidden;display:none}
.dropdown.show{display:block}
.dropdown-item{padding:10px 16px;font-size:13px;cursor:pointer;color:#eee}
.dropdown-item:hover{background:#2a2a4a}
.dropdown-item.danger{color:#ff4e4e}
.channels{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.ch{background:#111128;border-radius:10px;padding:14px;text-align:center}
.ch-label{font-size:11px;color:#666;margin-bottom:10px}
.toggle{width:100%;padding:12px;border:none;border-radius:8px;
        font-size:14px;font-weight:700;cursor:pointer;transition:all 0.15s;
        position:relative}
.toggle.on{background:#00d4ff;color:#000;box-shadow:0 0 12px rgba(0,212,255,0.3)}
.toggle.off{background:#1e1e38;color:#666;border:1px solid #2a2a4a}
.toggle:active{transform:scale(0.95)}
.toggle:disabled{cursor:not-allowed;opacity:0.7}
.toggle .spinner{display:none;width:14px;height:14px;border:2px solid rgba(0,0,0,0.3);
                 border-top-color:#000;border-radius:50%;animation:spin 0.6s linear infinite;
                 margin:0 auto}
.toggle.loading .spinner{display:block}
.toggle.loading .label{display:none}
@keyframes spin{to{transform:rotate(360deg)}}
.empty{color:#444;font-size:13px;text-align:center;padding:30px;
       border:1px dashed #2a2a4a;border-radius:14px;margin-bottom:16px}
/* Boot overlay */
.boot-overlay{display:none;position:fixed;inset:0;
              background:rgba(10,10,26,0.85);backdrop-filter:blur(8px);
              z-index:200;align-items:center;justify-content:center;
              flex-direction:column;gap:16px}
.boot-overlay.show{display:flex}
.boot-spinner{width:40px;height:40px;border:3px solid #2a2a4a;
              border-top-color:#00d4ff;border-radius:50%;
              animation:spin 0.8s linear infinite}
.boot-text{color:#888;font-size:14px;text-align:center}
/* Batch modal */
.overlay{display:none;position:fixed;inset:0;background:rgba(0,0,0,0.8);
         z-index:100;align-items:center;justify-content:center;padding:16px}
.overlay.show{display:flex}
.modal{background:#1a1a2e;border-radius:18px;padding:24px;width:100%;
       max-width:420px;border:1px solid #2a2a4a;max-height:80vh;overflow-y:auto}
.modal h2{color:#00d4ff;font-size:18px;margin-bottom:6px}
.modal .subtitle{color:#888;font-size:12px;margin-bottom:20px}
.ext-item{background:#111128;border-radius:12px;padding:14px;margin-bottom:12px;
          border:1px solid #2a2a4a}
.ext-item-header{display:flex;align-items:center;
                 justify-content:space-between;margin-bottom:12px}
.ext-uid{font-family:monospace;font-size:11px;color:#555}
.ext-item input{width:100%;padding:10px;background:#1a1a2e;
                border:1px solid #2a2a4a;border-radius:8px;
                color:#eee;font-size:14px;margin-bottom:10px;outline:none}
.ext-item input:focus{border-color:#00d4ff}
.ext-item select{width:100%;padding:10px;background:#1a1a2e;
                 border:1px solid #2a2a4a;border-radius:8px;
                 color:#eee;font-size:13px;margin-bottom:10px;outline:none}
.ext-actions{display:flex;gap:8px}
.btn{padding:9px 16px;border:none;border-radius:8px;
     font-size:13px;font-weight:700;cursor:pointer}
.btn.primary{background:#00d4ff;color:#000}
.btn.ghost{background:#2a2a4a;color:#aaa}
.btn.danger{background:#2a0a0a;color:#ff4e4e;border:1px solid #ff4e4e}
.modal-close{display:flex;justify-content:flex-end;margin-top:16px}
/* Rename modal */
.rename-modal{background:#1a1a2e;border-radius:18px;padding:24px;
              width:100%;max-width:360px;border:1px solid #2a2a4a}
.rename-modal h2{color:#00d4ff;font-size:16px;margin-bottom:16px}
.rename-modal input{width:100%;padding:12px;background:#111128;
                    border:1px solid #2a2a4a;border-radius:10px;
                    color:#eee;font-size:15px;margin-bottom:16px;outline:none}
.rename-modal input:focus{border-color:#00d4ff}
</style>
</head>
<body>

<!-- Boot overlay -->
<div class="boot-overlay" id="boot-overlay">
  <div class="boot-spinner"></div>
  <div class="boot-text">Connecting to switches...<br>
    <span style="font-size:11px;color:#555;margin-top:4px;display:block">
      Please wait while extensions come online
    </span>
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

<!-- Rename modal -->
<div class="overlay" id="rename-overlay">
  <div class="rename-modal">
    <h2>Rename Extension</h2>
    <input id="rename-input" type="text" maxlength="23" placeholder="New name"/>
    <div class="btn-row" style="display:flex;gap:10px">
      <button class="btn ghost" onclick="closeRenameModal()">Cancel</button>
      <button class="btn primary" onclick="submitRename()">Save</button>
    </div>
  </div>
</div>

<div class="topbar">
  <div>
    <h1>Unisync</h1>
    <div class="sub">
      <div class="dot" id="dot"></div>
      <span id="sub">Connecting...</span>
    </div>
  </div>
  <button class="scan-btn" id="scan-btn" onclick="startScan()">
    <span>&#9685;</span> Scan
  </button>
</div>

<div id="root"></div>

<script>
let ws, pendingData=[], offlineSlots=[];
let reconnTimer=null;
let activeMenuSlot=-1;
let renameSlot=-1;
let pendingToggles={};  /* slot_ch -> timeout */

function uptime(s){
  if(s<60)return s+'s';
  if(s<3600)return Math.floor(s/60)+'m '+s%60+'s';
  return Math.floor(s/3600)+'h '+Math.floor((s%3600)/60)+'m';
}

/* Close any open dropdown when clicking outside */
document.addEventListener('click', function(e){
  if(!e.target.closest('.card')){
    document.querySelectorAll('.dropdown.show')
      .forEach(d=>d.classList.remove('show'));
    activeMenuSlot=-1;
  }
});

function toggleMenu(slot, e){
  e.stopPropagation();
  const d=document.getElementById('menu-'+slot);
  const wasOpen=d.classList.contains('show');
  document.querySelectorAll('.dropdown.show')
    .forEach(dd=>dd.classList.remove('show'));
  if(!wasOpen){ d.classList.add('show'); activeMenuSlot=slot; }
  else activeMenuSlot=-1;
}

function card(id, slot, name, badgeCls, badgeLabel, r1, r2, offline, isMaster){
  const menuHtml = isMaster ? '' : `
    <button class="menu-btn" onclick="toggleMenu(${slot},event)">&#8942;</button>
    <div class="dropdown" id="menu-${slot}">
      <div class="dropdown-item" onclick="openRename(${slot},'${name.replace(/'/g,"\\'")}')">Rename</div>
      <div class="dropdown-item danger" onclick="removeExt(${slot})">Remove</div>
    </div>`;

  const ch=(label,state,action,key)=>`
    <div class="ch">
      <div class="ch-label">${label}</div>
      <button class="toggle ${state?'on':'off'}" id="btn-${key}"
        onclick="${action}">
        <span class="label">${state?'ON':'OFF'}</span>
        <div class="spinner"></div>
      </button>
    </div>`;

  return `<div class="card${offline?' offline':''}">
    <div class="card-header">
      <span class="card-title">${name}</span>
      <div class="card-menu">
        <span class="badge ${badgeCls}">${badgeLabel}</span>
        ${menuHtml}
      </div>
    </div>
    <div class="channels">
      ${ch('Channel 1',r1,`toggle('${id}',1,'${id}_1')`,`${id}_1`)}
      ${ch('Channel 2',r2,`toggle('${id}',2,'${id}_2')`,`${id}_2`)}
    </div>
  </div>`;
}

function toggle(id, ch, key){
  const btn=document.getElementById('btn-'+key);
  if(!btn||btn.disabled) return;

  /* Optimistic update */
  const isOn=btn.classList.contains('on');
  btn.classList.remove('on','off');
  btn.classList.add(isOn?'off':'on','loading');
  btn.querySelector('.label').textContent=isOn?'OFF':'ON';
  btn.disabled=true;

  /* Revert timeout if no WS confirmation in 1s */
  const timer=setTimeout(()=>{
    btn.classList.remove('loading');
    btn.classList.remove(isOn?'off':'on');
    btn.classList.add(isOn?'on':'off');
    btn.querySelector('.label').textContent=isOn?'ON':'OFF';
    btn.disabled=false;
    delete pendingToggles[key];
  },1000);
  pendingToggles[key]={timer,expectedState:!isOn};

  fetch('/api/relay?id='+id+'&ch='+ch,{method:'POST'})
    .catch(()=>{
      clearTimeout(timer);
      btn.classList.remove('loading');
      btn.classList.remove(isOn?'off':'on');
      btn.classList.add(isOn?'on':'off');
      btn.querySelector('.label').textContent=isOn?'ON':'OFF';
      btn.disabled=false;
      delete pendingToggles[key];
    });
}

function confirmToggle(key, actualState){
  if(!pendingToggles[key]) return;
  clearTimeout(pendingToggles[key].timer);
  const btn=document.getElementById('btn-'+key);
  if(btn){
    btn.classList.remove('loading','on','off');
    btn.classList.add(actualState?'on':'off');
    btn.querySelector('.label').textContent=actualState?'ON':'OFF';
    btn.disabled=false;
  }
  delete pendingToggles[key];
}

function render(d){
  /* Boot overlay */
  const bo=document.getElementById('boot-overlay');
  if(d.boot_complete) bo.classList.remove('show');
  else bo.classList.add('show');

  document.getElementById('sub').textContent=
    '192.168.4.1 | Uptime: '+uptime(d.uptime);

  let html=card('master',-1,'Master','master','MASTER',
    d.master.relay1,d.master.relay2,false,true);

  for(const e of d.extensions){
    const off=e.state==='offline';
    html+=card(e.id,e.slot,e.name,
      off?'offline':'online',off?'OFFLINE':'ONLINE',
      e.relay1,e.relay2,off,false);

    /* Confirm pending toggles */
    confirmToggle(e.id+'_1', e.relay1);
    confirmToggle(e.id+'_2', e.relay2);
  }
  /* Confirm master toggles */
  confirmToggle('master_1', d.master.relay1);
  confirmToggle('master_2', d.master.relay2);

  if(!d.extensions.length&&!d.pending.length)
    html+='<div class="empty">No extensions connected yet.<br>'+
          '<span style="font-size:11px;color:#333;margin-top:4px;display:block">'+
          'Tap Scan to find new extensions.</span></div>';

  document.getElementById('root').innerHTML=html;

  /* Store for batch modal */
  pendingData=d.pending||[];
  offlineSlots=d.offline_slots||[];

  /* Scan button state */
  const sb=document.getElementById('scan-btn');
  if(d.scan_active) sb.classList.add('scanning');
  else sb.classList.remove('scanning');

  /* Auto-open batch modal if pending and not already open */
  const batchOverlay=document.getElementById('batch-overlay');
  if(pendingData.length>0&&!batchOverlay.classList.contains('show')){
    openBatchModal();
  }
}

/* -- Scan -- */
async function startScan(){
  await fetch('/api/scan',{method:'POST'});
}

/* -- Batch modal -- */
function openBatchModal(){
  const list=document.getElementById('batch-list');
  const subtitle=document.getElementById('batch-subtitle');
  subtitle.textContent=pendingData.length+' new extension'+(pendingData.length>1?'s':'')+' found';

  list.innerHTML=pendingData.map((p,idx)=>{
    const opts=offlineSlots.map(s=>
      `<option value="replace:${s.slot}">Replace "${s.name}"</option>`
    ).join('');
    return `<div class="ext-item">
      <div class="ext-item-header">
        <span style="color:#888;font-size:12px">Extension ${idx+1}</span>
        <span class="ext-uid">${p.uid}</span>
      </div>
      <input id="name-${p.uid}" type="text" placeholder="e.g. Living Room" maxlength="23"/>
      <select id="action-${p.uid}">
        <option value="new">Add as new extension</option>
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
  const name=document.getElementById('name-'+uid).value.trim();
  if(!name){document.getElementById('name-'+uid).focus();return;}
  const action=document.getElementById('action-'+uid).value;

  if(action.startsWith('replace:')){
    const slot=parseInt(action.split(':')[1]);
    if(!confirm('Replace the offline extension in slot '+(slot+1)+'?')) return;
    await fetch('/api/replace?uid='+uid+'&slot='+slot+'&name='+encodeURIComponent(name),{method:'POST'});
  } else {
    await fetch('/api/assign?uid='+uid+'&name='+encodeURIComponent(name),{method:'POST'});
  }

  /* Remove from local list */
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

/* -- Rename -- */
function openRename(slot,currentName){
  document.querySelectorAll('.dropdown.show')
    .forEach(d=>d.classList.remove('show'));
  renameSlot=slot;
  document.getElementById('rename-input').value=currentName;
  document.getElementById('rename-overlay').classList.add('show');
  setTimeout(()=>document.getElementById('rename-input').focus(),100);
}

function closeRenameModal(){
  document.getElementById('rename-overlay').classList.remove('show');
  renameSlot=-1;
}

async function submitRename(){
  const name=document.getElementById('rename-input').value.trim();
  if(!name||renameSlot<0) return;
  await fetch('/api/rename?slot='+renameSlot+'&name='+encodeURIComponent(name),{method:'POST'});
  closeRenameModal();
}

/* -- Remove -- */
async function removeExt(slot){
  document.querySelectorAll('.dropdown.show')
    .forEach(d=>d.classList.remove('show'));
  if(!confirm('Remove this extension? It will need to be re-assigned if reconnected.')) return;
  await fetch('/api/remove?slot='+slot,{method:'POST'});
}

/* -- WebSocket -- */
function connect(){
  if(reconnTimer){clearTimeout(reconnTimer);reconnTimer=null;}
  ws=new WebSocket('ws://192.168.4.1:81');
  ws.onopen=()=>{
    document.getElementById('dot').classList.add('on');
    document.getElementById('sub').textContent='Connected';
    document.getElementById('boot-overlay').classList.add('show');
  };
  ws.onmessage=(e)=>{try{render(JSON.parse(e.data));}catch(err){}};
  ws.onclose=()=>{
    document.getElementById('dot').classList.remove('on');
    document.getElementById('sub').textContent='Reconnecting...';
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

        if (id=="master"&&(ch==1||ch==2)) {
            /* Rate limiting */
            uint32_t *last=(ch==1)?&last_relay1_cmd_ms:&last_relay2_cmd_ms;
            if ((now-*last)<RELAY_RATE_LIMIT_MS) {
                server.send(429,"application/json","{\"error\":\"rate_limited\"}");
                return;
            }
            *last=now;
            relay_cmd_t cmd; cmd.target=-1; cmd.channel=ch;
            xSemaphoreTake(state_mutex,portMAX_DELAY);
            cmd.state=(ch==1)?!master_relay1:!master_relay2;
            xSemaphoreGive(state_mutex);
            xQueueSend(master_relay_queue,&cmd,0);
            server.send(200,"application/json","{\"ok\":true}"); return;
        }
        if (id.startsWith("ext")) {
            int slot=id.substring(3).toInt();
            if (slot>=0&&slot<MAX_EXTENSIONS) {
                /* Rate limiting per channel */
                uint32_t *last=(ch==1)?&extensions[slot].last_relay1_cmd_ms
                                      :&extensions[slot].last_relay2_cmd_ms;
                if ((now-*last)<RELAY_RATE_LIMIT_MS) {
                    server.send(429,"application/json","{\"error\":\"rate_limited\"}");
                    return;
                }
                *last=now;
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

        nvs_save(uid,slot,name.c_str());
        send_welcome(uid,new_addr,false,false);
        Serial.printf("[ASSIGN] %s -> slot%d addr=0x%02X\n",
                      name.c_str(),slot+1,new_addr);
        notify_ui();
        server.send(200,"application/json","{\"ok\":true}");
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
        send_welcome(new_uid,new_addr,false,false);
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
    while (!Serial) delay(10);
    delay(500);
    Serial.println("\n[MASTER] Unisync v5.0 - booting");

    /* Get master UID from ESP32 MAC */
    uint8_t mac[6]; WiFi.macAddress(mac);
    master_uid[0]=mac[2]; master_uid[1]=mac[3];
    master_uid[2]=mac[4]; master_uid[3]=mac[5];
    Serial.printf("[MASTER] UID=%02X%02X%02X%02X\n",
                  master_uid[0],master_uid[1],master_uid[2],master_uid[3]);

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
    for (int i=0;i<MAX_PENDING;i++) pending_queue[i].active=false;

    prefs.begin("ext_map",false); prefs.end();
    nvs_restore_all();

    /* If no extensions in NVS, boot is immediately complete */
    bool has_extensions=false;
    for (int i=0;i<MAX_EXTENSIONS;i++)
        if (extensions[i].state!=EXT_EMPTY) { has_extensions=true; break; }
    if (!has_extensions) boot_complete=true;

    state_mutex=xSemaphoreCreateMutex();
    master_relay_queue=xQueueCreate(16,sizeof(relay_cmd_t));
    ext_relay_queue=xQueueCreate(16,sizeof(relay_cmd_t));
    ws_notify_queue=xQueueCreate(8,sizeof(uint8_t));

    WiFi.mode(WIFI_AP);
    WiFi.softAPConfig(AP_IP,AP_GW,AP_SUBNET);
    WiFi.softAP(AP_SSID,AP_PASS);
    Serial.printf("[WIFI] AP: %s  IP: %s\n",AP_SSID,AP_IP.toString().c_str());

    setup_web();

    xTaskCreate(task_touch,"touch",2048,NULL,3,NULL);
    xTaskCreate(task_bus,  "bus",  4096,NULL,2,NULL);
    xTaskCreate(task_web,  "web",  8192,NULL,1,NULL);

    Serial.println("[MASTER] Ready - connect to Unisync -> 192.168.4.1");
}

void loop() {
    vTaskDelay(pdMS_TO_TICKS(1000));
}
