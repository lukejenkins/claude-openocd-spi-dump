/**
 * RAM-Resident SPI Flash Dumper - Linker Script Template
 *
 * This script places all code and data in SRAM for execution via OpenOCD.
 * Customize the memory addresses for your target MCU.
 *
 * Memory Layout:
 *   SRAM_BASE + 0x0000     Vector table (64 bytes)
 *   SRAM_BASE + 0x0040     Code and rodata
 *   BUFFER_ADDR            Read buffer (4KB default)
 *   STACK_TOP - 0x100      Stack (grows down)
 *   COMM_BASE              Communication area (256 bytes)
 */

/*===========================================================================
 * CUSTOMIZE: Memory Addresses for Your MCU
 *
 * These can also be passed from command line:
 *   -Wl,--defsym,__sram_base=0x20000000
 *===========================================================================*/

/* Default values - override with -Wl,--defsym if needed */
PROVIDE(__sram_base = 0x20000000);   /* SRAM start address */
PROVIDE(__sram_size = 0x10000);      /* 64KB - adjust for your MCU */
PROVIDE(__code_size = 0xE000);       /* Max code size (~56KB) */
PROVIDE(__buffer_size = 0x1000);     /* 4KB read buffer */
PROVIDE(__stack_size = 0x100);       /* 256 bytes stack */
PROVIDE(__comm_size = 0x100);        /* 256 bytes communication area */

/*===========================================================================
 * Memory Regions
 *===========================================================================*/

MEMORY
{
    /* Code region at start of SRAM */
    CODE (rwx) : ORIGIN = __sram_base, LENGTH = __code_size

    /* Data buffer for flash reads */
    BUFFER (rw) : ORIGIN = __sram_base + __code_size, LENGTH = __buffer_size

    /* Stack region (grows downward) */
    STACK (rw) : ORIGIN = __sram_base + __sram_size - __comm_size - __stack_size,
                 LENGTH = __stack_size

    /* Communication area at end of SRAM */
    COMM (rw) : ORIGIN = __sram_base + __sram_size - __comm_size, LENGTH = __comm_size
}

/*===========================================================================
 * Entry Point
 *===========================================================================*/

ENTRY(spi_dump_main)

/*===========================================================================
 * Sections
 *===========================================================================*/

SECTIONS
{
    /* Vector table must be at very start of SRAM */
    .vectors : ALIGN(4)
    {
        KEEP(*(.vectors))
    } > CODE

    /* Code */
    .text : ALIGN(4)
    {
        *(.text*)
        *(.rodata*)
    } > CODE

    /* Initialized data - in CODE region since we're RAM-only */
    .data : ALIGN(4)
    {
        *(.data*)
    } > CODE

    /* Uninitialized data */
    .bss : ALIGN(4)
    {
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    } > CODE

    /* Provide symbols for runtime use */
    __stack_top = ORIGIN(STACK) + LENGTH(STACK);
    __comm_base = ORIGIN(COMM);
    __buffer_base = ORIGIN(BUFFER);

    /* Discard unneeded sections */
    /DISCARD/ :
    {
        *(.ARM.exidx*)
        *(.ARM.extab*)
        *(.comment)
        *(.note*)
    }
}

/*===========================================================================
 * Exported Symbols
 *===========================================================================*/

PROVIDE(_estack = __stack_top);
PROVIDE(_sbss = __bss_start);
PROVIDE(_ebss = __bss_end);
