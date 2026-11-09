`timescale 1ns/1ps
module tb_matmul4x4;
    reg clk = 0, rst_n = 0, start = 0;
    reg  [255:0] a_flat, b_flat;
    wire [511:0] c_flat;
    wire busy, done;

    matmul4x4 dut (.clk(clk), .rst_n(rst_n), .start(start),
                   .a_flat(a_flat), .b_flat(b_flat), .c_flat(c_flat),
                   .busy(busy), .done(done));

    always #5 clk = ~clk;   // 100 MHz

    reg signed [15:0] A [0:3][0:3];
    reg signed [15:0] B [0:3][0:3];
    reg signed [31:0] expected, got;
    integer i, j, k, errors;

    initial begin
        errors = 0;
        for (i = 0; i < 4; i = i + 1)
            for (j = 0; j < 4; j = j + 1) begin
                A[i][j] = i*4 + j - 8;                 // includes negatives
                B[i][j] = (i == j) ? 2 : j - i;
                a_flat[(i*4+j)*16 +: 16] = A[i][j];
                b_flat[(i*4+j)*16 +: 16] = B[i][j];
            end

        #20 rst_n = 1;
        @(negedge clk) start = 1;
        @(negedge clk) start = 0;
        wait (done);
        @(negedge clk);

        for (i = 0; i < 4; i = i + 1)
            for (j = 0; j < 4; j = j + 1) begin
                expected = 0;
                for (k = 0; k < 4; k = k + 1)
                    expected = expected + A[i][k] * B[k][j];
                got = c_flat[(i*4+j)*32 +: 32];
                if (got !== expected) begin
                    $display("MISMATCH C[%0d][%0d]: got %0d expected %0d", i, j, got, expected);
                    errors = errors + 1;
                end
            end

        if (errors == 0) $display("PASS: all 16 outputs match");
        else             $display("FAIL: %0d mismatches", errors);
        $finish;
    end
endmodule
