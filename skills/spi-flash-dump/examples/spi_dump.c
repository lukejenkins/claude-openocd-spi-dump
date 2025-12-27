/**
 * RAM-Resident SPI Flash Dumper Template
 *
 * This template provides a complete, working SPI flash reader that runs
 * from SRAM. Customize the register addresses for your target MCU.
 *
 * Target: [YOUR MCU HERE - e.g., ATSAM4S2A]
 *
 * Usage:
 *   1. Update register addresses for your MCU (see sections marked CUSTOMIZE)
 *   2. Compile: arm-none-eabi-gcc -mcpu=cortex-m4 -mthumb -Os -ffreestanding \
 *              -nostdlib -T spi_dump.ld -o spi_dump.elf spi_dump.c
 *   3. Convert: arm-none-eabi-objcopy -O binary spi_dump.elf spi_dump.bin
 *   4. Load via OpenOCD and execute
 */

#include <stdint.h>

/*===========================================================================
 * CUSTOMIZE: Memory Layout for Your MCU
 *===========================================================================*/

#define SRAM_BASE       0x20000000
#define SRAM_SIZE       0x10000     /* 64KB - adjust for your MCU */
#define STACK_TOP       (SRAM_BASE + SRAM_SIZE - 0x100)  /* 256 bytes for comm */
#define COMM_BASE       (SRAM_BASE + SRAM_SIZE - 0x100)  /* Communication area */

/*===========================================================================
 * CUSTOMIZE: SPI Peripheral Registers for Your MCU
 *
 * Example values shown for SAM4S. See references/mcu-registers.md for other MCUs.
 *===========================================================================*/

/* SPI Base Address */
#define SPI_BASE        0x40008000

/* SPI Register Offsets */
#define SPI_CR_OFFSET   0x00    /* Control Register */
#define SPI_MR_OFFSET   0x04    /* Mode Register */
#define SPI_RDR_OFFSET  0x08    /* Receive Data Register */
#define SPI_TDR_OFFSET  0x0C    /* Transmit Data Register */
#define SPI_SR_OFFSET   0x10    /* Status Register */

/* SPI Control Register Bits */
#define SPI_CR_SPIEN    (1 << 0)    /* SPI Enable */
#define SPI_CR_SPIDIS   (1 << 1)    /* SPI Disable */

/* SPI Mode Register Bits (SAM4S specific) */
#define SPI_MR_MSTR     (1 << 0)    /* Master Mode */
#define SPI_MR_MODFDIS  (1 << 4)    /* Mode Fault Detection Disable */
#define SPI_MR_PCS_NPCS0 (0x0E << 16) /* Select NPCS0 - CRITICAL for SAM4S! */

/* SPI Status Register Bits */
#define SPI_SR_RDRF_BIT 0           /* Receive Data Register Full */
#define SPI_SR_TDRE_BIT 1           /* Transmit Data Register Empty */

/*===========================================================================
 * CUSTOMIZE: GPIO Registers for Chip Select
 *
 * Example values shown for SAM4S PIOA. Adjust for your MCU.
 *===========================================================================*/

#define GPIO_BASE       0x400E0E00  /* PIOA base for SAM4S */
#define GPIO_PER_OFFSET 0x00        /* PIO Enable Register */
#define GPIO_OER_OFFSET 0x10        /* Output Enable Register */
#define GPIO_SODR_OFFSET 0x30       /* Set Output Data Register */
#define GPIO_CODR_OFFSET 0x34       /* Clear Output Data Register */

#define CS_PIN          11          /* PA11 for SAM4S SPI0 */

/*===========================================================================
 * CUSTOMIZE: Watchdog Timer (optional)
 *===========================================================================*/

#define HAS_WATCHDOG    1           /* Set to 0 if no watchdog or already disabled */
#define WDT_BASE        0x400E1450  /* SAM4S WDT base */
#define WDT_CR_OFFSET   0x00
#define WDT_FEED_VALUE  0xA5000001  /* SAM4S: KEY + WDRSTT */

/*===========================================================================
 * System Control Block (same for all Cortex-M)
 *===========================================================================*/

#define SCB_VTOR        0xE000ED08

/*===========================================================================
 * Communication Protocol
 *===========================================================================*/

/* Communication Area Offsets */
#define COMM_STATUS_OFFSET      0x00
#define COMM_FLASH_ADDR_OFFSET  0x04
#define COMM_SIZE_OFFSET        0x08
#define COMM_DEST_OFFSET        0x0C
#define COMM_JEDEC_ID_OFFSET    0x10
#define COMM_ERROR_OFFSET       0x14
#define COMM_HEARTBEAT_OFFSET   0x18    /* Increments in main loop - proves code is running */

/* Status Values */
#define STATUS_IDLE     0x00000000
#define STATUS_BUSY     0x00000001
#define STATUS_DONE     0x00000002
#define STATUS_ERROR    0xDEAD0000

/* Command Values */
#define CMD_NOP         0x00000000
#define CMD_READ_FLASH  0x00000010
#define CMD_GET_JEDEC   0x00000020
#define CMD_EXIT        0x000000FF

/* SPI Flash Commands */
#define FLASH_CMD_READ_DATA     0x03
#define FLASH_CMD_READ_JEDEC_ID 0x9F

/* Flash Size (adjust for your flash chip) */
#define FLASH_SIZE      0x400000    /* 4MB */

/*===========================================================================
 * Register Access Macros
 *===========================================================================*/

#define REG32(addr)     (*(volatile uint32_t *)(addr))

#define SPI_CR          REG32(SPI_BASE + SPI_CR_OFFSET)
#define SPI_MR          REG32(SPI_BASE + SPI_MR_OFFSET)
#define SPI_RDR         REG32(SPI_BASE + SPI_RDR_OFFSET)
#define SPI_TDR         REG32(SPI_BASE + SPI_TDR_OFFSET)
#define SPI_SR          REG32(SPI_BASE + SPI_SR_OFFSET)

#define GPIO_PER        REG32(GPIO_BASE + GPIO_PER_OFFSET)
#define GPIO_OER        REG32(GPIO_BASE + GPIO_OER_OFFSET)
#define GPIO_SODR       REG32(GPIO_BASE + GPIO_SODR_OFFSET)
#define GPIO_CODR       REG32(GPIO_BASE + GPIO_CODR_OFFSET)

#define CS_MASK         (1 << CS_PIN)

#define COMM_STATUS     REG32(COMM_BASE + COMM_STATUS_OFFSET)
#define COMM_FLASH_ADDR REG32(COMM_BASE + COMM_FLASH_ADDR_OFFSET)
#define COMM_SIZE_REG   REG32(COMM_BASE + COMM_SIZE_OFFSET)
#define COMM_DEST       REG32(COMM_BASE + COMM_DEST_OFFSET)
#define COMM_JEDEC_ID   REG32(COMM_BASE + COMM_JEDEC_ID_OFFSET)
#define COMM_ERROR      REG32(COMM_BASE + COMM_ERROR_OFFSET)
#define COMM_HEARTBEAT  REG32(COMM_BASE + COMM_HEARTBEAT_OFFSET)

#define SCB_VTOR_REG    REG32(SCB_VTOR)

#if HAS_WATCHDOG
#define WDT_CR          REG32(WDT_BASE + WDT_CR_OFFSET)
#endif

/*===========================================================================
 * Helper Functions
 *===========================================================================*/

static inline void feed_watchdog(void) {
#if HAS_WATCHDOG
    WDT_CR = WDT_FEED_VALUE;
#endif
}

static inline void cs_low(void) {
    GPIO_CODR = CS_MASK;
}

static inline void cs_high(void) {
    GPIO_SODR = CS_MASK;
}

/*===========================================================================
 * SPI Functions
 *===========================================================================*/

static uint8_t spi_transfer(uint8_t data) {
    /* Wait for TX ready */
    while (!(SPI_SR & (1 << SPI_SR_TDRE_BIT)));

    /* Send byte */
    SPI_TDR = data;

    /* Wait for RX complete */
    while (!(SPI_SR & (1 << SPI_SR_RDRF_BIT)));

    /* Return received byte */
    return (uint8_t)SPI_RDR;
}

static void spi_init(void) {
    /* Disable SPI first */
    SPI_CR = SPI_CR_SPIDIS;

    /* Configure SPI: Master mode, NPCS0 selected */
    SPI_MR = SPI_MR_MSTR | SPI_MR_MODFDIS | SPI_MR_PCS_NPCS0;

    /* Enable SPI */
    SPI_CR = SPI_CR_SPIEN;

    /* Configure CS pin as GPIO output */
    GPIO_PER = CS_MASK;     /* Enable PIO control */
    GPIO_OER = CS_MASK;     /* Enable output */

    /* Ensure CS starts high (deselected) */
    cs_high();
}

/*===========================================================================
 * Flash Operations
 *===========================================================================*/

static uint32_t read_jedec_id(void) {
    uint32_t id;

    cs_low();
    spi_transfer(FLASH_CMD_READ_JEDEC_ID);
    id = spi_transfer(0x00) << 16;
    id |= spi_transfer(0x00) << 8;
    id |= spi_transfer(0x00);
    cs_high();

    return id;
}

static void read_flash(uint32_t flash_addr, uint8_t *dest, uint32_t size) {
    uint32_t i;

    cs_low();

    /* Send READ command + 24-bit address */
    spi_transfer(FLASH_CMD_READ_DATA);
    spi_transfer((flash_addr >> 16) & 0xFF);
    spi_transfer((flash_addr >> 8) & 0xFF);
    spi_transfer(flash_addr & 0xFF);

    /* Read data bytes */
    for (i = 0; i < size; i++) {
        dest[i] = spi_transfer(0x00);

        /* Feed watchdog every 4KB */
        if ((i & 0xFFF) == 0) {
            feed_watchdog();
        }
    }

    cs_high();
}

/*===========================================================================
 * Main Entry Point
 *===========================================================================*/

void spi_dump_main(void) {
    uint32_t cmd;

    /* CRITICAL: Set VTOR to point to our vector table in SRAM */
    SCB_VTOR_REG = SRAM_BASE;

    /* Initialize communication area */
    COMM_STATUS = STATUS_IDLE;
    COMM_JEDEC_ID = 0;
    COMM_ERROR = 0;
    COMM_HEARTBEAT = 0;

    /* Initialize SPI peripheral */
    spi_init();

    /* Main command loop */
    while (1) {
        feed_watchdog();

        /* Increment heartbeat - proves main loop is running */
        COMM_HEARTBEAT++;

        cmd = COMM_STATUS;

        if (cmd == CMD_READ_FLASH) {
            /* Read flash data */
            COMM_STATUS = STATUS_BUSY;

            uint32_t addr = COMM_FLASH_ADDR;
            uint32_t size = COMM_SIZE_REG;
            uint8_t *dest = (uint8_t *)COMM_DEST;

            /* Validate parameters */
            if (size > 0x10000 || addr + size > FLASH_SIZE) {
                COMM_ERROR = 0x0001;
                COMM_STATUS = STATUS_ERROR | 0x0001;
                continue;
            }

            read_flash(addr, dest, size);
            COMM_STATUS = STATUS_DONE;

        } else if (cmd == CMD_GET_JEDEC) {
            /* Read JEDEC ID */
            COMM_STATUS = STATUS_BUSY;
            COMM_JEDEC_ID = read_jedec_id();
            COMM_STATUS = STATUS_DONE;

        } else if (cmd == CMD_EXIT) {
            /* Exit loop */
            COMM_STATUS = STATUS_DONE;
            break;
        }

        /* Small delay to reduce polling overhead */
        for (volatile int i = 0; i < 100; i++);
    }
}

/*===========================================================================
 * Exception Handlers
 *===========================================================================*/

void __attribute__((naked)) fault_handler(void) {
    __asm volatile (
        "mov r0, #0xFA\n"       /* Marker: 0xFA17 = "FAIT" (fault) */
        "lsl r0, r0, #8\n"
        "orr r0, #0x17\n"
        "1: b 1b\n"             /* Infinite loop */
    );
}

/*===========================================================================
 * Vector Table
 *
 * CRITICAL: This must be placed at SRAM_BASE and VTOR must point here.
 *===========================================================================*/

__attribute__((section(".vectors")))
const uint32_t vectors[] = {
    STACK_TOP,                          /* 0x00: Initial stack pointer */
    (uint32_t)spi_dump_main + 1,        /* 0x04: Reset vector (+1 for Thumb) */
    (uint32_t)fault_handler + 1,        /* 0x08: NMI */
    (uint32_t)fault_handler + 1,        /* 0x0C: HardFault */
    (uint32_t)fault_handler + 1,        /* 0x10: MemManage */
    (uint32_t)fault_handler + 1,        /* 0x14: BusFault */
    (uint32_t)fault_handler + 1,        /* 0x18: UsageFault */
    0, 0, 0, 0,                         /* 0x1C-0x28: Reserved */
    (uint32_t)fault_handler + 1,        /* 0x2C: SVCall */
    (uint32_t)fault_handler + 1,        /* 0x30: Debug Monitor */
    0,                                  /* 0x34: Reserved */
    (uint32_t)fault_handler + 1,        /* 0x38: PendSV */
    (uint32_t)fault_handler + 1,        /* 0x3C: SysTick */
};
