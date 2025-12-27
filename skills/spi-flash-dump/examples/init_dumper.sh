#!/bin/bash
#
# SPI Dumper Initialization Script
#
# Properly loads and initializes the RAM-resident SPI dumper.
# This script handles the critical initialization sequence that ensures
# the code starts from its reset vector (not an arbitrary address).
#
# Usage:
#   ./init_dumper.sh [binary_file]
#
# Environment Variables (set these for your MCU):
#   SRAM_BASE    - SRAM start address (default: 0x20000000)
#   SRAM_SIZE    - SRAM size in bytes (default: 0x10000 = 64KB)
#   OPENOCD_HOST - OpenOCD telnet host (default: localhost)
#   OPENOCD_PORT - OpenOCD telnet port (default: 4444)
#
# Examples:
#   # SAM4S/STM32 (default settings)
#   ./init_dumper.sh spi_dump.bin
#
#   # LPC1768 (SRAM at 0x10000000)
#   SRAM_BASE=0x10000000 ./init_dumper.sh spi_dump.bin
#

set -e

#===========================================================================
# Configuration
#===========================================================================

# MCU Memory Configuration
SRAM_BASE="${SRAM_BASE:-0x20000000}"
SRAM_SIZE="${SRAM_SIZE:-0x10000}"

# OpenOCD Connection
OPENOCD_HOST="${OPENOCD_HOST:-localhost}"
OPENOCD_PORT="${OPENOCD_PORT:-4444}"

# Binary file
BINARY="${1:-spi_dump.bin}"

# Convert to decimal
SRAM_BASE_DEC=$((SRAM_BASE))
SRAM_SIZE_DEC=$((SRAM_SIZE))
SRAM_END=$((SRAM_BASE_DEC + SRAM_SIZE_DEC))
COMM_ADDR=$((SRAM_END - 256))

#===========================================================================
# Helper Functions
#===========================================================================

openocd_cmd() {
    printf '%s\nexit\n' "$1" | nc "$OPENOCD_HOST" "$OPENOCD_PORT" 2>/dev/null
}

read_word() {
    local addr=$1
    openocd_cmd "halt
mdw $(printf '0x%08X' $addr) 1" | grep "$(printf '0x%08x' $addr)" | awk '{print $2}'
}

#===========================================================================
# Main Script
#===========================================================================

echo "=== SPI Dumper Initialization ==="
echo ""
echo "Configuration:"
echo "  Binary:     $BINARY"
echo "  SRAM Base:  $(printf '0x%08X' $SRAM_BASE_DEC)"
echo "  SRAM Size:  $(printf '0x%08X' $SRAM_SIZE_DEC) ($((SRAM_SIZE_DEC / 1024)) KB)"
echo "  Comm Addr:  $(printf '0x%08X' $COMM_ADDR)"
echo "  OpenOCD:    $OPENOCD_HOST:$OPENOCD_PORT"
echo ""

# Check binary exists
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary file not found: $BINARY"
    exit 1
fi

BINARY_SIZE=$(stat -f%z "$BINARY" 2>/dev/null || stat -c%s "$BINARY" 2>/dev/null)
echo "Binary size: $BINARY_SIZE bytes"
echo ""

# Step 1: Reset and halt the target
echo "Step 1: Reset and halt target..."
RESULT=$(openocd_cmd "reset halt")
if echo "$RESULT" | grep -q "halted"; then
    echo "  Target halted successfully"
else
    echo "  Warning: Unexpected response (continuing anyway)"
fi

# Step 2: Load binary into SRAM
echo ""
echo "Step 2: Loading binary into SRAM at $(printf '0x%08X' $SRAM_BASE_DEC)..."
RESULT=$(openocd_cmd "halt
load_image $BINARY $(printf '0x%08X' $SRAM_BASE_DEC) bin")
if echo "$RESULT" | grep -q "bytes"; then
    echo "  Binary loaded successfully"
else
    echo "  Warning: Load may have failed"
    echo "  Response: $RESULT"
fi

# Step 3: Read vector table from loaded binary
echo ""
echo "Step 3: Reading vector table..."

# Vector table format (Cortex-M):
#   Offset 0x00: Initial Stack Pointer
#   Offset 0x04: Reset Vector (entry point, with Thumb bit set)

SP=$(read_word $SRAM_BASE_DEC)
PC=$(read_word $((SRAM_BASE_DEC + 4)))

if [ -z "$SP" ] || [ -z "$PC" ]; then
    echo "  ERROR: Failed to read vector table"
    exit 1
fi

echo "  Initial SP:   0x$SP"
echo "  Reset Vector: 0x$PC"

# Validate the values make sense
SP_DEC=$((16#$SP))
PC_DEC=$((16#$PC))

# SP should be near end of SRAM
if [ $SP_DEC -lt $SRAM_BASE_DEC ] || [ $SP_DEC -gt $SRAM_END ]; then
    echo "  WARNING: SP (0x$SP) is outside SRAM range!"
fi

# PC should be in SRAM (with Thumb bit potentially set)
PC_NOBIT=$((PC_DEC & ~1))
if [ $PC_NOBIT -lt $SRAM_BASE_DEC ] || [ $PC_NOBIT -gt $SRAM_END ]; then
    echo "  WARNING: PC (0x$PC) is outside SRAM range!"
fi

# Check Thumb bit
if [ $((PC_DEC & 1)) -eq 1 ]; then
    echo "  Thumb bit is set (correct for Cortex-M)"
else
    echo "  WARNING: Thumb bit not set - adding it"
    PC=$(printf '%08X' $((PC_DEC | 1)))
fi

# Step 4: Set registers and start execution
echo ""
echo "Step 4: Setting registers and starting execution..."

openocd_cmd "halt
reg sp 0x$SP
reg pc 0x$PC
resume" >/dev/null 2>&1

echo "  Registers set, execution started"

# Step 5: Wait for initialization and verify
echo ""
echo "Step 5: Verifying initialization..."
sleep 0.5

# Halt and check status
STATUS=$(openocd_cmd "halt
mdw $(printf '0x%08X' $COMM_ADDR) 1" | grep "$(printf '0x%08x' $COMM_ADDR)" | awk '{print $2}')

# Also check PC to make sure we're in the main loop
CURRENT_PC=$(openocd_cmd "reg pc" | grep "pc" | awk -F: '{print $2}' | tr -d ' ')

echo "  Status register: ${STATUS:-unknown}"
echo "  Current PC:      ${CURRENT_PC:-unknown}"

# Validate status
if [ "$STATUS" = "00000000" ]; then
    echo ""
    echo "=== Initialization Successful ==="
    echo ""
    echo "The SPI dumper is ready. You can now:"
    echo "  1. Test JEDEC ID: Use test_jedec.sh or run spi_test in OpenOCD"
    echo "  2. Dump flash:    ./dump.sh output.bin [flash_size]"
    echo ""
elif [ -n "$STATUS" ]; then
    echo ""
    echo "=== Initialization Complete (with warning) ==="
    echo ""
    echo "Status is 0x$STATUS (expected 0x00000000 for IDLE)"
    echo "The dumper may be in an unexpected state."
    echo ""
    echo "Try resetting status with:"
    echo "  echo 'mww $(printf '0x%08X' $COMM_ADDR) 0x00' | nc $OPENOCD_HOST $OPENOCD_PORT"
    echo ""
else
    echo ""
    echo "=== Initialization May Have Failed ==="
    echo ""
    echo "Could not read status register. Possible causes:"
    echo "  1. Code crashed (check PC - should be in 0x200000xx range)"
    echo "  2. Wrong SRAM_BASE for this MCU"
    echo "  3. OpenOCD connection issue"
    echo ""
    echo "See troubleshooting.md for debugging steps."
    exit 1
fi
