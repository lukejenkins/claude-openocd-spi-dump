# MCU Register Reference for SPI Flash Dumping

This reference provides detailed register maps for common MCU families used in SPI flash dumping operations.

## Atmel/Microchip SAM4S Series

**Example parts:** ATSAM4S2A, ATSAM4S4A, ATSAM4S8B, ATSAM4SD32

### Memory Map

| Region | Address | Size |
|--------|---------|------|
| Flash | 0x00400000 | 128KB-2MB |
| SRAM | 0x20000000 | 64KB-160KB |
| Peripherals | 0x40000000 | - |

### SPI Peripheral (SPI0)

**Base Address:** 0x40008000

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | SPI_CR | Control Register |
| 0x04 | SPI_MR | Mode Register |
| 0x08 | SPI_RDR | Receive Data Register |
| 0x0C | SPI_TDR | Transmit Data Register |
| 0x10 | SPI_SR | Status Register |
| 0x30 | SPI_CSR0 | Chip Select Register 0 |

**SPI_CR bits:**
- Bit 0: SPIEN (SPI Enable)
- Bit 1: SPIDIS (SPI Disable)

**SPI_MR bits:**
- Bit 0: MSTR (Master Mode)
- Bit 4: MODFDIS (Mode Fault Detection Disable)
- Bits 16-19: PCS (Peripheral Chip Select) - **CRITICAL: Must not be 0xF**

**SPI_SR bits:**
- Bit 0: RDRF (Receive Data Register Full)
- Bit 1: TDRE (Transmit Data Register Empty)

**SPI_MR initialization (CRITICAL):**
```c
#define SPI_MR_MSTR      (1 << 0)
#define SPI_MR_MODFDIS   (1 << 4)
#define SPI_MR_PCS_NPCS0 (0x0E << 16)  // Select NPCS0, NOT 0xF!

SPI_MR = SPI_MR_MSTR | SPI_MR_MODFDIS | SPI_MR_PCS_NPCS0;
```

### GPIO (PIOA)

**Base Address:** 0x400E0E00

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | PIO_PER | PIO Enable (reclaim from peripheral) |
| 0x10 | PIO_OER | Output Enable |
| 0x30 | PIO_SODR | Set Output Data (pin high) |
| 0x34 | PIO_CODR | Clear Output Data (pin low) |

**Common SPI0 pins:**
- PA11: NPCS0 (Chip Select)
- PA12: MISO
- PA13: MOSI
- PA14: SPCK

### Watchdog Timer

**Base Address:** 0x400E1450

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | WDT_CR | Control Register |
| 0x04 | WDT_MR | Mode Register |

**Feed watchdog:**
```c
#define WDT_CR_KEY    (0xA5 << 24)
#define WDT_CR_WDRSTT (1 << 0)
WDT_CR = WDT_CR_KEY | WDT_CR_WDRSTT;
```

---

## Atmel/Microchip SAM3X Series

**Example parts:** ATSAM3X8E (Arduino Due), ATSAM3X8H

### Memory Map

| Region | Address | Size |
|--------|---------|------|
| Flash | 0x00080000 | 256KB-512KB |
| SRAM0 | 0x20000000 | 64KB |
| SRAM1 | 0x20080000 | 32KB |
| Peripherals | 0x40000000 | - |

### SPI Peripheral (SPI0)

**Base Address:** 0x40008000 (same as SAM4S)

Register layout identical to SAM4S. Same PCS requirement applies.

### GPIO (PIOA/PIOB)

**PIOA Base:** 0x400E0E00
**PIOB Base:** 0x400E1000

Register layout identical to SAM4S.

---

## STM32F1 Series

**Example parts:** STM32F103C8 (Blue Pill), STM32F103RB

### Memory Map

| Region | Address | Size |
|--------|---------|------|
| Flash | 0x08000000 | 64KB-512KB |
| SRAM | 0x20000000 | 20KB-96KB |
| Peripherals | 0x40000000 | - |

### SPI Peripheral (SPI1)

**Base Address:** 0x40013000

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | SPI_CR1 | Control Register 1 |
| 0x04 | SPI_CR2 | Control Register 2 |
| 0x08 | SPI_SR | Status Register |
| 0x0C | SPI_DR | Data Register (shared TX/RX) |

**SPI_CR1 bits:**
- Bit 0: CPHA (Clock Phase)
- Bit 1: CPOL (Clock Polarity)
- Bit 2: MSTR (Master Mode)
- Bits 3-5: BR (Baud Rate)
- Bit 6: SPE (SPI Enable)
- Bit 8: SSI (Internal Slave Select)
- Bit 9: SSM (Software Slave Management)

**SPI_SR bits:**
- Bit 0: RXNE (RX Not Empty)
- Bit 1: TXE (TX Empty)
- Bit 7: BSY (Busy)

**SPI_CR1 initialization:**
```c
#define SPI_CR1_MSTR  (1 << 2)
#define SPI_CR1_SPE   (1 << 6)
#define SPI_CR1_SSI   (1 << 8)
#define SPI_CR1_SSM   (1 << 9)
#define SPI_CR1_BR_4  (1 << 3)  // fPCLK/4

SPI_CR1 = SPI_CR1_MSTR | SPI_CR1_SSI | SPI_CR1_SSM | SPI_CR1_BR_4 | SPI_CR1_SPE;
```

### GPIO (GPIOA)

**Base Address:** 0x40010800

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | GPIOx_CRL | Config Low (pins 0-7) |
| 0x04 | GPIOx_CRH | Config High (pins 8-15) |
| 0x10 | GPIOx_BSRR | Bit Set/Reset (set) |
| 0x14 | GPIOx_BRR | Bit Reset (clear) |

**Common SPI1 pins:**
- PA4: NSS (Chip Select)
- PA5: SCK
- PA6: MISO
- PA7: MOSI

### Independent Watchdog (IWDG)

**Base Address:** 0x40003000

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | IWDG_KR | Key Register |

**Feed watchdog:**
```c
#define IWDG_KEY_RELOAD 0xAAAA
IWDG_KR = IWDG_KEY_RELOAD;
```

---

## STM32F4 Series

**Example parts:** STM32F407VG, STM32F411CE, STM32F446RE

### Memory Map

| Region | Address | Size |
|--------|---------|------|
| Flash | 0x08000000 | 512KB-2MB |
| SRAM | 0x20000000 | 128KB-256KB |
| CCM SRAM | 0x10000000 | 64KB (F4x7/F4x9) |
| Peripherals | 0x40000000 | - |

### SPI Peripheral (SPI1)

**Base Address:** 0x40013000

Same register layout as STM32F1, with additional features:
- Bit 11: CRCEN (CRC Enable)
- Bits 12-13: DFF (Data Frame Format, 8/16-bit)

### GPIO (GPIOA)

**Base Address:** 0x40020000

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | GPIOx_MODER | Mode Register |
| 0x18 | GPIOx_BSRR | Bit Set/Reset |

**GPIO_BSRR usage (set/reset in one register):**
```c
// Set pin (bits 0-15)
GPIOA_BSRR = (1 << pin);

// Reset pin (bits 16-31)
GPIOA_BSRR = (1 << (pin + 16));
```

**Common SPI1 pins:**
- PA4: NSS
- PA5: SCK
- PA6: MISO
- PA7: MOSI

---

## Nordic nRF52 Series

**Example parts:** nRF52832, nRF52840, nRF52833

### Memory Map

| Region | Address | Size |
|--------|---------|------|
| Flash | 0x00000000 | 256KB-1MB |
| SRAM | 0x20000000 | 64KB-256KB |
| Peripherals | 0x40000000 | - |

### SPI Peripheral (SPIM0)

**Base Address:** 0x40003000

The nRF52 uses EasyDMA for SPI transfers:

| Offset | Register | Description |
|--------|----------|-------------|
| 0x010 | TASKS_START | Start SPI transaction |
| 0x014 | TASKS_STOP | Stop SPI transaction |
| 0x104 | EVENTS_STOPPED | Transaction stopped |
| 0x110 | EVENTS_END | End of transfer |
| 0x500 | ENABLE | Enable SPIM (7=enable) |
| 0x508 | PSEL.SCK | Pin select for SCK |
| 0x50C | PSEL.MOSI | Pin select for MOSI |
| 0x510 | PSEL.MISO | Pin select for MISO |
| 0x524 | FREQUENCY | SPI frequency |
| 0x534 | TXD.PTR | TX buffer pointer |
| 0x538 | TXD.MAXCNT | TX buffer length |
| 0x544 | RXD.PTR | RX buffer pointer |
| 0x548 | RXD.MAXCNT | RX buffer length |

**Simplified single-byte transfer:**
```c
static uint8_t tx_buf, rx_buf;

uint8_t spi_transfer(uint8_t data) {
    tx_buf = data;
    SPIM_TXD_PTR = (uint32_t)&tx_buf;
    SPIM_TXD_MAXCNT = 1;
    SPIM_RXD_PTR = (uint32_t)&rx_buf;
    SPIM_RXD_MAXCNT = 1;
    SPIM_EVENTS_END = 0;
    SPIM_TASKS_START = 1;
    while (!SPIM_EVENTS_END);
    return rx_buf;
}
```

### GPIO (P0)

**Base Address:** 0x50000000

| Offset | Register | Description |
|--------|----------|-------------|
| 0x504 | OUT | Output value |
| 0x508 | OUTSET | Set output |
| 0x50C | OUTCLR | Clear output |
| 0x514 | DIR | Direction |
| 0x518 | DIRSET | Set direction to output |

---

## NXP LPC1768

**Example parts:** LPC1768, LPC1769

### Memory Map

| Region | Address | Size |
|--------|---------|------|
| Flash | 0x00000000 | 512KB |
| SRAM | 0x10000000 | 32KB |
| AHB SRAM | 0x2007C000 | 32KB |
| Peripherals | 0x40000000 | - |

**Note:** SRAM starts at 0x10000000, not 0x20000000!

### SPI Peripheral (SSP0)

**Base Address:** 0x40088000

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | SSPCR0 | Control Register 0 |
| 0x04 | SSPCR1 | Control Register 1 |
| 0x08 | SSPDR | Data Register |
| 0x0C | SSPSR | Status Register |

**SSPCR0 bits:**
- Bits 0-3: DSS (Data Size Select, 0x7 = 8-bit)
- Bits 4-5: FRF (Frame Format, 0 = SPI)
- Bit 6: CPOL
- Bit 7: CPHA
- Bits 8-15: SCR (Serial Clock Rate)

**SSPCR1 bits:**
- Bit 1: SSE (SSP Enable)
- Bit 2: MS (Master/Slave, 0 = Master)

**SSPSR bits:**
- Bit 0: TFE (TX FIFO Empty)
- Bit 2: RNE (RX FIFO Not Empty)

**SSP initialization:**
```c
#define SSPCR0_DSS_8BIT  0x7
#define SSPCR1_SSE       (1 << 1)

SSPCR0 = SSPCR0_DSS_8BIT;
SSPCR1 = SSPCR1_SSE;
```

### GPIO

**Base Address:** 0x2009C000

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | FIODIR | Direction |
| 0x14 | FIOPIN | Pin value |
| 0x18 | FIOSET | Set output |
| 0x1C | FIOCLR | Clear output |

**Port offset:** Each port is 0x20 bytes apart.

---

## Cortex-M System Registers

These registers are common across all Cortex-M MCUs.

### System Control Block (SCB)

**Base Address:** 0xE000ED00

| Offset | Register | Description |
|--------|----------|-------------|
| 0x08 | SCB_VTOR | Vector Table Offset Register |

**CRITICAL - Set VTOR for RAM execution:**
```c
#define SCB_VTOR (*((volatile uint32_t *)0xE000ED08))
SCB_VTOR = 0x20000000;  // Point to SRAM vector table
```

### SysTick Timer

**Base Address:** 0xE000E010

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | SYST_CSR | Control and Status |
| 0x04 | SYST_RVR | Reload Value |
| 0x08 | SYST_CVR | Current Value |

---

## Adding New MCU Families

To add support for a new MCU:

1. **Find datasheet** - Search for MCU part number + datasheet
2. **Locate memory map** - Find SRAM base address and size
3. **Find SPI section** - Look for "SPI" or "Serial Peripheral Interface"
4. **Document registers:**
   - Control register (enable/disable)
   - Mode register (master, clock settings)
   - Data registers (TX/RX)
   - Status register (TX empty, RX full bits)
5. **Find GPIO section** - Look for "GPIO" or "PIO"
6. **Document pin control:**
   - Direction register
   - Set/clear output registers
7. **Check watchdog** - Find feed/disable mechanism

Use the patterns from existing MCUs as templates—the core SPI algorithm is the same, only addresses differ.
