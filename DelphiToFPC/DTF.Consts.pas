unit DTF.Consts;

{$I zLib.inc}

interface

resourcestring
  SInvalidSourceArray = 'Invalid source array';
  SInvalidCharCount = 'Invalid count (%d)';
  SNoMappingForUnicodeCharacter = 'No mapping for the Unicode character exists in the target multi-byte code page';

  { System.NetEncoding }
  sErrorDecodingURLText = 'Fehler beim Decodieren eines im URL-Stil (%%XX) codierten Strings bei Position %d';
  sInvalidURLEncodedChar = 'Ungültiges URL-codiertes Zeichen (%s) an Position %d';
  sInvalidHTMLEncodedChar = 'Ungültiges HTML-codiertes Zeichen (%s) an Position %d';

  SArgumentNil = 'Argument must not be nil';
  sArgumentOutOfRange_NeedNonNegValue = 'Argument, %s, must be >= 0';
  sArgumentOutOfRange_OffLenInvalid = 'Offset and length are invalid for the given array';

  SParamIsNil = 'Parameter %s cannot be nil';

  SInsufficientReadBuffer = 'Insufficient buffer for requested data';
  SInvalid7BitEncodedInteger = 'Invalid 7 bit integer stream encoding';
  SReadPastEndOfStream = 'Attempt to read past end of stream';
  SInvalidStringLength = 'Invalid string length';
  SNoSurrogates = 'Surrogates not allowed as a single char';

const
  INFINITE = Cardinal(-1);

implementation

end.

