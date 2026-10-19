# Session 语义与清理线程回归

对应 A09/F17/F18。原 14 项语义测试覆盖未知 ID、过期获取/Exists、显式导入、续期、ID 碰撞、写锁重入、锁内更新时间、并发获取及真实 HTTP Cookie 写回。原 5 项生命周期测试用事件控制线程入口、清理前、持锁清理、空闲停止和异常退出。修复后另外增加不可用 ID 生成器及 Start 前构造失败两项，共 21 项。

`CROSS_SESSION_TESTS` 仅在测试构建增加时序观察与短清理间隔；原红基线仅增加这些钩子，原线程和会话算法保持不变。启动/析构用事件固定时序；清理前用例等待超过旧代码明确的 5 秒上限，验证不能超时后释放仍在运行的对象，不以随机 Sleep 碰撞窗口。每项独立进程且有超时。

HTTP 用例使用真实解析、路由、Session 和响应编码，仅替代网络写入；不等于真实网络集成测试。仅语义分支可不定义测试开关，runner 使用 `--semantics-only`。

## 构建与运行

本目录执行。使用已有 Delphi 13.1、FPC 3.3.1 及相邻工程的搜索路径，不安装依赖、不改全局配置。

```powershell
New-Item -ItemType Directory -Force -Path bin/delphi-win64,lib/delphi-win64 | Out-Null
& 'D:\Design\Delphi\D13.1\bin\dcc64.exe' -Q -B -DCROSS_SESSION_TESTS '-NSSystem;System.Win;Winapi' `
  '-U..\..\..;..\..\..\..\Utils;D:\Design\Delphi\D13.1\lib\win64\release' `
  '-I..\..\..\..;..\..\..' '-Ebin\delphi-win64' '-N0lib\delphi-win64' HttpSessionTests.dpr
python run_tests.py bin/delphi-win64/HttpSessionTests.exe --report bin/delphi-result.json
& 'D:\Design\FreePascal\lazarus\lazbuild.exe' --build-all --skip-dependencies HttpSessionTests.lpi
python run_tests.py bin/x86_64-win64/HttpSessionTests.exe --report bin/fpc-result.json
python build_linux.py delphi-linux64 fpc-linux64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/HttpSessionTests -- python3 -B run_tests.py bin/delphi-linux64/HttpSessionTests --report bin/delphi-linux-result.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/HttpSessionTests -- python3 -B run_tests.py bin/fpc-linux64/HttpSessionTests --report bin/fpc-linux-result.json
```

关闭测试入口的生产分支：Delphi 去掉 `-DCROSS_SESSION_TESTS` 并将输出分别设为 `bin/production-delphi-win64`、`lib/production-delphi-win64`；先创建这两个目录。FPC 使用与 `.lpi` 相同的路径补充直接编译：

```powershell
New-Item -ItemType Directory -Force -Path bin/production-fpc-win64,lib/production-fpc-win64 | Out-Null
& 'D:\Design\FreePascal\fpc\bin\x86_64-win64\ppcx64.exe' -B -uCROSS_SESSION_TESTS `
  '-Fu..\..\..' '-Fu..\..\..\..\Utils' '-Fu..\..\..\..\DelphiToFPC' `
  '-FuD:\Design\FreePascal\lazarus\components\lazutils\lib\x86_64-win64' `
  '-Fi..\..\..\..' '-Fi..\..\..' '-FEbin\production-fpc-win64' '-FUlib\production-fpc-win64' HttpSessionTests.lpr
python run_tests.py bin/production-fpc-win64/HttpSessionTests.exe --semantics-only
python build_linux.py --production delphi-linux64 fpc-linux64
```

生产分支的四个可执行文件均用 `--semantics-only` 运行 15 项；每项都创建并销毁真实 Session 容器及清理线程。Linux 路径为 `bin/production-delphi-linux64/HttpSessionTests` 和 `bin/production-fpc-linux64/HttpSessionTests`，通过上述 WSL 方式实际运行。

## 兼容与锁约定

- 保留公开签名及显式 `AddSession(ID)`。`GetSession`/`Sessions[ID]` 与两种 `ExistsSession` 都在内部取得写锁，原子完成过期检查、删除和续期，**不能包在外部读锁中调用**；外部写锁的重入用法已验证。
- `AddSession`、删除、Clear、枚举等原有显式锁约定仍由调用方遵守；没有扩大 `Session.Values` 的并发保证。释放容器前必须先释放调用方持有的会话锁；清理虚函数不能直接销毁正在执行它的容器。
- 未知或过期的客户端 ID 改为服务端新 ID，服务器已有逻辑负责回写 Cookie。自定义 ID 生成器若连续返回空值、客户端原值或已存在值，16 次尝试后明确失败，避免固定会话、覆盖现有会话或无限循环。
- 线程启动前已设置非自动释放，析构先触发停止事件，在不持会话锁时等待线程真正结束，再释放资源；不再使用入口运行标记或 5 秒后放任释放。测试钩子仅 `CROSS_SESSION_TESTS` 可见，正式使用应全量重编译所有依赖单元。

## 2026-10-19 结果

Delphi/FPC Windows Win64、Delphi/FPC Linux64（Ubuntu 22.04 WSL 实际运行）四个目标一致：

- 原 19 项基线：**8/19 通过**，其中 F17 为 5/14，F18 为 3/5。
- 只修线程阶段：Windows 两目标达到 10/19，F18 原 5 项全部通过，F17 的 9 项仍失败，确认两批修复独立。
- 最终：**21/21 通过**，其中 F17 为 15/15，F18 为 6/6；关闭测试入口的生产构建 **15/15 通过**。
- 构造失败是在 TThread 已创建、尚未 Start 时注入异常，验证 `FExpiredThreadStarted=False` 收尾分支；未注入操作系统真实拒绝创建线程或 Resume 失败。未覆盖清理回调直接释放自身、Session.Values 任意并发修改、实际 TCP/TLS 或长期压力。
- 基线在 `bin/baseline-*/`，重跑时加 `--baseline`（只运行旧文件包含的 19 项）；结果 JSON 与构建日志也在 `bin/`。`baseline-source.json` 标明仅加入时序钩子的旧算法，`final-source.json` 记录本次源码与测试哈希。共享工作区有其他分工修改，不将所有可执行文件描述为纯 HEAD 构建。

## S03 Session 单元拆分

会话声明与实现迁至 `Net.CrossHttpSessions`，不依赖 HTTP 参数或服务器单元。`Net.CrossHttpParams` 保留 `ISession`、`ISessions`、`TSessionBase`、`TSession`、`TSessionClass`、`TSessionsBase`、`TSessions` 七个类型别名，测试配置类型和入口也只转发至同一实现。普通调用方继续使用原 uses 路径；新代码可直接引用新单元。

搬移后声明与方法实现逐字比对 O02 提交 `0e0615b`，GUID、虚方法顺序、保护字段和清理算法均未修改。声明所属单元和限定 RTTI 名称会变化，使用包/预编译单元的项目需要完整重编译；依赖单元限定类型名做反射或注册的代码应同步调整。类型别名保持类型同一性，不是再建一套包装类或独立容器。

新增 `unit-compatibility` 验证新旧两种接口的 TypeInfo 相同，以及从旧单元提供 SessionClass、通过旧接口写入后经新接口读取同一个实例。原继承测试继续从旧路径编译，覆盖保护字段和虚方法。五目标 Delphi Win64/Win32、FPC Win64、Delphi/FPC Linux64 各 **22/22，共 110/110**；关闭测试宏的两个 Windows64 和两个 Linux64 目标各 **16/16，共 64/64**。相邻 BatchCleanupTests 的 Session 五项在同五目标共 **25/25**，包括锁外释放和钩子异常，未重新测量纯搬移前后性能。

证据保存在两套件各自的 `bin/s03-sessions/`，构建记录均包含 Params 与新 Sessions 单元哈希。正式 HTTP 服务端示例验证见下节；HTTP 客户端与 WS 示例随其后续容量/整理做组合验收，不把本组组件结果扩大为全部正式示例已通过。

```powershell
python -B build_tests.py delphi-win64 delphi-win32 fpc-win64 delphi-linux64 fpc-linux64 --label s03-sessions
python -B run_tests.py bin/s03-sessions/delphi-win64/HttpSessionTests.exe --unit-compatibility --report bin/s03-sessions/delphi-win64/results.json
python -B build_tests.py delphi-win64 fpc-win64 delphi-linux64 fpc-linux64 --label s03-sessions --production
python -B run_tests.py bin/s03-sessions/production-delphi-win64/HttpSessionTests.exe --semantics-only --unit-compatibility
```

Linux 在真实 Linux 环境使用同一 `run_tests.py`，替换为对应无 `.exe` 的程序路径。`build_linux.py` 原有入口保留，新增可选 `--label` 隔离产物。

## 正式 HTTP 服务端示例的构建与上传验收

`Net/Demos/Delphi/HttpServer/HttpServer.dpr` 的上传字段 `Value` 是 `TStream`，原先传给 `Utils.Hash` 的 `GetHashString`，与现有重载不匹配。正式 Release/Win64 构建在第 71/72 行得到 E2250，日志在 `bin/s03-formal-before/build.log`。两行改用已有 `GetHashStringFromStream` 后，同一 `.dproj` 经 MSBuild 构建通过，产物和日志在 `bin/s03-formal-server/`；原 GB18030 源同时统一为 UTF-8 BOM/CRLF，中文注释保持原文。未修改哈希实现。

2026-10-20 本地实际运行该正式程序，TLS 1.2/1.3 各在同一连接上传两次，共 4 次请求、12 个文件、24 个摘要。内容包括 0 字节、45 字节中文 UTF-8/NUL、65,798 字节全字节值二进制，MD5/SHA1 均与 Python hashlib 相同，中文文件名一致。SHA1 在 MD5 之后仍计算非空文件的完整内容；两次调用的默认 `APos=0` 保证各自从开头读取。它们是示例已有的摘要展示，不是新增密码存储或认证方案。

`run_demo_upload.py` 保持证书及主机名校验，使用已有握手套件的自签名测试证书，实际检查子进程加载的 OpenSSL DLL 路径及哈希。运行前确认固定端口 8080 空闲，只停止自己启动的进程；回车退出码为 0，最终没有该进程或监听残留。示例沿用 `AutoDeleteFiles=False`，所以测试先记录保留的 12 个上传文件，再清理测试独占目录，不能把这一清理说成示例自动删除。

完整证据在 `bin/s03-formal-server/upload-tls-final4/results.json` 及响应、服务端日志中。报告区分构建日志、运行程序哈希和运行时源码快照，不把最后者单独当作编译来源证明。脚本复用已编译的程序：

```powershell
python -B run_demo_upload.py --exe bin/s03-formal-server/HttpServer.exe --cert <现有测试证书> --key <对应测试私钥>
```

证书必须具有正确 SAN 和约束；缺省输出使用新的独立目录，显式 `--output` 也必须尚不存在。其他平台或编译器的正式示例尚未据此获得运行验证。
