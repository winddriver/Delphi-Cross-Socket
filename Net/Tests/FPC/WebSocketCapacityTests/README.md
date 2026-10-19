# WebSocket 发送队列容量与长度边界

对应 O03 的 WS 部分。仅新增具体类配置，原 WS 接口 GUID、方法及 vtable 保持；旧调用默认不限。没有共享调度器、后台线程或新的公共继承层。

## 配置与超限行为

`Net.CrossWebSocketSender.TWsSendQueueLimits` 的四项均为 `Int64`，0 表示该项不限，负数抛出 `EArgumentOutOfRangeException`。通过两端具体连接类的 `SetWebSocketSendQueueLimits` 配置，或直接配置 Sender 的 `SetQueueLimits`。配置时必须没有排队、在途、构帧或正在运行的发送泵，且发送器/连接没有关闭；否则抛出 `ECrossSocket`。建议在 WS 握手完成、开始业务发送前设置。

```pascal
var
  LLimits: TWsSendQueueLimits;
begin
  LLimits := Default(TWsSendQueueLimits);
  LLimits.MaxMessageCount := 128;
  LLimits.MaxMessageBytes := 8 * 1024 * 1024;
  LLimits.MaxControlCount := 16;
  LLimits.MaxControlBytes := 4096;
  // AConnection 是具体的 TCrossWebSocketClientConnection
  // 或 TCrossWebSocketConnection；不是已有的 WS 接口。
  AConnection.SetWebSocketSendQueueLimits(LLimits);
end;
```

- 消息数包括构帧中、排队、当前分块消息和物理在途消息，同一项只计一次；控制帧及 Close 单独计数。完整消息在复制/编码前原子预留数量和字节，不会先分配大帧再判超限。
- 字节数统计本层预留、持有的**编码后帧**，包含帧头及客户端掩码。它不包括 provider 自己分配的源缓冲、闭包捕获对象、下层 TLS/Socket 缓冲或进程总内存。仅设置字节上限不能限制尚未产生帧的 provider 数量，需要同时设置消息数量上限。
- 完整数据消息入队前超限：一次 False 通知，健康连接可继续使用；拒绝通知自身抛异常会按既有同步通知规则传播，不因此关闭连接。编码或随机掩码失败仍走原发送失败收尾。
- provider 入队仅预留消息数，不提前调用它。轮到当前帧时先检查最小帧头预算，再读取并在复制/编码前检查实际帧大小。每帧物理完成后归还帧字节，整条消息结束才归还消息数。provider 已接纳后任何一帧额度不足都会关闭连接、取消剩余消息，避免发送不完整的分片序列后继续拼接下一条消息；包括第一帧超额。
- 控制帧或 Close 预算不足时直接关闭连接，不丢弃控制帧后继续使用。底层已关闭时直接取消队列，不再创建额外 Close 项。关闭仅取消尚未发出的内容，在途帧仍保活到物理完成；此前在途的完整消息/最终帧沿用物理结果结算规则。
- 完成/取消先一次归还预算，再清理引用和执行通知；通知可以重入。构帧、取数和用户完成通知均不持有 Sender 队列锁；这不代表调用链没有外层接收锁。

默认四项均为 0 时复用原有接纳锁，不增加正常完成路径的预算锁或包装闭包；仍有构帧状态与条件判断，不宣称零指令开销。本专项没有性能速度提升或进程峰值内存测量结论。

`MakeFrameData` 对非 nil 实体数据，按实际帧头长度在任何 `Integer` 窄化/分配前检查上限；例如声明 `2^32+1` 的实体载荷会受控拒绝，不能绕回 1 字节。nil 数据保留原有仅生成帧头的能力，包括大于 32 位的长度。Sender 仍保留已有的 `High(Integer)-14` 实体长度限制，没有放宽发送 API 的可用帧大小。

## 夹具及覆盖

专项使用真实 Sender 和帧编码，仅物理连接由夹具控制完成时机。每项独立进程、15 秒超时；并发测试使用事件屏障，不靠长 Sleep 争取概率。覆盖精确 count/bytes 边界、客户端掩码开销、provider 不预读与中途超限、控制/Close 预算、在途晚完成、重复物理完成、重入与异常、512 次固定队列深度、16 个并发发送者竞争 4 个名额、125/126/65535/65536 帧头边界、Int64 大额度和底层同步拒绝/异步失败。

`CROSS_WS_SENDER_SELFTEST` 仅用于观测预算以及注入构帧/随机掩码失败、阻塞构帧窗口。关闭该宏仍运行 31 项生产入口回归；没有把测试 getter 或故障开关加入正式构建。未知 provider 源缓冲的内存不由本测试或限额管理。

另复用既有 WS 流工程，通过两端具体连接配置有限队列后，重新运行普通流短读、提前 EOF、Read/Size/Seek 异常、排队取消和借用所有权用例；旧版流缺陷的原始红绿报告保持不变。组件及真实 TCP/101 回归从原测试源重新构建到本目录隔离输出，未修改共享回环测试代码。

## 2026-10-20 验证记录

五目标为 Delphi 13.1 Windows Win64 / Win32、FPC 3.3.1 Windows Win64、Delphi 13.1 Linux64、FPC 3.3.1 Linux64；Linux 程序实际在 Ubuntu 22.04 WSL 执行。

| 每个目标 | 原版首轮 | 最终版 |
| --- | --- | --- |
| 首轮容量/实体长度断言 | 4/13 通过、9 失败 | 包含在 36/36 中 |
| 完整专项（含测试入口） | 后续新增断言未回跑原版 | 36/36 |
| 关闭测试入口的生产分支 | 不适用 | 31/31 |
| 双端普通流，默认不限 | 沿用原流专项基线 | 24/24 |
| 双端普通流，开启限额 | 不适用 | 24/24 |
| 原 Sender 队列/寿命专项 | 沿用原专项基线 | 23/23 |
| 真实 TCP 服务端/客户端 | 沿用原专项基线 | 8+3 场景通过 |
| 真实 101 握手 | 沿用原专项基线 | 47/47 |

最终专项合计 180 项含测试入口、155 项无入口；双端流两模式合计 240 项。帧组件还输出每目标 `61 passed` 及 `11056` 个合法帧/拆包组合通过，其余严格解析/兼容/回调和 Sender 组件也通过；这些属于组件断言，不混作独立进程或 TCP 场景计数。Windows 32 位旧 Sender 专项使用原有 `__LITTLE_PIECE__` 分块构建。

首轮红基线仅有 13 项，默认、不跨额度的 provider 帧、Close 等待和 nil 大长度帧头共 4 项通过，其余 9 项揭示原版没有容量限制及实体长度窄化问题。不能把后来补齐的 36 项都称为已做原版红测。基线程序及当时四生产单元快照保存在 `bin/baseline-*/` 和 `bin/baseline-source/`，报告为 `bin/red-*.json`。

集成期间旧 Sender 的精确销毁计数曾在三个 Windows 目标各出现 21/23：底层已关闭仍额外创建 Close 项，导致计数多 1；并非未释放旧队列项。修正后旧套件五目标均为 23/23，容量和普通流也基于该最终修正重新全量构建。中间结果保留，不覆盖红证据。

最终证据标签：本目录 `bin/final2-*`、`bin/release-final2-*`、`bin/regression-final-*`；流目录 `bin/o03-final-default-*`、`bin/o03-final-capacity-*`；旧 Sender 目录 `bin/sender-o03-capacity-final/`。`source.json` 记录各构建实际记录的源码哈希，运行 JSON 记录可执行文件哈希与结果；`bin/final-source.json` 汇总冻结生产/测试源、二进制、报告及原版快照。共享依赖随其他任务推进，不把整份可执行文件称为某个原始 HEAD 的产物。

## 重现命令

从本目录运行，使用仓库现有 Delphi/FPC、Lazarus、CNcrypto、Linux SDK 和 WSL；不安装依赖。构建目录按目标/标签/宏隔离，Pascal 源码为 UTF-8 BOM / CRLF。

```powershell
python -B build_tests.py delphi-win64 delphi-win32 fpc-win64 delphi-linux64 fpc-linux64 --label final2 --limits
python -B build_tests.py delphi-win64 delphi-win32 fpc-win64 delphi-linux64 fpc-linux64 --label release-final2 --limits --no-selftest
python -B run_tests.py bin/final2-delphi-win64/WebSocketCapacityTests.exe --report bin/final2-delphi-win64.json
python -B run_tests.py bin/release-final2-delphi-win64/WebSocketCapacityTests.exe --report bin/release-final2-delphi-win64.json --no-selftest
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/WebSocketCapacityTests -- python3 -B run_tests.py bin/final2-fpc-linux64/WebSocketCapacityTests --report bin/final2-fpc-linux64.json
python -B build_regressions.py delphi-win64 delphi-win32 fpc-win64 delphi-linux64 fpc-linux64
python -B run_regressions.py delphi-win64 delphi-win32 fpc-win64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/WebSocketCapacityTests -- python3 -B run_regressions.py delphi-linux64 fpc-linux64
```

其余专项目标替换命令中的目标名；Linux 无入口运行同样加 `--no-selftest`。普通流矩阵命令见[流测试补充](../WebSocketStreamTests/README.md#o03-容量集成回归)。旧 Sender 使用原目录 `run_sender_tests.py` 的标签 `o03-capacity-final`：Windows 运行 `win64 fpc64 win32-pieces`，Linux 先在 Windows `--build-only` 后在 WSL `--run-only`。

本轮实测了普通 TCP 回归及模拟下层拒绝，没有把它描述成真实 TLS+WS 双层限额联合压力验证。没有 macOS/Kqueue、MbedTLS、移动端、长期压力或进程内存上限保证；这些不因本层配额通过而自动成立。
