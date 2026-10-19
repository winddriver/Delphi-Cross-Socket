# Socket close-on-exec 回归

生产修改仅涉及 `Net/Net.SocketAPI.pas`。Linux / Android 的 x86、x64、ARM、ARM64 路径优先使用 `SOCK_CLOEXEC` 和动态解析的 `accept4`；其他架构及 POSIX 平台保留 `socket/accept + fcntl`。公开接口不变。

回退只能保证设置完成后的 close-on-exec，不能消除与其他线程并发 `fork + exec` 的窗口。`fcntl` 设置失败会关闭刚创建的描述符并返回失败；关闭过程不覆盖原错误码。Windows 行为保持不变。

## 构建

沿用相邻测试工程的 Delphi/FPC 编译方式。`build.py` 使用已有 Delphi 13.1、FPC 3.3.1 交叉编译器及 `ubuntu22.04.sdk`；其他机器调整脚本中的工具路径。仅写忽略的 `bin/` 和 `lib/`，不安装工具，不修改第三方源码或全局配置。

在本目录运行：

```powershell
python build.py
python build.py delphi-android delphi-android64 delphi-osx64 delphi-osxarm64 delphi-iosDevice64
```

默认生成可执行的 Delphi/FPC Linux64 测试程序；其他目标只编译完整的 `Net.SocketAPI.pas` 单元，不能据此宣称已完成这些系统的运行测试。

## Linux 运行

需要 x86_64 glibc Linux、Python 3 和 GCC。可在已有 WSL Ubuntu 中执行，不需要管理员权限：

```sh
python3 run_linux.py bin/fpc-linux64/SocketCloseOnExecTests
python3 run_linux.py bin/delphi-linux64/SocketCloseOnExecTests
```

每个目标包含 16 个独立进程场景：

- TCP/UDP 创建、描述符 0、保留调用者标志；接入时传地址缓冲区或 `nil`，真实回环收发。
- 原 socket 在 `fork/exec` 后不再存在。按 `/proc/self/fd` 中的 socket 身份核对，允许新程序运行库将已关闭的编号用于其他资源。
- `accept4` 符号缺失、`dlopen` 失败，以及实际调用返回 `ENOSYS`。
- `ENOSYS` 在同一线程内只尝试一次，两个新线程各自重新尝试，互不污染缓存。
- `EINTR/EAGAIN/EINVAL/EMFILE/EPERM` 原样返回，FPC 的 libc errno 同步到 RTL errno。
- 旧内核不接受 socket 的 CLOEXEC 标志时回退；不移除调用者明确指定的 CLOEXEC；非 EINVAL 错误不回退。
- `F_GETFD/F_SETFD` 失败时关闭新 socket、保留 errno；反复失败不增加打开的描述符数；接入失败同样清理。
- 禁止 `F_GETFD/F_SETFD` 的进程仍可走原子创建与接入路径，验证成功路径没有额外 fcntl。

`accept4_inject.c` 仅在测试子进程中通过 `LD_PRELOAD` 模拟 libc 符号/错误。`run_linux.py` 使用仅对子进程生效的 seccomp 规则模拟旧内核和 fcntl 失败；所有 socket、文件描述符、线程及 fork/exec 均由真实 Linux 提供。不会修改宿主的全局安全策略。测试只监听 127.0.0.1 临时端口。

## 2026-10-19 验证

- Ubuntu 22.04 / WSL2，Linux 6.18.54.1：Delphi 13.1 Linux64、FPC 3.3.1 Linux64 分别 **16/16 通过**。构建日志在 `bin/<target>/build.log`，运行记录在 `bin/linux/<target>-results.json`。
- 两个 Linux 可执行文件均无必须解析的 `accept4` 外部符号。
- 原版 `d5f63d1` 的 `Net.SocketAPI.pas` 独立构建后在同一普通场景失败：缺少 FD_CLOEXEC。对照源码与产物仅放在忽略目录中，没有切换或改写当前源码。
- Delphi Android32/64、macOS x64/ARM64、iOS ARM64 单元编译通过；没有设备运行验证。
- 原有 WebSocket 回归：Delphi Win64/Win32、FPC Win64 的组件测试、每目标 11,056 组合法帧组合及 11 个真实回环场景全部通过。
- 正式 `WebSocketServer.dproj` Release/Win64 构建通过。尝试的 `HttpServer.dproj` 在未改动的 `HttpServer.dpr:71-72` 处报告 `GetHashString` 重载不匹配，没有修改该独立示例问题。两份正式构建日志位于 `bin/formal-win64/`。
- 仍有项目原有平台/字符串转换警告；不宣称零警告。旧系统故障路径通过注入验证，不等于在旧版内核或旧 Android 实机上运行过。未开展连接吞吐基准或长期压力测试。
