# 真实 TLS 与 WebSocket 容量传播回环

本专项连接原生 WS/TLS 服务端与 Python 标准库 TLS 客户端，经过真实本地 TCP、OpenSSL、101 升级及 WS 编解码。没有覆写物理发送、内存 transport 或返回伪造 False。仅测试本地 `127.0.0.1`，不安装依赖或修改证书/网络配置。

正常模式分别强制 TLS 1.2、TLS 1.3，双方校验协商版本，验证完整 101、一个小消息成功通知和 Close/线上 EOF。使用已有 `TlsCipherSuitesTests/bin/handshake-7da2cdf00d4746348af6e7865b93e945/rsa-cert.pem` / `rsa-key.pem` 测试材料，客户端把该证书作为本地信任锚，并保持 `CERT_REQUIRED` 与 `localhost` 主机名检查。证书过期后应重新运行原证书生成流程或用 `--cert` / `--key` 指定新的有效测试材料，不能关闭验证绕过错误。

限额模式在监听、接纳新连接**之前**配置具体类 `MaxPendingSendBytes := 4096`；底层按新连接快照，不能在握手后改 owner 属性并声称已有连接限额改变。4KiB 容纳本例证书的握手和小消息，大 WS 帧为 64KiB。在 provider 首次实际取数时先将尾消息排入 Sender，再返回大数据，以确定地覆盖排队取消；没有靠发送速度或长 Sleep 制造竞争。预期为底层拒绝后 TLS 终止、主消息 False 一次、尾消息 False 一次、provider 不再读取，以及对端线上 EOF。WS/TLS 自身额度保持默认，避免把上层先拒绝误当底层生效。

完成和关闭回调只记数/发事件，父进程确认网络结果后通过标准输入释放原生主线程，再由主线程 Stop；不在 I/O 回调同步停止服务器。独立子进程和所有网络/事件等待均设超时。

## 当前验证

2026-10-20，Delphi 13.1 / FPC 3.3.1 的 Windows Win64 和 Linux64 四目标，各 TLS 1.2、TLS 1.3 正常模式 2/2，共 8/8 实际通过。Linux 在 Ubuntu 22.04 WSL 执行；正常构建标签为 `normal`，Base/三后端来自当时已提交 HEAD 的 `bin/normal-base-source/` 快照，避免读取并行实现的中间态。其他源码来自共享工作区，各 `source.json` 记录实际依赖，不能把完整二进制称为单一历史提交的产物。

随后基于 Base/后端完整可编译点，四目标各 TLS 1.2、TLS 1.3 的正常/限额四项全部通过，共 **16/16**，标签为 `limits`。开启 `CROSS_CAPACITY_TESTS` 后只观测真实 Reserve 拒绝与剩余额度，没有改变发送返回值或调度。四目标结果一致：

| 场景 | 小消息 | Base 实际拒绝 | WS 主消息 / 尾消息 | provider / 关闭 | 最终 Base 额度 |
| --- | --- | --- | --- | --- | --- |
| TLS 1.2 正常 | True 一次 | 0 次 | 未发送 | 0 次 / 1 次 | 0 项 / 0 字节 |
| TLS 1.3 正常 | True 一次 | 0 次 | 未发送 | 0 次 / 1 次 | 0 项 / 0 字节 |
| TLS 1.2 限额 | True 一次 | 65,691 字节，1 次 | 各 False 一次 | 1 次 / 1 次 | 0 项 / 0 字节 |
| TLS 1.3 限额 | True 一次 | 65,656 字节，1 次 | 各 False 一次 | 1 次 / 1 次 | 0 项 / 0 字节 |

拒绝钩子确认被拒的是同一真实 WS 连接上的底层密文；Python 对端在大消息后直接观察到线上 EOF，没有收到大帧或尾消息字节。测试不把准备阶段正常 8 项重复加进最终 16 项，不把正常准备描述为缺陷红基线。`bin/final-source.json` 汇总八个阶段二进制、各实际源码元数据和运行报告哈希；TLS/Base 实现仍由其他任务负责，本目录不修改生产源码。

该专项不覆盖原生 WS 客户端方向、长期压力、全密码套件、MbedTLS 或 Kqueue 运行时。Linux 使用系统 OpenSSL 3，Windows 使用仓库 OpenSSL 3 x64；没有把本结果扩大为所有 TLS 库版本保证。

## 构建与运行

从本目录运行，使用项目现有工具链。生产代码无测试修改，Pascal 源码为 UTF-8 BOM / CRLF。

```powershell
python -B build_tests.py delphi-win64 fpc-win64 delphi-linux64 fpc-linux64 --label normal --source-dir bin/normal-base-source
python -B run_tests.py bin/normal-delphi-win64/WebSocketTlsCapacityTests.exe --report bin/normal-delphi-win64.json --normal-only
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/WebSocketTlsCapacityTests -- python3 -B run_tests.py bin/normal-fpc-linux64/WebSocketTlsCapacityTests --report bin/normal-fpc-linux64.json --normal-only
python -B build_tests.py delphi-win64 fpc-win64 delphi-linux64 fpc-linux64 --label limits --base-limits
python -B run_tests.py bin/limits-delphi-win64/WebSocketTlsCapacityTests.exe --report bin/limits-delphi-win64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/WebSocketTlsCapacityTests -- python3 -B run_tests.py bin/limits-fpc-linux64/WebSocketTlsCapacityTests --report bin/limits-fpc-linux64.json
```

其余目标替换目标名。限额构建使用 `--base-limits`，运行不加 `--normal-only`，每目标执行两个 TLS 版本的正常/限额共四项。Windows 默认使用仓库 OpenSSL 3 x64 DLL，Linux 默认 `libssl.so.3` / `libcrypto.so.3`；可通过 `--ssl` / `--crypto` 显式指定匹配目标位数的库。

## 最终 Base 默认路径拆分后的复验

最终 Base SHA-256 为 `1dea20133be770f6cc998a08973fa8fa35884f27b35553b9f349474b138e7af8`。仅默认路径的局部处理发生拆分，三后端保持上一轮版本。以新标签 `final-base` 完整重编四目标后，上述正常/限额 **16/16 再次通过**；拒绝字节数、一次 False/取消、provider 停读、线上 EOF 和最终 0/0 额度均与上表一致。正常模式覆盖默认双 0 路径，限额模式覆盖实际预留/拒绝路径。

本轮没有重复未变的 Sender/帧/流大矩阵，也没有修改测试断言或生产源码。首版 `normal`、`limits` 二进制、报告及 `bin/final-source.json` 保留；新的四个二进制与结果在 `bin/final-base-*`，独立清单为 `bin/final-base-source.json`。重现时把前述限额构建和运行命令的 `limits` 标签替换为 `final-base` 即可。
