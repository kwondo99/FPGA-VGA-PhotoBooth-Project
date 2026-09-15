`timescale 1ns / 1ps

// =====================================================
// filter_grayscale
//  - Luma-weighted grayscale (Y = 0.299R + 0.587G + 0.114B, scaled to
//    8-bit coefficients) replicated across all 3 channels.
//  - 2-stage pipeline: multiply, then sum + extract + output register.
// =====================================================
module filter_grayscale (
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

    // --------stage 1: multiply------------

    logic [11:0] r_s1_R, r_s1_G, r_s1_B;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            r_s1_R <= 12'd0;
            r_s1_G <= 12'd0;
            r_s1_B <= 12'd0;
        end else begin
            r_s1_R <= 8'd77 * i_pixel_data[11:8];
            r_s1_G <= 8'd150 * i_pixel_data[7:4];
            r_s1_B <= 8'd29 * i_pixel_data[3:0];
        end
    end

    // --------stage 2: sum + extract high bits + output register------------

    logic [11:0] w_y_sum;
    logic [ 3:0] w_gray;

    assign w_y_sum = r_s1_R + r_s1_G + r_s1_B;
    assign w_gray  = w_y_sum[11:8];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            o_pixel_data <= 12'd0;
        end else begin
            o_pixel_data <= {w_gray, w_gray, w_gray};
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
