#include "Vnpc.h"
#include "verilated.h"
#include "mem.h"
#include "monitor.h"

// ============================================================================
// AXI4-Lite 从设备模拟器 (封装状态机，解耦主循环)
// ============================================================================
class Axi4LiteSlave {
private:
    int r_state = 0;       // 读通道状态: 0=等待地址, 1=返回数据
    uint32_t r_addr = 0;   // 锁存的读地址

    int w_state = 0;       // 写通道状态: 0=等待地址和数据, 1=返回响应

public:
    // 处理 AXI 读通道握手
    void eval_read(uint8_t& arvalid, uint8_t& arready, vluint32_t& araddr,
                   uint8_t& rvalid,  uint8_t& rready,  vluint32_t& rdata) {
        if (r_state == 0) {
            arready = 1;
            rvalid  = 0;
            if (arvalid && arready) {
                r_addr = araddr;
                r_state = 1; // 握手成功，进入读数据阶段
            }
        } else {
            arready = 0;
            rvalid  = 1;
            rdata   = pmem_read(r_addr);
            if (rvalid && rready) {
                r_state = 0; // 数据被 CPU 拿走，回到空闲
            }
        }
    }

    // 处理 AXI 写通道握手 (简化版：要求 AW 和 W 同步到达)
    void eval_write(uint8_t& awvalid, uint8_t& awready, vluint32_t& awaddr,
                    uint8_t& wvalid,  uint8_t& wready,  vluint32_t& wdata, uint8_t& wstrb,
                    uint8_t& bvalid,  uint8_t& bready,  uint8_t& bresp) {
        if (w_state == 0) {
            awready = 1;
            wready  = 1;
            bvalid  = 0;
            if (awvalid && wvalid) {
                pmem_write(awaddr, wdata, wstrb);
                w_state = 1; // 数据写入成功，进入响应阶段
            }
        } else {
            awready = 0;
            wready  = 0;
            bvalid  = 1;
            bresp   = 0; // 0=OKAY
            if (bvalid && bready) {
                w_state = 0; // CPU 确认响应，回到空闲
            }
        }
    }
};

// ============================================================================
// 仿真主循环
// ============================================================================
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vnpc* top = new Vnpc();

    if (argc > 1) load_image(argv[1]);

    // 实例化两条 AXI 总线
    Axi4LiteSlave if_bus;   // 取指总线
    Axi4LiteSlave mem_bus;  // 访存总线

    // 硬件复位
    top->rst_i = 1; top->clk_i = 0; top->eval();
    top->clk_i = 1; top->eval();
    top->rst_i = 0;

    int cycles = 0;

    while (!top->halt_o && cycles < 100000000) {
        top->clk_i = 0;
        top->eval();

        // 1. 处理 IF (取指) AXI 通道
        if_bus.eval_read(top->if_arvalid, top->if_arready, top->if_araddr,
                         top->if_rvalid,  top->if_rready,  top->if_rdata);

        // 2. 处理 MEM (访存) AXI 通道
        mem_bus.eval_read(top->mem_arvalid, top->mem_arready, top->mem_araddr,
                          top->mem_rvalid,  top->mem_rready,  top->mem_rdata);

        mem_bus.eval_write(top->mem_awvalid, top->mem_awready, top->mem_awaddr,
                           top->mem_wvalid,  top->mem_wready,  top->mem_wdata, top->mem_wstrb,
                           top->mem_bvalid,  top->mem_bready,  top->mem_bresp);

        top->clk_i = 1;
        top->eval();
        cycles++;
    }

    if (top->halt_o) check_exit_status();

    delete top;
    return 0;
}