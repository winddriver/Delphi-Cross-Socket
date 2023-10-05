program HttpClient;

{$I zLib.inc}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  LazUTF8
  ,SysUtils
  ,Classes
  ,Net.CrossHttpClient
  ,Net.OpenSSL
  ,Utils.Utils
  ;

var
  __HttpCli: ICrossHttpClient;

procedure TestHttpCli;
var
  LUrl: string;
begin
  if (__HttpCli = nil) then
    __HttpCli := TCrossHttpClient.Create;

  LUrl := 'https://www.bilibili.com/';

  __HttpCli.DoRequest('GET', LUrl, nil, TBytes(nil),
    nil,
    nil,
    procedure(const AResponse: ICrossHttpClientResponse)
    begin
      if (AResponse <> nil) and (AResponse.Content <> nil) then
      begin
        Writeln('HTTP GET success');
        Writeln(TUtils.GetString(AResponse.Content));
      end else
        Writeln('HTTP GET failed');
    end);
end;

begin
  // 如果 openssl 运行库名称与默认名称不一致, 请自行用以下代码修改
  // TSSLTools.LibSSL := 'libssl.so';
  // TSSLTools.LibCRYPTO := 'libcrypto.so';

  TestHttpCli;
  Readln;
end.

