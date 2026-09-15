`timescale 1ns / 1ps

module result_auto_restart #(
    parameter integer RESULT_TICKS = 20_000
) (
    input  logic clk         ,
    input  logic rst_manual  ,
    input  logic i_tick      ,
    input  logic i_in_result ,
    input  logic i_ext_btn   ,
    output logic o_restart
);

    localparam integer HOLD_CLKS = 32;

    logic [14:0] tick_cnt_reg, tick_cnt_next;
    logic        armed_reg, armed_next;
    logic [5:0]  hold_cnt_reg, hold_cnt_next;
    logic        restart_reg, restart_next;
    logic        fire;

    assign o_restart = restart_reg;

    always_ff @(posedge clk or posedge rst_manual) begin
        if (rst_manual) begin
            tick_cnt_reg <= 15'd0;
            armed_reg    <= 1'b1;
            hold_cnt_reg <= 6'd0;
            restart_reg  <= 1'b0;
        end else begin
            tick_cnt_reg <= tick_cnt_next;
            armed_reg    <= armed_next;
            hold_cnt_reg <= hold_cnt_next;
            restart_reg  <= restart_next;
        end
    end

    always_comb begin
        tick_cnt_next = tick_cnt_reg;
        armed_next    = armed_reg;
        hold_cnt_next = hold_cnt_reg;
        restart_next  = 1'b0;

        if (!i_in_result) begin
            tick_cnt_next = 15'd0;
            armed_next    = 1'b1;
        end else if (i_tick && (tick_cnt_reg != RESULT_TICKS - 1)) begin
            tick_cnt_next = tick_cnt_reg + 15'd1;
        end

        fire = i_in_result && armed_reg &&
               (i_ext_btn ||
                (i_tick && (tick_cnt_reg == RESULT_TICKS - 1)));

        if (fire) begin
            armed_next    = 1'b0;
            hold_cnt_next = HOLD_CLKS - 1;
            restart_next  = 1'b1;
        end else if (hold_cnt_reg != 0) begin
            hold_cnt_next = hold_cnt_reg - 1'b1;
            restart_next  = 1'b1;
        end
    end

endmodule
