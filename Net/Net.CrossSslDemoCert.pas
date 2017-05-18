{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSslDemoCert;

interface

const
  SSL_SERVER_CERT: string =
    '-----BEGIN CERTIFICATE-----' + sLineBreak +
    'MIIDRDCCAiwCAf8wDQYJKoZIhvcNAQEFBQAwaDELMAkGA1UEBhMCVVMxCzAJBgNV' + sLineBreak +
    'BAgMAkNBMQswCQYDVQQHDAJMQTEVMBMGA1UECgwMVGVzdCBSb290IENBMQswCQYD' + sLineBreak +
    'VQQLDAJJVDEbMBkGA1UEAwwSd3d3LnRlc3Ryb290Y2EuY29tMB4XDTEzMDIyNzE4' + sLineBreak +
    'MjE1NloXDTIzMDIyNTE4MjE1NlowaDELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAkNB' + sLineBreak +
    'MQswCQYDVQQHDAJMQTEVMBMGA1UECgwMVGVzdCBDb21wYW55MQswCQYDVQQLDAJJ' + sLineBreak +
    'VDEbMBkGA1UEAwwSd3d3LnRlc3RzZXJ2ZXIuY29tMIIBIjANBgkqhkiG9w0BAQEF' + sLineBreak +
    'AAOCAQ8AMIIBCgKCAQEAzkHv+S30g5Dc+F1RJ1PUq9Hbh1YkEUJdYEj7ti+UfONV' + sLineBreak +
    'NOT24hXzg8zaNSVO2Bhm+l8vzOVYMnjK9xcGSq5R5I633+lEeFdxURfsSJv9Vymq' + sLineBreak +
    'tHUj5eNkmjzWBVrf4HvnZTJtRJljs941zYUgyJT9tkQXaerGFKJ6sfdXYfhGrkuK' + sLineBreak +
    'gA1e71TwpRFYcfyYbQ3htENTh2CFBv7l5gjrITcmEJwpcU3U4nx4ZTr0IPLmV2kr' + sLineBreak +
    'K8IJysY4dqgRcmduEI5ZgbYGkdG8L7QjggFXA6QNDPu8DfmXeeqS0gIffEm22bk7' + sLineBreak +
    'b2fMnPfnFsJLsDdyhgrdYktnWhtZNij0y80tV4YCTwIDAQABMA0GCSqGSIb3DQEB' + sLineBreak +
    'BQUAA4IBAQDMLn9VnUQt6BWx73J1lExYO/LWulMOnMR/WSVFy9dSwry+E807ekMY' + sLineBreak +
    'WC8b3gpgDIqfkZjmttE9VtAdss2Baten+oBW+K13339sxHvcn30OxOs/Bln0yvaZ' + sLineBreak +
    'Be+Zir7iE450b1IdYI98PMTSKgrK2e3vx/uUOCgG2yvs6/1v5rz5er/M1SQNzdMS' + sLineBreak +
    'blelHWRQ1/ExwoUWBfIBkx/A4lTPmLgoC9fnXSiLhHKbZdfCJD8KLzEV0Se+ocn/' + sLineBreak +
    'vl+6tlcUznap0TsRQpC67T/NGUimxdAhb6G1/U6z9bq0QQIuDxpOIpvwIgLvfRFx' + sLineBreak +
    'qZQxmxOcK28fejHngmek7ZJNYKQbNewP' + sLineBreak +
    '-----END CERTIFICATE-----' + sLineBreak;

  SSL_SERVER_PKEY: string =
    '-----BEGIN PRIVATE KEY-----' + sLineBreak +
    'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDOQe/5LfSDkNz4' + sLineBreak +
    'XVEnU9Sr0duHViQRQl1gSPu2L5R841U05PbiFfODzNo1JU7YGGb6Xy/M5VgyeMr3' + sLineBreak +
    'FwZKrlHkjrff6UR4V3FRF+xIm/1XKaq0dSPl42SaPNYFWt/ge+dlMm1EmWOz3jXN' + sLineBreak +
    'hSDIlP22RBdp6sYUonqx91dh+EauS4qADV7vVPClEVhx/JhtDeG0Q1OHYIUG/uXm' + sLineBreak +
    'COshNyYQnClxTdTifHhlOvQg8uZXaSsrwgnKxjh2qBFyZ24QjlmBtgaR0bwvtCOC' + sLineBreak +
    'AVcDpA0M+7wN+Zd56pLSAh98SbbZuTtvZ8yc9+cWwkuwN3KGCt1iS2daG1k2KPTL' + sLineBreak +
    'zS1XhgJPAgMBAAECggEAIT83s27Y7yw2skI4hqJYsamOPW6BOdb8vjyFdoSM5uSu' + sLineBreak +
    'I2yU7zSioCgxNEfjQaoNT2ZwihKd+OTHsrSfawJWaQUoVot/YfaWaX/1sm6Sk64/' + sLineBreak +
    'uf733mKdIM+VoB9Z3xGZ5xIN0vT2wVOcUJiZBDwf+XVYYNZbP5BBPtaj20LuAcIZ' + sLineBreak +
    'OmW9uigdXQkQ1dylUkRPitjJ92bbysrTr621JTBSmvKnF7ctcF/Ql6VfS5RcqzYI' + sLineBreak +
    '6U1vozoFkjmUnExlYZHC6qKCFG73Z+IcC7ojdMpzMp4/EqiveV/9EVdFlLRB1YAa' + sLineBreak +
    'tND93xU9mo7L26XQzy79Xf2dWRUgUvaJ/7EvLA1RoQKBgQD2ZhJ9ogqfQ0ahq0D6' + sLineBreak +
    '5neZo6bPbckEKshv1GKR5ixnYpPp1kCIxM8oIzb9fOvTX4MOMeRzPJyrJNwhVgfY' + sLineBreak +
    'otWLrvkNviGHXN0frmkdj/Y/WSWh7clzzwXmGbB/8NPG4yzREvQ8vhKBkAmZln6K' + sLineBreak +
    'ICl8J5NxOxF6GgYJ793GcsfZVQKBgQDWS3DYMVQ3eRgFajkQ/8+Gacgdu+8/SyM1' + sLineBreak +
    'WptHOlPvKfqg3nZYPlAjMnVmk0Q7l/d2EtFBPP07/Jz0IvC/pMz0S8XfW/NigcRn' + sLineBreak +
    '0R5Nci3BXbmQEjxNGt0m0sX4C4/Bx8ei8pugipX96OemT/bWP05RskL6tWsofGsb' + sLineBreak +
    '8zgIQcldEwKBgCyx90iyzBp3qahJ2E+q3qcP+IJH9965pAIlFHxCtGtMhmg0ZSBq' + sLineBreak +
    'EunE+YSh1GVTPgKlKjt9Ey44UXX6lRHG99WOt762bn6Pac0FZivmoVR8Z0coSxKm' + sLineBreak +
    'yvsiTdHnbYL2UnraZVNfZxv5dMRXeDy1+NB8nVI81L7BWbcTu7bzuyzBAoGAY0j4' + sLineBreak +
    's3HHbxwvwPKCFhovcDs6eGxGYLDTUzjzkIC5uqlccYQgmKnmPyh1tFyu1F2ITbBS' + sLineBreak +
    'O0OioFRd887sdB5KxzUELIRRs2YkNWVyALfR8zEVdGa+gYrcw8wL5OyWYlXJbPmy' + sLineBreak +
    'mSMcc1OhYDDUUFdsVfWdisLbLxrWFVEOuOSiAvkCgYEA2viHsxoFxOrhnZQOhaLT' + sLineBreak +
    'RPrgaSojv9pooHQ6fJwplewt91tb1OchDIeZk9Sl1hqPAXB0167of43GDOw2vfnq' + sLineBreak +
    'Ust7RtiyJhQhSkz0qp4aH4P9l+dZJIWnpgjcyWkcz893br9gEuVnQgh13V/lcxOn' + sLineBreak +
    'JtpaCFuHNTU3PcFiuQW+cN0=' + sLineBreak +
    '-----END PRIVATE KEY-----' + sLineBreak;

implementation

end.
