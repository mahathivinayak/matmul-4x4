// 4x4 signed matrix multiplier: C = A * B
// Inputs: 16-bit signed, row-major. Outputs: 32-bit signed.
// Computes one output element per clock (4 parallel MACs), 16 cycles total.
module matmul4x4 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [255:0] a_flat,   // 16 x 16-bit, element (i,j) at [(i*4+j)*16 +: 16]
    input  wire [255:0] b_flat,
    output reg  [511:0] c_flat,   // 16 x 32-bit, element (i,j) at [(i*4+j)*32 +: 32]
    output reg          busy,
    output reg          done
);
    wire signed [15:0] a [0:15];
    wire signed [15:0] b [0:15];

    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : unpack
            assign a[g] = a_flat[g*16 +: 16];
            assign b[g] = b_flat[g*16 +: 16];
        end
    endgenerate

    reg  [3:0] idx;               // output element index = i*4 + j
    wire [1:0] i = idx[3:2];
    wire [1:0] j = idx[1:0];

    // Row i of A dot column j of B. Index a[i*4+k] = {i,k}, b[k*4+j] = {k,j}
    wire signed [31:0] dot = a[{i,2'd0}] * b[{2'd0,j}]
                           + a[{i,2'd1}] * b[{2'd1,j}]
                           + a[{i,2'd2}] * b[{2'd2,j}]
                           + a[{i,2'd3}] * b[{2'd3,j}];

    always @(posedge clk) begin
        if (!rst_n) begin
            idx    <= 4'd0;
            busy   <= 1'b0;
            done   <= 1'b0;
            c_flat <= 512'd0;
        end else if (start && !busy) begin
            busy <= 1'b1;
            done <= 1'b0;
            idx  <= 4'd0;
        end else if (busy) begin
            c_flat[idx*32 +: 32] <= dot;
            if (idx == 4'd15) begin
                busy <= 1'b0;
                done <= 1'b1;     // stays high until next start
            end
            idx <= idx + 4'd1;
        end
    end
endmodule
