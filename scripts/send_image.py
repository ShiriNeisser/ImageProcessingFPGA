"""
send_image.py - Host-side utility to send image data to the FPGA via UART.

This script reads pre-computed RGB channel data from three .mem files
(red.mem, green.mem, blue.mem), concatenates them in planar format
(all Red bytes, then all Green bytes, then all Blue bytes), and sends
the combined data to the FPGA over a serial (UART) connection.

The data is sent in 1KB chunks with small delays to prevent buffer overflow
on the FPGA's UART receiver.

Usage:
    1. Connect the Nexys A7-100T board via USB
    2. Update SERIAL_PORT to match your system's COM port
    3. Run: python send_image.py

Requirements:
    - PySerial: pip install pyserial
"""

import serial
import sys
import time
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.join(SCRIPT_DIR, '..')

# Serial port configuration
SERIAL_PORT = 'COM8'       # COM port for FPGA's USB-UART bridge (adjust as needed)
BAUD_RATE = 115200         # Must match uart_pkg.sv BAUD_RATE parameter


def read_mem_file(filename):
    """
    Read a .mem file containing hexadecimal byte values (one per line).

    Args:
        filename: Path to the .mem file (e.g., 'red.mem')

    Returns:
        List of integer byte values (0-255)
    """
    data = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                data.append(int(line, 16))  # Parse hex string to integer
    return data


def main():
    # Read the three color channel files
    print("Reading MEM files...")
    red_data = read_mem_file(os.path.join(PROJECT_ROOT, 'mem', 'red.mem'))
    green_data = read_mem_file(os.path.join(PROJECT_ROOT, 'mem', 'green.mem'))
    blue_data = read_mem_file(os.path.join(PROJECT_ROOT, 'mem', 'blue.mem'))


    # Concatenate in planar order: R + G + B (must match FPGA memory layout)
    all_data = red_data + green_data + blue_data
    print(f"Total bytes to send: {len(all_data)}")

    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=2)
        print("Connected to FPGA. Sending data in safe chunks...")

        chunk_size = 1024  # Send in 1KB blocks to avoid UART buffer overflow
        for i in range(0, len(all_data), chunk_size):
            chunk = bytearray(all_data[i : i+chunk_size])
            ser.write(chunk)
            ser.flush()        # Force OS to push data to hardware immediately
            time.sleep(0.01)   # Small delay to prevent FPGA buffer overflow

            # Print progress on the same line (no newline)
            sys.stdout.write(f"\rSent: {min(i+chunk_size, len(all_data))} / {len(all_data)}")
            sys.stdout.flush()

        print("\nData sent successfully!")
        ser.close()
    except Exception as e:
        print(f"Error: {e}")


if __name__ == "__main__":
    main()
