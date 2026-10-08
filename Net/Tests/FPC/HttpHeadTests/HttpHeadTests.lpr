program HttpHeadTests;

{$I ..\..\..\..\zLib.inc}

uses
  SysUtils, Classes
  {$IFDEF FPC}
  ,DTF.RTL in '..\..\..\..\DelphiToFPC\DTF.RTL.pas'
  {$ENDIF}
  ,Utils.SyncObjs in '..\..\..\..\Utils\Utils.SyncObjs.pas'
  ,Net.CrossHttpUtils in '..\..\..\Net.CrossHttpUtils.pas'
  ,Net.CrossHttpParams in '..\..\..\Net.CrossHttpParams.pas'
  ,Net.CrossHttpClient in '..\..\..\Net.CrossHttpClient.pas'
  ;

type
  TResponseWaiter = class
  private
    FEvent: IEvent;
    FStatus: Integer;
    FBodySize: Int64;
    FConnectionId: string;
    FError: string;
  public
    CallbackCount: Integer;
    constructor Create;
    procedure Receive(const AResponse: ICrossHttpClientResponse);
    procedure Wait(const ABodySize: Int64);
    procedure Reset;
    property ConnectionId: string read FConnectionId;
  end;

procedure Check(const AValue: Boolean; const AMessage: string);
begin
  if not AValue then raise Exception.Create(AMessage);
end;

constructor TResponseWaiter.Create;
begin
  inherited;
  FEvent := TEvent.Create(True, False);
end;

procedure TResponseWaiter.Receive(const AResponse: ICrossHttpClientResponse);
begin
  try
    AtomicIncrement(CallbackCount);
    FStatus := AResponse.StatusCode;
    FConnectionId := AResponse.Header['X-Connection-Id'];
    if (AResponse.Content <> nil) then
      FBodySize := AResponse.Content.Size
    else
      FBodySize := 0;
  except
    on E: Exception do FError := E.Message;
  end;
  FEvent.SetEvent;
end;

procedure TResponseWaiter.Wait(const ABodySize: Int64);
begin
  Check(FEvent.WaitFor(8000) = TWaitResult.wrSignaled, '请求回调超时');
  Check(FError = '', '响应回调异常: ' + FError);
  Check(FStatus = 200, '响应状态错误: ' + IntToStr(FStatus));
  Check(FBodySize = ABodySize, '响应正文长度错误');
  Check(FConnectionId <> '', '缺少服务端连接标识');
end;

procedure TResponseWaiter.Reset;
begin
  FEvent.ResetEvent;
  FStatus := 0;
  FBodySize := -1;
  FConnectionId := '';
  FError := '';
end;

procedure TestRemove;
var
  LParams: TBaseParams;
begin
  LParams := THttpHeader.Create;
  try
    LParams.Remove('missing');
    LParams.Add('X-Keep', 'first');
    LParams.Add('Content-Length', '3', True);
    LParams.Add('content-length', '4', True);
    LParams.Add('X-Other', 'middle');
    LParams.Add('CONTENT-LENGTH', '5', True);
    LParams.Add('X-Keep', 'last', True);
    LParams.Remove('CoNtEnT-LeNgTh');
    Check(not LParams.ExistsParam('Content-Length'), '同名参数未全部删除');
    Check(LParams.Count = 3, '误删其它参数');
    Check(LParams.Items[0].Value = 'first', '其它参数顺序改变');
    Check(LParams.Items[1].Value = 'middle', '其它参数顺序改变');
    Check(LParams.Items[2].Value = 'last', '其它参数顺序改变');
    LParams.Remove(0);
    Check(LParams.Count = 2, '按索引删除了多项');
    Check(LParams['X-Keep'] = 'last', '按索引删除影响其它同名项');
    LParams.Remove('missing');
    Check(LParams.Count = 2, '不存在名称的删除改变了集合');
    LParams.Remove('X-Keep');
    LParams.Remove('X-Other');
    Check(LParams.Count = 0, '未能清空集合');
  finally
    LParams.Free;
  end;
end;

procedure TestRequest(const AMode, AUrl: string);
var
  LClient: ICrossHttpClient;
  LWaiter: TResponseWaiter;
  LCallback: TCrossHttpResponseProc;
  LInit: TCrossHttpRequestInitProc;
  LChunk: TCrossHttpChunkDataFunc;
  LHeaders: THttpHeader;
  LBody: TBytes;
  LStream: TMemoryStream;
  LProviderCalls: Integer;
  LConnectionId, LMethod: string;
  LCompressType: TCompressType;
begin
  LProviderCalls := 0;
  LStream := nil;
  LCompressType := ctNone;
  if (AMode = 'head-gzip') or (AMode = 'head-gzip-empty') then
    LCompressType := ctGZip;
  if (AMode = 'head-deflate-empty') then
    LCompressType := ctDeflate;
  LClient := TCrossHttpClient.Create(1, LCompressType);
  LClient.RequestTimeout := 3;
  LWaiter := TResponseWaiter.Create;
  LHeaders := THttpHeader.Create;
  try
    LCallback :=
      procedure(const AResponse: ICrossHttpClientResponse)
      begin
        LWaiter.Receive(AResponse);
      end;
    LInit := nil;
    LBody := TEncoding.ASCII.GetBytes('abc');
    LMethod := THttpMethod.HEAD;
    if (AMode = 'head-empty') or (AMode = 'head-headers')
      or (AMode = 'head-gzip-empty') or (AMode = 'head-deflate-empty') then
      LBody := nil;
    if (AMode = 'head-headers') then
    begin
      LHeaders.Add(HEADER_CONTENT_LENGTH, '3', True);
      LHeaders.Add('content-length', '3', True);
      LHeaders.Add(HEADER_TRANSFER_ENCODING, 'chunked', True);
      LInit :=
        procedure(const ARequest: ICrossHttpClientRequest)
        begin
          ARequest.Header.Add('CONTENT-LENGTH', '3', True);
          ARequest.Header.Add('transfer-encoding', 'chunked', True);
        end;
    end;
    if (AMode = 'post-empty') or (AMode = 'post-body')
      or (AMode = 'post-chunk') then LMethod := THttpMethod.POST;
    if (AMode = 'put-empty') then LMethod := THttpMethod.PUT;
    if (AMode = 'patch-empty') then LMethod := THttpMethod.PATCH;
    if (AMode = 'post-empty') or (AMode = 'put-empty')
      or (AMode = 'patch-empty') then LBody := nil;

    if (AMode = 'head-chunk') or (AMode = 'post-chunk') then
    begin
      LChunk :=
        function(const AData: PPointer; const ACount: PNativeInt): Boolean
        begin
          Inc(LProviderCalls);
          Result := LProviderCalls = 1;
          if Result then
          begin
            AData^ := @LBody[0];
            ACount^ := Length(LBody);
          end else
          begin
            AData^ := nil;
            ACount^ := 0;
          end;
        end;
      LClient.DoRequest(LMethod, AUrl, LHeaders, LChunk, nil, LInit, LCallback);
    end else
    if (AMode = 'head-stream') then
    begin
      LStream := TMemoryStream.Create;
      LStream.WriteBuffer(LBody[0], Length(LBody));
      LClient.DoRequest(LMethod, AUrl, LHeaders, TStream(LStream), nil, LInit, LCallback);
    end else
      LClient.DoRequest(LMethod, AUrl, LHeaders, LBody, nil, LInit, LCallback);

    if (LMethod = THttpMethod.HEAD) then
      LWaiter.Wait(0)
    else
      LWaiter.Wait(2);
    if (AMode = 'head-chunk') then
      Check(LProviderCalls = 0, 'HEAD 调用了正文 provider');
    if (AMode = 'post-chunk') then
      Check(LProviderCalls = 2, 'POST 未完整读取分块正文');
    LConnectionId := LWaiter.ConnectionId;
    LWaiter.Reset;

    // 同一客户端的后续 GET 必须复用连接，且响应不能被 HEAD 干扰。
    LClient.DoRequest(THttpMethod.GET, AUrl + '/after', nil,
      TBytes(nil), nil, nil, LCallback);
    LWaiter.Wait(2);
    Check(LWaiter.ConnectionId = LConnectionId, '未复用原连接');
    Check(AtomicCmpExchange(LWaiter.CallbackCount, 0, 0) = 2, '响应回调次数错误');
  finally
    // 先结束异步客户端，再释放回调使用的对象和正文。
    LClient.CancelAll;
    LClient := nil;
    LCallback := nil;
    LChunk := nil;
    LInit := nil;
    LHeaders.Free;
    LStream.Free;
    LWaiter.Free;
  end;
end;

begin
  try
    if ParamStr(1) = 'remove' then
      TestRemove
    else
    begin
      Check(ParamCount = 2, '参数: 测试名称 URL');
      TestRequest(ParamStr(1), ParamStr(2));
    end;
    Writeln('PASS: ', ParamStr(1));
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', ParamStr(1), ': ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
