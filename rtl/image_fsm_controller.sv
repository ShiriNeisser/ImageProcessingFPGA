// ============================================================================
// Module: image_fsm_controller
// Description: Main Finite State Machine (FSM) that controls the entire image
//              processing pipeline. Manages three operations:
//              1. Image Reception  - receives bytes from UART and stores in SRAM
//              2. Color Swap       - rotates RGB channels (R->G, G->B, B->R)
//              3. Image Transmission - reads SRAM and sends bytes via UART
//
// Memory Layout (Planar RGB format):
//   Address [0            .. PIXELS-1]       = Red channel   (157,320 bytes)
//   Address [PIXELS       .. 2*PIXELS-1]     = Green channel (157,320 bytes)
//   Address [2*PIXELS     .. 3*PIXELS-1]     = Blue channel  (157,320 bytes)
//   Total: 471,960 bytes
//
// FSM States (18 total):
//   ST_RECV          -> Receive image data from UART into SRAM
//   ST_IDLE          -> Wait for user button press (swap or send)
//   ST_SWAP_RD_R     -> Set address to read Red channel for current pixel
//   ST_SWAP_WAIT_R   -> Wait 1 cycle for Block RAM read latency
//   ST_SWAP_SAVE_R   -> Capture Red value, set address for Green
//   ST_SWAP_WAIT_G   -> Wait 1 cycle for Block RAM read latency
//   ST_SWAP_SAVE_G   -> Capture Green value, set address for Blue
//   ST_SWAP_WAIT_B   -> Wait 1 cycle for Block RAM read latency
//   ST_SWAP_SAVE_B   -> Capture Blue value, begin write-back phase
//   ST_SWAP_WR_R     -> Write Blue value into Red position
//   ST_SWAP_WR_G     -> Write Red value into Green position
//   ST_SWAP_WR_B     -> Write Green value into Blue position
//   ST_SWAP_NEXT     -> Advance to next pixel or finish
//   ST_TX_RD         -> Set address for reading from SRAM
//   ST_TX_WAIT       -> Wait 1 cycle for Block RAM read latency
//   ST_TX_SEND       -> Load byte into UART TX and trigger transmission
//   ST_TX_WAIT_START -> Wait for UART TX to acknowledge start
//   ST_TX_WAIT_DONE  -> Wait for UART TX to finish sending the byte
// ============================================================================

module image_fsm_controller #(
    parameter PIXELS = 157320,             // Number of pixels in the image (345 x 456)
    parameter TOTAL_BYTES = PIXELS * 3     // Total bytes (3 channels x PIXELS)
)(
    input  logic clk,

    // UART RX interface
    input  logic rx_valid,                 // Pulse: a new byte has been received
    input  logic [7:0] rx_data,            // The received byte

    // UART TX interface
    input  logic tx_busy,                  // HIGH while UART TX is sending a byte
    output logic tx_start,                 // Pulse: begin transmitting tx_data
    output logic [7:0] tx_data,            // Byte to transmit

    // SRAM interface (FSM is the sole controller of the memory)
    input  logic [7:0] ram_dout,           // Data read from SRAM at current address
    output logic ram_we,                   // Write enable (HIGH = write, LOW = read)
    output logic [18:0] ram_addr,          // 19-bit memory address
    output logic [7:0] ram_din,            // Data to write into SRAM

    // Button inputs (debounced single-cycle pulses)
    input  logic bright_pulse,             // Triggers color channel swap
    input  logic send_pulse,               // Triggers image transmission to host
    input  logic reset_pulse,              // Resets FSM to initial state

    // LED status outputs (active-high, one per operation)
    output logic [2:0] led_status,         // [0]=RX done, [1]=Swap done, [2]=TX done

    // Activity flags for LED blinking in top module
    output logic rx_active,                // HIGH during image reception
    output logic tx_active                 // HIGH during image transmission
);

    // --------------------------------------------------------
    // Internal registers
    // --------------------------------------------------------
    logic [18:0] addr = 0;                 // Current SRAM address
    logic [18:0] pixel_idx = 0;            // Current pixel index during color swap (0 to PIXELS-1)
    logic [7:0] temp_R, temp_G, temp_B;    // Temporary storage for RGB values during swap
    logic rx_started = 0;                  // Set to 1 when first byte is received

    // Connect internal address register to output port
    assign ram_addr = addr;

    // Activity flags: HIGH when FSM is in the corresponding operation
    // rx_active only turns on after the first byte arrives (prevents LED blink on power-up)
    assign rx_active = (state == ST_RECV) && rx_started;
    assign tx_active = (state == ST_TX_RD) || (state == ST_TX_WAIT) ||
                       (state == ST_TX_SEND) || (state == ST_TX_WAIT_START) ||
                       (state == ST_TX_WAIT_DONE);

    // --------------------------------------------------------
    // State type definition
    // --------------------------------------------------------
    typedef enum logic [4:0] {
        ST_RECV,
        ST_IDLE,
        ST_SWAP_RD_R,
        ST_SWAP_WAIT_R,
        ST_SWAP_SAVE_R,
        ST_SWAP_WAIT_G,
        ST_SWAP_SAVE_G,
        ST_SWAP_WAIT_B,
        ST_SWAP_SAVE_B,
        ST_SWAP_WR_R,
        ST_SWAP_WR_G,
        ST_SWAP_WR_B,
        ST_SWAP_NEXT,
        ST_TX_RD,
        ST_TX_WAIT,
        ST_TX_SEND,
        ST_TX_WAIT_START,
        ST_TX_WAIT_DONE
    } state_t;

    state_t state = ST_RECV;  // FSM starts in receive mode, ready for incoming image

    // --------------------------------------------------------
    // Main FSM logic (synchronous, rising-edge triggered)
    // --------------------------------------------------------
    always_ff @(posedge clk) begin
        // Default: deassert write enable and TX start each cycle
        // They are only asserted in the specific states that need them
        ram_we <= 0;
        tx_start <= 0;

        if (reset_pulse) begin
            // ---- RESET: return to initial state, clear all registers ----
            state      <= ST_RECV;
            addr       <= 0;
            pixel_idx  <= 0;
            led_status <= 3'b000;
            rx_started <= 0;
            temp_R     <= 8'b0;
            temp_G     <= 8'b0;
            temp_B     <= 8'b0;
            ram_din    <= 8'b0;
            tx_data    <= 8'b0;
        end else case (state)

            // ============================================================
            // IMAGE RECEPTION: Store incoming UART bytes into SRAM
            // Bytes arrive in order: all Red, then all Green, then all Blue
            // ============================================================
            ST_RECV: begin
                if (rx_valid) begin
                    rx_started <= 1;          // Mark that reception has begun (enables LED blink)
                    ram_din <= rx_data;       // Place received byte on data input bus
                    ram_we <= 1;              // Enable write to SRAM
                    if (addr == TOTAL_BYTES - 1) begin
                        state <= ST_IDLE;     // All bytes received -> go to idle
                        addr <= 0;            // Reset address for next operation
                        led_status[0] <= 1;   // LED[0] ON: image received successfully
                    end else begin
                        addr <= addr + 1;     // Move to next address
                    end
                end
            end

            // ============================================================
            // IDLE: Wait for user to press a button
            // ============================================================
            ST_IDLE: begin
                addr <= 0;
                if (bright_pulse) begin
                    state <= ST_SWAP_RD_R;    // Start color swap operation
                    pixel_idx <= 0;           // Begin from the first pixel
                end
                if (send_pulse) state <= ST_TX_RD; // Start image transmission
            end

            // ============================================================
            // COLOR CHANNEL SWAP: For each pixel, read R, G, B values
            // then write them back in rotated positions:
            //   Red position   <- Blue value   (temp_B)
            //   Green position <- Red value    (temp_R)
            //   Blue position  <- Green value  (temp_G)
            //
            // Each memory read requires a 1-cycle wait state because
            // Block RAM has synchronous read (1 clock cycle latency).
            // ============================================================

            // Step 1: Set address to read Red channel (addr = pixel_idx)
            ST_SWAP_RD_R: begin
                addr <= pixel_idx;
                state <= ST_SWAP_WAIT_R;
            end

            // Step 2: Wait one cycle for Block RAM read latency
            ST_SWAP_WAIT_R: begin
                state <= ST_SWAP_SAVE_R;
            end

            // Step 3: Capture Red value, then set address for Green channel
            ST_SWAP_SAVE_R: begin
                temp_R <= ram_dout;                 // Save Red value
                addr <= pixel_idx + PIXELS;         // Green channel address
                state <= ST_SWAP_WAIT_G;
            end

            // Step 4: Wait one cycle for Block RAM read latency
            ST_SWAP_WAIT_G: begin
                state <= ST_SWAP_SAVE_G;
            end

            // Step 5: Capture Green value, then set address for Blue channel
            ST_SWAP_SAVE_G: begin
                temp_G <= ram_dout;                 // Save Green value
                addr <= pixel_idx + (2 * PIXELS);   // Blue channel address
                state <= ST_SWAP_WAIT_B;
            end

            // Step 6: Wait one cycle for Block RAM read latency
            ST_SWAP_WAIT_B: begin
                state <= ST_SWAP_SAVE_B;
            end

            // Step 7: Capture Blue value, prepare for write-back phase
            ST_SWAP_SAVE_B: begin
                temp_B <= ram_dout;                 // Save Blue value
                addr <= pixel_idx;                  // Red channel address (for write)
                state <= ST_SWAP_WR_R;
            end

            // Step 8: Write Blue value into Red position (R <- B)
            ST_SWAP_WR_R: begin
                ram_din <= temp_B;                  // Blue -> Red position
                ram_we <= 1;
                addr <= pixel_idx + PIXELS;         // Next: Green channel address
                state <= ST_SWAP_WR_G;
            end

            // Step 9: Write Red value into Green position (G <- R)
            ST_SWAP_WR_G: begin
                ram_din <= temp_R;                  // Red -> Green position
                ram_we <= 1;
                addr <= pixel_idx + (2 * PIXELS);   // Next: Blue channel address
                state <= ST_SWAP_WR_B;
            end

            // Step 10: Write Green value into Blue position (B <- G)
            ST_SWAP_WR_B: begin
                ram_din <= temp_G;                  // Green -> Blue position
                ram_we <= 1;
                state <= ST_SWAP_NEXT;
            end

            // Step 11: Move to next pixel or finish swap
            ST_SWAP_NEXT: begin
                if (pixel_idx == PIXELS - 1) begin
                    state <= ST_IDLE;               // All pixels processed
                    led_status[1] <= 1;             // LED[1] ON: swap complete
                    addr <= 0;
                end else begin
                    pixel_idx <= pixel_idx + 1;     // Advance to next pixel
                    state <= ST_SWAP_RD_R;          // Start swap for next pixel
                end
            end

            // ============================================================
            // IMAGE TRANSMISSION: Read bytes from SRAM and send via UART
            // Sends all 471,960 bytes sequentially (R, G, B channels)
            // ============================================================

            // Step 1: Address is already set; wait for Block RAM read
            ST_TX_RD: begin
                state <= ST_TX_WAIT;
            end

            // Step 2: Wait one cycle for Block RAM read latency
            ST_TX_WAIT: begin
                state <= ST_TX_SEND;
            end

            // Step 3: Load the read byte into UART TX and trigger send
            ST_TX_SEND: begin
                tx_data <= ram_dout;                // Place byte on TX data bus
                tx_start <= 1;                      // Pulse: tell UART TX to start
                state <= ST_TX_WAIT_START;
            end

            // Step 4: Wait one cycle for UART TX to register the start
            ST_TX_WAIT_START: begin
                state <= ST_TX_WAIT_DONE;
            end

            // Step 5: Wait for UART TX to finish sending the byte
            ST_TX_WAIT_DONE: begin
                if (!tx_busy) begin                 // UART TX is done
                    if (addr == TOTAL_BYTES - 1) begin
                        state <= ST_IDLE;           // All bytes sent
                        led_status[2] <= 1;         // LED[2] ON: transmission complete
                    end else begin
                        addr <= addr + 1;           // Move to next byte
                        state <= ST_TX_RD;          // Read next byte from SRAM
                    end
                end
            end
        endcase
    end
endmodule
