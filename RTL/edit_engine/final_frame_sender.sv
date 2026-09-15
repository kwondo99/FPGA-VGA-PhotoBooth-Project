`timescale 1ns / 1ps

// =====================================================
// final_frame_sender (Image Export implementation)
//  - Scans all 640x480 coordinates from (0,0), one at a time
//    (no downscaling; storage stays at VGA resolution).
//  - SETUP/SETUP2/SETUP3 wait 3 clocks after changing the pixel
//    address before asserting valid, matching the read latency of
//    mem_addr_gen (2 stages) + memory (1 stage). Fewer wait states
//    would let image export read a stale pixel value.
// =====================================================
module final_frame_sender (
    input  logic       clk,
    input  logic       reset,
    input  logic       i_img_req_valid,
    output logic       o_img_req_ready,
    output logic       o_img_export_done,
    output logic [9:0] o_x_pixel,
    output logic [8:0] o_y_pixel,
    input  logic       i_pixel_ready,
    output logic       o_pixel_valid
);

    parameter IDLE = 0, SETUP = 1, SETUP2 = 3, SETUP3 = 4, ACCESS = 2;

    logic [2:0] c_state, n_state;
    logic valid_r, n_valid_r;
    logic [9:0] x_pixel_r, n_x_pixel_r;
    logic [8:0] y_pixel_r, n_y_pixel_r;

    logic img_req_ready_r, n_img_req_ready_r;
    logic img_export_done_r, n_img_export_done_r;

    assign o_x_pixel = x_pixel_r;
    assign o_y_pixel = y_pixel_r;
    assign o_pixel_valid = valid_r;
    assign o_img_req_ready = img_req_ready_r;
    assign o_img_export_done = img_export_done_r;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            c_state <= IDLE;
            valid_r <= 1'b0;
            x_pixel_r <= 0;
            y_pixel_r <= 0;
            img_req_ready_r <= 0;
            img_export_done_r <= 0;
        end else begin
            c_state <= n_state;
            valid_r <= n_valid_r;
            x_pixel_r <= n_x_pixel_r;
            y_pixel_r <= n_y_pixel_r;
            img_req_ready_r <= n_img_req_ready_r;
            img_export_done_r <= n_img_export_done_r;
        end
    end

    always_comb begin
        n_state = c_state;
        n_valid_r = valid_r;
        n_x_pixel_r = x_pixel_r;
        n_y_pixel_r = y_pixel_r;
        n_img_req_ready_r = 1'b1;
        n_img_export_done_r = 1'b0;
        case (c_state)
            IDLE: begin
                if (i_img_req_valid) begin
                    n_state = SETUP;
                    n_img_req_ready_r = 1'b0;
                end
            end
            SETUP: begin
                n_img_req_ready_r = 1'b0;
                n_state   = SETUP2;
            end
            SETUP2: begin
                n_img_req_ready_r = 1'b0;
                n_state   = SETUP3;
            end
            SETUP3: begin
                n_img_req_ready_r = 1'b0;
                n_state   = ACCESS;
                n_valid_r = 1'b1;
            end
            ACCESS: begin
                n_img_req_ready_r = 1'b0;
                if (i_pixel_ready) begin
                    if (x_pixel_r == 639 && y_pixel_r == 479) begin
                        n_x_pixel_r = 0;
                        n_y_pixel_r = 0;
                        n_img_export_done_r = 1'b1;
                        n_state = IDLE;
                    end else if (x_pixel_r == 639) begin
                        n_x_pixel_r = 0;
                        n_y_pixel_r = y_pixel_r + 1;
                        n_state = SETUP;
                    end else begin
                        n_x_pixel_r = x_pixel_r + 1;
                        n_state = SETUP;
                    end
                    n_valid_r = 1'b0;
                end
            end
        endcase
    end

endmodule
