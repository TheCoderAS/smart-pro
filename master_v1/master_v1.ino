/*
 * Smart Switch - Master Firmware v4.0
 * ESP32-C6 Beetle v1.1
 *
 * Libraries:
 *   - WebServer.h (built-in ESP32)
 *   - WebSocketsServer by Markus Sattler
 *   - ArduinoJson
 *   - Preferences (built-in ESP32)
 *
 * Architecture:
 *   - WebServer.h: HTTP REST API
 *   - WebSocketsServer: push state to UI on every change
 *   - 3 FreeRTOS tasks: touch(3) > bus(2) > web(1)
 *   - touch task: relay fires in <20ms, never blocked
 *   - bus task: RS-485 polling, discovery, relay commands
 *   - web task: HTTP + WebSocket, handles UI requests
 *
 * Pins:
 *   GPIO4  - RS485 RX
 *   GPIO5  - RS485 TX
 *   GPIO16 - Relay 1
 *   GPIO17 - Relay 2
 *   GPIO19 - Touch 1
 *   GPIO20 - Touch 2
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
#define AP_SSID   "SmartSwitch"
#define AP_PASS   "12345678"
#define AP_IP     IPAddress(192,168,4,1)
#define AP_GW     IPAddress(192,168,4,1)
#define AP_SUBNET IPAddress(255,255,255,0)

/* ================================================================
 * BUS PROTOCOL
 * ================================================================ */
#define UART_BAUD         250000
#define MAX_EXTENSIONS    5
#define POLL_MS           200
#define MISSED_MAX        3
#define BUS_RESP_MS       20
#define DISCOVERY_MS      5000

#define SOF               0xAA
#define ADDR_MASTER       0x00
#define ADDR_UNASSIGNED   0xFE
#define ADDR_BCAST        0xFF

#define CMD_PING          0x00
#define CMD_PONG          0x01
#define CMD_ENUM_REQ      0x10
#define CMD_ENUM_RESP     0x11
#define CMD_SET_ADDR      0x12
#define CMD_SET_RELAY     0x20
#define CMD_GET_STATE     0x21
#define CMD_STATE_RESP    0x22
#define CMD_DRAIN_EVENTS  0x23

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
} extension_t;

typedef struct {
    int     target;   /* -1=master, 0-4=extension slot */
    uint8_t channel;
    bool    state;
} relay_cmd_t;

/* ================================================================
 * SHARED STATE
 * ================================================================ */
static extension_t extensions[MAX_EXTENSIONS];
static bool        master_relay1 = false;
static bool        master_relay2 = false;
static bool        pending_ext   = false;
static uint8_t     pending_uid[4] = {0};
static uint8_t     pending_addr   = 0;

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
        for (int i = 0; i < 8; i++)
            crc = (crc & 0x80) ? (crc << 1) ^ 0x07 : crc << 1;
    }
    return crc;
}

/* ================================================================
 * RS-485
 * ================================================================ */
static void bus_send(uint8_t dst, uint8_t cmd,
                     const uint8_t *payload, uint8_t len) {
    uint8_t frame[38];
    frame[0] = SOF;
    frame[1] = dst;
    frame[2] = ADDR_MASTER;
    frame[3] = cmd;
    frame[4] = len;
    for (int i = 0; i < len; i++) frame[5+i] = payload[i];
    frame[5+len] = crc8(&frame[1], 4+len);
    digitalWrite(RS485_DE_PIN, HIGH);
    BusSerial.write(frame, 6+len);
    BusSerial.flush();
    digitalWrite(RS485_DE_PIN, LOW);
}

static uint8_t bus_recv(uint8_t *buf, uint8_t max_len,
                        uint32_t timeout_ms) {
    uint32_t start = millis();
    uint8_t  pos   = 0;
    uint8_t  elen  = 0;
    while ((millis() - start) < timeout_ms) {
        if (BusSerial.available()) {
            uint8_t b = BusSerial.read();
            if (pos == 0) {
                if (b == SOF) buf[pos++] = b;
            } else {
                if (pos >= max_len) return 0;
                buf[pos++] = b;
                if (pos == 5) elen = 6 + buf[4];
                if (elen > 0 && pos >= elen) return pos;
            }
        } else {
            vTaskDelay(pdMS_TO_TICKS(1));
        }
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
    uint8_t sig = 1;
    xQueueSend(ws_notify_queue, &sig, 0);
}

/* ================================================================
 * NVS
 * ================================================================ */
static void nvs_uid_key(const uint8_t *uid, char *key, int klen) {
    snprintf(key, klen, "%02X%02X%02X%02X",
             uid[0], uid[1], uid[2], uid[3]);
}

static int nvs_load_slot(const uint8_t *uid) {
    char key[12]; nvs_uid_key(uid, key, sizeof(key));
    prefs.begin("ext_map", true);
    int s = prefs.getInt(key, -1);
    prefs.end();
    return s;
}

static void nvs_load_name(const uint8_t *uid, char *name, int nlen) {
    char key[12]; nvs_uid_key(uid, key, sizeof(key));
    char nkey[16]; snprintf(nkey, sizeof(nkey), "n%s", key);
    prefs.begin("ext_map", true);
    String s = prefs.getString(nkey, "Switch");
    prefs.end();
    strncpy(name, s.c_str(), nlen-1);
    name[nlen-1] = '\0';
}

static void nvs_save(const uint8_t *uid, int slot, const char *name) {
    char key[12]; nvs_uid_key(uid, key, sizeof(key));
    char nkey[16]; snprintf(nkey, sizeof(nkey), "n%s", key);
    prefs.begin("ext_map", false);
    prefs.putInt(key, slot);
    prefs.putString(nkey, name);
    String index   = prefs.getString("uid_index", "");
    String uid_str = String(key);
    if (index.indexOf(uid_str) < 0) {
        if (index.length() > 0) index += ",";
        index += uid_str;
        prefs.putString("uid_index", index);
    }
    prefs.end();
}

static void nvs_restore_all(void) {
    prefs.begin("ext_map", true);
    String index = prefs.getString("uid_index", "");
    prefs.end();
    if (index.length() == 0) return;
    int start = 0;
    while (start < (int)index.length()) {
        int    comma   = index.indexOf(',', start);
        String uid_str = (comma < 0) ? index.substring(start)
                                     : index.substring(start, comma);
        start = (comma < 0) ? index.length() : comma+1;
        if (uid_str.length() != 8) continue;
        uint8_t uid[4];
        uid[0] = strtoul(uid_str.substring(0,2).c_str(), NULL, 16);
        uid[1] = strtoul(uid_str.substring(2,4).c_str(), NULL, 16);
        uid[2] = strtoul(uid_str.substring(4,6).c_str(), NULL, 16);
        uid[3] = strtoul(uid_str.substring(6,8).c_str(), NULL, 16);
        int slot = nvs_load_slot(uid);
        if (slot < 0 || slot >= MAX_EXTENSIONS) continue;
        char name[24]; nvs_load_name(uid, name, sizeof(name));
        extension_t *e = &extensions[slot];
        memcpy(e->uid, uid, 4);
        e->address = ADDR_UNASSIGNED;
        e->state   = EXT_OFFLINE;
        e->missed  = 0;
        e->relay1  = false;
        e->relay2  = false;
        e->last_seen_ms = 0;
        strncpy(e->name, name, sizeof(e->name)-1);
        e->name[sizeof(e->name)-1] = '\0';
        Serial.printf("[NVS] Restored: %s -> slot%d\n", name, slot+1);
    }
}

/* ================================================================
 * SLOT HELPERS
 * ================================================================ */
static int find_slot_by_addr(uint8_t addr) {
    for (int i = 0; i < MAX_EXTENSIONS; i++)
        if (extensions[i].state != EXT_EMPTY &&
            extensions[i].address == addr) return i;
    return -1;
}

static int find_slot_by_uid(const uint8_t *uid) {
    for (int i = 0; i < MAX_EXTENSIONS; i++)
        if (extensions[i].state != EXT_EMPTY &&
            memcmp(extensions[i].uid, uid, 4) == 0) return i;
    return -1;
}

static int find_empty_slot(void) {
    for (int i = 0; i < MAX_EXTENSIONS; i++)
        if (extensions[i].state == EXT_EMPTY) return i;
    return -1;
}

static uint8_t next_free_addr(void) {
    for (uint8_t a = 1; a <= MAX_EXTENSIONS; a++)
        if (find_slot_by_addr(a) == -1) return a;
    return ADDR_UNASSIGNED;
}

/* ================================================================
 * DISCOVERY (called from bus task only)
 * ================================================================ */
static void run_discovery(void) {
    xSemaphoreTake(state_mutex, portMAX_DELAY);
    bool has_pending = pending_ext;
    xSemaphoreGive(state_mutex);
    if (has_pending) return;

    uint8_t resp[40];
    uint8_t resp_len, plen;

    /* Step 1: Broadcast PING - finds already-addressed extensions */
    flush_rx();
    bus_send(ADDR_BCAST, CMD_PING, NULL, 0);
    resp_len = bus_recv(resp, sizeof(resp), 100);

    if (resp_len > 0 && resp[3] == CMD_PONG) {
        plen = resp[4];
        if (resp[5+plen] == crc8(&resp[1], 4+plen)) {
            uint8_t src = resp[2];
            xSemaphoreTake(state_mutex, portMAX_DELAY);
            bool known = (find_slot_by_addr(src) >= 0);
            xSemaphoreGive(state_mutex);
            if (known) return;

            /* Unknown address - query its UID */
            Serial.printf("[DISC] Untracked ext at addr=0x%02X\n", src);
            flush_rx();
            bus_send(src, CMD_ENUM_REQ, NULL, 0);
            resp_len = bus_recv(resp, sizeof(resp), 150);
            if (resp_len > 0 && resp[3] == CMD_ENUM_RESP && resp[4] >= 4) {
                plen = resp[4];
                if (resp[5+plen] == crc8(&resp[1], 4+plen)) {
                    uint8_t *uid = &resp[5];
                    int saved_slot = nvs_load_slot(uid);
                    if (saved_slot >= 0 && saved_slot < MAX_EXTENSIONS) {
                        char saved_name[24];
                        nvs_load_name(uid, saved_name, sizeof(saved_name));
                        xSemaphoreTake(state_mutex, portMAX_DELAY);
                        extension_t *e = &extensions[saved_slot];
                        memcpy(e->uid, uid, 4);
                        e->address      = src;
                        e->state        = EXT_ONLINE;
                        e->missed       = 0;
                        e->last_seen_ms = millis();
                        strncpy(e->name, saved_name, sizeof(e->name)-1);
                        xSemaphoreGive(state_mutex);
                        Serial.printf("[DISC] Restored: %s slot=%d addr=0x%02X\n",
                                      saved_name, saved_slot+1, src);
                        notify_ui();
                        return;
                    }
                    /* Not in NVS - new extension with existing address */
                    xSemaphoreTake(state_mutex, portMAX_DELAY);
                    pending_ext  = true;
                    memcpy(pending_uid, uid, 4);
                    pending_addr = src;
                    xSemaphoreGive(state_mutex);
                    notify_ui();
                    return;
                }
            }
        }
    }

    /* Step 2: ENUM_REQ - for unaddressed extensions */
    flush_rx();
    bus_send(ADDR_BCAST, CMD_ENUM_REQ, NULL, 0);
    resp_len = bus_recv(resp, sizeof(resp), 150);
    if (resp_len == 0) return;

    plen = resp[4];
    if (resp[3] != CMD_ENUM_RESP || plen < 4) return;
    if (resp[5+plen] != crc8(&resp[1], 4+plen)) return;

    uint8_t *uid = &resp[5];

    /* Already tracked in RAM? */
    xSemaphoreTake(state_mutex, portMAX_DELAY);
    int existing = find_slot_by_uid(uid);
    xSemaphoreGive(state_mutex);
    if (existing >= 0) {
        uint8_t new_addr = next_free_addr();
        if (new_addr == ADDR_UNASSIGNED) return;
        uint8_t payload[5] = {uid[0],uid[1],uid[2],uid[3],new_addr};
        flush_rx();
        bus_send(ADDR_UNASSIGNED, CMD_SET_ADDR, payload, 5);
        resp_len = bus_recv(resp, sizeof(resp), 200);
        if (resp_len == 0 || resp[3] != CMD_PONG || resp[2] != new_addr) return;
        xSemaphoreTake(state_mutex, portMAX_DELAY);
        extensions[existing].address      = new_addr;
        extensions[existing].state        = EXT_ONLINE;
        extensions[existing].missed       = 0;
        extensions[existing].last_seen_ms = millis();
        xSemaphoreGive(state_mutex);
        notify_ui();
        return;
    }

    /* Check NVS */
    int saved_slot = nvs_load_slot(uid);
    if (saved_slot >= 0 && saved_slot < MAX_EXTENSIONS) {
        uint8_t new_addr = next_free_addr();
        if (new_addr == ADDR_UNASSIGNED) return;
        uint8_t payload[5] = {uid[0],uid[1],uid[2],uid[3],new_addr};
        flush_rx();
        bus_send(ADDR_UNASSIGNED, CMD_SET_ADDR, payload, 5);
        resp_len = bus_recv(resp, sizeof(resp), 200);
        if (resp_len == 0 || resp[3] != CMD_PONG || resp[2] != new_addr) return;
        char saved_name[24]; nvs_load_name(uid, saved_name, sizeof(saved_name));
        xSemaphoreTake(state_mutex, portMAX_DELAY);
        extension_t *e = &extensions[saved_slot];
        memcpy(e->uid, uid, 4);
        e->address      = new_addr;
        e->state        = EXT_ONLINE;
        e->missed       = 0;
        e->relay1       = false;
        e->relay2       = false;
        e->last_seen_ms = millis();
        strncpy(e->name, saved_name, sizeof(e->name)-1);
        xSemaphoreGive(state_mutex);
        notify_ui();
        return;
    }

    /* Brand new extension */
    uint8_t new_addr = next_free_addr();
    if (new_addr == ADDR_UNASSIGNED) return;
    uint8_t payload[5] = {uid[0],uid[1],uid[2],uid[3],new_addr};
    flush_rx();
    bus_send(ADDR_UNASSIGNED, CMD_SET_ADDR, payload, 5);
    resp_len = bus_recv(resp, sizeof(resp), 200);
    if (resp_len == 0 || resp[3] != CMD_PONG || resp[2] != new_addr) return;
    xSemaphoreTake(state_mutex, portMAX_DELAY);
    pending_ext  = true;
    memcpy(pending_uid, uid, 4);
    pending_addr = new_addr;
    xSemaphoreGive(state_mutex);
    Serial.printf("[DISC] New ext UID=%02X%02X%02X%02X\n",
                  uid[0],uid[1],uid[2],uid[3]);
    notify_ui();
}

/* ================================================================
 * POLL ONE EXTENSION (bus task only)
 * ================================================================ */
static void poll_extension(int i) {
    xSemaphoreTake(state_mutex, portMAX_DELAY);
    if (extensions[i].state == EXT_EMPTY) {
        xSemaphoreGive(state_mutex); return;
    }
    uint8_t addr = extensions[i].address;
    if (addr == ADDR_UNASSIGNED) {
        xSemaphoreGive(state_mutex); return;
    }
    xSemaphoreGive(state_mutex);

    uint8_t resp[40]; uint8_t resp_len, plen;
    flush_rx();
    bus_send(addr, CMD_GET_STATE, NULL, 0);
    resp_len = bus_recv(resp, sizeof(resp), BUS_RESP_MS);

    xSemaphoreTake(state_mutex, portMAX_DELAY);
    if (resp_len == 0) {
        extensions[i].missed++;
        if (extensions[i].missed >= MISSED_MAX &&
            extensions[i].state == EXT_ONLINE) {
            extensions[i].state = EXT_OFFLINE;
            Serial.printf("[OFFLINE] %s\n", extensions[i].name);
            xSemaphoreGive(state_mutex);
            notify_ui(); return;
        }
        xSemaphoreGive(state_mutex); return;
    }

    plen = resp[4];
    if (resp[5+plen] != crc8(&resp[1], 4+plen) || resp[2] != addr) {
        extensions[i].missed++;
        xSemaphoreGive(state_mutex); return;
    }

    extensions[i].missed       = 0;
    extensions[i].last_seen_ms = millis();
    bool was_offline = (extensions[i].state == EXT_OFFLINE);
    if (was_offline) extensions[i].state = EXT_ONLINE;

    bool changed = was_offline;
    if (resp[3] == CMD_STATE_RESP && resp[4] >= 3) {
        uint8_t flags = resp[5];
        uint8_t evts  = resp[7];
        bool r1 = (flags >> 0) & 0x01;
        bool r2 = (flags >> 1) & 0x01;
        if (r1 != extensions[i].relay1 || r2 != extensions[i].relay2) {
            extensions[i].relay1 = r1;
            extensions[i].relay2 = r2;
            changed = true;
        }
        if (evts > 0) {
            uint8_t drain[1] = {evts};
            xSemaphoreGive(state_mutex);
            bus_send(addr, CMD_DRAIN_EVENTS, drain, 1);
            if (changed) notify_ui();
            if (was_offline) Serial.printf("[ONLINE] %s\n", extensions[i].name);
            return;
        }
    }
    xSemaphoreGive(state_mutex);
    if (changed) notify_ui();
    if (was_offline) Serial.printf("[ONLINE] %s\n", extensions[i].name);
}

/* ================================================================
 * TASK: TOUCH (priority 3 - highest)
 * Relay fires in <20ms, never blocked by bus or web
 * ================================================================ */
static void task_touch(void *arg) {
    bool last_t1 = false, last_t2 = false;
    for (;;) {
        bool t1 = digitalRead(TOUCH1_PIN);
        bool t2 = digitalRead(TOUCH2_PIN);

        if (t1 && !last_t1) {
            xSemaphoreTake(state_mutex, portMAX_DELAY);
            master_relay1 = !master_relay1;
            bool s = master_relay1;
            xSemaphoreGive(state_mutex);
            digitalWrite(RELAY1_PIN, s ? HIGH : LOW);
            Serial.printf("[TOUCH] CH1 -> %s\n", s?"ON":"OFF");
            notify_ui();
        }
        if (t2 && !last_t2) {
            xSemaphoreTake(state_mutex, portMAX_DELAY);
            master_relay2 = !master_relay2;
            bool s = master_relay2;
            xSemaphoreGive(state_mutex);
            digitalWrite(RELAY2_PIN, s ? HIGH : LOW);
            Serial.printf("[TOUCH] CH2 -> %s\n", s?"ON":"OFF");
            notify_ui();
        }
        last_t1 = t1;
        last_t2 = t2;

        /* Drain master relay commands sent from web */
        relay_cmd_t cmd;
        while (xQueueReceive(master_relay_queue, &cmd, 0) == pdTRUE) {
            xSemaphoreTake(state_mutex, portMAX_DELAY);
            if (cmd.channel == 1) master_relay1 = cmd.state;
            else                  master_relay2 = cmd.state;
            xSemaphoreGive(state_mutex);
            digitalWrite(cmd.channel==1 ? RELAY1_PIN : RELAY2_PIN,
                         cmd.state ? HIGH : LOW);
            notify_ui();
        }

        vTaskDelay(pdMS_TO_TICKS(20));
    }
}

/* ================================================================
 * TASK: BUS (priority 2)
 * RS-485 polling and discovery
 * ================================================================ */
static void task_bus(void *arg) {
    uint32_t last_poll      = 0;
    uint32_t last_discovery = 0;

    for (;;) {
        uint32_t now = millis();

        /* Drain extension relay commands from web */
        relay_cmd_t cmd;
        while (xQueueReceive(ext_relay_queue, &cmd, 0) == pdTRUE) {
            if (cmd.target >= 0 && cmd.target < MAX_EXTENSIONS) {
                xSemaphoreTake(state_mutex, portMAX_DELAY);
                if (extensions[cmd.target].state == EXT_ONLINE) {
                    uint8_t addr = extensions[cmd.target].address;
                    bool r1 = extensions[cmd.target].relay1;
                    bool r2 = extensions[cmd.target].relay2;
                    if (cmd.channel == 1) r1 = cmd.state;
                    else                  r2 = cmd.state;
                    extensions[cmd.target].relay1 = r1;
                    extensions[cmd.target].relay2 = r2;
                    uint8_t mask = (r1?0x01:0)|(r2?0x02:0);
                    xSemaphoreGive(state_mutex);
                    uint8_t payload[1] = {mask};
                    bus_send(addr, CMD_SET_RELAY, payload, 1);
                    notify_ui();
                } else {
                    xSemaphoreGive(state_mutex);
                }
            }
        }

        /* Poll extensions */
        if ((now - last_poll) >= POLL_MS) {
            last_poll = now;
            for (int i = 0; i < MAX_EXTENSIONS; i++)
                poll_extension(i);
        }

        /* Discovery */
        if ((now - last_discovery) >= DISCOVERY_MS) {
            last_discovery = now;
            run_discovery();
        }

        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

/* ================================================================
 * BUILD STATE JSON
 * ================================================================ */
static String build_state_json(void) {
    xSemaphoreTake(state_mutex, portMAX_DELAY);
    StaticJsonDocument<2048> doc;
    doc["uptime"] = millis() / 1000;
    JsonObject master = doc.createNestedObject("master");
    master["relay1"] = master_relay1;
    master["relay2"] = master_relay2;
    JsonArray exts = doc.createNestedArray("extensions");
    for (int i = 0; i < MAX_EXTENSIONS; i++) {
        if (extensions[i].state == EXT_EMPTY) continue;
        JsonObject e = exts.createNestedObject();
        char uid_str[12];
        snprintf(uid_str, sizeof(uid_str), "%02X%02X%02X%02X",
                 extensions[i].uid[0], extensions[i].uid[1],
                 extensions[i].uid[2], extensions[i].uid[3]);
        e["id"]     = "ext" + String(i);
        e["name"]   = extensions[i].name;
        e["state"]  = (extensions[i].state == EXT_ONLINE) ? "online" : "offline";
        e["relay1"] = extensions[i].relay1;
        e["relay2"] = extensions[i].relay2;
        e["uid"]    = uid_str;
    }
    if (pending_ext) {
        char uid_str[12];
        snprintf(uid_str, sizeof(uid_str), "%02X%02X%02X%02X",
                 pending_uid[0],pending_uid[1],
                 pending_uid[2],pending_uid[3]);
        JsonObject p = doc.createNestedObject("pending");
        p["uid"] = uid_str;
    } else {
        doc["pending"] = nullptr;
    }
    xSemaphoreGive(state_mutex);
    String out; serializeJson(doc, out);
    return out;
}

/* ================================================================
 * TASK: WEB (priority 1)
 * HTTP REST + WebSocket push
 * ================================================================ */
static void ws_broadcast(void) {
    String json = build_state_json();
    wss.broadcastTXT(json);
}

static void task_web(void *arg) {
    for (;;) {
        server.handleClient();
        wss.loop();

        /* Push state to all WS clients when notified */
        uint8_t sig;
        if (xQueueReceive(ws_notify_queue, &sig, 0) == pdTRUE) {
            /* Drain extras */
            while (xQueueReceive(ws_notify_queue, &sig, 0) == pdTRUE);
            ws_broadcast();
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
<title>Smart Switch</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
     background:#0f0f1a;color:#eee;min-height:100vh;padding:16px}
h1{color:#00d4ff;font-size:22px;margin-bottom:4px}
.sub{color:#666;font-size:12px;margin-bottom:20px;
     display:flex;align-items:center;gap:8px}
.dot{width:8px;height:8px;border-radius:50%;
     background:#444;transition:background 0.3s}
.dot.on{background:#4eff4e}
.card{background:#1a1a2e;border-radius:14px;padding:18px;
      margin-bottom:16px;border:1px solid #2a2a4a;
      transition:opacity 0.3s}
.card.offline{opacity:0.4;pointer-events:none}
.card-header{display:flex;align-items:center;
             justify-content:space-between;margin-bottom:16px}
.card-title{font-size:16px;font-weight:600}
.badge{font-size:10px;padding:3px 10px;border-radius:20px;font-weight:700}
.badge.online{background:#0a2a0a;color:#4eff4e;border:1px solid #4eff4e}
.badge.offline{background:#2a0a0a;color:#ff4e4e;border:1px solid #ff4e4e}
.badge.master{background:#0a2a3a;color:#00d4ff;border:1px solid #00d4ff}
.channels{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.ch{background:#111128;border-radius:10px;padding:14px;text-align:center}
.ch-label{font-size:11px;color:#666;margin-bottom:10px}
.toggle{width:100%;padding:12px;border:none;border-radius:8px;
        font-size:14px;font-weight:700;cursor:pointer;transition:all 0.15s}
.toggle.on{background:#00d4ff;color:#000;
           box-shadow:0 0 12px rgba(0,212,255,0.3)}
.toggle.off{background:#1e1e38;color:#666;border:1px solid #2a2a4a}
.toggle:active{transform:scale(0.95)}
.empty{color:#444;font-size:13px;text-align:center;padding:30px;
       border:1px dashed #2a2a4a;border-radius:14px;margin-bottom:16px}
.overlay{display:none;position:fixed;inset:0;
         background:rgba(0,0,0,0.8);z-index:100;
         align-items:center;justify-content:center;padding:16px}
.overlay.show{display:flex}
.modal{background:#1a1a2e;border-radius:18px;padding:24px;
       width:100%;max-width:380px;border:1px solid #2a2a4a}
.modal h2{color:#00d4ff;font-size:18px;margin-bottom:6px}
.modal p{color:#888;font-size:13px;margin-bottom:16px;line-height:1.5}
.modal-uid{font-size:10px;color:#444;margin-bottom:16px;
           font-family:monospace;background:#111;
           padding:6px 10px;border-radius:6px}
.modal input{width:100%;padding:12px;background:#111128;
             border:1px solid #2a2a4a;border-radius:10px;
             color:#eee;font-size:15px;margin-bottom:16px;outline:none}
.modal input:focus{border-color:#00d4ff}
.btn-row{display:flex;gap:10px}
.btn{flex:1;padding:12px;border:none;border-radius:10px;
     font-size:14px;font-weight:700;cursor:pointer}
.btn.primary{background:#00d4ff;color:#000}
.btn.ghost{background:#2a2a4a;color:#aaa}
</style>
</head>
<body>
<h1>Smart Switch</h1>
<div class="sub">
  <div class="dot" id="dot"></div>
  <span id="sub">Connecting...</span>
</div>
<div id="root"></div>
<div class="overlay" id="overlay">
  <div class="modal">
    <h2>New Extension Found</h2>
    <p>Give it a name to add it to your system.</p>
    <div class="modal-uid" id="modal-uid"></div>
    <input id="ext-name" type="text" placeholder="e.g. Living Room" maxlength="23"/>
    <div class="btn-row">
      <button class="btn ghost" onclick="rejectExt()">Ignore</button>
      <button class="btn primary" onclick="assignExt()">Add</button>
    </div>
  </div>
</div>
<script>
let ws, pendingUid=null, reconnTimer=null;

function uptime(s){
  if(s<60)return s+'s';
  if(s<3600)return Math.floor(s/60)+'m '+s%60+'s';
  return Math.floor(s/3600)+'h '+Math.floor((s%3600)/60)+'m';
}

function card(id,name,badgeCls,badgeLabel,r1,r2,offline){
  return `<div class="card${offline?' offline':''}">
    <div class="card-header">
      <span class="card-title">${name}</span>
      <span class="badge ${badgeCls}">${badgeLabel}</span>
    </div>
    <div class="channels">
      <div class="ch"><div class="ch-label">Channel 1</div>
        <button class="toggle ${r1?'on':'off'}"
          onclick="toggle('${id}',1)">${r1?'ON':'OFF'}</button></div>
      <div class="ch"><div class="ch-label">Channel 2</div>
        <button class="toggle ${r2?'on':'off'}"
          onclick="toggle('${id}',2)">${r2?'ON':'OFF'}</button></div>
    </div></div>`;
}

function render(d){
  document.getElementById('sub').textContent=
    '192.168.4.1 | Uptime: '+uptime(d.uptime);
  let html=card('master','Master','master','MASTER',
    d.master.relay1,d.master.relay2,false);
  for(const e of d.extensions){
    const off=e.state==='offline';
    html+=card(e.id,e.name,off?'offline':'online',
      off?'OFFLINE':'ONLINE',e.relay1,e.relay2,off);
  }
  if(!d.extensions.length&&!d.pending)
    html+='<div class="empty">No extensions connected yet</div>';
  document.getElementById('root').innerHTML=html;
  if(d.pending&&!pendingUid){
    pendingUid=d.pending.uid;
    document.getElementById('modal-uid').textContent='ID: '+d.pending.uid;
    document.getElementById('ext-name').value='';
    document.getElementById('overlay').classList.add('show');
    setTimeout(()=>document.getElementById('ext-name').focus(),100);
  } else if(!d.pending){
    pendingUid=null;
    document.getElementById('overlay').classList.remove('show');
  }
}

function toggle(id,ch){
  fetch('/api/relay?id='+id+'&ch='+ch,{method:'POST'});
}

async function assignExt(){
  const name=document.getElementById('ext-name').value.trim();
  if(!name){document.getElementById('ext-name').focus();return;}
  await fetch('/api/assign?uid='+pendingUid+'&name='+encodeURIComponent(name),{method:'POST'});
  document.getElementById('overlay').classList.remove('show');
}

async function rejectExt(){
  await fetch('/api/reject?uid='+pendingUid,{method:'POST'});
  document.getElementById('overlay').classList.remove('show');
  pendingUid=null;
}

function connect(){
  if(reconnTimer){clearTimeout(reconnTimer);reconnTimer=null;}
  ws=new WebSocket('ws://192.168.4.1:81');
  ws.onopen=()=>{
    document.getElementById('dot').classList.add('on');
    document.getElementById('sub').textContent='Connected';
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
        server.send_P(200, "text/html", HTML);
    });

    server.on("/api/relay", HTTP_POST, [](){
        String id = server.arg("id");
        int    ch = server.arg("ch").toInt();

        if (id == "master" && (ch==1||ch==2)) {
            relay_cmd_t cmd;
            cmd.target  = -1;
            cmd.channel = ch;
            xSemaphoreTake(state_mutex, portMAX_DELAY);
            cmd.state = (ch==1) ? !master_relay1 : !master_relay2;
            xSemaphoreGive(state_mutex);
            xQueueSend(master_relay_queue, &cmd, 0);
            server.send(200, "application/json", "{\"ok\":true}");
            return;
        }
        if (id.startsWith("ext")) {
            int slot = id.substring(3).toInt();
            if (slot >= 0 && slot < MAX_EXTENSIONS) {
                relay_cmd_t cmd;
                cmd.target  = slot;
                cmd.channel = ch;
                xSemaphoreTake(state_mutex, portMAX_DELAY);
                cmd.state = (ch==1) ? !extensions[slot].relay1
                                    : !extensions[slot].relay2;
                xSemaphoreGive(state_mutex);
                xQueueSend(ext_relay_queue, &cmd, 0);
                server.send(200, "application/json", "{\"ok\":true}");
                return;
            }
        }
        server.send(404, "application/json", "{\"ok\":false}");
    });

    server.on("/api/assign", HTTP_POST, [](){
        String name = server.arg("name");
        if (name.length() == 0) name = "Switch";
        xSemaphoreTake(state_mutex, portMAX_DELAY);
        if (!pending_ext) {
            xSemaphoreGive(state_mutex);
            server.send(400, "application/json", "{\"ok\":false}");
            return;
        }
        int slot = find_empty_slot();
        if (slot < 0) {
            xSemaphoreGive(state_mutex);
            server.send(400, "application/json", "{\"error\":\"no slots\"}");
            return;
        }
        extension_t *e = &extensions[slot];
        memcpy(e->uid, pending_uid, 4);
        e->address = pending_addr;
        e->state   = EXT_ONLINE;
        e->missed  = 0;
        e->relay1  = false;
        e->relay2  = false;
        e->last_seen_ms = millis();
        strncpy(e->name, name.c_str(), sizeof(e->name)-1);
        e->name[sizeof(e->name)-1] = '\0';
        uint8_t uid_copy[4]; memcpy(uid_copy, pending_uid, 4);
        char name_copy[24]; strncpy(name_copy, e->name, sizeof(name_copy));
        pending_ext = false;
        memset(pending_uid, 0, 4);
        pending_addr = 0;
        xSemaphoreGive(state_mutex);
        nvs_save(uid_copy, slot, name_copy);
        Serial.printf("[ASSIGN] %s -> slot%d\n", name_copy, slot+1);
        notify_ui();
        server.send(200, "application/json", "{\"ok\":true}");
    });

    server.on("/api/reject", HTTP_POST, [](){
        xSemaphoreTake(state_mutex, portMAX_DELAY);
        pending_ext = false;
        memset(pending_uid, 0, 4);
        pending_addr = 0;
        xSemaphoreGive(state_mutex);
        server.send(200, "application/json", "{\"ok\":true}");
    });

    /* WebSocket event handler */
    wss.onEvent([](uint8_t num, WStype_t type,
                   uint8_t *payload, size_t length){
        if (type == WStype_CONNECTED) {
            Serial.printf("[WS] Client #%u connected\n", num);
            /* Send current state immediately */
            String json = build_state_json();
            wss.sendTXT(num, json);
        } else if (type == WStype_DISCONNECTED) {
            Serial.printf("[WS] Client #%u disconnected\n", num);
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
    Serial.println("\n[MASTER] Smart Switch v4.0 - booting");

    pinMode(RELAY1_PIN,   OUTPUT); digitalWrite(RELAY1_PIN,   LOW);
    pinMode(RELAY2_PIN,   OUTPUT); digitalWrite(RELAY2_PIN,   LOW);
    pinMode(RS485_DE_PIN, OUTPUT); digitalWrite(RS485_DE_PIN, LOW);
    pinMode(TOUCH1_PIN,   INPUT);
    pinMode(TOUCH2_PIN,   INPUT);

    BusSerial.begin(UART_BAUD, SERIAL_8N1, BUS_RX_PIN, BUS_TX_PIN);

    prefs.begin("ext_map", false); prefs.end();

    for (int i = 0; i < MAX_EXTENSIONS; i++) {
        extensions[i].state   = EXT_EMPTY;
        extensions[i].address = ADDR_UNASSIGNED;
        extensions[i].missed  = 0;
        extensions[i].relay1  = false;
        extensions[i].relay2  = false;
        memset(extensions[i].uid, 0, 4);
        snprintf(extensions[i].name, sizeof(extensions[i].name),
                 "Slot-%d", i+1);
    }

    nvs_restore_all();

    state_mutex        = xSemaphoreCreateMutex();
    master_relay_queue = xQueueCreate(16, sizeof(relay_cmd_t));
    ext_relay_queue    = xQueueCreate(16, sizeof(relay_cmd_t));
    ws_notify_queue    = xQueueCreate(8,  sizeof(uint8_t));

    WiFi.mode(WIFI_AP);
    WiFi.softAPConfig(AP_IP, AP_GW, AP_SUBNET);
    WiFi.softAP(AP_SSID, AP_PASS);
    Serial.printf("[WIFI] AP: %s  IP: %s\n",
                  AP_SSID, AP_IP.toString().c_str());

    setup_web();

    /* touch(3) > bus(2) > web(1)
     * No async_tcp, no watchdog issues  */
    xTaskCreate(task_touch, "touch", 2048, NULL, 3, NULL);
    xTaskCreate(task_bus,   "bus",   4096, NULL, 2, NULL);
    xTaskCreate(task_web,   "web",   8192, NULL, 1, NULL);

    Serial.println("[MASTER] Ready - connect to SmartSwitch -> 192.168.4.1");
}

void loop() {
    vTaskDelay(pdMS_TO_TICKS(1000));
}
