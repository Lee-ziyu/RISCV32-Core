module lsu (
    input  wire [2:0]  mem_op_i,
    input  wire [31:0] alu_res_i,
    input  wire [31:0] rs2_data_i,
    input  wire        mem_we_i,
    input  wire [31:0] mem_rdata_i,  // 这个数据直接来自于 sram2axi 桥读回的数据

    output wire        mem_we_o,
    output wire [31:0] mem_addr_o,
    output wire [31:0] mem_wdata_o,
    output reg  [3:0]  mem_mask_o,
    output reg  [31:0] mem_read_data_o
);

    // 直接透传地址、数据和写使能给外部桥
    assign mem_we_o    = mem_we_i;
    assign mem_addr_o  = alu_res_i;
    assign mem_wdata_o = rs2_data_i;

    // 纯组合逻辑符号扩展
    wire [31:0] lb_data  = {{24{mem_rdata_i[7]}},  mem_rdata_i[7:0]};
    wire [31:0] lh_data  = {{16{mem_rdata_i[15]}}, mem_rdata_i[15:0]};
    wire [31:0] lbu_data = {24'b0, mem_rdata_i[7:0]};
    wire [31:0] lhu_data = {16'b0, mem_rdata_i[15:0]};

    always @(*) begin
        case (mem_op_i)
            3'b000:  mem_read_data_o = lb_data;
            3'b001:  mem_read_data_o = lh_data;
            3'b010:  mem_read_data_o = mem_rdata_i; // lw
            3'b100:  mem_read_data_o = lbu_data;
            3'b101:  mem_read_data_o = lhu_data;
            default: mem_read_data_o = mem_rdata_i;
        endcase
    end

    // 生成掩码
    always @(*) begin
        if (mem_we_i) begin
            case (mem_op_i)
                3'b000:  mem_mask_o = 4'b0001;
                3'b001:  mem_mask_o = 4'b0011;
                3'b010:  mem_mask_o = 4'b1111;
                default: mem_mask_o = 4'b0000;
            endcase
        end else begin
            mem_mask_o = 4'b0000;
        end
    end
endmodule
