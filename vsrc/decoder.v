`include "defines.v"

module decoder (
    input  wire [31:0] inst_i,
    output wire [4:0]  rs1_addr_o, rs2_addr_o, rd_addr_o,
    output reg  [31:0] imm_o,

    // 控制信号
    output wire        rf_we_o, mem_we_o, wb_sel_o,
    output wire        alu_src1_sel_o, alu_src2_sel_o,
    output reg  [4:0]  alu_op_o,
    output wire        branch_en_o, jump_en_o, jalr_en_o,
    output wire        halt_en_o, error_o,
    output wire [2:0]  mem_op_o,

    // 系统与 CSR 控制信号
    output wire        csr_we_o,
    output wire        ecall_en_o,
    output wire        mret_en_o
);

    wire [6:0] opcode = inst_i[6:0];
    wire [2:0] funct3 = inst_i[14:12];
    wire [6:0] funct7 = inst_i[31:25];

    assign rd_addr_o  = inst_i[11:7];
    assign rs1_addr_o = (opcode == `OP_LUI) ? 5'b0 : inst_i[19:15];
    assign rs2_addr_o = inst_i[24:20];
    assign mem_op_o   = funct3;

    // --- 1. 指令分类解析 ---
    wire is_load   = (opcode == `OP_LOAD);
    wire is_imm    = (opcode == `OP_IMM);
    wire is_auipc  = (opcode == `OP_AUIPC);
    wire is_store  = (opcode == `OP_STORE);
    wire is_op     = (opcode == `OP_OP);
    wire is_lui    = (opcode == `OP_LUI);
    wire is_branch = (opcode == `OP_BRANCH);
    wire is_jalr   = (opcode == `OP_JALR);
    wire is_jal    = (opcode == `OP_JAL);
    wire is_sys    = (opcode == `OP_SYS);

    // M 扩展标志
    wire is_m_ext  = is_op && (funct7 == 7'b0000001);

    // SYS 子指令解析
    wire is_ecall  = is_sys && (funct3 == 3'b000) && (funct7 == 7'b0000000) && (rs2_addr_o == 5'b00000);
    wire is_ebreak = is_sys && (funct3 == 3'b000) && (funct7 == 7'b0000000) && (rs2_addr_o == 5'b00001);
    wire is_mret   = is_sys && (funct3 == 3'b000) && (funct7 == 7'b0011000) && (rs2_addr_o == 5'b00010);
    wire is_csrrw  = is_sys && (funct3 == 3'b001);
    wire is_csrrs  = is_sys && (funct3 == 3'b010);

    // --- 2. 立即数生成 ---
    always @(*) begin
        case (opcode)
            `OP_IMM, `OP_LOAD, `OP_JALR, `OP_SYS: imm_o = {{20{inst_i[31]}}, inst_i[31:20]};
            `OP_STORE:                            imm_o = {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]};
            `OP_BRANCH:                           imm_o = {{20{inst_i[31]}}, inst_i[7], inst_i[30:25], inst_i[11:8], 1'b0};
            `OP_AUIPC, `OP_LUI:                   imm_o = {inst_i[31:12], 12'b0};
            `OP_JAL:                              imm_o = {{12{inst_i[31]}}, inst_i[19:12], inst_i[20], inst_i[30:21], 1'b0};
            default:                              imm_o = 32'b0;
        endcase
    end

    // --- 3. 控制信号汇总 (查表法) ---
    assign rf_we_o        = is_lui | is_auipc | is_jal | is_jalr | is_load | is_imm | is_op | is_csrrw | is_csrrs;
    assign mem_we_o       = is_store;
    assign wb_sel_o       = is_load;

    assign alu_src1_sel_o = is_auipc;
    assign alu_src2_sel_o = is_lui | is_auipc | is_load | is_store | is_imm | is_jalr;

    assign branch_en_o    = is_branch;
    assign jump_en_o      = is_jal;
    assign jalr_en_o      = is_jalr;

    assign csr_we_o       = is_csrrw | is_csrrs;
    assign ecall_en_o     = is_ecall;
    assign mret_en_o      = is_mret;
    assign halt_en_o      = is_ebreak;

    // 错误指令检测：非预期的 opcode 或 SYS 非法组合
    wire sys_error = is_sys && !(is_ecall | is_ebreak | is_mret | is_csrrw | is_csrrs);
    assign error_o = sys_error | !(is_load|is_imm|is_auipc|is_store|is_op|is_lui|is_branch|is_jalr|is_jal|is_sys);

    // --- 4. ALU 操作码解析 ---
    always @(*) begin
        if (is_branch) begin
            alu_op_o = `ALU_SUB;
        end else if (is_m_ext) begin
            case (funct3)
                3'b000: alu_op_o = `ALU_MUL;
                3'b001: alu_op_o = `ALU_MULH;
                3'b010: alu_op_o = `ALU_MULHSU;
                3'b011: alu_op_o = `ALU_MULHU;
                3'b100: alu_op_o = `ALU_DIV;
                3'b101: alu_op_o = `ALU_DIVU;
                3'b110: alu_op_o = `ALU_REM;
                3'b111: alu_op_o = `ALU_REMU;
            endcase
        end else if (is_op || is_imm) begin
            case (funct3)
                3'b000: alu_op_o = (is_op && funct7 == 7'b0100000) ? `ALU_SUB : `ALU_ADD;
                3'b001: alu_op_o = `ALU_SLL;
                3'b010: alu_op_o = `ALU_SLT;
                3'b011: alu_op_o = `ALU_SLTU;
                3'b100: alu_op_o = `ALU_XOR;
                3'b101: alu_op_o = (funct7 == 7'b0100000) ? `ALU_SRA : `ALU_SRL;
                3'b110: alu_op_o = `ALU_OR;
                3'b111: alu_op_o = `ALU_AND;
            endcase
        end else begin
            alu_op_o = `ALU_ADD; // 默认加法用于计算地址
        end
    end
endmodule
