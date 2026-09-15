`timescale 1ns / 1ps

module system_controller (
    input  logic        clk                ,
    input  logic        rst                ,

    // User inputs are already conditioned by the input stage.
    input  logic        ext_btn            ,
    input  logic        btnR               ,
    input  logic        btnL               ,
    input  logic        btnU               ,
    input  logic        btnD               ,
    input  logic        sw_tool            ,
    input  logic        sw_frame           ,

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

    typedef enum logic [3:0] {
        S_OPEN         = 4'h0,
        S_SHOOT        = 4'h1,
        S_CAPTURE      = 4'h2,
        S_STICKER      = 4'h3,
        S_DRAW         = 4'h4,
        S_FINAL_EXPORT = 4'h5,
        S_RESULT       = 4'h6
    } state_t;

    localparam logic [2:0] FILTER_NONE  = 3'b000,
                           FILTER_GRAY  = 3'b001,
                           FILTER_SEPIA = 3'b010,
                           FILTER_SOFT  = 3'b011,
                           FILTER_FILM  = 3'b100;

    localparam logic [1:0] EDIT_NONE    = 2'b00,
                           EDIT_STICKER = 2'b01,
                           EDIT_DRAW    = 2'b10,
                           EDIT_MOSAIC  = 2'b11;

    state_t c_state, n_state;

    logic [2:0] filter_sel_reg, filter_sel_next;
    logic [1:0] stk_id_reg, stk_id_next;
    logic [1:0] stk_size_reg, stk_size_next;
    logic [2:0] drw_color_reg, drw_color_next;
    logic       edit_active_reg, edit_active_next;
    logic       sw_tool_prev_reg, sw_tool_prev_next;
    logic [2:0] shot_cnt_reg, shot_cnt_next;
    logic       cap_req_sent_reg, cap_req_sent_next;
    logic       img_req_sent_reg, img_req_sent_next;
    logic       img_done_reg, img_done_next;
    logic       send_done_reg, send_done_next;
    logic       stk_place_reg, stk_place_next;
    logic [31:0] status_data_reg, status_data_next;
    logic        send_valid_reg, send_valid_next;
    logic        status_init_reg, status_init_next;

    logic cap_accept;
    logic img_accept;
    logic img_done_ok;
    logic send_done_ok;
    logic [31:0] status_now;
    logic        status_accept;
    logic        suppress;
    logic        status_new;
    logic        status_event;

    assign cap_accept = o_cap_req_valid && i_cap_req_ready;
    assign img_accept = o_img_req_valid && i_img_req_ready;

    assign img_done_ok  = img_done_reg  || i_img_export_done;
    assign send_done_ok = send_done_reg || i_send_done;

    assign o_cam_stream_en   = (c_state == S_SHOOT)   ||
                               (c_state == S_CAPTURE) ||
                               (c_state == S_STICKER) ||
                               (c_state == S_DRAW);

    assign o_marker_track_en = (c_state == S_STICKER) ||
                               (c_state == S_DRAW);

    assign o_cap_req_valid   = (c_state == S_CAPTURE) &&
                               !cap_req_sent_reg;

    assign o_img_req_valid   = (c_state == S_FINAL_EXPORT) &&
                               !img_req_sent_reg;

    assign o_edit_mode       = (c_state == S_STICKER)          ? EDIT_STICKER :
                               (c_state == S_DRAW && !sw_tool) ? EDIT_DRAW    :
                               (c_state == S_DRAW &&  sw_tool) ? EDIT_MOSAIC  :
                                                                 EDIT_NONE;

    assign o_edit_active = (c_state == S_DRAW) ? edit_active_reg : 1'b0;

    assign o_filter_sel  = filter_sel_reg;
    assign o_stk_id      = stk_id_reg;
    assign o_stk_size    = stk_size_reg;
    assign o_stk_place_p = stk_place_reg;
    assign o_drw_color   = drw_color_reg;

    // Frame selection is a synchronized switch level, not a stored setting.
    assign o_frame_sel = sw_frame;

    assign status_now = {
        4'(c_state)                 ,
        1'b0                        ,
        o_filter_sel                ,
        i_capture_count             ,
        2'b00                       ,
        o_frame_sel                 ,
        o_edit_mode                 ,
        o_edit_active               ,
        o_stk_id                    ,
        o_stk_size                  ,
        o_drw_color                 ,
        i_cam_ready                 ,
        1'b0                        ,
        1'b0                        ,
        i_all_done                  ,
        o_cam_stream_en             ,
        o_marker_track_en           ,
        (c_state == S_FINAL_EXPORT) ,
        1'b0
    };

    assign status_accept = send_valid_reg && i_send_ready;
    assign suppress      = (c_state == S_FINAL_EXPORT) &&
                           (status_data_reg[31:28] == 4'(S_FINAL_EXPORT));
    assign status_new    = !status_init_reg ||
                           (status_now != status_data_reg);
    assign status_event  = status_new && !suppress;

    assign o_send_valid  = send_valid_reg;
    assign o_status_data = status_data_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            c_state          <= S_OPEN;
            filter_sel_reg   <= FILTER_NONE;
            stk_id_reg       <= 2'b00;
            stk_size_reg     <= 2'b00;
            drw_color_reg    <= 3'b000;
            edit_active_reg  <= 1'b0;
            sw_tool_prev_reg <= 1'b0;
            shot_cnt_reg     <= 3'd0;
            cap_req_sent_reg <= 1'b0;
            img_req_sent_reg <= 1'b0;
            img_done_reg     <= 1'b0;
            send_done_reg    <= 1'b0;
            stk_place_reg    <= 1'b0;
            status_data_reg  <= 32'b0;
            send_valid_reg   <= 1'b0;
            status_init_reg  <= 1'b0;
        end else begin
            c_state          <= n_state;
            filter_sel_reg   <= filter_sel_next;
            stk_id_reg       <= stk_id_next;
            stk_size_reg     <= stk_size_next;
            drw_color_reg    <= drw_color_next;
            edit_active_reg  <= edit_active_next;
            sw_tool_prev_reg <= sw_tool_prev_next;
            shot_cnt_reg     <= shot_cnt_next;
            cap_req_sent_reg <= cap_req_sent_next;
            img_req_sent_reg <= img_req_sent_next;
            img_done_reg     <= img_done_next;
            send_done_reg    <= send_done_next;
            stk_place_reg    <= stk_place_next;
            status_data_reg  <= status_data_next;
            send_valid_reg   <= send_valid_next;
            status_init_reg  <= status_init_next;
        end
    end

    always_comb begin
        n_state          = c_state;
        filter_sel_next  = filter_sel_reg;
        stk_id_next      = stk_id_reg;
        stk_size_next    = stk_size_reg;
        drw_color_next   = drw_color_reg;
        edit_active_next = edit_active_reg;
        sw_tool_prev_next = sw_tool;
        shot_cnt_next     = shot_cnt_reg;
        cap_req_sent_next = cap_req_sent_reg;
        img_req_sent_next = img_req_sent_reg;
        img_done_next     = img_done_reg;
        send_done_next    = send_done_reg;
        stk_place_next    = 1'b0;
        status_data_next  = status_data_reg;
        send_valid_next   = send_valid_reg;
        status_init_next  = status_init_reg;

        case (c_state)
            S_OPEN : begin
                if (ext_btn && i_cam_ready) begin
                    n_state = S_SHOOT;
                end
            end

            S_SHOOT : begin
                if (ext_btn) begin
                    n_state = S_CAPTURE;
                end else if (btnR) begin
                    if (filter_sel_reg == FILTER_FILM) begin
                        filter_sel_next = FILTER_NONE;
                    end else begin
                        filter_sel_next = filter_sel_reg + 3'd1;
                    end
                end
            end

            S_CAPTURE : begin
                if (cap_req_sent_reg && i_cap_done) begin
                    shot_cnt_next = shot_cnt_reg + 3'd1;
                    if (shot_cnt_reg == 3'd3) begin
                        n_state = S_STICKER;
                    end else begin
                        n_state = S_SHOOT;
                    end
                end
            end

            S_STICKER : begin
                if (ext_btn) begin
                    n_state = S_DRAW;
                end else begin
                    if (btnR) begin
                        stk_id_next = stk_id_reg + 2'd1;
                    end

                    if (btnL) begin
                        stk_place_next = 1'b1;
                    end

                    if (btnU && btnD) begin
                        stk_size_next = stk_size_reg;
                    end else if (btnU && (stk_size_reg != 2'b11)) begin
                        stk_size_next = stk_size_reg + 2'd1;
                    end else if (btnD && (stk_size_reg != 2'b00)) begin
                        stk_size_next = stk_size_reg - 2'd1;
                    end
                end
            end

            S_DRAW : begin
                if (ext_btn) begin
                    n_state = S_FINAL_EXPORT;
                end else begin
                    if (!sw_tool && !edit_active_reg && btnR) begin
                        drw_color_next = drw_color_reg + 3'd1;
                    end

                    if (btnL) begin
                        edit_active_next = ~edit_active_reg;
                    end
                end
            end

            S_FINAL_EXPORT : begin
                if (img_done_ok && send_done_ok) begin
                    n_state = S_RESULT;
                end
            end

            S_RESULT : begin
            end

            default : begin
                n_state = S_OPEN;
            end
        endcase

        // Leaving a request state wins over a same-cycle acceptance.
        if ((c_state == S_CAPTURE) && (n_state != S_CAPTURE)) begin
            cap_req_sent_next = 1'b0;
        end else if (cap_accept) begin
            cap_req_sent_next = 1'b1;
        end

        if ((c_state == S_FINAL_EXPORT) &&
            (n_state != S_FINAL_EXPORT)) begin
            img_req_sent_next = 1'b0;
        end else if (img_accept) begin
            img_req_sent_next = 1'b1;
        end

        // Entry clear wins over a stale completion pulse on the transition edge.
        if ((c_state != S_FINAL_EXPORT) &&
            (n_state == S_FINAL_EXPORT)) begin
            img_done_next  = 1'b0;
            send_done_next = 1'b0;
        end else begin
            if ((c_state == S_FINAL_EXPORT) && i_img_export_done) begin
                img_done_next = 1'b1;
            end

            if ((c_state == S_FINAL_EXPORT) && i_send_done) begin
                send_done_next = 1'b1;
            end
        end

        // Mode changes and DRAW boundaries take priority over the apply toggle.
        if (((c_state != S_DRAW) && (n_state == S_DRAW)) ||
            ((c_state == S_DRAW) && (n_state != S_DRAW)) ||
            (sw_tool != sw_tool_prev_reg)) begin
            edit_active_next = 1'b0;
        end

        if (status_accept) begin
            if (status_event) begin
                status_data_next = status_now;
                send_valid_next  = 1'b1;
                status_init_next = 1'b1;
            end else begin
                send_valid_next = 1'b0;
            end
        end else if (!send_valid_reg && status_event) begin
            status_data_next = status_now;
            send_valid_next  = 1'b1;
            status_init_next = 1'b1;
        end
    end

endmodule
