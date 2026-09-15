`timescale 1ns / 1ps
// =====================================================
// memory (320x240, RGB444, 2-port)
//  - Port A: mem_writer only (write + mosaic read share this port, top muxes the address)
//  - Port B: marker_overlay only (read-only, driven every clock for display)
//  - depth = 320*240 = 76,800 (17-bit address is sufficient)
//  - 2 ports map to a single True Dual-Port BRAM primitive (no replication)
// =====================================================
module memory #(
    parameter MEM_W = 320,
    parameter MEM_H = 240
) (
    input logic clk,
    input logic rst,

    // ---- Port A: mem_writer (write + mosaic read, muxed by top) ----
    input  logic        i_we,
    input  logic [16:0] i_addr,
    input  logic [11:0] i_wdata,
    output logic [11:0] o_rdata_a,   // valid 1 clock after i_addr

    // ---- Port B: marker_overlay (read-only) ----
    input  logic [16:0] i_raddr,
    output logic [11:0] o_rdata_b    // valid 1 clock after i_raddr
);

    localparam DEPTH = MEM_W * MEM_H;  // 320*240 = 76800

    (* ram_style = "block" *) logic [11:0] mem [0:DEPTH-1];

    // No explicit init block: a 76,800-iteration loop exceeds Vivado's default
    // loop limit (65536), which silently drops the whole initial block
    // (AR#8-6896). BRAM defaults to 0 anyway, so the initial state is unchanged.

    // Port A: write-first, read is also driven every clock (unused while writing)
    always_ff @(posedge clk) begin
        if (i_we) begin
            mem[i_addr] <= i_wdata;
        end
        o_rdata_a <= mem[i_addr];
    end

    // Port B: read-only
    always_ff @(posedge clk) begin
        o_rdata_b <= mem[i_raddr];
    end

endmodule
