# 目录输出与路径回归

对应 `docs/plans/2026-10-19-project-improvements.md` 的 F07/A10.1。测试使用真实 HTTP 解析、路由、目录读取、页面生成及文件发送，仅将网络写入替换为内存。Python 解析真实响应 HTML，检查标签/事件属性/原始文本，并沿生成的链接再次请求和比较文件内容；不通过搜索源码或检查实现函数代替行为验证。

18 项包括编码路径加 `..` 的标签和属性注入、规范化导航、根路径与末尾斜杠、嵌套导航、中文/空格/`&`/引号/`%`/`+`、实体样式文件名、无扩展名条目、根挂载与特殊挂载路径、直接下载和目录边界。Windows 跳过两项非法文件名，Linux 在 `/tmp` 创建这些真实文件，避免 `/mnt/d` 的 Windows 文件名约束。

构建沿用相邻 HttpAuthTests/HttpFailureTests 的已有双编译器和 Linux SDK，不安装依赖、不修改全局配置。所有 Pascal 文件使用 UTF-8 BOM/CRLF。runner 只清理经父目录与专用前缀校验的本次临时目录。

```powershell
New-Item -ItemType Directory -Force -Path bin/delphi-win64,lib/delphi-win64 | Out-Null
& 'D:\Design\Delphi\D13.1\bin\dcc64.exe' -Q -B '-NSSystem;System.Win;Winapi' `
  '-U..\..\..;..\..\..\..\Utils;D:\Design\Delphi\D13.1\lib\win64\release' `
  '-I..\..\..\..;..\..\..' '-Ebin\delphi-win64' '-N0lib\delphi-win64' HttpDirectoryTests.dpr
python run_tests.py bin/delphi-win64/HttpDirectoryTests.exe --report bin/delphi-result.json
& 'D:\Design\FreePascal\lazarus\lazbuild.exe' --build-all --skip-dependencies HttpDirectoryTests.lpi
python run_tests.py bin/x86_64-win64/HttpDirectoryTests.exe --report bin/fpc-result.json
python build_linux.py delphi-linux64 fpc-linux64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/HttpDirectoryTests -- python3 -B run_tests.py bin/delphi-linux64/HttpDirectoryTests --report bin/delphi-linux-result.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/HttpDirectoryTests -- python3 -B run_tests.py bin/fpc-linux64/HttpDirectoryTests --report bin/fpc-linux-result.json
```

本套件不验证实际 TCP/TLS、浏览器脚本执行、符号链接/重解析点穿越或目录并发变更；通过 HTML 语法与链接内容断言确认原注入入口被消除。

## 2026-10-19 红绿对照

所有目标都使用同一组 18 项断言，基线可执行文件在修改 Router 源码前保存。基线失败属于已复现问题，不计作回归通过。

| 编译器和运行环境 | 未修复基线 | 修复后 |
| --- | --- | --- |
| Delphi 13.1 / Windows Win64 | 7/16 通过，9 失败，2 项跳过 | 16/16 通过，2 项跳过 |
| FPC 3.3.1 / Windows Win64 | 7/16 通过，9 失败，2 项跳过 | 16/16 通过，2 项跳过 |
| Delphi 13.1 Linux64 / Ubuntu 22.04 WSL | 7/18 通过，11 失败 | 18/18 通过 |
| FPC 3.3.1 Linux64 / Ubuntu 22.04 WSL | 7/18 通过，11 失败 | 18/18 通过 |

- 红基线确认实际 HTML 出现 SVG/事件属性；Linux 还确认真实恶意文件名成为标签。修复后这些内容不再成为可执行标签/属性，原始文件名作为文本保留；请求路径中被 `..` 折叠的片段不再出现于导航。
- 生成链接逐段 URL 编码后用于再次真实请求，中文、空格、实体样式、引号、百分号和加号文件的正文逐字节匹配。根、嵌套、末尾斜杠及上级导航均可用，目录外文件仍返回 404。
- 本轮 Linux 实测发现附加的既存差异：`FindFirst('*.*')` 漏掉无扩展名文件/目录。经确认改为 `'*'` 并加入 `LICENSE`、`plain-directory/child` 回归；这是目录浏览的附加正确性修正，不另计原审查 30 条的完成项，也未加入分页、缓存或修改 Utils 库。
- 未修复可执行文件保存在 `bin/baseline-delphi-win64/`、`bin/baseline-fpc-win64/`、`bin/baseline-delphi-linux64/`、`bin/baseline-fpc-linux64/`。对应 `bin/baseline-*-result.json` 为最新同组用例结果；修复后为 `bin/*-result.json`，含可执行文件 SHA-256。后续构建不得覆盖保留的基线目录。
- `bin/baseline-source.json` 和 `bin/final-source.json` 记录本次 Router 与测试源码哈希；Linux 构建目录另有 `source.json`。以 `bf9ef51` 为工作区基础，其他分工同时修改 Socket 生命周期，不能把所有依赖描述成纯粹来自该提交。
- 使用现有 Windows 工具链和 Ubuntu SDK交叉构建，然后在已有 Ubuntu 22.04 WSL 实际运行 Linux 二进制，没有安装依赖或修改系统配置。WSL 已有的 `network.ipv6` 配置警告未修改；编译器已有依赖/字符串转换警告不属于本轮零警告保证。

## O07 / B05：可选目录上限与异常清理

保留 `TNetCrossRouter.Dir(APath, ALocalDir, ADirParamName)` 和 `BuildDirList(ARealPath, ARequestPath, AHome)`，新增第四参数 `AMaxEntries: Integer` 的重载。旧签名委托上限 0，保持完整列表；负数在入口抛出 `EArgumentOutOfRangeException`。例如 `TNetCrossRouter.Dir('/files', LocalDir, '*', 100)`。

正数上限最多取到 N+1 个有效条目（排除 `.` / `..`），只保存枚举前 N 项，再按既有目录优先、自然顺序排序。它不承诺选出整个目录排序最靠前的 N 项，枚举顺序由文件系统决定。只有实际检测到第 N+1 项时显示截断提示和“本页”统计；总条目数不超过 N 时，完整 HTML 与旧实现逐字节一致。直接文件下载、规范化导航及原来的路径边界检查保留。没有新增缓存、分页框架或共享状态。

两个列表及原生目录搜索记录分别由 `try/finally` 释放，覆盖创建第二个列表之前、枚举中断、排序和页面生成异常。`CROSS_HTTP_DIRECTORY_TESTS` 仅测试构建启用：阶段钩子抛出受控异常，真实列表子类的析构计数验证对象释放；父进程同时读取 Windows 进程句柄数或 Linux `/proc/<pid>/fd`，确认搜索句柄没有遗留。正常路径先预热日期/时区的延迟初始化，避免把 FPC Windows 首次格式化打开的正常运行库句柄误判为搜索泄漏。正式 HTTP 程序和性能程序不定义该宏。

### 红绿与保留证据

每个目标新增 20 项真实 HTTP 页面断言和 14 项组件资源/枚举断言。页面覆盖空目录、零/精确/小于/大于总数/`High(Integer)` 上限、负数拒绝、目录优先自然排序、0/1023/1024/1048576 字节显示、选取实际枚举前缀、截断提示与本页统计、特殊字符、未展示文件仍能下载、嵌套/反射路径/边界；资源测试覆盖六个异常阶段、N+1 枚举、空目录、目录不存在和直接调用负数拒绝。

| 编译器/环境 | O07 页面红基线 | O07 页面最终 | 资源红基线 | 资源最终 | F07 安全回归最终 |
| --- | --- | --- | --- | --- | --- |
| Delphi / Windows | 12/20 | 20/20 | 5/14 | 14/14 | 16/16，2 项跳过 |
| FPC / Windows | 12/20 | 20/20 | 5/14 | 14/14 | 16/16，2 项跳过 |
| Delphi / Ubuntu WSL | 12/20 | 20/20 | 5/14 | 14/14 | 18/18 |
| FPC / Ubuntu WSL | 12/20 | 20/20 | 5/14 | 14/14 | 18/18 |

四目标合计 204 项实际通过，另有 4 次 Windows 非法文件名跳过。O07 红基线已包含 F07 安全修复：页面的失败来自尚未支持限额或负数拒绝；资源红基线显示枚举阶段抛错后两个列表仍存活、原生搜索句柄增加 1，后续阶段抛错也不释放列表。最终版本这些阶段列表计数为 0、句柄数不增长。

O07 原版程序在 `bin/listing-baseline-*/`、`bin/perf-baseline-*/`，资源红基线在 `bin/resource-baseline2-*/`（加入钩子但未改变原清理逻辑）。不覆盖更早 F07 的 `bin/baseline-*/`。本轮最终程序是 `bin/final-*/`；`bin/{security,listing,resource}-final-*.json` 含实际运行结果及可执行文件哈希，`bin/{listing,resource}-red-final-*.json` 含同一组红基线结果。每个构建目录的 `<工程名>.source.json` 记录所编译的 Router、DirUtils 和测试主程序哈希。先前未预热的资源试跑在 `resource-red-*`，不作为最终红绿计数。

### 构建与运行

以下命令在本目录执行。已有 Python、Delphi、FPC、Ubuntu SDK 和 WSL；Windows 进程度量复用已安装的 `psutil`，Linux 直接读取 `/proc`。各工程的中间产物单独放在 `lib/<标签>-<目标>/<工程名>/`，防止不同测试宏相互覆盖。

```powershell
python -B build_windows.py delphi-win64 fpc-win64 --label final --new-api
python -B build_windows.py delphi-win64 fpc-win64 --label final --new-api --resources --hooks
python -B build_windows.py delphi-win64 fpc-win64 --label final --new-api --bench
python -B run_suite.py delphi-win64 fpc-win64
python -B run_suite.py delphi-win64 fpc-win64 --red

python -B build_linux.py delphi-linux64 fpc-linux64 --label final --new-api
python -B build_linux.py delphi-linux64 fpc-linux64 --label final --new-api --resources --hooks
python -B build_linux.py delphi-linux64 fpc-linux64 --label final --new-api --bench
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/HttpDirectoryTests -- python3 -B run_suite.py delphi-linux64 fpc-linux64
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/HttpDirectoryTests -- python3 -B run_suite.py delphi-linux64 fpc-linux64 --red

python -B run_directory_perf.py bin/perf-baseline-delphi-win64/DirectoryBench.exe --candidate bin/final-delphi-win64/DirectoryBench.exe --report bin/perf-final-delphi-win64.json
wsl.exe -d Ubuntu-22.04 --cd /mnt/d/GitHub/Delphi-Cross-Socket/Net/Tests/FPC/HttpDirectoryTests -- python3 -B run_directory_perf.py bin/perf-baseline-fpc-linux64/DirectoryBench --candidate bin/final-fpc-linux64/DirectoryBench --report bin/perf-final-fpc-linux64.json
```

红基线命令预期返回非零；不能把它当成通过。性能命令对另外两个目标替换二进制及报告名称即可。基线可执行文件是修改前保存的本地证据，重新编译当前源码不会重新得到红基线。整个工作区还有其他分工的并行改动，不能把所有依赖描述为来自单一原始提交。

### 性能测量口径与边界

每个平台为 100 / 1,000 / 10,000 条创建同一组真实目录和文件（10% 目录，文件名含中文、空格、`&`、`%`），同一目录交替运行原版与最终版，三轮取中位数。每个新进程先做一次未计时预热，再重复 60 / 15 / 3 次；每次释放上一页面，最终页面保留到父进程采样结束。完整列表同时比较字符数和内容散列，HTTP 小型夹具则直接比较正文的每个字节。

峰值由 Windows `peak_wset` 或 Linux `VmHWM` 得到，单位为实际工作集 MiB（1,048,576 字节），包括一次预热、运行库与最终页面；原始 JSON 另存就绪时工作集/峰值和相对峰值增长。它不是仅采样 RSS 的近似峰值，也不等同于 Pascal 堆分配量。计时覆盖目录枚举、元数据、排序和页面生成，不包括 HTTP 编码、网络传输或创建夹具。

上限只减少应用层保留和遍历的有效条目；操作系统内部可能批量预取目录项，所以 N+1 不代表底层恰好发生 N+1 次磁盘读取。当前数据来自预热后的本地 NTFS / WSL 本地临时文件系统，不代表冷盘、网络共享、并发变更目录或硬性时延保证。0 仍是兼容默认值，大目录服务需要调用方显式选择合适上限。

### 最终性能结果

以下每格为“毫秒 / 峰值 MiB”，均为三轮中位数。完整列表的字符数与散列在每一轮都与同目录原版相同。

| 目标 | 条目数 | 原版完整 | 最终完整（0） | 最终限额 100 |
| --- | ---: | ---: | ---: | ---: |
| Delphi Windows | 100 | 0.614 / 8.42 | 0.608 / 8.48 | — |
| Delphi Windows | 1,000 | 5.521 / 10.80 | 5.387 / 10.25 | 0.503 / 8.43 |
| Delphi Windows | 10,000 | 78.421 / 26.48 | 79.762 / 26.49 | 1.812 / 8.43 |
| FPC Windows | 100 | 0.819 / 8.63 | 0.818 / 8.64 | — |
| FPC Windows | 1,000 | 6.505 / 10.96 | 6.082 / 10.16 | 0.988 / 8.64 |
| FPC Windows | 10,000 | 121.845 / 28.95 | 118.076 / 28.14 | 2.186 / 8.64 |
| Delphi Linux | 100 | 1.063 / 11.77 | 1.072 / 11.88 | — |
| Delphi Linux | 1,000 | 13.998 / 13.62 | 13.418 / 13.65 | 1.340 / 11.70 |
| Delphi Linux | 10,000 | 191.281 / 28.97 | 194.827 / 29.58 | 1.558 / 11.75 |
| FPC Linux | 100 | 0.683 / 4.11 | 0.683 / 4.11 | — |
| FPC Linux | 1,000 | 8.600 / 6.15 | 9.533 / 5.78 | 0.800 / 4.11 |
| FPC Linux | 10,000 | 110.333 / 17.00 | 110.667 / 17.06 | 0.667 / 4.11 |

明确收益来自调用方启用上限，减少枚举、排序及页面体量；0 仍需全量工作，没有统一加速保证。本轮完整模式有快有慢，例如 FPC Linux 1,000 项中位数由 8.600 增至 9.533 ms，不能用有限模式的结果掩盖该观测，也不把单机三轮数据解释成统计显著性结论。原始数据保存在 `bin/perf-final-<目标>.json`，含每次调用次数、原始时钟计数、频率、峰值及二进制哈希；汇总为 `bin/o07-perf-summary.json`。

本轮确实试过整页 StringBuilder：10,000 项时 FPC Windows 原版/候选的中位数为 118.693 / 80.514 ms、峰值约 28.95 / 23.61 MiB，但 Delphi Windows 为 75.540 / 77.713 ms、峰值约 26.49 / 32.11 MiB；Delphi Linux 的峰值也增加约 6 MiB，FPC Linux 时间基本持平而峰值增加。因此没有将这种平台间取舍变成生产代码。随后试过 64K 字符分批清空 StringBuilder，Windows Delphi 仍从 79.651 / 26.49 增至 83.308 / 30.99，未继续增加调参或编译器分支。最终保留原字符串追加，只采用已有证据支持的上限和资源释放修复。

被淘汰的整页候选四目标记录为 `bin/perf-compare-*.json`，64K 候选仅完成 Windows 双目标实测，记录为 `bin/perf-chunks-*-win64.json`；相关二进制、源码快照和构建哈希保存在各自 `perf-green-*` / `perf-chunks-*`、`stringbuilder-source` / `chunks-source` 目录，不作为最终版本成绩。不同轮次数据各自配对，不能把早一轮原版数值与后一轮最终数值拼成速度收益。

本轮未覆盖实际 TCP/TLS、冷盘/网络目录、权限拒绝的系统异常、磁盘或堆分配失败、符号链接/重解析点安全性、并发目录增删；异常注入验证的是当前函数已经拥有资源后的清理路径。测试宏未提供生产公开 API，也没有线程或后台清理任务。
