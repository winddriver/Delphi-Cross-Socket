{$IFDEF FPC}
  {$UNDEF DELPHI}

  {$MODE DELPHI}
  {$MODESWITCH UNICODESTRINGS}

  {$MODESWITCH FUNCTIONREFERENCES}
  {$MODESWITCH ANONYMOUSFUNCTIONS}
  {$WARN 05036 OFF}// "Warning: (5036) Local variable "$Capturer" does not seem to be initialized"
  {$WARN 06058 OFF}// Call to subroutine "$1" marked as inline is not inlined}

  {$H+}

  {$IFNDEF MSWINDOWS}
    {$DEFINE POSIX}
  {$ENDIF}

  {$IFDEF CPU32}
    {$DEFINE CPU32BITS}
  {$ENDIF}

  {$IFDEF CPU64}
    {$DEFINE CPU64BITS}
  {$ENDIF}

  {$IFDEF ANDROID}
    {$IFDEF CPU32}
      {$DEFINE ANDROID32}
    {$ENDIF}
    {$IFDEF CPU64}
      {$DEFINE ANDROID64}
    {$ENDIF}
  {$ENDIF}

{$ELSE}
  {$DEFINE DELPHI}

  {$IFDEF CPU32BITS}
    {$DEFINE CPU32}
  {$ENDIF}

  {$IFDEF CPU64BITS}
    {$DEFINE CPU64}
  {$ENDIF}
{$ENDIF}

