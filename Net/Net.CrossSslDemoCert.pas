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
    'MIID2DCCAsCgAwIBAgITEfC1IBD5L+rXiDNM6pe5JB/SzzANBgkqhkiG9w0BAQsF' + sLineBreak +
    'ADBaMQswCQYDVQQGEwJDTjEQMA4GA1UECAwHQmVpSmluZzEQMA4GA1UEBwwHQmVp' + sLineBreak +
    'SmluZzENMAsGA1UECgwEREVNTzEYMBYGA1UEAwwPd3d3LnNzbGRlbW8uY29tMCAX' + sLineBreak +
    'DTIzMDkxNzE0MDYwOVoYDzIxMjMwODI0MTQwNjA5WjBaMQswCQYDVQQGEwJDTjEQ' + sLineBreak +
    'MA4GA1UECAwHQmVpSmluZzEQMA4GA1UEBwwHQmVpSmluZzENMAsGA1UECgwEREVN' + sLineBreak +
    'TzEYMBYGA1UEAwwPd3d3LnNzbGRlbW8uY29tMIIBIjANBgkqhkiG9w0BAQEFAAOC' + sLineBreak +
    'AQ8AMIIBCgKCAQEAtwwX7o1opUHECzuFfxAZ52zhQ21vWbHX2i/RpWFsUwhTLEF8' + sLineBreak +
    'ONse3Bcbe5dOTYxV0YgyXHm++E90sjTTTB291PCWSjRArJrzeKx/7at2wuiXNEIE' + sLineBreak +
    '+UkPj3p+TJXXweKDPdJw3mC8ZVulVJ6WjBwOg2QYk0HXVk31ijFusil6oW79KdfE' + sLineBreak +
    '2pwSJ0tZmudw0Pa/S5XFc1FKKNzaU8792AgIaBd8QUAptznq6uebrqwIrPOPCLXK' + sLineBreak +
    'YtQTBjYntnrRiVoYJpvAiHqJOP8/aZoBtOXcx4FOrITqS0lov1qooE4jgJsmYvdr' + sLineBreak +
    '1n7nh2OBbDJLtzE9t5pZ0rZKdOIwmIpQ1TSa0wIDAQABo4GUMIGRMB8GA1UdIwQY' + sLineBreak +
    'MBaAFJp3UTqnWncoNOw4ShBiaNjE7N8LMAkGA1UdEwQCMAAwHQYDVR0lBBYwFAYI' + sLineBreak +
    'KwYBBQUHAwEGCCsGAQUFBwMCMCUGA1UdEQQeMByCDSouc3NsZGVtby5jb22CC3Nz' + sLineBreak +
    'bGRlbW8uY29tMB0GA1UdDgQWBBTl9R4lNKdcQ6inw4GPdjZwBFG47TANBgkqhkiG' + sLineBreak +
    '9w0BAQsFAAOCAQEAT2Ff+sBcj/P7uouwgdBkmpq9uLXdgD7SvoBuUdvbrTBHNnFS' + sLineBreak +
    'aNVHEkpxWEA+0Bpy4g4EzKHbdSTRqB1sv0XTbf9j0P3Zw13E5TWEE3p3imT4nE0Z' + sLineBreak +
    'mCf3ZmUe8kJof9FcgJ3FNVh7vcNyPXrvqu3PeFbJPesnP0di1EfPBtsznyyqqnVN' + sLineBreak +
    'fOqJkJgxf2T0AB1Ue7N/sdTnHkOwcNzpLGvDHcQ4rDflQqjYlarwN1y1aWn+3+CN' + sLineBreak +
    'cA2BHr8u+bkjlNsWUa7nMVbravpaL5n2BCQzlNIgaGWbDA9bssT5P59pMpjd2wYI' + sLineBreak +
    'rUKXcJHrMWVzfppQ9Kk/mL5U66VL0WcnsSrAlw==' + sLineBreak +
    '-----END CERTIFICATE-----' + sLineBreak;

  SSL_SERVER_PKEY: string =
    '-----BEGIN PRIVATE KEY-----' + sLineBreak +
    'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC3DBfujWilQcQL' + sLineBreak +
    'O4V/EBnnbOFDbW9ZsdfaL9GlYWxTCFMsQXw42x7cFxt7l05NjFXRiDJceb74T3Sy' + sLineBreak +
    'NNNMHb3U8JZKNECsmvN4rH/tq3bC6Jc0QgT5SQ+Pen5MldfB4oM90nDeYLxlW6VU' + sLineBreak +
    'npaMHA6DZBiTQddWTfWKMW6yKXqhbv0p18TanBInS1ma53DQ9r9LlcVzUUoo3NpT' + sLineBreak +
    'zv3YCAhoF3xBQCm3Oerq55uurAis848Itcpi1BMGNie2etGJWhgmm8CIeok4/z9p' + sLineBreak +
    'mgG05dzHgU6shOpLSWi/WqigTiOAmyZi92vWfueHY4FsMku3MT23mlnStkp04jCY' + sLineBreak +
    'ilDVNJrTAgMBAAECggEABlFeihdLY1jPwWt+ghI2MqypYcBnNXtT7e30mHayXHNP' + sLineBreak +
    'G5nvBa9ac1JA2pUwWLDdTWwcAOEa3EsxxezY1im4oZ7kMQ94o/x9Js8dY0Clyrho' + sLineBreak +
    'b59PuKLy7IrXzSDm34RH71xSFPrVxdHR9Qe8Pn3BanuL9ZkyK4JpVSm7nl6cIvI4' + sLineBreak +
    'zDPC+nckB7R4fhG7tQJ/L+vC7YTN957t9AFuhcM9kiqKYacWjmjHck3ypmSal3YR' + sLineBreak +
    'BUmRDMNirGBOpWrarXHPqdRC7Tycfir+LJ6vWVbjgtd5BUqyL6ntI3RfL13XrMUt' + sLineBreak +
    'BsCTHXRoLzTCPDti2g7ToFgZ9CtrUEuiGBglIG4WsQKBgQDdmPvRpyr7VI9bZbHW' + sLineBreak +
    '11W8slsE4eVJ8Zdt3Hxisau9BOkTsg/gZK5CbO9hzCOcuy0JS/KdXa//zfejqo+r' + sLineBreak +
    'PnbxvGiKYgvkwfFq34KZz4zwC0UDJh8OSAJEVHkZjGOTbC5PkzdLKZSnVUCXohG9' + sLineBreak +
    'JuW6eMLR6sZPe/lJREmqObminQKBgQDTdv3+uBGDmd0+bf9NnJOiIHp8hMbTH9sW' + sLineBreak +
    'kwG9a2xwzVN3s+rGGObkk/50sme3T6K0cDCwt642GrU7pXB1QRlZKFdXeumUiFCQ' + sLineBreak +
    'c8/iHwoPK7bD2xWQmRuXsupQaK48fObdKExAllWUquZQqnszLoyCqQe1mQNHSLQe' + sLineBreak +
    '0LeSZbLALwKBgQCU1FrMxGmpw3FFAVgf4yBCS8e1z8Ifl5MMxjkEUC/4E4Q3JjBj' + sLineBreak +
    'lTs0gdWE6YZBjbUBuXCJIJNESyE3WyaC7MEWOmQ8DP3P9jIehV9BzpPp5KfFJaVW' + sLineBreak +
    'AicDnXh4IEIAkXfJGibY5GRivm9TaBZh4+4G/3RZaEUovSsAeky/d2WmQQKBgCCL' + sLineBreak +
    'QY+/+EIOnfQLrazeGgJriS48qPS5BFi3Cx+BttCtaNkVQV53WqF2/UQsaLXXdazb' + sLineBreak +
    'T0MDIbaF6bpiPapt+F62TKrT6brIN83jZOzh5gRrr9b4kpsMVSjFijYRxi7c8hK7' + sLineBreak +
    'LvEJseYNXyCu/ALmeQ1qwhr6j3ya/c14RagsKpRVAoGAD/syFdpzy0Z9+PksuAPq' + sLineBreak +
    'EbtCgTQvI1/5NBbR/K5UyQcNLElejnsq+u+V4XfxAana/UUlrsUKATxmUDAnwtl6' + sLineBreak +
    'QBFoycMk37edyscGLzPIXKcBtzEk9XldyMBORW8aDx3IXr3zwcnaAD8Yybk5yQyz' + sLineBreak +
    'S9661mnJTLVujbyMDz3L8Uk=' + sLineBreak +
    '-----END PRIVATE KEY-----' + sLineBreak;

implementation

end.
