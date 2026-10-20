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

## 2026-10-20 用户最新版迁移：生命周期适配

本轮依据 `docs/plans/2026-10-20-latest-thread-timer-merge.md`，保留用户提供的独立 Control 回调身份、`EEasyThread` 和 `WaitFor(Cardinal): Boolean` 重载。工作回调得到的接口不再是包装对象，允许保存该 Control 并在 wrapper 释放后继续读取状态和等待。

原四个 self 场景改为在工作线程内明确释放最后的 wrapper 引用，再继续使用回调 Control，仍检查 wrapper 和捕获资源各释放一次。`self-terminate` 在释放 wrapper 之前检查外部 Terminate 传播，避免析构自动终止掩盖错误。新增 `control-external-destroy`：与原无参数匿名任务一样，用独立释放线程验证有参数任务最后外部引用析构会等待实际任务结束；不允许直接删掉阻塞等待断言。

真实线程 ID 复用场景继续要求本次确实发生复用。由于新实现会在 Execute 尾部提前清掉 Proc，捕获资源释放已经不能单独证明底层线程对象释放。因此测试宏新增只读 `GetEasyThreadDestroyedCountForTest`，在此场景检查 join 后 wrapper 仍存在时计数为 0、由复用 ID 的新线程释放 wrapper 后计数为 1；生产分支没有该计数器或析构观测代码。

等待语义分开记录：

- 无参及 `High(Cardinal)` 等待、外部析构：原生 join 恰好一次；主线程竞争等待锁时仍处理 Synchronize。
- 有限等待：只等任务及线程持有的闭包清理完成，不进入 join 锁，不在等待中执行 CheckSynchronize。True 不表示原生 join 已完成；后续无参等待和析构仍负责回收。主线程有限等待可能因 worker 等待 Synchronize 而超时，返回后由正常主线程循环继续处理。
- 自身调用两种 WaitFor 均为 no-op，有限重载返回 True；这不表示工作线程已经退出。
- 已 Start 的任务即使立即 Terminate 也会进入 Proc，由任务按协作终止状态执行自身收尾。原生 Terminate 仅在 worker 进入 Execute 后同步，避免 RTL 跳过整个 Execute 而遗漏捕获清理；Start 前失败仍显式拆掉未执行捕获且不调用 Proc。

`--baseline` 保持历史六项列表不变，用于已有旧二进制。默认及 `--production` 列表各增加 `control-external-destroy`；当前源不能因独立 Control 带来的释放时序变化而照搬旧的 Self 捕获假设。此处仅记录本轮代码和测试安排，未将历史通过数视为本轮运行结果；新 API 专项及本轮平台结果由后续完整构建另行记录。

### Thread 预验证：固定旧 Timer 快照

新版 Thread `1532ebb26dee3efc659a5c230fa2e2988648382cfa493880f44b96c94d67218b` 已在 Windows Delphi 13.1/FPC 3.3.1 各通过 13/13 项。Timer 单元搜索优先固定到相邻 `EasyTimerTests/bin/latest-merge-input/project/` 的旧项目快照，本轮不代表最终新版 Timer 整合验证；Windows 列表不包含 Unix 真实线程 ID 复用场景。

- Delphi Win64：`bin/latest-thread-fpc-fix/delphi-win64/`。
- FPC Win64：`bin/latest-thread-fpc-deps/fpc-win64/`。

以上目录各有 build.log、run.log、source.json、results.json，输入哈希在构建/运行前后相同，可执行文件哈希与结果相同。宏构建包含 Start 前故障注入及 worker 析构观测；本轮尚未运行关闭测试宏的生产构建。

原始 `bin/latest-thread-first/` 保留 Delphi 13/13 及 FPC 的重载解析编译失败：Boolean WaitFor 内裸 `WaitFor;` 需明确写 `Self.WaitFor;`。该一行兼容修复后，`latest-thread-fpc-fix/fpc-win64` 又记录旧 Timer 依赖 Masks 缺搜索路径；按照现有 Linux 构建约定补 Lazarus components/lazutils 后得到上述 FPC 13/13，未因此修改生产逻辑。`--baseline` 历史六项列表未变。

### 最新 Thread + Timer 最终整合（Windows / Linux）

此次直接编译项目 `Utils/` 的新版 Thread 和 Timer，不再使用旧 Timer 快照。冻结输入：Thread `1532ebb26dee3efc659a5c230fa2e2988648382cfa493880f44b96c94d67218b`；Timer `99c2e81e09840dd3d6e4397d312f894d170297afff6fc6ebf6e351da5e10d02f`。

| 平台 | 开启测试宏 | 关闭测试宏（--production） |
| --- | --- | --- |
| Delphi Win64 | 13/13 | 11/11 |
| FPC Win64 | 13/13 | 11/11 |
| Delphi Linux64 / Ubuntu 22.04 WSL | 14/14 | 12/12 |
| FPC Linux64 / Ubuntu 22.04 WSL | 14/14 | 12/12 |

合计 **100/100**。Linux 四组均实际取得复用的线程 ID；宏构建额外确认底层 worker 析构计数由 0 变为 1。生产分支排除两个构造注入案例，但保留原六项、Control 参数的外部 lastref 等待、批量 Timer、并发等待、自身等待和 Unix ID 复用，没有缩减成 --baseline 六项。

证据统一放在 `bin/latest-integrated/` 下的八个 flavor（四个目标及对应 `production-` 前缀）。每组保存 build.log、source.json、results.json、run.log；Linux 另有 build.json 记录完整编译命令和前后输入哈希。所有结果已逐项核对当前源码哈希与可执行文件哈希，外部用户提供的两个文件仍与本计划记录的输入哈希一致。此次不包含 Mac，也不替代新 API 专项结果。

Linux 构建脚本新增可选 --label，省略时保留原路径。例如：

```powershell
python build_linux.py delphi-linux64 fpc-linux64 --label latest-integrated
python build_linux.py delphi-linux64 fpc-linux64 --production --label latest-integrated
```

随后在 WSL 使用现有 run_tests.py 运行相应目录中的 EasyThreadTests，生产二进制加 --production。Windows 继续使用本 README 的 Delphi/FPC 编译参数；FPC 补充已有 Lazarus components/lazutils 搜索路径，完整命令已记录在对应 source.json。历史目录未覆盖。

### 真实 HTTP 客户端兼容与正式示例构建

相同 Thread/Timer 冻结版本下，既有 HttpHeadTests 在 Delphi/FPC Win64、Delphi/FPC Linux64 各 14/14，共 **56/56**；真实 TCP 检查仍包括请求定界、正文以及后续 GET 复用同一连接。未扩跑临时响应等无关套件。证据为 `Net/Tests/FPC/HttpHeadTests/bin/latest-timers/` 的四目标结果、build-inputs.json 和 manifest.json。

正式 `Net/Demos/Delphi/HttpClient/HttpClient.dproj` 经 MSBuild Rebuild、Release/Win64 构建成功，输出位于同标签的 `formal-httpclient-fixed/`；未运行该示例。首次启动命令的 rsvars 引号包装错误保留在 `formal-httpclient/build.log`，该次未进入编译器；修正命令后未改变项目源文件。正式构建前后全部输入哈希一致，新生成的 HttpClient.res 已移除，原有项目文件字节未变，没有覆盖用户文件。外部用户提供的 Thread/Timer 文件哈希再次确认不变。
