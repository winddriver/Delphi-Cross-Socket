# OpenSSL 加载生命周期回归

## 接口与兼容边界

- `TSSLTools.LoadSSL: Boolean` 成功时取得一份引用；预期的库加载、符号绑定或初始化失败返回 `False`，不取得引用。`LoadSSL(out AError: string)` 同时返回本次失败的错误文本，不依赖共享的最后错误状态。
- 非预期异常在回滚后继续抛出。直接调用者必须检查返回值，只对成功的加载调用一次 `UnloadSSL`。忽略返回值的旧调用可能仍能编译，但失败路径的行为已经改变。需要全量重编译，不能混用旧 DCU/BPL。
- socket 构造仍在加载失败时抛 `ESsl`，携带错误文本；`FSslLoaded` 区分 SSL 配置开关和实际取得的引用。
- 加载、卸载、计数及库配置读写使用 `Utils.SyncObjs.ILock` / `TLock`。锁接口自动释放，引用数仅使用锁内 `Inc/Dec`。没有给 `SSL_read/SSL_write` 增加此锁。
- 所有动态函数入口（含兼容回退入口）、句柄和版本在失败或最后卸载时清理；失败时恢复加载前的库名。配置在已有引用时可修改，仅影响下一次完整加载。
- 包装层不主动调用 `OPENSSL_cleanup`，不设置 `NO_ATEXIT`。保留其公开声明。静态链接不清空外部函数地址，不执行动态库卸载。
- 释放最后引用前，调用者须释放 SSL 对象并结束相关线程的使用。外部存活线程的 OpenSSL 线程局部资源仍须遵守 OpenSSL 清理约定。没有改为进程驻留策略，也不保证 OpenSSL 内部已记录的初始化失败一定能在同一模块中恢复。

## 构建与运行

脚本沿用相邻 TLS/WebSocket 测试的 Delphi/FPC 工具链和搜索路径。使用本机已有 Delphi 13.1、FPC 3.3.1、Lazarus、cncrypto 和 Ubuntu SDK；其他机器调整脚本中的路径。不修改第三方库、全局配置或安装依赖，所有产物写入忽略的 `bin/`、`lib/`。

在本目录运行：

```powershell
python -B run_tests.py
python -B run_tests.py --ssl D:\path\libssl-1_1-x64.dll --crypto D:\path\libcrypto-1_1-x64.dll --label openssl111 delphi-win64 fpc-win64
python -B run_tests.py --build-only delphi-linux64 fpc-linux64
python -B check_platforms.py
```

默认执行 Delphi Win64/Win32 和 FPC Win64。Win64 使用仓库内 OpenSSL 3；Win32 使用已有 `D:\Design\Delphi\VclFmxRtl\zLib\Net\OpenSSL.Libs\OpenSSL3\Windows\x86` 中的 DLL。也可通过 `--ssl/--crypto` 提供匹配位数的其他库。FPC Linux 测试共享库的链接器输入显式指向已有交叉库中的加载器文件，避免 Windows 宿主无法解析 Linux 的 `/lib64` 绝对路径。

Linux 交叉编译产物在已有 Ubuntu 22.04 / WSL2 环境运行：

```sh
python3 -B run_linux.py bin/delphi-linux64/OpenSslLoadTests
python3 -B run_linux.py bin/fpc-linux64/OpenSslLoadTests
```

`CROSS_OPENSSL_SELFTEST` 提供仅测试构建启用的初始化前钩子；生产构建没有此入口。事件同步确定并发时序，等待超时算失败。不完整的测试库故意缺少符号；其余使用真实 OpenSSL 库和上下文。初始化返回零和异常通过函数指针/钩子注入，不能据此声称任意 OpenSSL 内部失败都能恢复。

13 个场景覆盖：缺 crypto、crypto 成功但 ssl 失败、缺失符号、失败后进程退出、自动库名回滚、多引用与配置延后生效、两种初始化函数返回零、非预期异常、上下文创建失败、16 线程并发首次加载、16 线程各 64 次交错加载/创建上下文/卸载、失败构造延迟析构与另一个成功实例交错。

脚本还核对动态声明/绑定与清理项集合，目前为 183 项，避免以后新增绑定却遗漏清理。

## 2026-10-19 验证

| 编译器与平台 | 库 | 专项结果 |
| --- | --- | --- |
| Delphi 13.1 Win64 | OpenSSL 3.1.2 | 13/13 |
| Delphi 13.1 Win32 | OpenSSL 3.x | 13/13 |
| FPC 3.3.1 Win64 | OpenSSL 3.1.2 | 13/13 |
| Delphi 13.1 Win64 | OpenSSL 1.1.1o | 13/13 |
| FPC 3.3.1 Win64 | OpenSSL 1.1.1o | 13/13 |
| Delphi 13.1 Linux64 | Ubuntu 系统 OpenSSL 3 | 13/13 |
| FPC 3.3.1 Linux64 | Ubuntu 系统 OpenSSL 3 | 13/13 |

- 修改前基线 `d7c051b` 的 Delphi Win64 对照程序在 `failure-exit` 场景失败，报告仍保留 `OPENSSL_cleanup` 地址。新版同一场景通过，正常结束进程。
- 既有 `TlsCipherSuitesTests`：Delphi/FPC Win64 × OpenSSL 3.1.2/1.1.1o，四组配置测试和各 38 项真实 TLS 握手均通过，共 **152/152** 握手。
- 既有 `WebSocketFrameTests`：Delphi/FPC Win64 的组件测试、各 11,056 组合法帧组合及各 11 个真实回环场景通过。
- `WebSocketServer.dproj` Release/Win64 正式工程构建通过。
- Delphi Android32/64、iOS ARM64、macOS x64/ARM64，以及 Delphi/FPC Linux64 静态链接条件分支的生产单元编译通过。未在移动设备或 macOS 运行，未链接并运行静态 OpenSSL 可执行程序。
- 编译与运行日志见 `bin/<target>/`，场景 JSON 在 `bin/<target>/<label>/results.json`。真实握手日志仍由相邻 TLS 测试保存。项目及依赖仍有既有警告，不宣称零警告；未进行吞吐基准和长期压力测试。
