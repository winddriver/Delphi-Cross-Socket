library IncompleteCrypto;

{$I ../../../../zLib.inc}

function OpenSSL_version_num: Longword; cdecl;
begin
  Result := $30000000;
end;

function OPENSSL_init_crypto(AOptions: UInt64; ASettings: Pointer): Integer; cdecl;
begin
  Result := 1;
end;

procedure OPENSSL_cleanup; cdecl;
begin
end;

// 故意缺少 ERR_clear_error，使真实动态绑定在部分赋值后失败。
exports OpenSSL_version_num, OPENSSL_init_crypto, OPENSSL_cleanup;

begin
end.
