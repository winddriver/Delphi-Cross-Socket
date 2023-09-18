program HttpServer;

{$APPTYPE CONSOLE}

{$I zLib.inc}

uses
  SysUtils
  ,Classes
  ,Net.CrossSocket.Base
  ,Net.CrossHttpServer
  ,Net.OpenSSL
  ,Utils.Utils
  ;

var
  __HttpServer: ICrossHttpServer;

procedure TestCrossHttpServer;
var
  LResponseStr: string;
begin
  __HttpServer := TCrossHttpServer.Create(2, True);
  if __HttpServer.Ssl then
  begin
    __HttpServer.SetCertificateFile('server.crt');
    __HttpServer.SetPrivateKeyFile('server.key');
  end;

  __HttpServer.Port := 8080;
  __HttpServer.Start(
      procedure(const AListen: ICrossListen; const ASuccess: Boolean)
      begin
        if ASuccess then
        begin
          if __HttpServer.Ssl then
            Writeln('HTTP server(ssl) listen on [', AListen.LocalAddr, ':' , AListen.LocalPort, ']')
          else
            Writeln('HTTP server listen on [', AListen.LocalAddr, ':' , AListen.LocalPort, ']');
        end;
      end);

  __HttpServer.Get('/',
    procedure(const ARequest: ICrossHttpRequest; const AResponse: ICrossHttpResponse; var AHandled: Boolean)
    begin
      LResponseStr := TOSVersion.ToString + '<br>Hello World!';
      AResponse.Send(LResponseStr);
      AHandled := True;
    end);
end;

begin
  // 如果 openssl 运行库名称与默认名称不一致, 请自行用以下代码修改
  // TSSLTools.LibSSL := 'libssl.so';
  // TSSLTools.LibCRYPTO := 'libcrypto.so';

  TestCrossHttpServer;
  Readln;
end.

