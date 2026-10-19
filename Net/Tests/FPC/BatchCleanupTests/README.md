# 批量清理与超时快照回归

对应 O02/B02，以及 O01 后单独处理的 Epoll/Kqueue 完成回调收集。生产范围仅 `Net.CrossHttpParams.pas`、`Net.CrossHttpClient.pas`、`Net.CrossSocket.Epoll.pas`、`Net.CrossSocket.Kqueue.pas`，不改变事件注册算法或公开接口布局，不引入新的调度器。

## 实现边界

- Session 清理首次匹配才分配最多 8 槽接口数组，满后几何增长且不超过字典条目数；零过期不分配快照，最终按有效数量收缩。判定、收集、删除仍在同一写锁内，保留 Before/OnCheck/After 钩子的位置与次数。删除对象的快照和遍历变量在外层 finally 中释放，确保正常及异常路径都在解锁后析构。
- HTTP 客户端三类超时候选各在首次匹配时按连接数预留数组，记录实际数量；锁外处理时重验当前状态和最后活动时间。空闲判定包含 `FPending=0`，与池复用的检查及预占共用请求锁；认领关闭后标记 `rsClose`，然后锁外 Close。失效的请求超时候选不再清空新请求字段。watch 的更新及读取使用现有递归临界区。
- DEBUG 日志在连接锁内保存数量及首个 idle 的接口引用，在请求锁内复制 watch 值，再锁外写日志；不在解锁后读取字典或裸连接指针。
- Epoll/Kqueue 成功回调数组在第一个完成项时按当前队列数预留，零完成/EAGAIN 不分配；取消路径先数非空回调再一次分配。仍先保留回调再 Dequeue/Dispose 指针，用户通知在队列锁外逐项执行，异常隔离保持。

## 用例与真实边界

Session 五项：正常删除和 After 钩子抛异常时，首个 Session 析构等待另一个线程取得读锁；全部 1000 个实例必须释放。续期、同 ID 替换在清理进入写锁前完成，保留新状态；清理持写锁时另一线程续期必须等待。调用真实 `TSessions` 和真实过期判断，测试宏只开放同步清理入口及既有清理间隔选项。测试调用方按现有约定持写锁修改 Session，不声称无锁修改可与清理竞争。

客户端六项均使用真实 TCP、解析器和连接池，测试宏仅停止自动定时器、同步调用扫描及在候选收集后门控：

| 用例 | 收集后发生的变化或对照 |
| --- | --- |
| idle-reuse | 空闲候选实际被第二个请求复用，第二个响应仍须 200，同一连接保持打开。 |
| request-progress | 请求候选收集后，对端再发一字节；自定义响应流确认已进入真实解析路径，旧候选不得中断正文。 |
| request-reuse | 候选收集后首个响应完成，再在同一连接发第二个请求，不能清空第二个请求字段或将其判为超时。 |
| idle-reserved | 第二个请求停在 Init 回调，连接已被预占但状态仍 idle；超过 idle 时限后不应收集或关闭它。 |
| idle-expire | 真正空闲过期必须实际断开 TCP，下一请求使用新连接。 |
| request-expire | 真正请求超时必须实际断开 TCP，仅通知一次 408。 |

连接建立超时使用同一当前状态重验逻辑，但未用外部网络 SYN 黑洞复现连接建立时限；不把上述回环案例记作这一平台边界的运行验证。

Epoll 八项：成功批次、成功回调重入、成功回调抛异常、全取消、混合 nil 回调、全 nil 回调、取消回调抛异常、取消回调跨线程重入。每项 1000 条，逐项检查顺序/次数/结果及回调捕获析构计数；跨线程 Send 必须及时返回一次 False，证明取消通知没有持发送队列锁。辅助线程显式捕获对象，避免本机 FPC 构造器匿名线程隐式 Self 捕获导致的测试门控失效。

相邻 `QueueFifoTests/run_socket.py` 覆盖真实 EAGAIN、部分写后恢复和取消；`SocketCallbackTests` 覆盖事件异常、同批继续、关闭竞争及真正注册失败。Kqueue 只有编译验证，未运行 macOS/FreeBSD，不改变 F05 注册引用算法。

## 红绿与最终结果

- 基线 Client：Delphi/FPC Win64 各 **4 失败、2 通过**。四个竞争用例失败，两个真正超时对照通过；保存于 `bin/client-before/<target>/client-results.json`。快照保持原算法，只加入同样的测试入口；修复前后测试 Pascal 源一致。
- Session 与 Epoll 原算法的功能用例本来通过，这两部分主要消除重复数组增长；不把性能用例伪称正确性红例。
- Release `bin/final`：Delphi Win64/Win32、FPC Win64、Delphi/FPC Linux64 各 Session 5/5、Client 6/6；Linux 两目标各 Epoll 8/8，共 **71/71**。
- DEBUG 最后补修：`bin/final-debug` 的 Delphi/FPC Win64 Client 各 6/6，共 **12/12**。此前 Release 矩阵的 Client SHA-256 为 `d51858f993ad0793b2613f06b81e5a511de647cb4ca211951673f383037aa37d`；最终 Client 为 `82e5d71a3f8873259b9fb65cd40f45ff1fde78e3e49efa4f99912617073b19d2`，这次增量全部位于 DEBUG 条件块，未重复性能采样。
- 相邻回归：HTTP 客户端定界 Delphi/FPC Win64 44/44；Linux SocketCallbackTests 44/44；QueueFifoTests 真实 EAGAIN 两目标 12/12。DEBUG 增量后重新构建不含测试宏的客户端两目标，各再运行正常复用、请求 close、EOF 定界三项，共 6/6。
- Kqueue Delphi OSX64/OSXARM64 两次编译通过，仅编译，不计入运行测试数。

## 测量口径

所有数字为微秒。每组保留第一个独立进程样本但不纳入统计，之后五个样本取中位数；这不代表每个后续进程内部都已经预热。Windows Session 线程固定在 CPU 掩码 4，Linux 在 WSL Ubuntu 22.04 中运行，未设置 affinity。前后采样窗口没有其他代理执行性能采样；测试不是部署负载。

Session 使用真实过期项。对象构造、填表在计时外；total 覆盖调用清理、锁获取、收集、删除及锁外最终析构；lock 是成功取得写锁后到解锁前的实际持锁时长，不含等锁；collect 从 Before 钩子到 RemoveSessions 入口，包含真实过期判断；remove 是实际字典删除时间。**没有测 HTTP 请求 P99、客户端扫描单独吞吐或全进程峰值**。下列是首轮全表预留实现的历史数据；最终稀疏分配、RTL 申请计数和连续扫描 P99 见后面的补修记录。

10000 个过期 Session：

| 平台 | total 前→后（IQR 前→后） | lock 前→后 | collect 前→后 | remove 前→后 |
| --- | --- | --- | --- | --- |
| Delphi Win64 | 5171.1→3377.1（639.0→78.3） | 3556.9→1929.2 | 2472.3→1209.0 | 921.2→714.2 |
| FPC Win64 | 4262.2→4010.7（482.2→293.5） | 2944.3→2501.1 | 1641.7→1226.4 | 1302.9→1284.7 |
| Delphi Linux64 | 8315.682→6567.357（506.281→603.385） | 6134.634→4714.841 | 5047.933→3579.801 | 1113.761→1152.089 |
| FPC Linux64 | 9841.748→8858.146（283.895→415.905） | 7882.936→6906.624 | 6026.687→5121.584 | 1958.264→1784.840 |

各深度的实际写锁时长：

| 平台 | 0 | 1 | 100 | 1000 | 10000 |
| --- | --- | --- | --- | --- | --- |
| Delphi Win64 | 2.4→1.8 | 2.0→1.8 | 29.3→17.5 | 272.4→182.2 | 3556.9→1929.2 |
| FPC Win64 | 1.6→1.4 | 2.6→2.5 | 32.8→25.2 | 290.7→227.9 | 2944.3→2501.1 |
| Delphi Linux64 | 1.313→1.398 | 175.764→183.813 | 262.840→212.909 | 819.628→587.346 | 6134.634→4714.841 |
| FPC Linux64 | 1.025→1.003 | 176.002→175.070 | 260.930→232.820 | 958.741→860.929 | 7882.936→6906.624 |

Epoll write 计时从释放接收回调门控到完成事件返回，包含 epoll 调度、实际 send 系统调用、回调收集、通知及捕获释放；每项只有一字节。观察到深度 10000 的五个样本均在同一事件内完成全部回调。cancel 从调用 Close 到返回，包含关闭事件、清队列、失败通知、捕获释放及关闭句柄。**这不是纯数组收集时间或网络 P99**。

| 平台/路径 | 1 | 100 | 1000 | 10000 |
| --- | --- | --- | --- | --- |
| Delphi Linux write | 71.762→80.830 | 454.726→428.989 | 2410.853→2341.054 | 24058.010→20321.087 |
| FPC Linux write | 71.810→72.936 | 408.713→394.847 | 2172.273→2254.602 | 20064.580→20361.293 |
| Delphi Linux cancel | 41.360→41.116 | 57.966→56.568 | 228.233→182.673 | 2193.832→1634.669 |
| FPC Linux cancel | 38.455→41.343 | 55.248→50.656 | 166.558→148.826 | 1502.398→1222.285 |

大批取消与 Session 收集有实测收益；真实成功发送并非各组都变快（FPC 深度 1000 为 +3.8%，10000 为 +1.5%；单项 Delphi 为 +9.068us）。本轮未隔离系统调用/调度噪声或做显著性检验，不能把这些小幅变化全归于容器，也不能声称统一吞吐提升。原数组扩容成本取决于 RTL/分配器是否原地扩展，不根据源码直接宣称测到了平方曲线。

Windows 前后基准在 `bin/before`/`bin/after`，测试 LPR 哈希前后一致；Linux 前后在 `bin/before-final`/`bin/after-final`，同样使用相同 LPR/include。这些原始全过期基线保持不覆盖；之后 Session 改为惰性几何增长，新增结果单独记录，Epoll 被测实现与计时区间未改。每组目录保留 source.json、原始 samples、构建日志和结果。最终 Params/Epoll/Kqueue SHA-256 分别为：

```
3cd2a876be7b0b45dee677b9876793f3d14cb5a942b4436db5794b6e1ec7701f
bc66819a1dc6958be266adf2e860bf2253efb6e40b78a28537948cf5f31fc755
068c2c184bee993693bce8a7b9707cd65527b145e6a54ed66adb038d139fa658
```

## Session 稀疏分配补修（最终实现）

复核发现首轮按总条目数预留会使 10000 个活跃会话、零过期也申请整表数组。最终改为首次过期分配最多 8 槽，满后倍增，容量始终不超过总条目数，最终按有效数量收缩；原有锁边界、钩子和异常释放不变。`bin/sparse-before/production/Net.CrossHttpParams.pas` 保存首轮全表预留快照（SHA `7126729aabbbe5546518375dd17ab82b23e4aa41fa03cb6743b84423fdef5831`），没有覆盖最初逐项拼接的 `bin/before` 基线。

`SESSION_ONLY` 构建排除 Client/Socket/TLS 测试依赖，本次仅重验 Session。最终 `bin/sparse-final/<target>/` 五目标生命周期回归 **25/25**、0/1 过期的分配边界检查 **10/10**；原全表预留版本在两个 Windows 目标的四个稀疏边界均不满足 `<4096` 字节单次申请约束。0/1/100/1000/10000 全过期复测保存在 `bin/sparse-after/<target>/benchmarks.json`，原全过期基线仍完整保留。

时间与分配在独立进程中测量，计时进程不安装 MM hook。分配进程统计扫描线程的 RTL GetMem/AllocMem/ReallocMem 请求，threadvar 排除后台清理线程；数字是累计请求字节和最大单次请求，**不是进程峰值、OS 分配或仍占用内存**。剩余少量申请来自枚举等操作，不能把零快照分配表述为整个扫描零分配。

| 目标 | 0过期累计请求字节 前→后 | 1过期累计请求字节 前→后 | 最大单次请求 前→后（0/1过期） |
| --- | --- | --- | --- |
| Delphi/FPC Win64、FPC Linux64 | 80048→32 | 80072→136 | 80016→32 / 80 |
| Delphi Linux64 | 80064→40 | 80088→152 | 80016→32 / 80 |

Delphi Win32 最终为累计 16/68 字节，最大单次 16/40 字节；未额外建立 Win32 稀疏分配基线。

为避免独立进程启动和主机频率变化影响结论，最终另做 1 对剔除样本加 9 对前后交替测量（次序每轮互换），原始结果在 `bin/sparse-final/<target>/paired-sparse.json`。这里“前”是全表预留，“后”是几何增长；两版测试 Pascal 源一致。以下为总清理时间中位数（括号内 IQR），单位微秒：

| 目标 | 过期数量 / 总数10000 | 前 | 后 |
| --- | --- | --- | --- |
| Delphi Win64 | 0 | 1144.500（57.300） | 1130.800（54.800） |
| Delphi Win64 | 1 | 1142.700（15.400） | 1147.500（155.000） |
| Delphi Win64 | 10000 | 3042.000（152.800） | 3027.700（330.100） |
| FPC Win64 | 0 | 1269.600（71.800） | 1282.200（30.600） |
| FPC Win64 | 1 | 1281.200（80.500） | 1307.700（38.400） |
| FPC Win64 | 10000 | 3590.000（160.600） | 3537.600（176.500） |
| Delphi Linux64 | 0 | 3235.200（278.937） | 3158.463（179.904） |
| Delphi Linux64 | 1 | 3095.558（273.574） | 3052.707（275.203） |
| Delphi Linux64 | 10000 | 7307.084（620.912） | 6894.113（639.430） |
| FPC Linux64 | 0 | 5792.801（763.172） | 5862.850（445.488） |
| FPC Linux64 | 1 | 5601.207（603.420） | 5537.465（178.863） |
| FPC Linux64 | 10000 | 8706.649（738.388） | 8903.799（1129.315） |

此调整明确减少稀疏扫描的申请规模，没有声称每组扫描都更快：FPC Win64 0/1 过期总耗时分别约 +1.0%/+2.1%，FPC Linux 全过期约 +2.3%；这些差异小于对应样本 IQR。这里没有做显著性检验，也不据此强行断言一定只是噪声。几何扩容保留了满匹配路径的少量容量检查/扩容成本，避免了零/稀疏匹配的全表预留。

尾延迟另用同进程 10000 个活跃会话、0 过期，先连续预热 10 次，再记录 100 次真实扫描。每次记录成功获取写锁后至解锁前的时长，以及整个清理调用时长；P99 使用 nearest-rank，即 100 个样本排序后的第 99 个。输出全部原始样本，未用五样本基准估算 P99。结果在 `bin/sparse-before-tail/<target>/tail.json` 与 `bin/sparse-final/<target>/tail.json`，单位微秒：

| 目标 | 持锁中位数 前→后 | 持锁P99 前→后 | 总清理P99 前→后 |
| --- | --- | --- | --- |
| Delphi Win64 | 1143.250→1114.650 | 1567.400→1515.400 | 1568.600→1516.400 |
| FPC Win64 | 1152.800→1147.900 | 1213.900→1193.800 | 1215.100→1195.000 |
| Delphi Linux64 | 3253.039→3017.173 | 3604.083→3232.897 | 3605.514→3234.019 |
| FPC Linux64 | 5294.271→5076.340 | 6541.448→5367.806 | 6549.320→5369.540 |

以上仅是本次环境的清理/持锁尾延迟，**不是 HTTP 请求 P99，也不是生产负载尾延迟保证**。此轮不重跑未改变的 Client/Epoll 测试；它们保留前述证据。最终 Params 源及 Session 测试源与五目标 `source.json` 一致，BOM/CRLF 和差异检查通过。

复现本轮：

```powershell
python run_tests.py win64 win32 fpc64 fpc-linux64 linux64 --label sparse-final --session-only --build-only
python run_tests.py win64 win32 fpc64 --label sparse-final --run-only --regression-only
python run_tests.py win64 win32 fpc64 --label sparse-final --run-only --sparse-only --check-sparse-alloc
python run_tests.py win64 fpc64 --label sparse-final --run-only --tail-only
```

Linux 使用相同 `--run-only` 选项在实际 Linux 中运行 `fpc-linux64 linux64` 两目标；前版编译额外指定 `--source bin/sparse-before/production`，另设标签，保留证据不覆盖。

## 运行

使用现有工具链，产物仅写 bin/lib。Windows 在本目录运行：

```powershell
python run_tests.py win64 win32 fpc64 fpc-linux64 linux64 --label final --build-only
python run_tests.py win64 win32 fpc64 --label final --run-only --regression-only
python run_client.py bin/final/win64/BatchCleanupTests.exe --output bin/final/win64/client-results.json
python run_tests.py win64 fpc64 --label final-debug --debug --build-only
python run_client.py bin/final-debug/win64/BatchCleanupTests.exe --output bin/final-debug/win64/client-results.json
```

其余目标替换可执行文件路径。在真实 Linux 中执行交叉构建产物：

```sh
python3 run_tests.py fpc-linux64 linux64 --label final --run-only --regression-only
python3 run_client.py bin/final/fpc-linux64/BatchCleanupTests --output bin/final/fpc-linux64/client-results.json
python3 run_socket.py bin/final/fpc-linux64/BatchCleanupTests --regression-only --output bin/final/fpc-linux64/socket-results.json
```

`run_tests.py --bench-only --run-only` 运行 Session 计时，`run_socket.py` 不加 `--regression-only` 时运行真实发送/取消计时。前后源码快照通过 `--source <directory>` 优先编译，source.json 记录实际使用内容的哈希。基线目录必须另存原算法和相同测试宏入口，不能把当前源码重新编译到 before 标签后当作红基线。

每个测试进程有超时并等待回收；TCP 对端、输出读取线程及管道在 finally 中清理。没有后台测试服务，没有修改全局环境或第三方 RTL。
