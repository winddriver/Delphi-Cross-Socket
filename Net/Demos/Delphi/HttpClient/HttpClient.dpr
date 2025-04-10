program HttpClient;

{$APPTYPE CONSOLE}

{$I zLib.inc}

uses
  SysUtils,
  Classes,
  Net.CrossSocket.Base,
  Net.CrossHttpClient,
  Net.CrossHttpParams,
  Net.CrossSslSocket.Types,
  Net.CrossSslSocket.Base,
  Net.CrossSslSocket.OpenSSL,
  Net.OpenSSL,
  Utils.IOUtils,
  Utils.Utils;

var
  __HttpCli: ICrossHttpClient;

procedure PrintHelp;
begin
  Writeln('HttpClient <url>');
end;

procedure PrintEntryList(const AEntryList: TArray<TEntryData>; const AIndent: string);
var
  LEntryItem: TEntryData;
begin
  for LEntryItem in AEntryList do
  begin
    Writeln(AIndent + Format('%s: %s', [
      LEntryItem.Name,
      LEntryItem.Value
    ]));
  end;
end;

procedure PrintExtList(const AExtList: TArray<TExtensionRawData>; const AIndent: string);
var
  LExtItem: TExtensionRawData;
begin
  for LExtItem in AExtList do
  begin
    Writeln(AIndent + 'Name: ', LExtItem.Name);
    Writeln(AIndent + 'NID: ', LExtItem.NID);
    Writeln(AIndent + 'OID: ', LExtItem.OID);
    Writeln(AIndent + 'Critical: ', BoolToStr(LExtItem.Critical, True));
    Writeln(AIndent + 'Value: ', TUtils.BytesToHex(LExtItem.Value));
    Writeln;
  end;
end;

procedure PrintGeneralName(const AName: TGeneralName; const AIndent: string);
begin
  Writeln(AIndent + 'TypeID: ', AName.TypeID);
  Writeln(AIndent + 'TypeName: ', AName.TypeName);
  Writeln(AIndent + 'Value: ', AName.Value);
end;

procedure PrintGeneralNameList(const ANameList: TArray<TGeneralName>; const AIndent: string);
var
  LNameItem: TGeneralName;
begin
  for LNameItem in ANameList do
  begin
    PrintGeneralName(LNameItem, AIndent);
    Writeln;
  end;
end;

procedure PrintCrlDistPointList(const ACrlDistPointList: TArray<TCrlDistPoint>; const AIndent: string);
var
  LCrlDistPointItem: TCrlDistPoint;
begin
  for LCrlDistPointItem in ACrlDistPointList do
  begin
    Writeln(AIndent + 'Reasons: ', LCrlDistPointItem.Reasons);
    Writeln(AIndent + 'DpReasons: ', LCrlDistPointItem.DpReasons);

    Writeln(AIndent + 'DistPoint:');
    PrintGeneralNameList(LCrlDistPointItem.DistPoint, AIndent + '  ');

    Writeln(AIndent + 'CRLissuer:');
    PrintGeneralNameList(LCrlDistPointItem.CRLissuer, AIndent + '  ');

    Writeln;
  end;
end;

procedure PrintAuthorityInfoAccesses(const AAuthorityInfoAccesses: TArray<TAuthorityInfoAccess>; const AIndent: string);
var
  LAuthorityInfoAccessItem: TAuthorityInfoAccess;
begin
  for LAuthorityInfoAccessItem in AAuthorityInfoAccesses do
  begin
    Writeln(AIndent + 'Method: ', LAuthorityInfoAccessItem.Method);
    Writeln(AIndent + 'MethodDesc: ', LAuthorityInfoAccessItem.MethodDesc);

    Writeln(AIndent + 'Location:');
    PrintGeneralName(LAuthorityInfoAccessItem.Location, AIndent + '  ');

    Writeln;
  end;
end;

procedure PrintSctList(const ASctList: TArray<TSct>; const AIndent: string);
var
  LSctItem: TSct;
begin
  for LSctItem in ASctList do
  begin
    Writeln(AIndent + 'Version: ', LSctItem.Version);
    Writeln(AIndent + 'Sct: ', TUtils.BytesToHex(LSctItem.Sct));
    Writeln(AIndent + 'LogID: ', TUtils.BytesToHex(LSctItem.LogID));
    Writeln(AIndent + 'Timestamp: ', LSctItem.Timestamp);
    Writeln(AIndent + 'Ext: ', TUtils.BytesToHex(LSctItem.Ext));
    Writeln(AIndent + 'HashAlg: ', LSctItem.HashAlg);
    Writeln(AIndent + 'SigAlg: ', LSctItem.SigAlg);
    Writeln(AIndent + 'Sig: ', TUtils.BytesToHex(LSctItem.Sig));
    Writeln(AIndent + 'EntryType: ', LSctItem.EntryType);
    Writeln(AIndent + 'Source: ', LSctItem.Source);
    Writeln(AIndent + 'ValidationStatus: ', LSctItem.ValidationStatus);

    Writeln;
  end;
end;

procedure PrintBasicConstraints(const ABasicConstraints: TBasicConstraints; const AIndent: string);
begin
  Writeln(AIndent + 'CA: ', ABasicConstraints.CA);
  Writeln(AIndent + 'PathLen: ', ABasicConstraints.PathLen);
end;

procedure PringExtKeyUsage(const AExtKeyUsage: TExtKeyUsage; const AIndent: string);
var
  LExtKeyUsageItem: TExtKeyUsageItem;
begin
  Writeln(AIndent + Format('Flags: 0x%x', [AExtKeyUsage.Flags]));
  Writeln;
  for LExtKeyUsageItem in AExtKeyUsage.List do
  begin
    Writeln(AIndent + 'NID: ', LExtKeyUsageItem.NID);
    Writeln(AIndent + 'OID: ', LExtKeyUsageItem.OID);
    Writeln(AIndent + 'Value: ', LExtKeyUsageItem.Value);
    Writeln;
  end;
end;

procedure PrintSslInfo(const ASslInfo: TSslInfo);
begin
  Writeln(Format('TLS Server Name: %s', [
    ASslInfo.HostName
  ]));

  Writeln(Format('SSL/TLS Protocol: %s,%s,%d,%d', [
    ASslInfo.SslVersion,
    ASslInfo.CurrentCipher,
    ASslInfo.CertInfo.PubKeyBits,
    ASslInfo.CurrentCipherBits
  ]));

  Writeln(Format('Server Temp Key: %s %d bits', [
    ASslInfo.TmpKeyType,
    ASslInfo.TmpKeyBits
  ]));

  Writeln(Format('Public Key: %s %d bits', [
    ASslInfo.CertInfo.PubKeyType,
    ASslInfo.CertInfo.PubKeyBits
  ]));

  Writeln('Signature Algorithm: ', ASslInfo.CertInfo.SigAlg);

  Writeln(Format('CertVersion: %d', [
    ASslInfo.CertInfo.Version + 1
  ]));

  Writeln(Format('Serial Number: %s', [
    TUtils.BytesToHex(ASslInfo.CertInfo.SerialNumber)
  ]));

  Writeln(Format('Expiration Date: %s - %s', [
    FormatDateTime('yyyy-mm-dd hh:nn:ss', ASslInfo.CertInfo.NotBefore),
    FormatDateTime('yyyy-mm-dd hh:nn:ss', ASslInfo.CertInfo.NotAfter)
  ]));

  Writeln;

  Writeln('Subject:');
  PrintEntryList(ASslInfo.CertInfo.Subject, '  ');
  Writeln;

  Writeln('Issuer:');
  PrintEntryList(ASslInfo.CertInfo.Issuer, '  ');
  Writeln;

  Writeln('SHA256Digest:');
  Writeln(Format('  Certificate: %s', [
    TUtils.BytesToHex(ASslInfo.CertInfo.SHA256Digest)
  ]));
  Writeln(Format('  Public Key: %s', [
    TUtils.BytesToHex(ASslInfo.CertInfo.PubKeySHA256Digest)
  ]));
  Writeln;

  Writeln('Extension:');
  Writeln('  AuthorityKeyID: ', TUtils.BytesToHex(ASslInfo.CertInfo.Extension.AuthorityKeyID));
  Writeln('  SubjectKeyID: ', TUtils.BytesToHex(ASslInfo.CertInfo.Extension.SubjectKeyID));
  Writeln(Format('  Key Usage: 0x%x', [ASslInfo.CertInfo.Extension.KeyUsage]));

  Writeln('  Alt Names:');
  PrintGeneralNameList(ASslInfo.CertInfo.Extension.AltNames, '    ');

  Writeln('  Crl Dist Points:');
  PrintCrlDistPointList(ASslInfo.CertInfo.Extension.CrlDistPoints, '    ');

  Writeln('  Authority Info Accesses:');
  PrintAuthorityInfoAccesses(ASslInfo.CertInfo.Extension.AuthorityInfoAccesses, '    ');

  Writeln('  Basic Constraints:');
  PrintBasicConstraints(ASslInfo.CertInfo.Extension.BasicConstraints, '    ');
  Writeln;

  Writeln('  ExtKey Usage:');
  PringExtKeyUsage(ASslInfo.CertInfo.Extension.ExtKeyUsage, '    ');

  Writeln('  Sct List:');
  PrintSctList(ASslInfo.CertInfo.Extension.SctList, '    ');

  Writeln('  RawData:');
  PrintExtList(ASslInfo.CertInfo.Extension.RawData, '    ');

  Writeln('Cert PEM:' + sLineBreak, ASslInfo.CertInfo.PEM);
  Writeln('Cert DER:' + sLineBreak, TUtils.BytesToHex(ASslInfo.CertInfo.DER));

  Writeln;
end;

procedure TestHttpCli;
var
  LUrl: string;
begin
  LUrl := ParamStr(1);
  if (LUrl = '') then
  begin
    PrintHelp();
    Exit;
  end;

  if (__HttpCli = nil) then
    __HttpCli := TCrossHttpClient.Create;

//  __HttpCli.LocalPort := 1111;
  __HttpCli.AutoUrlEncode := False;
  __HttpCli.DoRequest('GET', LUrl, nil, nil, 0,
    nil,
    procedure(const ARequest: ICrossHttpClientRequest)
    begin
//      ARequest.Header['User-Agent'] := 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36';
    end,
    procedure(const AResponse: ICrossHttpClientResponse)
    var
      LSslConnection: ICrossSslConnection;
      LSslInfo: TSslInfo;
    begin
      if (AResponse <> nil) and (AResponse.Content <> nil) then
      begin
        LSslConnection := AResponse.Connection as ICrossSslConnection;

        if LSslConnection.Ssl and LSslConnection.GetSslInfo(LSslInfo) then
          PrintSslInfo(LSslInfo);

        Writeln('HTTP GET success');
        Writeln(AResponse.StatusCode, ' ', AResponse.StatusText);
        Writeln(AResponse.Header.Encode);
        Writeln(TUtils.GetString(AResponse.Content));
      end else
        Writeln('HTTP GET failed');
    end);
end;

begin
  // 如果 openssl 运行库名称与默认名称不一致, 请自行用以下代码修改
  // TSSLTools.LibSSL := 'libssl.so';
  // TSSLTools.LibCRYPTO := 'libcrypto.so';

//  ReportMemoryLeaksOnShutdown := True;

  CrossSocketLogEnabled := False;
  TestHttpCli;
  Readln;
end.

