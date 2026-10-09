# fw/Makefile — Muse MCU firmware builds (bare-metal + FreeRTOS).
#
# Usage: make -C fw APP=<name>
# Builds fw/build/<name>.elf and fw/build/<name>.hex.
# The .hex is 32-bit little-endian words, one hex word per line, padded to
# 16384 words, suitable for Verilog $readmemh into the boot ROM model.
#
# Bare-metal apps: hello, uart_rx_test, spi_test, timer_gpio_test
# FreeRTOS apps:   pingpong, min_yield, regtest2 (bring-up),
#                  rtos_regtest, rtos_queue, rtos_sema, rtos_notify,
#                  rtos_timer, rtos_isr, rtos_blocktim, preempt_test, app_demo

TOOLCHAIN ?= $(HOME)/workspace/building-ai-computer/toolchains/riscv/xpack-riscv-none-elf-gcc-15.2.0-1/bin
CC      := $(TOOLCHAIN)/riscv-none-elf-gcc
OBJCOPY := $(TOOLCHAIN)/riscv-none-elf-objcopy
OBJSIZE := $(TOOLCHAIN)/riscv-none-elf-size

APP ?= hello
BUILD := build
REPO  := $(abspath $(CURDIR)/..)

# Note: -march=rv32i_zicsr (not bare rv32i): the MCU implements Zicsr and
# crt0/drivers/port use CSR instructions.
CFLAGS := -march=rv32i_zicsr -mabi=ilp32 -mcmodel=medany -O2 -ffreestanding -nostdlib \
          -msmall-data-limit=0 -Wall -Wextra \
          -Iinclude -I$(REPO)/fw/include \
          -I$(REPO)/fw/freertos -I$(REPO)/fw/port -I$(REPO)/fw/sha256 \
          -I$(REPO)/third_party/freertos_kernel/include \
          -I$(REPO)/third_party/freertos_kernel/portable/GCC/RISC-V \
          -I$(REPO)/third_party/freertos_demos \
          -I$(REPO)/third_party/freertos_template
ASFLAGS := -march=rv32i_zicsr -mabi=ilp32 -I$(REPO)/fw/port
# -lgcc: compiler support routines (__udivsi3 etc.) from the toolchain's own
# libgcc; not application code. NOTE: -lgcc must come AFTER the objects.
LDFLAGS := -T startup/linker.ld -nostdlib -Wl,--gc-sections

# --- app classification ---
BAREMETAL_APPS := hello uart_rx_test spi_test timer_gpio_test
FREERTOS_APPS  := pingpong min_yield regtest2 \
                  rtos_regtest rtos_queue rtos_sema rtos_notify rtos_timer \
                  rtos_isr rtos_blocktim preempt_test app_demo

# --- common sources ---
CSRCS := startup/crt0.S drivers/string.c \
         drivers/uart.c drivers/spi.c drivers/gpio.c drivers/timer.c \
         app/$(APP).c

# --- FreeRTOS sources (only for FreeRTOS apps) ---
KDIR := $(REPO)/third_party/freertos_kernel
KSRC := $(KDIR)/tasks.c $(KDIR)/queue.c $(KDIR)/list.c $(KDIR)/timers.c \
        $(KDIR)/event_groups.c $(KDIR)/stream_buffer.c \
        $(KDIR)/portable/MemMang/heap_4.c \
        $(KDIR)/portable/GCC/RISC-V/port.c \
        $(KDIR)/portable/GCC/RISC-V/portASM.S
PSRC := port/port_glue.c port/port_glue.S

# --- per-app demo/test sources ---
DSRC :=
ifeq ($(APP),rtos_queue)
DSRC := $(REPO)/third_party/freertos_demos/BlockQ.c \
        $(REPO)/third_party/freertos_demos/GenQTest.c \
        $(REPO)/third_party/freertos_demos/QPeek.c \
        $(REPO)/third_party/freertos_demos/PollQ.c
endif
ifeq ($(APP),rtos_sema)
DSRC := $(REPO)/third_party/freertos_demos/semtest.c \
        $(REPO)/third_party/freertos_demos/countsem.c \
        $(REPO)/third_party/freertos_demos/recmutex.c
endif
ifeq ($(APP),rtos_notify)
DSRC := $(REPO)/third_party/freertos_demos/TaskNotify.c \
        $(REPO)/third_party/freertos_demos/TaskNotifyArray.c
endif
ifeq ($(APP),rtos_timer)
DSRC := $(REPO)/third_party/freertos_demos/TimerDemo.c
endif
ifeq ($(APP),rtos_isr)
DSRC := $(REPO)/third_party/freertos_demos/IntQueue.c \
        $(REPO)/third_party/freertos_demos/IntSemTest.c \
        $(REPO)/third_party/freertos_template/IntQueueTimer.c
endif
ifeq ($(APP),rtos_blocktim)
DSRC := $(REPO)/third_party/freertos_demos/blocktim.c
endif
ifeq ($(APP),app_demo)
DSRC := sha256/sha256.c sha256/sha256_fw.c sha256/sha_selftest.c
endif

ifneq ($(filter $(APP),$(FREERTOS_APPS)),)
SRCS := $(CSRCS) $(KSRC) $(PSRC) $(DSRC)
else
SRCS := $(CSRCS)
endif

.PHONY: all clean
all: $(BUILD)/$(APP).elf $(BUILD)/$(APP).hex

$(BUILD)/$(APP).elf: $(SRCS) startup/linker.ld | $(BUILD)/obj
	i=0; \
	for s in $(SRCS); do \
	  case "$$s" in *.S) flags="$(ASFLAGS)";; *) flags="$(CFLAGS)";; esac; \
	  o="$(BUILD)/obj/fw$$i.o"; i=$$((i+1)); \
	  echo "CC $$s"; \
	  $(CC) $$flags -c "$$s" -o "$$o" || exit 1; \
	done
	$(CC) $(CFLAGS) $(LDFLAGS) $(BUILD)/obj/fw*.o -lgcc -o $@
	$(OBJSIZE) $@

$(BUILD)/$(APP).hex: $(BUILD)/$(APP).elf
	$(OBJCOPY) -O binary $< $(BUILD)/$(APP).bin
	python3 $(REPO)/tools/elf_to_hex.py $(BUILD)/$(APP).bin $@

$(BUILD)/obj:
	mkdir -p $(BUILD)/obj

clean:
	rm -rf $(BUILD)
