`timescale 1ns / 1ps

// =====================================================
// downscaler
//  - VGA controller outputs 640x480 coordinates; scale to 320x240
//    before entering the edit_engine pipeline.
//  - Marker detection is already native 320x240, not handled here.
//  - Combinational (zero-latency), does not affect edit_engine pipeline depth.
// =====================================================
module downscaler (
    input  logic [9:0] i_x_pixel,   // 640 scale
    input  logic [9:0] i_y_pixel,
    output logic [9:0] o_x_pixel,   // 320 scale
    output logic [9:0] o_y_pixel
);

    assign o_x_pixel = i_x_pixel >> 1;
    assign o_y_pixel = i_y_pixel >> 1;

endmodule
