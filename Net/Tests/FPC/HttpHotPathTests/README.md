# HTTP 热路径回归与微基准

范围：token 查询、重复头字段查询、路由快照。请求容器按需创建已取消，所有修改保持头体分离发送。

构建沿用相邻 HttpFailureTests 的 Delphi/FPC 路径；Pascal 源文件使用 UTF-8 BOM。

```powershell
python Net/Tests/FPC/HttpHotPathTests/run_tests.py --label p1-before --cases tokens
python Net/Tests/FPC/HttpHotPathTests/run_tests.py --label p1-after --cases tokens --before p1-before --benchmarks tokens
```

可使用 `--source-root` 指定包含修改前单元的目录，优先读取该目录而不覆盖工作区。
`--checked` 开启范围和溢出检查；Checked 构建不用于性能对比。

微基准固定在同一个逻辑 CPU；第一轮预热不计入统计，之后前后版本交替五轮。
分配次数另行安装 RTL 统计包装测量，不计入正常计时；结果保存在 `bin/<label>/<target>/`。
只把微基准解释为对应操作成本，端到端吞吐须另用真实 HTTP 服务测量并确认零错误。

## P1：ContainsToken（2026-10-21）

三目标普通及 Checked 构建各通过 13,543 条比较；相邻 HttpFailureTests 的连接策略/真实 TCP 回归 28/28 通过。

| 目标 | 修改前 us | 修改后 us | 下降 | 每万组三次查询分配 |
| --- | ---: | ---: | ---: | ---: |
| Delphi Win64 | 187039.9 | 34290.1 | 81.7% | 70000 → 0 |
| Delphi Win32 | 149969.8 | 32092.6 | 78.6% | 70000 → 0 |
| FPC Win64 | 666331.063 | 401573.813 | 39.7% | 70000 → 0 |

时间为 30 万组操作的五轮中位数，不是 HTTP RPS。测试同时保留了旧算法作为独立语义参照。

## P2：GetHeaderValues（2026-10-21）

`--label p2-after --cases tokens headers --before p2-before --benchmarks missing present duplicates`，三目标 headers 各 4008 条通过，普通及 Checked 均通过；相关协议回归 27/27。

| 目标 | 无匹配修改前 us | 修改后 us | 下降 | 每万组分配 |
| --- | ---: | ---: | ---: | ---: |
| Delphi Win64 | 37761.2 | 19436.0 | 48.5% | 20000 → 0 |
| Delphi Win32 | 29276.9 | 16751.5 | 42.8% | 20000 → 0 |
| FPC Win64 | 274609.219 | 258916.406 | 5.7% | 20000 → 0 |

单匹配耗时下降 2–9%；重复匹配基本持平，Win32 中位数慢 1.8%，但返回数组申请字节减少。所有原始时间范围保存在 benchmarks.json，不将小差异解释为确定收益。

## P3：路由处理器快照（2026-10-21）

三目标正常/Checked 验证处理器顺序、Handled/Sent 短路、回调中注册、闭包释放；四个执行线程各执行 3000 次，与 64 次追加注册并发。相邻 HTTP 队列/真实 TCP 回归 24/24 通过。

| 目标 | 30 万次执行修改前 us | 修改后 us | 下降 | 每万次分配 |
| --- | ---: | ---: | ---: | ---: |
| Delphi Win64 | 104942.8 | 88521.4 | 15.6% | 10000 → 0 |
| Delphi Win32 | 132788.3 | 119943.5 | 9.7% | 10000 → 0 |
| FPC Win64 | 143307.297 | 108361.102 | 24.4% | 30000 → 0 |

注册改为复制并发布独立数组；动态路由频繁追加的成本由注册方承担。原有请求取得快照的锁及处理器调用顺序不变。

## 仅保留前三项的整体复测（2026-10-21）

基线97ce754，对照c2cca8b（含前三项优化，第四项已撤回）。正式示例使用临时副本，统一 HTTP、18080端口、FastMM5及默认65个I/O线程；原工程和头体分离发送不变。

每个版本：1000并发，ab预热2万后测10万请求，Bombardier测15秒，前后顺序交替五轮。ab合计100万测量请求、Bombardier合计14421766次请求，全部成功；响应210字节、正文78字节。

| 五轮中位数 | 优化前 | 仅前三项 | 变化 |
| --- | ---: | ---: | ---: |
| ab，请求/秒 | 33520.10 | 33404.95 | -0.34% |
| Bombardier，请求/秒 | 97035.25 | 96245.62 | -0.81% |
| Bombardier P99，毫秒 | 13.672 | 13.790 | +0.86% |
| 服务端CPU时间，微秒/成功响应 | 125.337 | 123.454 | -1.50% |

本次整体吞吐没有显示明确提升；微基准中的分配和时间改善不能直接换算为RPS。各轮结果存在波动，CPU时间也只是进程累计时间，不是调用栈采样。五轮原始数据、源码哈希见 [FOLLOWUP_RESULTS.json](FOLLOWUP_RESULTS.json)。

```powershell
python Net/Tests/FPC/HttpHotPathTests/run_http_bench.py --label three-only-repeat --before 97ce754 --samples 5 --duration 15
```

## 低线程数连接拒绝的定位

诊断只修改 `bin` 内独立副本：增加接入计数及只读统计、通过命令行独立选择工作线程/AcceptEx预投数/backlog。生产IOCP、发送层和系统TCP设置均未修改。

1000并发、每次10秒，4个工作线程及4个AcceptEx预投：

| Windows backlog | 三次连接拒绝数 | 成功请求/秒范围 | 运行期已接入连接 |
| --- | --- | ---: | --- |
| SOMAXCONN，系统选择上限 | 296764 / 287836 / 292432 | 8300–12458 | 本组观测最高326–458 |
| SOMAXCONN_HINT(2048) | 0 / 0 / 0 | 43449–49221 | 稳定达到1000 |

所有样本的监听均保持存在，压测后新建连接成功；AcceptEx同步提交错误、异步完成错误及对应错误日志均为0。只修改backlog便消除拒绝，证据支持等待接入队列在此突发场景下承受不足。

辅助对照：只将预投数增加到65，仍有38288次初始连接拒绝；将请求速率限制为30000/s，只剩47次拒绝。默认65线程/65预投为零错误，成功吞吐约95545/s。扩容backlog解决此次接入失败，4线程的稳态处理能力仍低于默认线程配置。

失败样本不能直接把Bombardier显示的Reqs/sec当成功吞吐：例如第一次4线程样本显示42187，但实际2xx/time约12458/s，其余多数为失败尝试。

[Microsoft listen文档](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-listen)说明SOMAXCONN由服务提供程序选择合理上限，队列满可返回WSAECONNREFUSED；SOMAXCONN_HINT允许更大的队列。SDK宏为 `SOMAXCONN_HINT(b) (-(b))`。这里没有测得系统默认队列的精确容量，也没有把2048直接定为生产默认值。

```powershell
python Net/Tests/FPC/HttpHotPathTests/diagnose_accept.py --label accept-repeat --cases threads4 backlog2048 --samples 3 --duration 10
```

后续若修复接入策略，应先讨论Windows backlog的配置与兼容边界，再决定是否将预投接受数量与工作线程数量解耦；不涉及头体合并发送。本轮未提交、未推送，未做HTTPS、Linux/macOS验证。
