`timescale 1ns / 1ps

// =====================================================
// setup_fsm
//  - Sequences the OV7670 register table (setup_rom) out over I2C:
//    START -> slave addr -> reg addr -> reg data -> STOP, repeated for
//    each table entry, with a 30 ms delay after entry 0 and a 30 ms
//    warm-up delay before the very first command.
// =====================================================
module setup_fsm (

    input logic clk,
    input logic reset,

    //rom
    output logic [6:0] idx,
    input logic [7:0] reg_addr,
    input logic [7:0] reg_data,
    
    //i2c
    output logic [7:0] tx_data,
    output logic o_cmd_start,
    output logic o_cmd_write,
    output logic o_cmd_stop,
    output logic o_setup_done,

    input logic        done
); 

    typedef enum logic [3:0] {
        IDLE,
        INIT_DELAY, // explicit 30 ms wait for the OV7670 to stabilize after power-up
        START_CMD,
        START_WAIT,

        SLAVE_CMD,
        SLAVE_WAIT,

        REG_CMD,
        REG_WAIT,

        DATA_CMD,
        DATA_WAIT,

        STOP_CMD,
        STOP_WAIT,

        DELAY,
        NEXT,
        DONE
    } state_t;

    state_t state;

    localparam logic [6:0] LAST_CFG_IDX = 7'd78; // last index, so all 79 words (0..78) in setup_table.mem get sent

    logic cmd_start, cmd_write, cmd_stop, setup_done;
    logic tick, tick_start;

    assign o_cmd_start = cmd_start;
    assign o_cmd_write = cmd_write;
    assign o_cmd_stop = cmd_stop;
    assign o_setup_done = setup_done;

    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            cmd_start <= 0;
            cmd_write <= 0;
            cmd_stop <= 0;
            setup_done <= 0;
            idx <= 0;
            tx_data <= 0;
            tick_start <= 0;
        end


        else begin
            case (state)

                IDLE: begin
                    state <= INIT_DELAY; // wait for XCLK and OV7670 power-up before the first SCCB command
                end

                INIT_DELAY: begin
                    tick_start <= 1'b1; // start a 30 ms wait (100 MHz reference) before the first register write

                    if (tick) begin
                        tick_start <= 1'b0; // 30 ms elapsed, stop the delay counter
                        state <= START_CMD; // camera is stable, begin sending the setup table
                    end
                end
                START_CMD: begin
                    cmd_start <= 1;
                    state <= START_WAIT;
                end

                START_WAIT: begin
                    cmd_start <= 0;
                    if(done)
                        state <= SLAVE_CMD;
                end

                SLAVE_CMD: begin
                    cmd_write <= 1;
                    tx_data <= 8'h42;
                    state <= SLAVE_WAIT;
                end

                SLAVE_WAIT: begin
                    cmd_write <= 0;
                    if(done)
                        state <= REG_CMD;
                end

                REG_CMD: begin
                    cmd_write <= 1;
                    tx_data <= reg_addr;
                    state <= REG_WAIT;
                end

                REG_WAIT: begin
                    cmd_write <= 0;
                    if(done)
                        state <= DATA_CMD;
                end

                DATA_CMD: begin
                    cmd_write <= 1;
                    tx_data <= reg_data;
                    state <= DATA_WAIT;
                end

                DATA_WAIT: begin
                    cmd_write <= 0;
                    if(done)
                        state <= STOP_CMD;
                end

                STOP_CMD: begin
                    cmd_stop <= 1;
                    state <= STOP_WAIT;
                end

                STOP_WAIT: begin
                    cmd_stop <= 0;
                    if(done) begin
                        if(idx==0)
                            state <= DELAY;
                        else if(idx==LAST_CFG_IDX) // move to DONE once STOP completes for the last config word
                            state <= DONE; // assert cam_ready only after all 79 config words have been sent
                        else
                            state <= NEXT;
                    end
                end

                DELAY: begin
                    // count out a 30 ms delay between register writes
                    tick_start <= 1;
                    if(tick)
                        state <= NEXT;
                end

                NEXT: begin
                    tick_start <= 0;
                    idx <= idx + 1;
                    state <= START_CMD;
                end

                DONE: begin
                    setup_done <= 1;
                    state <= DONE;
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end


i2c_delay_tick u_tick_gen( // named separately from System_controller/tick_gen to avoid a module name clash
    .clk(clk),
    .reset(reset),
    .tick_start(tick_start),
    .tick(tick)
);


endmodule


module i2c_delay_tick ( // separate module (different ports than System_controller/tick_gen) to avoid a build conflict
    input logic clk,
    input logic reset,
    input logic tick_start,
    output logic tick
);

    logic [21:0] delay_cnt;


    always_ff @( posedge clk, posedge reset ) begin


        if(reset) begin
            delay_cnt <= 0;
            tick <= 0;
        end
        else begin
            if(tick_start) begin
                    delay_cnt <= delay_cnt + 1;
                    if(delay_cnt == 2999999) begin
                        delay_cnt <= 0;
                        tick <= 1;
                    end
                    else begin
                        tick <= 0;
                    end
                
            end
            else begin
                delay_cnt <= 0;
                tick <= 0;
            end
        end


    end
endmodule
