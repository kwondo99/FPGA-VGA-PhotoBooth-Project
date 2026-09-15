`timescale 1ns / 1ps

// =====================================================
// mem_addr_gen
//  - Converts display coordinates to a memory read address.
//  - In MOSAIC mode, snaps the 5x5 region around the marker to the
//    center pixel's address so the preview reads the same sample
//    used for the committed write (see mem_writer.sv).
//  - 2-stage pipeline: o_mem_raddr is valid 2 clocks after the inputs.
// =====================================================
module mem_addr_gen #(
    parameter MEM_W = 320,
    parameter MEM_H = 240
) (
    input  logic        clk,
    input  logic [9:0]  i_x_pixel,     // 320 scale (post-downscaler)
    input  logic [9:0]  i_y_pixel,
    input  logic [9:0]  i_marker_x,    // marker position (320 scale)
    input  logic [9:0]  i_marker_y,
    input  logic [1:0]  i_edit_mode,   // 00:NONE 01:STICKER 10:DRAW 11:MOSAIC
    input  logic        i_edit_active,

    output logic [16:0] o_mem_raddr    // valid 2 clocks after inputs (2-stage pipeline)
);

    localparam EDIT_MOSAIC = 2'b11;
    localparam [9:0] MOSAIC_REGION_RADIUS = 10'd2; // radius 2 around center -> 5x5 region
    localparam [9:0] MOSAIC_MAX_X = MEM_W - 1 - MOSAIC_REGION_RADIUS; // max on-screen center X for a 5x5 box
    localparam [9:0] MOSAIC_MAX_Y = MEM_H - 1 - MOSAIC_REGION_RADIUS; // max on-screen center Y for a 5x5 box
    // Same boundary clamp as mem_writer, so the 5x5 preview position matches the committed write position.

    wire mosaic_mode_on = (i_edit_mode == EDIT_MOSAIC) && i_edit_active;

    // Clamp the marker center so the full 5x5 region stays on-screen, matching the committed write.
    wire [9:0] mosaic_center_x = (i_marker_x < MOSAIC_REGION_RADIUS) ? MOSAIC_REGION_RADIUS : (i_marker_x > MOSAIC_MAX_X) ? MOSAIC_MAX_X : i_marker_x; // clamp X center to 2..317
    wire [9:0] mosaic_center_y = (i_marker_y < MOSAIC_REGION_RADIUS) ? MOSAIC_REGION_RADIUS : (i_marker_y > MOSAIC_MAX_Y) ? MOSAIC_MAX_Y : i_marker_y; // clamp Y center to 2..237

    // ---- Test membership in the clamped marker region using absolute distance (avoids subtraction underflow) ----
    wire [9:0] mdx = (i_x_pixel >= mosaic_center_x) ? (i_x_pixel - mosaic_center_x) : (mosaic_center_x - i_x_pixel); // X distance from the same center as mem_writer
    wire [9:0] mdy = (i_y_pixel >= mosaic_center_y) ? (i_y_pixel - mosaic_center_y) : (mosaic_center_y - i_y_pixel); // Y distance from the same center as mem_writer
    wire in_region = (mdx <= MOSAIC_REGION_RADIUS) && (mdy <= MOSAIC_REGION_RADIUS);

    wire mosaic_on = mosaic_mode_on && in_region;

    wire [9:0] mem_x = mosaic_on ? mosaic_center_x : i_x_pixel; // preview samples the single center-pixel color across the 5x5 region, same as mem_writer
    wire [9:0] mem_y = mosaic_on ? mosaic_center_y : i_y_pixel; // keeps preview and commit sample addresses identical

    // ---- Stage 1: register the snap logic result (comparisons/mux, cheap ops) first.
    // Breaks the combinational path that would otherwise run straight from the VGA
    // pixel counter (far register, high routing delay) into the multiplier.
    logic [9:0] mem_x_r1, mem_y_r1;
    always_ff @(posedge clk) begin
        mem_x_r1 <= mem_x;
        mem_y_r1 <= mem_y;
    end

    // ---- Stage 2: multiply (DSP48E1+CARRY4) using the stage-1 registers, then
    // register again. Synthesis can often retime this register into the DSP48E1's
    // built-in output register at no extra resource cost, improving timing only.
    // Also keeps this multiply out of the same cycle as memory.sv's BRAM decode.
    wire [16:0] mem_raddr_comb = mem_y_r1 * MEM_W + mem_x_r1;
    logic [16:0] mem_raddr_r2;
    always_ff @(posedge clk) mem_raddr_r2 <= mem_raddr_comb;
    assign o_mem_raddr = mem_raddr_r2;

endmodule
