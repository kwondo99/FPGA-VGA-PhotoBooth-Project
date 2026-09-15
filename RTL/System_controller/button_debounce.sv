`timescale 1ns / 1ps

module button_debounce (
    input  logic clk    ,
    input  logic rst    ,
    input  logic i_tick ,
    input  logic i_btn  ,
    output logic o_btn
);

    (* ASYNC_REG = "TRUE" *) logic [1:0] btn_sync_reg;
    logic [1:0] btn_sync_next;
    logic [7:0] sync_reg, sync_next;
    logic       armed_reg, armed_next;
    logic       btn_reg, btn_next;
    logic       pressed;
    logic       released;

    assign pressed  =  &sync_reg;
    assign released = ~|sync_reg;
    assign o_btn    = btn_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            btn_sync_reg <= 2'b11;
            sync_reg     <= 8'hFF;
            armed_reg    <= 1'b0;
            btn_reg      <= 1'b0;
        end else begin
            btn_sync_reg <= btn_sync_next;
            sync_reg     <= sync_next;
            armed_reg    <= armed_next;
            btn_reg      <= btn_next;
        end
    end

    always_comb begin
        btn_sync_next = {btn_sync_reg[0], i_btn};
        sync_next     = sync_reg;
        armed_next    = armed_reg;
        btn_next      = 1'b0;

        if (i_tick) begin
            sync_next = {btn_sync_reg[1], sync_reg[7:1]};

            if (released) begin
                armed_next = 1'b1;
            end else if (pressed && armed_reg) begin
                armed_next = 1'b0;
                btn_next   = 1'b1;
            end
        end
    end

endmodule
