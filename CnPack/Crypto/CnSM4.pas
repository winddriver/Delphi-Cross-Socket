{******************************************************************************}
{                       CnPack For Delphi/C++Builder                           }
{                     中国人自己的开放源码第三方开发包                         }
{                   (C)Copyright 2001-2026 CnPack 开发组                       }
{                   ------------------------------------                       }
{                                                                              }
{            本开发包是开源的自由软件，您可以遵照 CnPack 的发布协议来修        }
{        改和重新发布这一程序。                                                }
{                                                                              }
{            发布这一开发包的目的是希望它有用，但没有任何担保。甚至没有        }
{        适合特定目的而隐含的担保。更详细的情况请参阅 CnPack 发布协议。        }
{                                                                              }
{            您应该已经和开发包一起收到一份 CnPack 发布协议的副本。如果        }
{        还没有，可访问我们的网站：                                            }
{                                                                              }
{            网站地址：https://www.cnpack.org                                  }
{            电子邮件：master@cnpack.org                                       }
{                                                                              }
{******************************************************************************}

unit CnSM4;
{* |<PRE>
================================================================================
* 软件名称：开发包基础库
* 单元名称：国家商用密码 SM4 对称加解密算法实现单元
* 单元作者：CnPack 开发组（master@cnpack.org)
*           参考并部分移植了 goldboar 的 C 代码
* 备    注：本单元实现了国家商用密码 SM4 对称加解密算法，分块大小 16 字节，块运算实现了
*           的对齐方式均在末尾补 0。本单元内部不支持 PKCS 等块对齐方式，如需要，请在外部调用
*           CnPemUtils.pas 单元中的 PKCS 系列函数对加解密内容进行额外处理。
*           本单元的实现参考国密算法公开文档《SM4 Encryption alogrithm》。
*
*           另外高版本 Delphi 中请尽量避免使用 AnsiString 参数版本的函数（十六进制除外），
*           避免不可视字符出现乱码影响加解密结果。
*
*           ECB/CBC 是块模式，需要处理对齐。CFB/OFB/CTR 是异或明文密文的流模式，无需对齐到块。
*           另外，本单元中的 CTR 是 8 字节 Nonce 加 8 字节计数器作为内部 16 字节初始化向量的模式，
*           与有些其他场合用整个 16 字节 Iv 的后 4 或后 8 字节做计数器的不同，使用时需注意。
*
* 开发平台：Windows 7 + Delphi 5.0
* 兼容测试：PWin9X/2000/XP/7 + Delphi 5/6 + MaxOS 64
* 本 地 化：该单元中的字符串均符合本地化处理方式
* 修改记录：2025.01.22 V1.9
*               修正 CFB/OFB 模式下末尾非整数块时加解密可能超界的问题
*           2024.12.01 V1.8
*               去掉部分不必要的 const 参数修饰并调整注释
*           2022.07.21 V1.7
*               加入 CTR 模式的支持
*           2022.06.21 V1.6
*               加入几个字节数组到十六进制字符串之间的加解密函数
*           2022.04.26 V1.5
*               修改 LongWord 与 Integer 地址转换以支持 MacOS64
*           2022.04.19 V1.4
*               使用初始化向量时内部备份，不修改传入的内容
*           2021.12.12 V1.3
*               加入 CFB/OFB 模式的支持
*           2020.03.24 V1.2
*               增加部分封装函数包括流函数
*           2019.04.15 V1.1
*               支持 Win32/Win64/MacOS
*           2014.09.25 V1.0
*               移植并创建单元
================================================================================
|</PRE>}

interface

{$I CnPack.inc}

uses
  Classes, SysUtils, CnNative;

const
  CN_SM4_KEYSIZE = 16;
  {* SM4 的密钥长度 16 字节}

  CN_SM4_BLOCKSIZE = 16;
  {* SM4 的分块长度 16 字节}

  CN_SM4_NONCESIZE = 8;
  {* SM4 的 CTR 模式下的准初始化向量长度 8 字节}

type
  ECnSM4Exception = class(Exception);
  {* SM4 相关异常}

  TCnSM4Key    = array[0..CN_SM4_KEYSIZE - 1] of Byte;
  {* SM4 的加密 Key，16 字节}

  TCnSM4Buffer = array[0..CN_SM4_BLOCKSIZE - 1] of Byte;
  {* SM4 的加密块，16 字节}

  TCnSM4Iv     = array[0..CN_SM4_BLOCKSIZE - 1] of Byte;
  {* SM4 的 CBC/CFB/OFB 等的初始化向量，16 字节}

  TCnSM4Nonce  = array[0..CN_SM4_NONCESIZE - 1] of Byte;
  {* SM4 的 CTR 模式下的初始化向量 8 字节，与一个 8 字节计数器拼在一起作为真正的 16 字节 Iv}

  TCnSM4Context = packed record
  {* SM4 的上下文结构}
    Mode: Integer;                                       {!<  encrypt/decrypt }
    Sk: array[0..CN_SM4_KEYSIZE * 2 - 1] of Cardinal;    {!<  SM4 subkeys     }
  end;

function SM4GetOutputLengthFromInputLength(InputByteLength: Integer): Integer;
{* 根据输入明文字节长度计算其块对齐的输出长度。如果非块整数倍则向上增长至块整数倍。

   参数：
     InputByteLength: Integer             - 输入的明文字节长度

   返回值：Integer                        - 返回 SM4 块对齐后的长度
}

procedure SM4Encrypt(Key: PAnsiChar; Input: PAnsiChar; Output: PAnsiChar; ByteLen: Integer);
{* 原始的 SM4 加密数据块，块间使用 ECB 模式。将 Input 内的明文内容加密放入 Output 中，
   调用者自行保证 Key 指向内容至少 16 字节，Input 和 Output 指向内容长相等并且都为 ByteLen 字节
   且 ByteLen 必须被 16 整除。

   参数：
     Key: PAnsiChar                       - 16 字节 SM4 密钥
     Input: PAnsiChar                     - 待加密的数据块地址
     Output: PAnsiChar                    - 密文输出数据块地址
     ByteLen: Integer                     - 加解密数据块的字节长度

   返回值：（无）
}

procedure SM4Decrypt(Key: PAnsiChar; Input: PAnsiChar; Output: PAnsiChar; ByteLen: Integer);
{* 原始的 SM4 解密数据块，ECB 模式，将 Input 内的密文内容解密搁到 Output 中
  调用者自行保证 Key 指向内容至少需 16 字节，Input 和 Output 指向内容长相等并且都为 ByteLen 字节
  且 ByteLen 必须被 16 整除。

   参数：
     Key: PAnsiChar                       - 16 字节 SM4 密钥
     Input: PAnsiChar                     - 待解密的数据块地址
     Output: PAnsiChar                    - 明文输出数据块地址
     ByteLen: Integer                     - 加解密数据块的字节长度

   返回值：（无）
}

// ============== 明文字符串与密文十六进制字符串之间的加解密 ===================

procedure SM4EncryptEcbStr(Key: AnsiString; const Input: AnsiString; Output: PAnsiChar);
{* 针对 AnsiString 的 SM4 加密，块间使用 ECB 模式。

   参数：
     Key: AnsiString                      - 16 字节 SM4 密钥，太长则截断，不足则补 #0
     const Input: AnsiString              - 待加密的明文字符串，其长度如不是 16 的倍数，计算时会被填充 #0 至长度达到 16 的倍数
     Output: PAnsiChar                    - 密文输出区，其长度必须大于或等于 (((Length(Input) - 1) div 16) + 1) * 16

   返回值：（无）
}

procedure SM4DecryptEcbStr(Key: AnsiString; const Input: AnsiString; Output: PAnsiChar);
{* 针对 AnsiString 的 SM4 解密，块间使用 ECB 模式。

   参数：
     Key: AnsiString                      - 16 字节 SM4 密钥，太长则截断，不足则补 #0
     const Input: AnsiString              - 待解密的密文字符串，其长度如不是 16 的倍数，计算时会被填充 #0 至长度达到 16 的倍数
     Output: PAnsiChar                    - 明文输出区，其长度必须大于或等于 (((Length(Input) - 1) div 16) + 1) * 16

   返回值：（无）
}

procedure SM4EncryptCbcStr(Key: AnsiString; Iv: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
{* 针对 AnsiString 的 SM4 加密，块间使用 CBC 模式。

   参数：
     Key: AnsiString                      - 16 字节 SM4 密钥，太长则截断，不足则补 #0
     Iv: PAnsiChar                        - 16 字节初始化向量，注意有效内容必须大于或等于 16 字节
     const Input: AnsiString              - 待加密的明文字符串，其长度如不是 16 的倍数，计算时会被填充 #0 至长度达到 16 的倍数
     Output: PAnsiChar                    - 密文输出区，其长度必须大于或等于 (((Length(Input) - 1) div 16) + 1) * 16

   返回值：（无）
}

procedure SM4DecryptCbcStr(Key: AnsiString; Iv: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
{* 针对 AnsiString 的 SM4 解密，块间使用 CBC 模式。

   参数：
     Key: AnsiString                      - 16 字节 SM4 密钥，太长则截断，不足则补 #0
     Iv: PAnsiChar                        - 16 字节初始化向量，注意有效内容必须大于或等于 16 字节
     const Input: AnsiString              - 待解密的密文字符串，其长度如不是 16 的倍数，计算时会被填充 #0 至长度达到 16 的倍数
     Output: PAnsiChar                    - 密文输出区，其长度必须大于或等于 (((Length(Input) - 1) div 16) + 1) * 16

   返回值：（无）
}

procedure SM4EncryptCfbStr(Key: AnsiString; Iv: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
{* 针对 AnsiString 的 SM4 加密，块间使用 CFB 模式。

   参数：
     Key: AnsiString                      - 16 字节 SM4 密钥，太长则截断，不足则补 #0
     Iv: PAnsiChar                        - 16 字节初始化向量，注意有效内容必须大于或等于 16 字节
     const Input: AnsiString              - 待加密的明文字符串
     Output: PAnsiChar                    - 密文输出区，其长度必须大于或等于 Length(Input)

   返回值：（无）
}

procedure SM4DecryptCfbStr(Key: AnsiString; Iv: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
{* 针对 AnsiString 的 SM4 解密，块间使用 CFB 模式。

   参数：
     Key: AnsiString                      - 16 字节 SM4 密钥，太长则截断，不足则补 #0
     Iv: PAnsiChar                        - 16 字节初始化向量，注意有效内容必须大于或等于 16 字节
     const Input: AnsiString              - 待解密的密文字符串
     Output: PAnsiChar                    - 密文输出区，其长度必须大于或等于 Length(Input)

   返回值：（无）
}

procedure SM4EncryptOfbStr(Key: AnsiString; Iv: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
{* 针对 AnsiString 的 SM4 加密，块间使用 OFB 模式。

   参数：
     Key: AnsiString                      - 16 字节 SM4 密钥，太长则截断，不足则补 #0
     Iv: PAnsiChar                        - 16 字节初始化向量，注意有效内容必须大于或等于 16 字节
     const Input: AnsiString              - 待加密的明文字符串
     Output: PAnsiChar                    - 密文输出区，其长度必须大于或等于 Length(Input)

   返回值：（无）
}

procedure SM4DecryptOfbStr(Key: AnsiString; Iv: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
{* 针对 AnsiString 的 SM4 解密，块间使用 OFB 模式。

   参数：
     Key: AnsiString                      - 16 字节 SM4 密钥，太长则截断，不足则补 #0
     Iv: PAnsiChar                        - 16 字节初始化向量，注意有效内容必须大于或等于 16 字节
     const Input: AnsiString              - 待解密的密文字符串
     Output: PAnsiChar                    - 明文输出区，其长度必须大于或等于 Length(Input)

   返回值：（无）
}

procedure SM4EncryptCtrStr(Key: AnsiString; Nonce: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
{* 针对 AnsiString 的 SM4 加密，块间使用 CTR 模式。

   参数：
     Key: AnsiString                      - 16 字节 SM4 密钥，太长则截断，不足则补 #0
     Nonce: PAnsiChar                     - 8 字节初始化向量，注意有效内容必须大于或等于 8 字节
     const Input: AnsiString              - 待加密的明文字符串
     Output: PAnsiChar                    - 密文输出区，其长度必须大于或等于 Length(Input)

   返回值：（无）
}

procedure SM4DecryptCtrStr(Key: AnsiString; Nonce: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
{* 针对 AnsiString 的 SM4 解密，块间使用 CTR 模式。

   参数：
     Key: AnsiString                      - 16 字节 SM4 密钥，太长则截断，不足则补 #0
     Nonce: PAnsiChar                     - 8 字节初始化向量，注意有效内容必须大于或等于 8 字节
     const Input: AnsiString              - 待解密的密文字符串
     Output: PAnsiChar                    - 明文输出区，其长度必须大于或等于 Length(Input)

   返回值：（无）
}

// ================= 明文字节数组与密文字节数组之间的加解密 ====================

function SM4EncryptEcbBytes(Key: TBytes; Input: TBytes): TBytes;
{* 针对字节数组的 SM4 加密，块间使用 ECB 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Input: TBytes                        - 待加密的明文字节数组

   返回值：TBytes                         - 返回加密后的密文字节数组
}

function SM4DecryptEcbBytes(Key: TBytes; Input: TBytes): TBytes;
{* 针对字节数组的 SM4 解密，块间使用 ECB 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Input: TBytes                        - 待解密的密文字节数组

   返回值：TBytes                         - 返回解密后的明文字节数组
}

function SM4EncryptCbcBytes(Key: TBytes; Iv: TBytes; Input: TBytes): TBytes;
{* 针对字节数组的 SM4 加密，块间使用 CBC 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Iv: TBytes                           - 16 字节初始化向量，太长则截断，不足则补 0
     Input: TBytes                        - 待加密的明文字节数组

   返回值：TBytes                         - 返回加密后的密文字节数组
}

function SM4DecryptCbcBytes(Key: TBytes; Iv: TBytes; Input: TBytes): TBytes;
{* 针对字节数组的 SM4 解密，块间使用 CBC 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Iv: TBytes                           - 16 字节初始化向量，太长则截断，不足则补 0
     Input: TBytes                        - 待解密的密文字节数组

   返回值：TBytes                         - 返回解密后的明文字节数组
}

function SM4EncryptCfbBytes(Key: TBytes; Iv: TBytes; Input: TBytes): TBytes;
{* 针对字节数组的 SM4 加密，块间使用 CFB 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Iv: TBytes                           - 16 字节初始化向量，太长则截断，不足则补 0
     Input: TBytes                        - 待加密的明文字节数组

   返回值：TBytes                         - 返回加密后的密文字节数组
}

function SM4DecryptCfbBytes(Key: TBytes; Iv: TBytes; Input: TBytes): TBytes;
{* 针对字节数组的 SM4 解密，块间使用 CFB 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Iv: TBytes                           - 16 字节初始化向量，太长则截断，不足则补 0
     Input: TBytes                        - 待解密的密文字节数组

   返回值：TBytes                         - 返回解密后的明文字节数组
}

function SM4EncryptOfbBytes(Key: TBytes; Iv: TBytes; Input: TBytes): TBytes;
{* 针对字节数组的 SM4 加密，块间使用 OFB 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Iv: TBytes                           - 16 字节初始化向量，太长则截断，不足则补 0
     Input: TBytes                        - 待加密的明文字节数组

   返回值：TBytes                         - 返回加密后的密文字节数组
}

function SM4DecryptOfbBytes(Key: TBytes; Iv: TBytes; Input: TBytes): TBytes;
{* 针对字节数组的 SM4 解密，块间使用 OFB 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Iv: TBytes                           - 16 字节初始化向量，太长则截断，不足则补 0
     Input: TBytes                        - 待解密的密文字节数组

   返回值：TBytes                         - 返回解密后的明文字节数组
}

function SM4EncryptCtrBytes(Key: TBytes; Nonce: TBytes; Input: TBytes): TBytes;
{* 针对字节数组的 SM4 加密，块间使用 CTR 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Nonce: TBytes                        - 8 字节初始化向量，太长则截断，不足则补 0
     Input: TBytes                        - 待加密的明文字节数组

   返回值：TBytes                         - 返回加密后的密文字节数组
}

function SM4DecryptCtrBytes(Key: TBytes; Nonce: TBytes; Input: TBytes): TBytes;
{* 针对字节数组的 SM4 解密，块间使用 CTR 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Nonce: TBytes                        - 8 字节初始化向量，太长则截断，不足则补 0
     Input: TBytes                        - 待解密的密文字节数组

   返回值：TBytes                         - 返回解密后的明文字节数组
}

// ============== 明文字节数组与密文十六进制字符串之间的加解密 =================

function SM4EncryptEcbBytesToHex(Key: TBytes; Input: TBytes): AnsiString;
{* 传入明文与加密 Key，SM4 加密返回转换成十六进制的密文，块间使用 ECB 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Input: TBytes                        - 待加密的明文字节数组

   返回值：AnsiString                     - 返回加密后的十六进制密文字符串
}

function SM4DecryptEcbBytesFromHex(Key: TBytes; const Input: AnsiString): TBytes;
{* 传入十六进制的密文与加密 Key，SM4 解密返回明文，块间使用 ECB 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     const Input: AnsiString              - 待解密的十六进制密文字符串

   返回值：TBytes                         - 返回解密后的明文字节数组
}

function SM4EncryptCbcBytesToHex(Key: TBytes; Iv: TBytes; Input: TBytes): AnsiString;
{* 传入明文与加密 Key 与 Iv，SM4 加密返回转换成十六进制的密文，块间使用 CBC 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Iv: TBytes                           - 16 字节初始化向量，太长则截断，不足则补 0
     Input: TBytes                        - 待加密的明文字节数组

   返回值：AnsiString                     - 返回加密后的十六进制密文字符串
}

function SM4DecryptCbcBytesFromHex(Key: TBytes; Iv: TBytes; const Input: AnsiString): TBytes;
{* 传入十六进制的密文与加密 Key 与 Iv，SM4 解密返回明文，块间使用 CBC 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Iv: TBytes                           - 16 字节初始化向量，太长则截断，不足则补 0
     const Input: AnsiString              - 待解密的十六进制密文字符串

   返回值：TBytes                         - 返回解密后的明文字节数组
}

function SM4EncryptCfbBytesToHex(Key: TBytes; Iv: TBytes; Input: TBytes): AnsiString;
{* 传入明文与加密 Key 与 Iv，SM4 加密返回转换成十六进制的密文，块间使用 CFB 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Iv: TBytes                           - 16 字节初始化向量，太长则截断，不足则补 0
     Input: TBytes                        - 待加密的明文字节数组

   返回值：AnsiString                     - 返回加密后的十六进制密文字符串
}

function SM4DecryptCfbBytesFromHex(Key: TBytes; Iv: TBytes; const Input: AnsiString): TBytes;
{* 传入十六进制的密文与加密 Key 与 Iv，SM4 解密返回明文，块间使用 CFB 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Iv: TBytes                           - 16 字节初始化向量，太长则截断，不足则补 0
     const Input: AnsiString              - 待解密的十六进制密文字符串

   返回值：TBytes                         - 返回解密后的明文字节数组
}

function SM4EncryptOfbBytesToHex(Key: TBytes; Iv: TBytes; Input: TBytes): AnsiString;
{* 传入明文与加密 Key 与 Iv，SM4 加密返回转换成十六进制的密文，块间使用 OFB 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Iv: TBytes                           - 16 字节初始化向量，太长则截断，不足则补 0
     Input: TBytes                        - 待加密的明文字节数组

   返回值：AnsiString                     - 返回加密后的十六进制密文字符串
}

function SM4DecryptOfbBytesFromHex(Key: TBytes; Iv: TBytes; const Input: AnsiString): TBytes;
{* 传入十六进制的密文与加密 Key 与 Iv，SM4 解密返回明文，块间使用 OFB 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Iv: TBytes                           - 16 字节初始化向量，太长则截断，不足则补 0
     const Input: AnsiString              - 待解密的十六进制密文字符串

   返回值：TBytes                         - 返回解密后的明文字节数组
}

function SM4EncryptCtrBytesToHex(Key: TBytes; Nonce: TBytes; Input: TBytes): AnsiString;
{* 传入明文与加密 Key 与 Nonce，SM4 加密返回转换成十六进制的密文，块间使用 CTR 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Nonce: TBytes                        - 8 字节初始化向量，太长则截断，不足则补 0
     Input: TBytes                        - 待加密的明文字节数组

   返回值：AnsiString                     - 返回加密后的十六进制密文字符串
}

function SM4DecryptCtrBytesFromHex(Key: TBytes; Nonce: TBytes; const Input: AnsiString): TBytes;
{* 传入十六进制的密文与加密 Key 与 Nonce，SM4 解密返回明文，块间使用 CTR 模式。

   参数：
     Key: TBytes                          - 16 字节 SM4 密钥，太长则截断，不足则补 0
     Nonce: TBytes                        - 8 字节初始化向量，太长则截断，不足则补 0
     const Input: AnsiString              - 待解密的十六进制密文字符串

   返回值：TBytes                         - 返回解密后的明文字节数组
}

// ======================= 明文流与密文流之间的加解密 ==========================

procedure SM4EncryptStreamECB(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; Dest: TStream); overload;
{* 针对流的 SM4 加密，块间使用 ECB 模式。
   Count 为 0 表示从头加密整个流，否则只加密 Stream 当前位置起 Count 的字节数。

   参数：
     Source: TStream                      - 待加密的明文流
     Count: Cardinal                      - 从流当前位置起的待加密的字节长度，如为 0，表示从头加密整个流
     const Key: TCnSM4Key                 - 16 字节 SM4 密钥
     Dest: TStream                        - 输出的密文流

   返回值：（无）
}

procedure SM4DecryptStreamECB(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; Dest: TStream); overload;
{* 针对流的 SM4 解密，块间使用 ECB 模式。
   Count 为 0 表示从头解密整个流，否则只解密 Stream 当前位置起 Count 的字节数。

   参数：
     Source: TStream                      - 待解密的密文流
     Count: Cardinal                      - 从流当前位置起的待解密的字节长度，如为 0，表示从头解密整个流
     const Key: TCnSM4Key                 - 16 字节 SM4 密钥
     Dest: TStream                        - 输出的明文流

   返回值：（无）
}

procedure SM4EncryptStreamCBC(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; const InitVector: TCnSM4Iv; Dest: TStream);
{* 针对流的 SM4 加密，块间使用 CBC 模式。
   Count 为 0 表示从头加密整个流，否则只加密 Stream 当前位置起 Count 的字节数。

   参数：
     Source: TStream                      - 待加密的明文流
     Count: Cardinal                      - 从流当前位置起的待加密的字节长度，如为 0，表示从头加密整个流
     const Key: TCnSM4Key                 - 16 字节 SM4 密钥
     const InitVector: TCnSM4Iv           - 16 字节初始化向量
     Dest: TStream                        - 输出的密文流

   返回值：（无）
}

procedure SM4DecryptStreamCBC(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; const InitVector: TCnSM4Iv; Dest: TStream);
{* 针对流的 SM4 解密，块间使用 CBC 模式。
   Count 为 0 表示从头解密整个流，否则只解密 Stream 当前位置起 Count 的字节数。

   参数：
     Source: TStream                      - 待解密的密文流
     Count: Cardinal                      - 从流当前位置起的待解密的字节长度，如为 0，表示从头解密整个流
     const Key: TCnSM4Key                 - 16 字节 SM4 密钥
     const InitVector: TCnSM4Iv           - 16 字节初始化向量
     Dest: TStream                        - 输出的明文流

   返回值：（无）
}

procedure SM4EncryptStreamCFB(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; const InitVector: TCnSM4Iv; Dest: TStream);
{* 针对流的 SM4 加密，块间使用 CFB 模式。
   Count 为 0 表示从头加密整个流，否则只加密 Stream 当前位置起 Count 的字节数。

   参数：
     Source: TStream                      - 待加密的明文流
     Count: Cardinal                      - 从流当前位置起的待加密的字节长度，如为 0，表示从头加密整个流
     const Key: TCnSM4Key                 - 16 字节 SM4 密钥
     const InitVector: TCnSM4Iv           - 16 字节初始化向量
     Dest: TStream                        - 输出的密文流

   返回值：（无）
}

procedure SM4DecryptStreamCFB(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; const InitVector: TCnSM4Iv; Dest: TStream);
{* 针对流的 SM4 解密，块间使用 CFB 模式。
   Count 为 0 表示从头解密整个流，否则只解密 Stream 当前位置起 Count 的字节数。

   参数：
     Source: TStream                      - 待解密的密文流
     Count: Cardinal                      - 从流当前位置起的待解密的字节长度，如为 0，表示从头解密整个流
     const Key: TCnSM4Key                 - 16 字节 SM4 密钥
     const InitVector: TCnSM4Iv           - 16 字节初始化向量
     Dest: TStream                        - 输出的明文流

   返回值：（无）
}

procedure SM4EncryptStreamOFB(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; const InitVector: TCnSM4Iv; Dest: TStream);
{* 针对流的 SM4 加密，块间使用 OFB 模式。
   Count 为 0 表示从头加密整个流，否则只加密 Stream 当前位置起 Count 的字节数。

   参数：
     Source: TStream                      - 待加密的明文流
     Count: Cardinal                      - 从流当前位置起的待加密的字节长度，如为 0，表示从头加密整个流
     const Key: TCnSM4Key                 - 16 字节 SM4 密钥
     const InitVector: TCnSM4Iv           - 16 字节初始化向量
     Dest: TStream                        - 输出的密文流

   返回值：（无）
}

procedure SM4DecryptStreamOFB(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; const InitVector: TCnSM4Iv; Dest: TStream);
{* 针对流的 SM4 解密，块间使用 OFB 模式。
   Count 为 0 表示从头解密整个流，否则只解密 Stream 当前位置起 Count 的字节数。

   参数：
     Source: TStream                      - 待解密的密文流
     Count: Cardinal                      - 从流当前位置起的待解密的字节长度，如为 0，表示从头解密整个流
     const Key: TCnSM4Key                 - 16 字节 SM4 密钥
     const InitVector: TCnSM4Iv           - 16 字节初始化向量
     Dest: TStream                        - 输出的明文流

   返回值：（无）
}

procedure SM4EncryptStreamCTR(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; const InitNonce: TCnSM4Nonce; Dest: TStream);
{* 针对流的 SM4 加密，块间使用 CTR 模式。
   Count 为 0 表示从头加密整个流，否则只加密 Stream 当前位置起 Count 的字节数。

   参数：
     Source: TStream                      - 待加密的明文流
     Count: Cardinal                      - 从流当前位置起的待加密的字节长度，如为 0，表示从头加密整个流
     const Key: TCnSM4Key                 - 16 字节 SM4 密钥
     const InitNonce: TCnSM4Nonce         - 8 字节初始化向量
     Dest: TStream                        - 输出的密文流

   返回值：（无）
}

procedure SM4DecryptStreamCTR(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; const InitNonce: TCnSM4Nonce; Dest: TStream);
{* 针对流的 SM4 解密，块间使用 CTR 模式。
   Count 为 0 表示从头解密整个流，否则只解密 Stream 当前位置起 Count 的字节数。

   参数：
     Source: TStream                      - 待解密的密文流
     Count: Cardinal                      - 从流当前位置起的待解密的字节长度，如为 0，表示从头解密整个流
     const Key: TCnSM4Key                 - 16 字节 SM4 密钥
     const InitNonce: TCnSM4Nonce         - 8 字节初始化向量
     Dest: TStream                        - 输出的明文流

   返回值：（无）
}

// 以下仨函数为底层加密函数，开放出来供外部挨块加密使用

procedure SM4SetKeyEnc(var Ctx: TCnSM4Context; Key: PAnsiChar);
{* 将 16 字节 Key 塞进 SM4 上下文并设置为加密模式。

   参数：
     var Ctx: TCnSM4Context               - 待设置的 SM4 上下文
     Key: PAnsiChar                       - 16 字节 SM4 密钥

   返回值：（无）
}

procedure SM4SetKeyDec(var Ctx: TCnSM4Context; Key: PAnsiChar);
{* 将 16 字节 Key 塞进 SM4 上下文并设置为解密模式。

   参数：
     var Ctx: TCnSM4Context               - 待设置的 SM4 上下文
     Key: PAnsiChar                       - 16 字节 SM4 密钥

   返回值：（无）
}

procedure SM4OneRound(SK: PCardinal; Input: PAnsiChar; Output: PAnsiChar);
{* 加解密一个块，内容从 Input 至 Output，长度 16 字节，两者可以是同一个区域。
   SK是 TSM4Context 的 Sk，加密还是解密由其决定。

   参数：
     SK: PCardinal                        - SM4 的 SubKey
     Input: PAnsiChar                     - 待处理的数据块地址，长度至少 16 字节
     Output: PAnsiChar                    - 处理完毕的输出数据块地址，长度至少 16 字节

   返回值：（无）
}

implementation

resourcestring
  SCnErrorSM4InvalidInBufSize = 'Invalid Buffer Size for Decryption';
  SCnErrorSM4ReadError = 'Stream Read Error';
  SCnErrorSM4WriteError = 'Stream Write Error';

const
  SM4_ENCRYPT = 1;
  SM4_DECRYPT = 0;

  SBoxTable: array[0..CN_SM4_KEYSIZE - 1] of array[0..CN_SM4_KEYSIZE - 1] of Byte = (
    ($D6, $90, $E9, $FE, $CC, $E1, $3D, $B7, $16, $B6, $14, $C2, $28, $FB, $2C, $05),
    ($2B, $67, $9A, $76, $2A, $BE, $04, $C3, $AA, $44, $13, $26, $49, $86, $06, $99),
    ($9C, $42, $50, $F4, $91, $EF, $98, $7A, $33, $54, $0B, $43, $ED, $CF, $AC, $62),
    ($E4, $B3, $1C, $A9, $C9, $08, $E8, $95, $80, $DF, $94, $FA, $75, $8F, $3F, $A6),
    ($47, $07, $A7, $FC, $F3, $73, $17, $BA, $83, $59, $3C, $19, $E6, $85, $4F, $A8),
    ($68, $6B, $81, $B2, $71, $64, $DA, $8B, $F8, $EB, $0F, $4B, $70, $56, $9D, $35),
    ($1E, $24, $0E, $5E, $63, $58, $D1, $A2, $25, $22, $7C, $3B, $01, $21, $78, $87),
    ($D4, $00, $46, $57, $9F, $D3, $27, $52, $4C, $36, $02, $E7, $A0, $C4, $C8, $9E),
    ($EA, $BF, $8A, $D2, $40, $C7, $38, $B5, $A3, $F7, $F2, $CE, $F9, $61, $15, $A1),
    ($E0, $AE, $5D, $A4, $9B, $34, $1A, $55, $AD, $93, $32, $30, $F5, $8C, $B1, $E3),
    ($1D, $F6, $E2, $2E, $82, $66, $CA, $60, $C0, $29, $23, $AB, $0D, $53, $4E, $6F),
    ($D5, $DB, $37, $45, $DE, $FD, $8E, $2F, $03, $FF, $6A, $72, $6D, $6C, $5B, $51),
    ($8D, $1B, $AF, $92, $BB, $DD, $BC, $7F, $11, $D9, $5C, $41, $1F, $10, $5A, $D8),
    ($0A, $C1, $31, $88, $A5, $CD, $7B, $BD, $2D, $74, $D0, $12, $B8, $E5, $B4, $B0),
    ($89, $69, $97, $4A, $0C, $96, $77, $7E, $65, $B9, $F1, $09, $C5, $6E, $C6, $84),
    ($18, $F0, $7D, $EC, $3A, $DC, $4D, $20, $79, $EE, $5F, $3E, $D7, $CB, $39, $48)
  );

  FK: array[0..3] of Cardinal = ($A3B1BAC6, $56AA3350, $677D9197, $B27022DC);

  CK: array[0..CN_SM4_KEYSIZE * 2 - 1] of Cardinal = (
    $00070E15, $1C232A31, $383F464D, $545B6269,
    $70777E85, $8C939AA1, $A8AFB6BD, $C4CBD2D9,
    $E0E7EEF5, $FC030A11, $181F262D, $343B4249,
    $50575E65, $6C737A81, $888F969D, $A4ABB2B9,
    $C0C7CED5, $DCE3EAF1, $F8FF060D, $141B2229,
    $30373E45, $4C535A61, $686F767D, $848B9299,
    $A0A7AEB5, $BCC3CAD1, $D8DFE6ED, $F4FB0209,
    $10171E25, $2C333A41, $484F565D, $646B7279 );

function Min(A, B: Integer): Integer; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  if A < B then
    Result := A
  else
    Result := B;
end;

procedure GetULongBe(var N: Cardinal; B: PAnsiChar; I: Integer); {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
var
  D: Cardinal;
begin
  D := (Cardinal(B[I]) shl 24) or (Cardinal(B[I + 1]) shl 16) or
    (Cardinal(B[I + 2]) shl 8) or (Cardinal(B[I + 3]));
  N := D;
end;

procedure PutULongBe(N: Cardinal; B: PAnsiChar; I: Integer); {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  B[I] := AnsiChar(N shr 24);
  B[I + 1] := AnsiChar(N shr 16);
  B[I + 2] := AnsiChar(N shr 8);
  B[I + 3] := AnsiChar(N);
end;

function SM4Shl(X: Cardinal; N: Integer): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := (X and $FFFFFFFF) shl N;
end;

// 循环左移。注意 N 为 0 或 32 时返回值仍为 X，N 为 33 时返回值等于 N 为 1 时的返回值
function ROTL(X: Cardinal; N: Integer): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := SM4Shl(X, N) or (X shr (32 - N));
end;

procedure Swap(var A: Cardinal; var B: Cardinal); {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
var
  T: Cardinal;
begin
  T := A;
  A := B;
  B := T;
end;

function SM4SBox(Inch: Byte): Byte; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
var
  PTable: Pointer;
begin
  PTable := @(SboxTable[0][0]);
  Result := PByte(TCnIntAddress(PTable) + Inch)^;
end;

function SM4Lt(Ka: Cardinal): Cardinal;
var
  BB: Cardinal;
  A: array[0..3] of Byte;
  B: array[0..3] of Byte;
begin
  BB := 0;
  PutULongBe(Ka, @(A[0]), 0);
  B[0] := SM4SBox(A[0]);
  B[1] := SM4SBox(A[1]);
  B[2] := SM4SBox(A[2]);
  B[3] := SM4SBox(A[3]);
  GetULongBe(BB, @(B[0]), 0);

  Result := BB xor (ROTL(BB, 2)) xor (ROTL(BB, 10)) xor (ROTL(BB, 18))
    xor (ROTL(BB, 24));
end;

function SM4F(X0: Cardinal; X1: Cardinal; X2: Cardinal; X3: Cardinal; RK: Cardinal): Cardinal; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  Result := X0 xor SM4Lt(X1 xor X2 xor X3 xor RK);
end;

function SM4CalciRK(Ka: Cardinal): Cardinal;
var
  BB: Cardinal;
  A: array[0..3] of Byte;
  B: array[0..3] of Byte;
begin
  PutULongBe(Ka, @(A[0]), 0);
  B[0] := SM4SBox(A[0]);
  B[1] := SM4SBox(A[1]);
  B[2] := SM4SBox(A[2]);
  B[3] := SM4SBox(A[3]);
  GetULongBe(BB, @(B[0]), 0);
  Result := BB xor ROTL(BB, 13) xor ROTL(BB, 23);
end;

// SK Points to 32 DWord Array; Key Points to 16 Byte Array
procedure SM4SetKey(SK: PCardinal; Key: PAnsiChar);
var
  MK: array[0..3] of Cardinal;
  K: array[0..35] of Cardinal;
  I: Integer;
begin
  GetULongBe(MK[0], Key, 0);
  GetULongBe(MK[1], Key, 4);
  GetULongBe(MK[2], Key, 8);
  GetULongBe(MK[3], Key, 12);

  K[0] := MK[0] xor FK[0];
  K[1] := MK[1] xor FK[1];
  K[2] := MK[2] xor FK[2];
  K[3] := MK[3] xor FK[3];

  for I := 0 to 31 do
  begin
    K[I + 4] := K[I] xor SM4CalciRK(K[I + 1] xor K[I + 2] xor K[I + 3] xor CK[I]);
    (PCardinal(TCnIntAddress(SK) + I * SizeOf(Cardinal)))^ := K[I + 4];
  end;
end;

// SK Points to 32 DWord Array; Input/Output Points to 16 Byte Array
// Input 和 Output 可以是同一处区域
procedure SM4OneRound(SK: PCardinal; Input: PAnsiChar; Output: PAnsiChar);
var
  I: Integer;
  UlBuf: array[0..35] of Cardinal;
begin
  FillChar(UlBuf[0], SizeOf(UlBuf), 0);

  GetULongBe(UlBuf[0], Input, 0);
  GetULongBe(UlBuf[1], Input, 4);
  GetULongBe(UlBuf[2], Input, 8);
  GetULongBe(UlBuf[3], Input, 12);

  for I := 0 to 31 do
  begin
    UlBuf[I + 4] := SM4F(UlBuf[I], UlBuf[I + 1], UlBuf[I + 2], UlBuf[I + 3],
      (PCardinal(TCnNativeInt(SK) + I * SizeOf(Cardinal)))^);
  end;

  PutULongBe(UlBuf[35], Output, 0);
  PutULongBe(UlBuf[34], Output, 4);
  PutULongBe(UlBuf[33], Output, 8);
  PutULongBe(UlBuf[32], Output, 12);
end;

procedure SM4SetKeyEnc(var Ctx: TCnSM4Context; Key: PAnsiChar);
begin
  Ctx.Mode := SM4_ENCRYPT;
  SM4SetKey(@(Ctx.Sk[0]), Key);
end;

procedure SM4SetKeyDec(var Ctx: TCnSM4Context; Key: PAnsiChar);
var
  I: Integer;
begin
  Ctx.Mode := SM4_DECRYPT;
  SM4SetKey(@(Ctx.Sk[0]), Key);

  for I := 0 to CN_SM4_KEYSIZE - 1 do
    Swap(Ctx.Sk[I], Ctx.Sk[31 - I]);
end;

procedure SM4CryptEcb(var Ctx: TCnSM4Context; Mode: Integer; Length: Integer;
  Input: PAnsiChar; Output: PAnsiChar);
var
  EndBuf: TCnSM4Buffer;
begin
  while Length > 0 do
  begin
    if Length >= CN_SM4_BLOCKSIZE then
    begin
      SM4OneRound(@(Ctx.Sk[0]), Input, Output);
    end
    else
    begin
      // 尾部不足 16，补 0
      FillChar(EndBuf[0], CN_SM4_BLOCKSIZE, 0);
      Move(Input^, EndBuf[0], Length);
      SM4OneRound(@(Ctx.Sk[0]), @(EndBuf[0]), Output);
    end;
    Inc(Input, CN_SM4_BLOCKSIZE);
    Inc(Output, CN_SM4_BLOCKSIZE);
    Dec(Length, CN_SM4_BLOCKSIZE);
  end;
end;

procedure SM4CryptEcbStr(Mode: Integer; Key: AnsiString;
  const Input: AnsiString; Output: PAnsiChar);
var
  Ctx: TCnSM4Context;
begin
  if Length(Key) < CN_SM4_KEYSIZE then
    while Length(Key) < CN_SM4_KEYSIZE do Key := Key + Chr(0) // 16 bytes at least padding 0.
  else if Length(Key) > CN_SM4_KEYSIZE then
    Key := Copy(Key, 1, CN_SM4_KEYSIZE);  // Only keep 16

  if Mode = SM4_ENCRYPT then
  begin
    SM4SetKeyEnc(Ctx, @(Key[1]));
    SM4CryptEcb(Ctx, SM4_ENCRYPT, Length(Input), @(Input[1]), @(Output[0]));
  end
  else if Mode = SM4_DECRYPT then
  begin
    SM4SetKeyDec(Ctx, @(Key[1]));
    SM4CryptEcb(Ctx, SM4_DECRYPT, Length(Input), @(Input[1]), @(Output[0]));
  end;
end;

procedure SM4CryptCbc(var Ctx: TCnSM4Context; Mode: Integer; ByteLen: Integer;
  Iv: PAnsiChar; Input: PAnsiChar; Output: PAnsiChar);
var
  I: Integer;
  EndBuf: TCnSM4Buffer;
  LocalIv: TCnSM4Iv;
begin
  Move(Iv^, LocalIv[0], CN_SM4_BLOCKSIZE);
  if Mode = SM4_ENCRYPT then
  begin
    while ByteLen > 0 do
    begin
      if ByteLen >= CN_SM4_BLOCKSIZE then
      begin
        for I := 0 to CN_SM4_BLOCKSIZE - 1 do
          (PByte(TCnIntAddress(Output) + I))^ := (PByte(TCnIntAddress(Input) + I))^
            xor LocalIv[I];

        SM4OneRound(@(Ctx.Sk[0]), Output, Output);
        Move(Output[0], LocalIv[0], CN_SM4_BLOCKSIZE);
      end
      else
      begin
        // 尾部不足 16，补 0
        FillChar(EndBuf[0], SizeOf(EndBuf), 0);
        Move(Input^, EndBuf[0], ByteLen);

        for I := 0 to CN_SM4_BLOCKSIZE - 1 do
          (PByte(TCnIntAddress(Output) + I))^ := EndBuf[I]
            xor LocalIv[I];

        SM4OneRound(@(Ctx.Sk[0]), Output, Output);
        Move(Output[0], LocalIv[0], CN_SM4_BLOCKSIZE);
      end;

      Inc(Input, CN_SM4_BLOCKSIZE);
      Inc(Output, CN_SM4_BLOCKSIZE);
      Dec(ByteLen, CN_SM4_BLOCKSIZE);
    end;
  end
  else if Mode = SM4_DECRYPT then
  begin
    while ByteLen > 0 do
    begin
      if ByteLen >= CN_SM4_BLOCKSIZE then
      begin
        SM4OneRound(@(Ctx.Sk[0]), Input, Output);

        for I := 0 to CN_SM4_BLOCKSIZE - 1 do
          (PByte(TCnIntAddress(Output) + I))^ := (PByte(TCnIntAddress(Output) + I))^
            xor LocalIv[I];

        Move(Input^, LocalIv[0], CN_SM4_BLOCKSIZE);
      end
      else
      begin
        // 尾部不足 16，补 0
        FillChar(EndBuf[0], SizeOf(EndBuf), 0);
        Move(Input^, EndBuf[0], ByteLen);
        SM4OneRound(@(Ctx.Sk[0]), @(EndBuf[0]), Output);

        for I := 0 to CN_SM4_BLOCKSIZE - 1 do
          (PByte(TCnIntAddress(Output) + I))^ := (PByte(TCnIntAddress(Output) + I))^
            xor LocalIv[I];

        Move(EndBuf[0], LocalIv[0], CN_SM4_BLOCKSIZE);
      end;

      Inc(Input, CN_SM4_BLOCKSIZE);
      Inc(Output, CN_SM4_BLOCKSIZE);
      Dec(ByteLen, CN_SM4_BLOCKSIZE);
    end;
  end;
end;

procedure SM4CryptCfb(var Ctx: TCnSM4Context; Mode: Integer; ByteLen: Integer;
  Iv: PAnsiChar; Input: PAnsiChar; Output: PAnsiChar);
var
  I: Integer;
  LocalIv, Tail: TCnSM4Iv;
begin
  Move(Iv^, LocalIv[0], CN_SM4_BLOCKSIZE);
  if Mode = SM4_ENCRYPT then
  begin
    while ByteLen > 0 do
    begin
      if ByteLen >= CN_SM4_BLOCKSIZE then
      begin
        SM4OneRound(@(Ctx.Sk[0]), @LocalIv[0], Output);  // 先加密 Iv

        for I := 0 to CN_SM4_BLOCKSIZE - 1 do
          (PByte(TCnIntAddress(Output) + I))^ := (PByte(TCnIntAddress(Input) + I))^
            xor (PByte(TCnIntAddress(Output) + I))^;  // 加密结果与明文异或作为输出密文

        Move(Output[0], LocalIv[0], CN_SM4_BLOCKSIZE);  // 密文取代 Iv 以备下一轮
      end
      else
      begin
        SM4OneRound(@(Ctx.Sk[0]), @LocalIv[0], @Tail[0]);

        for I := 0 to ByteLen - 1 do // 只需异或剩余长度，无需处理完整的 16 字节
          (PByte(TCnIntAddress(Output) + I))^ := (PByte(TCnIntAddress(Input) + I))^ xor Tail[I];
      end;

      Inc(Input, CN_SM4_BLOCKSIZE);
      Inc(Output, CN_SM4_BLOCKSIZE);
      Dec(ByteLen, CN_SM4_BLOCKSIZE);
    end;
  end
  else if Mode = SM4_DECRYPT then
  begin
    while ByteLen > 0 do
    begin
      if ByteLen >= CN_SM4_BLOCKSIZE then
      begin
        SM4OneRound(@(Ctx.Sk[0]), @LocalIv[0], Output);   // 先加密 Iv

        for I := 0 to CN_SM4_BLOCKSIZE - 1 do
          (PByte(TCnIntAddress(Output) + I))^ := (PByte(TCnIntAddress(Output) + I))^
            xor (PByte(TCnIntAddress(Input) + I))^;    // 加密结果与密文异或得到明文

        Move(Input[0], LocalIv[0], CN_SM4_BLOCKSIZE);    // 密文取代 Iv 再拿去下一轮加密
      end
      else
      begin
        SM4OneRound(@(Ctx.Sk[0]), @LocalIv[0], @Tail[0]);

        for I := 0 to ByteLen - 1 do
          (PByte(TCnIntAddress(Output) + I))^ := Tail[I] xor (PByte(TCnIntAddress(Input) + I))^;
      end;

      Inc(Input, CN_SM4_BLOCKSIZE);
      Inc(Output, CN_SM4_BLOCKSIZE);
      Dec(ByteLen, CN_SM4_BLOCKSIZE);
    end;
  end;
end;

procedure SM4CryptOfb(var Ctx: TCnSM4Context; Mode: Integer; ByteLen: Integer;
  Iv: PAnsiChar; Input: PAnsiChar; Output: PAnsiChar);
var
  I: Integer;
  LocalIv, Tail: TCnSM4Iv;
begin
  Move(Iv^, LocalIv[0], CN_SM4_BLOCKSIZE);
  if Mode = SM4_ENCRYPT then
  begin
    while ByteLen > 0 do
    begin
      if ByteLen >= CN_SM4_BLOCKSIZE then
      begin
        SM4OneRound(@(Ctx.Sk[0]), @LocalIv[0], Output);  // 先加密 Iv
        Move(Output[0], LocalIv[0], CN_SM4_BLOCKSIZE);   // 加密结果先留存给下一步

        for I := 0 to CN_SM4_BLOCKSIZE - 1 do      // 加密结果与明文异或出密文
          (PByte(TCnIntAddress(Output) + I))^ := (PByte(TCnIntAddress(Input) + I))^
            xor (PByte(TCnIntAddress(Output) + I))^;
      end
      else
      begin
        SM4OneRound(@(Ctx.Sk[0]), @LocalIv[0], @Tail[0]);  // 先加密 Iv

        for I := 0 to ByteLen - 1 do             // 无需完整 16 字节
          (PByte(TCnIntAddress(Output) + I))^ := (PByte(TCnIntAddress(Input) + I))^ xor Tail[I];
      end;

      Inc(Input, CN_SM4_BLOCKSIZE);
      Inc(Output, CN_SM4_BLOCKSIZE);
      Dec(ByteLen, CN_SM4_BLOCKSIZE);
    end;
  end
  else if Mode = SM4_DECRYPT then
  begin
    while ByteLen > 0 do
    begin
      if ByteLen >= CN_SM4_BLOCKSIZE then
      begin
        SM4OneRound(@(Ctx.Sk[0]), @LocalIv[0], Output);   // 先加密 Iv
        Move(Output[0], LocalIv[0], CN_SM4_BLOCKSIZE);    // 加密结果先留存给下一步

        for I := 0 to CN_SM4_BLOCKSIZE - 1 do       // 加密内容与密文异或得到明文
          (PByte(TCnIntAddress(Output) + I))^ := (PByte(TCnIntAddress(Output) + I))^
            xor (PByte(TCnIntAddress(Input) + I))^;
      end
      else
      begin
        SM4OneRound(@(Ctx.Sk[0]), @LocalIv[0], @Tail[0]);   // 先加密 Iv

        for I := 0 to ByteLen - 1 do
          (PByte(TCnIntAddress(Output) + I))^ := Tail[I] xor (PByte(TCnIntAddress(Input) + I))^;
      end;

      Inc(Input, CN_SM4_BLOCKSIZE);
      Inc(Output, CN_SM4_BLOCKSIZE);
      Dec(ByteLen, CN_SM4_BLOCKSIZE);
    end;
  end;
end;

// CTR 模式加密数据块。Output 长度可以和 Input 一样，不必向上取整
procedure SM4CryptCtr(var Ctx: TCnSM4Context; Mode: Integer; ByteLen: Integer;
  Nonce: PAnsiChar; Input: PAnsiChar; Output: PAnsiChar);
var
  I: Integer;
  LocalIv: TCnSM4Iv;
  Cnt, T: Int64;
begin
  Cnt := 1;

  // 不区分加解密
  while ByteLen > 0 do
  begin
    if ByteLen >= CN_SM4_BLOCKSIZE then
    begin
      Move(Nonce^, LocalIv[0], SizeOf(TCnSM4Nonce));
      T := Int64HostToNetwork(Cnt);
      Move(T, LocalIv[SizeOf(TCnSM4Nonce)], SizeOf(Int64));

      SM4OneRound(@(Ctx.Sk[0]), @LocalIv[0], @LocalIv[0]);  // 先加密 Iv

      for I := 0 to CN_SM4_BLOCKSIZE - 1 do      // 加密结果与明文异或出密文
        (PByte(TCnIntAddress(Output) + I))^ := (PByte(TCnIntAddress(Input) + I))^
          xor LocalIv[I];
    end
    else
    begin
      Move(Nonce^, LocalIv[0], SizeOf(TCnSM4Nonce));
      T := Int64HostToNetwork(Cnt);
      Move(T, LocalIv[SizeOf(TCnSM4Nonce)], SizeOf(Int64));

      SM4OneRound(@(Ctx.Sk[0]), @LocalIv[0], @LocalIv[0]);  // 先加密 Iv

      for I := 0 to ByteLen - 1 do             // 无需完整 16 字节
        (PByte(TCnIntAddress(Output) + I))^ := (PByte(TCnIntAddress(Input) + I))^
          xor LocalIv[I];
    end;

    Inc(Input, CN_SM4_BLOCKSIZE);
    Inc(Output, CN_SM4_BLOCKSIZE);
    Dec(ByteLen, CN_SM4_BLOCKSIZE);
    Inc(Cnt);
  end;
end;

procedure SM4CryptCbcStr(Mode: Integer; Key: AnsiString; Iv: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
var
  Ctx: TCnSM4Context;
begin
  if Length(Key) < CN_SM4_KEYSIZE then
    while Length(Key) < CN_SM4_KEYSIZE do Key := Key + Chr(0) // 16 bytes at least padding 0.
  else if Length(Key) > CN_SM4_KEYSIZE then
    Key := Copy(Key, 1, CN_SM4_KEYSIZE);  // Only keep 16

  if Mode = SM4_ENCRYPT then
  begin
    SM4SetKeyEnc(Ctx, @(Key[1]));
    SM4CryptCbc(Ctx, SM4_ENCRYPT, Length(Input), @(Iv[0]), @(Input[1]), @(Output[0]));
  end
  else if Mode = SM4_DECRYPT then
  begin
    SM4SetKeyDec(Ctx, @(Key[1]));
    SM4CryptCbc(Ctx, SM4_DECRYPT, Length(Input), @(Iv[0]), @(Input[1]), @(Output[0]));
  end;
end;

procedure SM4CryptCfbStr(Mode: Integer; Key: AnsiString; Iv: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
var
  Ctx: TCnSM4Context;
begin
  if Length(Key) < CN_SM4_KEYSIZE then
    while Length(Key) < CN_SM4_KEYSIZE do Key := Key + Chr(0) // 16 bytes at least padding 0.
  else if Length(Key) > CN_SM4_KEYSIZE then
    Key := Copy(Key, 1, CN_SM4_KEYSIZE);  // Only keep 16

  if Mode = SM4_ENCRYPT then
  begin
    SM4SetKeyEnc(Ctx, @(Key[1]));
    SM4CryptCfb(Ctx, SM4_ENCRYPT, Length(Input), @(Iv[0]), @(Input[1]), @(Output[0]));
  end
  else if Mode = SM4_DECRYPT then
  begin
    SM4SetKeyEnc(Ctx, @(Key[1])); // 注意 CFB 的解密也用的是加密！
    SM4CryptCfb(Ctx, SM4_DECRYPT, Length(Input), @(Iv[0]), @(Input[1]), @(Output[0]));
  end;
end;

procedure SM4CryptOfbStr(Mode: Integer; Key: AnsiString; Iv: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
var
  Ctx: TCnSM4Context;
begin
  if Length(Key) < CN_SM4_KEYSIZE then
    while Length(Key) < CN_SM4_KEYSIZE do Key := Key + Chr(0) // 16 bytes at least padding 0.
  else if Length(Key) > CN_SM4_KEYSIZE then
    Key := Copy(Key, 1, CN_SM4_KEYSIZE);  // Only keep 16

  if Mode = SM4_ENCRYPT then
  begin
    SM4SetKeyEnc(Ctx, @(Key[1]));
    SM4CryptOfb(Ctx, SM4_ENCRYPT, Length(Input), @(Iv[0]), @(Input[1]), @(Output[0]));
  end
  else if Mode = SM4_DECRYPT then
  begin
    SM4SetKeyEnc(Ctx, @(Key[1])); // 注意 OFB 的解密也用的是加密！
    SM4CryptOfb(Ctx, SM4_DECRYPT, Length(Input), @(Iv[0]), @(Input[1]), @(Output[0]));
  end;
end;

procedure SM4CryptCtrStr(Mode: Integer; Key: AnsiString; Nonce: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
var
  Ctx: TCnSM4Context;
begin
  if Length(Key) < CN_SM4_KEYSIZE then
    while Length(Key) < CN_SM4_KEYSIZE do Key := Key + Chr(0) // 16 bytes at least padding 0.
  else if Length(Key) > CN_SM4_KEYSIZE then
    Key := Copy(Key, 1, CN_SM4_KEYSIZE);  // Only keep 16

  if Mode = SM4_ENCRYPT then
  begin
    SM4SetKeyEnc(Ctx, @(Key[1]));
    SM4CryptCtr(Ctx, SM4_ENCRYPT, Length(Input), @(Nonce[0]), @(Input[1]), @(Output[0]));
  end
  else if Mode = SM4_DECRYPT then
  begin
    SM4SetKeyEnc(Ctx, @(Key[1])); // 注意 CTR 的解密也用的是加密！
    SM4CryptCtr(Ctx, SM4_DECRYPT, Length(Input), @(Nonce[0]), @(Input[1]), @(Output[0]));
  end;
end;

procedure SM4EncryptEcbStr(Key: AnsiString; const Input: AnsiString; Output: PAnsiChar);
begin
  SM4CryptEcbStr(SM4_ENCRYPT, Key, Input, Output);
end;

procedure SM4DecryptEcbStr(Key: AnsiString; const Input: AnsiString; Output: PAnsiChar);
begin
  SM4CryptEcbStr(SM4_DECRYPT, Key, Input, Output);
end;

procedure SM4EncryptCbcStr(Key: AnsiString; Iv: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
begin
  SM4CryptCbcStr(SM4_ENCRYPT, Key, Iv, Input, Output);
end;

procedure SM4DecryptCbcStr(Key: AnsiString; Iv: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
begin
  SM4CryptCbcStr(SM4_DECRYPT, Key, Iv, Input, Output);
end;

procedure SM4EncryptCfbStr(Key: AnsiString; Iv: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
begin
  SM4CryptCfbStr(SM4_ENCRYPT, Key, Iv, Input, Output);
end;

procedure SM4DecryptCfbStr(Key: AnsiString; Iv: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
begin
  SM4CryptCfbStr(SM4_DECRYPT, Key, Iv, Input, Output);
end;

procedure SM4EncryptOfbStr(Key: AnsiString; Iv: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
begin
  SM4CryptOfbStr(SM4_ENCRYPT, Key, Iv, Input, Output);
end;

procedure SM4DecryptOfbStr(Key: AnsiString; Iv: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
begin
  SM4CryptOfbStr(SM4_DECRYPT, Key, Iv, Input, Output);
end;

procedure SM4EncryptCtrStr(Key: AnsiString; Nonce: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
begin
  SM4CryptCtrStr(SM4_ENCRYPT, Key, Nonce, Input, Output);
end;

procedure SM4DecryptCtrStr(Key: AnsiString; Nonce: PAnsiChar;
  const Input: AnsiString; Output: PAnsiChar);
begin
  SM4CryptCtrStr(SM4_DECRYPT, Key, Nonce, Input, Output);
end;

function SM4CryptEcbBytes(Mode: Integer; Key: TBytes;
  const Input: TBytes): TBytes;
var
  Ctx: TCnSM4Context;
  I, Len: Integer;
begin
  Len := Length(Input);
  if Len <= 0 then
  begin
    Result := nil;
    Exit;
  end;
  SetLength(Result, (((Len - 1) div 16) + 1) * 16);

  Len := Length(Key);
  if Len < CN_SM4_KEYSIZE then // Key 长度小于 16 字节补 0
  begin
    SetLength(Key, CN_SM4_KEYSIZE);
    for I := Len to CN_SM4_KEYSIZE - 1 do
      Key[I] := 0;
  end;
  // 长度大于 16 字节时 SM4SetKeyEnc 会自动忽略后面的部分

  if Mode = SM4_ENCRYPT then
  begin
    SM4SetKeyEnc(Ctx, @(Key[0]));
    SM4CryptEcb(Ctx, SM4_ENCRYPT, Length(Input), @(Input[0]), @(Result[0]));
  end
  else if Mode = SM4_DECRYPT then
  begin
    SM4SetKeyDec(Ctx, @(Key[0]));
    SM4CryptEcb(Ctx, SM4_DECRYPT, Length(Input), @(Input[0]), @(Result[0]));
  end;
end;

function SM4CryptCbcBytes(Mode: Integer; Key, Iv: TBytes;
  const Input: TBytes): TBytes;
var
  Ctx: TCnSM4Context;
  LocalIv: TCnSM4Iv;
  I, Len: Integer;
begin
  Len := Length(Input);
  if Len <= 0 then
  begin
    Result := nil;
    Exit;
  end;
  SetLength(Result, (((Len - 1) div 16) + 1) * 16);

  Len := Length(Key);
  if Len < CN_SM4_KEYSIZE then // Key 长度小于 16 字节补 0
  begin
    SetLength(Key, CN_SM4_KEYSIZE);
    for I := Len to CN_SM4_KEYSIZE - 1 do
      Key[I] := 0;
  end;
  // 长度大于 16 字节时 SM4SetKeyEnc 会自动忽略后面的部分

  MoveMost(Iv[0], LocalIv[0], Length(Iv), SizeOf(TCnSM4Iv));

  if Mode = SM4_ENCRYPT then
  begin
    SM4SetKeyEnc(Ctx, @(Key[0]));
    SM4CryptCbc(Ctx, SM4_ENCRYPT, Length(Input), @(LocalIv[0]), @(Input[0]), @(Result[0]));
  end
  else if Mode = SM4_DECRYPT then
  begin
    SM4SetKeyDec(Ctx, @(Key[0]));
    SM4CryptCbc(Ctx, SM4_DECRYPT, Length(Input), @(LocalIv[0]), @(Input[0]), @(Result[0]));
  end;
end;

function SM4CryptCfbBytes(Mode: Integer; Key, Iv: TBytes;
  const Input: TBytes): TBytes;
var
  Ctx: TCnSM4Context;
  LocalIv: TCnSM4Iv;
  I, Len: Integer;
begin
  Len := Length(Input);
  if Len <= 0 then
  begin
    Result := nil;
    Exit;
  end;
  SetLength(Result, Len); // 注意 CFB 是流模式，输出无需补足块

  Len := Length(Key);
  if Len < CN_SM4_KEYSIZE then // Key 长度小于 16 字节补 0
  begin
    SetLength(Key, CN_SM4_KEYSIZE);
    for I := Len to CN_SM4_KEYSIZE - 1 do
      Key[I] := 0;
  end;
  // 长度大于 16 字节时 SM4SetKeyEnc 会自动忽略后面的部分

  MoveMost(Iv[0], LocalIv[0], Length(Iv), SizeOf(TCnSM4Iv));

  if Mode = SM4_ENCRYPT then
  begin
    SM4SetKeyEnc(Ctx, @(Key[0]));
    SM4CryptCfb(Ctx, SM4_ENCRYPT, Length(Input), @(LocalIv[0]), @(Input[0]), @(Result[0]));
  end
  else if Mode = SM4_DECRYPT then
  begin
    SM4SetKeyEnc(Ctx, @(Key[0])); // 注意 CFB 的解密也用的是加密！
    SM4CryptCfb(Ctx, SM4_DECRYPT, Length(Input), @(LocalIv[0]), @(Input[0]), @(Result[0]));
  end;
end;

function SM4CryptOfbBytes(Mode: Integer; Key, Iv: TBytes;
  const Input: TBytes): TBytes;
var
  Ctx: TCnSM4Context;
  LocalIv: TCnSM4Iv;
  I, Len: Integer;
begin
  Len := Length(Input);
  if Len <= 0 then
  begin
    Result := nil;
    Exit;
  end;
  SetLength(Result, Len);  // 注意 OFB 是流模式，输出无需补足块

  Len := Length(Key);
  if Len < CN_SM4_KEYSIZE then // Key 长度小于 16 字节补 0
  begin
    SetLength(Key, CN_SM4_KEYSIZE);
    for I := Len to CN_SM4_KEYSIZE - 1 do
      Key[I] := 0;
  end;
  // 长度大于 16 字节时 SM4SetKeyEnc 会自动忽略后面的部分

  MoveMost(Iv[0], LocalIv[0], Length(Iv), SizeOf(TCnSM4Iv));

  if Mode = SM4_ENCRYPT then
  begin
    SM4SetKeyEnc(Ctx, @(Key[0]));
    SM4CryptOfb(Ctx, SM4_ENCRYPT, Length(Input), @(LocalIv[0]), @(Input[0]), @(Result[0]));
  end
  else if Mode = SM4_DECRYPT then
  begin
    SM4SetKeyEnc(Ctx, @(Key[0])); // 注意 OFB 的解密也用的是加密！
    SM4CryptOfb(Ctx, SM4_DECRYPT, Length(Input), @(LocalIv[0]), @(Input[0]), @(Result[0]));
  end;
end;

function SM4CryptCtrBytes(Mode: Integer; Key, Nonce: TBytes;
  const Input: TBytes): TBytes;
var
  Ctx: TCnSM4Context;
  LocalNonce: TCnSM4Nonce;
  I, Len: Integer;
begin
  Len := Length(Input);
  if Len <= 0 then
  begin
    Result := nil;
    Exit;
  end;
  SetLength(Result, Len);

  Len := Length(Key);
  if Len < CN_SM4_KEYSIZE then // Key 长度小于 16 字节补 0
  begin
    SetLength(Key, CN_SM4_KEYSIZE);
    for I := Len to CN_SM4_KEYSIZE - 1 do
      Key[I] := 0;
  end;
  // 长度大于 16 字节时 SM4SetKeyEnc 会自动忽略后面的部分

  MoveMost(Nonce[0], LocalNonce[0], Length(Nonce), SizeOf(TCnSM4Nonce));

  if Mode = SM4_ENCRYPT then
  begin
    SM4SetKeyEnc(Ctx, @(Key[0]));
    SM4CryptCtr(Ctx, SM4_ENCRYPT, Length(Input), @(LocalNonce[0]), @(Input[0]), @(Result[0]));
  end
  else if Mode = SM4_DECRYPT then
  begin
    SM4SetKeyEnc(Ctx, @(Key[0])); // 注意 CTR 的解密也用的是加密！
    SM4CryptCtr(Ctx, SM4_DECRYPT, Length(Input), @(LocalNonce[0]), @(Input[0]), @(Result[0]));
  end;
end;

function SM4EncryptEcbBytes(Key: TBytes; Input: TBytes): TBytes;
begin
  Result := SM4CryptEcbBytes(SM4_ENCRYPT, Key, Input);
end;

function SM4DecryptEcbBytes(Key: TBytes; Input: TBytes): TBytes;
begin
  Result := SM4CryptEcbBytes(SM4_DECRYPT, Key, Input);
end;

function SM4EncryptCbcBytes(Key, Iv: TBytes; Input: TBytes): TBytes;
begin
  Result := SM4CryptCbcBytes(SM4_ENCRYPT, Key, Iv, Input);
end;

function SM4DecryptCbcBytes(Key, Iv: TBytes; Input: TBytes): TBytes;
begin
  Result := SM4CryptCbcBytes(SM4_DECRYPT, Key, Iv, Input);
end;

function SM4EncryptCfbBytes(Key, Iv: TBytes; Input: TBytes): TBytes;
begin
  Result := SM4CryptCfbBytes(SM4_ENCRYPT, Key, Iv, Input);
end;

function SM4DecryptCfbBytes(Key, Iv: TBytes; Input: TBytes): TBytes;
begin
  Result := SM4CryptCfbBytes(SM4_DECRYPT, Key, Iv, Input);
end;

function SM4EncryptOfbBytes(Key, Iv: TBytes; Input: TBytes): TBytes;
begin
  Result := SM4CryptOfbBytes(SM4_ENCRYPT, Key, Iv, Input);
end;

function SM4DecryptOfbBytes(Key, Iv: TBytes; Input: TBytes): TBytes;
begin
  Result := SM4CryptOfbBytes(SM4_DECRYPT, Key, Iv, Input);
end;

function SM4EncryptCtrBytes(Key, Nonce: TBytes; Input: TBytes): TBytes;
begin
  Result := SM4CryptCtrBytes(SM4_ENCRYPT, Key, Nonce, Input);
end;

function SM4DecryptCtrBytes(Key, Nonce: TBytes; Input: TBytes): TBytes;
begin
  Result := SM4CryptCtrBytes(SM4_DECRYPT, Key, Nonce, Input);
end;

function SM4EncryptEcbBytesToHex(Key: TBytes; Input: TBytes): AnsiString;
begin
  Result := AnsiString(BytesToHex(SM4EncryptEcbBytes(Key, Input)));
end;

function SM4DecryptEcbBytesFromHex(Key: TBytes; const Input: AnsiString): TBytes;
begin
  Result := SM4DecryptEcbBytes(Key, HexToBytes(string(Input)));
end;

function SM4EncryptCbcBytesToHex(Key, Iv: TBytes; Input: TBytes): AnsiString;
begin
  Result := AnsiString(BytesToHex(SM4EncryptCbcBytes(Key, Iv, Input)));
end;

function SM4DecryptCbcBytesFromHex(Key, Iv: TBytes; const Input: AnsiString): TBytes;
begin
  Result := SM4DecryptCbcBytes(Key, Iv, HexToBytes(string(Input)));
end;

function SM4EncryptCfbBytesToHex(Key, Iv: TBytes; Input: TBytes): AnsiString;
begin
  Result := AnsiString(BytesToHex(SM4EncryptCfbBytes(Key, Iv, Input)));
end;

function SM4DecryptCfbBytesFromHex(Key, Iv: TBytes; const Input: AnsiString): TBytes;
begin
  Result := SM4DecryptCfbBytes(Key, Iv, HexToBytes(string(Input)));
end;

function SM4EncryptOfbBytesToHex(Key, Iv: TBytes; Input: TBytes): AnsiString;
begin
  Result := AnsiString(BytesToHex(SM4EncryptOfbBytes(Key, Iv, Input)));
end;

function SM4DecryptOfbBytesFromHex(Key, Iv: TBytes; const Input: AnsiString): TBytes;
begin
  Result := SM4DecryptOfbBytes(Key, Iv, HexToBytes(string(Input)));
end;

function SM4EncryptCtrBytesToHex(Key, Nonce: TBytes; Input: TBytes): AnsiString;
begin
  Result := AnsiString(BytesToHex(SM4EncryptCtrBytes(Key, Nonce, Input)));
end;

function SM4DecryptCtrBytesFromHex(Key, Nonce: TBytes; const Input: AnsiString): TBytes;
begin
  Result := SM4DecryptCtrBytes(Key, Nonce, HexToBytes(string(Input)));
end;

procedure SM4EncryptStreamECB(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; Dest: TStream);
var
  TempIn, TempOut: TCnSM4Buffer;
  Done: Cardinal;
  Ctx: TCnSM4Context;
begin
  if Count = 0 then
  begin
    Source.Position := 0;
    Count := Source.Size;
  end
  else
    Count := Min(Count, Source.Size - Source.Position);

  if Count = 0 then
    Exit;

  SM4SetKeyEnc(Ctx, @(Key[0]));
  while Count >= SizeOf(TCnSM4Buffer) do
  begin
    Done := Source.Read(TempIn, SizeOf(TempIn));
    if Done < SizeOf(TempIn) then
      raise EStreamError.Create(SCnErrorSM4ReadError);

    SM4OneRound(@(Ctx.Sk[0]), @(TempIn[0]), @(TempOut[0]));

    Done := Dest.Write(TempOut, SizeOf(TempOut));
    if Done < SizeOf(TempOut) then
      raise EStreamError.Create(SCnErrorSM4WriteError);

    Dec(Count, SizeOf(TCnSM4Buffer));
  end;

  if Count > 0 then // 尾部补 0
  begin
    Done := Source.Read(TempIn, Count);
    if Done < Count then
      raise EStreamError.Create(SCnErrorSM4ReadError);
    FillChar(TempIn[Count], SizeOf(TempIn) - Count, 0);

    SM4OneRound(@(Ctx.Sk[0]), @(TempIn[0]), @(TempOut[0]));

    Done := Dest.Write(TempOut, SizeOf(TempOut));
    if Done < SizeOf(TempOut) then
      raise EStreamError.Create(SCnErrorSM4WriteError);
  end;
end;

procedure SM4DecryptStreamECB(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; Dest: TStream);
var
  TempIn, TempOut: TCnSM4Buffer;
  Done: Cardinal;
  Ctx: TCnSM4Context;
begin
  if Count = 0 then
  begin
    Source.Position := 0;
    Count := Source.Size;
  end
  else
    Count := Min(Count, Source.Size - Source.Position);

  if Count = 0 then
    Exit;
  if (Count mod SizeOf(TCnSM4Buffer)) > 0 then
    raise ECnSM4Exception.Create(SCnErrorSM4InvalidInBufSize);

  SM4SetKeyDec(Ctx, @(Key[0]));
  while Count >= SizeOf(TCnSM4Buffer) do
  begin
    Done := Source.Read(TempIn, SizeOf(TempIn));
    if Done < SizeOf(TempIn) then
      raise EStreamError.Create(SCnErrorSM4ReadError);

    SM4OneRound(@(Ctx.Sk[0]), @(TempIn[0]), @(TempOut[0]));

    Done := Dest.Write(TempOut, SizeOf(TempOut));
    if Done < SizeOf(TempOut) then
      raise EStreamError.Create(SCnErrorSM4WriteError);

    Dec(Count, SizeOf(TCnSM4Buffer));
  end;
end;

procedure SM4EncryptStreamCBC(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; const InitVector: TCnSM4Iv; Dest: TStream);
var
  TempIn, TempOut: TCnSM4Buffer;
  Vector: TCnSM4Iv;
  Done: Cardinal;
  Ctx: TCnSM4Context;
begin
  if Count = 0 then
  begin
    Source.Position := 0;
    Count := Source.Size;
  end
  else
    Count := Min(Count, Source.Size - Source.Position);

  if Count = 0 then
    Exit;

  Vector := InitVector;
  SM4SetKeyEnc(Ctx, @(Key[0]));

  while Count >= SizeOf(TCnSM4Buffer) do
  begin
    Done := Source.Read(TempIn, SizeOf(TempIn));
    if Done < SizeOf(TempIn) then
      raise EStreamError.Create(SCnErrorSM4ReadError);

    PCardinal(@TempIn[0])^ := PCardinal(@TempIn[0])^ xor PCardinal(@Vector[0])^;
    PCardinal(@TempIn[4])^ := PCardinal(@TempIn[4])^ xor PCardinal(@Vector[4])^;
    PCardinal(@TempIn[8])^ := PCardinal(@TempIn[8])^ xor PCardinal(@Vector[8])^;
    PCardinal(@TempIn[12])^ := PCardinal(@TempIn[12])^ xor PCardinal(@Vector[12])^;

    SM4OneRound(@(Ctx.Sk[0]), @(TempIn[0]), @(TempOut[0]));

    Done := Dest.Write(TempOut, SizeOf(TempOut));
    if Done < SizeOf(TempOut) then
      raise EStreamError.Create(SCnErrorSM4WriteError);

    Move(TempOut[0], Vector[0], SizeOf(TCnSM4Iv));
    Dec(Count, SizeOf(TCnSM4Buffer));
  end;

  if Count > 0 then
  begin
    Done := Source.Read(TempIn, Count);
    if Done < Count then
      raise EStreamError.Create(SCnErrorSM4ReadError);
    FillChar(TempIn[Count], SizeOf(TempIn) - Count, 0);

    PCardinal(@TempIn[0])^ := PCardinal(@TempIn[0])^ xor PCardinal(@Vector[0])^;
    PCardinal(@TempIn[4])^ := PCardinal(@TempIn[4])^ xor PCardinal(@Vector[4])^;
    PCardinal(@TempIn[8])^ := PCardinal(@TempIn[8])^ xor PCardinal(@Vector[8])^;
    PCardinal(@TempIn[12])^ := PCardinal(@TempIn[12])^ xor PCardinal(@Vector[12])^;

    SM4OneRound(@(Ctx.Sk[0]), @(TempIn[0]), @(TempOut[0]));

    Done := Dest.Write(TempOut, SizeOf(TempOut));
    if Done < SizeOf(TempOut) then
      raise EStreamError.Create(SCnErrorSM4WriteError);
  end;
end;

procedure SM4DecryptStreamCBC(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; const InitVector: TCnSM4Iv; Dest: TStream);
var
  TempIn, TempOut: TCnSM4Buffer;
  Vector1, Vector2: TCnSM4Iv;
  Done: Cardinal;
  Ctx: TCnSM4Context;
begin
  if Count = 0 then
  begin
    Source.Position := 0;
    Count := Source.Size;
  end
  else
    Count := Min(Count, Source.Size - Source.Position);

  if Count = 0 then
    Exit;
  if (Count mod SizeOf(TCnSM4Buffer)) > 0 then
    raise ECnSM4Exception.Create(SCnErrorSM4InvalidInBufSize);

  Vector1 := InitVector;
  SM4SetKeyDec(Ctx, @(Key[0]));

  while Count >= SizeOf(TCnSM4Buffer) do
  begin
    Done := Source.Read(TempIn, SizeOf(TempIn));
    if Done < SizeOf(TempIn) then
      raise EStreamError(SCnErrorSM4ReadError);

    Move(TempIn[0], Vector2[0], SizeOf(TCnSM4Iv));
    SM4OneRound(@(Ctx.Sk[0]), @(TempIn[0]), @(TempOut[0]));

    PCardinal(@TempOut[0])^ := PCardinal(@TempOut[0])^ xor PCardinal(@Vector1[0])^;
    PCardinal(@TempOut[4])^ := PCardinal(@TempOut[4])^ xor PCardinal(@Vector1[4])^;
    PCardinal(@TempOut[8])^ := PCardinal(@TempOut[8])^ xor PCardinal(@Vector1[8])^;
    PCardinal(@TempOut[12])^ := PCardinal(@TempOut[12])^ xor PCardinal(@Vector1[12])^;

    Done := Dest.Write(TempOut, SizeOf(TempOut));
    if Done < SizeOf(TempOut) then
      raise EStreamError(SCnErrorSM4WriteError);

    Vector1 := Vector2;
    Dec(Count, SizeOf(TCnSM4Buffer));
  end;
end;

procedure SM4EncryptStreamCFB(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; const InitVector: TCnSM4Iv; Dest: TStream);
var
  TempIn, TempOut: TCnSM4Buffer;
  Vector: TCnSM4Iv;
  Done: Cardinal;
  Ctx: TCnSM4Context;
begin
  if Count = 0 then
  begin
    Source.Position := 0;
    Count := Source.Size;
  end
  else
    Count := Min(Count, Source.Size - Source.Position);

  if Count = 0 then
    Exit;

  Vector := InitVector;
  SM4SetKeyEnc(Ctx, @(Key[0]));

  while Count >= SizeOf(TCnSM4Buffer) do
  begin
    Done := Source.Read(TempIn, SizeOf(TempIn));
    if Done < SizeOf(TempIn) then
      raise EStreamError.Create(SCnErrorSM4ReadError);

    SM4OneRound(@(Ctx.Sk[0]), @(Vector[0]), @(TempOut[0]));     // Key 先加密 Iv

    PCardinal(@TempOut[0])^ := PCardinal(@TempIn[0])^ xor PCardinal(@TempOut[0])^;  // 加密结果与明文异或
    PCardinal(@TempOut[4])^ := PCardinal(@TempIn[4])^ xor PCardinal(@TempOut[4])^;
    PCardinal(@TempOut[8])^ := PCardinal(@TempIn[8])^ xor PCardinal(@TempOut[8])^;
    PCardinal(@TempOut[12])^ := PCardinal(@TempIn[12])^ xor PCardinal(@TempOut[12])^;

    Done := Dest.Write(TempOut, SizeOf(TempOut));   // 异或的结果写进密文结果
    if Done < SizeOf(TempOut) then
      raise EStreamError.Create(SCnErrorSM4WriteError);

    Move(TempOut[0], Vector[0], SizeOf(TCnSM4Iv));    // 密文结果取代 Iv 供下一轮加密
    Dec(Count, SizeOf(TCnSM4Buffer));
  end;

  if Count > 0 then
  begin
    Done := Source.Read(TempIn, Count);
    if Done < Count then
      raise EStreamError.Create(SCnErrorSM4ReadError);
    SM4OneRound(@(Ctx.Sk[0]), @(Vector[0]), @(TempOut[0]));

    PCardinal(@TempOut[0])^ := PCardinal(@TempIn[0])^ xor PCardinal(@TempOut[0])^;
    PCardinal(@TempOut[4])^ := PCardinal(@TempIn[4])^ xor PCardinal(@TempOut[4])^;
    PCardinal(@TempOut[8])^ := PCardinal(@TempIn[8])^ xor PCardinal(@TempOut[8])^;
    PCardinal(@TempOut[12])^ := PCardinal(@TempIn[12])^ xor PCardinal(@TempOut[12])^;

    Done := Dest.Write(TempOut, Count);  // 最后写入的只包括密文长度的部分，无需整个块
    if Done < Count then
      raise EStreamError.Create(SCnErrorSM4WriteError);
  end;
end;

procedure SM4DecryptStreamCFB(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; const InitVector: TCnSM4Iv; Dest: TStream);
var
  TempIn, TempOut: TCnSM4Buffer;
  Vector: TCnSM4Iv;
  Done: Cardinal;
  Ctx: TCnSM4Context;
begin
  if Count = 0 then
  begin
    Source.Position := 0;
    Count := Source.Size;
  end
  else
    Count := Min(Count, Source.Size - Source.Position);

  if Count = 0 then
    Exit;

  Vector := InitVector;
  SM4SetKeyEnc(Ctx, @(Key[0]));  // 注意是加密！不是解密！

  while Count >= SizeOf(TCnSM4Buffer) do
  begin
    Done := Source.Read(TempIn, SizeOf(TempIn));             // 密文读入至 TempIn
    if Done < SizeOf(TempIn) then
      raise EStreamError(SCnErrorSM4ReadError);
    SM4OneRound(@(Ctx.Sk[0]), @(Vector[0]), @(TempOut[0])); // Iv 先加密至 TempOut

    // 加密后的内容 TempOut 和密文 TempIn 异或得到明文 TempOut
    PCardinal(@TempOut[0])^ := PCardinal(@TempOut[0])^ xor PCardinal(@TempIn[0])^;
    PCardinal(@TempOut[4])^ := PCardinal(@TempOut[4])^ xor PCardinal(@TempIn[4])^;
    PCardinal(@TempOut[8])^ := PCardinal(@TempOut[8])^ xor PCardinal(@TempIn[8])^;
    PCardinal(@TempOut[12])^ := PCardinal(@TempOut[12])^ xor PCardinal(@TempIn[12])^;

    Done := Dest.Write(TempOut, SizeOf(TempOut));      // 明文 TempOut 写出去
    if Done < SizeOf(TempOut) then
      raise EStreamError(SCnErrorSM4WriteError);
    Move(TempIn[0], Vector[0], SizeOf(TCnSM4Iv));       // 保留密文 TempIn 取代 Iv 作为下一次加密再异或的内容
    Dec(Count, SizeOf(TCnSM4Buffer));
  end;

  if Count > 0 then
  begin
    Done := Source.Read(TempIn, Count);
    if Done < Count then
      raise EStreamError.Create(SCnErrorSM4ReadError);
    SM4OneRound(@(Ctx.Sk[0]), @(Vector[0]), @(TempOut[0]));

    PCardinal(@TempOut[0])^ := PCardinal(@TempIn[0])^ xor PCardinal(@TempOut[0])^;
    PCardinal(@TempOut[4])^ := PCardinal(@TempIn[4])^ xor PCardinal(@TempOut[4])^;
    PCardinal(@TempOut[8])^ := PCardinal(@TempIn[8])^ xor PCardinal(@TempOut[8])^;
    PCardinal(@TempOut[12])^ := PCardinal(@TempIn[12])^ xor PCardinal(@TempOut[12])^;

    Done := Dest.Write(TempOut, Count);  // 最后写入的只包括密文长度的部分，无需整个块
    if Done < Count then
      raise EStreamError.Create(SCnErrorSM4WriteError);
  end;
end;

procedure SM4EncryptStreamOFB(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; const InitVector: TCnSM4Iv; Dest: TStream);
var
  TempIn, TempOut: TCnSM4Buffer;
  Vector: TCnSM4Iv;
  Done: Cardinal;
  Ctx: TCnSM4Context;
begin
  if Count = 0 then
  begin
    Source.Position := 0;
    Count := Source.Size;
  end
  else
    Count := Min(Count, Source.Size - Source.Position);

  if Count = 0 then
    Exit;

  Vector := InitVector;
  SM4SetKeyEnc(Ctx, @(Key[0]));

  while Count >= SizeOf(TCnSM4Buffer) do
  begin
    Done := Source.Read(TempIn, SizeOf(TempIn));
    if Done < SizeOf(TempIn) then
      raise EStreamError.Create(SCnErrorSM4ReadError);

    SM4OneRound(@(Ctx.Sk[0]), @(Vector[0]), @(TempOut[0]));     // Key 先加密 Iv

    PCardinal(@TempIn[0])^ := PCardinal(@TempIn[0])^ xor PCardinal(@TempOut[0])^;  // 加密结果与明文异或
    PCardinal(@TempIn[4])^ := PCardinal(@TempIn[4])^ xor PCardinal(@TempOut[4])^;
    PCardinal(@TempIn[8])^ := PCardinal(@TempIn[8])^ xor PCardinal(@TempOut[8])^;
    PCardinal(@TempIn[12])^ := PCardinal(@TempIn[12])^ xor PCardinal(@TempOut[12])^;

    Done := Dest.Write(TempIn, SizeOf(TempIn));     // 异或的结果写进密文结果
    if Done < SizeOf(TempIn) then
      raise EStreamError.Create(SCnErrorSM4WriteError);

    Move(TempOut[0], Vector[0], SizeOf(TCnSM4Iv));    // 加密结果取代 Iv 供下一轮加密，注意不是异或结果
    Dec(Count, SizeOf(TCnSM4Buffer));
  end;

  if Count > 0 then
  begin
    Done := Source.Read(TempIn, Count);
    if Done < Count then
      raise EStreamError.Create(SCnErrorSM4ReadError);
    SM4OneRound(@(Ctx.Sk[0]), @(Vector[0]), @(TempOut[0]));

    PCardinal(@TempIn[0])^ := PCardinal(@TempIn[0])^ xor PCardinal(@TempOut[0])^;
    PCardinal(@TempIn[4])^ := PCardinal(@TempIn[4])^ xor PCardinal(@TempOut[4])^;
    PCardinal(@TempIn[8])^ := PCardinal(@TempIn[8])^ xor PCardinal(@TempOut[8])^;
    PCardinal(@TempIn[12])^ := PCardinal(@TempIn[12])^ xor PCardinal(@TempOut[12])^;

    Done := Dest.Write(TempIn, Count);  // 最后写入的只包括密文长度的部分，无需整个块
    if Done < Count then
      raise EStreamError.Create(SCnErrorSM4WriteError);
  end;
end;

procedure SM4DecryptStreamOFB(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; const InitVector: TCnSM4Iv; Dest: TStream);
var
  TempIn, TempOut: TCnSM4Buffer;
  Vector: TCnSM4Iv;
  Done: Cardinal;
  Ctx: TCnSM4Context;
begin
  if Count = 0 then
  begin
    Source.Position := 0;
    Count := Source.Size;
  end
  else
    Count := Min(Count, Source.Size - Source.Position);

  if Count = 0 then
    Exit;

  Vector := InitVector;
  SM4SetKeyEnc(Ctx, @(Key[0]));  // 注意是加密！不是解密！

  while Count >= SizeOf(TCnSM4Buffer) do
  begin
    Done := Source.Read(TempIn, SizeOf(TempIn));             // 密文读入至 TempIn
    if Done < SizeOf(TempIn) then
      raise EStreamError(SCnErrorSM4ReadError);
    SM4OneRound(@(Ctx.Sk[0]), @(Vector[0]), @(TempOut[0]));  // Iv 先加密至 TempOut

    // 加密后的内容 TempOut 和密文 TempIn 异或得到明文 TempIn
    PCardinal(@TempIn[0])^ := PCardinal(@TempOut[0])^ xor PCardinal(@TempIn[0])^;
    PCardinal(@TempIn[4])^ := PCardinal(@TempOut[4])^ xor PCardinal(@TempIn[4])^;
    PCardinal(@TempIn[8])^ := PCardinal(@TempOut[8])^ xor PCardinal(@TempIn[8])^;
    PCardinal(@TempIn[12])^ := PCardinal(@TempOut[12])^ xor PCardinal(@TempIn[12])^;

    Done := Dest.Write(TempIn, SizeOf(TempIn));        // 明文 TempIn 写出去
    if Done < SizeOf(TempIn) then
      raise EStreamError(SCnErrorSM4WriteError);
    Move(TempOut[0], Vector[0], SizeOf(TCnSM4Iv));       // 保留加密结果 TempOut 取代 Iv 作为下一次加密再异或的内容
    Dec(Count, SizeOf(TCnSM4Buffer));
  end;

  if Count > 0 then
  begin
    Done := Source.Read(TempIn, Count);
    if Done < Count then
      raise EStreamError.Create(SCnErrorSM4ReadError);
    SM4OneRound(@(Ctx.Sk[0]), @(Vector[0]), @(TempOut[0]));

    PCardinal(@TempIn[0])^ := PCardinal(@TempIn[0])^ xor PCardinal(@TempOut[0])^;
    PCardinal(@TempIn[4])^ := PCardinal(@TempIn[4])^ xor PCardinal(@TempOut[4])^;
    PCardinal(@TempIn[8])^ := PCardinal(@TempIn[8])^ xor PCardinal(@TempOut[8])^;
    PCardinal(@TempIn[12])^ := PCardinal(@TempIn[12])^ xor PCardinal(@TempOut[12])^;

    Done := Dest.Write(TempIn, Count);  // 最后写入的只包括密文长度的部分，无需整个块
    if Done < Count then
      raise EStreamError.Create(SCnErrorSM4WriteError);
  end;
end;

procedure SM4EncryptStreamCTR(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; const InitNonce: TCnSM4Nonce; Dest: TStream);
var
  TempIn, TempOut: TCnSM4Buffer;
  Vector: TCnSM4Iv;
  Done: Cardinal;
  Ctx: TCnSM4Context;
  Cnt, T: Int64;
begin
  if Count = 0 then
  begin
    Source.Position := 0;
    Count := Source.Size;
  end
  else
    Count := Min(Count, Source.Size - Source.Position);

  if Count = 0 then
    Exit;

  Cnt := 1;
  SM4SetKeyEnc(Ctx, @(Key[0]));

  while Count >= SizeOf(TCnSM4Buffer) do
  begin
    Done := Source.Read(TempIn, SizeOf(TempIn));
    if Done < SizeOf(TempIn) then
      raise EStreamError.Create(SCnErrorSM4ReadError);

    // Nonce 和计数器拼成 Iv
    T := Int64HostToNetwork(Cnt);
    Move(InitNonce[0], Vector[0], SizeOf(TCnSM4Nonce));
    Move(T, Vector[SizeOf(TCnSM4Nonce)], SizeOf(Int64));

    SM4OneRound(@(Ctx.Sk[0]), @(Vector[0]), @(TempOut[0]));     // Key 先加密 Iv

    PCardinal(@TempIn[0])^ := PCardinal(@TempIn[0])^ xor PCardinal(@TempOut[0])^;  // 加密结果与明文异或
    PCardinal(@TempIn[4])^ := PCardinal(@TempIn[4])^ xor PCardinal(@TempOut[4])^;
    PCardinal(@TempIn[8])^ := PCardinal(@TempIn[8])^ xor PCardinal(@TempOut[8])^;
    PCardinal(@TempIn[12])^ := PCardinal(@TempIn[12])^ xor PCardinal(@TempOut[12])^;

    Done := Dest.Write(TempIn, SizeOf(TempIn));   // 异或的结果写进密文结果
    if Done < SizeOf(TempIn) then
      raise EStreamError.Create(SCnErrorSM4WriteError);

    Inc(Cnt);
    Dec(Count, SizeOf(TCnSM4Buffer));
  end;

  if Count > 0 then
  begin
    Done := Source.Read(TempIn, Count);
    if Done < Count then
      raise EStreamError.Create(SCnErrorSM4ReadError);

    // Nonce 和计数器拼成 Iv
    T := Int64HostToNetwork(Cnt);
    Move(InitNonce[0], Vector[0], SizeOf(TCnSM4Nonce));
    Move(T, Vector[SizeOf(TCnSM4Nonce)], SizeOf(Int64));

    SM4OneRound(@(Ctx.Sk[0]), @(Vector[0]), @(TempOut[0]));

    PCardinal(@TempIn[0])^ := PCardinal(@TempIn[0])^ xor PCardinal(@TempOut[0])^;
    PCardinal(@TempIn[4])^ := PCardinal(@TempIn[4])^ xor PCardinal(@TempOut[4])^;
    PCardinal(@TempIn[8])^ := PCardinal(@TempIn[8])^ xor PCardinal(@TempOut[8])^;
    PCardinal(@TempIn[12])^ := PCardinal(@TempIn[12])^ xor PCardinal(@TempOut[12])^;

    Done := Dest.Write(TempIn, Count);  // 最后写入的只包括密文长度的部分，无需整个块
    if Done < Count then
      raise EStreamError.Create(SCnErrorSM4WriteError);
  end;
end;

procedure SM4DecryptStreamCTR(Source: TStream; Count: Cardinal;
  const Key: TCnSM4Key; const InitNonce: TCnSM4Nonce; Dest: TStream);
var
  TempIn, TempOut: TCnSM4Buffer;
  Vector: TCnSM4Iv;
  Done: Cardinal;
  Ctx: TCnSM4Context;
  Cnt, T: Int64;
begin
  if Count = 0 then
  begin
    Source.Position := 0;
    Count := Source.Size;
  end
  else
    Count := Min(Count, Source.Size - Source.Position);

  if Count = 0 then
    Exit;

  Cnt := 1;
  SM4SetKeyEnc(Ctx, @(Key[0]));    // 注意是加密！不是解密！

  while Count >= SizeOf(TCnSM4Buffer) do
  begin
    Done := Source.Read(TempIn, SizeOf(TempIn));
    if Done < SizeOf(TempIn) then
      raise EStreamError.Create(SCnErrorSM4ReadError);

    // Nonce 和计数器拼成 Iv
    T := Int64HostToNetwork(Cnt);
    Move(InitNonce[0], Vector[0], SizeOf(TCnSM4Nonce));
    Move(T, Vector[SizeOf(TCnSM4Nonce)], SizeOf(Int64));

    SM4OneRound(@(Ctx.Sk[0]), @(Vector[0]), @(TempOut[0]));     // Key 先加密 Iv

    PCardinal(@TempIn[0])^ := PCardinal(@TempIn[0])^ xor PCardinal(@TempOut[0])^;  // 加密结果与密文异或
    PCardinal(@TempIn[4])^ := PCardinal(@TempIn[4])^ xor PCardinal(@TempOut[4])^;
    PCardinal(@TempIn[8])^ := PCardinal(@TempIn[8])^ xor PCardinal(@TempOut[8])^;
    PCardinal(@TempIn[12])^ := PCardinal(@TempIn[12])^ xor PCardinal(@TempOut[12])^;

    Done := Dest.Write(TempIn, SizeOf(TempIn));   // 异或的结果写进明文结果
    if Done < SizeOf(TempIn) then
      raise EStreamError.Create(SCnErrorSM4WriteError);

    Inc(Cnt);
    Dec(Count, SizeOf(TCnSM4Buffer));
  end;

  if Count > 0 then
  begin
    Done := Source.Read(TempIn, Count);
    if Done < Count then
      raise EStreamError.Create(SCnErrorSM4ReadError);

    // Nonce 和计数器拼成 Iv
    T := Int64HostToNetwork(Cnt);
    Move(InitNonce[0], Vector[0], SizeOf(TCnSM4Nonce));
    Move(T, Vector[SizeOf(TCnSM4Nonce)], SizeOf(Int64));

    SM4OneRound(@(Ctx.Sk[0]), @(Vector[0]), @(TempOut[0]));

    PCardinal(@TempIn[0])^ := PCardinal(@TempIn[0])^ xor PCardinal(@TempOut[0])^;
    PCardinal(@TempIn[4])^ := PCardinal(@TempIn[4])^ xor PCardinal(@TempOut[4])^;
    PCardinal(@TempIn[8])^ := PCardinal(@TempIn[8])^ xor PCardinal(@TempOut[8])^;
    PCardinal(@TempIn[12])^ := PCardinal(@TempIn[12])^ xor PCardinal(@TempOut[12])^;

    Done := Dest.Write(TempIn, Count);  // 最后写入的只包括密文长度的部分，无需整个块
    if Done < Count then
      raise EStreamError.Create(SCnErrorSM4WriteError);
  end;
end;

function SM4GetOutputLengthFromInputLength(InputByteLength: Integer): Integer;
begin
  Result := (((InputByteLength - 1) div CN_SM4_BLOCKSIZE) + 1) * CN_SM4_BLOCKSIZE;
end;

procedure SM4Encrypt(Key: PAnsiChar; Input: PAnsiChar; Output: PAnsiChar; ByteLen: Integer);
var
  Ctx: TCnSM4Context;
begin
  SM4SetKeyEnc(Ctx, Key);
  SM4CryptEcb(Ctx, SM4_ENCRYPT, ByteLen, Input, Output);
end;

procedure SM4Decrypt(Key: PAnsiChar; Input: PAnsiChar; Output: PAnsiChar; ByteLen: Integer);
var
  Ctx: TCnSM4Context;
begin
  SM4SetKeyDec(Ctx, Key);
  SM4CryptEcb(Ctx, SM4_DECRYPT, ByteLen, Input, Output);
end;

end.
