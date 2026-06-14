#include "Preferences.h"

Preferences prefs;

void setup() {
    Serial.begin(115200);
    delay(500);
    Serial.println("Wiping all NVS data...");

    /* Wipe extension slot mappings */
    prefs.begin("ext_map", false);
    prefs.clear();
    prefs.end();

    /* Wipe relay states */
    prefs.begin("relay_state", false);
    prefs.clear();
    prefs.end();

    Serial.println("Done. Flash real firmware now.");
}

void loop() {}