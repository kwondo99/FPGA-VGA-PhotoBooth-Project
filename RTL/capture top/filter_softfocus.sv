`timescale 1ns / 1ps

// =====================================================
// filter_softfocus
//  - 3x3 Gaussian blur (line-buffered) blended with the original pixel
//    at a fixed ratio (BLEND_NUM/16), producing a soft-focus look.
//  - Does not assert i_pixel_valid for the first 2 rows/columns, since
//    the 3x3 window isn't fully populated there.
// =====================================================
module filter_softfocus #(
    parameter IMG_WIDTH = 160,
    parameter BLEND_NUM = 13
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        i_pixel_valid,
    input  logic [11:0] i_pixel_data,
    input  logic [ 7:0] i_x_pixel,
    input  logic [ 6:0] i_y_pixel,
    output logic        o_pixel_valid,
    output logic [11:0] o_pixel_data,
    output logic [ 7:0] o_x_pixel,
    output logic [ 6:0] o_y_pixel
);

    logic [11:0] r_linebuf_a[0:IMG_WIDTH-1];
    logic [11:0] r_linebuf_b[0:IMG_WIDTH-1];

    logic [11:0] r_row0_d0, r_row0_d1, r_row0_d2;
    logic [11:0] r_row1_d0, r_row1_d1, r_row1_d2;
    logic [11:0] r_row2_d0, r_row2_d1, r_row2_d2;

    always_ff @(posedge clk) begin
        if (i_pixel_valid) begin
            r_row0_d0 <= r_row0_d1;
            r_row0_d1 <= r_row0_d2;
            r_row0_d2 <= r_linebuf_b[i_x_pixel];
            r_row1_d0 <= r_row1_d1;
            r_row1_d1 <= r_row1_d2;
            r_row1_d2 <= r_linebuf_a[i_x_pixel];
            r_row2_d0 <= r_row2_d1;
            r_row2_d1 <= r_row2_d2;
            r_row2_d2 <= i_pixel_data;

            r_linebuf_b[i_x_pixel] <= r_linebuf_a[i_x_pixel];
            r_linebuf_a[i_x_pixel] <= i_pixel_data;
        end
    end

    // 3x3 Gaussian kernel
    logic [7:0] w_sum_R, w_sum_G, w_sum_B;

    assign w_sum_R = r_row0_d0[11:8] + 2*r_row0_d1[11:8] + r_row0_d2[11:8]
                    + 2*r_row1_d0[11:8] + 4*r_row1_d1[11:8] + 2*r_row1_d2[11:8]
                    + r_row2_d0[11:8] + 2*r_row2_d1[11:8] + r_row2_d2[11:8];

    assign w_sum_G = r_row0_d0[7:4] + 2*r_row0_d1[7:4] + r_row0_d2[7:4]
                    + 2*r_row1_d0[7:4] + 4*r_row1_d1[7:4] + 2*r_row1_d2[7:4]
                    + r_row2_d0[7:4] + 2*r_row2_d1[7:4] + r_row2_d2[7:4];

    assign w_sum_B = r_row0_d0[3:0] + 2*r_row0_d1[3:0] + r_row0_d2[3:0]
                    + 2*r_row1_d0[3:0] + 4*r_row1_d1[3:0] + 2*r_row1_d2[3:0]
                    + r_row2_d0[3:0] + 2*r_row2_d1[3:0] + r_row2_d2[3:0];

    // Register between the 3x3 weighted sum and the blend stage to split the
    // worst-case combinational path for 100 MHz timing.
    logic [7:0]  r_sum_R, r_sum_G, r_sum_B; // holds the per-channel weighted sums one clock before blending
    logic [11:0] r_center;                  // original center pixel, registered on the same clock as the sums
    logic        r_valid;                   // valid moved to the same pipeline stage as the data
    logic [7:0]  r_x;                       // x coordinate moved to the same pipeline stage as the data
    logic [6:0]  r_y;                       // y coordinate moved to the same pipeline stage as the data

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            r_sum_R  <= 8'd0;
            r_sum_G  <= 8'd0;
            r_sum_B  <= 8'd0;
            r_center <= 12'd0;
            r_valid  <= 1'b0;
            r_x      <= 8'd0;
            r_y      <= 7'd0;
        end else begin
            r_sum_R  <= w_sum_R; // terminates the long weighted-sum path at this register
            r_sum_G  <= w_sum_G;
            r_sum_B  <= w_sum_B;
            r_center <= r_row1_d1; // captures the blend source in the same cycle as the weighted sum
            r_valid  <= i_pixel_valid && (i_x_pixel >= 8'd2) && (i_y_pixel >= 7'd2); // delay the valid condition by one clock to match the data
            r_x      <= i_x_pixel; // registers the x coordinate matching this filter result
            r_y      <= i_y_pixel; // registers the y coordinate matching this filter result
        end
    end

    logic [3:0] w_soft_R, w_soft_G, w_soft_B;

    assign w_soft_R = r_sum_R[7:4]; // start the blend path from the pipelined weighted sum
    assign w_soft_G = r_sum_G[7:4];
    assign w_soft_B = r_sum_B[7:4];

    logic [3:0] w_orig_R, w_orig_G, w_orig_B;

    assign w_orig_R = r_center[11:8]; // registered center pixel, aligned with the weighted sum
    assign w_orig_G = r_center[7:4];
    assign w_orig_B = r_center[3:0];

    logic [7:0] w_blend_R, w_blend_G, w_blend_B;

    assign w_blend_R = w_orig_R * (16 - BLEND_NUM) + w_soft_R * BLEND_NUM;
    assign w_blend_G = w_orig_G * (16 - BLEND_NUM) + w_soft_G * BLEND_NUM;
    assign w_blend_B = w_orig_B * (16 - BLEND_NUM) + w_soft_B * BLEND_NUM;

    logic [3:0] w_out_R, w_out_G, w_out_B;

    assign w_out_R = w_blend_R[7:4];
    assign w_out_G = w_blend_G[7:4];
    assign w_out_B = w_blend_B[7:4];

    assign o_pixel_data = {w_out_R, w_out_G, w_out_B};
    assign o_pixel_valid = r_valid; // valid for the same pipeline stage as the pixel data
    assign o_x_pixel = r_x;         // x for the same pipeline stage as the pixel data
    assign o_y_pixel = r_y;         // y for the same pipeline stage as the pixel data

endmodule
