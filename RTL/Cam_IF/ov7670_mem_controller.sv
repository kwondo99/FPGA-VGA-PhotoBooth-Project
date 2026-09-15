`timescale 1ns / 1ps


module ov7670_mem_controller #(
    parameter IMG_W = 320,
    parameter IMG_H = 240,
    parameter DW = 16,
    parameter AW = $clog2(IMG_W * IMG_H)
    )(
    input logic pclk,
    input logic reset,
    input logic i_cam_stream_en,
    input logic cam_href,
    input logic cam_vsync,
    input logic [7:0] cam_data,

    output logic we,
    output logic [AW-1:0]wAddr,
    output logic [DW-1:0]wData,
    output logic [9:0] x,
    output logic [8:0] y
    );

    cam_pixel_counter #(
    .IMG_W(IMG_W),
    .IMG_H(IMG_H)
    ) u_pixel_counter (
        .pclk      (pclk),
        .reset     (reset),
        .we        (we),
        .cam_vsync (cam_vsync),
        .x         (x),
        .y         (y)
    );


    logic byteSel;
    logic [15:0] px_data;
    logic stream_active;

    assign wData = px_data;

    always_ff @( posedge pclk or posedge reset ) begin
        if (reset ) begin
            wAddr <= 0;
            byteSel <= 0;
            px_data <= 0;
            we <= 0;
            stream_active <= 0;
        end

        else begin
            we <= 0;
            if(we) wAddr <= wAddr + 1;
            if(cam_vsync) begin
                wAddr <= 0;
                byteSel <= 0;

                if (i_cam_stream_en)
                    stream_active <= 1;
                else
                    stream_active <= 0;

            end else if (stream_active && cam_href) begin
                byteSel <= ~byteSel;
                if(!byteSel) begin
                    px_data[15:8] <= cam_data;
                end
                else begin
                    px_data[7:0] <= cam_data;
                    we <= 1;
                end
            end
        end
    end

endmodule


module cam_pixel_counter #(
    parameter IMG_W = 640,
    parameter IMG_H = 480
)(
    input  logic       pclk,
    input  logic       reset,
    input  logic       we,
    input  logic       cam_vsync,

    output logic [9:0] x,
    output logic [8:0] y
);

    always_ff @(posedge pclk or posedge reset) begin
        if (reset) begin
            x <= 0;
            y <= 0;
        end
        else if (cam_vsync) begin
            x <= 0;
            y <= 0;
        end
        else if (we) begin
            if (x == IMG_W-1) begin
                x <= 0;

                if (y == IMG_H-1)
                    y <= 0;
                else
                    y <= y + 1;
            end
            else begin
                x <= x + 1;
            end
        end
    end

endmodule