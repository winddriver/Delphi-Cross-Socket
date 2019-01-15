unit Net.CrossSslSocket;

interface

uses
  Net.CrossSocket.Base,
  Net.CrossSslSocket.Base
  {$IFDEF __MBED_TLS__}
  ,Net.CrossSslSocket.MbedTls
  {$ELSE}
  ,Net.CrossSslSocket.OpenSSL
  {$ENDIF};

type
  TCrossSslConnection =
    {$IFDEF __MBED_TLS__}
    TCrossMbedTlsConnection
    {$ELSE}
    TCrossOpenSslConnection
    {$ENDIF};

  TCrossSslSocket =
    {$IFDEF __MBED_TLS__}
    TCrossMbedTlsSocket
    {$ELSE}
    TCrossOpenSslSocket
    {$ENDIF};

implementation

end.
