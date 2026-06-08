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

unit CnKDF;
{* |<PRE>
================================================================================
* 软件名称：开发包基础库
* 单元名称：密钥派生算法（KDF）单元
* 单元作者：CnPack 开发组 (master@cnpack.org)
* 备    注：本单元实现了基于 RFC2898 的 PBKDF1 与 PBKDF2 密钥派生算法，但 PBKDF1 不支持 MD2 算法。
*           同时也实现了基于 RFC5869 的 HKDF（基于 HMac 的密钥派生算法），
*           及国密 SM2/SM9 算法中规定的密码生成算法。
* 开发平台：WinXP + Delphi 5.0
* 兼容测试：暂未进行
* 本 地 化：该单元无需本地化处理
* 修改记录：2025.01.09 V1.5
*               加入 HKDF 实现函数
*           2022.06.21 V1.4
*               合并出一个基于字节数组的 CnSM2SM9KDF 函数，避免 AnsiString 在高版本 Delphi 下可能乱码
*           2022.04.26 V1.3
*               修改 LongWord 与 Integer 地址转换以支持 MacOS64
*           2022.01.02 V1.2
*               修正 CnPBKDF2 的一处问题以及在 Unicode 下的兼容性问题
*           2021.11.25 V1.1
*               修正 CnSM2KDF 在 Unicode 下的兼容性问题
*           2020.03.30 V1.0
*               创建单元，从 CnPemUtils 中独立出来
================================================================================
|</PRE>}

interface

{$I CnPack.inc}

uses
  SysUtils, Classes, CnNative, CnMD5, CnSHA1, CnSHA2, CnSHA3, CnSM3;

type
  TCnKeyDeriveHash = (ckdMd5, ckdSha256, ckdSha1);
  {* CnGetDeriveKey 中使用的杂凑方法}

  TCnPBKDF1KeyHash = (cpdfMd2, cpdfMd5, cpdfSha1);
  {* PBKDF1 规定的三种杂凑方法，其中 MD2 我们不支持}

  TCnPBKDF2KeyHash = (cpdfSha1Hmac, cpdfSha256Hmac);
  {* PBKDF2 规定的两种杂凑方法}

  TCnHKDFHash = (chkMd5, chkSha1, chkSha256, chkSha3_256, chkSm3);
  {* HKDF（HMAC-based Key Derivation Function）支持的杂凑类型}

  ECnKDFException = class(Exception);
  {* KDF 相关异常}

function CnGetDeriveKey(const Password: AnsiString; const Salt: AnsiString;
  OutKey: PAnsiChar; KeyLength: Cardinal; KeyHash: TCnKeyDeriveHash = ckdMd5): Boolean;
{* 类似于 Openssl 中的 BytesToKey，用密码和盐与指定的杂凑算法生成加密 Key，
   目前的限制是 KeyLength 最多支持两轮 Hash，也就是 MD5 32 字节，SHA256 64 字节。

   参数：
     const Password: AnsiString           - 明文密码
     const Salt: AnsiString               - 盐值
     OutKey: PAnsiChar                    - 输出密钥的数据块地址
     KeyLength: Cardinal                  - 输出密钥的数据块字节长度
     KeyHash: TCnKeyDeriveHash            - 杂凑算法

   返回值：Boolean                        - 返回是否生成成功
}

function CnPBKDF1(const Password: AnsiString; const Salt: AnsiString; Count: Integer;
  DerivedKeyByteLength: Integer; KeyHash: TCnPBKDF1KeyHash = cpdfMd5): AnsiString;
{* Password Based KDF 1 实现，简单的固定杂凑迭代，只支持 MD5 和 SHA1，参数与返回值均为 AnsiString。
   DerivedKeyByteLength 是所需的密钥字节数，长度固定。

   参数：
     const Password: AnsiString           - 明文密码
     const Salt: AnsiString               - 盐值
     Count: Integer                       - 运算轮数
     DerivedKeyByteLength: Integer        - 待生成的密钥的字节长度
     KeyHash: TCnPBKDF1KeyHash            - 杂凑算法

   返回值：AnsiString                     - 返回生成的密钥
}

function CnPBKDF2(const Password: AnsiString; const Salt: AnsiString; Count: Integer;
  DerivedKeyByteLength: Integer; KeyHash: TCnPBKDF2KeyHash = cpdfSha1Hmac): AnsiString;
{* Password Based KDF 2 实现，基于 HMAC-SHA1 或 HMAC-SHA256，参数与返回值均为 AnsiString。
   DerivedKeyByteLength 是所需的密钥字节数，长度可变，允许超长。

   参数：
     const Password: AnsiString           - 明文密码
     const Salt: AnsiString               - 盐值
     Count: Integer                       - 运算轮数
     DerivedKeyByteLength: Integer        - 待生成的密钥的字节长度
     KeyHash: TCnPBKDF2KeyHash            - 杂凑算法

   返回值：AnsiString                     - 返回生成的密钥
}

function CnPBKDF1Bytes(const Password: TBytes; const Salt: TBytes; Count: Integer;
  DerivedKeyByteLength: Integer; KeyHash: TCnPBKDF1KeyHash = cpdfMd5): TBytes;
{* Password Based KDF 1 实现，简单的固定杂凑迭代，只支持 MD5 和 SHA1，参数与返回值均为字节数组。
   DerivedKeyByteLength 是所需的密钥字节数，长度固定。

   参数：
     const Password: TBytes               - 明文密码
     const Salt: TBytes                   - 盐值
     Count: Integer                       - 运算轮数
     DerivedKeyByteLength: Integer        - 待生成的密钥的字节长度
     KeyHash: TCnPBKDF1KeyHash            - 杂凑算法

   返回值：TBytes                         - 返回生成的密钥
}

function CnPBKDF2Bytes(const Password: TBytes; const Salt: TBytes; Count: Integer;
  DerivedKeyByteLength: Integer; KeyHash: TCnPBKDF2KeyHash = cpdfSha1Hmac): TBytes;
{* Password Based KDF 2 实现，基于 HMAC-SHA1 或 HMAC-SHA256，参数与返回值均为字节数组。
   DerivedKeyByteLength 是所需的密钥字节数，长度可变，允许超长。

   参数：
     const Password: TBytes               - 明文密码
     const Salt: TBytes                   - 盐值
     Count: Integer                       - 运算轮数
     DerivedKeyByteLength: Integer        - 待生成的密钥的字节长度
     KeyHash: TCnPBKDF2KeyHash            - 杂凑算法

   返回值：TBytes                         - 返回生成的密钥
}

// ============ SM2/SM9 中规定的同一种密钥派生函数的六种封装实现 ===============

function CnSM2KDF(const Data: AnsiString; DerivedKeyByteLength: Integer): AnsiString;
{* SM2 椭圆曲线公钥密码算法中规定的密钥派生函数，DerivedKeyLength 是所需的密钥字节数，
   返回 AnsiString，同时似乎也是没有 SharedInfo 的 ANSI-X9.63-KDF。

   参数：
     const Data: AnsiString               - 用来生成密钥的原始数据，可以是明文密码
     DerivedKeyByteLength: Integer        - 待生成的密钥的字节长度

   返回值：AnsiString                     - 返回生成的密钥
}

function CnSM9KDF(Data: Pointer; DataByteLen: Integer; DerivedKeyByteLength: Integer): AnsiString;
{* SM9 标识密码算法中规定的密钥派生函数，DerivedKeyLength 是所需的密钥字节数，
   返回 AnsiString，同时似乎也是没有 SharedInfo 的 ANSI-X9.63-KDF。

   参数：
     Data: Pointer                        - 用来生成密钥的原始数据块地址
     DataByteLen: Integer                 - 用来生成密钥的原始数据的字节长度
     DerivedKeyByteLength: Integer        - 待生成的密钥的字节长度

   返回值：AnsiString                     - 返回生成的密钥
}

function CnSM2KDFBytes(const Data: TBytes; DerivedKeyByteLength: Integer): TBytes;
{* 参数为字节数组形式的 SM2 椭圆曲线公钥密码算法中规定的密钥派生函数，
   DerivedKeyLength 是所需的密钥字节数，返回生成的字节数组。

   参数：
     const Data: TBytes                   - 用来生成密钥的原始数据的字节数组
     DerivedKeyByteLength: Integer        - 待生成的密钥的字节长度

   返回值：TBytes                         - 返回生成的密钥
}

function CnSM9KDFBytes(Data: Pointer; DataByteLen: Integer; DerivedKeyByteLength: Integer): TBytes;
{* 参数为内存块形式的 SM9 标识密码算法中规定的密钥派生函数，
   DerivedKeyLength 是所需的密钥字节数，返回生成的字节数组。

   参数：
     Data: Pointer                        - 用来生成密钥的原始数据块地址
     DataByteLen: Integer                 - 用来生成密钥的原始数据的字节长度
     DerivedKeyByteLength: Integer        - 待生成的密钥的字节长度

   返回值：TBytes                         - 返回生成的密钥
}

function CnSM2SM9KDF(Data: TBytes; DerivedKeyByteLength: Integer): TBytes; overload;
{* 参数为字节数组形式的 SM2 椭圆曲线公钥密码算法与 SM9 标识密码算法中规定的密钥派生函数，
   DerivedKeyLength 是所需的密钥字节数，返回生成的密钥字节数组。

   参数：
     Data: TBytes                         - 用来生成密钥的原始数据的字节数组
     DerivedKeyByteLength: Integer        - 待生成的密钥的字节长度

   返回值：TBytes                         - 返回生成的密钥
}

function CnSM2SM9KDF(Data: Pointer; DataByteLen: Integer; DerivedKeyByteLength: Integer): TBytes; overload;
{* 参数为内存块形式的 SM2 椭圆曲线公钥密码算法与 SM9 标识密码算法中规定的密钥派生函数，
   DerivedKeyLength 是所需的密钥字节数，返回派生的密钥字节数组。

   参数：
     Data: Pointer                        - 用来生成密钥的原始数据块地址
     DataByteLen: Integer                 - 用来生成密钥的原始数据的字节长度
     DerivedKeyByteLength: Integer        - 待生成的密钥的字节长度

   返回值：TBytes                         - 返回生成的密钥
}

function CnHKDF(HKDF: TCnHKDFHash; IKM: Pointer; IKMByteLen: Integer;
  Salt: Pointer; SaltByteLen: Integer; Info: Pointer; InfoByteLen: Integer;
  DerivedKeyByteLength: Integer): TBytes; overload;
{* 基于 HMAC 的 KDF 密钥派生函数。输入 IKM、Salt 和 Info，产生指定长度的密钥。
   Salt 可为空，空则内部使用固定杂凑结果长度的全 0，Info 可为空。返回生成的密钥。

   参数：
     HKDF: TCnHKDFHash                    - 杂凑算法种类
     IKM: Pointer                         - 用来生成密钥的输入密码数据（Input Keying Material）块地址
     IKMByteLen: Integer                  - 用来生成密钥的输入密码数据的字节长度
     Salt: Pointer                        - 用来生成密钥的盐值数据块地址
     SaltByteLen: Integer                 - 用来生成密钥的盐值数据的字节长度
     Info: Pointer                        - 用来生成密钥的可选的信息数据块地址
     InfoByteLen: Integer                 - 用来生成密钥的可选的信息数据的字节长度
     DerivedKeyByteLength: Integer        - 待生成的密钥的字节长度

   返回值：TBytes                         - 返回生成的密钥
}

function CnHKDFBytes(HKDF: TCnHKDFHash; IKM: TBytes; Salt: TBytes; Info: TBytes;
  DerivedKeyByteLength: Integer): TBytes; overload;
{* 基于 HMAC 的 KDF 密钥派生函数。输入 IKM、Salt 和 Info 的字节数组，产生指定长度的密钥。
   Salt 可为空，空则内部使用固定杂凑结果长度的全 0，Info 可为空。返回生成的密钥。

     HKDF: TCnHKDFHash                    - 杂凑算法种类
     IKM: TBytes                          - 用来生成密钥的输入密码数据
     Salt: TBytes                         - 用来生成密钥的盐值数据
     Info: TBytes                         - 用来生成密钥的可选的信息数据
     DerivedKeyByteLength: Integer        - 待生成的密钥的字节长度

   返回值：TBytes                         - 返回生成的密钥
}

implementation

resourcestring
  SCnErrorKDFKeyTooLong = 'Derived Key Too Long.';
  SCnErrorKDFParam = 'Invalid Parameters.';
  SCnErrorKDFHashNOTSupport = 'Hash Method NOT Support.';

function Min(A, B: Integer): Integer; {$IFDEF SUPPORT_INLINE} inline; {$ENDIF}
begin
  if A < B then
    Result := A
  else
    Result := B;
end;

function CnGetDeriveKey(const Password, Salt: AnsiString; OutKey: PAnsiChar; KeyLength: Cardinal;
  KeyHash: TCnKeyDeriveHash): Boolean;
var
  Md5Dig, Md5Dig2: TCnMD5Digest;
  Sha256Dig, Sha256Dig2: TCnSHA256Digest;
  SaltBuf, PS, PSMD5, PSSHA256: AnsiString;
begin
  Result := False;

  if (Password = '') or (OutKey = nil) or (KeyLength < 8) then
    Exit;

  SetLength(SaltBuf, 8);
  FillChar(SaltBuf[1], Length(SaltBuf), 0);
  if Salt <> '' then
    Move(Salt[1], SaltBuf[1], Min(Length(Salt), 8));

  if not (KeyHash in [ckdMd5, ckdSha256]) then
    raise ECnKDFException.Create(SCnErrorKDFHashNOTSupport);

  PS := AnsiString(Password) + SaltBuf; // 规定前 8 个字节作为 Salt
  if KeyHash = ckdMd5 then
  begin
    SetLength(PSMD5, SizeOf(TCnMD5Digest) + Length(PS));
    Move(PS[1], PSMD5[SizeOf(TCnMD5Digest) + 1], Length(PS));
    Md5Dig := MD5StringA(PS);
    // 密码与 Salt 拼起来的 MD5 结果（16 Byte）作为第一部分

    Move(Md5Dig[0], OutKey^, Min(KeyLength, SizeOf(TCnMD5Digest)));
    if KeyLength <= SizeOf(TCnMD5Digest) then
    begin
      Result := True;
      Exit;
    end;

    KeyLength := KeyLength - SizeOf(TCnMD5Digest);
    OutKey := PAnsiChar(TCnNativeUInt(OutKey) + SizeOf(TCnMD5Digest));

    Move(Md5Dig[0], PSMD5[1], SizeOf(TCnMD5Digest));
    Md5Dig2 := MD5StringA(PSMD5);
    Move(Md5Dig2[0], OutKey^, Min(KeyLength, SizeOf(TCnMD5Digest)));
    if KeyLength <= SizeOf(TCnMD5Digest) then
      Result := True;

    // 否则 KeyLength 太大，满足不了
  end
  else if KeyHash = ckdSha256 then
  begin
    SetLength(PSSHA256, SizeOf(TCnSHA256Digest) + Length(PS));
    Move(PS[1], PSSHA256[SizeOf(TCnSHA256Digest) + 1], Length(PS));
    Sha256Dig := SHA256StringA(PS);
    // 密码与 Salt 拼起来的 SHA256 结果（32 Byte）作为第一部分

    Move(Sha256Dig[0], OutKey^, Min(KeyLength, SizeOf(TCnSHA256Digest)));
    if KeyLength <= SizeOf(TCnSHA256Digest) then
    begin
      Result := True;
      Exit;
    end;

    KeyLength := KeyLength - SizeOf(TCnSHA256Digest);
    OutKey := PAnsiChar(TCnNativeUInt(OutKey) + SizeOf(TCnSHA256Digest));

    Move(Sha256Dig[0], PSSHA256[1], SizeOf(TCnSHA256Digest));
    Sha256Dig2 := SHA256StringA(PSSHA256);
    Move(Sha256Dig2[0], OutKey^, Min(KeyLength, SizeOf(TCnSHA256Digest)));
    if KeyLength <= SizeOf(TCnSHA256Digest) then
      Result := True;

    // 否则 KeyLength 太大，满足不了
  end;
end;

(*
  T_1 = Hash (P || S) ,
  T_2 = Hash (T_1) ,
  ...
  T_c = Hash (T_{c-1}) ,
  DK = Tc<0..dkLen-1>
*)
function CnPBKDF1(const Password, Salt: AnsiString; Count, DerivedKeyByteLength: Integer;
  KeyHash: TCnPBKDF1KeyHash): AnsiString;
var
  P, S, Res: TBytes;
begin
  P := AnsiToBytes(Password);
  S := AnsiToBytes(Salt);
  Res := CnPBKDF1Bytes(P, S, Count, DerivedKeyByteLength, KeyHash);
  Result := BytesToAnsi(Res);
end;

{
  DK = T1 + T2 + ... + Tdklen/hlen
  Ti = F(Password, Salt, c, i)

  F(Password, Salt, c, i) = U1 ^ U2 ^ ... ^ Uc

  U1 = PRF(Password, Salt + INT_32_BE(i))
  U2 = PRF(Password, U1)
  ...
  Uc = PRF(Password, Uc-1)
}
function CnPBKDF2(const Password, Salt: AnsiString; Count, DerivedKeyByteLength: Integer;
  KeyHash: TCnPBKDF2KeyHash): AnsiString;
var
  P, S, Res: TBytes;
begin
  P := AnsiToBytes(Password);
  S := AnsiToBytes(Salt);
  Res := CnPBKDF2Bytes(P, S, Count, DerivedKeyByteLength, KeyHash);
  Result := BytesToAnsi(Res);
end;

function CnPBKDF1Bytes(const Password, Salt: TBytes; Count, DerivedKeyByteLength: Integer;
  KeyHash: TCnPBKDF1KeyHash = cpdfMd5): TBytes;
var
  I: Integer;
  Md5Dig, TM: TCnMD5Digest;
  Sha1Dig, TS: TCnSHA1Digest;
begin
  Result := nil;
  if (Password = nil) or (Count <= 0) or (DerivedKeyByteLength <= 0) then
    raise ECnKDFException.Create(SCnErrorKDFParam);

  case KeyHash of
    cpdfMd5:
      begin
        if DerivedKeyByteLength > SizeOf(TCnMD5Digest) then
          raise ECnKDFException.Create(SCnErrorKDFKeyTooLong);

        SetLength(Result, DerivedKeyByteLength);
        Md5Dig := MD5Bytes(ConcatBytes(Password, Salt));  // Got T1
        if Count > 1 then
        begin
          for I := 2 to Count do
          begin
            TM := Md5Dig;
            Md5Dig := MD5Buffer(TM[0], SizeOf(TCnMD5Digest)); // Got T_c
          end;
        end;

        Move(Md5Dig[0], Result[0], DerivedKeyByteLength);
      end;
    cpdfSha1:
      begin
        if DerivedKeyByteLength > SizeOf(TCnSHA1Digest) then
          raise ECnKDFException.Create(SCnErrorKDFKeyTooLong);

        SetLength(Result, DerivedKeyByteLength);
        Sha1Dig := SHA1Bytes(ConcatBytes(Password, Salt));  // Got T1
        if Count > 1 then
        begin
          for I := 2 to Count do
          begin
            TS := Sha1Dig;
            Sha1Dig := SHA1Buffer(TS[0], SizeOf(TCnSHA1Digest)); // Got T_c
          end;
        end;

        Move(Sha1Dig[0], Result[0], DerivedKeyByteLength);
      end;
    else
      raise ECnKDFException.Create(SCnErrorKDFHashNOTSupport);
  end;
end;

function CnPBKDF2Bytes(const Password, Salt: TBytes; Count, DerivedKeyByteLength: Integer;
  KeyHash: TCnPBKDF2KeyHash = cpdfSha1Hmac): TBytes;
var
  HLen, D, I, J, K: Integer;
  Sha1Dig1, Sha1Dig, T1: TCnSHA1Digest;
  Sha256Dig1, Sha256Dig, T256: TCnSHA256Digest;
  S, S1, S256, Pad: TBytes;
  PAddr: Pointer;
begin
  Result := nil;
  if (Salt = nil) or (Count <= 0) or (DerivedKeyByteLength <=0) then
    raise ECnKDFException.Create(SCnErrorKDFParam);

  if (Password = nil) or (Length(Password) = 0) then
    PAddr := nil
  else
    PAddr := @Password[0];

  case KeyHash of
    cpdfSha1Hmac:
      HLen := 20;
    cpdfSha256Hmac:
      HLen := 32;
  else
    raise ECnKDFException.Create(SCnErrorKDFParam);
  end;

  D := (DerivedKeyByteLength div HLen) + 1;
  SetLength(S1, SizeOf(TCnSHA1Digest));
  SetLength(S256, SizeOf(TCnSHA256Digest));

  SetLength(Pad, 4);
  if KeyHash = cpdfSha1Hmac then
  begin
    for I := 1 to D do
    begin
      Pad[0] := I shr 24;
      Pad[1] := I shr 16;
      Pad[2] := I shr 8;
      Pad[3] := I;
      S := ConcatBytes(Salt, Pad);

      SHA1Hmac(PAddr, Length(Password), PAnsiChar(@S[0]), Length(S), Sha1Dig1);
      T1 := Sha1Dig1;

      for J := 2 to Count do
      begin
        SHA1Hmac(PAddr, Length(Password), PAnsiChar(@T1[0]), SizeOf(TCnSHA1Digest), Sha1Dig);
        T1 := Sha1Dig;
        for K := Low(TCnSHA1Digest) to High(TCnSHA1Digest) do
          Sha1Dig1[K] := Sha1Dig1[K] xor T1[K];
      end;

      Move(Sha1Dig1[0], S1[0], Length(S1));
      Result := ConcatBytes(Result, S1);
    end;
    Result := Copy(Result, 0, DerivedKeyByteLength);
  end
  else if KeyHash = cpdfSha256Hmac then
  begin
    for I := 1 to D do
    begin
      Pad[0] := I shr 24;
      Pad[1] := I shr 16;
      Pad[2] := I shr 8;
      Pad[3] := I;
      S := ConcatBytes(Salt, Pad);

      SHA256Hmac(PAddr, Length(Password), PAnsiChar(@S[0]), Length(S), Sha256Dig1);
      T256 := Sha256Dig1;

      for J := 2 to Count do
      begin
        SHA256Hmac(PAddr, Length(Password), PAnsiChar(@T256[0]), SizeOf(TCnSHA256Digest), Sha256Dig);
        T256 := Sha256Dig;
        for K := Low(TCnSHA256Digest) to High(TCnSHA256Digest) do
          Sha256Dig1[K] := Sha256Dig1[K] xor T256[K];
      end;

      Move(Sha256Dig1[0], S256[0], SizeOf(TCnSHA256Digest));
      Result := ConcatBytes(Result, S256);
    end;
    Result := Copy(Result, 0, DerivedKeyByteLength);
  end;
end;

function CnSM2KDF(const Data: AnsiString; DerivedKeyByteLength: Integer): AnsiString;
var
  Res: TBytes;
begin
  if (Data = '') or (DerivedKeyByteLength <= 0) then
    raise ECnKDFException.Create(SCnErrorKDFParam);

  Res := CnSM2SM9KDF(@Data[1], Length(Data), DerivedKeyByteLength);
  Result := BytesToAnsi(Res);
end;

function CnSM9KDF(Data: Pointer; DataByteLen: Integer; DerivedKeyByteLength: Integer): AnsiString;
var
  Res: TBytes;
begin
  Res := CnSM2SM9KDF(Data, DataByteLen, DerivedKeyByteLength);
  Result := BytesToAnsi(Res);
end;

function CnSM2KDFBytes(const Data: TBytes; DerivedKeyByteLength: Integer): TBytes;
begin
  Result := CnSM2SM9KDF(Data, DerivedKeyByteLength);
end;

function CnSM9KDFBytes(Data: Pointer; DataByteLen: Integer; DerivedKeyByteLength: Integer): TBytes;
begin
  Result := CnSM2SM9KDF(Data, DataByteLen, DerivedKeyByteLength);
end;

function CnSM2SM9KDF(Data: TBytes; DerivedKeyByteLength: Integer): TBytes;
begin
  if (Data = nil) or (Length(Data) <= 0) or (DerivedKeyByteLength <= 0) then
    raise ECnKDFException.Create(SCnErrorKDFParam);

  Result := CnSM2SM9KDF(@Data[0], Length(Data), DerivedKeyByteLength);
end;

function CnSM2SM9KDF(Data: Pointer; DataByteLen: Integer; DerivedKeyByteLength: Integer): TBytes; overload;
var
  DArr: TBytes;
  CT, SCT: Cardinal;
  I, CeilLen: Integer;
  IsInt: Boolean;
  SM3D: TCnSM3Digest;
begin
  Result := nil;
  if (Data = nil) or (DataByteLen <= 0) or (DerivedKeyByteLength <= 0) then
    raise ECnKDFException.Create(SCnErrorKDFParam);

  DArr := nil;
  CT := 1;

  try
    SetLength(DArr, DataByteLen + SizeOf(Cardinal));
    Move(Data^, DArr[0], DataByteLen);

    IsInt := DerivedKeyByteLength mod SizeOf(TCnSM3Digest) = 0;
    CeilLen := (DerivedKeyByteLength + SizeOf(TCnSM3Digest) - 1) div SizeOf(TCnSM3Digest);

    SetLength(Result, DerivedKeyByteLength);
    for I := 1 to CeilLen do
    begin
      SCT := UInt32HostToNetwork(CT);  // 虽然文档中没说，但要倒序一下
      Move(SCT, DArr[DataByteLen], SizeOf(Cardinal));
      SM3D := SM3(@DArr[0], Length(DArr));

      if (I = CeilLen) and not IsInt then
      begin
        // 是最后一个，不整除 32 时只移动一部分
        Move(SM3D[0], Result[(I - 1) * SizeOf(TCnSM3Digest)], (DerivedKeyByteLength mod SizeOf(TCnSM3Digest)));
      end
      else
        Move(SM3D[0], Result[(I - 1) * SizeOf(TCnSM3Digest)], SizeOf(TCnSM3Digest));

      Inc(CT);
    end;
  finally
    SetLength(DArr, 0);
  end;
end;

function CnHKDF(HKDF: TCnHKDFHash; IKM: Pointer; IKMByteLen: Integer;
  Salt: Pointer; SaltByteLen: Integer; Info: Pointer; InfoByteLen: Integer;
  DerivedKeyByteLength: Integer): TBytes;
const
  MAX_BYTE = 255;
var
  PRKMd5, Md5T: TCnMD5Digest;
  PRKSha1, Sha1T: TCnSHA1Digest;
  PRKSha256, Sha256T: TCnSHA256Digest;
  PRKSha3256, Sha3256T: TCnSHA3_256Digest;
  PRKSm3, Sm3T: TCnSM3Digest;
  T0, T: TBytes;
  N, I, Start, HashLen: Integer;
begin
  if IKM = nil then
    IKMByteLen := 0;

  if Salt = nil then
    SaltByteLen := 0;

  if Info = nil then
    InfoByteLen := 0;

  if (IKMByteLen < 0) or (SaltByteLen < 0) or (InfoByteLen < 0) then
    raise ECnKDFException.Create(SCnErrorKDFParam);

  // Extract，就是 HMac(Salt, IKM)，注意 IKM 是数据，并非 HMac 的 Key
  case HKDF of
    chkMd5:
      begin
        if (DerivedKeyByteLength <= 0) or (DerivedKeyByteLength > MAX_BYTE * SizeOf(TCnMD5Digest)) then
          raise ECnKDFException.Create(SCnErrorKDFKeyTooLong);

        HashLen := SizeOf(TCnMD5Digest);
        if (Salt = nil) or (SaltByteLen <= 0) then
        begin
          FillChar(PRKMd5[0], HashLen, 0);
          MD5Hmac(@PRKMd5[0], HashLen, IKM, IKMByteLen, PRKMd5);
        end
        else
          MD5Hmac(Salt, SaltByteLen, IKM, IKMByteLen, PRKMd5);
      end;
    chkSha1:
      begin
        if (DerivedKeyByteLength <= 0) or (DerivedKeyByteLength > MAX_BYTE * SizeOf(TCnSHA1Digest)) then
          raise ECnKDFException.Create(SCnErrorKDFKeyTooLong);

        HashLen := SizeOf(TCnSHA1Digest);
        if (Salt = nil) or (SaltByteLen <= 0) then
        begin
          FillChar(PRKSha1[0], HashLen, 0);
          SHA1Hmac(@PRKSha1[0], HashLen, IKM, IKMByteLen, PRKSha1);
        end
        else
          SHA1Hmac(Salt, SaltByteLen, IKM, IKMByteLen, PRKSha1);
      end;
    chkSha256:
      begin
        if (DerivedKeyByteLength <= 0) or (DerivedKeyByteLength > MAX_BYTE * SizeOf(TCnSHA256Digest)) then
          raise ECnKDFException.Create(SCnErrorKDFKeyTooLong);

        HashLen := SizeOf(TCnSHA256Digest);
        if (Salt = nil) or (SaltByteLen <= 0) then
        begin
          FillChar(PRKSha256[0], HashLen, 0);
          SHA256Hmac(@PRKSha256[0], HashLen, IKM, IKMByteLen, PRKSha256);
        end
        else
          SHA256Hmac(Salt, SaltByteLen, IKM, IKMByteLen, PRKSha256);
      end;
    chkSha3_256:
      begin
        if (DerivedKeyByteLength <= 0) or (DerivedKeyByteLength > MAX_BYTE * SizeOf(TCnSHA3_256Digest)) then
          raise ECnKDFException.Create(SCnErrorKDFKeyTooLong);

        HashLen := SizeOf(TCnSHA3_256Digest);
        if (Salt = nil) or (SaltByteLen <= 0) then
        begin
          FillChar(PRKSha3256[0], HashLen, 0);
          SHA3_256Hmac(@PRKSha3256[0], HashLen, IKM, IKMByteLen, PRKSha3256);
        end
        else
          SHA3_256Hmac(Salt, SaltByteLen, IKM, IKMByteLen, PRKSha3256);
      end;
    chkSm3:
      begin
        if (DerivedKeyByteLength <= 0) or (DerivedKeyByteLength > MAX_BYTE * SizeOf(TCnSM3Digest)) then
          raise ECnKDFException.Create(SCnErrorKDFKeyTooLong);

        HashLen := SizeOf(TCnSM3Digest);
        if (Salt = nil) or (SaltByteLen <= 0) then
        begin
          FillChar(PRKSm3[0], HashLen, 0);
          SM3Hmac(@PRKSm3[0], HashLen, IKM, IKMByteLen, PRKSm3);
        end
        else
          SM3Hmac(Salt, SaltByteLen, IKM, IKMByteLen, PRKSm3);
      end;
  else
    raise ECnKDFException.Create(SCnErrorKDFHashNOTSupport);
  end;

  // 开始 Expand
  SetLength(T0, InfoByteLen + 1);
  if InfoByteLen > 0 then
    Move(Info^, T0[0], InfoByteLen);
  T0[InfoByteLen] := 1;    // 设置完拼装了 T0 计算的内容

  // 初始化每轮的计算内容
  SetLength(T, HashLen + InfoByteLen + 1);

  // 设置结果长度并计算轮数
  N := (DerivedKeyByteLength + HashLen - 1) div HashLen;
  SetLength(Result, DerivedKeyByteLength);

  // 从 T0 计算出第一个 T1
  case HKDF of
    chkMd5:       MD5Hmac(@PRKMd5[0], HashLen, @T0[0], Length(T0), Md5T);
    chkSha1:      SHA1Hmac(@PRKSha1[0], HashLen, @T0[0], Length(T0), Sha1T);
    chkSha256:    SHA256Hmac(@PRKSha256[0], HashLen, @T0[0], Length(T0), Sha256T);
    chkSha3_256:  SHA3_256Hmac(@PRKSha3256[0], HashLen, @T0[0], Length(T0), Sha3256T);
    chkSm3:       SM3Hmac(@PRKSm3[0], HashLen, @T0[0], Length(T0), Sm3T);
  end;

  Start := 0;
  for I := 1 to N do
  begin
    // 把 T1 拼在结果里
    if DerivedKeyByteLength > HashLen then
    begin
      case HKDF of
        chkMd5:       Move(Md5T[0], Result[Start], HashLen);
        chkSha1:      Move(Sha1T[0], Result[Start], HashLen);
        chkSha256:    Move(Sha256T[0], Result[Start], HashLen);
        chkSha3_256:  Move(Sha3256T[0], Result[Start], HashLen);
        chkSm3:       Move(Sm3T[0], Result[Start], HashLen);
      end;
      Inc(Start, HashLen);
      Dec(DerivedKeyByteLength, HashLen);
    end
    else
    begin
      case HKDF of
        chkMd5:       Move(Md5T[0], Result[Start], DerivedKeyByteLength);
        chkSha1:      Move(Sha1T[0], Result[Start], DerivedKeyByteLength);
        chkSha256:    Move(Sha256T[0], Result[Start], DerivedKeyByteLength);
        chkSha3_256:  Move(Sha3256T[0], Result[Start], DerivedKeyByteLength);
        chkSm3:       Move(Sm3T[0], Result[Start], DerivedKeyByteLength);
      end;
      Break;
    end;

    // 再拿 T1 和 Info 拼一起并加一
    case HKDF of
      chkMd5:       Move(Md5T[0], T[0], HashLen);
      chkSha1:      Move(Sha1T[0], T[0], HashLen);
      chkSha256:    Move(Sha256T[0], T[0], HashLen);
      chkSha3_256:  Move(Sha3256T[0], T[0], HashLen);
      chkSm3:       Move(Sm3T[0], T[0], HashLen);
    end;
    Move(Info^, T[HashLen], InfoByteLen);
    T[HashLen + InfoByteLen] := I + 1;

    // 计算杂凑 T2 搁回 T1
    case HKDF of
      chkMd5:       MD5Hmac(@PRKMd5[0], HashLen, @T[0], Length(T), Md5T);
      chkSha1:      SHA1Hmac(@PRKSha1[0], HashLen, @T[0], Length(T), Sha1T);
      chkSha256:    SHA256Hmac(@PRKSha256[0], HashLen, @T[0], Length(T), Sha256T);
      chkSha3_256:  SHA3_256Hmac(@PRKSha3256[0], HashLen, @T[0], Length(T), Sha3256T);
      chkSm3:       SM3Hmac(@PRKSm3[0], HashLen, @T[0], Length(T), Sm3T);
    end;
  end;
end;

function CnHKDFBytes(HKDF: TCnHKDFHash; IKM: TBytes; Salt: TBytes; Info: TBytes;
  DerivedKeyByteLength: Integer): TBytes;
var
  IKMP, SaltP, InfoP: Pointer;
  IKML, SaltL, InfoL: Integer;
begin
  IKMP := nil;
  SaltP := nil;
  InfoP := nil;
  IKML := 0;
  SaltL := 0;
  InfoL := 0;

  if Length(IKM) > 0 then
  begin
    IKMP := @IKM[0];
    IKML := Length(IKM);
  end;
  if Length(Salt) > 0 then
  begin
    SaltP := @Salt[0];
    SaltL := Length(Salt);
  end;
  if Length(Info) > 0 then
  begin
    InfoP := @Info[0];
    InfoL := Length(Info);
  end;

  Result := CnHKDF(HKDF, IKMP, IKML, SaltP, SaltL, InfoP, InfoL, DerivedKeyByteLength);
end;

end.
