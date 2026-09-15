`timescale 1ns / 1ps

module switch_sync (
    input  logic clk    ,
    input  logic rst    ,
    input  logic i_tick ,
    input  logic i_sw   ,
    output logic o_sw
);

    (* ASYNC_REG = "TRUE" *) logic [1:0] sw_sync_reg;
    logic [1:0] sw_sync_next;
    logic [7:0] sync_reg, sync_next;
    logic       sw_reg, sw_next;

    assign o_sw = sw_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sw_sync_reg <= 2'b00;
            sync_reg    <= 8'h00;
            sw_reg      <= 1'b0;
        end else begin
            sw_sync_reg <= sw_sync_next;
            sync_reg    <= sync_next;
            sw_reg      <= sw_next;
        end
    end

    always_comb begin
        sw_sync_next = {sw_sync_reg[0], i_sw};
        sync_next    = sync_reg;
        sw_next      = sw_reg;

        if (i_tick) begin
            sync_next = {sw_sync_reg[1], sync_reg[7:1]};

            if (&sync_next) begin
                sw_next = 1'b1;
            end else if (~|sync_next) begin
                sw_next = 1'b0;
            end
        end
    end

endmodule
