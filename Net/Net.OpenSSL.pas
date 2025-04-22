{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.OpenSSL;

{$I zLib.inc}

{
  本单元支持 openssl 1.1 及以上版本

  OpenSSL 下载:
  https://wiki.openssl.org/index.php/Binaries
  https://indy.fulgan.com/SSL/
  https://github.com/leenjewel/openssl_for_ios_and_android

  OpenSSL iOS静态库下载:
  https://indy.fulgan.com/SSL/OpenSSLStaticLibs.7z

  LibreSSL 下载:
  http://ftp.openbsd.org/pub/OpenBSD/LibreSSL/

  Linux下需要安装libssl开发包
  sudo apt-get install libssl-dev

  补充说明:
    由于不同的操作系统所带的 openssl 运行库版本并不相同,
    所以本单元提供了几个变量用于自定义运行库的路径及名称
    在首次加载 openssl 库之前指定即可

    // 手动指定 ssl 库路径
    TSSLTools.LibPath: string;

    // 手动指定 libssl 库名称
    TSSLTools.LibSSL: string;

    // 手动指定 libcrypto 库名称
    TSSLTools.LibCRYPTO: string;
}

// iOS真机必须用openssl的静态库(未验证)
{$IF defined(IOS) or defined(ANDROID)}
  {$DEFINE __SSL_STATIC__}
{$ENDIF}

{.$DEFINE __SSL_STATIC__}
{$IFDEF __SSL_STATIC__}
  {$DEFINE __SSL3__}

  {$IFDEF FPC}
    {$LINKLIB libssl.a}
    {$LINKLIB libcrypto.a}
  {$ELSE}
    {$IFDEF POSIX}
      {$DEFINE __STATIC_WITH_EXTERNAL__}
    {$ELSE}
      // {$L xxx.o}
    {$ENDIF}
  {$ENDIF}
{$ENDIF}

// 让枚举类型占用4个字节
{$Z4}

interface

uses
  {$IFDEF MSWINDOWS}
  Windows,
  {$ENDIF}

  {$IFDEF POSIX}
  {$IFDEF DELPHI}
  Posix.Base,
  Posix.Pthread,
  {$ELSE}
  baseunix,
  unix,
  {$ENDIF DELPHI}
  {$ENDIF POSIX}

  SysUtils,
  DateUtils,
  Math,
  Utils.DateTime,
  Utils.IOUtils,

  Net.CrossSslSocket.Types;

const
  LIBSSL_NAME =
    {$IFDEF __STATIC_WITH_EXTERNAL__}
    'libssl.a'
    {$ELSE}
    ''
    {$ENDIF}
    ;

  LIBCRYPTO_NAME =
    {$IFDEF __STATIC_WITH_EXTERNAL__}
    'libcrypto.a'
    {$ELSE}
    ''
    {$ENDIF}
    ;

  SSL_ERROR_NONE                              = 0;
  SSL_ERROR_SSL                               = 1;
  SSL_ERROR_WANT_READ                         = 2;
  SSL_ERROR_WANT_WRITE                        = 3;
  SSL_ERROR_WANT_X509_LOOKUP                  = 4;
  SSL_ERROR_SYSCALL                           = 5;
  SSL_ERROR_ZERO_RETURN                       = 6;
  SSL_ERROR_WANT_CONNECT                      = 7;
  SSL_ERROR_WANT_ACCEPT                       = 8;

  SSL_ST_CONNECT                              = $1000;
  SSL_ST_ACCEPT                               = $2000;
  SSL_ST_MASK                                 = $0FFF;
  SSL_ST_INIT                                 = (SSL_ST_CONNECT or SSL_ST_ACCEPT);

  BIO_CTRL_EOF     = 2;
  BIO_CTRL_INFO		 = 3;
  BIO_CTRL_PENDING = 10;
  BIO_C_GET_BUF_MEM_PTR = 115;

  SSL_VERIFY_NONE                             = 0;
  SSL_VERIFY_PEER                             = 1;
  SSL_VERIFY_FAIL_IF_NO_PEER_CERT             = 2;
  SSL_VERIFY_CLIENT_ONCE                      = 4;

  SSL_CTRL_NEED_TMP_RSA                       = 1;
  SSL_CTRL_SET_TMP_RSA                        = 2;
  SSL_CTRL_SET_TMP_DH                         = 3;
  SSL_CTRL_SET_TMP_ECDH                       = 4;
  SSL_CTRL_SET_TMP_RSA_CB                     = 5;
  SSL_CTRL_SET_TMP_DH_CB                      = 6;
  SSL_CTRL_SET_TMP_ECDH_CB                    = 7;
  SSL_CTRL_GET_SESSION_REUSED                 = 8;
  SSL_CTRL_GET_CLIENT_CERT_REQUEST            = 9;
  SSL_CTRL_GET_NUM_RENEGOTIATIONS             = 10;
  SSL_CTRL_CLEAR_NUM_RENEGOTIATIONS           = 11;
  SSL_CTRL_GET_TOTAL_RENEGOTIATIONS           = 12;
  SSL_CTRL_GET_FLAGS                          = 13;
  SSL_CTRL_EXTRA_CHAIN_CERT                   = 14;
  SSL_CTRL_SET_MSG_CALLBACK                   = 15;
  SSL_CTRL_SET_MSG_CALLBACK_ARG               = 16;
  SSL_CTRL_SET_MTU                            = 17;

  SSL_CTRL_SESS_NUMBER                        = 20;
  SSL_CTRL_SESS_CONNECT                       = 21;
  SSL_CTRL_SESS_CONNECT_GOOD                  = 22;
  SSL_CTRL_SESS_CONNECT_RENEGOTIATE           = 23;
  SSL_CTRL_SESS_ACCEPT                        = 24;
  SSL_CTRL_SESS_ACCEPT_GOOD                   = 25;
  SSL_CTRL_SESS_ACCEPT_RENEGOTIATE            = 26;
  SSL_CTRL_SESS_HIT                           = 27;
  SSL_CTRL_SESS_CB_HIT                        = 28;
  SSL_CTRL_SESS_MISSES                        = 29;
  SSL_CTRL_SESS_TIMEOUTS                      = 30;
  SSL_CTRL_SESS_CACHE_FULL                    = 31;
  SSL_CTRL_OPTIONS                            = 32;
  SSL_CTRL_MODE                               = 33;
  SSL_CTRL_GET_READ_AHEAD                     = 40;
  SSL_CTRL_SET_READ_AHEAD                     = 41;
  SSL_CTRL_SET_SESS_CACHE_SIZE                = 42;
  SSL_CTRL_GET_SESS_CACHE_SIZE                = 43;
  SSL_CTRL_SET_SESS_CACHE_MODE                = 44;
  SSL_CTRL_GET_SESS_CACHE_MODE                = 45;
  SSL_CTRL_GET_MAX_CERT_LIST                  = 50;
  SSL_CTRL_SET_MAX_CERT_LIST                  = 51;
  SSL_CTRL_SET_MAX_SEND_FRAGMENT              = 52;
  SSL_CTRL_SET_TLSEXT_SERVERNAME_CB           = 53;
  SSL_CTRL_SET_TLSEXT_SERVERNAME_ARG          = 54;
  SSL_CTRL_SET_TLSEXT_HOSTNAME                = 55;
  SSL_CTRL_SET_TLSEXT_DEBUG_CB                = 56;
  SSL_CTRL_SET_TLSEXT_DEBUG_ARG               = 57;
  SSL_CTRL_GET_TLSEXT_TICKET_KEYS             = 58;
  SSL_CTRL_SET_TLSEXT_TICKET_KEYS             = 59;
  SSL_CTRL_SET_TLSEXT_OPAQUE_PRF_INPUT        = 60;
  SSL_CTRL_SET_TLSEXT_OPAQUE_PRF_INPUT_CB     = 61;
  SSL_CTRL_SET_TLSEXT_OPAQUE_PRF_INPUT_CB_ARG = 62;
  SSL_CTRL_SET_TLSEXT_STATUS_REQ_CB           = 63;
  SSL_CTRL_SET_TLSEXT_STATUS_REQ_CB_ARG       = 64;
  SSL_CTRL_SET_TLSEXT_STATUS_REQ_TYPE         = 65;
  SSL_CTRL_GET_TLSEXT_STATUS_REQ_EXTS         = 66;
  SSL_CTRL_SET_TLSEXT_STATUS_REQ_EXTS         = 67;
  SSL_CTRL_GET_TLSEXT_STATUS_REQ_IDS          = 68;
  SSL_CTRL_SET_TLSEXT_STATUS_REQ_IDS          = 69;
  SSL_CTRL_GET_TLSEXT_STATUS_REQ_OCSP_RESP    = 70;
  SSL_CTRL_SET_TLSEXT_STATUS_REQ_OCSP_RESP    = 71;
  DTLS_CTRL_GET_TIMEOUT                       = 73;
  DTLS_CTRL_HANDLE_TIMEOUT                    = 74;
  SSL_CTRL_SET_TLS_EXT_SRP_USERNAME_CB        = 75;
  SSL_CTRL_GET_RI_SUPPORT                     = 76;
  SSL_CTRL_CLEAR_OPTIONS                      = 77;
  SSL_CTRL_CLEAR_MODE                         = 78;
  SSL_CTRL_SET_TLS_EXT_SRP_USERNAME           = 79;
  SSL_CTRL_SET_TLS_EXT_SRP_STRENGTH           = 80;
  SSL_CTRL_SET_TLS_EXT_SRP_PASSWORD           = 81;
  SSL_CTRL_GET_EXTRA_CHAIN_CERTS              = 82;
  SSL_CTRL_CLEAR_EXTRA_CHAIN_CERTS            = 83;
  SSL_CTRL_CHAIN                              = 88;
  SSL_CTRL_CHAIN_CERT                         = 89;
  SSL_CTRL_GET_CURVES                         = 90;
  SSL_CTRL_SET_CURVES                         = 91;
  SSL_CTRL_SET_CURVES_LIST                    = 92;
  SSL_CTRL_GET_SHARED_CURVE                   = 93;
  SSL_CTRL_SET_ECDH_AUTO                      = 94;
  SSL_CTRL_SET_SIGALGS                        = 97;
  SSL_CTRL_SET_SIGALGS_LIST                   = 98;
  SSL_CTRL_CERT_FLAGS                         = 99;
  SSL_CTRL_CLEAR_CERT_FLAGS                   = 100;
  SSL_CTRL_SET_CLIENT_SIGALGS                 = 101;
  SSL_CTRL_SET_CLIENT_SIGALGS_LIST            = 102;
  SSL_CTRL_GET_CLIENT_CERT_TYPES              = 103;
  SSL_CTRL_SET_CLIENT_CERT_TYPES              = 104;
  SSL_CTRL_BUILD_CERT_CHAIN                   = 105;
  SSL_CTRL_SET_VERIFY_CERT_STORE              = 106;
  SSL_CTRL_SET_CHAIN_CERT_STORE               = 107;
  SSL_CTRL_GET_PEER_SIGNATURE_NID             = 108;
  SSL_CTRL_GET_PEER_TMP_KEY                   = 109;
  SSL_CTRL_GET_SERVER_TMP_KEY                 = SSL_CTRL_GET_PEER_TMP_KEY;
  SSL_CTRL_GET_RAW_CIPHERLIST                 = 110;
  SSL_CTRL_GET_EC_POINT_FORMATS               = 111;
  SSL_CTRL_GET_CHAIN_CERTS                    = 115;
  SSL_CTRL_SELECT_CURRENT_CERT                = 116;
  SSL_CTRL_SET_CURRENT_CERT                   = 117;
  SSL_CTRL_SET_DH_AUTO                        = 118;
  SSL_CTRL_CHECK_PROTO_VERSION                = 119;
  DTLS_CTRL_SET_LINK_MTU                      = 120;
  DTLS_CTRL_GET_LINK_MIN_MTU                  = 121;
  SSL_CTRL_GET_EXTMS_SUPPORT                  = 122;
  SSL_CTRL_SET_MIN_PROTO_VERSION              = 123;
  SSL_CTRL_SET_MAX_PROTO_VERSION              = 124;
  SSL_CTRL_SET_SPLIT_SEND_FRAGMENT            = 125;
  SSL_CTRL_SET_MAX_PIPELINES                  = 126;
  SSL_CTRL_GET_TLSEXT_STATUS_REQ_TYPE         = 127;
  SSL_CTRL_GET_TLSEXT_STATUS_REQ_CB           = 128;
  SSL_CTRL_GET_TLSEXT_STATUS_REQ_CB_ARG       = 129;
  SSL_CTRL_GET_MIN_PROTO_VERSION              = 130;
  SSL_CTRL_GET_MAX_PROTO_VERSION              = 131;
  SSL_CTRL_GET_SIGNATURE_NID                  = 132;
  SSL_CTRL_GET_TMP_KEY                        = 133;
  SSL_CTRL_GET_NEGOTIATED_GROUP               = 134;
  SSL_CTRL_SET_RETRY_VERIFY                   = 136;
  SSL_CTRL_GET_VERIFY_CERT_STORE              = 137;
  SSL_CTRL_GET_CHAIN_CERT_STORE               = 138;

  // NameType value from RFC3546
  TLSEXT_NAMETYPE_host_name = 0;
  // status request value from RFC3546
  TLSEXT_STATUSTYPE_ocsp    = 1;

  SSL_MODE_ENABLE_PARTIAL_WRITE       = $00000001;
  SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER = $00000002;
  SSL_MODE_AUTO_RETRY                 = $00000004;
  SSL_MODE_NO_AUTO_CHAIN              = $00000008;

  // OBSOLETE OPTIONS retained for compatibility
  SSL_OP_MICROSOFT_SESS_ID_BUG                    = 0;
  SSL_OP_NETSCAPE_CHALLENGE_BUG                   = 0;
  SSL_OP_NETSCAPE_REUSE_CIPHER_CHANGE_BUG         = 0;
  SSL_OP_SSLREF2_REUSE_CERT_TYPE_BUG              = 0;
  SSL_OP_MICROSOFT_BIG_SSLV3_BUFFER               = 0;
  SSL_OP_MSIE_SSLV2_RSA_PADDING                   = 0;
  SSL_OP_SSLEAY_080_CLIENT_DH_BUG                 = 0;
  SSL_OP_TLS_D5_BUG                               = 0;
  SSL_OP_TLS_BLOCK_PADDING_BUG                    = 0;
  SSL_OP_SINGLE_ECDH_USE                          = 0;
  SSL_OP_SINGLE_DH_USE                            = 0;
  SSL_OP_EPHEMERAL_RSA                            = 0;
  SSL_OP_NO_SSLv2                                 = 0;
  SSL_OP_PKCS1_CHECK_1                            = 0;
  SSL_OP_PKCS1_CHECK_2                            = 0;
  SSL_OP_NETSCAPE_CA_DN_BUG                       = 0;
  SSL_OP_NETSCAPE_DEMO_CIPHER_CHANGE_BUG          = 0;

  // SSL/TLS connection options
  SSL_OP_NO_EXTENDED_MASTER_SECRET          = 1 shl 0;  // 禁用扩展主密钥
  SSL_OP_CLEANSE_PLAINTEXT                  = 1 shl 1;  // 清除交付给应用程序的明文数据副本
  SSL_OP_LEGACY_SERVER_CONNECT              = 1 shl 2;  // 允许连接到不支持RI的旧服务器
  SSL_OP_ENABLE_KTLS                        = 1 shl 3;  // 启用内核TLS支持
  SSL_OP_TLSEXT_PADDING                     = 1 shl 4;  // TLS扩展填充
  SSL_OP_SAFARI_ECDHE_ECDSA_BUG             = 1 shl 6;  // 修复Safari ECDHE-ECDSA兼容性问题
  SSL_OP_IGNORE_UNEXPECTED_EOF              = 1 shl 7;  // 忽略意外的EOF
  SSL_OP_ALLOW_CLIENT_RENEGOTIATION         = 1 shl 8;  // 允许客户端重新协商
  SSL_OP_DISABLE_TLSEXT_CA_NAMES            = 1 shl 9;  // 禁用TLS扩展CA名称
  SSL_OP_ALLOW_NO_DHE_KEX                   = 1 shl 10; // 在TLS1.3中允许非(EC)DHE密钥交换
  SSL_OP_DONT_INSERT_EMPTY_FRAGMENTS        = 1 shl 11; // 禁用空片段插入（CBC漏洞修复）

  // DTLS选项
  SSL_OP_NO_QUERY_MTU                       = 1 shl 12; // 禁用MTU查询
  SSL_OP_COOKIE_EXCHANGE                    = 1 shl 13; // 启用Cookie交换（仅服务器端）
  SSL_OP_NO_TICKET                          = 1 shl 14; // 禁用RFC4507票据扩展

{$IFNDEF OPENSSL_NO_DTLS1_METHOD}
  SSL_OP_CISCO_ANYCONNECT                   = 1 shl 15; // 使用Cisco的DTLS版本标识
{$ENDIF}

  SSL_OP_NO_SESSION_RESUMPTION_ON_RENEGOTIATION = 1 shl 16; // 服务器端禁止在重新协商时恢复会话
  SSL_OP_NO_COMPRESSION                     = 1 shl 17; // 禁用压缩
  SSL_OP_ALLOW_UNSAFE_LEGACY_RENEGOTIATION  = 1 shl 18; // 允许不安全的旧式重新协商
  SSL_OP_NO_ENCRYPT_THEN_MAC                = 1 shl 19; // 禁用Encrypt-then-MAC
  SSL_OP_ENABLE_MIDDLEBOX_COMPAT            = 1 shl 20; // 启用TLS1.3中间件兼容模式
  SSL_OP_PRIORITIZE_CHACHA                  = 1 shl 21; // 优先使用ChaCha20-Poly1305
  SSL_OP_CIPHER_SERVER_PREFERENCE           = 1 shl 22; // 服务器端密码套件优先
  SSL_OP_TLS_ROLLBACK_BUG                   = 1 shl 23; // 允许SSLv3版本号回滚
  SSL_OP_NO_ANTI_REPLAY                     = 1 shl 24; // 禁用TLS1.3反重放保护
  SSL_OP_NO_SSLV3                           = 1 shl 25; // 禁用SSLv3
  SSL_OP_NO_TLSV1                           = 1 shl 26; // 禁用TLS1.0
  SSL_OP_NO_TLSV1_2                         = 1 shl 27; // 禁用TLS1.2
  SSL_OP_NO_TLSV1_1                         = 1 shl 28; // 禁用TLS1.1
  SSL_OP_NO_TLSV1_3                         = 1 shl 29; // 禁用TLS1.3
  SSL_OP_NO_DTLSV1                          = 1 shl 26; // 禁用DTLS1.0
  SSL_OP_NO_DTLSV1_2                        = 1 shl 27; // 禁用DTLS1.2
  SSL_OP_NO_RENEGOTIATION                   = 1 shl 30; // 禁止所有重新协商
  SSL_OP_CRYPTOPRO_TLSEXT_BUG               = 1 shl 31; // Cryptopro TLS扩展兼容模式

  SSL_SESS_CACHE_OFF                      = $0000;
  SSL_SESS_CACHE_CLIENT                   = $0001;
  SSL_SESS_CACHE_SERVER                   = $0002;
  SSL_SESS_CACHE_BOTH                     = (SSL_SESS_CACHE_CLIENT or SSL_SESS_CACHE_SERVER);
  SSL_SESS_CACHE_NO_AUTO_CLEAR            = $0080;
  SSL_SESS_CACHE_NO_INTERNAL_LOOKUP       = $0100;
  SSL_SESS_CACHE_NO_INTERNAL_STORE        = $0200;
  SSL_SESS_CACHE_NO_INTERNAL              = (SSL_SESS_CACHE_NO_INTERNAL_LOOKUP or SSL_SESS_CACHE_NO_INTERNAL_STORE);
  SSL_SESS_CACHE_UPDATE_TIME              = $0400;

  NID_X9_62_prime192v1            = 409;
  NID_X9_62_prime192v2            = 410;
  NID_X9_62_prime192v3            = 411;
  NID_X9_62_prime239v1            = 412;
  NID_X9_62_prime239v2            = 413;
  NID_X9_62_prime239v3            = 414;
  NID_X9_62_prime256v1            = 415;

  NID_subject_key_identifier              = 82;
  NID_key_usage                           = 83;
  NID_subject_alt_name                    = 85;
  NID_basic_constraints                   = 87;
  NID_certificate_policies                = 89;
  NID_authority_key_identifier            = 90;
  NID_crl_distribution_points             = 103;
  NID_ext_key_usage                       = 126;
  NID_server_auth                         = 129;
  NID_client_auth                         = 130;
  NID_code_sign                           = 131;
  NID_email_protect                       = 132;
  NID_time_stamp                          = 133;
  NID_ms_sgc                              = 137;
  NID_ns_sgc                              = 139;
  NID_id_qt_cps                           = 164;
  NID_id_qt_unotice                       = 165;
  NID_info_access                         = 177;
  NID_OCSP_sign                           = 180;
  NID_dvcs                                = 297;
  NID_anyExtendedKeyUsage                 = 910;
  NID_ct_cert_scts                        = 954;
  NID_ct_precert_scts                     = 951;

  CRYPTO_LOCK		= 1;
  CRYPTO_UNLOCK	= 2;
  CRYPTO_READ   = 4;
  CRYPTO_WRITE  = 8;

  BIO_FLAGS_READ                          = 1;
  BIO_FLAGS_WRITE                         = 2;
  BIO_FLAGS_IO_SPECIAL                    = 4;
  BIO_FLAGS_RWS                           = (BIO_FLAGS_READ or
                                             BIO_FLAGS_WRITE or
                                             BIO_FLAGS_IO_SPECIAL);
  BIO_FLAGS_SHOULD_RETRY                  = 8;

  OSSL_VER_0908  = $00908000;
  OSSL_VER_1000  = $10000000;
  OSSL_VER_1001  = $10001000;
  OSSL_VER_1002  = $10002000;
  OSSL_VER_1100  = $10100000;

  SSL3_VERSION                                = $0300;
  SSL3_VERSION_MAJOR                          = $03;
  SSL3_VERSION_MINOR                          = $00;

  TLS1_VERSION                                = $0301;
  TLS1_VERSION_MAJOR                          = $03;
  TLS1_VERSION_MINOR                          = $01;

  TLS1_1_VERSION                              = $0302;
  TLS1_1_VERSION_MAJOR                        = $03;
  TLS1_1_VERSION_MINOR                        = $02;

  TLS1_2_VERSION                              = $0303;
  TLS1_2_VERSION_MAJOR                        = $03;
  TLS1_2_VERSION_MINOR                        = $03;

  TLS1_3_VERSION                              = $0304;
  TLS1_3_VERSION_MAJOR                        = $03;
  TLS1_3_VERSION_MINOR                        = $04;

  TLS_MAX_VERSION                             = TLS1_3_VERSION;
  // Special value for method supporting multiple versions
  TLS_ANY_VERSION                             = $10000;

  DTLS1_VERSION                               = $FEFF;
  DTLS1_2_VERSION                             = $FEFD;
  DTLS_MAX_VERSION                            = DTLS1_2_VERSION;
  DTLS1_VERSION_MAJOR                         = $FE;
  DTLS1_BAD_VER                               = $0100;
  // Special value for method supporting multiple versions
  DTLS_ANY_VERSION                            = $1FFFF;

  OPENSSL_INIT_NO_LOAD_SSL_STRINGS            = $00100000;
  OPENSSL_INIT_LOAD_SSL_STRINGS               = $00200000;

  TLS_ST_OK                                   = 1;

  OPENSSL_INIT_NO_LOAD_CRYPTO_STRINGS = $00000001;
  OPENSSL_INIT_LOAD_CRYPTO_STRINGS    = $00000002;
  OPENSSL_INIT_ADD_ALL_CIPHERS        = $00000004;
  OPENSSL_INIT_ADD_ALL_DIGESTS        = $00000008;
  OPENSSL_INIT_NO_ADD_ALL_CIPHERS     = $00000010;
  OPENSSL_INIT_NO_ADD_ALL_DIGESTS     = $00000020;
  OPENSSL_INIT_LOAD_CONFIG            = $00000040;
  OPENSSL_INIT_NO_LOAD_CONFIG         = $00000080;
  OPENSSL_INIT_ASYNC                  = $00000100;
  OPENSSL_INIT_ENGINE_RDRAND          = $00000200;
  OPENSSL_INIT_ENGINE_DYNAMIC         = $00000400;
  OPENSSL_INIT_ENGINE_OPENSSL         = $00000800;
  OPENSSL_INIT_ENGINE_CRYPTODEV       = $00001000;
  OPENSSL_INIT_ENGINE_CAPI            = $00002000;
  OPENSSL_INIT_ENGINE_PADLOCK         = $00004000;
  OPENSSL_INIT_ENGINE_AFALG           = $00008000;

  ASN1_STRFLGS_ESC_2253     = 1;
  ASN1_STRFLGS_ESC_CTRL     = 2;
  ASN1_STRFLGS_ESC_MSB      = 4;
  ASN1_STRFLGS_ESC_QUOTE    = 8;
  ASN1_STRFLGS_UTF8_CONVERT = $10;
  ASN1_STRFLGS_IGNORE_TYPE  = $20;
  ASN1_STRFLGS_SHOW_TYPE    = $40;
  ASN1_STRFLGS_DUMP_ALL     = $80;
  ASN1_STRFLGS_DUMP_UNKNOWN = $100;
  ASN1_STRFLGS_DUMP_DER     = $200;
  ASN1_STRFLGS_ESC_2254     = $400;

  ASN1_STRFLGS_RFC2253 = ASN1_STRFLGS_ESC_2253
    or ASN1_STRFLGS_ESC_CTRL
    or ASN1_STRFLGS_ESC_MSB
    or ASN1_STRFLGS_UTF8_CONVERT
    or ASN1_STRFLGS_DUMP_UNKNOWN
    or ASN1_STRFLGS_DUMP_DER;

  X509_VERSION_1  = 0;
  X509_VERSION_2  = 1;
  X509_VERSION_3  = 2;

  X509_SIG_INFO_VALID = 1;
  X509_SIG_INFO_TLS   = 2;

  X509_FILETYPE_PEM     = 1;
  X509_FILETYPE_ASN1    = 2;
  X509_FILETYPE_DEFAULT = 3;

  X509v3_KU_DIGITAL_SIGNATURE = $0080;
  X509v3_KU_NON_REPUDIATION   = $0040;
  X509v3_KU_KEY_ENCIPHERMENT  = $0020;
  X509v3_KU_DATA_ENCIPHERMENT = $0010;
  X509v3_KU_KEY_AGREEMENT     = $0008;
  X509v3_KU_KEY_CERT_SIGN     = $0004;
  X509v3_KU_CRL_SIGN          = $0002;
  X509v3_KU_ENCIPHER_ONLY     = $0001;
  X509v3_KU_DECIPHER_ONLY     = $8000;
  X509v3_KU_UNDEF             = $FFFF;

  X509_EX_V_NETSCAPE_HACK = $8000;
  X509_EX_V_INIT          = $0001;

  X509_FLAG_COMPAT              = 0;
  X509_FLAG_NO_HEADER           = 1;
  X509_FLAG_NO_VERSION          = 1 shl 1;
  X509_FLAG_NO_SERIAL           = 1 shl 2;
  X509_FLAG_NO_SIGNAME          = 1 shl 3;
  X509_FLAG_NO_ISSUER           = 1 shl 4;
  X509_FLAG_NO_VALIDITY         = 1 shl 5;
  X509_FLAG_NO_SUBJECT          = 1 shl 6;
  X509_FLAG_NO_PUBKEY           = 1 shl 7;
  X509_FLAG_NO_EXTENSIONS       = 1 shl 8;
  X509_FLAG_NO_SIGDUMP          = 1 shl 9;
  X509_FLAG_NO_AUX              = 1 shl 10;
  X509_FLAG_NO_ATTRIBUTES       = 1 shl 11;
  X509_FLAG_NO_IDS              = 1 shl 12;
  X509_FLAG_EXTENSIONS_ONLY_KID = 1 shl 13;

  XN_FLAG_SEP_MASK = $F shl 16;
  XN_FLAG_COMPAT = 0;
  XN_FLAG_SEP_COMMA_PLUS = 1 shl 16;
  XN_FLAG_SEP_CPLUS_SPC  = 2 shl 16;
  XN_FLAG_SEP_SPLUS_SPC  = 3 shl 16;
  XN_FLAG_SEP_MULTILINE  = 4 shl 16;

  XN_FLAG_DN_REV  = 1 shl 20;

  XN_FLAG_FN_MASK = 3 shl 21;
  XN_FLAG_FN_SN   = 0;
  XN_FLAG_FN_LN   = 1 shl 21;
  XN_FLAG_FN_OID  = 2 shl 21;
  XN_FLAG_FN_NONE = 3 shl 21;

  XN_FLAG_SPC_EQ              = 1 shl 23;
  XN_FLAG_DUMP_UNKNOWN_FIELDS = 1 shl 24;
  XN_FLAG_FN_ALIGN            = 1 shl 25;

  XN_FLAG_RFC2253 = ASN1_STRFLGS_RFC2253
    or XN_FLAG_SEP_COMMA_PLUS
    or XN_FLAG_DN_REV
    or XN_FLAG_FN_SN
    or XN_FLAG_DUMP_UNKNOWN_FIELDS;

  XN_FLAG_ONELINE = ASN1_STRFLGS_RFC2253
    or ASN1_STRFLGS_ESC_QUOTE
    or XN_FLAG_SEP_CPLUS_SPC
    or XN_FLAG_SPC_EQ
    or XN_FLAG_FN_SN;

  XN_FLAG_MULTILINE = ASN1_STRFLGS_ESC_CTRL
    or ASN1_STRFLGS_ESC_MSB
    or XN_FLAG_SEP_MULTILINE
    or XN_FLAG_SPC_EQ
    or XN_FLAG_FN_LN
    or XN_FLAG_FN_ALIGN;

  EVP_MAX_MD_SIZE                = 64;
  EVP_MAX_KEY_LENGTH             = 64;
  EVP_MAX_IV_LENGTH              = 16;
  EVP_MAX_BLOCK_LENGTH           = 32;
  EVP_MAX_AEAD_TAG_LENGTH        = 16;

  EVP_MAX_PIPES                  = 32;

  GEN_OTHERNAME   = 0;
  GEN_EMAIL       = 1;
  GEN_DNS         = 2;
  GEN_X400        = 3;
  GEN_DIRNAME     = 4;
  GEN_EDIPARTY    = 5;
  GEN_URI         = 6;
  GEN_IPADD       = 7;
  GEN_RID         = 8;

  XKU_SSL_SERVER          = $1;
  XKU_SSL_CLIENT          = $2;
  XKU_SMIME               = $4;
  XKU_CODE_SIGN           = $8;
  XKU_SGC                 = $10; // Netscape or MS Server-Gated Crypto
  XKU_OCSP_SIGN           = $20;
  XKU_TIMESTAMP           = $40;
  XKU_DVCS                = $80;
  XKU_ANYEKU              = $100;

  CRL_REASON_NONE	                  =	-1;
  CRL_REASON_UNSPECIFIED            = 0;
  CRL_REASON_KEY_COMPROMISE	        = 1;
  CRL_REASON_CA_COMPROMISE          = 2;
  CRL_REASON_AFFILIATION_CHANGED    = 3;
  CRL_REASON_SUPERSEDED             = 4;
  CRL_REASON_CESSATION_OF_OPERATION = 5;
  CRL_REASON_CERTIFICATE_HOLD	      = 6;
  CRL_REASON_REMOVE_FROM_CRL        = 8;
  CRL_REASON_PRIVILEGE_WITHDRAWN    = 9;
  CRL_REASON_AA_COMPROMISE          = 10;

type
  size_t = NativeUInt;
  ASN1_BOOLEAN = Integer;
  PASN1_BOOLEAN = ^ASN1_BOOLEAN;

  asn1_string_st = record
    length: Integer;
    &type: Integer;
    data: Pointer;
    (*
     * The value of the following field depends on the type being held.  It
     * is mostly being used for BIT_STRING so if the input data has a
     * non-zero 'unused bits' value, it will be handled correctly
     *)
    flags: LongInt;
  end;
  ASN1_STRING = asn1_string_st;
  PASN1_STRING = ^ASN1_STRING;

  PASN1_INTEGER         = PASN1_STRING;
  PASN1_ENUMERATED      = PASN1_STRING;
  PASN1_BIT_STRING      = PASN1_STRING;
  PASN1_OCTET_STRING    = PASN1_STRING;
  PASN1_PRINTABLESTRING = PASN1_STRING;
  PASN1_T61STRING       = PASN1_STRING;
  PASN1_IA5STRING       = PASN1_STRING;
  PASN1_GENERALSTRING   = PASN1_STRING;
  PASN1_UNIVERSALSTRING = PASN1_STRING;
  PASN1_BMPSTRING       = PASN1_STRING;
  PASN1_UTCTIME         = PASN1_STRING;
  PASN1_TIME            = PASN1_STRING;
  PASN1_GENERALIZEDTIME = PASN1_STRING;
  PASN1_VISIBLESTRING   = PASN1_STRING;
  PASN1_UTF8STRING      = PASN1_STRING;

  PPASN1_INTEGER         = ^PASN1_INTEGER;
  PPASN1_ENUMERATED      = ^PASN1_ENUMERATED;
  PPASN1_BIT_STRING      = ^PASN1_BIT_STRING;
  PPASN1_OCTET_STRING    = ^PASN1_OCTET_STRING;
  PPASN1_PRINTABLESTRING = ^PASN1_PRINTABLESTRING;
  PPASN1_T61STRING       = ^PASN1_T61STRING;
  PPASN1_IA5STRING       = ^PASN1_IA5STRING;
  PPASN1_GENERALSTRING   = ^PASN1_GENERALSTRING;
  PPASN1_UNIVERSALSTRING = ^PASN1_UNIVERSALSTRING;
  PPASN1_BMPSTRING       = ^PASN1_BMPSTRING;
  PPASN1_UTCTIME         = ^PASN1_UTCTIME;
  PPASN1_TIME            = ^PASN1_TIME;
  PPASN1_GENERALIZEDTIME = ^PASN1_GENERALIZEDTIME;
  PPASN1_VISIBLESTRING   = ^PASN1_VISIBLESTRING;
  PPASN1_UTF8STRING      = ^PASN1_UTF8STRING;
  PPASN1_STRING          = ^PASN1_STRING;

  asn1_object_st = record
    sn, ln: PAnsiChar;
    nid: Integer;
    length: Integer;
    data: Pointer;  // data remains const after init
    flags: Integer; // Should we free this one
  end;
  ASN1_OBJECT = asn1_object_st;
  PASN1_OBJECT = ^ASN1_OBJECT;

  PASN1_VALUE  = Pointer;
  PPASN1_VALUE = ^PASN1_VALUE;
  PASN1_ITEM   = Pointer;

  asn1_type_st = record
    &type: Integer;
    value: record
      case Integer of
        0: (ptr: Pointer);
        1: (&boolean: PASN1_BOOLEAN);
        2: (asn1_string: PASN1_STRING);
        3: (&object: PASN1_OBJECT);
        4: (&integer: PASN1_INTEGER);
        5: (enumerated: PASN1_ENUMERATED);
        6: (bit_string: PASN1_BIT_STRING);
        7: (octet_string: PASN1_OCTET_STRING);
        8: (printablestring: PASN1_PRINTABLESTRING);
        9: (t61string: PASN1_T61STRING);
        10: (ia5string: PASN1_IA5STRING);
        11: (generalstring: PASN1_GENERALSTRING);
        12: (bmpstring: PASN1_BMPSTRING);
        13: (universalstring: PASN1_UNIVERSALSTRING);
        14: (utctime: PASN1_UTCTIME);
        15: (generalizedtime: PASN1_GENERALIZEDTIME);
        16: (visiblestring: PASN1_VISIBLESTRING);
        17: (utf8string: PASN1_UTF8STRING);
        (*
         * set and sequence are left complete and still contain the set or
         * sequence bytes
         *)
        18: (&set: PASN1_STRING);
        19: (sequence: PASN1_STRING);
        20: (asn1_value: PASN1_VALUE);
    end;
  end;
  ASN1_TYPE = asn1_type_st;
  PASN1_TYPE = ^ASN1_TYPE;

  PBIGNUM = Pointer;
  PPBIGNUM = ^PBIGNUM;

  PSSL_CTX = Pointer;
  PSSL = Pointer;
  PSSL_METHOD = Pointer;
  PSSL_CIPHER = Pointer;

  PBIO = Pointer;
  PPBIO = ^PBIO;

  PEVP_PKEY = Pointer;
  PPEVP_PKEY = ^PEVP_PKEY;
  PEVP_MD = Pointer;
  PEVP_MD_CTX = Pointer;
  PRSA = Pointer;

  PENGINE = Pointer;

  PX509 = Pointer;
  PPX509 = ^PX509;
  PX509_NAME = Pointer;
  PX509_NAME_ENTRY = Pointer;
  PX509_STORE_CTX = Pointer;
  PX509_STORE = Pointer;
  PX509_EXTENSION = Pointer;
  PX509V3_EXT_METHOD = Pointer;

  X509_ALGOR_st = record
    algorithm: PASN1_OBJECT;
    parameter: PASN1_TYPE;
  end;
  X509_ALGOR = X509_ALGOR_st;
  PX509_ALGOR = ^X509_ALGOR;
  PPX509_ALGOR = ^PX509_ALGOR;

  otherName_st = record
    type_id: PASN1_OBJECT;
    value: PASN1_TYPE;
  end;
  OTHERNAME = otherName_st;
  POTHERNAME = ^OTHERNAME;

  PEDIPARTYNAME = Pointer;

  GENERAL_NAME_st = record
    &type: Integer;
    d: record
      case Integer of
        0: (ptr: Pointer);
        1: (otherName: POTHERNAME);   // otherName
        2: (rfc822Name: PASN1_IA5STRING);
        3: (dNSName: PASN1_IA5STRING);
        4: (x400Address: PASN1_STRING);
        5: (directoryName: PX509_NAME);
        6: (ediPartyName: PEDIPARTYNAME);
        7: (uniformResourceIdentifier: PASN1_IA5STRING);
        8: (iPAddress: PASN1_OCTET_STRING);
        9: (registeredID: PASN1_OBJECT);
        // Old names
        10: (ip: PASN1_OCTET_STRING);  // iPAddress
        11: (dirn: PX509_NAME);        // dirn
        12: (ia5: PASN1_IA5STRING);    // rfc822Name, dNSName,
                                       // uniformResourceIdentifier
        13: (rid: PASN1_OBJECT);       // registeredID
        14: (other: PASN1_TYPE);       // x400Address
    end;
  end;
  GENERAL_NAME = GENERAL_NAME_st;
  PGENERAL_NAME = ^GENERAL_NAME;
  PGENERAL_NAMES = PGENERAL_NAME;

  DIST_POINT_NAME_st = record
    &type: Integer;
    name: record
      case Integer of
        0: (fullname: PGENERAL_NAMES);
        1: (relativename: PX509_NAME_ENTRY);
    end;
    // If relativename then this contains the full distribution point name */
    dpname: PX509_NAME;
  end;
  DIST_POINT_NAME = DIST_POINT_NAME_st;
  PDIST_POINT_NAME = ^DIST_POINT_NAME;
  PPDIST_POINT_NAME = ^PDIST_POINT_NAME;

  DIST_POINT_st = record
    distpoint: PDIST_POINT_NAME;
    reasons: PASN1_BIT_STRING;
    CRLissuer: PGENERAL_NAMES;
    dp_reasons: Integer;
  end;
  DIST_POINT = DIST_POINT_st;
  PDIST_POINT = ^DIST_POINT;
  PPDIST_POINT = ^PDIST_POINT;

  AUTHORITY_KEYID_st = record
    keyid: PASN1_OCTET_STRING;
    issuer: PGENERAL_NAMES;
    serial: PASN1_INTEGER;
  end;
  AUTHORITY_KEYID = AUTHORITY_KEYID_st;
  PAUTHORITY_KEYID = ^AUTHORITY_KEYID;
  PPAUTHORITY_KEYID = ^PAUTHORITY_KEYID;

  POLICYINFO_st = record
      policyid: PASN1_OBJECT;
      qualifiers: Pointer;
  end;
  POLICYINFO = POLICYINFO_st;
  PPOLICYINFO = ^POLICYINFO;

  NOTICEREF_st = record
    organization: PASN1_STRING;
    noticenos: PASN1_INTEGER;
  end;
  NOTICEREF = NOTICEREF_st;
  PNOTICEREF = ^NOTICEREF;

  USERNOTICE_st = record
    noticeref: PNOTICEREF;
    exptext: PASN1_STRING;
  end;
  USERNOTICE = USERNOTICE_st;
  PUSERNOTICE = ^USERNOTICE;

  POLICYQUALINFO_st = record
    pqualid: PASN1_OBJECT;
    d: record
      case Integer of
        0: (cpsuri: PASN1_IA5STRING);
        1: (usernotice: PUSERNOTICE);
        2: (other: PASN1_TYPE);
    end;
  end;
  POLICYQUALINFO = POLICYQUALINFO_st;
  PPOLICYQUALINFO = ^POLICYQUALINFO;

  ACCESS_DESCRIPTION_st = record
    method : PASN1_OBJECT;
    location : PGENERAL_NAME;
  end;
  ACCESS_DESCRIPTION = ACCESS_DESCRIPTION_st;
  PACCESS_DESCRIPTION = ^ACCESS_DESCRIPTION;
  PPACCESS_DESCRIPTION = ^PACCESS_DESCRIPTION;

  PAUTHORITY_INFO_ACCESS = Pointer;

  BASIC_CONSTRAINTS_st = record
   ca : Integer;
   pathlen: PASN1_INTEGER;
  end;
  BASIC_CONSTRAINTS = BASIC_CONSTRAINTS_st;
  PBASIC_CONSTRAINTS = ^BASIC_CONSTRAINTS;
  PPBASIC_CONSTRAINTS = ^PBASIC_CONSTRAINTS;

  ct_log_entry_type_t = (
    CT_LOG_ENTRY_TYPE_NOT_SET = -1,
    CT_LOG_ENTRY_TYPE_X509 = 0,
    CT_LOG_ENTRY_TYPE_PRECERT = 1
  );
  TCtLogEntryType = ct_log_entry_type_t;

  sct_version_t = (
    SCT_VERSION_NOT_SET = -1,
    SCT_VERSION_V1 = 0
  );
  TSctVersion = sct_version_t;

  sct_source_t = (
    SCT_SOURCE_UNKNOWN,
    SCT_SOURCE_TLS_EXTENSION,
    SCT_SOURCE_X509V3_EXTENSION,
    SCT_SOURCE_OCSP_STAPLED_RESPONSE
  );
  TSctSource = sct_source_t;

  sct_validation_status_t = (
    SCT_VALIDATION_STATUS_NOT_SET,
    SCT_VALIDATION_STATUS_UNKNOWN_LOG,
    SCT_VALIDATION_STATUS_VALID,
    SCT_VALIDATION_STATUS_INVALID,
    SCT_VALIDATION_STATUS_UNVERIFIED,
    SCT_VALIDATION_STATUS_UNKNOWN_VERSION
  );
  TSctValidationStatus = sct_validation_status_t;

  sct_st = record
    version: sct_version_t;
    // If version is not SCT_VERSION_V1, this contains the encoded SCT
    sct: Pointer;
    sct_len: size_t;
    // If version is SCT_VERSION_V1, fields below contain components of the SCT
    log_id: Pointer;
    log_id_len: size_t;
    (*
    * Note, we cannot distinguish between an unset timestamp, and one
    * that is set to 0.  However since CT didn't exist in 1970, no real
    * SCT should ever be set as such.
    *)
    timestamp: UInt64;
    ext: Pointer;
    ext_len: size_t;
    hash_alg: Byte;
    sig_alg: Byte;
    sig: Pointer;
    sig_len: size_t;
    // Log entry type
    entry_type: ct_log_entry_type_t;
    // Where this SCT was found, e.g. certificate, OCSP response, etc.
    source: sct_source_t;
    // The result of the last attempt to validate this SCT.
    validation_status: sct_validation_status_t;
  end;
  SCT = sct_st;
  PSCT = ^SCT;
  PPSCT = ^PSCT;

  buf_mem_st = record
    length: size_t;              // current number of bytes
    data: Pointer;
    max: size_t;                 // size of buffer
    flags: LongWord;
  end;
  BUF_MEM = buf_mem_st;
  PBUF_MEM = ^BUF_MEM;
  PPBUF_MEM = ^PBUF_MEM;

  TTM = record
    tm_sec: Integer;  // 秒      [0, 60]（允许闰秒）
    tm_min: Integer;  // 分      [0, 59]
    tm_hour: Integer; // 小时    [0, 23]
    tm_mday: Integer; // 月内日  [1, 31]
    tm_mon: Integer;  // 月份    [0, 11]（0=一月，11=十二月）
    tm_year: Integer; // 年份    （实际年份 = tm_year + 1900）
    tm_wday: Integer; // 周内日  [0, 6] （0=周日，1=周一，...）
    tm_yday: Integer; // 年内日  [0, 365]
    tm_isdst: Integer;// 夏令时标志（负数=未知，0=未生效，正数=生效）

    // 以下字段为扩展（非标准，部分平台支持）
    tm_gmtoff: LongInt;     // 与UTC的秒数偏移（如东八区为 +28800）
    tm_zone: PAnsiChar; // 时区缩写（如"CST"）
  end;
  PTM = ^TTM;

  TSetVerifyCb = function(Ok: Integer; StoreCtx: PX509_STORE_CTX): Integer; cdecl;

  PCRYPTO_THREADID = Pointer;
  PBIO_METHOD = Pointer;
  PSTACK = Pointer;
  PEC_KEY = Pointer;
  POPENSSL_STACK = Pointer;
  OPENSSL_sk_freefunc = procedure(p: Pointer); cdecl;

  TPemPasswordCb =  function(buf: Pointer; size, rwflag: Integer; userdata: Pointer): Integer; cdecl;

{$IFNDEF __SSL_STATIC__}

var
  {$REGION 'LIBCRYPTO-FUNC'}
  OpenSSL_version_num: function: Longword; cdecl;
  OPENSSL_init_crypto: function(opts: UInt64; settings: Pointer): Integer; cdecl;
  OPENSSL_cleanup: procedure; cdecl;

  ERR_error_string_n: procedure(err: Cardinal; buf: MarshaledAString; len: size_t); cdecl;
  ERR_get_error: function: Cardinal; cdecl;

  EVP_PKEY_new: function(): PEVP_PKEY; cdecl;
  EVP_PKEY_free: procedure(pkey: PEVP_PKEY); cdecl;
  EVP_PKEY_get_size: function(key: PEVP_PKEY): Integer; cdecl;
  EVP_PKEY_get_bits: function(key: PEVP_PKEY): Integer; cdecl;
  EVP_PKEY_get_id: function(key: PEVP_PKEY): Integer; cdecl;
  EVP_PKEY_get_security_bits: function(key: PEVP_PKEY): Integer; cdecl;
  EVP_PKEY_get0_RSA: function(key: PEVP_PKEY): PRSA; cdecl;
  EVP_PKEY_CTX_new_id: function(id: Integer; e: Pointer): PEVP_PKEY; cdecl;

  EVP_sha256: function(): PEVP_MD; cdecl;
  EVP_Digest: function(data: Pointer; count: size_t; md: Pointer; size: PCardinal; t: PEVP_MD; impl: PENGINE): Integer; cdecl;

  EVP_MD_CTX_new: function(): PEVP_MD_CTX; cdecl;
  EVP_MD_CTX_free: procedure(ctx: PEVP_MD_CTX); cdecl;
  EVP_DigestInit_ex: function(ctx: PEVP_MD_CTX; t: PEVP_MD; impl: PENGINE): Integer; cdecl;
  EVP_DigestUpdate: function(ctx: PEVP_MD_CTX; d: Pointer; cnt: size_t): Integer; cdecl;
  EVP_DigestFinal_ex: function(ctx: PEVP_MD_CTX; md: Pointer; s: PCardinal): Integer; cdecl;

  BIO_new: function(BioMethods: PBIO_METHOD): PBIO; cdecl;
  BIO_ctrl: function(bp: PBIO; cmd: Integer; larg: Longint; parg: Pointer): Longint; cdecl;
  BIO_new_mem_buf: function(buf: Pointer; len: Integer): PBIO; cdecl;
  BIO_free: function(b: PBIO): Integer; cdecl;
  BIO_s_mem: function: PBIO_METHOD; cdecl;
  BIO_read: function(b: PBIO; Buf: Pointer; Len: Integer): Integer; cdecl;
  BIO_write: function(b: PBIO; Buf: Pointer; Len: Integer): Integer; cdecl;

  EC_KEY_new_by_curve_name: function(nid: Integer): PEC_KEY; cdecl;
  EC_KEY_free: procedure(key: PEC_KEY); cdecl;

  X509_get_issuer_name: function(cert: PX509): PX509_NAME; cdecl;
  X509_get_subject_name: function(cert: PX509): PX509_NAME; cdecl;
  X509_get_serialNumber: function(x: PX509): PASN1_INTEGER; cdecl;
  X509_get_version: function(x: PX509): LongInt; cdecl;
  X509_get_ext_d2i: function(x: PX509; nid: Integer; crit, idx: PInteger): Pointer; cdecl;
  X509_get_signature_nid: function(x: PX509): Integer; cdecl;
  X509_get0_signature: procedure(psig: PPASN1_BIT_STRING; palg: PPX509_ALGOR; x: PX509); cdecl;
  X509_get0_notBefore: function(x: PX509): PASN1_TIME; cdecl;
  X509_get0_notAfter: function(x: PX509): PASN1_TIME; cdecl;
  X509_get0_tbs_sigalg: function(x: PX509): PX509_ALGOR; cdecl;
  X509_get0_pubkey: function(x: PX509): PEVP_PKEY; cdecl;
  X509_get0_extensions: function(x: PX509): PX509_EXTENSION; cdecl;
  X509_get_ext_count: function(x: PX509): Integer; cdecl;
  X509_get_ext: function(x: PX509; loc: Integer): PX509_EXTENSION; cdecl;
  X509_NAME_print_ex: function(bout: PBIO; nm: PX509_NAME; indent: Integer; flags: Cardinal): Integer; cdecl;
  X509_NAME_get_entry: function(name: PX509_NAME; loc: Integer): PX509_NAME_ENTRY; cdecl;
  X509_NAME_ENTRY_get_object: function(ne: PX509_NAME_ENTRY): PASN1_OBJECT; cdecl;
  X509_NAME_ENTRY_get_data: function(ne: PX509_NAME_ENTRY): PASN1_STRING; cdecl;
  X509_NAME_entry_count: function(name: PX509_NAME): Integer; cdecl;
  X509_EXTENSION_get_object: function(ex: PX509_EXTENSION): PASN1_OBJECT; cdecl;
  X509_EXTENSION_get_critical: function(ex: PX509_EXTENSION): Integer; cdecl;
  X509_EXTENSION_get_data: function(ex: PX509_EXTENSION): PASN1_OCTET_STRING; cdecl;
  X509V3_EXT_d2i: function(ex: PX509_EXTENSION): Pointer; cdecl;
  X509V3_EXT_get: function(ex: PX509_EXTENSION): PX509V3_EXT_METHOD; cdecl;
  X509_STORE_add_cert: function(Store: PX509_STORE; Cert: PX509): Integer; cdecl;

  X509_digest: function(data: PX509; t: PEVP_MD; md: Pointer; len: PCardinal): Integer; cdecl;
  X509_pubkey_digest: function(data: PX509; t: PEVP_MD; md: Pointer; len: PCardinal): Integer; cdecl;
  X509_free: procedure(cert: PX509); cdecl;

  OPENSSL_sk_num: function(stack: PSTACK): Integer; cdecl;
  OPENSSL_sk_pop: function(stack: PSTACK): Pointer; cdecl;
  OPENSSL_sk_value: function(stack: PSTACK; i: Integer): Pointer; cdecl;
  OPENSSL_sk_free: procedure(p: PSTACK); cdecl;
  OPENSSL_sk_pop_free: procedure(st: POPENSSL_STACK; func: OPENSSL_sk_freefunc); cdecl;

  OPENSSL_hexstr2buf: function(str: PAnsiString; len: PLongInt): Pointer; cdecl;
  OPENSSL_buf2hexstr: function(buf: Pointer; buflen: LongInt): PAnsiChar; cdecl;

  PEM_read_bio_X509: function(bp: PBIO; x: PPX509; cb: TPemPasswordCb; u: Pointer): PX509; cdecl;
  PEM_read_bio_X509_AUX: function(bp: PBIO; x: PPX509; cb: TPemPasswordCb; u: Pointer): PX509; cdecl;
  PEM_read_bio_PrivateKey: function(bp: PBIO; x: PPEVP_PKEY; cb: TPemPasswordCb; u: Pointer): PEVP_PKEY; cdecl;
  PEM_write_bio_PUBKEY: function(bp: PBIO; x: PEVP_PKEY): Integer; cdecl;
  PEM_read_bio_PUBKEY: function(bp: PBIO; x: PPEVP_PKEY; cb: TPemPasswordCb; u: Pointer): PEVP_PKEY; cdecl;
  PEM_write_bio_X509: function(bp: PBIO; x: PX509): Integer; cdecl;

  OBJ_nid2obj: function(n: Integer): PASN1_OBJECT; cdecl;
  OBJ_nid2ln: function(n: Integer): PAnsiChar; cdecl;
  OBJ_nid2sn: function(n: Integer): PAnsiChar; cdecl;
  OBJ_obj2nid: function(o: PASN1_OBJECT): Integer; cdecl;
  OBJ_ln2nid: function(ln: PAnsiChar): Integer; cdecl;
  OBJ_sn2nid: function(sn: PAnsiChar): Integer; cdecl;
  OBJ_obj2txt: function(buf: PAnsiChar; buf_len: Integer; a: PASN1_OBJECT; no_name: Integer): Integer; cdecl;

  CRYPTO_malloc: function(num: size_t; f: PAnsiChar; l: Integer): Pointer; cdecl;
  CRYPTO_free: procedure(str: Pointer; f: PAnsiChar; l: Integer); cdecl;

  ASN1_STRING_to_UTF8: function(outs: PPAnsiChar; ins: PASN1_STRING): Integer; cdecl;
  ASN1_STRING_length: function(x: PASN1_STRING): Integer; cdecl;
  ASN1_STRING_get0_data: function(x: PASN1_STRING): PAnsiChar; cdecl;
  ASN1_TIME_to_tm: function(t: PASN1_TIME; tm: PTM): Integer; cdecl;
  ASN1_TIME_print: function(b: PBIO; tm: PASN1_TIME): Integer; cdecl;
  ASN1_item_d2i: function(pval: PPASN1_VALUE; idata: PPointer; len: LongInt; it: PASN1_ITEM): PASN1_VALUE; cdecl;
  ASN1_BIT_STRING_get_bit: function(a: PASN1_BIT_STRING; n: Integer): Integer; cdecl;
  ASN1_BIT_STRING_set_bit: function(a: PASN1_BIT_STRING; n, value: Integer): Integer; cdecl;
  ASN1_INTEGER_get: function(a: PASN1_BIT_STRING): LongInt; cdecl;
  ASN1_INTEGER_set: function(a: PASN1_BIT_STRING; v: LongInt): Integer; cdecl;

  ASN1_INTEGER_to_BN: function(ai: PASN1_INTEGER; bn: PBIGNUM): PBIGNUM; cdecl;
  BN_to_ASN1_INTEGER: function(bn: PBIGNUM; ai: PASN1_INTEGER): PASN1_INTEGER; cdecl;
  BN_bn2hex: function(bn: PBIGNUM): PAnsiChar; cdecl;

  i2d_PublicKey: function(a: PEVP_PKEY; pp: PPointer): Integer; cdecl;
  i2d_PUBKEY: function(a: PEVP_PKEY; pp: PPointer): Integer; cdecl;
  i2d_X509: function(x: PX509; d: PPointer): Integer; cdecl;

  RSA_get0_key: procedure(r: PRSA; n, e, d: PPBIGNUM); cdecl;

  AUTHORITY_KEYID_free: procedure(p: Pointer); cdecl;
  ASN1_OCTET_STRING_free: procedure(p: Pointer); cdecl;
  GENERAL_NAME_free: procedure(p: Pointer); cdecl;
  GENERAL_NAMES_free: procedure(p: Pointer); cdecl;
  CERTIFICATEPOLICIES_free: procedure(p: Pointer); cdecl;
  ASN1_OBJECT_free: procedure(p: Pointer); cdecl;
  CRL_DIST_POINTS_free: procedure(p: Pointer); cdecl;
  AUTHORITY_INFO_ACCESS_free: procedure(p: Pointer); cdecl;
  BASIC_CONSTRAINTS_free: procedure(p: Pointer); cdecl;
  ASN1_BIT_STRING_free: procedure(p: Pointer); cdecl;
  DIST_POINT_free: procedure(p: Pointer); cdecl;
  SCT_free: procedure(p: Pointer); cdecl;
  {$ENDREGION}

  {$REGION 'SSL-FUNC'}
  OPENSSL_init_ssl: function(opts: UInt64; settings: Pointer): Integer; cdecl;

  TLS_method: function: PSSL_METHOD; cdecl;
  TLS_client_method: function: PSSL_METHOD; cdecl;
  TLS_server_method: function: PSSL_METHOD; cdecl;

  SSL_CTX_new: function(meth: PSSL_METHOD): PSSL_CTX; cdecl;
  SSL_CTX_free: procedure(ctx: PSSL_CTX); cdecl;
  SSL_CTX_ctrl: function(ctx: PSSL_CTX; Cmd: Integer; LArg: Integer; PArg: MarshaledAString): Integer; cdecl;
  SSL_CTX_set_verify: procedure(ctx: PSSL_CTX; mode: Integer; callback: TSetVerifyCb); cdecl;
  SSL_CTX_set_cipher_list: function(ctx: PSSL_CTX; CipherString: MarshaledAString): Integer; cdecl;
  SSL_CTX_set_ciphersuites: function(ctx: PSSL_CTX; CipherString: MarshaledAString): Integer; cdecl;
  SSL_CTX_use_PrivateKey: function(ctx: PSSL_CTX; pkey: PEVP_PKEY): Integer; cdecl;
  SSL_CTX_use_certificate: function(ctx: PSSL_CTX; cert: PX509): Integer; cdecl;
  SSL_CTX_check_private_key: function(ctx: PSSL_CTX): Integer; cdecl;
  SSL_CTX_get_cert_store: function(const Ctx: PSSL_CTX): PX509_STORE; cdecl;
  SSL_CTX_add_client_CA: function(const Ctx: PSSL_CTX; CaCert: PX509): Integer; cdecl;
  SSL_CTX_set_default_verify_paths: function(const Ctx: PSSL_CTX): Integer; cdecl;

  SSL_new: function(ctx: PSSL_CTX): PSSL; cdecl;
  SSL_set_bio: procedure(s: PSSL; rbio, wbio: PBIO); cdecl;
  SSL_get_error: function(s: PSSL; ret_code: Integer): Integer; cdecl;
  SSL_get_cipher_list: function(s: PSSL; priority: Integer): PAnsiChar; cdecl;
  SSL_get_version: function(s: PSSL): PAnsiChar; cdecl;
  SSL_get_current_cipher: function(s: PSSL): PSSL_CIPHER; cdecl;
  SSL_CIPHER_get_name: function(cipher: PSSL_CIPHER): PAnsiChar; cdecl;
  SSL_CIPHER_get_bits: function(cipher: PSSL_CIPHER; alg_bits: PInteger): Integer; cdecl;
  SSL_get_servername: function(ssl: PSSL; t: Integer): PAnsiChar; cdecl;
  SSL_get0_peer_certificate: function(ssl: PSSL): PX509; cdecl;

  SSL_ctrl: function(ssl: PSSL; Cmd: Integer; LArg: Integer; PArg: Pointer): Integer; cdecl;

  SSL_shutdown: function(ssl: PSSL): Integer; cdecl;
  SSL_free: procedure(s: PSSL); cdecl;

  SSL_set_connect_state: procedure(s: PSSL); cdecl;
  SSL_set_accept_state: procedure(s: PSSL); cdecl;
  SSL_set_fd : function(s: PSSL; fd: Integer): Integer cdecl;
  SSL_accept: function(S: PSSL): Integer; cdecl;
  SSL_connect: function(S: PSSL): Integer; cdecl;
  SSL_do_handshake: function(S: PSSL): Integer; cdecl;
  SSL_read: function(s: PSSL; buf: Pointer; num: Integer): Integer; cdecl;
  SSL_write: function(s: PSSL; const buf: Pointer; num: Integer): Integer; cdecl;
  SSL_pending: function(s: PSSL): Integer; cdecl;
  SSL_is_init_finished: function (s: PSSL): Integer; cdecl;

  {$ENDREGION}

{$ELSE __SSL_STATIC__}

{$REGION 'LIBCRYPTO-FUNC'}
function OpenSSL_version_num: Longword; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OpenSSL_version_num';
function OPENSSL_init_crypto(opts: UInt64; settings: Pointer): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OPENSSL_init_crypto';
procedure OPENSSL_cleanup; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OPENSSL_cleanup';

procedure ERR_error_string_n(err: Cardinal; buf: MarshaledAString; len: size_t); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'ERR_error_string_n';
function ERR_get_error: Cardinal; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'ERR_get_error';

function EVP_PKEY_new(): PEVP_PKEY; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'EVP_PKEY_new';
procedure EVP_PKEY_free(pkey: PEVP_PKEY); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'EVP_PKEY_free';
function EVP_PKEY_get0_RSA(key: PEVP_PKEY): PRSA; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'EVP_PKEY_get0_RSA';
function EVP_PKEY_CTX_new_id(id: Integer; e: Pointer): PEVP_PKEY; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'EVP_PKEY_CTX_new_id';
{$IFDEF __SSL3__}
function EVP_PKEY_get_size(key: PEVP_PKEY): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF};
function EVP_PKEY_get_bits(key: PEVP_PKEY): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF};
function EVP_PKEY_get_id(key: PEVP_PKEY): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF};
function EVP_PKEY_get_security_bits(key: PEVP_PKEY): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF};
{$ELSE}
function EVP_PKEY_size(key: PEVP_PKEY): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF};
function EVP_PKEY_bits(key: PEVP_PKEY): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF};
function EVP_PKEY_id(key: PEVP_PKEY): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF};
function EVP_PKEY_security_bits(key: PEVP_PKEY): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF};

function EVP_PKEY_get_size(key: PEVP_PKEY): Integer; inline;
function EVP_PKEY_get_bits(key: PEVP_PKEY): Integer; inline;
function EVP_PKEY_get_id(key: PEVP_PKEY): Integer; inline;
function EVP_PKEY_get_security_bits(key: PEVP_PKEY): Integer; inline;
{$ENDIF}

function EVP_sha256(): PEVP_MD; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'EVP_sha256';
function EVP_Digest(data: Pointer; count: size_t; md: Pointer; size: PCardinal; t: PEVP_MD; impl: PENGINE): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'EVP_Digest';
function EVP_MD_CTX_new(): PEVP_MD_CTX; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'EVP_Digest';
procedure EVP_MD_CTX_free(ctx: PEVP_MD_CTX); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'EVP_MD_CTX_free';
function EVP_DigestInit_ex(ctx: PEVP_MD_CTX; t: PEVP_MD; impl: PENGINE): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'EVP_DigestInit_ex';
function EVP_DigestUpdate(ctx: PEVP_MD_CTX; d: Pointer; cnt: size_t): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'EVP_DigestUpdate';
function EVP_DigestFinal_ex(ctx: PEVP_MD_CTX; md: Pointer; s: PCardinal): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'EVP_DigestFinal_ex';

function BIO_new(BioMethods: PBIO_METHOD): PBIO; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'BIO_new';
function BIO_ctrl(bp: PBIO; cmd: Integer; larg: Longint; parg: Pointer): Longint; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'BIO_ctrl';
function BIO_new_mem_buf(buf: Pointer; len: Integer): PBIO; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'BIO_new_mem_buf';
function BIO_free(b: PBIO): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'BIO_free';
function BIO_s_mem: PBIO_METHOD; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'BIO_s_mem';
function BIO_read(b: PBIO; Buf: Pointer; Len: Integer): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'BIO_read';
function BIO_write(b: PBIO; Buf: Pointer; Len: Integer): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'BIO_write';

function EC_KEY_new_by_curve_name(nid: Integer): PEC_KEY; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'EC_KEY_new_by_curve_name';
procedure EC_KEY_free(key: PEC_KEY); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'EC_KEY_free';

function X509_get_issuer_name(cert: PX509): PX509_NAME; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_get_issuer_name';
function X509_get_subject_name(cert: PX509): PX509_NAME; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_get_subject_name';
function X509_get_serialNumber(x: PX509): PASN1_INTEGER; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_get_serialNumber';
function X509_get_version(x: PX509): LongInt; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_get_version';
function X509_get_ext_d2i(x: PX509; nid: Integer; crit, idx: PInteger): Pointer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_get_ext_d2i';
function X509_get_signature_nid(x: PX509): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_get_signature_nid';
procedure X509_get0_signature(psig: PPASN1_BIT_STRING; palg: PPX509_ALGOR; x: PX509); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_get0_signature';
function X509_get0_notBefore(x: PX509): PASN1_TIME; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_get0_notBefore';
function X509_get0_notAfter(x: PX509): PASN1_TIME; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_get0_notAfter';
function X509_get0_tbs_sigalg(x: PX509): PX509_ALGOR; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_get0_tbs_sigalg';
function X509_get0_pubkey(x: PX509): PEVP_PKEY; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_get0_pubkey';
function X509_get0_extensions(x: PX509): PX509_EXTENSION; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_get0_extensions';
function X509_get_ext_count(x: PX509): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_get_ext_count';
function X509_get_ext(x: PX509; loc: Integer): PX509_EXTENSION; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_get_ext';
function X509_NAME_print_ex(bout: PBIO; nm: PX509_NAME; indent: Integer; flags: Cardinal): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_NAME_print_ex';
function X509_NAME_get_entry(name: PX509_NAME; loc: Integer): PX509_NAME_ENTRY; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_NAME_get_entry';
function X509_NAME_ENTRY_get_object(ne: PX509_NAME_ENTRY): PASN1_OBJECT; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_NAME_ENTRY_get_object';
function X509_NAME_ENTRY_get_data(ne: PX509_NAME_ENTRY): PASN1_STRING; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_NAME_ENTRY_get_data';
function X509_NAME_entry_count(name: PX509_NAME): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_NAME_entry_count';
function X509_EXTENSION_get_object(ex: PX509_EXTENSION): PASN1_OBJECT; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_EXTENSION_get_object';
function X509_EXTENSION_get_critical(ex: PX509_EXTENSION): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_EXTENSION_get_critical';
function X509_EXTENSION_get_data(ex: PX509_EXTENSION): PASN1_OCTET_STRING; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_EXTENSION_get_data';
function X509V3_EXT_d2i(ex: PX509_EXTENSION): Pointer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509V3_EXT_d2i';
function X509V3_EXT_get(ex: PX509_EXTENSION): PX509V3_EXT_METHOD; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509V3_EXT_get';
function X509_STORE_add_cert(Store: PX509_STORE; Cert: PX509): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_STORE_add_cert';
function X509_digest(data: PX509; t: PEVP_MD; md: Pointer; len: PCardinal): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_digest';
function X509_pubkey_digest(data: PX509; t: PEVP_MD; md: Pointer; len: PCardinal): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_pubkey_digest';
procedure X509_free(cert: PX509); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'X509_free';

function OPENSSL_sk_num(stack: PSTACK): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OPENSSL_sk_num';
function OPENSSL_sk_pop(stack: PSTACK): Pointer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OPENSSL_sk_pop';
function OPENSSL_sk_value(stack: PSTACK; i: Integer): Pointer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OPENSSL_sk_value';
procedure OPENSSL_sk_free(p: PSTACK); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OPENSSL_sk_free';
procedure OPENSSL_sk_pop_free(st: POPENSSL_STACK; func: OPENSSL_sk_freefunc); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OPENSSL_sk_pop_free';

function OPENSSL_hexstr2buf(str: PAnsiString; len: PLongInt): Pointer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OPENSSL_hexstr2buf';
function OPENSSL_buf2hexstr(buf: Pointer; buflen: LongInt): PAnsiChar; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OPENSSL_buf2hexstr';

function PEM_read_bio_X509(bp: PBIO; x: PPX509; cb: TPemPasswordCb; u: Pointer): PX509; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'PEM_read_bio_X509';
function PEM_read_bio_X509_AUX(bp: PBIO; x: PPX509; cb: TPemPasswordCb; u: Pointer): PX509; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'PEM_read_bio_X509_AUX';
function PEM_read_bio_PrivateKey(bp: PBIO; x: PPEVP_PKEY; cb: TPemPasswordCb; u: Pointer): PEVP_PKEY; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'PEM_read_bio_PrivateKey';
function PEM_write_bio_PUBKEY(bp: PBIO; x: PEVP_PKEY): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'PEM_write_bio_PUBKEY';
function PEM_read_bio_PUBKEY(bp: PBIO; x: PPEVP_PKEY; cb: TPemPasswordCb; u: Pointer): PEVP_PKEY; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'PEM_read_bio_PUBKEY';
function PEM_write_bio_X509(bp: PBIO; x: PX509): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'PEM_write_bio_X509';

function OBJ_nid2obj(n: Integer): PASN1_OBJECT; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OBJ_nid2obj';
function OBJ_nid2ln(n: Integer): PAnsiChar; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OBJ_nid2ln';
function OBJ_nid2sn(n: Integer): PAnsiChar; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OBJ_nid2sn';
function OBJ_obj2nid(o: PASN1_OBJECT): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OBJ_obj2nid';
function OBJ_ln2nid(ln: PAnsiChar): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OBJ_ln2nid';
function OBJ_sn2nid(sn: PAnsiChar): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OBJ_sn2nid';
function OBJ_obj2txt(buf: PAnsiChar; buf_len: Integer; a: PASN1_OBJECT; no_name: Integer): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'OBJ_obj2txt';

function CRYPTO_malloc(num: size_t; f: PAnsiChar; l: Integer): Pointer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'CRYPTO_malloc';
procedure CRYPTO_free(str: Pointer; f: PAnsiChar; l: Integer); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'CRYPTO_free';

function ASN1_STRING_to_UTF8(outs: PPAnsiChar; ins: PASN1_STRING): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'ASN1_STRING_to_UTF8';
function ASN1_STRING_length(x: PASN1_STRING): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'ASN1_STRING_length';
function ASN1_STRING_get0_data(x: PASN1_STRING): PAnsiChar; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'ASN1_STRING_get0_data';
function ASN1_TIME_to_tm(t: PASN1_TIME; tm: PTM): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'ASN1_TIME_to_tm';
function ASN1_TIME_print(b: PBIO; tm: PASN1_TIME): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'ASN1_TIME_print';
function ASN1_item_d2i(pval: PPASN1_VALUE; idata: PPointer; len: LongInt; it: PASN1_ITEM): PASN1_VALUE; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'ASN1_item_d2i';
function ASN1_BIT_STRING_set_bit(a: PASN1_BIT_STRING; n, value: Integer): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'ASN1_BIT_STRING_set_bit';
function ASN1_BIT_STRING_get_bit(a: PASN1_BIT_STRING; n: Integer): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'ASN1_BIT_STRING_get_bit';
function ASN1_INTEGER_get(a: PASN1_BIT_STRING): LongInt; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'ASN1_INTEGER_get';
function ASN1_INTEGER_set(a: PASN1_BIT_STRING; v: LongInt): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'ASN1_INTEGER_set';

function ASN1_INTEGER_to_BN(ai: PASN1_INTEGER; bn: PBIGNUM): PBIGNUM; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'ASN1_INTEGER_to_BN';
function BN_to_ASN1_INTEGER(bn: PBIGNUM; ai: PASN1_INTEGER): PASN1_INTEGER; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'BN_to_ASN1_INTEGER';
function BN_bn2hex(bn: PBIGNUM): PAnsiChar; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'BN_bn2hex';

function i2d_PublicKey(a: PEVP_PKEY; pp: PPointer): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'i2d_PublicKey';
function i2d_PUBKEY(a: PEVP_PKEY; pp: PPointer): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'i2d_PublicKey';
function i2d_X509(x: PX509; d: PPointer): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'i2d_X509';
procedure RSA_get0_key(r: PRSA; n, e, d: PPBIGNUM); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'RSA_get0_key';
procedure AUTHORITY_KEYID_free(p: Pointer); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'AUTHORITY_KEYID_free';
procedure ASN1_OCTET_STRING_free(p: Pointer); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'ASN1_OCTET_STRING_free';
procedure GENERAL_NAME_free(p: Pointer); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'GENERAL_NAME_free';
procedure GENERAL_NAMES_free(p: Pointer); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'GENERAL_NAMES_free';
procedure CERTIFICATEPOLICIES_free(p: Pointer); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'CERTIFICATEPOLICIES_free';
procedure ASN1_OBJECT_free(p: Pointer); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'ASN1_OBJECT_free';
procedure CRL_DIST_POINTS_free(p: Pointer); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'CRL_DIST_POINTS_free';
procedure AUTHORITY_INFO_ACCESS_free(p: Pointer); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'AUTHORITY_INFO_ACCESS_free';
procedure BASIC_CONSTRAINTS_free(p: Pointer); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'BASIC_CONSTRAINTS_free';
procedure ASN1_BIT_STRING_free(p: Pointer); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'ASN1_BIT_STRING_free';
procedure DIST_POINT_free(p: Pointer); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'DIST_POINT_free';
procedure SCT_free(p: Pointer); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBCRYPTO_NAME{$ENDIF} name 'SCT_free';
{$ENDREGION}

{$REGION 'LIBSSL-FUNC'}
function OPENSSL_init_ssl(opts: UInt64; settings: Pointer): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'OPENSSL_init_ssl';

function TLS_method: PSSL_METHOD; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'TLS_method';
function TLS_client_method: PSSL_METHOD; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'TLS_client_method';
function TLS_server_method: PSSL_METHOD; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'TLS_server_method';

function SSL_CTX_new(meth: PSSL_METHOD): PSSL_CTX; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_CTX_new';
procedure SSL_CTX_free(ctx: PSSL_CTX); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_CTX_free';
function SSL_CTX_ctrl(ctx: PSSL_CTX; Cmd: Integer; LArg: Integer; PArg: MarshaledAString): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_CTX_ctrl';
procedure SSL_CTX_set_verify(ctx: PSSL_CTX; mode: Integer; callback: TSetVerifyCb); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_CTX_set_verify';
function SSL_CTX_set_cipher_list(ctx: PSSL_CTX; CipherString: MarshaledAString): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_CTX_set_cipher_list';
function SSL_CTX_set_ciphersuites(ctx: PSSL_CTX; CipherString: MarshaledAString): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_CTX_set_ciphersuites';
function SSL_CTX_use_PrivateKey(ctx: PSSL_CTX; pkey: PEVP_PKEY): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_CTX_use_PrivateKey';
function SSL_CTX_use_certificate(ctx: PSSL_CTX; cert: PX509): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_CTX_use_certificate';
function SSL_CTX_check_private_key(ctx: PSSL_CTX): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_CTX_check_private_key';
function SSL_CTX_get_cert_store(const Ctx: PSSL_CTX): PX509_STORE; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_CTX_get_cert_store';
function SSL_CTX_add_client_CA(const Ctx: PSSL_CTX; CaCert: PX509): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_CTX_add_client_CA';
function SSL_CTX_set_default_verify_paths(const Ctx: PSSL_CTX): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_CTX_set_default_verify_paths';

function SSL_new(ctx: PSSL_CTX): PSSL; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_new';
procedure SSL_set_bio(s: PSSL; rbio, wbio: PBIO); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_set_bio';
function SSL_get_error(s: PSSL; ret_code: Integer): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_get_error';
function SSL_get_cipher_list(s: PSSL; priority: Integer): PAnsiChar; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_get_cipher_list';
function SSL_get_version(s: PSSL): PAnsiChar; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_get_version';
function SSL_get_current_cipher(s: PSSL): PSSL_CIPHER; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_get_current_cipher';
function SSL_CIPHER_get_name(cipher: PSSL_CIPHER): PAnsiChar; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_CIPHER_get_name';
function SSL_CIPHER_get_bits(cipher: PSSL_CIPHER; alg_bits: PInteger): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_CIPHER_get_bits';
function SSL_get_servername(s: PSSL; t: Integer): PAnsiChar; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_get_servername';

{$IFDEF __SSL3__}
function SSL_get0_peer_certificate(s: PSSL): PX509; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF};
{$ELSE}
function SSL_get_peer_certificate(s: PSSL): PX509; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF};
function SSL_get0_peer_certificate(s: PSSL): PX509; inline;
{$ENDIF}

function SSL_ctrl(S: PSSL; Cmd: Integer; LArg: Integer; PArg: Pointer): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_ctrl';

function SSL_shutdown(s: PSSL): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_shutdown';
procedure SSL_free(s: PSSL); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_free';

procedure SSL_set_connect_state(s: PSSL); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_set_connect_state';
procedure SSL_set_accept_state(s: PSSL); cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_set_accept_state';
function SSL_set_fd(s: PSSL; fd: Integer): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_set_fd';
function SSL_accept(S: PSSL): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_accept';
function SSL_connect(S: PSSL): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_connect';
function SSL_do_handshake(S: PSSL): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_do_handshake';
function SSL_read(s: PSSL; buf: Pointer; num: Integer): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_read';
function SSL_write(s: PSSL; const buf: Pointer; num: Integer): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_write';
function SSL_pending(s: PSSL): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_pending';
function SSL_is_init_finished(s: PSSL): Integer; cdecl;
  external {$IFDEF __STATIC_WITH_EXTERNAL__}LIBSSL_NAME{$ENDIF} name 'SSL_is_init_finished';
{$ENDREGION}

{$ENDIF __SSL_STATIC__}

function SSL_CTX_need_tmp_rsa(ctx: PSSL_CTX): Integer; inline;
function SSL_CTX_set_tmp_rsa(ctx: PSSL_CTX; rsa: MarshaledAString): Integer; inline;
function SSL_CTX_set_tmp_dh(ctx: PSSL_CTX; dh: MarshaledAString): Integer; inline;
function SSL_CTX_set_tmp_ecdh(ctx: PSSL_CTX; ecdh: PEC_KEY): Integer; inline;
function SSL_CTX_add_extra_chain_cert(ctx: PSSL_CTX; cert: PX509): Integer; inline;
function SSL_CTX_set_options(ctx: PSSL_CTX; Op: Integer): Integer; inline;
function SSL_CTX_get_options(ctx: PSSL_CTX): Integer; inline;
function SSL_CTX_set_mode(ctx: PSSL_CTX; op: Integer): Integer; inline;
function SSL_CTX_clear_mode(ctx: PSSL_CTX; op: Integer): Integer; inline;
function SSL_CTX_get_mode(ctx: PSSL_CTX): Integer; inline;
function SSL_CTX_get_min_proto_version(ctx: PSSL_CTX): Integer; inline;
function SSL_CTX_set_min_proto_version(ctx: PSSL_CTX; version: Integer): Integer; inline;
function SSL_CTX_get_max_proto_version(ctx: PSSL_CTX): Integer; inline;
function SSL_CTX_set_max_proto_version(ctx: PSSL_CTX; version: Integer): Integer; inline;
function SSL_CTX_get_session_cache_mode(ctx: PSSL_CTX): Integer; inline;
function SSL_CTX_set_session_cache_mode(ctx: PSSL_CTX; m: Integer): Integer; inline;

function SSL_need_tmp_rsa(ssl: PSSL): Integer; inline;
function SSL_set_tmp_rsa(ssl: PSSL; rsa: MarshaledAString): Integer; inline;
function SSL_set_tmp_dh(ssl: PSSL; dh: MarshaledAString): Integer; inline;
function SSL_set_tmp_ecdh(ssl: PSSL; ecdh: MarshaledAString): Integer; inline;
function SSL_set_options(ssl: PSSL; Op: Integer): Integer; inline;
function SSL_get_options(ssl: PSSL): Integer; inline;
function SSL_clear_options(ssl: PSSL; Op: Integer): Integer; inline;
function SSL_set_tlsext_host_name(ssl: PSSL; name: MarshaledAString): Integer; inline;
function SSL_get_cipher_name(ssl: PSSL): PAnsiChar; inline;
function SSL_get_cipher_bits(ssl: PSSL): Integer; inline;
function SSL_get_peer_tmp_key(ssl: PSSL; key: PPEVP_PKEY): Integer; inline;

function BIO_eof(bp: PBIO): Boolean; inline;
function BIO_pending(bp: PBIO): Integer; inline;
function BIO_get_mem_data(b: PBIO; pp: PPointer): Integer; inline;
function BIO_get_mem_ptr(b: PBIO; pp: PPBUF_MEM): Integer; inline;
function BIO_get_flags(b: PBIO): Integer; inline;
function BIO_should_retry(b: PBIO): Boolean; inline;

function SSL_is_fatal_error(ssl_error: Integer): Boolean;
function SSL_error_message(ssl_error: Integer): string;
function OPENSSL_malloc(num: Integer): Pointer; inline;
procedure OPENSSL_free(str: Pointer); inline;

type
  ESsl = class(Exception);
  ESslInvalidLib = class(ESsl);
  ESslInvalidProc = class(ESsl);

  // FPC 中 一定要用 TLibHandle 来保存动态库的句柄
  // 否则在部分操作系统中调用 GetProcAddress 时会引发异常
  // 目前测试发现在 Linux-LoongArch64 中会出现该异常
  {$IFDEF DELPHI}
  TLibHandle = THandle;
  {$ENDIF}

  {$REGION 'SSLTools'}

  { TSSLTools }

  TSSLTools = class
  private
    class var FRef: Integer;
    class var FSslVersion: Longword;

    class destructor Destroy;

    class var FLibPath, FLibSSL, FLibCRYPTO: string;
    class var FSslLibHandle, FCryptoLibHandle: TLibHandle;

    class function LoadLib(const ALibName: string): TLibHandle; static;
    class function GetProc(const ALibHandle: TLibHandle;
      const AProcName: string): Pointer; static;

    class function GetSslLibPath: string; static;
    class function GetSslLibProc(const ALibHandle: TLibHandle;
      const AProcNames: array of string): Pointer; overload; static;
    class function GetSslLibProc(const ALibHandle: TLibHandle;
      const AProcName: string): Pointer; overload; static;
    class function LoadSslLib(const ALibNames: array of string): TLibHandle; overload; static;
    class procedure LoadSslLibs; static;
    class procedure UnloadSslLibs; static;

    class procedure SslInit; static;
    class procedure SslUninit; static;
  private
    class procedure SetLibCRYPTO(const AValue: string); static;
    class procedure SetLibPath(const AValue: string); static;
    class procedure SetLibSSL(const AValue: string); static;
  public
    // 加载 SSL 库
    class procedure LoadSSL; static;

    // 卸载 SSL 库
    class procedure UnloadSSL; static;

    // SSL 版本号
    class function SSLVersion: Longword; static;

    // 新建 SSL 上下文对象
    class function NewCTX(AMeth: PSSL_METHOD = nil): PSSL_CTX; static;

    // 释放 SSL 上下文对象
    class procedure FreeCTX(var AContext: PSSL_CTX); static;

    // 加载证书
    class procedure SetCertificate(AContext: PSSL_CTX; ACertBuf: Pointer; ACertBufSize: Integer); overload; static;
    class procedure SetCertificate(AContext: PSSL_CTX; const ACertBytes: TBytes); overload; static;
    class procedure SetCertificate(AContext: PSSL_CTX; const ACertStr: string); overload; static;
    class procedure SetCertificateFile(AContext: PSSL_CTX; const ACertFile: string); static;

    // 加载私钥
    class procedure SetPrivateKey(AContext: PSSL_CTX; APKeyBuf: Pointer; APKeyBufSize: Integer); overload; static;
    class procedure SetPrivateKey(AContext: PSSL_CTX; const APKeyBytes: TBytes); overload; static;
    class procedure SetPrivateKey(AContext: PSSL_CTX; const APKeyStr: string); overload; static;
    class procedure SetPrivateKeyFile(AContext: PSSL_CTX; const APKeyFile: string); static;

    // 从内存bio中读取字符串
    class function GetStrFromMemBIO(ABio: PBIO): string; static;

    // ASN1_TIME转本地时间
    class function ASN1_TIME_ToDateTime(t: PASN1_TIME): TDateTime; static;

    // ASN1_TIME转字符串
    class function ASN1_TIME_ToStr(t: PASN1_TIME): string; static;

    // ASN1_OBJECT转字符串
    class function ASN1_OBJECT_ToStr(o: PASN1_OBJECT; no_name: Integer): string; static;

    // ASN1_STRING转字符串
    class function ASN1_STRING_ToStr(a: PASN1_STRING): string; static;

    // 任意内存数据转字节数组
    class function AnyDataToBytes(AData: Pointer; ADataSize: Integer): TBytes; static;

    // ASN1_INTEGER转字节数组
    class function ASN1_INTEGER_ToBytes(a: PASN1_INTEGER): TBytes; static;

    // PASN1_BIT_STRING转字节数组
    class function ASN1_BIT_STRING_ToBytes(a: PASN1_BIT_STRING): TBytes; static;

    // PASN1_OCTET_STRING转字节数组
    class function ASN1_OCTET_STRING_ToBytes(a: PASN1_OCTET_STRING): TBytes; static;

    // 获取证书内容(二进制DER格式)
    class function GetCertDER(ACert: PX509): TBytes; static;

    // 获取证书内容(文本PEM格式)
    class function GetCertPEM(ACert: PX509): string; static;

    // 获取证书签名
    class function GetCertSignature(ACert: PX509): TBytes; static;

    // 获取证书序列号
    class function GetCertSerialNumber(ACert: PX509): TBytes; static;

    // 获取证书指纹
    class function GetCertDigest(ACert: PX509; AHasher: PEVP_MD): TBytes; static;

    // 获取证书颁发机构密钥ID
    class function GetCertAuthKeyID(ACert: PX509): TBytes; static;

    // 获取证书使用者密钥ID
    class function GetCertSubKeyID(ACert: PX509): TBytes; static;

    // 标准化公钥DER编码
    class function GetNormalizedPubKeyDer(pubkey: PEVP_PKEY; ADer: PPointer): Integer; static;

    // 获取公钥指纹
    class function GetPubKeyDigest(APubKey: PEVP_PKEY; AHasher: PEVP_MD): TBytes; static;

    // 将X509_NAME结构转换为可阅读的文本
    class function X509NameToStr(name: PX509_NAME; AFlags: Cardinal): string; static;

    // 获取加密套件列表
    class function GetCipherList(ASsl: PSSL): TArray<string>; static;

    // 提取X509_NAME结构的详细数据
    // 返回数据格式大致如下:
    // CN=WoTrus DV Server CA  [Run by the Issuer]
    // O=WoTrus CA Limited
    // C=CN
    // 含义:
    //   CN=xxx 证书颁发机构,         CN是"Common Name"的缩写
    //   O=xxx  证书颁发者的企业身份, O是"Organization"的缩写
    //   C=xx   两个字母的国家缩写,   C是"Country"的缩写
    class function GetX509NameEntryDataList(AX509Name: PX509_NAME): TArray<TEntryData>; static;

    // 解析GENERAL_NAMES数据
    class function GetGeneralName(AName: PGENERAL_NAME; var AGeneralName: TGeneralName): Boolean; static;

    // GENERAL_NAMES转成数组
    class function GetGeneralNames(ANames: PGENERAL_NAMES): TArray<TGeneralName>; static;

    // 获取单条授权信息访问数据
    class function GetAuthorityInfoAccess(AAccessDesc: PACCESS_DESCRIPTION; var AAuthInfo: TAuthorityInfoAccess): Boolean; static;

    // 获取授权信息访问数组
    class function GetAuthorityInfoAccesses(AAuthInfoAccess: PAUTHORITY_INFO_ACCESS): TArray<TAuthorityInfoAccess>; static;

    // 获取扩展原始数据
    class function GetExtensionRawData(AExtItem: PX509_EXTENSION; var AExtData: TExtensionRawData): Boolean; static;

    // 获取证书扩展信息原始数据
    class function GetCertRawExtensions(ACert: PX509): TArray<TExtensionRawData>; static;

    // 获取证书使用者可选名称
    class function GetCertAltNames(ACert: PX509): TArray<TGeneralName>; static;

    // 获取证书授权信息访问
    class function GetCertAuthorityInfoAccesses(ACert: PX509): TArray<TAuthorityInfoAccess>; static;

    // 获取证书基本约束
    class function GetCertBasicConstraints(ACert: PX509; var ABasicConstraints: TBasicConstraints): Boolean; static;

    // 获取分发点数据
    class function GetDistPoint(ADpItem: PDIST_POINT; var ADistPoint: TCrlDistPoint): Boolean; static;

    // 获取证书CRL分发点
    class function GetCertCrlDistPoints(ACert: PX509): TArray<TCrlDistPoint>; static;

    // 获取策略限定符
    class function GetQualifiers(APolicy: PPOLICYINFO): TArray<TQualifier>; static;

    // 获取签名证书时间戳数据
    class function GetSct(ASctItem: PSCT; var ASct: TSct): Boolean; static;

    // 获取签名证书时间戳列表
    class function GetSctList(ASctList: Pointer): TArray<TSct>; static;

    // 获取证书策略
    class function GetCertPolicies(ACert: PX509): TArray<TPolicie>; static;

    // 获取证书密钥用法
    class function GetCertKeyUsage(ACert: PX509): Cardinal; static;

    // 获取证书扩展密钥用法
    class function GetCertExtKeyUsage(ACert: PX509; var AExtKeyUsage: TExtKeyUsage): Boolean; static;

    // 获取签名证书时间戳列表
    class function GetCertSctList(ACert: PX509): TArray<TSct>; static;

    // 获取证书扩展信息
    class function GetCertExtInfo(ACert: PX509; var AExtInfo: TExtensionInfo): Boolean; static;

    // 获取证书信息
    class function GetCertInfo(ACert: PX509; var ACertInfo: TCertInfo): Boolean; static;

    // 获取SSL信息
    class function GetSslInfo(ASsl: PSSL; var ASslInfo: TSslInfo): Boolean; static;

    // 手动指定 ssl 库路径
    class property LibPath: string read FLibPath write SetLibPath;

    // 手动指定 libssl 库名称
    class property LibSSL: string read FLibSSL write SetLibSSL;

    // 手动指定 libcrypto 库名称
    class property LibCRYPTO: string read FLibCRYPTO write SetLibCRYPTO;
  end;
  {$ENDREGION}

implementation

{$IF DEFINED(__SSL_STATIC__) AND NOT DEFINED(__SSL3__)}
function EVP_PKEY_get_size(key: PEVP_PKEY): Integer;
begin
  Result := EVP_PKEY_size(key);
end;

function EVP_PKEY_get_bits(key: PEVP_PKEY): Integer;
begin
  Result := EVP_PKEY_bits(key);
end;

function EVP_PKEY_get_id(key: PEVP_PKEY): Integer;
begin
  Result := EVP_PKEY_id(key);
end;

function EVP_PKEY_get_security_bits(key: PEVP_PKEY): Integer;
begin
  Result := EVP_PKEY_security_bits(key);
end;

function SSL_get0_peer_certificate(s: PSSL): PX509;
begin
  Result := SSL_get_peer_certificate(s);
end;
{$ENDIF}

function SSL_CTX_need_tmp_rsa(ctx: PSSL_CTX): Integer;
begin
  Result := SSL_CTX_ctrl(ctx, SSL_CTRL_NEED_TMP_RSA, 0, nil);
end;

function SSL_CTX_set_tmp_rsa(ctx: PSSL_CTX; rsa: MarshaledAString): Integer;
begin
  Result := SSL_CTX_ctrl(ctx, SSL_CTRL_SET_TMP_RSA, 0, rsa);
end;

function SSL_CTX_set_tmp_dh(ctx: PSSL_CTX; dh: MarshaledAString): Integer;
begin
  Result := SSL_CTX_ctrl(ctx, SSL_CTRL_SET_TMP_DH, 0, dh);
end;

function SSL_CTX_set_tmp_ecdh(ctx: PSSL_CTX; ecdh: PEC_KEY): Integer;
begin
  Result := SSL_CTX_ctrl(ctx, SSL_CTRL_SET_TMP_ECDH, 0, MarshaledAString(ecdh));
end;

function SSL_CTX_add_extra_chain_cert(ctx: PSSL_CTX; cert: PX509): Integer;
begin
  Result := SSL_CTX_ctrl(ctx, SSL_CTRL_EXTRA_CHAIN_CERT, 0, MarshaledAString(cert));
end;

function SSL_need_tmp_rsa(ssl: PSSL): Integer;
begin
  Result := SSL_ctrl(ssl, SSL_CTRL_NEED_TMP_RSA, 0, nil);
end;

function SSL_set_tmp_rsa(ssl: PSSL; rsa: MarshaledAString): Integer;
begin
  Result := SSL_ctrl(ssl, SSL_CTRL_SET_TMP_RSA, 0, rsa);
end;

function SSL_set_tmp_dh(ssl: PSSL; dh: MarshaledAString): Integer;
begin
  Result := SSL_ctrl(ssl, SSL_CTRL_SET_TMP_DH, 0, dh);
end;

function SSL_set_tmp_ecdh(ssl: PSSL; ecdh: MarshaledAString): Integer;
begin
  Result := SSL_ctrl(ssl, SSL_CTRL_SET_TMP_ECDH, 0, ecdh);
end;

function  SSL_CTX_set_options(ctx: PSSL_CTX; Op: Integer): Integer;
begin
  Result := SSL_CTX_ctrl(ctx, SSL_CTRL_OPTIONS, Op, nil);
end;

function SSL_CTX_get_options(ctx: PSSL_CTX): Integer;
begin
  Result := SSL_CTX_ctrl(ctx, SSL_CTRL_OPTIONS, 0, nil);
end;

function SSL_CTX_set_mode(ctx: PSSL_CTX; op: Integer): Integer;
begin
  Result := SSL_CTX_ctrl(ctx, SSL_CTRL_MODE, op, nil);
end;

function SSL_CTX_clear_mode(ctx: PSSL_CTX; op: Integer): Integer;
begin
  Result := SSL_CTX_ctrl(ctx, SSL_CTRL_CLEAR_MODE, op, nil);
end;

function SSL_CTX_get_mode(ctx: PSSL_CTX): Integer;
begin
  Result := SSL_CTX_ctrl(ctx, SSL_CTRL_MODE, 0, nil);
end;

function SSL_CTX_get_min_proto_version(ctx: PSSL_CTX): Integer;
begin
  Result := SSL_CTX_ctrl(ctx, SSL_CTRL_GET_MIN_PROTO_VERSION, 0, nil);
end;

function SSL_CTX_set_min_proto_version(ctx: PSSL_CTX; version: Integer): Integer;
begin
  Result := SSL_CTX_ctrl(ctx, SSL_CTRL_SET_MIN_PROTO_VERSION, version, nil);
end;

function SSL_CTX_get_max_proto_version(ctx: PSSL_CTX): Integer;
begin
  Result := SSL_CTX_ctrl(ctx, SSL_CTRL_GET_MAX_PROTO_VERSION, 0, nil);
end;

function SSL_CTX_set_max_proto_version(ctx: PSSL_CTX; version: Integer): Integer;
begin
  Result := SSL_CTX_ctrl(ctx, SSL_CTRL_SET_MAX_PROTO_VERSION, version, nil);
end;

function SSL_CTX_get_session_cache_mode(ctx: PSSL_CTX): Integer;
begin
  Result := SSL_CTX_ctrl(ctx, SSL_CTRL_GET_SESS_CACHE_MODE, 0, nil);
end;

function SSL_CTX_set_session_cache_mode(ctx: PSSL_CTX; m: Integer): Integer;
begin
  Result := SSL_CTX_ctrl(ctx, SSL_CTRL_SET_SESS_CACHE_MODE, m, nil);
end;

function SSL_set_options(ssl: PSSL; Op: Integer): Integer;
begin
  Result := SSL_ctrl(ssl, SSL_CTRL_OPTIONS, Op, nil);
end;

function SSL_get_options(ssl: PSSL): Integer;
begin
  Result := SSL_ctrl(ssl, SSL_CTRL_OPTIONS, 0, nil);
end;

function SSL_clear_options(ssl: PSSL; Op: Integer): Integer;
begin
  Result := SSL_ctrl(ssl, SSL_CTRL_CLEAR_OPTIONS, Op, nil);
end;

function SSL_set_tlsext_host_name(ssl: PSSL; name: MarshaledAString): Integer;
begin
  Result := SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, name);
end;

function SSL_get_cipher_name(ssl: PSSL): PAnsiChar;
begin
  Result := SSL_CIPHER_get_name(SSL_get_current_cipher(ssl));
end;

function SSL_get_cipher_bits(ssl: PSSL): Integer;
begin
  Result := SSL_CIPHER_get_bits(SSL_get_current_cipher(ssl), nil);
end;

function SSL_get_peer_tmp_key(ssl: PSSL; key: PPEVP_PKEY): Integer;
begin
  Result := SSL_ctrl(ssl, SSL_CTRL_GET_PEER_TMP_KEY, 0, key);
end;

function BIO_eof(bp: PBIO): Boolean;
begin
  Result := (BIO_ctrl(bp, BIO_CTRL_EOF, 0, nil) <> 0);
end;

function BIO_pending(bp: PBIO): Integer;
begin
  Result := BIO_ctrl(bp, BIO_CTRL_PENDING, 0, nil);
end;

function BIO_get_mem_data(b: PBIO; pp: PPointer): Integer;
begin
  Result := BIO_ctrl(b, BIO_CTRL_INFO, 0, pp);
end;

function BIO_get_mem_ptr(b: PBIO; pp: PPBUF_MEM): Integer;
begin
  Result := BIO_ctrl(b, BIO_C_GET_BUF_MEM_PTR, 0, pp);
end;

function BIO_get_flags(b: PBIO): Integer;
begin
  // This is a hack : BIO structure has not been defined. But I know
  // flags member is the 6th field in the structure (index is 5)
  // This could change when OpenSSL is updated. Check "struct bio_st".
  Result := PInteger(MarshaledAString(b) + 3 * SizeOf(Pointer) + 2 * SizeOf(Integer))^;
end;

function BIO_should_retry(b: PBIO): Boolean;
begin
  Result := ((BIO_get_flags(b) and BIO_FLAGS_SHOULD_RETRY) <> 0);
end;

function SSL_is_fatal_error(ssl_error: Integer): Boolean;
begin
	case ssl_error of
		SSL_ERROR_NONE,
		SSL_ERROR_WANT_READ,
		SSL_ERROR_WANT_WRITE,
		SSL_ERROR_WANT_CONNECT,
		SSL_ERROR_WANT_ACCEPT: Result := False;
  else
    Result := True;
	end;
end;

function SSL_error_message(ssl_error: Integer): string;
var
  LPtr: TPtrWrapper;
begin
  LPtr := TMarshal.AllocMem(1024);
  try
    ERR_error_string_n(ssl_error, LPtr.ToPointer, 1024);
    Result := TMarshal.ReadStringAsAnsi(LPtr);
  finally
    TMarshal.FreeMem(LPtr);
  end;
end;

function OPENSSL_malloc(num: Integer): Pointer;
begin
  Result := CRYPTO_malloc(num, '', 0);
end;

procedure OPENSSL_free(str: Pointer);
begin
  CRYPTO_free(str, '', 0);
end;

{ TSSLTools }

class function TSSLTools.NewCTX(AMeth: PSSL_METHOD): PSSL_CTX;
begin
  if (AMeth = nil) then
    AMeth := TLS_method();
  Result := SSL_CTX_new(AMeth);
end;

class function TSSLTools.ASN1_OCTET_STRING_ToBytes(
  a: PASN1_OCTET_STRING): TBytes;
begin
  if (a = nil) then Exit(nil);

  Result := AnyDataToBytes(a.data, a.length);
end;

class function TSSLTools.ASN1_STRING_ToStr(a: PASN1_STRING): string;
var
  N: Integer;
  LTemp: PAnsiChar;
begin
  Result := '';
  if (a = nil) then Exit;
  
  N := ASN1_STRING_to_UTF8(@LTemp, a);
  if (N <= 0) or (LTemp = nil) then Exit;

  Result := UTF8ToString(LTemp);
  OPENSSL_free(LTemp);
end;

class function TSSLTools.SSLVersion: Longword;
begin
  Result := FSslVersion;
end;

class function TSSLTools.AnyDataToBytes(AData: Pointer;
  ADataSize: Integer): TBytes;
begin
  if (AData = nil) or (ADataSize <= 0) then Exit(nil);

  SetLength(Result, ADataSize);
  Move(AData^, Result[0], ADataSize);
end;

class function TSSLTools.ASN1_BIT_STRING_ToBytes(a: PASN1_BIT_STRING): TBytes;
begin
  if (a = nil) then Exit(nil);

  Result := AnyDataToBytes(a.data, a.length);
end;

class function TSSLTools.ASN1_INTEGER_ToBytes(a: PASN1_INTEGER): TBytes;
begin
  if (a = nil) then Exit(nil);

  Result := AnyDataToBytes(a.data, a.length);
end;

class function TSSLTools.ASN1_OBJECT_ToStr(o: PASN1_OBJECT; no_name: Integer): string;
var
  LBuf: AnsiString;
  LLen: Integer;
begin
  Result := '';
  if (o = nil) then Exit;

  SetLength(LBuf, 256);

  LLen := OBJ_obj2txt(Pointer(LBuf), Length(LBuf), o, no_name);
  if (LLen <= 0) then Exit;

  SetLength(LBuf, LLen);
  Result := UTF8ToString(LBuf);
end;

class function TSSLTools.ASN1_TIME_ToDateTime(t: PASN1_TIME): TDateTime;
var
  LTm: TTM;
begin
  if (t <> nil) then
  begin
    ASN1_TIME_to_tm(t, @LTm);
    Result := TDateTime.Create(
      LTm.tm_year + 1900,
      LTm.tm_mon + 1,
      LTm.tm_mday,
      LTm.tm_hour,
      LTm.tm_min,
      LTm.tm_sec,
      0).ToLocalTime;
  end else
    Result := 0;
end;

class function TSSLTools.ASN1_TIME_ToStr(t: PASN1_TIME): string;
var
  LBio: PBIO;
begin
  Result := '';
  if (t = nil) then Exit;

  LBio := BIO_new(BIO_s_mem());
  if (LBio = nil) then Exit;

  ASN1_TIME_print(LBio, t);
  Result := GetStrFromMemBIO(LBio);

  BIO_free(LBio);
end;

class destructor TSSLTools.Destroy;
begin
  if (@OPENSSL_cleanup <> nil) then
    OPENSSL_cleanup();
end;

class procedure TSSLTools.FreeCTX(var AContext: PSSL_CTX);
begin
  SSL_CTX_free(AContext);
  AContext := nil;
end;

class procedure TSSLTools.LoadSSL;
begin
  if (AtomicIncrement(FRef) <> 1) then Exit;

  {$IFNDEF __SSL_STATIC__}
  LoadSslLibs;
  {$ENDIF}

  SslInit;
end;

class procedure TSSLTools.UnloadSSL;
begin
  if (AtomicDecrement(FRef) <> 0) then Exit;

  SslUninit;

  {$IFNDEF __SSL_STATIC__}
  UnloadSslLibs;
  {$ENDIF}
end;

class procedure TSSLTools.SetCertificate(AContext: PSSL_CTX; ACertBuf: Pointer;
  ACertBufSize: Integer);
var
  LBIOCert: PBIO;
  LSSLCert: PX509;
  LStore: PX509_STORE;
begin
	LBIOCert := BIO_new_mem_buf(ACertBuf, ACertBufSize);
  if (LBIOCert = nil) then
    raise ESsl.Create('Failed to allocate certificate cache.');

	LSSLCert := PEM_read_bio_X509_AUX(LBIOCert, nil, nil, nil);
  if (LSSLCert = nil) then
    raise ESsl.Create('Failed to read certificate data.');

	if (SSL_CTX_use_certificate(AContext, LSSLCert) <= 0) then
    raise ESsl.Create('Failed to use certificate.');

	X509_free(LSSLCert);

  LStore := SSL_CTX_get_cert_store(AContext);
  if (LStore = nil) then
    raise ESsl.Create('Failed to retrieve certificate store.');

  // 将证书链中剩余的证书添加到仓库中
  // 有完整证书链在 ssllabs.com 评分中才能评为 A
  while not BIO_eof(LBIOCert) do
  begin
  	LSSLCert := PEM_read_bio_X509(LBIOCert, nil, nil, nil);
    if (LSSLCert = nil) then
      raise ESsl.Create('Failed to read certificate data.');

    if (X509_STORE_add_cert(LStore, LSSLCert) <= 0) then
      raise ESsl.Create('Failed to add certificate to the store.');

  	X509_free(LSSLCert);
  end;

	BIO_free(LBIOCert);
end;

class procedure TSSLTools.SetCertificate(AContext: PSSL_CTX;
  const ACertBytes: TBytes);
begin
  SetCertificate(AContext, Pointer(ACertBytes), Length(ACertBytes));
end;

class procedure TSSLTools.SetCertificate(AContext: PSSL_CTX;
  const ACertStr: string);
begin
  SetCertificate(AContext, TEncoding.ANSI.GetBytes(ACertStr));
end;

class procedure TSSLTools.SetCertificateFile(AContext: PSSL_CTX;
  const ACertFile: string);
begin
  SetCertificate(AContext, TFileUtils.ReadAllBytes(ACertFile));
end;

class procedure TSSLTools.SetPrivateKey(AContext: PSSL_CTX; APKeyBuf: Pointer;
  APKeyBufSize: Integer);
var
  LBIOKey: PBIO;
  LSSLPKey: PEVP_PKEY;
begin
	LBIOKey := BIO_new_mem_buf(APKeyBuf, APKeyBufSize);
  if (LBIOKey = nil) then
    raise ESsl.Create('Failed to allocate private key cache.');

	LSSLPKey := PEM_read_bio_PrivateKey(LBIOKey, nil, nil, nil);
  if (LSSLPKey = nil) then
    raise ESsl.Create('Failed to read private key data.');

	if (SSL_CTX_use_PrivateKey(AContext, LSSLPKey) <= 0) then
    raise ESsl.Create('Failed to use private key.');

	EVP_PKEY_free(LSSLPKey);
	BIO_free(LBIOKey);

  if (SSL_CTX_check_private_key(AContext) <= 0) then
    raise ESsl.Create('Private key does not match the public key of the certificate.');
end;

class procedure TSSLTools.SetPrivateKey(AContext: PSSL_CTX;
  const APKeyBytes: TBytes);
begin
  SetPrivateKey(AContext, Pointer(APKeyBytes), Length(APKeyBytes));
end;

class procedure TSSLTools.SetPrivateKey(AContext: PSSL_CTX;
  const APKeyStr: string);
begin
  SetPrivateKey(AContext, TEncoding.ANSI.GetBytes(APKeyStr));
end;

class procedure TSSLTools.SetPrivateKeyFile(AContext: PSSL_CTX;
  const APKeyFile: string);
begin
  SetPrivateKey(AContext, TFileUtils.ReadAllBytes(APKeyFile));
end;

class procedure TSSLTools.SslInit;
begin
  {$IFNDEF __SSL_STATIC__}
  if (FSslLibHandle = 0) or (FCryptoLibHandle = 0) then Exit;
  {$ENDIF}

  // 初始化 OpenSSL 库的 SSL/TLS 部分
  OPENSSL_init_ssl(
    OPENSSL_INIT_LOAD_SSL_STRINGS,
    nil);

  // 初始化 OpenSSL 的加密和密码学库
  OPENSSL_init_crypto(
    OPENSSL_INIT_LOAD_CRYPTO_STRINGS or
    OPENSSL_INIT_ADD_ALL_CIPHERS or
    OPENSSL_INIT_ADD_ALL_DIGESTS,
    nil);

  // 获取 OpenSSL 版本号
  FSslVersion := OpenSSL_version_num();
end;

class procedure TSSLTools.SslUninit;
begin
  {$IFNDEF __SSL_STATIC__}
  if (FSslLibHandle = 0) or (FCryptoLibHandle = 0) then Exit;
  {$ENDIF}

  // 回收资源
  // openssl 1.1.0及更高版本不再需要显示调用OPENSSL_cleanup()释放资源
  // 在ssl库被卸载时资源会自动回收
  // 在这里显示调用反倒会引起再次执行 OPENSSL_init_ssl() 和 OPENSSL_init_crypto() 失败
//  OPENSSL_cleanup();
end;

class function TSSLTools.GetCertAltNames(ACert: PX509): TArray<TGeneralName>;
var
  LAltNames: PGENERAL_NAMES;
begin
  Result := nil;
  if (ACert = nil) then Exit;
  
  LAltNames := X509_get_ext_d2i(ACert, NID_subject_alt_name, nil, nil);
  if (LAltNames = nil) then Exit;

  try
    Result := GetGeneralNames(LAltNames);
  finally
    OPENSSL_sk_pop_free(LAltNames, GENERAL_NAME_free);
  end;
end;

class function TSSLTools.GetCertAuthKeyID(ACert: PX509): TBytes;
var
  LAuthKeyID: PAUTHORITY_KEYID;
begin
  Result := nil;
  if (ACert = nil) then Exit;
  
  LAuthKeyID := X509_get_ext_d2i(ACert, NID_authority_key_identifier, nil, nil);
  if (LAuthKeyID = nil) then Exit;

  Result := ASN1_OCTET_STRING_ToBytes(LAuthKeyID.keyid);
  AUTHORITY_KEYID_free(LAuthKeyID);
end;

class function TSSLTools.GetCertAuthorityInfoAccesses(
  ACert: PX509): TArray<TAuthorityInfoAccess>;
var
  LAuthInfo: PAUTHORITY_INFO_ACCESS;
begin
  Result := nil;
  if (ACert = nil) then Exit;

  LAuthInfo := X509_get_ext_d2i(ACert, NID_info_access, nil, nil);
  if (LAuthInfo = nil) then Exit;

  try
    Result := GetAuthorityInfoAccesses(LAuthInfo);
  finally
    // 不能用 OPENSSL_sk_pop_free(LAuthInfo, AUTHORITY_INFO_ACCESS_free) 释放
    // 否则会触发异常, 同样是堆栈结构, NID_info_access的数据却不能用堆栈释放函数,
    // 搞不懂为什么 openssl 内部要这么设计, 和其它堆栈结构的释放方式搞得不一样了
    // 很让人迷惑
    AUTHORITY_INFO_ACCESS_free(LAuthInfo);
  end;
end;

class function TSSLTools.GetCertBasicConstraints(ACert: PX509;
  var ABasicConstraints: TBasicConstraints): Boolean;
var
  LBasicConstraints: PBASIC_CONSTRAINTS;
begin
  Result := False;
  FillChar(ABasicConstraints, SizeOf(TBasicConstraints), 0);
  if (ACert = nil) then Exit;

  LBasicConstraints := X509_get_ext_d2i(ACert, NID_basic_constraints, nil, nil);
  if (LBasicConstraints = nil) then Exit;

  try
    ABasicConstraints.CA := LBasicConstraints.ca;
    if (LBasicConstraints.pathlen <> nil) then
      ABasicConstraints.PathLen := ASN1_INTEGER_get(LBasicConstraints.pathlen);

    Result := True;
  finally
    BASIC_CONSTRAINTS_free(LBasicConstraints);
  end;
end;

class function TSSLTools.GetCertCrlDistPoints(
  ACert: PX509): TArray<TCrlDistPoint>;
var
  LCrlDistPoints: Pointer;
  I, N: Integer;
begin
  Result := nil;
  if (ACert = nil) then Exit;

  LCrlDistPoints := X509_get_ext_d2i(ACert, NID_crl_distribution_points, nil, nil);
  if (LCrlDistPoints = nil) then Exit;

  try
    N := OPENSSL_sk_num(LCrlDistPoints);
    if (N <= 0) then Exit;

    SetLength(Result, N);
    for I := 0 to N - 1 do
      GetDistPoint(OPENSSL_sk_value(LCrlDistPoints, I), Result[I]);
  finally
    OPENSSL_sk_pop_free(LCrlDistPoints, DIST_POINT_free);
  end;
end;

class function TSSLTools.GetCertDER(ACert: PX509): TBytes;
var
  LTemp: Pointer;
  LCount: Integer;
begin
  LTemp := nil;
  LCount := i2d_X509(ACert, @LTemp);
  if (LCount > 0) then
    Result := AnyDataToBytes(LTemp, LCount)
  else
    Result := nil;
end;

class function TSSLTools.GetCertDigest(ACert: PX509; AHasher: PEVP_MD): TBytes;
var
 LDigestLen: Cardinal;
begin
  Result := nil;
  if (ACert = nil) or (AHasher = nil) then Exit;

  SetLength(Result, EVP_MAX_MD_SIZE);
  LDigestLen := 0;
  if (X509_digest(ACert, AHasher, @Result[0], @LDigestLen) = 1) then
    SetLength(Result, LDigestLen)
  else
    Result := nil;
end;

class function TSSLTools.GetCertExtInfo(ACert: PX509;
  var AExtInfo: TExtensionInfo): Boolean;
begin
  Result := False;
  FillChar(AExtInfo, SizeOf(TExtensionInfo), 0);
  if (ACert = nil) then Exit;

  // 原始数据
  AExtInfo.RawData := GetCertRawExtensions(ACert);

  // 证书颁发机构密钥ID
  AExtInfo.AuthorityKeyID := GetCertAuthKeyID(ACert);

  // 证书使用者密钥ID
  AExtInfo.SubjectKeyID := GetCertSubKeyID(ACert);

  // 证书使用者可选名称
  AExtInfo.AltNames := GetCertAltNames(ACert);

  // CRL分发点
  AExtInfo.CrlDistPoints := GetCertCrlDistPoints(ACert);

  // 证书策略
  AExtInfo.Policies := GetCertPolicies(ACert);

  // 授权信息访问
  AExtInfo.AuthorityInfoAccesses := GetCertAuthorityInfoAccesses(ACert);

  // 证书基本约束
  GetCertBasicConstraints(ACert, AExtInfo.BasicConstraints);

  // 证书密钥用法
  AExtInfo.KeyUsage := GetCertKeyUsage(ACert);

  // 扩展密钥用法
  GetCertExtKeyUsage(ACert, AExtInfo.ExtKeyUsage);

  // 签名证书时间戳列表
  AExtInfo.SctList := GetCertSctList(ACert);

  Result := True;
end;

class function TSSLTools.GetCertExtKeyUsage(ACert: PX509;
  var AExtKeyUsage: TExtKeyUsage): Boolean;
var
  LExtKeyUsage: Pointer;
  I, N: Integer;
  LObj: PASN1_OBJECT;
begin
  Result := False;
  FillChar(AExtKeyUsage, SizeOf(TExtKeyUsage), 0);
  if (ACert = nil) then Exit;

  LExtKeyUsage := X509_get_ext_d2i(ACert, NID_ext_key_usage, nil, nil);
  if (LExtKeyUsage = nil) then Exit;

  try
    N := OPENSSL_sk_num(LExtKeyUsage);
    if (N <= 0) then Exit;

    SetLength(AExtKeyUsage.List, N);
    for I := 0 to N - 1 do
    begin
      FillChar(AExtKeyUsage.List[I], SizeOf(TExtKeyUsageItem), 0);

      LObj := OPENSSL_sk_value(LExtKeyUsage, I);
      if (LObj = nil) then Continue;

      AExtKeyUsage.List[I].NID := OBJ_obj2nid(LObj);
      AExtKeyUsage.List[I].OID := ASN1_OBJECT_ToStr(LObj, 0);
      AExtKeyUsage.List[I].Value := ASN1_OBJECT_ToStr(LObj, 1);

      case AExtKeyUsage.List[I].NID of
        NID_server_auth:        AExtKeyUsage.Flags := AExtKeyUsage.Flags or XKU_SSL_SERVER;
        NID_client_auth:        AExtKeyUsage.Flags := AExtKeyUsage.Flags or XKU_SSL_CLIENT;
        NID_email_protect:      AExtKeyUsage.Flags := AExtKeyUsage.Flags or XKU_SMIME;
        NID_code_sign:          AExtKeyUsage.Flags := AExtKeyUsage.Flags or XKU_CODE_SIGN;
        NID_ms_sgc, NID_ns_sgc: AExtKeyUsage.Flags := AExtKeyUsage.Flags or XKU_SGC;
        NID_OCSP_sign:          AExtKeyUsage.Flags := AExtKeyUsage.Flags or XKU_OCSP_SIGN;
        NID_time_stamp:         AExtKeyUsage.Flags := AExtKeyUsage.Flags or XKU_TIMESTAMP;
        NID_dvcs:               AExtKeyUsage.Flags := AExtKeyUsage.Flags or XKU_DVCS;
        NID_anyExtendedKeyUsage:AExtKeyUsage.Flags := AExtKeyUsage.Flags or XKU_ANYEKU;
      end;
    end;
  finally
    OPENSSL_sk_pop_free(LExtKeyUsage, ASN1_OBJECT_free);
  end;

  Result := True;
end;

class function TSSLTools.GetCertInfo(ACert: PX509;
  var ACertInfo: TCertInfo): Boolean;
var
  LPubKey: PEVP_PKEY;
  LRSA: PRSA;
  n, e, d: PBIGNUM;
begin
  Result := False;
  FillChar(ACertInfo, SizeOf(TCertInfo), 0);

  if (ACert = nil) then Exit;

  // 证书版本号
  ACertInfo.Version := X509_get_version(ACert);

  // 证书内容(二进制DER格式)
  ACertInfo.DER := GetCertDER(ACert);
  // 证书内容(文本PEM格式)
  ACertInfo.PEM := GetCertPEM(ACert);

  // 证书主题信息
  ACertInfo.Subject := GetX509NameEntryDataList(X509_get_subject_name(ACert));
  // 证书颁发者信息
  ACertInfo.Issuer := GetX509NameEntryDataList(X509_get_issuer_name(ACert));
  // 证书扩展信息
  GetCertExtInfo(ACert, ACertInfo.Extension);
  // 颁发时间
  ACertInfo.NotBefore := ASN1_TIME_ToDateTime(X509_get0_notBefore(ACert));
  // 截止时间
  ACertInfo.NotAfter := ASN1_TIME_ToDateTime(X509_get0_notAfter(ACert));

  // 证书序列号
  ACertInfo.SerialNumber := GetCertSerialNumber(ACert);

  // 签名算法ID(668=RSA-SHA256)
  ACertInfo.SigAlgID := X509_get_signature_nid(ACert);

  // 签名算法(RSA-SHA256)
  ACertInfo.SigAlg := UTF8ToString(OBJ_nid2sn(ACertInfo.SigAlgID));

  // 证书签名
  ACertInfo.Signature := GetCertSignature(ACert);

  // 证书SHA256指纹
  ACertInfo.SHA256Digest := GetCertDigest(ACert, EVP_sha256());

  // 公钥
  LPubKey := X509_get0_pubkey(ACert);
  if (LPubKey <> nil) then
  begin
    // 公钥SHA256指纹
    ACertInfo.PubKeySHA256Digest := GetPubKeyDigest(LPubKey, EVP_sha256());
    // 公钥ID(6=NID_rsaEncryption)
    ACertInfo.PubKeyID := EVP_PKEY_get_id(LPubKey);
    // 公钥类型(rsaEncryption)
    ACertInfo.PubKeyType := UTF8ToString(OBJ_nid2sn(ACertInfo.PubKeyID));
    // 公钥密码位数(2048)
    ACertInfo.PubKeyBits := EVP_PKEY_get_bits(LPubKey);
    // 公钥安全位数(112)
    ACertInfo.PubKeySecurityBits := EVP_PKEY_get_security_bits(LPubKey);
    // 公钥输出缓冲区字节数(256)
    ACertInfo.PubKeyOutSize := EVP_PKEY_get_size(LPubKey);

    // 获取RSA结构
    LRSA := EVP_PKEY_get0_RSA(LPubKey);
    if (LRSA <> nil) then
    begin
      // 获取模数和指数
      RSA_get0_key(LRSA, @n, @e, @d);
      // 公钥模数(256字节)
      ACertInfo.PubKeyModulus := ASN1_INTEGER_ToBytes(BN_to_ASN1_INTEGER(n, nil));
      // 公钥公开指数(3字节)
      ACertInfo.PubKeyExponent := ASN1_INTEGER_ToBytes(BN_to_ASN1_INTEGER(e, nil));
    end;
  end;

  Result := True;
end;

class function TSSLTools.GetCertKeyUsage(ACert: PX509): Cardinal;
var
  LKeyUsage: PASN1_BIT_STRING;
begin
  Result := 0;
  if (ACert = nil) then Exit;
  
  LKeyUsage := X509_get_ext_d2i(ACert, NID_ext_key_usage, nil, nil);
  if (LKeyUsage = nil) or (LKeyUsage.data = nil) then Exit;

  Move(LKeyUsage.data^, Result, Min(LKeyUsage.length, SizeOf(Cardinal)));

  ASN1_BIT_STRING_free(LKeyUsage);
end;

class function TSSLTools.GetCertPEM(ACert: PX509): string;
var
  LBio: PBIO;
begin
  Result := '';
  if (ACert = nil) then Exit;

  LBio := BIO_new(BIO_s_mem());
  if (LBio = nil) then Exit;

  if (PEM_write_bio_X509(LBio, ACert) = 1) then
    Result := GetStrFromMemBIO(LBio);

  BIO_free(LBio);
end;

class function TSSLTools.GetCertPolicies(ACert: PX509): TArray<TPolicie>;
var
  LPolicies: Pointer;
  I, N: Integer;
  LPolicy: PPOLICYINFO;
begin
  Result := nil;
  if (ACert = nil) then Exit;
  
  LPolicies := X509_get_ext_d2i(ACert, NID_certificate_policies, nil, nil);
  if (LPolicies = nil) then Exit;

  N := OPENSSL_sk_num(LPolicies);
  SetLength(Result, N);

  for I := 0 to N - 1 do
  begin
    FillChar(Result[I], SizeOf(TPolicie), 0);

    LPolicy := OPENSSL_sk_value(LPolicies, I);
    if (LPolicy = nil) then Continue;

    Result[I].OID := ASN1_OBJECT_ToStr(LPolicy.policyid, 1);
    Result[I].Qualifiers := GetQualifiers(LPolicy)
  end;

  CERTIFICATEPOLICIES_free(LPolicies);
end;

class function TSSLTools.GetCertRawExtensions(
  ACert: PX509): TArray<TExtensionRawData>;
var
  LCount, I: Integer;
begin
  Result := nil;
  if (ACert = nil) then Exit;

  LCount := X509_get_ext_count(ACert);
  if (LCount <= 0) then Exit;

  SetLength(Result, LCount);
  for I := 0 to LCount - 1 do
    GetExtensionRawData(X509_get_ext(ACert, I), Result[I]);
end;

class function TSSLTools.GetCertSctList(ACert: PX509): TArray<TSct>;
var
  LSctList: Pointer;
begin
  Result := nil;
  if (ACert = nil) then Exit;

  LSctList := X509_get_ext_d2i(ACert, NID_ct_precert_scts, nil, nil);
  if (LSctList = nil) then Exit;

  try
    Result := GetSctList(LSctList);
  finally
    OPENSSL_sk_pop_free(LSctList, SCT_free);
  end;
end;

class function TSSLTools.GetCertSerialNumber(ACert: PX509): TBytes;
begin
  if (ACert <> nil) then
    Result := ASN1_INTEGER_ToBytes(X509_get_serialNumber(ACert))
  else
    Result := nil;
end;

class function TSSLTools.GetCertSignature(ACert: PX509): TBytes;
var
  LSig: PASN1_BIT_STRING;
  LAlg: PX509_ALGOR;
begin
  LSig := nil;
  LAlg := nil;
  X509_get0_signature(@LSig, @LAlg, ACert);

  Result := ASN1_BIT_STRING_ToBytes(LSig);
end;

class function TSSLTools.GetCertSubKeyID(ACert: PX509): TBytes;
var
  LSubKeyID: PASN1_OCTET_STRING;
begin
  Result := nil;
  if (ACert = nil) then Exit;
  
  LSubKeyID := X509_get_ext_d2i(ACert, NID_subject_key_identifier, nil, nil);
  if (LSubKeyID = nil) then Exit;

  Result := ASN1_OCTET_STRING_ToBytes(LSubKeyID);
  ASN1_OCTET_STRING_free(LSubKeyID);
end;

class function TSSLTools.GetCipherList(ASsl: PSSL): TArray<string>;
var
  I: Integer;
  LCiper: PAnsiChar;
begin
  Result := [];
  I := 0;
  while True do
  begin
    LCiper := SSL_get_cipher_list(ASsl, I);
    if (LCiper = nil) then Break;

    Result := Result + [UTF8ToString(LCiper)];

    Inc(I);
  end;
end;

class function TSSLTools.GetDistPoint(ADpItem: PDIST_POINT;
  var ADistPoint: TCrlDistPoint): Boolean;
begin
  Result := False;
  FillChar(ADistPoint, SizeOf(TCrlDistPoint), 0);

  if (ADpItem = nil) then Exit;

  if (ADpItem.reasons <> nil) then
    Move(ADpItem.reasons.data^, ADistPoint.Reasons, Min(ADpItem.reasons.length, SizeOf(Cardinal)));

  ADistPoint.DpReasons := ADpItem.dp_reasons;
  
  if (ADpItem.distpoint <> nil) and (ADpItem.distpoint.name.fullname <> nil) then
    ADistPoint.DistPoint := GetGeneralNames(ADpItem.distpoint.name.fullname);

  if (ADpItem.CRLissuer <> nil) then
    ADistPoint.CRLissuer := GetGeneralNames(ADpItem.CRLissuer);
end;

class function TSSLTools.GetExtensionRawData(AExtItem: PX509_EXTENSION;
  var AExtData: TExtensionRawData): Boolean;
var
  LObj: PASN1_OBJECT;
begin
  Result := False;
  FillChar(AExtData, SizeOf(TExtensionRawData), 0);

  if (AExtItem = nil) then Exit;

  LObj := X509_EXTENSION_get_object(AExtItem);
  if (LObj = nil) then Exit;

  AExtData.NID := OBJ_obj2nid(LObj);
  AExtData.OID := ASN1_OBJECT_ToStr(LObj, 1);
  AExtData.Critical := (X509_EXTENSION_get_critical(AExtItem) <> 0);
  AExtData.Name := UTF8ToString(OBJ_nid2ln(AExtData.NID));
  AExtData.Value := ASN1_OCTET_STRING_ToBytes(X509_EXTENSION_get_data(AExtItem));

  Result := True;
end;

class function TSSLTools.GetGeneralName(AName: PGENERAL_NAME;
  var AGeneralName: TGeneralName): Boolean;
var
  LIPv4: PByteArray;
  LIPv6: PWordArray;
begin
  Result := False;
  FillChar(AGeneralName, SizeOf(TGeneralName), 0);
  if (AName = nil) then Exit;
  
  AGeneralName.TypeID := AName.&type;

  case AName.&type of
    GEN_DNS:
      begin
        AGeneralName.TypeName := 'DNS';
        AGeneralName.Value := ASN1_STRING_ToStr(AName.d.dNSName);
      end;

    GEN_EMAIL:
      begin
        AGeneralName.TypeName := 'EMAIL';
        AGeneralName.Value := ASN1_STRING_ToStr(AName.d.rfc822Name);
      end;

    GEN_URI:
      begin
        AGeneralName.TypeName := 'URI';
        AGeneralName.Value := ASN1_STRING_ToStr(AName.d.uniformResourceIdentifier);
      end;

    GEN_DIRNAME:
      begin
        AGeneralName.TypeName := 'DIRNAME';
        AGeneralName.Value := X509NameToStr(AName.d.directoryName,
          XN_FLAG_RFC2253 and not ASN1_STRFLGS_ESC_MSB and not ASN1_STRFLGS_ESC_CTRL);
      end;

    GEN_IPADD:
      begin
        AGeneralName.TypeName := 'IP';
        // IPv4
        if (AName.d.iPAddress.length = 4) then
        begin
          LIPv4 := AName.d.iPAddress.data;
          AGeneralName.Value := Format('%d.%d.%d.%d', [
            LIPv4[0], LIPv4[1], LIPv4[2], LIPv4[3]
          ]);
        end else
        // IPv6
        if (AName.d.iPAddress.length = 16) then
        begin
          LIPv6 := AName.d.iPAddress.data;
          AGeneralName.Value := Format('%x:%x:%x:%x:%x:%x:%x:%x', [
            LIPv6[0], LIPv6[1], LIPv6[2], LIPv6[3],
            LIPv6[4], LIPv6[5], LIPv6[6], LIPv6[7]
          ]);
        end;
      end;

    GEN_RID:
      begin
        AGeneralName.TypeName := 'RID';
        AGeneralName.Value := ASN1_OBJECT_ToStr(AName.d.rid, 0);
      end;
  else
    AGeneralName.TypeName := 'Unsupported';
  end;

  Result := True;
end;

class function TSSLTools.GetGeneralNames(
  ANames: PGENERAL_NAMES): TArray<TGeneralName>;
var
  LCount, I: Integer;
begin
  Result := nil;
  if (ANames = nil) then Exit;
  
  LCount := OPENSSL_sk_num(ANames);
  if (LCount <= 0) then Exit;

  SetLength(Result, LCount);
  for I := 0 to LCount - 1 do
    GetGeneralName(OPENSSL_sk_value(ANames, I), Result[I]);
end;

class function TSSLTools.GetNormalizedPubKeyDer(pubkey: PEVP_PKEY;
  ADer: PPointer): Integer;
var
  LBio, pem_bio: PBIO;
  pem_data: Pointer;
  pem_len: Integer;
  normalized: PEVP_PKEY;
  der_len: Integer;
begin
  Result := 0;
  LBio := BIO_new(BIO_s_mem());
  if (LBio = nil) then Exit;
  
  if (PEM_write_bio_PUBKEY(LBio, pubkey) <> 1) then
  begin
    BIO_free(LBio);
    Exit;
  end;

  // 从BIO读取PEM并转换为DER
  pem_len := BIO_get_mem_data(LBio, @pem_data);
  pem_bio := BIO_new_mem_buf(pem_data, pem_len);
  normalized := PEM_read_bio_PUBKEY(pem_bio, nil, nil, nil);

  der_len := i2d_PUBKEY(normalized, ADer);

  BIO_free(LBio);
  BIO_free(pem_bio);
  EVP_PKEY_free(normalized);
  Result := der_len;
end;

class function TSSLTools.GetSct(ASctItem: PSCT; var ASct: TSct): Boolean;
begin
  Result := False;
  FillChar(ASct, SizeOf(TSct), 0);
  if (ASctItem = nil) then Exit;

  if (ASctItem.version <> SCT_VERSION_V1) then Exit;

  ASct.Version := Integer(ASctItem.version);
  ASct.Sct := AnyDataToBytes(ASctItem.sct, ASctItem.sct_len);
  ASct.LogID := AnyDataToBytes(ASctItem.log_id, ASctItem.log_id_len);
  ASct.Timestamp := ASctItem.timestamp;
  ASct.Ext := AnyDataToBytes(ASctItem.ext, ASctItem.ext_len);
  ASct.HashAlg := ASctItem.hash_alg;
  ASct.SigAlg := ASctItem.sig_alg;
  ASct.Sig := AnyDataToBytes(ASctItem.sig, ASctItem.sig_len);
  ASct.EntryType := Integer(ASctItem.entry_type);
  ASct.Source := Integer(ASctItem.source);
  ASct.ValidationStatus := Integer(ASctItem.validation_status);

  Result := True;
end;

class function TSSLTools.GetSctList(ASctList: Pointer): TArray<TSct>;
var
  LCount, I: Integer;
begin
  Result := nil;
  if (ASctList = nil) then Exit;

  LCount := OPENSSL_sk_num(ASctList);
  if (LCount <= 0) then Exit;

  SetLength(Result, LCount);
  for I := 0 to LCount - 1 do
    GetSct(OPENSSL_sk_value(ASctList, I), Result[I]);
end;

class function TSSLTools.GetSslInfo(ASsl: PSSL; var ASslInfo: TSslInfo): Boolean;
var
  LTempKey: PEVP_PKEY;
  LCert: PX509;
begin
  Result := False;
  FillChar(ASslInfo, SizeOf(TSslInfo), 0);

  if (ASsl = nil) then Exit;

  // 对端使用的SSL版本
  ASslInfo.SslVersion := UTF8ToString(SSL_get_version(ASsl));
  // 服务端名称
  ASslInfo.HostName := UTF8ToString(SSL_get_servername(ASsl, TLSEXT_NAMETYPE_host_name));
  // 对端所有加密套件列表
  ASslInfo.CipherList := GetCipherList(ASsl);
  // 当前加密算法(TLS_AES_128_GCM_SHA256)
  ASslInfo.CurrentCipher := UTF8ToString(SSL_get_cipher_name(ASsl));
  // 当前加密位数
  ASslInfo.CurrentCipherBits := SSL_get_cipher_bits(ASsl);

  // 临时密钥
  SSL_get_peer_tmp_key(ASsl, @LTempKey);
  // 临时密钥ID(1034=NID_X25519)
  ASslInfo.TmpKeyID := EVP_PKEY_get_id(LTempKey);
  // 临时密钥类型(X25519)
  ASslInfo.TmpKeyType := UTF8ToString(OBJ_nid2sn(ASslInfo.TmpKeyID));
  // 临时密钥密码位数(253)
  ASslInfo.TmpKeyBits := EVP_PKEY_get_bits(LTempKey);
  // 临时密钥安全位数(128)
  ASslInfo.TmpKeySecurityBits := EVP_PKEY_get_security_bits(LTempKey);
  // 临时密钥输出缓冲区字节数(32)
  ASslInfo.TmpKeyOutSize := EVP_PKEY_get_size(LTempKey);

  // 证书信息
  LCert := SSL_get0_peer_certificate(ASsl);
  if (LCert <> nil) then
    GetCertInfo(LCert, ASslInfo.CertInfo);

  Result := True;
end;

class function TSSLTools.GetPubKeyDigest(APubKey: PEVP_PKEY; AHasher: PEVP_MD): TBytes;
var
  LDigestLen: Cardinal;
  LDer: Pointer;
  LDerLen: Integer;
begin
  Result := nil;
  if (APubKey = nil) or (AHasher = nil) then Exit;

  LDer := nil;
  // 一定要用 i2d_PUBKEY, 用它计算出来的公钥指纹与主流浏览器上看到的一致
  // 还有一个 i2d_PublicKey, 用它计算出来的公钥指纹与浏览器显示不一致
  LDerLen := i2d_PUBKEY(APubKey, @LDer);
  if (LDerLen <= 0) then Exit;

  try
    SetLength(Result, EVP_MAX_MD_SIZE);
    LDigestLen := 0;
    if (EVP_Digest(LDer, LDerLen, @Result[0], @LDigestLen, AHasher, nil) = 1) then
      SetLength(Result, LDigestLen)
    else
      Result := nil;
  finally
    OPENSSL_free(LDer);
  end;
end;

class function TSSLTools.GetQualifiers(APolicy: PPOLICYINFO): TArray<TQualifier>;
var
  I, N: Integer;
  LQual: PPOLICYQUALINFO;
begin
  Result := nil;
  if (APolicy = nil) or (APolicy.qualifiers = nil) then Exit;

  N := OPENSSL_sk_num(APolicy.qualifiers);
  if (N <= 0) then Exit;

  SetLength(Result, N);
  for I := 0 to N - 1 do
  begin
    FillChar(Result[I], SizeOf(TQualifier), 0);
    LQual := OPENSSL_sk_value(APolicy.qualifiers, I);
    if (LQual = nil) or (LQual.pqualid = nil) then Continue;

    Result[I].QID := OBJ_obj2nid(LQual.pqualid);

    case Result[I].QID of
      // 提取CPS URI
      NID_id_qt_cps:
        Result[I].Value := ASN1_STRING_ToStr(LQual.d.cpsuri);

      // 提取用户通知
      NID_id_qt_unotice:
        if (LQual.d.usernotice <> nil) then
          Result[I].Value := ASN1_STRING_ToStr(LQual.d.usernotice.exptext);
    end;
  end;
end;

class function TSSLTools.LoadLib(const ALibName: string): TLibHandle;
begin
  Result := SafeLoadLibrary(ALibName);
end;

class function TSSLTools.GetProc(const ALibHandle: TLibHandle;
  const AProcName: string): Pointer;
begin
  {$IFDEF DELPHI}
  Result := GetProcAddress(ALibHandle, PChar(AProcName));
  {$ELSE}
  Result := GetProcedureAddress(ALibHandle, AnsiString(AProcName));
  {$ENDIF}
end;

class function TSSLTools.GetSslLibPath: string;
begin
  if (FLibPath <> '') then
    Result := IncludeTrailingPathDelimiter(FLibPath)
  else
    Result := FLibPath;
end;

class function TSSLTools.LoadSslLib(
  const ALibNames: array of string): TLibHandle;
var
  LLibPath, LLibName: string;
begin
  LLibPath := GetSslLibPath;

  Result := 0;
  for LLibName in ALibNames do
  begin
    Result := LoadLib(LLibPath + LLibName);
    if (Result > 0) then Break;
  end;
end;

class function TSSLTools.GetSslLibProc(const ALibHandle: TLibHandle;
  const AProcNames: array of string): Pointer;
var
  LProcName: string;
begin
  if (ALibHandle = 0) or (Length(AProcNames) = 0) then Exit(nil);

  for LProcName in AProcNames do
  begin
    Result := GetProc(ALibHandle, LProcName);
    if (Result <> nil) then Exit;
  end;

  raise ESslInvalidProc.CreateFmt('Invalid SSL interface function: %s', [AProcNames[0]]);
end;

class function TSSLTools.GetSslLibProc(const ALibHandle: TLibHandle; const AProcName: string): Pointer;
begin
  Result := GetSslLibProc(ALibHandle, [AProcName]);
end;

class function TSSLTools.GetStrFromMemBIO(ABio: PBIO): string;
var
  LData: PAnsiChar;
  LDataSize: Integer;
  LTempAnsiStr: AnsiString;
begin
  Result := '';
  if (ABio = nil) then Exit;

  // 从 BIO 提取数据
  LDataSize := BIO_get_mem_data(ABio, @LData);

  if (LDataSize > 0) and (LData <> nil) then
  begin
    LTempAnsiStr := AnsiString(LData);
    SetLength(LTempAnsiStr, LDataSize);
    Result := UTF8ToString(LTempAnsiStr);
  end;
end;

class function TSSLTools.GetAuthorityInfoAccess(
  AAccessDesc: PACCESS_DESCRIPTION;
  var AAuthInfo: TAuthorityInfoAccess): Boolean;
begin
  Result := False;
  FillChar(AAuthInfo, SizeOf(TAuthorityInfoAccess), 0);
  if (AAccessDesc = nil) then Exit;

  AAuthInfo.Method := ASN1_OBJECT_ToStr(AAccessDesc.method, 1);
  AAuthInfo.MethodDesc := ASN1_OBJECT_ToStr(AAccessDesc.method, 0);
  GetGeneralName(AAccessDesc.location, AAuthInfo.Location);

  Result := True;
end;

class function TSSLTools.GetAuthorityInfoAccesses(
  AAuthInfoAccess: PAUTHORITY_INFO_ACCESS): TArray<TAuthorityInfoAccess>;
var
  LCount, I: Integer;
begin
  Result := nil;
  if (AAuthInfoAccess = nil) then Exit;

  LCount := OPENSSL_sk_num(AAuthInfoAccess);
  if (LCount <= 0) then Exit;

  SetLength(Result, LCount);
  for I := 0 to LCount - 1 do
    GetAuthorityInfoAccess(OPENSSL_sk_value(AAuthInfoAccess, I), Result[I]);
end;

class function TSSLTools.GetX509NameEntryDataList(
  AX509Name: PX509_NAME): TArray<TEntryData>;
var
  LEntryCount, I: Integer;
  LX509NameEntry: PX509_NAME_ENTRY;
  LEntryName: PASN1_OBJECT;
  LEntryValue: PASN1_STRING;
begin
  if (AX509Name = nil) then Exit(nil);
  
  LEntryCount := X509_NAME_entry_count(AX509Name);
  SetLength(Result, LEntryCount);

  for I := 0 to LEntryCount - 1 do
  begin
    Result[I].Name := '';
    Result[I].Value := '';

    LX509NameEntry := X509_NAME_get_entry(AX509Name, I);
    if (LX509NameEntry = nil) then Continue;

    LEntryName := X509_NAME_ENTRY_get_object(LX509NameEntry);
    LEntryValue := X509_NAME_ENTRY_get_data(LX509NameEntry);
    if (LEntryName = nil) or (LEntryValue = nil) then Continue;

    Result[I].Name := UTF8ToString(OBJ_nid2sn(OBJ_obj2nid(LEntryName)));
    Result[I].Value := ASN1_STRING_ToStr(LEntryValue);
  end;
end;

class procedure TSSLTools.LoadSslLibs;
{$IFNDEF __SSL_STATIC__}
var
  LCryptoLibs, LSslLibs: TArray<string>;
{$ENDIF}
begin
  {$IFNDEF __SSL_STATIC__}
  if (FCryptoLibHandle = 0) then
  begin
    if (FLibCRYPTO <> '') then
      LCryptoLibs := [FLibCRYPTO]
    else if (LIBCRYPTO_NAME <> '') then
      LCryptoLibs := [LIBCRYPTO_NAME]
    else
    begin
      LCryptoLibs := [
        {$IF DEFINED(MSWINDOWS)}
          {$IFDEF CPU64}
          'libcrypto-3-x64.dll',
          'libcrypto-1_1-x64.dll'
          {$ELSE}
          'libcrypto-3.dll',
          'libcrypto-1_1.dll'
          {$ENDIF}
        {$ELSEIF DEFINED(LINUX)}
        'libcrypto.so.3',
        'libcrypto.so.1.1',
        'libcrypto.so'
        {$ELSEIF DEFINED(MACOS)}
        'libssl.dylib'
        {$ENDIF}
      ];
    end;

    FCryptoLibHandle := LoadSslLib(LCryptoLibs);
    if (FCryptoLibHandle = 0) then
      raise ESslInvalidLib.Create('No available libcrypto library.');

    @OpenSSL_version_num := GetSslLibProc(FCryptoLibHandle, 'OpenSSL_version_num');
    @OPENSSL_init_crypto := GetSslLibProc(FCryptoLibHandle, 'OPENSSL_init_crypto');
    @OPENSSL_cleanup := GetSslLibProc(FCryptoLibHandle, 'OPENSSL_cleanup');

    @ERR_error_string_n := GetSslLibProc(FCryptoLibHandle, 'ERR_error_string_n');
    @ERR_get_error := GetSslLibProc(FCryptoLibHandle, 'ERR_get_error');

    @EVP_PKEY_new := GetSslLibProc(FCryptoLibHandle, 'EVP_PKEY_new');
    @EVP_PKEY_free := GetSslLibProc(FCryptoLibHandle, 'EVP_PKEY_free');
    @EVP_PKEY_get_size := GetSslLibProc(FCryptoLibHandle, ['EVP_PKEY_get_size', 'EVP_PKEY_size']);
    @EVP_PKEY_get_bits := GetSslLibProc(FCryptoLibHandle, ['EVP_PKEY_get_bits', 'EVP_PKEY_bits']);
    @EVP_PKEY_get_id := GetSslLibProc(FCryptoLibHandle, ['EVP_PKEY_get_id', 'EVP_PKEY_id']);
    @EVP_PKEY_get_security_bits := GetSslLibProc(FCryptoLibHandle, ['EVP_PKEY_get_security_bits', 'EVP_PKEY_security_bits']);
    @EVP_PKEY_get0_RSA := GetSslLibProc(FCryptoLibHandle, 'EVP_PKEY_get0_RSA');
    @EVP_PKEY_CTX_new_id := GetSslLibProc(FCryptoLibHandle, 'EVP_PKEY_CTX_new_id');

    @EVP_sha256 := GetSslLibProc(FCryptoLibHandle, 'EVP_sha256');
    @EVP_Digest := GetSslLibProc(FCryptoLibHandle, 'EVP_Digest');
    @EVP_MD_CTX_new := GetSslLibProc(FCryptoLibHandle, 'EVP_MD_CTX_new');
    @EVP_MD_CTX_free := GetSslLibProc(FCryptoLibHandle, 'EVP_MD_CTX_free');
    @EVP_DigestInit_ex := GetSslLibProc(FCryptoLibHandle, 'EVP_DigestInit_ex');
    @EVP_DigestUpdate := GetSslLibProc(FCryptoLibHandle, 'EVP_DigestUpdate');
    @EVP_DigestFinal_ex := GetSslLibProc(FCryptoLibHandle, 'EVP_DigestFinal_ex');

    @BIO_new := GetSslLibProc(FCryptoLibHandle, 'BIO_new');
    @BIO_ctrl := GetSslLibProc(FCryptoLibHandle, 'BIO_ctrl');
    @BIO_new_mem_buf := GetSslLibProc(FCryptoLibHandle, 'BIO_new_mem_buf');
    @BIO_free := GetSslLibProc(FCryptoLibHandle, 'BIO_free');
    @BIO_s_mem := GetSslLibProc(FCryptoLibHandle, 'BIO_s_mem');
    @BIO_read := GetSslLibProc(FCryptoLibHandle, 'BIO_read');
    @BIO_write := GetSslLibProc(FCryptoLibHandle, 'BIO_write');

    @EC_KEY_new_by_curve_name := GetSslLibProc(FCryptoLibHandle, 'EC_KEY_new_by_curve_name');
    @EC_KEY_free := GetSslLibProc(FCryptoLibHandle, 'EC_KEY_free');

    @X509_get_issuer_name := GetSslLibProc(FCryptoLibHandle, 'X509_get_issuer_name');
    @X509_get_subject_name := GetSslLibProc(FCryptoLibHandle, 'X509_get_subject_name');
    @X509_get_serialNumber := GetSslLibProc(FCryptoLibHandle, 'X509_get_serialNumber');
    @X509_get_version := GetSslLibProc(FCryptoLibHandle, 'X509_get_version');
    @X509_get_ext_d2i := GetSslLibProc(FCryptoLibHandle, 'X509_get_ext_d2i');
    @X509_get_signature_nid := GetSslLibProc(FCryptoLibHandle, 'X509_get_signature_nid');
    @X509_get0_signature := GetSslLibProc(FCryptoLibHandle, 'X509_get0_signature');
    @X509_get0_notBefore := GetSslLibProc(FCryptoLibHandle, 'X509_get0_notBefore');
    @X509_get0_notAfter := GetSslLibProc(FCryptoLibHandle, 'X509_get0_notAfter');
    @X509_get0_tbs_sigalg := GetSslLibProc(FCryptoLibHandle, 'X509_get0_tbs_sigalg');
    @X509_get0_pubkey := GetSslLibProc(FCryptoLibHandle, 'X509_get0_pubkey');
    @X509_get0_extensions := GetSslLibProc(FCryptoLibHandle, 'X509_get0_extensions');
    @X509_get_ext_count := GetSslLibProc(FCryptoLibHandle, 'X509_get_ext_count');
    @X509_get_ext := GetSslLibProc(FCryptoLibHandle, 'X509_get_ext');
    @X509_NAME_print_ex := GetSslLibProc(FCryptoLibHandle, 'X509_NAME_print_ex');
    @X509_NAME_get_entry := GetSslLibProc(FCryptoLibHandle, 'X509_NAME_get_entry');
    @X509_NAME_ENTRY_get_object := GetSslLibProc(FCryptoLibHandle, 'X509_NAME_ENTRY_get_object');
    @X509_NAME_ENTRY_get_data := GetSslLibProc(FCryptoLibHandle, 'X509_NAME_ENTRY_get_data');
    @X509_NAME_entry_count := GetSslLibProc(FCryptoLibHandle, 'X509_NAME_entry_count');
    @X509_EXTENSION_get_object := GetSslLibProc(FCryptoLibHandle, 'X509_EXTENSION_get_object');
    @X509_EXTENSION_get_critical := GetSslLibProc(FCryptoLibHandle, 'X509_EXTENSION_get_critical');
    @X509_EXTENSION_get_data := GetSslLibProc(FCryptoLibHandle, 'X509_EXTENSION_get_data');
    @X509V3_EXT_d2i := GetSslLibProc(FCryptoLibHandle, 'X509V3_EXT_d2i');
    @X509V3_EXT_get := GetSslLibProc(FCryptoLibHandle, 'X509V3_EXT_get');
    @X509_STORE_add_cert := GetSslLibProc(FCryptoLibHandle, 'X509_STORE_add_cert');
    @X509_digest := GetSslLibProc(FCryptoLibHandle, 'X509_digest');
    @X509_pubkey_digest := GetSslLibProc(FCryptoLibHandle, 'X509_pubkey_digest');
    @X509_free := GetSslLibProc(FCryptoLibHandle, 'X509_free');

    @OPENSSL_sk_num := GetSslLibProc(FCryptoLibHandle, 'OPENSSL_sk_num');
    @OPENSSL_sk_pop := GetSslLibProc(FCryptoLibHandle, 'OPENSSL_sk_pop');
    @OPENSSL_sk_value := GetSslLibProc(FCryptoLibHandle, 'OPENSSL_sk_value');
    @OPENSSL_sk_free := GetSslLibProc(FCryptoLibHandle, 'OPENSSL_sk_free');
    @OPENSSL_sk_pop_free := GetSslLibProc(FCryptoLibHandle, 'OPENSSL_sk_pop_free');

    @OPENSSL_hexstr2buf := GetSslLibProc(FCryptoLibHandle, 'OPENSSL_hexstr2buf');
    @OPENSSL_buf2hexstr := GetSslLibProc(FCryptoLibHandle, 'OPENSSL_buf2hexstr');

    @PEM_read_bio_X509 := GetSslLibProc(FCryptoLibHandle, 'PEM_read_bio_X509');
    @PEM_read_bio_X509_AUX := GetSslLibProc(FCryptoLibHandle, 'PEM_read_bio_X509_AUX');
    @PEM_read_bio_PrivateKey := GetSslLibProc(FCryptoLibHandle, 'PEM_read_bio_PrivateKey');
    @PEM_write_bio_PUBKEY := GetSslLibProc(FCryptoLibHandle, 'PEM_write_bio_PUBKEY');
    @PEM_read_bio_PUBKEY := GetSslLibProc(FCryptoLibHandle, 'PEM_read_bio_PUBKEY');
    @PEM_write_bio_X509 := GetSslLibProc(FCryptoLibHandle, 'PEM_write_bio_X509');

    @OBJ_nid2obj := GetSslLibProc(FCryptoLibHandle, 'OBJ_nid2obj');
    @OBJ_nid2ln := GetSslLibProc(FCryptoLibHandle, 'OBJ_nid2ln');
    @OBJ_nid2sn := GetSslLibProc(FCryptoLibHandle, 'OBJ_nid2sn');
    @OBJ_obj2nid := GetSslLibProc(FCryptoLibHandle, 'OBJ_obj2nid');
    @OBJ_ln2nid := GetSslLibProc(FCryptoLibHandle, 'OBJ_ln2nid');
    @OBJ_sn2nid := GetSslLibProc(FCryptoLibHandle, 'OBJ_sn2nid');
    @OBJ_obj2txt := GetSslLibProc(FCryptoLibHandle, 'OBJ_obj2txt');

    @ASN1_STRING_to_UTF8 := GetSslLibProc(FCryptoLibHandle, 'ASN1_STRING_to_UTF8');
    @CRYPTO_malloc := GetSslLibProc(FCryptoLibHandle, 'CRYPTO_malloc');
    @CRYPTO_free := GetSslLibProc(FCryptoLibHandle, 'CRYPTO_free');
    @ASN1_STRING_length := GetSslLibProc(FCryptoLibHandle, 'ASN1_STRING_length');
    @ASN1_STRING_get0_data := GetSslLibProc(FCryptoLibHandle, 'ASN1_STRING_get0_data');
    @ASN1_TIME_to_tm := GetSslLibProc(FCryptoLibHandle, 'ASN1_TIME_to_tm');
    @ASN1_TIME_print := GetSslLibProc(FCryptoLibHandle, 'ASN1_TIME_print');
    @ASN1_item_d2i := GetSslLibProc(FCryptoLibHandle, 'ASN1_item_d2i');
    @ASN1_BIT_STRING_get_bit := GetSslLibProc(FCryptoLibHandle, 'ASN1_BIT_STRING_get_bit');
    @ASN1_BIT_STRING_set_bit := GetSslLibProc(FCryptoLibHandle, 'ASN1_BIT_STRING_set_bit');
    @ASN1_INTEGER_get := GetSslLibProc(FCryptoLibHandle, 'ASN1_INTEGER_get');
    @ASN1_INTEGER_set := GetSslLibProc(FCryptoLibHandle, 'ASN1_INTEGER_set');

    @ASN1_INTEGER_to_BN := GetSslLibProc(FCryptoLibHandle, 'ASN1_INTEGER_to_BN');
    @BN_to_ASN1_INTEGER := GetSslLibProc(FCryptoLibHandle, 'BN_to_ASN1_INTEGER');
    @BN_bn2hex := GetSslLibProc(FCryptoLibHandle, 'BN_bn2hex');

    @i2d_PublicKey := GetSslLibProc(FCryptoLibHandle, 'i2d_PublicKey');
    @i2d_PUBKEY := GetSslLibProc(FCryptoLibHandle, 'i2d_PUBKEY');
    @i2d_X509 := GetSslLibProc(FCryptoLibHandle, 'i2d_X509');

    @RSA_get0_key := GetSslLibProc(FCryptoLibHandle, 'RSA_get0_key');

    @AUTHORITY_KEYID_free := GetSslLibProc(FCryptoLibHandle, 'AUTHORITY_KEYID_free');
    @ASN1_OCTET_STRING_free := GetSslLibProc(FCryptoLibHandle, 'ASN1_OCTET_STRING_free');
    @GENERAL_NAME_free := GetSslLibProc(FCryptoLibHandle, 'GENERAL_NAME_free');
    @GENERAL_NAMES_free := GetSslLibProc(FCryptoLibHandle, 'GENERAL_NAMES_free');
    @CERTIFICATEPOLICIES_free := GetSslLibProc(FCryptoLibHandle, 'CERTIFICATEPOLICIES_free');
    @ASN1_OBJECT_free := GetSslLibProc(FCryptoLibHandle, 'ASN1_OBJECT_free');
    @CRL_DIST_POINTS_free := GetSslLibProc(FCryptoLibHandle, 'CRL_DIST_POINTS_free');
    @AUTHORITY_INFO_ACCESS_free := GetSslLibProc(FCryptoLibHandle, 'AUTHORITY_INFO_ACCESS_free');
    @BASIC_CONSTRAINTS_free := GetSslLibProc(FCryptoLibHandle, 'BASIC_CONSTRAINTS_free');
    @ASN1_BIT_STRING_free := GetSslLibProc(FCryptoLibHandle, 'ASN1_BIT_STRING_free');
    @DIST_POINT_free := GetSslLibProc(FCryptoLibHandle, 'DIST_POINT_free');
    @SCT_free := GetSslLibProc(FCryptoLibHandle, 'SCT_free');
  end;

  if (FSslLibHandle = 0) then
  begin
    if (FLibSSL <> '') then
      LSslLibs := [FLibSSL]
    else if (LIBCRYPTO_NAME <> '') then
      LSslLibs := [LIBSSL_NAME]
    else
    begin
      LSslLibs := [
	      {$IF DEFINED(MSWINDOWS)}
          {$IFDEF CPU64}
          'libssl-3-x64.dll',
          'libssl-1_1-x64.dll'
          {$ELSE}
          'libssl-3.dll',
          'libssl-1_1.dll'
          {$ENDIF}
        {$ELSEIF DEFINED(LINUX)}
        'libssl.so.3',
        'libssl.so.1.1',
        'libssl.so'
        {$ELSEIF DEFINED(MACOS)}
        'libcrypto.dylib'
        {$ENDIF}
      ];
    end;

    FSslLibHandle := LoadSslLib(LSslLibs);
    if (FSslLibHandle = 0) then
      raise ESslInvalidLib.Create('No available libssl library.');

    @OPENSSL_init_ssl := GetSslLibProc(FSslLibHandle, 'OPENSSL_init_ssl');

    @TLS_method := GetSslLibProc(FSslLibHandle, 'TLS_method');
    @TLS_client_method := GetSslLibProc(FSslLibHandle, 'TLS_client_method');
    @TLS_server_method := GetSslLibProc(FSslLibHandle, 'TLS_server_method');

    @SSL_CTX_new := GetSslLibProc(FSslLibHandle, 'SSL_CTX_new');
    @SSL_CTX_free := GetSslLibProc(FSslLibHandle, 'SSL_CTX_free');
    @SSL_CTX_ctrl := GetSslLibProc(FSslLibHandle, 'SSL_CTX_ctrl');
    @SSL_CTX_set_verify := GetSslLibProc(FSslLibHandle, 'SSL_CTX_set_verify');
    @SSL_CTX_set_cipher_list := GetSslLibProc(FSslLibHandle, 'SSL_CTX_set_cipher_list');
    @SSL_CTX_set_ciphersuites := GetSslLibProc(FSslLibHandle, 'SSL_CTX_set_ciphersuites');
    @SSL_CTX_use_PrivateKey := GetSslLibProc(FSslLibHandle, 'SSL_CTX_use_PrivateKey');
    @SSL_CTX_use_certificate := GetSslLibProc(FSslLibHandle, 'SSL_CTX_use_certificate');
    @SSL_CTX_check_private_key := GetSslLibProc(FSslLibHandle, 'SSL_CTX_check_private_key');
    @SSL_CTX_get_cert_store := GetSslLibProc(FSslLibHandle, 'SSL_CTX_get_cert_store');
    @SSL_CTX_add_client_CA := GetSslLibProc(FSslLibHandle, 'SSL_CTX_add_client_CA');
    @SSL_CTX_set_default_verify_paths := GetSslLibProc(FSslLibHandle, 'SSL_CTX_set_default_verify_paths');

    @SSL_new := GetSslLibProc(FSslLibHandle, 'SSL_new');
    @SSL_set_bio := GetSslLibProc(FSslLibHandle, 'SSL_set_bio');
    @SSL_get_error := GetSslLibProc(FSslLibHandle, 'SSL_get_error');
    @SSL_get_cipher_list := GetSslLibProc(FSslLibHandle, 'SSL_get_cipher_list');
    @SSL_get_version := GetSslLibProc(FSslLibHandle, 'SSL_get_version');
    @SSL_get_current_cipher := GetSslLibProc(FSslLibHandle, 'SSL_get_current_cipher');
    @SSL_CIPHER_get_name := GetSslLibProc(FSslLibHandle, 'SSL_CIPHER_get_name');
    @SSL_CIPHER_get_bits := GetSslLibProc(FSslLibHandle, 'SSL_CIPHER_get_bits');
    @SSL_get_servername := GetSslLibProc(FSslLibHandle, 'SSL_get_servername');
    @SSL_get0_peer_certificate := GetSslLibProc(FSslLibHandle, ['SSL_get0_peer_certificate', 'SSL_get_peer_certificate']);

    @SSL_ctrl := GetSslLibProc(FSslLibHandle, 'SSL_ctrl');

    @SSL_shutdown := GetSslLibProc(FSslLibHandle, 'SSL_shutdown');
    @SSL_free := GetSslLibProc(FSslLibHandle, 'SSL_free');

    @SSL_set_connect_state := GetSslLibProc(FSslLibHandle, 'SSL_set_connect_state');
    @SSL_set_accept_state := GetSslLibProc(FSslLibHandle, 'SSL_set_accept_state');
    @SSL_set_fd := GetSslLibProc(FSslLibHandle, 'SSL_set_fd');
    @SSL_accept := GetSslLibProc(FSslLibHandle, 'SSL_accept');
    @SSL_connect := GetSslLibProc(FSslLibHandle, 'SSL_connect');
    @SSL_do_handshake := GetSslLibProc(FSslLibHandle, 'SSL_do_handshake');
    @SSL_read := GetSslLibProc(FSslLibHandle, 'SSL_read');
    @SSL_write := GetSslLibProc(FSslLibHandle, 'SSL_write');
    @SSL_pending := GetSslLibProc(FSslLibHandle, 'SSL_pending');
    @SSL_is_init_finished := GetSslLibProc(FSslLibHandle, 'SSL_is_init_finished');
  end;
  {$ENDIF}
end;

class procedure TSSLTools.SetLibCRYPTO(const AValue: string);
begin
  {$IFNDEF __SSL_STATIC__}
  if (FLibCRYPTO = AValue) then Exit;
  FLibCRYPTO := AValue;
  {$ENDIF}
end;

class procedure TSSLTools.SetLibPath(const AValue: string);
begin
  {$IFNDEF __SSL_STATIC__}
  if (FLibPath = AValue) then Exit;
  FLibPath := AValue;
  {$ENDIF}
end;

class procedure TSSLTools.SetLibSSL(const AValue: string);
begin
  {$IFNDEF __SSL_STATIC__}
  if (FLibSSL = AValue) then Exit;
  FLibSSL := AValue;
  {$ENDIF}
end;


class procedure TSSLTools.UnloadSslLibs;
begin
  {$IFNDEF __SSL_STATIC__}
  if (FSslLibHandle <> 0) then
  begin
    FreeLibrary(FSslLibHandle);
    FSslLibHandle := 0;
  end;

  if (FCryptoLibHandle <> 0) then
  begin
    FreeLibrary(FCryptoLibHandle);
    FCryptoLibHandle := 0;
  end;
  {$ENDIF}
end;

class function TSSLTools.X509NameToStr(name: PX509_NAME; AFlags: Cardinal): string;
var
  LBio: PBIO;
  LFlags: Cardinal;
begin
  Result := '';
  if (name = nil) then Exit;

  LBio := BIO_new(BIO_s_mem());
  if (LBio = nil) then Exit;

  // 使用 RFC2253 格式标志，模拟 X509_NAME_oneline 的简洁输出
  // (XN_FLAG_RFC2253 and not ASN1_STRFLGS_ESC_MSB);
//  LFlags := ASN1_STRFLGS_ESC_2253
//    or ASN1_STRFLGS_ESC_CTRL
//    or ASN1_STRFLGS_UTF8_CONVERT
//    or XN_FLAG_SEP_MULTILINE
//    or XN_FLAG_FN_SN;
  LFlags := AFlags;
  if (X509_NAME_print_ex(LBio, name, 0, LFlags) < 0) then
  begin
    BIO_free(LBio);
    Exit;
  end;

  Result := GetStrFromMemBIO(LBio);

  BIO_free(LBio);
end;

end.
