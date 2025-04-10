unit Net.CrossSslSocket.Types;

interface

{$I zLib.inc}

uses
  SysUtils;

type
  // 名称-数据结构体
  TEntryData = record
    Name, Value: string;
  end;

  // 主题备用名称数据
  TGeneralName = record
    TypeID: Integer;
    TypeName: string;
    Value: string;
  end;

  // 策略限定符
  TQualifier = record
    QID: Integer;
    Value: string;
  end;

  // 证书策略数据
  TPolicie = record
    OID: string;
    Qualifiers: TArray<TQualifier>;
  end;

  // CRL分发点
  TCrlDistPoint = record
    // 该分发点覆盖的证书吊销原因
    // 每位代表一种原因
    //  CRL_REASON_UNSPECIFIED            = 0;
    //  CRL_REASON_KEY_COMPROMISE	        = 1;
    //  CRL_REASON_CA_COMPROMISE          = 2;
    //  CRL_REASON_AFFILIATION_CHANGED    = 3;
    //  CRL_REASON_SUPERSEDED             = 4;
    //  CRL_REASON_CESSATION_OF_OPERATION = 5;
    //  CRL_REASON_CERTIFICATE_HOLD	      = 6;
    //  CRL_REASON_REMOVE_FROM_CRL        = 8;
    //  CRL_REASON_PRIVILEGE_WITHDRAWN    = 9;
    //  CRL_REASON_AA_COMPROMISE          = 10;
    Reasons: Cardinal;

    // 对吊销原因的补充说明
    DpReasons: Cardinal;

    // CRL的实际分发地址
    // 通常为URI(如http://example.com/crl.crl)
    DistPoint: TArray<TGeneralName>;

    // 颁发该CRL的证书颁发机构(CA)
    CRLissuer: TArray<TGeneralName>;
  end;

  // 扩展密钥用法条目
  TExtKeyUsageItem = record
    NID: Integer;
    OID: string;
    Value: string;
  end;

  // 扩展密钥用法
  TExtKeyUsage = record
    // 标志位
    //  XKU_SSL_SERVER          = $1;
    //  XKU_SSL_CLIENT          = $2;
    //  XKU_SMIME               = $4;
    //  XKU_CODE_SIGN           = $8;
    //  XKU_SGC                 = $10; // Netscape or MS Server-Gated Crypto
    //  XKU_OCSP_SIGN           = $20;
    //  XKU_TIMESTAMP           = $40;
    //  XKU_DVCS                = $80;
    //  XKU_ANYEKU              = $100;
    Flags: Cardinal;

    // 详细条目
    List: TArray<TExtKeyUsageItem>;
  end;

  // 授权信息访问
  TAuthorityInfoAccess = record
    Method: string;
    MethodDesc: string;
    Location: TGeneralName;
  end;

  // 证书基本约束
  TBasicConstraints = record
    CA: Integer;
    PathLen: LongInt;
  end;

  // 签名证书时间戳
  TSct = record
    // 版本号
    Version: Integer;

    // 原始数据
    Sct: TBytes;

    // 日志ID(32字节)
    LogID: TBytes;

    // 时间戳
    Timestamp: UInt64;

    // 扩展数据(RFC 6962定义的CT扩展)
    Ext: TBytes;

    // 哈希算法
    // TLSEXT_hash_sha256
    HashAlg: Byte;

    // 签名算法
    // TLSEXT_signature_ecdsa
    // TLSEXT_signature_rsa
    SigAlg: Byte;

    // 签名数据
    Sig: TBytes;

    // 日志条目类型(X.509证书或预证书)
    EntryType: Integer;

    // 来源
    Source: Integer;

    // 验证状态
    ValidationStatus: Integer;
  end;

  // 扩展原始数据
  TExtensionRawData = record
    // 扩展ID
    NID: Integer;

    // OID
    OID: string;

    // 是否关键数据
    Critical: Boolean;

    // 扩展名称
    Name: string;

    // 扩展原始数据
    // 还可以根据NID类型进行进一步解析, 比如
    //   NID_subject_alt_name(备用域名)
    //   NID_key_usage(密钥用法)
    //   NID_ext_key_usage(扩展密钥用法)
    //   NID_basic_constraints(基本约束)
    Value: TBytes;
  end;

  // 扩展信息
  TExtensionInfo = record
    // 原始数据
    RawData: TArray<TExtensionRawData>;

    // 证书颁发机构密钥ID
    AuthorityKeyID: TBytes;

    // 证书使用者密钥ID
    SubjectKeyID: TBytes;

    // 证书使用者可选名称
    AltNames: TArray<TGeneralName>;

    // 证书策略
    Policies: TArray<TPolicie>;

    // 证书密钥用法
    //  X509v3_KU_DIGITAL_SIGNATURE = $0080;
    //  X509v3_KU_NON_REPUDIATION   = $0040;
    //  X509v3_KU_KEY_ENCIPHERMENT  = $0020;
    //  X509v3_KU_DATA_ENCIPHERMENT = $0010;
    //  X509v3_KU_KEY_AGREEMENT     = $0008;
    //  X509v3_KU_KEY_CERT_SIGN     = $0004;
    //  X509v3_KU_CRL_SIGN          = $0002;
    //  X509v3_KU_ENCIPHER_ONLY     = $0001;
    //  X509v3_KU_DECIPHER_ONLY     = $8000;
    KeyUsage: Cardinal;

    // 扩展密钥用法
    ExtKeyUsage: TExtKeyUsage;

    // CRL分发点
    CrlDistPoints: TArray<TCrlDistPoint>;

    // 授权信息访问
    AuthorityInfoAccesses: TArray<TAuthorityInfoAccess>;

    // 证书基本约束
    BasicConstraints: TBasicConstraints;

    // 签名证书时间戳列表
    SctList: TArray<TSct>;
  end;

  // 证书信息
  TCertInfo = record
    // 证书版本号
    Version: LongInt;

    // 证书内容(二进制DER格式)
    DER: TBytes;

    // 证书内容(文本PEM格式)
    PEM: string;

    // 证书主题信息
    Subject: TArray<TEntryData>;

    // 证书颁发者信息
    Issuer: TArray<TEntryData>;

    // 扩展信息
    Extension: TExtensionInfo;

    // 颁发时间
    NotBefore: TDateTime;

    // 截止时间
    NotAfter: TDateTime;

    // 证书序列号
    SerialNumber: TBytes;

    // 签名算法ID(668=NID_sha256WithRSAEncryption)
    SigAlgID: Integer;

    // 签名算法(RSA-SHA256)
    SigAlg: string;

    // 证书签名
    Signature: TBytes;

    // SHA256指纹
    SHA256Digest: TBytes;

    // 公钥SHA256指纹
    PubKeySHA256Digest: TBytes;

    // 公钥ID(6=NID_rsaEncryption)
    PubKeyID: Integer;

    // 公钥类型(X25519)
    PubKeyType: string;

    // 公钥密码位数(253)
    PubKeyBits: Integer;

    // 公钥安全位数(128)
    PubKeySecurityBits: Integer;

    // 公钥输出缓冲区字节数(256)
    PubKeyOutSize: Integer;

    // 公钥模数(256字节)
    PubKeyModulus: TBytes;

    // 公钥公开指数(3字节)
    PubKeyExponent: TBytes;
  end;

  // SSL信息
  TSslInfo = record
    // SSL版本
    SslVersion: string;

    // 服务端名称
    HostName: string;

    // 加密套件列表
    CipherList: TArray<string>;

    // 当前加密算法(TLS_AES_128_GCM_SHA256)
    CurrentCipher: string;

    // 当前加密位数(128)
    CurrentCipherBits: Integer;

    // 临时密钥ID(1034=NID_X25519)
    TmpKeyID: Integer;

    // 临时密钥类型(X25519)
    TmpKeyType: string;

    // 临时密钥密码位数(253)
    TmpKeyBits: Integer;

    // 临时密钥安全位数(128)
    TmpKeySecurityBits: Integer;

    // 临时密钥输出缓冲区字节数(32)
    TmpKeyOutSize: Integer;

    // 证书信息
    CertInfo: TCertInfo;
  end;

implementation

end.
