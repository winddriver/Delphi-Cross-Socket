# TLS 容量默认关闭的开销检查

生产基线为 `6fbd712`，对照为本批 O03 TLS 容量最终源码，六项新限额都为 0。只验证 64 KiB/1 MiB、TLS 1.2/1.3 收发，不扩展到全部负载；没有为测量调整生产代码或系统配置。

## 方法与边界

- Delphi/FPC Win64 显式优化构建（`-$O+` / `-O2`），真实 OpenSSL 3.1.2。CPU1/掩码2、QPC计时，沿用已有基准；每个负载128次预热，5对前后交替进程。
- RX 的64KiB每pass512次、1MiB每pass128次；TX每pass256次。1MiB RX预生成同一TLS会话的512MiB顺序密文，避免原最小512次设置一次占用约1.6GiB；生成/握手不在计时内。
- 时间、单次本地调用P99、分配统计分为三个pass；P99为nearest-rank，包含本地计时开销，不是网络P99。分配钩子只统计基准线程的Pascal分配/正大小重分配请求，不含OpenSSL原生堆。
- 旧生产源没有新容量API，基线使用TLS_LIMITS_BASELINE，仅让未运行的容量测试辅助函数不引用该API；本基准不调用这些辅助函数。两个版本都实际收发/验证相同明文。
- 以下时间为微秒；IQR为Q3-Q1，五对样本均保留，没有剔除异常值。累计请求量不是峰值RSS。

## 首轮完整窄矩阵

| 编译器 | 路径/版本/大小 | 前版中位数 / IQR | 后版中位数 / IQR | 变化 | 本地P99前/后 | 分配调用前=后 | 请求字节前=后 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Delphi | RX / 1.2 / 64KiB | 22.47 / 4.29 | 22.45 / 0.28 | -0.07% | 31.70 / 27.60 | 7 | 327864 |
| Delphi | RX / 1.2 / 1MiB | 972.33 / 30.21 | 968.35 / 34.01 | -0.41% | 1245.40 / 1162.60 | 22 | 1.11415e+07 |
| Delphi | RX / 1.3 / 64KiB | 24.07 / 0.25 | 24.71 / 1.75 | +2.65% | 29.80 / 33.90 | 7 | 327864 |
| Delphi | RX / 1.3 / 1MiB | 1001.60 / 16.66 | 997.45 / 46.07 | -0.41% | 1274.10 / 1250.50 | 22 | 1.11415e+07 |
| Delphi | TX / 1.2 / 64KiB | 39.09 / 1.04 | 39.74 / 4.43 | +1.67% | 44.40 / 57.80 | 10 | 148264 |
| Delphi | TX / 1.2 / 1MiB | 1065.83 / 9.82 | 1068.94 / 23.62 | +0.29% | 1312.50 / 1389.10 | 10 | 2.11782e+06 |
| Delphi | TX / 1.3 / 64KiB | 39.62 / 0.63 | 39.82 / 0.75 | +0.52% | 45.90 / 61.20 | 10 | 148208 |
| Delphi | TX / 1.3 / 1MiB | 1095.22 / 7.67 | 1194.69 / 173.75 | +9.08% | 1313.10 / 1515.90 | 10 | 2.11693e+06 |
| FPC | RX / 1.2 / 64KiB | 23.32 / 0.53 | 23.62 / 0.24 | +1.32% | 29.30 / 28.70 | 7 | 327864 |
| FPC | RX / 1.2 / 1MiB | 1230.48 / 41.69 | 1628.66 / 352.29 | +32.36% | 1379.00 / 2090.40 | 22 | 1.11415e+07 |
| FPC | RX / 1.3 / 64KiB | 25.00 / 0.24 | 24.94 / 0.37 | -0.25% | 30.30 / 33.50 | 7 | 327864 |
| FPC | RX / 1.3 / 1MiB | 1279.73 / 13.98 | 1286.79 / 39.39 | +0.55% | 1649.30 / 1712.80 | 22 | 1.11415e+07 |
| FPC | TX / 1.2 / 64KiB | 38.72 / 0.18 | 39.52 / 1.58 | +2.06% | 44.10 / 47.30 | 10 | 148264 |
| FPC | TX / 1.2 / 1MiB | 852.18 / 21.64 | 845.15 / 27.78 | -0.82% | 1066.90 / 1115.80 | 10 | 2.11782e+06 |
| FPC | TX / 1.3 / 64KiB | 41.49 / 2.75 | 42.45 / 0.93 | +2.32% | 47.90 / 56.60 | 10 | 148208 |
| FPC | TX / 1.3 / 1MiB | 887.04 / 9.13 | 902.18 / 85.04 | +1.71% | 1061.20 / 1085.10 | 10 | 2.11693e+06 |

## 两个波动负载的定向复测

首轮两项偏慢，先定向重复，再协调其他任务暂停重型构建/测试，在独占窗口用同一二进制再做5对。未改变亲和性或采样参数，也未根据结果调整生产代码。

| 负载 | 首轮变化 | 定向重复变化 | 独占窗口变化 | 独占前/后 IQR占中位数 |
| --- | ---: | ---: | ---: | ---: |
| Delphi TLS1.3 TX 1MiB | +9.08% | -2.05% | +0.08% | 2.49% / 1.29% |
| FPC TLS1.2 RX 1MiB | +32.36% | +27.48% | -1.04% | 11.63% / 10.56% |

独占窗口未复现稳定回退，因此保留生产实现。FPC的1MiB接收在该窗口中两版绝对中位数都上移到约1.26/1.25ms，仍有约11%的IQR；本轮不能排除所有小幅差异，也不能把首轮的+32%直接归因于容量分支。16个首轮负载的分配/重分配调用数和累计申请量完全一致，O06减少申请量的效果未被默认关闭的额度覆盖。

## 证据

- `bin/limits-default-baseline/production/`：6fbd712生产快照。
- `bin/limits-default-before/`、`bin/limits-default-after/`：两编译器的基准二进制、source.json和每轮日志。
- `bin/limits-default-results-{default0,recheck-tx,recheck-rx,quiet-tx,quiet-rx}/`：所有配对原始样本、中位数、四分位数、P99和实际二进制哈希。
- `bin/limits-default-manifest.json`：本次基准独立汇总。此前容量正确性证据`bin/limits-final-manifest.json`保持原样；基准新增模式使测试主程序哈希变化，不将旧正确性二进制描述为新增基准版本。

复现示例：

```powershell
python -B run_buffer_bench.py --artifact-label limits-default --baseline-label limits-default-baseline --baseline-ref 6fbd712 --build before --targets win64 fpc64
python -B run_buffer_bench.py --artifact-label limits-default --baseline-label limits-default-baseline --baseline-ref 6fbd712 --build after --targets win64 fpc64
python -B run_buffer_bench.py --artifact-label limits-default --baseline-label limits-default-baseline --baseline-ref 6fbd712 --compare --rounds 5 --run-label default0 --targets win64 fpc64 --modes bench-large-rx12 bench-large-rx13 bench-large-tx12 bench-large-tx13
```
