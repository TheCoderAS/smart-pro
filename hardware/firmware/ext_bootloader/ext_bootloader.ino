/*
 * OTA Bootloader -- Copy-swap approach
 *
 * Layout:
 *   0x08000000 - 0x08001000  Bootloader (4KB)
 *   0x08001000 - 0x08003800  Slot A -- always executes here (10KB)
 *   0x08003800 - 0x08006000  Slot B -- OTA staging only (10KB)
 *   0x08006000 - 0x08008000  NVS (8KB)
 *
 * NVS byte 7: UPDATE_PENDING flag (0xAA = copy Slot B to Slot A)
 *
 * LED3 (PA7):
 *   1 long blink  = normal boot, jumping to Slot A
 *   3 short blinks = OTA update detected, copying Slot B to Slot A
 *   rapid blink   = error
 *
 * Build: U(S)ART disabled, Flash offset 0x0, -Os LTO
 * Flash at: 0x08000000
 */
#include "stm32g0xx.h"

#define SLOT_A        0x08001000UL
#define SLOT_B        0x08003800UL
#define SLOT_SIZE     (10UL * 1024UL)  /* 10KB */
#define PAGE_SIZE     2048UL
#define NVS_BASE      0x08006000UL
#define UPDATE_PENDING 0xAA

#define DLY(n) do{for(volatile int _i=0;_i<(n);_i++);}while(0)

static void led_init(void) {
    RCC->IOPENR |= 1u;
    GPIOA->MODER = (GPIOA->MODER & ~(3u<<14)) | (1u<<14);
}

static void blink(int n, int duration) {
    for (int i=0; i<n; i++) {
        GPIOA->BSRR=(1u<<7); DLY(duration);
        GPIOA->BRR =(1u<<7); DLY(duration);
    }
    DLY(300000);
}

static void flash_unlock(void) {
    if (FLASH->CR & FLASH_CR_LOCK) {
        FLASH->KEYR = 0x45670123UL;
        FLASH->KEYR = 0xCDEF89ABUL;
    }
}

static void flash_lock(void) {
    FLASH->CR |= FLASH_CR_LOCK;
}

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
    *(volatile uint32_t*)addr       = w0;
    __ISB();
    *(volatile uint32_t*)(addr + 4) = w1;
    flash_wait();
    FLASH->CR &= ~FLASH_CR_PG;
}

static void copy_slot_b_to_a(void) {
    flash_unlock();
    uint32_t *src = (uint32_t*)SLOT_B;
    uint32_t dst  = SLOT_A;
    uint32_t end  = SLOT_A + SLOT_SIZE;

    while (dst < end) {
        /* Erase destination page */
        flash_erase_page(dst);
        /* Write one page (2KB = 256 dwords) */
        for (uint32_t i = 0; i < PAGE_SIZE/8; i++) {
            flash_write_dword(dst, src[0], src[1]);
            dst += 8;
            src += 2;
        }
    }

    /* Clear UPDATE_PENDING flag -- erase NVS page */
    flash_erase_page(NVS_BASE);
    flash_lock();
}

static int valid(uint32_t a) {
    uint32_t sp = *(volatile uint32_t*)a;
    return (sp & 0xFFFF0000) == 0x20000000;
}

static void jump_to_slot_a(void) {
    uint32_t sp = *(volatile uint32_t*)SLOT_A;
    uint32_t pc = *(volatile uint32_t*)(SLOT_A + 4);
    SCB->VTOR = SLOT_A;
    __asm volatile("msr msp,%0\nbx %1\n"::"r"(sp),"r"(pc));
}

int main(void) {
    led_init();

    uint8_t flag = ((volatile uint8_t*)NVS_BASE)[7]; /* NVS_OTA_FLAG = byte 7 */

    if (flag == UPDATE_PENDING) {
        /* OTA update pending -- copy Slot B to Slot A */
        blink(3, 80000); /* 3 short blinks = OTA update */
        copy_slot_b_to_a();
    }

    if (valid(SLOT_A)) {
        blink(1, 300000); /* 1 long blink = normal boot */
        jump_to_slot_a();
    }

    /* Error -- rapid blink */
    for(;;){GPIOA->BSRR=(1u<<7);DLY(30000);GPIOA->BRR=(1u<<7);DLY(30000);}
}
