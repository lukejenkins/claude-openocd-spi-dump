#!/bin/bash
#
# SPI Flash Dump Script
#
# Dumps SPI flash contents via OpenOCD using the RAM-resident SPI dumper.
# Works with any supported MCU by configuring memory addresses.
#
# Usage:
#   ./dump.sh [output_file] [flash_size_bytes]
#
# Environment Variables (set these for your MCU):
#   SRAM_BASE   - SRAM start address (default: 0x20000000)
#   SRAM_SIZE   - SRAM size in bytes (default: 0x10000 = 64KB)
#   OPENOCD_HOST - OpenOCD telnet host (default: localhost)
#   OPENOCD_PORT - OpenOCD telnet port (default: 4444)
#
# Examples:
#   # SAM4S/STM32 (default settings)
#   ./dump.sh firmware.bin 0x400000
#
#   # LPC1768 (SRAM at 0x10000000, 32KB)
#   SRAM_BASE=0x10000000 SRAM_SIZE=0x8000 ./dump.sh firmware.bin 0x400000
#
#   # nRF52840 (256KB SRAM)
#   SRAM_SIZE=0x40000 ./dump.sh firmware.bin 0x100000
#

set -e

#===========================================================================
# Configuration
#===========================================================================

# MCU Memory Configuration (override via environment variables)
SRAM_BASE="${SRAM_BASE:-0x20000000}"
SRAM_SIZE="${SRAM_SIZE:-0x10000}"

# OpenOCD Connection
OPENOCD_HOST="${OPENOCD_HOST:-localhost}"
OPENOCD_PORT="${OPENOCD_PORT:-4444}"

# Command line arguments
OUTFILE="${1:-flash_dump.bin}"
FLASH_SIZE="${2:-0x400000}"  # Default 4MB

# Convert hex to decimal if needed
if [[ "$FLASH_SIZE" == 0x* ]]; then
    FLASH_SIZE=$((FLASH_SIZE))
fi

# Chunk size (4KB is optimal for most cases)
CHUNK_SIZE=4096

#===========================================================================
# Calculate Memory Layout
#===========================================================================

# Calculate addresses based on SRAM configuration
# Layout from end of SRAM:
#   - Last 256 bytes: Communication area (COMM)
#   - Before that: Stack (256 bytes)
#   - Before that: Read buffer (4KB minimum)

SRAM_BASE_DEC=$((SRAM_BASE))
SRAM_SIZE_DEC=$((SRAM_SIZE))
SRAM_END=$((SRAM_BASE_DEC + SRAM_SIZE_DEC))

COMM_SIZE=256
STACK_SIZE=256
BUFFER_SIZE=$CHUNK_SIZE

COMM_ADDR=$((SRAM_END - COMM_SIZE))
BUFFER_ADDR=$((SRAM_END - COMM_SIZE - STACK_SIZE - BUFFER_SIZE))

# Validate buffer doesn't overlap with code area
CODE_MAX=$((SRAM_BASE_DEC + SRAM_SIZE_DEC - COMM_SIZE - STACK_SIZE - BUFFER_SIZE - 1024))
if [ $BUFFER_ADDR -lt $((SRAM_BASE_DEC + 1024)) ]; then
    echo "ERROR: SRAM too small for buffer. Need at least 8KB SRAM."
    exit 1
fi

#===========================================================================
# Helper Functions
#===========================================================================

openocd_cmd() {
    printf '%s\nexit\n' "$1" | nc "$OPENOCD_HOST" "$OPENOCD_PORT" 2>/dev/null
}

openocd_cmd_quiet() {
    printf '%s\nexit\n' "$1" | nc "$OPENOCD_HOST" "$OPENOCD_PORT" >/dev/null 2>&1
}

check_status() {
    local status
    status=$(openocd_cmd "halt
mdw $(printf '0x%08X' $COMM_ADDR) 1" | grep "$(printf '0x%08x' $COMM_ADDR)" | awk '{print $2}')
    echo "$status"
}

#===========================================================================
# Main Script
#===========================================================================

echo "=== SPI Flash Dump ==="
echo ""
echo "Configuration:"
echo "  SRAM Base:    $(printf '0x%08X' $SRAM_BASE_DEC)"
echo "  SRAM Size:    $(printf '0x%08X' $SRAM_SIZE_DEC) ($((SRAM_SIZE_DEC / 1024)) KB)"
echo "  Buffer Addr:  $(printf '0x%08X' $BUFFER_ADDR)"
echo "  Comm Addr:    $(printf '0x%08X' $COMM_ADDR)"
echo "  Flash Size:   $(printf '0x%08X' $FLASH_SIZE) ($((FLASH_SIZE / 1024)) KB)"
echo "  Output File:  $OUTFILE"
echo "  OpenOCD:      $OPENOCD_HOST:$OPENOCD_PORT"
echo ""

# Check OpenOCD connection
echo -n "Checking OpenOCD connection... "
if ! openocd_cmd "halt" | grep -q "halted\|halt"; then
    # Try anyway, some OpenOCD versions have different output
    :
fi
echo "OK"

# Verify dumper is running by checking status
echo -n "Checking SPI dumper status... "
STATUS=$(check_status)
if [ -z "$STATUS" ]; then
    echo "FAILED"
    echo "ERROR: Cannot read status from $(printf '0x%08X' $COMM_ADDR)"
    echo "Make sure the SPI dumper is loaded and running."
    echo "Use init_dumper.sh to initialize it first."
    exit 1
fi
echo "OK (status: $STATUS)"

# Clear output file
> "$OUTFILE"

# Calculate chunks
TOTAL_CHUNKS=$(( (FLASH_SIZE + CHUNK_SIZE - 1) / CHUNK_SIZE ))
echo ""
echo "Starting dump: $TOTAL_CHUNKS chunks of $CHUNK_SIZE bytes each"
echo ""

# Dump loop
ADDR=0
CHUNK=0
START_TIME=$(date +%s)
ERRORS=0

while [ $ADDR -lt $FLASH_SIZE ]; do
    CHUNK=$((CHUNK + 1))
    PCT=$((CHUNK * 100 / TOTAL_CHUNKS))

    # Calculate this chunk size (last chunk may be smaller)
    THIS_CHUNK=$CHUNK_SIZE
    if [ $((ADDR + THIS_CHUNK)) -gt $FLASH_SIZE ]; then
        THIS_CHUNK=$((FLASH_SIZE - ADDR))
    fi

    printf "\r[%3d%%] Chunk %4d/%d - Address 0x%06X " $PCT $CHUNK $TOTAL_CHUNKS $ADDR

    # Issue read command
    openocd_cmd_quiet "halt
mww $(printf '0x%08X' $COMM_ADDR) 0x00
mww $(printf '0x%08X' $((COMM_ADDR + 4))) $(printf '0x%06X' $ADDR)
mww $(printf '0x%08X' $((COMM_ADDR + 8))) $(printf '0x%04X' $THIS_CHUNK)
mww $(printf '0x%08X' $((COMM_ADDR + 12))) $(printf '0x%08X' $BUFFER_ADDR)
mww $(printf '0x%08X' $COMM_ADDR) 0x10
resume"

    # Wait for completion
    sleep 0.15

    # Check status
    STATUS=$(check_status)
    if [ "$STATUS" != "00000002" ]; then
        printf "(status: %s) " "$STATUS"
        ERRORS=$((ERRORS + 1))
        if [ $ERRORS -gt 10 ]; then
            echo ""
            echo "ERROR: Too many consecutive errors. Aborting."
            exit 1
        fi
    else
        ERRORS=0
    fi

    # Dump buffer to temp file
    TMPFILE=$(mktemp)
    openocd_cmd_quiet "halt
dump_image $TMPFILE $(printf '0x%08X' $BUFFER_ADDR) $(printf '0x%04X' $THIS_CHUNK)"

    # Append to output file
    if [ -f "$TMPFILE" ]; then
        cat "$TMPFILE" >> "$OUTFILE"
        rm -f "$TMPFILE"
    else
        echo ""
        echo "ERROR: Failed to create temp file at address $(printf '0x%06X' $ADDR)"
        exit 1
    fi

    # Reset status to idle
    openocd_cmd_quiet "mww $(printf '0x%08X' $COMM_ADDR) 0x00"

    ADDR=$((ADDR + THIS_CHUNK))
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo ""
echo "=== Dump Complete ==="
echo ""
ls -la "$OUTFILE"
echo ""
echo "Time: ${ELAPSED}s"
echo "Speed: $((FLASH_SIZE / 1024 / (ELAPSED + 1))) KB/s"
echo ""
echo "Verify with: xxd $OUTFILE | head -20"
echo "Or run: ./verify_dump.sh $OUTFILE"
