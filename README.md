# riscv_emufun (mini-rv32ima)

[中文 README](README.zh-CN.md)

Click below for the YouTube video introducing this project:

[![Writing a Really Tiny RISC-V Emulator](https://img.youtube.com/vi/YT5vB3UqU_E/0.jpg)](https://www.youtube.com/watch?v=YT5vB3UqU_E) [![But Will It Run Doom?](https://img.youtube.com/vi/uZMNK17VCMU/0.jpg)](https://www.youtube.com/watch?v=uZMNK17VCMU) 

## What

mini-rv32ima is a single-file-header, [mini-rv32ima.h](https://github.com/cnlohr/riscv_emufun/blob/master/mini-rv32ima/mini-rv32ima.h), in the [STB Style library](https://github.com/nothings/stb) that:
 * Implements a RISC-V **rv32ima/Zifencei†+Zicsr** (and partial su), with CLINT and MMIO.
 * Is about **400 lines** of actual code.
 * Has **no dependencies**, not even libc.
 * Is **easily extensible**.  So you can easily add CSRs, instructions, MMIO, etc!
 * Is pretty **performant**. (~450 coremark on my laptop, about 1/2 the speed of QEMU)
 * Is human-readable and in **basic C** code.
 * Is "**incomplete**" in that it didn't implement the tons of the spec that Linux doesn't (and you shouldn't) use.
 * Is trivially **embeddable** in applications.

It has a [demo wrapper](https://github.com/cnlohr/riscv_emufun/blob/master/mini-rv32ima/mini-rv32ima.c) that:
 * Implements a CLI, SYSCON, UART, DTB and Kernel image loading.
 * Is only around **250 lines** of code, itself.
 * Compiles down to a **~18kB executable** and only relies on libc.

†: Fence behavior is effectively ignored, and RV32A is implemented as a simple single-core model. Tweaks will be needed if you want to emulate a multiprocessor system with this emulator.

Just see the `mini-rv32ima` folder.

It's "fully functional" now in that I can run Linux, apps, etc.  Compile flat binaries and drop them in an image.

## Core, Dependencies and Runtime Targets

This project has two separable layers: the header-only CPU core and the host-side demo wrapper.

### What the header-only CPU core implements

`mini-rv32ima/mini-rv32ima.h` is the reusable CPU core. It keeps a `MiniRV32IMAState` with 32 integer registers, `pc`, a small set of machine-mode CSRs, cycle/timer counters, timer compare registers, and an `extraflags` field for simplified privilege state, `WFI`, and LR/SC reservation state.

The core implements a small RV32 machine intended for NOMMU guests:

 * RV32I integer instructions: jumps, branches, loads/stores, and ALU operations.
 * RV32M multiply/divide instructions. High-half multiply uses host 64-bit arithmetic unless `CUSTOM_MULH` is supplied.
 * RV32A atomics, including `LR.W`, `SC.W`, and common word AMOs. This is a simple single-core style implementation and does not make MMIO atomics work.
 * Zicsr CSR operations for `mscratch`, `mtvec`, `mie`, `mip`, `mepc`, `mstatus`, `mcause`, `mtval`, `cycle`, `mvendorid`, and `misa`, with hooks for other CSRs.
 * Fence opcodes are recognized but effectively ignored.
 * A small privileged subset: `ECALL`, `EBREAK`, `MRET`, `WFI`, trap entry, and machine timer interrupts.

It does **not** implement an MMU, page tables, `satp`, virtual address translation, TLBs, compressed instructions, floating point, vector instructions, or a complete supervisor-mode environment. Memory is direct: guest physical RAM starts at `MINIRV32_RAM_IMAGE_OFFSET`, default `0x80000000`; addresses outside RAM are treated as MMIO only if they match `MINIRV32_MMIO_RANGE`, default `0x10000000` through `0x12000000`.

### What `MiniRV32IMAStep` does

`MiniRV32IMAStep(state, image, vProcAddress, elapsedUs, count)` advances the virtual CPU by up to `count` instructions.

Each call:

 * Adds `elapsedUs` to the internal timer.
 * Sets or clears the timer interrupt pending bit in `mip`.
 * Returns `1` immediately if the CPU is in `WFI` and no interrupt wakes it.
 * Checks whether `mip.MTIP`, `mie.MTIE`, and `mstatus.MIE` allow a machine timer interrupt.
 * Otherwise fetches 32-bit instructions from `image`, decodes them, executes them, writes back registers, and increments `pc`.
 * On traps or interrupts, writes `mcause`, `mtval`, and `mepc`, updates `mstatus`, enters machine mode, and redirects execution to `mtvec`.
 * Updates `cycle` and `pc`, then returns `0` for normal execution.

The function may also return `1` for `WFI`; outer code can sleep briefly and call it again. Other host-visible behaviors, such as poweroff codes, UART output, or custom debug CSRs, are supplied by the wrapper through macros.

### Embedding and platform hooks

The header does not include libc headers by itself and does not call host OS APIs. The embedding program supplies fixed-width integer types, a RAM image, and optional hooks:

 * `MINI_RV32_RAM_SIZE` for guest RAM size.
 * `MINIRV32_HANDLE_MEM_STORE_CONTROL` and `MINIRV32_HANDLE_MEM_LOAD_CONTROL` for MMIO.
 * `MINIRV32_OTHERCSR_WRITE` and `MINIRV32_OTHERCSR_READ` for custom CSRs.
 * `MINIRV32_POSTEXEC` for post-instruction trap, interrupt, or host event handling.

The default memory access macros cast `image + offset` to `uint32_t *` or `uint16_t *`. On strict-alignment MCUs, unusual endian targets, or RTOS ports, define `MINIRV32_CUSTOM_MEMORY_BUS` and provide target-safe load/store helpers.

### Demo wrapper and build dependencies

`mini-rv32ima/mini-rv32ima.c` is a desktop command-line wrapper around the core. It depends on libc and platform APIs for files, memory allocation, terminal input, time, and sleep. On Unix-like hosts it uses headers such as `termios`, `unistd`, `signal`, `sys/time.h`, and `sys/ioctl.h`; on Windows it uses `windows.h` and `conio.h`.

The wrapper loads guest images and optional DTBs, allocates guest RAM, patches the kernel command line, and implements an 8250/16550-like UART at `0x10000000`, CLINT timer registers around `0x11004000` and `0x1100bff8`, and SYSCON at `0x11100000`.

For only compiling the wrapper, a C compiler such as `gcc` or TinyCC is enough. For the Linux demo and bundled guest programs, the top-level `Makefile` also uses `git`, `make`, Buildroot host dependencies, Buildroot-generated RISC-V tools under `buildroot/output/host/bin/`, `wget`, `unzip`, and `device-tree-compiler`. The Dockerfile lists the complete practical package set for this checkout.

### Bare-metal guests, RTOS hosts, and MCU ports

The emulator core can run inside bare-metal firmware or an RTOS task after porting the wrapper responsibilities: provide guest RAM, a timer source for `elapsedUs`, a target-safe memory bus, MMIO/CSR handlers, and a way to supply guest binaries from flash or firmware data instead of `fopen`.

The `baremetal/` directory demonstrates a guest program, not a bare-metal host port of the emulator. It places code at `0x80000000`, starts from `baremetal.S`, prints through custom CSRs `0x136`, `0x137`, and `0x138`, reads the timer at `0x1100bff8`, and powers off by writing `0x5555` to SYSCON at `0x11100000`.

Small MCUs such as RP2040 or ordinary ESP32-class parts should be treated as targets for small RV32 bare-metal guests only. The full Linux path expects tens of MiB of guest RAM, a loaded kernel image and DTB, and the small MMIO surface needed by this RV32 NOMMU Linux setup.

## Why

I'm working on a really really simple C Risc-V emulator. So simple it doesn't even have an MMU (Memory Management Unit). I have a few goals, they include:
 * Furthering RV32-NOMMU work to improve Linux support for RV32-NOMMU.  (Imagine if we could run Linux on the $1 ESP32-C3)
 * Learning more about RV32 and writing emulators.
 * Being further inspired by @pimaker's amazing work on [Running Linux in a Pixel Shader](https://blog.pimaker.at/texts/rvc1/) and having the sneaking suspicion performance could be even better!
 * Hoping to port it to some weird places.
 * Understand the *most simplistic* system you can run Linux on and trying to push that boundary.
 * Continue to include my [education of people about assembly language](https://www.youtube.com/watch?v=Gelf0AyVGy4).

## How

Windows instructions (Just playing with the image)
 * Clone this repo.
 * Install or have TinyCC.  [Powershell Installer](https://github.com/cntools/Install-TCC) or [Regular Windows Installer](https://github.com/cnlohr/tinycc-win64-installer/releases/tag/v0_0.9.27)
 * Run `winrun.ps` in the `windows` folder.

WSL (For full toolchain and image build:
 * You will need to remove all spaces from your path i.e. `export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/mnt/c/Windows/system32:/snap/bin` and continue the instructions.  P.S. What in the world was Windows thinking, putting a space between "Program" and "Files"??!?

Linux instructions (both): 
 * Clone this repo.
 * Install `git build-essential` and/or whatever other requirements are in place for [buildroot](https://buildroot.org/).
 * `make testdlimage`
 * It automatically downloads the image (~1MB) and runs the emulator.
 * Should be up and running in about 2.5s depending on internet speed.

You can do in-depth work on Linux by:
 * `make everything`

Or use the Docker helper:
 * `./build-docker.sh` builds the Docker image only when the Dockerfile or entrypoint changed, then runs `make everything` in `/work`.
 * `./build-docker.sh --cmd` opens an interactive shell in `/work`.
 * `./build-docker.sh --cmd 'make testdlimage'` runs a command in `/work`.
 * `./build-docker.sh --rebuild` forces the image to rebuild before running the default command.

If you want to play with the bare metal guest example, use:
 * `make testbare`

If you just want to play emdoom, and use the prebuilt image:
 * On Windows, run `windows\winrundoom.ps1`
 * On Linux, `cd mini-rv32ima`, and type `make testdoom`

## Questions?
 * Why not rv64?
   * Because then I can't run it as easily in a pixel shader if I ever hope to.
 * Can I add an MMU?
   * Yes.  It actually probably wouldn't be too difficult.
 * Should I add an MMU?
   * No.  It is important to further support for nommu systems to empower minimal Risc-V designs!

Everything else: Contact us on my Discord: https://discord.com/invite/CCeyWyZ

## How do I use this in my own project?

You should not need to modify `mini-rv32ima.h`, but instead, use `mini-rv32ima.c` as a template for what you are trying to do in your own project.

You can override all functionality by defining the following macros. Here are examples of what `mini-rv32ima.c` does with them.  You can see the definition of the functions, or augment their definitions, by altering `mini-rv32ima.c`.

| Macro | Definition / Comment |
| --- | --- |
| `MINIRV32WARN( x... )` | `printf( x );` <br> Warnings emitted from mini-rv32ima.h |
| `MINIRV32_DECORATE` | `static` <br> How to decorate the functions. |
| `MINI_RV32_RAM_SIZE` | `ram_amt` <br> A variable, how big is system RAM? |
| `MINIRV32_IMPLEMENTATION` | If using mini-rv32ima.h, need to define this. |
| `MINIRV32_POSTEXEC( pc, ir, retval )` | `{ if( retval > 0 ) { if( fail_on_all_faults ) { printf( "FAULT\n" ); return 3; } else retval = HandleException( ir, retval ); } }` <br> If you want to execute something every time slice. |
| `MINIRV32_HANDLE_MEM_STORE_CONTROL( addy, val )` | `if( HandleControlStore( addy, val ) ) return val;` <br> Called on non-RAM memory access. |
| `MINIRV32_HANDLE_MEM_LOAD_CONTROL( addy, rval )` | `rval = HandleControlLoad( addy );` <br> Called on non-RAM memory access return a value. |
| `MINIRV32_OTHERCSR_WRITE( csrno, value )` | `HandleOtherCSRWrite( image, csrno, value );` <br> You can use CSRs for control requests. |
| `MINIRV32_OTHERCSR_READ( csrno, value )` |  `value = HandleOtherCSRRead( image, csrno );` <br> You can use CSRs for control requests. |

## Hopeful goals?
 * Further drive down needed features to run Linux.
   * Remove need for RV32A extension on systems with only one CPU.
   * Support for relocatable ELF executables.
   * Add support for an unreal UART.  One that's **much** simpler than the current 8250 driver.
 * Maybe run this in a pixelshader too!
 * Get opensbi working with this.
 * Be able to "embed" rv32 emulators in random projects.
 * Can I use early console to be a full system console?
 * Can I increase the maximum contiguous memory allocatable?

## Special Thanks
 * For @regymm and their [patches to buildroot](https://github.com/regymm/buildroot) and help!
   * callout: Regymm's [quazisoc project](https://github.com/regymm/quasiSoC/).
 * Buildroot (For being so helpful).
 * @vowstar and their team working on [k210-linux-nommu](https://github.com/vowstar/k210-linux-nommu).
 * This [guide](https://jborza.com/emulation/2020/04/09/riscv-environment.html)
 * [rvcodecjs](https://luplab.gitlab.io/rvcodecjs/) I probably went through over 1,000 codes here.
 * @splinedrive from the [KianV RISC-V noMMU SoC](https://github.com/splinedrive/kianRiscV/tree/master/linux_socs/kianv_harris_mcycle_edition?s=09) project.
 
## More details

If you want to build the kernel yourself:
 * `make everything`
 * About 20 minutes.  (Or 4+ hours if you're on [Windows Subsytem for Linux 2](https://github.com/microsoft/WSL/issues/4197))
 * And you should be dropped into a Linux busybox shell with some little tools that were compiled here.

## Emdoom notes
 * Emdoom building is in the `experiments/emdoom` folder
 * You *MUST* build your kernel with `MAX_ORDER` set to >12 in `buildroot/output/build/linux-5.19/include/linux/mmzone.h` if you are building your own image.
 * You CAN use the pre-existing image that is described above.
 * On Windows, it will be very slow.  Not sure why.

## Links
 * "Hackaday Supercon 2022: Charles Lohr - Assembly in 2022: Yes! We Still Use it and Here's Why" : https://www.youtube.com/watch?v=Gelf0AyVGy4
 
## Attic


## General notes:
 * https://github.com/cnlohr/riscv_emufun/commit/2f09cdeb378dc0215c07eb63f5a6fb43dbbf1871#diff-b48ccd795ae9aced07d022bf010bf9376232c4d78210c3113d90a8d349c59b3dL440


(These things don't currently work)

### Building Tests

(This does not work, now)
```
cd riscv-tests
export CROSS_COMPILE=riscv64-linux-gnu-
export PLATFORM_RISCV_XLEN=32
CC=riscv64-linux-gnu-gcc ./configure
make XLEN=32 RISCV_PREFIX=riscv64-unknown-elf- RISCV_GCC_OPTS="-g -O1 -march=rv32imaf -mabi=ilp32f -I/usr/include"
```

### Building OpenSBI

(This does not currently work!)
```
cd opensbi
export CROSS_COMPILE=riscv64-unknown-elf-
export PLATFORM_RISCV_XLEN=32
make
```

### Extra links
 * Clear outline of CSRs: https://five-embeddev.com/riscv-isa-manual/latest/priv-csrs.html
 * Fonts used in videos: https://audiolink.dev/

### Using custom build

Where yminpatch is the patch from the mailing list.
```
rm -rf buildroot
git clone git://git.buildroot.net/buildroot
cd buildroot
git am < ../yminpatch.txt
make qemu_riscv32_nommu_virt_defconfig
make
# Or use our configs.
```

Note: For emdoom you will need to modify include/linux/mmzone.h and change MAX_ORDER to 13.

### Buildroot Notes

Add this:
https://github.com/cnlohr/buildroot/pull/1/commits/bc890f74354e7e2f2b1cf7715f6ef334ff6ed1b2

Use this:
https://github.com/cnlohr/buildroot/commit/e97714621bfae535d947817e98956b112eb80a75
