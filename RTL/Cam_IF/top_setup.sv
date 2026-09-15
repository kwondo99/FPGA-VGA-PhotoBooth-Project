`timescale 1ns / 1ps

// =====================================================
// top_setup
//  - Wires setup_rom -> setup_fsm -> I2C_Master_top to run the OV7670
//    register configuration sequence at power-up.
// =====================================================
module top_setup(
    input  logic clk,
    input  logic reset,

    output logic scl,
    inout  wire  sda, // net type, not a variable, to match Cam_IF's sda and avoid Vivado version-dependent inout errors

    output logic setup_done
);

    // setup_fsm <-> setup_rom
    logic [6:0] idx;
    logic [7:0] reg_addr;
    logic [7:0] reg_data;

    // setup_fsm <-> i2c_master
    logic [7:0] tx_data;

    logic cmd_start;
    logic cmd_write;
    logic cmd_stop;

    logic done;

    // I2C signals currently unused
    logic [7:0] rx_data;
    logic ack_out;
    logic busy;


    setup_rom u_setup_rom (
        .setup_idx (idx),
        .reg_addr  (reg_addr),
        .reg_data  (reg_data)
    );


    setup_fsm u_setup_fsm (
        .clk          (clk),
        .reset        (reset),

        .idx          (idx),
        .reg_addr     (reg_addr),
        .reg_data     (reg_data),

        .tx_data      (tx_data),
        .o_cmd_start  (cmd_start),
        .o_cmd_write  (cmd_write),
        .o_cmd_stop   (cmd_stop),
        .o_setup_done (setup_done),

        .done         (done)
    );


    I2C_Master_top u_i2c_master (
        .clk       (clk),
        .reset     (reset),

        .cmd_start (cmd_start),
        .cmd_write (cmd_write),
        .cmd_read  (1'b0),
        .cmd_stop  (cmd_stop),

        .tx_data   (tx_data),
        .rx_data   (rx_data),

        .ack_in    (1'b1),
        .ack_out   (ack_out),

        .busy      (busy),
        .done      (done),

        .scl       (scl),
        .sda       (sda)
    );

endmodule
