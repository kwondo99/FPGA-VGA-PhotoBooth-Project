`timescale 1ns / 1ps

// =====================================================
// marker_overlay
//  - Priority (highest first): sticker > draw > cursor > frame > raw memory.
//    Stickers/drawing render on top of the frame (frame is the background
//    layer, edits sit above it). Mosaic is handled by address-snapping in
//    mem_addr_gen and arrives pre-applied via i_mem_rdata, so the frame
//    ranks above mem_rdata but below the interactive overlays.
//  - Cursor: cross-hair at the marker position (marker_x/y, center-based).
//    Shown whenever marker_valid, except in sticker-placement mode where
//    the sticker preview itself indicates position. The exact center pixel
//    is left blank so the pixel that would be drawn isn't obscured.
//  - Sticker: sticker_rom stores full-resolution artwork per size (no
//    downsampling); size is passed straight through to the ROM.
//  - All coordinates are in 320x240 scale.
// =====================================================
module marker_overlay #(
    parameter MEM_W = 320,
    parameter MEM_H = 240,
    parameter FRAME_THICKNESS = 4,  // cross/border line thickness in pixels
    parameter CURSOR_ARM = 3  // cursor cross-hair arm length in pixels
) (
    input logic clk,
    input logic rst,

    input logic [9:0] i_x_pixel,      // 0-319, current scan coordinate
    input logic [9:0] i_y_pixel,      // 0-239
    input logic [9:0] i_marker_x,     // 0-319, marker/pen position
    input logic [9:0] i_marker_y,     // 0-239
    input logic       i_marker_valid,

    input logic [1:0] i_edit_mode,  // 00:NONE 01:STICKER 10:DRAW 11:MOSAIC
    input logic i_edit_active,
    input logic [1:0] i_stk_id,  // matches SC / 4-slot sticker_rom 2-bit ID width
    input logic [1:0] i_stk_size,  // 0(4x4, smallest) .. 3(32x32, native size)
    input  logic        i_stk_place_p,  // 1-clock pulse: commit sticker at current position
    input logic [2:0] i_draw_color,

    input  logic        i_frame_sel,    // 0: white frame, 1: black frame. always active

    input  logic [11:0] i_mem_rdata,    // memory output, valid 3 clocks after i_x_pixel
                                        // (2 mem_addr_gen pipeline stages + 1 memory read stage)

    output logic [11:0] o_pixel_data
);

    localparam EDIT_STICKER = 2'b01;
    localparam EDIT_DRAW = 2'b10;

    // ---- Clamp a single axis to [0, mem_len-len] so the box stays on-screen ----
    function automatic [9:0] clamp_pos(input [9:0] center, input [9:0] len,
                                       input [9:0] mem_len);
        if (center < (len >> 1)) clamp_pos = 10'd0;
        else if (center - (len >> 1) + len > mem_len) clamp_pos = mem_len - len;
        else clamp_pos = center - (len >> 1);
    endfunction

    // =========================================================
    // Sticker: live preview that follows the marker
    //  - sticker_rom stores each size at native resolution, so this just
    //    forwards i_stk_size and the in-box relative coordinates (no
    //    manual downsampling needed here).
    // =========================================================
    function automatic [9:0] stk_len_of(input [1:0] size);
        case (size)
            2'd3:    stk_len_of = 10'd32;
            2'd2:    stk_len_of = 10'd16;
            2'd1:    stk_len_of = 10'd8;
            default: stk_len_of = 10'd4;
        endcase
    endfunction

    wire [9:0] stk_len = stk_len_of(i_stk_size);

    logic [9:0] stk_x, stk_y;
    always_ff @(posedge clk) begin
        if (rst) begin
            stk_x <= 10'd0;
            stk_y <= 10'd0;
        end else if (!i_stk_place_p && i_marker_valid) begin
            stk_x <= clamp_pos(i_marker_x, stk_len, MEM_W[9:0]);
            stk_y <= clamp_pos(i_marker_y, stk_len, MEM_H[9:0]);
        end
    end

    wire stk_hit = i_marker_valid && (i_edit_mode == EDIT_STICKER) && // block preview after marker timeout leaves a stale last position
                   (i_x_pixel >= stk_x) && (i_x_pixel < stk_x + stk_len) &&
                   (i_y_pixel >= stk_y) && (i_y_pixel < stk_y + stk_len);

    logic stk_hit_q; // aligns hit mask with sticker ROM's 1-clock synchronous read latency
    always_ff @(posedge clk) stk_hit_q <= stk_hit;

    wire [9:0] stk_rom_x = i_x_pixel - stk_x;   // in-box relative coord, 0 .. stk_len-1
    wire [9:0] stk_rom_y = i_y_pixel - stk_y;

    logic [11:0] stk_rgb;
    logic stk_transparent;

    sticker_rom U_STICKER_ROM (
        .clk        (clk),
        .idx        (i_stk_id),
        .size       (i_stk_size),
        .x          (stk_rom_x[4:0]),
        .y          (stk_rom_y[4:0]),
        .rgb        (stk_rgb),
        .transparent(stk_transparent)
    );

    // =========================================================
    // Draw: shows the currently selected color live at the marker (pen tip) position
    // =========================================================
    wire draw_hit = (i_edit_mode == EDIT_DRAW) && i_edit_active &&
                     (i_x_pixel == i_marker_x) && (i_y_pixel == i_marker_y);

    logic [11:0] draw_rgb;
    always_comb begin
        case (i_draw_color)
            3'd0: draw_rgb = 12'h000;  // black
            3'd1: draw_rgb = 12'hF00;  // red
            3'd2: draw_rgb = 12'hF80;  // orange
            3'd3: draw_rgb = 12'hFF0;  // yellow
            3'd4: draw_rgb = 12'h0F0;  // green
            3'd5: draw_rgb = 12'h00F;  // blue
            3'd6: draw_rgb = 12'h309;  // navy
            3'd7: draw_rgb = 12'hF0F;  // purple
            default: draw_rgb = 12'h000;
        endcase
    end

    // =========================================================
    // 4-cut frame: cross divider (quadrant boundary) + outer border.
    // Always on, coordinate-driven only, independent of marker/mode
    // (pure combinational, no state).
    // =========================================================
    localparam [9:0] FRAME_HALF_W = MEM_W[9:0] >> 1;  // 160
    localparam [9:0] FRAME_HALF_H = MEM_H[9:0] >> 1;  // 120
    localparam [9:0] FRAME_T = FRAME_THICKNESS[9:0];

    wire frame_border = (i_x_pixel < FRAME_T) || (i_x_pixel >= MEM_W[9:0] - FRAME_T) ||
                         (i_y_pixel < FRAME_T) || (i_y_pixel >= MEM_H[9:0] - FRAME_T);

    wire frame_cross = (i_x_pixel >= FRAME_HALF_W - (FRAME_T >> 1) && i_x_pixel < FRAME_HALF_W + (FRAME_T >> 1)) ||
                        (i_y_pixel >= FRAME_HALF_H - (FRAME_T >> 1) && i_y_pixel < FRAME_HALF_H + (FRAME_T >> 1));

    wire frame_hit = frame_border || frame_cross;
    wire [11:0] frame_rgb = i_frame_sel ? 12'h000 : 12'hFFF;  // 0:white 1:black

    // =========================================================
    // Cursor: cross-hair centered on the marker position. The exact center
    // pixel is left blank so a drawn pixel there isn't hidden by the cursor.
    // Suppressed in sticker-placement mode since the sticker preview already
    // shows position (otherwise the cursor would overlap the sticker).
    // =========================================================
    wire [9:0] cx_dist = (i_x_pixel >= i_marker_x) ? (i_x_pixel - i_marker_x) : (i_marker_x - i_x_pixel);
    wire [9:0] cy_dist = (i_y_pixel >= i_marker_y) ? (i_y_pixel - i_marker_y) : (i_marker_y - i_y_pixel);

    wire cursor_hit = i_marker_valid && (i_edit_mode != EDIT_STICKER) &&
                       ((i_y_pixel == i_marker_y && i_x_pixel != i_marker_x && cx_dist <= CURSOR_ARM[9:0]) ||
                        (i_x_pixel == i_marker_x && i_y_pixel != i_marker_y && cy_dist <= CURSOR_ARM[9:0]));

    // In draw mode, match the cursor color to the selected draw color so the
    // user can tell the pen color from the cursor alone. Other modes keep the
    // fixed cyan cursor since draw_color is meaningless there.
    wire [11:0] cursor_rgb = (i_edit_mode == EDIT_DRAW) ? draw_rgb : 12'h0FF;

    // Align all sources to the same 3-clock latency as i_mem_rdata: memory/draw/
    // cursor/frame naturally take 3 clocks; sticker's 1-clock ROM latency is
    // compensated via stk_hit_q so it lands at the same pipeline stage (d2).
    logic stk_hit_d1, draw_hit_d1, cursor_hit_d1, frame_hit_d1;
    logic [11:0] stk_rgb_d1, draw_rgb_d1, cursor_rgb_d1, frame_rgb_d1;
    logic stk_hit_d2, draw_hit_d2, cursor_hit_d2, frame_hit_d2;
    logic [11:0] stk_rgb_d2, draw_rgb_d2, cursor_rgb_d2, frame_rgb_d2;
    logic stk_hit_d3, draw_hit_d3, cursor_hit_d3, frame_hit_d3;
    logic [11:0] stk_rgb_d3, draw_rgb_d3, cursor_rgb_d3, frame_rgb_d3;
    always_ff @(posedge clk) begin
        stk_hit_d1    <= stk_hit_q && !stk_transparent; // gate hit with the transparent flag from the same ROM address
        draw_hit_d1   <= draw_hit;
        cursor_hit_d1 <= cursor_hit;
        frame_hit_d1  <= frame_hit;
        stk_rgb_d1    <= stk_rgb;
        draw_rgb_d1   <= draw_rgb;
        cursor_rgb_d1 <= cursor_rgb;
        frame_rgb_d1  <= frame_rgb;

        stk_hit_d2    <= stk_hit_d1;
        draw_hit_d2   <= draw_hit_d1;
        cursor_hit_d2 <= cursor_hit_d1;
        frame_hit_d2  <= frame_hit_d1;
        stk_rgb_d2    <= stk_rgb_d1;
        draw_rgb_d2   <= draw_rgb_d1;
        cursor_rgb_d2 <= cursor_rgb_d1;
        frame_rgb_d2  <= frame_rgb_d1;

        stk_hit_d3    <= stk_hit_d2;
        draw_hit_d3   <= draw_hit_d2;
        cursor_hit_d3 <= cursor_hit_d2;
        frame_hit_d3  <= frame_hit_d2;
        stk_rgb_d3    <= stk_rgb_d2;
        draw_rgb_d3   <= draw_rgb_d2;
        cursor_rgb_d3 <= cursor_rgb_d2;
        frame_rgb_d3  <= frame_rgb_d2;
    end

    // ---- Final priority: sticker > draw > cursor > frame > raw memory ----
    always_comb begin
        if (stk_hit_d2) o_pixel_data = stk_rgb_d2; // ROM-latency-compensated, aligns with the others' 3-clock total
        else if (draw_hit_d3) o_pixel_data = draw_rgb_d3;
        else if (cursor_hit_d3) o_pixel_data = cursor_rgb_d3;
        else if (frame_hit_d3) o_pixel_data = frame_rgb_d3;
        else o_pixel_data = i_mem_rdata;
    end

endmodule
