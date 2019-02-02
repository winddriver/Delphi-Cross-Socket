{ ****************************************************************************** }
{                                                                                }
{ Delphi cross platform socket library                                           }
{                                                                                }
{ Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                             }
{                                                                                }
{ Homepage: https://github.com/winddriver/Delphi-Cross-Socket                    }
{                                                                                }
{ ****************************************************************************** }
unit Net.MbedTls;

{
 MbedTls 库编译说明

 > Windows
 用 C++ Builder 打开 mbedtls.cbproj 工程文件
 Win32编译时一定要设置 Use 'classic' Borland compiler 为 true
 Win64编译的 Release 目标文件链接到 Delphi 中时, aes.o 会报告错误的文件格式
 使用 Debug 版本的 aes.o 代替则不会报错, 测试了 C++ Builder 10.2.3 和 10.3 生成的 aes.o 文件均有该问题

 > Linux iOS Android
 使用 Make 命令进行编译
}

interface

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
  System.Win.Crtl,
{$ENDIF}
  System.SysUtils;

// C 语言中枚举类型大小为 4 字节
{$Z4}

const
{$IF defined(WIN32)}
  _PU = '_';
{$ELSE}
  _PU = '';
{$ENDIF}

{$IF defined(WIN32)}
  {$DEFINE __HAS_MBED_TLS_OBJ__}
{$ELSEIF defined(WIN64)}
  {$DEFINE __HAS_MBED_TLS_O__}
{$ELSE} // POSIX
  {$DEFINE __HAS_MBED_TLS_LIB__}
{$ENDIF}

{$IFDEF __HAS_MBED_TLS_LIB__}
  {$IF defined(IOS) or defined(ANDROID)}
    LIB_MBED_CRYPTO = 'libmbedtls.a';
    LIB_MBED_TLS    = 'libmbedtls.a';
    LIB_MBED_X509   = 'libmbedtls.a';
  {$ELSEIF defined(OSX)}
    LIB_MBED_CRYPTO = 'libmbedcrypto.dylib';
    LIB_MBED_TLS    = 'libmbedtls.dylib';
    LIB_MBED_X509   = 'libmbedx509.dylib';
  {$ELSE} // LINUX
    LIB_MBED_CRYPTO = 'libmbedcrypto.so';
    LIB_MBED_TLS    = 'libmbedtls.so';
    LIB_MBED_X509   = 'libmbedx509.so';
  {$ENDIF}
{$ENDIF}

{$REGION 'MbedTls定义'}
const
  MBEDTLS_SSL_VERIFY_DATA_MAX_LEN = 36;
  MBEDTLS_ENTROPY_MAX_SOURCES     = 20; // *< Maximum number of sources supported
  MBEDTLS_HAVEGE_COLLECT_SIZE     = 1024;
  DEBUG_LEVEL                     = 0;

  MBEDTLS_TLS_RSA_WITH_NULL_MD5                         = $01;
  MBEDTLS_TLS_RSA_WITH_NULL_SHA                         = $02;
  MBEDTLS_TLS_RSA_WITH_RC4_128_MD5                      = $04;
  MBEDTLS_TLS_RSA_WITH_RC4_128_SHA                      = $05;
  MBEDTLS_TLS_RSA_WITH_DES_CBC_SHA                      = $09;
  MBEDTLS_TLS_RSA_WITH_3DES_EDE_CBC_SHA                 = $0A;
  MBEDTLS_TLS_DHE_RSA_WITH_DES_CBC_SHA                  = $15;
  MBEDTLS_TLS_DHE_RSA_WITH_3DES_EDE_CBC_SHA             = $16;
  MBEDTLS_TLS_PSK_WITH_NULL_SHA                         = $2C;
  MBEDTLS_TLS_DHE_PSK_WITH_NULL_SHA                     = $2D;
  MBEDTLS_TLS_RSA_PSK_WITH_NULL_SHA                     = $2E;
  MBEDTLS_TLS_RSA_WITH_AES_128_CBC_SHA                  = $2F;
  MBEDTLS_TLS_DHE_RSA_WITH_AES_128_CBC_SHA              = $33;
  MBEDTLS_TLS_RSA_WITH_AES_256_CBC_SHA                  = $35;
  MBEDTLS_TLS_DHE_RSA_WITH_AES_256_CBC_SHA              = $39;
  MBEDTLS_TLS_RSA_WITH_NULL_SHA256                      = $3B;
  MBEDTLS_TLS_RSA_WITH_AES_128_CBC_SHA256               = $3C;
  MBEDTLS_TLS_RSA_WITH_AES_256_CBC_SHA256               = $3D;
  MBEDTLS_TLS_RSA_WITH_CAMELLIA_128_CBC_SHA             = $41;
  MBEDTLS_TLS_DHE_RSA_WITH_CAMELLIA_128_CBC_SHA         = $45;
  MBEDTLS_TLS_DHE_RSA_WITH_AES_128_CBC_SHA256           = $67;
  MBEDTLS_TLS_DHE_RSA_WITH_AES_256_CBC_SHA256           = $6B;
  MBEDTLS_TLS_RSA_WITH_CAMELLIA_256_CBC_SHA             = $84;
  MBEDTLS_TLS_DHE_RSA_WITH_CAMELLIA_256_CBC_SHA         = $88;
  MBEDTLS_TLS_PSK_WITH_RC4_128_SHA                      = $8A;
  MBEDTLS_TLS_PSK_WITH_3DES_EDE_CBC_SHA                 = $8B;
  MBEDTLS_TLS_PSK_WITH_AES_128_CBC_SHA                  = $8C;
  MBEDTLS_TLS_PSK_WITH_AES_256_CBC_SHA                  = $8D;
  MBEDTLS_TLS_DHE_PSK_WITH_RC4_128_SHA                  = $8E;
  MBEDTLS_TLS_DHE_PSK_WITH_3DES_EDE_CBC_SHA             = $8F;
  MBEDTLS_TLS_DHE_PSK_WITH_AES_128_CBC_SHA              = $90;
  MBEDTLS_TLS_DHE_PSK_WITH_AES_256_CBC_SHA              = $91;
  MBEDTLS_TLS_RSA_PSK_WITH_RC4_128_SHA                  = $92;
  MBEDTLS_TLS_RSA_PSK_WITH_3DES_EDE_CBC_SHA             = $93;
  MBEDTLS_TLS_RSA_PSK_WITH_AES_128_CBC_SHA              = $94;
  MBEDTLS_TLS_RSA_PSK_WITH_AES_256_CBC_SHA              = $95;
  MBEDTLS_TLS_RSA_WITH_AES_128_GCM_SHA256               = $9C;
  MBEDTLS_TLS_RSA_WITH_AES_256_GCM_SHA384               = $9D;
  MBEDTLS_TLS_DHE_RSA_WITH_AES_128_GCM_SHA256           = $9E;
  MBEDTLS_TLS_DHE_RSA_WITH_AES_256_GCM_SHA384           = $9F;
  MBEDTLS_TLS_PSK_WITH_AES_128_GCM_SHA256               = $A8;
  MBEDTLS_TLS_PSK_WITH_AES_256_GCM_SHA384               = $A9;
  MBEDTLS_TLS_DHE_PSK_WITH_AES_128_GCM_SHA256           = $AA;
  MBEDTLS_TLS_DHE_PSK_WITH_AES_256_GCM_SHA384           = $AB;
  MBEDTLS_TLS_RSA_PSK_WITH_AES_128_GCM_SHA256           = $AC;
  MBEDTLS_TLS_RSA_PSK_WITH_AES_256_GCM_SHA384           = $AD;
  MBEDTLS_TLS_PSK_WITH_AES_128_CBC_SHA256               = $AE;
  MBEDTLS_TLS_PSK_WITH_AES_256_CBC_SHA384               = $AF;
  MBEDTLS_TLS_PSK_WITH_NULL_SHA256                      = $B0;
  MBEDTLS_TLS_PSK_WITH_NULL_SHA384                      = $B1;
  MBEDTLS_TLS_DHE_PSK_WITH_AES_128_CBC_SHA256           = $B2;
  MBEDTLS_TLS_DHE_PSK_WITH_AES_256_CBC_SHA384           = $B3;
  MBEDTLS_TLS_DHE_PSK_WITH_NULL_SHA256                  = $B4;
  MBEDTLS_TLS_DHE_PSK_WITH_NULL_SHA384                  = $B5;
  MBEDTLS_TLS_RSA_PSK_WITH_AES_128_CBC_SHA256           = $B6;
  MBEDTLS_TLS_RSA_PSK_WITH_AES_256_CBC_SHA384           = $B7;
  MBEDTLS_TLS_RSA_PSK_WITH_NULL_SHA256                  = $B8;
  MBEDTLS_TLS_RSA_PSK_WITH_NULL_SHA384                  = $B9;
  MBEDTLS_TLS_RSA_WITH_CAMELLIA_128_CBC_SHA256          = $BA;
  MBEDTLS_TLS_DHE_RSA_WITH_CAMELLIA_128_CBC_SHA256      = $BE;
  MBEDTLS_TLS_RSA_WITH_CAMELLIA_256_CBC_SHA256          = $C0;
  MBEDTLS_TLS_DHE_RSA_WITH_CAMELLIA_256_CBC_SHA256      = $C4;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_NULL_SHA                  = $C001;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_RC4_128_SHA               = $C002;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_3DES_EDE_CBC_SHA          = $C003;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA           = $C004;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA           = $C005;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_NULL_SHA                 = $C006;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_RC4_128_SHA              = $C007;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_3DES_EDE_CBC_SHA         = $C008;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA          = $C009;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA          = $C00A;
  MBEDTLS_TLS_ECDH_RSA_WITH_NULL_SHA                    = $C00B;
  MBEDTLS_TLS_ECDH_RSA_WITH_RC4_128_SHA                 = $C00C;
  MBEDTLS_TLS_ECDH_RSA_WITH_3DES_EDE_CBC_SHA            = $C00D;
  MBEDTLS_TLS_ECDH_RSA_WITH_AES_128_CBC_SHA             = $C00E;
  MBEDTLS_TLS_ECDH_RSA_WITH_AES_256_CBC_SHA             = $C00F;
  MBEDTLS_TLS_ECDHE_RSA_WITH_NULL_SHA                   = $C010;
  MBEDTLS_TLS_ECDHE_RSA_WITH_RC4_128_SHA                = $C011;
  MBEDTLS_TLS_ECDHE_RSA_WITH_3DES_EDE_CBC_SHA           = $C012;
  MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA            = $C013;
  MBEDTLS_TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA            = $C014;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256       = $C023;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384       = $C024;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA256        = $C025;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA384        = $C026;
  MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256         = $C027;
  MBEDTLS_TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384         = $C028;
  MBEDTLS_TLS_ECDH_RSA_WITH_AES_128_CBC_SHA256          = $C029;
  MBEDTLS_TLS_ECDH_RSA_WITH_AES_256_CBC_SHA384          = $C02A;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256       = $C02B;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384       = $C02C;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_AES_128_GCM_SHA256        = $C02D;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_AES_256_GCM_SHA384        = $C02E;
  MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256         = $C02F;
  MBEDTLS_TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384         = $C030;
  MBEDTLS_TLS_ECDH_RSA_WITH_AES_128_GCM_SHA256          = $C031;
  MBEDTLS_TLS_ECDH_RSA_WITH_AES_256_GCM_SHA384          = $C032;
  MBEDTLS_TLS_ECDHE_PSK_WITH_RC4_128_SHA                = $C033;
  MBEDTLS_TLS_ECDHE_PSK_WITH_3DES_EDE_CBC_SHA           = $C034;
  MBEDTLS_TLS_ECDHE_PSK_WITH_AES_128_CBC_SHA            = $C035;
  MBEDTLS_TLS_ECDHE_PSK_WITH_AES_256_CBC_SHA            = $C036;
  MBEDTLS_TLS_ECDHE_PSK_WITH_AES_128_CBC_SHA256         = $C037;
  MBEDTLS_TLS_ECDHE_PSK_WITH_AES_256_CBC_SHA384         = $C038;
  MBEDTLS_TLS_ECDHE_PSK_WITH_NULL_SHA                   = $C039;
  MBEDTLS_TLS_ECDHE_PSK_WITH_NULL_SHA256                = $C03A;
  MBEDTLS_TLS_ECDHE_PSK_WITH_NULL_SHA384                = $C03B;
  MBEDTLS_TLS_RSA_WITH_ARIA_128_CBC_SHA256              = $C03C;
  MBEDTLS_TLS_RSA_WITH_ARIA_256_CBC_SHA384              = $C03D;
  MBEDTLS_TLS_DHE_RSA_WITH_ARIA_128_CBC_SHA256          = $C044;
  MBEDTLS_TLS_DHE_RSA_WITH_ARIA_256_CBC_SHA384          = $C045;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_ARIA_128_CBC_SHA256      = $C048;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_ARIA_256_CBC_SHA384      = $C049;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_ARIA_128_CBC_SHA256       = $C04A;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_ARIA_256_CBC_SHA384       = $C04B;
  MBEDTLS_TLS_ECDHE_RSA_WITH_ARIA_128_CBC_SHA256        = $C04C;
  MBEDTLS_TLS_ECDHE_RSA_WITH_ARIA_256_CBC_SHA384        = $C04D;
  MBEDTLS_TLS_ECDH_RSA_WITH_ARIA_128_CBC_SHA256         = $C04E;
  MBEDTLS_TLS_ECDH_RSA_WITH_ARIA_256_CBC_SHA384         = $C04F;
  MBEDTLS_TLS_RSA_WITH_ARIA_128_GCM_SHA256              = $C050;
  MBEDTLS_TLS_RSA_WITH_ARIA_256_GCM_SHA384              = $C051;
  MBEDTLS_TLS_DHE_RSA_WITH_ARIA_128_GCM_SHA256          = $C052;
  MBEDTLS_TLS_DHE_RSA_WITH_ARIA_256_GCM_SHA384          = $C053;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_ARIA_128_GCM_SHA256      = $C05C;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_ARIA_256_GCM_SHA384      = $C05D;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_ARIA_128_GCM_SHA256       = $C05E;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_ARIA_256_GCM_SHA384       = $C05F;
  MBEDTLS_TLS_ECDHE_RSA_WITH_ARIA_128_GCM_SHA256        = $C060;
  MBEDTLS_TLS_ECDHE_RSA_WITH_ARIA_256_GCM_SHA384        = $C061;
  MBEDTLS_TLS_ECDH_RSA_WITH_ARIA_128_GCM_SHA256         = $C062;
  MBEDTLS_TLS_ECDH_RSA_WITH_ARIA_256_GCM_SHA384         = $C063;
  MBEDTLS_TLS_PSK_WITH_ARIA_128_CBC_SHA256              = $C064;
  MBEDTLS_TLS_PSK_WITH_ARIA_256_CBC_SHA384              = $C065;
  MBEDTLS_TLS_DHE_PSK_WITH_ARIA_128_CBC_SHA256          = $C066;
  MBEDTLS_TLS_DHE_PSK_WITH_ARIA_256_CBC_SHA384          = $C067;
  MBEDTLS_TLS_RSA_PSK_WITH_ARIA_128_CBC_SHA256          = $C068;
  MBEDTLS_TLS_RSA_PSK_WITH_ARIA_256_CBC_SHA384          = $C069;
  MBEDTLS_TLS_PSK_WITH_ARIA_128_GCM_SHA256              = $C06A;
  MBEDTLS_TLS_PSK_WITH_ARIA_256_GCM_SHA384              = $C06B;
  MBEDTLS_TLS_DHE_PSK_WITH_ARIA_128_GCM_SHA256          = $C06C;
  MBEDTLS_TLS_DHE_PSK_WITH_ARIA_256_GCM_SHA384          = $C06D;
  MBEDTLS_TLS_RSA_PSK_WITH_ARIA_128_GCM_SHA256          = $C06E;
  MBEDTLS_TLS_RSA_PSK_WITH_ARIA_256_GCM_SHA384          = $C06F;
  MBEDTLS_TLS_ECDHE_PSK_WITH_ARIA_128_CBC_SHA256        = $C070;
  MBEDTLS_TLS_ECDHE_PSK_WITH_ARIA_256_CBC_SHA384        = $C071;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_CAMELLIA_128_CBC_SHA256  = $C072;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_CAMELLIA_256_CBC_SHA384  = $C073;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_CAMELLIA_128_CBC_SHA256   = $C074;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_CAMELLIA_256_CBC_SHA384   = $C075;
  MBEDTLS_TLS_ECDHE_RSA_WITH_CAMELLIA_128_CBC_SHA256    = $C076;
  MBEDTLS_TLS_ECDHE_RSA_WITH_CAMELLIA_256_CBC_SHA384    = $C077;
  MBEDTLS_TLS_ECDH_RSA_WITH_CAMELLIA_128_CBC_SHA256     = $C078;
  MBEDTLS_TLS_ECDH_RSA_WITH_CAMELLIA_256_CBC_SHA384     = $C079;
  MBEDTLS_TLS_RSA_WITH_CAMELLIA_128_GCM_SHA256          = $C07A;
  MBEDTLS_TLS_RSA_WITH_CAMELLIA_256_GCM_SHA384          = $C07B;
  MBEDTLS_TLS_DHE_RSA_WITH_CAMELLIA_128_GCM_SHA256      = $C07C;
  MBEDTLS_TLS_DHE_RSA_WITH_CAMELLIA_256_GCM_SHA384      = $C07D;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_CAMELLIA_128_GCM_SHA256  = $C086;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_CAMELLIA_256_GCM_SHA384  = $C087;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_CAMELLIA_128_GCM_SHA256   = $C088;
  MBEDTLS_TLS_ECDH_ECDSA_WITH_CAMELLIA_256_GCM_SHA384   = $C089;
  MBEDTLS_TLS_ECDHE_RSA_WITH_CAMELLIA_128_GCM_SHA256    = $C08A;
  MBEDTLS_TLS_ECDHE_RSA_WITH_CAMELLIA_256_GCM_SHA384    = $C08B;
  MBEDTLS_TLS_ECDH_RSA_WITH_CAMELLIA_128_GCM_SHA256     = $C08C;
  MBEDTLS_TLS_ECDH_RSA_WITH_CAMELLIA_256_GCM_SHA384     = $C08D;
  MBEDTLS_TLS_PSK_WITH_CAMELLIA_128_GCM_SHA256          = $C08E;
  MBEDTLS_TLS_PSK_WITH_CAMELLIA_256_GCM_SHA384          = $C08F;
  MBEDTLS_TLS_DHE_PSK_WITH_CAMELLIA_128_GCM_SHA256      = $C090;
  MBEDTLS_TLS_DHE_PSK_WITH_CAMELLIA_256_GCM_SHA384      = $C091;
  MBEDTLS_TLS_RSA_PSK_WITH_CAMELLIA_128_GCM_SHA256      = $C092;
  MBEDTLS_TLS_RSA_PSK_WITH_CAMELLIA_256_GCM_SHA384      = $C093;
  MBEDTLS_TLS_PSK_WITH_CAMELLIA_128_CBC_SHA256          = $C094;
  MBEDTLS_TLS_PSK_WITH_CAMELLIA_256_CBC_SHA384          = $C095;
  MBEDTLS_TLS_DHE_PSK_WITH_CAMELLIA_128_CBC_SHA256      = $C096;
  MBEDTLS_TLS_DHE_PSK_WITH_CAMELLIA_256_CBC_SHA384      = $C097;
  MBEDTLS_TLS_RSA_PSK_WITH_CAMELLIA_128_CBC_SHA256      = $C098;
  MBEDTLS_TLS_RSA_PSK_WITH_CAMELLIA_256_CBC_SHA384      = $C099;
  MBEDTLS_TLS_ECDHE_PSK_WITH_CAMELLIA_128_CBC_SHA256    = $C09A;
  MBEDTLS_TLS_ECDHE_PSK_WITH_CAMELLIA_256_CBC_SHA384    = $C09B;
  MBEDTLS_TLS_RSA_WITH_AES_128_CCM                      = $C09C;
  MBEDTLS_TLS_RSA_WITH_AES_256_CCM                      = $C09D;
  MBEDTLS_TLS_DHE_RSA_WITH_AES_128_CCM                  = $C09E;
  MBEDTLS_TLS_DHE_RSA_WITH_AES_256_CCM                  = $C09F;
  MBEDTLS_TLS_RSA_WITH_AES_128_CCM_8                    = $C0A0;
  MBEDTLS_TLS_RSA_WITH_AES_256_CCM_8                    = $C0A1;
  MBEDTLS_TLS_DHE_RSA_WITH_AES_128_CCM_8                = $C0A2;
  MBEDTLS_TLS_DHE_RSA_WITH_AES_256_CCM_8                = $C0A3;
  MBEDTLS_TLS_PSK_WITH_AES_128_CCM                      = $C0A4;
  MBEDTLS_TLS_PSK_WITH_AES_256_CCM                      = $C0A5;
  MBEDTLS_TLS_DHE_PSK_WITH_AES_128_CCM                  = $C0A6;
  MBEDTLS_TLS_DHE_PSK_WITH_AES_256_CCM                  = $C0A7;
  MBEDTLS_TLS_PSK_WITH_AES_128_CCM_8                    = $C0A8;
  MBEDTLS_TLS_PSK_WITH_AES_256_CCM_8                    = $C0A9;
  MBEDTLS_TLS_DHE_PSK_WITH_AES_128_CCM_8                = $C0AA;
  MBEDTLS_TLS_DHE_PSK_WITH_AES_256_CCM_8                = $C0AB;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_CCM              = $C0AC;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_256_CCM              = $C0AD;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_CCM_8            = $C0AE;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_256_CCM_8            = $C0AF;
  MBEDTLS_TLS_ECJPAKE_WITH_AES_128_CCM_8                = $C0FF;
  MBEDTLS_TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256   = $CCA8;
  MBEDTLS_TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256 = $CCA9;
  MBEDTLS_TLS_DHE_RSA_WITH_CHACHA20_POLY1305_SHA256     = $CCAA;
  MBEDTLS_TLS_PSK_WITH_CHACHA20_POLY1305_SHA256         = $CCAB;
  MBEDTLS_TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256   = $CCAC;
  MBEDTLS_TLS_DHE_PSK_WITH_CHACHA20_POLY1305_SHA256     = $CCAD;
  MBEDTLS_TLS_RSA_PSK_WITH_CHACHA20_POLY1305_SHA256     = $CCAE;

type
  TMbedtls_SSL_States = Integer;
  // 定义完整的 TMbedtls_SSL_States 枚举类型在编译 Win64 执行文件时会报错
  // [dcc64 Error] Net.MbedTls.pas(1638): E2068 Illegal reference to symbol 'MBEDTLS_SSL_HANDSHAKE_WRAPUP' in object file 'D:\Design\Delphi\VclFmxRtl\zLib\Net\MbedTls\Win64\Release\ssl_cli.o'
  // 这显然是编译器的问题, 经测试 Delphi 10.2.3 和 Delphi 10.3 均有该问题
//  TMbedtls_SSL_States = (
//    MBEDTLS_SSL_HELLO_REQUEST = 0,
//    MBEDTLS_SSL_CLIENT_HELLO,
//    MBEDTLS_SSL_SERVER_HELLO,
//    MBEDTLS_SSL_SERVER_CERTIFICATE,
//    MBEDTLS_SSL_SERVER_KEY_EXCHANGE,
//    MBEDTLS_SSL_CERTIFICATE_REQUEST,
//    MBEDTLS_SSL_SERVER_HELLO_DONE,
//    MBEDTLS_SSL_CLIENT_CERTIFICATE,
//    MBEDTLS_SSL_CLIENT_KEY_EXCHANGE,
//    MBEDTLS_SSL_CERTIFICATE_VERIFY,
//    MBEDTLS_SSL_CLIENT_CHANGE_CIPHER_SPEC,
//    MBEDTLS_SSL_CLIENT_FINISHED,
//    MBEDTLS_SSL_SERVER_CHANGE_CIPHER_SPEC,
//    MBEDTLS_SSL_SERVER_FINISHED,
//    MBEDTLS_SSL_FLUSH_BUFFERS,
//    MBEDTLS_SSL_HANDSHAKE_WRAPUP,
//    MBEDTLS_SSL_HANDSHAKE_OVER,
//    MBEDTLS_SSL_SERVER_NEW_SESSION_TICKET,
//    MBEDTLS_SSL_SERVER_HELLO_VERIFY_REQUEST_SENT
//  );

  Size_T = NativeUInt;
  PSize_T = ^Size_T;
  UInt32_T = UInt32;
  PUint32_T = ^UInt32_T;
  UInt16_T = UInt16;
  UInt64_T = UInt64;
  UInt8_T = UInt8;

  PMbedtls_SSL_Session = Pointer;
  PMbedtls_SSL_Transform = Pointer;
  PMbedtls_SSL_Handshake_Params = Pointer;
  PMbedtls_MD_Info = Pointer; // opaque
  PMbedtls_X509_Crl = Pointer;
  PMbedtls_Cipher_Info = Pointer;

  PMbedtls_SSL_Send = Pointer;
  PMbedtls_SSL_Recv = Pointer;
  PMbedtls_SSL_Recv_Timeout = Pointer;
  PMbedtls_SSL_Set_Timer = Pointer;
  PMbedtls_SSL_Get_Timer = Pointer;

  PMbedtls_SSL_Cache_Entry = Pointer;

  PTlsMutex = ^TTlsMutex;
  TTlsMutex = record
    Lock: TObject;
    IsValid: Byte;
  end;

  TMbedtls_MPI = record
    s: Integer; // integer sign
    n: Size_T; // total # of limbs
    p: Pointer; // pointer to limbs
  end;

  //
  // SSL/TLS configuration to be shared between mbedtls_ssl_context structures.
  //
  PMbedtls_SSL_Config = ^TMbedtls_SSL_Config;
  TMbedtls_SSL_Config = record
    // Group items by size (largest first) to minimize padding overhead

    //
    // Pointers
    //

    ciphersuite_list: array [0 .. 3] of PInteger;
    // allowed ciphersuites per version

    // Callback for printing debug output
    f_dbg: Pointer;
    p_dbg: Pointer; // !< context for the debug function

    // ** Callback for getting (pseudo-)random numbers
    f_rng: Pointer;
    p_rng: Pointer; // !< context for the RNG function

    // ** Callback to retrieve a session from the cache
    f_get_cache: Pointer;
    // ** Callback to store a session into the cache
    f_set_cache: Pointer;
    p_cache: Pointer; // !< context for cache callbacks

    // ** Callback for setting cert according to SNI extension
    f_sni: Pointer;
    p_sni: Pointer; // !< context for SNI callback

    // ** Callback to customize X.509 certificate chain verification
    f_vrfy: Pointer;
    p_vrfy: Pointer; // !< context for X.509 verify calllback

    // ** Callback to retrieve PSK key from identity
    f_psk: Pointer;
    p_psk: Pointer; // !< context for PSK callback

    // ** Callback to create & write a cookie for ClientHello veirifcation
    f_cookie_write: Pointer;
    // ** Callback to verify validity of a ClientHello cookie
    f_cookie_check: Pointer;
    p_cookie: Pointer; // !< context for the cookie callbacks

    // ** Callback to create & write a session ticket
    f_ticket_write: Pointer;
    // ** Callback to parse a session ticket into a session structure
    f_ticket_parse: Pointer;
    p_ticket: Pointer; // !< context for the ticket callbacks

    // ** Callback to export key block and master secret
    f_export_keys: Pointer;
    p_export_keys: Pointer; // !< context for key export callback

    cert_profile: Pointer; // !< verification profile
    key_cert: Pointer; // !< own certificate/key pair(s)
    ca_chain: Pointer; // !< trusted CAs
    ca_crl: Pointer; // !< trusted CAs CRLs

    f_async_sign_start: Pointer; // !< start asynchronous signature operation
    f_async_decrypt_start: Pointer; // !< start asynchronous decryption operation
    f_async_resume: Pointer; // !< resume asynchronous operation
    f_async_cancel: Pointer; // !< cancel asynchronous operation
    p_async_config_data: Pointer; // !< Configuration data set by mbedtls_ssl_conf_async_private_cb().

    sig_hashes: PInteger; // !< allowed signature hashes

    curve_list: Pointer; // !< allowed curves

    dhm_P: TMbedtls_MPI; // !< prime modulus for DHM
    dhm_G: TMbedtls_MPI; // !< generator for DHM

    psk: PByte; // !< pre-shared key. This field should
                //    only be set via
                //    mbedtls_ssl_conf_psk()
    psk_len: Size_T; // !< length of the pre-shared key. This
                     //    field should only be set via
                     //    mbedtls_ssl_conf_psk()
    psk_identity: PByte; // !< identity for PSK negotiation. This
                         //    field should only be set via
                         //    mbedtls_ssl_conf_psk()
    psk_identity_len: Size_T; // !< length of identity. This field should
                              //    only be set via
                              //    mbedtls_ssl_conf_psk()

    alpn_list: PMarshaledAString; // !< ordered list of protocols

    //
    // * Numerical settings (int then char)
    //

    read_timeout: UInt32_T; // !< timeout for mbedtls_ssl_read (ms)

    hs_timeout_min: UInt32_T; // !< initial value of the handshake
                              //    retransmission timeout (ms)
    hs_timeout_max: UInt32_T; // !< maximum value of the handshake
                              //    retransmission timeout (ms)

    renego_max_records: Integer; // !< grace period for renegotiation
    renego_period: array [0 .. 7] of UInt8_T; // !< value of the record counters
                                              //    that triggers renegotiation

    badmac_limit: UInt32_T; // !< limit of records with a bad MAC

    dhm_min_bitlen: UInt32_T; // !< min. bit length of the DHM prime

    max_major_ver: UInt8_T; // !< max. major version used
    max_minor_ver: UInt8_T; // !< max. minor version used
    min_major_ver: UInt8_T; // !< min. major version used
    min_minor_ver: UInt8_T; // !< min. minor version used

    //
    // * Flags (bitfields)
    //
    Flag: UInt32_T;
  end;

  PMbedtls_SSL_Context = ^TMbedtls_SSL_Context;
  TMbedtls_SSL_Context = record
    conf: PMbedtls_SSL_Config; // !< configuration information

    //
    // * Miscellaneous
    //
    state: Integer; // !< SSL handshake: current state
    renego_status: Integer; // !< Initial, in progress, pending?
    renego_records_seen: Integer; // !< Records since renego request, or with DTLS,
                                  //    number of retransmissions of request if
                                  //    renego_max_records is < 0

    major_ver: Integer; // !< equal to  MBEDTLS_SSL_MAJOR_VERSION_3
    minor_ver: Integer; // !< either 0 (SSL3) or 1 (TLS1.0)

    badmac_seen: Cardinal; // !< records with a bad MAC received

    f_send: PMbedtls_SSL_Send; // !< Callback for network send
    f_recv: PMbedtls_SSL_Recv; // !< Callback for network receive
    f_recv_timeout: PMbedtls_SSL_Recv_Timeout; // !< Callback for network receive with timeout

    p_bio: Pointer; // !< context for I/O operations

    //
    // * Session layer
    //
    session_in: PMbedtls_SSL_Session; // !<  current session data (in)
    session_out: PMbedtls_SSL_Session; // !<  current session data (out)
    session: PMbedtls_SSL_Session; // !<  negotiated session data
    session_negotiate: PMbedtls_SSL_Session; // !<  session data in negotiation

    handshake: PMbedtls_SSL_Handshake_Params; // !<  params required only during
                                              //     the handshake process

    //
    // * Record layer transformations
    //
    transform_in: PMbedtls_SSL_Transform; // !<  current transform params (in)
    transform_out: PMbedtls_SSL_Transform; // !<  current transform params (in)
    transform: PMbedtls_SSL_Transform; // !<  negotiated transform params
    transform_negotiate: PMbedtls_SSL_Transform; // !<  transform params in negotiation

    //
    // * Timers
    //
    p_timer: Pointer; // !< context for the timer callbacks

    f_set_timer: PMbedtls_SSL_Set_Timer; // !< set timer callback
    f_get_timer: PMbedtls_SSL_Get_Timer; // !< get timer callback

    //
    // * Record layer (incoming data)
    //
    in_buf: PByte; // !< input buffer
    in_ctr: PByte; // !< 64-bit incoming message counter
                   //    TLS: maintained by us
                   //    DTLS: read from peer
    in_hdr: PByte; // !< start of record header
    in_len: PByte; // !< two-bytes message length field
    in_iv: PByte; // !< ivlen-byte IV
    in_msg: PByte; // !< message contents (in_iv+ivlen)
    in_offt: PByte; // !< read offset in application data

    in_msgtype: Integer; // !< record header: message type
    in_msglen: Size_T; // !< record header: message length
    in_left: Size_T; // !< amount of data read so far
    in_epoch: UInt16_T; // !< DTLS epoch for incoming records
    next_record_offset: Size_T; // !< offset of the next record in datagram
                                //    (equal to in_left if none)
    in_window_top: UInt64_T; // !< last validated record seq_num
    in_window: UInt64_T; // !< bitmask for replay detection

    in_hslen: Size_T; // !< current handshake message length,
                      //    including the handshake header
    nb_zero: Integer; // !< # of 0-length encrypted messages

    keep_current_message: Integer; // !< drop or reuse current message
                                   //    on next call to record layer?

    disable_datagram_packing: UInt8_T; // !< Disable packing multiple records
                                       //    within a single datagram.

    //
    // * Record layer (outgoing data)
    //
    out_buf: PByte; // !< output buffer
    out_ctr: PByte; // !< 64-bit outgoing message counter
    out_hdr: PByte; // !< start of record header
    out_len: PByte; // !< two-bytes message length field
    out_iv: PByte; // !< ivlen-byte IV
    out_msg: PByte; // !< message contents (out_iv+ivlen)

    out_msgtype: Integer; // !< record header: message type
    out_msglen: Size_T; // !< record header: message length
    out_left: Size_T; // !< amount of data not yet written

    cur_out_ctr: array [0 .. 7] of Byte; // !<  Outgoing record sequence  number.

    mtu: UInt16_T; // !< path mtu, used to fragment outgoing messages

    compress_buf: PByte; // !<  zlib data buffer
    split_done: Byte; // !< current record already splitted?

    //
    // * PKI layer
    //
    client_auth: Integer; // !<  flag for client auth.

    //
    // * User settings
    //
    hostname: MarshaledAString; // !< expected peer CN for verification
                                //    (and SNI if available)

    alpn_chosen: MarshaledAString; // !<  negotiated protocol

    //
    // * Information for DTLS hello verify
    //
    cli_id: PByte; // !<  transport-level ID of the client
    cli_id_len: Size_T; // !<  length of cli_id

    //
    // * Secure renegotiation
    //
    // needed to know when to send extension on server
    secure_renegotiation: Integer; // !<  does peer support legacy or
                                   //     secure renegotiation
    verify_data_len: Size_T; // !<  length of verify data stored
    own_verify_data: array [0 .. MBEDTLS_SSL_VERIFY_DATA_MAX_LEN - 1] of Byte; // !<  previous handshake verify data
    peer_verify_data: array [0 .. MBEDTLS_SSL_VERIFY_DATA_MAX_LEN - 1] of Byte; // !<  previous handshake verify data
  end;

  PMbedtls_SSL_Cache_Context = ^TMbedtls_SSL_Cache_Context;
  TMbedtls_SSL_Cache_Context = record
    chain: PMbedtls_SSL_Cache_Entry; // !< start of the chain
    timeout: Integer; // !< cache entry timeout
    max_entries: Integer; // !< maximum entries
    mutex: TTlsMutex; // !< mutex
  end;

  TMbedtls_Asn1_Buf = record
    tag: Integer; // **< ASN1 type, e.g. MBEDTLS_ASN1_UTF8_STRING.
    len: Size_T; // **< ASN1 length, in octets.
    p: PByte; // **< ASN1 data, e.g. in ASCII.
  end;

  TMbedtls_X509_Buf = TMbedtls_Asn1_Buf;

  PMbedtls_Asn1_Named_Data = ^TMbedtls_Asn1_Named_Data;
  TMbedtls_Asn1_Named_Data = record
    oid: TMbedtls_Asn1_Buf; // **< The object identifier.
    val: TMbedtls_Asn1_Buf; // **< The named value.
    next: PMbedtls_Asn1_Named_Data; // **< The next entry in the sequence.
    next_merged: Byte; // **< Merge next item into the current one?
  end;

  TMbedtls_X509_Name = TMbedtls_Asn1_Named_Data;

  TMbedtls_X509_Time = record
    year, mon, day: Integer; // **< Date.
    hour, min, sec: Integer; // **< Time.
  end;

  TMbedtls_PK_Type = (
    MBEDTLS_PK_NONE = 0,
    MBEDTLS_PK_RSA,
    MBEDTLS_PK_ECKEY,
    MBEDTLS_PK_ECKEY_DH,
    MBEDTLS_PK_ECDSA,
    MBEDTLS_PK_RSA_ALT,
    MBEDTLS_PK_RSASSA_PSS
  );

  PMbedtls_PK_Info = ^TMbedtls_PK_Info;
  TMbedtls_PK_Info = record
    // ** Public key type
    &type: TMbedtls_PK_Type;

    // ** Type name
    name: MarshaledAString;

    // ** Get key size in bits
    get_bitlen: Pointer;

    // ** Tell if the context implements this type (e.g. ECKEY can do ECDSA)
    can_do: Pointer;

    // ** Verify signature
    verify_func: Pointer;

    // ** Make signature
    sign_func: Pointer;

    // ** Decrypt message
    decrypt_func: Pointer;

    // ** Encrypt message
    encrypt_func: Pointer;

    // ** Check public-private key pair
    check_pair_func: Pointer;

    // ** Allocate a new context
    ctx_alloc_func: Pointer;

    // ** Free the given context
    ctx_free_func: Pointer;

    // ** Interface with the debug module
    debug_func: Pointer;
  end;

  PMbedtls_PK_Context = ^TMbedtls_PK_Context;
  TMbedtls_PK_Context = record
    pk_info: PMbedtls_PK_Info; // **< Public key informations
    pk_ctx: Pointer; // **< Underlying public key context
  end;

  PMbedtls_Asn1_Sequence = ^TMbedtls_Asn1_Sequence;
  TMbedtls_Asn1_Sequence = record
    buf: TMbedtls_Asn1_Buf; // **< Buffer containing the given ASN.1 item.
    next: PMbedtls_Asn1_Sequence; // **< The next entry in the sequence.
  end;

  TMbedtls_X509_Sequence = TMbedtls_Asn1_Sequence;

  TMbedtls_MD_Type = (
    MBEDTLS_MD_NONE = 0, // **< None.
    MBEDTLS_MD_MD2,      // **< The MD2 message digest.
    MBEDTLS_MD_MD4,      // **< The MD4 message digest.
    MBEDTLS_MD_MD5,      // **< The MD5 message digest.
    MBEDTLS_MD_SHA1,     // **< The SHA-1 message digest.
    MBEDTLS_MD_SHA224,   // **< The SHA-224 message digest.
    MBEDTLS_MD_SHA256,   // **< The SHA-256 message digest.
    MBEDTLS_MD_SHA384,   // **< The SHA-384 message digest.
    MBEDTLS_MD_SHA512,   // **< The SHA-512 message digest.
    MBEDTLS_MD_RIPEMD160 // **< The RIPEMD-160 message digest.
  );

  PMbedtls_X509_CRT = ^TMbedtls_X509_CRT;
  TMbedtls_X509_CRT = record
    raw: TMbedtls_X509_Buf; // **< The raw certificate data (DER).
    tbs: TMbedtls_X509_Buf; // **< The raw certificate body (DER). The part that is To Be Signed.

    version: Integer; // **< The X.509 version. (1=v1, 2=v2, 3=v3)
    serial: TMbedtls_X509_Buf; // **< Unique id for certificate issued by a specific CA.
    sig_oid: TMbedtls_X509_Buf; // **< Signature algorithm, e.g. sha1RSA

    issuer_raw: TMbedtls_X509_Buf; // **< The raw issuer data (DER). Used for quick comparison.
    subject_raw: TMbedtls_X509_Buf; // **< The raw subject data (DER). Used for quick comparison.

    issuer: TMbedtls_X509_Name; // **< The parsed issuer data (named information object).
    subject: TMbedtls_X509_Name; // **< The parsed subject data (named information object).

    valid_from: TMbedtls_X509_Time; // **< Start time of certificate validity.
    valid_to: TMbedtls_X509_Time; // **< End time of certificate validity.

    pk: TMbedtls_PK_Context; // **< Container for the public key context.

    issuer_id: TMbedtls_X509_Buf; // **< Optional X.509 v2/v3 issuer unique identifier.
    subject_id: TMbedtls_X509_Buf; // **< Optional X.509 v2/v3 subject unique identifier.
    v3_ext: TMbedtls_X509_Buf; // **< Optional X.509 v3 extensions.
    subject_alt_names: TMbedtls_X509_Sequence; // **< Optional list of Subject Alternative Names (Only dNSName supported).

    ext_types: Integer; // **< Bit string containing detected and parsed extensions
    ca_istrue: Integer; // **< Optional Basic Constraint extension value: 1 if this certificate belongs to a CA, 0 otherwise.
    max_pathlen: Integer; // **< Optional Basic Constraint extension value: The maximum path length to the root certificate. Path length is 1 higher than RFC 5280 'meaning', so 1+

    key_usage: UInt32_T; // **< Optional key usage extension value: See the values in x509.h

    ext_key_usage: TMbedtls_X509_Sequence; // **< Optional list of extended key usage OIDs.

    ns_cert_type: Byte; // **< Optional Netscape certificate type extension value: See the values in x509.h

    sig: TMbedtls_X509_Buf; // **< Signature: hash of the tbs part signed with the private key.
    sig_md: TMbedtls_MD_Type; // **< Internal representation of the MD algorithm of the signature algorithm, e.g. MBEDTLS_MD_SHA256
    sig_pk: TMbedtls_PK_Type; // **< Internal representation of the Public Key algorithm of the signature algorithm, e.g. MBEDTLS_PK_RSA
    sig_opts: Pointer; // **< Signature options to be passed to mbedtls_pk_verify_ext(), e.g. for RSASSA-PSS

    next: PMbedtls_X509_CRT; // **< Next certificate in the CA-chain.
  end;

  TMbedtls_SHA512_Context = record
    total: array [0 .. 1] of UInt64_T; // !< The number of Bytes processed.
    state: array [0 .. 7] of UInt64_T; // !< The intermediate digest state.
    buffer: array [0 .. 127] of Byte;  // !< The data block being processed.
    is384: Integer;                    // !< Determines which function to use:
                                       //    0: Use SHA-512, or 1: Use SHA-384.
  end;

  TMbedtls_Entropy_Source_State = record
    f_source: Pointer; // **< The entropy source callback
    p_source: Pointer; // **< The callback data pointer
    size: Size_T;      // **< Amount received in bytes
    threshold: Size_T; // **< Minimum bytes required before release
    strong: Integer;   // **< Is the source strong?
  end;

  TMbedtls_Havege_State = record
    PT1: Integer;
    PT2: Integer;
    offset: array [0 .. 1] of Integer;
    pool: array [0 .. MBEDTLS_HAVEGE_COLLECT_SIZE - 1] of Integer;
    WALK: array [0 .. 8191] of Integer;
  end;

  PMbedtls_Entropy_Context = ^TMbedtls_Entropy_Context;
  TMbedtls_Entropy_Context = record
    accumulator_started: Integer;
    accumulator: TMbedtls_SHA512_Context;
    source_count: Integer;
    source: array [0 .. MBEDTLS_ENTROPY_MAX_SOURCES - 1] of TMbedtls_Entropy_Source_State;
    havege_data: TMbedtls_Havege_State;
    mutex: TTlsMutex; // !< mutex
    initial_entropy_run: Integer;
  end;

  TMbedtls_AES_Context = record
    nr: Integer;                      // !< The number of rounds.
    rk: PUint32_T;                    // !< AES round keys.
    buf: array [0 .. 67] of UInt32_T; // !< Unaligned data buffer. This buffer can
                                      //    hold 32 extra Bytes, which can be used for
                                      //    one of the following purposes:
                                      //    <ul><li>Alignment if VIA padlock is
                                      //    used.</li>
                                      //    <li>Simplifying key expansion in the 256-bit
                                      //    case by generating an extra round key.
                                      //    </li></ul>
  end;

  PMbedtls_CTR_DRBG_Context = ^TMbedtls_CTR_DRBG_Context;
  TMbedtls_CTR_DRBG_Context = record
    counter: array [0 .. 15] of Byte; // !< The counter (V).
    reseed_counter: Integer; // !< The reseed counter.
    prediction_resistance: Integer; // !< This determines whether prediction
                                    //    resistance is enabled, that is
                                    //    whether to systematically reseed before
                                    //    each random generation.
    entropy_len: Size_T; // !< The amount of entropy grabbed on each
                         //    seed or reseed operation.
    reseed_interval: Integer; // !< The reseed interval.

    aes_ctx: TMbedtls_AES_Context; // !< The AES context.

    //
    // * Callbacks (Entropy)
    //
    f_entropy: Pointer; // !< The entropy callback function.

    p_entropy: Pointer; // !< The context for the entropy function.

    mutex: TTlsMutex;
  end;

  TEntropyFunc = function(data: Pointer; output: MarshaledAString; len: Size_T): Integer; cdecl;
  PEntropyFunc = ^TEntropyFunc;
  TrngFunc = function(data: Pointer; output: MarshaledAString; len: Size_T): Integer; cdecl;
  TdbgFunc = procedure(data: Pointer; i: Integer; c: MarshaledAString; i2: Integer; c2: MarshaledAString); cdecl;
  TNetSendFunc = function(ctx: Pointer; buf: Pointer; len: Size_T): Integer; cdecl;
  TNetRecvFunc = function(ctx: Pointer; buf: Pointer; len: Size_T): Integer; cdecl;
  TNetRecvTimeoutFunc = function(ctx: Pointer; buf: Pointer; len: Size_T; timeout: UInt32_T): Integer; cdecl;
  TGetTimerFunc = function(ctx: Pointer): Integer; cdecl;
  TSetTimerFunc = procedure(ctx: Pointer; int_ms: UInt32_T; fin_ms: UInt32_T); cdecl;

  TGetCacheFunc = function(data: Pointer; session: PMbedtls_SSL_Session): Integer; cdecl;
  TSetCacheFunc = function(data: Pointer; const session: PMbedtls_SSL_Session): Integer; cdecl;

const
  // SSL Error codes  - actually negative of these
  MBEDTLS_ERR_MPI_FILE_IO_ERROR     = -$0002; // An error occurred while reading from or writing to a file.
  MBEDTLS_ERR_MPI_BAD_INPUT_DATA    = -$0004; // Bad input parameters to function.
  MBEDTLS_ERR_MPI_INVALID_CHARACTER = -$0006; // There is an invalid character in the digit string.
  MBEDTLS_ERR_MPI_BUFFER_TOO_SMALL  = -$0008; // The buffer is too small to write to.
  MBEDTLS_ERR_MPI_NEGATIVE_VALUE    = -$000A; // The input arguments are negative or result in illegal output.
  MBEDTLS_ERR_MPI_DIVISION_BY_ZERO  = -$000C; // The input argument for division is zero, which is not allowed.
  MBEDTLS_ERR_MPI_NOT_ACCEPTABLE    = -$000E; // The input arguments are not acceptable.
  MBEDTLS_ERR_MPI_ALLOC_FAILED      = -$0010; // Memory allocation failed.

  MBEDTLS_ERR_HMAC_DRBG_REQUEST_TOO_BIG       = -$0003; // Too many random requested in single call.
  MBEDTLS_ERR_HMAC_DRBG_INPUT_TOO_BIG         = -$0005; // Input too large (Entropy + additional).
  MBEDTLS_ERR_HMAC_DRBG_FILE_IO_ERROR         = -$0007; // Read/write error in file.
  MBEDTLS_ERR_HMAC_DRBG_ENTROPY_SOURCE_FAILED = -$0009; // The entropy source failed.

  MBEDTLS_ERR_CCM_BAD_INPUT       = -$000D; // Bad input parameters to the function.
  MBEDTLS_ERR_CCM_AUTH_FAILED     = -$000F; // Authenticated decryption failed.
  MBEDTLS_ERR_CCM_HW_ACCEL_FAILED = -$0011; // CCM hardware accelerator failed.

  MBEDTLS_ERR_GCM_AUTH_FAILED     = -$0012; // Authenticated decryption failed.
  MBEDTLS_ERR_GCM_HW_ACCEL_FAILED = -$0013; // GCM hardware accelerator failed.
  MBEDTLS_ERR_GCM_BAD_INPUT       = -$0014; // Bad input parameters to function.

  MBEDTLS_ERR_BLOWFISH_INVALID_KEY_LENGTH   = -$0016; // Invalid key length.
  MBEDTLS_ERR_BLOWFISH_HW_ACCEL_FAILED      = -$0017; // Blowfish hardware accelerator failed.
  MBEDTLS_ERR_BLOWFISH_INVALID_INPUT_LENGTH = -$0018; // Invalid data input length.

  MBEDTLS_ERR_ARC4_HW_ACCEL_FAILED = -$0019; // ARC4 hardware accelerator failed.

  MBEDTLS_ERR_THREADING_FEATURE_UNAVAILABLE = -$001A; // The selected feature is not available.
  MBEDTLS_ERR_THREADING_BAD_INPUT_DATA      = -$001C; // Bad input parameters to function.
  MBEDTLS_ERR_THREADING_MUTEX_ERROR         = -$001E; // Locking / unlocking / free failed with error code.

  MBEDTLS_ERR_AES_INVALID_KEY_LENGTH   = -$0020; // Invalid key length.
  MBEDTLS_ERR_AES_INVALID_INPUT_LENGTH = -$0022; // Invalid data input length.

  MBEDTLS_ERR_AES_FEATURE_UNAVAILABLE = -$0023; // Feature not available. For example, an unsupported AES key size.
  MBEDTLS_ERR_AES_HW_ACCEL_FAILED     = -$0025; // AES hardware accelerator failed.

  MBEDTLS_ERR_CAMELLIA_INVALID_KEY_LENGTH   = -$0024; // Invalid key length.
  MBEDTLS_ERR_CAMELLIA_INVALID_INPUT_LENGTH = -$0026; // Invalid data input length.
  MBEDTLS_ERR_CAMELLIA_HW_ACCEL_FAILED      = -$0027; // Camellia hardware accelerator failed.

  MBEDTLS_ERR_XTEA_INVALID_INPUT_LENGTH = -$0028; // The data input has an invalid length.
  MBEDTLS_ERR_XTEA_HW_ACCEL_FAILED      = -$0029; // XTEA hardware accelerator failed.

  MBEDTLS_ERR_BASE64_BUFFER_TOO_SMALL  = -$002A; // Output buffer too small.
  MBEDTLS_ERR_BASE64_INVALID_CHARACTER = -$002C; // Invalid character in input.

  MBEDTLS_ERR_MD2_HW_ACCEL_FAILED = -$002B; // MD2 hardware accelerator failed
  MBEDTLS_ERR_MD4_HW_ACCEL_FAILED = -$002D; // MD4 hardware accelerator failed
  MBEDTLS_ERR_MD5_HW_ACCEL_FAILED = -$002F; // MD5 hardware accelerator failed

  MBEDTLS_ERR_OID_NOT_FOUND     = -$002E; // OID is not found.
  MBEDTLS_ERR_OID_BUF_TOO_SMALL = -$000B; // output buffer is too small

  MBEDTLS_ERR_PADLOCK_DATA_MISALIGNED = -$0030; // Input data should be aligned.

  MBEDTLS_ERR_RIPEMD160_HW_ACCEL_FAILED = -$0031; // RIPEMD160 hardware accelerator failed

  MBEDTLS_ERR_DES_INVALID_INPUT_LENGTH = -$0032; // The data input has an invalid length.
  MBEDTLS_ERR_DES_HW_ACCEL_FAILED      = -$0033; // DES hardware accelerator failed.

  MBEDTLS_ERR_CTR_DRBG_ENTROPY_SOURCE_FAILED = -$0034; // The entropy source failed.
  MBEDTLS_ERR_CTR_DRBG_REQUEST_TOO_BIG       = -$0036; // The requested random buffer length is too big.
  MBEDTLS_ERR_CTR_DRBG_INPUT_TOO_BIG         = -$0038; // The input (entropy + additional data) is too large.
  MBEDTLS_ERR_CTR_DRBG_FILE_IO_ERROR         = -$003A; // Read or write error in file.

  MBEDTLS_ERR_SHA1_HW_ACCEL_FAILED   = -$0035; // SHA-1 hardware accelerator failed
  MBEDTLS_ERR_SHA256_HW_ACCEL_FAILED = -$0037; // SHA-256 hardware accelerator failed
  MBEDTLS_ERR_SHA512_HW_ACCEL_FAILED = -$0039; // SHA-512 hardware accelerator failed

  MBEDTLS_ERR_ENTROPY_SOURCE_FAILED      = -$003C; // Critical entropy source failure.
  MBEDTLS_ERR_ENTROPY_MAX_SOURCES        = -$003E; // No more sources can be added.
  MBEDTLS_ERR_ENTROPY_NO_SOURCES_DEFINED = -$0040; // No sources have been added to poll.
  MBEDTLS_ERR_ENTROPY_NO_STRONG_SOURCE   = -$003D; // No strong sources have been added to poll.
  MBEDTLS_ERR_ENTROPY_FILE_IO_ERROR      = -$003F; // Read/write error in file.

  MBEDTLS_ERR_NET_SOCKET_FAILED    = -$0042; // Failed to open a socket.
  MBEDTLS_ERR_NET_CONNECT_FAILED   = -$0044; // The connection to the given server / port failed.
  MBEDTLS_ERR_NET_BIND_FAILED      = -$0046; // Binding of the socket failed.
  MBEDTLS_ERR_NET_LISTEN_FAILED    = -$0048; // Could not listen on the socket.
  MBEDTLS_ERR_NET_ACCEPT_FAILED    = -$004A; // Could not accept the incoming connection.
  MBEDTLS_ERR_NET_RECV_FAILED      = -$004C; // Reading information from the socket failed.
  MBEDTLS_ERR_NET_SEND_FAILED      = -$004E; // Sending information through the socket failed.
  MBEDTLS_ERR_NET_CONN_RESET       = -$0050; // Connection was reset by peer.
  MBEDTLS_ERR_NET_UNKNOWN_HOST     = -$0052; // Failed to get an IP address for the given hostname.
  MBEDTLS_ERR_NET_BUFFER_TOO_SMALL = -$0043; // Buffer is too small to hold the data.
  MBEDTLS_ERR_NET_INVALID_CONTEXT  = -$0045; // The context is invalid, eg because it was free()ed.

  MBEDTLS_ERR_ASN1_OUT_OF_DATA     = -$0060; // Out of data when parsing an ASN1 data structure.
  MBEDTLS_ERR_ASN1_UNEXPECTED_TAG  = -$0062; // ASN1 tag was of an unexpected value.
  MBEDTLS_ERR_ASN1_INVALID_LENGTH  = -$0064; // Error when trying to determine the length or invalid length.
  MBEDTLS_ERR_ASN1_LENGTH_MISMATCH = -$0066; // Actual length differs from expected length.
  MBEDTLS_ERR_ASN1_INVALID_DATA    = -$0068; // Data is invalid. (not used)
  MBEDTLS_ERR_ASN1_ALLOC_FAILED    = -$006A; // Memory allocation failed
  MBEDTLS_ERR_ASN1_BUF_TOO_SMALL   = -$006C; // Buffer too small when writing ASN.1 data structure.

  MBEDTLS_ERR_CMAC_HW_ACCEL_FAILED = -$007A; // CMAC hardware accelerator failed.

  MBEDTLS_ERR_PEM_NO_HEADER_FOOTER_PRESENT = -$1080; // No PEM header or footer found.
  MBEDTLS_ERR_PEM_INVALID_DATA             = -$1100; // PEM string is not as expected.
  MBEDTLS_ERR_PEM_ALLOC_FAILED             = -$1180; // Failed to allocate memory.
  MBEDTLS_ERR_PEM_INVALID_ENC_IV           = -$1200; // RSA IV is not in hex-format.
  MBEDTLS_ERR_PEM_UNKNOWN_ENC_ALG          = -$1280; // Unsupported key encryption algorithm.
  MBEDTLS_ERR_PEM_PASSWORD_REQUIRED        = -$1300; // Private key password can't be empty.
  MBEDTLS_ERR_PEM_PASSWORD_MISMATCH        = -$1380; // Given private key password does not allow for correct decryption.
  MBEDTLS_ERR_PEM_FEATURE_UNAVAILABLE      = -$1400; // Unavailable feature, e.g. hashing/encryption combination.
  MBEDTLS_ERR_PEM_BAD_INPUT_DATA           = -$1480; // Bad input parameters to function.

  MBEDTLS_ERR_PKCS12_BAD_INPUT_DATA      = -$1F80; // Bad input parameters to function.
  MBEDTLS_ERR_PKCS12_FEATURE_UNAVAILABLE = -$1F00; // Feature not available, e.g. unsupported encryption scheme.
  MBEDTLS_ERR_PKCS12_PBE_INVALID_FORMAT  = -$1E80; // PBE ASN.1 data not as expected.
  MBEDTLS_ERR_PKCS12_PASSWORD_MISMATCH   = -$1E00; // Given private key password does not allow for correct decryption.

  MBEDTLS_ERR_X509_FEATURE_UNAVAILABLE = -$2080; // Unavailable feature, e.g. RSA hashing/encryption combination.
  MBEDTLS_ERR_X509_UNKNOWN_OID         = -$2100; // Requested OID is unknown.
  MBEDTLS_ERR_X509_INVALID_FORMAT      = -$2180; // The CRT/CRL/CSR format is invalid, e.g. different type expected.
  MBEDTLS_ERR_X509_INVALID_VERSION     = -$2200; // The CRT/CRL/CSR version element is invalid.
  MBEDTLS_ERR_X509_INVALID_SERIAL      = -$2280; // The serial tag or value is invalid.
  MBEDTLS_ERR_X509_INVALID_ALG         = -$2300; // The algorithm tag or value is invalid.
  MBEDTLS_ERR_X509_INVALID_NAME        = -$2380; // The name tag or value is invalid.
  MBEDTLS_ERR_X509_INVALID_DATE        = -$2400; // The date tag or value is invalid.
  MBEDTLS_ERR_X509_INVALID_SIGNATURE   = -$2480; // The signature tag or value invalid.
  MBEDTLS_ERR_X509_INVALID_EXTENSIONS  = -$2500; // The extension tag or value is invalid.
  MBEDTLS_ERR_X509_UNKNOWN_VERSION     = -$2580; // CRT/CRL/CSR has an unsupported version number.
  MBEDTLS_ERR_X509_UNKNOWN_SIG_ALG     = -$2600; // Signature algorithm (oid) is unsupported.
  MBEDTLS_ERR_X509_SIG_MISMATCH        = -$2680; // Signature algorithms do not match. (see \c ::mbedtls_x509_crt sig_oid)
  MBEDTLS_ERR_X509_CERT_VERIFY_FAILED  = -$2700; // Certificate verification failed, e.g. CRL, CA or signature check failed.
  MBEDTLS_ERR_X509_CERT_UNKNOWN_FORMAT = -$2780; // Format not recognized as DER or PEM.
  MBEDTLS_ERR_X509_BAD_INPUT_DATA      = -$2800; // Input invalid.
  MBEDTLS_ERR_X509_ALLOC_FAILED        = -$2880; // Allocation of memory failed.
  MBEDTLS_ERR_X509_FILE_IO_ERROR       = -$2900; // Read/write of file failed.
  MBEDTLS_ERR_X509_BUFFER_TOO_SMALL    = -$2980; // Destination buffer is too small.
  MBEDTLS_ERR_X509_FATAL_ERROR         = -$3000; // A fatal error occured, eg the chain is too long or the vrfy callback failed.

  MBEDTLS_ERR_PKCS5_BAD_INPUT_DATA      = -$2F80; // Bad input parameters to function.
  MBEDTLS_ERR_PKCS5_INVALID_FORMAT      = -$2F00; // Unexpected ASN.1 data.
  MBEDTLS_ERR_PKCS5_FEATURE_UNAVAILABLE = -$2E80; // Requested encryption or digest alg not available.
  MBEDTLS_ERR_PKCS5_PASSWORD_MISMATCH   = -$2E00; // Given private key password does not allow for correct decryption.

  MBEDTLS_ERR_DHM_BAD_INPUT_DATA     = -$3080; // Bad input parameters.
  MBEDTLS_ERR_DHM_READ_PARAMS_FAILED = -$3100; // Reading of the DHM parameters failed.
  MBEDTLS_ERR_DHM_MAKE_PARAMS_FAILED = -$3180; // Making of the DHM parameters failed.
  MBEDTLS_ERR_DHM_READ_PUBLIC_FAILED = -$3200; // Reading of the public values failed.
  MBEDTLS_ERR_DHM_MAKE_PUBLIC_FAILED = -$3280; // Making of the public value failed.
  MBEDTLS_ERR_DHM_CALC_SECRET_FAILED = -$3300; // Calculation of the DHM secret failed.
  MBEDTLS_ERR_DHM_INVALID_FORMAT     = -$3380; // The ASN.1 data is not formatted correctly.
  MBEDTLS_ERR_DHM_ALLOC_FAILED       = -$3400; // Allocation of memory failed.
  MBEDTLS_ERR_DHM_FILE_IO_ERROR      = -$3480; // Read or write of file failed.
  MBEDTLS_ERR_DHM_HW_ACCEL_FAILED    = -$3500; // DHM hardware accelerator failed.
  MBEDTLS_ERR_DHM_SET_GROUP_FAILED   = -$3580; // Setting the modulus and generator failed.

  MBEDTLS_ERR_PK_ALLOC_FAILED        = -$3F80; // Memory allocation failed.
  MBEDTLS_ERR_PK_TYPE_MISMATCH       = -$3F00; // Type mismatch, eg attempt to encrypt with an ECDSA key
  MBEDTLS_ERR_PK_BAD_INPUT_DATA      = -$3E80; // Bad input parameters to function.
  MBEDTLS_ERR_PK_FILE_IO_ERROR       = -$3E00; // Read/write of file failed.
  MBEDTLS_ERR_PK_KEY_INVALID_VERSION = -$3D80; // Unsupported key version
  MBEDTLS_ERR_PK_KEY_INVALID_FORMAT  = -$3D00; // Invalid key tag or value.
  MBEDTLS_ERR_PK_UNKNOWN_PK_ALG      = -$3C80; // Key algorithm is unsupported (only RSA and EC are supported).
  MBEDTLS_ERR_PK_PASSWORD_REQUIRED   = -$3C00; // Private key password can't be empty.
  MBEDTLS_ERR_PK_PASSWORD_MISMATCH   = -$3B80; // Given private key password does not allow for correct decryption.
  MBEDTLS_ERR_PK_INVALID_PUBKEY      = -$3B00; // The pubkey tag or value is invalid (only RSA and EC are supported).
  MBEDTLS_ERR_PK_INVALID_ALG         = -$3A80; // The algorithm tag or value is invalid.
  MBEDTLS_ERR_PK_UNKNOWN_NAMED_CURVE = -$3A00; // Elliptic curve is unsupported (only NIST curves are supported).
  MBEDTLS_ERR_PK_FEATURE_UNAVAILABLE = -$3980; // Unavailable feature, e.g. RSA disabled for RSA key.
  MBEDTLS_ERR_PK_SIG_LEN_MISMATCH    = -$3900; // The signature is valid but its length is less than expected.
  MBEDTLS_ERR_PK_HW_ACCEL_FAILED     = -$3880; // PK hardware accelerator failed.

  MBEDTLS_ERR_RSA_BAD_INPUT_DATA        = -$4080; // Bad input parameters to function.
  MBEDTLS_ERR_RSA_INVALID_PADDING       = -$4100; // Input data contains invalid padding and is rejected.
  MBEDTLS_ERR_RSA_KEY_GEN_FAILED        = -$4180; // Something failed during generation of a key.
  MBEDTLS_ERR_RSA_KEY_CHECK_FAILED      = -$4200; // Key failed to pass the validity check of the library.
  MBEDTLS_ERR_RSA_PUBLIC_FAILED         = -$4280; // The public key operation failed.
  MBEDTLS_ERR_RSA_PRIVATE_FAILED        = -$4300; // The private key operation failed.
  MBEDTLS_ERR_RSA_VERIFY_FAILED         = -$4380; // The PKCS#1 verification failed.
  MBEDTLS_ERR_RSA_OUTPUT_TOO_LARGE      = -$4400; // The output buffer for decryption is not large enough.
  MBEDTLS_ERR_RSA_RNG_FAILED            = -$4480; // The random generator failed to generate non-zeros.
  MBEDTLS_ERR_RSA_UNSUPPORTED_OPERATION = -$4500; // The implementation does not offer the requested operation, for example, because of security violations or lack of functionality.
  MBEDTLS_ERR_RSA_HW_ACCEL_FAILED       = -$4580; // RSA hardware accelerator failed.

  MBEDTLS_ERR_ECP_BAD_INPUT_DATA      = -$4F80; // Bad input parameters to function.
  MBEDTLS_ERR_ECP_BUFFER_TOO_SMALL    = -$4F00; // The buffer is too small to write to.
  MBEDTLS_ERR_ECP_FEATURE_UNAVAILABLE = -$4E80; // Requested curve not available.
  MBEDTLS_ERR_ECP_VERIFY_FAILED       = -$4E00; // The signature is not valid.
  MBEDTLS_ERR_ECP_ALLOC_FAILED        = -$4D80; // Memory allocation failed.
  MBEDTLS_ERR_ECP_RANDOM_FAILED       = -$4D00; // Generation of random value, such as (ephemeral) key, failed.
  MBEDTLS_ERR_ECP_INVALID_KEY         = -$4C80; // Invalid private or public key.
  MBEDTLS_ERR_ECP_SIG_LEN_MISMATCH    = -$4C00; // Signature is valid but shorter than the user-supplied length.
  MBEDTLS_ERR_ECP_HW_ACCEL_FAILED     = -$4B80; // ECP hardware accelerator failed.

  MBEDTLS_ERR_MD_FEATURE_UNAVAILABLE = -$5080; // The selected feature is not available.
  MBEDTLS_ERR_MD_BAD_INPUT_DATA      = -$5100; // Bad input parameters to function.
  MBEDTLS_ERR_MD_ALLOC_FAILED        = -$5180; // Failed to allocate memory.
  MBEDTLS_ERR_MD_FILE_IO_ERROR       = -$5200; // Opening or reading of file failed.
  MBEDTLS_ERR_MD_HW_ACCEL_FAILED     = -$5280; // MD hardware accelerator failed.

  MBEDTLS_ERR_CIPHER_FEATURE_UNAVAILABLE = -$6080; // The selected feature is not available.
  MBEDTLS_ERR_CIPHER_BAD_INPUT_DATA      = -$6100; // Bad input parameters.
  MBEDTLS_ERR_CIPHER_ALLOC_FAILED        = -$6180; // Failed to allocate memory.
  MBEDTLS_ERR_CIPHER_INVALID_PADDING     = -$6200; // Input data contains invalid padding and is rejected.
  MBEDTLS_ERR_CIPHER_FULL_BLOCK_EXPECTED = -$6280; // Decryption of block requires a full block.
  MBEDTLS_ERR_CIPHER_AUTH_FAILED         = -$6300; // Authentication failed (for AEAD modes).
  MBEDTLS_ERR_CIPHER_INVALID_CONTEXT     = -$6380; // The context is invalid. For example, because it was freed.
  MBEDTLS_ERR_CIPHER_HW_ACCEL_FAILED     = -$6400; // Cipher hardware accelerator failed.

  MBEDTLS_ERR_SSL_FEATURE_UNAVAILABLE           = -$7080; // The requested feature is not available.
  MBEDTLS_ERR_SSL_BAD_INPUT_DATA                = -$7100; // Bad input parameters to function.
  MBEDTLS_ERR_SSL_INVALID_MAC                   = -$7180; // Verification of the message MAC failed.
  MBEDTLS_ERR_SSL_INVALID_RECORD                = -$7200; // An invalid SSL record was received.
  MBEDTLS_ERR_SSL_CONN_EOF                      = -$7280; // The connection indicated an EOF.
  MBEDTLS_ERR_SSL_UNKNOWN_CIPHER                = -$7300; // An unknown cipher was received.
  MBEDTLS_ERR_SSL_NO_CIPHER_CHOSEN              = -$7380; // The server has no ciphersuites in common with the client.
  MBEDTLS_ERR_SSL_NO_RNG                        = -$7400; // No RNG was provided to the SSL module.
  MBEDTLS_ERR_SSL_NO_CLIENT_CERTIFICATE         = -$7480; // No client certification received from the client, but required by the authentication mode.
  MBEDTLS_ERR_SSL_CERTIFICATE_TOO_LARGE         = -$7500; // Our own certificate(s) is/are too large to send in an SSL message.
  MBEDTLS_ERR_SSL_CERTIFICATE_REQUIRED          = -$7580; // The own certificate is not set, but needed by the server.
  MBEDTLS_ERR_SSL_PRIVATE_KEY_REQUIRED          = -$7600; // The own private key or pre-shared key is not set, but needed.
  MBEDTLS_ERR_SSL_CA_CHAIN_REQUIRED             = -$7680; // No CA Chain is set, but required to operate.
  MBEDTLS_ERR_SSL_UNEXPECTED_MESSAGE            = -$7700; // An unexpected message was received from our peer.
  MBEDTLS_ERR_SSL_FATAL_ALERT_MESSAGE           = -$7780; // A fatal alert message was received from our peer.
  MBEDTLS_ERR_SSL_PEER_VERIFY_FAILED            = -$7800; // Verification of our peer failed.
  MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY             = -$7880; // The peer notified us that the connection is going to be closed.
  MBEDTLS_ERR_SSL_BAD_HS_CLIENT_HELLO           = -$7900; // Processing of the ClientHello handshake message failed.
  MBEDTLS_ERR_SSL_BAD_HS_SERVER_HELLO           = -$7980; // Processing of the ServerHello handshake message failed.
  MBEDTLS_ERR_SSL_BAD_HS_CERTIFICATE            = -$7A00; // Processing of the Certificate handshake message failed.
  MBEDTLS_ERR_SSL_BAD_HS_CERTIFICATE_REQUEST    = -$7A80; // Processing of the CertificateRequest handshake message failed.
  MBEDTLS_ERR_SSL_BAD_HS_SERVER_KEY_EXCHANGE    = -$7B00; // Processing of the ServerKeyExchange handshake message failed.
  MBEDTLS_ERR_SSL_BAD_HS_SERVER_HELLO_DONE      = -$7B80; // Processing of the ServerHelloDone handshake message failed.
  MBEDTLS_ERR_SSL_BAD_HS_CLIENT_KEY_EXCHANGE    = -$7C00; // Processing of the ClientKeyExchange handshake message failed.
  MBEDTLS_ERR_SSL_BAD_HS_CLIENT_KEY_EXCHANGE_RP = -$7C80; // Processing of the ClientKeyExchange handshake message failed in DHM / ECDH Read Public.
  MBEDTLS_ERR_SSL_BAD_HS_CLIENT_KEY_EXCHANGE_CS = -$7D00; // Processing of the ClientKeyExchange handshake message failed in DHM / ECDH Calculate Secret.
  MBEDTLS_ERR_SSL_BAD_HS_CERTIFICATE_VERIFY     = -$7D80; // Processing of the CertificateVerify handshake message failed.
  MBEDTLS_ERR_SSL_BAD_HS_CHANGE_CIPHER_SPEC     = -$7E00; // Processing of the ChangeCipherSpec handshake message failed.
  MBEDTLS_ERR_SSL_BAD_HS_FINISHED               = -$7E80; // Processing of the Finished handshake message failed.
  MBEDTLS_ERR_SSL_ALLOC_FAILED                  = -$7F00; // Memory allocation failed
  MBEDTLS_ERR_SSL_HW_ACCEL_FAILED               = -$7F80; // Hardware acceleration function returned with error
  MBEDTLS_ERR_SSL_HW_ACCEL_FALLTHROUGH          = -$6F80; // Hardware acceleration function skipped / left alone data
  MBEDTLS_ERR_SSL_COMPRESSION_FAILED            = -$6F00; // Processing of the compression / decompression failed
  MBEDTLS_ERR_SSL_BAD_HS_PROTOCOL_VERSION       = -$6E80; // Handshake protocol not within min/max boundaries
  MBEDTLS_ERR_SSL_BAD_HS_NEW_SESSION_TICKET     = -$6E00; // Processing of the NewSessionTicket handshake message failed.
  MBEDTLS_ERR_SSL_SESSION_TICKET_EXPIRED        = -$6D80; // Session ticket has expired.
  MBEDTLS_ERR_SSL_PK_TYPE_MISMATCH              = -$6D00; // Public key type mismatch (eg, asked for RSA key exchange and presented EC key)
  MBEDTLS_ERR_SSL_UNKNOWN_IDENTITY              = -$6C80; // Unknown identity received (eg, PSK identity)
  MBEDTLS_ERR_SSL_INTERNAL_ERROR                = -$6C00; // Internal error (eg, unexpected failure in lower-level module)
  MBEDTLS_ERR_SSL_COUNTER_WRAPPING              = -$6B80; // A counter would wrap (eg, too many messages exchanged).
  MBEDTLS_ERR_SSL_WAITING_SERVER_HELLO_RENEGO   = -$6B00; // Unexpected message at ServerHello in renegotiation.
  MBEDTLS_ERR_SSL_HELLO_VERIFY_REQUIRED         = -$6A80; // DTLS client must retry for hello verification
  MBEDTLS_ERR_SSL_BUFFER_TOO_SMALL              = -$6A00; // A buffer is too small to receive or write a message
  MBEDTLS_ERR_SSL_NO_USABLE_CIPHERSUITE         = -$6980; // None of the common ciphersuites is usable (eg, no suitable certificate, see debug messages).
  MBEDTLS_ERR_SSL_WANT_READ                     = -$6900; // Connection requires a read call.
  MBEDTLS_ERR_SSL_WANT_WRITE                    = -$6880; // Connection requires a write call.
  MBEDTLS_ERR_SSL_TIMEOUT                       = -$6800; // The operation timed out.
  MBEDTLS_ERR_SSL_CLIENT_RECONNECT              = -$6780; // The client initiated a reconnect from the same port.
  MBEDTLS_ERR_SSL_UNEXPECTED_RECORD             = -$6700; // Record header looks valid but is not expected.
  MBEDTLS_ERR_SSL_NON_FATAL                     = -$6680; // The alert message received indicates a non-fatal error.
  MBEDTLS_ERR_SSL_INVALID_VERIFY_HASH           = -$6600; // Couldn't set the hash for verifying CertificateVerify

  // Various constants

  MBEDTLS_SSL_MAJOR_VERSION_3 = 3;
  MBEDTLS_SSL_MINOR_VERSION_0 = 0; // SSL v3.0
  MBEDTLS_SSL_MINOR_VERSION_1 = 1; // TLS v1.0
  MBEDTLS_SSL_MINOR_VERSION_2 = 2; // TLS v1.1
  MBEDTLS_SSL_MINOR_VERSION_3 = 3; // TLS v1.2

  MBEDTLS_SSL_TRANSPORT_STREAM   = 0; // TLS
  MBEDTLS_SSL_TRANSPORT_DATAGRAM = 1; // DTLS

  MBEDTLS_SSL_MAX_HOST_NAME_LEN = 255; // Maximum host name defined in RFC 1035

  // RFC 6066 section 4, see also mfl_code_to_length in ssl_tls.c
  // NONE must be zero so that memset()ing structure to zero works

  MBEDTLS_SSL_MAX_FRAG_LEN_NONE    = 0; // don't use this extension
  MBEDTLS_SSL_MAX_FRAG_LEN_512     = 1; // MaxFragmentLength 2^9
  MBEDTLS_SSL_MAX_FRAG_LEN_1024    = 2; // MaxFragmentLength 2^10
  MBEDTLS_SSL_MAX_FRAG_LEN_2048    = 3; // MaxFragmentLength 2^11
  MBEDTLS_SSL_MAX_FRAG_LEN_4096    = 4; // MaxFragmentLength 2^12
  MBEDTLS_SSL_MAX_FRAG_LEN_INVALID = 5; // first invalid value

  MBEDTLS_SSL_IS_CLIENT = 0;
  MBEDTLS_SSL_IS_SERVER = 1;

  MBEDTLS_SSL_IS_NOT_FALLBACK = 0;
  MBEDTLS_SSL_IS_FALLBACK     = 1;

  MBEDTLS_SSL_EXTENDED_MS_DISABLED = 0;
  MBEDTLS_SSL_EXTENDED_MS_ENABLED  = 1;

  MBEDTLS_SSL_ETM_DISABLED = 0;
  MBEDTLS_SSL_ETM_ENABLED  = 1;

  MBEDTLS_SSL_COMPRESS_NULL    = 0;
  MBEDTLS_SSL_COMPRESS_DEFLATE = 1;

  MBEDTLS_SSL_VERIFY_NONE     = 0;
  MBEDTLS_SSL_VERIFY_OPTIONAL = 1;
  MBEDTLS_SSL_VERIFY_REQUIRED = 2;
  MBEDTLS_SSL_VERIFY_UNSET    = 3; // Used only for sni_authmode

  MBEDTLS_SSL_LEGACY_RENEGOTIATION = 0;
  MBEDTLS_SSL_SECURE_RENEGOTIATION = 1;

  MBEDTLS_SSL_RENEGOTIATION_DISABLED = 0;
  MBEDTLS_SSL_RENEGOTIATION_ENABLED  = 1;

  MBEDTLS_SSL_ANTI_REPLAY_DISABLED = 0;
  MBEDTLS_SSL_ANTI_REPLAY_ENABLED  = 1;

  MBEDTLS_SSL_RENEGOTIATION_NOT_ENFORCED = -1;
  MBEDTLS_SSL_RENEGO_MAX_RECORDS_DEFAULT = 16;

  MBEDTLS_SSL_LEGACY_NO_RENEGOTIATION    = 0;
  MBEDTLS_SSL_LEGACY_ALLOW_RENEGOTIATION = 1;
  MBEDTLS_SSL_LEGACY_BREAK_HANDSHAKE     = 2;

  MBEDTLS_SSL_TRUNC_HMAC_DISABLED = 0;
  MBEDTLS_SSL_TRUNC_HMAC_ENABLED  = 1;
  MBEDTLS_SSL_TRUNCATED_HMAC_LEN  = 10; // 80 bits, rfc 6066 section 7

  MBEDTLS_SSL_SESSION_TICKETS_DISABLED = 0;
  MBEDTLS_SSL_SESSION_TICKETS_ENABLED  = 1;

  MBEDTLS_SSL_CBC_RECORD_SPLITTING_DISABLED = 0;
  MBEDTLS_SSL_CBC_RECORD_SPLITTING_ENABLED  = 1;

  MBEDTLS_SSL_ARC4_ENABLED  = 0;
  MBEDTLS_SSL_ARC4_DISABLED = 1;

  MBEDTLS_SSL_PRESET_DEFAULT = 0;
  MBEDTLS_SSL_PRESET_SUITEB  = 2;

  MBEDTLS_SSL_CERT_REQ_CA_LIST_ENABLED  = 1;
  MBEDTLS_SSL_CERT_REQ_CA_LIST_DISABLED = 0;

  // Default range for DTLS retransmission timer value, in milliseconds.
  // RFC 6347 4.2.4.1 says from 1 second to 60 seconds.

  MBEDTLS_SSL_DTLS_TIMEOUT_DFL_MIN = 1000;
  MBEDTLS_SSL_DTLS_TIMEOUT_DFL_MAX = 60000;

  MBEDTLS_SSL_INITIAL_HANDSHAKE         = 0;
  MBEDTLS_SSL_RENEGOTIATION_IN_PROGRESS = 1; // In progress
  MBEDTLS_SSL_RENEGOTIATION_DONE        = 2; // Done or aborted
  MBEDTLS_SSL_RENEGOTIATION_PENDING     = 3; // Requested (server only)

  MBEDTLS_SSL_RETRANS_PREPARING = 0;
  MBEDTLS_SSL_RETRANS_SENDING   = 1;
  MBEDTLS_SSL_RETRANS_WAITING   = 2;
  MBEDTLS_SSL_RETRANS_FINISHED  = 3;

  MBEDTLS_SSL_MSG_CHANGE_CIPHER_SPEC = 20;
  MBEDTLS_SSL_MSG_ALERT              = 21;
  MBEDTLS_SSL_MSG_HANDSHAKE          = 22;
  MBEDTLS_SSL_MSG_APPLICATION_DATA   = 23;

  MBEDTLS_SSL_ALERT_LEVEL_WARNING = 1;
  MBEDTLS_SSL_ALERT_LEVEL_FATAL   = 2;

  MBEDTLS_SSL_ALERT_MSG_CLOSE_NOTIFY            = 0; // 0x00
  MBEDTLS_SSL_ALERT_MSG_UNEXPECTED_MESSAGE      = 10; // 0x0A
  MBEDTLS_SSL_ALERT_MSG_BAD_RECORD_MAC          = 20; // 0x14
  MBEDTLS_SSL_ALERT_MSG_DECRYPTION_FAILED       = 21; // 0x15
  MBEDTLS_SSL_ALERT_MSG_RECORD_OVERFLOW         = 22; // 0x16
  MBEDTLS_SSL_ALERT_MSG_DECOMPRESSION_FAILURE   = 30; // 0x1E
  MBEDTLS_SSL_ALERT_MSG_HANDSHAKE_FAILURE       = 40; // 0x28
  MBEDTLS_SSL_ALERT_MSG_NO_CERT                 = 41; // 0x29
  MBEDTLS_SSL_ALERT_MSG_BAD_CERT                = 42; // 0x2A
  MBEDTLS_SSL_ALERT_MSG_UNSUPPORTED_CERT        = 43; // 0x2B
  MBEDTLS_SSL_ALERT_MSG_CERT_REVOKED            = 44; // 0x2C
  MBEDTLS_SSL_ALERT_MSG_CERT_EXPIRED            = 45; // 0x2D
  MBEDTLS_SSL_ALERT_MSG_CERT_UNKNOWN            = 46; // 0x2E
  MBEDTLS_SSL_ALERT_MSG_ILLEGAL_PARAMETER       = 47; // 0x2F
  MBEDTLS_SSL_ALERT_MSG_UNKNOWN_CA              = 48; // 0x30
  MBEDTLS_SSL_ALERT_MSG_ACCESS_DENIED           = 49; // 0x31
  MBEDTLS_SSL_ALERT_MSG_DECODE_ERROR            = 50; // 0x32
  MBEDTLS_SSL_ALERT_MSG_DECRYPT_ERROR           = 51; // 0x33
  MBEDTLS_SSL_ALERT_MSG_EXPORT_RESTRICTION      = 60; // 0x3C
  MBEDTLS_SSL_ALERT_MSG_PROTOCOL_VERSION        = 70; // 0x46
  MBEDTLS_SSL_ALERT_MSG_INSUFFICIENT_SECURITY   = 71; // 0x47
  MBEDTLS_SSL_ALERT_MSG_INTERNAL_ERROR          = 80; // 0x50
  MBEDTLS_SSL_ALERT_MSG_INAPROPRIATE_FALLBACK   = 86; // 0x56
  MBEDTLS_SSL_ALERT_MSG_USER_CANCELED           = 90; // 0x5A
  MBEDTLS_SSL_ALERT_MSG_NO_RENEGOTIATION        = 100; // 0x64
  MBEDTLS_SSL_ALERT_MSG_UNSUPPORTED_EXT         = 110; // 0x6E
  MBEDTLS_SSL_ALERT_MSG_UNRECOGNIZED_NAME       = 112; // 0x70
  MBEDTLS_SSL_ALERT_MSG_UNKNOWN_PSK_IDENTITY    = 115; // 0x73
  MBEDTLS_SSL_ALERT_MSG_NO_APPLICATION_PROTOCOL = 120; // 0x78

  MBEDTLS_SSL_HS_HELLO_REQUEST        = 0;
  MBEDTLS_SSL_HS_CLIENT_HELLO         = 1;
  MBEDTLS_SSL_HS_SERVER_HELLO         = 2;
  MBEDTLS_SSL_HS_HELLO_VERIFY_REQUEST = 3;
  MBEDTLS_SSL_HS_NEW_SESSION_TICKET   = 4;
  MBEDTLS_SSL_HS_CERTIFICATE          = 11;
  MBEDTLS_SSL_HS_SERVER_KEY_EXCHANGE  = 12;
  MBEDTLS_SSL_HS_CERTIFICATE_REQUEST  = 13;
  MBEDTLS_SSL_HS_SERVER_HELLO_DONE    = 14;
  MBEDTLS_SSL_HS_CERTIFICATE_VERIFY   = 15;
  MBEDTLS_SSL_HS_CLIENT_KEY_EXCHANGE  = 16;
  MBEDTLS_SSL_HS_FINISHED             = 20;

  // TLS extensions
  MBEDTLS_TLS_EXT_SERVERNAME                = 0;
  MBEDTLS_TLS_EXT_SERVERNAME_HOSTNAME       = 0;
  MBEDTLS_TLS_EXT_MAX_FRAGMENT_LENGTH       = 1;
  MBEDTLS_TLS_EXT_TRUNCATED_HMAC            = 4;
  MBEDTLS_TLS_EXT_SUPPORTED_ELLIPTIC_CURVES = 10;
  MBEDTLS_TLS_EXT_SUPPORTED_POINT_FORMATS   = 11;
  MBEDTLS_TLS_EXT_SIG_ALG                   = 13;
  MBEDTLS_TLS_EXT_ALPN                      = 16;
  MBEDTLS_TLS_EXT_ENCRYPT_THEN_MAC          = 22; // 0x16
  MBEDTLS_TLS_EXT_EXTENDED_MASTER_SECRET    = $0017; // 23
  MBEDTLS_TLS_EXT_SESSION_TICKET            = 35;
  MBEDTLS_TLS_EXT_ECJPAKE_KKPP              = 256; // experimental
  MBEDTLS_TLS_EXT_RENEGOTIATION_INFO        = $FF01;

  MBEDTLS_ENTROPY_SOURCE_STRONG = 1; // Entropy source is strong
  MBEDTLS_ENTROPY_SOURCE_WEAK   = 0; // Entropy source is weak

{$REGION 'libmbedcrypto'}
function mbedtls_entropy_add_source(ctx: PMbedtls_Entropy_Context; f_source: TEntropyFunc; p_source: Pointer; threshold: Size_T; strong: Integer): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_entropy_add_source';
procedure mbedtls_entropy_free(ctx: PMbedtls_Entropy_Context); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_entropy_free';
function mbedtls_entropy_func(data: Pointer; output: MarshaledAString; len: Size_T): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_entropy_func';
procedure mbedtls_entropy_init(ctx: PMbedtls_Entropy_Context); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_entropy_init';

procedure mbedtls_ctr_drbg_init(ctx: PMbedtls_CTR_DRBG_Context); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_ctr_drbg_init';
function mbedtls_ctr_drbg_seed(ctx: PMbedtls_CTR_DRBG_Context; f_entropy: TEntropyFunc; p_entropy: Pointer; custom: MarshaledAString; len: Size_T): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_ctr_drbg_seed';
function mbedtls_ctr_drbg_random_with_add(p_rng: Pointer; output: MarshaledAString; output_len: Size_T; additional: MarshaledAString; add_len: Size_T): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_ctr_drbg_random_with_add';
function mbedtls_ctr_drbg_random(p_rng: Pointer; output: MarshaledAString; output_len: Size_T): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_ctr_drbg_random';
procedure mbedtls_ctr_drbg_free(ctx: PMbedtls_CTR_DRBG_Context); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_ctr_drbg_free';

function mbedtls_pk_parse_key(pk: PMbedtls_PK_Context; key: PByte; keylen: Size_T; pwd: PByte; pwdlen: Size_T): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_pk_parse_key';

procedure mbedtls_pk_init(ctx: PMbedtls_PK_Context); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_pk_init';
procedure mbedtls_pk_free(ctx: PMbedtls_PK_Context); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_pk_free';

function mbedtls_version_get_number: Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_version_get_number';
procedure mbedtls_version_get_string(string_: MarshaledAString); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_version_get_string';
procedure mbedtls_version_get_string_full(string_: MarshaledAString); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_version_get_string_full';

procedure mbedtls_strerror(errnum: Integer; buffer: MarshaledAString; buflen: Size_T); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_strerror';

procedure mbedtls_threading_set_alt(_mutex_init: Pointer; _mutex_free: Pointer; _mutex_lock: Pointer; _mutex_unlock: Pointer); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_threading_set_alt';
procedure mbedtls_threading_free_alt; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_CRYPTO{$ENDIF} name _PU + 'mbedtls_threading_free_alt';
{$ENDREGION}

{$REGION 'libmbedtls'}
function mbedtls_ssl_close_notify(ssl: PMbedtls_SSL_Context): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_close_notify';
procedure mbedtls_ssl_free(ssl: PMbedtls_SSL_Context); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_free';
function mbedtls_ssl_get_verify_result(ssl: PMbedtls_SSL_Context): UInt32_T; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_get_verify_result';
function mbedtls_ssl_get_ciphersuite(const ssl: PMbedtls_SSL_Context): MarshaledAString; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_get_ciphersuite';
function mbedtls_ssl_get_version(const ssl: PMbedtls_SSL_Context): MarshaledAString; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_get_version';
function mbedtls_ssl_get_max_frag_len(const ssl: PMbedtls_SSL_Context): Size_T; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_get_max_frag_len';
function mbedtls_ssl_get_peer_cert(const ssl: PMbedtls_SSL_Context): PMbedtls_X509_CRT; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_get_peer_cert';
function mbedtls_ssl_get_session(const ssl: PMbedtls_SSL_Context; session: PMbedtls_SSL_Session): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_get_session';
function mbedtls_ssl_get_ciphersuite_name(const ciphersuite_id: Integer): MarshaledAString; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_get_ciphersuite_name';
function mbedtls_ssl_get_ciphersuite_id(const ciphersuite_name: MarshaledAString): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_get_ciphersuite_id';
function mbedtls_ssl_handshake(ssl: PMbedtls_SSL_Context): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_handshake';
procedure mbedtls_ssl_init(ssl: PMbedtls_SSL_Context); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_init';
function mbedtls_ssl_list_ciphersuites: PInteger; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_list_ciphersuites';
function mbedtls_ssl_read(ssl: PMbedtls_SSL_Context; buf: Pointer; len: Size_T): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_read';
function mbedtls_ssl_set_hostname(ssl: PMbedtls_SSL_Context; hostname: MarshaledAString): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_set_hostname';
procedure mbedtls_ssl_set_bio(ssl: PMbedtls_SSL_Context; p_bio: Pointer; f_send: TNetSendFunc; f_recv: TNetRecvFunc; f_recv_timeout: TNetRecvTimeoutFunc); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_set_bio';
procedure mbedtls_ssl_set_timer_cb(ssl: PMbedtls_SSL_Context; p_timer: Pointer; f_set_timer: TSetTimerFunc; f_get_timer: TGetTimerFunc); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_set_timer_cb';
function mbedtls_ssl_setup(ssl: PMbedtls_SSL_Context; conf: PMbedtls_SSL_Config): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_setup';
function mbedtls_ssl_write(ssl: PMbedtls_SSL_Context; const buf: Pointer; len: Size_T): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_write';

procedure mbedtls_ssl_cache_init(cache: PMbedtls_SSL_Cache_Context); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_cache_init';

procedure mbedtls_ssl_config_init(conf: PMbedtls_SSL_Config); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_config_init';
function mbedtls_ssl_config_defaults(conf: PMbedtls_SSL_Config; endpoint: Integer; transport: Integer; preset: Integer): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_config_defaults';
procedure mbedtls_ssl_conf_authmode(conf: PMbedtls_SSL_Config; authmode: Integer); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_conf_authmode';
procedure mbedtls_ssl_conf_ca_chain(conf: PMbedtls_SSL_Config; ca_chain: PMbedtls_X509_CRT; ca_crl: PMbedtls_X509_Crl); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_conf_ca_chain';
procedure mbedtls_ssl_conf_transport(conf: PMbedtls_SSL_Config; transport: Integer); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_conf_transport';
procedure mbedtls_ssl_conf_rng(conf: PMbedtls_SSL_Config; f_rng: TrngFunc; p_rng: Pointer); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_conf_rng';
procedure mbedtls_ssl_conf_dbg(conf: PMbedtls_SSL_Config; f_dbg: TdbgFunc; p_dbg: Pointer); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_conf_dbg';
procedure mbedtls_ssl_config_free(conf: PMbedtls_SSL_Config); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_config_free';

procedure mbedtls_ssl_conf_ciphersuites(conf: PMbedtls_SSL_Config; ciphersuites: PInteger); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_conf_ciphersuites';

function mbedtls_ssl_session_reset(ssl: PMbedtls_SSL_Context): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_session_reset';
function mbedtls_ssl_set_session(ssl: PMbedtls_SSL_Context; const session: PMbedtls_SSL_Session): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_set_session';
procedure mbedtls_ssl_conf_max_version(conf: PMbedtls_SSL_Config; major, minor: Integer); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_conf_max_version';
procedure mbedtls_ssl_conf_min_version(conf: PMbedtls_SSL_Config; major, minor: Integer); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_conf_min_version';
function mbedtls_ssl_get_bytes_avail(ssl: PMbedtls_SSL_Context): Size_T; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_get_bytes_avail';

procedure mbedtls_ssl_conf_session_cache(conf: PMbedtls_SSL_Config; p_cache: Pointer; f_get_cache: TGetCacheFunc; f_set_cache: TSetCacheFunc); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_conf_session_cache';

function mbedtls_ssl_cache_get(data: Pointer; session: PMbedtls_SSL_Session): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_cache_get';
function mbedtls_ssl_cache_set(data: Pointer; const session: PMbedtls_SSL_Session): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_cache_set';

function mbedtls_ssl_conf_own_cert(conf: PMbedtls_SSL_Config; own_cert: PMbedtls_X509_CRT; pk_key: PMbedtls_PK_Context): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_conf_own_cert';

procedure mbedtls_ssl_cache_free(cache: PMbedtls_SSL_Cache_Context); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_cache_free';
{$ENDREGION}

{$REGION 'libmbedx509'}
procedure mbedtls_x509_crt_init(crt: PMbedtls_X509_CRT); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_X509{$ENDIF} name _PU + 'mbedtls_x509_crt_init';
procedure mbedtls_x509_crt_free(crt: PMbedtls_X509_CRT); cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_X509{$ENDIF} name _PU + 'mbedtls_x509_crt_free';
function mbedtls_x509_crt_parse(chain: PMbedtls_X509_CRT; buf: PByte; buflen: Size_T): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_X509{$ENDIF} name _PU + 'mbedtls_x509_crt_parse';
function mbedtls_x509_crt_verify_info(buf: MarshaledAString; size_: Size_T; const prefix: MarshaledAString; flags: UInt32_T): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_X509{$ENDIF} name _PU + 'mbedtls_x509_crt_verify_info';
{$ENDREGION}

type
  TMbedtls_Cipher_ID = (
    MBEDTLS_CIPHER_ID_NONE = 0, // **< Placeholder to mark the end of cipher ID lists.
    MBEDTLS_CIPHER_ID_NULL,     // **< The identity cipher, treated as a stream cipher.
    MBEDTLS_CIPHER_ID_AES,      // **< The AES cipher.
    MBEDTLS_CIPHER_ID_DES,      // **< The DES cipher.
    MBEDTLS_CIPHER_ID_3DES,     // **< The Triple DES cipher.
    MBEDTLS_CIPHER_ID_CAMELLIA, // **< The Camellia cipher.
    MBEDTLS_CIPHER_ID_BLOWFISH, // **< The Blowfish cipher.
    MBEDTLS_CIPHER_ID_ARC4,     // **< The RC4 cipher.
    MBEDTLS_CIPHER_ID_ARIA,     // **< The Aria cipher.
    MBEDTLS_CIPHER_ID_CHACHA20  // **< The ChaCha20 cipher.
  );

  TMbedtls_Cipher_Mode = (
    MBEDTLS_MODE_NONE = 0,  // **< None.
    MBEDTLS_MODE_ECB,       // **< The ECB cipher mode.
    MBEDTLS_MODE_CBC,       // **< The CBC cipher mode.
    MBEDTLS_MODE_CFB,       // **< The CFB cipher mode.
    MBEDTLS_MODE_OFB,       // **< The OFB cipher mode.
    MBEDTLS_MODE_CTR,       // **< The CTR cipher mode.
    MBEDTLS_MODE_GCM,       // **< The GCM cipher mode.
    MBEDTLS_MODE_STREAM,    // **< The stream cipher mode.
    MBEDTLS_MODE_CCM,       // **< The CCM cipher mode.
    MBEDTLS_MODE_XTS,       // **< The XTS cipher mode.
    MBEDTLS_MODE_CHACHAPOLY // **< The ChaCha-Poly cipher mode.
  );

function mbedtls_ssl_handshake_client_step(ssl: PMbedtls_SSL_Context): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_handshake_client_step';

function mbedtls_ssl_handshake_server_step(ssl: PMbedtls_SSL_Context): Integer; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_ssl_handshake_server_step';

function mbedtls_cipher_info_from_values(const cipher_id: TMbedtls_Cipher_ID; key_bitlen: Integer; const mode: TMbedtls_Cipher_Mode): PMbedtls_Cipher_Info; cdecl; external {$IFDEF __HAS_MBED_TLS_LIB__}LIB_MBED_TLS{$ENDIF} name _PU + 'mbedtls_cipher_info_from_values';
{$ENDREGION}

function MbedErrToStr(AErrCode: Integer): string;

implementation

{$IFDEF __HAS_MBED_TLS_OBJ__}
  {$L aesni.obj}
  {$L aria.obj}
  {$L cmac.obj}
  {$L ctr_drbg.obj}
  {$L entropy.obj}
  {$L entropy_poll.obj}
  {$L error.obj}
  {$L havege.obj}
  {$L hkdf.obj}
  {$L md2.obj}
  {$L md4.obj}
  {$L memory_buffer_alloc.obj}
  {$L nist_kw.obj}
  {$L pkcs11.obj}
  {$L ssl_cache.obj}
  {$L ssl_cookie.obj}
  {$L ssl_ticket.obj}
  {$L threading.obj}
  {$L timing.obj}
  {$L version.obj}
  {$L version_features.obj}
  {$L x509write_crt.obj}
  {$L x509write_csr.obj}
  {$L x509_create.obj}
  {$L x509_crl.obj}
  {$L x509_csr.obj}
  {$L xtea.obj}
  {$L asn1write.obj}
  {$L pem.obj}
  {$L platform.obj}
  {$L pkwrite.obj}
  {$L pkparse.obj}
  {$L base64.obj}
  {$L pkcs12.obj}
  {$L pkcs5.obj}
  {$L arc4.obj}
  {$L ssl_cli.obj}
  {$L ssl_srv.obj}
  {$L ssl_tls.obj}
  {$L ssl_ciphersuites.obj}
  {$L debug.obj}
  {$L x509_crt.obj}
  {$L pk.obj}
  {$L pk_wrap.obj}
  {$L x509.obj}
  {$L platform_util.obj}
  {$L rsa.obj}
  {$L rsa_internal.obj}
  {$L oid.obj}
  {$L ecjpake.obj}
  {$L ecdsa.obj}
  {$L ecdh.obj}
  {$L ecp.obj}
  {$L hmac_drbg.obj}
  {$L dhm.obj}
  {$L ecp_curves.obj}
  {$L asn1parse.obj}
  {$L md.obj}
  {$L md_wrap.obj}
  {$L cipher.obj}
  {$L cipher_wrap.obj}
  {$L ccm.obj}
  {$L gcm.obj}
  {$L aes.obj}
  {$L camellia.obj}
  {$L des.obj}
  {$L blowfish.obj}
  {$L chachapoly.obj}
  {$L chacha20.obj}
  {$L md5.obj}
  {$L ripemd160.obj}
  {$L sha1.obj}
  {$L sha256.obj}
  {$L sha512.obj}
  {$L poly1305.obj}
  {$L bignum.obj}
{$ENDIF}

{$IFDEF __HAS_MBED_TLS_O__}
  {$L aesni.o}
  {$L aria.o}
  {$L cmac.o}
  {$L ctr_drbg.o}
  {$L entropy.o}
  {$L entropy_poll.o}
  {$L error.o}
  {$L havege.o}
  {$L hkdf.o}
  {$L md2.o}
  {$L md4.o}
  {$L memory_buffer_alloc.o}
  {$L nist_kw.o}
  {$L pkcs11.o}
  {$L ssl_cache.o}
  {$L ssl_cookie.o}
  {$L ssl_ticket.o}
  {$L threading.o}
  {$L timing.o}
  {$L version.o}
  {$L version_features.o}
  {$L x509write_crt.o}
  {$L x509write_csr.o}
  {$L x509_create.o}
  {$L x509_crl.o}
  {$L x509_csr.o}
  {$L xtea.o}
  {$L asn1write.o}
  {$L pem.o}
  {$L platform.o}
  {$L pkwrite.o}
  {$L pkparse.o}
  {$L base64.o}
  {$L pkcs12.o}
  {$L pkcs5.o}
  {$L arc4.o}
  {$L ssl_cli.o}
  {$L ssl_srv.o}
  {$L ssl_tls.o}
  {$L ssl_ciphersuites.o}
  {$L debug.o}
  {$L x509_crt.o}
  {$L pk.o}
  {$L pk_wrap.o}
  {$L x509.o}
  {$L platform_util.o}
  {$L rsa.o}
  {$L rsa_internal.o}
  {$L oid.o}
  {$L ecjpake.o}
  {$L ecdsa.o}
  {$L ecdh.o}
  {$L ecp.o}
  {$L hmac_drbg.o}
  {$L dhm.o}
  {$L ecp_curves.o}
  {$L asn1parse.o}
  {$L md.o}
  {$L md_wrap.o}
  {$L cipher.o}
  {$L cipher_wrap.o}
  {$L ccm.o}
  {$L gcm.o}
  {$L aes.o}
  {$L camellia.o}
  {$L des.o}
  {$L blowfish.o}
  {$L chachapoly.o}
  {$L chacha20.o}
  {$L md5.o}
  {$L ripemd160.o}
  {$L sha1.o}
  {$L sha256.o}
  {$L sha512.o}
  {$L poly1305.o}
  {$L bignum.o}
{$ENDIF}

{$IFDEF MSWINDOWS}
type
  HCRYPTPROV = ULONG_PTR;

function CryptAcquireContextA(var phProv: HCRYPTPROV; pszContainer, pszProvider: LPCSTR; dwProvType, dwFlags: DWORD): BOOL; stdcall; external advapi32;

function CryptGenRandom(hProv: HCRYPTPROV; dwLen: DWORD; pbBuffer: LPBYTE): BOOL; stdcall; external advapi32;

function CryptReleaseContext(hProv: HCRYPTPROV; dwFlags: ULONG_PTR): BOOL; stdcall; external advapi32;
{$ENDIF}

procedure _mutex_init(mutex: PTlsMutex); cdecl;
begin
  mutex.Lock := TObject.Create;
end;

procedure _mutex_free(mutex: PTlsMutex); cdecl;
begin
  mutex.Lock.DisposeOf;
end;

function _mutex_lock(mutex: PTlsMutex): Integer; cdecl;
begin
  Result := 0;
  System.TMonitor.Enter(mutex.Lock);
end;

function _mutex_unlock(mutex: PTlsMutex): Integer; cdecl;
begin
  Result := 0;
  System.TMonitor.Exit(mutex.Lock);
end;

function MbedErrToStr(AErrCode: Integer): string;
var
  LBuf: array [0 .. 511] of Byte;
begin
  mbedtls_strerror(AErrCode, @LBuf, 512);
  Result := TMarshal.ReadStringAsAnsi(TPtrWrapper.Create(@LBuf));
end;

{$IFDEF WIN32}
function _calloc(nitems: Size_T; size: Size_T): Pointer; cdecl;
begin
  Result := AllocMem(nitems * size);
end;

procedure __llmul; cdecl;
asm
  jmp System.@_llmul
end;

procedure __lludiv; cdecl;
asm
  jmp System.@_lludiv
end;

procedure __llumod; cdecl;
asm
  jmp System.@_llumod
end;

procedure __lldiv; cdecl;
asm
  jmp System.@_lldiv
end;

procedure __llshl; cdecl;
asm
  jmp System.@_llshl
end;
{$ENDIF}

{$IFDEF WIN64}
function calloc(nitems: Size_T; size: Size_T): Pointer; cdecl;
begin
  Result := AllocMem(nitems * size);
end;

procedure __chkstk;
label
  _loop1, _exit;
asm
  lea r10,  [rsp]
  mov	r11,  r10
  sub	r11,  rax
  and	r11w, 0f000h
  and	r10w, 0f000h
  _loop1:
  sub	r10,  01000h
  cmp r10,  r11      // more to go?
  jl  _exit
  mov qword [r10], 0 // probe this page
  jmp _loop1
  _exit:
  ret
end;
{$ENDIF}

initialization
  mbedtls_threading_set_alt(@_mutex_init, @_mutex_free, @_mutex_lock, @_mutex_unlock);

finalization
  mbedtls_threading_free_alt;

end.
