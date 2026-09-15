`timescale 1ns / 1ps

module tick_gen #(
    parameter integer TICK_DIV = 100_000
) (
    input  logic clk    ,
    input  logic rst    ,
    output logic o_tick
);

    logic [16:0] tick_cnt_reg, tick_cnt_next;
    logic        tick_reg, tick_next;

    assign o_tick = tick_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tick_cnt_reg <= 17'b0;
            tick_reg     <= 1'b0;
        end else begin
            tick_cnt_reg <= tick_cnt_next;
            tick_reg     <= tick_next;
        end
    end

    always_comb begin
        tick_cnt_next = tick_cnt_reg;
        tick_next     = 1'b0;

        if (tick_cnt_reg == TICK_DIV - 1) begin
            tick_cnt_next = 17'b0;
            tick_next     = 1'b1;
        end else begin
            tick_cnt_next = tick_cnt_reg + 1'b1;
        end
    end

endmodule
