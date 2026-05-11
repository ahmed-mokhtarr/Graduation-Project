module update_matrices #(
    parameter W_R2 = 47,
    parameter W_R3 = 49,
    parameter W_R4 = 46,
    parameter W_R5 = 49,
    parameter W_R6 = 47,

    // Calculated parameters
    parameter W_DB_X = W_R2 + 1,
    parameter W_DB_Y = W_R3 + 1,
    parameter W_A11  = W_R4 + 1,
    parameter W_A22  = W_R5 + 1,
    parameter W_A12  = W_R6 + 1,

    parameter W_A11_SQ = 2 * W_A11,
    parameter W_A22_SQ = 2 * W_A22,
    parameter W_A12_SQ = 2 * W_A12,

    parameter W_H1_T1 = W_A11 + W_DB_X,
    parameter W_H1_T2 = W_A12 + W_DB_Y,
    parameter W_H2_T1 = W_A12 + W_DB_X,
    parameter W_H2_T2 = W_A22 + W_DB_Y,

    parameter W_A_TRACE = (W_A11 > W_A22 ? W_A11 : W_A22) + 1,

    parameter W_G11 = (W_A11_SQ > W_A12_SQ ? W_A11_SQ : W_A12_SQ) + 1,
    parameter W_G22 = (W_A12_SQ > W_A22_SQ ? W_A12_SQ : W_A22_SQ) + 1,
    parameter W_G12 = W_A12 + W_A_TRACE,

    parameter W_H1 = (W_H1_T1 > W_H1_T2 ? W_H1_T1 : W_H1_T2) + 1,
    parameter W_H2 = (W_H2_T1 > W_H2_T2 ? W_H2_T1 : W_H2_T2) + 1
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 valid_in,

    // Previous Frame Inputs (Frame 1)
    input  wire signed [W_R2-1:0]   prev_frame_r2,
    input  wire signed [W_R3-1:0]   prev_frame_r3,
    input  wire signed [W_R4-1:0]   prev_frame_r4,
    input  wire signed [W_R5-1:0]   prev_frame_r5,
    input  wire signed [W_R6-1:0]   prev_frame_r6,

    // Current Frame Inputs (Frame 2)
    input  wire signed [W_R2-1:0]   curr_frame_r2,
    input  wire signed [W_R3-1:0]   curr_frame_r3,
    input  wire signed [W_R4-1:0]   curr_frame_r4,
    input  wire signed [W_R5-1:0]   curr_frame_r5,
    input  wire signed [W_R6-1:0]   curr_frame_r6,

    // Final Pipelined Outputs
    output reg                  valid_out,

    output reg  signed [W_G11-1:0]  matrix_G11_out,
    output reg  signed [W_G12-1:0]  matrix_G12_out,
    output reg  signed [W_G22-1:0]  matrix_G22_out,
    output reg  signed [W_H1-1:0]   vector_h1_out,
    output reg  signed [W_H2-1:0]   vector_h2_out
);

    // ==========================================
    // Stage 1 Registers: Pre-computation & Shifts
    // ==========================================
    reg signed [W_DB_X-1:0] delta_b_x_s1;
    reg signed [W_DB_Y-1:0] delta_b_y_s1;
    reg signed [W_A11-1:0]  matrix_A11_s1;
    reg signed [W_A22-1:0]  matrix_A22_s1;
    reg signed [W_A12-1:0]  matrix_A12_s1;
        reg               valid_s1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            delta_b_x_s1  <= 'd0;
            delta_b_y_s1  <= 'd0;
            matrix_A11_s1 <= 'd0;
            matrix_A22_s1 <= 'd0;
            matrix_A12_s1 <= 'd0;

            valid_s1      <= 1'b0;
        end else if (valid_in) begin
            // Arithmetic shift right (>>>) divides by 2 and 4 preserving the sign bit.
            delta_b_x_s1  <= ($signed(prev_frame_r2) - $signed(curr_frame_r2)) >>> 1; // delta_b = -0.5(b2 - b1)  ==  0.5(b1 - b2)
            delta_b_y_s1  <= ($signed(prev_frame_r3) - $signed(curr_frame_r3)) >>> 1;
            matrix_A11_s1 <= ($signed(prev_frame_r4) + $signed(curr_frame_r4)) >>> 1; // A = 0.5(A1 + A2)
            matrix_A22_s1 <= ($signed(prev_frame_r5) + $signed(curr_frame_r5)) >>> 1;
            matrix_A12_s1 <= ($signed(prev_frame_r6) + $signed(curr_frame_r6)) >>> 2; 
            
            valid_s1      <= 1'b1;
        end else begin
            valid_s1      <= 1'b0;
        end
    end

    // ==========================================
    // Stage 2 Registers: DSP Multiplications
    // ==========================================
    reg signed [W_A11_SQ-1:0] A11_squared_s2;
    reg signed [W_A22_SQ-1:0] A22_squared_s2;
    reg signed [W_A12_SQ-1:0] A12_squared_s2;
    
    reg signed [W_H1_T1-1:0] h1_term1_s2;
    reg signed [W_H1_T2-1:0] h1_term2_s2;
    reg signed [W_H2_T1-1:0] h2_term1_s2;
    reg signed [W_H2_T2-1:0] h2_term2_s2;
    
    // Sum of diagonal elements (Trace of matrix A) for optimized G12 calculation -->  from A12 * A11 + A12 * A22 TO A12(A11+A22)
    reg signed [W_A_TRACE-1:0] A_trace_sum_s2;
    
    // Pipeline alignment registers
    reg signed [W_A12-1:0] matrix_A12_delay_s2; 
    reg               valid_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A11_squared_s2      <= 'd0;
            A22_squared_s2      <= 'd0;
            A12_squared_s2      <= 'd0;
            h1_term1_s2         <= 'd0;
            h1_term2_s2         <= 'd0;
            h2_term1_s2         <= 'd0;
            h2_term2_s2         <= 'd0;
            A_trace_sum_s2      <= 'd0;
            matrix_A12_delay_s2 <= 'd0;
            valid_s2            <= 1'b0;
        end else if (valid_s1) begin
            A11_squared_s2      <= matrix_A11_s1 * matrix_A11_s1; // A11^2
            A22_squared_s2      <= matrix_A22_s1 * matrix_A22_s1; // A22^2
            A12_squared_s2      <= matrix_A12_s1 * matrix_A12_s1; // A12^2
            
            h1_term1_s2         <= matrix_A11_s1 * delta_b_x_s1;    // A11 * delta_b_x
            h1_term2_s2         <= matrix_A12_s1 * delta_b_y_s1;    // A12 * delta_b_y
            h2_term1_s2         <= matrix_A12_s1 * delta_b_x_s1;    // A12 * delta_b_x
            h2_term2_s2         <= matrix_A22_s1 * delta_b_y_s1;    // A22 * delta_b_y
            
            A_trace_sum_s2      <= $signed(matrix_A11_s1) + $signed(matrix_A22_s1); // A11 + A22 
            matrix_A12_delay_s2 <= matrix_A12_s1;  // A12 

            valid_s2            <= 1'b1;
        end else begin
            valid_s2            <= 1'b0;
        end
    end

    // ==========================================
    // Stage 3 Registers: Final Accumulation
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            matrix_G11_out <= 'd0;
            matrix_G12_out <= 'd0;
            matrix_G22_out <= 'd0;
            vector_h1_out  <= 'd0;
            vector_h2_out  <= 'd0;
            valid_out      <= 1'b0;
        end else if (valid_s2) begin
            matrix_G11_out <= $signed(A11_squared_s2) + $signed(A12_squared_s2); // A11^2 + A12^2
            matrix_G22_out <= $signed(A12_squared_s2) + $signed(A22_squared_s2); // A12^2 + A22^2
            matrix_G12_out <= matrix_A12_delay_s2 * A_trace_sum_s2;              // A12(A11 + A22)
            
            vector_h1_out  <= $signed(h1_term1_s2)  + $signed(h1_term2_s2);  // A11 * delta_b_x + A12 * delta_b_y
            vector_h2_out  <= $signed(h2_term1_s2)  + $signed(h2_term2_s2);  // A12 * delta_b_x + A22 * delta_b_y
            
            valid_out      <= 1'b1;
        end else begin
            valid_out      <= 1'b0;
        end
    end

endmodule