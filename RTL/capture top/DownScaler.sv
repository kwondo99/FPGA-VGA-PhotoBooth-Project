`timescale 1ns / 1ps

// =====================================================
// capture_downscaler
//  - Downsamples the 320x240 camera stream to 160x120 by taking every
//    other pixel (even x, even y) and converts RGB565 -> RGB444.
//  - Named capture_downscaler (not downscaler) to avoid a Vivado
//    design-unit name clash with the Edit Engine's downscaler module.
// =====================================================
module capture_downscaler #(
    parameter WIDTH_320  = $clog2(320) - 1,
    parameter HEIGHT_240 = $clog2(240) - 1,
    parameter WIDTH_160  = $clog2(160) - 1,
    parameter HEIGHT_120 = $clog2(120) - 1
) (

    // global signals
    input logic clk,
    input logic rst,

    // camera interface : input
    input logic [ WIDTH_320:0] i_x_pixel,
    input logic [HEIGHT_240:0] i_y_pixel,
    input logic [        15:0] i_pixel_data,  // RGB565
    input logic                i_pixel_valid,

    // filter top : output
    output logic                o_pixel_valid,
    output logic [        11:0] o_pixel_data,
    output logic [ WIDTH_160:0] o_x_pixel,
    output logic [HEIGHT_120:0] o_y_pixel

);

    logic [11:0] pixel_data_12bit;  // RGB444

    assign pixel_data_12bit = {
        i_pixel_data[15:12], i_pixel_data[10:7], i_pixel_data[4:1]
    };  // RGB565 -> RGB444

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            o_pixel_valid <= 1'b0;
            o_pixel_data  <= 12'd0;
            o_x_pixel     <= 0;
            o_y_pixel     <= 0;
        end else begin
            if (i_x_pixel[0] == 0 && i_y_pixel[0] == 0 && i_pixel_valid) begin
                o_pixel_valid <= 1'b1;
                o_pixel_data  <= pixel_data_12bit;  // 160x120
                o_x_pixel     <= i_x_pixel >> 1;
                o_y_pixel     <= i_y_pixel >> 1;
            end else begin
                o_pixel_valid <= 1'b0;
                o_pixel_data  <= 12'd0;
                o_x_pixel     <= 0;
                o_y_pixel     <= 0;
            end
        end
    end

endmodule
