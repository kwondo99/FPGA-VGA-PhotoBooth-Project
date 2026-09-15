`timescale 1ns / 1ps

// =====================================================
// filter_top
//  - Runs all 4 filters (grayscale/sepia/softfocus/filmlook) in parallel
//    and muxes the selected one to the output.
//  - Filter selection is latched at frame start (x=0,y=0) into
//    r_safe_filter_sel so a mid-frame selection change doesn't produce
//    a torn frame with mixed filters.
// =====================================================
module filter_top (
    input  logic        clk,
    input  logic        rst,
    input  logic        i_pixel_valid,
    input  logic [11:0] i_pixel_data,
    input  logic [ 7:0] i_x_pixel,
    input  logic [ 6:0] i_y_pixel,
    input  logic [ 2:0] i_filter_sel,
    output logic        o_pixel_valid,
    output logic [11:0] o_pixel_data,
    output logic [ 7:0] o_x_pixel,
    output logic [ 6:0] o_y_pixel
);

    logic [11:0] w_gray_data, w_sepia_data, w_soft_data, w_film_data;
    logic w_gray_valid, w_sepia_valid, w_soft_valid, w_film_valid;
    logic [7:0] w_gray_x, w_sepia_x, w_soft_x, w_film_x;
    logic [6:0] w_gray_y, w_sepia_y, w_soft_y, w_film_y;

    filter_grayscale u_filter_grayscale (
        .clk(clk),
        .rst(rst),
        .i_pixel_valid(i_pixel_valid),
        .i_pixel_data(i_pixel_data),
        .i_x_pixel(i_x_pixel),
        .i_y_pixel(i_y_pixel),
        .o_pixel_valid(w_gray_valid),
        .o_pixel_data(w_gray_data),
        .o_x_pixel(w_gray_x),
        .o_y_pixel(w_gray_y)
    );

    filter_sepia u_filter_sepia (
        .clk(clk),
        .rst(rst),
        .i_pixel_valid(i_pixel_valid),
        .i_pixel_data(i_pixel_data),
        .i_x_pixel(i_x_pixel),
        .i_y_pixel(i_y_pixel),
        .o_pixel_valid(w_sepia_valid),
        .o_pixel_data(w_sepia_data),
        .o_x_pixel(w_sepia_x),
        .o_y_pixel(w_sepia_y)
    );

    filter_softfocus #(
        .IMG_WIDTH(160),
        .BLEND_NUM(13)
    ) u_filter_softfocus (
        .clk(clk),
        .rst(rst),
        .i_pixel_valid(i_pixel_valid),
        .i_pixel_data(i_pixel_data),
        .i_x_pixel(i_x_pixel),
        .i_y_pixel(i_y_pixel),
        .o_pixel_valid(w_soft_valid),
        .o_pixel_data(w_soft_data),
        .o_x_pixel(w_soft_x),
        .o_y_pixel(w_soft_y)
    );

    filter_filmlook u_filter_filmlook (
        .clk(clk),
        .rst(rst),
        .i_pixel_valid(i_pixel_valid),
        .i_pixel_data(i_pixel_data),
        .i_x_pixel(i_x_pixel),
        .i_y_pixel(i_y_pixel),
        .o_pixel_valid(w_film_valid),
        .o_pixel_data(w_film_data),
        .o_x_pixel(w_film_x),
        .o_y_pixel(w_film_y)
    );

    logic [2:0] r_safe_filter_sel;
    logic w_frame_start_in;
    assign w_frame_start_in = i_pixel_valid && (i_x_pixel == 8'd0) && (i_y_pixel == 7'd0);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) r_safe_filter_sel <= 3'b000;
        else if (w_frame_start_in) r_safe_filter_sel <= i_filter_sel;
    end

    logic w_mux_valid;
    logic [11:0] w_mux_data;
    logic [7:0] w_mux_x;
    logic [6:0] w_mux_y;

    always_comb begin
        case (r_safe_filter_sel)
            3'b001: begin
                w_mux_valid = w_gray_valid;
                w_mux_data  = w_gray_data;
                w_mux_x     = w_gray_x;
                w_mux_y     = w_gray_y;
            end
            3'b010: begin
                w_mux_valid = w_sepia_valid;
                w_mux_data  = w_sepia_data;
                w_mux_x     = w_sepia_x;
                w_mux_y     = w_sepia_y;
            end
            3'b011: begin
                w_mux_valid = w_soft_valid;
                w_mux_data  = w_soft_data;
                w_mux_x     = w_soft_x;
                w_mux_y     = w_soft_y;
            end
            3'b100: begin
                w_mux_valid = w_film_valid;
                w_mux_data  = w_film_data;
                w_mux_x     = w_film_x;
                w_mux_y     = w_film_y;
            end
            default: begin
                w_mux_valid = i_pixel_valid;
                w_mux_data  = i_pixel_data;
                w_mux_x     = i_x_pixel;
                w_mux_y     = i_y_pixel;
            end
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            o_pixel_valid <= 1'b0;
            o_pixel_data  <= 12'd0;
            o_x_pixel     <= 8'd0;
            o_y_pixel     <= 7'd0;
        end else begin
            o_pixel_valid <= w_mux_valid;
            o_pixel_data  <= w_mux_data;
            o_x_pixel     <= w_mux_x;
            o_y_pixel     <= w_mux_y;
        end
    end

endmodule
