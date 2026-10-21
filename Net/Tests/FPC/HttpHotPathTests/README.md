# HTTP 热路径回归与微基准

范围：token 查询、重复头字段查询、路由快照、请求容器按需创建。所有修改保持头体分离发送。

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
