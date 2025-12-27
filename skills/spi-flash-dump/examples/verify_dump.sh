#!/bin/bash
#
# SPI Flash Dump Verification Script
#
# Analyzes a dump file to verify integrity and identify content.
# Helps detect common issues like incomplete dumps, stuck data lines,
# or corrupted reads.
#
# Usage:
#   ./verify_dump.sh <dump_file> [expected_size]
#
# Examples:
#   ./verify_dump.sh flash_dump.bin
#   ./verify_dump.sh flash_dump.bin 0x400000   # Expect 4MB
#   ./verify_dump.sh flash_dump.bin 4194304   # Expect 4MB (decimal)
#

set -e

#===========================================================================
# Configuration
#===========================================================================

DUMP_FILE="${1:-flash_dump.bin}"
EXPECTED_SIZE="${2:-}"

# Convert hex to decimal if needed
if [[ "$EXPECTED_SIZE" == 0x* ]]; then
    EXPECTED_SIZE=$((EXPECTED_SIZE))
fi

#===========================================================================
# Helper Functions
#===========================================================================

# Check if file contains only a single repeated byte
check_stuck_pattern() {
    local file="$1"
    local sample_size=1024

    # Get first 1KB
    local first_bytes=$(xxd -l $sample_size -p "$file" | tr -d '\n')

    # Check for all 0x00
    if [[ "$first_bytes" =~ ^0+$ ]]; then
        echo "all_zeros"
        return
    fi

    # Check for all 0xFF
    if [[ "$first_bytes" =~ ^[fF]+$ ]]; then
        echo "all_ones"
        return
    fi

    echo "varied"
}

# Count occurrences of 0xFF and 0x00 in file (approximate)
count_byte_patterns() {
    local file="$1"
    local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)

    # Sample every 256th byte for large files
    local sample_rate=256
    local ff_count=0
    local zero_count=0

    # Use xxd to analyze
    local total_ff=$(xxd -p "$file" | grep -o 'ff' | wc -l || echo 0)
    local total_00=$(xxd -p "$file" | grep -o '00' | wc -l || echo 0)

    echo "$total_ff $total_00 $size"
}

# Look for ARM Cortex-M vector table signature
find_vector_tables() {
    local file="$1"
    local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)

    # Vector table typically starts with:
    # - Stack pointer (usually 0x2000xxxx or 0x1000xxxx)
    # - Reset vector (address in SRAM or flash, odd for Thumb)

    # Search for potential vector tables at common offsets
    local offsets="0 0x1000 0x4000 0x8000 0x10000 0x20000"

    for offset in $offsets; do
        if [ $((offset)) -ge $size ]; then
            continue
        fi

        # Read first 8 bytes at offset
        local sp=$(xxd -s $((offset)) -l 4 -e "$file" 2>/dev/null | awk '{print $2}')
        local pc=$(xxd -s $((offset + 4)) -l 4 -e "$file" 2>/dev/null | awk '{print $2}')

        if [ -z "$sp" ] || [ -z "$pc" ]; then
            continue
        fi

        # Check if SP looks like SRAM address (0x20xxxxxx or 0x10xxxxxx)
        if [[ "$sp" =~ ^(20|10)[0-9a-fA-F]{6}$ ]]; then
            # Check if PC looks like valid code address with Thumb bit
            if [[ "$pc" =~ ^(20|10|00|08)[0-9a-fA-F]{5}[13579bdfBDF]$ ]]; then
                echo "$(printf '0x%06X' $((offset))) SP=0x$sp PC=0x$pc"
            fi
        fi
    done
}

# Calculate simple entropy estimate
estimate_entropy() {
    local file="$1"

    # Count unique byte values in sample
    local unique=$(xxd -l 4096 -p "$file" | fold -w2 | sort -u | wc -l)

    if [ $unique -lt 10 ]; then
        echo "very_low"
    elif [ $unique -lt 50 ]; then
        echo "low"
    elif [ $unique -lt 200 ]; then
        echo "medium"
    else
        echo "high"
    fi
}

#===========================================================================
# Main Script
#===========================================================================

echo "=== SPI Flash Dump Verification ==="
echo ""

# Check file exists
if [ ! -f "$DUMP_FILE" ]; then
    echo "ERROR: File not found: $DUMP_FILE"
    exit 1
fi

# Get file info
FILE_SIZE=$(stat -f%z "$DUMP_FILE" 2>/dev/null || stat -c%s "$DUMP_FILE" 2>/dev/null)

echo "File: $DUMP_FILE"
echo "Size: $FILE_SIZE bytes ($(echo "scale=2; $FILE_SIZE / 1048576" | bc) MB)"

# Check expected size
if [ -n "$EXPECTED_SIZE" ]; then
    if [ "$FILE_SIZE" -eq "$EXPECTED_SIZE" ]; then
        echo "Expected size: $EXPECTED_SIZE bytes - MATCH"
    else
        echo "Expected size: $EXPECTED_SIZE bytes - MISMATCH!"
        echo "  Difference: $((FILE_SIZE - EXPECTED_SIZE)) bytes"
    fi
fi
echo ""

#---------------------------------------------------------------------------
# Check for stuck data lines
#---------------------------------------------------------------------------
echo "=== Data Line Check ==="

PATTERN=$(check_stuck_pattern "$DUMP_FILE")

case "$PATTERN" in
    "all_zeros")
        echo "WARNING: File contains all zeros!"
        echo "  This usually indicates:"
        echo "  - SPI MISO line not connected"
        echo "  - Flash chip not responding"
        echo "  - Chip select not working"
        ;;
    "all_ones")
        echo "WARNING: File contains all 0xFF!"
        echo "  This usually indicates:"
        echo "  - Erased/blank flash"
        echo "  - SPI clock not running"
        echo "  - MISO stuck high"
        ;;
    "varied")
        echo "Data appears varied (good)"
        ;;
esac
echo ""

#---------------------------------------------------------------------------
# Byte distribution analysis
#---------------------------------------------------------------------------
echo "=== Byte Distribution ==="

# Quick entropy check
ENTROPY=$(estimate_entropy "$DUMP_FILE")
echo "Entropy estimate: $ENTROPY"

case "$ENTROPY" in
    "very_low")
        echo "  Very low entropy suggests repetitive/empty data"
        ;;
    "low")
        echo "  Low entropy may indicate sparse data or padding"
        ;;
    "medium")
        echo "  Medium entropy is typical for firmware"
        ;;
    "high")
        echo "  High entropy suggests compressed/encrypted data"
        ;;
esac
echo ""

#---------------------------------------------------------------------------
# Look for firmware signatures
#---------------------------------------------------------------------------
echo "=== Firmware Detection ==="

# Look for ARM vector tables
echo "Searching for ARM vector tables..."
VECTORS=$(find_vector_tables "$DUMP_FILE")
if [ -n "$VECTORS" ]; then
    echo "Potential vector tables found:"
    echo "$VECTORS" | while read line; do
        echo "  $line"
    done
else
    echo "  No obvious vector tables found"
fi
echo ""

# Look for common magic bytes
echo "Checking for known signatures..."

# Check first few bytes
MAGIC=$(xxd -l 16 -p "$DUMP_FILE" | tr -d '\n')

# ELF magic
if [[ "$MAGIC" == 7f454c46* ]]; then
    echo "  Found: ELF executable header"
fi

# UF2 magic
if [[ "$MAGIC" == 55463241* ]]; then
    echo "  Found: UF2 firmware format"
fi

# BIN with ARM vector (SP at 0x20xxxxxx)
if [[ "${MAGIC:0:2}" =~ ^(20|10)$ ]]; then
    echo "  Found: Possible ARM binary (starts with RAM address)"
fi

echo ""

#---------------------------------------------------------------------------
# Sample data preview
#---------------------------------------------------------------------------
echo "=== Data Preview ==="
echo ""
echo "First 64 bytes:"
xxd -l 64 "$DUMP_FILE"
echo ""

# If file is large enough, show data at common firmware offset
if [ $FILE_SIZE -ge 65536 ]; then
    echo "Data at 0x10000 (common firmware start):"
    xxd -s 0x10000 -l 64 "$DUMP_FILE"
    echo ""
fi

#---------------------------------------------------------------------------
# Summary
#---------------------------------------------------------------------------
echo "=== Summary ==="

ISSUES=0

if [ "$PATTERN" = "all_zeros" ] || [ "$PATTERN" = "all_ones" ]; then
    echo "  [FAIL] Data appears stuck (all same value)"
    ISSUES=$((ISSUES + 1))
else
    echo "  [PASS] Data is varied"
fi

if [ -n "$EXPECTED_SIZE" ] && [ "$FILE_SIZE" -ne "$EXPECTED_SIZE" ]; then
    echo "  [FAIL] Size mismatch"
    ISSUES=$((ISSUES + 1))
else
    echo "  [PASS] Size OK"
fi

if [ "$ENTROPY" = "very_low" ]; then
    echo "  [WARN] Very low entropy"
else
    echo "  [PASS] Entropy reasonable"
fi

echo ""
if [ $ISSUES -eq 0 ]; then
    echo "Dump appears valid!"
else
    echo "Found $ISSUES potential issue(s) - review above for details"
fi
