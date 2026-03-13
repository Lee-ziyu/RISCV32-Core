/* verilator lint_off UNUSEDSIGNAL */

module sram2axi (
    input  wire        clk,
    input  wire        rst,

    // --- CPU 侧 SRAM 接口 ---
    input  wire        req_valid_i,
    output wire        req_ready_o,
    input  wire [31:0] req_addr_i,
    input  wire        req_we_i,
    input  wire [31:0] req_wdata_i,
    input  wire [3:0]  req_wmask_i,

    output reg         resp_valid_o,
    output reg  [31:0] resp_rdata_o,

    // --- AXI4-Lite 侧接口 (连到外部) ---
    // 读地址通道 (AR)
    output wire [31:0] axi_araddr,
    output wire [2:0]  axi_arprot,   // 特权访问
    output wire        axi_arvalid,
    input  wire        axi_arready,
    // 读数据通道 (R)
    input  wire [31:0] axi_rdata,
    input  wire [1:0]  axi_rresp,
    input  wire        axi_rvalid,
    output wire        axi_rready,
    // 写地址通道 (AW)
    output wire [31:0] axi_awaddr,
    output wire [2:0]  axi_awprot,
    output wire        axi_awvalid,
    input  wire        axi_awready,
    // 写数据通道 (W)
    output wire [31:0] axi_wdata,
    output wire [3:0]  axi_wstrb,
    output wire        axi_wvalid,
    input  wire        axi_wready,
    // 写响应通道 (B)
    input  wire [1:0]  axi_bresp,
    input  wire        axi_bvalid,
    output wire        axi_bready
);

    // 简易桥接状态机
    localparam IDLE  = 0;
    localparam AR    = 1;
    localparam R     = 2;
    localparam AW_W  = 3;
    localparam B     = 4;

    reg [2:0] state, next_state;

    // ==========================================
    // AXI 信号驱动 (组合逻辑)
    // ==========================================
    // 默认输出 3'b000 (Unprivileged, Secure, Data)
    assign axi_arprot  = 3'b000;
    assign axi_awprot  = 3'b000;

    assign axi_arvalid = (state == AR);
    assign axi_araddr  = req_addr_i;
    assign axi_rready  = (state == R);

    assign axi_awvalid = (state == AW_W);
    assign axi_awaddr  = req_addr_i;
    assign axi_wvalid  = (state == AW_W);
    assign axi_wdata   = req_wdata_i;
    assign axi_wstrb   = req_wmask_i;
    assign axi_bready  = (state == B);

    assign req_ready_o = (state == IDLE);

    always @(posedge clk) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    always @(*) begin
        next_state   = state;
        resp_valid_o = 0;
        resp_rdata_o = 32'b0;

        case (state)
            IDLE: begin
                if (req_valid_i) begin
                    next_state = req_we_i ? AW_W : AR;
                end
            end
            AR: begin
                if (axi_arvalid && axi_arready) next_state = R;
            end
            R: begin
                if (axi_rvalid && axi_rready) begin
                    resp_valid_o = 1;
                    resp_rdata_o = axi_rdata;
                    // 这里应该检查 if (axi_rresp == 2'b00)，目前简化处理
                    next_state   = IDLE;
                end
            end
            AW_W: begin
                if (axi_awvalid && axi_awready && axi_wvalid && axi_wready)
                    next_state = B;
            end
            B: begin
                if (axi_bvalid && axi_bready) begin
                    resp_valid_o = 1;
                    // 这里应该检查 if (axi_bresp == 2'b00)，目前简化处理
                    next_state   = IDLE;
                end
            end
            default: next_state = IDLE;
        endcase
    end
endmodule
