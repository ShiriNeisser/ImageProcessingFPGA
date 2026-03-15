// ============================================================================
// Module: sram_memory
// Description: Synchronous Block RAM module for storing image data.
//              Provides 472KB of storage (471,960 bytes) to hold a full
//              345x456 RGB image in planar format.
// Memory Size: 471,960 bytes (8-bit wide, 19-bit address)
// Read Latency: 1 clock cycle (synchronous read)
// Write Mode:   Synchronous write when 'we' is HIGH
//
// Vivado Attributes:
//   ram_style = "block"     -> Forces use of dedicated Block RAM primitives
//                              (instead of distributed LUT-based RAM)
//   cascade_height = 1      -> Prevents REQP-1962 routing crash in Vivado
//                              by disabling Block RAM cascading
// ============================================================================

module sram_memory (
    input  logic clk,              // 100MHz system clock
    input  logic we,               // Write enable: HIGH = write, LOW = read
    input  logic [18:0] addr,      // 19-bit address (supports up to 524,288 locations)
    input  logic [7:0] din,        // 8-bit data input (for writes)
    output logic [7:0] dout        // 8-bit data output (available 1 cycle after address is set)
);
    // Block RAM array: 471,960 bytes
    // Synthesis attributes ensure Vivado uses Block RAM resources efficiently
    (* ram_style = "block", cascade_height = 1 *) logic [7:0] mem [0:471959];

    always_ff @(posedge clk) begin
        if (we) begin
            mem[addr] <= din;      // Synchronous write
        end
        dout <= mem[addr];         // Synchronous read (1 cycle latency)
    end
endmodule
