/*
 * Smart Modular Switch System
 * Master Firmware — ESP32-C6
 * WiFi web server for demo control
 */

#include "Arduino.h"
#include "HardwareSerial.h"
#include "WiFi.h"
#include "WebServer.h"

/* ─── WiFi ───────────────────────────────────────────────────── */
const char *WIFI_SSID = "No available networks";
const char *WIFI_PASS = "Tap 2 connect";

/* ─── Static IP ──────────────────────────────────────────────── */
IPAddress local_IP(10, 231, 74, 200);
IPAddress gateway(10, 231, 74, 166);
IPAddress subnet(255, 255, 255, 0);
IPAddress dns(10, 231, 74, 166);

/* ─── Web server ─────────────────────────────────────────────── */
WebServer server(80);

/* ─── Bus config ─────────────────────────────────────────────── */
#define UART_BAUD          250000
#define MAX_EXTENSIONS     2
#define POLL_INTERVAL_MS   50
#define MISSED_POLL_MAX    3
#define ONLINE_CONFIRM_MS  60000
#define ENUM_TIMEOUT_MS    200

/* ─── Frame constants ────────────────────────────────────────── */
#define SOF              0xAA
#define ADDR_MASTER      0x00
#define ADDR_UNASSIGNED  0xFE
#define ADDR_BCAST       0xFF

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

/* ─── Extension record ───────────────────────────────────────── */
typedef struct {
    uint8_t  address;
    uint8_t  uid[4];
    char     name[24];
    bool     online;
    bool     ever_seen;
    bool     enumerated;
    uint8_t  relay1;
    uint8_t  relay2;
    uint8_t  missed_polls;
    uint32_t last_seen_ms;
    uint32_t online_since_ms;
} extension_t;

static extension_t extensions[MAX_EXTENSIONS];
static uint8_t     master_relay1 = 0;
static uint8_t     master_relay2 = 0;

HardwareSerial ExtSerial1(1);
HardwareSerial ExtSerial2(2);
HardwareSerial *ext_serial[MAX_EXTENSIONS] = {&ExtSerial1, &ExtSerial2};

/* ═══════════════════════════════════════════════════════════════
 * CRC-8
 * ═══════════════════════════════════════════════════════════════ */
static uint8_t crc8(const uint8_t *data, uint8_t len) {
    uint8_t crc = 0x00;
    while (len--) {
        crc ^= *data++;
        for (int i = 0; i < 8; i++)
            crc = (crc & 0x80) ? (crc << 1) ^ 0x07 : crc << 1;
    }
    return crc;
}

/* ═══════════════════════════════════════════════════════════════
 * Send frame
 * ═══════════════════════════════════════════════════════════════ */
static void send_frame(uint8_t idx, uint8_t dst, uint8_t cmd,
                       const uint8_t *payload, uint8_t len) {
    uint8_t frame[38];
    frame[0] = SOF;
    frame[1] = dst;
    frame[2] = ADDR_MASTER;
    frame[3] = cmd;
    frame[4] = len;
    for (int i = 0; i < len; i++) frame[5 + i] = payload[i];
    frame[5 + len] = crc8(&frame[1], 4 + len);
    ext_serial[idx]->write(frame, 6 + len);
}

/* ═══════════════════════════════════════════════════════════════
 * Read response with timeout
 * ═══════════════════════════════════════════════════════════════ */
static uint8_t read_response(uint8_t idx, uint8_t *buf,
                              uint8_t max_len, uint32_t timeout_ms) {
    uint32_t start        = millis();
    uint8_t  pos          = 0;
    uint8_t  expected_len = 0;

    while ((millis() - start) < timeout_ms) {
        if (ext_serial[idx]->available()) {
            uint8_t b = ext_serial[idx]->read();
            if (pos == 0) {
                if (b == SOF) buf[pos++] = b;
            } else {
                buf[pos++] = b;
                if (pos == 5) expected_len = 6 + buf[4];
                if (expected_len > 0 && pos >= expected_len) return pos;
                if (pos >= max_len) return 0;
            }
        }
    }
    return 0;
}

/* ═══════════════════════════════════════════════════════════════
 * Set relay on extension
 * ═══════════════════════════════════════════════════════════════ */
static void set_extension_relay(uint8_t idx, uint8_t ch, uint8_t state) {
    if (!extensions[idx].online) return;
    uint8_t mask = (extensions[idx].relay1 & 0x01)
                 | ((extensions[idx].relay2 & 0x01) << 1);
    if (ch == 1) {
        if (state) mask |=  0x01;
        else       mask &= ~0x01;
    } else {
        if (state) mask |=  0x02;
        else       mask &= ~0x02;
    }
    send_frame(idx, extensions[idx].address, CMD_SET_RELAY, &mask, 1);
    if (ch == 1) extensions[idx].relay1 = state;
    else         extensions[idx].relay2 = state;
}

/* ═══════════════════════════════════════════════════════════════
 * Enumeration
 * ═══════════════════════════════════════════════════════════════ */
static void enumerate_extension(uint8_t idx) {
    uint8_t resp[40];
    uint8_t resp_len;
    uint8_t set_addr_payload[5];
    uint8_t *uid;
    uint8_t new_addr;

    send_frame(idx, ADDR_BCAST, CMD_ENUM_REQ, NULL, 0);
    resp_len = read_response(idx, resp, sizeof(resp), ENUM_TIMEOUT_MS);
    if (resp_len == 0) return;

    uint8_t plen = resp[4];
    if (resp[3] != CMD_ENUM_RESP || plen < 4) return;
    if (resp[5 + plen] != crc8(&resp[1], 4 + plen)) return;

    uid      = &resp[5];
    new_addr = idx + 1;

    set_addr_payload[0] = uid[0];
    set_addr_payload[1] = uid[1];
    set_addr_payload[2] = uid[2];
    set_addr_payload[3] = uid[3];
    set_addr_payload[4] = new_addr;
    send_frame(idx, ADDR_UNASSIGNED, CMD_SET_ADDR, set_addr_payload, 5);

    resp_len = read_response(idx, resp, sizeof(resp), 500);
    if (resp_len == 0 || resp[3] != CMD_PONG) return;

    bool is_new = !extensions[idx].ever_seen ||
                  memcmp(extensions[idx].uid, uid, 4) != 0;

    extensions[idx].address      = new_addr;
    extensions[idx].uid[0]       = uid[0];
    extensions[idx].uid[1]       = uid[1];
    extensions[idx].uid[2]       = uid[2];
    extensions[idx].uid[3]       = uid[3];
    extensions[idx].enumerated   = true;
    extensions[idx].ever_seen    = true;
    extensions[idx].online       = true;
    extensions[idx].missed_polls = 0;
    extensions[idx].last_seen_ms = millis();

    if (is_new)
        snprintf(extensions[idx].name, sizeof(extensions[idx].name),
                 "Switch-%d", idx + 1);
}

/* ═══════════════════════════════════════════════════════════════
 * Online / offline
 * ═══════════════════════════════════════════════════════════════ */
static void mark_online(uint8_t idx) {
    extension_t *e = &extensions[idx];
    if (!e->online) {
        if (e->online_since_ms == 0) e->online_since_ms = millis();
        if ((millis() - e->online_since_ms) >= ONLINE_CONFIRM_MS
            || !e->ever_seen) {
            e->online       = true;
            e->ever_seen    = true;
            e->missed_polls = 0;
        }
    } else {
        e->online_since_ms = 0;
        e->missed_polls    = 0;
    }
    e->last_seen_ms = millis();
}

static void mark_offline(uint8_t idx) {
    extension_t *e = &extensions[idx];
    if (e->online) {
        e->online          = false;
        e->online_since_ms = 0;
        e->enumerated      = false;
    }
}

/* ═══════════════════════════════════════════════════════════════
 * Process STATE_RESP
 * ═══════════════════════════════════════════════════════════════ */
static void process_state_resp(uint8_t idx, const uint8_t *frame) {
    if (frame[4] < 3) return;
    const uint8_t *p    = &frame[5];
    uint8_t event_count = p[2];

    extensions[idx].relay1 = (p[0] >> 0) & 0x01;
    extensions[idx].relay2 = (p[0] >> 1) & 0x01;

    if (event_count > 0) {
        uint8_t drain[1] = {event_count};
        send_frame(idx, extensions[idx].address, CMD_DRAIN_EVENTS, drain, 1);
    }
}

/* ═══════════════════════════════════════════════════════════════
 * Poll one extension
 * ═══════════════════════════════════════════════════════════════ */
static void poll_extension(uint8_t idx) {
    uint8_t resp[40];
    uint8_t resp_len;
    uint8_t plen;

    if (!extensions[idx].enumerated) {
        enumerate_extension(idx);
        return;
    }

    send_frame(idx, extensions[idx].address, CMD_GET_STATE, NULL, 0);
    resp_len = read_response(idx, resp, sizeof(resp), 5);

    if (resp_len == 0) {
        if (++extensions[idx].missed_polls >= MISSED_POLL_MAX)
            mark_offline(idx);
        return;
    }

    plen = resp[4];
    if (resp[5 + plen] != crc8(&resp[1], 4 + plen)) return;

    if (resp[2] == ADDR_UNASSIGNED) {
        enumerate_extension(idx);
        return;
    }

    mark_online(idx);
    if (resp[3] == CMD_STATE_RESP) process_state_resp(idx, resp);
}

/* ═══════════════════════════════════════════════════════════════
 * Web UI
 * ═══════════════════════════════════════════════════════════════ */
static void handle_root() {
    String html = R"(<!DOCTYPE html>
<html>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>Smart Switch</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, sans-serif; background: #0f0f0f; color: #fff; min-height: 100vh; padding: 20px; }
  h1 { font-size: 22px; font-weight: 700; margin-bottom: 4px; }
  .sub { font-size: 12px; color: #555; margin-bottom: 28px; }
  .card { background: #1a1a1a; border-radius: 14px; padding: 18px; margin-bottom: 14px; border: 1px solid #252525; }
  .card-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 6px; }
  .card-title { font-size: 16px; font-weight: 600; }
  .badge { font-size: 10px; padding: 3px 10px; border-radius: 20px; font-weight: 700; letter-spacing: 0.5px; }
  .online  { background: #0d3320; color: #30d158; border: 1px solid #1a5c36; }
  .offline { background: #2a1212; color: #ff453a; border: 1px solid #4a1a1a; }
  .uid { font-size: 10px; color: #333; margin-bottom: 14px; font-family: monospace; }
  .channels { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
  .ch { background: #111; border-radius: 10px; padding: 14px 10px; text-align: center; }
  .ch-label { font-size: 11px; color: #555; margin-bottom: 10px; text-transform: uppercase; letter-spacing: 0.5px; }
  .btn { width: 100%; padding: 12px; border: none; border-radius: 8px; font-size: 13px; font-weight: 700; cursor: pointer; transition: transform 0.1s; }
  .btn:active { transform: scale(0.96); }
  .btn-on  { background: #30d158; color: #000; }
  .btn-off { background: #1e1e1e; color: #555; border: 1px solid #2a2a2a; }
  .btn-dis { background: #111; color: #333; border: 1px solid #1a1a1a; cursor: default; }
  .footer  { text-align: center; font-size: 11px; color: #2a2a2a; margin-top: 28px; }
</style>
</head>
<body>
<h1>Smart Switch</h1>
<p class='sub'>Demo &nbsp;·&nbsp; )";

    html += WiFi.localIP().toString();
    html += "</p>";

    for (int i = 0; i < MAX_EXTENSIONS; i++) {
        html += "<div class='card'>";
        html += "<div class='card-header'>";
        html += "<span class='card-title'>" + String(extensions[i].name) + "</span>";
        html += extensions[i].online
                ? "<span class='badge online'>ONLINE</span>"
                : "<span class='badge offline'>OFFLINE</span>";
        html += "</div>";

        char uid_str[20];
        snprintf(uid_str, sizeof(uid_str), "UID: %02X%02X%02X%02X",
                 extensions[i].uid[0], extensions[i].uid[1],
                 extensions[i].uid[2], extensions[i].uid[3]);
        html += "<div class='uid'>" + String(uid_str) + "</div>";
        html += "<div class='channels'>";

        /* CH1 */
        html += "<div class='ch'><div class='ch-label'>Channel 1</div>";
        if (extensions[i].online) {
            if (extensions[i].relay1)
                html += "<button class='btn btn-on' onclick=\"toggle(" + String(i) + ",1,0)\">ON</button>";
            else
                html += "<button class='btn btn-off' onclick=\"toggle(" + String(i) + ",1,1)\">OFF</button>";
        } else {
            html += "<button class='btn btn-dis' disabled>—</button>";
        }
        html += "</div>";

        /* CH2 */
        html += "<div class='ch'><div class='ch-label'>Channel 2</div>";
        if (extensions[i].online) {
            if (extensions[i].relay2)
                html += "<button class='btn btn-on' onclick=\"toggle(" + String(i) + ",2,0)\">ON</button>";
            else
                html += "<button class='btn btn-off' onclick=\"toggle(" + String(i) + ",2,1)\">OFF</button>";
        } else {
            html += "<button class='btn btn-dis' disabled>—</button>";
        }
        html += "</div>";

        html += "</div></div>";
    }

    html += R"(
<div class='footer'>Auto-refresh every 3s</div>
<script>
function toggle(ext, ch, state) {
    fetch('/relay?ext=' + ext + '&ch=' + ch + '&state=' + state)
        .then(() => setTimeout(() => location.reload(), 400));
}
setTimeout(() => location.reload(), 3000);
</script>
</body></html>)";

    server.send(200, "text/html", html);
}

static void handle_relay() {
    if (!server.hasArg("ext") || !server.hasArg("ch") || !server.hasArg("state")) {
        server.send(400, "text/plain", "bad request");
        return;
    }
    int ext   = server.arg("ext").toInt();
    int ch    = server.arg("ch").toInt();
    int state = server.arg("state").toInt();
    if (ext >= 0 && ext < MAX_EXTENSIONS && (ch == 1 || ch == 2))
        set_extension_relay(ext, ch, state);
    server.send(200, "text/plain", "ok");
}

static void handle_status() {
    String json = "{\"extensions\":[";
    for (int i = 0; i < MAX_EXTENSIONS; i++) {
        if (i > 0) json += ",";
        char uid[12];
        snprintf(uid, sizeof(uid), "%02X%02X%02X%02X",
                 extensions[i].uid[0], extensions[i].uid[1],
                 extensions[i].uid[2], extensions[i].uid[3]);
        json += "{\"name\":\"" + String(extensions[i].name) + "\","
              + "\"online\":"  + (extensions[i].online ? "true" : "false") + ","
              + "\"relay1\":"  + String(extensions[i].relay1) + ","
              + "\"relay2\":"  + String(extensions[i].relay2) + ","
              + "\"uid\":\""   + String(uid) + "\"}";
    }
    json += "]}";
    server.send(200, "application/json", json);
}

/* ═══════════════════════════════════════════════════════════════
 * Setup
 * ═══════════════════════════════════════════════════════════════ */
void setup() {
    Serial.begin(115200);
    delay(3000);

    ExtSerial1.begin(UART_BAUD, SERIAL_8N1, 4,  5);
    ExtSerial2.begin(UART_BAUD, SERIAL_8N1, 17, 18);

    for (int i = 0; i < MAX_EXTENSIONS; i++) {
        extensions[i].address         = i + 1;
        extensions[i].online          = false;
        extensions[i].ever_seen       = false;
        extensions[i].enumerated      = false;
        extensions[i].relay1          = 0;
        extensions[i].relay2          = 0;
        extensions[i].missed_polls    = 0;
        extensions[i].last_seen_ms    = 0;
        extensions[i].online_since_ms = 0;
        memset(extensions[i].uid, 0, 4);
        snprintf(extensions[i].name, sizeof(extensions[i].name),
                 "Switch-%d", i + 1);
    }

    /* Static IP then connect */
    WiFi.config(local_IP, gateway, subnet, dns);
    WiFi.begin(WIFI_SSID, WIFI_PASS);

    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 20) {
        delay(500);
        attempts++;
    }

    server.on("/",       handle_root);
    server.on("/relay",  handle_relay);
    server.on("/status", handle_status);
    server.begin();
}

/* ═══════════════════════════════════════════════════════════════
 * Loop
 * ═══════════════════════════════════════════════════════════════ */
void loop() {
    static uint32_t last_poll_ms = 0;

    server.handleClient();

    if ((millis() - last_poll_ms) >= POLL_INTERVAL_MS) {
        last_poll_ms = millis();
        for (int i = 0; i < MAX_EXTENSIONS; i++) poll_extension(i);
    }
}