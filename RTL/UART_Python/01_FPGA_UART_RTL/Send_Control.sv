`timescale 1ns / 1ps

module Send_Control #(
    parameter int IMG_W = 640,
    parameter int IMG_H = 480,
    parameter logic [3:0] STATE_EXPORT = 4'h5
)(
    input  logic        clk,
    input  logic        rst,

    // System Controller
    input  logic [31:0] i_status_data,
    input  logic        i_status_valid,
    output logic        o_status_ready,
    output logic        o_send_done,

    // ROM Reader / Edit Engine
    input  logic [11:0] i_pixel_data,
    input  logic        i_pixel_valid,
    output logic        o_pixel_ready,

    // UART TX
    input  logic        i_tx_busy,
    input  logic        i_tx_done,
    output logic [7:0]  o_tx_data,
    output logic        o_tx_start
);

    localparam int PIXEL_COUNT = IMG_W * IMG_H;
    localparam int PIXEL_CNT_WIDTH = (PIXEL_COUNT <= 1)
                                   ? 1 : $clog2(PIXEL_COUNT);
    localparam logic [PIXEL_CNT_WIDTH-1:0] LAST_PIXEL = PIXEL_COUNT - 1;

    typedef enum logic [2:0] {
        IDLE,
        TX_LOAD,
        TX_START,
        TX_WAIT,
        PIXEL_WAIT,
        TX_DONE
    } state_t;

    typedef enum logic {
        STATUS,
        PIXEL
    } send_mode_t;

    state_t       state, next_state;
    send_mode_t   send_mode;
    logic [31:0]  status_reg;
    logic [11:0]  pixel_reg;
    logic         export_flag_reg;
    logic [1:0]   byte_cnt;
    logic [PIXEL_CNT_WIDTH-1:0] pixel_cnt;

    always_ff @(posedge clk) begin
        if (rst) begin
            state           <= IDLE;
            send_mode       <= STATUS;
            status_reg      <= 32'h0000_0000;
            pixel_reg       <= 12'h000;
            export_flag_reg <= 1'b0;
            byte_cnt        <= 2'd0;
            pixel_cnt       <= '0;
        end
        else begin
            state <= next_state;

            case (state)
                IDLE: begin
                    if (i_status_valid && o_status_ready) begin
                        status_reg      <= i_status_data;
                        export_flag_reg <=
                            (i_status_data[31:28] == STATE_EXPORT);
                        send_mode       <= STATUS;
                        byte_cnt        <= 2'd0;
                    end
                end

                TX_WAIT: begin
                    if (i_tx_done) begin
                        if (send_mode == STATUS) begin
                            if (byte_cnt == 2'd3) begin
                                byte_cnt <= 2'd0;

                                if (export_flag_reg) begin
                                    send_mode <= PIXEL;
                                    pixel_cnt <= '0;
                                end
                            end
                            else begin
                                byte_cnt <= byte_cnt + 1'b1;
                            end
                        end
                        else begin
                            if (byte_cnt == 2'd1) begin
                                byte_cnt <= 2'd0;

                                if (pixel_cnt != LAST_PIXEL) begin
                                    pixel_cnt <= pixel_cnt + 1'b1;
                                end
                            end
                            else begin
                                byte_cnt <= byte_cnt + 1'b1;
                            end
                        end
                    end
                end

                PIXEL_WAIT: begin
                    if (i_pixel_valid && o_pixel_ready) begin
                        pixel_reg <= i_pixel_data;
                        byte_cnt  <= 2'd0;
                    end
                end

                default: begin
                    // No register update.
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (i_status_valid && o_status_ready) begin
                    next_state = TX_LOAD;
                end
            end

            TX_LOAD: begin
                if (!i_tx_busy) begin
                    next_state = TX_START;
                end
            end

            TX_START: begin
                next_state = TX_WAIT;
            end

            TX_WAIT: begin
                if (i_tx_done) begin
                    if (send_mode == PIXEL) begin
                        if (byte_cnt == 2'd1) begin
                            if (pixel_cnt == LAST_PIXEL) begin
                                next_state = TX_DONE;
                            end
                            else begin
                                next_state = PIXEL_WAIT;
                            end
                        end
                        else begin
                            next_state = TX_LOAD;
                        end
                    end
                    else begin
                        if (byte_cnt == 2'd3) begin
                            if (export_flag_reg) begin
                                next_state = PIXEL_WAIT;
                            end
                            else begin
                                next_state = IDLE;
                            end
                        end
                        else begin
                            next_state = TX_LOAD;
                        end
                    end
                end
            end

            PIXEL_WAIT: begin
                if (i_pixel_valid && o_pixel_ready) begin
                    next_state = TX_LOAD;
                end
            end

            TX_DONE: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always_comb begin
        o_status_ready = 1'b0;
        o_pixel_ready  = 1'b0;
        o_tx_start     = 1'b0;
        o_send_done    = 1'b0;

        case (state)
            IDLE: begin
                o_status_ready = 1'b1;
            end

            TX_START: begin
                o_tx_start = 1'b1;
            end

            PIXEL_WAIT: begin
                o_pixel_ready = 1'b1;
            end

            TX_DONE: begin
                o_send_done = 1'b1;
            end

            default: begin
                // Keep default outputs.
            end
        endcase
    end

    // Byte mapping between consecutive UART bytes is LSB byte first.
    // UART_TX still sends the individual bits inside each byte LSB bit first.
    always_comb begin
        o_tx_data = 8'h00;

        case (send_mode)
            STATUS: begin
                case (byte_cnt)
                    2'd0:    o_tx_data = status_reg[7:0];
                    2'd1:    o_tx_data = status_reg[15:8];
                    2'd2:    o_tx_data = status_reg[23:16];
                    2'd3:    o_tx_data = status_reg[31:24];
                    default: o_tx_data = 8'h00;
                endcase
            end

            PIXEL: begin
                case (byte_cnt)
                    2'd0:    o_tx_data = pixel_reg[7:0];
                    2'd1:    o_tx_data = {4'b0000, pixel_reg[11:8]};
                    default: o_tx_data = 8'h00;
                endcase
            end

            default: begin
                o_tx_data = 8'h00;
            end
        endcase
    end

endmodule
