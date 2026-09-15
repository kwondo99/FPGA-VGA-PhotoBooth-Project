`timescale 1ns / 1ps

module reset_sync (
    input  logic clk       ,
    input  logic i_rst_raw ,
    output logic o_rst
);

    (* ASYNC_REG = "TRUE" *) logic [1:0] rst_sync_reg;
    logic [1:0] rst_sync_next;

    assign o_rst = rst_sync_reg[1];

    always_ff @(posedge clk or posedge i_rst_raw) begin
        if (i_rst_raw) begin
            rst_sync_reg <= 2'b11;
        end else begin
            rst_sync_reg <= rst_sync_next;
        end
    end

    always_comb begin
        rst_sync_next = {rst_sync_reg[0], 1'b0};
    end

endmodule
