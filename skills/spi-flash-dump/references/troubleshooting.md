# Troubleshooting SPI Flash Dump Operations

This reference provides detailed troubleshooting guidance for common issues encountered when dumping SPI flash through a microcontroller via OpenOCD.

## Issue Categories

1. [Execution Failures](#execution-failures) - Code won't run or crashes
2. [SPI Communication Issues](#spi-communication-issues) - SPI transfers fail
3. [JEDEC ID Problems](#jedec-id-problems) - Unexpected ID values
4. [OpenOCD Issues](#openocd-issues) - Command and connection problems
5. [Data Integrity Issues](#data-integrity-issues) - Dump appears corrupted

---

## Execution Failures

### HardFault Immediately After Resume

**Symptoms:**
- CPU enters HardFault exception immediately
- PC register shows address in flash (e.g., 0x0040xxxx)
- Code never reaches main function

**Cause:** VTOR (Vector Table Offset Register) still points to flash. When any exception occurs, CPU jumps to flash vector table instead of SRAM.

**Solution:**
```c
// At the very start of main function:
#define SCB_VTOR (*((volatile uint32_t *)0xE000ED08))
SCB_VTOR = 0x20000000;  // Point to SRAM vector table
```

**Verification:**
```tcl
# In OpenOCD, check VTOR after init:
mdw 0xE000ED08
# Should show 0x20000000, not 0x00000000 or flash address
```

### HardFault with PC in SRAM

**Symptoms:**
- HardFault with PC showing SRAM address
- Register dump shows unusual values

**Causes and solutions:**

1. **Stack overflow** - Increase stack size in linker script
2. **Invalid memory access** - Check pointer arithmetic
3. **Unaligned access** - Ensure 4-byte alignment for word access
4. **Missing vector table entries** - Provide full 16-entry vector table

**Vector table template:**
```c
__attribute__((section(".vectors")))
const uint32_t vectors[] = {
    STACK_TOP,                          // 0x00: Initial SP
    (uint32_t)main_func + 1,            // 0x04: Reset (Thumb mode)
    (uint32_t)fault_handler + 1,        // 0x08: NMI
    (uint32_t)fault_handler + 1,        // 0x0C: HardFault
    (uint32_t)fault_handler + 1,        // 0x10: MemManage
    (uint32_t)fault_handler + 1,        // 0x14: BusFault
    (uint32_t)fault_handler + 1,        // 0x18: UsageFault
    0, 0, 0, 0,                         // 0x1C-0x28: Reserved
    (uint32_t)fault_handler + 1,        // 0x2C: SVCall
    (uint32_t)fault_handler + 1,        // 0x30: Debug Monitor
    0,                                  // 0x34: Reserved
    (uint32_t)fault_handler + 1,        // 0x38: PendSV
    (uint32_t)fault_handler + 1,        // 0x3C: SysTick
};
```

### Code Doesn't Start Executing

**Symptoms:**
- No HardFault, but code doesn't run
- Status area remains uninitialized (0xFFFFFFFF or 0x00000000)

**Causes and solutions:**

1. **Wrong PC value** - Ensure Thumb bit is set (+1):
   ```tcl
   # Read reset vector from loaded binary
   set pc [read_word 0x20000004]
   reg pc $pc  # Should have bit 0 set
   ```

2. **Wrong SP value** - Set stack pointer before resume:
   ```tcl
   set sp [read_word 0x20000000]
   reg sp $sp
   ```

3. **CPU still halted** - Issue resume command:
   ```tcl
   resume
   ```

### Code Stuck Polling SPI Status

**Symptoms:**
- PC shows address in SPI transfer function (e.g., 0x2000004a)
- Status register never changes from the command value you wrote
- Code appears to hang but doesn't fault
- Different flash addresses all return the same data

**Cause:** The dumper was started at the wrong address, skipping initialization. The `spi_init()` function never ran, so:
- SPI peripheral is not configured
- GPIO for chip select is not set up
- Code is stuck waiting for SPI_SR_TDRE which never gets set

**This commonly happens when you set PC to an arbitrary address instead of reading it from the vector table.**

**Wrong approach:**
```tcl
# WRONG - hardcoded address skips initialization!
load_image spi_dump.bin 0x20000000 bin
reg pc 0x20000041
resume
```

**Correct approach:**
```tcl
# RIGHT - read SP and PC from the loaded binary's vector table
load_image spi_dump.bin 0x20000000 bin

# Read Initial SP from offset 0x00
mem2array sp_arr 32 0x20000000 1
reg sp $sp_arr(0)

# Read Reset Vector from offset 0x04 (includes Thumb bit)
mem2array pc_arr 32 0x20000004 1
reg pc $pc_arr(0)

resume
```

**Or use the init_dumper.sh script which handles this automatically.**

**Verification:**
```tcl
halt
reg pc

# WRONG - PC in spi_transfer function (stuck polling):
# pc (/32): 0x2000004a

# RIGHT - PC in main loop (ready for commands):
# pc (/32): 0x20000120
```

**Debugging steps:**
1. Halt the target
2. Check PC - if it's in the 0x20000040-0x20000080 range, it's likely stuck in `spi_transfer()`
3. Check SPI status register (SAM4S: 0x40008010, STM32: 0x40013008)
4. Reload the binary and use proper initialization sequence

**Note for different MCUs:** The address ranges shown assume SRAM at 0x20000000. For LPC1768, the SRAM base is 0x10000000, so adjust accordingly.

---

### Watchdog Reset During Operation

**Symptoms:**
- Dump starts but MCU resets partway through
- Pattern repeats at consistent intervals

**Solution:** Feed watchdog periodically during long operations:

```c
// SAM4S
#define WDT_CR (*((volatile uint32_t *)0x400E1450))
WDT_CR = 0xA5000001;

// STM32
#define IWDG_KR (*((volatile uint32_t *)0x40003000))
IWDG_KR = 0xAAAA;

// In read loop:
for (i = 0; i < size; i++) {
    dest[i] = spi_transfer(0x00);
    if ((i & 0xFFF) == 0) {  // Every 4KB
        feed_watchdog();
    }
}
```

---

## SPI Communication Issues

### SPI Transfer Hangs (Never Completes)

**Symptoms:**
- Code hangs polling SPI status register
- TDRE (TX empty) or RDRF (RX full) never set

**Cause 1: SPI peripheral not enabled**

```c
// SAM4S: Enable SPI
SPI_CR = (1 << 0);  // SPIEN

// STM32: Enable SPI
SPI_CR1 |= (1 << 6);  // SPE
```

**Cause 2: SPI clock not running (SAM4S/SAM3X specific)**

The SAM4S SPI peripheral won't generate clock if PCS field is 0xF:

```c
// WRONG - PCS=0xF means no peripheral selected, no clock!
SPI_MR = SPI_MR_MSTR | SPI_MR_MODFDIS | (0x0F << 16);

// CORRECT - PCS=0x0E selects NPCS0 (inverted logic)
SPI_MR = SPI_MR_MSTR | SPI_MR_MODFDIS | (0x0E << 16);
```

**Cause 3: Peripheral clock not enabled**

Some MCUs require enabling peripheral clock in system controller:

```c
// STM32: Enable SPI1 clock in RCC
RCC_APB2ENR |= (1 << 12);  // SPI1EN
```

### SPI Returns All 0x00 or 0xFF

**Symptoms:**
- Transfers complete but data is all zeros or all ones
- JEDEC ID reads as 0x000000 or 0xFFFFFF

**Cause 1: Chip select not toggling**

Verify GPIO is properly configured:

```c
// SAM4S: Reclaim pin from SPI peripheral for GPIO control
PIOA_PER = (1 << CS_PIN);   // Enable PIO control
PIOA_OER = (1 << CS_PIN);   // Enable output driver

// Then toggle:
PIOA_CODR = (1 << CS_PIN);  // CS low (select)
// ... do SPI transfer ...
PIOA_SODR = (1 << CS_PIN);  // CS high (deselect)
```

**Cause 2: Wrong SPI mode**

Most SPI flash uses Mode 0 (CPOL=0, CPHA=0). Check if Mode 3 is needed:

```c
// STM32 Mode 0 (default, usually correct):
SPI_CR1 &= ~((1 << 0) | (1 << 1));  // CPHA=0, CPOL=0

// STM32 Mode 3 (if needed):
SPI_CR1 |= (1 << 0) | (1 << 1);     // CPHA=1, CPOL=1
```

**Cause 3: SPI clock too fast**

Reduce SPI clock speed:

```c
// STM32: Increase baud rate divisor
SPI_CR1 = (SPI_CR1 & ~(0x7 << 3)) | (0x5 << 3);  // fPCLK/64
```

---

## JEDEC ID Problems

### JEDEC ID Returns 0x000000

**Meaning:** No response from flash chip.

**Checklist:**
1. [ ] Verify SPI wiring (MOSI, MISO, CLK, CS)
2. [ ] Confirm flash chip is powered
3. [ ] Check chip select is actually toggling (use oscilloscope/logic analyzer)
4. [ ] Verify MISO line is connected (0x00 = MISO stuck low)
5. [ ] Try reducing SPI clock speed
6. [ ] Ensure SPI mode matches flash requirements

### JEDEC ID Returns 0xFFFFFF

**Meaning:** MISO line stuck high or no clock.

**Checklist:**
1. [ ] Verify SPI clock is running
2. [ ] Check MISO connection
3. [ ] Confirm flash chip is not in power-down mode
4. [ ] Try wake-up command (0xAB) before reading ID

**Wake from power-down:**
```c
cs_low();
spi_transfer(0xAB);  // Release from power-down
cs_high();
delay_us(3);         // Wait tRES1 (typically 3µs)
```

### JEDEC ID Returns Unexpected Value

**Symptoms:** Valid-looking ID but doesn't match expected chip.

**Common causes:**
1. **Different flash chip installed** - Verify part number on board
2. **Multiple flash chips** - Wrong CS pin selected
3. **Byte order swapped** - Check bit ordering

**Decode the ID:**
```
ID format: 0xMMTTCC
  MM = Manufacturer
  TT = Device Type
  CC = Capacity

Common manufacturers:
  0x1F = Atmel/Adesto
  0xEF = Winbond
  0xC2 = Macronix
  0x20 = Micron/Numonyx
  0x01 = Spansion/Cypress
  0xBF = SST/Microchip
```

---

## OpenOCD Issues

### 'mrw' Command Not Found

**Symptoms:**
```
invalid command name "mrw"
```

**Cause:** Newer OpenOCD versions removed the `mrw` command.

**Solution:** Use `mem2array` wrapper:
```tcl
proc read_word { addr } {
    set result [mem2array tmp 32 $addr 1]
    return $tmp(0)
}

# Usage:
set value [read_word 0x20000000]
```

### Binary Load Fails

**Symptoms:**
```
Error: Failed to load binary
```

**Checklist:**
1. [ ] Verify binary file exists and path is correct
2. [ ] Check file permissions
3. [ ] Ensure target is halted before loading
4. [ ] Verify SRAM address is correct for target MCU

```tcl
halt
load_image /path/to/spi_dump.bin 0x20000000 bin
```

### Target Not Responding

**Symptoms:**
- Commands timeout
- "Target not halted" errors

**Solutions:**
1. **Reset and halt:**
   ```tcl
   reset halt
   ```

2. **Check debug connection:**
   ```tcl
   targets
   ```

3. **Verify SWD/JTAG wiring**

4. **Check debug interface speed:**
   ```tcl
   adapter speed 1000  # Reduce to 1MHz
   ```

### Memory Read Returns All 0xFF

**Symptoms:**
- `mdw` commands return 0xFFFFFFFF
- Reads from valid SRAM addresses fail

**Cause:** Target may be locked or in protected state.

**Solutions:**
1. Check if chip has read protection enabled
2. Try mass erase (will erase flash):
   ```tcl
   flash erase_sector 0 0 last
   ```
3. Verify you're reading valid memory regions

---

## Data Integrity Issues

### Dump Contains Unexpected Patterns

**Symptoms:**
- Repeating patterns in dump
- Data doesn't match expected content

**Cause 1: Buffer overrun**

Ensure read size doesn't exceed buffer:
```c
if (size > BUFFER_SIZE) {
    COMM_ERROR = 0x0001;
    return;
}
```

**Cause 2: Incorrect flash address calculation**

Verify 24-bit address formatting:
```c
spi_transfer((flash_addr >> 16) & 0xFF);  // Byte 2 (MSB)
spi_transfer((flash_addr >> 8) & 0xFF);   // Byte 1
spi_transfer(flash_addr & 0xFF);          // Byte 0 (LSB)
```

### Dump Has Periodic Differences

**Symptoms:**
- Comparing two dumps shows differences at regular intervals
- Differences at same offsets within each sector

**Cause:** Per-sector metadata (wear leveling counters, timestamps).

**Explanation:** Some file systems (SPIFFS, LittleFS) store metadata at fixed offsets within each sector. This metadata changes on each write.

**Verification:**
```bash
# Check if differences are at consistent sector offsets
xxd dump1.bin > dump1.hex
xxd dump2.bin > dump2.hex
diff dump1.hex dump2.hex | grep -oE '0x[0-9a-f]+' | \
    xargs -I{} python3 -c "print('{}: offset in sector = ' + hex(int('{}', 16) % 4096))"
```

**This is expected behavior**, not corruption. The actual firmware code is identical.

### Dump Size Mismatch

**Symptoms:**
- Dump file is smaller than expected flash size
- Dump truncated

**Causes:**
1. **Read operation error** - Check status for errors
2. **OpenOCD timeout** - Increase timeout for slow operations
3. **Flash size misconfigured** - Verify actual flash capacity

**Verify flash size from JEDEC ID:**
```
Capacity byte (last byte of JEDEC ID):
  0x14 = 8Mbit (1MB)
  0x15 = 16Mbit (2MB)
  0x16 = 32Mbit (4MB)
  0x17 = 64Mbit (8MB)
  0x18 = 128Mbit (16MB)
```

---

## Diagnostic Procedures

### Verify SPI Communication

1. **Read JEDEC ID first** - This is the simplest test
2. **Check for valid manufacturer ID** - Should be recognized value
3. **Read first few bytes** - Should not be all 0x00 or 0xFF

### Check Vector Table Setup

```tcl
# Verify vector table in SRAM
mdw 0x20000000 16

# Expected output:
# 0x20000000: STACK_PTR  RESET_VEC  NMI_VEC    HARDFAULT
# Should see valid addresses, reset vector has bit 0 set
```

### Monitor SPI Registers

```tcl
# SAM4S SPI status
mdw 0x40008010  # SPI_SR - check RDRF/TDRE bits

# STM32 SPI status
mdw 0x40013008  # SPI_SR - check RXNE/TXE bits
```

### Debug Fault Handler

Add distinctive marker in fault handler for easy identification:

```c
void __attribute__((naked)) fault_handler(void) {
    __asm volatile (
        "mov r0, #0xFA\n"       // Marker
        "lsl r0, r0, #8\n"
        "orr r0, #0x17\n"       // r0 = 0xFA17
        "1: b 1b\n"             // Infinite loop
    );
}
```

Then check register after halt:
```tcl
reg r0
# If 0xFA17, code entered fault handler
```

---

## Quick Reference Table

| Symptom | Most Likely Cause | Quick Fix |
|---------|-------------------|-----------|
| HardFault at flash addr | VTOR not set | `SCB_VTOR = 0x20000000` |
| SPI hangs polling | No SPI clock | Set PCS field properly |
| JEDEC = 0x000000 | CS not toggling | Configure GPIO for CS |
| JEDEC = 0xFFFFFF | No clock/MISO issue | Check SPI clock, wiring |
| Watchdog reset | Not feeding WDT | Feed every 4KB in loop |
| `mrw` not found | Old OpenOCD | Use `mem2array` wrapper |
| Periodic differences | Normal metadata | Compare actual code regions |
