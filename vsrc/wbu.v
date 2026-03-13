module wbu (
    input  wire [31:0] pc_i, alu_res_i, mem_read_data_i,
    input  wire        wb_sel_i, jump_en_i, jalr_en_i,

    // --- 新增 CSR 写回信号 ---
    input  wire [31:0] csr_rdata_i,
    input  wire        is_sys_inst_i, // 是否是 SYSTEM 类指令

    output reg [31:0] wb_data_o
);
    always @(*) begin
        if (is_sys_inst_i) begin
            // CSR 指令，写回 CSR 的旧值
            wb_data_o = csr_rdata_i;
        end
        else if (jump_en_i || jalr_en_i) begin
            wb_data_o = pc_i + 32'h4;
        end
        else if (wb_sel_i) begin
            wb_data_o = mem_read_data_i;
        end
        else begin
            wb_data_o = alu_res_i;
        end
    end
endmodule
