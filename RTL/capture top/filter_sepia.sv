`timescale 1ns / 1ps

// =====================================================
// filter_sepia
//  - Classic sepia tone matrix applied to RGB444:
//      R' = 0.393R + 0.769G + 0.189B
//      G' = 0.349R + 0.686G + 0.168B
//      B' = 0.272R + 0.534G + 0.131B
//    (coefficients scaled to 8-bit integers), clamped back to 4 bits.
//  - 2-stage pipeline: multiply, then sum + clamp + output register.
// =====================================================
module filter_sepia (
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

    localparam LATENCY = 2;

    // ----------stage 1: multiply results needed for R', G', B'---------------

    logic [11:0] r_s1_RR, r_s1_RG, r_s1_RB;
    logic [11:0] r_s1_GR, r_s1_GG, r_s1_GB;
    logic [11:0] r_s1_BR, r_s1_BG, r_s1_BB;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            r_s1_RR <= 12'd0;
            r_s1_RG <= 12'd0;
            r_s1_RB <= 12'd0;
            r_s1_GR <= 12'd0;
            r_s1_GG <= 12'd0;
            r_s1_GB <= 12'd0;
            r_s1_BR <= 12'd0;
            r_s1_BG <= 12'd0;
            r_s1_BB <= 12'd0;
        end else begin
            r_s1_RR <= 8'd101 * i_pixel_data[11:8];
            r_s1_RG <= 8'd197 * i_pixel_data[7:4];
            r_s1_RB <= 8'd48 * i_pixel_data[3:0];
            r_s1_GR <= 8'd89 * i_pixel_data[11:8];
            r_s1_GG <= 8'd176 * i_pixel_data[7:4];
            r_s1_GB <= 8'd43 * i_pixel_data[3:0];
            r_s1_BR <= 8'd70 * i_pixel_data[11:8];
            r_s1_BG <= 8'd137 * i_pixel_data[7:4];
            r_s1_BB <= 8'd34 * i_pixel_data[3:0];
        end
    end

    // ----------stage 2: sum + clamp + output register ---------------

    logic [12:0] w_sum_R, w_sum_G, w_sum_B;

    assign w_sum_R = r_s1_RR + r_s1_RG + r_s1_RB;
    assign w_sum_G = r_s1_GR + r_s1_GG + r_s1_GB;
    assign w_sum_B = r_s1_BR + r_s1_BG + r_s1_BB;

    logic [4:0] w_pre_R, w_pre_G, w_pre_B;

    assign w_pre_R = w_sum_R[12:8];
    assign w_pre_G = w_sum_G[12:8];
    assign w_pre_B = w_sum_B[12:8];

    logic [3:0] w_sepia_R_c, w_sepia_G_c, w_sepia_B_c;

    assign w_sepia_R_c = (w_pre_R > 5'd15) ? 4'd15 : w_pre_R[3:0];
    assign w_sepia_G_c = (w_pre_G > 5'd15) ? 4'd15 : w_pre_G[3:0];
    assign w_sepia_B_c = (w_pre_B > 5'd15) ? 4'd15 : w_pre_B[3:0];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            o_pixel_data <= 12'd0;
        end else begin
            o_pixel_data <= {w_sepia_R_c, w_sepia_G_c, w_sepia_B_c};
        end
    end

    logic r_valid_d1, r_valid_d2;
    logic [7:0] r_x_d1, r_x_d2;
    logic [6:0] r_y_d1, r_y_d2;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            r_valid_d1 <= 1'b0;
            r_valid_d2 <= 1'b0;
            r_x_d1     <= 8'd0;
            r_x_d2     <= 8'd0;
            r_y_d1     <= 7'd0;
            r_y_d2     <= 7'd0;
        end else begin
            r_valid_d1 <= i_pixel_valid;
            r_valid_d2 <= r_valid_d1;
            r_x_d1     <= i_x_pixel;
            r_x_d2     <= r_x_d1;
            r_y_d1     <= i_y_pixel;
            r_y_d2     <= r_y_d1;
        end
    end

    assign o_pixel_valid = r_valid_d2;
    assign o_x_pixel     = r_x_d2;
    assign o_y_pixel     = r_y_d2;

endmodule
