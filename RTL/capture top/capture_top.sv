`timescale 1ns / 1ps

// =====================================================
// capture_top
//  - Pipeline: capture_downscaler (320x240->160x120, RGB444) -> filter_top
//    (applies the selected filter) -> Capture_Controller (writes into the
//    4-quadrant frame memory).
// =====================================================
module capture_top (
    input logic clk,
    input logic rst,

    input logic       i_cap_req_valid,
    input logic [2:0] i_filter_sel,

    input logic [ 8:0] i_x_pixel,
    input logic [ 7:0] i_y_pixel,
    input logic [15:0] i_pixel_data,
    input logic        i_pixel_valid,

    output logic        o_wr_en,
    output logic [16:0] o_wr_addr,
    output logic [11:0] o_wr_data,

    output logic       o_cap_done,
    output logic [2:0] o_cap_count,
    output logic       o_cap_req_ready,
    output logic       o_all_done
);

    logic w_ds_pixel_valid;
    logic [11:0] w_ds_pixel_data;
    logic [7:0] w_ds_x_pixel;
    logic [6:0] w_ds_y_pixel;

    logic w_filt_pixel_valid;
    logic [11:0] w_filt_pixel_data;
    logic [7:0] w_filt_x_pixel;
    logic [6:0] w_filt_y_pixel;

    capture_downscaler u_downscaler ( // renamed to capture_downscaler to avoid a name clash with the Edit Engine's downscaler
        .clk          (clk),
        .rst          (rst),
        .i_x_pixel    (i_x_pixel),
        .i_y_pixel    (i_y_pixel),
        .i_pixel_data (i_pixel_data),
        .i_pixel_valid(i_pixel_valid),
        .o_pixel_valid(w_ds_pixel_valid),
        .o_pixel_data (w_ds_pixel_data),
        .o_x_pixel    (w_ds_x_pixel),
        .o_y_pixel    (w_ds_y_pixel)
    );

    filter_top u_filter_top (
        .clk          (clk),
        .rst          (rst),
        .i_pixel_valid(w_ds_pixel_valid),
        .i_pixel_data (w_ds_pixel_data),
        .i_x_pixel    (w_ds_x_pixel),
        .i_y_pixel    (w_ds_y_pixel),
        .i_filter_sel (i_filter_sel),
        .o_pixel_valid(w_filt_pixel_valid),
        .o_pixel_data (w_filt_pixel_data),
        .o_x_pixel    (w_filt_x_pixel),
        .o_y_pixel    (w_filt_y_pixel)
    );

    Capture_Controller u_capture_controller (
        .clk            (clk),
        .rst            (rst),
        .i_pixel_valid  (w_filt_pixel_valid),
        .i_pixel_data   (w_filt_pixel_data),
        .i_x_pixel      (w_filt_x_pixel),
        .i_y_pixel      (w_filt_y_pixel),
        .i_cap_req_valid(i_cap_req_valid),
        .o_wr_en        (o_wr_en),
        .o_wr_addr      (o_wr_addr),
        .o_wr_data      (o_wr_data),
        .o_cap_done     (o_cap_done),
        .o_cap_count    (o_cap_count),
        .o_cap_req_ready(o_cap_req_ready),
        .o_all_done     (o_all_done)
    );
endmodule
