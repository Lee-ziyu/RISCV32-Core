module regfile (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire [4:0]  ra1_i,
    output wire [31:0] rd1_o,
    input  wire [4:0]  ra2_i,
    output wire [31:0] rd2_o,
    input  wire [4:0]  wa_i,
    input  wire [31:0] wd_i,
    input  wire        we_i
);
    // riscv的32个寄存器
    bit [31:0] rf [0:31] /* verilator public */;

    // --- DPI-C 声明 ---
    // void 表示不返回数据，input 表示从 Verilog 传给 C++
    import "DPI-C" function void set_gpr_ptr(input bit [31:0] a []);
    initial begin
        $display("Verilog: 正在尝试调用 DPI 函数同步寄存器...");
        set_gpr_ptr(rf);
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            integer i;
            for (i = 0; i < 32; i = i + 1) rf[i] <= 32'b0;
        end else if (we_i && (wa_i != 5'b0)) begin
            rf[wa_i] <= wd_i;
        end
    end

    assign rd1_o = (ra1_i == 5'b0) ? 32'b0 : rf[ra1_i];
    assign rd2_o = (ra2_i == 5'b0) ? 32'b0 : rf[ra2_i];
endmodule

