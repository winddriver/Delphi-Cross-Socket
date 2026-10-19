unit Net.CrossHttpRouterDirUtils;

interface

{$I zLib.inc}

uses
  SysUtils,
  Classes,
  Generics.Collections,
  Generics.Defaults,

  {$IFDEF FPC}
  DTF.Generics,
  {$ENDIF}

  Net.CrossHttpUtils,
  Utils.StrUtils,
  Utils.Utils,
  Utils.IOUtils;

function BuildDirList(const ARealPath, ARequestPath, AHome: string): string; overload;
// 0 保留完整列表；正数最多枚举 N+1 个有效条目，选取前 N 项后排序。
function BuildDirList(const ARealPath, ARequestPath, AHome: string;
  const AMaxEntries: Integer): string; overload;

{$IFDEF CROSS_HTTP_DIRECTORY_TESTS}
type
  TDirectoryTestStage = (dsListCreated, dsSearchOpened, dsEntry,
    dsBeforeSort, dsBeforeRender, dsRow);
var
  DirectoryTestHook: procedure(const AStage: TDirectoryTestStage);
  DirectoryTestLiveLists, DirectoryTestEntries: Integer;
{$ENDIF}

implementation

{$region 'Dir辅助代码'}
type
  THttpFileEntry = record
    Name: string;
    Size: Int64;
    Time: TDateTime;
    Directory: Boolean;
    ReadOnly: Boolean;
    SysFile: Boolean;
    Hidden: Boolean;
  end;

  TPathComparer = {$IFDEF DELPHI}TDelegatedComparer{$ELSE}TDelegatedComparerAnonymousFunc{$ENDIF}<THttpFileEntry>;

  {$IFDEF CROSS_HTTP_DIRECTORY_TESTS}
  TDirectoryEntryList = class(TList<THttpFileEntry>)
  private
    FCounted: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
  end;

constructor TDirectoryEntryList.Create;
begin
  inherited Create;
  Inc(DirectoryTestLiveLists);
  FCounted := True;
end;

destructor TDirectoryEntryList.Destroy;
begin
  if FCounted then Dec(DirectoryTestLiveLists);
  inherited;
end;

procedure DirectoryTestStep(const AStage: TDirectoryTestStage);
begin
  if AStage = dsEntry then Inc(DirectoryTestEntries);
  if Assigned(DirectoryTestHook) then DirectoryTestHook(AStage);
end;
  {$ELSE}
  TDirectoryEntryList = TList<THttpFileEntry>;
  {$ENDIF}

function BuildDirList(const ARealPath, ARequestPath, AHome: string): string;
begin
  Result := BuildDirList(ARealPath, ARequestPath, AHome, 0);
end;

function BuildDirList(const ARealPath, ARequestPath, AHome: string;
  const AMaxEntries: Integer): string;
  function EncodeDirPath(const APath: string): string;
  var
    LParts: TArray<string>;
    I: Integer;
  begin
    LParts := APath.Split(['/'], TStringSplitOptions.ExcludeEmpty);
    for I := 0 to High(LParts) do
      LParts[I] := TCrossHttpUtils.UrlEncode(LParts[I]);
    Result := '/' + string.Join('/', LParts);
    if Length(LParts) > 0 then Result := Result + '/';
  end;

  function SmartSizeToStr(const ABytes: Int64): string;
  const
    KBYTES = Int64(1024);
    MBYTES = KBYTES * 1024;
    GBYTES = MBYTES * 1024;
    TBYTES = GBYTES * 1024;
    PBYTES = TBYTES * 1024;
  begin
    if (ABytes < KBYTES) then
      Result := Format('%dB', [ABytes])
    else if (ABytes < MBYTES) then
      Result := Format('%.2fK ', [ABytes / KBYTES])
    else if (ABytes < GBYTES) then
      Result := Format('%.2fM ', [ABytes / MBYTES])
    else if (ABytes < TBYTES) then
      Result := Format('%.2fG ', [ABytes / GBYTES])
    else if (ABytes < PBYTES) then
      Result := Format('%.2fT ', [ABytes / TBYTES])
    else
      Result := Format('%.2fP ', [ABytes / PBYTES]);
  end;

  function FormatDirEntry(const AUrlPath: string; const F: THttpFileEntry): string;
  var
    Attr, Link, NameString, SizeString: string;
  begin
    if (F.Name = '.') or (F.Name = '..') then
    begin
      Result := '';
      Exit;
    end;

    // drwsh
    Attr := '-rw--';
    if F.Directory then
    begin
      Attr[1] := 'd';
      SizeString := '';
      NameString := '<font color="#0074d9">' + TCrossHttpUtils.HtmlEncode(F.Name) + '</font>';
    end
    else
    begin
      SizeString := SmartSizeToStr(F.Size);
      NameString := TCrossHttpUtils.HtmlEncode(F.Name);
    end;

    if F.ReadOnly then
      Attr[3] := '-';

    if F.SysFile then
      Attr[4] := 's';

    if F.Hidden then
      Attr[5] := 'h';

    Link := AUrlPath + TCrossHttpUtils.UrlEncode(F.Name);
    if F.Directory then Link := Link + '/';

    Result :=
      '<TD WIDTH="55%" NOWRAP><A HREF="' + TCrossHttpUtils.HtmlEncode(Link) + '">' + NameString + '</A></TD>' +
      '<TD WIDTH="5%" ALIGN="LEFT" NOWRAP>' + Attr + '</TD>' +
      '<TD WIDTH="%15" ALIGN="right" NOWRAP>' + SizeString + '</TD>' +
      '<TD WIDTH="5%" NOWRAP></TD>' +
      '<TD WIDTH="20%" NOWRAP>' + FormatDateTime('YYYY-MM-DD HH:NN:SS', F.Time) + '</TD>';
  end;

  function PathToURL(const APath, AHome: string): string;
    function _NormalizePath(const APathStr: string): string;
    begin
      Result := '/' + string.Join('/', APathStr.Split(['/'], TStringSplitOptions.ExcludeEmpty));
      if Result <> '/' then Result := Result + '/';
    end;
  var
    LPath, LHome, LSubPath: string;
    LPathArr, LHomeArr: TArray<string>;
    I: Integer;
  begin
    LPath := _NormalizePath(APath);
    LHome := _NormalizePath(AHome);

    LPathArr := LPath.Split(['/'], TStringSplitOptions.ExcludeEmpty);
    LHomeArr := LHome.Split(['/'], TStringSplitOptions.ExcludeEmpty);
    if Length(LHomeArr) > Length(LPathArr) then Exit('');

    I := 0;
    while True do
    begin
      if (I >= Length(LPathArr)) or (I >= Length(LHomeArr))
        or not TStrUtils.SameText(LPathArr[I], LHomeArr[I]) then Break;
      Inc(I);
    end;

    Result := Format('<A HREF="%s"><b><font color="#ff4136">Home</font></b></A> / ',
      [TCrossHttpUtils.HtmlEncode(EncodeDirPath(LHome))]);
    LSubPath := LHome;

    while True do
    begin
      if (I >= Length(LPathArr)) then Break;

      LSubPath := LSubPath + LPathArr[I] + '/';
      Result := Result + Format('<A HREF="%s"><b><font color="#0074d9">%s</font></b></A> / ',
        [TCrossHttpUtils.HtmlEncode(EncodeDirPath(LSubPath)), TCrossHttpUtils.HtmlEncode(LPathArr[I])]);
      Inc(I);
    end;
  end;
var
  Status: Integer;
  F: TSearchRec;
  DirList, FileList: TDirectoryEntryList;
  Data: THttpFileEntry;
  LComparer: IComparer<THttpFileEntry>;
  i: Integer;
  Total: Cardinal;
  TotalBytes: Int64;
  HTML, LRequestUrl, LStatsPrefix: string;
  LSelected: Integer;
  LTruncated: Boolean;
begin
  if AMaxEntries < 0 then
    raise EArgumentOutOfRangeException.Create('目录条目上限不能为负数');
  LRequestUrl := EncodeDirPath(ARequestPath);
  LComparer := TPathComparer.Create(
    function(const ALeft, ARight: THttpFileEntry): Integer
    begin
      Result := TUtils.CompareStringIncludeNumber(
        ALeft.Name, ARight.Name);
    end);

  DirList := nil;
  FileList := nil;
  LSelected := 0;
  LTruncated := False;
  try
    DirList := TDirectoryEntryList.Create;
    {$IFDEF CROSS_HTTP_DIRECTORY_TESTS}DirectoryTestStep(dsListCreated);{$ENDIF}
    FileList := TDirectoryEntryList.Create;
    Status := FindFirst(TPathUtils.Combine(ARealPath, '*'), faAnyFile, F);
    try
      {$IFDEF CROSS_HTTP_DIRECTORY_TESTS}DirectoryTestStep(dsSearchOpened);{$ENDIF}
      while Status = 0 do
      begin
        if (F.Name <> '.') and (F.Name <> '..') then
        begin
          {$IFDEF CROSS_HTTP_DIRECTORY_TESTS}DirectoryTestStep(dsEntry);{$ENDIF}
          if (AMaxEntries > 0) and (LSelected >= AMaxEntries) then
          begin
            LTruncated := True;
            Break;
          end;
          Data.Name := F.Name;
          Data.Size := F.Size;
          Data.Time := F.TimeStamp;
          Data.Directory := ((F.Attr and faDirectory) <> 0);
          Data.ReadOnly := ((F.Attr and faReadOnly) <> 0);
          {$WARN SYMBOL_PLATFORM OFF}
          Data.SysFile := ((F.Attr and faSysFile) <> 0);
          Data.Hidden := ((F.Attr and faHidden) <> 0);
          {$WARN SYMBOL_PLATFORM ON}

          if ((F.Attr and faDirectory) <> 0) then
            DirList.Add(Data)
          else
            FileList.Add(Data);
          Inc(LSelected);
        end;

        Status := FindNext(F);
      end;
    finally
      FindClose(F);
    end;
    {$IFDEF CROSS_HTTP_DIRECTORY_TESTS}DirectoryTestStep(dsBeforeSort);{$ENDIF}
    DirList.Sort(LComparer);
    FileList.Sort(LComparer);

    {$IFDEF CROSS_HTTP_DIRECTORY_TESTS}DirectoryTestStep(dsBeforeRender);{$ENDIF}
    HTML :=
      '<HTML>' +
      '<HEAD>' +
      '' +
      '<STYLE TYPE="text/css">' +
      '.dirline {font-family: "Microsoft Yahei",simsun,arial; color: #111111; font-style: normal;}' +
      '.hline {height:0;overflow:hiddne;border-top:1px solid #C3C3C3}' +
      '.vline {width:0;overflow:hiddne;border-left:1px solid #C3C3C3}' +
      'a:link {text-decoration: none; color: #111111;}' +
      'a:visited {text-decoration: none; color: #111111;} ' +
      'a:hover {text-decoration: underline; color: #0000FF;}' +
      'a:active {text-decoration: none; color: #111111;}' +
      '</STYLE>' +
      '<TITLE>文件列表</TITLE>' +
      '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">' +
      '</HEAD>' +
      '<BODY>' +
      '<TABLE CLASS="dirline" WIDTH="90%" ALIGN="CENTER">' +
      '<TR><TD>' + PathToURL(ARequestPath, AHome) + '<BR><BR></TD></TR></TABLE>';

    LStatsPrefix := '';
    if LTruncated then
    begin
      LStatsPrefix := '本页';
      HTML := HTML + '<TABLE CLASS="dirline" WIDTH="90%" ALIGN="CENTER"><TR><TD>' +
        Format('仅显示枚举前 %d 项（非目录全量统计），已显示条目按目录优先和自然顺序排序。', [AMaxEntries]) +
        '</TD></TR></TABLE>';
    end;

    TotalBytes := 0;
    Total := DirList.Count + FileList.Count;
    if Total <= 0 then
      HTML := HTML + '<TABLE CLASS="dirline" WIDTH="90%" ALIGN="CENTER"><TR><TD><BR>空目录</TD></TR></TABLE>'
    else
    begin
      HTML := HTML +
        // 标题
        '<TABLE CLASS="dirline" WIDTH="90%" ALIGN="CENTER">' +
        '<TR>' +
        '<TD WIDTH="55%" NOWRAP>文件名</TD>' +
        '<TD WIDTH="5%" ALIGN="LEFT" NOWRAP>属性</TD>' +
        '<TD WIDTH="%15" ALIGN="right" NOWRAP>大小</TD>' +
        '<TD WIDTH="5%" NOWRAP></TD>' +
        '<TD WIDTH="20%" NOWRAP>修改时间</TD>' +
        '</TR>' +
        '</TABLE>' +

        // 一条灰色横线
        '<TABLE CLASS="dirline" WIDTH="90%" ALIGN="CENTER">' +
        '<TR><TD HEIGHT="3"><div class="hline"></div></TD></TR>' +
        '</TABLE>' +

        // 文件列表表格
        '<TABLE CLASS="dirline" WIDTH="90%" ALIGN="CENTER">';

      for i := 0 to DirList.Count - 1 do
      begin
        Data := DirList[i];
        {$IFDEF CROSS_HTTP_DIRECTORY_TESTS}DirectoryTestStep(dsRow);{$ENDIF}
        HTML := HTML + '<TR>' + FormatDirEntry(LRequestUrl, Data) + '</TR>';
      end;

      for i := 0 to FileList.Count - 1 do
      begin
        Data := FileList[i];
        {$IFDEF CROSS_HTTP_DIRECTORY_TESTS}DirectoryTestStep(dsRow);{$ENDIF}
        HTML := HTML + '<TR>' + FormatDirEntry(LRequestUrl, Data) + '</TR>';
        TotalBytes := TotalBytes + Data.Size;
      end;

      HTML := HTML + '</TABLE>' +
        // 一条灰色横线
        '<TABLE CLASS="dirline" WIDTH="90%" ALIGN="CENTER">' +
        '<TR><TD HEIGHT="3"><div class="hline"></div></TD></TR>' +
        '</TABLE>' +

        // 页脚统计信息
        '<TABLE CLASS="dirline" WIDTH="90%" ALIGN="CENTER">' +
        '<TR>' +
        '<TD WIDTH="55%" NOWRAP>' + LStatsPrefix + Format('目录: %d, 文件: %d', [DirList.Count, FileList.Count]) + '</TD>' +
        '<TD WIDTH="5%" NOWRAP></TD>' +
        '<TD WIDTH="%15" ALIGN="right" NOWRAP>' + SmartSizeToStr(TotalBytes) + '</TD>' +
        '<TD WIDTH="5%" NOWRAP></TD>' +
        '<TD WIDTH="20%" NOWRAP></TD>' +
        '</TR>' +
        '</TABLE>';
    end;

    HTML := HTML + '</BODY></HTML>';
    Result := HTML;
  finally
    FileList.Free;
    DirList.Free;
  end;
end;
{$endregion}

end.
