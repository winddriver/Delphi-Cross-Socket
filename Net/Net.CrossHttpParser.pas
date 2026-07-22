{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossHttpParser;

{$I zLib.inc}

interface

uses
  SysUtils,
  Classes,
  Math,
  //ZLib,
  {$IFDEF DELPHI}
  ZLib,
  {$ELSE}
  DTF.StaticZLib,
  {$ENDIF}

  Net.CrossHttpUtils,

  Utils.StrUtils;

const
  // 默认压缩比上限 (DecodedSize / EncodedSize)
  // 合法数据典型 1.5-15:1, 极端规整数据 (StringOfChar, 大块重复字节) 可达 100-500:1
  // 经典 zip bomb (42.zip) 约 100000:1, 极简 bomb 约 1000:1
  // 默认 1000:1 兜底拦截 zip bomb, 不影响合法极规整数据
  DEFAULT_MAX_COMPRESS_RATIO = 1000;

type
  TCrossHttpParseMode = (pmServer, pmClient);
  TCrossHttpParseState = (psIdle, psHeader, psBodyData, psChunkSize, psChunkData, psChunkEnd, psDone);

  /// <summary>
  ///   psHeader 阶段严格 CRLF 状态机 (RFC 7230 §3): 拒绝 bare-CR / bare-LF / 错乱
  ///   序列, 防御 HTTP 请求走私 (request smuggling).
  /// </summary>
  TCrossHttpHeaderCRLFState = (
    hcsLineBody,      // 行内字节, 期望普通字节或 \r
    hcsAfterCR,       // 已读 \r, 期望 \n
    hcsAfterCRLF,     // 已读 \r\n (空行起始), 期望普通字节、\r 或 EOF
    hcsAfterCRLFCR,   // 已读 \r\n\r, 期望 \n 完成 header
    hcsHeaderDone     // 已读完整 \r\n\r\n, header 结束
  );

  TOnHeaderData = procedure(const ADataPtr: Pointer; const ADataSize: Integer) of object;
  TOnGetHeaderValue = function(const AHeaderName: string; out AHeaderValues: TArray<string>): Boolean of object;
  TOnBodyBegin = procedure of object;
  TOnBodyData = procedure(const ADataPtr: Pointer; const ADataSize: Integer) of object;
  TOnBodyEnd = procedure of object;
  TOnParseBegin = procedure of object;
  TOnParseSuccess = procedure of object;
  TOnParseFailed = procedure(const ACode: Integer; const AError: string) of object;

  ICrossHttpParser = interface
  ['{A7E3F8D1-6B2C-4A9E-B5D7-1F0E8C3A2B4D}']
    procedure Decode(var ABuf: Pointer; var ALen: Integer);
    procedure Finish;
    procedure SetNoBody(const AValue: Boolean);

    function GetMaxHeaderSize: Integer;
    procedure SetMaxHeaderSize(const AValue: Integer);
    function GetMaxBodyDataSize: Integer;
    procedure SetMaxBodyDataSize(const AValue: Integer);
    function GetMaxCompressRatio: Integer;
    procedure SetMaxCompressRatio(const AValue: Integer);

    function GetOnHeaderData: TOnHeaderData;
    procedure SetOnHeaderData(const AValue: TOnHeaderData);
    function GetOnGetHeaderValue: TOnGetHeaderValue;
    procedure SetOnGetHeaderValue(const AValue: TOnGetHeaderValue);
    function GetOnBodyBegin: TOnBodyBegin;
    procedure SetOnBodyBegin(const AValue: TOnBodyBegin);
    function GetOnBodyData: TOnBodyData;
    procedure SetOnBodyData(const AValue: TOnBodyData);
    function GetOnBodyEnd: TOnBodyEnd;
    procedure SetOnBodyEnd(const AValue: TOnBodyEnd);
    function GetOnParseBegin: TOnParseBegin;
    procedure SetOnParseBegin(const AValue: TOnParseBegin);
    function GetOnParseSuccess: TOnParseSuccess;
    procedure SetOnParseSuccess(const AValue: TOnParseSuccess);
    function GetOnParseFailed: TOnParseFailed;
    procedure SetOnParseFailed(const AValue: TOnParseFailed);

    property MaxHeaderSize: Integer read GetMaxHeaderSize write SetMaxHeaderSize;
    property MaxBodyDataSize: Integer read GetMaxBodyDataSize write SetMaxBodyDataSize;
    property MaxCompressRatio: Integer read GetMaxCompressRatio write SetMaxCompressRatio;

    property OnHeaderData: TOnHeaderData read GetOnHeaderData write SetOnHeaderData;
    property OnGetHeaderValue: TOnGetHeaderValue read GetOnGetHeaderValue write SetOnGetHeaderValue;
    property OnBodyBegin: TOnBodyBegin read GetOnBodyBegin write SetOnBodyBegin;
    property OnBodyData: TOnBodyData read GetOnBodyData write SetOnBodyData;
    property OnBodyEnd: TOnBodyEnd read GetOnBodyEnd write SetOnBodyEnd;
    property OnParseBegin: TOnParseBegin read GetOnParseBegin write SetOnParseBegin;
    property OnParseSuccess: TOnParseSuccess read GetOnParseSuccess write SetOnParseSuccess;
    property OnParseFailed: TOnParseFailed read GetOnParseFailed write SetOnParseFailed;
  end;

  TCrossHttpParser = class(TInterfacedObject, ICrossHttpParser)
  private
    FMode: TCrossHttpParseMode;
    FMaxHeaderSize, FMaxBodyDataSize, FMaxCompressRatio: Integer;
    FOnHeaderData: TOnHeaderData;
    FOnGetHeaderValue: TOnGetHeaderValue;
    FOnBodyBegin: TOnBodyBegin;
    FOnBodyData: TOnBodyData;
    FOnBodyEnd: TOnBodyEnd;
    FOnParseBegin: TOnParseBegin;
    FOnParseSuccess: TOnParseSuccess;
    FOnParseFailed: TOnParseFailed;

    FContentLength: Int64;
    FTransferEncoding, FContentEncoding, FConnectionStr: string;
    FIsChunked: Boolean;

    FParsedBodySize, FDecodedBodySize: Int64;
    FParseState: TCrossHttpParseState;
    FCRCount, FLFCount: Integer;
    // psHeader 严格 CRLF 状态机 (含义详见 TCrossHttpHeaderCRLFState).
    FHeaderCRLFState: TCrossHttpHeaderCRLFState;
    FHeaderStream, FChunkSizeStream: TMemoryStream;
    FChunkSize, FChunkLeftSize: Integer;
    FHasBody, FNoBody: Boolean;

    // 动态解压
    FZCompressed: Boolean;
    FZStream: TZStreamRec;
    FZFlush: Integer;
    FZResult: Integer;
    FZOutSize: Integer;
    FZBuffer: TBytes;

    procedure _OnHeaderData(const ADataPtr: Pointer; const ADataSize: Integer);
    function _OnGetHeaderValues(const AHeaderName: string; out AHeaderValues: TArray<string>): Boolean;
    function _OnGetHeaderValue(const AHeaderName: string; out AHeaderValue: string): Boolean;
    procedure _OnBodyBegin;
    procedure _OnBodyData(const ADataPtr: Pointer; const ADataSize: Integer);
    procedure _OnBodyEnd;
    procedure _OnParseBegin;
    procedure _OnParseSuccess;
    procedure _OnParseFailed(const ACode: Integer; const AError: string);

    procedure _OnHeaderComplete;
    procedure _Reset;
  protected
    function GetMaxHeaderSize: Integer;
    procedure SetMaxHeaderSize(const AValue: Integer);
    function GetMaxBodyDataSize: Integer;
    procedure SetMaxBodyDataSize(const AValue: Integer);
    function GetMaxCompressRatio: Integer;
    procedure SetMaxCompressRatio(const AValue: Integer);

    function GetOnHeaderData: TOnHeaderData;
    procedure SetOnHeaderData(const AValue: TOnHeaderData);
    function GetOnGetHeaderValue: TOnGetHeaderValue;
    procedure SetOnGetHeaderValue(const AValue: TOnGetHeaderValue);
    function GetOnBodyBegin: TOnBodyBegin;
    procedure SetOnBodyBegin(const AValue: TOnBodyBegin);
    function GetOnBodyData: TOnBodyData;
    procedure SetOnBodyData(const AValue: TOnBodyData);
    function GetOnBodyEnd: TOnBodyEnd;
    procedure SetOnBodyEnd(const AValue: TOnBodyEnd);
    function GetOnParseBegin: TOnParseBegin;
    procedure SetOnParseBegin(const AValue: TOnParseBegin);
    function GetOnParseSuccess: TOnParseSuccess;
    procedure SetOnParseSuccess(const AValue: TOnParseSuccess);
    function GetOnParseFailed: TOnParseFailed;
    procedure SetOnParseFailed(const AValue: TOnParseFailed);
  public
    constructor Create(const AMode: TCrossHttpParseMode);
    destructor Destroy; override;

    procedure Decode(var ABuf: Pointer; var ALen: Integer);
    procedure Finish;
    procedure SetNoBody(const AValue: Boolean);

    property MaxHeaderSize: Integer read GetMaxHeaderSize write SetMaxHeaderSize;
    property MaxBodyDataSize: Integer read GetMaxBodyDataSize write SetMaxBodyDataSize;
    property MaxCompressRatio: Integer read GetMaxCompressRatio write SetMaxCompressRatio;

    property OnHeaderData: TOnHeaderData read GetOnHeaderData write SetOnHeaderData;
    property OnGetHeaderValue: TOnGetHeaderValue read GetOnGetHeaderValue write SetOnGetHeaderValue;
    property OnBodyBegin: TOnBodyBegin read GetOnBodyBegin write SetOnBodyBegin;
    property OnBodyData: TOnBodyData read GetOnBodyData write SetOnBodyData;
    property OnBodyEnd: TOnBodyEnd read GetOnBodyEnd write SetOnBodyEnd;
    property OnParseBegin: TOnParseBegin read GetOnParseBegin write SetOnParseBegin;
    property OnParseSuccess: TOnParseSuccess read GetOnParseSuccess write SetOnParseSuccess;
    property OnParseFailed: TOnParseFailed read GetOnParseFailed write SetOnParseFailed;
  end;

implementation

const
  MAX_CHUNK_SIZE_LINE = 64;
  // 解压初期累计输出小于此阈值时不检查 ratio, 避免短数据造成的误报
  MIN_DECOMPRESS_CHECK_BYTES = 1024;

function _TryParseContentLengthValue(const AValue: string;
  out AContentLength: Int64): Boolean;
var
  I, LDigit: Integer;
  LValueStr: string;
  LValue: Int64;
  LChar: Char;
begin
  AContentLength := -1;

  LValueStr := AValue.Trim;
  if (LValueStr = '') then Exit(False);

  LValue := 0;
  for I := 1 to Length(LValueStr) do
  begin
    LChar := LValueStr[I];
    case LChar of
      '0'..'9': LDigit := Ord(LChar) - Ord('0');
    else
      Exit(False);
    end;

    if (LValue > (High(Int64) - LDigit) div 10) then Exit(False);
    LValue := LValue * 10 + LDigit;
  end;

  AContentLength := LValue;
  Result := True;
end;

function _TryParseTransferEncodingValue(const AValue: string;
  out ATransferEncoding: string; out AIsChunked: Boolean): Boolean;
var
  LStart, LPos, LLen, LTokenCount: Integer;
  LToken: string;
begin
  ATransferEncoding := '';
  AIsChunked := False;
  LTokenCount := 0;

  LLen := Length(AValue);
  LStart := 1;
  while (LStart <= LLen + 1) do
  begin
    LPos := LStart;
    while (LPos <= LLen) and (AValue[LPos] <> ',') do
      Inc(LPos);

    LToken := Trim(Copy(AValue, LStart, LPos - LStart));
    if not TStrUtils.SameText(LToken, 'chunked') then Exit(False);

    Inc(LTokenCount);

    if (LPos > LLen) then Break;
    LStart := LPos + 1;
  end;

  if (LTokenCount <> 1) then Exit(False);

  ATransferEncoding := 'chunked';
  AIsChunked := True;
  Result := True;
end;

function _TryParseChunkSizeLine(const ALine: string; out AChunkSize: Integer): Boolean;
var
  I, LExtIndex, LDigit: Integer;
  LLine: string;
  LValue: Int64;
  LChar: Char;
begin
  AChunkSize := 0;
  LLine := ALine.Trim;
  LExtIndex := LLine.IndexOf(';');
  if (LExtIndex >= 0) then
    LLine := LLine.Substring(0, LExtIndex).Trim;

  if (LLine = '') then Exit(False);

  LValue := 0;
  for I := 1 to Length(LLine) do
  begin
    LChar := LLine[I];
    case LChar of
      '0'..'9': LDigit := Ord(LChar) - Ord('0');
      'a'..'f': LDigit := Ord(LChar) - Ord('a') + 10;
      'A'..'F': LDigit := Ord(LChar) - Ord('A') + 10;
    else
      Exit(False);
    end;

    if (LValue > (High(Integer) - LDigit) div 16) then Exit(False);
    LValue := LValue * 16 + LDigit;
  end;

  AChunkSize := LValue;
  Result := True;
end;

{ TCrossHttpParser }

constructor TCrossHttpParser.Create(const AMode: TCrossHttpParseMode);
begin
  FMode := AMode;
  FMaxCompressRatio := DEFAULT_MAX_COMPRESS_RATIO;
  FHeaderStream := TMemoryStream.Create;
  FParseState := psIdle;
end;

destructor TCrossHttpParser.Destroy;
begin
  Finish;

  FreeAndNil(FHeaderStream);
  FreeAndNil(FChunkSizeStream);

  inherited;
end;

procedure TCrossHttpParser.Decode(var ABuf: Pointer; var ALen: Integer);
var
  LPtr, LPtrEnd, LPtrHeader: PByte;
  LChunkSize: Integer;
  LLineStr: string;
begin
  {
  HTTP/1.1 200 OK
  Content-Type: application/json;charset=utf-8
  Content-Encoding: gzip
  Transfer-Encoding: chunked
  }
  {
  HTTP/1.1 200 OK
  Content-Type: text/plain
  Transfer-Encoding: chunked

  7\r\n
  Chunk 1\r\n
  6\r\n
  Chunk 2\r\n
  0\r\n
  \r\n
  }

  try
    if (FParseState = psIdle) then
    begin
      FParseState := psHeader;
      _OnParseBegin;
    end;

    // 在这里解析服务端发送过来的响应数据
    LPtr := ABuf;
    LPtrEnd := LPtr + ALen;
    LPtrHeader := LPtr;

    // 使用循环处理粘包, 比递归调用节省资源
    while (LPtr < LPtrEnd) and (FParseState <> psDone) do
    begin
      case FParseState of
        psHeader:
          begin
            // 严格 CRLF 状态机 (RFC 7230 §3): 拒绝 bare-CR / bare-LF, 防御请求走私.
            case LPtr^ of
              13 {\r}:
                begin
                  case FHeaderCRLFState of
                    hcsLineBody:   FHeaderCRLFState := hcsAfterCR;
                    hcsAfterCRLF:  FHeaderCRLFState := hcsAfterCRLFCR;
                  else
                    _OnParseFailed(400, 'CR not followed by LF in request header.');
                    Exit;
                  end;
                end;
              10 {\n}:
                begin
                  case FHeaderCRLFState of
                    hcsAfterCR:     FHeaderCRLFState := hcsAfterCRLF;
                    hcsAfterCRLFCR: FHeaderCRLFState := hcsHeaderDone;
                  else
                    _OnParseFailed(400, 'Bare LF in request header.');
                    Exit;
                  end;
                end;
            else
              case FHeaderCRLFState of
                hcsLineBody, hcsAfterCRLF:
                  FHeaderCRLFState := hcsLineBody;
                hcsAfterCR, hcsAfterCRLFCR:
                  begin
                    _OnParseFailed(400, 'CR not followed by LF in request header.');
                    Exit;
                  end;
              end;
            end;

            // Header尺寸超标
            if (FMaxHeaderSize > 0) and (FHeaderStream.Size + (LPtr - LPtrHeader) + 1 > FMaxHeaderSize) then
            begin
              _OnParseFailed(400, 'Request header too large.');
              Exit;
            end;

            Inc(LPtr);

            // HTTP头已接收完毕(标准 \r\n\r\n)
            if (FHeaderCRLFState = hcsHeaderDone) then
            begin
              FHeaderStream.Write(LPtrHeader^, LPtr - LPtrHeader);
              LPtrHeader := LPtr;
              FHeaderCRLFState := hcsLineBody;
              _OnHeaderComplete;
            end;
          end;

        // 非Chunked编码的Post数据(有 ContentLength)
        psBodyData:
          begin
            LChunkSize := LPtrEnd - LPtr;
            if (FContentLength > 0) then
              LChunkSize := Min(FContentLength - FParsedBodySize, LChunkSize);
            if (FMaxBodyDataSize > 0) and (FParsedBodySize + LChunkSize > FMaxBodyDataSize) then
            begin
              _OnParseFailed(400, 'Post data too large.');
              Exit;
            end;

            _OnBodyData(LPtr, LChunkSize);

            Inc(FParsedBodySize, LChunkSize);
            Inc(LPtr, LChunkSize);

            if (FContentLength > 0) and (FParsedBodySize >= FContentLength) then
            begin
              FParseState := psDone;
              _OnBodyEnd();
              Break;
            end;
          end;

        // Chunked编码: 块尺寸
        psChunkSize:
          begin
            case LPtr^ of
              13{\r}: Inc(FCRCount);
              10{\n}: Inc(FLFCount);
            else
              FCRCount := 0;
              FLFCount := 0;
              FChunkSizeStream.Write(LPtr^, 1);
              if (FChunkSizeStream.Size > MAX_CHUNK_SIZE_LINE) then
              begin
                _OnParseFailed(400, 'Invalid chunk size.');
                Exit;
              end;
            end;
            Inc(LPtr);

            if (FCRCount = 1) and (FLFCount = 1) then
            begin
              SetString(LLineStr, MarshaledAString(FChunkSizeStream.Memory), FChunkSizeStream.Size);
              if not _TryParseChunkSizeLine(LLineStr, FChunkSize) then
              begin
                _OnParseFailed(400, 'Invalid chunk size.');
                Exit;
              end;
              FParseState := psChunkData;
              FChunkLeftSize := FChunkSize;
            end;
          end;

        // Chunked编码: 块数据
        psChunkData:
          begin
            if (FChunkLeftSize > 0) then
            begin
              LChunkSize := Min(FChunkLeftSize, LPtrEnd - LPtr);
              if (FMaxBodyDataSize > 0) and (FParsedBodySize + LChunkSize > FMaxBodyDataSize) then
              begin
                _OnParseFailed(400, 'Post data too large.');
                Exit;
              end;

              _OnBodyData(LPtr, LChunkSize);

              Inc(FParsedBodySize, LChunkSize);
              Dec(FChunkLeftSize, LChunkSize);
              Inc(LPtr, LChunkSize);
            end;

            if (FChunkLeftSize <= 0) then
            begin
              FParseState := psChunkEnd;
              FCRCount := 0;
              FLFCount := 0;
            end;
          end;

        // Chunked编码: 块结束符\r\n
        psChunkEnd:
          begin
            case LPtr^ of
              13{\r}: Inc(FCRCount);
              10{\n}: Inc(FLFCount);
            else
              begin
                _OnParseFailed(400, 'Invalid chunk data.');
                Exit;
              end;
            end;
            Inc(LPtr);

            if (FCRCount = 1) and (FLFCount = 1) then
            begin
              // 最后一块的ChunSize为0
              if (FChunkSize > 0) then
              begin
                FParseState := psChunkSize;
                FChunkSizeStream.Clear;
                FCRCount := 0;
                FLFCount := 0;
              end else
              begin
                FParseState := psDone;
                FreeAndNil(FChunkSizeStream);
                _OnBodyEnd();
                Break;
              end;
            end;
          end;
      end;
    end;

    // 循环中途退出 (psBodyData 在循环内 Break, psDone 自然结束),
    // psHeader 仍有未提交数据则批量写入
    if (FParseState = psHeader) then
      FHeaderStream.Write(LPtrHeader^, LPtr - LPtrHeader);

    // 响应数据接收完毕
    if (FParseState = psDone) then
    begin
      _Reset;
      _OnParseSuccess();
    end;

    ABuf := LPtr;
    ALen := LPtrEnd - LPtr;
  except
    on e: Exception do
    begin
      // 出错后消耗全部数据，避免调用者死循环
      ABuf := Pointer(PByte(ABuf) + ALen);
      ALen := 0;

      if not (e is EAbort) then
        _OnParseFailed(500, e.Message);
    end;
  end;
end;

procedure TCrossHttpParser.Finish;
begin
  if (FMode = pmClient) and (FParseState = psBodyData) and FHasBody
    and (FContentLength < 0) and not FIsChunked then
  begin
    FParseState := psDone;
    _OnBodyEnd;
    _Reset;
    _OnParseSuccess;
  end;
end;

procedure TCrossHttpParser.SetNoBody(const AValue: Boolean);
begin
  FNoBody := AValue;
end;

procedure TCrossHttpParser._OnBodyBegin;
var
  LCompressType: TCompressType;
begin
  FZCompressed := False;
  FDecodedBodySize := 0;
  LCompressType := ctNone;

  // 根据 FContentEncoding(gzip deflate br) 判断使用哪种方式解压
  // 目前暂时只支持 gzip deflate
  // 初始化解压库
  if (FContentEncoding <> '') then
  begin
    if TStrUtils.SameText(FContentEncoding, 'gzip') then
    begin
      LCompressType := ctGZip;
      FZCompressed := True;
    end else
    if TStrUtils.SameText(FContentEncoding, 'deflate') then
    begin
      LCompressType := ctDeflate;
      FZCompressed := True;
    end;

    if FZCompressed then
    begin
      SetLength(FZBuffer, ZLIB_BUF_SIZE);

      FillChar(FZStream, SizeOf(TZStreamRec), 0);
      FZResult := Z_OK;
      FZFlush := Z_NO_FLUSH;

      if (inflateInit2(FZStream, ZLIB_WINDOW_BITS[LCompressType]) <> Z_OK) then
      begin
        FZCompressed := False;
        _OnParseFailed(400, 'inflateInit2 failed');
        Exit;
      end;
    end;
  end;

  if Assigned(FOnBodyBegin) then
    FOnBodyBegin();
end;

procedure TCrossHttpParser._OnBodyData(const ADataPtr: Pointer;
  const ADataSize: Integer);
begin
  // 如果数据是压缩的, 进行解压
  if FZCompressed then
  begin
    // 往输入缓冲区填入新数据
    // 对于使用 inflate 函数解压缩数据, 通常不需要使用 Z_FINISH 进行收尾。
    // Z_FINISH 选项通常在压缩时使用, 以表示已经完成了压缩的数据块。
    // 在解压缩过程中, inflate 函数会自动处理数据流的结束。
    // 当输入数据流中的所有数据都被解压缩时, inflate 函数会返回 Z_STREAM_END,
    // 这表示数据流已经结束，不需要额外的处理。
    FZStream.avail_in := ADataSize;
    FZStream.next_in := ADataPtr;
    FZFlush := Z_NO_FLUSH;

    repeat
      // 返回 Z_STREAM_END 表示所有数据处理完毕
      if (FZResult = Z_STREAM_END) then Break;

      // 解压数据输出缓冲区
      FZStream.avail_out := ZLIB_BUF_SIZE;
      FZStream.next_out := @FZBuffer[0];

      // 进行解压处理
      // 输入缓冲区数据可以大于输出缓冲区
      // 这种情况可以多次调用 inflate 分批解压,
      // 直到 avail_in=0  表示当前输入缓冲区数据已解压完毕
      FZResult := inflate(FZStream, FZFlush);

      // 解压出错之后直接结束
      if (FZResult < 0) then
      begin
        FZOutSize := 0;
        _OnParseFailed(400, 'inflate failed');
        Exit;
      end;

      // 已解压完成的数据大小
      FZOutSize := ZLIB_BUF_SIZE - FZStream.avail_out;

      if (FMaxBodyDataSize > 0) and (FDecodedBodySize + FZOutSize > FMaxBodyDataSize) then
      begin
        _OnParseFailed(400, 'Post data too large.');
        Exit;
      end;

      // 压缩比检查: 提前识别 zip bomb, 比 MaxBodyDataSize 更早截断
      // 用 (FParsedBodySize + ADataSize) 作为输入字节上限分母, 保守估计
      // 累计输出 <= MIN_DECOMPRESS_CHECK_BYTES 时跳过, 避免初期数据少时 ratio 失真
      if (FMaxCompressRatio > 0)
        and (FDecodedBodySize + FZOutSize > MIN_DECOMPRESS_CHECK_BYTES)
        and (FDecodedBodySize + FZOutSize >
             Int64(FParsedBodySize + ADataSize) * FMaxCompressRatio) then
      begin
        _OnParseFailed(400, 'Decompression ratio too high.');
        Exit;
      end;

      Inc(FDecodedBodySize, FZOutSize);

      // 保存已解压的数据
      if (FZOutSize > 0) and Assigned(FOnBodyData) then
        FOnBodyData(@FZBuffer[0], FZOutSize);
    until ((FZResult = Z_STREAM_END) or (FZStream.avail_in = 0));
  end else
  if Assigned(FOnBodyData) then
    FOnBodyData(ADataPtr, ADataSize);
end;

procedure TCrossHttpParser._OnBodyEnd;
begin
  if FZCompressed then
  begin
    inflateEnd(FZStream);
    FZCompressed := False;
  end;

  if Assigned(FOnBodyEnd) then
    FOnBodyEnd();
end;

function TCrossHttpParser._OnGetHeaderValues(const AHeaderName: string;
  out AHeaderValues: TArray<string>): Boolean;
begin
  if Assigned(FOnGetHeaderValue) then
    Result := FOnGetHeaderValue(AHeaderName, AHeaderValues)
  else
  begin
    SetLength(AHeaderValues, 0);
    Result := False;
  end;
end;

function TCrossHttpParser._OnGetHeaderValue(const AHeaderName: string;
  out AHeaderValue: string): Boolean;
var
  LHeaderValues: TArray<string>;
begin
  Result := _OnGetHeaderValues(AHeaderName, LHeaderValues)
    and (Length(LHeaderValues) > 0);
  if Result then
    AHeaderValue := LHeaderValues[0]
  else
    AHeaderValue := '';
end;

procedure TCrossHttpParser._OnHeaderData(const ADataPtr: Pointer;
  const ADataSize: Integer);
begin
  if Assigned(FOnHeaderData) then
    FOnHeaderData(ADataPtr, ADataSize);
end;

procedure TCrossHttpParser._OnParseBegin;
begin
  if Assigned(FOnParseBegin) then
    FOnParseBegin();
end;

procedure TCrossHttpParser._OnParseFailed(const ACode: Integer;
  const AError: string);
begin
  FParseState := psDone;

  if FZCompressed then
  begin
    inflateEnd(FZStream);
    FZCompressed := False;
  end;
  FreeAndNil(FChunkSizeStream);

  if Assigned(FOnParseFailed) then
    FOnParseFailed(ACode, AError);

  Abort;
end;

procedure TCrossHttpParser._OnParseSuccess;
begin
  if Assigned(FOnParseSuccess) then
    FOnParseSuccess();
end;

procedure TCrossHttpParser._OnHeaderComplete;
var
  LContentLength, LTransferEncoding: string;
  LContentLengthValues, LTransferEncodingValues: TArray<string>;
  LHasContentLength, LHasTransferEncoding: Boolean;
begin
  // 调用解码Header的回调
  _OnHeaderData(FHeaderStream.Memory, FHeaderStream.Size);

  // 数据体长度
  LHasContentLength := _OnGetHeaderValues(HEADER_CONTENT_LENGTH, LContentLengthValues)
    and (Length(LContentLengthValues) > 0);
  if LHasContentLength then
  begin
    if (Length(LContentLengthValues) > 1) then
    begin
      _OnParseFailed(400, 'Duplicate Content-Length.');
      Exit;
    end;
    LContentLength := LContentLengthValues[0];
  end else
    LContentLength := '';

  // 数据的编码方式
  LHasTransferEncoding := _OnGetHeaderValues(HEADER_TRANSFER_ENCODING, LTransferEncodingValues)
    and (Length(LTransferEncodingValues) > 0);
  if LHasTransferEncoding then
  begin
    if (Length(LTransferEncodingValues) <> 1) then
    begin
      _OnParseFailed(400, 'Duplicate Transfer-Encoding.');
      Exit;
    end;
    FTransferEncoding := LTransferEncodingValues[0];
  end else
    FTransferEncoding := '';

  // 数据的压缩方式
  _OnGetHeaderValue(HEADER_CONTENT_ENCODING, FContentEncoding);

  // 读取响应头中连接保持方式
  _OnGetHeaderValue(HEADER_CONNECTION, FConnectionStr);

  if (FMode = pmServer) and LHasContentLength then
  begin
    if not _TryParseContentLengthValue(LContentLength, FContentLength) then
    begin
      _OnParseFailed(400, 'Invalid Content-Length.');
      Exit;
    end;
  end else
  if LHasContentLength then
  begin
    if not _TryParseContentLengthValue(LContentLength, FContentLength) then
      FContentLength := -1;
  end else
    FContentLength := -1;

  if (FMode = pmServer) and LHasTransferEncoding then
  begin
    if not _TryParseTransferEncodingValue(FTransferEncoding,
      LTransferEncoding, FIsChunked) then
    begin
      _OnParseFailed(400, 'Invalid Transfer-Encoding.');
      Exit;
    end;
    FTransferEncoding := LTransferEncoding;
  end else
    FIsChunked := TStrUtils.SameText(FTransferEncoding, 'chunked');

  if (FMode = pmServer) and LHasContentLength and LHasTransferEncoding then
  begin
    _OnParseFailed(400, 'Content-Length and Transfer-Encoding conflict.');
    Exit;
  end;
  if FNoBody then
  begin
    FContentLength := 0;
    FIsChunked := False;
  end;

  // 检查 body 大小是否超限
  if (FMaxBodyDataSize > 0) and (FContentLength > FMaxBodyDataSize) then
  begin
    _OnParseFailed(400, 'Post data too large.');
    Exit;
  end;

  // 根据不同模式确认是否有body数据
  if FNoBody then
    FHasBody := False
  else if (FMode = pmServer) then
    FHasBody := (FContentLength > 0) or FIsChunked
  else
  begin
    if (FContentLength < 0) and not FIsChunked
      and TStrUtils.SameText(FConnectionStr, 'keep-alive') then
    begin
      _OnParseFailed(400, 'Invalid response data.');
      Exit;
    end;

    // 显式 Content-Length 决定消息体长度; 只有缺失时才允许按连接关闭定界.
    // 这样 Content-Length: 0 在 HTTP/1.1 隐式 keep-alive 下可立即完成解析.
    FHasBody := (FContentLength > 0) or FIsChunked
      or ((FContentLength < 0)
        and ((FConnectionStr = '')
          or TStrUtils.SameText(FConnectionStr, 'close')));
  end;

  if FHasBody then
  begin
    FParsedBodySize := 0;

    if FIsChunked then
    begin
      FParseState := psChunkSize;
      FChunkSizeStream := TMemoryStream.Create;
    end else
      FParseState := psBodyData;

    _OnBodyBegin();
  end else
  begin
    FParseState := psDone;
  end;
end;

procedure TCrossHttpParser._Reset;
begin
  FParseState := psIdle;
  FHeaderStream.Clear;
  FreeAndNil(FChunkSizeStream);
  FCRCount := 0;
  FLFCount := 0;
  FHeaderCRLFState := hcsLineBody;
  FParsedBodySize := 0;
  FDecodedBodySize := 0;
  FNoBody := False;
end;

function TCrossHttpParser.GetMaxHeaderSize: Integer;
begin
  Result := FMaxHeaderSize;
end;

procedure TCrossHttpParser.SetMaxHeaderSize(const AValue: Integer);
begin
  FMaxHeaderSize := AValue;
end;

function TCrossHttpParser.GetMaxBodyDataSize: Integer;
begin
  Result := FMaxBodyDataSize;
end;

procedure TCrossHttpParser.SetMaxBodyDataSize(const AValue: Integer);
begin
  FMaxBodyDataSize := AValue;
end;

function TCrossHttpParser.GetMaxCompressRatio: Integer;
begin
  Result := FMaxCompressRatio;
end;

procedure TCrossHttpParser.SetMaxCompressRatio(const AValue: Integer);
begin
  FMaxCompressRatio := AValue;
end;

function TCrossHttpParser.GetOnHeaderData: TOnHeaderData;
begin
  Result := FOnHeaderData;
end;

procedure TCrossHttpParser.SetOnHeaderData(const AValue: TOnHeaderData);
begin
  FOnHeaderData := AValue;
end;

function TCrossHttpParser.GetOnGetHeaderValue: TOnGetHeaderValue;
begin
  Result := FOnGetHeaderValue;
end;

procedure TCrossHttpParser.SetOnGetHeaderValue(const AValue: TOnGetHeaderValue);
begin
  FOnGetHeaderValue := AValue;
end;

function TCrossHttpParser.GetOnBodyBegin: TOnBodyBegin;
begin
  Result := FOnBodyBegin;
end;

procedure TCrossHttpParser.SetOnBodyBegin(const AValue: TOnBodyBegin);
begin
  FOnBodyBegin := AValue;
end;

function TCrossHttpParser.GetOnBodyData: TOnBodyData;
begin
  Result := FOnBodyData;
end;

procedure TCrossHttpParser.SetOnBodyData(const AValue: TOnBodyData);
begin
  FOnBodyData := AValue;
end;

function TCrossHttpParser.GetOnBodyEnd: TOnBodyEnd;
begin
  Result := FOnBodyEnd;
end;

procedure TCrossHttpParser.SetOnBodyEnd(const AValue: TOnBodyEnd);
begin
  FOnBodyEnd := AValue;
end;

function TCrossHttpParser.GetOnParseBegin: TOnParseBegin;
begin
  Result := FOnParseBegin;
end;

procedure TCrossHttpParser.SetOnParseBegin(const AValue: TOnParseBegin);
begin
  FOnParseBegin := AValue;
end;

function TCrossHttpParser.GetOnParseSuccess: TOnParseSuccess;
begin
  Result := FOnParseSuccess;
end;

procedure TCrossHttpParser.SetOnParseSuccess(const AValue: TOnParseSuccess);
begin
  FOnParseSuccess := AValue;
end;

function TCrossHttpParser.GetOnParseFailed: TOnParseFailed;
begin
  Result := FOnParseFailed;
end;

procedure TCrossHttpParser.SetOnParseFailed(const AValue: TOnParseFailed);
begin
  FOnParseFailed := AValue;
end;

end.
