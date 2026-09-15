`timescale 1ns / 1ps

// =====================================================
// filter_filmlook
//  - Warm "film look" color grade: per-channel gain (R x287/256,
//    G x267/256, B x225/256), clamped back to 4 bits.
//  - 2-stage pipeline: multiply, then clamp + output register.
// =====================================================
module filter_filmlook (
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

    //-----------stage 1: multiply -------------

    logic [12:0] w_s1_R, w_s1_G, w_s1_B;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            w_s1_R <= 13'd0;
            w_s1_G <= 13'd0;
            w_s1_B <= 13'd0;
        end else begin
            w_s1_R <= 9'd287 * i_pixel_data[11:8];
            w_s1_G <= 9'd267 * i_pixel_data[7:4];
            w_s1_B <= 9'd225 * i_pixel_data[3:0];
        end
    end

    //-----------stage 2: clamp + output register --------

    logic [4:0] w_pre_R, w_pre_G, w_pre_B;

    assign w_pre_R = w_s1_R[12:8];
    assign w_pre_G = w_s1_G[12:8];
    assign w_pre_B = w_s1_B[12:8];

    logic [3:0] w_film_R_c, w_film_G_c, w_film_B_c;

    assign w_film_R_c = (w_pre_R > 5'd15) ? 4'd15 : w_pre_R[3:0];
    assign w_film_G_c = (w_pre_G > 5'd15) ? 4'd15 : w_pre_G[3:0];
    assign w_film_B_c = (w_pre_B > 5'd15) ? 4'd15 : w_pre_B[3:0];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            o_pixel_data <= 12'd0;
        end else begin
            o_pixel_data <= {w_film_R_c, w_film_G_c, w_film_B_c};
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

