module icache (
    input  wire        clk,
    input  wire        rst,

    // ==========================================
    // 左侧：对接 CPU (IFU 取指阶段)
    // ==========================================
    input  wire        cpu_req_valid_i,  // CPU 发起取指请求
    input  wire [31:0] cpu_req_addr_i,   // CPU 请求的 PC 地址
    output reg         cpu_resp_valid_o, // Cache 命中，返回有效信号
    output reg  [31:0] cpu_resp_data_o,  // Cache 返回的指令数据

    // ==========================================
    // 右侧：对接 下级转接桥 (sram2axi)
    // ==========================================
    output reg         mem_req_valid_o,  // Cache 没命中，请求下级桥接器去内存拿
    output wire [31:0] mem_req_addr_o,   // 给下级桥接器的物理地址
    input  wire        mem_resp_valid_i, // 下级桥接器把数据拿回来了
    input  wire [31:0] mem_resp_data_i   // 下级桥接器拿回来的数据
);

    // --- 1. 地址切分 (64 个格子版) ---
    // 32 位地址切分：
    // [1:0]  偏移量 (总是00，忽略)
    // [7:2]  格子号 (Index)，6位二进制刚好表示 0~63
    // [31:8] 身份签 (Tag)，剩下的 24 位用于核对身份
    wire [5:0]  index = cpu_req_addr_i[7:2];
    wire [23:0] tag   = cpu_req_addr_i[31:8];

    // --- 2. 物理存储体 (64行 SRAM) ---
    reg [31:0] cache_data  [0:63]; // 存指令
    reg [23:0] cache_tag   [0:63]; // 存标签
    reg        cache_valid [0:63]; // 存有效位

    // --- 3. 极简状态机 ---
    localparam S_IDLE   = 1'b0; // 空闲/命中判断状态
    localparam S_REFILL = 1'b1; // 缺失进货状态

    reg state, next_state;

    // 瞬间判断是否命中：柜子有效 且 标签完全相等
    wire is_hit = cache_valid[index] && (cache_tag[index] == tag);

    always @(posedge clk) begin
        if (rst) state <= S_IDLE;
        else     state <= next_state;
    end

    // 状态流转逻辑
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                // CPU 来要数据，且没命中，去进货
                if (cpu_req_valid_i && !is_hit) next_state = S_REFILL;
            end
            S_REFILL: begin
                // 下级把货送回来了，回空闲状态
                if (mem_resp_valid_i) next_state = S_IDLE;
            end
        endcase
    end

    // --- 4. 存入新数据 ---
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            // 复位时清空所有柜子
            for (i = 0; i < 64; i = i + 1) cache_valid[i] <= 1'b0;
        end else if (state == S_REFILL && mem_resp_valid_i) begin
            // 进货成功，写入对应柜子，贴上标签
            cache_valid[index] <= 1'b1;
            cache_tag[index]   <= tag;
            cache_data[index]  <= mem_resp_data_i;
        end
    end

    // --- 5. 信号输出与旁路 ---
    // 请求内存的地址永远是 CPU 请求的地址
    assign mem_req_addr_o = cpu_req_addr_i;

    always @(*) begin
        cpu_resp_valid_o = 1'b0;
        cpu_resp_data_o  = 32'b0;
        mem_req_valid_o  = 1'b0;

        if (state == S_IDLE) begin
            if (cpu_req_valid_i) begin
                if (is_hit) begin
                    // 【0 周期命中】：纯导线直连，瞬间返回！
                    cpu_resp_valid_o = 1'b1;
                    cpu_resp_data_o  = cache_data[index];
                end else begin
                    // 【未命中】：拉高请求，叫 sram2axi 去干活
                    mem_req_valid_o  = 1'b1;
                end
            end
        end else if (state == S_REFILL) begin
            // 【旁路直传】：货到的那一刻，直接跨过柜子扔给 CPU，省一个周期
            if (mem_resp_valid_i) begin
                cpu_resp_valid_o = 1'b1;
                cpu_resp_data_o  = mem_resp_data_i;
            end
        end
    end

endmodule
