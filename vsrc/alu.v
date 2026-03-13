// ALU 操作码 (扩容为 5 bit，以支持更多指令)
`define ALU_ADD    5'd0
`define ALU_SUB    5'd1
`define ALU_SLL    5'd2
`define ALU_SLT    5'd3
`define ALU_SLTU   5'd4
`define ALU_XOR    5'd5
`define ALU_SRL    5'd6
`define ALU_SRA    5'd7
`define ALU_OR     5'd8
`define ALU_AND    5'd9
// M 扩展 (乘除法)
`define ALU_MUL    5'd10
`define ALU_MULH   5'd11
`define ALU_MULHSU 5'd12
`define ALU_MULHU  5'd13
`define ALU_DIV    5'd14
`define ALU_DIVU   5'd15
`define ALU_REM    5'd16
`define ALU_REMU   5'd17

module alu (
    input  wire [31:0] src1_i,
    input  wire [31:0] src2_i,
    input  wire [4:0]  op_i,  // 宽度改为 5 位
    output reg  [31:0] res_o
);
    wire signed [31:0] s_src1 = $signed(src1_i);
    wire signed [31:0] s_src2 = $signed(src2_i);
    wire [4:0] shamt = src2_i[4:0]; // 移位量
    wire signed [31:0] s_div_res = s_src1 / s_src2;
    wire signed [31:0] s_rem_res = s_src1 % s_src2;

    // 【新增】把乘法的 64 位中间结果放在 always 块外面计算
    /* verilator lint_off UNUSEDSIGNAL */
    wire [63:0] mul_ss = {{32{src1_i[31]}}, src1_i} * {{32{src2_i[31]}}, src2_i};
    wire [63:0] mul_su = {{32{src1_i[31]}}, src1_i} * {32'b0, src2_i};
    wire [63:0] mul_uu = {32'b0, src1_i} * {32'b0, src2_i};


    always @(*) begin
        case(op_i)
            `ALU_ADD:  res_o = src1_i + src2_i;
            `ALU_SUB:  res_o = src1_i - src2_i;
            `ALU_SLL:  res_o = src1_i << shamt;
            `ALU_SLT:  res_o = (s_src1 < s_src2) ? 32'b1 : 32'b0;
            `ALU_SLTU: res_o = (src1_i < src2_i) ? 32'b1 : 32'b0;
            `ALU_XOR:  res_o = src1_i ^ src2_i;
            `ALU_SRL:  res_o = src1_i >> shamt;
            `ALU_SRA:  res_o = s_src1 >>> shamt; // >>> 是算术右移
            `ALU_OR:   res_o = src1_i | src2_i;
            `ALU_AND:  res_o = src1_i & src2_i;

            // --- M 扩展 (乘除法) ---
            `ALU_MUL:  res_o = src1_i * src2_i;
            `ALU_MULH: res_o = mul_ss[63:32];
            `ALU_MULHSU:res_o = mul_su[63:32];
            `ALU_MULHU:res_o = mul_uu[63:32];
            // ... M 扩展 ...
            `ALU_DIV:  res_o = (src2_i == 0) ? 32'hFFFFFFFF :
                               (src1_i == 32'h80000000 && src2_i == 32'hFFFFFFFF) ? src1_i : s_div_res;
            `ALU_DIVU: res_o = (src2_i == 0) ? 32'hFFFFFFFF : (src1_i / src2_i);
            `ALU_REM:  res_o = (src2_i == 0) ? src1_i :
                               (src1_i == 32'h80000000 && src2_i == 32'hFFFFFFFF) ? 32'b0 : s_rem_res;
            `ALU_REMU: res_o = (src2_i == 0) ? src1_i : (src1_i % src2_i);
            default:   res_o = 32'b0;
        endcase
    end
endmodule
