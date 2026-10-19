# EasyThread 生命周期回归

对应全项目计划 A09/F19。原六项覆盖最后一个外部 `IEasyThread` 引用提前释放后正常结束、异常结束、Terminate、自身调用 WaitFor；以及外部重复 WaitFor、无参数匿名任务由其他线程析构。另增两个构造重载在 Start 前失败的资源收尾，共八项。

用事件固定任务开始、允许结束和析构时序，不通过长 Sleep 撞竞态。包装对象析构和线程回调捕获的接口资源都必须释放一次。每项独立进程，内部事件等待与外部 runner 都有超时，旧版自等不会挂住整套测试。

Pascal 使用 UTF-8 BOM/CRLF。Windows 构建沿用既有 Delphi/FPC，Linux 由 `build_linux.py` 使用已有 SDK 交叉构建，再在 Ubuntu WSL 执行。不安装依赖、不修改工具链配置。

## 构建与运行

本目录执行：

```powershell
New-Item -ItemType Directory -Force -Path bin/delphi-win64,lib/delphi-win64 | Out-Null
& 'D:\Design\Delphi\D13.1\bin\dcc64.exe' -Q -B -DCROSS_EASY_THREAD_TESTS '-NSSystem;System.Win;Winapi' `
  '-U..\..\..;D:\Design\Delphi\D13.1\lib\win64\release' '-I..\..\..\..' `
  '-Ebin\delphi-win64' '-N0lib\delphi-win64' EasyThreadTests.dpr
python run_tests.py bin/delphi-win64/EasyThreadTests.exe --report bin/delphi-result.json
& 'D:\Design\FreePascal\lazarus\lazbuild.exe' --build-all --skip-dependencies EasyThreadTests.lpi
python run_tests.py bin/x86_64-win64/EasyThreadTests.exe --report bin/fpc-result.json
python build_linux.py delphi-linux64 fpc-linux64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyThreadTests -- python3 -B run_tests.py bin/delphi-linux64/EasyThreadTests --report bin/delphi-linux-result.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/EasyThreadTests -- python3 -B run_tests.py bin/fpc-linux64/EasyThreadTests --report bin/fpc-linux-result.json
```

`CROSS_EASY_THREAD_TESTS` 只增加启动前故障注入入口，生产不定义它。Delphi 生产分支去掉该 `-D`，创建并使用 `bin/production-delphi-win64`、`lib/production-delphi-win64` 输出目录；FPC 补充构建如下：

```powershell
New-Item -ItemType Directory -Force -Path bin/production-fpc-win64,lib/production-fpc-win64 | Out-Null
& 'D:\Design\FreePascal\fpc\bin\x86_64-win64\ppcx64.exe' -B -uCROSS_EASY_THREAD_TESTS `
  '-Fu..\..\..' '-Fu..\..\..\..\DelphiToFPC' '-Fi..\..\..\..' `
  '-FEbin\production-fpc-win64' '-FUlib\production-fpc-win64' EasyThreadTests.lpr
python run_tests.py bin/production-fpc-win64/EasyThreadTests.exe --baseline
python build_linux.py --production delphi-linux64 fpc-linux64
```

生产分支及保留旧基线均加 `--baseline` 只跑原六项；Linux 生产文件位于 `bin/production-delphi-linux64/`、`bin/production-fpc-linux64/`，按上述 WSL 命令运行。

## 2026-10-19 结果与边界

- Delphi 13.1/FPC 3.3.1 的 Windows Win64、Linux64（Ubuntu 22.04 WSL 实际运行）四目标原基线均 **2/6 通过**；任务自身析构或自身 WaitFor 的四项失败。
- 最终测试构建均 **8/8 通过**；关闭故障注入入口的生产构建均 **6/6 通过**。
- 工作线程内析构只设置底层线程 `FreeOnTerminate` 并移交释放，避免等待自己或释放仍在运行的线程；外部线程仍正常等待并释放。Terminate 使用原子状态。公开签名保持不变。
- 两个构造失败用例在底层线程已创建、Start 前抛异常，验证未启动线程和捕获资源都完成一次清理；没有模拟操作系统真实线程创建/Resume 失败。没有扩展到 Win32、ARM 或长期压力。
- `bin/baseline-*/` 保存旧二进制；JSON 包含每项结果与可执行文件哈希，构建日志及源码哈希也在 `bin/`。不覆盖保留的红基线，不把旧文件运行当成最新源码验证。
