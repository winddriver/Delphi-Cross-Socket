# SSL 信息读取与记录复用回归

对应本地计划 `docs/plans/2026-10-19-project-improvements.md` 的 F13 / A10.3。

本次有两个独立子项：

1. `GetSslInfo` 只使用成功取得的临时对端密钥，并在正常、异常路径释放原生引用。
2. `GetSslInfo` / `GetCertInfo` 重置复用的输出记录时，先正确释放旧字符串、数组及嵌套托管字段，不能直接 `FillChar` 丢失引用。

公开签名、加载引用计数及 `LoadSSL` 的 procedure/异常语义保持不变。

## 验证方式

沿用相邻 `OpenSslLoadTests` 的 Delphi/FPC 工具链及搜索路径；运行器不修改全局配置或第三方源码。所有编译文件、短期测试证书、日志和结果均放在本目录忽略的 `bin/`、`lib/`。

```powershell
python run_tests.py --label final3 --targets win64 fpc64 win32
python run_tests.py --label final111 --targets win64 fpc64 `
  --ssl D:\Design\Delphi\VclFmxRtl\zLib\Net\Demos\Delphi\HttpClient\bin\Win64\openssl1.1\libssl-1_1-x64.dll `
  --crypto D:\Design\Delphi\VclFmxRtl\zLib\Net\Demos\Delphi\HttpClient\bin\Win64\openssl1.1\libcrypto-1_1-x64.dll
```

`--targets` 可选择 `win64`、`fpc64`、`win32`，运行其他机器时修改脚本顶部的工具路径。`--ssl/--crypto` 必须成对指定且位数匹配。每个用例在独立进程运行，超时会终止并回收该子进程。未使用测试条件编译或生产测试钩子。

八个用例：

| 用例 | 验证内容 |
| --- | --- |
| no-key | 原生未握手查询返回 0，输出指针保持哨兵值；随后调用真实 `GetSslInfo` 不访问未取得的 key |
| failed-key | 让查询返回 0 且携带不可解引用的输出，确认必须检查返回值 |
| tls12 | 真实 TLS 1.2 内存 BIO 握手，客户端、服务端各复用同一输出记录查询 32 次 |
| tls13 | 真实 TLS 1.3 内存 BIO 握手，客户端、服务端各查询 32 次 |
| rsa-no-key | TLS 1.2 静态 RSA 套件，双方没有临时对端 key 仍可读取协议信息 |
| key-error | 取得真实 key 后注入字段读取异常，原异常保留，每个原生引用仍恰好释放一次 |
| ssl-reset | 128 次给 `TSslInfo` 的字符串、数组及嵌套证书字段分配数据，再用 nil 输入重置 |
| cert-reset | 128 次给 `TCertInfo` 的字符串、字节数组及嵌套字段分配数据，再用 nil 输入重置 |

握手实际运行 OpenSSL 状态机并交换加密握手数据，不替换加密操作；它使用内存 BIO，**不是本库 Socket 的网络回环测试**。固定 `X25519` 使临时密钥查询不受不同运行库默认混合组策略影响；静态 RSA 另行验证无 key。服务端 TLS 1.2 是否提供临时对端 key，以真实 API 返回值确定。

原生引用检查只观察 `SSL_get_peer_tmp_key` 成功输出对应的 `EVP_PKEY_free`，不把进程内存波动当作密钥引用证明。托管字段检查单独使用 nil 输入，不进入证书原生解析，通过 `GetHeapStatus.TotalAllocated` 衡量复用后的存量；允许不足 1 MiB 的运行库/分配器保留，但不能容忍基线约 25 MiB 的持续增长。本测试不宣称审计了其他证书信息辅助函数的全部原生资源。

## 2026-10-19 实测

基线源码为 `bf9ef51` 的 `Net.OpenSSL.pas`，开始时工作区干净。

- Delphi Win64、FPC Win64：修复前各 **0/8**。未握手及强制失败输出产生访问异常；TLS 1.2/1.3 首次查询取得 1 个 key 却释放 0 个；字段读取异常同样遗留引用。
- 修复前两个托管记录用例各 128 次累积约 **25 MiB**。Delphi 修复后存量保持不变；FPC 修复后额外保留约 **100 KiB**，低于阈值。
- 修复后 Delphi Win64/FPC Win64 × OpenSSL **3.1.2** 与 **1.1.1v**，以及 Delphi Win32 × OpenSSL **3.5.0**，共五组各 **8/8**，合计 **40/40**。
- 成功取得 key 的正常查询和异常查询均观测到 **32 次获取、32 次释放**。TLS 1.2 服务端与静态 RSA 路径没有 key 时，字段保持空/零。

首次 Win32 的 TLS 1.3 测试没有固定交换组，OpenSSL 3.5.0 默认握手未提供测试所假定的可查询临时 key，两项断言失败；这属于测试前提不一致。固定 X25519 后五组重新构建并全部通过，旧日志保留在 `bin/fixed3-win32/`。

证据位置：

- `bin/baseline/`：基线两目标结果、当时生产源码和测试源码快照；初次构建中的测试字段拼写及缺少本地 OpenSSL 配置问题在正式基线运行前已修正。
- `bin/final3/{win64,fpc64,win32}/`、`bin/final111/{win64,fpc64}/`：编译日志、实际运行库版本、逐项日志、`results.json` 和源码 SHA-256。
- `GetHeapStatus` 在 Delphi 上有弃用/平台限定警告，现有依赖也有提示；不声称零警告。

未运行 Linux/macOS、静态链接或正式服务长时间压力测试；没有修改 TLS 收发状态机。
