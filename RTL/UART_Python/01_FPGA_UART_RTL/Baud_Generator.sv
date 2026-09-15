`timescale 1ns / 1ps

module Baud_Generator #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 1_000_000,
    parameter int DIVISOR   = CLK_FREQ / BAUD_RATE,
    parameter int CNT_WIDTH = (DIVISOR <= 1) ? 1 : $clog2(DIVISOR)
)(
    input  logic clk,
    input  logic rst,
    output logic o_baud_tick
);

    logic [CNT_WIDTH-1:0] count;

    always_ff @(posedge clk) begin
        if (rst) begin
            count       <= '0;
            o_baud_tick <= 1'b0;
        end
        else begin
            o_baud_tick <= 1'b0;

            if (DIVISOR <= 1) begin
                count       <= '0;
                o_baud_tick <= 1'b1;
            end
            else if (count == DIVISOR - 1) begin
                count       <= '0;
                o_baud_tick <= 1'b1;
            end
            else begin
                count <= count + 1'b1;
            end
        end
    end

endmodule
