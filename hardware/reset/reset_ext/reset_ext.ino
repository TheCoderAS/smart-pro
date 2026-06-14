void setup() {
    /* Unlock EEPROM */
    FLASH->DUKR = 0xAE;
    FLASH->DUKR = 0x56;
    while (!(FLASH->IAPSR & 0x08));

    /* Write known pattern */
    *((volatile uint8_t *)0x4000) = 0x00;
    *((volatile uint8_t *)0x4001) = 0x00;
    *((volatile uint8_t *)0x4002) = 0x00;
    while (!(FLASH->IAPSR & 0x04));
    FLASH->IAPSR &= ~0x08;

    /* Read back and verify */
    uint8_t v0 = *((volatile uint8_t *)0x4000);
    uint8_t v1 = *((volatile uint8_t *)0x4001);
    uint8_t v2 = *((volatile uint8_t *)0x4002);

    pinMode(PB5, OUTPUT);

    if (v0 == 0x00 && v1 == 0x00 && v2 == 0x00) {
        /* Success - 3 slow blinks */
        for (int i = 0; i < 3; i++) {
            GPIO_WriteHigh(GPIOB, GPIO_PIN_5);
            delay(500);
            GPIO_WriteLow(GPIOB, GPIO_PIN_5);
            delay(500);
        }
    } else {
        /* Failed - rapid blinks forever */
        while(1) {
            GPIO_WriteHigh(GPIOB, GPIO_PIN_5);
            delay(100);
            GPIO_WriteLow(GPIOB, GPIO_PIN_5);
            delay(100);
        }
    }
}

void loop() {}
