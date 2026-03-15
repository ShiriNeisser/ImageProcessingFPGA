// ============================================================================
// Module: uart_rx
// Description: UART Receiver module. Deserializes incoming serial data into
//              parallel 8-bit bytes. Uses standard 8N1 protocol:
//              1 start bit, 8 data bits (LSB first), 1 stop bit, no parity.
// Baud Rate:   115200 (configured via uart_pkg)
// Sampling:    Mid-bit sampling for reliable data capture
// Output:      Pulses 'valid' HIGH for one clock cycle when a byte is ready
// ============================================================================

module uart_rx (
    input  logic clk,              // 100MHz system clock
    input  logic rx,               // Serial input line (idle = HIGH)
    output logic [7:0] data_out,   // Received byte (valid when 'valid' is HIGH)
    output logic valid             // Single-cycle pulse indicating a byte is ready
);
    import uart_pkg::*;            // Import CLKS_PER_BIT (= 868 at 100MHz / 115200 baud)

    // FSM states for UART reception
    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t state = IDLE;

    logic [15:0] clk_count = 0;    // Clock cycle counter within each bit period
    logic [2:0]  bit_index = 0;    // Current data bit being received (0-7)
    logic [7:0]  rx_data   = 0;    // Shift register to assemble received byte

    always_ff @(posedge clk) begin
        valid <= 0;                // Default: valid is LOW (only pulsed in STOP state)

        case (state)
            // IDLE: Wait for start bit (falling edge on RX line, idle = HIGH)
            IDLE: begin
                clk_count <= 0;
                bit_index <= 0;
                if (rx == 0) state <= START;  // Start bit detected (RX goes LOW)
            end

            // START: Verify start bit by sampling at the middle of the bit period.
            // Wait CLKS_PER_BIT/2 cycles to reach the center of the start bit,
            // then check if RX is still LOW (filters out noise glitches).
            START: begin
                if (clk_count == (CLKS_PER_BIT/2)) begin
                    if (rx == 0) begin
                        clk_count <= 0;       // Valid start bit confirmed
                        state <= DATA;        // Begin receiving data bits
                    end else state <= IDLE;    // False start (noise), go back to idle
                end else clk_count <= clk_count + 1;
            end

            // DATA: Sample each of the 8 data bits at the center of their bit period.
            // Bits arrive LSB first (bit 0 first, bit 7 last).
            DATA: begin
                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= 0;
                    rx_data[bit_index] <= rx;  // Capture current bit value
                    if (bit_index == 7) state <= STOP;  // All 8 bits received
                    else bit_index <= bit_index + 1;
                end else clk_count <= clk_count + 1;
            end

            // STOP: Wait for the stop bit period to complete, then output the byte.
            // The stop bit is HIGH (line returns to idle level).
            STOP: begin
                if (clk_count == CLKS_PER_BIT - 1) begin
                    valid <= 1;               // Pulse: byte is ready
                    data_out <= rx_data;       // Output the assembled byte
                    state <= IDLE;            // Ready for next byte
                end else clk_count <= clk_count + 1;
            end
        endcase
    end
endmodule
