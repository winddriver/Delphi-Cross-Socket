# 基于用户最新版的 Thread / Timer 合并回归

本轮以用户提供的两个 zLib 单元为输入，将 a122c97、8a30168、b935b69 的生命周期和等待优化迁移到新版结构。只修改项目副本；外部输入保持原字节。

输入 SHA-256：

- EasyThread：`b866a347e558b8960b03f5bcccdc2a143a9e320d050e250954f1af38fca13721`
- EasyTimer：`7e6656eaf82b8ce92d98f068300ec961abed14e0a206ff2a7cc2c075f596f2d6`

输入及原项目副本保存在相邻旧套件的 `bin/latest-merge-input/`，精确输入也汇集在本套件 `bin/supplied-source/`。这些产物按仓库规则忽略，不提交私有环境或二进制。

## 合并后的约定

- 保留新版异常类型、两个 `WaitFor` 重载、Timer 的 `Timeout`、`BeforeExecute`、`AfterExecute`、`IsTimeout` 默认参数，以及非正 `StartTime` 立即启动。`ThreadID` 原本已有，继续保留原生类型和缓存身份。
- 用户明确选择项目修复版的两项行为：自身无参等待直接返回、有限自身等待返回 True；非正周期允许创建，后续按 10ms 调度。自身 True 是 no-op，不能据此判断当前线程已经退出。
- Thread 回调继续收到新版独立 Control。它可以比包装对象活得更久；包装对象释放后，Control 仍可读取终止状态和原线程 ID，未完成任务不会因指针解绑被误报完成。
- 无参及 `High(Cardinal)` 等待、外部析构完成一次真实 native join。有限等待只等待任务及线程保存的闭包清理完成，不进入无界 join 锁；True 不表示已经完成 native join。超时返回 False 不终止任务。主线程有限等待不处理 Synchronize，业务需要主线程配合时可能正常超时。
- 保留事件唤醒、单调周期、巨大参数分段、暂停/周期修改/终止唤醒、空闲健康及结束后冻结心跳。没有恢复固定 10ms 空闲轮询。
- Timer 保留具体类 `Interval` 扩展。`IsTimeout` 的正参数优先，否则使用 `Timeout` 配置；最终阈值非正时禁用超时判断。
- 一个已接纳周期按 Before→Proc→After 执行。Before 抛异常会跳过后续；Proc 异常隔离后仍执行 After；Proc 内替换 After 对本轮生效。事件接收对象仍由调用方保活，属性锁不负责管理接收对象的寿命。
- 事件参数是实际 Timer 的接口和对象身份。只在带事件的周期临时保活，Proc 首次设置 After 时补当前周期引用，finally 在锁外释放；无事件的裸对象 Free 和外部析构等待路径保留原语义。非 nil 事件须在构造完成、持有接口后安装；不自动转换裸对象与接口的所有权。

新版已在相同 GUID 下扩展接口方法布局。使用这些单元的项目、包及依赖 DCU/PPU **必须完整重编**，不能混用原项目旧接口二进制。

## 新增 13 项

| 用例 | 实际检查 |
| --- | --- |
| thread-api | 两构造重载、ThreadID、0/有限超时、超时不终止、完成后重复等待 |
| selected-self-wait | 无参及有限自身等待均继续执行，有限返回 True |
| thread-mixed | 无限等待者存在时，Control 的有限等待仍遵守自己的预算；大有限值不溢出 |
| thread-retained-control | 工作线程释放包装对象后继续停在屏障，保留的 Control 不得误报完成 |
| thread-capture-cleanup | 捕获对象析构被屏障阻塞时，0/短有限等待仍为 False；清理完成后才为 True |
| timer-hooks | 真实身份及基接口往返、Before 异常跳过、Proc 异常仍调用动态替换的 After、自身有限等待 |
| timer-timeout-fallback | 默认/0/-1 参数使用 Timeout，正参数覆盖，暂停健康及回调卡顿 |
| selected-nonpositive-interval | 构造接受 0/负周期，后续不会形成忙循环 |
| timer-release-before/proc/after | 三阶段各释放最后外部引用，周期、析构和捕获清理正确 |
| timer-base-release | 暂停并安装事件后，将唯一外部引用转为 IInterface 再释放，全部资源回收 |
| timer-install-after | 无初始事件的 Proc 首次安装 After 并释放 Timer，本轮仍以真实身份完成 After |

每项为独立子进程，默认总超时 15 秒；工作与释放时序用事件屏障。退休对象内存保留到实际 worker 析构被观察到后才比较和回收，避免提前比较造成假阳性。测试宏仅提供私有 worker 的析构计数，不模拟完成；runner 自动检测支持它的 Thread 源码并记录开关。

## 红基线与测试修正

用户输入原版在两个 Windows 编译器上各 4/10。两个 `selected-*` 红例属于用户明确选择的行为差异，不混同安全缺陷；Control 保留场景实际复现了仍在回调屏障中却报告完成。

仅换成合并后的 Thread、仍保留用户原 Timer 时，前/中释放触发访问异常。原快照检查对 After 曾显示通过，但没有等待实际 worker 终结，不能证明安全；补上析构观察后，三个释放场景在两编译器上均为 0/3。旧记录保留在 `bin/timer-supplied-thread-fixed*/`，没有覆盖失败或薄弱证据。

Delphi Linux 曾有 9/10：测试把 `TThread.CurrentThread.ThreadID` 当作运行期不变值，而 RTL 会在 pthread_join 前清零该对象属性。已改用任何 join 开始前记录的真实身份，不改变生产缓存；随后通过。记录在 `bin/merged-observed/` 与后续标签。

## 最终实际验证

| 范围 | Windows/Linux | Mac arm64/FPC | 合计 |
| --- | ---: | ---: | ---: |
| 原 EasyThread 套件（测试宏及生产分支） | 100/100 | 26/26 | 126/126 |
| 原 EasyTimer 套件（原断言保留） | 212/212 | 53/53 | 265/265 |
| 新版 API 与生命周期 13 项 | 65/65 | 13/13 | 78/78 |
| 真实 HTTP HEAD/连接复用客户端 | 56/56 | 未运行 | 56/56 |

共 525 项运行检查通过，不重复计入前期 10/12 项迭代。Windows/Linux 的64位矩阵各含 Delphi 与 FPC，新增API另覆盖 Delphi Win32；Mac 为 macOS14 arm64 / FPC3.3.1。Unix 的旧 Thread 套件实际覆盖线程 ID 复用，宏分支另外核对 worker 析构一次。正式 HttpClient 的 Release/Win64 MSBuild 构建通过，未启动示例界面。

原套件和 HTTP 的证据分别位于相邻套件 `bin/latest-integrated/`、`bin/latest-merge-source.json`、`Net/Tests/FPC/HttpHeadTests/bin/latest-timers/`。期间用户另同步其它 Utils：这些修改不属于本轮修复或提交；最终 78 项新增回归已在当前依赖组合上重编并通过，当前组合的正式构建记录在 `formal-httpclient-current-utils/`。各轮依赖按其实际哈希保存，不把旧依赖结果伪称为当前全部组合验证。

短性能核对只运行四目标、16 实例的 idle/paused 共 8 个一秒窗口，CALLS=0、正常清理，观测 CPU/上下文切换增量为 0，用于确认没有恢复轮询；不重述为新的吞吐收益。Win32仅覆盖新增API的13项，没有扩展为旧套件及HTTP组合的32位保证；未覆盖Delphi macOS、FreeBSD、移动端、长期压力或任意业务锁互等。

## 重现入口

```powershell
python run_tests.py --build delphi-win64 --label verify --report bin/verify/delphi-win64/results.json
python run_tests.py --build fpc-win64 --label verify --report bin/verify/fpc-win64/results.json
python run_tests.py --build delphi-win32 --label verify --report bin/verify/delphi-win32/results.json
python run_tests.py --build delphi-linux64 --label verify --build-only
python run_tests.py --build fpc-linux64 --label verify --build-only
```

Linux 在真实目标上对产物执行同一 runner；Mac 使用已有配置，不安装工具或修改全局设置：

```sh
python3 -B run_tests.py --build fpc-macos-arm64 --label verify \
  --compiler "$HOME/FreePascall/fpc/bin/aarch64-darwin/fpc" \
  --fpc-config "$HOME/FreePascall/fpc/bin/aarch64-darwin/fpc.cfg" \
  --lazutils "$HOME/FreePascall/lazarus/components/lazutils" \
  --report bin/verify/fpc-macos-arm64/results.json
```

`--source` 可指定只读的两个单元快照目录。构建、报告标签均拒绝覆盖旧证据；source.json 记录真实依赖、编译命令、观察宏及构建前后哈希，results.json 记录二进制哈希及逐项结果。

最终索引为 `bin/final-manifest.json`：核心源码、外部输入未变、九个用户同步文件保持、六目标新增API报告和总计525项。Mac原套件/12项阶段证据在 `bin/mac-evidence/`，同步当前依赖后的最终13项在 `bin/mac-current/`，两个阶段不覆盖。生产最终SHA：Thread `1532ebb26dee3efc659a5c230fa2e2988648382cfa493880f44b96c94d67218b`，Timer `99c2e81e09840dd3d6e4397d312f894d170297afff6fc6ebf6e351da5e10d02f`。

如需释放事件接收对象，应从外部线程先 Terminate、再无参 WaitFor，完成后释放Timer接口及接收对象；单纯清掉某个外部接口引用不代表事件周期已经结束。
