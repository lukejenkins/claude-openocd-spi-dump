#
# RAM-Resident SPI Flash Dumper - OpenOCD TCL Script Template
#
# This script provides commands to load and control the RAM-resident
# SPI flash dumper. Customize the addresses for your target MCU.
#
# Usage:
#   1. Connect to OpenOCD telnet (port 4444)
#   2. source spi_dump.tcl
#   3. spi_test          (verify JEDEC ID)
#   4. spi_dump_full output.bin
#

#===========================================================================
# CUSTOMIZE: Memory Addresses for Your Target
#===========================================================================

set CODE_ADDR       0x20000000      ;# SRAM base where binary is loaded
set BUFFER_ADDR     0x2000E000      ;# Read buffer location
set BUFFER_SIZE     0x1000          ;# 4KB buffer
set COMM_ADDR       0x2000FF00      ;# Communication area
set FLASH_SIZE      0x400000        ;# 4MB flash (adjust for your chip)
set BINARY_FILE     "spi_dump.bin"  ;# Path to compiled binary

#===========================================================================
# Communication Protocol (must match spi_dump.c)
#===========================================================================

# Offsets within communication area
set COMM_STATUS     0x00
set COMM_FLASH_ADDR 0x04
set COMM_SIZE       0x08
set COMM_DEST       0x0C
set COMM_JEDEC_ID   0x10

# Status codes
set STATUS_IDLE     0x00000000
set STATUS_BUSY     0x00000001
set STATUS_DONE     0x00000002
set STATUS_ERROR    0xDEAD0000

# Command codes
set CMD_NOP         0x00000000
set CMD_READ_FLASH  0x00000010
set CMD_GET_JEDEC   0x00000020
set CMD_EXIT        0x000000FF

#===========================================================================
# Helper Procedures
#===========================================================================

# Read a 32-bit word from memory
# Uses mem2array for compatibility with newer OpenOCD versions
proc read_word { addr } {
    set result [mem2array tmp 32 $addr 1]
    return $tmp(0)
}

# Write a 32-bit word to memory
proc write_word { addr value } {
    mww $addr $value
}

# Wait for status to change from BUSY
proc wait_status { timeout_ms } {
    global COMM_ADDR COMM_STATUS STATUS_BUSY STATUS_DONE STATUS_ERROR

    set status_addr [expr {$COMM_ADDR + $COMM_STATUS}]
    set start [clock milliseconds]

    while {1} {
        set status [read_word $status_addr]

        if {$status == $STATUS_DONE} {
            return 1
        }

        if {($status & 0xFFFF0000) == $STATUS_ERROR} {
            puts "ERROR: Status = [format 0x%08X $status]"
            return 0
        }

        set elapsed [expr {[clock milliseconds] - $start}]
        if {$elapsed > $timeout_ms} {
            puts "ERROR: Timeout (status = [format 0x%08X $status])"
            return 0
        }

        after 10
    }
}

#===========================================================================
# Main Commands
#===========================================================================

# Load the dumper binary into SRAM
proc spi_load {} {
    global CODE_ADDR BINARY_FILE

    puts "Loading $BINARY_FILE to [format 0x%08X $CODE_ADDR]..."

    halt

    if {[catch {load_image $BINARY_FILE $CODE_ADDR bin} err]} {
        puts "ERROR: Failed to load binary: $err"
        return 0
    }

    puts "Binary loaded successfully"
    return 1
}

# Initialize and start the dumper
proc spi_init {} {
    global CODE_ADDR COMM_ADDR STATUS_IDLE

    puts "Initializing SPI dumper..."

    halt

    # Read initial SP and reset vector from loaded binary
    set init_sp [read_word $CODE_ADDR]
    set reset_vector [read_word [expr {$CODE_ADDR + 4}]]

    puts "  Initial SP:    [format 0x%08X $init_sp]"
    puts "  Reset vector:  [format 0x%08X $reset_vector]"
    puts "  Entry point:   [format 0x%08X [expr {$reset_vector & ~1}]]"

    # Set CPU registers
    reg sp $init_sp
    reg pc $reset_vector

    # Start execution
    puts "Starting execution..."
    resume

    # Wait for initialization
    after 200

    halt

    set status [read_word $COMM_ADDR]
    if {$status == $STATUS_IDLE} {
        puts "SPI dumper ready!"
        return 1
    } else {
        puts "WARNING: Unexpected status [format 0x%08X $status]"
        return 1
    }
}

# Quick test - read JEDEC ID
proc spi_test {} {
    global COMM_ADDR COMM_STATUS COMM_JEDEC_ID CMD_GET_JEDEC

    puts "=== SPI Flash Test ==="
    puts ""

    # Load and initialize
    if {![spi_load]} { return 0 }
    if {![spi_init]} { return 0 }

    puts "Reading JEDEC ID..."

    halt
    write_word $COMM_ADDR $CMD_GET_JEDEC
    resume

    after 100
    halt

    if {![wait_status 1000]} {
        puts "ERROR: JEDEC ID read failed"
        return 0
    }

    # Read result
    set jedec_id [read_word [expr {$COMM_ADDR + $COMM_JEDEC_ID}]]

    puts ""
    puts "JEDEC ID: [format 0x%06X $jedec_id]"
    puts "  Manufacturer: [format 0x%02X [expr {($jedec_id >> 16) & 0xFF}]]"
    puts "  Device Type:  [format 0x%02X [expr {($jedec_id >> 8) & 0xFF}]]"
    puts "  Capacity:     [format 0x%02X [expr {$jedec_id & 0xFF}]]"

    # Decode manufacturer
    set mfr [expr {($jedec_id >> 16) & 0xFF}]
    switch -- $mfr {
        0x1F { puts "  -> Adesto/Atmel" }
        0xEF { puts "  -> Winbond" }
        0xC2 { puts "  -> Macronix" }
        0x20 { puts "  -> Micron/Numonyx" }
        0x01 { puts "  -> Spansion/Cypress" }
        0xBF { puts "  -> SST/Microchip" }
        0x00 { puts "  -> ERROR: No response (check CS pin)" }
        0xFF { puts "  -> ERROR: No clock or MISO issue" }
    }

    puts ""
    return 1
}

# Dump entire flash to file
proc spi_dump_full { filename } {
    global FLASH_SIZE
    spi_dump_range $filename 0 $FLASH_SIZE
}

# Dump a range of flash to file
proc spi_dump_range { filename start_addr size } {
    global COMM_ADDR BUFFER_ADDR BUFFER_SIZE
    global COMM_STATUS COMM_FLASH_ADDR COMM_SIZE COMM_DEST
    global CMD_READ_FLASH STATUS_IDLE

    puts "=== SPI Flash Dump ==="
    puts "  Range: [format 0x%06X $start_addr] - [format 0x%06X [expr {$start_addr + $size - 1}]]"
    puts "  Size:  [expr {$size / 1024}] KB"
    puts "  File:  $filename"
    puts ""

    # Open output file
    set fd [open $filename wb]

    # Calculate chunks
    set chunk_size $BUFFER_SIZE
    set total_chunks [expr {($size + $chunk_size - 1) / $chunk_size}]
    set bytes_remaining $size
    set current_addr $start_addr
    set chunk_num 0

    set start_time [clock seconds]

    while {$bytes_remaining > 0} {
        set this_chunk $chunk_size
        if {$this_chunk > $bytes_remaining} {
            set this_chunk $bytes_remaining
        }

        incr chunk_num
        set pct [expr {$chunk_num * 100 / $total_chunks}]
        puts -nonewline "\r  Chunk $chunk_num/$total_chunks ($pct%) - [format 0x%06X $current_addr]"
        flush stdout

        # Set up read parameters
        halt
        write_word [expr {$COMM_ADDR + $COMM_FLASH_ADDR}] $current_addr
        write_word [expr {$COMM_ADDR + $COMM_SIZE}] $this_chunk
        write_word [expr {$COMM_ADDR + $COMM_DEST}] $BUFFER_ADDR

        # Issue read command
        write_word $COMM_ADDR $CMD_READ_FLASH
        resume

        after 50
        halt

        if {![wait_status 5000]} {
            puts "\nERROR: Read failed at [format 0x%06X $current_addr]"
            close $fd
            return 0
        }

        # Read data from buffer and write to file
        set data [read_memory $BUFFER_ADDR 8 $this_chunk]
        foreach byte $data {
            puts -nonewline $fd [binary format c $byte]
        }

        # Reset status
        write_word $COMM_ADDR $STATUS_IDLE

        set current_addr [expr {$current_addr + $this_chunk}]
        set bytes_remaining [expr {$bytes_remaining - $this_chunk}]
    }

    close $fd

    set elapsed [expr {[clock seconds] - $start_time}]
    puts ""
    puts ""
    puts "Dump complete!"
    puts "  File: $filename"
    puts "  Size: $size bytes"
    puts "  Time: ${elapsed}s"

    return 1
}

# Stop the dumper
proc spi_stop {} {
    global COMM_ADDR CMD_EXIT

    puts "Stopping SPI dumper..."
    halt
    write_word $COMM_ADDR $CMD_EXIT
    resume
    after 100
    halt
    puts "Done."
}

#===========================================================================
# Usage Information
#===========================================================================

puts ""
puts "=== SPI Flash Dumper Loaded ==="
puts ""
puts "Commands:"
puts "  spi_test              - Test connection (read JEDEC ID)"
puts "  spi_dump_full <file>  - Dump entire flash"
puts "  spi_dump_range <file> <addr> <size> - Dump range"
puts "  spi_stop              - Stop dumper"
puts ""
puts "Configuration:"
puts "  Binary:     $BINARY_FILE"
puts "  Code addr:  [format 0x%08X $CODE_ADDR]"
puts "  Flash size: [expr {$FLASH_SIZE / 1024 / 1024}] MB"
puts ""
