/*
 * Unisync Extension Bootloader v4.0  -- FROZEN INTERFACE
 * STM32G030F6P6
 *
 * THIS IMAGE CAN NEVER BE UPDATED IN THE FIELD. The NVS layout and the
 * staging-metadata format below are a permanent contract with every
 * extension firmware that will ever run on this hardware.
 *
 * Flash map
 *   0x08000000 - 0x08001000   bootloader (4 KB, 2 pages)
 *   0x08001000 - 0x08004000   Slot A -- the running application (12 KB)
 *   0x08004000 - 0x08007000   Slot B -- OTA staging only (12 KB)
 *   0x08007000 - 0x08008000   NVS (4 KB, first 64 bytes used)
 *
 * Sized in whole 2 KB erase pages: 2 + 6 + 6 + 2 = 16 pages = 32 KB.
 * NVS was 8 KB for 64 bytes of data; that waste now buys 2 KB of slot.
 *
 * NVS v2 (32 bytes, 4 doublewords)
 *   0      magic            0xA5 registered / 0x5A standalone
 *   1      bus address
 *   2      relay state
 *   3-6    master UID
 *   7      OTA pending      0xAA = a staged image is waiting
 *   8      hw_type          written at manufacture. 0xFF = unprovisioned
 *   9      hw_revision
 *   10     boot counter
 *   11     security version (rollback floor)
 *   12-15  reserved
 *   16     meta magic       0x5A when metadata is valid
 *   17     staged image target type
 *   18-20  staged image version (major, minor, patch)
 *   22-23  staged image size, little endian
 *   24-27  staged image CRC32, little endian
 *   21     staged image security version
 *   28-31  reserved
 *   32-47  fw_key   -- firmware verification key
 *   48-63  dev_key  -- per-device bus key
 *
 * An update is applied only if ALL of these hold:
 *   - pending flag is 0xAA
 *   - metadata magic is 0x5A
 *   - this unit is provisioned (hw_type != 0xFF)
 *   - staged image type == this unit's hw_type
 *   - 0 < size <= 12 KB
 *   - CRC32 over Slot B matches the recorded CRC
 * Any failure leaves Slot A untouched and boots the existing application.
 *
 * Power-fail behaviour: the pending flag is cleared only AFTER the copy
 * completes, and Slot B is never written during it, so a supply cut mid-copy
 * simply repeats the copy on the next boot. Do not reorder main().
 *
 * LED3 (PA7)
 *   1 long blink    normal boot
 *   3 short blinks  valid image staged, copying
 *   5 short blinks  staged image rejected, booting existing application
 *   rapid forever   no bootable application
 *
 * Build: Generic G030F6Px, U(S)ART support DISABLED, flash offset 0x0,
 *        -Os with LTO. Flash to 0x08000000 over SWD.
 */
#include "stm32g0xx.h"

#define SLOT_A           0x08001000UL
#define SLOT_B           0x08004000UL
#define SLOT_SIZE        (12UL * 1024UL)
#define PAGE_SIZE        2048UL
#define NVS_BASE         0x08007000UL
#define NVS_SIZE         64

#define NVS_OTA_FLAG     7
#define NVS_HW_TYPE      8
#define NVS_FW_KEY       32
#define NVS_META_MAGIC   16
#define NVS_META_TYPE    17
#define NVS_META_SIZE    22
#define NVS_META_CRC     24
#define NVS_META_SEC     21   /* security version of the staged image */
#define NVS_SEC_VER      11   /* rollback floor stored on the device */

#define UPDATE_PENDING   0xAA
#define META_MAGIC_VAL   0x5A
#define HW_UNPROVISIONED 0xFF

#define DLY(n) do { for (volatile int _i = 0; _i < (n); _i++); } while (0)

typedef void (*fn_t)(void);

/* ------------------------------------------------------------------ LED */
static void led_init(void) {
    RCC->IOPENR |= 1u;
    GPIOA->MODER = (GPIOA->MODER & ~(3u << 14)) | (1u << 14);
}

static void blink(int n, int width) {
    for (int i = 0; i < n; i++) {
        GPIOA->BSRR = (1u << 7); DLY(width);
        GPIOA->BRR  = (1u << 7); DLY(width);
    }
    DLY(300000);
}

/* ---------------------------------------------------------------- FLASH */
static void flash_unlock(void) {
    if (FLASH->CR & FLASH_CR_LOCK) {
        FLASH->KEYR = 0x45670123UL;
        FLASH->KEYR = 0xCDEF89ABUL;
    }
}

static void flash_lock(void) { FLASH->CR |= FLASH_CR_LOCK; }

static void flash_wait(void) {
    while (FLASH->SR & FLASH_SR_BSY1);
    FLASH->SR = FLASH_SR_EOP;
}

static void flash_erase_page(uint32_t addr) {
    FLASH->SR = 0xFFFFFFFF;
    uint32_t page = (addr - FLASH_BASE) / PAGE_SIZE;
    FLASH->CR = (page << FLASH_CR_PNB_Pos) | FLASH_CR_PER | FLASH_CR_STRT;
    flash_wait();
    FLASH->CR &= ~FLASH_CR_PER;
}

static void flash_write_dword(uint32_t addr, uint32_t w0, uint32_t w1) {
    FLASH->CR |= FLASH_CR_PG;
    *(volatile uint32_t *)addr       = w0;
    __ISB();
    *(volatile uint32_t *)(addr + 4) = w1;
    flash_wait();
    FLASH->CR &= ~FLASH_CR_PG;
}

/* --------------------------------------------------------------- CRC32 */
/* CRC-32/ISO-HDLC -- identical to the master and the extension. */
static uint32_t crc32_flash(uint32_t addr, uint32_t len) {
    const volatile uint8_t *d = (const volatile uint8_t *)addr;
    uint32_t c = 0xFFFFFFFF;
    while (len--) {
        c ^= *d++;
        for (uint8_t i = 8; i--; )
            c = (c & 1) ? (c >> 1) ^ 0xEDB88320UL : c >> 1;
    }
    return c ^ 0xFFFFFFFF;
}

/* ----------------------------------------------------------------- NVS */
static uint8_t nvs[NVS_SIZE];

static void nvs_read(void) {
    const volatile uint8_t *p = (const volatile uint8_t *)NVS_BASE;
    for (uint8_t i = 0; i < NVS_SIZE; i++) nvs[i] = p[i];
}

/* Rewrite NVS preserving device identity, clearing the pending flag and
 * discarding the staging metadata. Flash erases page-wise, so a bare erase
 * would destroy pairing and the manufacturing data. */
static void nvs_clear_pending(void) {
    /* Wipe only the staging metadata (16..31). Bytes 32..63 hold the
     * device keys and must survive; clearing them would leave the unit
     * unable to authenticate or accept any future update. */
    for (uint8_t i = NVS_META_MAGIC; i < NVS_FW_KEY; i++) nvs[i] = 0xFF;
    nvs[NVS_OTA_FLAG] = 0xFF;
    flash_erase_page(NVS_BASE);
    for (uint8_t i = 0; i < NVS_SIZE; i += 8) {
        uint32_t w0 = (uint32_t)nvs[i + 0]         | ((uint32_t)nvs[i + 1] << 8)
                    | ((uint32_t)nvs[i + 2] << 16) | ((uint32_t)nvs[i + 3] << 24);
        uint32_t w1 = (uint32_t)nvs[i + 4]         | ((uint32_t)nvs[i + 5] << 8)
                    | ((uint32_t)nvs[i + 6] << 16) | ((uint32_t)nvs[i + 7] << 24);
        flash_write_dword(NVS_BASE + i, w0, w1);
    }
}

/* ------------------------------------------------------------ VALIDATE */
/* Returns the staged image length if it is safe to apply, else 0. */
static uint32_t staged_image_len(void) {
    if (nvs[NVS_OTA_FLAG]   != UPDATE_PENDING)   return 0;
    if (nvs[NVS_META_MAGIC] != META_MAGIC_VAL)   return 0;
    /* Fail closed: an unprovisioned unit accepts nothing. */
    if (nvs[NVS_HW_TYPE]    == HW_UNPROVISIONED) return 0;
    if (nvs[NVS_META_TYPE]  != nvs[NVS_HW_TYPE]) return 0;

    /* Rollback floor: a genuine but withdrawn image must not be
     * reinstallable, or a known vulnerability could be restored by
     * replaying an old signed build. */
    if (nvs[NVS_META_SEC] < nvs[NVS_SEC_VER]) return 0;

    uint32_t len = (uint32_t)nvs[NVS_META_SIZE]
                 | ((uint32_t)nvs[NVS_META_SIZE + 1] << 8);
    if (len == 0 || len > SLOT_SIZE) return 0;

    uint32_t want = (uint32_t)nvs[NVS_META_CRC]
                  | ((uint32_t)nvs[NVS_META_CRC + 1] << 8)
                  | ((uint32_t)nvs[NVS_META_CRC + 2] << 16)
                  | ((uint32_t)nvs[NVS_META_CRC + 3] << 24);
    if (crc32_flash(SLOT_B, len) != want) return 0;

    return len;
}

/* ---------------------------------------------------------------- COPY */
static void copy_slot_b_to_a(void) {
    flash_unlock();

    uint32_t src = SLOT_B;
    uint32_t dst = SLOT_A;
    uint32_t end = SLOT_A + SLOT_SIZE;

    while (dst < end) {
        flash_erase_page(dst);
        for (uint32_t i = 0; i < PAGE_SIZE / 8; i++) {
            /* Slot B is word aligned, so a direct read is safe here. */
            uint32_t w0 = *(volatile uint32_t *)src;
            uint32_t w1 = *(volatile uint32_t *)(src + 4);
            flash_write_dword(dst, w0, w1);
            dst += 8;
            src += 8;
        }
    }

    /* Only now is it safe to drop the pending flag. */
    nvs_clear_pending();
    flash_lock();
}

/* ---------------------------------------------------------------- JUMP */
static int slot_a_valid(void) {
    uint32_t sp = *(volatile uint32_t *)SLOT_A;
    return (sp & 0xFFFF0000) == 0x20000000;
}

static void jump_to_slot_a(void) {
    uint32_t sp = *(volatile uint32_t *)SLOT_A;
    uint32_t pc = *(volatile uint32_t *)(SLOT_A + 4);
    /* Relocate the vector table and nothing else.
     *
     * Do NOT call __disable_irq() here: PRIMASK survives the jump and the
     * application never clears it, so the SysTick interrupt never fires,
     * millis() stays at 0 and everything time-based dies silently while
     * GPIO still works. Do NOT stop SysTick either; the application's
     * framework configures it during startup.
     *
     * This bootloader enables no interrupt sources of its own, so leaving
     * interrupts enabled across the jump is safe. */
    SCB->VTOR = SLOT_A;
    __asm volatile("msr msp,%0\nbx %1\n" : : "r"(sp), "r"(pc));
}

/* ---------------------------------------------------------------- MAIN */
int main(void) {
    led_init();
    nvs_read();

    if (nvs[NVS_OTA_FLAG] == UPDATE_PENDING) {
        if (staged_image_len()) {
            blink(3, 80000);            /* valid image, applying */
            /* Adopt the new image's security version as the new floor. */
            if (nvs[NVS_META_SEC] > nvs[NVS_SEC_VER])
                nvs[NVS_SEC_VER] = nvs[NVS_META_SEC];
            copy_slot_b_to_a();
        } else {
            blink(5, 80000);            /* rejected, keep running image */
            flash_unlock();
            nvs_clear_pending();
            flash_lock();
        }
    }

    if (slot_a_valid()) {
        blink(1, 300000);
        jump_to_slot_a();
    }

    for (;;) {
        GPIOA->BSRR = (1u << 7); DLY(30000);
        GPIOA->BRR  = (1u << 7); DLY(30000);
    }
}
