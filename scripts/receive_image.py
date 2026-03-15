"""
receive_image.py - Host-side utility to receive processed image data from the FPGA.

This script listens on the serial port for image data transmitted by the FPGA
after the user presses the "Send" button on the board. It receives 471,960 bytes
in planar RGB format, reconstructs the image as a 345x456 pixel RGB image,
and saves it as a JPEG file.

Usage:
    1. Run this script first: python receive_image.py
    2. Press the 'Send' button (btn_send / up button) on the FPGA board
    3. Wait for all bytes to be received
    4. The reconstructed image is saved as 'final_shiny_image.jpg'

Requirements:
    - PySerial: pip install pyserial
    - Pillow:   pip install Pillow
"""

import serial
import sys
from PIL import Image
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.join(SCRIPT_DIR, '..')



# Serial port configuration
SERIAL_PORT = 'COM8'       # COM port for FPGA's USB-UART bridge (adjust as needed)
BAUD_RATE = 115200         # Must match uart_pkg.sv BAUD_RATE parameter

# Image dimensions (must match FPGA parameters)
PIXELS = 157320            # Total pixels = 345 * 456
TOTAL_BYTES = PIXELS * 3   # 3 bytes per pixel (R + G + B channels)
WIDTH = 345                # Image width in pixels
HEIGHT = 456               # Image height in pixels


def main():
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=3)
        print("Listening for incoming data...")
        print(">>> NOW PRESS THE 'SEND' BUTTON ON THE FPGA! <<<")

        received_data = bytearray()

        # Receive bytes until we have the full image
        while len(received_data) < TOTAL_BYTES:
            bytes_waiting = max(1, ser.in_waiting)  # Read at least 1 byte
            chunk = ser.read(min(bytes_waiting, TOTAL_BYTES - len(received_data)))

            if not chunk:
                # Timeout: no data received within the timeout period
                print("\n\n[!] TIMEOUT: The FPGA stopped sending data!")
                break

            received_data.extend(chunk)

            # Print progress on the same line
            sys.stdout.write(f"\rReceived: {len(received_data)} / {TOTAL_BYTES} bytes")
            sys.stdout.flush()

        print(f"\n\n--- SUMMARY ---")
        print(f"Total bytes actually received: {len(received_data)}")
        ser.close()

        # Reconstruct the image if all bytes were received
        if len(received_data) == TOTAL_BYTES:
            print("Processing image data...")

            # Split planar data into separate R, G, B channels
            r_bytes = received_data[0 : PIXELS]             # Red channel
            g_bytes = received_data[PIXELS : PIXELS*2]       # Green channel
            b_bytes = received_data[PIXELS*2 : TOTAL_BYTES]  # Blue channel

            # Create a new RGB image and fill pixel by pixel
            img = Image.new('RGB', (WIDTH, HEIGHT))
            pixels_map = img.load()

            idx = 0
            for y in range(HEIGHT):
                for x in range(WIDTH):
                    if idx < PIXELS:
                        # Combine the three channels into an RGB tuple
                        pixels_map[x, y] = (r_bytes[idx], g_bytes[idx], b_bytes[idx])
                        idx += 1

            # Save the reconstructed image
            output_filename = os.path.join(PROJECT_ROOT, 'images', 'final_shiny_image.jpg')
            img.save(output_filename)
            print(f"SUCCESS! Open '{output_filename}' to see the CLEAR result!")
        else:
            print("Did not receive all bytes. Cannot generate the image.")

    except Exception as e:
        print(f"Error: {e}")


if __name__ == "__main__":
    main()
