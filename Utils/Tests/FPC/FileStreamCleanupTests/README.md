# 文件流析构失败清理回归

对应 O03b 正文阈值落盘依赖的现有临时文件流资源问题。生产修改仅 `Utils/Utils.IOUtils.pas` 两个析构：`TFastFileStream` 刷新失败仍释放缓冲并关闭句柄；`TTempFileStream` 父类析构失败仍尝试删除临时文件。保留原 `EWriteError` 及消息，不吞掉失败，不增加公开接口或生产测试钩子。

测试使用实际文件与运行库，不通过关闭/替换流持有的句柄制造错误，也不会误关被复用的句柄。每项为独立子进程，10 秒超时。

- 普通只读文件：以真正 `fmOpenRead` 创建缓冲流，少量写入先进入缓冲，析构调用实际原生写入而失败。父进程逐字节确认原文件未改变。
- 临时文件 / Windows：通过第二个只读句柄建立共享字节区锁，所有句柄对此区间的写入都被阻止；流原句柄始终有效。锁句柄允许删除，析构后释放测试锁，再核验文件消失。依据 [Microsoft LockFileEx 文档](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-lockfileex) 的共享锁写入排斥语义。
- 临时文件 / Linux：Python 只在测试子进程中设置 `RLIMIT_FSIZE=0`、忽略 `SIGXFSZ`；创建空文件与缓存写入成功，析构刷新得到实际写入错误。父进程和其他任务的资源上限不变。
- 测试进程暂时包装已有内存管理器的 `GetMem` / `FreeMem`（FPC 另含 `FreeMemSize`），仍调用原管理器；确认构造恰好分配一次目标大小的缓冲，并捕获其实际释放。普通流使用 123,457 字节，临时流使用默认 32,768 字节。恢复原管理器后才输出结果。
- 析构返回或抛错后，先检查保留的原句柄已经无效；在此之前不再打开文件，避免由测试自身引入句柄复用。临时文件再检查实际删除。错误类和消息必须仍是 `EWriteError` / `SWriteError`；显式刷新先失败的用例还比较两次错误一致。

9 项为只读脏缓存析构、只读显式刷新后析构、只读干净缓存、正常写入析构、正常显式刷新、空临时流、已写入临时流、临时流真实刷新失败，以及显式刷新先失败后的临时流析构。

## 2026-10-19 红绿结果

| 目标 | 原版 | 修复后 |
| --- | --- | --- |
| Delphi 13.1 Windows | 5/9 | 9/9 |
| FPC 3.3.1 Windows | 5/9 | 9/9 |
| Delphi 13.1 Linux / Ubuntu 22.04 WSL | 5/9 | 9/9 |
| FPC 3.3.1 Linux / Ubuntu 22.04 WSL | 5/9 | 9/9 |

四目标合计 36 项通过。原版的四个错误用例均记录 `allocated=1 freed=0 closed=0 error=EWriteError`，临时文件还记录 `deleted=0`；修复后为 `freed=1 closed=1`，临时文件 `deleted=1`，错误仍为 `EWriteError`。普通只读文件的字节在红、绿版本都保持原样；正常写入完成，普通文件没有被删除。

`bin/baseline-*/` 为生产修改前保留的可执行基线，`bin/red-*.json` 为其运行记录；`bin/final-*/` 和 `bin/final-*.json` 为修复后记录。报告包含可执行文件 SHA-256，各构建目录 `source.json` 记录生产及测试源码哈希，`bin/final-source.json` 汇总最终证据。不要用当前源码覆盖基线：重新编译当前源码不能重现旧实现。

## 构建与运行

在本目录执行，沿用已安装的 Delphi/FPC、Lazarus 单元、Linux SDK 和 WSL，不安装依赖或修改全局设置。所有 Pascal 源码为 UTF-8 BOM / CRLF。

```powershell
python -B build_tests.py delphi-win64 fpc-win64 delphi-linux64 fpc-linux64 --label final
python -B run_tests.py bin/final-delphi-win64/FileStreamCleanupTests.exe --report bin/final-delphi-win64.json
python -B run_tests.py bin/final-fpc-win64/FileStreamCleanupTests.exe --report bin/final-fpc-win64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/FileStreamCleanupTests -- python3 -B run_tests.py bin/final-delphi-linux64/FileStreamCleanupTests --report bin/final-delphi-linux64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Utils/Tests/FPC/FileStreamCleanupTests -- python3 -B run_tests.py bin/final-fpc-linux64/FileStreamCleanupTests --report bin/final-fpc-linux64.json
```

将路径中的 `final-` 换为 `baseline-` 可运行保留的红基线，预期非零退出。测试只清理经过绝对父目录和专用前缀校验的本次夹具；Windows 夹具沿用工作区继承权限，Linux 使用本地临时目录。WSL 既有 `network.ipv6` 配置警告未修改。

此套件没有制造磁盘耗尽、系统堆损坏、`FreeMem` 自身异常、权限导致删除失败或进程强制终止，不承诺这些场景能成功删除文件。`TFileUtils.Delete` 仍保留既有 Boolean 返回语义；本补丁只保证原刷新异常不会跳过删除尝试。这里不代替 HTTP 断开、正文落盘迁移和请求引用持有的集成回归。
