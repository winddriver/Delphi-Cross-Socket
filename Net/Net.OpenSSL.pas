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
  Utils.IOUtils;

const
  LIBSSL_NAME =
    {$IFDEF MSWINDOWS}
      {$IFDEF CPUX86}
      'libssl-3.dll'
      {$ENDIF}
      {$IFDEF CPUX64}
      'libssl-3-x64.dll'
      {$ENDIF}
    {$ENDIF}
    {$IFDEF POSIX}
      {$IFDEF __SSL_STATIC__}
      'libssl.a'
      {$ELSEIF DEFINED(MACOS)}
      'libssl.dylib'
      {$ELSE}
      ''
      {$ENDIF}
    {$ENDIF};

  LIBCRYPTO_NAME =
    {$IFDEF MSWINDOWS}
      {$IFDEF CPUX86}
      'libcrypto-3.dll'
      {$ENDIF}
      {$IFDEF CPUX64}
      'libcrypto-3-x64.dll'
      {$ENDIF}
    {$ENDIF}
    {$IFDEF POSIX}
      {$IFDEF __SSL_STATIC__}
      'libcrypto.a'
      {$ELSEIF DEFINED(MACOS)}
      'libcrypto.dylib'
      {$ELSE}
      ''
      {$ENDIF}
    {$ENDIF};

  _PU = '';

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
  SSL_CTRL_GET_RI_SUPPORT                     = 76;
  SSL_CTRL_CLEAR_OPTIONS                      = 77;
  SSL_CTRL_CLEAR_MODE                         = 78;
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
  SSL_CTRL_GET_SERVER_TMP_KEY                 = 109;
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

  SSL_MODE_ENABLE_PARTIAL_WRITE       = $00000001;
  SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER = $00000002;
  SSL_MODE_AUTO_RETRY                 = $00000004;
  SSL_MODE_NO_AUTO_CHAIN              = $00000008;

  SSL_OP_MICROSOFT_SESS_ID_BUG                = $00000001;
  SSL_OP_NETSCAPE_CHALLENGE_BUG               = $00000002;
  SSL_OP_NETSCAPE_REUSE_CIPHER_CHANGE_BUG     = $00000008;
  SSL_OP_TLSEXT_PADDING                       = $00000010;
  SSL_OP_SSLREF2_REUSE_CERT_TYPE_BUG          = $00000000;
  SSL_OP_MICROSOFT_BIG_SSLV3_BUFFER           = $00000020;
  SSL_OP_SAFARI_ECDHE_ECDSA_BUG               = $00000040;
  SSL_OP_MSIE_SSLV2_RSA_PADDING               = $00000000;
  SSL_OP_SSLEAY_080_CLIENT_DH_BUG             = $00000080;
  SSL_OP_TLS_D5_BUG                           = $00000100;
  SSL_OP_TLS_BLOCK_PADDING_BUG                = $00000200;
  SSL_OP_DONT_INSERT_EMPTY_FRAGMENTS          = $00000800;
  SSL_OP_ALL                                  = $00000BFF;
  SSL_OP_NO_QUERY_MTU                         = $00001000;
  SSL_OP_COOKIE_EXCHANGE                      = $00002000;
  SSL_OP_NO_TICKET                            = $00004000;
  SSL_OP_CISCO_ANYCONNECT                     = $00008000;
  SSL_OP_NO_SESSION_RESUMPTION_ON_RENEGOTIATION  = $00010000;
  SSL_OP_NO_COMPRESSION                       = $00020000;
  SSL_OP_ALLOW_UNSAFE_LEGACY_RENEGOTIATION    = $00040000;
  SSL_OP_SINGLE_ECDH_USE                      = $0;
  SSL_OP_SINGLE_DH_USE                        = $00100000;
  SSL_OP_EPHEMERAL_RSA                        = $00200000;
  SSL_OP_CIPHER_SERVER_PREFERENCE             = $00400000;
  SSL_OP_TLS_ROLLBACK_BUG                     = $00800000;
  SSL_OP_NO_SSLv2                             = $0;
  SSL_OP_NO_SSLv3                             = $02000000;
  SSL_OP_NO_TLSv1                             = $04000000;
  SSL_OP_NO_TLSv1_2                           = $08000000;
  SSL_OP_NO_TLSv1_1                           = $10000000;
  SSL_OP_NO_TLSv1_3                           = $20000000;
  SSL_OP_PKCS1_CHECK_1                        = $00000000;
  SSL_OP_PKCS1_CHECK_2                        = $00000000;
  SSL_OP_NETSCAPE_CA_DN_BUG                   = $20000000;
  SSL_OP_NETSCAPE_DEMO_CIPHER_CHANGE_BUG      = $40000000;
  SSL_OP_CRYPTOPRO_TLSEXT_BUG                 = $80000000;

  NID_X9_62_prime192v1            = 409;
  NID_X9_62_prime192v2            = 410;
  NID_X9_62_prime192v3            = 411;
  NID_X9_62_prime239v1            = 412;
  NID_X9_62_prime239v2            = 413;
  NID_X9_62_prime239v3            = 414;
  NID_X9_62_prime256v1            = 415;

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

type
  size_t = NativeUInt;

  {$REGION 'SSL'}
  PSSL_CTX = Pointer;
  PSSL = Pointer;
  PSSL_METHOD = Pointer;

  PBIO = Pointer;
  PPBIO = ^PBIO;

  PEVP_PKEY = Pointer;
  PPEVP_PKEY = ^PEVP_PKEY;

  PX509_STORE_CTX = Pointer;
  PX509_STORE = Pointer;

  PX509 = Pointer;
  PPX509 = ^PX509;

  TSetVerifyCb = function(Ok: Integer; StoreCtx: PX509_STORE_CTX): Integer; cdecl;
  {$ENDREGION}

  {$REGION 'LIBSSL'}
  PCRYPTO_THREADID = Pointer;
  PBIO_METHOD = Pointer;
  PX509_NAME = Pointer;
  PSTACK = Pointer;
  PEC_KEY = Pointer;

  TPemPasswordCb = function(buf: Pointer; size: Integer; rwflag: Integer; userdata: Pointer): Integer; cdecl;
  {$ENDREGION}

{$IFDEF __SSL_STATIC__}

{$REGION 'LIBSSL-FUNC'}
function OPENSSL_init_ssl(opts: UInt64; settings: Pointer): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'OPENSSL_init_ssl';

function TLS_method: PSSL_METHOD; cdecl;
  external LIBSSL_NAME name _PU + 'TLS_method';
function TLS_client_method: PSSL_METHOD; cdecl;
  external LIBSSL_NAME name _PU + 'TLS_client_method';
function TLS_server_method: PSSL_METHOD; cdecl;
  external LIBSSL_NAME name _PU + 'TLS_server_method';

function SSL_CTX_new(meth: PSSL_METHOD): PSSL_CTX; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_CTX_new';
procedure SSL_CTX_free(ctx: PSSL_CTX); cdecl;
  external LIBSSL_NAME name _PU + 'SSL_CTX_free';
function SSL_CTX_ctrl(ctx: PSSL_CTX; Cmd: Integer; LArg: Integer; PArg: MarshaledAString): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_CTX_ctrl';
procedure SSL_CTX_set_verify(ctx: PSSL_CTX; mode: Integer; callback: TSetVerifyCb); cdecl;
  external LIBSSL_NAME name _PU + 'SSL_CTX_set_verify';
function SSL_CTX_set_cipher_list(ctx: PSSL_CTX; CipherString: MarshaledAString): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_CTX_set_cipher_list';
function SSL_CTX_use_PrivateKey(ctx: PSSL_CTX; pkey: PEVP_PKEY): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_CTX_use_PrivateKey';
function SSL_CTX_use_certificate(ctx: PSSL_CTX; cert: PX509): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_CTX_use_certificate';
function SSL_CTX_check_private_key(ctx: PSSL_CTX): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_CTX_check_private_key';

function SSL_new(ctx: PSSL_CTX): PSSL; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_new';
procedure SSL_set_bio(s: PSSL; rbio, wbio: PBIO); cdecl;
  external LIBSSL_NAME name _PU + 'SSL_set_bio';
function SSL_get_error(s: PSSL; ret_code: Integer): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_get_error';

function SSL_ctrl(S: PSSL; Cmd: Integer; LArg: Integer; PArg: Pointer): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_ctrl';

function SSL_shutdown(s: PSSL): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_shutdown';
procedure SSL_free(s: PSSL); cdecl;
  external LIBSSL_NAME name _PU + 'SSL_free';

procedure SSL_set_connect_state(s: PSSL); cdecl;
  external LIBSSL_NAME name _PU + 'SSL_set_connect_state';
procedure SSL_set_accept_state(s: PSSL); cdecl;
  external LIBSSL_NAME name _PU + 'SSL_set_accept_state';
function SSL_set_fd(s: PSSL; fd: Integer): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_set_fd';
function SSL_accept(S: PSSL): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_accept';
function SSL_connect(S: PSSL): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_connect';
function SSL_do_handshake(S: PSSL): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_do_handshake';
function SSL_read(s: PSSL; buf: Pointer; num: Integer): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_read';
function SSL_write(s: PSSL; const buf: Pointer; num: Integer): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_write';
function SSL_pending(s: PSSL): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_pending';
function SSL_is_init_finished(s: PSSL): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_is_init_finished';

function SSL_CTX_get_cert_store(const Ctx: PSSL_CTX): PX509_STORE; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_CTX_get_cert_store';
function SSL_CTX_add_client_CA(C: PSSL_CTX; CaCert: PX509): Integer; cdecl;
  external LIBSSL_NAME name _PU + 'SSL_CTX_add_client_CA';
{$ENDREGION}

{$REGION 'LIBCRYPTO-FUNC'}
function OpenSSL_version_num: Longword; cdecl;
  external LIBCRYPTO_NAME name _PU + 'OpenSSL_version_num';
function OPENSSL_init_crypto(opts: UInt64; settings: Pointer): Integer; cdecl;
  external LIBCRYPTO_NAME name _PU + 'OPENSSL_init_crypto';
procedure OPENSSL_cleanup; cdecl;
  external LIBCRYPTO_NAME name _PU + 'OPENSSL_cleanup';

procedure ERR_error_string_n(err: Cardinal; buf: MarshaledAString; len: size_t); cdecl;
  external LIBCRYPTO_NAME name _PU + 'ERR_error_string_n';
function ERR_get_error: Cardinal; cdecl;
  external LIBCRYPTO_NAME name _PU + 'ERR_get_error';

procedure EVP_PKEY_free(pkey: PEVP_PKEY); cdecl;
  external LIBCRYPTO_NAME name _PU + 'EVP_PKEY_free';

function BIO_new(BioMethods: PBIO_METHOD): PBIO; cdecl;
  external LIBCRYPTO_NAME name _PU + 'BIO_new';
function BIO_ctrl(bp: PBIO; cmd: Integer; larg: Longint; parg: Pointer): Longint; cdecl;
  external LIBCRYPTO_NAME name _PU + 'BIO_ctrl';
function BIO_new_mem_buf(buf: Pointer; len: Integer): PBIO; cdecl;
  external LIBCRYPTO_NAME name _PU + 'BIO_new_mem_buf';
function BIO_free(b: PBIO): Integer; cdecl;
  external LIBCRYPTO_NAME name _PU + 'BIO_free';
function BIO_s_mem: PBIO_METHOD; cdecl;
  external LIBCRYPTO_NAME name _PU + 'BIO_s_mem';
function BIO_read(b: PBIO; Buf: Pointer; Len: Integer): Integer; cdecl;
  external LIBCRYPTO_NAME name _PU + 'BIO_read';
function BIO_write(b: PBIO; Buf: Pointer; Len: Integer): Integer; cdecl;
  external LIBCRYPTO_NAME name _PU + 'BIO_write';

function EC_KEY_new_by_curve_name(nid: Integer): PEC_KEY; cdecl;
  external LIBCRYPTO_NAME name _PU + 'EC_KEY_new_by_curve_name';
procedure EC_KEY_free(key: PEC_KEY); cdecl;
  external LIBCRYPTO_NAME name _PU + 'EC_KEY_free';

function X509_get_issuer_name(cert: PX509): PX509_NAME; cdecl;
  external LIBCRYPTO_NAME name _PU + 'X509_get_issuer_name';
function X509_get_subject_name(cert: PX509): PX509_NAME; cdecl;
  external LIBCRYPTO_NAME name _PU + 'X509_get_subject_name';
procedure X509_free(cert: PX509); cdecl;
  external LIBCRYPTO_NAME name _PU + 'X509_free';
function X509_NAME_print_ex(bout: PBIO; nm: PX509_NAME; indent: Integer; flags: Cardinal): Integer; cdecl;
  external LIBCRYPTO_NAME name _PU + 'X509_NAME_print_ex';
function X509_get_ext_d2i(x: PX509; nid: Integer; var crit, idx: Integer): Pointer; cdecl;
  external LIBCRYPTO_NAME name _PU + 'X509_get_ext_d2i';

function X509_STORE_add_cert(Store: PX509_STORE; Cert: PX509): Integer; cdecl;
  external LIBCRYPTO_NAME name _PU + 'X509_STORE_add_cert';

function OPENSSL_sk_num(stack: PSTACK): Integer; cdecl;
  external LIBCRYPTO_NAME name _PU + 'OPENSSL_sk_num';
function OPENSSL_sk_pop(stack: PSTACK): Pointer; cdecl;
  external LIBCRYPTO_NAME name _PU + 'OPENSSL_sk_pop';

function PEM_read_bio_X509(bp: PBIO; x: PPX509; cb: TPemPasswordCb; u: Pointer): PX509; cdecl;
  external LIBCRYPTO_NAME name _PU + 'PEM_read_bio_X509';
function PEM_read_bio_X509_AUX(bp: PBIO; x: PPX509; cb: TPemPasswordCb; u: Pointer): PX509; cdecl;
  external LIBCRYPTO_NAME name _PU + 'PEM_read_bio_X509_AUX';
function PEM_read_bio_PrivateKey(bp: PBIO; x: PPEVP_PKEY; cb: TPemPasswordCb; u: Pointer): PEVP_PKEY; cdecl;
  external LIBCRYPTO_NAME name _PU + 'PEM_read_bio_PrivateKey';
{$ENDREGION}

{$ENDIF __SSL_STATIC__}

function SSL_CTX_need_tmp_rsa(ctx: PSSL_CTX): Integer; inline;
function SSL_CTX_set_tmp_rsa(ctx: PSSL_CTX; rsa: MarshaledAString): Integer; inline;
function SSL_CTX_set_tmp_dh(ctx: PSSL_CTX; dh: MarshaledAString): Integer; inline;
function SSL_CTX_set_tmp_ecdh(ctx: PSSL_CTX; ecdh: PEC_KEY): Integer; inline;
function SSL_CTX_add_extra_chain_cert(ctx: PSSL_CTX; cert: PX509): Integer; inline;
function SSL_need_tmp_rsa(ssl: PSSL): Integer; inline;
function SSL_set_tmp_rsa(ssl: PSSL; rsa: MarshaledAString): Integer; inline;
function SSL_set_tmp_dh(ssl: PSSL; dh: MarshaledAString): Integer; inline;
function SSL_set_tmp_ecdh(ssl: PSSL; ecdh: MarshaledAString): Integer; inline;

function SSL_CTX_set_options(ctx: PSSL_CTX; Op: Integer): Integer; inline;
function SSL_CTX_get_options(ctx: PSSL_CTX): Integer; inline;
function SSL_CTX_set_mode(ctx: PSSL_CTX; op: Integer): Integer; inline;
function SSL_CTX_clear_mode(ctx: PSSL_CTX; op: Integer): Integer; inline;
function SSL_CTX_get_mode(ctx: PSSL_CTX): Integer; inline;

function SSL_set_options(ssl: PSSL; Op: Integer): Integer; inline;
function SSL_get_options(ssl: PSSL): Integer; inline;
function SSL_clear_options(ssl: PSSL; Op: Integer): Integer; inline;

function BIO_eof(bp: PBIO): Boolean; inline;
function BIO_pending(bp: PBIO): Integer; inline;
function BIO_get_mem_data(bp: PBIO; parg: Pointer): Integer; inline;
function BIO_get_flags(b: PBIO): Integer; inline;
function BIO_should_retry(b: PBIO): Boolean; inline;

function SSL_is_fatal_error(ssl_error: Integer): Boolean;
function SSL_error_message(ssl_error: Integer): string;

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
  TSSLTools = class
  private
    class var FRef: Integer;
    class var FSslVersion: Longword;

    class destructor Destroy;

    {$IFNDEF __SSL_STATIC__}
    class var FLibPath, FLibSSL, FLibCRYPTO: string;
    class var FSslLibHandle, FCryptoLibHandle: TLibHandle;

    class function GetSslLibPath: string; static;
    class function GetSslLibProc(const ALibHandle: TLibHandle;
      const AProcName: string): Pointer; static;
    class function LoadSslLib(const ALibName: string): TLibHandle; static;
    class procedure LoadSslLibs; static;
    class procedure UnloadSslLibs; static;
    {$ENDIF}

    class procedure SslInit; static;
    class procedure SslUninit; static;
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

    {$IFNDEF __SSL_STATIC__}
    // 手动指定 ssl 库路径
    class property LibPath: string read FLibPath write FLibPath;

    // 手动指定 libssl 库名称
    class property LibSSL: string read FLibSSL write FLibSSL;

    // 手动指定 libcrypto 库名称
    class property LibCRYPTO: string read FLibCRYPTO write FLibCRYPTO;
    {$ENDIF}
  end;
  {$ENDREGION}

{$IFNDEF __SSL_STATIC__}

var
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
  SSL_CTX_use_PrivateKey: function(ctx: PSSL_CTX; pkey: PEVP_PKEY): Integer; cdecl;
  SSL_CTX_use_certificate: function(ctx: PSSL_CTX; cert: PX509): Integer; cdecl;
  SSL_CTX_check_private_key: function(ctx: PSSL_CTX): Integer; cdecl;

  SSL_new: function(ctx: PSSL_CTX): PSSL; cdecl;
  SSL_set_bio: procedure(s: PSSL; rbio, wbio: PBIO); cdecl;
  SSL_get_error: function(s: PSSL; ret_code: Integer): Integer; cdecl;

  SSL_ctrl: function(S: PSSL; Cmd: Integer; LArg: Integer; PArg: Pointer): Integer; cdecl;

  SSL_shutdown: function(s: PSSL): Integer; cdecl;
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

  SSL_CTX_get_cert_store: function(const Ctx: PSSL_CTX): PX509_STORE; cdecl;
  SSL_CTX_add_client_CA: function(C: PSSL_CTX; CaCert: PX509): Integer; cdecl;
  {$ENDREGION}

  {$REGION 'LIBCRYPTO-FUNC'}
  OpenSSL_version_num: function: Longword; cdecl;
  OPENSSL_init_crypto: function(opts: UInt64; settings: Pointer): Integer; cdecl;
  OPENSSL_cleanup: procedure; cdecl;

  ERR_error_string_n: procedure(err: Cardinal; buf: MarshaledAString; len: size_t); cdecl;
  ERR_get_error: function: Cardinal; cdecl;

  EVP_PKEY_free: procedure(pkey: PEVP_PKEY); cdecl;

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
  X509_free: procedure(cert: PX509); cdecl;
  X509_NAME_print_ex: function(bout: PBIO; nm: PX509_NAME; indent: Integer; flags: Cardinal): Integer; cdecl;
  X509_get_ext_d2i: function(x: PX509; nid: Integer; var crit, idx: Integer): Pointer; cdecl;

  X509_STORE_add_cert: function(Store: PX509_STORE; Cert: PX509): Integer; cdecl;

  OPENSSL_sk_num: function(stack: PSTACK): Integer; cdecl;
  OPENSSL_sk_pop: function(stack: PSTACK): Pointer; cdecl;

  PEM_read_bio_X509: function(bp: PBIO; x: PPX509; cb: TPemPasswordCb; u: Pointer): PX509; cdecl;
  PEM_read_bio_X509_AUX: function(bp: PBIO; x: PPX509; cb: TPemPasswordCb; u: Pointer): PX509; cdecl;
  PEM_read_bio_PrivateKey: function(bp: PBIO; x: PPEVP_PKEY; cb: TPemPasswordCb; u: Pointer): PEVP_PKEY; cdecl;
  {$ENDREGION}

{$ENDIF}

implementation

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

function BIO_eof(bp: PBIO): Boolean;
begin
  Result := (BIO_ctrl(bp, BIO_CTRL_EOF, 0, nil) <> 0);
end;

function BIO_pending(bp: PBIO): Integer;
begin
  Result := BIO_ctrl(bp, BIO_CTRL_PENDING, 0, nil);
end;

function BIO_get_mem_data(bp: PBIO; parg: Pointer): Integer;
begin
  Result := BIO_ctrl(bp, BIO_CTRL_INFO, 0, parg);
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

{ TSSLTools }

class function TSSLTools.NewCTX(AMeth: PSSL_METHOD): PSSL_CTX;
begin
  if (AMeth = nil) then
    AMeth := TLS_method();
  Result := SSL_CTX_new(AMeth);
end;

class function TSSLTools.SSLVersion: Longword;
begin
  Result := FSslVersion;
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

{$IFNDEF __SSL_STATIC__}

class function TSSLTools.GetSslLibPath: string;
begin
  if (FLibPath <> '') then
    Result := IncludeTrailingPathDelimiter(FLibPath)
  else
    Result := FLibPath;
end;

class function TSSLTools.LoadSslLib(const ALibName: string): TLibHandle;
begin
  Result := SafeLoadLibrary(GetSslLibPath + ALibName);
end;

class function TSSLTools.GetSslLibProc(const ALibHandle: TLibHandle; const AProcName: string): Pointer;
begin
  {$IFDEF DELPHI}
  Result := GetProcAddress(ALibHandle, PChar(AProcName));
  {$ELSE}
  Result := GetProcedureAddress(ALibHandle, AnsiString(AProcName));
  {$ENDIF}

  if (Result = nil) then
    raise ESslInvalidProc.CreateFmt('Invalid SSL interface function: %s', [AProcName]);
end;

class procedure TSSLTools.LoadSslLibs;
var
  LCryptoLibName, LSslLibName: string;
  LCryptoLibs, LSslLibs: TArray<string>;
begin
  if (FCryptoLibHandle = 0) then
  begin
    if (FLibCRYPTO <> '') then
      LCryptoLibs := [FLibCRYPTO]
    else if (LIBCRYPTO_NAME <> '') then
      LCryptoLibs := [LIBCRYPTO_NAME]
    else
      LCryptoLibs := ['libcrypto.so.3', 'libcrypto.so.1.1', 'libcrypto.so'];

    FCryptoLibHandle := 0;
    for LCryptoLibName in LCryptoLibs do
    begin
      FCryptoLibHandle := LoadSslLib(LCryptoLibName);
      if (FCryptoLibHandle > 0) then
      begin
        FLibCRYPTO := LCryptoLibName;
        Break;
      end;
    end;
    if (FCryptoLibHandle = 0) then
      raise ESslInvalidLib.Create('No available libcrypto library.');

    @OpenSSL_version_num := GetSslLibProc(FCryptoLibHandle, 'OpenSSL_version_num');
    @OPENSSL_init_crypto := GetSslLibProc(FCryptoLibHandle, 'OPENSSL_init_crypto');
    @OPENSSL_cleanup := GetSslLibProc(FCryptoLibHandle, 'OPENSSL_cleanup');

    @ERR_error_string_n := GetSslLibProc(FCryptoLibHandle, 'ERR_error_string_n');
    @ERR_get_error := GetSslLibProc(FCryptoLibHandle, 'ERR_get_error');

    @EVP_PKEY_free := GetSslLibProc(FCryptoLibHandle, 'EVP_PKEY_free');

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
    @X509_free := GetSslLibProc(FCryptoLibHandle, 'X509_free');
    @X509_NAME_print_ex := GetSslLibProc(FCryptoLibHandle, 'X509_NAME_print_ex');
    @X509_get_ext_d2i := GetSslLibProc(FCryptoLibHandle, 'X509_get_ext_d2i');

    @X509_STORE_add_cert := GetSslLibProc(FCryptoLibHandle, 'X509_STORE_add_cert');

    @OPENSSL_sk_num := GetSslLibProc(FCryptoLibHandle, 'OPENSSL_sk_num');
    @OPENSSL_sk_pop := GetSslLibProc(FCryptoLibHandle, 'OPENSSL_sk_pop');

    @PEM_read_bio_X509 := GetSslLibProc(FCryptoLibHandle, 'PEM_read_bio_X509');
    @PEM_read_bio_X509_AUX := GetSslLibProc(FCryptoLibHandle, 'PEM_read_bio_X509_AUX');
    @PEM_read_bio_PrivateKey := GetSslLibProc(FCryptoLibHandle, 'PEM_read_bio_PrivateKey');
  end;

  if (FSslLibHandle = 0) then
  begin
    if (FLibSSL <> '') then
      LSslLibs := [FLibSSL]
    else if (LIBCRYPTO_NAME <> '') then
      LSslLibs := [LIBSSL_NAME]
    else
      LSslLibs := ['libssl.so.3', 'libssl.so.1.1', 'libssl.so'];

    FSslLibHandle := 0;
    for LSslLibName in LSslLibs do
    begin
      FSslLibHandle := LoadSslLib(LSslLibName);
      if (FSslLibHandle > 0) then
      begin
        FLibSSL := LSslLibName;
        Break;
      end;
    end;
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
    @SSL_CTX_use_PrivateKey := GetSslLibProc(FSslLibHandle, 'SSL_CTX_use_PrivateKey');
    @SSL_CTX_use_certificate := GetSslLibProc(FSslLibHandle, 'SSL_CTX_use_certificate');
    @SSL_CTX_check_private_key := GetSslLibProc(FSslLibHandle, 'SSL_CTX_check_private_key');

    @SSL_new := GetSslLibProc(FSslLibHandle, 'SSL_new');
    @SSL_set_bio := GetSslLibProc(FSslLibHandle, 'SSL_set_bio');
    @SSL_get_error := GetSslLibProc(FSslLibHandle, 'SSL_get_error');

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

    @SSL_CTX_get_cert_store := GetSslLibProc(FSslLibHandle, 'SSL_CTX_get_cert_store');
    @SSL_CTX_add_client_CA := GetSslLibProc(FSslLibHandle, 'SSL_CTX_add_client_CA');
  end;
end;

class procedure TSSLTools.UnloadSslLibs;
begin
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
end;

{$ENDIF}

end.
