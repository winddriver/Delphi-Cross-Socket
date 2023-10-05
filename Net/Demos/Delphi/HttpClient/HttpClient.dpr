program HttpClient;

{$APPTYPE CONSOLE}

{$I zLib.inc}

uses
  SysUtils
  ,Classes
  ,Net.CrossHttpClient
  ,Net.CrossHttpParams
  ,Net.OpenSSL
  ,Utils.Utils
  ;

var
  __HttpCli: ICrossHttpClient;

procedure TestHttpCli;
var
  LUrl: string;
  LMultiPart: THttpMultiPartFormData;
begin
  if (__HttpCli = nil) then
    __HttpCli := TCrossHttpClient.Create;;

//  LUrl := 'https://www.bilibili.com/';
//
//  __HttpCli.DoRequest('GET', LUrl, nil, TBytes(nil),
//    nil,
//    nil,
//    procedure(const AResponse: ICrossHttpClientResponse)
//    begin
//      if (AResponse <> nil) and (AResponse.Content <> nil) then
//      begin
//        Writeln('HTTP GET success');
//        Writeln(TUtils.GetString(AResponse.Content));
//      end else
//        Writeln('HTTP GET failed');
//    end);

  LMultiPart := THttpMultiPartFormData.Create;
  LMultiPart.AddFile('testfile', 'E:\books_chinese_withisbn.sql');

  __HttpCli.DoRequest('POST', 'http://192.168.230.220:8080/upload', nil, LMultiPart,
    nil,
    nil,
    procedure(const AResponse: ICrossHttpClientResponse)
    begin
      FreeAndNil(LMultiPart);
      if (AResponse <> nil) and (AResponse.Content <> nil) then
      begin
        Writeln('HTTP POST success');
        Writeln(TUtils.GetString(AResponse.Content));
      end else
        Writeln('HTTP POST failed');
    end);
end;

begin
  // 如果 openssl 运行库名称与默认名称不一致, 请自行用以下代码修改
  // TSSLTools.LibSSL := 'libssl.so';
  // TSSLTools.LibCRYPTO := 'libcrypto.so';

  TestHttpCli;
  Readln;
end.

