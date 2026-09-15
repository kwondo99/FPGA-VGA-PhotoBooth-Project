`timescale 1ns / 1ps

// =====================================================
// edit_engine (top)
//  - Ports match the team interface spec (v1.0).
//  - Destructive-write pipeline:
//      downscaler -> mem_addr_gen (read address / mosaic snap)
//                 -> memory (320x240, 2-port) -> marker_overlay (read-only overlay)
//      + mem_writer (committed writes: sticker/draw/mosaic bake)
//      + final_frame_sender (image export)
//    Each submodule lives in its own file.
//
//  - memory stays 2-port (Port A: shared by capture load + mem_writer,
//    Port B: marker_overlay). A 3rd port caused BRAM replication and
//    RAMB18/36 over-utilization DRC errors on the target board, so
//    mem_writer's write address and mosaic-read address are muxed onto
//    Port A here (mem_writer.sv itself is unmodified).
// =====================================================
module edit_engine #(
    parameter MEM_W = 320,
    parameter MEM_H = 240
) (
    input  logic        clk,
    input  logic        rst,

    // ---- Controller <-> Image Export ----
    input  logic        i_img_req_valid,
    output logic        o_img_req_ready,
    output logic        o_img_export_done,
    output logic        o_img_export_active, // blanks VGA RGB while shared memory read is occupied by UART export
    output logic        o_img_export_error,

    // ---- VGA controller (native 640x480 scale) ----
    input  logic [9:0]  i_x_pixel,
    input  logic [9:0]  i_y_pixel,
    input  logic        i_data_en,

    // ---- Marker detection (spec bit widths: x[8:0]/y[7:0]) ----
    input  logic [8:0]  i_marker_x,
    input  logic [7:0]  i_marker_y,
    input  logic        i_marker_valid,

    // ---- Capture/Memory top: initial load of captured 320x240 photo ----
    input  logic [16:0] i_addr,
    input  logic [11:0] i_rgb,
    input  logic        i_pixel_valid,

    // ---- Pixel output, shared by live display and image export ----
    output logic [11:0] o_pixel_data,
    output logic        o_pixel_valid,
    input  logic        i_pixel_ready,

    // ---- System controller: edit control ----
    input  logic [1:0]  i_edit_mode,
    input  logic        i_edit_active,
    input  logic [1:0]  i_stk_id,  // 2-bit sticker ID, matches 4-slot sticker_rom
    input  logic [1:0]  i_stk_size,
    input  logic        i_stk_place_p,
    input  logic [2:0]  i_draw_color,

    // ---- 4-cut frame overlay: always on, 0=white 1=black ----
    input  logic         i_frame_sel
);

    // ---- Image export: scans all 640x480 pixels from (0,0) on req/ready handshake ----
    wire [9:0] uart_x_pixel;
    wire [8:0] uart_y_pixel;
    wire       uart_valid;

    logic sending_r;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) sending_r <= 1'b0;
        else if (i_img_req_valid && !sending_r) sending_r <= 1'b1;
        else if (o_img_export_done) sending_r <= 1'b0;
    end
    wire sending = sending_r;
    assign o_img_export_active = sending_r; // held from export start through the final pixel

    logic frame_sel_latched;  // holds frame color for the duration of an export
    always_ff @(posedge clk or posedge rst) begin
        if (rst) frame_sel_latched <= 1'b0;
        else if (i_img_req_valid && !sending_r) frame_sel_latched <= i_frame_sel;  // latch on request accept
    end
    wire frame_sel_eff = sending_r ? frame_sel_latched : i_frame_sel;  // fixed during export, live otherwise

    assign o_img_export_error = 1'b0;  // final_frame_sender has no error output

    final_frame_sender U_IMAGE_EXPORT (
        .clk              (clk),
        .reset            (rst),
        .i_img_req_valid  (i_img_req_valid),
        .o_img_req_ready  (o_img_req_ready),
        .o_img_export_done(o_img_export_done),
        .o_x_pixel        (uart_x_pixel),
        .o_y_pixel        (uart_y_pixel),
        .i_pixel_ready    (i_pixel_ready),
        .o_pixel_valid    (uart_valid)
    );

    // ---- Coordinate mux: export scan coords while sending, else VGA coords (both 640x480 scale) ----
    wire [9:0] mux_x = sending ? uart_x_pixel : i_x_pixel;
    wire [9:0] mux_y = sending ? {1'b0, uart_y_pixel} : i_y_pixel;

    // ---- downscaler: 640x480 -> 320x240 (combinational, no added latency) ----
    wire [9:0] eff_x, eff_y;
    downscaler U_DOWNSCALER (
        .i_x_pixel(mux_x),
        .i_y_pixel(mux_y),
        .o_x_pixel(eff_x),
        .o_y_pixel(eff_y)
    );

    // ---- Marker detection is native 320x240; zero-extend to marker_overlay's 10-bit ports ----
    wire [9:0] marker_x_s = {1'b0, i_marker_x};
    wire [9:0] marker_y_s = {2'b00, i_marker_y};

    // Stretch the 1-clock marker_valid pulse into a level, with a timeout so a stale
    // marker doesn't stay latched forever (e.g. cursor/sticker placement source).
    localparam int MARKER_TIMEOUT = 10_000_000;  // 100 ms at 100 MHz
    logic marker_present_r;
    logic [23:0] marker_age_r;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            marker_present_r <= 1'b0;
            marker_age_r     <= '0;
        end else if (i_marker_valid) begin
            marker_present_r <= 1'b1;
            marker_age_r     <= '0;
        end else if (i_edit_mode == 2'b00) begin
            marker_present_r <= 1'b0;  // outside edit mode, disable marker-driven actions
            marker_age_r     <= '0;
        end else if (marker_age_r == MARKER_TIMEOUT) begin
            marker_present_r <= 1'b0;  // no update for 100 ms -> treat marker as lost
        end else begin
            marker_age_r <= marker_age_r + 1'b1;
        end
    end

    // mem_addr_gen: converts screen coords to a read address; snaps MOSAIC preview
    // to the same 5x5 center-color sample used by the committed write.
    //
    // Timing note: mem_addr_gen has a 2-stage internal pipeline, so disp_raddr lags
    // eff_x/eff_y by 2 clocks (3 total with the memory read stage). marker_overlay
    // and final_frame_sender are pipelined to match this 3-clock latency.
    wire [16:0] disp_raddr;
    wire [11:0] disp_rdata;

    mem_addr_gen #(.MEM_W(MEM_W), .MEM_H(MEM_H)) U_MEM_ADDR_GEN (
        .clk          (clk),
        .i_x_pixel    (eff_x),
        .i_y_pixel    (eff_y),
        .i_marker_x   (marker_x_s),
        .i_marker_y   (marker_y_s),
        .i_edit_mode  (i_edit_mode),
        .i_edit_active(i_edit_active),
        .o_mem_raddr  (disp_raddr)
    );

    // ---- mem_writer <-> memory: committed write / mosaic sample read ----
    wire        mw_we;
    wire [16:0] mw_waddr;
    wire [11:0] mw_wdata;
    wire [16:0] mw_raddr;
    wire [11:0] mw_rdata;

    // Dedicated sticker_rom instance for mem_writer's committed sticker write
    // (separate from the instance inside marker_overlay used for live preview).
    wire [1:0]  mw_stk_idx;  // matches 4-slot ROM / 2-bit sticker ID
    wire [1:0]  mw_stk_size;
    wire [4:0]  mw_stk_x, mw_stk_y;
    wire [11:0] mw_stk_rgb;
    wire        mw_stk_transparent;

    sticker_rom U_STICKER_ROM_WRITER (
        .clk        (clk),
        .idx        (mw_stk_idx),
        .size       (mw_stk_size),
        .x          (mw_stk_x),
        .y          (mw_stk_y),
        .rgb        (mw_stk_rgb),
        .transparent(mw_stk_transparent)
    );

    mem_writer #(.MEM_W(MEM_W), .MEM_H(MEM_H)) U_MEM_WRITER (
        .clk           (clk),
        .reset         (rst),
        .i_edit_mode   (i_edit_mode),
        .i_edit_active (i_edit_active),
        .i_stk_id      (i_stk_id),
        .i_stk_size    (i_stk_size),
        .i_stk_place_p (i_stk_place_p),
        .i_draw_color  (i_draw_color),
        .marker_x      (i_marker_x),
        .marker_y      (i_marker_y),
        .marker_valid  (marker_present_r),  // timeout-qualified level, not the raw 1-clock pulse
        .mem_en        (mw_we),
        .mem_waddr     (mw_waddr),
        .mem_wdata     (mw_wdata),
        .mem_raddr     (mw_raddr),
        .mem_rdata     (mw_rdata),
        .stk_rom_idx   (mw_stk_idx),
        .stk_rom_size  (mw_stk_size),
        .stk_rom_x     (mw_stk_x),
        .stk_rom_y     (mw_stk_y),
        .stk_rom_rgb   (mw_stk_rgb),
        .stk_rom_transparent(mw_stk_transparent)
    );

    // ---- memory (320x240, 2-port: Port A=capture load/mem_writer shared, Port B=marker_overlay) ----
    // mem_writer's write address and mosaic-read address are never needed in the same
    // cycle (write only when we=1, mosaic read only when we=0), so they're muxed onto
    // a single Port A address bus here. Capture load (i_addr/i_rgb/i_pixel_valid) is
    // given top priority on Port A since it only occurs before editing starts and
    // never overlaps mem_writer activity.
    wire [16:0] mem_a_addr  = i_pixel_valid ? i_addr  : (mw_we ? mw_waddr : mw_raddr);
    wire [11:0] mem_a_wdata = i_pixel_valid ? i_rgb   : mw_wdata;
    wire        mem_a_we    = i_pixel_valid ? 1'b1    : mw_we;
    wire [11:0] mem_rdata;

    memory #(.MEM_W(MEM_W), .MEM_H(MEM_H)) U_MEMORY (
        .clk       (clk),
        .rst       (rst),
        .i_we      (mem_a_we),
        .i_addr    (mem_a_addr),
        .i_wdata   (mem_a_wdata),
        .o_rdata_a (mw_rdata),
        .i_raddr   (disp_raddr),
        .o_rdata_b (mem_rdata)
    );

    // ---- marker_overlay: read-only display compositing, includes 4-cut frame ----
    wire [11:0] composited;

    marker_overlay #(.MEM_W(MEM_W), .MEM_H(MEM_H)) U_MARKER_OVERLAY (
        .clk           (clk),
        .rst           (rst),
        .i_x_pixel     (eff_x),
        .i_y_pixel     (eff_y),
        .i_marker_x    (marker_x_s),
        .i_marker_y    (marker_y_s),
        .i_marker_valid(marker_present_r),  // level (not per-frame pulse) for a stable cursor
        .i_edit_mode   (i_edit_mode),
        .i_edit_active (i_edit_active),
        .i_stk_id      (i_stk_id),
        .i_stk_size    (i_stk_size),
        .i_stk_place_p (i_stk_place_p),
        .i_draw_color  (i_draw_color),
        .i_frame_sel   (frame_sel_eff),  // latched value during export
        .i_mem_rdata   (mem_rdata),
        .o_pixel_data  (composited)
    );

    // ---- Delay i_data_en to align with the memory/marker_overlay pipeline (3 clocks) ----
    logic de_d1, de_d2, de_d3;
    always_ff @(posedge clk) begin
        de_d1 <= i_data_en;
        de_d2 <= de_d1;
        de_d3 <= de_d2;
    end

    // ---- i_addr/i_rgb/i_pixel_valid are already handled by mem_a_* mux above ----

    // ---- Output: UART scan result while exporting, else VGA display result (with de blanking) ----
    //      Both paths use composited (marker_overlay's compositing output).
    assign o_pixel_data  = (sending || de_d3) ? composited : 12'h000;
    assign o_pixel_valid = sending ? uart_valid : de_d3;

endmodule
