# WebSocket 已知长度流发送回归

对应 S01 的完成通知与失败契约，不增加原审查 30 条计数。仅修正 Client/Server 的普通 `TStream` 读取适配：仍有预期字节而 `Read <= 0` 时抛出 `EReadError`，交给已有 Sender 失败路径关闭连接并取消后续消息。合法正数短读继续发送；流仍由调用方持有和释放；`Size` / 初始 `Seek` 异常仍同步抛出且不发生发送完成通知。本批不搬移流适配、不修改 Sender/Parser。

专项使用真实双端 WS 连接、真实握手及帧编码，只替换网络建立与物理写入：客户端通过测试 Manager 的 `CreateHttpCli` 和 Socket 的 `Connect` 两个已有虚方法接入，真实 `WebSocket.Open` 发出请求并解析合法 101；服务端解析真实升级请求并发送 101。没有通过写私有字段或增加生产测试钩子跳过握手。

握手后用一个阻塞帧控制物理完成时机，普通流在轮到它之前不得 `Read`。完成每次物理写之前比较原发送缓冲区与复制的字节，验证在途寿命。解析实际 WS 帧（包括客户端掩码）恢复消息，检查内容、FIN、顺序和失败消息没有被完成。

双端各 12 项：声明 8 字节而实际只有 3 字节、负数读取结束、每次合法短读 1 字节、完整流、第一次/后续读取抛异常、排队流启动前取消且不预读、`Size`/`Seek` 同步异常、失败回调自身再抛异常、空流、offset/count 范围。失败时确认主回调 False 一次、关闭一次、后续字符串与流各取消一次、后续流读取次数为 0；正常路径及入队前异常不错误关闭。调用方最终释放流，发送器没有擅自取得流所有权。

每项在独立进程运行，外部超时 15 秒。测试不要求真实网络，也不替代既有 WS 回环、握手、控制帧和并发发送测试。

## 构建与运行

使用已有 Delphi/FPC、Lazarus、CNcrypto、Linux SDK 与 WSL，不安装依赖。各标签输出隔离；新旧可执行文件均全量重编，生产代码不需要测试宏。Pascal 文件使用 UTF-8 BOM / CRLF。

```powershell
python -B build_tests.py delphi-win64 delphi-win32 fpc-win64 delphi-linux64 fpc-linux64 --label final
python -B run_tests.py bin/final-delphi-win64/WebSocketStreamTests.exe --report bin/final-delphi-win64.json
python -B run_tests.py bin/final-delphi-win32/WebSocketStreamTests.exe --report bin/final-delphi-win32.json
python -B run_tests.py bin/final-fpc-win64/WebSocketStreamTests.exe --report bin/final-fpc-win64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/WebSocketStreamTests -- python3 -B run_tests.py bin/final-delphi-linux64/WebSocketStreamTests --report bin/final-delphi-linux64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/WebSocketStreamTests -- python3 -B run_tests.py bin/final-fpc-linux64/WebSocketStreamTests --report bin/final-fpc-linux64.json
```

修改前的首轮可执行文件保存在 `bin/baseline-*/`。进一步明确“启动前取消”后，同一组最终断言的红基线保存在 `bin/baseline2-*/`，用 `bin/baseline-source/` 中仅两份旧 Client/Server 单元快照重编；快照字节哈希已与原轮次记录核对一致，不回滚生产源码。构建目录 `source.json` 记录实际生产与测试源码哈希，运行 JSON 记录可执行文件哈希、每项输出和结果。工作区共享依赖可能包含其他任务的已稳定改动，不能把整个二进制描述为来自某一原始提交。

## 2026-10-19 红绿结果

| 目标 | 最终同组红基线 | 修复后 |
| --- | --- | --- |
| Delphi 13.1 Windows Win64 | 18/24 | 24/24 |
| Delphi 13.1 Windows Win32 | 18/24 | 24/24 |
| FPC 3.3.1 Windows Win64 | 18/24 | 24/24 |
| Delphi 13.1 Linux64 / Ubuntu 22.04 WSL | 18/24 | 24/24 |
| FPC 3.3.1 Linux64 / Ubuntu 22.04 WSL | 18/24 | 24/24 |

合计 120 项实际通过，没有跳过。每个目标红基线的 6 个失败来自双端的 EOF、负返回、EOF 后失败回调再抛异常场景：原版显示 `success=1 closes=0 following_reads=1`；最终显示 `success=0 closes=1 following_reads=0 error=EReadError`。原版已经正确处理的普通 Read 异常、合法短读、参数异常和排队取消没有计作本次缺陷。

最终报告为 `bin/final-<目标>.json`，同组红报告为 `bin/red2-<目标>.json`；`bin/final-source.json` 汇总 10 个红绿二进制、测试源码和实际生产单元哈希。重跑红基线预期非零，不能将其当作通过。

可用以下命令从已保存快照重建同组红基线，不覆盖最初保存的二进制：

```powershell
python -B build_tests.py delphi-win64 delphi-win32 fpc-win64 delphi-linux64 fpc-linux64 --label baseline2 --source-dir bin/baseline-source
```

本轮没有宣称真实 TCP/TLS、连接重建或长期并发压力覆盖；物理关闭由真实 Sender 调用测试连接的关闭实现来验证次数与状态。先前 Sender 的控制帧/并发/回环验证也不作为本专项重新运行的成绩。没有修改公开接口、流所有权、Sender 状态机或引入重构；后续 S03 收敛适配时可复用本组用例。
