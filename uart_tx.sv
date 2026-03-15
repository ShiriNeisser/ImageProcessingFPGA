// ============================================================================
// Module: uart_tx
// Description: UART Transmitter module. Serializes parallel 8-bit bytes into
//              a serial bitstream. Uses standard 8N1 protocol:
//              1 start bit, 8 data bits (LSB first), 1 stop bit, no parity.
// Baud Rate:   115200 (configured via uart_pkg)
// Interface:   Pulse 'tx_start' to begin transmission. Check 'busy' before
//              sending a new byte (HIGH = transmission in progress).
// ============================================================================

module uart_tx (
    input  logic clk,              // 100MHz system clock
    input  logic tx_start,         // Pulse HIGH to begin transmitting data_in
    input  logic [7:0] data_in,    // Byte to transmit (latched on tx_start)

    output logic tx,               // Serial output line (idle = HIGH)
    output logic busy              // HIGH while transmission is in progress
);
    import uart_pkg::*;            // Import CLKS_PER_BIT (= 868 at 100MHz / 115200 baud)

    // FSM states for UART transmission
    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t state = IDLE;

    logic [15:0] clk_count = 0;    // Clock cycle counter within each bit period
    logic [2:0]  bit_index = 0;    // Current data bit being transmitted (0-7)
    logic [7:0]  tx_data   = 0;    // Latched copy of byte being transmitted

    always_ff @(posedge clk) begin
        case (state)
            // IDLE: Line is HIGH (idle). Wait for tx_start pulse.
            // When tx_start arrives, latch the input byte and begin.
            IDLE: begin
                tx   <= 1;                // TX line idle = HIGH
                busy <= 0;               // Ready to accept a new byte
                if (tx_start) begin
                    tx_data   <= data_in; // Latch the byte to transmit
                    busy      <= 1;       // Signal that transmission is starting
                    state     <= START;
                    clk_count <= 0;
                end
            end

            // START: Send start bit (LOW) for one full bit period
            START: begin
                tx <= 0;                  // Start bit = LOW
                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= 0;
                    bit_index <= 0;
                    state <= DATA;        // Move to data bits
                end else clk_count <= clk_count + 1;
            end

            // DATA: Send 8 data bits, LSB first (bit 0 first, bit 7 last)
            // Each bit is held on the TX line for one full bit period
            DATA: begin
                tx <= tx_data[bit_index]; // Output current bit
                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= 0;
                    if (bit_index == 7) state <= STOP;  // All 8 bits sent
                    else bit_index <= bit_index + 1;
                end else clk_count <= clk_count + 1;
            end

            // STOP: Send stop bit (HIGH) for one full bit period, then return to IDLE
            STOP: begin
                tx <= 1;                  // Stop bit = HIGH
                if (clk_count == CLKS_PER_BIT - 1) begin
                    state <= IDLE;        // Transmission complete
                end else clk_count <= clk_count + 1;
            end
        endcase
    end
endmodule
