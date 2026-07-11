#include "Arduino.h"
#include "WiFi.h"
#include "esp_now.h"
#include "esp_mac.h"

void on_recv(const esp_now_recv_info_t *info,
             const uint8_t *data, int len) {
    Serial.printf("[RX] From %02X:%02X:%02X:%02X:%02X:%02X | %s\n",
        info->src_addr[0],info->src_addr[1],info->src_addr[2],
        info->src_addr[3],info->src_addr[4],info->src_addr[5],
        (char*)data);
}

void setup() {
    Serial.begin(115200);
    delay(1000);
    Serial.println("\n=== ESP-NOW RECEIVER ===");

    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    Serial.printf("[MY MAC] %02X:%02X:%02X:%02X:%02X:%02X\n",
        mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]);
    Serial.println("[INFO] Copy MY MAC into sender RECEIVER_MAC[]");

    WiFi.mode(WIFI_AP_STA);
    WiFi.softAP("ESPNOW-RECEIVER", "12345678", 1);
    delay(200);
    Serial.printf("[WIFI] Channel: %d\n", WiFi.channel());

    if (esp_now_init() != ESP_OK) {
        Serial.println("[ERROR] ESP-NOW init FAILED");
        while(1) delay(1000);
    }
    Serial.println("[OK] ESP-NOW init");
    esp_now_register_recv_cb(on_recv);
    Serial.println("[WAITING] Ready to receive...\n");
}

void loop() { delay(100); }
