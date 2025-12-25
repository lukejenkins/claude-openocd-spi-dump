---
name: spi-dump
description: Guided workflow for dumping SPI flash/EEPROM through a microcontroller via OpenOCD
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
argument-hint: "[mcu-type]"
---

# SPI Flash Dump Workflow

Guide the user through dumping SPI flash or EEPROM memory through a microcontroller's SPI peripheral using OpenOCD. This is a fully interactive workflow that gathers information, generates customized code, and walks through testing.

## Workflow Phases

### Phase 1: Gather Target Information

Start by understanding the user's hardware setup. Ask these questions:

1. **MCU Information**
   - What MCU are you targeting? (e.g., ATSAM4S2A, STM32F407, nRF52832)
   - If unknown, ask about the board or help identify from debug output

2. **SPI Flash Information**
   - Do you know the flash chip? (e.g., AT25DF321A, W25Q32)
   - If unknown, will discover via JEDEC ID later
   - What is the expected flash size? (1MB, 4MB, 8MB, etc.)

3. **SPI Pin Configuration**
   - Which SPI peripheral is connected to the flash? (SPI0, SPI1, etc.)
   - Which pin is used for chip select? (e.g., PA11, PB12)
   - If unknown, help find from schematic or board documentation

4. **OpenOCD Status**
   - Is OpenOCD already connected to the target?
   - What debug probe are you using? (J-Link, ST-Link, etc.)

### Phase 2: Load Skill Knowledge

Load the spi-flash-dump skill to get detailed MCU register information:

- Reference `skills/spi-flash-dump/references/mcu-registers.md` for register addresses
- Reference `skills/spi-flash-dump/references/troubleshooting.md` for potential issues
- Use `skills/spi-flash-dump/examples/` as code templates

### Phase 3: Generate Customized Code

Based on gathered information, customize the code templates:

1. **spi_dump.c** - Update with:
   - Correct SPI peripheral base address
   - Correct GPIO base address and CS pin
   - Correct watchdog address (if applicable)
   - SRAM size for the target MCU

2. **spi_dump.ld** - Update with:
   - Correct SRAM base address
   - Correct SRAM size
   - Appropriate buffer and stack sizes

3. **spi_dump.tcl** - Update with:
   - Correct memory addresses
   - Correct flash size
   - Path to compiled binary

Write the customized files to the user's project directory.

### Phase 4: Build Instructions

Provide build commands:

```bash
# Compile
arm-none-eabi-gcc -mcpu=cortex-m4 -mthumb -Os -ffreestanding \
    -nostdlib -T spi_dump.ld -o spi_dump.elf spi_dump.c

# Convert to binary
arm-none-eabi-objcopy -O binary spi_dump.elf spi_dump.bin

# Check size (should be ~500 bytes)
arm-none-eabi-size spi_dump.elf
```

Adjust `-mcpu` flag based on MCU:
- Cortex-M0: `-mcpu=cortex-m0`
- Cortex-M3: `-mcpu=cortex-m3`
- Cortex-M4: `-mcpu=cortex-m4`
- Cortex-M7: `-mcpu=cortex-m7`

### Phase 5: Test JEDEC ID

Guide the user through the first test:

1. Connect to OpenOCD telnet:
   ```
   telnet localhost 4444
   ```

2. Source the TCL script:
   ```tcl
   source spi_dump.tcl
   ```

3. Run JEDEC ID test:
   ```tcl
   spi_test
   ```

**Expected result:** Valid JEDEC ID (not 0x000000 or 0xFFFFFF)

**If test fails:** Reference troubleshooting guide and help debug:
- 0x000000 → CS pin not toggling (check GPIO config)
- 0xFFFFFF → No clock or MISO issue (check SPI config)
- HardFault → VTOR issue (check vector table)

### Phase 6: Full Dump

Once JEDEC ID test passes, proceed with full dump:

```tcl
spi_dump_full flash_dump.bin
```

Monitor progress and handle any errors that occur.

### Phase 7: Verify Dump

After dump completes:

1. **Check file size:**
   ```bash
   ls -la flash_dump.bin
   # Should match expected flash size
   ```

2. **Quick content check:**
   ```bash
   xxd flash_dump.bin | head -20
   # Should see non-0xFF data (unless flash is erased)
   ```

3. **Optional: Compare with known dump** (if available)

## Tips

- If the MCU type was provided as an argument, skip the MCU identification questions
- Always test JEDEC ID before attempting full dump
- For unknown flash chips, decode JEDEC ID to determine manufacturer and size
- Keep the user informed of progress during long dumps
- If errors occur, reference the troubleshooting guide for solutions

## Example Usage

User runs: `/spi-dump sam4s`

Response flow:
1. "I see you're targeting a SAM4S MCU. Let me gather a few more details..."
2. Ask about SPI pins and flash chip
3. Generate customized code
4. Guide through build and test
5. Perform full dump
