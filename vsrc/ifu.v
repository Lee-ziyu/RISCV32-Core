module ifu #(parameter RESET_VAL = 32'h80000000) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        pc_we_i,      // 【新增】PC 写使能
    input  wire [31:0] next_pc_i,
    output reg  [31:0] pc_o
);
    always @(posedge clk_i) begin
        if (rst_i) begin
            pc_o <= RESET_VAL;
        end else if (pc_we_i) begin  // 【新增】只有使能有效时才跳！
            pc_o <= next_pc_i;
        end
    end
endmodule
