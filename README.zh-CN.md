# riscv_emufun (mini-rv32ima)

[English README](README.md)

mini-rv32ima 是一个很小的 RISC-V RV32IMA 模拟器。核心实现放在 `mini-rv32ima/mini-rv32ima.h`，采用类似 STB 的单头文件风格，便于嵌入到其他 C/C++ 项目中。仓库还包含一个命令行包装器 `mini-rv32ima/mini-rv32ima.c`，可以加载内核镜像、裸机 flat binary，并模拟基本的 UART、SYSCON、CLINT、DTB 等设备。

## 项目能做什么

 * 模拟 RV32IMA/Zicsr/Zifencei 的主要行为，并带有部分 supervisor 相关支持。
 * 运行 RV32 NOMMU Linux 演示镜像。
 * 构建和运行裸机 RISC-V 程序。
 * 作为一个很小的 C 模拟器核心嵌入到其他程序或固件中。

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

裸机程序的入口在 `baremetal/` 目录。建议从现有示例开始改：

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

当前裸机示例使用几个自定义 CSR 与宿主侧交互：

 * `0x138`：按 C 字符串指针打印字符串。
 * `0x137`：打印指针或数值。
 * `0x136`：打印数字。

示例最后向链接脚本中的 `SYSCON` MMIO 地址写入 `0x5555` 来关机。如果你想增加自己的外设，优先修改模拟器侧的 CSR/MMIO 处理逻辑，也就是 `mini-rv32ima/mini-rv32ima.c`，让 guest 程序保持简单。

## 能否移植到 RP2040 或 ESP32

可以移植模拟器核心，但不能现实地移植完整 Linux 演示环境。

RP2040 只有 264 KiB SRAM，无法容纳默认 Linux 镜像或 64 MiB 级别的 guest RAM。比较合理的方向是运行很小的 RV32 裸机程序：缩小 `MINI_RV32_RAM_SIZE`，静态分配 guest RAM，把 guest binary 放在固件或 flash 中，并用 Pico SDK 替换文件、终端、计时器等宿主接口。

ESP32 的可行性取决于具体芯片和模组。带 PSRAM 的 ESP32/ESP32-S3 更适合尝试小型裸机 guest，但性能会比较有限。ESP32-C3/C6 本身就是 RISC-V MCU，如果目标只是跑自己的固件，通常直接写原生 RISC-V 固件更简单；只有在需要沙箱、兼容层或教学演示时，才值得在其上再跑一个 RV32 模拟器。

移植到这类 MCU 时通常需要做这些事：

 * 用固件内嵌数据或 flash 读取替代文件加载。
 * 静态分配 guest RAM，并把大小压到目标 MCU 能承受的范围。
 * 用 Pico SDK 或 ESP-IDF 替换 `mini-rv32ima.c` 中的 POSIX 文件、时间和终端接口。
 * 只实现裸机 guest 真正需要的 CSR/MMIO。
 * 不走 buildroot/Linux 路径，除非目标板有数十 MiB 可用 RAM 和足够存储。

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
