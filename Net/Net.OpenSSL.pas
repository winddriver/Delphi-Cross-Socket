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

{
  OpenSSL 下载:
  https://indy.fulgan.com/SSL/
  https://github.com/leenjewel/openssl_for_ios_and_android

  OpenSSL iOS静态库下载:
  https://indy.fulgan.com/SSL/OpenSSLStaticLibs.7z

  LibreSSL 下载:
  http://ftp.openbsd.org/pub/OpenBSD/LibreSSL/

  Linux下需要安装libssl开发包
  sudo apt-get install libssl-dev
}

// 使用 LibreSSL
// LibreSSL 是 OpenSSL 的一个分支, 由 OpenBSD 维护, 接口与 OpenSSL 兼容
// 目前(2.4.2) 执行效率比 OpenSSL(1.0.2h) 低
{.$DEFINE __LIBRE_SSL__}

// iOS真机必须用openssl的静态库
{$IF defined(IOS) and defined(CPUARM)}
  {$DEFINE __SSL_STATIC__}
{$ENDIF}

interface

uses
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  {$IFDEF POSIX}
  Posix.Base, Posix.Pthread,
  {$ENDIF}
  System.SysUtils, System.SyncObjs;

const
  SSLEAY_DLL =
    {$IFDEF MSWINDOWS}
      {$IFDEF __LIBRE_SSL__}
        'libssl-39.dll'
      {$ELSE}
        'ssleay32.dll'
      {$ENDIF}
    {$ENDIF}
    {$IFDEF POSIX}
      {$IFDEF __SSL_STATIC__}
        'libssl.a'
      {$ELSEIF defined(MACOS)}
        'libssl.dylib'
      {$ELSE}
        'libssl.so'
      {$ENDIF}
    {$ENDIF};

  LIBEAY_DLL =
    {$IFDEF MSWINDOWS}
      {$IFDEF __LIBRE_SSL__}
        'libcrypto-38.dll'
      {$ELSE}
        'libeay32.dll'
      {$ENDIF}
    {$ENDIF}
    {$IFDEF POSIX}
      {$IFDEF __SSL_STATIC__}
        'libcrypto.a'
      {$ELSEIF defined(MACOS)}
        'libcrypto.dylib'
      {$ELSE}
        'libcrypto.so'
      {$ENDIF}
    {$ENDIF};

  {$IFDEF MSWINDOWS}
  _PU = '';
  {$ENDIF}

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
  SSL_ST_BEFORE                               = $4000;
  SSL_ST_OK                                   = $03;
  SSL_ST_RENEGOTIATE                          = ($04 or SSL_ST_INIT);

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
  SSL_OP_SINGLE_ECDH_USE                      = $00080000;
  SSL_OP_SINGLE_DH_USE                        = $00100000;
  SSL_OP_EPHEMERAL_RSA                        = $00200000;
  SSL_OP_CIPHER_SERVER_PREFERENCE             = $00400000;
  SSL_OP_TLS_ROLLBACK_BUG                     = $00800000;
  SSL_OP_NO_SSLv2                             = $01000000;
  SSL_OP_NO_SSLv3                             = $02000000;
  SSL_OP_NO_TLSv1                             = $04000000;
  SSL_OP_NO_TLSv1_2                           = $08000000;
  SSL_OP_NO_TLSv1_1                           = $10000000;
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

  TLS1_VERSION                                = $0301;
  TLS1_VERSION_MAJOR                          = $03;
  TLS1_VERSION_MINOR                          = $01;

  TLS1_1_VERSION                              = $0302;
  TLS1_1_VERSION_MAJOR                        = $03;
  TLS1_1_VERSION_MINOR                        = $02;

  TLS1_2_VERSION                              = $0303;
  TLS1_2_VERSION_MAJOR                        = $03;
  TLS1_2_VERSION_MINOR                        = $03;

  TLS_MAX_VERSION                             = TLS1_2_VERSION;
  TLS_ANY_VERSION                             = $10000;

  DTLS1_VERSION                               = $FEFF;
  DTLS1_2_VERSION                             = $FEFD;
  DTLS_MAX_VERSION                            = DTLS1_2_VERSION;
  DTLS1_VERSION_MAJOR                         = $FE;

  DTLS1_BAD_VER                               = $0100;

  // Special value for method supporting multiple versions
  DTLS_ANY_VERSION                            = $1FFFF;

type
  size_t = NativeUInt;

  {$REGION 'SSL'}
  TSSL_METHOD_st = packed record
    Dummy: array [0..0] of Byte;
  end;
  PSSL_METHOD = ^TSSL_METHOD_st;

  TSSL_CTX_st = packed record
    Dummy: array [0..0] of Byte;
  end;
  PSSL_CTX = ^TSSL_CTX_st;

  TBIO_st = packed record
    Dummy: array [0..0] of Byte;
  end;
  PBIO = ^TBIO_st;
  PPBIO = ^PBIO;

  TSSL_st = packed record
    Dummy: array [0..0] of Byte;
  end;
  PSSL = ^TSSL_st;

  TX509_STORE_CTX_st = packed record
    Dummy: array [0..0] of Byte;
  end;
  PX509_STORE_CTX = ^TX509_STORE_CTX_st;

  TEVP_PKEY_st = packed record
    Dummy: array [0..0] of Byte;
  end;
  PEVP_PKEY = ^TEVP_PKEY_st;
  PPEVP_PKEY = ^PEVP_PKEY;

  TX509_st = packed record
    Dummy: array [0..0] of Byte;
  end;
  PX509 = ^TX509_st;
  PPX509 = ^PX509;

  TX509_STORE_st = packed record
      Dummy : array [0..0] of Byte;
  end;
  PX509_STORE = ^TX509_STORE_st;

  // 0.9.7g, 0.9.8a, 0.9.8e, 1.0.0d
  TASN1_STRING_st = record
    length : Integer;
    type_  : Integer;
    data   : MarshaledAString;
    //* The value of the following field depends on the type being
    //* held.  It is mostly being used for BIT_STRING so if the
    //* input data has a non-zero 'unused bits' value, it will be
    //* handled correctly */
    flags  : Longword;
  end;
  PASN1_STRING       = ^TASN1_STRING_st;
  TASN1_OCTET_STRING = TASN1_STRING_st;
  PASN1_OCTET_STRING = ^TASN1_OCTET_STRING;
  TASN1_BIT_STRING   = TASN1_STRING_st;
  PASN1_BIT_STRING   = ^TASN1_BIT_STRING;

  TSetVerify_cb = function(Ok: Integer; StoreCtx: PX509_STORE_CTX): Integer; cdecl;
  {$ENDREGION}

  {$REGION 'LIBEAY'}
  TCRYPTO_THREADID_st = packed record
    Dummy: array [0..0] of Byte;
  end;
  PCRYPTO_THREADID = ^TCRYPTO_THREADID_st;

  TCRYPTO_dynlock_value_st = record
    Mutex: TCriticalSection;
  end;
  PCRYPTO_dynlock_value = ^TCRYPTO_dynlock_value_st;
  CRYPTO_dynlock_value  = TCRYPTO_dynlock_value_st;

  TBIO_METHOD_st = packed record
    Dummy: array [0..0] of Byte;
  end;
  PBIO_METHOD = ^TBIO_METHOD_st;

  TX509_NAME_st = packed record
    Dummy: array [0..0] of Byte;
  end;
  PX509_NAME = ^TX509_NAME_st;

  TSTACK_st = packed record
    Dummy : array [0..0] of Byte;
  end;
  PSTACK = ^TSTACK_st;

  TASN1_OBJECT_st = packed record
    Dummy : array [0..0] of Byte;
  end;
  PASN1_OBJECT = ^TASN1_OBJECT_st;

  TEC_KEY_st = packed record
    Dummy : array [0..0] of Byte;
  end;
  PEC_KEY = ^TEC_KEY_st;

  TStatLockLockCallback   = procedure(Mode: Integer; N: Integer; const _File: MarshaledAString; Line: Integer); cdecl;
  TStatLockIDCallback     = function: Longword; cdecl;
  TCryptoThreadIDCallback = procedure(ID: PCRYPTO_THREADID) cdecl;

  TDynLockCreateCallback  = function(const _file: MarshaledAString; Line: Integer): PCRYPTO_dynlock_value; cdecl;
  TDynLockLockCallback    = procedure(Mode: Integer; L: PCRYPTO_dynlock_value; _File: MarshaledAString; Line: Integer); cdecl;
  TDynLockDestroyCallback = procedure(L: PCRYPTO_dynlock_value; _File: MarshaledAString; Line: Integer); cdecl;
  pem_password_cb         = function(buf: Pointer; size: Integer; rwflag: Integer; userdata: Pointer): Integer; cdecl;
  {$ENDREGION}

{$IFDEF __SSL_STATIC__}

{$REGION 'SSL-FUNC'}
function SSL_library_init: Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_library_init';
procedure SSL_load_error_strings; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_load_error_strings';

function SSLv23_method: PSSL_METHOD; cdecl;
  external SSLEAY_DLL name _PU + 'SSLv23_method';
function SSLv23_client_method: PSSL_METHOD; cdecl;
  external SSLEAY_DLL name _PU + 'SSLv23_client_method';
function SSLv23_server_method: PSSL_METHOD; cdecl;
  external SSLEAY_DLL name _PU + 'SSLv23_server_method';

function TLSv1_method: PSSL_METHOD; cdecl;
  external SSLEAY_DLL name _PU + 'TLSv1_method';
function TLSv1_client_method: PSSL_METHOD; cdecl;
  external SSLEAY_DLL name _PU + 'TLSv1_client_method';
function TLSv1_server_method: PSSL_METHOD; cdecl;
  external SSLEAY_DLL name _PU + 'TLSv1_server_method';

{$IF not(defined(MACOS) and not defined(IOS))}
function TLSv1_2_method: PSSL_METHOD; cdecl;
  external SSLEAY_DLL name _PU + 'TLSv1_2_method';
{$ENDIF}
function TLSv1_2_client_method: PSSL_METHOD; cdecl;
  external SSLEAY_DLL name _PU + 'TLSv1_2_client_method';
function TLSv1_2_server_method: PSSL_METHOD; cdecl;
  external SSLEAY_DLL name _PU + 'TLSv1_2_server_method';

function SSL_CTX_new(meth: PSSL_METHOD): PSSL_CTX; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_CTX_new';
procedure SSL_CTX_free(ctx: PSSL_CTX); cdecl;
  external SSLEAY_DLL name _PU + 'SSL_CTX_free';
function SSL_CTX_ctrl(ctx: PSSL_CTX; Cmd: Integer; LArg: Integer; PArg: MarshaledAString): Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_CTX_ctrl';
procedure SSL_CTX_set_verify(ctx: PSSL_CTX; mode: Integer; callback: TSetVerify_cb); cdecl;
  external SSLEAY_DLL name _PU + 'SSL_CTX_set_verify';
function SSL_CTX_set_cipher_list(ctx: PSSL_CTX; CipherString: MarshaledAString): Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_CTX_set_cipher_list';
function SSL_CTX_use_PrivateKey(ctx: PSSL_CTX; pkey: PEVP_PKEY): Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_CTX_use_PrivateKey';
function SSL_CTX_use_certificate(ctx: PSSL_CTX; cert: PX509): Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_CTX_use_certificate';
function SSL_CTX_check_private_key(ctx: PSSL_CTX): Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_CTX_check_private_key';

function SSL_new(ctx: PSSL_CTX): PSSL; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_new';
procedure SSL_set_bio(s: PSSL; rbio, wbio: PBIO); cdecl;
  external SSLEAY_DLL name _PU + 'SSL_set_bio';
function SSL_get_peer_certificate(s: PSSL): PX509; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_get_peer_certificate';
function SSL_get_error(s: PSSL; ret_code: Integer): Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_get_error';

function SSL_ctrl(S: PSSL; Cmd: Integer; LArg: Integer; PArg: Pointer): Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_ctrl';

function SSL_shutdown(s: PSSL): Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_shutdown';
procedure SSL_free(s: PSSL); cdecl;
  external SSLEAY_DLL name _PU + 'SSL_free';

procedure SSL_set_connect_state(s: PSSL); cdecl;
  external SSLEAY_DLL name _PU + 'SSL_set_connect_state';
procedure SSL_set_accept_state(s: PSSL); cdecl;
  external SSLEAY_DLL name _PU + 'SSL_set_accept_state';
function SSL_accept(S: PSSL): Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_accept';
function SSL_connect(S: PSSL): Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_connect';
function SSL_do_handshake(S: PSSL): Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_do_handshake';
function SSL_read(s: PSSL; buf: Pointer; num: Integer): Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_read';
function SSL_write(s: PSSL; const buf: Pointer; num: Integer): Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_write';
function SSL_state(s: PSSL): Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_state';
function SSL_pending(s: PSSL): Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_pending';

function SSL_CTX_get_cert_store(const Ctx: PSSL_CTX): PX509_STORE; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_CTX_get_cert_store';
function SSL_CTX_add_client_CA(C: PSSL_CTX; CaCert: PX509): Integer; cdecl;
  external SSLEAY_DLL name _PU + 'SSL_CTX_add_client_CA';
{$ENDREGION}

{$REGION 'LIBEAY-FUNC'}
function SSLeay: Longword; cdecl;
  external LIBEAY_DLL name _PU + 'SSLeay';

function CRYPTO_set_id_callback(callback: TStatLockIDCallback): Integer; cdecl;
  external LIBEAY_DLL name _PU + 'CRYPTO_set_id_callback';

{$IF not(defined(MACOS) and not defined(IOS))}
// MACOS 内置的 OpenSSL 库版本较低(0.9.x)
// CRYPTO_THREADID_set_callback 只有 OpenSSL 1.0 以上版本才有
function CRYPTO_THREADID_set_callback(callback: TCryptoThreadIDCallback): Integer; cdecl;
  external LIBEAY_DLL name _PU + 'CRYPTO_THREADID_set_callback';
procedure CRYPTO_THREADID_set_numeric(id : PCRYPTO_THREADID; val: LongWord); cdecl;
  external LIBEAY_DLL name _PU + 'CRYPTO_THREADID_set_numeric';
procedure CRYPTO_THREADID_set_pointer(id : PCRYPTO_THREADID; ptr: Pointer); cdecl;
  external LIBEAY_DLL name _PU + 'CRYPTO_THREADID_set_pointer';
{$ENDIF}

function CRYPTO_num_locks: Integer; cdecl;
  external LIBEAY_DLL name _PU + 'CRYPTO_num_locks';
procedure CRYPTO_set_locking_callback(callback: TStatLockLockCallback); cdecl;
  external LIBEAY_DLL name _PU + 'CRYPTO_set_locking_callback';
procedure CRYPTO_set_dynlock_create_callback(callback: TDynLockCreateCallBack); cdecl;
  external LIBEAY_DLL name _PU + 'CRYPTO_set_dynlock_create_callback';
procedure CRYPTO_set_dynlock_lock_callback(callback: TDynLockLockCallBack); cdecl;
  external LIBEAY_DLL name _PU + 'CRYPTO_set_dynlock_lock_callback';
procedure CRYPTO_set_dynlock_destroy_callback(callback: TDynLockDestroyCallBack); cdecl;
  external LIBEAY_DLL name _PU + 'CRYPTO_set_dynlock_destroy_callback';
procedure CRYPTO_cleanup_all_ex_data; cdecl;
  external LIBEAY_DLL name _PU + 'CRYPTO_cleanup_all_ex_data';

procedure ERR_remove_state(tid: Cardinal); cdecl;
  external LIBEAY_DLL name _PU + 'ERR_remove_state';

{$IF not(defined(MACOS) and not defined(IOS))}
procedure ERR_remove_thread_state(tid: PCRYPTO_THREADID); cdecl;
  external LIBEAY_DLL name _PU + 'ERR_remove_thread_state';
{$ENDIF}

procedure ERR_free_strings; cdecl;
  external LIBEAY_DLL name _PU + 'ERR_free_strings';
procedure ERR_error_string_n(err: Cardinal; buf: MarshaledAString; len: size_t); cdecl;
  external LIBEAY_DLL name _PU + 'ERR_error_string_n';
function ERR_get_error: Cardinal; cdecl;
  external LIBEAY_DLL name _PU + 'ERR_get_error';
procedure ERR_clear_error; cdecl;
  external LIBEAY_DLL name _PU + 'ERR_clear_error';

procedure EVP_cleanup; cdecl;
  external LIBEAY_DLL name _PU + 'EVP_cleanup';
procedure EVP_PKEY_free(pkey: PEVP_PKEY); cdecl;
  external LIBEAY_DLL name _PU + 'EVP_PKEY_free';

function BIO_new(BioMethods: PBIO_METHOD): PBIO; cdecl;
  external LIBEAY_DLL name _PU + 'BIO_new';
function BIO_ctrl(bp: PBIO; cmd: Integer; larg: Longint; parg: Pointer): Longint; cdecl;
  external LIBEAY_DLL name _PU + 'BIO_ctrl';
function BIO_new_mem_buf(buf: Pointer; len: Integer): PBIO; cdecl;
  external LIBEAY_DLL name _PU + 'BIO_new_mem_buf';
function BIO_free(b: PBIO): Integer; cdecl;
  external LIBEAY_DLL name _PU + 'BIO_free';
function BIO_s_mem: PBIO_METHOD; cdecl;
  external LIBEAY_DLL name _PU + 'BIO_s_mem';
function BIO_read(b: PBIO; Buf: Pointer; Len: Integer): Integer; cdecl;
  external LIBEAY_DLL name _PU + 'BIO_read';
function BIO_write(b: PBIO; Buf: Pointer; Len: Integer): Integer; cdecl;
  external LIBEAY_DLL name _PU + 'BIO_write';

function EC_KEY_new_by_curve_name(nid: Integer): PEC_KEY; cdecl;
  external LIBEAY_DLL name _PU + 'EC_KEY_new_by_curve_name';
procedure EC_KEY_free(key: PEC_KEY); cdecl;
  external LIBEAY_DLL name _PU + 'EC_KEY_free';

function X509_get_issuer_name(cert: PX509): PX509_NAME; cdecl;
  external LIBEAY_DLL name _PU + 'X509_get_issuer_name';
function X509_get_subject_name(cert: PX509): PX509_NAME; cdecl;
  external LIBEAY_DLL name _PU + 'X509_get_subject_name';
procedure X509_free(cert: PX509); cdecl;
  external LIBEAY_DLL name _PU + 'X509_free';
function X509_NAME_print_ex(bout: PBIO; nm: PX509_NAME; indent: Integer; flags: Cardinal): Integer; cdecl;
  external LIBEAY_DLL name _PU + 'X509_NAME_print_ex';
function X509_get_ext_d2i(x: PX509; nid: Integer; var crit, idx: Integer): Pointer; cdecl;
  external LIBEAY_DLL name _PU + 'X509_get_ext_d2i';

function X509_STORE_add_cert(Store: PX509_STORE; Cert: PX509): Integer; cdecl;
  external LIBEAY_DLL name _PU + 'X509_STORE_add_cert';

function sk_num(stack: PSTACK): Integer; cdecl;
  external LIBEAY_DLL name _PU + 'sk_num';
function sk_pop(stack: PSTACK): Pointer; cdecl;
  external LIBEAY_DLL name _PU + 'sk_pop';

function ASN1_BIT_STRING_get_bit(a: PASN1_BIT_STRING; n: Integer): Integer; cdecl;
  external LIBEAY_DLL name _PU + 'ASN1_BIT_STRING_get_bit';
function OBJ_obj2nid(o: PASN1_OBJECT): Integer; cdecl;
  external LIBEAY_DLL name _PU + 'OBJ_obj2nid';
function OBJ_nid2sn(n: Integer): MarshaledAString; cdecl;
  external LIBEAY_DLL name _PU + 'OBJ_nid2sn';
function ASN1_STRING_data(x: PASN1_STRING): Pointer; cdecl;
  external LIBEAY_DLL name _PU + 'ASN1_STRING_data';
function PEM_read_bio_X509(bp: PBIO; x: PPX509; cb: pem_password_cb; u: Pointer): PX509; cdecl;
  external LIBEAY_DLL name _PU + 'PEM_read_bio_X509';
function PEM_read_bio_X509_AUX(bp: PBIO; x: PPX509; cb: pem_password_cb; u: Pointer): PX509; cdecl;
  external LIBEAY_DLL name _PU + 'PEM_read_bio_X509_AUX';
function PEM_read_bio_PrivateKey(bp: PBIO; x: PPEVP_PKEY; cb: pem_password_cb; u: Pointer): PEVP_PKEY; cdecl;
  external LIBEAY_DLL name _PU + 'PEM_read_bio_PrivateKey';

procedure OPENSSL_add_all_algorithms_noconf; cdecl;
  external LIBEAY_DLL name _PU + 'OPENSSL_add_all_algorithms_noconf';
procedure OPENSSL_add_all_algorithms_conf; cdecl;
  external LIBEAY_DLL name _PU + 'OPENSSL_add_all_algorithms_conf';

procedure OpenSSL_add_all_ciphers; cdecl;
  external LIBEAY_DLL name _PU + 'OpenSSL_add_all_ciphers';
procedure OpenSSL_add_all_digests; cdecl;
  external LIBEAY_DLL name _PU + 'OpenSSL_add_all_digests';
{$ENDREGION}

{$ENDIF}

function SSL_CTX_need_tmp_RSA(ctx: PSSL_CTX): Integer; inline;
function SSL_CTX_set_tmp_rsa(ctx: PSSL_CTX; rsa: MarshaledAString): Integer; inline;
function SSL_CTX_set_tmp_dh(ctx: PSSL_CTX; dh: MarshaledAString): Integer; inline;
function SSL_CTX_set_tmp_ecdh(ctx: PSSL_CTX; ecdh: PEC_KEY): Integer; inline;
function SSL_CTX_add_extra_chain_cert(ctx: PSSL_CTX; cert: PX509): Integer; inline;
function SSL_need_tmp_RSA(ssl: PSSL): Integer; inline;
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

function SSL_is_init_finished(s: PSSL): Boolean; inline;

function ssl_is_fatal_error(ssl_error: Integer): Boolean;
function ssl_error_message(ssl_error: Integer): string;

function sk_ASN1_OBJECT_num(stack: PSTACK): Integer; inline;
function sk_GENERAL_NAME_num(stack: PSTACK): Integer; inline;
function sk_GENERAL_NAME_pop(stack: PSTACK): Pointer; inline;

type
  ESsl = class(Exception);
  ESslInvalidLib = class(ESsl);
  ESslInvalidProc = class(ESsl);

  {$REGION 'SSLTools'}
  TSSLTools = class
  private class var
    FRef: Integer;
  public
    class procedure LoadSSL;
    class procedure UnloadSSL;
    class function SSLVersion: Longword;
    class function NewCTX(meth: PSSL_METHOD = nil): PSSL_CTX;
    class procedure FreeCTX(var AContext: PSSL_CTX);

    class procedure SetCertificate(AContext: PSSL_CTX; ACertBuf: Pointer; ACertBufSize: Integer); overload;
    class procedure SetCertificate(AContext: PSSL_CTX; const ACertStr: string); overload;
    class procedure SetCertificateFile(AContext: PSSL_CTX; const ACertFile: string);

    class procedure SetPrivateKey(AContext: PSSL_CTX; APKeyBuf: Pointer; APKeyBufSize: Integer); overload;
    class procedure SetPrivateKey(AContext: PSSL_CTX; const APKeyStr: string); overload;
    class procedure SetPrivateKeyFile(AContext: PSSL_CTX; const APKeyFile: string);
  end;
  {$ENDREGION}

{$IFNDEF __SSL_STATIC__}

var
  _SslLibPath: string;
  _SslLibHandle: THandle;
  _CryptoLibHandle: THandle;

  {$REGION 'SSL-FUNC'}
  SSL_library_init: function: Integer; cdecl;
  SSL_load_error_strings: procedure; cdecl;

  SSLv23_method: function: PSSL_METHOD; cdecl;
  SSLv23_client_method: function: PSSL_METHOD; cdecl;
  SSLv23_server_method: function: PSSL_METHOD; cdecl;

  TLSv1_method: function: PSSL_METHOD; cdecl;
  TLSv1_client_method: function: PSSL_METHOD; cdecl;
  TLSv1_server_method: function: PSSL_METHOD; cdecl;

  TLSv1_2_method: function: PSSL_METHOD; cdecl;
  TLSv1_2_client_method: function: PSSL_METHOD; cdecl;
  TLSv1_2_server_method: function : PSSL_METHOD; cdecl;

  SSL_CTX_new: function(meth: PSSL_METHOD): PSSL_CTX; cdecl;
  SSL_CTX_free: procedure(ctx: PSSL_CTX); cdecl;
  SSL_CTX_ctrl: function(ctx: PSSL_CTX; Cmd: Integer; LArg: Integer; PArg: MarshaledAString): Integer; cdecl;
  SSL_CTX_set_verify: procedure(ctx: PSSL_CTX; mode: Integer; callback: TSetVerify_cb); cdecl;
  SSL_CTX_set_cipher_list: function(ctx: PSSL_CTX; CipherString: MarshaledAString): Integer; cdecl;
  SSL_CTX_use_PrivateKey: function(ctx: PSSL_CTX; pkey: PEVP_PKEY): Integer; cdecl;
  SSL_CTX_use_certificate: function(ctx: PSSL_CTX; cert: PX509): Integer; cdecl;
  SSL_CTX_check_private_key: function(ctx: PSSL_CTX): Integer; cdecl;

  SSL_new: function(ctx: PSSL_CTX): PSSL; cdecl;
  SSL_set_bio: procedure(s: PSSL; rbio, wbio: PBIO); cdecl;
  SSL_get_peer_certificate: function(s: PSSL): PX509; cdecl;
  SSL_get_error: function(s: PSSL; ret_code: Integer): Integer; cdecl;

  SSL_ctrl: function(S: PSSL; Cmd: Integer; LArg: Integer; PArg: Pointer): Integer; cdecl;

  SSL_shutdown: function(s: PSSL): Integer; cdecl;
  SSL_free: procedure(s: PSSL); cdecl;

  SSL_set_connect_state: procedure(s: PSSL); cdecl;
  SSL_set_accept_state: procedure(s: PSSL); cdecl;
  SSL_accept: function(S: PSSL): Integer; cdecl;
  SSL_connect: function(S: PSSL): Integer; cdecl;
  SSL_do_handshake: function(S: PSSL): Integer; cdecl;
  SSL_read: function(s: PSSL; buf: Pointer; num: Integer): Integer; cdecl;
  SSL_write: function(s: PSSL; const buf: Pointer; num: Integer): Integer; cdecl;
  SSL_state: function(s: PSSL): Integer; cdecl;
  SSL_pending: function(s: PSSL): Integer; cdecl;

  SSL_CTX_get_cert_store: function(const Ctx: PSSL_CTX): PX509_STORE; cdecl;
  SSL_CTX_add_client_CA: function(C: PSSL_CTX; CaCert: PX509): Integer; cdecl;
  {$ENDREGION}

  {$REGION 'LIBEAY-FUNC'}
  SSLeay: function: Longword; cdecl;

  CRYPTO_set_id_callback: function(callback: TStatLockIDCallback): Integer; cdecl;

  {$IF not(defined(MACOS) and not defined(IOS))}
  // MACOS 内置的 OpenSSL 库版本较低(0.9.x)
  // CRYPTO_THREADID_set_callback 只有 OpenSSL 1.0 以上版本才有
  CRYPTO_THREADID_set_callback: function(callback: TCryptoThreadIDCallback): Integer; cdecl;
  CRYPTO_THREADID_set_numeric: procedure(id : PCRYPTO_THREADID; val: LongWord); cdecl;
  CRYPTO_THREADID_set_pointer: procedure(id : PCRYPTO_THREADID; ptr: Pointer); cdecl;
  {$ENDIF}

  CRYPTO_num_locks: function: Integer; cdecl;
  CRYPTO_set_locking_callback: procedure(callback: TStatLockLockCallback); cdecl;
  CRYPTO_set_dynlock_create_callback: procedure(callback: TDynLockCreateCallBack); cdecl;
  CRYPTO_set_dynlock_lock_callback: procedure(callback: TDynLockLockCallBack); cdecl;
  CRYPTO_set_dynlock_destroy_callback: procedure(callback: TDynLockDestroyCallBack); cdecl;
  CRYPTO_cleanup_all_ex_data: procedure; cdecl;

  ERR_remove_state: procedure(tid: Cardinal); cdecl;

  {$IF not(defined(MACOS) and not defined(IOS))}
  ERR_remove_thread_state: procedure(tid: PCRYPTO_THREADID); cdecl;
  {$ENDIF}

  ERR_free_strings: procedure; cdecl;
  ERR_error_string_n: procedure(err: Cardinal; buf: MarshaledAString; len: size_t); cdecl;
  ERR_get_error: function: Cardinal; cdecl;
  ERR_clear_error: procedure; cdecl;

  EVP_cleanup: procedure; cdecl;
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

  sk_num: function(stack: PSTACK): Integer; cdecl;
  sk_pop: function(stack: PSTACK): Pointer; cdecl;

  ASN1_BIT_STRING_get_bit: function(a: PASN1_BIT_STRING; n: Integer): Integer; cdecl;
  OBJ_obj2nid: function(o: PASN1_OBJECT): Integer; cdecl;
  OBJ_nid2sn: function(n: Integer): MarshaledAString; cdecl;
  ASN1_STRING_data: function(x: PASN1_STRING): Pointer; cdecl;
  PEM_read_bio_X509: function(bp: PBIO; x: PPX509; cb: pem_password_cb; u: Pointer): PX509; cdecl;
  PEM_read_bio_X509_AUX: function(bp: PBIO; x: PPX509; cb: pem_password_cb; u: Pointer): PX509; cdecl;
  PEM_read_bio_PrivateKey: function(bp: PBIO; x: PPEVP_PKEY; cb: pem_password_cb; u: Pointer): PEVP_PKEY; cdecl;

  OPENSSL_add_all_algorithms_noconf: procedure; cdecl;
  OPENSSL_add_all_algorithms_conf: procedure; cdecl;

  OpenSSL_add_all_ciphers: procedure; cdecl;
  OpenSSL_add_all_digests: procedure; cdecl;
  {$ENDREGION}

{$ENDIF}

implementation

uses
  System.IOUtils;

var
  _FSslLocks: TArray<TCriticalSection>;
  _FSslVersion: Longword;

function SSL_CTX_need_tmp_RSA(ctx: PSSL_CTX): Integer;
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

function SSL_need_tmp_RSA(ssl: PSSL): Integer;
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

function sk_ASN1_OBJECT_num(stack: PSTACK): Integer;
begin
  Result := sk_num(stack);
end;

function sk_GENERAL_NAME_num(stack: PSTACK): Integer;
begin
  Result := sk_num(stack);
end;

function sk_GENERAL_NAME_pop(stack: PSTACK): Pointer;
begin
  Result := sk_pop(stack);
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

function SSL_is_init_finished(s: PSSL): Boolean;
begin
  Result := (SSL_state(s) = SSL_ST_OK);
end;

function ssl_is_fatal_error(ssl_error: Integer): Boolean;
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

function ssl_error_message(ssl_error: Integer): string;
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

function set_id_callback: Longword; cdecl;
begin
  Result := GetCurrentThreadID;
end;

{$IF not(defined(MACOS) and not defined(IOS))}
procedure ssl_threadid_callback(ID : PCRYPTO_THREADID); cdecl;
begin
  CRYPTO_THREADID_set_numeric(ID, GetCurrentThreadId);
end;
{$ENDIF}

procedure ssl_lock_callback(Mode, N: Integer;
  const _File: MarshaledAString; Line: Integer); cdecl;
begin
	if(mode and CRYPTO_LOCK <> 0) then
    _FSslLocks[N].Enter
	else
    _FSslLocks[N].Leave;
end;

procedure ssl_lock_dyn_callback(Mode: Integer;
  L: PCRYPTO_dynlock_value; _File: MarshaledAString; Line: Integer); cdecl;
begin
  if (Mode and CRYPTO_LOCK <> 0) then
    L.Mutex.Enter
  else
    L.Mutex.Leave;
end;

function ssl_lock_dyn_create_callback(
  const _file: MarshaledAString; Line: Integer): PCRYPTO_dynlock_value; cdecl;
begin
  New(Result);
  Result.Mutex := TCriticalSection.Create;
end;

procedure ssl_lock_dyn_destroy_callback(
  L: PCRYPTO_dynlock_value; _File: MarshaledAString; Line: Integer); cdecl;
begin
  L.Mutex.Free;
  Dispose(L);
end;

{$IFNDEF __SSL_STATIC__}

function GetSslLibPath: string;
begin
  if (_SslLibPath <> '') then
    Result := IncludeTrailingPathDelimiter(_SslLibPath)
  else
    Result := _SslLibPath;
end;

function LoadSslLib(const ALibName: string): THandle;
begin
  Result := SafeLoadLibrary(GetSslLibPath + ALibName);
  if (Result = 0) then
    raise ESslInvalidLib.CreateFmt('无效的SSL库: %s', [ALibName]);
end;

function GetSslLibProc(const ALibHandle: THandle; const AProcName: string): Pointer;
begin
  Result := GetProcAddress(ALibHandle, PChar(AProcName));
  if (Result = nil) then
    raise ESslInvalidProc.CreateFmt('无效的SSL接口函数: %s', [AProcName]);
end;

procedure LoadSslLibs;
begin
  if (_SslLibHandle = 0) then
  begin
    _SslLibHandle := LoadSslLib(SSLEAY_DLL);

    @SSL_library_init := GetSslLibProc(_SslLibHandle, 'SSL_library_init');
    @SSL_load_error_strings := GetSslLibProc(_SslLibHandle, 'SSL_load_error_strings');

    @SSLv23_method := GetSslLibProc(_SslLibHandle, 'SSLv23_method');
    @SSLv23_client_method := GetSslLibProc(_SslLibHandle, 'SSLv23_client_method');
    @SSLv23_server_method := GetSslLibProc(_SslLibHandle, 'SSLv23_server_method');

    @TLSv1_method := GetSslLibProc(_SslLibHandle, 'TLSv1_method');
    @TLSv1_client_method := GetSslLibProc(_SslLibHandle, 'TLSv1_client_method');
    @TLSv1_server_method := GetSslLibProc(_SslLibHandle, 'TLSv1_server_method');

    {$IF not(defined(MACOS) and not defined(IOS))}
    @TLSv1_2_method := GetSslLibProc(_SslLibHandle, 'TLSv1_2_method');
    @TLSv1_2_client_method := GetSslLibProc(_SslLibHandle, 'TLSv1_2_client_method');
    @TLSv1_2_server_method := GetSslLibProc(_SslLibHandle, 'TLSv1_2_server_method');
    {$ENDIF}

    @SSL_CTX_new := GetSslLibProc(_SslLibHandle, 'SSL_CTX_new');
    @SSL_CTX_free := GetSslLibProc(_SslLibHandle, 'SSL_CTX_free');
    @SSL_CTX_ctrl := GetSslLibProc(_SslLibHandle, 'SSL_CTX_ctrl');
    @SSL_CTX_set_verify := GetSslLibProc(_SslLibHandle, 'SSL_CTX_set_verify');
    @SSL_CTX_set_cipher_list := GetSslLibProc(_SslLibHandle, 'SSL_CTX_set_cipher_list');
    @SSL_CTX_use_PrivateKey := GetSslLibProc(_SslLibHandle, 'SSL_CTX_use_PrivateKey');
    @SSL_CTX_use_certificate := GetSslLibProc(_SslLibHandle, 'SSL_CTX_use_certificate');
    @SSL_CTX_check_private_key := GetSslLibProc(_SslLibHandle, 'SSL_CTX_check_private_key');

    @SSL_new := GetSslLibProc(_SslLibHandle, 'SSL_new');
    @SSL_set_bio := GetSslLibProc(_SslLibHandle, 'SSL_set_bio');
    @SSL_get_peer_certificate := GetSslLibProc(_SslLibHandle, 'SSL_get_peer_certificate');
    @SSL_get_error := GetSslLibProc(_SslLibHandle, 'SSL_get_error');

    @SSL_ctrl := GetSslLibProc(_SslLibHandle, 'SSL_ctrl');

    @SSL_shutdown := GetSslLibProc(_SslLibHandle, 'SSL_shutdown');
    @SSL_free := GetSslLibProc(_SslLibHandle, 'SSL_free');

    @SSL_set_connect_state := GetSslLibProc(_SslLibHandle, 'SSL_set_connect_state');
    @SSL_set_accept_state := GetSslLibProc(_SslLibHandle, 'SSL_set_accept_state');
    @SSL_accept := GetSslLibProc(_SslLibHandle, 'SSL_accept');
    @SSL_connect := GetSslLibProc(_SslLibHandle, 'SSL_connect');
    @SSL_do_handshake := GetSslLibProc(_SslLibHandle, 'SSL_do_handshake');
    @SSL_read := GetSslLibProc(_SslLibHandle, 'SSL_read');
    @SSL_write := GetSslLibProc(_SslLibHandle, 'SSL_write');
    @SSL_state := GetSslLibProc(_SslLibHandle, 'SSL_state');
    @SSL_pending := GetSslLibProc(_SslLibHandle, 'SSL_pending');

    @SSL_CTX_get_cert_store := GetSslLibProc(_SslLibHandle, 'SSL_CTX_get_cert_store');
    @SSL_CTX_add_client_CA := GetSslLibProc(_SslLibHandle, 'SSL_CTX_add_client_CA');
  end;

  if (_CryptoLibHandle = 0) then
  begin
    _CryptoLibHandle := LoadSslLib(LIBEAY_DLL);

    @SSLeay := GetSslLibProc(_CryptoLibHandle, 'SSLeay');

    @CRYPTO_set_id_callback := GetSslLibProc(_CryptoLibHandle, 'CRYPTO_set_id_callback');

    {$IF not(defined(MACOS) and not defined(IOS))}
    // MACOS 内置的 OpenSSL 库版本较低(0.9.x)
    // CRYPTO_THREADID_set_callback 只有 OpenSSL 1.0 以上版本才有
    @CRYPTO_THREADID_set_callback := GetSslLibProc(_CryptoLibHandle, 'CRYPTO_THREADID_set_callback');
    @CRYPTO_THREADID_set_numeric := GetSslLibProc(_CryptoLibHandle, 'CRYPTO_THREADID_set_numeric');
    @CRYPTO_THREADID_set_pointer := GetSslLibProc(_CryptoLibHandle, 'CRYPTO_THREADID_set_pointer');
    {$ENDIF}

    @CRYPTO_num_locks := GetSslLibProc(_CryptoLibHandle, 'CRYPTO_num_locks');
    @CRYPTO_set_locking_callback := GetSslLibProc(_CryptoLibHandle, 'CRYPTO_set_locking_callback');
    @CRYPTO_set_dynlock_create_callback := GetSslLibProc(_CryptoLibHandle, 'CRYPTO_set_dynlock_create_callback');
    @CRYPTO_set_dynlock_lock_callback := GetSslLibProc(_CryptoLibHandle, 'CRYPTO_set_dynlock_lock_callback');
    @CRYPTO_set_dynlock_destroy_callback := GetSslLibProc(_CryptoLibHandle, 'CRYPTO_set_dynlock_destroy_callback');
    @CRYPTO_cleanup_all_ex_data := GetSslLibProc(_CryptoLibHandle, 'CRYPTO_cleanup_all_ex_data');

    @ERR_remove_state := GetSslLibProc(_CryptoLibHandle, 'ERR_remove_state');

    {$IF not(defined(MACOS) and not defined(IOS))}
    @ERR_remove_thread_state := GetSslLibProc(_CryptoLibHandle, 'ERR_remove_thread_state');
    {$ENDIF}

    @ERR_free_strings := GetSslLibProc(_CryptoLibHandle, 'ERR_free_strings');
    @ERR_error_string_n := GetSslLibProc(_CryptoLibHandle, 'ERR_error_string_n');
    @ERR_get_error := GetSslLibProc(_CryptoLibHandle, 'ERR_get_error');
    @ERR_clear_error := GetSslLibProc(_CryptoLibHandle, 'ERR_clear_error');

    @EVP_cleanup := GetSslLibProc(_CryptoLibHandle, 'EVP_cleanup');
    @EVP_PKEY_free := GetSslLibProc(_CryptoLibHandle, 'EVP_PKEY_free');

    @BIO_new := GetSslLibProc(_CryptoLibHandle, 'BIO_new');
    @BIO_ctrl := GetSslLibProc(_CryptoLibHandle, 'BIO_ctrl');
    @BIO_new_mem_buf := GetSslLibProc(_CryptoLibHandle, 'BIO_new_mem_buf');
    @BIO_free := GetSslLibProc(_CryptoLibHandle, 'BIO_free');
    @BIO_s_mem := GetSslLibProc(_CryptoLibHandle, 'BIO_s_mem');
    @BIO_read := GetSslLibProc(_CryptoLibHandle, 'BIO_read');
    @BIO_write := GetSslLibProc(_CryptoLibHandle, 'BIO_write');

    @EC_KEY_new_by_curve_name := GetSslLibProc(_CryptoLibHandle, 'EC_KEY_new_by_curve_name');
    @EC_KEY_free := GetSslLibProc(_CryptoLibHandle, 'EC_KEY_free');

    @X509_get_issuer_name := GetSslLibProc(_CryptoLibHandle, 'X509_get_issuer_name');
    @X509_get_subject_name := GetSslLibProc(_CryptoLibHandle, 'X509_get_subject_name');
    @X509_free := GetSslLibProc(_CryptoLibHandle, 'X509_free');
    @X509_NAME_print_ex := GetSslLibProc(_CryptoLibHandle, 'X509_NAME_print_ex');
    @X509_get_ext_d2i := GetSslLibProc(_CryptoLibHandle, 'X509_get_ext_d2i');

    @X509_STORE_add_cert := GetSslLibProc(_CryptoLibHandle, 'X509_STORE_add_cert');

    @sk_num := GetSslLibProc(_CryptoLibHandle, 'sk_num');
    @sk_pop := GetSslLibProc(_CryptoLibHandle, 'sk_pop');

    @ASN1_BIT_STRING_get_bit := GetSslLibProc(_CryptoLibHandle, 'ASN1_BIT_STRING_get_bit');
    @OBJ_obj2nid := GetSslLibProc(_CryptoLibHandle, 'OBJ_obj2nid');
    @OBJ_nid2sn := GetSslLibProc(_CryptoLibHandle, 'OBJ_nid2sn');
    @ASN1_STRING_data := GetSslLibProc(_CryptoLibHandle, 'ASN1_STRING_data');
    @PEM_read_bio_X509 := GetSslLibProc(_CryptoLibHandle, 'PEM_read_bio_X509');
    @PEM_read_bio_X509_AUX := GetSslLibProc(_CryptoLibHandle, 'PEM_read_bio_X509_AUX');
    @PEM_read_bio_PrivateKey := GetSslLibProc(_CryptoLibHandle, 'PEM_read_bio_PrivateKey');

    @OPENSSL_add_all_algorithms_noconf := GetSslLibProc(_CryptoLibHandle, 'OPENSSL_add_all_algorithms_noconf');
    @OPENSSL_add_all_algorithms_conf := GetSslLibProc(_CryptoLibHandle, 'OPENSSL_add_all_algorithms_conf');

    @OpenSSL_add_all_ciphers := GetSslLibProc(_CryptoLibHandle, 'OpenSSL_add_all_ciphers');
    @OpenSSL_add_all_digests := GetSslLibProc(_CryptoLibHandle, 'OpenSSL_add_all_digests');
  end;
end;

procedure UnloadSslLibs;
begin
  if (_SslLibHandle <> 0) then
  begin
    FreeLibrary(_SslLibHandle);
    _SslLibHandle := 0;
  end;

  if (_CryptoLibHandle <> 0) then
  begin
    FreeLibrary(_CryptoLibHandle);
    _CryptoLibHandle := 0;
  end;
end;

{$ENDIF}

procedure SslInit;
var
  LNumberOfLocks, I: Integer;
begin
  SSL_library_init();
  OPENSSL_add_all_algorithms_noconf;
  SSL_load_error_strings();

  _FSslVersion := SSLeay();

  LNumberOfLocks := CRYPTO_num_locks();
	if(LNumberOfLocks > 0) then
  begin
    SetLength(_FSslLocks, LNumberOfLocks);
    for I := Low(_FSslLocks) to High(_FSslLocks) do
      _FSslLocks[I] := TCriticalSection.Create;
	end;

	CRYPTO_set_locking_callback(ssl_lock_callback);
  {$IF defined(MACOS) and not defined(IOS)}
  CRYPTO_set_id_callback(set_id_callback);
  {$ELSE}
  CRYPTO_THREADID_set_callback(ssl_threadid_callback);
  {$ENDIF}
end;

procedure SslUninit;
var
  I: Integer;
begin
	CRYPTO_set_locking_callback(nil);

  CRYPTO_cleanup_all_ex_data();
  {$IF defined(MACOS) and not defined(IOS)}
  ERR_remove_state(0);
  {$ELSE}
  ERR_remove_thread_state(nil);
  {$ENDIF}
  ERR_clear_error();
  ERR_free_strings();
  EVP_cleanup();

  for I := Low(_FSslLocks) to High(_FSslLocks) do
    _FSslLocks[I].Free;
  _FSslLocks := nil;
end;

{ TSSLTools }

class function TSSLTools.NewCTX(meth: PSSL_METHOD): PSSL_CTX;
begin
  if (meth = nil) then
    meth := SSLv23_method();
  Result := SSL_CTX_new(meth);
end;

class function TSSLTools.SSLVersion: Longword;
begin
  Result := _FSslVersion;
end;

class procedure TSSLTools.FreeCTX(var AContext: PSSL_CTX);
begin
  SSL_CTX_free(AContext);
  AContext := nil;
end;

class procedure TSSLTools.LoadSSL;
begin
  if (TInterlocked.Increment(FRef) <> 1) then Exit;

  {$IFNDEF __SSL_STATIC__}
  LoadSslLibs;
  {$ENDIF}

  SslInit;
end;

class procedure TSSLTools.UnloadSSL;
begin
  if (TInterlocked.Decrement(FRef) <> 0) then Exit;

  SslUninit;

  {$IFNDEF __SSL_STATIC__}
  UnloadSslLibs;
  {$ENDIF}
end;

class procedure TSSLTools.SetCertificate(AContext: PSSL_CTX; ACertBuf: Pointer;
  ACertBufSize: Integer);
var
  bio_cert: PBIO;
  ssl_cert: PX509;
  store: PX509_STORE;
begin
	bio_cert := BIO_new_mem_buf(ACertBuf, ACertBufSize);
  if (bio_cert = nil) then
    raise ESsl.Create('分配证书缓存失败');

	ssl_cert := PEM_read_bio_X509_AUX(bio_cert, nil, nil, nil);
  if (ssl_cert = nil) then
    raise ESsl.Create('读取证书数据失败');

	if (SSL_CTX_use_certificate(AContext, ssl_cert) <= 0) then
    raise ESsl.Create('使用证书失败');

	X509_free(ssl_cert);

  store := SSL_CTX_get_cert_store(AContext);
  if (store = nil) then
    raise ESsl.Create('获取证书仓库失败');

  // 将证书链中剩余的证书添加到仓库中
  // 有完整证书链在 ssllabs.com 评分中才能评为 A
  while not BIO_eof(bio_cert) do
  begin
  	ssl_cert := PEM_read_bio_X509(bio_cert, nil, nil, nil);
    if (ssl_cert = nil) then
      raise ESsl.Create('读取证书数据失败');

    if (X509_STORE_add_cert(store, ssl_cert) <= 0) then
      raise ESsl.Create('添加证书到仓库失败');

  	X509_free(ssl_cert);
  end;

	BIO_free(bio_cert);
end;

class procedure TSSLTools.SetCertificate(AContext: PSSL_CTX;
  const ACertStr: string);
var
  LCertBytes: TBytes;
begin
  LCertBytes := TEncoding.ANSI.GetBytes(ACertStr);
  SetCertificate(AContext, Pointer(LCertBytes), Length(LCertBytes));
end;

class procedure TSSLTools.SetCertificateFile(AContext: PSSL_CTX;
  const ACertFile: string);
var
  LCertBytes: TBytes;
begin
  LCertBytes := TFile.ReadAllBytes(ACertFile);
  SetCertificate(AContext, Pointer(LCertBytes), Length(LCertBytes));
end;

class procedure TSSLTools.SetPrivateKey(AContext: PSSL_CTX; APKeyBuf: Pointer;
  APKeyBufSize: Integer);
var
  bio_pkey: PBIO;
  ssl_pkey: PEVP_PKEY;
begin
	bio_pkey := BIO_new_mem_buf(APKeyBuf, APKeyBufSize);
  if (bio_pkey = nil) then
    raise ESsl.Create('分配私钥缓存失败');

	ssl_pkey := PEM_read_bio_PrivateKey(bio_pkey, nil, nil, nil);
  if (ssl_pkey = nil) then
    raise ESsl.Create('读取私钥数据失败');

	if (SSL_CTX_use_PrivateKey(AContext, ssl_pkey) <= 0) then
    raise ESsl.Create('使用私钥失败');

	EVP_PKEY_free(ssl_pkey);
	BIO_free(bio_pkey);

  if (SSL_CTX_check_private_key(AContext) <= 0) then
    raise ESsl.Create('私钥与证书的公钥不匹配');
end;

class procedure TSSLTools.SetPrivateKey(AContext: PSSL_CTX;
  const APKeyStr: string);
var
  LPKeyBytes: TBytes;
begin
  LPKeyBytes := TEncoding.ANSI.GetBytes(APKeyStr);
  SetPrivateKey(AContext, Pointer(LPKeyBytes), Length(LPKeyBytes));
end;

class procedure TSSLTools.SetPrivateKeyFile(AContext: PSSL_CTX;
  const APKeyFile: string);
var
  LPKeyBytes: TBytes;
begin
  LPKeyBytes := TFile.ReadAllBytes(APKeyFile);
  SetPrivateKey(AContext, Pointer(LPKeyBytes), Length(LPKeyBytes));
end;

end.
