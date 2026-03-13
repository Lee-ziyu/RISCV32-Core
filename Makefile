# --- 基础配置 ---
TOPNAME ?= npc
INC_PATH ?= $(abspath ./vsrc)

# --- 工具链配置 ---
VERILATOR = verilator
# -Wall: 开启所有警告
# --trace: 开启波形追踪支持 (关键！为了后续看波形)
VERILATOR_CFLAGS += -MMD --build -cc \
                    -O3 --x-assign fast --x-initial fast --noassert -Wall --trace \
                    $(addprefix -I, $(INC_PATH))


# --- 目录配置 ---
BUILD_DIR = ./build
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(BUILD_DIR)/$(TOPNAME)

# --- 自动搜集源码 ---
# 搜集 vsrc 下所有的 Verilog 文件
VSRCS = $(shell find $(abspath ./vsrc) -name "*.v")
# 搜集 csrc 下所有的 C++ 仿真代码
CSRCS = $(shell find $(abspath ./csrc) -name "*.c" -or -name "*.cc" -or -name "*.cpp")
INCFLAGS = $(addprefix -I, $(INC_PATH))
# 将 C++ 编译参数传给 Verilator
# TOP_NAME 定义了生成的 C++ 类名，方便 main.cpp 实例化
CXXFLAGS += $(INCFLAGS) -DTOP_NAME="\"V$(TOPNAME)\""

# --- 核心规则 (Rules) ---

default: $(BIN)

# 创建构建目录
$(shell mkdir -p $(BUILD_DIR))

# 编译生成可执行文件
$(BIN): $(VSRCS) $(CSRCS)
	@rm -rf $(OBJ_DIR)
	$(VERILATOR) $(VERILATOR_CFLAGS) \
		--top-module $(TOPNAME) $^ \
		$(addprefix -CFLAGS , $(CXXFLAGS)) \
		--Mdir $(OBJ_DIR) --exe -o $(abspath $(BIN))

all: default

# 仿真运行
# 在 npc/Makefile 的底部修改 run 规则：

run: $(BIN)
	@echo "--- 启动 NPC 仿真器 ---"
	@$(BIN) $(IMG)   # <--- 关键：把 $(IMG) 传给可执行文件

# 清理
clean:
	rm -rf $(BUILD_DIR)

# 静态检查
lint:
	$(VERILATOR) --lint-only -Wall $(VSRCS)

.PHONY: default all clean run lint