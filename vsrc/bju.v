module bju (
    input  wire [31:0] pc_i, imm_i, rs1_data_i, rs2_data_i, alu_res_i,
    input  wire [2:0]  funct3_i,
    input  wire        branch_en_i, jump_en_i, jalr_en_i,

    // --- 新增 CSR 跳转信号 ---
    input  wire        ecall_en_i,
    input  wire        mret_en_i,
    input  wire [31:0] csr_mtvec_i,
    input  wire [31:0] csr_mepc_i,

    output reg [31:0] next_pc_o
);
    // 分支条件判断
    wire is_beq  = (rs1_data_i == rs2_data_i);
    wire is_bne  = (rs1_data_i != rs2_data_i);
    wire is_blt  = ($signed(rs1_data_i) < $signed(rs2_data_i));
    wire is_bge  = ($signed(rs1_data_i) >= $signed(rs2_data_i));
    wire is_bltu = (rs1_data_i < rs2_data_i);
    wire is_bgeu = (rs1_data_i >= rs2_data_i);

    reg br_taken;
    always @(*) begin
        if (branch_en_i) begin
            case (funct3_i)
                3'b000: br_taken = is_beq;
                3'b001: br_taken = is_bne;
                3'b100: br_taken = is_blt;
                3'b101: br_taken = is_bge;
                3'b110: br_taken = is_bltu;
                3'b111: br_taken = is_bgeu;
                default: br_taken = 1'b0;
            endcase
        end else begin
            br_taken = 1'b0;
        end
    end

    always @(*) begin
        // 异常跳转优先级最高！
        if (ecall_en_i) begin
            next_pc_o = csr_mtvec_i;
        end
        else if (mret_en_i) begin
            next_pc_o = csr_mepc_i;
        end
        else if (jalr_en_i) begin
            next_pc_o = alu_res_i & ~32'h1;
        end
        else if (br_taken || jump_en_i) begin
            next_pc_o = pc_i + imm_i;
        end
        else begin
            next_pc_o = pc_i + 32'h4;
        end
    end
endmodule
