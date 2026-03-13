#include "monitor.h"
#include "svdpi.h"
#include <stdio.h>
#include <stdlib.h>

static uint32_t* cpu_gpr = NULL;

extern "C" void set_gpr_ptr(const svOpenArrayHandle r) {
    cpu_gpr = (uint32_t *)svGetArrayPtr(r);
}

extern "C" void difftest_step(int pc, int inst) {
    // 预留给 Difftest
    // printf("[DPI-C] 提交指令: PC = 0x%08x, inst = 0x%08x\n", (unsigned int)pc, (unsigned int)inst);
}

void dump_registers() {
    if (!cpu_gpr) return;
    printf("---------- Register Snapshot ----------\n");
    for (int i = 0; i < 32; i++) {
        printf("x%-2d: 0x%08x  ", i, cpu_gpr[i]);
        if ((i + 1) % 4 == 0) printf("\n");
    }
    printf("---------------------------------------\n");
}

void check_exit_status() {
    if (cpu_gpr && cpu_gpr[10] == 0) {
        printf("\33[1;32m[SUCCESS] HIT GOOD TRAP!\33[0m\n");
    } else {
        printf("\33[1;31m[FAILED] HIT BAD TRAP!\33[0m\n");
        dump_registers();
        exit(1);
    }
}