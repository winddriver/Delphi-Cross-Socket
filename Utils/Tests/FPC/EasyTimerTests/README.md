# EasyTimer 回归与测量

计划 B04/O04。已实现独立状态对象和可唤醒事件等待，保留旧版问题基线及生命周期正确的轮询性能对照。

基线测量空闲/暂停进程的 CPU、系统上下文切换和线程数，以及真实回调触发时间。系统上下文切换是空闲唤醒的代理指标，不等同于精确唤醒次数；测量包含零 Timer 的进程对照。

生命周期用事件控制；回调内销毁通过测试派生类保留已经 CleanupInstance 的对象内存，待工作回调捕获资源释放后比较字节，确定性检测析构后写入，不依赖释放内存碰巧被覆盖。

## 已建立的基线

`bin/baseline3-<target>/` 是保留的未修复二进制，包含 18 项；Windows Delphi/FPC、Delphi Linux 分别为 15/18，FPC Linux 为 14/18。三项共同失败为回调内销毁、销毁后抛异常和构造失败收尾；FPC Linux 另有批量重复 WaitFor/析构失败。后者属于 EasyThread 的独立兼容回归，已经另批修复，不能把本目录旧基线结果当作当前 EasyThread 的状态。

前一版 `baseline2-*` 的 17 项四目标都是 14/17；性能测量使用该版，CPU/上下文切换测量不带观察生产轮询的修改。更早的 `baseline-*` 包含 100 次顺序创建释放，在 FPC Linux 触及测试外部超时；已改为 16 次有界批次，这个测试超时不算生产缺陷。

行为覆盖立即触发、初始延迟、暂停/恢复、暂停发生在回调期间、长周期 Terminate、外部析构等待回调、回调内 WaitFor/Terminate、异常后继续，以及空闲/暂停/执行中/Finished 的心跳。原有 API 没有 Interval 修改入口；本批在具体类新增该属性并补齐调整周期的测试，IEasyTimer 接口布局保持不变。

## 首轮性能采样（修改前）

每种空闲场景预热 0.3 秒，采样 2 秒；分别创建 0/1/16/64 个实例，回调延迟和周期均为一小时。该表仅是一轮原始基线，不能据此宣称稳定收益；最终多轮比较见后文，使用生命周期均正确的两个版本。

| 目标，64 个实例 | idle 上下文切换/秒 | paused 上下文切换/秒 | idle CPU 时间/2 秒 | paused CPU 时间/2 秒 |
| --- | ---: | ---: | ---: | ---: |
| Delphi Win64 | 6119 | 6180 | 0 ms | 31.25 ms |
| FPC Win64 | 6099 | 6276 | 78.125 ms | 0 ms |
| Delphi Linux64 | 6624 | 6468 | 220 ms | 180 ms |
| FPC Linux64 | 6362 | 6364 | 170 ms | 150 ms |

- Windows 使用已安装的 psutil 7.1.0 和 QueryProcessCycleTime；CPU 时间存在明显量化，0 ms 不代表没有 CPU 开销。64 个实例两秒实际周期数约为 Delphi 2.68/3.09 亿、FPC 2.52/2.85 亿（idle/paused），不将周期数按假定频率换算为时间。
- Linux 从 `/proc` 读取进程 CPU，汇总所有线程的上下文切换；零 Timer 对照 CPU 与上下文切换均为零。64 个实例使 Windows 进程线程数从 4 到 68，Linux 从 1 到 65；保留每实例线程是已选范围，不将线程数下降作为本批目标。
- FPC Linux 的 16/64 实例采样区间正常，随后旧版重复 join 的批量析构失败；JSON 明确保存 `cleanup_ok=false` 和调用栈。测量值不能替代生命周期通过结论。
- 每个间隔采集 50 次真实回调。5/25/100 ms 间隔的额外间隔中位数在 Windows 约为 6/7/7 ms，在 Linux 约为 5/5～6/1 ms；原始样本保存在 `bin/perf-baseline2-<target>.json`。没有修改时钟分辨率、进程优先级或系统调度配置。

## 重现命令

本目录执行，使用已有 Delphi 13.1/FPC 3.3.1 和 Ubuntu 22.04 SDK。`--build` 全量重编，输出放到新的标签目录；不要覆盖 `baseline*`。

```powershell
python run_tests.py --build delphi-win64 --label current --report bin/current-delphi-win64.json
python run_tests.py --build fpc-win64 --label current --report bin/current-fpc-win64.json
python build_linux.py delphi-linux64 fpc-linux64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyTimerTests -- python3 -B run_tests.py bin/delphi-linux64/EasyTimerTests --report bin/current-delphi-linux64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyTimerTests -- python3 -B run_tests.py bin/fpc-linux64/EasyTimerTests --report bin/current-fpc-linux64.json
python run_perf.py bin/baseline2-delphi-win64/EasyTimerTests.exe --report bin/perf-repeat-delphi-win64.json --rounds 3
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyTimerTests -- python3 -B run_perf.py bin/baseline2-fpc-linux64/EasyTimerTests --report bin/perf-repeat-fpc-linux64.json --rounds 3
```

生产验证去掉 `CROSS_EASY_THREAD_TESTS`（Windows runner 加 `--production`、Linux build 加 `--production`），运行阶段同样加 `--production`，仅排除构造失败注入，仍运行其他全部用例。`--original` 可重跑保存的原 18 项二进制；`--baseline` 仅运行早期 16 项子集。没有新增 EasyTimer 的生产测试入口。

## 实现语义

- 使用可唤醒事件等待实际剩余时间，仍保留每实例线程；以单调时钟计算周期。新增一个状态对象、状态锁和事件，工作回调不再捕获 Timer 的 Self。
- 具体类提供 Interval 属性（接口变量可转为 TEasyTimer 访问），IEasyTimer 既有布局保持不变；暂停、周期变更和 Terminate 唤醒等待。首次 Delay 不受 Interval 修改影响；之后从前次回调处理结束起计时，非正周期按 10 ms 执行。暂停期间已过时间继续累计，恢复时若已到期则立即触发；暂停不取消已经接纳的回调。
- 工作回调捕获独立强引用状态，不再依赖 Timer 对象活到回调返回，解决回调内销毁后的访问。
- 保持心跳含义：空闲或暂停的活线程不误报超时；LastTick 返回当前观察时间；回调中返回开始前心跳并能检测长时间卡顿；Finished 后保留最后值。这些约定已经写入 API 注释并通过边界回归。

- 单元初始化时预热 Stopwatch 的共享频率参数，避免首次并发创建 Timer 时进入 RTL 无锁懒初始化窗口。
- 有限等待单次不超过 High(Integer) 毫秒，超过时重新计算剩余时间；暂停可无限等待但随时能被唤醒。High(Int64) Delay/Interval 的不提前触发和及时终止已实测。

## 最终正确性结果

| 目标 | 生命周期正确的轮询对照 | 事件等待最终版 | 无测试宏最终生产构建 |
| --- | --- | --- | --- |
| Delphi Win64 | 25/25 | 27/27 | 26/26 |
| FPC Win64 | 25/25 | 27/27 | 26/26 |
| Delphi Linux64（Ubuntu 22.04 WSL） | 25/25 | 27/27 | 26/26 |
| FPC Linux64（Ubuntu 22.04 WSL） | 25/25 | 27/27 | 26/26 |

新增用例覆盖缩短/延长周期、暂停中改周期、回调内改周期、Interval 不改变首次 Delay、非正值避免忙循环、八线程首次并发创建和极大时间参数。生产分支仅少一项构造失败注入。每项独立进程，使用事件控制生命周期并有外部超时；正常销毁和回调内销毁都检查回调捕获资源最终释放，后者还比较已清理对象的内存，确保工作线程不再写入。

## 三轮交替性能对照

先修复生命周期、时钟与 Interval/心跳契约，保留一个仍然 Sleep(10) 的正确版本；再仅替换等待方式。最终性能对照的两个版本四目标均通过当时全部 25 项回归。每轮逐场景交替运行，下一轮反转先后次序；每个空闲样本预热 0.3 秒、采样 2 秒，触发偏差每个样本记录 50 次回调。每目标有 42 个空闲窗口、18 组时序样本，全部 `cleanup_ok=true`。

下表是 64 个实例的三轮中位数；上下文切换仍为唤醒的代理指标。

| 目标 | idle 切换/秒：轮询→事件 | paused 切换/秒：轮询→事件 | Linux CPU毫秒/2秒（idle/paused）：轮询→事件 | Windows CPU周期/2秒（idle/paused）：轮询→事件 |
| --- | ---: | ---: | ---: | ---: |
| Delphi Win64 | 6119→0 | 6124→0 | 不适用 | 337,485,496 / 321,698,990 → 0 / 0 |
| FPC Win64 | 6153→0 | 6139→0 | 不适用 | 276,928,266 / 294,854,970 → 0 / 0 |
| Delphi Linux64 | 6360→0 | 6354→0 | 160 / 190 → 0 / 0 | 不适用 |
| FPC Linux64 | 6364→0 | 6359→0 | 160 / 170 → 0 / 0 | 不适用 |

所有 1/16/64 实例的事件版空闲及暂停样本中，CPU 时间、上下文切换和可用的周期计数增量均为 0。这里的 0 是测量窗口内的观测值，不是任意负载下的绝对零开销承诺。Windows CPU 时间量化明显，因此列周期数，不按假定主频换算。两版线程数相同：64 个实例时 Windows 为 68、Linux 为 65；没有引入共享调度器。

将同目标三轮的间隔误差合并，P95 额外延迟如下（毫秒）：

| 目标 | 请求 5 ms：轮询→事件 | 请求 25 ms：轮询→事件 | 请求 100 ms：轮询→事件 |
| --- | ---: | ---: | ---: |
| Delphi Win64 | 6→1 | 8→1 | 8→1 |
| FPC Win64 | 6→1 | 8→1 | 7→1 |
| Delphi Linux64 | 6→1 | 6→1 | 3→1 |
| FPC Linux64 | 6→1 | 6→1 | 3→1 |

原始最大值也保留在 JSON；例如 Delphi Win64 25 ms 事件版仍有单次 6 ms 额外延迟。上述是本机采样，不是实时精度保证，也不等于 HTTP 吞吐提升。

基准使用冻结的 Timer 源码 SHA256 `3d7cbac7846a4c4d299dd0d2d151bf2f7595e292586df76ce26f5e8da7f7050d`，轮询对照为 `680f1fa862eb54ae83daa3a2750ffce12e8fa78714895b792ba8a98826edfd51`。其后唯一生产变更是有限等待上限从 High(Cardinal)-1 改为 High(Integer)，避免 32 位 POSIX 的有符号转换；样本使用一小时等待与 5/25/100 ms 周期，未触发该上限分支。最终源码已重新完整构建并验证 27/26 项，包括两个极大参数用例，未把旧基准二进制伪称为最终哈希构建。

## 最终构建及基准命令

```powershell
python run_tests.py --build delphi-win64 --label release --report bin/release-delphi-win64.json
python run_tests.py --build fpc-win64 --label release --report bin/release-fpc-win64.json
python run_tests.py --build delphi-win64 --label release-production --production --report bin/release-production-delphi-win64.json
python run_tests.py --build fpc-win64 --label release-production --production --report bin/release-production-fpc-win64.json
python build_linux.py --label release delphi-linux64 fpc-linux64
python build_linux.py --label release --production delphi-linux64 fpc-linux64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyTimerTests -- python3 -B run_tests.py bin/release-delphi-linux64/EasyTimerTests --report bin/release-delphi-linux64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyTimerTests -- python3 -B run_tests.py bin/release-fpc-linux64/EasyTimerTests --report bin/release-fpc-linux64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyTimerTests -- python3 -B run_tests.py bin/release-production-delphi-linux64/EasyTimerTests --production --report bin/release-production-delphi-linux64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyTimerTests -- python3 -B run_tests.py bin/release-production-fpc-linux64/EasyTimerTests --production --report bin/release-production-fpc-linux64.json
```

已记录的冻结基准可直接复跑：

```powershell
python run_perf.py bin/final-delphi-win64/EasyTimerTests.exe --compare bin/polling-final-delphi-win64/EasyTimerTests.exe --report bin/perf-final-compare-delphi-win64.json --rounds 3
python run_perf.py bin/final-fpc-win64/EasyTimerTests.exe --compare bin/polling-final-fpc-win64/EasyTimerTests.exe --report bin/perf-final-compare-fpc-win64.json --rounds 3
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyTimerTests -- python3 -B run_perf.py bin/delphi-linux64/EasyTimerTests --compare bin/polling-final-delphi-linux64/EasyTimerTests --report bin/perf-final-compare-delphi-linux64.json --rounds 3
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyTimerTests -- python3 -B run_perf.py bin/fpc-linux64/EasyTimerTests --compare bin/polling-final-fpc-linux64/EasyTimerTests --report bin/perf-final-compare-fpc-linux64.json --rounds 3
```

新检出环境可用 `run_tests.py --build <target> --polling --label <新标签>` 或 `build_linux.py --polling --label <新标签> ...` 从当前生产单元生成仅等待语句不同的隔离源码和二进制；`build_common.py` 只替换唯一的等待语句，不修改生产文件，按内容散列保存源码，已有不同内容则拒绝覆盖。新生成的对照会对应当前源码，不冒充上表已记录的旧冻结版本。

`bin/final-source.json` 汇总最终组件与基准哈希；各构建目录 `source.json`、`build.log` 与结果 JSON 保留原始证据，`bin/perf-summary.json` 是从三轮原始记录生成的统计。旧版 FPC Linux 关闭失败记录仍在 `perf-baseline2-fpc-linux64.json`，没有删除或计为通过。

## 验证边界

- 本轮实际运行 Windows Win64 和 Linux64；没有运行 Win32、ARM、移动系统或长期压力，也没有修改系统优先级、时钟分辨率或系统时间。根代理用最终 `0e2f9ede` 源码重编 HttpHeadTests，Delphi/FPC Windows、Delphi/FPC Linux 四目标真实客户端各 14/14，共 56/56；覆盖请求、HEAD/压缩/provider、连接复用和退出。构建及源码哈希位于该套件 `bin/o04-final-<target>/`，未将此结果表述成 HTTP 吞吐测量。
- 周期和 IsTimeout 使用单调计时；但 Delphi Linux 的现有 TEvent RTL 使用 CLOCK_REALTIME 的 sem_timedwait，底层等待仍可能受系统墙钟跳变影响。没有修改第三方 RTL 或把单调计算表述成所有平台的底层等待都免受墙钟变化。
- 本次未改变 Logger 的独立线程或其他定时服务；比较的是独立 Timer 进程。共享工作区存在其他批次改动，源码和构建证据以记录的哈希为准。

## 2026-10-20 用户最新版合并后的旧矩阵复验

以用户新版 Timer 的公开 API 为基础，重新整合事件等待、独立状态和异常/自毁修复。新接口增加 `Timeout`、`BeforeExecute`、`AfterExecute`、`WaitFor(Cardinal): Boolean` 和 `IsTimeout` 默认参数；同 GUID 下方法布局已扩展，所有使用者必须完整重编译，不能混用旧 DCU/PPU/package。本节不追溯更改前述 b935b69 当时“接口布局保持”的历史记录。

用户明确保留此前两项行为：自身 WaitFor 不等待，有限版本返回 True（不表示自身线程已经退出）；非正 Interval 接受，后续周期按 10ms。其余新版行为包括 Timeout 回退、StartTime 非正值立即启动、Before → Proc → After 顺序及 Proc 中动态更换 After 的本轮生效。

有 Before/After 的周期临时保活实际 Timer 接口；Proc 本轮首次安装事件时可补当前周期引用，所有退出路径都在锁外释放。无事件路径不新增 Timer 接口引用，保留旧的外部析构等待与自毁收尾。安装非 nil 事件须在构造完成后持有 `IEasyTimer`，否则同步抛 `EEasyTimer`；不自动把裸对象改成接口所有权。事件的接收对象由调用方保活。有限 WaitFor 按新版 EasyThread 等待任务及其线程回调捕获清理，无参/无限等待承担实际 join；具体新增 API 交叉用例由另一个专项记录。

本目录测试源码和断言未修改，原有 `self-destroy`、`self-destroy-exception`、`external-destroy`、构造失败和已清理对象内存比对均保留。基于以下冻结生产源码重新构建：

- Timer：`99c2e81e09840dd3d6e4397d312f894d170297afff6fc6ebf6e351da5e10d02f`
- EasyThread：`1532ebb26dee3efc659a5c230fa2e2988648382cfa493880f44b96c94d67218b`

| 目标 | 测试宏 | 关闭测试宏 |
| --- | --- | --- |
| Delphi 13.1 Windows Win64 | 27/27 | 26/26 |
| FPC 3.3.1 Windows Win64 | 27/27 | 26/26 |
| Delphi 13.1 Linux64 / Ubuntu 22.04 WSL | 27/27 | 26/26 |
| FPC 3.3.1 Linux64 / Ubuntu 22.04 WSL | 27/27 | 26/26 |

合计 **212/212 实际通过**，无跳过；生产分支只排除既有构造故障注入。新标签为 `latest-merge-<target>` 和 `latest-merge-production-<target>`，没有覆盖历史原版、轮询或事件版本。八个二进制、源码/结果与简短等待核对的证据索引为 `bin/latest-merge-source.json`。

正确性通过后复用 `run_perf.idle`，四目标的生产程序各建立 16 个 Timer，分别空闲/暂停测量 1 秒（预热 0.3 秒）。八个窗口均为 `CALLS 0`、`cleanup_ok=true`，CPU 时间及系统上下文切换增量均为 0。原始记录为 `bin/latest-merge-idle-win.json` 和 `bin/latest-merge-idle-linux.json`。这只是确认可唤醒等待没有恢复轮询的短核对，不是新旧性能比较，不据此新增速度收益声明；既有三轮基准保持原有源码版本与适用范围。

复验命令沿用原 runner，输出标签独立：

```powershell
python -B run_tests.py --build delphi-win64 --label latest-merge --report bin/latest-merge-delphi-win64.json
python -B run_tests.py --build fpc-win64 --label latest-merge-production --production --report bin/latest-merge-production-fpc-win64.json
python -B build_linux.py --label latest-merge delphi-linux64 fpc-linux64
python -B build_linux.py --label latest-merge --production delphi-linux64 fpc-linux64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyTimerTests -- python3 -B run_tests.py bin/latest-merge-delphi-linux64/EasyTimerTests --report bin/latest-merge-delphi-linux64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyTimerTests -- python3 -B run_tests.py bin/latest-merge-production-fpc-linux64/EasyTimerTests --production --report bin/latest-merge-production-fpc-linux64.json
```

其余目标按表替换；本批未运行 Mac、Win32、新增事件 API 的完整矩阵或正式示例，这些由主任务其他验收记录负责，不能混入本目录 212 项。
