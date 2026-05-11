module update_flow #(
    parameter G11_WIDTH = 97,
    parameter G22_WIDTH = 101,
    parameter G12_WIDTH = 99,
    parameter h1_WIDTH  = 99,
    parameter h2_WIDTH  = 101,
    parameter NUMX_WIDTH = G22_WIDTH + h1_WIDTH + 17,
    parameter NUMY_WIDTH = G11_WIDTH + h2_WIDTH + 17,
    parameter DET_WIDTH  = G11_WIDTH + G22_WIDTH + 17
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 valid_in,
    input  wire [2:0]           layer_config,
    
    // Inputs from update_matrices (Parameterized)
    input  wire signed [G11_WIDTH-1:0]  G11_in,
    input  wire signed [G22_WIDTH-1:0]  G22_in,
    input  wire signed [G12_WIDTH-1:0]  G12_in,
    input  wire signed [h1_WIDTH-1:0]   h1_in,
    input  wire signed [h2_WIDTH-1:0]   h2_in,

    // Outputs (Calculated Deltas)
    output reg                  valid_out,
    output reg signed [NUMX_WIDTH-1:0]  delta_x_out, 
    output reg signed [NUMY_WIDTH-1:0]  delta_y_out
);

    // ========================================================
    // Frame Dimensions & Internal Counters
    // ========================================================
    reg [11:0] current_width;
    reg [11:0] current_height;

    always @(*) begin
        case (layer_config)
            3'd0: begin current_width = 12'd1280; current_height = 12'd720; end
            3'd1: begin current_width = 12'd640;  current_height = 12'd360; end
            3'd2: begin current_width = 12'd320;  current_height = 12'd180; end
            3'd3: begin current_width = 12'd160;  current_height = 12'd90;  end
            3'd4: begin current_width = 12'd80;   current_height = 12'd45;  end
            default: begin current_width = 12'd1280; current_height = 12'd720; end
        endcase
    end

    reg [11:0] x_counter;
    reg [11:0] y_counter;
    reg in_v_pad;

    wire internal_valid = valid_in || (in_v_pad && x_counter < current_width);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_counter <= 12'd0;
            y_counter <= 12'd0;
            in_v_pad  <= 1'b0;
        end else begin
            if (valid_in || (in_v_pad && x_counter < current_width)) begin
                if (x_counter == current_width + 12'd6) begin
                    x_counter <= 12'd0;
                    if (y_counter == current_height + 12'd6) begin
                        y_counter <= 12'd0;
                        in_v_pad  <= 1'b0;
                    end else begin
                        y_counter <= y_counter + 12'd1;
                        if (y_counter + 12'd1 == current_height) in_v_pad <= 1'b1;
                    end
                end else begin
                    x_counter <= x_counter + 12'd1;
                end
            end else begin
                if (x_counter >= current_width && x_counter < current_width + 12'd6) begin
                    x_counter <= x_counter + 12'd1;
                end else if (x_counter == current_width + 12'd6) begin
                    x_counter <= 12'd0;
                    if (y_counter == current_height + 12'd6) begin
                        y_counter <= 12'd0;
                        in_v_pad  <= 1'b0;
                    end else begin
                        y_counter <= y_counter + 12'd1;
                        if (y_counter + 12'd1 == current_height) in_v_pad <= 1'b1;
                    end
                end
            end
        end
    end

    // Enable vertical filters only when buffering the frame and the 7 bottom padding rows
    wire v_filter_valid = internal_valid && (y_counter >= 12'd7) && (y_counter <= current_height + 12'd6);

    // ========================================================
    // Boundary Reflection Helpers (15-Tap Window -> Max Idx = 14)
    // ========================================================
    function [3:0] clip_top;
        input [11:0] y;
        input [3:0] idx;
        reg signed [13:0] k;
        begin
            k = 2 * $signed({2'b0, y}) - $signed({10'b0, idx});
            if (k < 0) clip_top = 0;
            else if (k > 14) clip_top = 14;
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
            else if (k > 14) clip_bot = 14;
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
            else if (k > 14) clip_left = 14;
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
            else if (k > 14) clip_right = 14;
            else clip_right = k[3:0];
        end
    endfunction

    // ========================================================
    // 1. Line Buffers (14 taps for a 15-element window)
    // ========================================================
    wire signed [G11_WIDTH-1:0] raw_G11_col [0:14];
    wire signed [G22_WIDTH-1:0] raw_G22_col [0:14];
    wire signed [G12_WIDTH-1:0] raw_G12_col [0:14];
    wire signed [h1_WIDTH-1:0]  raw_h1_col  [0:14];
    wire signed [h2_WIDTH-1:0]  raw_h2_col  [0:14];

    assign raw_G11_col[0] = G11_in;
    assign raw_G22_col[0] = G22_in;
    assign raw_G12_col[0] = G12_in;
    assign raw_h1_col[0]  = h1_in;
    assign raw_h2_col[0]  = h2_in;

    genvar i, k;
    generate
        for (i = 0; i < 14; i = i + 1) begin : gen_lbs
            line_buffer #(.DATA_WIDTH(G11_WIDTH)) lb_G11 (.clk(clk), .rst_n(rst_n), .valid_in(internal_valid), .layer_config(layer_config), .pixel_in(raw_G11_col[i]), .pixel_out(raw_G11_col[i+1]));
            line_buffer #(.DATA_WIDTH(G22_WIDTH)) lb_G22 (.clk(clk), .rst_n(rst_n), .valid_in(internal_valid), .layer_config(layer_config), .pixel_in(raw_G22_col[i]), .pixel_out(raw_G22_col[i+1]));
            line_buffer #(.DATA_WIDTH(G12_WIDTH)) lb_G12 (.clk(clk), .rst_n(rst_n), .valid_in(internal_valid), .layer_config(layer_config), .pixel_in(raw_G12_col[i]), .pixel_out(raw_G12_col[i+1]));
            line_buffer #(.DATA_WIDTH(h1_WIDTH))  lb_h1  (.clk(clk), .rst_n(rst_n), .valid_in(internal_valid), .layer_config(layer_config), .pixel_in(raw_h1_col[i]),  .pixel_out(raw_h1_col[i+1]));
            line_buffer #(.DATA_WIDTH(h2_WIDTH))  lb_h2  (.clk(clk), .rst_n(rst_n), .valid_in(internal_valid), .layer_config(layer_config), .pixel_in(raw_h2_col[i]),  .pixel_out(raw_h2_col[i+1]));
        end
    endgenerate

    // ========================================================
    // 2. Vertical Boundary Reflection 
    // ========================================================
    wire signed [G11_WIDTH-1:0] ref_G11_col [0:14];
    wire signed [G22_WIDTH-1:0] ref_G22_col [0:14];
    wire signed [G12_WIDTH-1:0] ref_G12_col [0:14];
    wire signed [h1_WIDTH-1:0]  ref_h1_col  [0:14];
    wire signed [h2_WIDTH-1:0]  ref_h2_col  [0:14];

    // Center elements pass through perfectly
    assign ref_G11_col[7] = raw_G11_col[7];
    assign ref_G22_col[7] = raw_G22_col[7];
    assign ref_G12_col[7] = raw_G12_col[7];
    assign ref_h1_col[7]  = raw_h1_col[7];
    assign ref_h2_col[7]  = raw_h2_col[7];

    generate
        // TOP Boundary (Oldest taps, indices 8 to 14)
        for (k = 8; k < 15; k = k + 1) begin : vert_top_reflect
            assign ref_G11_col[k] = (y_counter < k) ? raw_G11_col[clip_top(y_counter, k[3:0])] : raw_G11_col[k];
            assign ref_G22_col[k] = (y_counter < k) ? raw_G22_col[clip_top(y_counter, k[3:0])] : raw_G22_col[k];
            assign ref_G12_col[k] = (y_counter < k) ? raw_G12_col[clip_top(y_counter, k[3:0])] : raw_G12_col[k];
            assign ref_h1_col[k]  = (y_counter < k) ? raw_h1_col[clip_top(y_counter, k[3:0])]  : raw_h1_col[k];
            assign ref_h2_col[k]  = (y_counter < k) ? raw_h2_col[clip_top(y_counter, k[3:0])]  : raw_h2_col[k];
        end

        // BOTTOM Boundary (Newest taps, indices 0 to 6)
        for (k = 0; k < 7; k = k + 1) begin : vert_bot_reflect
            assign ref_G11_col[k] = (y_counter >= current_height + k) ? raw_G11_col[clip_bot(y_counter, current_height, k[3:0])] : raw_G11_col[k];
            assign ref_G22_col[k] = (y_counter >= current_height + k) ? raw_G22_col[clip_bot(y_counter, current_height, k[3:0])] : raw_G22_col[k];
            assign ref_G12_col[k] = (y_counter >= current_height + k) ? raw_G12_col[clip_bot(y_counter, current_height, k[3:0])] : raw_G12_col[k];
            assign ref_h1_col[k]  = (y_counter >= current_height + k) ? raw_h1_col[clip_bot(y_counter, current_height, k[3:0])]  : raw_h1_col[k];
            assign ref_h2_col[k]  = (y_counter >= current_height + k) ? raw_h2_col[clip_bot(y_counter, current_height, k[3:0])]  : raw_h2_col[k];
        end
    endgenerate

    // Pack reflected columns for filters
    wire signed [G11_WIDTH*15-1:0] G11_col_packed;
    wire signed [G22_WIDTH*15-1:0] G22_col_packed;
    wire signed [G12_WIDTH*15-1:0] G12_col_packed;
    wire signed [h1_WIDTH*15-1:0]  h1_col_packed;
    wire signed [h2_WIDTH*15-1:0]  h2_col_packed;

    generate
        for (i = 0; i < 15; i = i + 1) begin : pack_v_cols
            assign G11_col_packed[(i+1)*G11_WIDTH-1 : i*G11_WIDTH]   = ref_G11_col[i];
            assign G22_col_packed[(i+1)*G22_WIDTH-1 : i*G22_WIDTH] = ref_G22_col[i];
            assign G12_col_packed[(i+1)*G12_WIDTH-1 : i*G12_WIDTH]   = ref_G12_col[i];
            assign h1_col_packed[(i+1)*h1_WIDTH-1 : i*h1_WIDTH]    = ref_h1_col[i];
            assign h2_col_packed[(i+1)*h2_WIDTH-1 : i*h2_WIDTH]  = ref_h2_col[i];
        end
    endgenerate

    // ========================================================
    // 3. Vertical Box Filters (4 cycles latency, +4 bit growth)
    // ========================================================
    localparam V_G11_W = G11_WIDTH + 4;
    localparam V_G22_W = G22_WIDTH + 4;
    localparam V_G12_W = G12_WIDTH + 4;
    localparam V_h1_W  = h1_WIDTH + 4;
    localparam V_h2_W  = h2_WIDTH + 4;

    wire v_valid; 
    wire signed [V_G11_W-1:0] V_G11; 
    wire signed [V_G22_W-1:0] V_G22; 
    wire signed [V_G12_W-1:0] V_G12; 
    wire signed [V_h1_W-1:0]  V_h1;  
    wire signed [V_h2_W-1:0]  V_h2;  

    filter_15tap #(.IN_WIDTH(G11_WIDTH)) vfilt_G11 (.clk(clk), .rst_n(rst_n), .valid_in(v_filter_valid), .data_in_packed(G11_col_packed), .valid_out(v_valid), .data_out(V_G11));
    filter_15tap #(.IN_WIDTH(G22_WIDTH)) vfilt_G22 (.clk(clk), .rst_n(rst_n), .valid_in(v_filter_valid), .data_in_packed(G22_col_packed), .valid_out(), .data_out(V_G22));
    filter_15tap #(.IN_WIDTH(G12_WIDTH)) vfilt_G12 (.clk(clk), .rst_n(rst_n), .valid_in(v_filter_valid), .data_in_packed(G12_col_packed), .valid_out(), .data_out(V_G12));
    filter_15tap #(.IN_WIDTH(h1_WIDTH))  vfilt_h1  (.clk(clk), .rst_n(rst_n), .valid_in(v_filter_valid), .data_in_packed(h1_col_packed),  .valid_out(), .data_out(V_h1));
    filter_15tap #(.IN_WIDTH(h2_WIDTH))  vfilt_h2  (.clk(clk), .rst_n(rst_n), .valid_in(v_filter_valid), .data_in_packed(h2_col_packed),  .valid_out(), .data_out(V_h2));

    // ========================================================
    // 4. x_counter Delay Pipeline & Shift Enables
    // ========================================================
    // Delay x_counter to match the 4-cycle latency of the vertical box filters
    reg [11:0] x_counter_d1, x_counter_d2, x_counter_d3, x_counter_sr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_counter_d1 <= 12'd0; x_counter_d2 <= 12'd0; x_counter_d3 <= 12'd0; x_counter_sr <= 12'd0;
        end else begin
            x_counter_d1 <= x_counter;
            x_counter_d2 <= x_counter_d1;
            x_counter_d3 <= x_counter_d2;
            x_counter_sr <= x_counter_d3; 
        end
    end

    // Enable shifting horizontally during active frame OR boundary flush (+6 cols for radius 7)
    reg row_has_valid_vfilt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) row_has_valid_vfilt <= 0;
        else begin
            if (x_counter_sr == 12'd0) row_has_valid_vfilt <= v_valid;
            else if (v_valid)          row_has_valid_vfilt <= 1'b1;
        end
    end

    wire flush_h = row_has_valid_vfilt && (x_counter_sr >= current_width) && (x_counter_sr <= current_width + 12'd6);
    wire h_shift_en = v_valid || flush_h;

    // ========================================================
    // 5. Horizontal Shift Registers
    // ========================================================
    wire signed [V_G11_W*15-1:0] raw_G11_row_packed;
    wire signed [V_G22_W*15-1:0] raw_G22_row_packed;
    wire signed [V_G12_W*15-1:0] raw_G12_row_packed;
    wire signed [V_h1_W*15-1:0]  raw_h1_row_packed;
    wire signed [V_h2_W*15-1:0]  raw_h2_row_packed;

    window_shift_reg #(.DATA_WIDTH(V_G11_W), .WINDOW_SIZE(15)) h_shift_G11 (.clk(clk), .rst_n(rst_n), .valid_in(h_shift_en), .data_in(V_G11), .window_out_packed(raw_G11_row_packed));
    window_shift_reg #(.DATA_WIDTH(V_G22_W), .WINDOW_SIZE(15)) h_shift_G22 (.clk(clk), .rst_n(rst_n), .valid_in(h_shift_en), .data_in(V_G22), .window_out_packed(raw_G22_row_packed));
    window_shift_reg #(.DATA_WIDTH(V_G12_W), .WINDOW_SIZE(15)) h_shift_G12 (.clk(clk), .rst_n(rst_n), .valid_in(h_shift_en), .data_in(V_G12), .window_out_packed(raw_G12_row_packed));
    window_shift_reg #(.DATA_WIDTH(V_h1_W),  .WINDOW_SIZE(15)) h_shift_h1  (.clk(clk), .rst_n(rst_n), .valid_in(h_shift_en), .data_in(V_h1),  .window_out_packed(raw_h1_row_packed));
    window_shift_reg #(.DATA_WIDTH(V_h2_W),  .WINDOW_SIZE(15)) h_shift_h2  (.clk(clk), .rst_n(rst_n), .valid_in(h_shift_en), .data_in(V_h2),  .window_out_packed(raw_h2_row_packed));

    // Unpack rows for boundary reflection
    wire signed [V_G11_W-1:0] raw_G11_row [0:14];
    wire signed [V_G22_W-1:0] raw_G22_row [0:14];
    wire signed [V_G12_W-1:0] raw_G12_row [0:14];
    wire signed [V_h1_W-1:0]  raw_h1_row  [0:14];
    wire signed [V_h2_W-1:0]  raw_h2_row  [0:14];

    generate
        for (i = 0; i < 15; i = i + 1) begin : unpack_h_rows
            assign raw_G11_row[i] = raw_G11_row_packed[i*V_G11_W +: V_G11_W];
            assign raw_G22_row[i] = raw_G22_row_packed[i*V_G22_W +: V_G22_W];
            assign raw_G12_row[i] = raw_G12_row_packed[i*V_G12_W +: V_G12_W];
            assign raw_h1_row[i]  = raw_h1_row_packed[i*V_h1_W +: V_h1_W];
            assign raw_h2_row[i]  = raw_h2_row_packed[i*V_h2_W +: V_h2_W];
        end
    endgenerate

    // ========================================================
    // 6. Horizontal Boundary Reflection
    // ========================================================
    wire signed [V_G11_W-1:0] ref_G11_row [0:14];
    wire signed [V_G22_W-1:0] ref_G22_row [0:14];
    wire signed [V_G12_W-1:0] ref_G12_row [0:14];
    wire signed [V_h1_W-1:0]  ref_h1_row  [0:14];
    wire signed [V_h2_W-1:0]  ref_h2_row  [0:14];

    // Center elements pass through
    assign ref_G11_row[7] = raw_G11_row[7];
    assign ref_G22_row[7] = raw_G22_row[7];
    assign ref_G12_row[7] = raw_G12_row[7];
    assign ref_h1_row[7]  = raw_h1_row[7];
    assign ref_h2_row[7]  = raw_h2_row[7];

    reg [11:0] x_counter_sr_d1;
    reg        h_shift_en_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin x_counter_sr_d1 <= 0; h_shift_en_d1 <= 0; end
        else begin h_shift_en_d1 <= h_shift_en; if (h_shift_en) x_counter_sr_d1 <= x_counter_sr; end
    end

    generate
        // LEFT Boundary (Oldest taps, indices 8 to 14)
        for (k = 8; k < 15; k = k + 1) begin : horiz_left_reflect
            assign ref_G11_row[k] = (x_counter_sr_d1 < k) ? raw_G11_row[clip_left(x_counter_sr_d1, k[3:0])] : raw_G11_row[k];
            assign ref_G22_row[k] = (x_counter_sr_d1 < k) ? raw_G22_row[clip_left(x_counter_sr_d1, k[3:0])] : raw_G22_row[k];
            assign ref_G12_row[k] = (x_counter_sr_d1 < k) ? raw_G12_row[clip_left(x_counter_sr_d1, k[3:0])] : raw_G12_row[k];
            assign ref_h1_row[k]  = (x_counter_sr_d1 < k) ? raw_h1_row[clip_left(x_counter_sr_d1, k[3:0])]  : raw_h1_row[k];
            assign ref_h2_row[k]  = (x_counter_sr_d1 < k) ? raw_h2_row[clip_left(x_counter_sr_d1, k[3:0])]  : raw_h2_row[k];
        end

        // RIGHT Boundary (Newest taps, indices 0 to 6)
        for (k = 0; k < 7; k = k + 1) begin : horiz_right_reflect
            assign ref_G11_row[k] = (x_counter_sr_d1 >= current_width + k) ? raw_G11_row[clip_right(x_counter_sr_d1, current_width, k[3:0])] : raw_G11_row[k];
            assign ref_G22_row[k] = (x_counter_sr_d1 >= current_width + k) ? raw_G22_row[clip_right(x_counter_sr_d1, current_width, k[3:0])] : raw_G22_row[k];
            assign ref_G12_row[k] = (x_counter_sr_d1 >= current_width + k) ? raw_G12_row[clip_right(x_counter_sr_d1, current_width, k[3:0])] : raw_G12_row[k];
            assign ref_h1_row[k]  = (x_counter_sr_d1 >= current_width + k) ? raw_h1_row[clip_right(x_counter_sr_d1, current_width, k[3:0])]  : raw_h1_row[k];
            assign ref_h2_row[k]  = (x_counter_sr_d1 >= current_width + k) ? raw_h2_row[clip_right(x_counter_sr_d1, current_width, k[3:0])]  : raw_h2_row[k];
        end
    endgenerate

    // Repack
    wire signed [V_G11_W*15-1:0] ref_G11_row_packed;
    wire signed [V_G22_W*15-1:0] ref_G22_row_packed;
    wire signed [V_G12_W*15-1:0] ref_G12_row_packed;
    wire signed [V_h1_W*15-1:0]  ref_h1_row_packed;
    wire signed [V_h2_W*15-1:0]  ref_h2_row_packed;

    generate
        for (i = 0; i < 15; i = i + 1) begin : pack_h_rows
            assign ref_G11_row_packed[i*V_G11_W +: V_G11_W] = ref_G11_row[i];
            assign ref_G22_row_packed[i*V_G22_W +: V_G22_W] = ref_G22_row[i];
            assign ref_G12_row_packed[i*V_G12_W +: V_G12_W] = ref_G12_row[i];
            assign ref_h1_row_packed[i*V_h1_W +: V_h1_W]  = ref_h1_row[i];
            assign ref_h2_row_packed[i*V_h2_W +: V_h2_W]  = ref_h2_row[i];
        end
    endgenerate

    // Only pass valid to filters during active frame (not during padded edges)
    wire h_filter_valid = h_shift_en_d1 && (x_counter_sr_d1 >= 12'd7) && (x_counter_sr_d1 <= current_width + 12'd6);

    // ========================================================
    // 7. Horizontal Box Filters (+4 bit growth)
    // ========================================================
    localparam S_G11_W = V_G11_W + 4;
    localparam S_G22_W = V_G22_W + 4;
    localparam S_G12_W = V_G12_W + 4;
    localparam S_h1_W  = V_h1_W + 4;
    localparam S_h2_W  = V_h2_W + 4;

    wire h_valid;
    wire signed [S_G11_W-1:0] S_G11; 
    wire signed [S_G22_W-1:0] S_G22; 
    wire signed [S_G12_W-1:0] S_G12; 
    wire signed [S_h1_W-1:0]  S_h1;  
    wire signed [S_h2_W-1:0]  S_h2;  

    filter_15tap #(.IN_WIDTH(V_G11_W)) hfilt_G11 (.clk(clk), .rst_n(rst_n), .valid_in(h_filter_valid), .data_in_packed(ref_G11_row_packed), .valid_out(h_valid), .data_out(S_G11));
    filter_15tap #(.IN_WIDTH(V_G22_W)) hfilt_G22 (.clk(clk), .rst_n(rst_n), .valid_in(h_filter_valid), .data_in_packed(ref_G22_row_packed), .valid_out(), .data_out(S_G22));
    filter_15tap #(.IN_WIDTH(V_G12_W)) hfilt_G12 (.clk(clk), .rst_n(rst_n), .valid_in(h_filter_valid), .data_in_packed(ref_G12_row_packed), .valid_out(), .data_out(S_G12));
    filter_15tap #(.IN_WIDTH(V_h1_W))  hfilt_h1  (.clk(clk), .rst_n(rst_n), .valid_in(h_filter_valid), .data_in_packed(ref_h1_row_packed),  .valid_out(), .data_out(S_h1));
    filter_15tap #(.IN_WIDTH(V_h2_W))  hfilt_h2  (.clk(clk), .rst_n(rst_n), .valid_in(h_filter_valid), .data_in_packed(ref_h2_row_packed),  .valid_out(), .data_out(S_h2));

    // ========================================================
    // 8. Matrix Math & Delta Calculation
    // ========================================================
    wire signed [NUMX_WIDTH-1:0] numX = (S_G22 * S_h1) - (S_G12 * S_h2);
    wire signed [NUMY_WIDTH-1:0] numY = (S_G11 * S_h2) - (S_G12 * S_h1);
    wire signed [DET_WIDTH-1:0]  det  = (S_G11 * S_G22) - (S_G12 * S_G12);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out   <= 0;
            delta_x_out <= 0;
            delta_y_out <= 0;
        end else begin
            valid_out <= h_valid;
            if (h_valid) begin
                if (det != 0) begin
                    delta_x_out <= numX / det;
                    delta_y_out <= numY / det;
                end else begin
                    delta_x_out <= 0;
                    delta_y_out <= 0;
                end
            end
        end
    end

endmodule