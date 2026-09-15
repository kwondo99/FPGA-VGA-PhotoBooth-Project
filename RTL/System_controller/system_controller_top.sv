`timescale 1ns / 1ps

module system_controller_top #(
    parameter integer TICK_DIV     = 100_000,
    parameter integer RESULT_TICKS = 20_000
) (
    input  logic        clk         ,
    input  logic        btnC        ,
    input  logic        btnU        ,
    input  logic        btnD        ,
    input  logic        btnL        ,
    input  logic        btnR        ,
    input  logic        sw_tool_raw ,
    input  logic        sw_frame_raw,
    input  logic        ext_btn_n   ,
    output logic [15:0] led         ,
    output logic        o_rst_global,

    // Camera Interface
    input  logic        i_cam_ready        ,
    output logic        o_cam_stream_en    ,

    // Marker Detection
    output logic        o_marker_track_en  ,

    // Capture / Filter
    input  logic        i_cap_req_ready    ,
    input  logic        i_cap_done         ,
    input  logic [2:0]  i_capture_count    ,
    input  logic        i_all_done         ,
    output logic        o_cap_req_valid    ,
    output logic [2:0]  o_filter_sel       ,

    // Edit Engine / Compositor / Image Export
    output logic [1:0]  o_edit_mode        ,
    output logic        o_edit_active      ,
    output logic [1:0]  o_stk_id           ,
    output logic [1:0]  o_stk_size         ,
    output logic        o_stk_place_p      ,
    output logic [2:0]  o_drw_color        ,
    output logic        o_frame_sel        ,
    input  logic        i_img_req_ready    ,
    input  logic        i_img_export_done  ,
    output logic        o_img_req_valid    ,

    // UART
    input  logic        i_send_ready       ,
    input  logic        i_send_done        ,
    output logic        o_send_valid       ,
    output logic [31:0] o_status_data
);

    // system_controller's S_RESULT encoding from the FSM specification.
    localparam logic [3:0] ST_RESULT = 4'h6;

    logic rst_manual;
    logic rst_raw_global;
    logic rst_global;
    logic restart_pulse;
    logic tick;
    logic in_result;
    logic ext_btn_raw;
    logic ext_btn_pulse;
    logic btnR_pulse;
    logic btnL_pulse;
    logic btnU_pulse;
    logic btnD_pulse;
    logic sw_tool;
    logic sw_frame;

    assign ext_btn_raw    = ~ext_btn_n;
    assign rst_raw_global = btnC | restart_pulse;
    assign in_result      = (o_status_data[31:28] == ST_RESULT);
    assign o_rst_global   = rst_global;

    reset_sync U_RST_MANUAL (
        .clk       (clk       ),
        .i_rst_raw (btnC      ),
        .o_rst     (rst_manual)
    );

    reset_sync U_RST_GLOBAL (
        .clk       (clk           ),
        .i_rst_raw (rst_raw_global),
        .o_rst     (rst_global    )
    );

    tick_gen #(
        .TICK_DIV (TICK_DIV)
    ) U_TICK_GEN (
        .clk    (clk       ),
        .rst    (rst_global),
        .o_tick (tick      )
    );

    button_debounce U_DEBOUNCE_EXT (
        .clk    (clk          ),
        .rst    (rst_global   ),
        .i_tick (tick         ),
        .i_btn  (ext_btn_raw  ),
        .o_btn  (ext_btn_pulse)
    );

    button_debounce U_DEBOUNCE_BTNR (
        .clk    (clk       ),
        .rst    (rst_global),
        .i_tick (tick      ),
        .i_btn  (btnR      ),
        .o_btn  (btnR_pulse)
    );

    button_debounce U_DEBOUNCE_BTNL (
        .clk    (clk       ),
        .rst    (rst_global),
        .i_tick (tick      ),
        .i_btn  (btnL      ),
        .o_btn  (btnL_pulse)
    );

    button_debounce U_DEBOUNCE_BTNU (
        .clk    (clk       ),
        .rst    (rst_global),
        .i_tick (tick      ),
        .i_btn  (btnU      ),
        .o_btn  (btnU_pulse)
    );

    button_debounce U_DEBOUNCE_BTND (
        .clk    (clk       ),
        .rst    (rst_global),
        .i_tick (tick      ),
        .i_btn  (btnD      ),
        .o_btn  (btnD_pulse)
    );

    switch_sync U_SYNC_SW_TOOL (
        .clk    (clk        ),
        .rst    (rst_global ),
        .i_tick (tick       ),
        .i_sw   (sw_tool_raw),
        .o_sw   (sw_tool    )
    );

    switch_sync U_SYNC_SW_FRAME (
        .clk    (clk         ),
        .rst    (rst_global  ),
        .i_tick (tick        ),
        .i_sw   (sw_frame_raw),
        .o_sw   (sw_frame    )
    );

    result_auto_restart #(
        .RESULT_TICKS (RESULT_TICKS)
    ) U_AUTO_RESTART (
        .clk         (clk          ),
        .rst_manual  (rst_manual   ),
        .i_tick      (tick         ),
        .i_in_result (in_result    ),
        .i_ext_btn   (ext_btn_pulse),
        .o_restart   (restart_pulse)
    );

    system_controller U_SYSTEM_CONTROLLER (
        .clk                (clk               ),
        .rst                (rst_global        ),
        .ext_btn            (ext_btn_pulse     ),
        .btnR               (btnR_pulse        ),
        .btnL               (btnL_pulse        ),
        .btnU               (btnU_pulse        ),
        .btnD               (btnD_pulse        ),
        .sw_tool            (sw_tool           ),
        .sw_frame           (sw_frame          ),
        .i_cam_ready        (i_cam_ready       ),
        .o_cam_stream_en    (o_cam_stream_en   ),
        .o_marker_track_en  (o_marker_track_en ),
        .i_cap_req_ready    (i_cap_req_ready   ),
        .i_cap_done         (i_cap_done        ),
        .i_capture_count    (i_capture_count   ),
        .i_all_done         (i_all_done        ),
        .o_cap_req_valid    (o_cap_req_valid   ),
        .o_filter_sel       (o_filter_sel      ),
        .o_edit_mode        (o_edit_mode       ),
        .o_edit_active      (o_edit_active     ),
        .o_stk_id           (o_stk_id          ),
        .o_stk_size         (o_stk_size        ),
        .o_stk_place_p      (o_stk_place_p     ),
        .o_drw_color        (o_drw_color       ),
        .o_frame_sel        (o_frame_sel       ),
        .i_img_req_ready    (i_img_req_ready   ),
        .i_img_export_done  (i_img_export_done ),
        .o_img_req_valid    (o_img_req_valid   ),
        .i_send_ready       (i_send_ready      ),
        .i_send_done        (i_send_done       ),
        .o_send_valid       (o_send_valid      ),
        .o_status_data      (o_status_data     )
    );

    always_comb begin
        led = 16'b0;

        case (o_status_data[31:28])
            4'h0    : led[0] = 1'b1;
            4'h1    : led[1] = 1'b1;
            4'h2    : led[2] = 1'b1;
            4'h3    : led[3] = 1'b1;
            4'h4    : led[4] = 1'b1;
            4'h5    : led[5] = 1'b1;
            4'h6    : led[6] = 1'b1;
            default : ;
        endcase

        led[9:7] = o_status_data[23:21];
        led[10]  = o_status_data[7];
        led[11]  = o_cap_req_valid;
        led[12]  = o_img_req_valid;
    end

endmodule
