# 监听登记、成功通知与停止回归

修复对象是 epoll 的首次事件早于 owner 登记，以及 IOCP 的 AcceptEx 初始化漏过关闭/停止快照。公共层将内部登记和成功通知分开，kqueue 仅接入公共状态；其独立注册表、事件 ID 和回收算法未改变。

生产接口签名保持；具体类布局变化，依赖单元须完整重编译。使用契约见 [生命周期说明](../../../LIFECYCLE.md)。

## 测试方法

`.dpr` include `.lpr`，Delphi/FPC 共用主体。Python 父进程持有真实 IPv4/IPv6 TCP 客户端；`TEvent` 暂停在指定窗口，不靠延长 Sleep 碰撞。每个场景独立进程，父进程有 25 秒超时，内部屏障也有超时。

`CROSS_LISTEN_TESTS` 只加入登记后/完成包处理前的暂停观察点及 IOCP 挂起计数读取。未定义时全部移除，不改变接口布局，不伪造内核完成。正常测试最终停止并释放 owner，核对监听和连接的构造/析构计数、容器与挂起操作归零。红例断言失败时直接结束测试进程，避免旧版泄漏请求导致错误的析构展开。

| 场景 | 断言 |
| --- | --- |
| `early-event` | 原生注册后、成功通知前接入第一个客户端，确认事件批次被处理，再发布；前后两个客户端均被接受 |
| `close-before-publish` / `stop-before-publish` | 成功认领前关闭或停止，旧调用只报告失败，不重新入表；IOCP 停止后 pending 为零 |
| `close-before-register` / `stop-before-register` | 工厂返回前关闭或停止，旧监听不能登记 |
| `close-before-arm` | 已登记、原生提交前关闭，不再提交旧句柄 |
| `restart-old-listen` | 停止并重新启动后，旧调用仍失效，新调用可成功 |
| `close-callback` / `close-all-callback` | 成功认领后主动关闭不改报失败；关闭全部停止后续地址。后者实际解析并断言至少两个候选地址 |
| `register-error` | 真实原生注册错误后清理 owner 引用及监听对象 |
| `publish-raises` / `update-raises` | 派生发布方法/UpdateAddr 抛指定异常，异常保留且监听清理 |
| `io-stop` | I/O 线程中 StopLoop 在任何关闭副作用前拒绝；主线程仍能完成停止 |
| `normal` / `ipv6` | 两个连续真实连接成功，随后资源回收 |
| `accept-before-publish-stop` | 接入连接工厂中暂停，停止完成连接快照后放行，不能发布遗漏连接 |
| `partial-accept-error`，Windows | 第一个真实 AcceptEx pending，第二个向无效监听句柄提交；关闭并排空第一个请求 |
| `late-accept-stop`，Windows | 成功完成包处理前停止，恢复后不补投、不发布连接 |
| `accept-context-error`，Windows | 前两个 SO_UPDATE_ACCEPT_CONTEXT 用无效监听句柄触发系统错误，第三个客户端仍能接入 |
| `logger-raises` / `logger-reenter`，Windows/Linux | 注册错误日志抛指定异常或启动另一线程关闭监听，不能持内部锁调用 logger |

错误注入只作用于测试进程：Windows 利用已有 Winsock 函数变量转调原生函数；Linux 将自有 `/dev/null` 描述符 dup2 到测试监听编号，避免编号被其他线程复用。没有修改系统配置或第三方源码。Mac 发布构建没有对应 kqueue 错误日志，两个 logger 场景不适用；未将它们计为通过，也未扩大本轮 kqueue 修改范围。

## 构建与运行

在仓库根目录执行；路径沿用相邻测试工程的 Delphi 13.1、FPC 3.3.1 和现有 SDK，不安装依赖或修改全局配置。

```powershell
python -B Net/Tests/FPC/ListenLifecycleTests/run_tests.py --label fixed --targets win64 win32 fpc64
python -B Net/Tests/FPC/ListenLifecycleTests/run_tests.py --label fixed --targets delphi-linux64 fpc-linux64 delphi-osxarm64 --build-only
python -B Net/Tests/FPC/ListenLifecycleTests/run_tests.py --label heap --targets fpc64 fpc-linux64 --heap-trace --build-only
```

在实际 Linux 环境执行：

```sh
python3 -B Net/Tests/FPC/ListenLifecycleTests/run_tests.py --label fixed --run \
  Net/Tests/FPC/ListenLifecycleTests/bin/fixed/delphi-linux64/ListenLifecycleTests \
  Net/Tests/FPC/ListenLifecycleTests/bin/fixed/fpc-linux64/ListenLifecycleTests
```

Mac 已有的 FPC 安装位于 `$HOME/FreePascall/fpc/bin/aarch64-darwin`，lazutils 位于 `$HOME/FreePascall/lazarus/components/lazutils`。本机原生构建和执行：

```sh
python3 -B Net/Tests/FPC/ListenLifecycleTests/run_tests.py --label native-heap --targets fpc-osxarm64 --heap-trace --build-only
python3 -B Net/Tests/FPC/ListenLifecycleTests/run_tests.py --label native-heap --run \
  Net/Tests/FPC/ListenLifecycleTests/bin/native-heap/fpc-osxarm64/ListenLifecycleTests
```

`--cases` 选择场景；`--run` 运行现有产物；`--baseline-ref` 从 git 冻结四个旧单元，不覆盖工作区。旧版只注入观察声明、挂起计数入口及晚到完成观察点，不修正生产逻辑；旧版没有登记观察点，不能用 `close-before-arm` 验证它。

日志、命令、源码/二进制 SHA-256 和 `results.json` 保存在忽略的 `bin/<label>/`，编译单元在 `lib/`。堆检查须另外查看 heaptrc 输出，不能只凭进程退出码判定零泄漏。

## 2026-10-20 至 21 日实测

旧 master `e4349b4f5599e234ec1b776993e4850f09a35a29`：

- FPC Linux：`early-event` 明确处理了提前到达的事件批次，但两个客户端均未被接受；发布前关闭后仍重新报告成功。普通连接对照通过。
- Delphi Win64：发布前 StopLoop 返回后仍有 2 个 pending 请求，恢复 Listen 后又报告成功、重新入表；登记前关闭同样失败。普通连接对照通过。
- 独立审查发现中间实现把补投移到了接入上下文检查之后。新增原生错误注入复现两次失败耗尽接受槽位；修正补投顺序后 Windows 三目标均通过。该红例属于本轮中间实现，不归因于旧 master。

最终四个生产单元一致时实际运行：

| 套件 | Windows Delphi64 / Delphi32 / FPC64 | Linux Delphi64 / FPC64 | macOS ARM64 Delphi / FPC |
| --- | --- | --- | --- |
| 本套件 | 各 21/21 | 各 18/18 | 各 16/16 |
| ConnectFallbackTests | 各 14/14 | 各 14/14 | 各 14/14 |
| SocketCallbackTests | 各 21/21 | 各 22/22 | FPC 13/13 |
| IocpLifecycleTests | 各 6/6 | 不适用 | 不适用 |
| KqueueLifecycle / Edge / Address | 不适用 | 不适用 | FPC 7/7、5/5、4/4 |

此外 Windows Delphi64/FPC64 的 HttpHeadTests 各 14/14、HttpRequestLifetimeTests 各 6/6；HttpClient 和 WebSocketServer 正式 Release/Win64 构建成功。相邻 HTTP 生命周期是组件测试，不能称作真实网络压力验证。

本套件 FPC 的 Windows 21、Linux 18、Mac 16 个场景，以及 Mac ConnectFallback 的 14 个场景，heaptrc 均为零未释放块。SocketCallback 的监听失败测试每项执行 20 次，Windows 非 DNS 分支句柄数和 Linux fd 数保持不变；Windows DNS 的系统初始化增长另由零 close、存活断言验证，不宣称该分支句柄数不变。

证据目录为各套件 `bin/listen-final/`，本套件 FPC 为 `bin/listen-final-heap/`；Mac 取回记录在本套件 `bin/mac-results/`。Mac Delphi 产物经临时签名后原生执行，签名前后哈希另有记录。新测试最后的 Darwin 单元引用修正仅影响测试编译，四个生产单元哈希未变。

最终生产 SHA-256：

```text
Base   195b899d55fdab637b0fca353500647273a888eeef305122ce23cda71d1cb356
Iocp   534fa1e4056d775ef0536c93d994cca81ec8d4fcf535c9ba00c145f7e743211b
Epoll  6b989fab25ffd93d8d373980a428f3a568b6341cff37303a5c0bddedf0e140c8
Kqueue 063e110e1693f2193ab49bfb9d4361815530f166ecf8c7f92dd9522e6249259b
```

未验证 FreeBSD、32 位 kqueue、全部线程交错、长期压力、性能及 Mac 上层 TLS/HTTP/WS。对象析构、堆报告、系统句柄和挂起 I/O 是不同证据，不能相互替代。
