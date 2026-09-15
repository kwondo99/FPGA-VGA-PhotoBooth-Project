`timescale 1ns / 1ps

// =====================================================
// Capture_Controller
//  - Continuously writes the live camera stream into the current quadrant
//    slot (r_cap_count) of frame memory -- this drives the live preview.
//  - On a capture trigger, keeps writing the current slot until the last
//    valid pixel of the in-progress frame, then advances to the next
//    quadrant. Waiting for frame-end (rather than cutting off mid-frame)
//    avoids mixing pixels from two different frames into one slot.
//  - Frame-end is detected on the last valid pixel rather than the first
//    (0,0) pixel, since the softfocus filter doesn't assert i_pixel_valid
//    at (0,0), so start-of-frame can't be reliably observed across filters.
//  - After the 4th slot completes, all writes stop and the 4 captured
//    quadrants stay held until reset.
// =====================================================
module Capture_Controller #(
    parameter WIDTH  = $clog2(160) - 1,
    parameter HEIGHT = $clog2(120) - 1
) (
    // global signals
    input logic clk,
    input logic rst,

    // Filter Top interface : input
    input logic            i_pixel_valid,
    input logic [    11:0] i_pixel_data,
    input logic [ WIDTH:0] i_x_pixel,
    input logic [HEIGHT:0] i_y_pixel,

    // System Controller interface : input
    input logic i_cap_req_valid,  // 1-clock pulse (already debounced/one-shot by the caller)

    // Frame Memory interface : output
    output logic        o_wr_en,
    output logic [16:0] o_wr_addr,
    output logic [11:0] o_wr_data,

    // System Controller interface : output
    output logic       o_cap_done,
    output logic [2:0] o_cap_count,
    output logic       o_cap_req_ready,
    output logic       o_all_done
);

    // Frame-end: last valid pixel of the downscaled 160x120 frame. Used as the
    // slot-advance boundary since softfocus never asserts valid at (0,0).
    logic w_frame_end;
    assign w_frame_end = i_pixel_valid && (i_x_pixel == 8'd159) && (i_y_pixel == 7'd119);

    // Holds a pending trigger until the current frame's end boundary
    logic r_trig_pending;
    logic r_all_done;
    logic [2:0] r_cap_count;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            r_trig_pending <= 1'b0;
        end else if (i_cap_req_valid && !r_all_done) begin
            r_trig_pending <= 1'b1;
        end else if (w_frame_end && r_trig_pending) begin
            r_trig_pending <= 1'b0;  // consumed at this frame boundary
        end
    end

    // The actual moment we stop writing the current slot and move to the next one
    logic w_advance;
    assign w_advance = w_frame_end && r_trig_pending && !r_all_done; // advance only after the last pixel of the current slot is written

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            r_cap_count <= 3'd0;
            r_all_done  <= 1'b0;
        end else if (w_advance) begin
            if (r_cap_count == 3'd3) r_all_done  <= 1'b1;   // 4th slot just completed
            else                     r_cap_count <= r_cap_count + 3'd1;
        end
    end

    // Always writes the live stream into the current slot (r_cap_count) -- this
    // is what makes the live preview work. Once all_done, writes stop entirely
    // so the 4 captured quadrants stay frozen.
    always_comb begin
        o_wr_en = i_pixel_valid && !r_all_done;
        case (r_cap_count)
            3'd0:    o_wr_addr = i_y_pixel * 320 + i_x_pixel;                  // quadrant 1
            3'd1:    o_wr_addr = i_y_pixel * 320 + (i_x_pixel + 160);          // quadrant 2
            3'd2:    o_wr_addr = (i_y_pixel + 120) * 320 + i_x_pixel;          // quadrant 3
            3'd3:    o_wr_addr = (i_y_pixel + 120) * 320 + (i_x_pixel + 160);  // quadrant 4
            default: o_wr_addr = 17'd0;
        endcase
        o_wr_data = i_pixel_data;
    end

    assign o_cap_done      = w_advance;              // pulses the clock a slot gets frozen
    assign o_cap_count     = r_all_done ? 3'd4 : r_cap_count; // slot index 0..3 while active, 4 once all slots are done
    assign o_cap_req_ready = !r_trig_pending && !r_all_done;  // ready only with no pending trigger and not yet finished
    assign o_all_done      = r_all_done;

endmodule
