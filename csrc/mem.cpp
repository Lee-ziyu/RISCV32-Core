#include "mem.h"
#include <stdio.h>
#include <assert.h>
#include <sys/time.h>
#include <stdint.h>

static uint64_t boot_time = 0;
static uint8_t guest_mem[128 * 1024 * 1024];

static uint64_t get_time_internal() {
    struct timeval now;
    gettimeofday(&now, NULL);
    uint64_t us = (uint64_t)now.tv_sec * 1000000 + now.tv_usec;
    if (boot_time == 0) boot_time = us;
    return us - boot_time;
}

void load_image(const char *img_file) {
    if (!img_file) return;
    FILE *fp = fopen(img_file, "rb");
    assert(fp != NULL);
    fseek(fp, 0, SEEK_END);
    long size = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    size_t ret = fread(guest_mem, size, 1, fp);
    assert(ret == 1 || size == 0);
    fclose(fp);
    printf("[MEM] 镜像加载完成: %s (%ld bytes)\n", img_file, size);
}

// 统一了普通内存和 MMIO 的读取
uint32_t pmem_read(uint32_t addr) {
    if (addr >= 0x80000000 && addr < 0x88000000) {
        return *(uint32_t *)(guest_mem + (addr - 0x80000000));
    } else if (addr == RTC_ADDR) {
        return (uint32_t)(get_time_internal() & 0xFFFFFFFF);
    } else if (addr == RTC_ADDR + 4) {
        return (uint32_t)(get_time_internal() >> 32);
    }
    return 0;
}

// 统一了普通内存和 MMIO 的写入
void pmem_write(uint32_t addr, uint32_t data, uint8_t mask) {
    if (addr >= 0x80000000 && addr < 0x88000000) {
        uint32_t offset = addr - 0x80000000;
        for (int i = 0; i < 4; i++) {
            if ((mask >> i) & 1) guest_mem[offset + i] = (uint8_t)(data >> (i * 8));
        }
    } else if (addr == SERIAL_PORT) {
        if (mask & 0x1) {
            putchar((unsigned char)data);
            fflush(stdout);
        }
    }
}