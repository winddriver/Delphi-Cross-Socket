# HTTP 认证回归

对应 `docs/plans/2026-10-19-project-improvements.md` 的 F02/A02。测试期望是修复后的认证行为；未修复版本出现失败是红色基线，不能将其标为回归通过。

沿用相邻 `HttpRequestLifetimeTests`：运行真实 HTTP 解析、路由、中间件、响应队列，仅把网络写入替换为同步成功的内存发送。每次请求创建独立 `INVALID_SOCKET` 连接并显式清理；同一个用例保留同一个服务器/中间件，验证 Digest nonce 状态跨连接生效。本套件不是实际 TCP/TLS 集成测试。

首批 18 个用例包括 Basic 正常、空密码、含冒号密码、未知用户 NUL、nil 回调、非法 Base64 字符/padding、错误 scheme、缺冒号和错误密码；Digest 正常、未知用户、nil 回调、自造 nonce、跨目标、重复认证头、错误 scheme 和错误密码。检查响应状态及受保护业务的调用次数。

扩展用例位于 `HttpAuthStateTests.inc`，当前共 59 项：新增严格 UTF-8/控制字符/重复认证头、中文凭据、认证域转义、Digest quoted-string 与原始请求目标、qop/算法/字段校验、userhash=false、拒绝 username* 和冒号用户名，以及 nonce 过期/容量、随机源失败/碰撞、异常、并发和闭包生命周期。

并发用事件屏障控制：同一个 nc 的两个请求同时通过预检但只能有一个进入业务；另一个用例让 nc=2 先完成，再放行已进入密码查询的 nc=1，两者都必须成功。过期用注入的单调时钟，不依赖 Sleep。覆盖错误密码不消费 nc、业务失败后不回滚消费、回调重入、清除正在执行的中间件、最后一个闭包引用清除后的状态释放。

## 构建与运行

本目录执行，工具链和依赖搜索路径沿用相邻测试工程，不修改全局配置。

```powershell
New-Item -ItemType Directory -Force -Path bin/delphi-win64,lib/delphi-win64 | Out-Null
& 'D:\Design\Delphi\D13.1\bin\dcc64.exe' -Q -B -DCROSS_HTTP_AUTH_TESTS `
  '-NSSystem;System.Win;Winapi' `
  '-U..\..\..;..\..\..\..\Utils;D:\Design\Delphi\D13.1\lib\win64\release' `
  '-I..\..\..\..;..\..\..' '-Ebin\delphi-win64' '-N0lib\delphi-win64' `
  HttpAuthTests.dpr
python run_tests.py bin/delphi-win64/HttpAuthTests.exe --report bin/delphi-result.json

& 'D:\Design\FreePascal\lazarus\lazbuild.exe' --build-all --skip-dependencies HttpAuthTests.lpi
python run_tests.py bin/x86_64-win64/HttpAuthTests.exe --report bin/fpc-result.json
```

所有用例通过才返回退出码 0。runner 给每个用例独立进程和 15 秒超时，记录可执行文件哈希；编译输出及结果放在忽略的 `bin/`、`lib/`。未修复基线单独保留在 `bin/baseline-delphi-win64/`、`bin/baseline-fpc-win64/`，后续修复构建不得覆盖这两个目录。

`CROSS_HTTP_AUTH_TESTS` 仅为本测试工程启用时钟、随机源、容量和析构观察入口；生产构建不定义它，原有公开认证签名不变。测试选项在工厂创建时复制，设置/重置只发生在启动并发请求之前或之后；时钟回调仅返回测试时间，不重入业务。

重跑保留的旧可执行文件时使用 `--baseline`，只运行当时的 18 项：

```powershell
python run_tests.py bin/baseline-delphi-win64/HttpAuthTests.exe --baseline
python run_tests.py bin/baseline-fpc-win64/HttpAuthTests.exe --baseline
```

## 无测试开关的补充构建

Delphi 沿用上面的构建命令，去掉 `-DCROSS_HTTP_AUTH_TESTS`，分别将 `-E`、`-N0` 输出目录改为 `bin/production-delphi-win64`、`lib/production-delphi-win64`。运行时加 `--baseline`。

FPC 使用 `.lpi` 中相同的源码、include 和 lazutils 路径，补充直接编译，显式取消测试开关；此步骤用于核对条件编译分支，不替代前面的 Lazarus 全量构建：

```powershell
New-Item -ItemType Directory -Force -Path bin/production-fpc-win64,lib/production-fpc-win64 | Out-Null
& 'D:\Design\FreePascal\fpc\bin\x86_64-win64\ppcx64.exe' -B -uCROSS_HTTP_AUTH_TESTS `
  '-Fu..\..\..' '-Fu..\..\..\..\Utils' '-Fu..\..\..\..\DelphiToFPC' `
  '-FuD:\Design\FreePascal\lazarus\components\lazutils\lib\x86_64-win64' `
  '-Fi..\..\..\..' '-Fi..\..\..' `
  '-FEbin\production-fpc-win64' '-FUlib\production-fpc-win64' HttpAuthTests.lpr
python run_tests.py bin/production-fpc-win64/HttpAuthTests.exe --baseline
```

## 当前认证边界

- Basic 保留 UTF-8、空密码及旧密码查询回调；`#0` 仍表示未取得密码。格式不合法时不调用密码查询，业务回调异常保持服务器原有异常处理契约。
- Digest 仅支持 MD5 和 qop=auth；缺省或显式 `userhash=false` 可用，不支持 username*、userhash=true 或其他算法。算法能力没有隐式扩大。
- 认证头上限 16,384 个字符（按 Pascal string 长度）；随机 nonce 为 32 字节，有效期 5 分钟。单个中间件最多保留 1024 个 nonce、每 nonce 1024 条成功使用记录、总共 8192 条使用记录。
- 达到容量上限时淘汰的是整个 nonce，旧凭据只能重新取得挑战；不会删掉某个 nc 后继续接受原 nonce。全局使用记录满时，优先淘汰其他包含记录的旧 nonce，使新的合法客户端仍可认证。随机源失败或连续碰撞时返回 503，不生成弱 nonce。

## 2026-10-19 修复验证

- 基于已提交 F01 `445ebec`，同时包含主分工正在验证的 F03 Parser/Server 工作区修改，全部重新构建；不能将这些可执行文件描述为完全来自该提交。`bin/final-source.json` 保存实际相关源码哈希。
- Delphi 13.1 Win64、FPC 3.3.1 Win64 的完整测试构建各 **59/59 通过**；无测试开关的生产分支各 **18/18 通过**。
- 完整结果：`bin/state-delphi-result.json`、`bin/state-fpc-result.json`；生产分支结果：`bin/production-delphi-result.json`、`bin/production-fpc-result.json`，同前缀 `*-build.log` 为构建日志。
- 未执行真实 TCP/TLS、非 Windows 平台、长时间压力或浏览器互操作测试。本套件验证真实认证/HTTP 逻辑，网络写入仍为内存替身。现有依赖和 FPC 字符串转换警告仍存在。

## 2026-10-19 未修复基线

- Delphi 13.1 Win64、FPC 3.3.1 Win64 均全量编译成功；两套编译器分别 **6/18 通过、12/18 失败**，runner 返回 1。
- 已通过：Basic 正常、空密码、缺少冒号及错误密码；Digest 正常及错误密码。
- 失败确认：Basic 含冒号密码被拒绝；未知用户/NUL、nil 回调、非法 Base64 字符、多余 padding、错误 scheme 被接受；Digest 未知用户/NUL、nil 回调、自造 nonce、跨目标、重放和错误 scheme 被接受。绕过用例都实际进入了受保护业务。
- `bin/baseline-source.json` 保存构建时 HEAD、Middleware 和测试源码 SHA-256，`bin/HttpAuthTests-baseline.lpr` 保存对应测试源码。认证源码未改变；同一工作区的 F01 Socket 修复由其他分工进行，不能将整个基线可执行文件描述为完全来自未修改的 HEAD。
- 结果：`bin/baseline-delphi-result.json`、`bin/baseline-fpc-result.json`；构建日志：`bin/baseline-delphi-build.log`、`bin/baseline-fpc-build.log`。存在已有依赖警告和 FPC 字符串转换警告，不声称零警告。
- 这些是修复前的预期失败记录，不是认证修复完成。未运行真实 TCP/TLS 或非 Windows 测试。
