`timescale 1ns / 1ps

// =====================================================
// Cam_IF
//  - Top-level OV7670 interface: register setup (I2C), XCLK generation,
//    and pixel reception (RGB565, 320x240).
// =====================================================
module Cam_IF #(
    parameter IMG_W = 320,
    parameter IMG_H = 240,
    parameter DW    = 16,
    parameter AW    = $clog2(IMG_W * IMG_H)
)(
    // system
    input  logic clk,
    input  logic reset,
    input  logic reset_pclk, // reset release for pclk-domain registers, synchronized to pclk

    //system controller
    input logic i_cam_stream_en,
    output logic o_cam_ready,


    // OV7670
    input  logic       pclk,
    output logic       xclk,
    input  logic       cam_href,
    input  logic       cam_vsync,
    input  logic [7:0] cam_data,

    output logic scl,
    inout  wire  sda,

    // pixel output
    output logic          w_en,
    //output logic [AW-1:0] w_addr,
    output logic [DW-1:0] w_data,
    output logic [8:0]    pixel_x,
    output logic [7:0]    pixel_y
);

    logic [9:0] pixel_x_full; // receives ov7670_mem_controller's 10-bit x output without truncation
    logic [8:0] pixel_y_full; // receives ov7670_mem_controller's 9-bit y output without truncation
    assign pixel_x = pixel_x_full[8:0]; // pass only the low 9 bits needed for width 320 to Cam_IF's interface
    assign pixel_y = pixel_y_full[7:0]; // pass only the low 8 bits needed for height 240 to Cam_IF's interface

    //==================================================
    // OV7670 register setup
    //==================================================
    top_setup u_top_setup (
        .clk        (clk),
        .reset        (reset),
        .scl        (scl),
        .sda        (sda),
        .setup_done (o_cam_ready)
    );


    //==================================================
    // OV7670 XCLK
    // 100 MHz -> 25 MHz
    //==================================================
    cam_xclk_gen u_cam_xclk_gen (
        .clk   (clk),
        .reset (reset),
        .xclk  (xclk)
    );


    //==================================================
    // OV7670 pixel receiver
    // 8-bit x 2 -> RGB565
    // + address / x / y
    //==================================================
    ov7670_mem_controller #(
        .IMG_W (IMG_W),
        .IMG_H (IMG_H),
        .DW    (DW),
        .AW    (AW)
    ) u_ov7670_mem_controller (
        .pclk      (pclk),
        .reset     (reset_pclk), // pclk-domain receiver uses the pclk-synchronized reset
        .i_cam_stream_en (i_cam_stream_en),

        .cam_href  (cam_href),
        .cam_vsync (cam_vsync),
        .cam_data  (cam_data),

        .we         (w_en),
        .wAddr      (), // intentionally unused: raw address (pre-downscale/pre-4-way split) isn't the final frame-memory address
        .wData      (w_data),

        .x          (pixel_x_full), // full-width signal matching the 10-bit output port, avoids an 8-689 width-mismatch warning
        .y          (pixel_y_full)  // full-width signal matching the 9-bit output port, avoids an 8-689 width-mismatch warning
    );


endmodule



//======================================================
// Camera XCLK Generator
// 100 MHz -> 25 MHz, 50% duty
//
// counter : 00 01 10 11 00 ...
// xclk    : 0  0  1  1  0  ...
//======================================================
module cam_xclk_gen (
    input  logic clk,
    input  logic reset,
    output logic xclk
);

    logic [1:0] div_cnt;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            div_cnt <= 2'b00;
        end
        else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end

    assign xclk = div_cnt[1];

endmodule
