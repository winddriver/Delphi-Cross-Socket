# EasyThread 生命周期回归

对应全项目计划 A09/F19。原六项覆盖最后一个外部 `IEasyThread` 引用提前释放后正常结束、异常结束、Terminate、自身调用 WaitFor；以及外部重复 WaitFor、无参数匿名任务由其他线程析构。另增两个构造重载在 Start 前失败的资源收尾，共八项。

用事件固定任务开始、允许结束和析构时序，不通过长 Sleep 撞竞态。包装对象析构和线程回调捕获的接口资源都必须释放一次。每项独立进程，内部事件等待与外部 runner 都有超时，旧版自等不会挂住整套测试。

Pascal 使用 UTF-8 BOM/CRLF。Windows 构建沿用既有 Delphi/FPC，Linux 由 `build_linux.py` 使用已有 SDK 交叉构建，再在 Ubuntu WSL 执行。不安装依赖、不修改工具链配置。

## 构建与运行

本目录执行：

```powershell
New-Item -ItemType Directory -Force -Path bin/delphi-win64,lib/delphi-win64 | Out-Null
& 'D:\Design\Delphi\D13.1\bin\dcc64.exe' -Q -B -DCROSS_EASY_THREAD_TESTS '-NSSystem;System.Win;Winapi' `
  '-U..\..\..;D:\Design\Delphi\D13.1\lib\win64\release' '-I..\..\..\..' `
  '-Ebin\delphi-win64' '-N0lib\delphi-win64' EasyThreadTests.dpr
python run_tests.py bin/delphi-win64/EasyThreadTests.exe --report bin/delphi-result.json
& 'D:\Design\FreePascal\lazarus\lazbuild.exe' --build-all --skip-dependencies EasyThreadTests.lpi
python run_tests.py bin/x86_64-win64/EasyThreadTests.exe --report bin/fpc-result.json
python build_linux.py delphi-linux64 fpc-linux64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyThreadTests -- python3 -B run_tests.py bin/delphi-linux64/EasyThreadTests --report bin/delphi-linux-result.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyThreadTests -- python3 -B run_tests.py bin/fpc-linux64/EasyThreadTests --report bin/fpc-linux-result.json
```

`CROSS_EASY_THREAD_TESTS` 只增加启动前故障注入入口，生产不定义它。Delphi 生产分支去掉该 `-D`，创建并使用 `bin/production-delphi-win64`、`lib/production-delphi-win64` 输出目录；FPC 补充构建如下：

```powershell
New-Item -ItemType Directory -Force -Path bin/production-fpc-win64,lib/production-fpc-win64 | Out-Null
& 'D:\Design\FreePascal\fpc\bin\x86_64-win64\ppcx64.exe' -B -uCROSS_EASY_THREAD_TESTS `
  '-Fu..\..\..' '-Fu..\..\..\..\DelphiToFPC' '-Fi..\..\..\..' `
  '-FEbin\production-fpc-win64' '-FUlib\production-fpc-win64' EasyThreadTests.lpr
python run_tests.py bin/production-fpc-win64/EasyThreadTests.exe --baseline
python build_linux.py --production delphi-linux64 fpc-linux64
```

生产分支及保留旧基线均加 `--baseline` 只跑原六项；Linux 生产文件位于 `bin/production-delphi-linux64/`、`bin/production-fpc-linux64/`，按上述 WSL 命令运行。

## 2026-10-19 首批结果与边界（a122c97）

- Delphi 13.1/FPC 3.3.1 的 Windows Win64、Linux64（Ubuntu 22.04 WSL 实际运行）四目标原基线均 **2/6 通过**；任务自身析构或自身 WaitFor 的四项失败。
- 最终测试构建均 **8/8 通过**；关闭故障注入入口的生产构建均 **6/6 通过**。
- 工作线程内析构只设置底层线程 `FreeOnTerminate` 并移交释放，避免等待自己或释放仍在运行的线程；外部线程仍正常等待并释放。Terminate 使用原子状态。公开签名保持不变。
- 两个构造失败用例在底层线程已创建、Start 前抛异常，验证未启动线程和捕获资源都完成一次清理；没有模拟操作系统真实线程创建/Resume 失败。没有扩展到 Win32、ARM 或长期压力。
- `bin/baseline-*/` 保存旧二进制；JSON 包含每项结果与可执行文件哈希，构建日志及源码哈希也在 `bin/`。不覆盖保留的红基线，不把旧文件运行当成最新源码验证。

## 追加：重复和并发原生等待回归

EasyTimer 的 B04 基线暴露出首批 8 项未覆盖的实际回归。本机 FPC Unix RTL 的 `TThread.WaitFor` 每次直接调用 `pthread_join`，只在析构时检查 `FThreadReaped`。多个 Timer 先显式 WaitFor，再析构，会再次等待已回收的线程；多个等待者同时 join 也不安全。原始单线程两次 WaitFor 偶然通过，不能证明这种用法正确。

本批保留 IEasyThread 签名，增加专门等待锁和单次 join 状态。外部 WaitFor 串行进入底层等待，首次成功后后续调用直接返回；即便线程 Finished，首次原生 join 仍必须执行。Terminate/GetTerminated 不取得等待锁。实际工作线程的自身 WaitFor 在进入等待锁之前返回；线程已 Finished/已 join 时不能因为 ID 被新线程复用而误转交 FreeOnTerminate。

新增 `EasyThreadJoinTests.inc` 覆盖：

- 16/64 个真实 Timer 分别 Terminate、两轮 WaitFor 后再析构。
- 八个等待者通过屏障同时等待一个未完成任务，每个等待者重复 WaitFor；检查任务未完成时不提前返回、终止不受等待锁阻挡、所有等待者最终返回。
- 外部等待者已经进入 WaitFor 后，工作回调自身再调用 WaitFor，不得等待等待锁形成互等。
- Linux 实际创建新线程拿到旧线程 ID，并在新线程释放已 join 的旧包装对象，检查包装对象和回调资源释放一次。未伪造 ID；若本次没有实际复用，测试会失败而不是把未覆盖当作通过。Windows 不包含此项。

| 目标 | 此批未修复基线 | 此批修复后 | 无测试开关生产构建 |
| --- | --- | --- | --- |
| Delphi Windows Win64 | 12/12 | 12/12 | 10/10 |
| FPC Windows Win64 | 12/12 | 12/12 | 10/10 |
| Delphi Linux64（Ubuntu 22.04 WSL） | 11/13 | 13/13 | 11/11 |
| FPC Linux64（Ubuntu 22.04 WSL） | 8/13 | 13/13 | 11/11 |

Delphi Linux 原版两个并发场景提前返回；FPC Linux 原版另有批量析构异常、等待者未全部返回及 ID 复用后的资源遗漏。当前四目标均由完整重编后的实际二进制验证。每项独立进程，外部 15 秒超时；线程时序仍由事件控制。

Windows 沿用上面的编译命令，将输出设为 `bin/join-green-delphi-win64` 或 `bin/join-green-fpc-win64`；FPC 加 `-dCROSS_EASY_THREAD_TESTS` 构建测试分支。生产分支去掉 Delphi 的 `-D`，FPC 用 `-uCROSS_EASY_THREAD_TESTS`，输出设为 `bin/join-production-<target>`。所有目录先创建，避免改全局编译器配置。

```powershell
python run_tests.py bin/join-green-delphi-win64/EasyThreadTests.exe --report bin/join-green-delphi-win64.json
python run_tests.py bin/join-green-fpc-win64/EasyThreadTests.exe --report bin/join-green-fpc-win64.json
python run_tests.py bin/join-production-delphi-win64/EasyThreadTests.exe --production --report bin/join-production-delphi-win64.json
python run_tests.py bin/join-production-fpc-win64/EasyThreadTests.exe --production --report bin/join-production-fpc-win64.json
python build_linux.py delphi-linux64 fpc-linux64
python build_linux.py --production delphi-linux64 fpc-linux64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyThreadTests -- python3 -B run_tests.py bin/delphi-linux64/EasyThreadTests --report bin/join-green-delphi-linux64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyThreadTests -- python3 -B run_tests.py bin/fpc-linux64/EasyThreadTests --report bin/join-green-fpc-linux64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyThreadTests -- python3 -B run_tests.py bin/production-delphi-linux64/EasyThreadTests --production --report bin/join-production-delphi-linux64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyThreadTests -- python3 -B run_tests.py bin/production-fpc-linux64/EasyThreadTests --production --report bin/join-production-fpc-linux64.json
```

此批红二进制位于 `bin/join-red-<target>/`，其运行使用当前默认完整列表；早期 `bin/baseline-*` 仍用 `--baseline`，仅运行原始六项。`--production` 执行现有全部非注入测试，包含批量及并发用例。源码和二进制记录保存在 `bin/join-final-source.json` 与各结果 JSON；没有声称覆盖 Win32、ARM 或长期压力，也未把 EasyTimer 本身的回调内销毁问题算作本批已修复。
