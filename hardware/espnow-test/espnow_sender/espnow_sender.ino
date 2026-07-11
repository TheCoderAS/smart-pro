#include "Arduino.h"
#include "WiFi.h"
#include "esp_now.h"
#include "esp_mac.h"

/* CHANGE THIS to Master 1 MAC (shown in receiver serial monitor) */
uint8_t RECEIVER_MAC[6] = {0x58, 0xE6, 0xC5, 0xF7, 0x62, 0xB8};

void on_sent(const wifi_tx_info_t *info, esp_now_send_status_t status) {
    Serial.printf("[CB] %s\n",
        status == ESP_NOW_SEND_SUCCESS ? "DELIVERED" : "NOT DELIVERED");
}

void setup() {
    Serial.begin(115200);
    delay(1000);
    Serial.println("\n=== ESP-NOW SENDER ===");

    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    Serial.printf("[MY MAC] %02X:%02X:%02X:%02X:%02X:%02X\n",
        mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]);

    WiFi.mode(WIFI_AP_STA);
    WiFi.softAP("ESPNOW-SENDER", "12345678", 1);
    delay(200);
    Serial.printf("[WIFI] Channel: %d\n", WiFi.channel());

    if (esp_now_init() != ESP_OK) {
        Serial.println("[ERROR] ESP-NOW init FAILED");
        while(1) delay(1000);
    }
    Serial.println("[OK] ESP-NOW init");
    esp_now_register_send_cb(on_sent);

    esp_now_peer_info_t peer = {};
    memcpy(peer.peer_addr, RECEIVER_MAC, 6);
    peer.channel = 1;
    peer.encrypt = false;
    if (esp_now_add_peer(&peer) != ESP_OK) {
        Serial.println("[ERROR] Add peer FAILED");
        while(1) delay(1000);
    }
    Serial.printf("[OK] Peer: %02X:%02X:%02X:%02X:%02X:%02X ch1\n",
        RECEIVER_MAC[0],RECEIVER_MAC[1],RECEIVER_MAC[2],
        RECEIVER_MAC[3],RECEIVER_MAC[4],RECEIVER_MAC[5]);
    Serial.println("[SENDING] every 2s...\n");
}

int n = 0;
void loop() {
    char msg[32];
    snprintf(msg, sizeof(msg), "PING_%d", n++);
    Serial.printf("[TX] %s -> send()=", msg);
    esp_err_t r = esp_now_send(RECEIVER_MAC, (uint8_t*)msg, strlen(msg)+1);
    Serial.println(r == ESP_OK ? "OK" : String(r));
    delay(2000);
}
