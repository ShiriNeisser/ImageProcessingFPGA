// ============================================================================
// Module: debouncer
// Description: Button debouncer that eliminates mechanical contact bounce.
//              Uses a 20-bit counter to ensure the button state is stable
//              before registering a press. Outputs a single-cycle pulse
//              only on the rising edge (button press), not on release.
// Debounce Time: ~10.5ms at 100MHz (2^20 = 1,048,576 clock cycles)
// ============================================================================

module debouncer(
    input  logic clk,          // 100MHz system clock
    input  logic btn_in,       // Raw button input (active-high, directly from pin)
    output logic btn_pulse     // Clean single-cycle pulse on button press
);
    logic [19:0] counter = 0;  // 20-bit counter for debounce timing
    logic state = 0;           // Stored (debounced) button state

    always_ff @(posedge clk) begin
        btn_pulse <= 0;        // Default: no pulse (only asserted below)

        if (btn_in != state) begin
            // Button state differs from stored state -> might be a real press
            // Increment counter until it overflows, confirming a stable change
            counter <= counter + 1;
            if (counter == 20'hFFFFF) begin
                state <= btn_in;           // Accept the new state
                counter <= 0;
                if (btn_in == 1)
                    btn_pulse <= 1;        // Pulse only on rising edge (press, not release)
            end
        end else begin
            counter <= 0;                  // Button matches stored state -> reset counter
        end
    end
endmodule
