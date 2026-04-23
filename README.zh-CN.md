# riscv_emufun (mini-rv32ima)

[English README](README.md)

mini-rv32ima 是一个很小的 RISC-V RV32IMA 模拟器。核心实现放在 `mini-rv32ima/mini-rv32ima.h`，采用类似 STB 的单头文件风格，便于嵌入到其他 C/C++ 项目中。仓库还包含一个命令行包装器 `mini-rv32ima/mini-rv32ima.c`，可以加载内核镜像、裸机 flat binary，并模拟基本的 UART、SYSCON、CLINT、DTB 等设备。

## 项目能做什么

 * 模拟 RV32IMA/Zicsr/Zifencei 的主要行为，并带有部分 supervisor 相关支持。
 * 运行 RV32 NOMMU Linux 演示镜像。
 * 构建和运行裸机 RISC-V 程序。
 * 作为一个很小的 C 模拟器核心嵌入到其他程序或固件中。

## 核心、依赖和运行目标

这个项目可以分成两层看：`mini-rv32ima.h` 里的 header-only CPU core，以及 `mini-rv32ima.c` 里的桌面命令行包装器。

### header-only CPU core 实现了什么

`mini-rv32ima/mini-rv32ima.h` 是真正可复用的 CPU core。它维护一个 `MiniRV32IMAState`，里面包括 32 个通用寄存器、`pc`、一小组 machine-mode CSR、cycle/timer、timer compare，以及用于简化 privilege、`WFI`、LR/SC reservation 的 `extraflags`。

这个 core 实现的是一个面向 NOMMU guest 的小型 RV32 机器：

 * RV32I 基础整数指令：跳转、分支、load/store、整数 ALU。
 * RV32M 乘除法；`MULH`、`MULHSU`、`MULHU` 默认使用宿主 64 位整数，也可以用 `CUSTOM_MULH` 覆盖。
 * RV32A 原子指令，包括 `LR.W`、`SC.W` 和常见 word AMO；这是单核风格的简化实现，不支持对 MMIO 做 AMO。
 * Zicsr CSR 指令，内建处理 `mscratch`、`mtvec`、`mie`、`mip`、`mepc`、`mstatus`、`mcause`、`mtval`、`cycle`、`mvendorid`、`misa`，其他 CSR 可交给 hook。
 * fence opcode 会被识别，但基本当作 no-op。
 * 一小部分 privileged 行为：`ECALL`、`EBREAK`、`MRET`、`WFI`、trap entry、machine timer interrupt。

它**不支持 MMU**，也没有页表、`satp`、虚拟地址转换、TLB、压缩指令 C、浮点、向量或完整 supervisor mode。访存是直接物理映射：guest RAM 默认从 `MINIRV32_RAM_IMAGE_OFFSET = 0x80000000` 开始；RAM 外地址只有落在 `MINIRV32_MMIO_RANGE`，默认 `0x10000000..0x12000000`，才会作为 MMIO 交给外部处理。

### `MiniRV32IMAStep` 会做什么

`MiniRV32IMAStep(state, image, vProcAddress, elapsedUs, count)` 会把虚拟 CPU 最多向前推进 `count` 条指令。

每次调用大致流程是：

 * 用 `elapsedUs` 推进内部 timer。
 * 根据 `timer` 和 `timermatch` 设置或清除 `mip` 里的 timer interrupt pending bit。
 * 如果 CPU 正在 `WFI` 且没有中断唤醒，直接返回 `1`，外层可以短暂 sleep 后再调用。
 * 如果 `mip.MTIP`、`mie.MTIE`、`mstatus.MIE` 都满足，则进入 machine timer interrupt。
 * 否则从 `image` 中取 32-bit 指令，译码、执行、写回寄存器并推进 `pc`。
 * 如果发生 trap 或 interrupt，写入 `mcause`、`mtval`、`mepc`，更新 `mstatus`，进入 machine mode，并跳转到 `mtvec`。
 * 最后更新 `cycle` 和 `pc`，正常返回 `0`。

所以它支持基本中断处理，但范围很小：主要是 machine timer interrupt 和 `WFI` 唤醒；没有 PLIC，也没有完整外部中断控制器。UART 中断或其他外部中断如果要支持，需要在外层包装器或宏 hook 中扩展。

### 嵌入和平台 hook

`mini-rv32ima.h` 本身不调用宿主 OS API，也不主动包含 libc 头文件。嵌入它的程序需要提供固定宽度整数类型、guest RAM，以及几个可选 hook：

 * `MINI_RV32_RAM_SIZE`：guest RAM 大小。
 * `MINIRV32_HANDLE_MEM_STORE_CONTROL` 和 `MINIRV32_HANDLE_MEM_LOAD_CONTROL`：处理 MMIO 读写。
 * `MINIRV32_OTHERCSR_WRITE` 和 `MINIRV32_OTHERCSR_READ`：处理自定义 CSR。
 * `MINIRV32_POSTEXEC`：每段执行后处理 trap、中断或宿主事件。

默认内存访问宏会把 `image + offset` 强转成 `uint32_t *` 或 `uint16_t *`。如果移植到严格对齐 MCU、特殊 endian 平台或 RTOS，建议定义 `MINIRV32_CUSTOM_MEMORY_BUS`，改成目标平台安全的 load/store。

### 命令行包装器和构建依赖

`mini-rv32ima/mini-rv32ima.c` 是桌面宿主程序，不是纯裸机代码。它负责加载镜像、分配 RAM、接键盘、模拟 UART/CLINT/SYSCON、加载默认 DTB 和 patch kernel command line。

它依赖 libc、文件接口、动态内存、终端输入、时间和 sleep。Unix-like 平台会用到 `termios`、`unistd`、`signal`、`sys/time.h`、`sys/ioctl.h`；Windows 平台会用到 `windows.h` 和 `conio.h`。

如果只是编译桌面模拟器，一个 C 编译器，例如 `gcc` 或 TinyCC，就基本够了。若要构建 Linux 演示、rootfs/kernel 或 guest 程序，还需要 `git`、`make`、Buildroot 宿主依赖、`buildroot/output/host/bin/` 下的 RISC-V 工具链、`wget`、`unzip` 和 `device-tree-compiler`。完整可工作的宿主依赖集合见 `docker/Dockerfile`。

### 裸机 guest、RTOS 宿主和 MCU 移植

结论是：CPU core 可以放进裸机固件或 RTOS task，现成 `mini-rv32ima.c` 不能直接裸机运行，需要移植包装层。

移植时至少要提供 guest RAM、传给 `MiniRV32IMAStep(...)` 的计时来源、目标平台安全的内存 bus、guest 需要的 MMIO/CSR handler，以及 guest binary 的来源，例如固件内嵌数组或从 flash 读取，而不是 `fopen`。

项目里的 `baremetal/` 目录展示的是 guest 侧裸机程序，不是把模拟器本身跑在裸机宿主上。它把代码放在 `0x80000000`，通过 `baremetal.S` 启动，通过自定义 CSR `0x136`、`0x137`、`0x138` 打印信息，读取 `0x1100bff8` 的 timer，最后向 `0x11100000` 的 SYSCON 写入 `0x5555` 关机。

完整 Linux 路径对裸机或 RTOS 宿主要求高得多：当前包装器默认分配 64 MiB guest RAM，并需要加载 kernel image 和 DTB。RP2040、普通 ESP32 这类小 MCU 更适合运行很小的 RV32 裸机 guest，而不是运行 Linux 演示。

## 快速运行

如果只想下载预构建 Linux 镜像并运行：

```sh
make testdlimage
```

如果要完整构建工具链、rootfs、内核和示例：

```sh
make everything
```

如果要构建并运行裸机示例：

```sh
make testbare
```

## Docker 构建环境

推荐使用项目根目录下的 Docker helper，避免在宿主机安装 buildroot 所需的一整套依赖。

```sh
./build-docker.sh
```

默认行为是在容器的 `/work` 路径下运行：

```sh
make everything
```

脚本只在 Dockerfile 或容器 entrypoint 发生变化时重建镜像；普通源码改动通过 volume 挂载进入容器，不会触发镜像重建。

常用命令：

```sh
./build-docker.sh --cmd
./build-docker.sh --cmd 'make testdlimage'
./build-docker.sh --cmd 'make testbare'
./build-docker.sh --rebuild
```

其中 `--cmd` 后面没有内容时会直接进入容器 shell；后面有内容时会在 `/work` 中执行该命令。

## 在项目中开发 RISC-V 裸机程序

如果你只是想编写运行在该模拟器里的 RV32 裸机 guest，从 `baremetal/` 目录开始：

 * `baremetal/baremetal.c`：C 代码入口，演示如何通过自定义 CSR 打印信息。
 * `baremetal/baremetal.S`：启动代码，设置栈并跳转到 `main`。
 * `baremetal/flatfile.lds`：链接脚本，定义 flat binary 的内存布局。
 * `baremetal/Makefile`：交叉编译器前缀、编译参数、链接参数和输出规则。

默认的 `baremetal/Makefile` 使用 buildroot 生成的交叉编译器，所以干净 checkout 第一次构建时，先运行一次：

```sh
./build-docker.sh
```

或者只构建工具链：

```sh
./build-docker.sh --cmd 'make toolchain'
```

构建裸机程序：

```sh
./build-docker.sh --cmd 'make -C baremetal'
```

如果你已经在宿主机安装了合适的裸机工具链，也可以覆盖 `PREFIX`：

```sh
make -C baremetal PREFIX=riscv64-unknown-elf-
```

运行裸机程序：

```sh
./build-docker.sh --cmd 'make testbare'
```

或者在已经构建好模拟器和工具链后直接运行：

```sh
mini-rv32ima/mini-rv32ima -f baremetal/baremetal.bin
```

如果要增加自己的外设，优先扩展模拟器侧的 CSR/MMIO 处理逻辑，也就是 `mini-rv32ima/mini-rv32ima.c`，让 guest 程序保持简单。

## 在自己的项目中嵌入

通常不需要直接修改 `mini-rv32ima.h`。更推荐把 `mini-rv32ima/mini-rv32ima.c` 当作模板，按你的宿主平台实现内存、CSR、MMIO、加载器和退出逻辑。

常见扩展点包括：

 * `MINI_RV32_RAM_SIZE`：guest RAM 大小。
 * `MINIRV32_HANDLE_MEM_STORE_CONTROL`：处理非 RAM 写访问。
 * `MINIRV32_HANDLE_MEM_LOAD_CONTROL`：处理非 RAM 读访问。
 * `MINIRV32_OTHERCSR_WRITE`：处理自定义 CSR 写。
 * `MINIRV32_OTHERCSR_READ`：处理自定义 CSR 读。
 * `MINIRV32_POSTEXEC`：每个执行片段后处理异常或外部事件。

更多背景、视频链接和历史说明请参见英文版 [README.md](README.md)。
