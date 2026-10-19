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
