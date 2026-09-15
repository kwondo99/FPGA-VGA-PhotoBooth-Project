`timescale 1ns / 1ps

module UART_TX (
    input  logic       clk,
    input  logic       rst,
    input  logic       i_baud_tick,
    input  logic [7:0] i_tx_data,
    input  logic       i_tx_start,
    output logic       o_tx_busy,
    output logic       o_tx_done,
    output logic       o_uart_tx
);

    typedef enum logic [2:0] {
        U_IDLE,
        U_WAIT_START_TICK,
        U_START_BIT,
        U_DATA_BITS,
        U_STOP_BIT
    } uart_state_t;

    uart_state_t state;
    logic [7:0] tx_data_reg;
    logic [2:0] bit_index;

    always_ff @(posedge clk) begin
        if (rst) begin
            state       <= U_IDLE;
            tx_data_reg <= 8'h00;
            bit_index   <= 3'd0;
            o_tx_busy   <= 1'b0;
            o_tx_done   <= 1'b0;
            o_uart_tx   <= 1'b1;
        end
        else begin
            o_tx_done <= 1'b0;

            case (state)
                U_IDLE: begin
                    o_tx_busy <= 1'b0;
                    o_uart_tx <= 1'b1;

                    if (i_tx_start) begin
                        tx_data_reg <= i_tx_data;
                        bit_index   <= 3'd0;
                        o_tx_busy   <= 1'b1;
                        state       <= U_WAIT_START_TICK;
                    end
                end

                U_WAIT_START_TICK: begin
                    if (i_baud_tick) begin
                        o_uart_tx <= 1'b0;
                        state     <= U_START_BIT;
                    end
                end

                U_START_BIT: begin
                    if (i_baud_tick) begin
                        o_uart_tx <= tx_data_reg[0];
                        bit_index <= 3'd0;
                        state     <= U_DATA_BITS;
                    end
                end

                U_DATA_BITS: begin
                    if (i_baud_tick) begin
                        if (bit_index == 3'd7) begin
                            o_uart_tx <= 1'b1;
                            state     <= U_STOP_BIT;
                        end
                        else begin
                            bit_index <= bit_index + 1'b1;
                            o_uart_tx <= tx_data_reg[bit_index + 1'b1];
                        end
                    end
                end

                U_STOP_BIT: begin
                    if (i_baud_tick) begin
                        o_uart_tx <= 1'b1;
                        o_tx_busy <= 1'b0;
                        o_tx_done <= 1'b1;
                        state     <= U_IDLE;
                    end
                end

                default: begin
                    state     <= U_IDLE;
                    o_tx_busy <= 1'b0;
                    o_uart_tx <= 1'b1;
                end
            endcase
        end
    end

endmodule
