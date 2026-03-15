// ============================================================================
// Package: uart_pkg
// Description: Shared UART configuration parameters used by both uart_rx and
//              uart_tx modules. Centralizes baud rate settings so changes
//              only need to be made in one place.
// ============================================================================

package uart_pkg;
    localparam CLK_FREQ     = 100_000_000;          // Board clock frequency: 100MHz
    localparam BAUD_RATE    = 115_200;               // Serial communication baud rate
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // Clock cycles per UART bit = 868
endpackage
