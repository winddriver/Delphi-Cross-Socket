program WebSocketClient;

{$APPTYPE CONSOLE}

{$I zLib.inc}

uses
  SysUtils
  ,Classes
  ,Net.CrossSocket.Base
  ,Net.CrossWebSocketClient
  ,Net.CrossWebSocketParser
  ,Net.OpenSSL
  ,Utils.Utils
  ;

var
  __WebSocket: ICrossWebSocket;

procedure TestWebSocketClient;
begin
  __WebSocket := TCrossWebSocket.Create('wss://127.0.0.1:8090/test_web_socket');

  __WebSocket.OnOpen(
    procedure
    begin
      Writeln('Open');
      __WebSocket.Ping;
    end);

  __WebSocket.OnClose(
    procedure
    begin
      Writeln('Close');
    end);

  __WebSocket.OnPing(
    procedure
    begin
      Writeln('Ping');
    end);

  __WebSocket.OnPong(
    procedure
    begin
      Writeln('Pong');
      __WebSocket.Send('你好AAA！',
        procedure(const ASuccess: Boolean)
        begin
          Writeln('你好AAA！ ', ASuccess);
        end);

      __WebSocket.Send('你好BBB！',
        procedure(const ASuccess: Boolean)
        begin
          Writeln('你好BBB！ ', ASuccess);
        end);

      __WebSocket.Send('你好CCC！',
      procedure(const ASuccess: Boolean)
        begin
          Writeln('你好CCC！ ', ASuccess);
        end);

      __WebSocket.Send('你好DDD！',
        procedure(const ASuccess: Boolean)
        begin
          Writeln('你好DDD！ ', ASuccess);
        end);
    end);

  __WebSocket.OnMessage(
    procedure(const AMessageType: TWsMessageType; const AMessageData: TBytes)
    var
      LMessage: string;
    begin
      case AMessageType of
        wtText:
          LMessage := TUtils.GetString(AMessageData);
      else
        LMessage := TUtils.BytesToHex(AMessageData);
      end;

      Writeln('[message]:', LMessage);
    end);

  __WebSocket.Open;
end;

begin
  // 如果 openssl 运行库名称与默认名称不一致, 请自行用以下代码修改
//  TSSLTools.LibSSL := 'libssl.so';
//  TSSLTools.LibCRYPTO := 'libcrypto.so';

  TestWebSocketClient;
  Readln;
end.

