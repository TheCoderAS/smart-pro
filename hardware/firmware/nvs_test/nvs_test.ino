/*
 * Relay + LED State Restore Test -- STM32G030F6P6
 * Touch PA3 toggles RELAY1+LED1
 * Touch PA4 toggles RELAY2+LED2
 * Both states persist across power cycles.
 *
 * PA3 = TOUCH1  (input)
 * PA4 = TOUCH2  (input)
 * PA1 = RELAY1  (active LOW -- LOW=ON, HIGH=OFF)
 * PA2 = RELAY2  (active LOW -- LOW=ON, HIGH=OFF)
 * PA5 = LED1    (active HIGH -- HIGH=ON, LOW=OFF)
 * PA6 = LED2    (active HIGH -- HIGH=ON, LOW=OFF)
 */

#include "Arduino.h"
#include <stm32g0xx_ll_gpio.h>
#include <stm32g0xx_ll_bus.h>

#define PIN_T1     3
#define PIN_T2     4
#define PIN_RELAY1 1
#define PIN_RELAY2 2
#define PIN_LED1   5
#define PIN_LED2   6
#define PIN_SET(p) (GPIOA->BSRR = (1u<<(p)))
#define PIN_CLR(p) (GPIOA->BRR  = (1u<<(p)))
#define PIN_READ(p)((GPIOA->IDR  >>(p))&1u)

#define NVS_PAGE_ADDR  0x08007800UL
#define NVS_MAGIC_VAL  0xA5

static uint8_t shadow[8];

static void nvs_load(void) {
    volatile uint8_t *p = (volatile uint8_t *)NVS_PAGE_ADDR;
    for (int i = 0; i < 8; i++) shadow[i] = p[i];
}

static void nvs_flush(void) {
    if (READ_BIT(FLASH->CR, FLASH_CR_LOCK)) {
        WRITE_REG(FLASH->KEYR, 0x45670123UL);
        WRITE_REG(FLASH->KEYR, 0xCDEF89ABUL);
    }
    WRITE_REG(FLASH->SR, 0xFFFFFFFF);
    MODIFY_REG(FLASH->CR, FLASH_CR_PNB, (15u << FLASH_CR_PNB_Pos));
    SET_BIT(FLASH->CR, FLASH_CR_PER);
    SET_BIT(FLASH->CR, FLASH_CR_STRT);
    uint32_t t = millis();
    while (READ_BIT(FLASH->SR, FLASH_SR_BSY1) && (millis()-t) < 500);
    CLEAR_BIT(FLASH->CR, FLASH_CR_PER);
    WRITE_REG(FLASH->SR, FLASH_SR_EOP);
    SET_BIT(FLASH->CR, FLASH_CR_PG);
    volatile uint32_t *dst = (volatile uint32_t *)NVS_PAGE_ADDR;
    uint32_t w0, w1;
    memcpy(&w0, &shadow[0], 4);
    memcpy(&w1, &shadow[4], 4);
    dst[0] = w0; __ISB(); dst[1] = w1;
    t = millis();
    while (READ_BIT(FLASH->SR, FLASH_SR_BSY1) && (millis()-t) < 500);
    CLEAR_BIT(FLASH->CR, FLASH_CR_PG);
    WRITE_REG(FLASH->SR, FLASH_SR_EOP);
    SET_BIT(FLASH->CR, FLASH_CR_LOCK);
}

static bool r1 = false;
static bool r2 = false;

static void set_relay1(bool s) {
    r1 = s;
    if (s) { PIN_CLR(PIN_RELAY1); PIN_SET(PIN_LED1); }  /* ON */
    else   { PIN_SET(PIN_RELAY1); PIN_CLR(PIN_LED1); }  /* OFF */
}

static void set_relay2(bool s) {
    r2 = s;
    if (s) { PIN_CLR(PIN_RELAY2); PIN_SET(PIN_LED2); }  /* ON */
    else   { PIN_SET(PIN_RELAY2); PIN_CLR(PIN_LED2); }  /* OFF */
}

static void save(void) {
    shadow[0] = NVS_MAGIC_VAL;
    shadow[1] = (r1 ? 0x01 : 0x00) | (r2 ? 0x02 : 0x00);
    nvs_flush();
}

void setup() {
    LL_IOP_GRP1_EnableClock(LL_IOP_GRP1_PERIPH_GPIOA);

    /* Set relay pins HIGH before output mode (active LOW = OFF) */
    GPIOA->BSRR = LL_GPIO_PIN_1 | LL_GPIO_PIN_2;

    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_1, LL_GPIO_MODE_OUTPUT);
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_2, LL_GPIO_MODE_OUTPUT);
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_5, LL_GPIO_MODE_OUTPUT);
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_6, LL_GPIO_MODE_OUTPUT);
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_3, LL_GPIO_MODE_INPUT);
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_4, LL_GPIO_MODE_INPUT);
    LL_GPIO_SetPinPull(GPIOA, LL_GPIO_PIN_3, LL_GPIO_PULL_NO);
    LL_GPIO_SetPinPull(GPIOA, LL_GPIO_PIN_4, LL_GPIO_PULL_NO);
    PIN_CLR(PIN_LED1);
    PIN_CLR(PIN_LED2);

    nvs_load();
    if (shadow[0] == NVS_MAGIC_VAL) {
        set_relay1((shadow[1] & 0x01) != 0);
        set_relay2((shadow[1] & 0x02) != 0);
    }
}

void loop() {
    static bool last1 = false;
    static bool last2 = false;
    bool t1 = PIN_READ(PIN_T1);
    bool t2 = PIN_READ(PIN_T2);
    if (t1 && !last1) { set_relay1(!r1); save(); }
    if (t2 && !last2) { set_relay2(!r2); save(); }
    last1 = t1;
    last2 = t2;
}
