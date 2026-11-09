// AXI4-Lite slave wrapper for matmul4x4.
// Register map (byte offsets):
//   0x00-0x3C  A[0..15]  (lower 16 bits used, row-major)
//   0x40-0x7C  B[0..15]
//   0x80       CTRL      bit0: write 1 to start
//   0x84       STATUS    bit0: done, bit1: busy
//   0xC0-0xFC  C[0..15]  (read-only, 32-bit signed)
// Note: WSTRB is ignored; PYNQ MMIO always writes full 32-bit words.
module matmul_axi_lite #(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 8
)(
    input  wire                          S_AXI_ACLK,
    input  wire                          S_AXI_ARESETN,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input  wire [2:0]                    S_AXI_AWPROT,
    input  wire                          S_AXI_AWVALID,
    output reg                           S_AXI_AWREADY,
    input  wire [31:0]                   S_AXI_WDATA,
    input  wire [3:0]                    S_AXI_WSTRB,
    input  wire                          S_AXI_WVALID,
    output reg                           S_AXI_WREADY,
    output reg  [1:0]                    S_AXI_BRESP,
    output reg                           S_AXI_BVALID,
    input  wire                          S_AXI_BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input  wire [2:0]                    S_AXI_ARPROT,
    input  wire                          S_AXI_ARVALID,
    output reg                           S_AXI_ARREADY,
    output reg  [31:0]                   S_AXI_RDATA,
    output reg  [1:0]                    S_AXI_RRESP,
    output reg                           S_AXI_RVALID,
    input  wire                          S_AXI_RREADY
);
    reg  [31:0] a_reg [0:15];
    reg  [31:0] b_reg [0:15];
    reg         start_pulse;
    wire [511:0] c_flat;
    wire        busy, done;

    wire [255:0] a_flat, b_flat;
    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : pack
            assign a_flat[g*16 +: 16] = a_reg[g][15:0];
            assign b_flat[g*16 +: 16] = b_reg[g][15:0];
        end
    endgenerate

    matmul4x4 core (
        .clk(S_AXI_ACLK), .rst_n(S_AXI_ARESETN), .start(start_pulse),
        .a_flat(a_flat), .b_flat(b_flat), .c_flat(c_flat),
        .busy(busy), .done(done)
    );

    // ---------------- Write channel ----------------
    wire [5:0] w_idx = S_AXI_AWADDR[7:2];
    integer n;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_AWREADY <= 1'b0;
            S_AXI_WREADY  <= 1'b0;
            S_AXI_BVALID  <= 1'b0;
            S_AXI_BRESP   <= 2'b00;
            start_pulse   <= 1'b0;
            for (n = 0; n < 16; n = n + 1) begin
                a_reg[n] <= 32'd0;
                b_reg[n] <= 32'd0;
            end
        end else begin
            start_pulse <= 1'b0;

            // Accept address and data together, one transaction at a time
            S_AXI_AWREADY <= ~S_AXI_AWREADY && S_AXI_AWVALID && S_AXI_WVALID && ~S_AXI_BVALID;
            S_AXI_WREADY  <= ~S_AXI_AWREADY && S_AXI_AWVALID && S_AXI_WVALID && ~S_AXI_BVALID;

            if (S_AXI_AWREADY && S_AXI_AWVALID) begin
                if (w_idx < 6'd16)       a_reg[w_idx[3:0]] <= S_AXI_WDATA;
                else if (w_idx < 6'd32)  b_reg[w_idx[3:0]] <= S_AXI_WDATA;
                else if (w_idx == 6'd32) start_pulse <= S_AXI_WDATA[0];
                S_AXI_BVALID <= 1'b1;
                S_AXI_BRESP  <= 2'b00;   // OKAY
            end else if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
        end
    end

    // ---------------- Read channel ----------------
    wire [5:0] r_idx = S_AXI_ARADDR[7:2];

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_ARREADY <= 1'b0;
            S_AXI_RVALID  <= 1'b0;
            S_AXI_RRESP   <= 2'b00;
            S_AXI_RDATA   <= 32'd0;
        end else begin
            S_AXI_ARREADY <= ~S_AXI_ARREADY && S_AXI_ARVALID && ~S_AXI_RVALID;

            if (S_AXI_ARREADY && S_AXI_ARVALID) begin
                S_AXI_RVALID <= 1'b1;
                S_AXI_RRESP  <= 2'b00;
                if (r_idx < 6'd16)       S_AXI_RDATA <= a_reg[r_idx[3:0]];
                else if (r_idx < 6'd32)  S_AXI_RDATA <= b_reg[r_idx[3:0]];
                else if (r_idx == 6'd33) S_AXI_RDATA <= {30'd0, busy, done};
                else if (r_idx >= 6'd48) S_AXI_RDATA <= c_flat[r_idx[3:0]*32 +: 32];
                else                     S_AXI_RDATA <= 32'd0;
            end else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end
endmodule
