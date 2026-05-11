module poly_exp_top (
    input  wire               clk,
    input  wire               rst_n,
    
    // Video Timing & Control In
    input  wire               vsync_in,
    input  wire               hsync_in,
    input  wire               valid_in,
    input  wire [2:0]         layer_config,

    // Pixel Coordinates (driven by external counters)
    // x_counter: current column index (0-based)
    // y_counter: must keep running for 5 extra rows after the image ends
    //            so the bottom boundary reflections flush correctly
    input  wire [11:0]        x_counter,
    input  wire [11:0]        y_counter,
    
    // Pixel Data In
    input  wire [7:0]         pixel_in,
    
    // Final Polynomial Coefficients (r2 to r6), after >>> 32 normalisation
    // Widths = raw_width - 32:
    //   r2,r6 (p1,29-bit in): 47-32 = 15  → [14:0]
    //   r3,r5 (p0,29-bit in): 49-32 = 17  → [16:0]
    //   r4    (p2,29-bit in): 46-32 = 14  → [13:0]
    output wire signed [14:0] r2_out,
    output wire signed [16:0] r3_out,
    output wire signed [13:0] r4_out,
    output wire signed [16:0] r5_out,
    output wire signed [14:0] r6_out,

    // Valid output (active when r2-r6 carry new data)
    output wire               valid_out
);

    // ========================================================
    // Layer-Dependent Frame Dimensions
    // ========================================================
    reg [10:0] current_width;
    reg [10:0] current_height;

    always @(*) begin
        case (layer_config)
            3'd0: current_width = 11'd1280;
            3'd1: current_width = 11'd640;
            3'd2: current_width = 11'd320;
            3'd3: current_width = 11'd160;
            3'd4: current_width = 11'd80;
            default: current_width = 11'd1280;
        endcase
    end

    always @(*) begin
        case (layer_config)
            3'd0: current_height = 11'd720;
            3'd1: current_height = 11'd360;
            3'd2: current_height = 11'd180;
            3'd3: current_height = 11'd90;
            3'd4: current_height = 11'd45;
            default: current_height = 11'd720;
        endcase
    end

    // ========================================================
    // Bit-Width Parameters
    // ========================================================
    // Pixel input: 8-bit unsigned zero-extended to 9-bit signed
    localparam PIXEL_W = 9;

    // Vertical filter output widths (OUT_WIDTH = IN_WIDTH + per-filter offset)
    //   p0: COEFF_W=16, 6 terms → OUT = PIXEL_W+1+16+3 = PIXEL_W+20 = 29
    //   p1: COEFF_W=14, 5 terms → OUT = PIXEL_W+1+14+3 = PIXEL_W+18 = 27
    //   p2: COEFF_W=13, 6 terms → OUT = PIXEL_W+1+13+3 = PIXEL_W+17 = 26
    localparam V_P0_W = PIXEL_W + 20;  // = 29 (natural p0 output width)
    localparam V_P1_W = PIXEL_W + 18;  // = 27 (used only for sign-extension)
    localparam V_P2_W = PIXEL_W + 17;  // = 26 (used only for sign-extension)
    // All paths beyond the vertical filters use a SINGLE unified VERT_W
    // equal to the widest vertical output (p0). Narrower p1/p2 outputs are
    // sign-extended to VERT_W before entering the shift registers.
    localparam VERT_W = V_P0_W;        // = 29

    // Horizontal filter output widths — all inputs are now VERT_W wide
    //   r2 = p1(VERT_W): VERT_W+1+14+3 = VERT_W+18 = 47
    //   r3 = p0(VERT_W): VERT_W+1+16+3 = VERT_W+20 = 49
    //   r4 = p2(VERT_W): VERT_W+1+13+3 = VERT_W+17 = 46
    //   r5 = p0(VERT_W): VERT_W+1+16+3 = VERT_W+20 = 49
    //   r6 = p1(VERT_W): VERT_W+1+14+3 = VERT_W+18 = 47
    localparam R2_W = VERT_W + 18;  // = 47  (raw)
    localparam R3_W = VERT_W + 20;  // = 49  (raw)
    localparam R4_W = VERT_W + 17;  // = 46  (raw)
    localparam R5_W = VERT_W + 20;  // = 49  (raw)
    localparam R6_W = VERT_W + 18;  // = 47  (raw)

    // Output widths after >>> 32 normalisation  (raw_width - 32)
    localparam OUT_R2_W = R2_W - 32;  // = 15
    localparam OUT_R3_W = R3_W - 32;  // = 17
    localparam OUT_R4_W = R4_W - 32;  // = 14
    localparam OUT_R5_W = R5_W - 32;  // = 17
    localparam OUT_R6_W = R6_W - 32;  // = 15

    // ========================================================
    // Valid Signal Routing
    // ========================================================
    // Vertical filters need 5 rows in the line buffers before producing valid output.
    // Enable them when y_counter is in [5 .. current_height+4] (inclusive),
    // covering the 5 boundary-extension rows past the frame bottom.
    wire v_filter_valid;
    assign v_filter_valid = valid_in &&
                            (y_counter >= 12'd5) &&
                            (y_counter <= (current_height + 12'd4));

    wire v_valid_p0, v_valid_p1, v_valid_p2;
    wire h_valid_r2;
    assign valid_out = h_valid_r2;

    // ========================================================
    // 1. Line Buffers & Column Assembly
    // ========================================================
    wire [7:0] delay_taps [0:9];

    genvar i;
    generate
        for (i = 0; i < 10; i = i + 1) begin : gen_line_buffers
            wire [7:0] lb_din = (i == 0) ? pixel_in : delay_taps[i-1];
            line_buffer u_line_buffer (
                .clk          (clk),
                .rst_n        (rst_n),
                .valid_in     (valid_in),
                .layer_config (layer_config),
                .pixel_in     (lb_din),
                .pixel_out    (delay_taps[i])
            );
        end
    endgenerate

    // Raw 11-tap column bus
    wire [7:0] raw_col [0:10];
    assign raw_col[0]  = pixel_in;
    assign raw_col[1]  = delay_taps[0];
    assign raw_col[2]  = delay_taps[1];
    assign raw_col[3]  = delay_taps[2];
    assign raw_col[4]  = delay_taps[3];
    assign raw_col[5]  = delay_taps[4]; // CENTER — always valid
    assign raw_col[6]  = delay_taps[5];
    assign raw_col[7]  = delay_taps[6];
    assign raw_col[8]  = delay_taps[7];
    assign raw_col[9]  = delay_taps[8];
    assign raw_col[10] = delay_taps[9];

    // ========================================================
    // Helper Functions for Dynamic BORDER_REFLECT_101
    // ========================================================
    function [3:0] clip_top;
        input [11:0] y;
        input [3:0] idx;
        reg signed [13:0] k;
        begin
            k = 2 * $signed({2'b0, y}) - $signed({10'b0, idx});
            if (k < 0) clip_top = 0;
            else if (k > 10) clip_top = 10;
            else clip_top = k[3:0];
        end
    endfunction

    function [3:0] clip_bot;
        input [11:0] y;
        input [11:0] h;
        input [3:0] idx;
        reg signed [14:0] k;
        begin
            k = 2 * $signed({3'b0, y}) - 2 * $signed({3'b0, h}) + 2 - $signed({11'b0, idx});
            if (k < 0) clip_bot = 0;
            else if (k > 10) clip_bot = 10;
            else clip_bot = k[3:0];
        end
    endfunction

    function [3:0] clip_left;
        input [11:0] x;
        input [3:0] idx;
        reg signed [13:0] k;
        begin
            k = 2 * $signed({2'b0, x}) - $signed({10'b0, idx});
            if (k < 0) clip_left = 0;
            else if (k > 10) clip_left = 10;
            else clip_left = k[3:0];
        end
    endfunction

    function [3:0] clip_right;
        input [11:0] x;
        input [11:0] w;
        input [3:0] idx;
        reg signed [14:0] k;
        begin
            k = 2 * $signed({3'b0, x}) - 2 * $signed({3'b0, w}) + 2 - $signed({11'b0, idx});
            if (k < 0) clip_right = 0;
            else if (k > 10) clip_right = 10;
            else clip_right = k[3:0];
        end
    endfunction

    // ========================================================
    // 2. Vertical Boundary Reflection (BORDER_REFLECT_101)
    // ========================================================
    // index 0 = newest row (just arrived), index 10 = oldest row
    // index 5 = CENTER — never reflected
    wire [7:0] column_data [0:10];
    assign column_data[5] = raw_col[5];

    // TOP boundary (y_counter < threshold → mirror from below)
    assign column_data[6]  = (y_counter < 12'd6)  ? raw_col[clip_top(y_counter, 4'd6)]  : raw_col[6];
    assign column_data[7]  = (y_counter < 12'd7)  ? raw_col[clip_top(y_counter, 4'd7)]  : raw_col[7];
    assign column_data[8]  = (y_counter < 12'd8)  ? raw_col[clip_top(y_counter, 4'd8)]  : raw_col[8];
    assign column_data[9]  = (y_counter < 12'd9)  ? raw_col[clip_top(y_counter, 4'd9)]  : raw_col[9];
    assign column_data[10] = (y_counter < 12'd10) ? raw_col[clip_top(y_counter, 4'd10)] : raw_col[10];

    // BOTTOM boundary (y_counter past frame edge → mirror from above)
    assign column_data[4] = (y_counter >= current_height + 12'd4) ? raw_col[clip_bot(y_counter, current_height, 4'd4)] : raw_col[4];
    assign column_data[3] = (y_counter >= current_height + 12'd3) ? raw_col[clip_bot(y_counter, current_height, 4'd3)] : raw_col[3];
    assign column_data[2] = (y_counter >= current_height + 12'd2) ? raw_col[clip_bot(y_counter, current_height, 4'd2)] : raw_col[2];
    assign column_data[1] = (y_counter >= current_height + 12'd1) ? raw_col[clip_bot(y_counter, current_height, 4'd1)] : raw_col[1];
    assign column_data[0] = (y_counter >= current_height)         ? raw_col[clip_bot(y_counter, current_height, 4'd0)] : raw_col[0];

    // Zero-extend to 9-bit signed
    wire signed [PIXEL_W-1:0] col_s [0:10];
    genvar j;
    generate
        for (j = 0; j < 11; j = j + 1) begin : sign_ext
            assign col_s[j] = {1'b0, column_data[j]};
        end
    endgenerate

    // Pack into a single bus for the filter inputs
    wire signed [PIXEL_W*11-1:0] column_data_packed;
    assign column_data_packed = {
        col_s[10], col_s[9], col_s[8], col_s[7], col_s[6],
        col_s[5],
        col_s[4], col_s[3], col_s[2], col_s[1], col_s[0]
    };

    // ========================================================
    // 3. Vertical MAC Stage
    // ========================================================
    // Raw outputs at their natural (narrower) widths
    wire signed [V_P0_W-1:0] v_p0_raw;
    wire signed [V_P1_W-1:0] v_p1_raw;
    wire signed [V_P2_W-1:0] v_p2_raw;

    p0_filter #(.IN_WIDTH(PIXEL_W)) vert_p0 (
        .clk(clk), .rst_n(rst_n), .valid_in(v_filter_valid),
        .data_in_packed(column_data_packed),
        .valid_out(v_valid_p0), .data_out(v_p0_raw)
    );

    p1_filter #(.IN_WIDTH(PIXEL_W)) vert_p1 (
        .clk(clk), .rst_n(rst_n), .valid_in(v_filter_valid),
        .data_in_packed(column_data_packed),
        .valid_out(v_valid_p1), .data_out(v_p1_raw)
    );

    p2_filter #(.IN_WIDTH(PIXEL_W)) vert_p2 (
        .clk(clk), .rst_n(rst_n), .valid_in(v_filter_valid),
        .data_in_packed(column_data_packed),
        .valid_out(v_valid_p2), .data_out(v_p2_raw)
    );

    // Sign-extend all vertical outputs to the unified VERT_W.
    // p0 is already VERT_W wide; p1 and p2 need MSB sign-extension.
    wire signed [VERT_W-1:0] v_p0_out;
    wire signed [VERT_W-1:0] v_p1_out;
    wire signed [VERT_W-1:0] v_p2_out;
    assign v_p0_out = v_p0_raw;  // no extension needed
    assign v_p1_out = {{(VERT_W-V_P1_W){v_p1_raw[V_P1_W-1]}}, v_p1_raw};
    assign v_p2_out = {{(VERT_W-V_P2_W){v_p2_raw[V_P2_W-1]}}, v_p2_raw};

    // ========================================================
    // 4. x_counter Pipeline Delay (3 cycles = filter pipeline depth)
    // ========================================================
    reg [11:0] x_counter_d1, x_counter_d2, x_counter_sr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_counter_d1 <= 12'd0;
            x_counter_d2 <= 12'd0;
            x_counter_sr <= 12'd0;
        end else begin
            x_counter_d1 <= x_counter;
            x_counter_d2 <= x_counter_d1;
            x_counter_sr <= x_counter_d2;
        end
    end

    // ========================================================
    // 5. Horizontal Shift Registers (11-tap sliding windows)
    // All three use the same VERT_W data width.
    // ========================================================
    wire signed [VERT_W*11-1:0] h_window_p0_packed;
    wire signed [VERT_W*11-1:0] h_window_p1_packed;
    wire signed [VERT_W*11-1:0] h_window_p2_packed;

    // Track if the current row had any valid vertical data
    reg row_has_valid_p0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_has_valid_p0 <= 1'b0;
        end else begin
            if (x_counter_sr == 12'd0) begin
                row_has_valid_p0 <= v_valid_p0;
            end else if (v_valid_p0) begin
                row_has_valid_p0 <= 1'b1;
            end
        end
    end

    // Enable horizontal shift when vertical data is valid OR during horizontal flush
    wire flush_h = row_has_valid_p0 && (x_counter_sr >= current_width) && (x_counter_sr <= current_width + 12'd4);
    wire h_shift_en = v_valid_p0 || flush_h;

    reg [11:0] x_counter_sr_d1;
    reg h_shift_en_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_counter_sr_d1 <= 12'd0;
            h_shift_en_d1   <= 1'b0;
        end else begin
            h_shift_en_d1 <= h_shift_en;
            if (h_shift_en) begin
                x_counter_sr_d1 <= x_counter_sr;
            end
        end
    end

    window_shift_reg #(.DATA_WIDTH(VERT_W), .WINDOW_SIZE(11)) shift_reg_p0 (
        .clk(clk), .rst_n(rst_n), .valid_in(h_shift_en),
        .data_in(v_p0_out), .window_out_packed(h_window_p0_packed)
    );

    window_shift_reg #(.DATA_WIDTH(VERT_W), .WINDOW_SIZE(11)) shift_reg_p1 (
        .clk(clk), .rst_n(rst_n), .valid_in(h_shift_en),
        .data_in(v_p1_out), .window_out_packed(h_window_p1_packed)
    );

    window_shift_reg #(.DATA_WIDTH(VERT_W), .WINDOW_SIZE(11)) shift_reg_p2 (
        .clk(clk), .rst_n(rst_n), .valid_in(h_shift_en),
        .data_in(v_p2_out), .window_out_packed(h_window_p2_packed)
    );



    // ========================================================
    // 6. Horizontal Boundary Reflection (BORDER_REFLECT_101)
    // ========================================================
    // Unpack raw taps — all VERT_W wide
    wire signed [VERT_W-1:0] raw_p0 [0:10];
    wire signed [VERT_W-1:0] raw_p1 [0:10];
    wire signed [VERT_W-1:0] raw_p2 [0:10];

    genvar t;
    generate
        for (t = 0; t < 11; t = t + 1) begin : unpack_h
            assign raw_p0[t] = h_window_p0_packed[t*VERT_W +: VERT_W];
            assign raw_p1[t] = h_window_p1_packed[t*VERT_W +: VERT_W];
            assign raw_p2[t] = h_window_p2_packed[t*VERT_W +: VERT_W];
        end
    endgenerate

    // Reflected taps — all VERT_W wide
    wire signed [VERT_W-1:0] ref_p0 [0:10];
    wire signed [VERT_W-1:0] ref_p1 [0:10];
    wire signed [VERT_W-1:0] ref_p2 [0:10];

    // Center — always pass-through
    assign ref_p0[5] = raw_p0[5];
    assign ref_p1[5] = raw_p1[5];
    assign ref_p2[5] = raw_p2[5];

    // LEFT boundary (oldest taps, indices 6-10)
    assign ref_p0[6]  = (x_counter_sr_d1 < 12'd6)  ? raw_p0[clip_left(x_counter_sr_d1, 4'd6)]  : raw_p0[6];
    assign ref_p0[7]  = (x_counter_sr_d1 < 12'd7)  ? raw_p0[clip_left(x_counter_sr_d1, 4'd7)]  : raw_p0[7];
    assign ref_p0[8]  = (x_counter_sr_d1 < 12'd8)  ? raw_p0[clip_left(x_counter_sr_d1, 4'd8)]  : raw_p0[8];
    assign ref_p0[9]  = (x_counter_sr_d1 < 12'd9)  ? raw_p0[clip_left(x_counter_sr_d1, 4'd9)]  : raw_p0[9];
    assign ref_p0[10] = (x_counter_sr_d1 < 12'd10) ? raw_p0[clip_left(x_counter_sr_d1, 4'd10)] : raw_p0[10];

    assign ref_p1[6]  = (x_counter_sr_d1 < 12'd6)  ? raw_p1[clip_left(x_counter_sr_d1, 4'd6)]  : raw_p1[6];
    assign ref_p1[7]  = (x_counter_sr_d1 < 12'd7)  ? raw_p1[clip_left(x_counter_sr_d1, 4'd7)]  : raw_p1[7];
    assign ref_p1[8]  = (x_counter_sr_d1 < 12'd8)  ? raw_p1[clip_left(x_counter_sr_d1, 4'd8)]  : raw_p1[8];
    assign ref_p1[9]  = (x_counter_sr_d1 < 12'd9)  ? raw_p1[clip_left(x_counter_sr_d1, 4'd9)]  : raw_p1[9];
    assign ref_p1[10] = (x_counter_sr_d1 < 12'd10) ? raw_p1[clip_left(x_counter_sr_d1, 4'd10)] : raw_p1[10];

    assign ref_p2[6]  = (x_counter_sr_d1 < 12'd6)  ? raw_p2[clip_left(x_counter_sr_d1, 4'd6)]  : raw_p2[6];
    assign ref_p2[7]  = (x_counter_sr_d1 < 12'd7)  ? raw_p2[clip_left(x_counter_sr_d1, 4'd7)]  : raw_p2[7];
    assign ref_p2[8]  = (x_counter_sr_d1 < 12'd8)  ? raw_p2[clip_left(x_counter_sr_d1, 4'd8)]  : raw_p2[8];
    assign ref_p2[9]  = (x_counter_sr_d1 < 12'd9)  ? raw_p2[clip_left(x_counter_sr_d1, 4'd9)]  : raw_p2[9];
    assign ref_p2[10] = (x_counter_sr_d1 < 12'd10) ? raw_p2[clip_left(x_counter_sr_d1, 4'd10)] : raw_p2[10];

    // RIGHT boundary (newest taps, indices 0-4)
    assign ref_p0[4] = (x_counter_sr_d1 >= current_width + 12'd4) ? raw_p0[clip_right(x_counter_sr_d1, current_width, 4'd4)] : raw_p0[4];
    assign ref_p0[3] = (x_counter_sr_d1 >= current_width + 12'd3) ? raw_p0[clip_right(x_counter_sr_d1, current_width, 4'd3)] : raw_p0[3];
    assign ref_p0[2] = (x_counter_sr_d1 >= current_width + 12'd2) ? raw_p0[clip_right(x_counter_sr_d1, current_width, 4'd2)] : raw_p0[2];
    assign ref_p0[1] = (x_counter_sr_d1 >= current_width + 12'd1) ? raw_p0[clip_right(x_counter_sr_d1, current_width, 4'd1)] : raw_p0[1];
    assign ref_p0[0] = (x_counter_sr_d1 >= current_width)         ? raw_p0[clip_right(x_counter_sr_d1, current_width, 4'd0)] : raw_p0[0];

    assign ref_p1[4] = (x_counter_sr_d1 >= current_width + 12'd4) ? raw_p1[clip_right(x_counter_sr_d1, current_width, 4'd4)] : raw_p1[4];
    assign ref_p1[3] = (x_counter_sr_d1 >= current_width + 12'd3) ? raw_p1[clip_right(x_counter_sr_d1, current_width, 4'd3)] : raw_p1[3];
    assign ref_p1[2] = (x_counter_sr_d1 >= current_width + 12'd2) ? raw_p1[clip_right(x_counter_sr_d1, current_width, 4'd2)] : raw_p1[2];
    assign ref_p1[1] = (x_counter_sr_d1 >= current_width + 12'd1) ? raw_p1[clip_right(x_counter_sr_d1, current_width, 4'd1)] : raw_p1[1];
    assign ref_p1[0] = (x_counter_sr_d1 >= current_width)         ? raw_p1[clip_right(x_counter_sr_d1, current_width, 4'd0)] : raw_p1[0];

    assign ref_p2[4] = (x_counter_sr_d1 >= current_width + 12'd4) ? raw_p2[clip_right(x_counter_sr_d1, current_width, 4'd4)] : raw_p2[4];
    assign ref_p2[3] = (x_counter_sr_d1 >= current_width + 12'd3) ? raw_p2[clip_right(x_counter_sr_d1, current_width, 4'd3)] : raw_p2[3];
    assign ref_p2[2] = (x_counter_sr_d1 >= current_width + 12'd2) ? raw_p2[clip_right(x_counter_sr_d1, current_width, 4'd2)] : raw_p2[2];
    assign ref_p2[1] = (x_counter_sr_d1 >= current_width + 12'd1) ? raw_p2[clip_right(x_counter_sr_d1, current_width, 4'd1)] : raw_p2[1];
    assign ref_p2[0] = (x_counter_sr_d1 >= current_width)         ? raw_p2[clip_right(x_counter_sr_d1, current_width, 4'd0)] : raw_p2[0];

    // Repack reflected windows — all VERT_W wide
    wire signed [VERT_W*11-1:0] h_ref_p0_packed;
    wire signed [VERT_W*11-1:0] h_ref_p1_packed;
    wire signed [VERT_W*11-1:0] h_ref_p2_packed;

    assign h_ref_p0_packed = {ref_p0[10], ref_p0[9], ref_p0[8], ref_p0[7], ref_p0[6],
                               ref_p0[5],
                               ref_p0[4], ref_p0[3], ref_p0[2], ref_p0[1], ref_p0[0]};
    assign h_ref_p1_packed = {ref_p1[10], ref_p1[9], ref_p1[8], ref_p1[7], ref_p1[6],
                               ref_p1[5],
                               ref_p1[4], ref_p1[3], ref_p1[2], ref_p1[1], ref_p1[0]};
    assign h_ref_p2_packed = {ref_p2[10], ref_p2[9], ref_p2[8], ref_p2[7], ref_p2[6],
                               ref_p2[5],
                               ref_p2[4], ref_p2[3], ref_p2[2], ref_p2[1], ref_p2[0]};

    // ========================================================
    // 7. Horizontal Filter Enable
    // ========================================================
    wire h_filter_valid;
    assign h_filter_valid = h_shift_en_d1 &&
                            (x_counter_sr_d1 >= 12'd5) &&
                            (x_counter_sr_d1 <= (current_width + 12'd4));

    // ========================================================
    // 8. Horizontal MAC Stage → r2..r6
    // ========================================================
    wire signed [R2_W-1:0] r2_raw;
    wire signed [R3_W-1:0] r3_raw;
    wire signed [R4_W-1:0] r4_raw;
    wire signed [R5_W-1:0] r5_raw;
    wire signed [R6_W-1:0] r6_raw;

    // All horizontal filters receive VERT_W-wide inputs
    // r2 = p1(V_p0): x-derivative of Gaussian-smoothed signal
    p1_filter #(.IN_WIDTH(VERT_W)) horiz_r2 (
        .clk(clk), .rst_n(rst_n), .valid_in(h_filter_valid),
        .data_in_packed(h_ref_p0_packed),
        .valid_out(h_valid_r2), .data_out(r2_raw)
    );

    // r3 = p0(V_p1): Gaussian-smooth the y-derivative
    p0_filter #(.IN_WIDTH(VERT_W)) horiz_r3 (
        .clk(clk), .rst_n(rst_n), .valid_in(h_filter_valid),
        .data_in_packed(h_ref_p1_packed),
        .valid_out(), .data_out(r3_raw)
    );

    // r4 = p2(V_p0): x second-derivative of Gaussian-smoothed signal
    p2_filter #(.IN_WIDTH(VERT_W)) horiz_r4 (
        .clk(clk), .rst_n(rst_n), .valid_in(h_filter_valid),
        .data_in_packed(h_ref_p0_packed),
        .valid_out(), .data_out(r4_raw)
    );

    // r5 = p0(V_p2): Gaussian-smooth the y second-derivative
    p0_filter #(.IN_WIDTH(VERT_W)) horiz_r5 (
        .clk(clk), .rst_n(rst_n), .valid_in(h_filter_valid),
        .data_in_packed(h_ref_p2_packed),
        .valid_out(), .data_out(r5_raw)
    );

    // r6 = p1(V_p1): cross-derivative (x-y)
    p1_filter #(.IN_WIDTH(VERT_W)) horiz_r6 (
        .clk(clk), .rst_n(rst_n), .valid_in(h_filter_valid),
        .data_in_packed(h_ref_p1_packed),
        .valid_out(), .data_out(r6_raw)
    );

    // ========================================================
    // 9. Final Normalisation (>>> 32 = remove the two Q16 scales)
    // Output ports are sized to OUT_R*_W = raw_width - 32, so
    // the assignment captures exactly the meaningful bits.
    // ========================================================
    assign r2_out = r2_raw >>> 32;
    assign r3_out = r3_raw >>> 32;
    assign r4_out = r4_raw >>> 32;
    assign r5_out = r5_raw >>> 32;
    assign r6_out = r6_raw >>> 32;

endmodule