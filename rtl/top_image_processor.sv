// ============================================================================
// Module: top_image_processor
// Description: Top-level module for the FPGA-based image processing system.
//              Instantiates all sub-modules (UART RX/TX, SRAM, debouncers,
//              and the FSM controller) and connects them together.
// Target Board: Nexys A7-100T (Artix-7 FPGA, 100MHz clock)
// Image Size:   345 x 456 pixels (157,320 pixels, 471,960 bytes in planar RGB)
// ============================================================================

module top_image_processor (
    input  logic clk,          // 100MHz system clock (pin E3)
    input  logic rx,           // UART receive line from host PC (pin C4)
    output logic tx,           // UART transmit line to host PC (pin D4)
    input  logic btn_bright,   // Button to trigger color channel swap (center button, pin N17)
    input  logic btn_send,     // Button to trigger image transmission back to host (up button, pin M18)
    input  logic cpu_resetn,   // CPU Reset button, active-low (pin C12)
    output logic [2:0] led     // Status LEDs: [0]=RX done, [1]=Swap done, [2]=TX done
);

    // Image size parameters
    localparam PIXELS = 157320;        // Total number of pixels (345 * 456)
    localparam TOTAL_BYTES = PIXELS * 3; // Total bytes in planar RGB format (471,960)

    // --------------------------------------------------------
    // Internal wires connecting sub-modules
    // --------------------------------------------------------
    logic [7:0] rx_data, tx_data, ram_din, ram_dout; // 8-bit data buses
    logic rx_valid, tx_start, tx_busy, ram_we;        // Control signals
    logic [18:0] ram_addr;                            // 19-bit address (supports up to 512KB)
    logic bright_pulse, send_pulse;                   // Debounced single-cycle button pulses
    logic reset_pulse;
    assign reset_pulse = ~cpu_resetn;  // Convert active-low reset to active-high

    logic [2:0] fsm_leds;      // LED status from FSM (solid ON when operation complete)
    logic rx_active, tx_active; // Activity flags from FSM (used for LED blinking)

    // Blink counter: 24-bit counter at 100MHz toggles bit[23] at ~6Hz,
    // creating a visible blink effect on LEDs during active RX/TX operations
    logic [23:0] blink_cnt = 0;
    always_ff @(posedge clk) blink_cnt <= blink_cnt + 1;

    // LED behavior:
    //   - During image reception: LED[0] blinks
    //   - After reception complete: LED[0] stays solid ON
    //   - LED[1] turns ON after color swap is complete
    //   - During image transmission: LED[2] blinks
    //   - After transmission complete: LED[2] stays solid ON
    assign led[0] = rx_active ? blink_cnt[23] : fsm_leds[0];
    assign led[1] = fsm_leds[1];
    assign led[2] = tx_active ? blink_cnt[23] : fsm_leds[2];

    // --------------------------------------------------------
    // Module Instantiations
    // --------------------------------------------------------

    // 1. UART Receiver - deserializes incoming serial data at 115200 baud
    uart_rx rx_inst (
        .clk(clk),
        .rx(rx),
        .data_out(rx_data),
        .valid(rx_valid)
    );

    // 2. UART Transmitter - serializes outgoing data at 115200 baud
    uart_tx tx_inst (
        .clk(clk),
        .tx_start(tx_start),
        .data_in(tx_data),
        .tx(tx),
        .busy(tx_busy)
    );

    // 3. Block RAM Memory - stores the full image (472KB, planar RGB format)
    sram_memory ram_inst (
        .clk(clk),
        .we(ram_we),
        .addr(ram_addr),
        .din(ram_din),
        .dout(ram_dout)
    );

    // 4. Button Debouncers - produce clean single-cycle pulses from noisy button presses
    debouncer db_bright (
        .clk(clk),
        .btn_in(btn_bright),
        .btn_pulse(bright_pulse)
    );

    debouncer db_send (
        .clk(clk),
        .btn_in(btn_send),
        .btn_pulse(send_pulse)
    );

    // 5. FSM Controller - the system's brain; manages image reception,
    //    color channel swapping, and image transmission
    image_fsm_controller #(
        .PIXELS(PIXELS),
        .TOTAL_BYTES(TOTAL_BYTES)
    ) fsm_inst (
        .clk(clk),
        .rx_valid(rx_valid),
        .rx_data(rx_data),
        .tx_busy(tx_busy),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .ram_dout(ram_dout),
        .ram_we(ram_we),
        .ram_addr(ram_addr),
        .ram_din(ram_din),
        .bright_pulse(bright_pulse),
        .send_pulse(send_pulse),
        .reset_pulse(reset_pulse),
        .led_status(fsm_leds),
        .rx_active(rx_active),
        .tx_active(tx_active)
    );

endmodule
