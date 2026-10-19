# Multipart 顺序读取回归与基准

对应 B05/O05。测试真实 Multipart 发送流的输出、短读、字段长度变化、整数边界和所有权；基准单独测量顺序排空，不将定位操作量等同于网络吞吐。

## 回归范围

脚本逐项执行并保存退出码，首个红例不会中断剩余用例：

- `wire-0/1/100/1000`：空表单及不同字段数量的字节输出、读取和 Seek。
- `short-read`、`early-zero`：底层源短读或提前结束。
- `length-grow/shrink/between`：发送流创建后字段长度变化。
- `seek-overflow`、`read-overflow`：正负偏移饱和处理，及逻辑总大小为 High(Int64) 时只剩一个结束字节的读取。
- `init-overflow/init-total-overflow/init-tail-overflow`、`negative-size`：单字段、字段之和、结束边界的长度溢出及负源大小。
- `sparse-file`：真实文件逻辑大小超过 2 GiB，验证洞内容、正文最后一个字节和整个结束 boundary；Windows 显式设置 sparse 属性，Linux 越过洞写尾字节。
- `ownership`、`ownership-init`：表单与字段流的借用/拥有组合，以及初始化失败时各资源释放一次。
- `count-1/100/1000`：探针记录初始化和顺序排空的 Size 查询次数，不混入计时基准。二分查找通过源码和随机 Seek 校验，不宣称计数了其每次比较。

字节 oracle 独立拼接公开字段信息、已知正文及固定 boundary。固定种子随机 Seek 与不同块长读取进行逐字节比较；1000 字段全量读取使用 17/4096/65536 字节块，其余规模还覆盖 1 字节块。空表单只有结束 boundary；稀疏文件用例从正文最后一个字节跨入完整结束 boundary，覆盖位置/长度交界。

## 性能测量边界

`bench memory|mixed <fields> <blocksize>` 使用普通内存流或真实文件与内存混合流；字段数为 0、1、100、1000，读取块为 4096、65536 字节。除空表单外，正文总量固定为 64 KiB，字段头总量随字段数变化。mixed 单字段使用真实文件，多字段交替使用内存及独立 FileStream；这些 FileStream 读取同一临时文件，各自维护位置。每个进程只排空一次，构造字段、编码头和打开文件均在计时外，计时内不使用计数探针。

每个组合保留一个独立预热进程和五个统计进程，汇总取中位数；`bytes` 是完整线上格式的字节数，`us` 是本次排空微秒。空表单及小表单接近计时器与固定调用成本，不能据其百分比声称真实吞吐同幅变化。前后比较需要相同目标、测试源码、字段数量和块大小。

## 运行

在本目录使用既有本机 Delphi/FPC 工具链，不安装依赖、不修改全局配置：

```powershell
python run_tests.py win64 fpc64 --label before
python run_tests.py win32 --label before
python run_tests.py fpc-linux64 delphi-linux64 --label before --build-only
```

Linux 二进制由 Windows 交叉编译，再在 WSL 的同一目录执行：

```sh
python3 run_tests.py fpc-linux64 delphi-linux64 --label before --run-only
```

改后换用 `--label after`；保留 `before` 目录，不覆盖旧二进制。只跑回归加 `--regression-only`，只跑基准加 `--bench-only`；用 `--cases short-read early-zero` 选例，或用 `--samples 5` 调整统计进程数。红基线返回非零是如实记录，不表示脚本提前放弃其余用例。

若生产文件已经修改，可从已保存的原 Params 单元重新构建基线，不回滚工作区：

```powershell
python run_tests.py win64 fpc64 --label before-final --params-source bin/before
python run_tests.py fpc-linux64 delphi-linux64 --label before-final --params-source bin/before --build-only
python run_tests.py win64 fpc64 --label after-final
python run_tests.py win32 --label after-final --regression-only
python run_tests.py fpc-linux64 delphi-linux64 --label after-final --build-only
```

`--params-source` 指向包含 `Net.CrossHttpParams.pas` 的目录，只调整该单元的编译查找路径；`source.json` 仍以规范单元路径记录实际使用源码的哈希。Linux 分别以 `--label before-final/after-final --run-only` 执行对应已构建二进制。

构建日志、编译命令、每例结果、原始基准和关键依赖 SHA-256 写入 `bin/<label>/<target>/`，编译单元仅写 `lib/`。测试工作目录及临时目录均位于该目标的 `bin/` 下。每个子进程限时 60 秒，超时或中断会终止进程组并等待退出。

`source.json` 保存构建时的 Params、HttpUtils、直接 Utils/DTF 依赖及 Pascal 测试源哈希，构建前后必须一致；它不是第三方 RTL 的完整依赖清单。`binary.json` 用于验证运行的是对应二进制。运行旧版时允许工作区源码已有变化，并在 `run-source.json` 明确记录 `matches_build=false`，旧版构建身份仍由原 `source.json` 和二进制哈希确定。运行前后再核对工作区关键源码，变化会使本轮验证返回失败。

## 验证结果

2026-10-19：最终 21 项回归在 Delphi Win64/Win32、FPC Win64、WSL Ubuntu-22.04 的 Delphi/FPC Linux64 上共 **105/105 通过**。四个基线目标均为 6 项兼容场景通过、15 项缺陷/计数场景按预期失败；Win32 只执行修复后回归，未补报原版红例。

`before-final` 和 `after-final` 使用同一最终 Pascal 测试源，已记录依赖仅 Params 单元不同。原始源码快照为 `bin/before/Net.CrossHttpParams.pas`，SHA-256 为 `669a3c2c495b4605cd2b3f9584c3a40cc9d6ae632fa7d6c259ad7599715feabd`；修复版为 `813992e1f72ed6a112e632f24e5814e060b18392e6b55a712e1e3c8d740a1886`。

1000 字段的计数流：初始化 Size 查询 **2000 → 1000**，排空查询 **518713 → 1032**；两版均为 34 次 Read、133901 字节。缓存长度与段末偏移，顺序读取递增游标，外部 Seek 对缓存区间二分。Read 只推进实际填入的字节；合法短读补齐，提前 0/负返回报 EReadError。

1000 字段、65536 字节读块，每次排空微秒中位数（五个独立进程样本）：

| 目标 | 内存：改前 → 改后 μs | 混合文件：改前 → 改后 μs |
| --- | ---: | ---: |
| Delphi Win64 | 5268.600 → 26.900 | 295803.200 → 2572.000 |
| FPC Win64 | 2280.100 → 25.900 | 330488.406 → 2643.300 |
| FPC Linux64 | 2197.695 → 28.118 | 326238.406 → 73239.461 |
| Delphi Linux64 | 8051.262 → 58.901 | 351567.139 → 71617.485 |

Linux 文件位于 WSL 的 `/mnt/d`，不能把其文件系统常数成本与 Windows 或原生 ext4 混为一谈。小规模也不宣称普遍变快：FPC Linux64 单字段内存、4096 块，本轮为 3.017 → 4.503 μs（绝对差 1.486 μs）；原始样本完整保留，未剔除该结果。这里验证的是流排空，不是网络吞吐或请求延迟。

视图存活期间字段集合、字段信息、底层流对象和所有权需保持不变；借用的表单和流必须存活到视图释放。每次访问字段校验对象及大小，长度改变显式失败，不支持与外部并发修改。缓存元数据增加 O(字段数) 空间，不缓存正文。该批没有改 Multipart 解码器、Session 或公开方法签名。
