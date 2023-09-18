unit Net.CrossSslSocket.Base;

interface

{$I zLib.inc}

uses
  SysUtils,
  Classes,

  Net.CrossSocket.Base,
  Net.CrossSocket,

  Utils.IOUtils;

type
  ICrossSslConnection = interface(ICrossConnection)
  ['{7B7B1DE2-8EDE-4F10-8193-2769D29C59FB}']
    function GetSsl: Boolean;

    /// <summary>
    ///   是否已启用 SSL
    /// </summary>
    property Ssl: Boolean read GetSsl;
  end;

  /// <summary>
  ///   SSL Socket
  /// </summary>
  /// <remarks>
  ///   正确的使用步骤:
  ///   <list type="number">
  ///     <item>
  ///       SetCertificateificate 或 SetCertificateificateFile
  ///     </item>
  ///     <item>
  ///       SetPrivateKey 或 SetPrivateKeyFile, 客户端不需要这一步
  ///     </item>
  ///     <item>
  ///       Connect / Listen
  ///     </item>
  ///   </list>
  /// </remarks>
  ICrossSslSocket = interface(ICrossSocket)
  ['{A4765486-A0F1-4EFD-BC39-FA16AED21A6A}']
    function GetSsl: Boolean;

    /// <summary>
    ///   从内存加载证书
    /// </summary>
    /// <param name="ACertBuf">
    ///   证书缓冲区
    /// </param>
    /// <param name="ACertBufSize">
    ///   证书缓冲区大小
    /// </param>
    procedure SetCertificate(const ACertBuf: Pointer; const ACertBufSize: Integer); overload;

    /// <summary>
    ///   从字符串加载证书
    /// </summary>
    /// <param name="ACertStr">
    ///   证书字符串
    /// </param>
    procedure SetCertificate(const ACertStr: string); overload;

    /// <summary>
    ///   从文件加载证书
    /// </summary>
    /// <param name="ACertFile">
    ///   证书文件
    /// </param>
    procedure SetCertificateFile(const ACertFile: string);

    /// <summary>
    ///   从内存加载私钥
    /// </summary>
    /// <param name="APKeyBuf">
    ///   私钥缓冲区
    /// </param>
    /// <param name="APKeyBufSize">
    ///   私钥缓冲区大小
    /// </param>
    procedure SetPrivateKey(const APKeyBuf: Pointer; const APKeyBufSize: Integer); overload;

    /// <summary>
    ///   从字符串加载私钥
    /// </summary>
    /// <param name="APKeyStr">
    ///   私钥字符串
    /// </param>
    procedure SetPrivateKey(const APKeyStr: string); overload;

    /// <summary>
    ///   从文件加载私钥
    /// </summary>
    /// <param name="APKeyFile">
    ///   私钥文件
    /// </param>
    procedure SetPrivateKeyFile(const APKeyFile: string);

    /// <summary>
    ///   是否已启用 SSL
    /// </summary>
    property Ssl: Boolean read GetSsl;
  end;

  TCrossSslListenBase = class(TCrossListen);

  TCrossSslConnectionBase = class(TCrossConnection, ICrossSslConnection)
  protected
    function GetSsl: Boolean;
  public
    property Ssl: Boolean read GetSsl;
  end;

  TCrossSslSocketBase = class(TCrossSocket, ICrossSslSocket)
  private
    FSsl: Boolean;
  protected
    function GetSsl: Boolean;
  public
    constructor Create(const AIoThreads: Integer; const ASsl: Boolean); reintroduce; virtual;

    procedure SetCertificate(const ACertBuf: Pointer; const ACertBufSize: Integer); overload; virtual; abstract;
    procedure SetCertificate(const ACertBytes: TBytes); overload; virtual;
    procedure SetCertificate(const ACertStr: string); overload; virtual;
    procedure SetCertificateFile(const ACertFile: string); virtual;

    procedure SetPrivateKey(const APKeyBuf: Pointer; const APKeyBufSize: Integer); overload; virtual; abstract;
    procedure SetPrivateKey(const APKeyBytes: TBytes); overload; virtual;
    procedure SetPrivateKey(const APKeyStr: string); overload; virtual;
    procedure SetPrivateKeyFile(const APKeyFile: string); virtual;

    property Ssl: Boolean read GetSsl;
  end;

implementation

{ TCrossSslSocketBase }

constructor TCrossSslSocketBase.Create(const AIoThreads: Integer;
  const ASsl: Boolean);
begin
  inherited Create(AIoThreads);

  FSsl := ASsl;
end;

function TCrossSslSocketBase.GetSsl: Boolean;
begin
  Result := FSsl;
end;

procedure TCrossSslSocketBase.SetCertificate(const ACertBytes: TBytes);
begin
  SetCertificate(Pointer(ACertBytes), Length(ACertBytes));
end;

procedure TCrossSslSocketBase.SetCertificate(const ACertStr: string);
begin
  SetCertificate(TEncoding.ANSI.GetBytes(ACertStr));
end;

procedure TCrossSslSocketBase.SetCertificateFile(const ACertFile: string);
begin
  SetCertificate(TFileUtils.ReadAllBytes(ACertFile));
end;

procedure TCrossSslSocketBase.SetPrivateKey(const APKeyBytes: TBytes);
begin
  SetPrivateKey(Pointer(APKeyBytes), Length(APKeyBytes));
end;

procedure TCrossSslSocketBase.SetPrivateKey(const APKeyStr: string);
begin
  SetPrivateKey(TEncoding.ANSI.GetBytes(APKeyStr));
end;

procedure TCrossSslSocketBase.SetPrivateKeyFile(const APKeyFile: string);
begin
  SetPrivateKey(TFileUtils.ReadAllBytes(APKeyFile));
end;

{ TCrossSslConnectionBase }

function TCrossSslConnectionBase.GetSsl: Boolean;
begin
  Result := TCrossSslSocketBase(Owner).Ssl;
end;

end.
