`timescale 1ns / 1ps

// ============================================================================
// StrokeInterpolator
//
// Role
//   - draw_active = 0 : passes MarkerDetector coordinates straight through
//                       (bypass), used for STICKER etc.
//   - draw_active = 1 : interpolates from the previous detected point to the
//                       current detected point using Bresenham's line algorithm
//   - If the marker disappears mid-DRAW, the previous point is dropped so
//     re-detection doesn't draw a long connecting line to the new position
//   - A jump that's too large is not connected to the previous point; a new
//     segment starts from the current point instead
//   - Interpolated coordinate valid pulses are spaced at least SEND_INTERVAL
//     clocks apart
//
// mem_writer's longest path (MOSAIC) occupies at least 28 clocks per
// coordinate (3-clock prep + 25-clock 5x5 write). SEND_INTERVAL is set to
// 32 clocks so DRAW and MOSAIC don't drop interpolated points.
// ============================================================================
module StrokeInterpolator #(
    parameter SEND_INTERVAL = 32,  // kept above MOSAIC's minimum 28-clock processing time to avoid dropping interpolated points
    parameter INTERP_MAX_DX = 18,
    parameter INTERP_MAX_DY = 18
)(
    input  logic       clk,
    input  logic       reset,

    input  logic       draw_active,

    // native 320x240 marker coordinates, already CDC'd
    input  logic [8:0] i_marker_x,
    input  logic [7:0] i_marker_y,
    input  logic       i_marker_valid,
    input  logic       i_marker_present,

    // wired straight into the Edit Engine's existing marker interface
    output logic [8:0] o_marker_x,
    output logic [7:0] o_marker_y,
    output logic       o_marker_valid,
    output logic       o_marker_present,

    // debug only, not needed for the Edit Engine connection
    output logic       o_interp_busy
);

    logic       segment_busy;

    // marker_present is a status flag rather than a new-coordinate event, so pass it through unchanged
    assign o_marker_present = i_marker_present;
    assign o_interp_busy    = segment_busy;

    // ------------------------------------------------------------------------
    // Clamp coordinates to the native image interior (1..318 / 1..238) so
    // mem_writer's 3x3 +/-1 address computation for DRAW never runs off-screen.
    // This clamp is not applied to STICKER bypass coordinates.
    // ------------------------------------------------------------------------
    function automatic [8:0] clamp_draw_x(input logic [8:0] x);
        begin
            if (x < 9'd1)
                clamp_draw_x = 9'd1;
            else if (x > 9'd318)
                clamp_draw_x = 9'd318;
            else
                clamp_draw_x = x;
        end
    endfunction

    function automatic [7:0] clamp_draw_y(input logic [7:0] y);
        begin
            if (y < 8'd1)
                clamp_draw_y = 8'd1;
            else if (y > 8'd238)
                clamp_draw_y = 8'd238;
            else
                clamp_draw_y = y;
        end
    endfunction

    // Holds the single most recent detector event.
    // Interpolation runs much faster than detector events arrive, so a
    // 1-entry latest-value buffer is sufficient.
    logic [8:0] pending_x;
    logic [7:0] pending_y;
    logic       pending_valid;

    logic [8:0] prev_x;
    logic [7:0] prev_y;
    logic       have_prev;

    // current Bresenham segment
    logic [8:0] line_x;
    logic [7:0] line_y;
    logic [8:0] target_x;
    logic [7:0] target_y;

    logic signed [10:0] dx_b;
    logic signed [10:0] dy_b;
    logic signed [10:0] sx_b;
    logic signed [10:0] sy_b;
    logic signed [11:0] err_b;

    // valid-pulse spacing is capped at SEND_INTERVAL (32) clocks to avoid
    // sending the next point before MOSAIC finishes the current one
    logic [7:0] cooldown;

    // distance between the pending point and the previous point
    logic [8:0] seg_dx;
    logic [7:0] seg_dy;
    logic       segment_connect_ok;

    always_comb begin
        if (pending_x >= prev_x)
            seg_dx = pending_x - prev_x;
        else
            seg_dx = prev_x - pending_x;

        if (pending_y >= prev_y)
            seg_dy = pending_y - prev_y;
        else
            seg_dy = prev_y - pending_y;

        segment_connect_ok =
            (seg_dx <= INTERP_MAX_DX) &&
            (seg_dy <= INTERP_MAX_DY);
    end

    // compute the next Bresenham point
    logic [8:0] bres_next_x;
    logic [7:0] bres_next_y;
    logic signed [11:0] bres_next_err;
    logic signed [12:0] bres_e2;

    always_comb begin
        bres_next_x   = line_x;
        bres_next_y   = line_y;
        bres_next_err = err_b;
        bres_e2       = $signed(err_b) <<< 1;

        if (bres_e2 > -$signed(dy_b)) begin
            bres_next_err = bres_next_err - $signed(dy_b);

            if (sx_b > 0)
                bres_next_x = line_x + 1'b1;
            else
                bres_next_x = line_x - 1'b1;
        end

        if (bres_e2 < $signed(dx_b)) begin
            bres_next_err = bres_next_err + $signed(dx_b);

            if (sy_b > 0)
                bres_next_y = line_y + 1'b1;
            else
                bres_next_y = line_y - 1'b1;
        end
    end

    // ------------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            o_marker_x     <= 9'd0;
            o_marker_y     <= 8'd0;
            o_marker_valid <= 1'b0;

            pending_x      <= 9'd0;
            pending_y      <= 8'd0;
            pending_valid  <= 1'b0;

            prev_x         <= 9'd0;
            prev_y         <= 8'd0;
            have_prev      <= 1'b0;

            segment_busy   <= 1'b0;
            line_x         <= 9'd0;
            line_y         <= 8'd0;
            target_x       <= 9'd0;
            target_y       <= 8'd0;

            dx_b           <= '0;
            dy_b           <= '0;
            sx_b           <= '0;
            sy_b           <= '0;
            err_b          <= '0;

            cooldown       <= 8'd0;
        end
        else begin
            // valid is always a 1-clock pulse
            o_marker_valid <= 1'b0;

            // ================================================================
            // Not in DRAW: interpolation fully bypassed.
            // Sticker etc. receive detector coordinates unchanged, as before.
            // ================================================================
            if (!draw_active) begin
                have_prev     <= 1'b0;
                segment_busy  <= 1'b0;
                pending_valid <= 1'b0;
                cooldown      <= 8'd0;

                if (i_marker_valid) begin
                    o_marker_x     <= i_marker_x;
                    o_marker_y     <= i_marker_y;
                    o_marker_valid <= 1'b1;
                end
            end

            // ================================================================
            // Marker dropout during DRAW: break the stroke.
            // ================================================================
            else if (!i_marker_present) begin
                have_prev     <= 1'b0;
                segment_busy  <= 1'b0;
                pending_valid <= 1'b0;
                cooldown      <= 8'd0;
            end

            // ================================================================
            // DRAW active
            // ================================================================
            else begin
                // rate limiter
                if (cooldown != 0)
                    cooldown <= cooldown - 1'b1;

                // ------------------------------------------------------------
                // Bresenham segment in progress.
                // Sends exactly one more point per cycle once cooldown reaches 0.
                // ------------------------------------------------------------
                if (segment_busy) begin
                    if (cooldown == 0) begin
                        o_marker_x     <= bres_next_x;
                        o_marker_y     <= bres_next_y;
                        o_marker_valid <= 1'b1;

                        line_x <= bres_next_x;
                        line_y <= bres_next_y;
                        err_b  <= bres_next_err;

                        if (SEND_INTERVAL > 1)
                            cooldown <= SEND_INTERVAL - 1;
                        else
                            cooldown <= 0;

                        // segment completes once its endpoint has been sent
                        if ((bres_next_x == target_x) &&
                            (bres_next_y == target_y)) begin
                            prev_x       <= target_x;
                            prev_y       <= target_y;
                            have_prev    <= 1'b1;
                            segment_busy <= 1'b0;
                        end
                    end
                end

                // ------------------------------------------------------------
                // No segment active: consume one pending detector point
                // ------------------------------------------------------------
                else if ((cooldown == 0) && pending_valid) begin
                    pending_valid <= 1'b0;

                    // first point of the stroke
                    if (!have_prev) begin
                        o_marker_x     <= pending_x;
                        o_marker_y     <= pending_y;
                        o_marker_valid <= 1'b1;

                        prev_x      <= pending_x;
                        prev_y      <= pending_y;
                        have_prev   <= 1'b1;

                        if (SEND_INTERVAL > 1)
                            cooldown <= SEND_INTERVAL - 1;
                        else
                            cooldown <= 0;
                    end

                    // same coordinate as before: nothing new to write
                    else if ((pending_x == prev_x) &&
                             (pending_y == prev_y)) begin
                        prev_x <= pending_x;
                        prev_y <= pending_y;
                    end

                    // normal continuous movement: start a Bresenham segment prev -> pending
                    else if (segment_connect_ok) begin
                        line_x   <= prev_x;
                        line_y   <= prev_y;
                        target_x <= pending_x;
                        target_y <= pending_y;

                        dx_b <= $signed({1'b0, seg_dx});
                        dy_b <= $signed({2'b00, seg_dy});

                        if (pending_x >= prev_x)
                            sx_b <= 11'sd1;
                        else
                            sx_b <= -11'sd1;

                        if (pending_y >= prev_y)
                            sy_b <= 11'sd1;
                        else
                            sy_b <= -11'sd1;

                        err_b <= $signed({2'b00, seg_dx})
                               - $signed({3'b000, seg_dy});

                        segment_busy <= 1'b1;
                    end

                    // jump too large: skip the connecting line, output only the current point
                    else begin
                        o_marker_x     <= pending_x;
                        o_marker_y     <= pending_y;
                        o_marker_valid <= 1'b1;

                        prev_x      <= pending_x;
                        prev_y      <= pending_y;
                        have_prev   <= 1'b1;

                        if (SEND_INTERVAL > 1)
                            cooldown <= SEND_INTERVAL - 1;
                        else
                            cooldown <= 0;
                    end
                end

                // ------------------------------------------------------------
                // Detector event capture.
                // Placed after the pending-consume logic so that if a new
                // event arrives the same cycle pending is consumed, it's
                // captured as the next pending value rather than lost.
                // ------------------------------------------------------------
                if (i_marker_valid) begin
                    pending_x     <= clamp_draw_x(i_marker_x);
                    pending_y     <= clamp_draw_y(i_marker_y);
                    pending_valid <= 1'b1;
                end
            end
        end
    end

endmodule
