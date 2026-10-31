# TLS 1.2 / TLS 1.3 加密套件配置计划

- 日期：2026-09-06。
- 状态：实施完成，OpenSSL 验收通过；mbedTLS 运行验证受现有静态对象缺失限制。
- 仓库：`D:\GitHub\Delphi-Cross-Socket`。
- 当前 master：`67c5f6b2697776fcb2d19c80afd7726ed338c739`。
- 实施基线：项目当前源码；本功能独立设计，不依赖任何已有 PR 或作者分支。
- OpenSSL 范围：1.1.1 及以上，包含项目支持的 3.x。
- 本文保留设计阶段代码示例；最终实现以项目源码为准，实际验证结果和实施调整见第 13 节。

## 1. 目标和范围

允许 `ICrossSslSocket` 调用方在首次 SSL 连接创建前，分别完整指定 TLS 1.2 和 TLS 1.3 的加密套件策略，客户端和服务端共用同一组配置入口。

接口采用对称命名 `SetTls12CipherSuites` 和 `SetTls13CipherSuites`：名称直接说明协议版本和配置对象，不要求调用方记忆 OpenSSL 的 list/suites 差别，不提供含糊的旧命名别名。

“完整配置”指两个版本的套件策略均可由调用方覆盖，不是新增所有 TLS 参数配置。本次增加两组公开默认常量，并用于 OpenSSL 上下文初始化；无需调用 setter 的用户采用新的现代通用默认值。不增加协议版本范围、签名算法、密钥交换组或 HTTP 客户端配置转发 API；不实现 OpenSSL 规则到 mbedTLS 的转换，也不增加自动重试。

代码注释用中文；异常文本沿用项目当前英文风格。不增加第三方依赖，不修改 OpenSSL 或 mbedTLS 源码。

**用户明确约束：禁止修改、替换或重写任何已有 FPC 配置文件（包括 fpc.cfg、my.cfg 及其 include），也不修改全局 Lazarus 环境配置。** 测试源通过本项目测试工程的显式文件引用选定；本轮及实施阶段都遵守这一约束。此前尚未改动任何 FPC 配置文件。

## 2. 已核实的现状

| 位置（当前 master） | 现状及影响 |
| --- | --- |
| `Net/Net.CrossSslSocket.Base.pas:57` | `ICrossSslSocket` 尚未公开两种协议的套件配置方法。 |
| `Net/Net.CrossSslSocket.Base.pas:311` | `BeginTlsConfigUpdate` 已检查配置锁和配置有效性，`finally` 必须配对解锁。 |
| `Net/Net.CrossSslSocket.Base.pas:331` | `LockTlsConfiguration` 会拒绝已失效配置；首次 SSL 连接创建会进入这条路径。 |
| `Net/Net.CrossSslSocket.Base.pas:345` | 已有 `InvalidateTlsConfiguration`，无需另造状态字段。 |
| `Net/Net.CrossSslSocket.MbedTls.pas:117` | 后端继承公共基类，新增方法应有默认明确拒绝实现，不增加抽象槽。 |
| `Net/Net.CrossSslSocket.OpenSSL.pas:975` | 上下文初始化分别配置 TLS 1.2 与 TLS 1.3，协议范围为 TLS 1.2–1.3。 |
| `Net/Net.CrossSslSocket.OpenSSL.pas:175` | 已有 `CROSS_OPENSSL_SELFTEST` 条件测试入口，可沿用，避免公开原生上下文。 |
| `Net/Net.OpenSSL.pas:2169` | `GetOpenSslErrors` 消费当前线程 OpenSSL 错误队列，可直接复用。 |
| `Net/Net.OpenSSL.pas:3141` | `TSSLTools.GetCipherList` 可读取原生 SSL 对象的套件列表，可用于真实状态断言。 |

另一个必须处理的问题：OpenSSL 3.0.18 的 `SSL_CTX_set_cipher_list` 源码明确说明，无匹配套件时可能先更新 `ctx->cipher_list`，再返回 0。不能向调用者承诺“抛异常后原配置完全不变”。

参考：

- [OpenSSL API 文档](https://docs.openssl.org/3.0/man3/SSL_CTX_set_cipher_list/)：两个函数分别配置 TLS 1.2 及更早版本和 TLS 1.3；未知项可能被忽略，不能承诺逐项严格校验。
- [OpenSSL 1.1.1 API 文档](https://docs.openssl.org/1.1.1/man3/SSL_CTX_set_cipher_list/)：确认最低支持版本提供两个函数；原生 TLS 1.3 API 允许空列表，本包装接口的空字符串行为另行定义。
- [OpenSSL cipher 规则](https://docs.openssl.org/1.1.1/man1/ciphers/)：`@SECLEVEL=n` 改变上下文安全级别，可能间接影响另一协议版本的握手。
- [OpenSSL 3.0.18 ssl_lib.c](https://github.com/openssl/openssl/blob/openssl-3.0.18/ssl/ssl_lib.c)：`SSL_CTX_set_cipher_list` 内关于失败后列表已经更新的注释。

## 3. 方案选择

| 方案 | 优点 | 代价 | 建议 |
| --- | --- | --- | --- |
| 公共接口增加方法；基类默认明确不支持；OpenSSL 覆盖 | 调用直接，变更小，mbedTLS 不会留下新增抽象槽 | 需要全量重编译接口使用者 | 推荐 |
| 新增独立能力接口，通过 Supports 查询 | 能设计旧接口 ABI 兼容策略 | 调用和维护成本更高，需新的接口及 GUID | 仅在必须混用旧 BPL/DLL 时选择 |
| 同时实现 mbedTLS 配置及 OpenSSL 规则转换 | 两后端都可配置 | 规则表达能力不等价，范围明显扩大 | 本次不采用 |

原生 setter 失败后的两个选择：

- 推荐复用 `InvalidateTlsConfiguration`，明确抛 `ESslContextInvalid`，要求释放并重建 socket。这个策略保守，但简单且与现有 CA 更新失败处理一致。
- 两个 setter 统一采用失败后重建对象的保守契约；这不表示两个原生函数的失败路径完全相同。不实现“备份配置—尝试更新—回滚”事务机制，也不创建临时上下文推断真实上下文必定可接受配置。若后续确有失败后原对象可恢复的需求，单独设计并验证。

### 接口兼容性约定

推荐方案按源码库升级处理：在 `ICrossSslSocket` 已有方法的末尾追加方法，暂保持现有 IID，不改已有方法顺序。所有引用它的单元、派生接口、DCU/PPU、BPL/DLL 必须从同一源码版本全量重编译。`ICrossServer`、`ICrossHttpClientSocket` 等派生接口的方法槽也会受影响，不能只重编译新 API 的直接调用者。

**不承诺新旧二进制混用兼容。** 若用户要求跨 DLL/BPL 保持旧 ABI，停止按此推荐实施，先把方案改为独立扩展接口和新的 IID；不能仅靠“追加方法”或“替换一个 GUID”宣称派生接口安全。

## 4. 确定 API 行为

| 新接口 | 参数含义 | 原生映射 |
| --- | --- | --- |
| `SetTls12CipherSuites(const ACipherRules: string)` | TLS 1.2 套件规则；允许名称、别名、排除和排序表达式 | `SSL_CTX_set_cipher_list` |
| `SetTls13CipherSuites(const ACipherSuites: string)` | TLS 1.3 套件名称，冒号分隔，顺序表示优先级 | `SSL_CTX_set_ciphersuites` |

两个接口使用相同的 `CipherSuites` 名称描述业务对象，差异直接体现在 `Tls12` / `Tls13`，参数名称则明确“规则”与“名称列表”的语法区别。

| 输入/状态 | 结果 |
| --- | --- |
| `Ssl=False` | 无操作，沿用现有证书配置方法风格。 |
| 两接口传空字符串 `''` | 无操作，保留当前配置；不是恢复默认值，也不是禁用协议。即使配置已锁定也不作修改。原生 TLS 1.3 API 虽接受空列表，本包装层不传递空字符串。 |
| TLS 1.2，非空规则，原生 API 配置成功 | 替换 TLS 1.2 名单，不直接改 TLS 1.3 名单。规则含 `@SECLEVEL` 时会改变全局安全级别，可能间接影响 TLS 1.3 握手。 |
| TLS 1.3，非空名称列表，原生 API 配置成功 | 替换 TLS 1.3 名单，不改 TLS 1.2 名单，也不重置安全级别。不能使用 HIGH、!aNULL 等作为 TLS 1.3 规则。 |
| 有效项与未知项混合 | 沿用 OpenSSL 规则语义，未知项可能被忽略；不承诺逐项拼写检查。 |
| 字符串传递 | 转为 AnsiString 后交给 OpenSSL，不增加逐字符校验。遵循原生 C 字符串语义，遇到 NUL 时结束；不承诺非 ASCII 输入无损转换。 |
| 首次 SSL 连接创建后调用非空配置 | 现有配置锁抛 `ECrossSocket`，不修改原生上下文。 |
| 任一个 OpenSSL 原生 setter 返回失败 | 标记整个 socket 的 TLS 配置无效，收集本次错误队列，抛 `ESslContextInvalid`；必须重建对象。 |
| 配置已无效后调用任一 setter 的非空配置/创建 SSL 连接 | 由已有有效性检查拒绝；不能改用另一版本的 setter 绕过失效状态。 |
| mbedTLS/未覆盖此方法的自定义后端，SSL 开启且配置非空 | 基类抛明确“不支持”异常；不静默忽略，不调用抽象方法。 |

“setter 成功”只证明该规则产生了可用列表，不证明证书、协议、对端或安全级别一定允许实际握手，也不等于完整的 FIPS/PCI 配置认证。

TLS 1.3 不提供 OpenSSL TLS 1.2 规则解释能力，但混合列表中的未知名称仍可能被原生 API 忽略，不能把“不是支持的语法”写成“包含该项就一定抛错”。测试分别验证全无效和有效/未知混合输入。

两个调用分别持有配置锁，不承诺一组双版本更新整体原子提交。调用方必须完成全部配置后才发布 socket 或开始连接；第二次更新失败时对象整体失效，不继续使用第一次更新的结果。

## 5. 拟实施的完整生产代码

### 5.0 两组默认套件常量与初始化

“最佳”按现代通用客户端/服务端的安全性、性能和互通性平衡定义，不声称同一排序适合所有硬件、私有协议或合规环境。默认值不含 @SECLEVEL，不隐式修改全局安全级别；实际可协商结果还受运行库构建、provider、证书及对端约束。

在 `Net/Net.CrossSslSocket.Types.pas` 的 interface 区、uses 后、type 前加入公开常量，供初始化和调用方显式恢复默认时共用：

```pascal
const
  // TLS 1.3：沿用 OpenSSL 1.1.1 的三项通用默认套件及顺序。
  DEFAULT_TLS13_CIPHER_SUITES =
    'TLS_AES_256_GCM_SHA384:' +
    'TLS_CHACHA20_POLY1305_SHA256:' +
    'TLS_AES_128_GCM_SHA256';

  // TLS 1.2：仅使用 ECDHE + AEAD，兼容 RSA 和 ECDSA 证书。
  // AES-128-GCM 优先；保留 ChaCha20-Poly1305 和 AES-256-GCM。
  DEFAULT_TLS12_CIPHER_SUITES =
    'ECDHE-RSA-AES128-GCM-SHA256:' +
    'ECDHE-ECDSA-AES128-GCM-SHA256:' +
    'ECDHE-RSA-CHACHA20-POLY1305:' +
    'ECDHE-ECDSA-CHACHA20-POLY1305:' +
    'ECDHE-RSA-AES256-GCM-SHA384:' +
    'ECDHE-ECDSA-AES256-GCM-SHA384';
```

选择依据与取舍：

- TLS 1.3 三项采用 [OpenSSL 1.1.1 官方默认值](https://docs.openssl.org/1.1.1/man3/SSL_CTX_set_cipher_list/)，去掉当前库额外加入的 CCM 与 CCM_8。它们不是一律不可用，但不纳入通用网络库默认策略。
- TLS 1.2 使用 ECDHE 提供前向保密，数据保护采用 AEAD；AES-GCM 选择与 [RFC 9325 §4.2](https://www.rfc-editor.org/rfc/rfc9325.html#section-4.2) 一致，补充 OpenSSL 1.1.1+ 支持的 ChaCha20-Poly1305。
- 六项集合与 [TLSRef 通用配置生成器](https://configurator.tlsref.org/) 的现代 TLS 1.2 选择方向一致；此处 RSA AES-128-GCM 优先及随后排序是本项目的通用折中，不宣称逐项复制外部配置顺序。TLS 1.3 的排序沿用 OpenSSL 默认，两个协议不需要强行相同排序。
- 不包含 CBC、静态 RSA 密钥交换、DSS、3DES、RC4、匿名套件或 HIGH/DEFAULT 等宽泛别名。这里的 ECDHE-RSA 是 RSA 身份认证加 ECDHE 密钥交换，不等于静态 RSA 密钥交换。
- 不纳入有限域 DHE，避免默认依赖额外 DH 参数并扩大策略；不限制只能使用某一种证书，RSA/ECDSA 两组都保留。
- 默认收紧会影响仅支持旧套件或 CCM 的端点，必须在变更说明中披露；调用方可以在首个连接前显式传入其所需配置。不要用静默回退到 HIGH 解决兼容性问题。
- 两组常量是 OpenSSL 后端的默认策略；mbedTLS 继续沿用其既有默认行为，两种新配置方法仍明确不支持。

默认套件初始化复用新增的两个配置方法，删除重复的编码转换、原生调用和错误处理；保留原先先 TLS 1.3、后 TLS 1.2 的顺序：

```pascal
  SetTls13CipherSuites(DEFAULT_TLS13_CIPHER_SUITES);
  SetTls12CipherSuites(DEFAULT_TLS12_CIPHER_SUITES);
```

此时基类的配置锁和有效性状态已初始化，SSL_CTX 也已建立，尚未创建连接。直接调用当前对象的方法，不转换为接口引用，避免构造期间触发接口引用计数。方法为虚方法，派生类覆盖时也可能在基类构造期间被调用，不应依赖尚未初始化的派生类字段。

最低协议版本保持 TLS 1.2，检查设置返回值；不再调用最大版本 setter，保留运行库和系统配置的上限策略。其他上下文选项保持不变。原生设置失败就让构造失败，不返回部分初始化的可用 socket；按既有构造失败/析构路径释放上下文和库引用，并以故障注入或受控缺算法环境验证资源清理。不重复释放已由构造失败析构接管的对象。

显式恢复各版本名单用对应常量，不改变空字符串“无操作”的约定：

```pascal
LSocket.SetTls12CipherSuites(DEFAULT_TLS12_CIPHER_SUITES);
LSocket.SetTls13CipherSuites(DEFAULT_TLS13_CIPHER_SUITES);
```

恢复名单不会重置调用方先前通过 @SECLEVEL 修改的安全级别，也不能恢复已经失效或已锁定的对象。

### 5.1 `Net/Net.CrossSslSocket.Base.pas`：公开接口

在 `ICrossSslSocket` 最后一个方法 `SetPrivateKeyFile` 后、属性声明前追加下面声明。不要在 `SetVerifyPeer` 后插入，以免移动同接口已有后续方法槽。

```pascal
    /// <summary>
    ///   配置 TLS 1.2 加密套件，使用 OpenSSL 规则表达式。
    /// </summary>
    /// <remarks>
    ///   当前仅 OpenSSL 后端支持，使用 OpenSSL cipher-list 规则。
    ///   必须在首个 SSL 连接创建前调用；空字符串不修改当前配置，
    ///   也不会恢复默认配置。未启用 SSL 时不执行配置。
    ///   未知规则项可能被 OpenSSL 忽略，仅无匹配套件等原生错误会失败。
    ///   OpenSSL 原生更新失败后，此 socket 的 TLS 配置失效，必须重建对象。
    ///   其他后端对非空配置明确抛出不支持异常。
    ///   不直接修改 TLS 1.3 套件名单；规则中的 @SECLEVEL 可改变全局安全级别。
    /// </remarks>
    procedure SetTls12CipherSuites(const ACipherRules: string);

    /// <summary>
    ///   配置 TLS 1.3 加密套件，名称按优先顺序用冒号分隔。
    /// </summary>
    /// <remarks>
    ///   当前仅 OpenSSL 后端支持。首次 SSL 连接创建后不能修改。
    ///   空字符串不操作，不恢复默认配置，也不禁用 TLS 1.3。
    ///   未知名称可能被忽略；不支持 TLS 1.2 的 HIGH、排除等规则语法。
    ///   原生更新失败后整个 socket 的 TLS 配置失效，必须重建对象。
    ///   不修改 TLS 1.2 名单，不重置全局安全级别。
    /// </remarks>
    procedure SetTls13CipherSuites(const ACipherSuites: string);
```

将接口上方原有“首个 SSL 连接创建后……”说明中的配置范围补上 cipher list。

在 `TCrossSslSocketBase` 的 public 区域新增两个非抽象方法：

```pascal
    procedure SetTls12CipherSuites(const ACipherRules: string); virtual;
    procedure SetTls13CipherSuites(const ACipherSuites: string); virtual;
```

在 implementation 中、`SetVerifyPeer` 实现附近新增完整默认实现：

```pascal
procedure TCrossSslSocketBase.SetTls12CipherSuites(const ACipherRules: string);
begin
  if not Ssl or (ACipherRules = '') then Exit;

  BeginTlsConfigUpdate;
  try
    raise ECrossSocket.CreateFmt(
      '%s does not support TLS 1.2 cipher-suite configuration.',
      [ClassName]);
  finally
    EndTlsConfigUpdate;
  end;
end;

procedure TCrossSslSocketBase.SetTls13CipherSuites(const ACipherSuites: string);
begin
  if not Ssl or (ACipherSuites = '') then Exit;

  BeginTlsConfigUpdate;
  try
    raise ECrossSocket.CreateFmt(
      '%s does not support TLS 1.3 cipher-suite configuration.',
      [ClassName]);
  finally
    EndTlsConfigUpdate;
  end;
end;
```

这段默认实现直接覆盖 mbedTLS 和未实现配置的第三方派生类，不需在 mbedTLS 类中再添加一份相同方法。

### 5.2 `Net/Net.CrossSslSocket.OpenSSL.pas`：完整覆盖实现

在 `TCrossOpenSslSocket` public 区域新增两个覆盖声明：

```pascal
    // 配置 TLS 1.2 套件列表，沿用首次连接前的配置锁。
    procedure SetTls12CipherSuites(const ACipherRules: string); override;
    // 配置 TLS 1.3 套件名称列表，沿用同一配置锁。
    procedure SetTls13CipherSuites(const ACipherSuites: string); override;
```

新增以下完整实现，不引入通用配置框架或接口别名：

```pascal
procedure TCrossOpenSslSocket.SetTls12CipherSuites(const ACipherRules: string);
var
  LAnsi: AnsiString;
  LError: string;
begin
  if not Ssl or (ACipherRules = '') then Exit;

  BeginTlsConfigUpdate;
  try
    if FSslCtx = nil then
    begin
      InvalidateTlsConfiguration;
      raise ESslContextInvalid.Create('SetTls12CipherSuites: SSL context is nil.');
    end;

    LAnsi := AnsiString(ACipherRules);
    ERR_clear_error();
    try
      if SSL_CTX_set_cipher_list(FSslCtx, PAnsiChar(LAnsi)) <> 1 then
      begin
        // 原生 API 可能已改变名单或安全级别，失败后禁止继续创建连接。
        InvalidateTlsConfiguration;
        LError := GetOpenSslErrors;
        raise ESslContextInvalid.CreateFmt(
          'SetTls12CipherSuites failed; recreate the socket before using TLS: %s.',
          [LError]);
      end;
    finally
      // 清理本次调用的错误状态，避免污染同线程后续 OpenSSL 操作。
      ERR_clear_error();
    end;
  finally
    EndTlsConfigUpdate;
  end;
end;
```

TLS 1.3 对应实现：

```pascal
procedure TCrossOpenSslSocket.SetTls13CipherSuites(const ACipherSuites: string);
var
  LAnsi: AnsiString;
  LError: string;
begin
  // 明确选择空串不操作，不使用原生 API 的空列表语义。
  if not Ssl or (ACipherSuites = '') then Exit;

  BeginTlsConfigUpdate;
  try
    if FSslCtx = nil then
    begin
      InvalidateTlsConfiguration;
      raise ESslContextInvalid.Create('SetTls13CipherSuites: SSL context is nil.');
    end;

    LAnsi := AnsiString(ACipherSuites);
    ERR_clear_error();
    try
      if SSL_CTX_set_ciphersuites(FSslCtx, PAnsiChar(LAnsi)) <> 1 then
      begin
        // 两版本统一采用原生更新失败后重建对象的保守契约。
        InvalidateTlsConfiguration;
        LError := GetOpenSslErrors;
        raise ESslContextInvalid.CreateFmt(
          'SetTls13CipherSuites failed; recreate the socket before using TLS: %s.',
          [LError]);
      end;
    finally
      ERR_clear_error();
    end;
  finally
    EndTlsConfigUpdate;
  end;
end;
```

套件配置直接使用现有绑定；为完成 OpenSSL 1.1.1 验证，按第 13 节增加最小的 RSA 宏兼容封装。`_InitSslCtx` 按第 5.0 节使用两组默认常量并检查返回值；上述 setter 继续用于初始化后的调用方覆盖。锁、失效标记、错误类型和错误队列函数均已存在。

### 5.3 仅用于测试的原生配置读取入口

在 `Net.CrossSslSocket.OpenSSL.pas` 现有 interface 的 `CROSS_OPENSSL_SELFTEST` 区域加入：

```pascal
function CrossOpenSslSelfTest_GetCipherList(
  const ASocket: TCrossOpenSslSocket): TArray<string>;
function CrossOpenSslSelfTest_GetSecurityLevel(
  const ASocket: TCrossOpenSslSocket): Integer;
```

在 implementation 的同类条件区域加入完整实现：

```pascal
function CrossOpenSslSelfTest_GetCipherList(
  const ASocket: TCrossOpenSslSocket): TArray<string>;
var
  LSsl: PSSL;
begin
  // 仅供首次连接前的配置测试使用；不对生产代码公开上下文指针。
  ASocket.BeginTlsConfigUpdate;
  try
    ERR_clear_error();
    LSsl := SSL_new(ASocket.FSslCtx);
    if LSsl = nil then
      raise ESsl.CreateFmt('SSL_new failed in cipher test: %s',
        [GetOpenSslErrors]);
    try
      Result := TSSLTools.GetCipherList(LSsl);
    finally
      SSL_free(LSsl);
      ERR_clear_error();
    end;
  finally
    ASocket.EndTlsConfigUpdate;
  end;
end;
```

同一条件编译区再加入安全级别读取实现；绑定已经存在，不增加生产 API：

```pascal
function CrossOpenSslSelfTest_GetSecurityLevel(
  const ASocket: TCrossOpenSslSocket): Integer;
begin
  ASocket.BeginTlsConfigUpdate;
  try
    Result := SSL_CTX_get_security_level(ASocket.FSslCtx);
  finally
    ASocket.EndTlsConfigUpdate;
  end;
end;
```

这些入口读取真实原生配置；不靠字符串字段或 mock 证明 setter 已生效。不在 production 配置定义 `CROSS_OPENSSL_SELFTEST`。

## 6. 拟新增的定向测试代码

新增 `Net/Tests/FPC/TlsCipherSuitesTests/TlsCipherSuitesTests.lpr`，采用现有独立控制台测试风格，并把待测单元及其本仓库依赖通过 uses-in 加入测试工程。下列完整程序草案以 Windows 为基准，可条件选择 OpenSSL/mbedTLS；不能把仅编译 OpenSSL 分支称为双后端通过。其他平台需替换对应平台的显式单元清单。

```pascal
program TlsCipherSuitesTests;

{$I ..\..\..\..\zLib.inc}

uses
  SysUtils,
  Classes
  {$IFDEF FPC}
  ,DTF.RTL in '..\..\..\..\DelphiToFPC\DTF.RTL.pas'
  ,DTF.Types in '..\..\..\..\DelphiToFPC\DTF.Types.pas'
  ,DTF.Consts in '..\..\..\..\DelphiToFPC\DTF.Consts.pas'
  ,DTF.Character in '..\..\..\..\DelphiToFPC\DTF.Character.pas'
  ,DTF.Diagnostics in '..\..\..\..\DelphiToFPC\DTF.Diagnostics.pas'
  ,DTF.Generics in '..\..\..\..\DelphiToFPC\DTF.Generics.pas'
  {$ENDIF}
  ,Utils.StrUtils in '..\..\..\..\Utils\Utils.StrUtils.pas'
  ,Utils.SyncObjs in '..\..\..\..\Utils\Utils.SyncObjs.pas'
  ,Utils.Rtti in '..\..\..\..\Utils\Utils.Rtti.pas'
  ,Utils.DateTime in '..\..\..\..\Utils\Utils.DateTime.pas'
  ,Utils.AnonymousThread in '..\..\..\..\Utils\Utils.AnonymousThread.pas'
  ,Utils.Utils in '..\..\..\..\Utils\Utils.Utils.pas'
  ,Utils.IOUtils in '..\..\..\..\Utils\Utils.IOUtils.pas'
  ,Net.Winsock2 in '..\..\..\Net.Winsock2.pas'
  ,Net.Wship6 in '..\..\..\Net.Wship6.pas'
  ,Net.SocketAPI in '..\..\..\Net.SocketAPI.pas'
  ,Net.CrossSocket.Base in '..\..\..\Net.CrossSocket.Base.pas'
  ,Net.CrossSocket.Iocp in '..\..\..\Net.CrossSocket.Iocp.pas'
  ,Net.CrossSocket in '..\..\..\Net.CrossSocket.pas'
  ,Net.CrossSslSocket.Types in '..\..\..\Net.CrossSslSocket.Types.pas'
  ,Net.CrossSslSocket.Base in '..\..\..\Net.CrossSslSocket.Base.pas'
  {$IFDEF __MBED_TLS__}
  ,Net.MbedTls in '..\..\..\Net.MbedTls.pas'
  ,Net.MbedBIO in '..\..\..\Net.MbedBIO.pas'
  ,Net.CrossSslSocket.MbedTls in '..\..\..\Net.CrossSslSocket.MbedTls.pas'
  {$ELSE}
  ,Net.OpenSSL in '..\..\..\Net.OpenSSL.pas'
  ,Net.CrossSslSocket.OpenSSL in '..\..\..\Net.CrossSslSocket.OpenSSL.pas'
  {$ENDIF}
  ,Net.CrossSslSocket in '..\..\..\Net.CrossSslSocket.pas'
  ;

type
  TTestProc = reference to procedure;

  TTestSslSocket = class(TCrossSslSocket)
  public
    procedure FreezeConfiguration;
  end;

procedure TTestSslSocket.FreezeConfiguration;
begin
  LockTlsConfiguration;
end;

procedure Check(const AValue: Boolean; const AMessage: string);
begin
  if not AValue then raise Exception.Create(AMessage);
end;

procedure ExpectError(const AClass: ExceptClass; const AProc: TTestProc;
  const AMessage: string);
begin
  try
    AProc();
  except
    on E: Exception do
    begin
      if not E.InheritsFrom(AClass) then raise;
      Exit;
    end;
  end;
  raise Exception.Create(AMessage);
end;

procedure TestDisabled;
var
  LApi: ICrossSslSocket;
begin
  LApi := TTestSslSocket.Create(0, False);
  LApi.SetTls12CipherSuites('');
  LApi.SetTls12CipherSuites('UNKNOWN');
  LApi.SetTls13CipherSuites('');
  LApi.SetTls13CipherSuites('UNKNOWN');
  LApi := nil;
end;

{$IFNDEF __MBED_TLS__}
function CipherText(const AItems: TArray<string>;
  const ATls13: Boolean): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Length(AItems) - 1 do
    if (Copy(AItems[I], 1, 4) = 'TLS_') = ATls13 then
    begin
      if Result <> '' then Result := Result + ':';
      Result := Result + AItems[I];
    end;
end;

procedure TestDefaults;
var
  LObj: TTestSslSocket;
  LApi: ICrossSslSocket;
  LActual: TArray<string>;
begin
  LObj := TTestSslSocket.Create(0, True);
  LApi := LObj;
  try
    // 尚未调用 setter，检查构造函数确实应用默认常量。
    LActual := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LActual, False) = DEFAULT_TLS12_CIPHER_SUITES,
      '初始化的 TLS 1.2 默认名单或顺序不正确');
    Check(CipherText(LActual, True) = DEFAULT_TLS13_CIPHER_SUITES,
      '初始化的 TLS 1.3 默认名单或顺序不正确');
    Check(Length(LActual) = 9, '默认名单不是 TLS 1.2 六项加 TLS 1.3 三项');

    LApi.SetTls12CipherSuites('ECDHE-RSA-AES128-GCM-SHA256');
    LApi.SetTls13CipherSuites('TLS_AES_128_GCM_SHA256');
    LApi.SetTls12CipherSuites(DEFAULT_TLS12_CIPHER_SUITES);
    LApi.SetTls13CipherSuites(DEFAULT_TLS13_CIPHER_SUITES);
    LActual := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LActual, False) = DEFAULT_TLS12_CIPHER_SUITES,
      '未能显式恢复 TLS 1.2 默认名单');
    Check(CipherText(LActual, True) = DEFAULT_TLS13_CIPHER_SUITES,
      '未能显式恢复 TLS 1.3 默认名单');
  finally
    LApi := nil;
  end;
end;

procedure TestOpenSsl;
const
  CIPHER = 'ECDHE-RSA-AES128-GCM-SHA256';
var
  LObj: TTestSslSocket;
  LApi: ICrossSslSocket;
  LBefore, LAfter: TArray<string>;
begin
  LObj := TTestSslSocket.Create(0, True);
  LApi := LObj;
  try
    LBefore := CrossOpenSslSelfTest_GetCipherList(LObj);
    LApi.SetTls12CipherSuites(CIPHER);
    LAfter := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LAfter, False) = CIPHER, 'TLS 1.2 列表未生效');
    Check(CipherText(LBefore, True) = CipherText(LAfter, True),
      'TLS 1.3 列表发生变化');

    LApi.SetTls12CipherSuites('');
    LAfter := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LAfter, False) = CIPHER, '空字符串错误地重置了配置');

    LApi.SetTls12CipherSuites(CIPHER + ':CROSS_SOCKET_UNKNOWN_CIPHER');
    LAfter := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LAfter, False) = CIPHER, '混合规则未遵循 OpenSSL 语义');

    LApi.SetTls12CipherSuites(CIPHER);
    Check(ERR_get_error() = 0, '成功路径遗留 OpenSSL 错误');

    // 第一种顺序：先配 TLS 1.2，再配 TLS 1.3。
    LApi.SetTls13CipherSuites('TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384');
    LAfter := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LAfter, False) = CIPHER, 'TLS 1.3 setter 改动了 TLS 1.2 名单');
    Check(CipherText(LAfter, True) =
      'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384', 'TLS 1.3 名单或顺序错误');

    LObj.FreezeConfiguration;
    ExpectError(ECrossSocket,
      procedure begin LApi.SetTls12CipherSuites('HIGH'); end,
      '冻结后仍能修改配置');
    ExpectError(ECrossSocket,
      procedure begin LApi.SetTls13CipherSuites('TLS_AES_128_GCM_SHA256'); end,
      '冻结后仍能修改 TLS 1.3');
    LApi.SetTls12CipherSuites('');
    LApi.SetTls13CipherSuites('');
  finally
    // 引用计数负责销毁，不能再对 LObj 调 Free。
    LApi := nil;
  end;

  LObj := TTestSslSocket.Create(0, True);
  LApi := LObj;
  try
    LApi.SetTls12CipherSuites(CIPHER);
    ExpectError(ESslContextInvalid,
      procedure begin LApi.SetTls12CipherSuites('CROSS_SOCKET_UNKNOWN_CIPHER'); end,
      '无匹配套件未使配置失效');
    Check(ERR_get_error() = 0, '失败路径遗留 OpenSSL 错误');
    ExpectError(ECrossSocket,
      procedure begin LApi.SetTls12CipherSuites(CIPHER); end,
      '失效对象错误地接受了后续更新');
    ExpectError(ECrossSocket,
      procedure begin LApi.SetTls13CipherSuites('TLS_AES_128_GCM_SHA256'); end,
      'TLS 1.2 失败后仍接受 TLS 1.3 更新');
    ExpectError(ECrossSocket,
      procedure begin LObj.FreezeConfiguration; end,
      '失效对象仍可进入创建 SSL 连接前的配置检查');
  finally
    LApi := nil;
  end;
end;

procedure TestTls13;
const
  CIPHER12 = 'ECDHE-RSA-AES128-GCM-SHA256';
  CIPHER13 = 'TLS_AES_128_GCM_SHA256';
var
  LObj: TTestSslSocket;
  LApi: ICrossSslSocket;
  LBefore, LAfter: TArray<string>;
begin
  LObj := TTestSslSocket.Create(0, True);
  LApi := LObj;
  try
    LBefore := CrossOpenSslSelfTest_GetCipherList(LObj);
    LApi.SetTls13CipherSuites(CIPHER13);
    LAfter := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LAfter, True) = CIPHER13, 'TLS 1.3 单项配置未生效');
    Check(CipherText(LBefore, False) = CipherText(LAfter, False),
      'TLS 1.3 setter 修改了 TLS 1.2 名单');
    LApi.SetTls13CipherSuites('');
    LAfter := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LAfter, True) = CIPHER13, 'TLS 1.3 空串改变了名单');

    LApi.SetTls13CipherSuites(CIPHER13 + ':CROSS_SOCKET_UNKNOWN_CIPHER');
    LAfter := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LAfter, True) = CIPHER13, 'TLS 1.3 混合列表处理错误');
    // 第二种顺序：先配 TLS 1.3，再配 TLS 1.2，最终名单相同。
    LApi.SetTls13CipherSuites(CIPHER13 + ':TLS_AES_256_GCM_SHA384');
    // 必须紧跟 setter 检查，读取名单的测试入口也会清理错误队列。
    Check(ERR_get_error() = 0, 'TLS 1.3 成功路径遗留错误');
    LApi.SetTls12CipherSuites(CIPHER12);
    LAfter := CrossOpenSslSelfTest_GetCipherList(LObj);
    Check(CipherText(LAfter, False) = CIPHER12, '反向配置顺序的 TLS 1.2 名单错误');
    Check(CipherText(LAfter, True) = CIPHER13 + ':TLS_AES_256_GCM_SHA384',
      '反向配置顺序的 TLS 1.3 名单错误');
  finally
    LApi := nil;
  end;

  LObj := TTestSslSocket.Create(0, True);
  LApi := LObj;
  try
    LApi.SetTls13CipherSuites(CIPHER13);
    ExpectError(ESslContextInvalid,
      procedure begin LApi.SetTls13CipherSuites('CROSS_SOCKET_UNKNOWN_CIPHER'); end,
      'TLS 1.3 无效名称未报告配置失效');
    Check(ERR_get_error() = 0, 'TLS 1.3 失败路径遗留错误');
    ExpectError(ECrossSocket,
      procedure begin LApi.SetTls13CipherSuites(CIPHER13); end,
      '失效对象仍接受 TLS 1.3 更新');
    ExpectError(ECrossSocket,
      procedure begin LApi.SetTls12CipherSuites(CIPHER12); end,
      'TLS 1.3 失败后仍接受 TLS 1.2 更新');
    ExpectError(ECrossSocket,
      procedure begin LObj.FreezeConfiguration; end,
      'TLS 1.3 配置失败后仍能通过连接门禁');
  finally
    LApi := nil;
  end;
end;

procedure TestSecurityLevel;
var
  LObj: TTestSslSocket;
  LApi: ICrossSslSocket;
begin
  LObj := TTestSslSocket.Create(0, True);
  LApi := LObj;
  try
    // 仅测试全局级别变化，绝不在该实例发起真实网络连接。
    LApi.SetTls12CipherSuites('ECDHE-RSA-AES128-GCM-SHA256:@SECLEVEL=3');
    Check(CrossOpenSslSelfTest_GetSecurityLevel(LObj) = 3,
      'TLS 1.2 规则没有更新安全级别');
    LApi.SetTls13CipherSuites('TLS_AES_256_GCM_SHA384');
    Check(CrossOpenSslSelfTest_GetSecurityLevel(LObj) = 3,
      'TLS 1.3 setter 错误地重置了安全级别');
  finally
    LApi := nil;
  end;
end;
{$ELSE}
procedure TestUnsupportedBackend;
var
  LApi: ICrossSslSocket;
begin
  LApi := TTestSslSocket.Create(0, True);
  try
    LApi.SetTls12CipherSuites('');
    ExpectError(ECrossSocket,
      procedure begin LApi.SetTls12CipherSuites('HIGH'); end,
      'mbedTLS 未明确报告不支持');
    ExpectError(ECrossSocket,
      procedure begin LApi.SetTls13CipherSuites('TLS_AES_128_GCM_SHA256'); end,
      'mbedTLS 未明确拒绝 TLS 1.3 配置');
    LApi.SetTls12CipherSuites('');
    LApi.SetTls13CipherSuites('');
  finally
    LApi := nil;
  end;
end;
{$ENDIF}

begin
  try
    TestDisabled;
    {$IFNDEF __MBED_TLS__}
    TestDefaults;
    TestOpenSsl;
    TestTls13;
    TestSecurityLevel;
    {$ELSE}
    TestUnsupportedBackend;
    {$ENDIF}
    Writeln('TlsCipherSuitesTests: PASS');
  except
    on E: Exception do
    begin
      Writeln('TlsCipherSuitesTests: FAIL: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
```

默认值测试以项目验证的完整算法 OpenSSL 构建为基准，要求实际名单为六项加三项、顺序与常量一致。裁剪算法或专用 provider 环境若缺项，应记录运行库配置和实际缺失，不能声称该完整默认矩阵通过，也不能为了通过测试改用户 OpenSSL/FPC 全局配置。原生 setter 返回 1 不保证九项全部存在，因此必须读取真实名单。

补充测试要求：分别为两个 setter 在同线程预置一个无关 OpenSSL 错误，调用成功后立即检查队列；断言之前不能调用会清理队列的 selftest 入口或其他 setter。连续执行“有效—非法—重建—有效”，确认异常不导致锁泄漏。原有两个 OpenSSL selftest 也应执行回归。上述程序中的 `FreezeConfiguration` 仅验证配置锁和失效门禁，不替代下一节真实连接验证。

## 7. 构建与真实握手验收

### 7.1 测试工程直接绑定项目源文件，禁止改 FPC 配置

此前规划期间已只读确认 lazbuild 4.99 和 FPC 3.3.1 可用；正常 FPC 配置还引用另一份 zLib。按用户最新要求，保留正常配置，不编辑 fpc.cfg、my.cfg、任何 include 配置或全局 Lazarus 环境，也不采用先改后还原的做法。

将第 6 节测试程序保存在 `Net/Tests/FPC/TlsCipherSuitesTests/TlsCipherSuitesTests.lpr`。该程序已经通过 `uses 单元名 in '本仓库相对路径'` 显式绑定 Windows OpenSSL 路径的 24 个项目单元；主程序也用显式相对路径包含本仓库 zLib.inc。RTL、系统及 Lazarus 外部依赖继续使用用户现有安装。

下列为配套 `TlsCipherSuitesTests.lpi` 的完整工程草案。Units 清单便于 IDE 管理，真正的编译绑定以 .lpr 的 uses-in 为准，两份清单必须同步。编译输出只放本测试工程的 bin/lib 子目录，不输出到外部 zLib 或 FPC 安装目录。

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CONFIG>
  <ProjectOptions>
    <Version Value="12"/>
    <PathDelim Value="\"/>
    <General>
      <Title Value="TlsCipherSuitesTests"/>
      <UseAppBundle Value="False"/>
      <SessionStorage Value="InProjectDir"/>
    </General>
    <Units>
      <Unit>
        <Filename Value="TlsCipherSuitesTests.lpr"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\..\DelphiToFPC\DTF.RTL.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\..\DelphiToFPC\DTF.Types.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\..\DelphiToFPC\DTF.Consts.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\..\DelphiToFPC\DTF.Character.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\..\DelphiToFPC\DTF.Diagnostics.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\..\DelphiToFPC\DTF.Generics.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\..\Utils\Utils.StrUtils.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\..\Utils\Utils.SyncObjs.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\..\Utils\Utils.Rtti.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\..\Utils\Utils.DateTime.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\..\Utils\Utils.AnonymousThread.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\..\Utils\Utils.Utils.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\..\Utils\Utils.IOUtils.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\Net.Winsock2.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\Net.Wship6.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\Net.SocketAPI.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\Net.CrossSocket.Base.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\Net.CrossSocket.Iocp.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\Net.CrossSocket.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\Net.CrossSslSocket.Types.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\Net.CrossSslSocket.Base.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\Net.OpenSSL.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\Net.CrossSslSocket.OpenSSL.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="..\..\..\Net.CrossSslSocket.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
    </Units>
  </ProjectOptions>
  <CompilerOptions>
    <Version Value="11"/>
    <PathDelim Value="\"/>
    <Target>
      <Filename Value="bin\$(TargetCPU)-$(TargetOS)-openssl\TlsCipherSuitesTests"/>
    </Target>
    <SearchPaths>
      <IncludeFiles Value="..\..\..\..;..\..\.."/>
      <OtherUnitFiles Value="..\..\..;..\..\..\..\Utils;..\..\..\..\DelphiToFPC;$(LazarusDir)\components\lazutils\lib\$(TargetCPU)-$(TargetOS)"/>
      <UnitOutputDirectory Value="lib\$(TargetCPU)-$(TargetOS)-openssl"/>
    </SearchPaths>
    <CodeGeneration>
      <TargetCPU Value="x86_64"/>
      <TargetOS Value="win64"/>
    </CodeGeneration>
    <Other>
      <CustomOptions Value="-dCROSS_OPENSSL_SELFTEST -vu -vt"/>
    </Other>
  </CompilerOptions>
</CONFIG>
```

第 6 节显式 uses-in 清单以 Windows 为基准；其他平台测试工程应把 IOCP/Winsock 单元换为目标平台的实际依赖并逐项显式引用，不直接把 Windows 清单称为跨平台可运行。

实施时从测试工程目录执行以下命令。保留用户 FPC 正常配置，不使用 -n，也不生成替代的用户配置文件。若缺少外部依赖路径，仅补测试工程自身的 SearchPaths：

```powershell
# 工作目录：实施 worktree 的 Net\Tests\FPC\TlsCipherSuitesTests
New-Item -ItemType Directory -Force -Path 'bin\x86_64-win64-openssl','lib\x86_64-win64-openssl' | Out-Null
& 'D:\Design\FreePascal\lazarus\lazbuild.exe' --build-all TlsCipherSuitesTests.lpi
if ($LASTEXITCODE -ne 0) { throw 'TlsCipherSuitesTests 编译失败' }

# 先按 Net.OpenSSL.pas 的加载约定准备测试运行库，并记录实际版本。
& '.\bin\x86_64-win64-openssl\TlsCipherSuitesTests.exe'
if ($LASTEXITCODE -ne 0) { throw 'TlsCipherSuitesTests 运行失败' }
```

源码来源是验收条件：使用 -vu/-vt 日志核对上述 24 个项目单元、仓库根目录 zLib.inc、Net/Net.Winsock.inc 均来自当前仓库或实施 worktree。不能只看“编译成功”，也不能因为读取了正常 FPC 配置，就把其指向的另一份 zLib 当成本次测试源码。若发现错误来源，修正测试工程 uses-in/IncludeFiles/OtherUnitFiles 后全量重建；不改用户配置。

记录编译器版本、实际命令、运行库版本和单元路径证据；编译诊断及生成文件保留在测试目录，交付时不提交 EXE、PPU、对象文件或临时日志。测试开始/结束可只读比较相关 FPC 配置的哈希，确认未改动。

Delphi 尚需在实施时定位可用工具链。Windows mbedTLS 的现有 `Net.MbedTls.pas` 直接引用 Winapi.Windows/System.Win.Crtl，FPC 该目标存在既有兼容前置阻塞；优先使用 Delphi 验证。它的测试工程将 Net.MbedTls、Net.MbedBIO 与 Net.CrossSslSocket.MbedTls 显式加入，使用独立输出目录，不修第三方源码，不为绕过链接问题改变用户 FPC 配置。未取得编译/运行证据时明确标为阻塞。

### 7.2 真实握手矩阵（验收前必须有证据）

使用仅绑定 `127.0.0.1` 的隔离测试服务和临时测试证书。端口选空闲端口；下例 18443 仅为测试配置示例。测试证书、私钥、日志不提交仓库。

```powershell
openssl req -x509 -newkey rsa:2048 -nodes -days 1 `
  -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' `
  -keyout test-key.pem -out test-cert.pem

# 每次只启动一个测试服务，上一服务退出后再运行下一个。
openssl s_server -accept 127.0.0.1:18443 -cert test-cert.pem `
  -key test-key.pem -tls1_2 -cipher ECDHE-RSA-AES128-GCM-SHA256 -www

openssl s_server -accept 127.0.0.1:18443 -cert test-cert.pem `
  -key test-key.pem -tls1_2 -cipher ECDHE-RSA-AES256-GCM-SHA384 -www

openssl s_server -accept 127.0.0.1:18443 -cert test-cert.pem `
  -key test-key.pem -tls1_3 -ciphersuites TLS_AES_128_GCM_SHA256 -www

openssl s_server -accept 127.0.0.1:18443 -cert test-cert.pem `
  -key test-key.pem -tls1_3 -ciphersuites TLS_AES_256_GCM_SHA384 -www
```

必须由编译后的 Cross-Socket 客户端/服务端调用新 setter 参与握手，不能只用 openssl 对 openssl 握手来冒充库测试。测试 fixture 应在实施时写入专用测试目录，其观测代码按实际类型编写如下；`OnConnected` 是 `of object` 事件，不能直接赋匿名过程。

```pascal
type
  TCipherHandshakeObserver = class
  public
    SslInfo: TSslInfo;
    ErrorText: string;
    Done: TEvent;
    procedure Connected(const Sender: TObject;
      const AConnection: ICrossConnection);
  end;

procedure TCipherHandshakeObserver.Connected(const Sender: TObject;
  const AConnection: ICrossConnection);
var
  LSslConnection: ICrossSslConnection;
begin
  try
    if not Supports(AConnection, ICrossSslConnection, LSslConnection) then
      ErrorText := 'Connection does not expose SSL information.'
    else if not LSslConnection.GetSslInfo(SslInfo) then
      ErrorText := 'Failed to read negotiated SSL information.';
  except
    on E: Exception do ErrorText := E.Message;
  end;
  Done.SetEvent;
end;
```

fixture 使用 `SyncObjs.TEvent`；创建 observer 和事件后才启动连接，主线程 `WaitFor(10000)` 后读取结果，停止并等待 socket IO 循环后再释放 observer/事件。断开路径也通知结束；双版本不匹配的负向用例要求明确握手失败，不能把无差别超时或服务未启动当作通过。TLS 1.2 用例强制 TLS 1.2，TLS 1.3 用例强制 TLS 1.3，防止另一版本回退造成假阳性。使用测试证书作为信任锚并启用 `VerifyPeer`，避免放宽生产默认策略。

服务端对称验证如果同样启用 `VerifyPeer`，会要求客户端提供证书。因此 Cross-Socket 服务端同时加载上述测试证书/私钥和测试 CA，openssl 客户端必须携带测试证书，避免把缺少客户端证书误判为套件限制成功。正、负向仅改变 `-cipher`：

```powershell
openssl s_client -connect 127.0.0.1:18443 -servername localhost `
  -tls1_2 -cipher ECDHE-RSA-AES128-GCM-SHA256 `
  -cert test-cert.pem -key test-key.pem -CAfile test-cert.pem `
  -verify_return_error -verify_hostname localhost

openssl s_client -connect 127.0.0.1:18443 -servername localhost `
  -tls1_2 -cipher ECDHE-RSA-AES256-GCM-SHA384 `
  -cert test-cert.pem -key test-key.pem -CAfile test-cert.pem `
  -verify_return_error -verify_hostname localhost

# TLS 1.3 对称验收：版本固定为 1.3，正负向仅改变套件名称。
openssl s_client -connect 127.0.0.1:18443 -servername localhost `
  -tls1_3 -ciphersuites TLS_AES_128_GCM_SHA256 `
  -cert test-cert.pem -key test-key.pem -CAfile test-cert.pem `
  -verify_return_error -verify_hostname localhost

openssl s_client -connect 127.0.0.1:18443 -servername localhost `
  -tls1_3 -ciphersuites TLS_AES_256_GCM_SHA384 `
  -cert test-cert.pem -key test-key.pem -CAfile test-cert.pem `
  -verify_return_error -verify_hostname localhost
```

| 场景 | 配置与预期 |
| --- | --- |
| 默认构造 | 不调用 setter，验证实际名单恰为默认常量；服务端/客户端都实际采用新默认。 |
| 默认套件覆盖 | TLS 1.2 六项逐项用匹配的 RSA/ECDSA 证书固定握手；TLS 1.3 三项逐项固定握手，记录协议和 CurrentCipher。 |
| 默认排除策略 | 确认仅提供旧 TLS 1.2 CBC 或 TLS 1.3 CCM/CCM_8 的受控端点无法与默认配置握手；先确认测试端点确实支持所设置套件，避免把服务端配置失败当成客户端拒绝证据。 |
| 初始化错误 | 受控原生设置失败时构造失败，资源被清理，不返回一半配置成功的 socket。 |
| 客户端 TLS 1.2 正向 | 客户端 setter 设 AES128，服务端只提供 AES128；`SslInfo.SslVersion` 为 TLSv1.2，`CurrentCipher` 精确匹配。 |
| 客户端 TLS 1.2 负向 | 客户端只允许 AES128，服务端只提供 AES256；明确握手失败，业务数据不发送。 |
| 客户端 TLS 1.3 正向 | 调用 `SetTls13CipherSuites('TLS_AES_128_GCM_SHA256')`，对端仅提供该套件；成功协商 TLSv1.3，CurrentCipher 精确匹配。 |
| 客户端 TLS 1.3 负向 | 客户端 TLS 1.3 仅允许 AES128，对端固定 TLS 1.3 且仅提供 AES256；明确握手失败。 |
| 服务端双版本验证 | Cross-Socket 服务端分别配置两个 setter，openssl s_client 做 TLS 1.2 和 TLS 1.3 各自匹配/不匹配用例，验证不是仅客户端生效。 |
| 双版本同时配置 | 同一个 socket 创建连接前配置两个版本，分别连接只支持 TLS 1.2/只支持 TLS 1.3 的服务端，各自严格使用配置名单。 |
| 安全级别边界 | 在受控 fixture 中验证 `@SECLEVEL` 的上下文级影响；不能仅凭 TLS 1.3 名单未变断言 TLS 1.3 握手策略完全未变。 |
| 真实首次连接锁 | 在第一条 SSL 连接创建后分别调用两个 setter 的非空配置，均必须拒绝；已有连接维持原协商结果。 |
| 失败后阻止连接 | 分别构造 TLS 1.2/TLS 1.3 原生 setter 失败，再尝试 Connect/接受连接，确认配置门禁阻止 SSL 建立。 |

编译/运行至少覆盖 FPC 3.3.1 Windows x64 OpenSSL 后端、Delphi 可用目标以及 mbedTLS 接口行为；OpenSSL 1.1.1 和当前支持的 3.x 分别记录结果。需要发布其他平台时，在对应平台补运行证据。无工具链或运行库的项保持“未验证/阻塞”，不以静态检查替代运行结果。

## 8. 文档修改内容

更新 `README.md` 与 `README.en.md` 的 TLS 配置段落，给出两个接口的示例。示例在 socket 层使用，不写成不存在的 `ICrossHttpClient` 配置转发方法：

文档同时公开 DEFAULT_TLS12_CIPHER_SUITES / DEFAULT_TLS13_CIPHER_SUITES 的值及默认收紧带来的兼容性变化。OpenSSL socket 构造时已使用这两个常量；调用方无需重复设置，只有自定义后想恢复名单时才显式传入常量。

```pascal
var
  LSocket: ICrossSslSocket;
begin
  LSocket := TCrossSslSocket.Create(1, True);
  // 在 Connect/首个 SSL 连接创建之前配置两种版本。
  LSocket.SetTls12CipherSuites('ECDHE-RSA-AES128-GCM-SHA256');
  LSocket.SetTls13CipherSuites(
    'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384');
  // 按业务继续配置 CA、VerifyPeer，以及需要的证书和私钥。
end;
```

中文拟加入的正文：

> OpenSSL 1.1.1+ 后端通过 ICrossSslSocket.SetTls12CipherSuites 和 SetTls13CipherSuites 分别配置 TLS 1.2 规则与 TLS 1.3 套件名称列表。两份名单独立配置；TLS 1.2 规则中的 @SECLEVEL 可以改变全局安全级别，间接影响 TLS 1.3 握手，TLS 1.3 setter 不重置该级别。空字符串保留当前配置，不恢复默认值、不禁用协议。未知规则或名称可能被原生 API 忽略。首次 SSL 连接创建后不能修改。任一个原生更新失败都会使整个 socket 的 TLS 配置失效，必须重建对象；mbedTLS 对两个方法的非空输入均明确报告不支持。本次接口升级要求所有使用者和派生接口从同一版本源码全量重编译，不支持混用旧、新 BPL/DLL。

英文拟加入的正文：

> The OpenSSL 1.1.1+ backend exposes ICrossSslSocket.SetTls12CipherSuites for TLS 1.2 cipher rules and SetTls13CipherSuites for an ordered, colon-separated list of TLS 1.3 cipher-suite names. The two lists are configured independently. However, @SECLEVEL in TLS 1.2 rules changes the context-wide security level and can also affect TLS 1.3 handshakes; the TLS 1.3 setter does not reset that level. An empty string preserves the current configuration, without restoring defaults or disabling a protocol. Unknown items may be ignored by OpenSSL. Complete configuration before creating the first SSL connection. Either native setter failing invalidates the socket's entire TLS configuration and requires recreating the socket. The mbedTLS backend explicitly rejects non-empty configuration for both methods. Rebuild all consumers and derived interfaces from the same source version; mixing old and new BPL/DLL binaries is unsupported.

不将某一套件示例标为所有业务通用推荐策略，不声称两个 setter 单独实现 FIPS/PCI 合规；TLS 协议启停与套件名单配置分开说明。

## 9. 分步实施

以下操作供后续实施阶段使用，本轮不执行。以当前项目源码为基线，先核对本计划与实际代码，任何范围变化先更新计划。

1. 检查 `git status` 和当前提交，保护已有改动。若需要隔离实施，创建项目自己的 `codex/tls-cipher-suites` 分支及 worktree，复制本计划到其 `docs/plans/` 后重新读取；文件存在时先核对，不覆盖。
2. 按第 5 节在 Types 增加两组公开默认常量，在 Base/OpenSSL 增加两个明确方法，并替换 OpenSSL 初始化中的旧硬编码名单。mbedTLS 继承默认明确拒绝实现，不添加多余 override，不改第三方后端源码。
3. 增加第 6 节 `TlsCipherSuitesTests.lpr` 与第 7 节配套 `.lpi`，显式加入待测源文件及本仓库依赖；增加默认值、初始化错误和握手测试，更新中英文 README。
4. 保留用户正常 FPC 配置，通过工程内 uses-in 和本地路径全量编译，核实单元来源，运行默认常量、两个 API 及双版本握手测试。记录编译器、OpenSSL 版本、命令与结果；已有 mbedTLS/FPC 限制单独记录。
5. 检查配置失败后的有效性门禁、接口 ABI 说明、@SECLEVEL 的全局影响，以及两次配置之间的调用顺序约束。
6. 执行 `git diff --check`，检查 diff、编码/换行和文件清单，确保无测试私钥、证书、EXE、DLL、DCU、PPU、其他用户改动或无关格式化。
7. 报告实现、验证结果和未验证项。用户要求提交时使用中文提交消息，例如 `增加 TLS 1.2 和 TLS 1.3 套件配置接口`；只暂存审查过的文件。
8. 推送或提交新的功能 PR 按用户后续发布要求执行；本计划不修改任何既有 PR、不向外部作者分支推送，也不含自动合并命令。

独立工作区准备示例（仅在选用 worktree 时执行；分支和目录都须不存在）：

```powershell
git status --short
git rev-parse HEAD
git worktree add -b codex/tls-cipher-suites ..\Delphi-Cross-Socket-tls-cipher-suites HEAD
# 将本计划复制到新 worktree 的 docs/plans/，重新读取后再开始实现。
```

计划文档默认不提交，本轮“修改计划”不意味着开始源码实现、提交或发布。

## 10. 验收清单与风险控制

- [x] 两组默认常量公开定义在 Types 单元，初始化实际使用它们，修改默认值只需改一处。
- [x] 完整算法构建下原生名单为 TLS 1.2 六项、TLS 1.3 三项，无 HIGH 扩张或旧 CBC/CCM 意外保留。
- [x] 默认收紧的兼容性变化已说明，能在首个连接前通过两个 setter 自定义或显式恢复默认名单。
- [x] 未修改任何 FPC 配置及其 include 或全局 Lazarus 配置，没有“临时改完再还原”。
- [x] 测试工程 uses-in 与 .lpi 清单同步，日志证明项目单元和 include 全部来自本仓库/实施 worktree。
- [x] 公共方法仅采用 SetTls12CipherSuites / SetTls13CipherSuites 两个明确名称，无含糊别名。
- [x] TLS 1.2 参数说明为规则表达式，TLS 1.3 参数说明为套件名称列表。
- [x] 公共接口可直接调用；mbedTLS 和第三方派生对象无新增抽象方法。
- [x] 两个 API 都覆盖 SSL 关闭、空串、有效、无效、混合、配置冻结和错误队列行为，不另行逐字符校验。
- [x] TLS 1.3 多项列表顺序正确，两个版本交叉配置的名单互不覆盖。
- [x] 不含 @SECLEVEL 的双 setter 调用顺序得到相同最终名单；文档不承诺双调用事务性。
- [x] @SECLEVEL 影响上下文安全级别，TLS 1.3 setter 不重置它；没有“完全不影响 TLS 1.3”的错误承诺。
- [x] 任一原生 setter 失败，两个 setter 的后续非空调用和真实 SSL 连接都被门禁阻止。
- [x] Cross-Socket 客户端和服务端的 TLS 1.2、TLS 1.3 正负向握手分别有证据，负向不会回退其他协议。
- [x] 首次 SSL 连接后两个 setter 均被锁定，异常路径不泄漏锁。
- [ ] 已完成目标工具链/后端全量重编译，派生接口也使用同一版本。
- [x] 文档与最终实现一致，无错误的协议启停、合规、ABI 或回滚承诺。
- [x] 交付代码与实际测试提交一致，工作区中无无关变更。

若失败后必须重建对象的契约不被接受，先调整本计划再实施；不直接删除失效标记而宣称原上下文未变化。已发布变更需要撤销时，通过新的 revert 提交回退该功能并重建使用者；不使用 reset/强推改写共享历史，不覆盖用户未提交工作。

## 11. 变更记录

- 2026-09-06：用户要求把功能改为独立的 TLS 1.2/1.3 套件完整配置，撤销旧计划针对 PR #200 的实施和采纳路线。计划文件重命名为 `2026-09-06-tls-cipher-suites-configuration.md`。
- 2026-09-06：采用 SetTls12CipherSuites / SetTls13CipherSuites 对称命名，新增 TLS 1.3 完整实现、双向名单和双版本握手测试；补充 @SECLEVEL、空字符串和双调用非事务性边界。
- 2026-09-06：按用户要求增加两组现代通用默认常量并用于 OpenSSL 初始化；加入默认名单/握手/初始化失败验证。明确禁止修改 FPC 配置，默认测试方案改为正常配置加工程 uses-in 显式引用本仓库源码，补充完整 Lazarus 工程文件草案。

## 12. 规划阶段交付记录（实施前）

最新修订（2026-09-06）：按用户意见删除两个 setter 的逐字符检查及相应的拒绝测试，同步更新输入契约；保留 OpenSSL 原生校验与失败处理。

已完成：修订计划，增加默认套件常量、初始化代码、默认行为测试和完整测试工程草案；明确用户 FPC 配置保护与项目源码来源验证。

未执行：生产源码修改、测试源码创建、编译或运行验证、Git 提交、远端 PR 操作、推送或合并。上述代码仍为规划草案。

## 13. 实施记录

- 2026-09-06：开始在当前干净源码基线上实施；保留现有未提交计划，禁止修改 FPC 配置。先建立显式源码引用的测试工程，再实现生产代码与真实握手验证。

- 2026-09-06：实际编译发现日志分支还依赖 Utils.Logger；测试工程显式清单补齐该本仓库单元。已定位 Delphi 13.1 编译器，可增加 Delphi 构建验证。握手 fixture 使用同一测试程序的命令行模式，并记录 TCP 建连/收到握手数据以避免把超时当作负向成功。
- 2026-09-06 实施调整：最低版本验证在原有 Net.OpenSSL.LoadSslLibs 中失败，原因是强制加载 EVP_PKEY_CTX_set_rsa_keygen_bits，而 OpenSSL 1.1.1 官方将它定义为调用 RSA_pkey_ctx_ctrl 的宏。为满足已确定的 OpenSSL 1.1.1+ 目标，增加仅在缺少直接导出时使用的官方宏等价封装，保留 3.x 直接导出；增加真正的 RSA 密钥生成测试验证封装，不修改第三方库。此项替代旧计划“完全不增加绑定”的限制。
- 2026-09-06 测试调整：服务端原有 GetSslInfo 对未取得的临时对端密钥继续解引用，导致测试观测 Access violation；不扩大范围修改证书信息解析。新增只在 CROSS_OPENSSL_SELFTEST 下编译的真实连接协议/套件读取入口，直接读取 SSL_get_version/SSL_get_current_cipher，用于当前套件功能的握手验收。

- 2026-09-06 运行验证修订：OpenSSL 1.1.1v 的 TLS 1.3 setter 对有效名称混合未知名称返回失败，而 3.1.2 忽略未知名称。包装层继续严格转发原生结果，不强行统一语法；测试改为独立实例验证各版本实际契约，文档不承诺混合列表一定成功。

### 实施结果

- 已实现两个公开套件接口、两组默认常量、构造默认策略、配置锁/原生错误/配置失效处理；未加入逐字符检查。
- 实际生产修改：Net.CrossSslSocket.Types.pas、Net.CrossSslSocket.Base.pas、Net.CrossSslSocket.OpenSSL.pas；另因最低版本验证需要，对 Net.OpenSSL.pas 的一个密钥生成宏增加官方等价的动态加载兼容封装。
- 新增共享 FPC/Delphi 测试程序、显式源码引用的 Lazarus 工程、只读握手观测入口和可复现 PowerShell 握手驱动；说明见 Net/Tests/FPC/TlsCipherSuitesTests/README.md。
- FPC 3.3.1 + OpenSSL 3.1.2：配置测试 PASS，真实握手 32/32。
- FPC 3.3.1 + OpenSSL 1.1.1v：配置测试 PASS，真实握手 32/32。
- Delphi 13.1 / dcc64 37.0 + OpenSSL 3.1.2：配置测试 PASS，真实握手 32/32。
- Delphi 13.1 / dcc64 37.0 + OpenSSL 1.1.1v：配置测试 PASS，真实握手 32/32。
- 真实握手总计 128/128，含客户端和服务端、RSA/ECDSA、两个协议逐项默认套件、自定义正负向以及默认排除 CBC/CCM/CCM_8。
- 既有 HttpClient 示例使用官方 Lazarus 工程，以 --build-all --skip-dependencies --build-mode=Windows-X64 全量编译通过；跳过重建已安装包以避免写全局 Lazarus 包缓存。
- 已核实 FPC 逐单元编译日志来自本仓库；fpc.cfg、my.cfg、fp.cfg 的 SHA-256 与实施前一致。
- mbedTLS Delphi 构建尝试受 aesni.o 等已有静态对象缺失阻塞；未修改第三方源码和对象，未声称 mbedTLS 运行通过。公共基类的明确拒绝行为已通过独立派生类测试。
- 其他平台、静态 OpenSSL 链接和更高 OpenSSL 3.x 未在本轮运行。完整 GetSslInfo 的原有服务端问题未扩大修复范围。
- 代码与文档未提交、未推送，未执行远端 PR 操作。
- 2026-09-06：按用户 diff 意见，默认套件初始化改为调用 SetTls13CipherSuites/SetTls12CipherSuites，复用配置锁与错误处理，删除重复原生初始化分支；补跑默认初始化、失败清理及握手回归。
- 2026-09-06 默认初始化复用接口回归：FPC/Delphi 两种编译器分别搭配 OpenSSL 1.1.1v/3.1.2 的配置测试全部通过（含初始化失败上下文释放）；FPC + OpenSSL 3.1.2 的客户端/服务端握手 32/32 通过；FPC 三份配置哈希保持不变。

- 2026-09-06：用户采纳协议版本建议，移除固定 TLS 1.3 上限，仅设置 TLS 1.2 最低版本并检查返回值；添加原生协议范围检查、最低版本设置失败测试和握手回归。未来协议版本仍需独立适配验证，不因取消上限而宣称已支持。
- 2026-09-06 协议范围修订验收：FPC/Delphi × OpenSSL 1.1.1v/3.1.2 四组配置测试通过，含默认上限继承和最低版本设置失败释放；FPC + OpenSSL 3.1.2 真实握手 32/32 通过。FPC 三份配置哈希未变化，未提交或推送。
