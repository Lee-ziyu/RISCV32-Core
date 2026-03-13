/* verilator lint_off PINCONNECTEMPTY */
/* verilator lint_off PINMISSING */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off DECLFILENAME */

`include "defines.v"

module npc (
    input  wire        clk_i,
    input  wire        rst_i,

    // ==========================================
    // AXI4-Lite: Instruction Fetch (IF) 接口
    // ==========================================
    output wire [31:0] if_araddr,
    output wire        if_arvalid,
    input  wire        if_arready,
    input  wire [31:0] if_rdata,
    input  wire [1:0]  if_rresp,
    input  wire        if_rvalid,
    output wire        if_rready,

    // ==========================================
    // AXI4-Lite: Memory Access (MEM) 接口
    // ==========================================
    output wire [31:0] mem_araddr,
    output wire        mem_arvalid,
    input  wire        mem_arready,
    input  wire [31:0] mem_rdata,
    input  wire [1:0]  mem_rresp,
    input  wire        mem_rvalid,
    output wire        mem_rready,
    output wire [31:0] mem_awaddr,
    output wire        mem_awvalid,
    input  wire        mem_awready,
    output wire [31:0] mem_wdata,
    output wire [3:0]  mem_wstrb,
    output wire        mem_wvalid,
    input  wire        mem_wready,
    input  wire [1:0]  mem_bresp,
    input  wire        mem_bvalid,
    output wire        mem_bready,

    output wire        halt_o
);

    // ========================================================================
    // [0] CPU 控制中心：冒险检测与流水线流控 (Hazard Unit)
    // ========================================================================
    wire ifu_resp_valid;
    wire lsu_resp_valid;
    wire is_jump_ex;

    // --- 数据冒险检测 (Load-Use Hazard) ---
    // 条件：EX阶段正在执行Load指令，且目标寄存器与ID阶段需要的源寄存器冲突
    wire load_use_hazard = wb_sel_ex && (rd_addr_ex != 5'd0) &&
                           ((rd_addr_ex == rs1_addr_id) || (rd_addr_ex == rs2_addr_id));

    // --- 访存停顿检测 (Memory Stall) ---
    wire icache_stall    = !ifu_resp_valid;
    wire need_lsu_mem    = mem_we_mem || wb_sel_mem;
    wire dcache_stall    = need_lsu_mem && !lsu_resp_valid;

    // --- 全局控制信号 (Stall & Flush) ---
    wire stall_if_id     = icache_stall || dcache_stall || load_use_hazard;
    wire stall_ex_mem_wb = icache_stall || dcache_stall;
    wire flush_if_id     = is_jump_ex;                      // 发生跳转时冲刷IF阶段
    wire flush_id_ex     = is_jump_ex || load_use_hazard;   // Load-Use或跳转时冲刷ID阶段气泡


    // ========================================================================
    // [1] IF 阶段 (Instruction Fetch)
    // ========================================================================
    // --- 信号声明 ---
    wire [31:0] pc_if, inst_if, next_pc_w;
    wire        bridge_ifu_req_valid;
    wire [31:0] bridge_ifu_req_addr;
    wire        bridge_ifu_resp_valid;
    wire [31:0] bridge_ifu_rdata;

    // --- 模块例化 ---
    ifu u_ifu(
        .clk_i      (clk_i),
        .rst_i      (rst_i),
        .pc_we_i    (!stall_if_id),
        .next_pc_i  (is_jump_ex ? next_pc_w : pc_if + 4),
        .pc_o       (pc_if)
    );

    icache u_icache(
        .clk              (clk_i),
        .rst              (rst_i),
        .cpu_req_valid_i  (1'b1),
        .cpu_req_addr_i   (pc_if),
        .cpu_resp_valid_o (ifu_resp_valid),
        .cpu_resp_data_o  (inst_if),
        .mem_req_valid_o  (bridge_ifu_req_valid),
        .mem_req_addr_o   (bridge_ifu_req_addr),
        .mem_resp_valid_i (bridge_ifu_resp_valid),
        .mem_resp_data_i  (bridge_ifu_rdata)
    );

    sram2axi u_ifu_bridge(
        .clk          (clk_i),
        .rst          (rst_i),
        .req_valid_i  (bridge_ifu_req_valid),
        .req_ready_o  (),
        .req_addr_i   (bridge_ifu_req_addr),
        .req_we_i     (1'b0),
        .req_wdata_i  (32'b0),
        .req_wmask_i  (4'b0),
        .resp_valid_o (bridge_ifu_resp_valid),
        .resp_rdata_o (bridge_ifu_rdata),

        .axi_araddr   (if_araddr),  .axi_arvalid  (if_arvalid), .axi_arready(if_arready),
        .axi_rdata    (if_rdata),   .axi_rresp    (if_rresp),   .axi_rvalid (if_rvalid), .axi_rready(if_rready),
        .axi_awvalid  (),           .axi_wvalid   (),           .axi_bready ()
    );

    // ------------------------------------------------------------------------
    // [IF/ID] 流水线级间寄存器
    // ------------------------------------------------------------------------
    reg [31:0] pc_id, inst_id;

    always @(posedge clk_i) begin
        if (rst_i) begin
            pc_id   <= 32'h80000000;
            inst_id <= 32'h00000013; // NOP (addi x0, x0, 0)
        end else if (stall_if_id) begin
            // 停顿：保持当前状态不变
        end else if (flush_if_id) begin
            pc_id   <= 32'h80000000;
            inst_id <= 32'h00000013; // 冲刷：插入NOP气泡
        end else begin
            pc_id   <= pc_if;
            inst_id <= inst_if;
        end
    end


    // ========================================================================
    // [2] ID 阶段 (Instruction Decode)
    // ========================================================================
    // --- 信号声明 ---
    wire [4:0]  rs1_addr_id, rs2_addr_id, rd_addr_id, alu_op_id;
    wire [31:0] imm_id;
    wire [2:0]  mem_op_id;
    wire        rf_we_id, mem_we_id, wb_sel_id, alu_src1_sel_id, alu_src2_sel_id;
    wire        branch_en_id, jump_en_id, jalr_en_id, halt_en_id, error_en_id;

    // CSR 与特权级信号
    wire        csr_we_id, ecall_en_id, mret_en_id;
    wire [11:0] csr_addr_id    = inst_id[31:20];
    wire        is_sys_inst_id = csr_we_id;

    // --- 模块例化 ---
    decoder u_decoder(
        .inst_i         (inst_id),
        .rs1_addr_o     (rs1_addr_id),     .rs2_addr_o     (rs2_addr_id),     .rd_addr_o      (rd_addr_id),
        .imm_o          (imm_id),
        .rf_we_o        (rf_we_id),        .mem_we_o       (mem_we_id),       .wb_sel_o       (wb_sel_id),
        .alu_src1_sel_o (alu_src1_sel_id), .alu_src2_sel_o (alu_src2_sel_id), .alu_op_o       (alu_op_id),
        .branch_en_o    (branch_en_id),    .jump_en_o      (jump_en_id),      .jalr_en_o      (jalr_en_id),
        .halt_en_o      (halt_en_id),      .error_o        (error_en_id),     .mem_op_o       (mem_op_id),
        .csr_we_o       (csr_we_id),       .ecall_en_o     (ecall_en_id),     .mret_en_o      (mret_en_id)
    );

    wire [31:0] rf_rdata1, rf_rdata2;
    regfile u_regfile(
        .clk_i (clk_i),       .rst_i (rst_i),
        .we_i  (rf_we_wb),
        .ra1_i (rs1_addr_id), .rd1_o (rf_rdata1),
        .ra2_i (rs2_addr_id), .rd2_o (rf_rdata2),
        .wa_i  (rd_addr_wb),  .wd_i  (wb_data_wb)
    );

    // --- 级内前递 (WB -> ID Bypass) ---
    // 解决 3 拍 RAW 冲突：如果ID要读的寄存器碰巧WB正在写回，直接截胡最新数据
    wire [31:0] rs1_data_id = (rf_we_wb && rd_addr_wb != 5'd0 && rd_addr_wb == rs1_addr_id) ? wb_data_wb : rf_rdata1;
    wire [31:0] rs2_data_id = (rf_we_wb && rd_addr_wb != 5'd0 && rd_addr_wb == rs2_addr_id) ? wb_data_wb : rf_rdata2;

    // ------------------------------------------------------------------------
    // [ID/EX] 流水线级间寄存器
    // ------------------------------------------------------------------------
    reg [31:0] pc_ex, inst_ex, rs1_data_ex, rs2_data_ex, imm_ex;
    reg [4:0]  rs1_addr_ex, rs2_addr_ex, rd_addr_ex, alu_op_ex;
    reg [2:0]  mem_op_ex;
    reg        rf_we_ex, mem_we_ex, wb_sel_ex, alu_src1_sel_ex, alu_src2_sel_ex;
    reg        branch_en_ex, jump_en_ex, jalr_en_ex, halt_en_ex;
    reg [11:0] csr_addr_ex;
    reg        csr_we_ex, ecall_en_ex, mret_en_ex, is_sys_inst_ex;

    always @(posedge clk_i) begin
        if (rst_i) begin
            {rf_we_ex, mem_we_ex, wb_sel_ex, branch_en_ex, jump_en_ex, jalr_en_ex, halt_en_ex} <= 7'b0;
            {csr_we_ex, ecall_en_ex, mret_en_ex, is_sys_inst_ex} <= 4'b0;
            inst_ex    <= 32'h00000013;
            rd_addr_ex <= 5'b0;
        end else if (stall_ex_mem_wb) begin
            // 保持不变
        end else if (flush_id_ex) begin
            // 冲刷：清空控制信号，制造气泡，消灭幽灵指令(如错误的Load)
            {rf_we_ex, mem_we_ex, wb_sel_ex, branch_en_ex, jump_en_ex, jalr_en_ex, halt_en_ex} <= 7'b0;
            {csr_we_ex, ecall_en_ex, mret_en_ex, is_sys_inst_ex} <= 4'b0;
            inst_ex    <= 32'h00000013;
            rd_addr_ex <= 5'b0;
        end else begin
            pc_ex           <= pc_id;
            inst_ex         <= inst_id;
            rs1_data_ex     <= rs1_data_id;
            rs2_data_ex     <= rs2_data_id;
            rs1_addr_ex     <= rs1_addr_id;
            rs2_addr_ex     <= rs2_addr_id;
            imm_ex          <= imm_id;
            rd_addr_ex      <= rd_addr_id;
            alu_op_ex       <= alu_op_id;
            mem_op_ex       <= mem_op_id;
            rf_we_ex        <= rf_we_id;
            mem_we_ex       <= mem_we_id;
            wb_sel_ex       <= wb_sel_id;
            alu_src1_sel_ex <= alu_src1_sel_id;
            alu_src2_sel_ex <= alu_src2_sel_id;
            branch_en_ex    <= branch_en_id;
            jump_en_ex      <= jump_en_id;
            jalr_en_ex      <= jalr_en_id;
            halt_en_ex      <= halt_en_id;
            csr_addr_ex     <= csr_addr_id;
            csr_we_ex       <= csr_we_id;
            ecall_en_ex     <= ecall_en_id;
            mret_en_ex      <= mret_en_id;
            is_sys_inst_ex  <= is_sys_inst_id;
        end
    end


    // ========================================================================
    // [3] EX 阶段 (Execute) 与 前递网络
    // ========================================================================
    // --- 旁路前递网络 (Forwarding Unit) ---
    reg [1:0] forward_a, forward_b;
    always @(*) begin
        // ALU 源操作数 A 的前递
        if      (rf_we_mem && rd_addr_mem != 5'd0 && rd_addr_mem == rs1_addr_ex) forward_a = 2'b10; // 从 MEM 阶段前递
        else if (rf_we_wb  && rd_addr_wb  != 5'd0 && rd_addr_wb  == rs1_addr_ex) forward_a = 2'b01; // 从 WB 阶段前递
        else                                                                     forward_a = 2'b00; // 不前递

        // ALU 源操作数 B 的前递
        if      (rf_we_mem && rd_addr_mem != 5'd0 && rd_addr_mem == rs2_addr_ex) forward_b = 2'b10;
        else if (rf_we_wb  && rd_addr_wb  != 5'd0 && rd_addr_wb  == rs2_addr_ex) forward_b = 2'b01;
        else                                                                     forward_b = 2'b00;
    end

    // MEM 阶段传回来的数据：普通指令是ALU结果，跳转指令是PC+4
    wire [31:0] mem_forward_data = (jump_en_mem || jalr_en_mem) ? (pc_mem + 32'h4) : alu_res_mem;

    wire [31:0] forward_val_a = (forward_a == 2'b10) ? mem_forward_data :
                                (forward_a == 2'b01) ? wb_data_wb       : rs1_data_ex;

    wire [31:0] forward_val_b = (forward_b == 2'b10) ? mem_forward_data :
                                (forward_b == 2'b01) ? wb_data_wb       : rs2_data_ex;

    // --- ALU 与 BJU 模块 ---
    wire [31:0] alu_src1_ex  = alu_src1_sel_ex ? pc_ex  : forward_val_a;
    wire [31:0] alu_src2_ex  = alu_src2_sel_ex ? imm_ex : forward_val_b;
    wire [31:0] alu_res_ex;
    wire [31:0] mtvec_out, mepc_out;
    wire [31:0] csr_wdata_ex = forward_val_a; // CSR 写入截胡后的最新值

    alu u_alu(
        .src1_i (alu_src1_ex),
        .src2_i (alu_src2_ex),
        .op_i   (alu_op_ex),
        .res_o  (alu_res_ex)
    );

    bju u_bju(
        .pc_i        (pc_ex),         .imm_i       (imm_ex),       .alu_res_i  (alu_res_ex),
        .funct3_i    (inst_ex[14:12]),
        .branch_en_i (branch_en_ex),  .jump_en_i   (jump_en_ex),   .jalr_en_i  (jalr_en_ex),
        .next_pc_o   (next_pc_w),
        .rs1_data_i  (forward_val_a), .rs2_data_i  (forward_val_b),
        .ecall_en_i  (ecall_en_ex),   .mret_en_i   (mret_en_ex),
        .csr_mtvec_i (mtvec_out),     .csr_mepc_i  (mepc_out)
    );

    // 异常/中断也被统一视作特殊的跳转指令处理冲刷
    assign is_jump_ex = (jump_en_ex || jalr_en_ex || (branch_en_ex && (next_pc_w != pc_ex + 4)) || ecall_en_ex || mret_en_ex);

    // ------------------------------------------------------------------------
    // [EX/MEM] 流水线级间寄存器
    // ------------------------------------------------------------------------
    reg [31:0] pc_mem, inst_mem, alu_res_mem, rs2_data_mem;
    reg [4:0]  rd_addr_mem;
    reg [2:0]  mem_op_mem;
    reg        rf_we_mem, mem_we_mem, wb_sel_mem, jump_en_mem, jalr_en_mem, halt_en_mem;
    reg [11:0] csr_addr_mem;
    reg [31:0] csr_wdata_mem;
    reg        csr_we_mem, is_sys_inst_mem;

    always @(posedge clk_i) begin
        if (rst_i) begin
            {rf_we_mem, mem_we_mem, halt_en_mem, csr_we_mem, is_sys_inst_mem} <= 5'b0;
            inst_mem <= 32'h00000013;
        end else if (!stall_ex_mem_wb) begin
            pc_mem          <= pc_ex;
            inst_mem        <= inst_ex;
            alu_res_mem     <= alu_res_ex;
            rs2_data_mem    <= forward_val_b;
            rd_addr_mem     <= rd_addr_ex;
            mem_op_mem      <= mem_op_ex;
            rf_we_mem       <= rf_we_ex;
            mem_we_mem      <= mem_we_ex;
            wb_sel_mem      <= wb_sel_ex;
            jump_en_mem     <= jump_en_ex;
            jalr_en_mem     <= jalr_en_ex;
            halt_en_mem     <= halt_en_ex;
            csr_addr_mem    <= csr_addr_ex;
            csr_wdata_mem   <= csr_wdata_ex;
            csr_we_mem      <= csr_we_ex;
            is_sys_inst_mem <= is_sys_inst_ex;
        end
    end


    // ========================================================================
    // [4] MEM 阶段 (Memory Access)
    // ========================================================================
    // --- 信号声明 ---
    wire [31:0] lsu_addr, lsu_wdata, mem_read_data_mem;
    wire [3:0]  lsu_wmask;
    wire        lsu_we;

    // --- 模块例化 ---
    lsu u_lsu(
        .mem_op_i        (mem_op_mem),        .alu_res_i  (alu_res_mem),   .rs2_data_i (rs2_data_mem),
        .mem_we_i        (mem_we_mem),        .mem_rdata_i(mem_rdata),
        .mem_we_o        (lsu_we),            .mem_addr_o (lsu_addr),      .mem_wdata_o(lsu_wdata),
        .mem_mask_o      (lsu_wmask),         .mem_read_data_o(mem_read_data_mem)
    );

    sram2axi u_lsu_bridge(
        .clk          (clk_i),
        .rst          (rst_i),
        .req_valid_i  (mem_we_mem || wb_sel_mem),
        .req_ready_o  (),
        .req_addr_i   (lsu_addr),
        .req_we_i     (lsu_we),
        .req_wdata_i  (lsu_wdata),
        .req_wmask_i  (lsu_wmask),
        .resp_valid_o (lsu_resp_valid),
        .resp_rdata_o (),

        .axi_araddr   (mem_araddr), .axi_arvalid(mem_arvalid), .axi_arready(mem_arready),
        .axi_rdata    (mem_rdata),  .axi_rresp  (mem_rresp),   .axi_rvalid (mem_rvalid),  .axi_rready (mem_rready),
        .axi_awaddr   (mem_awaddr), .axi_awvalid(mem_awvalid), .axi_awready(mem_awready),
        .axi_wdata    (mem_wdata),  .axi_wstrb  (mem_wstrb),   .axi_wvalid (mem_wvalid),  .axi_wready (mem_wready),
        .axi_bresp    (mem_bresp),  .axi_bvalid (mem_bvalid),  .axi_bready (mem_bready)
    );

    // ------------------------------------------------------------------------
    // [MEM/WB] 流水线级间寄存器
    // ------------------------------------------------------------------------
    reg [31:0] pc_wb, inst_wb, alu_res_wb, mem_read_data_wb;
    reg [4:0]  rd_addr_wb;
    reg        rf_we_wb, wb_sel_wb, jump_en_wb, jalr_en_wb, halt_en_wb;
    reg [11:0] csr_addr_wb;
    reg [31:0] csr_wdata_wb;
    reg        csr_we_wb, is_sys_inst_wb;

    always @(posedge clk_i) begin
        if (rst_i) begin
            {rf_we_wb, halt_en_wb, csr_we_wb, is_sys_inst_wb} <= 4'b0;
            inst_wb <= 32'h00000013;
        end else if (!stall_ex_mem_wb) begin
            pc_wb            <= pc_mem;
            inst_wb          <= inst_mem;
            alu_res_wb       <= alu_res_mem;
            mem_read_data_wb <= mem_read_data_mem;
            rd_addr_wb       <= rd_addr_mem;
            rf_we_wb         <= rf_we_mem;
            wb_sel_wb        <= wb_sel_mem;
            jump_en_wb       <= jump_en_mem;
            jalr_en_wb       <= jalr_en_mem;
            halt_en_wb       <= halt_en_mem;
            csr_addr_wb      <= csr_addr_mem;
            csr_wdata_wb     <= csr_wdata_mem;
            csr_we_wb        <= csr_we_mem;
            is_sys_inst_wb   <= is_sys_inst_mem;
        end
    end


    // ========================================================================
    // [5] WB 阶段 (Write Back) 与 特权级 CSR 文件
    // ========================================================================
    wire [31:0] wb_data_wb;
    wire [31:0] csr_rdata_wb;

    // --- CSR 文件独立例化 ---
    csr_file u_csr_file(
        .clk         (clk_i),
        .rst         (rst_i),
        .trap_pc_i   (pc_ex),          // ecall 发生时的 PC (EX阶段触发)
        .mcause_i    (32'd11),         // M-mode ecall (Environment Call)
        .trap_vld_i  (ecall_en_ex && !stall_ex_mem_wb), // 确保流水线流动时才记录异常

        .csr_addr_i  (csr_addr_wb),
        .csr_wdata_i (csr_wdata_wb),
        .csr_we_i    (csr_we_wb && !stall_ex_mem_wb),

        .csr_rdata_o (csr_rdata_wb),   // 异步读取，送往 WBU
        .mtvec_o     (mtvec_out),      // 送往 BJU 用于 ecall 跳转
        .mepc_o      (mepc_out)        // 送往 BJU 用于 mret 返回
    );

    // --- 写回多路选择器 (WBU) ---
    wbu u_wbu(
        .pc_i            (pc_wb),            .alu_res_i     (alu_res_wb),
        .mem_read_data_i (mem_read_data_wb), .wb_sel_i      (wb_sel_wb),
        .jump_en_i       (jump_en_wb),       .jalr_en_i     (jalr_en_wb),
        .wb_data_o       (wb_data_wb),
        .csr_rdata_i     (csr_rdata_wb),     .is_sys_inst_i (is_sys_inst_wb)
    );

    // ========================================================================
    // [6] 仿真调试与停机监控 (Monitor & Difftest)
    // ========================================================================
    assign halt_o = halt_en_wb;

    import "DPI-C" function void difftest_step(input int pc, input int inst);

    always @(posedge clk_i) begin
        // 确保跳过复位和气泡NOP，且在未停顿时，提交 Difftest 验证
        if (!rst_i && inst_wb != 32'h00000013 && !stall_ex_mem_wb) begin
            difftest_step(pc_wb, inst_wb);
        end
    end

endmodule
