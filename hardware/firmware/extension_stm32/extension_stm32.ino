/*
 * Unisync - Extension Firmware v4.6
 * STM32G030F6P6 (TSSOP-20) -- Arduino IDE + STM32duino + LL drivers
 *
 * Build settings:
 *   Board:           Generic STM32G0 series / Generic G030F6Px
 *   Optimize:        Smallest (-Os) with LTO
 *   C Runtime:       Newlib Nano
 *   Upload:          STM32CubeProgrammer (SWD)
 *
 * Pin assignments (schematic Rev 1.1):
 *   PA_0  - RS485_DE   (MAX3485 DE/RE# -- HIGH=TX, LOW=RX)
 *   PA_1  - RELAY1_DRV (S8050 NPN -- HIGH=ON, LOW=OFF)
 *   PA_2  - RELAY2_DRV (S8050 NPN -- HIGH=ON, LOW=OFF)
 *   PA_3  - TOUCH1_IRQ (TTP223 -- HIGH on touch)
 *   PA_4  - TOUCH2_IRQ (TTP223 -- HIGH on touch)
 *   PA_5  - LED1       (green -- mirrors relay1)
 *   PA_6  - LED2       (green -- mirrors relay2)
 *   PA_7  - LED3       (green -- heartbeat)
 *   PA_9  - RS485_TX   (USART1 TX)
 *   PA_10 - RS485_RX   (USART1 RX)
 */

#include "Arduino.h"   /* millis(), delay() only */

/* Placed directly after the includes on purpose: the Arduino build
 * generates function prototypes and inserts them above the first
 * function in the sketch. A type used in a prototype must therefore
 * be declared before that point, or every SHA-256 function fails to
 * compile with "sha256_t was not declared in this scope".
 */
/* ================================================================
 * SHA-256 and HMAC-SHA-256
 * Compact implementation shared byte-for-byte by the master and the
 * extension so both sides can never disagree. Replaces CRC32, which is
 * linear and therefore forgeable from a handful of observed pairs.
 * ================================================================ */
typedef struct {
    uint32_t st[8];
    uint32_t len;
    uint8_t  buf[64];
    uint8_t  n;
} sha256_t;

static const uint32_t SHA_K[64] = {
0x428a2f98UL,0x71374491UL,0xb5c0fbcfUL,0xe9b5dba5UL,0x3956c25bUL,0x59f111f1UL,
0x923f82a4UL,0xab1c5ed5UL,0xd807aa98UL,0x12835b01UL,0x243185beUL,0x550c7dc3UL,
0x72be5d74UL,0x80deb1feUL,0x9bdc06a7UL,0xc19bf174UL,0xe49b69c1UL,0xefbe4786UL,
0x0fc19dc6UL,0x240ca1ccUL,0x2de92c6fUL,0x4a7484aaUL,0x5cb0a9dcUL,0x76f988daUL,
0x983e5152UL,0xa831c66dUL,0xb00327c8UL,0xbf597fc7UL,0xc6e00bf3UL,0xd5a79147UL,
0x06ca6351UL,0x14292967UL,0x27b70a85UL,0x2e1b2138UL,0x4d2c6dfcUL,0x53380d13UL,
0x650a7354UL,0x766a0abbUL,0x81c2c92eUL,0x92722c85UL,0xa2bfe8a1UL,0xa81a664bUL,
0xc24b8b70UL,0xc76c51a3UL,0xd192e819UL,0xd6990624UL,0xf40e3585UL,0x106aa070UL,
0x19a4c116UL,0x1e376c08UL,0x2748774cUL,0x34b0bcb5UL,0x391c0cb3UL,0x4ed8aa4aUL,
0x5b9cca4fUL,0x682e6ff3UL,0x748f82eeUL,0x78a5636fUL,0x84c87814UL,0x8cc70208UL,
0x90befffaUL,0xa4506cebUL,0xbef9a3f7UL,0xc67178f2UL };

#define SHA_ROR(x,n) (((x)>>(n))|((x)<<(32-(n))))

static void sha256_block(sha256_t *c, const uint8_t *p) {
    uint32_t w[64], a,b,cc,d,e,f,g,h,t1,t2;
    for (int i=0;i<16;i++)
        w[i]=((uint32_t)p[i*4]<<24)|((uint32_t)p[i*4+1]<<16)|
             ((uint32_t)p[i*4+2]<<8)|(uint32_t)p[i*4+3];
    for (int i=16;i<64;i++) {
        uint32_t s0=SHA_ROR(w[i-15],7)^SHA_ROR(w[i-15],18)^(w[i-15]>>3);
        uint32_t s1=SHA_ROR(w[i-2],17)^SHA_ROR(w[i-2],19)^(w[i-2]>>10);
        w[i]=w[i-16]+s0+w[i-7]+s1;
    }
    a=c->st[0];b=c->st[1];cc=c->st[2];d=c->st[3];
    e=c->st[4];f=c->st[5];g=c->st[6];h=c->st[7];
    for (int i=0;i<64;i++) {
        uint32_t S1=SHA_ROR(e,6)^SHA_ROR(e,11)^SHA_ROR(e,25);
        uint32_t ch=(e&f)^((~e)&g);
        t1=h+S1+ch+SHA_K[i]+w[i];
        uint32_t S0=SHA_ROR(a,2)^SHA_ROR(a,13)^SHA_ROR(a,22);
        uint32_t mj=(a&b)^(a&cc)^(b&cc);
        t2=S0+mj;
        h=g;g=f;f=e;e=d+t1;d=cc;cc=b;b=a;a=t1+t2;
    }
    c->st[0]+=a;c->st[1]+=b;c->st[2]+=cc;c->st[3]+=d;
    c->st[4]+=e;c->st[5]+=f;c->st[6]+=g;c->st[7]+=h;
}

static void sha256_init(sha256_t *c) {
    c->st[0]=0x6a09e667UL;c->st[1]=0xbb67ae85UL;c->st[2]=0x3c6ef372UL;
    c->st[3]=0xa54ff53aUL;c->st[4]=0x510e527fUL;c->st[5]=0x9b05688cUL;
    c->st[6]=0x1f83d9abUL;c->st[7]=0x5be0cd19UL;
    c->len=0;c->n=0;
}

static void sha256_update(sha256_t *c, const uint8_t *p, uint32_t n) {
    c->len += n;
    while (n--) {
        c->buf[c->n++]=*p++;
        if (c->n==64) { sha256_block(c,c->buf); c->n=0; }
    }
}

static void sha256_final(sha256_t *c, uint8_t *out) {
    uint32_t bits = c->len * 8;
    c->buf[c->n++]=0x80;
    if (c->n>56) { while(c->n<64) c->buf[c->n++]=0; sha256_block(c,c->buf); c->n=0; }
    while (c->n<56) c->buf[c->n++]=0;
    c->buf[56]=0;c->buf[57]=0;c->buf[58]=0;c->buf[59]=0;
    c->buf[60]=(bits>>24)&0xFF;c->buf[61]=(bits>>16)&0xFF;
    c->buf[62]=(bits>>8)&0xFF; c->buf[63]=bits&0xFF;
    sha256_block(c,c->buf);
    for (int i=0;i<8;i++) {
        out[i*4]  =(c->st[i]>>24)&0xFF; out[i*4+1]=(c->st[i]>>16)&0xFF;
        out[i*4+2]=(c->st[i]>>8)&0xFF;  out[i*4+3]=c->st[i]&0xFF;
    }
}

/* HMAC-SHA-256 with a 16-byte key. */
static void hmac_sha256(const uint8_t *key, const uint8_t *msg, uint32_t mlen,
                        uint8_t *out32) {
    uint8_t k_ipad[64], k_opad[64], inner[32];
    sha256_t c;
    for (int i=0;i<64;i++) {
        uint8_t kb = (i<16) ? key[i] : 0;
        k_ipad[i]=kb^0x36; k_opad[i]=kb^0x5c;
    }
    sha256_init(&c); sha256_update(&c,k_ipad,64);
    sha256_update(&c,msg,mlen); sha256_final(&c,inner);
    sha256_init(&c); sha256_update(&c,k_opad,64);
    sha256_update(&c,inner,32); sha256_final(&c,out32);
}

/* Constant-time compare: an early exit leaks how many bytes matched. */
static bool ct_equal(const uint8_t *a, const uint8_t *b, uint8_t n) {
    uint8_t d=0;
    while (n--) d |= (uint8_t)(*a++ ^ *b++);
    return d==0;
}


/* ================================================================
 * GPIO BIT-BANG MACROS (replaces digitalWrite/pinMode)
 * All pins on GPIOA -- direct register writes, zero overhead
 * ================================================================ */
#define PIN_SET(pin)    (GPIOA->BSRR = (1u << (pin)))
#define PIN_CLR(pin)    (GPIOA->BRR  = (1u << (pin)))
#define PIN_READ(pin)   ((GPIOA->IDR  >> (pin)) & 1u)

/* Pin numbers (bit positions in GPIOA) */
#define PIN_RS485_DE   0
#define PIN_RELAY1     1
#define PIN_RELAY2     2
#define PIN_TOUCH1     3
#define PIN_TOUCH2     4
#define PIN_LED1       5
#define PIN_LED2       6
#define PIN_LED3       7
/* PA9=TX, PA10=RX handled by USART1 alternate function */

/* ================================================================
 * PROTOCOL
 * ================================================================ */
/* ================================================================
 * DEVICE IDENTITY
 * FW_DESC is a locatable blob inside the .bin. The master scans an
 * uploaded image for FW_DESC_MAGIC and reads the target type/version
 * straight out of it, so the operator never types a version by hand
 * and a wrong-type image is rejected before it is ever transmitted.
 * hw_type is NOT here -- it lives in NVS, written at manufacture, and
 * is the one fact an update must never be able to change.
 * ================================================================ */
#define FW_VER_MAJOR   1
#define FW_VER_MINOR   2
#define FW_VER_PATCH   5
#define FW_TARGET_TYPE 0x01          /* image is built for this hw_type */

/* No custom section: an orphan section is placed at the linker's
 * discretion and can disturb the .data load region. Ordinary .rodata,
 * kept alive by being read at run time below. */
/* volatile is load-bearing, not decoration: without it the compiler
 * constant-folds every FW_DESC[n] read into a literal, nothing references
 * the array any more, and -Os with LTO discards it -- leaving an image the
 * master cannot identify. volatile forces a real memory load, which forces
 * the array to exist in .rodata. External linkage for the same reason. */
__attribute__((used))
const volatile uint8_t FW_DESC[16] = {
    'U','N','I','S','Y','N','C','1',            /* magic, 8 bytes  */
    FW_TARGET_TYPE, 0x00,                       /* type, hw_rev_min */
    FW_VER_MAJOR, FW_VER_MINOR, FW_VER_PATCH,   /* version          */
    0x00, 0x00, 0x00                            /* reserved         */
};

#define UART_BAUD         250000
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
#define CMD_GET_INFO      0x24
#define CMD_INFO_RESP     0x25
#define CMD_OTA_BEGIN     0x40
#define CMD_OTA_CHUNK     0x41
#define CMD_OTA_END       0x42
#define CMD_OTA_ACK       0x43
#define CMD_BUS_QUIET     0x44
#define CMD_ERROR         0xF0
#define CMD_ANNOUNCE      0x50
#define CMD_WELCOME       0x51
#define CMD_REJECT        0x52
#define CMD_CHALLENGE     0x54
#define CMD_RESPONSE      0x55


/* ================================================================
 * FLASH EEPROM EMULATION
 * STM32G030F6P6: 32KB flash, 2KB pages
 * Use last page (0x08007800 - 0x08007FFF) for NVS
 * Page must be erased before write (erase sets all bytes to 0xFF)
 * Write 8 bytes (double-word) at a time
 * ================================================================ */
#define NVS_PAGE_ADDR   0x08007000UL  /* NVS start (4KB, 2 pages) */
#define NVS_PAGE_SIZE   2048  /* flash erase page size */

/* NVS byte offsets */
/* NVS v2 -- 32 bytes / 4 doublewords. FROZEN: the bootloader depends on
 * this layout and the bootloader cannot be updated in the field. */
#define NVS_SIZE        64
#define NVS_MAGIC       0   /* 1 byte: 0xA5 registered / 0x5A standalone */
#define NVS_ADDR        1   /* 1 byte: bus address */
#define NVS_RELAY       2   /* 1 byte: bit0=relay1, bit1=relay2 */
#define NVS_MUID0       3   /* 4 bytes: master UID */
/* byte 7 = NVS_OTA_FLAG (below) */
#define NVS_HW_TYPE     8   /* provisioned at manufacture, 0xFF = unprovisioned */
#define NVS_HW_REV      9
#define NVS_BOOT_CNT   10
#define NVS_SEC_VER    11   /* rollback floor: refuse images below this */
/* bytes 16..31 = OTA staging metadata, read by the bootloader */
#define NVS_META_MAGIC 16   /* 0x5A when a staged image is present */
#define NVS_META_TYPE  17   /* target hw_type of the staged image */
#define NVS_META_VER   18   /* 3 bytes: major, minor, patch */
#define NVS_META_SIZE  22   /* 2 bytes LE: staged image length */
#define NVS_META_CRC   24   /* 4 bytes LE: CRC32 of the staged image */
#define NVS_META_SEC   21   /* security version of the staged image */
#define NVS_FW_KEY     32   /* 16 bytes: firmware verification key */
#define NVS_DEV_KEY    48   /* 16 bytes: per-device bus key */
#define META_MAGIC_VAL 0x5A
#define NVS_MUID1       4
#define NVS_MUID2       5
#define NVS_MUID3       6
#define NVS_MAGIC_VAL   0xA5  /* registered to master */
#define NVS_RELAY_MAGIC 0x5A  /* standalone relay state only */
#define NVS_OTA_FLAG    7     /* byte 7: UPDATE_PENDING flag */
#define UPDATE_PENDING  0xAA  /* bootloader will copy Slot B to Slot A */

/* Flash layout (with bootloader):
 * 0x08000000 - 0x08001000  Bootloader (4KB)
 * 0x08001000 - 0x08004000  Slot A -- always runs here (12KB)
 * 0x08004000 - 0x08007000  Slot B -- OTA staging (12KB)
 * 0x08007000 - 0x08008000  NVS (4KB)
 */
#define SLOT_B_ADDR      0x08004000UL
#define SLOT_SIZE        (12UL * 1024UL)
#define OTA_CHUNK_SIZE   32

/* Shadow RAM copy of NVS page (2KB is too large -- use only first 8 bytes) */
static uint8_t nvs_shadow[NVS_SIZE] __attribute__((aligned(4)));

/* Shared flash primitives */
static void flash_unlock(void) {
    if(FLASH->CR&FLASH_CR_LOCK){FLASH->KEYR=0x45670123UL;FLASH->KEYR=0xCDEF89ABUL;}
}
static void flash_wait(uint32_t ms) {
    uint32_t t=millis();
    while((FLASH->SR&FLASH_SR_BSY1)&&(millis()-t)<ms);
    FLASH->SR=FLASH_SR_EOP;
}
static void flash_erase_page(uint32_t addr) {
    FLASH->SR=0xFFFFFFFF;
    FLASH->CR=((addr-FLASH_BASE)/NVS_PAGE_SIZE<<FLASH_CR_PNB_Pos)|FLASH_CR_PER|FLASH_CR_STRT;
    flash_wait(500);
    FLASH->CR&=~FLASH_CR_PER;
}
static void flash_write_dwords(volatile uint32_t *dst, const uint32_t *src, uint8_t n) {
    FLASH->CR|=FLASH_CR_PG;
    while(n--){*dst++=*src++;__ISB();*dst++=*src++;flash_wait(100);}
    FLASH->CR&=~FLASH_CR_PG;
}

static void nvs_flush(void) {
    flash_unlock();
    flash_erase_page(NVS_PAGE_ADDR);
    flash_write_dwords((volatile uint32_t*)NVS_PAGE_ADDR,(const uint32_t*)nvs_shadow,NVS_SIZE/8);
    FLASH->CR|=FLASH_CR_LOCK;
}

/* ================================================================
 * USART1 LL DRIVER (PA_9=TX, PA_10=RX, 250000 baud)
 * ================================================================ */
static void usart1_init(void) {
    /* Enable USART1, SYSCFG, GPIOA clocks */
    RCC->APBENR2 |= RCC_APBENR2_USART1EN | RCC_APBENR2_SYSCFGEN;
    RCC->IOPENR  |= RCC_IOPENR_GPIOAEN;
    /* SYSCFG remap -- required for USART1 on G030 */
    SYSCFG->CFGR1 |= SYSCFG_CFGR1_PA11_RMP | SYSCFG_CFGR1_PA12_RMP;
    /* PA9 = AF1 TX: high speed, push-pull */
    GPIOA->MODER   = (GPIOA->MODER   & ~(3u<<18)) | (2u<<18);
    GPIOA->AFR[1]  = (GPIOA->AFR[1]  & ~(15u<<4)) | (1u<<4);
    GPIOA->OSPEEDR = (GPIOA->OSPEEDR & ~(3u<<18)) | (3u<<18);
    GPIOA->OTYPER &= ~(1u<<9);
    /* PA10 = AF1 RX: pull-up */
    GPIOA->MODER  = (GPIOA->MODER  & ~(3u<<20)) | (2u<<20);
    GPIOA->AFR[1] = (GPIOA->AFR[1] & ~(15u<<8)) | (1u<<8);
    GPIOA->PUPDR  = (GPIOA->PUPDR  & ~(3u<<20)) | (1u<<20);
    /* USART1: 8N1, 250000 baud, TX+RX enabled */
    USART1->CR1  = 0;
    USART1->CR2  = 0;
    USART1->CR3  = 0;
    USART1->PRESC = 0;
    USART1->BRR  = (64000000UL / 250000UL);
    /* Enable FIFO mode: RX holding register becomes an 8-byte FIFO, so a
     * polled receiver tolerates 320us of loop jitter instead of 40us.
     * Without this a single late poll drops a byte and kills the frame. */
#ifdef USART_CR1_FIFOEN
    USART1->CR1  = USART_CR1_FIFOEN | USART_CR1_TE | USART_CR1_RE | USART_CR1_UE;
#else
    USART1->CR1  = USART_CR1_TE | USART_CR1_RE | USART_CR1_UE;
#endif
    uint32_t t   = millis();
    while (!(USART1->ISR & USART_ISR_TEACK) && (millis()-t) < 100);
    while (!(USART1->ISR & USART_ISR_REACK) && (millis()-t) < 100);
}

static void usart1_write_byte(uint8_t b) {
    while (!(USART1->ISR & USART_ISR_TXE_TXFNF));
    USART1->TDR = b;
}

static void usart1_wait_tc(void) {
    while (!(USART1->ISR & USART_ISR_TC));
}

static bool usart1_available(void) {
    if (USART1->ISR & USART_ISR_ORE) USART1->ICR = USART_ICR_ORECF;
    return (USART1->ISR & USART_ISR_RXNE_RXFNE) != 0;
}

static uint8_t usart1_read_byte(void) {
    return USART1->RDR & 0xFF;
}

/* ================================================================
 * GPIO INIT (replaces pinMode/digitalWrite)
 * ================================================================ */
static void gpio_init(void) {
    RCC->IOPENR |= RCC_IOPENR_GPIOAEN;
    /* Relay HIGH before output (active LOW = OFF) */
    GPIOA->BSRR = (1u<<1)|(1u<<2);
    GPIOA->BRR  = (1u<<0)|(1u<<5)|(1u<<6)|(1u<<7);
    /* PA0,1,2,5,6,7=output PA3,4=input no-pull */
    GPIOA->MODER = (GPIOA->MODER
        & ~((3u<<0)|(3u<<2)|(3u<<4)|(3u<<6)|(3u<<8)|(3u<<10)|(3u<<12)|(3u<<14)))
        |  ((1u<<0)|(1u<<2)|(1u<<4)|(1u<<10)|(1u<<12)|(1u<<14));
    GPIOA->PUPDR = (GPIOA->PUPDR & ~((3u<<6)|(3u<<8)));
}

/* ================================================================
 * CHIP UID (96-bit at 0x1FFF7590, use bytes 8-11)
 * Cached at startup -- UID never changes, no need to re-read flash
 * ================================================================ */
static uint8_t device_uid[4] = {0};

static void uid_init(void) {
    uint32_t w=((volatile uint32_t*)0x1FFF7590UL)[2];
    device_uid[0]=(w>>24)&0xFF;device_uid[1]=(w>>16)&0xFF;
    device_uid[2]=(w>>8)&0xFF; device_uid[3]=w&0xFF;
}


/* ================================================================
 * CRC-8
 * ================================================================ */
static uint8_t crc8(uint8_t *d, uint8_t n) {
    uint8_t c=0;
    while(n--){c^=*d++;for(uint8_t i=8;i--;)c=c&0x80?(c<<1)^7:c<<1;}
    return c;
}

/* ================================================================
 * CRC32 -- uses STM32G030 hardware CRC unit (CRC-32/MPEG-2 poly)
 * Reset unit, feed data word by word, read result.
 * Saves ~200 bytes vs software loop.
 * ================================================================ */
static uint32_t crc32_compute(const uint8_t *d, uint32_t n) {
    uint32_t c=0xFFFFFFFF;
    while(n--){c^=*d++;for(uint8_t i=8;i--;)c=c&1?(c>>1)^0xEDB88320UL:c>>1;}
    return c^0xFFFFFFFF;
}

/* HMAC-SHA256(dev_key, nonce || uid), truncated to 8 bytes.
 * The old construction was CRC32 over a key, which is linear: a few
 * observed pairs were enough to solve for the key's contribution. */
static void compute_response(const uint8_t *nonce, uint8_t nlen, uint8_t *out8) {
    uint8_t msg[16], mac[32];
    uint8_t n = (nlen > 8) ? 8 : nlen;
    for (uint8_t i=0;i<n;i++) msg[i]=nonce[i];
    for (uint8_t i=0;i<4;i++) msg[n+i]=device_uid[i];
    hmac_sha256(&nvs_shadow[NVS_DEV_KEY], msg, n+4, mac);
    for (uint8_t i=0;i<8;i++) out8[i]=mac[i];
}

/* ================================================================
 * PSEUDO-RANDOM
 * ================================================================ */

/* ================================================================
 * STATE
 * ================================================================ */
#define ORPHAN_TIMEOUT_MS  30000UL

typedef enum {
    MODE_UNREGISTERED = 0,
    MODE_REGISTERED,
    MODE_OTA,
    MODE_QUIET
} ext_mode_t;

static ext_mode_t mode          = MODE_UNREGISTERED;
static uint8_t    slot_address  = ADDR_UNASSIGNED;
static uint8_t    master_uid[4] = {0};
static bool       relay1_state  = false;
static bool       relay2_state  = false;

#define EVENT_BUF_SIZE 8
typedef struct {
    uint8_t channel;
    uint8_t state;
} touch_event_t;

static touch_event_t event_buf[EVENT_BUF_SIZE];
static uint8_t       event_head  = 0;
static uint8_t       event_tail  = 0;
static uint8_t       event_count = 0;

static bool     last_t1         = false;
static bool     last_t2         = false;
static uint32_t last_poll_ms    = 0;

static uint8_t  rx_buf[56] __attribute__((aligned(4)));
static uint8_t  rx_pos          = 0;
static uint8_t  rx_elen         = 0;

static uint32_t last_announce_ms  = 0;
static uint32_t announce_interval = 2000;

/* ================================================================
 * BREATH TICK -- TIM17 hardware PWM on PA7
 * Registered: 32 * 125ms = 4s cycle
 * Unregistered: 32 * 31ms = ~1s cycle
 * ================================================================ */
/* breath computed inline */

static void tim17_pwm_init(void) {
    RCC->APBENR2 |= RCC_APBENR2_TIM17EN;
    /* PA7 = AF5 (TIM17_CH1) push-pull */
    GPIOA->MODER  = (GPIOA->MODER  & ~(3u<<14)) | (2u<<14);
    GPIOA->AFR[0] = (GPIOA->AFR[0] & ~(15u<<28)) | (5u<<28);
    TIM17->PSC   = 0;
    TIM17->ARR   = 255;
    TIM17->CCR1  = 0;
    TIM17->CCMR1 = (6u << TIM_CCMR1_OC1M_Pos) | TIM_CCMR1_OC1PE;
    TIM17->CCER  = TIM_CCER_CC1E;
    TIM17->BDTR  = TIM_BDTR_MOE;
    TIM17->CR1   = TIM_CR1_CEN;
}

static void breath_tick(void) {
    static uint32_t last_ms = 0;
    static uint8_t  step    = 0;
    uint32_t interval = (mode == MODE_REGISTERED) ? 125 : 31;
    if ((millis() - last_ms) < interval) return;
    last_ms = millis();
    uint8_t s = step & 0x1F;
    TIM17->CCR1 = (s < 16) ? (uint32_t)(s << 4) : (uint32_t)((31 - s) << 4);
    step++;
}




/* ================================================================
 * PERSISTENCE
 * ================================================================ */
static void load_state(void) {
    volatile uint8_t *p=(volatile uint8_t*)NVS_PAGE_ADDR;
    for(uint8_t i=0;i<NVS_SIZE;i++) nvs_shadow[i]=p[i];
    relay1_state=(nvs_shadow[NVS_RELAY]&0x01)!=0;
    relay2_state=(nvs_shadow[NVS_RELAY]&0x02)!=0;
    if (nvs_shadow[NVS_MAGIC]==NVS_MAGIC_VAL) {
        slot_address=nvs_shadow[NVS_ADDR];
        master_uid[0]=nvs_shadow[NVS_MUID0]; master_uid[1]=nvs_shadow[NVS_MUID1];
        master_uid[2]=nvs_shadow[NVS_MUID2]; master_uid[3]=nvs_shadow[NVS_MUID3];
        mode=MODE_REGISTERED;
    } else {
        mode=MODE_UNREGISTERED; slot_address=ADDR_UNASSIGNED;
    }
}

static void save_registration(uint8_t addr, uint8_t *m_uid) {
    nvs_shadow[NVS_ADDR]  = addr;
    nvs_shadow[NVS_MUID0] = m_uid[0];
    nvs_shadow[NVS_MUID1] = m_uid[1];
    nvs_shadow[NVS_MUID2] = m_uid[2];
    nvs_shadow[NVS_MUID3] = m_uid[3];
    nvs_shadow[NVS_MAGIC] = NVS_MAGIC_VAL;
    /* Also persist current relay state at registration time */
    nvs_shadow[NVS_RELAY] = (relay1_state ? 0x01 : 0x00) |
                             (relay2_state ? 0x02 : 0x00);
    nvs_flush();
}

/* Every nvs_flush() erases and rewrites the whole 2 KB page. Doing that
 * inline on each toggle burns a page-erase cycle per press, which is the
 * flash-wear problem the tech story calls out. The shadow is updated
 * immediately (so every reader sees the truth at once) and only the
 * flash write is deferred until the user stops flipping the switch. */
#define NVS_WRITE_DEBOUNCE_MS 3000UL
static bool     nvs_dirty    = false;
static uint32_t nvs_dirty_ms = 0;

static void save_relay_state(void) {
    nvs_shadow[NVS_RELAY] = (relay1_state ? 0x01 : 0x00) |
                             (relay2_state ? 0x02 : 0x00);
    nvs_shadow[NVS_MAGIC] = NVS_RELAY_MAGIC; /* standalone -- not registered */
    nvs_dirty    = true;
    nvs_dirty_ms = millis();
}

/* Write now, cancelling any pending debounce. For mode changes, where
 * losing the state to a power cut would be worse than a page erase. */
static void save_relay_state_now(void) {
    save_relay_state();
    nvs_flush();
    nvs_dirty = false;
}

/* Called every loop: commits a debounced write once the burst ends.
 * Never during OTA -- nvs_flush() erases a flash page, and doing that
 * while the bootloader is writing firmware is how you brick a board. A
 * pending write simply waits; OTA ends in a reset anyway. */
static void nvs_tick(void) {
    if (!nvs_dirty || mode == MODE_OTA) return;
    if ((millis() - nvs_dirty_ms) < NVS_WRITE_DEBOUNCE_MS) return;
    nvs_flush();
    nvs_dirty = false;
}

static void wipe_registration(void) {
    /* Preserve manufacturing data (hw_type/hw_rev) across an unregister */
    for(uint8_t i=0;i<8;i++) nvs_shadow[i]=0;
    for(uint8_t i=NVS_META_MAGIC;i<NVS_SIZE;i++) nvs_shadow[i]=0xFF;
    nvs_flush();
}

/* ================================================================
 * RS-485 TRANSPORT
 * ================================================================ */
static void rs485_send(uint8_t *frame, uint8_t len) {
    PIN_SET(PIN_RS485_DE);
    __NOP(); __NOP(); __NOP(); __NOP(); /* ~250ns guard */
    for (uint8_t i = 0; i < len; i++) usart1_write_byte(frame[i]);
    usart1_wait_tc();
    __NOP(); __NOP(); __NOP(); __NOP();
    PIN_CLR(PIN_RS485_DE);
    /* MAX3485 RX enable guard + flush echo bytes */
    __NOP(); __NOP(); __NOP(); __NOP();
    if (USART1->ISR & USART_ISR_ORE) USART1->ICR = USART_ICR_ORECF;
    if (USART1->ISR & USART_ISR_RXNE_RXFNE) (void)USART1->RDR;
    rx_pos = 0; rx_elen = 0;
}

static void send_frame(uint8_t dst, uint8_t cmd,
                       uint8_t *payload, uint8_t plen) {
    uint8_t frame[56];
    frame[0] = SOF;
    frame[1] = dst;
    frame[2] = slot_address;
    frame[3] = cmd;
    frame[4] = plen;
    for(uint8_t _i=0;_i<plen;_i++) frame[5+_i]=payload[_i];
    frame[5 + plen] = crc8(&frame[1], 4 + plen);
    rs485_send(frame, 6 + plen);
}

/* ================================================================
 * RELAY CONTROL (active HIGH -- S8050 NPN)
 * ================================================================ */
static void set_relay1(bool s) {
    relay1_state = s;
    if (s) { PIN_CLR(PIN_RELAY1); PIN_SET(PIN_LED1); }
    else   { PIN_SET(PIN_RELAY1); PIN_CLR(PIN_LED1); }
}

static void set_relay2(bool s) {
    relay2_state = s;
    if (s) { PIN_CLR(PIN_RELAY2); PIN_SET(PIN_LED2); }
    else   { PIN_SET(PIN_RELAY2); PIN_CLR(PIN_LED2); }
}

/* ================================================================
 * SELF-UNREGISTER
 * ================================================================ */
/* Reached only from the orphan timeout: the master has stopped answering.
 * That is a lost *link*, not an instruction to change anything, so the
 * relays are left exactly as the user last set them -- a master reboot
 * must not darken a lit house. The board simply reverts to standalone
 * behaviour, where touch keeps working and it owns its own state again.
 *
 * wipe_registration() clears bytes 0..7, which includes NVS_RELAY, so the
 * live state is re-persisted afterwards under the standalone magic --
 * otherwise a later power cut would restore stale or empty state. */
static void self_unregister(void) {
    wipe_registration();
    slot_address      = ADDR_UNASSIGNED;
    mode              = MODE_UNREGISTERED;
    announce_interval = 2000;
    last_announce_ms  = 0;
    save_relay_state_now();
}

/* ================================================================
 * TOUCH EVENT BUFFER
 * ================================================================ */


/* ================================================================
 * TOUCH HANDLER
 * ================================================================ */
static void push_event(uint8_t ch, uint8_t s) {
    event_buf[event_head].channel=ch; event_buf[event_head].state=s;
    event_head=(event_head+1)&7;
    if(event_count<8)event_count++;else event_tail=(event_tail+1)&7;
}

static void handle_touch(void) {
    if (mode == MODE_OTA) return;   /* no relay or NVS activity during OTA */
    bool t1 = PIN_READ(PIN_TOUCH1);
    bool t2 = PIN_READ(PIN_TOUCH2);
    if (t1 && !last_t1) {
        set_relay1(!relay1_state);
        push_event(1,relay1_state);
        if (mode != MODE_REGISTERED) save_relay_state();
    }
    if (t2 && !last_t2) {
        set_relay2(!relay2_state);
        push_event(2,relay2_state);
        if (mode != MODE_REGISTERED) save_relay_state();
    }
    last_t1 = t1;
    last_t2 = t2;
}

/* ================================================================
 * ANNOUNCE
 * ================================================================ */
static void send_announce(void) {
    uint8_t f[15]={SOF,ADDR_MASTER,ADDR_UNASSIGNED,CMD_ANNOUNCE,9,
        device_uid[0],device_uid[1],device_uid[2],device_uid[3],
        (uint8_t)((relay1_state?1:0)|(relay2_state?2:0)|(event_count?4:0)),
        nvs_shadow[NVS_HW_TYPE],
        FW_DESC[10],FW_DESC[11],FW_DESC[12],0};
    f[14]=crc8(&f[1],13);
    rs485_send(f,15);
}

/* ================================================================
 * STATE RESPONSE
 * ================================================================ */
static void send_state_resp(void) {
    uint8_t payload[3 + 5*2];
    uint8_t plen = 0;
    uint8_t flags = 0;
    if (relay1_state)  flags |= 0x01;
    if (relay2_state)  flags |= 0x02;
    if (event_count>0) flags |= 0x04;
    payload[plen++] = flags;
    payload[plen++] = 25;
    payload[plen++] = event_count;
    uint8_t tail = event_tail;
    uint8_t cnt  = event_count < 5 ? event_count : 5;
    for (uint8_t ei = 0; ei < cnt; ei++) {
        payload[plen++] = event_buf[tail].channel;
        payload[plen++] = event_buf[tail].state;
        tail = (tail + 1) & 7;
    }
    send_frame(ADDR_MASTER, CMD_STATE_RESP, payload, plen);
}

/* ================================================================
 * PROCESS FRAME
 * ================================================================ */
static uint32_t ota_total=0,ota_crc_ex=0;
static uint16_t ota_last_idx=0xFFFF;  /* de-dupe retried chunks */
static uint8_t  ota_ver[3]={0,0,0};   /* version of the staged image */
static uint8_t  ota_sec = 0;          /* security version of staged image */
static uint8_t  ota_sig[32];          /* HMAC-SHA256 over the image */
static bool     ota_have_sig = false;

static void ota_write_chunk(uint32_t off, const uint8_t *d, uint8_t len) {
    uint32_t addr = SLOT_B_ADDR + off;
    flash_unlock();
    if (!(addr & (NVS_PAGE_SIZE - 1))) flash_erase_page(addr);
    FLASH->SR = 0xFFFFFFFF;          /* clear stale PROGERR/PGSERR/WRPERR */
    FLASH->CR |= FLASH_CR_PG;
    volatile uint32_t *dst = (volatile uint32_t *)addr;
    while (len) {
        uint8_t b[8] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
        uint8_t n = (len >= 8) ? 8 : len;
        for (uint8_t i = 0; i < n; i++) b[i] = *d++;
        /* Cortex-M0+ traps unaligned 32-bit loads -- build words by shifts.
         * The RS-485 payload sits at an odd offset inside rx_buf, so a
         * *(uint32_t*)ptr cast here HardFaults the MCU. */
        uint32_t w0 = (uint32_t)b[0]       | ((uint32_t)b[1] << 8)
                    | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
        uint32_t w1 = (uint32_t)b[4]       | ((uint32_t)b[5] << 8)
                    | ((uint32_t)b[6] << 16) | ((uint32_t)b[7] << 24);
        *dst++ = w0; __ISB(); *dst++ = w1;
        flash_wait(100);
        len -= n;
    }
    FLASH->CR &= ~FLASH_CR_PG;
}

static void process_frame(uint8_t *frame, uint8_t len) {
    uint8_t  dst  = frame[1];
    uint8_t  cmd  = frame[3];
    uint8_t  plen = frame[4];
    uint8_t *p    = &frame[5];
    uint8_t *uid = device_uid;
    uint8_t  buf[8];

    if (frame[5 + plen] != crc8(&frame[1], 4 + plen)) return;

    /* UID-addressed commands */
    if (cmd == CMD_WELCOME) {
        if (plen < 10) return;
        if (p[0]!=uid[0]||p[1]!=uid[1]||p[2]!=uid[2]||p[3]!=uid[3]) return;
        if (mode==MODE_REGISTERED &&
            (master_uid[0]||master_uid[1]||master_uid[2]||master_uid[3])) {
            if (p[6]!=master_uid[0]||p[7]!=master_uid[1]||
                p[8]!=master_uid[2]||p[9]!=master_uid[3])
                { send_frame(ADDR_MASTER,CMD_ERROR,uid,4); return; }
        }
        uint8_t new_addr = p[4];
        bool    new_r1   = (p[5] & 0x01) != 0;
        bool    new_r2   = (p[5] & 0x02) != 0;
        uint8_t m_uid[4] = {p[6],p[7],p[8],p[9]};
        save_registration(new_addr, m_uid);
        slot_address = new_addr;
        master_uid[0]=m_uid[0];master_uid[1]=m_uid[1];
        master_uid[2]=m_uid[2];master_uid[3]=m_uid[3];
        mode = MODE_REGISTERED;
        set_relay1(new_r1);
        set_relay2(new_r2);
        buf[0]=1; buf[1]=0;
        send_frame(ADDR_MASTER, CMD_PONG, buf, 2);
        last_poll_ms      = millis();
            last_announce_ms  = millis() + 30000UL;
        announce_interval = 2000;
        return;
    }

    if (cmd == CMD_REJECT) {
        if (plen < 4) return;
        if (p[0]!=uid[0]||p[1]!=uid[1]||p[2]!=uid[2]||p[3]!=uid[3]) return;
        announce_interval = 10000;
        return;
    }

    if (cmd == CMD_CHALLENGE) {
        /* payload: uid[4] nonce[8] */
        if (plen<12||p[0]!=uid[0]||p[1]!=uid[1]||p[2]!=uid[2]||p[3]!=uid[3]) return;
        uint8_t mac[8];
        compute_response(&p[4], 8, mac);
        uint8_t f[19]={SOF,ADDR_MASTER,ADDR_UNASSIGNED,CMD_RESPONSE,12,
            uid[0],uid[1],uid[2],uid[3],
            mac[0],mac[1],mac[2],mac[3],mac[4],mac[5],mac[6],mac[7],0,0};
        f[17]=crc8(&f[1],16);
        rs485_send(f,18); return;
    }

    /* Bus-address commands */
    bool for_me = (dst == slot_address) || (dst == ADDR_BCAST);
    if (!for_me) return;

    switch (cmd) {

    case CMD_PING:
        buf[0]=1; buf[1]=0;
        send_frame(ADDR_MASTER,CMD_PONG,buf,2);
        break;

    case CMD_GET_STATE:
        last_poll_ms  = millis();
            send_state_resp();
        break;

    case CMD_SET_RELAY:
        if (plen < 1) break;
        set_relay1((p[0] & 0x01) != 0);
        set_relay2((p[0] & 0x02) != 0);
        send_state_resp();
        break;

    case CMD_GET_INFO:
        buf[0]=nvs_shadow[NVS_HW_TYPE];
        buf[1]=nvs_shadow[NVS_HW_REV];
        buf[2]=FW_DESC[10]; buf[3]=FW_DESC[11]; buf[4]=FW_DESC[12];
        buf[5]=0; buf[6]=0; buf[7]=0;
        send_frame(ADDR_MASTER,CMD_INFO_RESP,buf,8);
        break;

    case CMD_DRAIN_EVENTS:
        if (plen>=1) { uint8_t _n=p[0];
          while(_n-->0&&event_count>0){event_tail=(event_tail+1)&7;event_count--;} }
        break;

    case CMD_BUS_QUIET:
        mode = MODE_QUIET;
        break;

    case CMD_OTA_BEGIN:
        /* payload: size[4] crc32[4] type[1] ver[3] */
        if(plen<12){buf[0]=0xFE;send_frame(ADDR_MASTER,CMD_OTA_ACK,buf,1);break;}
        /* Refuse an image built for different hardware, and refuse to run at
         * all if this unit was never provisioned. Checked before a single
         * byte is written, so a wrong image costs nothing. */
        if(nvs_shadow[NVS_HW_TYPE]==0xFF){
            buf[0]=0xFD;send_frame(ADDR_MASTER,CMD_OTA_ACK,buf,1);break;}
        if(p[8]!=nvs_shadow[NVS_HW_TYPE]){
            buf[0]=0xFC;send_frame(ADDR_MASTER,CMD_OTA_ACK,buf,1);break;}
        ota_total =((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3];
        ota_crc_ex=((uint32_t)p[4]<<24)|((uint32_t)p[5]<<16)|((uint32_t)p[6]<<8)|p[7];
        if(ota_total==0||ota_total>SLOT_SIZE){
            buf[0]=0xFB;send_frame(ADDR_MASTER,CMD_OTA_ACK,buf,1);break;}
        ota_ver[0]=p[9]; ota_ver[1]=p[10]; ota_ver[2]=p[11];
        ota_sec = (plen>=13) ? p[12] : 0;
        /* Refuse an image older than the security floor: a signed but
         * withdrawn build must not be reinstallable. */
        if (ota_sec < nvs_shadow[NVS_SEC_VER]) {
            buf[0]=0xFA; send_frame(ADDR_MASTER,CMD_OTA_ACK,buf,1); break;
        }
        for (uint8_t _i=0;_i<32;_i++) ota_sig[_i] = (plen>=45) ? p[13+_i] : 0;
        ota_have_sig = (plen>=45);
        ota_last_idx=0xFFFF;
        mode=MODE_OTA; buf[0]=0;
        send_frame(ADDR_MASTER,CMD_OTA_ACK,buf,1); break;

    case CMD_OTA_CHUNK:
        if(plen<3||mode!=MODE_OTA){buf[0]=0xFF;send_frame(ADDR_MASTER,CMD_OTA_ACK,buf,1);break;}
        {uint16_t ci=((uint16_t)p[0]<<8)|p[1];
         uint32_t off=(uint32_t)ci*OTA_CHUNK_SIZE;
         /* A retry re-sends a chunk we may already have programmed. Re-writing
          * un-erased flash raises PROGERR, so ACK duplicates without writing. */
         if(ci!=ota_last_idx && off+plen-2<=SLOT_SIZE){
             ota_write_chunk(off,&p[2],plen-2);
             ota_last_idx=ci;
         }
         buf[0]=0;buf[1]=p[0];buf[2]=p[1];
         send_frame(ADDR_MASTER,CMD_OTA_ACK,buf,3);}
        break;

    case CMD_OTA_END:
        {uint32_t crc=crc32_compute((const uint8_t*)SLOT_B_ADDR,ota_total);
         uint8_t mac[32];
         bool sig_ok=false;
         if (ota_have_sig) {
             hmac_sha256(&nvs_shadow[NVS_FW_KEY],
                         (const uint8_t*)SLOT_B_ADDR, ota_total, mac);
             sig_ok = ct_equal(mac, ota_sig, 32);
         }
         if(!sig_ok){
             /* CRC proves the image arrived intact; only the signature
              * proves it is ours. Unsigned or forged images are dropped
              * here, before the pending flag is ever raised. */
             buf[0]=0xF9; send_frame(ADDR_MASTER,CMD_OTA_ACK,buf,1);
             FLASH->CR|=FLASH_CR_LOCK; mode=MODE_REGISTERED; break;
         }
         if(crc==ota_crc_ex){
             buf[0]=0;send_frame(ADDR_MASTER,CMD_OTA_ACK,buf,1);
             /* Publish staging metadata, then raise the pending flag. The
              * bootloader re-validates type and CRC from this before it
              * overwrites the running image. */
             nvs_shadow[NVS_META_MAGIC]  = META_MAGIC_VAL;
             nvs_shadow[NVS_META_TYPE]   = nvs_shadow[NVS_HW_TYPE];
             nvs_shadow[NVS_META_VER+0]  = ota_ver[0];
             nvs_shadow[NVS_META_VER+1]  = ota_ver[1];
             nvs_shadow[NVS_META_VER+2]  = ota_ver[2];
             nvs_shadow[NVS_META_SEC]    = ota_sec;
             nvs_shadow[NVS_META_SIZE+0] = (uint8_t)(ota_total & 0xFF);
             nvs_shadow[NVS_META_SIZE+1] = (uint8_t)((ota_total >> 8) & 0xFF);
             nvs_shadow[NVS_META_CRC+0]  = (uint8_t)(ota_crc_ex & 0xFF);
             nvs_shadow[NVS_META_CRC+1]  = (uint8_t)((ota_crc_ex >> 8) & 0xFF);
             nvs_shadow[NVS_META_CRC+2]  = (uint8_t)((ota_crc_ex >> 16) & 0xFF);
             nvs_shadow[NVS_META_CRC+3]  = (uint8_t)((ota_crc_ex >> 24) & 0xFF);
             nvs_shadow[NVS_OTA_FLAG]    = UPDATE_PENDING;
             nvs_flush();
             delay(50);NVIC_SystemReset();
         }else{
             buf[0]=1;send_frame(ADDR_MASTER,CMD_OTA_ACK,buf,1);
             FLASH->CR|=FLASH_CR_LOCK;
             mode=MODE_REGISTERED;
         }}
        break;

    default:
        buf[0]=cmd; buf[1]=0x01;
        send_frame(ADDR_MASTER, CMD_ERROR, buf, 2);
        break;
    }
}

/* ================================================================
 * BUS RX (non-blocking)
 * ================================================================ */
static void bus_rx_tick(void) {
    while (usart1_available()) {
        uint8_t b = usart1_read_byte();
        if (rx_pos == 0) {
            if (b == SOF) rx_buf[rx_pos++] = b;
        } else {
            if (rx_pos >= 56) { rx_pos=0; rx_elen=0; return; }
            rx_buf[rx_pos++] = b;
            if (rx_pos == 5) rx_elen = 6 + rx_buf[4];
            if (rx_elen > 0 && rx_pos >= rx_elen) {
                process_frame(rx_buf, rx_pos);
                rx_pos=0; rx_elen=0;
            }
        }
    }
}

/* ================================================================
 * LED BLINK HELPER + STARTUP BLINK
 * ================================================================ */


/* ================================================================
 * SETUP
 * ================================================================ */
void setup() {
    gpio_init();
    tim17_pwm_init();
    usart1_init();
    /* Seed random from UID */
    uid_init();
    load_state();
    /* Boot relay state:
     * Registered to a real master --> boot OFF, master restores on first poll
     * Standalone (no master_uid)  --> restore from NVS */
    { bool has_master = (master_uid[0]||master_uid[1]||
                         master_uid[2]||master_uid[3]);
      if (mode == MODE_REGISTERED && has_master) {
          relay1_state = false; relay2_state = false;
          set_relay1(false); set_relay2(false);
      } else {
          set_relay1(relay1_state);
          set_relay2(relay2_state);
      }
    }
    last_poll_ms = millis();
}

/* ================================================================
 * LOOP
 * ================================================================ */
void loop() {
    handle_touch();
    nvs_tick();    /* commit any debounced relay-state write */

    bus_rx_tick(); /* always process bus including during OTA */

    switch (mode) {

    case MODE_UNREGISTERED:
        if ((millis() - last_announce_ms) >= announce_interval) {
            last_announce_ms  = millis();
            announce_interval = 2000 + (device_uid[3] & 0xFF);
            send_announce();
        }
        break;

    case MODE_REGISTERED:
        if ((millis() - last_poll_ms) > ORPHAN_TIMEOUT_MS &&
             millis() > ORPHAN_TIMEOUT_MS) {
            self_unregister();
        }
        break;

    case MODE_OTA:
        break;

    case MODE_QUIET:
        bus_rx_tick();
        break;
    }

    /* Hardware PWM breathing on LED3 */
    breath_tick();
}
