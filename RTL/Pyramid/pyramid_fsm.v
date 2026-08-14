`timescale 1ns / 1ps

module pyramid_fsm #(
    parameter BURST_LEN = 10'd64 // 64 beats * 4 bytes (32-bit bus) = 256 bytes per burst
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       eof_pulse,     
    input  wire [9:0] L0_cnt, L1_cnt, L2_cnt, L3_cnt, L4_cnt,
    input  wire       cmd_ready,     
    input  wire       axi_bvalid,    
    output reg        cmd_valid,
    output reg  [2:0] cmd_layer,     
    output reg  [9:0] cmd_len,       
    output wire [1:0] cmd_slot,  
    output reg        write_valid,
    output reg  [1:0] frame_num
);

    localparam [3:0] ST_STREAMING   = 4'd0, 
                     ST_FLUSH_L0    = 4'd1, 
                     ST_FLUSH_L1    = 4'd2,
                     ST_FLUSH_L2    = 4'd3, 
                     ST_FLUSH_L3    = 4'd4, 
                     ST_FLUSH_L4    = 4'd5,
                     ST_WAIT_BVALID = 4'd6, 
                     ST_NOTIFY_TAU  = 4'd7;

    reg [3:0] current_state, next_state;
    reg [1:0] idx;
    reg       eof_latched;

    assign cmd_slot = idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            current_state <= ST_STREAMING;
        else 
            current_state <= next_state;
    end

    always @(*) begin
        next_state = current_state;
        case (current_state)
            ST_STREAMING: if (eof_latched && cmd_ready && !cmd_valid) 
                            next_state = ST_FLUSH_L0;
            ST_FLUSH_L0: if (L0_cnt == 0) 
                            next_state = ST_FLUSH_L1;
            ST_FLUSH_L1: if (L1_cnt == 0) 
                            next_state = ST_FLUSH_L2;
            ST_FLUSH_L2: if (L2_cnt == 0) 
                            next_state = ST_FLUSH_L3;
            ST_FLUSH_L3: if (L3_cnt == 0) 
                            next_state = ST_FLUSH_L4;
            ST_FLUSH_L4: if (L4_cnt == 0) 
                            next_state = ST_WAIT_BVALID;
            ST_WAIT_BVALID: if (axi_bvalid) 
                            next_state = ST_NOTIFY_TAU;

            ST_NOTIFY_TAU: next_state = ST_STREAMING;
            default: next_state = ST_STREAMING;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx <= 2'b00; 
            write_valid <= 1'b0; 
            frame_num <= 2'b00; 
            eof_latched <= 1'b0;
            cmd_valid <= 1'b0; 
            cmd_layer <= 3'd0; 
            cmd_len <= 10'd0;
        end else begin
            write_valid <= 1'b0;
            if (eof_pulse) 
               eof_latched <= 1'b1;

            case (current_state)
                ST_STREAMING: begin
                    if (cmd_valid && cmd_ready) begin
                        cmd_valid <= 1'b0; 
                    end else if (!cmd_valid && cmd_ready && !eof_latched) begin
                        if (L0_cnt >= BURST_LEN) begin
                             cmd_valid <= 1'b1; 
                             cmd_layer <= 3'd0; 
                             cmd_len <= BURST_LEN; 
                        end 
                        else if (L1_cnt >= BURST_LEN) begin 
                            cmd_valid <= 1'b1; 
                            cmd_layer <= 3'd1; 
                            cmd_len <= BURST_LEN; 
                        end 
                        else if (L2_cnt >= BURST_LEN) begin 
                            cmd_valid <= 1'b1; 
                            cmd_layer <= 3'd2; 
                            cmd_len <= BURST_LEN; 
                        end 
                        else if (L3_cnt >= BURST_LEN) begin 
                            cmd_valid <= 1'b1; 
                            cmd_layer <= 3'd3; 
                            cmd_len <= BURST_LEN; 
                        end 
                        else if (L4_cnt >= BURST_LEN) begin 
                            cmd_valid <= 1'b1; 
                            cmd_layer <= 3'd4; 
                            cmd_len <= BURST_LEN; 
                        end
                    end
                end

                ST_FLUSH_L0: begin
                    if (L0_cnt > 0) begin
                        if (cmd_valid && cmd_ready) 
                          cmd_valid <= 1'b0; 
                        else if (!cmd_valid) begin
                            cmd_valid <= 1'b1; 
                            cmd_layer <= 3'd0;
                            cmd_len   <= (L0_cnt > BURST_LEN) ? BURST_LEN : L0_cnt;
                        end
                    end else cmd_valid <= 1'b0;
                end
                ST_FLUSH_L1: begin
                    if (L1_cnt > 0) begin
                        if (cmd_valid && cmd_ready) cmd_valid <= 1'b0; 
                        else if (!cmd_valid) begin
                            cmd_valid <= 1'b1; cmd_layer <= 3'd1;
                            cmd_len   <= (L1_cnt > BURST_LEN) ? BURST_LEN : L1_cnt;
                        end
                    end else cmd_valid <= 1'b0;
                end
                ST_FLUSH_L2: begin
                    if (L2_cnt > 0) begin
                        if (cmd_valid && cmd_ready) cmd_valid <= 1'b0; 
                        else if (!cmd_valid) begin
                            cmd_valid <= 1'b1; cmd_layer <= 3'd2;
                            cmd_len   <= (L2_cnt > BURST_LEN) ? BURST_LEN : L2_cnt;
                        end
                    end else cmd_valid <= 1'b0;
                end
                ST_FLUSH_L3: begin
                    if (L3_cnt > 0) begin
                        if (cmd_valid && cmd_ready) cmd_valid <= 1'b0; 
                        else if (!cmd_valid) begin
                            cmd_valid <= 1'b1; cmd_layer <= 3'd3;
                            cmd_len   <= (L3_cnt > BURST_LEN) ? BURST_LEN : L3_cnt;
                        end
                    end else cmd_valid <= 1'b0;
                end
                ST_FLUSH_L4: begin
                    if (L4_cnt > 0) begin
                        if (cmd_valid && cmd_ready) cmd_valid <= 1'b0; 
                        else if (!cmd_valid) begin
                            cmd_valid <= 1'b1; cmd_layer <= 3'd4;
                            cmd_len   <= (L4_cnt > BURST_LEN) ? BURST_LEN : L4_cnt;
                        end
                    end else cmd_valid <= 1'b0;
                end

                ST_WAIT_BVALID: cmd_valid <= 1'b0;

                ST_NOTIFY_TAU: begin
                    write_valid <= 1'b1; frame_num <= idx; idx <= idx + 2'b01; eof_latched <= 1'b0;
                end
                default: cmd_valid <= 1'b0;
            endcase
        end
    end
endmodule