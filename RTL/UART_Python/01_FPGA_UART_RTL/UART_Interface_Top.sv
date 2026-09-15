`timescale 1ns / 1ps

module UART_Interface_Top #(
    parameter int IMG_W = 640,
    parameter int IMG_H = 480,
    parameter int CLK_FREQ = 100_000_000,
    parameter int BAUD_RATE = 1_000_000,
    parameter logic [3:0] STATE_EXPORT = 4'h5
)(
    input  logic        clk,
    input  logic        rst,

    input  logic [31:0] i_status_data,
    input  logic        i_status_valid,
    output logic        o_status_ready,
    output logic        o_send_done,

    input  logic [11:0] i_pixel_data,
    input  logic        i_pixel_valid,
    output logic        o_pixel_ready,

    output logic        o_uart_tx
);

    logic       baud_tick;
    logic       tx_start;
    logic       tx_busy;
    logic       tx_done;
    logic [7:0] tx_data;

    Send_Control #(
        .IMG_W        (IMG_W),
        .IMG_H        (IMG_H),
        .STATE_EXPORT (STATE_EXPORT)
    ) U_Send_Control (
        .clk            (clk),
        .rst            (rst),
        .i_status_data  (i_status_data),
        .i_status_valid (i_status_valid),
        .o_status_ready (o_status_ready),
        .o_send_done    (o_send_done),
        .i_pixel_data   (i_pixel_data),
        .i_pixel_valid  (i_pixel_valid),
        .o_pixel_ready  (o_pixel_ready),
        .i_tx_busy      (tx_busy),
        .i_tx_done      (tx_done),
        .o_tx_data      (tx_data),
        .o_tx_start     (tx_start)
    );

    Baud_Generator #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) U_Baud_Generator (
        .clk         (clk),
        .rst         (rst),
        .o_baud_tick (baud_tick)
    );

    UART_TX U_UART_TX (
        .clk         (clk),
        .rst         (rst),
        .i_baud_tick (baud_tick),
        .i_tx_data   (tx_data),
        .i_tx_start  (tx_start),
        .o_tx_busy   (tx_busy),
        .o_tx_done   (tx_done),
        .o_uart_tx   (o_uart_tx)
    );

endmodule
