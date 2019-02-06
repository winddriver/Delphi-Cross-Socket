{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossHttpUtils;

interface

uses
  System.SysUtils;

type
  THttpStatus = record
    Code: Integer;
    Text: string;
  end;

  TMimeValue = record
    Key: string;
    Value: string;
  end;

const
  {$REGION 'STATUS CODE CONST'}
  STATUS_CODES: array [0..56] of THttpStatus = (
    (Code: 100; Text: 'Continue'),
    (Code: 101; Text: 'Switching Protocols'),
    (Code: 102; Text: 'Processing'),                  // RFC 2518, obsoleted by RFC 4918
    (Code: 200; Text: 'OK'),
    (Code: 201; Text: 'Created'),
    (Code: 202; Text: 'Accepted'),
    (Code: 203; Text: 'Non-Authoritative Information'),
    (Code: 204; Text: 'No Content'),
    (Code: 205; Text: 'Reset Content'),
    (Code: 206; Text: 'Partial Content'),
    (Code: 207; Text: 'Multi-Status'),                // RFC 4918
    (Code: 300; Text: 'Multiple Choices'),
    (Code: 301; Text: 'Moved Permanently'),
    (Code: 302; Text: 'Moved Temporarily'),
    (Code: 303; Text: 'See Other'),
    (Code: 304; Text: 'Not Modified'),
    (Code: 305; Text: 'Use Proxy'),
    (Code: 307; Text: 'Temporary Redirect'),
    (Code: 308; Text: 'Permanent Redirect'),          // RFC 7238
    (Code: 400; Text: 'Bad Request'),
    (Code: 401; Text: 'Unauthorized'),
    (Code: 402; Text: 'Payment Required'),
    (Code: 403; Text: 'Forbidden'),
    (Code: 404; Text: 'Not Found'),
    (Code: 405; Text: 'Method Not Allowed'),
    (Code: 406; Text: 'Not Acceptable'),
    (Code: 407; Text: 'Proxy Authentication Required'),
    (Code: 408; Text: 'Request Time-out'),
    (Code: 409; Text: 'Conflict'),
    (Code: 410; Text: 'Gone'),
    (Code: 411; Text: 'Length Required'),
    (Code: 412; Text: 'Precondition Failed'),
    (Code: 413; Text: 'Request Entity Too Large'),
    (Code: 414; Text: 'Request-URI Too Large'),
    (Code: 415; Text: 'Unsupported Media Type'),
    (Code: 416; Text: 'Requested Range Not Satisfiable'),
    (Code: 417; Text: 'Expectation Failed'),
    (Code: 418; Text: 'I''m a teapot'),               // RFC 2324
    (Code: 422; Text: 'Unprocessable Entity'),        // RFC 4918
    (Code: 423; Text: 'Locked'),                      // RFC 4918
    (Code: 424; Text: 'Failed Dependency'),           // RFC 4918
    (Code: 425; Text: 'Unordered Collection'),        // RFC 4918
    (Code: 426; Text: 'Upgrade Required'),            // RFC 2817
    (Code: 428; Text: 'Precondition Required'),       // RFC 6585
    (Code: 429; Text: 'Too Many Requests'),           // RFC 6585
    (Code: 431; Text: 'Request Header Fields Too Large'), // RFC 6585
    (Code: 500; Text: 'Internal Server Error'),
    (Code: 501; Text: 'Not Implemented'),
    (Code: 502; Text: 'Bad Gateway'),
    (Code: 503; Text: 'Service Unavailable'),
    (Code: 504; Text: 'Gateway Time-out'),
    (Code: 505; Text: 'HTTP Version Not Supported'),
    (Code: 506; Text: 'Variant Also Negotiates'),     // RFC 2295
    (Code: 507; Text: 'Insufficient Storage'),        // RFC 4918
    (Code: 509; Text: 'Bandwidth Limit Exceeded'),
    (Code: 510; Text: 'Not Extended'),                // RFC 2774
    (Code: 511; Text: 'Network Authentication Required') // RFC 6585
  );
  {$ENDREGION}

  {$REGION 'MIME CONST'}
  MIME_TYPES: array[0..987] of TMimeValue = (
    (Key: 'ez'; Value: 'application/andrew-inset'), // do not localize
    (Key: 'aw'; Value: 'application/applixware'), // do not localize
    (Key: 'atom'; Value: 'application/atom+xml'), // do not localize
    (Key: 'atomcat'; Value: 'application/atomcat+xml'), // do not localize
    (Key: 'atomsvc'; Value: 'application/atomsvc+xml'), // do not localize
    (Key: 'ccxml'; Value: 'application/ccxml+xml'), // do not localize
    (Key: 'cdmia'; Value: 'application/cdmi-capability'), // do not localize
    (Key: 'cdmic'; Value: 'application/cdmi-container'), // do not localize
    (Key: 'cdmid'; Value: 'application/cdmi-domain'), // do not localize
    (Key: 'cdmio'; Value: 'application/cdmi-object'), // do not localize
    (Key: 'cdmiq'; Value: 'application/cdmi-queue'), // do not localize
    (Key: 'cu'; Value: 'application/cu-seeme'), // do not localize
    (Key: 'davmount'; Value: 'application/davmount+xml'), // do not localize
    (Key: 'dbk'; Value: 'application/docbook+xml'), // do not localize
    (Key: 'dssc'; Value: 'application/dssc+der'), // do not localize
    (Key: 'xdssc'; Value: 'application/dssc+xml'), // do not localize
    (Key: 'ecma'; Value: 'application/ecmascript'), // do not localize
    (Key: 'emma'; Value: 'application/emma+xml'), // do not localize
    (Key: 'epub'; Value: 'application/epub+zip'), // do not localize
    (Key: 'exi'; Value: 'application/exi'), // do not localize
    (Key: 'pfr'; Value: 'application/font-tdpfr'), // do not localize
    (Key: 'gml'; Value: 'application/gml+xml'), // do not localize
    (Key: 'gpx'; Value: 'application/gpx+xml'), // do not localize
    (Key: 'gxf'; Value: 'application/gxf'), // do not localize
    (Key: 'stk'; Value: 'application/hyperstudio'), // do not localize
    (Key: 'ink'; Value: 'application/inkml+xml'), // do not localize
    (Key: 'inkml'; Value: 'application/inkml+xml'), // do not localize
    (Key: 'ipfix'; Value: 'application/ipfix'), // do not localize
    (Key: 'jar'; Value: 'application/java-archive'), // do not localize
    (Key: 'ser'; Value: 'application/java-serialized-object'), // do not localize
    (Key: 'class'; Value: 'application/java-vm'), // do not localize
    (Key: 'js'; Value: 'application/javascript'), // do not localize
    (Key: 'json'; Value: 'application/json'), // do not localize
    (Key: 'jsonml'; Value: 'application/jsonml+json'), // do not localize
    (Key: 'lostxml'; Value: 'application/lost+xml'), // do not localize
    (Key: 'hqx'; Value: 'application/mac-binhex40'), // do not localize
    (Key: 'cpt'; Value: 'application/mac-compactpro'), // do not localize
    (Key: 'mads'; Value: 'application/mads+xml'), // do not localize
    (Key: 'mrc'; Value: 'application/marc'), // do not localize
    (Key: 'mrcx'; Value: 'application/marcxml+xml'), // do not localize
    (Key: 'ma'; Value: 'application/mathematica'), // do not localize
    (Key: 'nb'; Value: 'application/mathematica'), // do not localize
    (Key: 'mb'; Value: 'application/mathematica'), // do not localize
    (Key: 'mathml'; Value: 'application/mathml+xml'), // do not localize
    (Key: 'mbox'; Value: 'application/mbox'), // do not localize
    (Key: 'mscml'; Value: 'application/mediaservercontrol+xml'), // do not localize
    (Key: 'metalink'; Value: 'application/metalink+xml'), // do not localize
    (Key: 'meta4'; Value: 'application/metalink4+xml'), // do not localize
    (Key: 'mets'; Value: 'application/mets+xml'), // do not localize
    (Key: 'mods'; Value: 'application/mods+xml'), // do not localize
    (Key: 'm21'; Value: 'application/mp21'), // do not localize
    (Key: 'mp21'; Value: 'application/mp21'), // do not localize
    (Key: 'mp4s'; Value: 'application/mp4'), // do not localize
    (Key: 'doc'; Value: 'application/msword'), // do not localize
    (Key: 'dot'; Value: 'application/msword'), // do not localize
    (Key: 'mxf'; Value: 'application/mxf'), // do not localize
    (Key: 'bin'; Value: 'application/octet-stream'), // do not localize
    (Key: 'bpk'; Value: 'application/octet-stream'), // do not localize
    (Key: 'class'; Value: 'application/octet-stream'), // do not localize
    (Key: 'deploy'; Value: 'application/octet-stream'), // do not localize
    (Key: 'dist'; Value: 'application/octet-stream'), // do not localize
    (Key: 'distz'; Value: 'application/octet-stream'), // do not localize
    (Key: 'dmg'; Value: 'application/octet-stream'), // do not localize
    (Key: 'dms'; Value: 'application/octet-stream'), // do not localize
    (Key: 'dump'; Value: 'application/octet-stream'), // do not localize
    (Key: 'elc'; Value: 'application/octet-stream'), // do not localize
    (Key: 'iso'; Value: 'application/octet-stream'), // do not localize
    (Key: 'lha'; Value: 'application/octet-stream'), // do not localize
    (Key: 'lrf'; Value: 'application/octet-stream'), // do not localize
    (Key: 'lzh'; Value: 'application/octet-stream'), // do not localize
    (Key: 'mar'; Value: 'application/octet-stream'), // do not localize
    (Key: 'pkg'; Value: 'application/octet-stream'), // do not localize
    (Key: 'so'; Value: 'application/octet-stream'), // do not localize
    (Key: 'oda'; Value: 'application/oda'), // do not localize
    (Key: 'opf'; Value: 'application/oebps-package+xml'), // do not localize
    (Key: 'ogx'; Value: 'application/ogg'), // do not localize
    (Key: 'omdoc'; Value: 'application/omdoc+xml'), // do not localize
    (Key: 'onetoc'; Value: 'application/onenote'), // do not localize
    (Key: 'onetoc2'; Value: 'application/onenote'), // do not localize
    (Key: 'onetmp'; Value: 'application/onenote'), // do not localize
    (Key: 'onepkg'; Value: 'application/onenote'), // do not localize
    (Key: 'oxps'; Value: 'application/oxps'), // do not localize
    (Key: 'xer'; Value: 'application/patch-ops-error+xml'), // do not localize
    (Key: 'pdf'; Value: 'application/pdf'), // do not localize
    (Key: 'pgp'; Value: 'application/pgp-encrypted'), // do not localize
    (Key: 'asc'; Value: 'application/pgp-signature'), // do not localize
    (Key: 'sig'; Value: 'application/pgp-signature'), // do not localize
    (Key: 'prf'; Value: 'application/pics-rules'), // do not localize
    (Key: 'p10'; Value: 'application/pkcs10'), // do not localize
    (Key: 'p7m'; Value: 'application/pkcs7-mime'), // do not localize
    (Key: 'p7c'; Value: 'application/pkcs7-mime'), // do not localize
    (Key: 'p7s'; Value: 'application/pkcs7-signature'), // do not localize
    (Key: 'p8'; Value: 'application/pkcs8'), // do not localize
    (Key: 'ac'; Value: 'application/pkix-attr-cert'), // do not localize
    (Key: 'cer'; Value: 'application/pkix-cert'), // do not localize
    (Key: 'crl'; Value: 'application/pkix-crl'), // do not localize
    (Key: 'pkipath'; Value: 'application/pkix-pkipath'), // do not localize
    (Key: 'pki'; Value: 'application/pkixcmp'), // do not localize
    (Key: 'pls'; Value: 'application/pls+xml'), // do not localize
    (Key: 'ai'; Value: 'application/postscript'), // do not localize
    (Key: 'eps'; Value: 'application/postscript'), // do not localize
    (Key: 'ps'; Value: 'application/postscript'), // do not localize
    (Key: 'cww'; Value: 'application/prs.cww'), // do not localize
    (Key: 'pskcxml'; Value: 'application/pskc+xml'), // do not localize
    (Key: 'rdf'; Value: 'application/rdf+xml'), // do not localize
    (Key: 'rif'; Value: 'application/reginfo+xml'), // do not localize
    (Key: 'rnc'; Value: 'application/relax-ng-compact-syntax'), // do not localize
    (Key: 'rl'; Value: 'application/resource-lists+xml'), // do not localize
    (Key: 'rld'; Value: 'application/resource-lists-diff+xml'), // do not localize
    (Key: 'rs'; Value: 'application/rls-services+xml'), // do not localize
    (Key: 'gbr'; Value: 'application/rpki-ghostbusters'), // do not localize
    (Key: 'mft'; Value: 'application/rpki-manifest'), // do not localize
    (Key: 'roa'; Value: 'application/rpki-roa'), // do not localize
    (Key: 'rsd'; Value: 'application/rsd+xml'), // do not localize
    (Key: 'rss'; Value: 'application/rss+xml'), // do not localize
    (Key: 'rtf'; Value: 'application/rtf'), // do not localize
    (Key: 'sbml'; Value: 'application/sbml+xml'), // do not localize
    (Key: 'scq'; Value: 'application/scvp-cv-request'), // do not localize
    (Key: 'scs'; Value: 'application/scvp-cv-response'), // do not localize
    (Key: 'spq'; Value: 'application/scvp-vp-request'), // do not localize
    (Key: 'spp'; Value: 'application/scvp-vp-response'), // do not localize
    (Key: 'sdp'; Value: 'application/sdp'), // do not localize
    (Key: 'setpay'; Value: 'application/set-payment-initiation'), // do not localize
    (Key: 'setreg'; Value: 'application/set-registration-initiation'), // do not localize
    (Key: 'shf'; Value: 'application/shf+xml'), // do not localize
    (Key: 'smi'; Value: 'application/smil+xml'), // do not localize
    (Key: 'smil'; Value: 'application/smil+xml'), // do not localize
    (Key: 'rq'; Value: 'application/sparql-query'), // do not localize
    (Key: 'srx'; Value: 'application/sparql-results+xml'), // do not localize
    (Key: 'gram'; Value: 'application/srgs'), // do not localize
    (Key: 'grxml'; Value: 'application/srgs+xml'), // do not localize
    (Key: 'sru'; Value: 'application/sru+xml'), // do not localize
    (Key: 'ssdl'; Value: 'application/ssdl+xml'), // do not localize
    (Key: 'ssml'; Value: 'application/ssml+xml'), // do not localize
    (Key: 'tei'; Value: 'application/tei+xml'), // do not localize
    (Key: 'teicorpus'; Value: 'application/tei+xml'), // do not localize
    (Key: 'tfi'; Value: 'application/thraud+xml'), // do not localize
    (Key: 'tsd'; Value: 'application/timestamped-data'), // do not localize
    (Key: 'plb'; Value: 'application/vnd.3gpp.pic-bw-large'), // do not localize
    (Key: 'psb'; Value: 'application/vnd.3gpp.pic-bw-small'), // do not localize
    (Key: 'pvb'; Value: 'application/vnd.3gpp.pic-bw-var'), // do not localize
    (Key: 'tcap'; Value: 'application/vnd.3gpp2.tcap'), // do not localize
    (Key: 'pwn'; Value: 'application/vnd.3m.post-it-notes'), // do not localize
    (Key: 'aso'; Value: 'application/vnd.accpac.simply.aso'), // do not localize
    (Key: 'imp'; Value: 'application/vnd.accpac.simply.imp'), // do not localize
    (Key: 'acu'; Value: 'application/vnd.acucobol'), // do not localize
    (Key: 'atc'; Value: 'application/vnd.acucorp'), // do not localize
    (Key: 'acutc'; Value: 'application/vnd.acucorp'), // do not localize
    (Key: 'air'; Value: 'application/vnd.adobe.air-application-installer-package+zip'), // do not localize
    (Key: 'fcdt'; Value: 'application/vnd.adobe.formscentral.fcdt'), // do not localize
    (Key: 'fxp'; Value: 'application/vnd.adobe.fxp'), // do not localize
    (Key: 'fxpl'; Value: 'application/vnd.adobe.fxp'), // do not localize
    (Key: 'xdp'; Value: 'application/vnd.adobe.xdp+xml'), // do not localize
    (Key: 'xfdf'; Value: 'application/vnd.adobe.xfdf'), // do not localize
    (Key: 'ahead'; Value: 'application/vnd.ahead.space'), // do not localize
    (Key: 'azf'; Value: 'application/vnd.airzip.filesecure.azf'), // do not localize
    (Key: 'azs'; Value: 'application/vnd.airzip.filesecure.azs'), // do not localize
    (Key: 'azw'; Value: 'application/vnd.amazon.ebook'), // do not localize
    (Key: 'acc'; Value: 'application/vnd.americandynamics.acc'), // do not localize
    (Key: 'ami'; Value: 'application/vnd.amiga.ami'), // do not localize
    (Key: 'apk'; Value: 'application/vnd.android.package-archive'), // do not localize
    (Key: 'cii'; Value: 'application/vnd.anser-web-certificate-issue-initiation'), // do not localize
    (Key: 'fti'; Value: 'application/vnd.anser-web-funds-transfer-initiation'), // do not localize
    (Key: 'atx'; Value: 'application/vnd.antix.game-component'), // do not localize
    (Key: 'mpkg'; Value: 'application/vnd.apple.installer+xml'), // do not localize
    (Key: 'm3u8'; Value: 'application/vnd.apple.mpegurl'), // do not localize
    (Key: 'swi'; Value: 'application/vnd.aristanetworks.swi'), // do not localize
    (Key: 'iota'; Value: 'application/vnd.astraea-software.iota'), // do not localize
    (Key: 'aep'; Value: 'application/vnd.audiograph'), // do not localize
    (Key: 'mpm'; Value: 'application/vnd.blueice.multipass'), // do not localize
    (Key: 'bmi'; Value: 'application/vnd.bmi'), // do not localize
    (Key: 'rep'; Value: 'application/vnd.businessobjects'), // do not localize
    (Key: 'cdxml'; Value: 'application/vnd.chemdraw+xml'), // do not localize
    (Key: 'mmd'; Value: 'application/vnd.chipnuts.karaoke-mmd'), // do not localize
    (Key: 'cdy'; Value: 'application/vnd.cinderella'), // do not localize
    (Key: 'cla'; Value: 'application/vnd.claymore'), // do not localize
    (Key: 'rp9'; Value: 'application/vnd.cloanto.rp9'), // do not localize
    (Key: 'c4g'; Value: 'application/vnd.clonk.c4group'), // do not localize
    (Key: 'c4d'; Value: 'application/vnd.clonk.c4group'), // do not localize
    (Key: 'c4f'; Value: 'application/vnd.clonk.c4group'), // do not localize
    (Key: 'c4p'; Value: 'application/vnd.clonk.c4group'), // do not localize
    (Key: 'c4u'; Value: 'application/vnd.clonk.c4group'), // do not localize
    (Key: 'c11amc'; Value: 'application/vnd.cluetrust.cartomobile-config'), // do not localize
    (Key: 'c11amz'; Value: 'application/vnd.cluetrust.cartomobile-config-pkg'), // do not localize
    (Key: 'csp'; Value: 'application/vnd.commonspace'), // do not localize
    (Key: 'cdbcmsg'; Value: 'application/vnd.contact.cmsg'), // do not localize
    (Key: 'cmc'; Value: 'application/vnd.cosmocaller'), // do not localize
    (Key: 'clkx'; Value: 'application/vnd.crick.clicker'), // do not localize
    (Key: 'clkk'; Value: 'application/vnd.crick.clicker.keyboard'), // do not localize
    (Key: 'clkp'; Value: 'application/vnd.crick.clicker.palette'), // do not localize
    (Key: 'clkt'; Value: 'application/vnd.crick.clicker.template'), // do not localize
    (Key: 'clkw'; Value: 'application/vnd.crick.clicker.wordbank'), // do not localize
    (Key: 'wbs'; Value: 'application/vnd.criticaltools.wbs+xml'), // do not localize
    (Key: 'pml'; Value: 'application/vnd.ctc-posml'), // do not localize
    (Key: 'ppd'; Value: 'application/vnd.cups-ppd'), // do not localize
    (Key: 'car'; Value: 'application/vnd.curl.car'), // do not localize
    (Key: 'pcurl'; Value: 'application/vnd.curl.pcurl'), // do not localize
    (Key: 'dart'; Value: 'application/vnd.dart'), // do not localize
    (Key: 'rdz'; Value: 'application/vnd.data-vision.rdz'), // do not localize
    (Key: 'uvf'; Value: 'application/vnd.dece.data'), // do not localize
    (Key: 'uvvf'; Value: 'application/vnd.dece.data'), // do not localize
    (Key: 'uvd'; Value: 'application/vnd.dece.data'), // do not localize
    (Key: 'uvvd'; Value: 'application/vnd.dece.data'), // do not localize
    (Key: 'uvt'; Value: 'application/vnd.dece.ttml+xml'), // do not localize
    (Key: 'uvvt'; Value: 'application/vnd.dece.ttml+xml'), // do not localize
    (Key: 'uvx'; Value: 'application/vnd.dece.unspecified'), // do not localize
    (Key: 'uvvx'; Value: 'application/vnd.dece.unspecified'), // do not localize
    (Key: 'uvz'; Value: 'application/vnd.dece.zip'), // do not localize
    (Key: 'uvvz'; Value: 'application/vnd.dece.zip'), // do not localize
    (Key: 'fe_launch'; Value: 'application/vnd.denovo.fcselayout-link'), // do not localize
    (Key: 'dna'; Value: 'application/vnd.dna'), // do not localize
    (Key: 'mlp'; Value: 'application/vnd.dolby.mlp'), // do not localize
    (Key: 'dpg'; Value: 'application/vnd.dpgraph'), // do not localize
    (Key: 'dfac'; Value: 'application/vnd.dreamfactory'), // do not localize
    (Key: 'kpxx'; Value: 'application/vnd.ds-keypoint'), // do not localize
    (Key: 'ait'; Value: 'application/vnd.dvb.ait'), // do not localize
    (Key: 'svc'; Value: 'application/vnd.dvb.service'), // do not localize
    (Key: 'geo'; Value: 'application/vnd.dynageo'), // do not localize
    (Key: 'mag'; Value: 'application/vnd.ecowin.chart'), // do not localize
    (Key: 'nml'; Value: 'application/vnd.enliven'), // do not localize
    (Key: 'esf'; Value: 'application/vnd.epson.esf'), // do not localize
    (Key: 'msf'; Value: 'application/vnd.epson.msf'), // do not localize
    (Key: 'qam'; Value: 'application/vnd.epson.quickanime'), // do not localize
    (Key: 'slt'; Value: 'application/vnd.epson.salt'), // do not localize
    (Key: 'ssf'; Value: 'application/vnd.epson.ssf'), // do not localize
    (Key: 'es3'; Value: 'application/vnd.eszigno3+xml'), // do not localize
    (Key: 'et3'; Value: 'application/vnd.eszigno3+xml'), // do not localize
    (Key: 'ez2'; Value: 'application/vnd.ezpix-album'), // do not localize
    (Key: 'ez3'; Value: 'application/vnd.ezpix-package'), // do not localize
    (Key: 'fdf'; Value: 'application/vnd.fdf'), // do not localize
    (Key: 'mseed'; Value: 'application/vnd.fdsn.mseed'), // do not localize
    (Key: 'seed'; Value: 'application/vnd.fdsn.seed'), // do not localize
    (Key: 'dataless'; Value: 'application/vnd.fdsn.seed'), // do not localize
    (Key: 'gph'; Value: 'application/vnd.flographit'), // do not localize
    (Key: 'ftc'; Value: 'application/vnd.fluxtime.clip'), // do not localize
    (Key: 'fm'; Value: 'application/vnd.framemaker'), // do not localize
    (Key: 'frame'; Value: 'application/vnd.framemaker'), // do not localize
    (Key: 'maker'; Value: 'application/vnd.framemaker'), // do not localize
    (Key: 'book'; Value: 'application/vnd.framemaker'), // do not localize
    (Key: 'fnc'; Value: 'application/vnd.frogans.fnc'), // do not localize
    (Key: 'ltf'; Value: 'application/vnd.frogans.ltf'), // do not localize
    (Key: 'fsc'; Value: 'application/vnd.fsc.weblaunch'), // do not localize
    (Key: 'oas'; Value: 'application/vnd.fujitsu.oasys'), // do not localize
    (Key: 'oa2'; Value: 'application/vnd.fujitsu.oasys2'), // do not localize
    (Key: 'oa3'; Value: 'application/vnd.fujitsu.oasys3'), // do not localize
    (Key: 'fg5'; Value: 'application/vnd.fujitsu.oasysgp'), // do not localize
    (Key: 'bh2'; Value: 'application/vnd.fujitsu.oasysprs'), // do not localize
    (Key: 'ddd'; Value: 'application/vnd.fujixerox.ddd'), // do not localize
    (Key: 'xdw'; Value: 'application/vnd.fujixerox.docuworks'), // do not localize
    (Key: 'xbd'; Value: 'application/vnd.fujixerox.docuworks.binder'), // do not localize
    (Key: 'fzs'; Value: 'application/vnd.fuzzysheet'), // do not localize
    (Key: 'txd'; Value: 'application/vnd.genomatix.tuxedo'), // do not localize
    (Key: 'ggb'; Value: 'application/vnd.geogebra.file'), // do not localize
    (Key: 'ggt'; Value: 'application/vnd.geogebra.tool'), // do not localize
    (Key: 'gex'; Value: 'application/vnd.geometry-explorer'), // do not localize
    (Key: 'gre'; Value: 'application/vnd.geometry-explorer'), // do not localize
    (Key: 'gxt'; Value: 'application/vnd.geonext'), // do not localize
    (Key: 'g2w'; Value: 'application/vnd.geoplan'), // do not localize
    (Key: 'g3w'; Value: 'application/vnd.geospace'), // do not localize
    (Key: 'gmx'; Value: 'application/vnd.gmx'), // do not localize
    (Key: 'kml'; Value: 'application/vnd.google-earth.kml+xml'), // do not localize
    (Key: 'kmz'; Value: 'application/vnd.google-earth.kmz'), // do not localize
    (Key: 'gqf'; Value: 'application/vnd.grafeq'), // do not localize
    (Key: 'gqs'; Value: 'application/vnd.grafeq'), // do not localize
    (Key: 'gac'; Value: 'application/vnd.groove-account'), // do not localize
    (Key: 'ghf'; Value: 'application/vnd.groove-help'), // do not localize
    (Key: 'gim'; Value: 'application/vnd.groove-identity-message'), // do not localize
    (Key: 'grv'; Value: 'application/vnd.groove-injector'), // do not localize
    (Key: 'gtm'; Value: 'application/vnd.groove-tool-message'), // do not localize
    (Key: 'tpl'; Value: 'application/vnd.groove-tool-template'), // do not localize
    (Key: 'vcg'; Value: 'application/vnd.groove-vcard'), // do not localize
    (Key: 'hal'; Value: 'application/vnd.hal+xml'), // do not localize
    (Key: 'zmm'; Value: 'application/vnd.handheld-entertainment+xml'), // do not localize
    (Key: 'hbci'; Value: 'application/vnd.hbci'), // do not localize
    (Key: 'les'; Value: 'application/vnd.hhe.lesson-player'), // do not localize
    (Key: 'hpgl'; Value: 'application/vnd.hp-hpgl'), // do not localize
    (Key: 'hpid'; Value: 'application/vnd.hp-hpid'), // do not localize
    (Key: 'hps'; Value: 'application/vnd.hp-hps'), // do not localize
    (Key: 'jlt'; Value: 'application/vnd.hp-jlyt'), // do not localize
    (Key: 'pcl'; Value: 'application/vnd.hp-pcl'), // do not localize
    (Key: 'pclxl'; Value: 'application/vnd.hp-pclxl'), // do not localize
    (Key: 'sfd-hdstx'; Value: 'application/vnd.hydrostatix.sof-data'), // do not localize
    (Key: 'mpy'; Value: 'application/vnd.ibm.minipay'), // do not localize
    (Key: 'afp'; Value: 'application/vnd.ibm.modcap'), // do not localize
    (Key: 'listafp'; Value: 'application/vnd.ibm.modcap'), // do not localize
    (Key: 'list3820'; Value: 'application/vnd.ibm.modcap'), // do not localize
    (Key: 'irm'; Value: 'application/vnd.ibm.rights-management'), // do not localize
    (Key: 'sc'; Value: 'application/vnd.ibm.secure-container'), // do not localize
    (Key: 'icc'; Value: 'application/vnd.iccprofile'), // do not localize
    (Key: 'icm'; Value: 'application/vnd.iccprofile'), // do not localize
    (Key: 'igl'; Value: 'application/vnd.igloader'), // do not localize
    (Key: 'ivp'; Value: 'application/vnd.immervision-ivp'), // do not localize
    (Key: 'ivu'; Value: 'application/vnd.immervision-ivu'), // do not localize
    (Key: 'igm'; Value: 'application/vnd.insors.igm'), // do not localize
    (Key: 'xpw'; Value: 'application/vnd.intercon.formnet'), // do not localize
    (Key: 'xpx'; Value: 'application/vnd.intercon.formnet'), // do not localize
    (Key: 'i2g'; Value: 'application/vnd.intergeo'), // do not localize
    (Key: 'qbo'; Value: 'application/vnd.intu.qbo'), // do not localize
    (Key: 'qfx'; Value: 'application/vnd.intu.qfx'), // do not localize
    (Key: 'rcprofile'; Value: 'application/vnd.ipunplugged.rcprofile'), // do not localize
    (Key: 'irp'; Value: 'application/vnd.irepository.package+xml'), // do not localize
    (Key: 'xpr'; Value: 'application/vnd.is-xpr'), // do not localize
    (Key: 'fcs'; Value: 'application/vnd.isac.fcs'), // do not localize
    (Key: 'jam'; Value: 'application/vnd.jam'), // do not localize
    (Key: 'rms'; Value: 'application/vnd.jcp.javame.midlet-rms'), // do not localize
    (Key: 'jisp'; Value: 'application/vnd.jisp'), // do not localize
    (Key: 'joda'; Value: 'application/vnd.joost.joda-archive'), // do not localize
    (Key: 'ktz'; Value: 'application/vnd.kahootz'), // do not localize
    (Key: 'ktr'; Value: 'application/vnd.kahootz'), // do not localize
    (Key: 'karbon'; Value: 'application/vnd.kde.karbon'), // do not localize
    (Key: 'chrt'; Value: 'application/vnd.kde.kchart'), // do not localize
    (Key: 'kfo'; Value: 'application/vnd.kde.kformula'), // do not localize
    (Key: 'flw'; Value: 'application/vnd.kde.kivio'), // do not localize
    (Key: 'kon'; Value: 'application/vnd.kde.kontour'), // do not localize
    (Key: 'kpr'; Value: 'application/vnd.kde.kpresenter'), // do not localize
    (Key: 'kpt'; Value: 'application/vnd.kde.kpresenter'), // do not localize
    (Key: 'ksp'; Value: 'application/vnd.kde.kspread'), // do not localize
    (Key: 'kwd'; Value: 'application/vnd.kde.kword'), // do not localize
    (Key: 'kwt'; Value: 'application/vnd.kde.kword'), // do not localize
    (Key: 'htke'; Value: 'application/vnd.kenameaapp'), // do not localize
    (Key: 'kia'; Value: 'application/vnd.kidspiration'), // do not localize
    (Key: 'kne'; Value: 'application/vnd.kinar'), // do not localize
    (Key: 'knp'; Value: 'application/vnd.kinar'), // do not localize
    (Key: 'skp'; Value: 'application/vnd.koan'), // do not localize
    (Key: 'skd'; Value: 'application/vnd.koan'), // do not localize
    (Key: 'skt'; Value: 'application/vnd.koan'), // do not localize
    (Key: 'skm'; Value: 'application/vnd.koan'), // do not localize
    (Key: 'sse'; Value: 'application/vnd.kodak-descriptor'), // do not localize
    (Key: 'lasxml'; Value: 'application/vnd.las.las+xml'), // do not localize
    (Key: 'lbd'; Value: 'application/vnd.llamagraphics.life-balance.desktop'), // do not localize
    (Key: 'lbe'; Value: 'application/vnd.llamagraphics.life-balance.exchange+xml'), // do not localize
    (Key: '123'; Value: 'application/vnd.lotus-1-2-3'), // do not localize
    (Key: 'apr'; Value: 'application/vnd.lotus-approach'), // do not localize
    (Key: 'pre'; Value: 'application/vnd.lotus-freelance'), // do not localize
    (Key: 'nsf'; Value: 'application/vnd.lotus-notes'), // do not localize
    (Key: 'org'; Value: 'application/vnd.lotus-organizer'), // do not localize
    (Key: 'scm'; Value: 'application/vnd.lotus-screencam'), // do not localize
    (Key: 'lwp'; Value: 'application/vnd.lotus-wordpro'), // do not localize
    (Key: 'portpkg'; Value: 'application/vnd.macports.portpkg'), // do not localize
    (Key: 'mcd'; Value: 'application/vnd.mcd'), // do not localize
    (Key: 'mc1'; Value: 'application/vnd.medcalcdata'), // do not localize
    (Key: 'cdkey'; Value: 'application/vnd.mediastation.cdkey'), // do not localize
    (Key: 'mwf'; Value: 'application/vnd.mfer'), // do not localize
    (Key: 'mfm'; Value: 'application/vnd.mfmp'), // do not localize
    (Key: 'flo'; Value: 'application/vnd.micrografx.flo'), // do not localize
    (Key: 'igx'; Value: 'application/vnd.micrografx.igx'), // do not localize
    (Key: 'mif'; Value: 'application/vnd.mif'), // do not localize
    (Key: 'daf'; Value: 'application/vnd.mobius.daf'), // do not localize
    (Key: 'dis'; Value: 'application/vnd.mobius.dis'), // do not localize
    (Key: 'mbk'; Value: 'application/vnd.mobius.mbk'), // do not localize
    (Key: 'mqy'; Value: 'application/vnd.mobius.mqy'), // do not localize
    (Key: 'msl'; Value: 'application/vnd.mobius.msl'), // do not localize
    (Key: 'plc'; Value: 'application/vnd.mobius.plc'), // do not localize
    (Key: 'txf'; Value: 'application/vnd.mobius.txf'), // do not localize
    (Key: 'mpn'; Value: 'application/vnd.mophun.application'), // do not localize
    (Key: 'mpc'; Value: 'application/vnd.mophun.certificate'), // do not localize
    (Key: 'xul'; Value: 'application/vnd.mozilla.xul+xml'), // do not localize
    (Key: 'cil'; Value: 'application/vnd.ms-artgalry'), // do not localize
    (Key: 'cab'; Value: 'application/vnd.ms-cab-compressed'), // do not localize
    (Key: 'xls'; Value: 'application/vnd.ms-excel'), // do not localize
    (Key: 'xlm'; Value: 'application/vnd.ms-excel'), // do not localize
    (Key: 'xla'; Value: 'application/vnd.ms-excel'), // do not localize
    (Key: 'xlc'; Value: 'application/vnd.ms-excel'), // do not localize
    (Key: 'xlt'; Value: 'application/vnd.ms-excel'), // do not localize
    (Key: 'xlw'; Value: 'application/vnd.ms-excel'), // do not localize
    (Key: 'xlam'; Value: 'application/vnd.ms-excel.addin.macroenabled.12'), // do not localize
    (Key: 'xlsb'; Value: 'application/vnd.ms-excel.sheet.binary.macroenabled.12'), // do not localize
    (Key: 'xlsm'; Value: 'application/vnd.ms-excel.sheet.macroenabled.12'), // do not localize
    (Key: 'xltm'; Value: 'application/vnd.ms-excel.template.macroenabled.12'), // do not localize
    (Key: 'eot'; Value: 'application/vnd.ms-fontobject'), // do not localize
    (Key: 'chm'; Value: 'application/vnd.ms-htmlhelp'), // do not localize
    (Key: 'ims'; Value: 'application/vnd.ms-ims'), // do not localize
    (Key: 'lrm'; Value: 'application/vnd.ms-lrm'), // do not localize
    (Key: 'thmx'; Value: 'application/vnd.ms-officetheme'), // do not localize
    (Key: 'cat'; Value: 'application/vnd.ms-pki.seccat'), // do not localize
    (Key: 'stl'; Value: 'application/vnd.ms-pki.stl'), // do not localize
    (Key: 'ppt'; Value: 'application/vnd.ms-powerpoint'), // do not localize
    (Key: 'pps'; Value: 'application/vnd.ms-powerpoint'), // do not localize
    (Key: 'pot'; Value: 'application/vnd.ms-powerpoint'), // do not localize
    (Key: 'ppam'; Value: 'application/vnd.ms-powerpoint.addin.macroenabled.12'), // do not localize
    (Key: 'pptm'; Value: 'application/vnd.ms-powerpoint.presentation.macroenabled.12'), // do not localize
    (Key: 'sldm'; Value: 'application/vnd.ms-powerpoint.slide.macroenabled.12'), // do not localize
    (Key: 'ppsm'; Value: 'application/vnd.ms-powerpoint.slideshow.macroenabled.12'), // do not localize
    (Key: 'potm'; Value: 'application/vnd.ms-powerpoint.template.macroenabled.12'), // do not localize
    (Key: 'mpp'; Value: 'application/vnd.ms-project'), // do not localize
    (Key: 'mpt'; Value: 'application/vnd.ms-project'), // do not localize
    (Key: 'docm'; Value: 'application/vnd.ms-word.document.macroenabled.12'), // do not localize
    (Key: 'dotm'; Value: 'application/vnd.ms-word.template.macroenabled.12'), // do not localize
    (Key: 'wps'; Value: 'application/vnd.ms-works'), // do not localize
    (Key: 'wks'; Value: 'application/vnd.ms-works'), // do not localize
    (Key: 'wcm'; Value: 'application/vnd.ms-works'), // do not localize
    (Key: 'wdb'; Value: 'application/vnd.ms-works'), // do not localize
    (Key: 'wpl'; Value: 'application/vnd.ms-wpl'), // do not localize
    (Key: 'xps'; Value: 'application/vnd.ms-xpsdocument'), // do not localize
    (Key: 'mseq'; Value: 'application/vnd.mseq'), // do not localize
    (Key: 'mus'; Value: 'application/vnd.musician'), // do not localize
    (Key: 'msty'; Value: 'application/vnd.muvee.style'), // do not localize
    (Key: 'taglet'; Value: 'application/vnd.mynfc'), // do not localize
    (Key: 'nlu'; Value: 'application/vnd.neurolanguage.nlu'), // do not localize
    (Key: 'ntf'; Value: 'application/vnd.nitf'), // do not localize
    (Key: 'nitf'; Value: 'application/vnd.nitf'), // do not localize
    (Key: 'nnd'; Value: 'application/vnd.noblenet-directory'), // do not localize
    (Key: 'nns'; Value: 'application/vnd.noblenet-sealer'), // do not localize
    (Key: 'nnw'; Value: 'application/vnd.noblenet-web'), // do not localize
    (Key: 'ngdat'; Value: 'application/vnd.nokia.n-gage.data'), // do not localize
    (Key: 'n-gage'; Value: 'application/vnd.nokia.n-gage.symbian.install'), // do not localize
    (Key: 'rpst'; Value: 'application/vnd.nokia.radio-preset'), // do not localize
    (Key: 'rpss'; Value: 'application/vnd.nokia.radio-presets'), // do not localize
    (Key: 'edm'; Value: 'application/vnd.novadigm.edm'), // do not localize
    (Key: 'edx'; Value: 'application/vnd.novadigm.edx'), // do not localize
    (Key: 'ext'; Value: 'application/vnd.novadigm.ext'), // do not localize
    (Key: 'odc'; Value: 'application/vnd.oasis.opendocument.chart'), // do not localize
    (Key: 'otc'; Value: 'application/vnd.oasis.opendocument.chart-template'), // do not localize
    (Key: 'odb'; Value: 'application/vnd.oasis.opendocument.database'), // do not localize
    (Key: 'odf'; Value: 'application/vnd.oasis.opendocument.formula'), // do not localize
    (Key: 'odft'; Value: 'application/vnd.oasis.opendocument.formula-template'), // do not localize
    (Key: 'odg'; Value: 'application/vnd.oasis.opendocument.graphics'), // do not localize
    (Key: 'otg'; Value: 'application/vnd.oasis.opendocument.graphics-template'), // do not localize
    (Key: 'odi'; Value: 'application/vnd.oasis.opendocument.image'), // do not localize
    (Key: 'oti'; Value: 'application/vnd.oasis.opendocument.image-template'), // do not localize
    (Key: 'odp'; Value: 'application/vnd.oasis.opendocument.presentation'), // do not localize
    (Key: 'otp'; Value: 'application/vnd.oasis.opendocument.presentation-template'), // do not localize
    (Key: 'ods'; Value: 'application/vnd.oasis.opendocument.spreadsheet'), // do not localize
    (Key: 'ots'; Value: 'application/vnd.oasis.opendocument.spreadsheet-template'), // do not localize
    (Key: 'odt'; Value: 'application/vnd.oasis.opendocument.text'), // do not localize
    (Key: 'odm'; Value: 'application/vnd.oasis.opendocument.text-master'), // do not localize
    (Key: 'ott'; Value: 'application/vnd.oasis.opendocument.text-template'), // do not localize
    (Key: 'oth'; Value: 'application/vnd.oasis.opendocument.text-web'), // do not localize
    (Key: 'xo'; Value: 'application/vnd.olpc-sugar'), // do not localize
    (Key: 'dd2'; Value: 'application/vnd.oma.dd2+xml'), // do not localize
    (Key: 'oxt'; Value: 'application/vnd.openofficeorg.extension'), // do not localize
    (Key: 'pptx'; Value: 'application/vnd.openxmlformats-officedocument.presentationml.presentation'), // do not localize
    (Key: 'sldx'; Value: 'application/vnd.openxmlformats-officedocument.presentationml.slide'), // do not localize
    (Key: 'ppsx'; Value: 'application/vnd.openxmlformats-officedocument.presentationml.slideshow'), // do not localize
    (Key: 'potx'; Value: 'application/vnd.openxmlformats-officedocument.presentationml.template'), // do not localize
    (Key: 'xlsx'; Value: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'), // do not localize
    (Key: 'xltx'; Value: 'application/vnd.openxmlformats-officedocument.spreadsheetml.template'), // do not localize
    (Key: 'docx'; Value: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'), // do not localize
    (Key: 'dotx'; Value: 'application/vnd.openxmlformats-officedocument.wordprocessingml.template'), // do not localize
    (Key: 'mgp'; Value: 'application/vnd.osgeo.mapguide.package'), // do not localize
    (Key: 'dp'; Value: 'application/vnd.osgi.dp'), // do not localize
    (Key: 'esa'; Value: 'application/vnd.osgi.subsystem'), // do not localize
    (Key: 'pdb'; Value: 'application/vnd.palm'), // do not localize
    (Key: 'pqa'; Value: 'application/vnd.palm'), // do not localize
    (Key: 'oprc'; Value: 'application/vnd.palm'), // do not localize
    (Key: 'paw'; Value: 'application/vnd.pawaafile'), // do not localize
    (Key: 'str'; Value: 'application/vnd.pg.format'), // do not localize
    (Key: 'ei6'; Value: 'application/vnd.pg.osasli'), // do not localize
    (Key: 'efif'; Value: 'application/vnd.picsel'), // do not localize
    (Key: 'wg'; Value: 'application/vnd.pmi.widget'), // do not localize
    (Key: 'plf'; Value: 'application/vnd.pocketlearn'), // do not localize
    (Key: 'pbd'; Value: 'application/vnd.powerbuilder6'), // do not localize
    (Key: 'box'; Value: 'application/vnd.previewsystems.box'), // do not localize
    (Key: 'mgz'; Value: 'application/vnd.proteus.magazine'), // do not localize
    (Key: 'qps'; Value: 'application/vnd.publishare-delta-tree'), // do not localize
    (Key: 'ptid'; Value: 'application/vnd.pvi.ptid1'), // do not localize
    (Key: 'qxd'; Value: 'application/vnd.quark.quarkxpress'), // do not localize
    (Key: 'qxt'; Value: 'application/vnd.quark.quarkxpress'), // do not localize
    (Key: 'qwd'; Value: 'application/vnd.quark.quarkxpress'), // do not localize
    (Key: 'qwt'; Value: 'application/vnd.quark.quarkxpress'), // do not localize
    (Key: 'qxl'; Value: 'application/vnd.quark.quarkxpress'), // do not localize
    (Key: 'qxb'; Value: 'application/vnd.quark.quarkxpress'), // do not localize
    (Key: 'bed'; Value: 'application/vnd.realvnc.bed'), // do not localize
    (Key: 'mxl'; Value: 'application/vnd.recordare.musicxml'), // do not localize
    (Key: 'musicxml'; Value: 'application/vnd.recordare.musicxml+xml'), // do not localize
    (Key: 'cryptonote'; Value: 'application/vnd.rig.cryptonote'), // do not localize
    (Key: 'cod'; Value: 'application/vnd.rim.cod'), // do not localize
    (Key: 'rm'; Value: 'application/vnd.rn-realmedia'), // do not localize
    (Key: 'rmvb'; Value: 'application/vnd.rn-realmedia-vbr'), // do not localize
    (Key: 'link66'; Value: 'application/vnd.route66.link66+xml'), // do not localize
    (Key: 'st'; Value: 'application/vnd.sailingtracker.track'), // do not localize
    (Key: 'see'; Value: 'application/vnd.seemail'), // do not localize
    (Key: 'sema'; Value: 'application/vnd.sema'), // do not localize
    (Key: 'semd'; Value: 'application/vnd.semd'), // do not localize
    (Key: 'semf'; Value: 'application/vnd.semf'), // do not localize
    (Key: 'ifm'; Value: 'application/vnd.shana.informed.formdata'), // do not localize
    (Key: 'itp'; Value: 'application/vnd.shana.informed.formtemplate'), // do not localize
    (Key: 'iif'; Value: 'application/vnd.shana.informed.interchange'), // do not localize
    (Key: 'ipk'; Value: 'application/vnd.shana.informed.package'), // do not localize
    (Key: 'twd'; Value: 'application/vnd.simtech-mindmapper'), // do not localize
    (Key: 'twds'; Value: 'application/vnd.simtech-mindmapper'), // do not localize
    (Key: 'mmf'; Value: 'application/vnd.smaf'), // do not localize
    (Key: 'teacher'; Value: 'application/vnd.smart.teacher'), // do not localize
    (Key: 'sdkm'; Value: 'application/vnd.solent.sdkm+xml'), // do not localize
    (Key: 'sdkd'; Value: 'application/vnd.solent.sdkm+xml'), // do not localize
    (Key: 'dxp'; Value: 'application/vnd.spotfire.dxp'), // do not localize
    (Key: 'sfs'; Value: 'application/vnd.spotfire.sfs'), // do not localize
    (Key: 'sdc'; Value: 'application/vnd.stardivision.calc'), // do not localize
    (Key: 'sda'; Value: 'application/vnd.stardivision.draw'), // do not localize
    (Key: 'sdd'; Value: 'application/vnd.stardivision.impress'), // do not localize
    (Key: 'smf'; Value: 'application/vnd.stardivision.math'), // do not localize
    (Key: 'sdw'; Value: 'application/vnd.stardivision.writer'), // do not localize
    (Key: 'vor'; Value: 'application/vnd.stardivision.writer'), // do not localize
    (Key: 'sgl'; Value: 'application/vnd.stardivision.writer-global'), // do not localize
    (Key: 'smzip'; Value: 'application/vnd.stepmania.package'), // do not localize
    (Key: 'sm'; Value: 'application/vnd.stepmania.stepchart'), // do not localize
    (Key: 'sxc'; Value: 'application/vnd.sun.xml.calc'), // do not localize
    (Key: 'stc'; Value: 'application/vnd.sun.xml.calc.template'), // do not localize
    (Key: 'sxd'; Value: 'application/vnd.sun.xml.draw'), // do not localize
    (Key: 'std'; Value: 'application/vnd.sun.xml.draw.template'), // do not localize
    (Key: 'sxi'; Value: 'application/vnd.sun.xml.impress'), // do not localize
    (Key: 'sti'; Value: 'application/vnd.sun.xml.impress.template'), // do not localize
    (Key: 'sxm'; Value: 'application/vnd.sun.xml.math'), // do not localize
    (Key: 'sxw'; Value: 'application/vnd.sun.xml.writer'), // do not localize
    (Key: 'sxg'; Value: 'application/vnd.sun.xml.writer.global'), // do not localize
    (Key: 'stw'; Value: 'application/vnd.sun.xml.writer.template'), // do not localize
    (Key: 'sus'; Value: 'application/vnd.sus-calendar'), // do not localize
    (Key: 'susp'; Value: 'application/vnd.sus-calendar'), // do not localize
    (Key: 'svd'; Value: 'application/vnd.svd'), // do not localize
    (Key: 'sis'; Value: 'application/vnd.symbian.install'), // do not localize
    (Key: 'sisx'; Value: 'application/vnd.symbian.install'), // do not localize
    (Key: 'xsm'; Value: 'application/vnd.syncml+xml'), // do not localize
    (Key: 'bdm'; Value: 'application/vnd.syncml.dm+wbxml'), // do not localize
    (Key: 'xdm'; Value: 'application/vnd.syncml.dm+xml'), // do not localize
    (Key: 'tao'; Value: 'application/vnd.tao.intent-module-archive'), // do not localize
    (Key: 'pcap'; Value: 'application/vnd.tcpdump.pcap'), // do not localize
    (Key: 'cap'; Value: 'application/vnd.tcpdump.pcap'), // do not localize
    (Key: 'dmp'; Value: 'application/vnd.tcpdump.pcap'), // do not localize
    (Key: 'tmo'; Value: 'application/vnd.tmobile-livetv'), // do not localize
    (Key: 'tpt'; Value: 'application/vnd.trid.tpt'), // do not localize
    (Key: 'mxs'; Value: 'application/vnd.triscape.mxs'), // do not localize
    (Key: 'tra'; Value: 'application/vnd.trueapp'), // do not localize
    (Key: 'ufd'; Value: 'application/vnd.ufdl'), // do not localize
    (Key: 'ufdl'; Value: 'application/vnd.ufdl'), // do not localize
    (Key: 'utz'; Value: 'application/vnd.uiq.theme'), // do not localize
    (Key: 'umj'; Value: 'application/vnd.umajin'), // do not localize
    (Key: 'unityweb'; Value: 'application/vnd.unity'), // do not localize
    (Key: 'uoml'; Value: 'application/vnd.uoml+xml'), // do not localize
    (Key: 'vcx'; Value: 'application/vnd.vcx'), // do not localize
    (Key: 'vsd'; Value: 'application/vnd.visio'), // do not localize
    (Key: 'vst'; Value: 'application/vnd.visio'), // do not localize
    (Key: 'vss'; Value: 'application/vnd.visio'), // do not localize
    (Key: 'vsw'; Value: 'application/vnd.visio'), // do not localize
    (Key: 'vis'; Value: 'application/vnd.visionary'), // do not localize
    (Key: 'vsf'; Value: 'application/vnd.vsf'), // do not localize
    (Key: 'wbxml'; Value: 'application/vnd.wap.wbxml'), // do not localize
    (Key: 'wmlc'; Value: 'application/vnd.wap.wmlc'), // do not localize
    (Key: 'wmlsc'; Value: 'application/vnd.wap.wmlscriptc'), // do not localize
    (Key: 'wtb'; Value: 'application/vnd.webturbo'), // do not localize
    (Key: 'nbp'; Value: 'application/vnd.wolfram.player'), // do not localize
    (Key: 'wpd'; Value: 'application/vnd.wordperfect'), // do not localize
    (Key: 'wqd'; Value: 'application/vnd.wqd'), // do not localize
    (Key: 'stf'; Value: 'application/vnd.wt.stf'), // do not localize
    (Key: 'xar'; Value: 'application/vnd.xara'), // do not localize
    (Key: 'xfdl'; Value: 'application/vnd.xfdl'), // do not localize
    (Key: 'hvd'; Value: 'application/vnd.yamaha.hv-dic'), // do not localize
    (Key: 'hvs'; Value: 'application/vnd.yamaha.hv-script'), // do not localize
    (Key: 'hvp'; Value: 'application/vnd.yamaha.hv-voice'), // do not localize
    (Key: 'osf'; Value: 'application/vnd.yamaha.openscoreformat'), // do not localize
    (Key: 'osfpvg'; Value: 'application/vnd.yamaha.openscoreformat.osfpvg+xml'), // do not localize
    (Key: 'saf'; Value: 'application/vnd.yamaha.smaf-audio'), // do not localize
    (Key: 'spf'; Value: 'application/vnd.yamaha.smaf-phrase'), // do not localize
    (Key: 'cmp'; Value: 'application/vnd.yellowriver-custom-menu'), // do not localize
    (Key: 'zir'; Value: 'application/vnd.zul'), // do not localize
    (Key: 'zirz'; Value: 'application/vnd.zul'), // do not localize
    (Key: 'zaz'; Value: 'application/vnd.zzazz.deck+xml'), // do not localize
    (Key: 'vxml'; Value: 'application/voicexml+xml'), // do not localize
    (Key: 'wgt'; Value: 'application/widget'), // do not localize
    (Key: 'hlp'; Value: 'application/winhlp'), // do not localize
    (Key: 'wsdl'; Value: 'application/wsdl+xml'), // do not localize
    (Key: 'wspolicy'; Value: 'application/wspolicy+xml'), // do not localize
    (Key: '7z'; Value: 'application/x-7z-compressed'), // do not localize
    (Key: 'abw'; Value: 'application/x-abiword'), // do not localize
    (Key: 'ace'; Value: 'application/x-ace-compressed'), // do not localize
    (Key: 'dmg'; Value: 'application/x-apple-diskimage'), // do not localize
    (Key: 'aab'; Value: 'application/x-authorware-bin'), // do not localize
    (Key: 'x32'; Value: 'application/x-authorware-bin'), // do not localize
    (Key: 'u32'; Value: 'application/x-authorware-bin'), // do not localize
    (Key: 'vox'; Value: 'application/x-authorware-bin'), // do not localize
    (Key: 'aam'; Value: 'application/x-authorware-map'), // do not localize
    (Key: 'aas'; Value: 'application/x-authorware-seg'), // do not localize
    (Key: 'bcpio'; Value: 'application/x-bcpio'), // do not localize
    (Key: 'torrent'; Value: 'application/x-bittorrent'), // do not localize
    (Key: 'blb'; Value: 'application/x-blorb'), // do not localize
    (Key: 'blorb'; Value: 'application/x-blorb'), // do not localize
    (Key: 'bz'; Value: 'application/x-bzip'), // do not localize
    (Key: 'bz2'; Value: 'application/x-bzip2'), // do not localize
    (Key: 'boz'; Value: 'application/x-bzip2'), // do not localize
    (Key: 'cbr'; Value: 'application/x-cbr'), // do not localize
    (Key: 'cba'; Value: 'application/x-cbr'), // do not localize
    (Key: 'cbt'; Value: 'application/x-cbr'), // do not localize
    (Key: 'cbz'; Value: 'application/x-cbr'), // do not localize
    (Key: 'cb7'; Value: 'application/x-cbr'), // do not localize
    (Key: 'vcd'; Value: 'application/x-cdlink'), // do not localize
    (Key: 'cfs'; Value: 'application/x-cfs-compressed'), // do not localize
    (Key: 'chat'; Value: 'application/x-chat'), // do not localize
    (Key: 'pgn'; Value: 'application/x-chess-pgn'), // do not localize
    (Key: 'nsc'; Value: 'application/x-conference'), // do not localize
    (Key: 'cpio'; Value: 'application/x-cpio'), // do not localize
    (Key: 'csh'; Value: 'application/x-csh'), // do not localize
    (Key: 'deb'; Value: 'application/x-debian-package'), // do not localize
    (Key: 'udeb'; Value: 'application/x-debian-package'), // do not localize
    (Key: 'dgc'; Value: 'application/x-dgc-compressed'), // do not localize
    (Key: 'dir'; Value: 'application/x-director'), // do not localize
    (Key: 'dcr'; Value: 'application/x-director'), // do not localize
    (Key: 'dxr'; Value: 'application/x-director'), // do not localize
    (Key: 'cst'; Value: 'application/x-director'), // do not localize
    (Key: 'cct'; Value: 'application/x-director'), // do not localize
    (Key: 'cxt'; Value: 'application/x-director'), // do not localize
    (Key: 'w3d'; Value: 'application/x-director'), // do not localize
    (Key: 'fgd'; Value: 'application/x-director'), // do not localize
    (Key: 'swa'; Value: 'application/x-director'), // do not localize
    (Key: 'wad'; Value: 'application/x-doom'), // do not localize
    (Key: 'ncx'; Value: 'application/x-dtbncx+xml'), // do not localize
    (Key: 'dtb'; Value: 'application/x-dtbook+xml'), // do not localize
    (Key: 'res'; Value: 'application/x-dtbresource+xml'), // do not localize
    (Key: 'dvi'; Value: 'application/x-dvi'), // do not localize
    (Key: 'evy'; Value: 'application/x-envoy'), // do not localize
    (Key: 'eva'; Value: 'application/x-eva'), // do not localize
    (Key: 'bdf'; Value: 'application/x-font-bdf'), // do not localize
    (Key: 'gsf'; Value: 'application/x-font-ghostscript'), // do not localize
    (Key: 'psf'; Value: 'application/x-font-linux-psf'), // do not localize
    (Key: 'otf'; Value: 'application/x-font-otf'), // do not localize
    (Key: 'pcf'; Value: 'application/x-font-pcf'), // do not localize
    (Key: 'snf'; Value: 'application/x-font-snf'), // do not localize
    (Key: 'ttf'; Value: 'application/x-font-ttf'), // do not localize
    (Key: 'ttc'; Value: 'application/x-font-ttf'), // do not localize
    (Key: 'pfa'; Value: 'application/x-font-type1'), // do not localize
    (Key: 'pfb'; Value: 'application/x-font-type1'), // do not localize
    (Key: 'pfm'; Value: 'application/x-font-type1'), // do not localize
    (Key: 'afm'; Value: 'application/x-font-type1'), // do not localize
    (Key: 'woff'; Value: 'application/x-font-woff'), // do not localize
    (Key: 'arc'; Value: 'application/x-freearc'), // do not localize
    (Key: 'spl'; Value: 'application/x-futuresplash'), // do not localize
    (Key: 'gca'; Value: 'application/x-gca-compressed'), // do not localize
    (Key: 'ulx'; Value: 'application/x-glulx'), // do not localize
    (Key: 'gnumeric'; Value: 'application/x-gnumeric'), // do not localize
    (Key: 'gramps'; Value: 'application/x-gramps-xml'), // do not localize
    (Key: 'gtar'; Value: 'application/x-gtar'), // do not localize
    (Key: 'hdf'; Value: 'application/x-hdf'), // do not localize
    (Key: 'install'; Value: 'application/x-install-instructions'), // do not localize
    (Key: 'iso'; Value: 'application/x-iso9660-image'), // do not localize
    (Key: 'jnlp'; Value: 'application/x-java-jnlp-file'), // do not localize
    (Key: 'latex'; Value: 'application/x-latex'), // do not localize
    (Key: 'lzh'; Value: 'application/x-lzh-compressed'), // do not localize
    (Key: 'lha'; Value: 'application/x-lzh-compressed'), // do not localize
    (Key: 'mie'; Value: 'application/x-mie'), // do not localize
    (Key: 'prc'; Value: 'application/x-mobipocket-ebook'), // do not localize
    (Key: 'mobi'; Value: 'application/x-mobipocket-ebook'), // do not localize
    (Key: 'application'; Value: 'application/x-ms-application'), // do not localize
    (Key: 'lnk'; Value: 'application/x-ms-shortcut'), // do not localize
    (Key: 'wmd'; Value: 'application/x-ms-wmd'), // do not localize
    (Key: 'wmz'; Value: 'application/x-ms-wmz'), // do not localize
    (Key: 'xbap'; Value: 'application/x-ms-xbap'), // do not localize
    (Key: 'mdb'; Value: 'application/x-msaccess'), // do not localize
    (Key: 'obd'; Value: 'application/x-msbinder'), // do not localize
    (Key: 'crd'; Value: 'application/x-mscardfile'), // do not localize
    (Key: 'clp'; Value: 'application/x-msclip'), // do not localize
    (Key: 'exe'; Value: 'application/x-msdownload'), // do not localize
    (Key: 'dll'; Value: 'application/x-msdownload'), // do not localize
    (Key: 'com'; Value: 'application/x-msdownload'), // do not localize
    (Key: 'bat'; Value: 'application/x-msdownload'), // do not localize
    (Key: 'msi'; Value: 'application/x-msdownload'), // do not localize
    (Key: 'mvb'; Value: 'application/x-msmediaview'), // do not localize
    (Key: 'm13'; Value: 'application/x-msmediaview'), // do not localize
    (Key: 'm14'; Value: 'application/x-msmediaview'), // do not localize
    (Key: 'wmf'; Value: 'application/x-msmetafile'), // do not localize
    (Key: 'wmz'; Value: 'application/x-msmetafile'), // do not localize
    (Key: 'emf'; Value: 'application/x-msmetafile'), // do not localize
    (Key: 'emz'; Value: 'application/x-msmetafile'), // do not localize
    (Key: 'mny'; Value: 'application/x-msmoney'), // do not localize
    (Key: 'pub'; Value: 'application/x-mspublisher'), // do not localize
    (Key: 'scd'; Value: 'application/x-msschedule'), // do not localize
    (Key: 'trm'; Value: 'application/x-msterminal'), // do not localize
    (Key: 'wri'; Value: 'application/x-mswrite'), // do not localize
    (Key: 'nc'; Value: 'application/x-netcdf'), // do not localize
    (Key: 'cdf'; Value: 'application/x-netcdf'), // do not localize
    (Key: 'nzb'; Value: 'application/x-nzb'), // do not localize
    (Key: 'p12'; Value: 'application/x-pkcs12'), // do not localize
    (Key: 'pfx'; Value: 'application/x-pkcs12'), // do not localize
    (Key: 'p7b'; Value: 'application/x-pkcs7-certificates'), // do not localize
    (Key: 'spc'; Value: 'application/x-pkcs7-certificates'), // do not localize
    (Key: 'p7r'; Value: 'application/x-pkcs7-certreqresp'), // do not localize
    (Key: 'rar'; Value: 'application/x-rar-compressed'), // do not localize
    (Key: 'ris'; Value: 'application/x-research-info-systems'), // do not localize
    (Key: 'sh'; Value: 'application/x-sh'), // do not localize
    (Key: 'shar'; Value: 'application/x-shar'), // do not localize
    (Key: 'swf'; Value: 'application/x-shockwave-flash'), // do not localize
    (Key: 'xap'; Value: 'application/x-silverlight-app'), // do not localize
    (Key: 'sql'; Value: 'application/x-sql'), // do not localize
    (Key: 'sit'; Value: 'application/x-stuffit'), // do not localize
    (Key: 'sitx'; Value: 'application/x-stuffitx'), // do not localize
    (Key: 'srt'; Value: 'application/x-subrip'), // do not localize
    (Key: 'sv4cpio'; Value: 'application/x-sv4cpio'), // do not localize
    (Key: 'sv4crc'; Value: 'application/x-sv4crc'), // do not localize
    (Key: 't3'; Value: 'application/x-t3vm-image'), // do not localize
    (Key: 'gam'; Value: 'application/x-tads'), // do not localize
    (Key: 'tar'; Value: 'application/x-tar'), // do not localize
    (Key: 'tcl'; Value: 'application/x-tcl'), // do not localize
    (Key: 'tex'; Value: 'application/x-tex'), // do not localize
    (Key: 'tfm'; Value: 'application/x-tex-tfm'), // do not localize
    (Key: 'texinfo'; Value: 'application/x-texinfo'), // do not localize
    (Key: 'texi'; Value: 'application/x-texinfo'), // do not localize
    (Key: 'obj'; Value: 'application/x-tgif'), // do not localize
    (Key: 'ustar'; Value: 'application/x-ustar'), // do not localize
    (Key: 'src'; Value: 'application/x-wais-source'), // do not localize
    (Key: 'der'; Value: 'application/x-x509-ca-cert'), // do not localize
    (Key: 'crt'; Value: 'application/x-x509-ca-cert'), // do not localize
    (Key: 'fig'; Value: 'application/x-xfig'), // do not localize
    (Key: 'xlf'; Value: 'application/x-xliff+xml'), // do not localize
    (Key: 'xpi'; Value: 'application/x-xpinstall'), // do not localize
    (Key: 'xz'; Value: 'application/x-xz'), // do not localize
    (Key: 'z1'; Value: 'application/x-zmachine'), // do not localize
    (Key: 'z2'; Value: 'application/x-zmachine'), // do not localize
    (Key: 'z3'; Value: 'application/x-zmachine'), // do not localize
    (Key: 'z4'; Value: 'application/x-zmachine'), // do not localize
    (Key: 'z5'; Value: 'application/x-zmachine'), // do not localize
    (Key: 'z6'; Value: 'application/x-zmachine'), // do not localize
    (Key: 'z7'; Value: 'application/x-zmachine'), // do not localize
    (Key: 'z8'; Value: 'application/x-zmachine'), // do not localize
    (Key: 'xaml'; Value: 'application/xaml+xml'), // do not localize
    (Key: 'xdf'; Value: 'application/xcap-diff+xml'), // do not localize
    (Key: 'xenc'; Value: 'application/xenc+xml'), // do not localize
    (Key: 'xhtml'; Value: 'application/xhtml+xml'), // do not localize
    (Key: 'xht'; Value: 'application/xhtml+xml'), // do not localize
    (Key: 'xml'; Value: 'application/xml'), // do not localize
    (Key: 'xsl'; Value: 'application/xml'), // do not localize
    (Key: 'dtd'; Value: 'application/xml-dtd'), // do not localize
    (Key: 'xop'; Value: 'application/xop+xml'), // do not localize
    (Key: 'xpl'; Value: 'application/xproc+xml'), // do not localize
    (Key: 'xslt'; Value: 'application/xslt+xml'), // do not localize
    (Key: 'xspf'; Value: 'application/xspf+xml'), // do not localize
    (Key: 'mxml'; Value: 'application/xv+xml'), // do not localize
    (Key: 'xhvml'; Value: 'application/xv+xml'), // do not localize
    (Key: 'xvml'; Value: 'application/xv+xml'), // do not localize
    (Key: 'xvm'; Value: 'application/xv+xml'), // do not localize
    (Key: 'yang'; Value: 'application/yang'), // do not localize
    (Key: 'yin'; Value: 'application/yin+xml'), // do not localize
    (Key: 'zip'; Value: 'application/zip'), // do not localize
    (Key: 'adp'; Value: 'audio/adpcm'), // do not localize
    (Key: 'au'; Value: 'audio/basic'), // do not localize
    (Key: 'snd'; Value: 'audio/basic'), // do not localize
    (Key: 'mid'; Value: 'audio/midi'), // do not localize
    (Key: 'midi'; Value: 'audio/midi'), // do not localize
    (Key: 'kar'; Value: 'audio/midi'), // do not localize
    (Key: 'rmi'; Value: 'audio/midi'), // do not localize
    (Key: 'mp4a'; Value: 'audio/mp4'), // do not localize
    (Key: 'mpga'; Value: 'audio/mpeg'), // do not localize
    (Key: 'mp2'; Value: 'audio/mpeg'), // do not localize
    (Key: 'mp2a'; Value: 'audio/mpeg'), // do not localize
    (Key: 'mp3'; Value: 'audio/mpeg'), // do not localize
    (Key: 'm2a'; Value: 'audio/mpeg'), // do not localize
    (Key: 'm3a'; Value: 'audio/mpeg'), // do not localize
    (Key: 'oga'; Value: 'audio/ogg'), // do not localize
    (Key: 'ogg'; Value: 'audio/ogg'), // do not localize
    (Key: 'spx'; Value: 'audio/ogg'), // do not localize
    (Key: 's3m'; Value: 'audio/s3m'), // do not localize
    (Key: 'sil'; Value: 'audio/silk'), // do not localize
    (Key: 'uva'; Value: 'audio/vnd.dece.audio'), // do not localize
    (Key: 'uvva'; Value: 'audio/vnd.dece.audio'), // do not localize
    (Key: 'eol'; Value: 'audio/vnd.digital-winds'), // do not localize
    (Key: 'dra'; Value: 'audio/vnd.dra'), // do not localize
    (Key: 'dts'; Value: 'audio/vnd.dts'), // do not localize
    (Key: 'dtshd'; Value: 'audio/vnd.dts.hd'), // do not localize
    (Key: 'lvp'; Value: 'audio/vnd.lucent.voice'), // do not localize
    (Key: 'pya'; Value: 'audio/vnd.ms-playready.media.pya'), // do not localize
    (Key: 'ecelp4800'; Value: 'audio/vnd.nuera.ecelp4800'), // do not localize
    (Key: 'ecelp7470'; Value: 'audio/vnd.nuera.ecelp7470'), // do not localize
    (Key: 'ecelp9600'; Value: 'audio/vnd.nuera.ecelp9600'), // do not localize
    (Key: 'rip'; Value: 'audio/vnd.rip'), // do not localize
    (Key: 'weba'; Value: 'audio/webm'), // do not localize
    (Key: 'aac'; Value: 'audio/x-aac'), // do not localize
    (Key: 'aif'; Value: 'audio/x-aiff'), // do not localize
    (Key: 'aiff'; Value: 'audio/x-aiff'), // do not localize
    (Key: 'aifc'; Value: 'audio/x-aiff'), // do not localize
    (Key: 'caf'; Value: 'audio/x-caf'), // do not localize
    (Key: 'flac'; Value: 'audio/x-flac'), // do not localize
    (Key: 'mka'; Value: 'audio/x-matroska'), // do not localize
    (Key: 'm3u'; Value: 'audio/x-mpegurl'), // do not localize
    (Key: 'wax'; Value: 'audio/x-ms-wax'), // do not localize
    (Key: 'wma'; Value: 'audio/x-ms-wma'), // do not localize
    (Key: 'ram'; Value: 'audio/x-pn-realaudio'), // do not localize
    (Key: 'ra'; Value: 'audio/x-pn-realaudio'), // do not localize
    (Key: 'rmp'; Value: 'audio/x-pn-realaudio-plugin'), // do not localize
    (Key: 'wav'; Value: 'audio/x-wav'), // do not localize
    (Key: 'xm'; Value: 'audio/xm'), // do not localize
    (Key: 'cdx'; Value: 'chemical/x-cdx'), // do not localize
    (Key: 'cif'; Value: 'chemical/x-cif'), // do not localize
    (Key: 'cmdf'; Value: 'chemical/x-cmdf'), // do not localize
    (Key: 'cml'; Value: 'chemical/x-cml'), // do not localize
    (Key: 'csml'; Value: 'chemical/x-csml'), // do not localize
    (Key: 'xyz'; Value: 'chemical/x-xyz'), // do not localize
    (Key: 'bmp'; Value: 'image/bmp'), // do not localize
    (Key: 'cgm'; Value: 'image/cgm'), // do not localize
    (Key: 'g3'; Value: 'image/g3fax'), // do not localize
    (Key: 'gif'; Value: 'image/gif'), // do not localize
    (Key: 'ief'; Value: 'image/ief'), // do not localize
    (Key: 'jpeg'; Value: 'image/jpeg'), // do not localize
    (Key: 'jpg'; Value: 'image/jpeg'), // do not localize
    (Key: 'jpe'; Value: 'image/jpeg'), // do not localize
    (Key: 'ktx'; Value: 'image/ktx'), // do not localize
    (Key: 'png'; Value: 'image/png'), // do not localize
    (Key: 'btif'; Value: 'image/prs.btif'), // do not localize
    (Key: 'sgi'; Value: 'image/sgi'), // do not localize
    (Key: 'svg'; Value: 'image/svg+xml'), // do not localize
    (Key: 'svgz'; Value: 'image/svg+xml'), // do not localize
    (Key: 'tiff'; Value: 'image/tiff'), // do not localize
    (Key: 'tif'; Value: 'image/tiff'), // do not localize
    (Key: 'psd'; Value: 'image/vnd.adobe.photoshop'), // do not localize
    (Key: 'uvi'; Value: 'image/vnd.dece.graphic'), // do not localize
    (Key: 'uvvi'; Value: 'image/vnd.dece.graphic'), // do not localize
    (Key: 'uvg'; Value: 'image/vnd.dece.graphic'), // do not localize
    (Key: 'uvvg'; Value: 'image/vnd.dece.graphic'), // do not localize
    (Key: 'sub'; Value: 'image/vnd.dvb.subtitle'), // do not localize
    (Key: 'djvu'; Value: 'image/vnd.djvu'), // do not localize
    (Key: 'djv'; Value: 'image/vnd.djvu'), // do not localize
    (Key: 'dwg'; Value: 'image/vnd.dwg'), // do not localize
    (Key: 'dxf'; Value: 'image/vnd.dxf'), // do not localize
    (Key: 'fbs'; Value: 'image/vnd.fastbidsheet'), // do not localize
    (Key: 'fpx'; Value: 'image/vnd.fpx'), // do not localize
    (Key: 'fst'; Value: 'image/vnd.fst'), // do not localize
    (Key: 'mmr'; Value: 'image/vnd.fujixerox.edmics-mmr'), // do not localize
    (Key: 'rlc'; Value: 'image/vnd.fujixerox.edmics-rlc'), // do not localize
    (Key: 'mdi'; Value: 'image/vnd.ms-modi'), // do not localize
    (Key: 'wdp'; Value: 'image/vnd.ms-photo'), // do not localize
    (Key: 'npx'; Value: 'image/vnd.net-fpx'), // do not localize
    (Key: 'wbmp'; Value: 'image/vnd.wap.wbmp'), // do not localize
    (Key: 'xif'; Value: 'image/vnd.xiff'), // do not localize
    (Key: 'webp'; Value: 'image/webp'), // do not localize
    (Key: '3ds'; Value: 'image/x-3ds'), // do not localize
    (Key: 'ras'; Value: 'image/x-cmu-raster'), // do not localize
    (Key: 'cmx'; Value: 'image/x-cmx'), // do not localize
    (Key: 'fh'; Value: 'image/x-freehand'), // do not localize
    (Key: 'fhc'; Value: 'image/x-freehand'), // do not localize
    (Key: 'fh4'; Value: 'image/x-freehand'), // do not localize
    (Key: 'fh5'; Value: 'image/x-freehand'), // do not localize
    (Key: 'fh7'; Value: 'image/x-freehand'), // do not localize
    (Key: 'ico'; Value: 'image/x-icon'), // do not localize
    (Key: 'sid'; Value: 'image/x-mrsid-image'), // do not localize
    (Key: 'pcx'; Value: 'image/x-pcx'), // do not localize
    (Key: 'pic'; Value: 'image/x-pict'), // do not localize
    (Key: 'pct'; Value: 'image/x-pict'), // do not localize
    (Key: 'pnm'; Value: 'image/x-portable-anymap'), // do not localize
    (Key: 'pbm'; Value: 'image/x-portable-bitmap'), // do not localize
    (Key: 'pgm'; Value: 'image/x-portable-graymap'), // do not localize
    (Key: 'ppm'; Value: 'image/x-portable-pixmap'), // do not localize
    (Key: 'rgb'; Value: 'image/x-rgb'), // do not localize
    (Key: 'tga'; Value: 'image/x-tga'), // do not localize
    (Key: 'xbm'; Value: 'image/x-xbitmap'), // do not localize
    (Key: 'xpm'; Value: 'image/x-xpixmap'), // do not localize
    (Key: 'xwd'; Value: 'image/x-xwindowdump'), // do not localize
    (Key: 'eml'; Value: 'message/rfc822'), // do not localize
    (Key: 'mime'; Value: 'message/rfc822'), // do not localize
    (Key: 'igs'; Value: 'model/iges'), // do not localize
    (Key: 'iges'; Value: 'model/iges'), // do not localize
    (Key: 'msh'; Value: 'model/mesh'), // do not localize
    (Key: 'mesh'; Value: 'model/mesh'), // do not localize
    (Key: 'silo'; Value: 'model/mesh'), // do not localize
    (Key: 'dae'; Value: 'model/vnd.collada+xml'), // do not localize
    (Key: 'dwf'; Value: 'model/vnd.dwf'), // do not localize
    (Key: 'gdl'; Value: 'model/vnd.gdl'), // do not localize
    (Key: 'gtw'; Value: 'model/vnd.gtw'), // do not localize
    (Key: 'mts'; Value: 'model/vnd.mts'), // do not localize
    (Key: 'vtu'; Value: 'model/vnd.vtu'), // do not localize
    (Key: 'wrl'; Value: 'model/vrml'), // do not localize
    (Key: 'vrml'; Value: 'model/vrml'), // do not localize
    (Key: 'x3db'; Value: 'model/x3d+binary'), // do not localize
    (Key: 'x3dbz'; Value: 'model/x3d+binary'), // do not localize
    (Key: 'x3dv'; Value: 'model/x3d+vrml'), // do not localize
    (Key: 'x3dvz'; Value: 'model/x3d+vrml'), // do not localize
    (Key: 'x3d'; Value: 'model/x3d+xml'), // do not localize
    (Key: 'x3dz'; Value: 'model/x3d+xml'), // do not localize
    (Key: 'appcache'; Value: 'text/cache-manifest'), // do not localize
    (Key: 'ics'; Value: 'text/calendar'), // do not localize
    (Key: 'ifb'; Value: 'text/calendar'), // do not localize
    (Key: 'css'; Value: 'text/css'), // do not localize
    (Key: 'csv'; Value: 'text/csv'), // do not localize
    (Key: 'html'; Value: 'text/html'), // do not localize
    (Key: 'htm'; Value: 'text/html'), // do not localize
    (Key: 'n3'; Value: 'text/n3'), // do not localize
    (Key: 'txt'; Value: 'text/plain'), // do not localize
    (Key: 'text'; Value: 'text/plain'), // do not localize
    (Key: 'conf'; Value: 'text/plain'), // do not localize
    (Key: 'def'; Value: 'text/plain'), // do not localize
    (Key: 'list'; Value: 'text/plain'), // do not localize
    (Key: 'log'; Value: 'text/plain'), // do not localize
    (Key: 'in'; Value: 'text/plain'), // do not localize
    (Key: 'dsc'; Value: 'text/prs.lines.tag'), // do not localize
    (Key: 'rtx'; Value: 'text/richtext'), // do not localize
    (Key: 'sgml'; Value: 'text/sgml'), // do not localize
    (Key: 'sgm'; Value: 'text/sgml'), // do not localize
    (Key: 'tsv'; Value: 'text/tab-separated-values'), // do not localize
    (Key: 't'; Value: 'text/troff'), // do not localize
    (Key: 'tr'; Value: 'text/troff'), // do not localize
    (Key: 'roff'; Value: 'text/troff'), // do not localize
    (Key: 'man'; Value: 'text/troff'), // do not localize
    (Key: 'me'; Value: 'text/troff'), // do not localize
    (Key: 'ms'; Value: 'text/troff'), // do not localize
    (Key: 'ttl'; Value: 'text/turtle'), // do not localize
    (Key: 'uri'; Value: 'text/uri-list'), // do not localize
    (Key: 'uris'; Value: 'text/uri-list'), // do not localize
    (Key: 'urls'; Value: 'text/uri-list'), // do not localize
    (Key: 'vcard'; Value: 'text/vcard'), // do not localize
    (Key: 'curl'; Value: 'text/vnd.curl'), // do not localize
    (Key: 'dcurl'; Value: 'text/vnd.curl.dcurl'), // do not localize
    (Key: 'scurl'; Value: 'text/vnd.curl.scurl'), // do not localize
    (Key: 'mcurl'; Value: 'text/vnd.curl.mcurl'), // do not localize
    (Key: 'sub'; Value: 'text/vnd.dvb.subtitle'), // do not localize
    (Key: 'fly'; Value: 'text/vnd.fly'), // do not localize
    (Key: 'flx'; Value: 'text/vnd.fmi.flexstor'), // do not localize
    (Key: 'gv'; Value: 'text/vnd.graphviz'), // do not localize
    (Key: '3dml'; Value: 'text/vnd.in3d.3dml'), // do not localize
    (Key: 'spot'; Value: 'text/vnd.in3d.spot'), // do not localize
    (Key: 'jad'; Value: 'text/vnd.sun.j2me.app-descriptor'), // do not localize
    (Key: 'wml'; Value: 'text/vnd.wap.wml'), // do not localize
    (Key: 'wmls'; Value: 'text/vnd.wap.wmlscript'), // do not localize
    (Key: 's'; Value: 'text/x-asm'), // do not localize
    (Key: 'asm'; Value: 'text/x-asm'), // do not localize
    (Key: 'c'; Value: 'text/x-c'), // do not localize
    (Key: 'cc'; Value: 'text/x-c'), // do not localize
    (Key: 'cxx'; Value: 'text/x-c'), // do not localize
    (Key: 'cpp'; Value: 'text/x-c'), // do not localize
    (Key: 'h'; Value: 'text/x-c'), // do not localize
    (Key: 'hh'; Value: 'text/x-c'), // do not localize
    (Key: 'dic'; Value: 'text/x-c'), // do not localize
    (Key: 'f'; Value: 'text/x-fortran'), // do not localize
    (Key: 'for'; Value: 'text/x-fortran'), // do not localize
    (Key: 'f77'; Value: 'text/x-fortran'), // do not localize
    (Key: 'f90'; Value: 'text/x-fortran'), // do not localize
    (Key: 'java'; Value: 'text/x-java-source'), // do not localize
    (Key: 'opml'; Value: 'text/x-opml'), // do not localize
    (Key: 'p'; Value: 'text/x-pascal'), // do not localize
    (Key: 'pas'; Value: 'text/x-pascal'), // do not localize
    (Key: 'nfo'; Value: 'text/x-nfo'), // do not localize
    (Key: 'etx'; Value: 'text/x-setext'), // do not localize
    (Key: 'sfv'; Value: 'text/x-sfv'), // do not localize
    (Key: 'uu'; Value: 'text/x-uuencode'), // do not localize
    (Key: 'vcs'; Value: 'text/x-vcalendar'), // do not localize
    (Key: 'vcf'; Value: 'text/x-vcard'), // do not localize
    (Key: '3gp'; Value: 'video/3gpp'), // do not localize
    (Key: '3g2'; Value: 'video/3gpp2'), // do not localize
    (Key: 'h261'; Value: 'video/h261'), // do not localize
    (Key: 'h263'; Value: 'video/h263'), // do not localize
    (Key: 'h264'; Value: 'video/h264'), // do not localize
    (Key: 'jpgv'; Value: 'video/jpeg'), // do not localize
    (Key: 'jpm'; Value: 'video/jpm'), // do not localize
    (Key: 'jpgm'; Value: 'video/jpm'), // do not localize
    (Key: 'mj2'; Value: 'video/mj2'), // do not localize
    (Key: 'mjp2'; Value: 'video/mj2'), // do not localize
    (Key: 'mp4'; Value: 'video/mp4'), // do not localize
    (Key: 'mp4v'; Value: 'video/mp4'), // do not localize
    (Key: 'mpg4'; Value: 'video/mp4'), // do not localize
    (Key: 'mpeg'; Value: 'video/mpeg'), // do not localize
    (Key: 'mpg'; Value: 'video/mpeg'), // do not localize
    (Key: 'mpe'; Value: 'video/mpeg'), // do not localize
    (Key: 'm1v'; Value: 'video/mpeg'), // do not localize
    (Key: 'm2v'; Value: 'video/mpeg'), // do not localize
    (Key: 'ogv'; Value: 'video/ogg'), // do not localize
    (Key: 'qt'; Value: 'video/quicktime'), // do not localize
    (Key: 'mov'; Value: 'video/quicktime'), // do not localize
    (Key: 'uvh'; Value: 'video/vnd.dece.hd'), // do not localize
    (Key: 'uvvh'; Value: 'video/vnd.dece.hd'), // do not localize
    (Key: 'uvm'; Value: 'video/vnd.dece.mobile'), // do not localize
    (Key: 'uvvm'; Value: 'video/vnd.dece.mobile'), // do not localize
    (Key: 'uvp'; Value: 'video/vnd.dece.pd'), // do not localize
    (Key: 'uvvp'; Value: 'video/vnd.dece.pd'), // do not localize
    (Key: 'uvs'; Value: 'video/vnd.dece.sd'), // do not localize
    (Key: 'uvvs'; Value: 'video/vnd.dece.sd'), // do not localize
    (Key: 'uvv'; Value: 'video/vnd.dece.video'), // do not localize
    (Key: 'uvvv'; Value: 'video/vnd.dece.video'), // do not localize
    (Key: 'dvb'; Value: 'video/vnd.dvb.file'), // do not localize
    (Key: 'fvt'; Value: 'video/vnd.fvt'), // do not localize
    (Key: 'mxu'; Value: 'video/vnd.mpegurl'), // do not localize
    (Key: 'm4u'; Value: 'video/vnd.mpegurl'), // do not localize
    (Key: 'pyv'; Value: 'video/vnd.ms-playready.media.pyv'), // do not localize
    (Key: 'uvu'; Value: 'video/vnd.uvvu.mp4'), // do not localize
    (Key: 'uvvu'; Value: 'video/vnd.uvvu.mp4'), // do not localize
    (Key: 'viv'; Value: 'video/vnd.vivo'), // do not localize
    (Key: 'webm'; Value: 'video/webm'), // do not localize
    (Key: 'f4v'; Value: 'video/x-f4v'), // do not localize
    (Key: 'fli'; Value: 'video/x-fli'), // do not localize
    (Key: 'flv'; Value: 'video/x-flv'), // do not localize
    (Key: 'm4v'; Value: 'video/x-m4v'), // do not localize
    (Key: 'mkv'; Value: 'video/x-matroska'), // do not localize
    (Key: 'mk3d'; Value: 'video/x-matroska'), // do not localize
    (Key: 'mks'; Value: 'video/x-matroska'), // do not localize
    (Key: 'mng'; Value: 'video/x-mng'), // do not localize
    (Key: 'asf'; Value: 'video/x-ms-asf'), // do not localize
    (Key: 'asx'; Value: 'video/x-ms-asf'), // do not localize
    (Key: 'vob'; Value: 'video/x-ms-vob'), // do not localize
    (Key: 'wm'; Value: 'video/x-ms-wm'), // do not localize
    (Key: 'wmv'; Value: 'video/x-ms-wmv'), // do not localize
    (Key: 'wmx'; Value: 'video/x-ms-wmx'), // do not localize
    (Key: 'wvx'; Value: 'video/x-ms-wvx'), // do not localize
    (Key: 'avi'; Value: 'video/x-msvideo'), // do not localize
    (Key: 'movie'; Value: 'video/x-sgi-movie'), // do not localize
    (Key: 'smv'; Value: 'video/x-smv'), // do not localize
    (Key: 'ice'; Value: 'x-conference/x-cooltalk') // do not localize
  );
  {$ENDREGION}

type
  TMediaType = class
  public const
    DELIM_PARAMS = ';';
    CHARSET_NAME = 'charset';
    CHARSET_UTF8 = 'utf-8';
    CHARSET_UTF8_DEF = CHARSET_NAME + '=' +  CHARSET_UTF8;

    TEXT_PLAIN = 'text/plain';
    TEXT_PLAIN_UTF8 = TEXT_PLAIN + DELIM_PARAMS + CHARSET_UTF8_DEF;

    TEXT_XML = 'text/xml';
    TEXT_XML_UTF8 = TEXT_XML + DELIM_PARAMS + CHARSET_UTF8_DEF;

    TEXT_HTML = 'text/html';
    TEXT_HTML_UTF8 = TEXT_HTML + DELIM_PARAMS + CHARSET_UTF8_DEF;

    APPLICATION_JSON = 'application/json';
    APPLICATION_JSON_UTF8 = APPLICATION_JSON + DELIM_PARAMS + CHARSET_UTF8_DEF;

    APPLICATION_XML = 'application/xml';
    APPLICATION_XML_UTF8 = APPLICATION_XML + DELIM_PARAMS + CHARSET_UTF8_DEF;

    APPLICATION_OCTET_STREAM = 'application/octet-stream';
    APPLICATION_FORM_URLENCODED_TYPE = 'application/x-www-form-urlencoded';
    MULTIPART_FORM_DATA = 'multipart/form-data';
    WILDCARD = '*/*';
  end;

  TCrossHttpUtils = class
  private const
    RFC1123_StrWeekDay: string = 'MonTueWedThuFriSatSun';
    RFC1123_StrMonth  : string = 'JanFebMarAprMayJunJulAugSepOctNovDec';
  public
    class function GetHttpStatusText(const AStatusCode: Integer): string; static;
    class function GetFileMIMEType(const AFileName: string): string; static;
    class function RFC1123_DateToStr(const ADate: TDateTime): string; static;
    class function RFC1123_StrToDate(const ADateStr: string): TDateTime; static;
    class function CombinePath(const APath1, APath2: string): string; static;
  end;

implementation

{ TCrossHttpUtils }

class function TCrossHttpUtils.GetHttpStatusText(const AStatusCode: Integer): string;
var
  LItem: THttpStatus;
begin
  for LItem in STATUS_CODES do
    if (LItem.Code = AStatusCode) then Exit(LItem.Text);
  Result := AStatusCode.ToString;
end;

class function TCrossHttpUtils.CombinePath(const APath1,
  APath2: string): string;
var
  LPath1Ends, LPath2Starts: string;
begin
  if (APath1 = '') then Exit(APath2);
  if (APath2 = '') then Exit(APath1);

  LPath1Ends := APath1.Substring(APath1.Length - 1, 1);
  LPath2Starts := APath2.Substring(0, 1);
  if (LPath1Ends = '/') and (LPath2Starts = '/') then
    Result := APath1 + APath2.Substring(1)
  else if (LPath1Ends = '/') and (LPath2Starts <> '/') then
    Result := APath1 + APath2
  else if (LPath1Ends <> '/') and (LPath2Starts = '/') then
    Result := APath1 + APath2
  else
    Result := APath1 + '/' + APath2;
end;

class function TCrossHttpUtils.GetFileMIMEType(const AFileName: string): string;
var
  I: Integer;
  LExt: string;
begin
  LExt := ExtractFileExt(AFileName).Substring(1);
  for I := 0 to High(MIME_TYPES) do
    if (CompareText(MIME_TYPES[I].Key, LExt) = 0) then
      Exit(MIME_TYPES[I].Value);
  Result := TMediaType.APPLICATION_OCTET_STREAM;
end;

class function TCrossHttpUtils.RFC1123_DateToStr(const ADate: TDateTime): string;
var
  Year, Month, Day       : Word;
  Hour, Min,   Sec, MSec : Word;
  DayOfWeek              : Word;
begin
  DecodeDate(ADate, Year, Month, Day);
  DecodeTime(ADate, Hour, Min,   Sec, MSec);
  DayOfWeek := ((Trunc(aDate) - 2) mod 7);
  Result := Copy(RFC1123_StrWeekDay, 1 + DayOfWeek * 3, 3) + ', ' +
    Format('%2.2d %s %4.4d %2.2d:%2.2d:%2.2d GMT',
      [Day, Copy(RFC1123_StrMonth, 1 + 3 * (Month - 1), 3),
      Year, Hour, Min, Sec]);
end;

class function TCrossHttpUtils.RFC1123_StrToDate(const ADateStr: string) : TDateTime;
var
  Year, Month, Day : Word;
  Hour, Min,   Sec : Word;
begin
  if (ADateStr = '') then Exit(0);

  { Fri, 30 Jul 2004 10:10:35 GMT }
  Day    := StrToIntDef(Copy(ADateStr, 6, 2), 0);
  Month  := (Pos(Copy(ADateStr, 9, 3), RFC1123_StrMonth) + 2) div 3;
  Year   := StrToIntDef(Copy(ADateStr, 13, 4), 0);
  Hour   := StrToIntDef(Copy(ADateStr, 18, 2), 0);
  Min    := StrToIntDef(Copy(ADateStr, 21, 2), 0);
  Sec    := StrToIntDef(Copy(ADateStr, 24, 2), 0);
  Result := EncodeDate(Year, Month, Day);
  Result := Result + EncodeTime(Hour, Min, Sec, 0);
end;

end.
