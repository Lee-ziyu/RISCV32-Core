module csr_file (
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] trap_pc_i,
    input  wire [31:0] mcause_i,
    input  wire        trap_vld_i,

    input  wire [11:0] csr_addr_i,
    input  wire [31:0] csr_wdata_i,
    input  wire        csr_we_i,

    output reg  [31:0] csr_rdata_o,
    output wire [31:0] mtvec_o,
    output wire [31:0] mepc_o
);

    reg [31:0] mstatus;
    reg [31:0] mtvec;
    reg [31:0] mepc;
    reg [31:0] mcause;

    assign mtvec_o = mtvec;
    assign mepc_o  = mepc;

    always @(posedge clk) begin
        if (rst) begin
            mepc    <= 32'b0;
            mcause  <= 32'b0;
            mtvec   <= 32'b0;
            mstatus <= 32'h1800; // 默认 M-mode
        end else if (trap_vld_i) begin
            mepc    <= trap_pc_i;
            mcause  <= mcause_i;
        end else if (csr_we_i) begin
            case (csr_addr_i)
                12'h300: mstatus <= csr_wdata_i;
                12'h305: mtvec   <= csr_wdata_i;
                12'h341: mepc    <= csr_wdata_i;
                12'h342: mcause  <= csr_wdata_i;
                default: ;
            endcase
        end
    end

    always @(*) begin
        case (csr_addr_i)
            12'h300: csr_rdata_o = mstatus;
            12'h305: csr_rdata_o = mtvec;
            12'h341: csr_rdata_o = mepc;
            12'h342: csr_rdata_o = mcause;
            default: csr_rdata_o = 32'b0;
        endcase
    end
endmodule
