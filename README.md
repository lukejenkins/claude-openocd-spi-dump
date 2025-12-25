# OpenOCD SPI Dump Plugin

A Claude Code plugin for dumping SPI flash/EEPROM memory through a microcontroller's SPI peripheral via OpenOCD, without requiring external SPI programming hardware.

## Overview

When reverse engineering embedded systems, you often need to dump SPI flash contents but lack dedicated SPI programming hardware. This plugin provides Claude with the knowledge and guided workflows to help you dump flash via the MCU's debug interface (SWD/JTAG).

## Features

- **Skill: spi-flash-dump** - Comprehensive knowledge about RAM-resident SPI dumping
  - MCU register maps for SAM4S, SAM3X, STM32F1/F4, nRF52, LPC1768
  - Ready-to-use code templates (C, linker scripts, OpenOCD TCL)
  - Troubleshooting guide for common issues

- **Command: /spi-dump** - Fully guided interactive workflow
  - Gathers information about your target MCU and SPI connections
  - Generates customized implementation for your hardware
  - Walks through testing and verification

## Prerequisites

- OpenOCD installed and configured for your debug probe
- SWD/JTAG connection to the target MCU
- Target MCU has SPI flash/EEPROM connected to its SPI peripheral

## Installation

```bash
# Use as a plugin directory
claude --plugin-dir /path/to/claude-openocd-spi-dump

# Or copy to your project's .claude-plugin directory
```

## Usage

### Quick Start

Just ask Claude about your scenario:
- "I need to dump the SPI flash on this SAM4S board"
- "How do I read the EEPROM through the MCU via OpenOCD?"
- "Help me dump flash from this STM32 target"

### Guided Workflow

Run the interactive command:
```
/spi-dump
```

This will guide you through:
1. Identifying your MCU and SPI connections
2. Verifying OpenOCD connectivity
3. Generating the RAM-resident dumper code
4. Testing with JEDEC ID read
5. Performing the full flash dump

## Supported MCU Families

| Family | Example Parts | Status |
|--------|--------------|--------|
| SAM4S | ATSAM4S2A, ATSAM4S4A | Full support |
| SAM3X | ATSAM3X8E (Arduino Due) | Full support |
| STM32F1 | STM32F103 (Blue Pill) | Full support |
| STM32F4 | STM32F407, STM32F411 | Full support |
| nRF52 | nRF52832, nRF52840 | Full support |
| LPC1768 | LPC1768 (mbed) | Full support |

Adding new MCUs is straightforward - see the skill documentation for guidance.

## License

MIT
