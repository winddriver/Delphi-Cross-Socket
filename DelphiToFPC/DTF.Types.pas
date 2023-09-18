unit DTF.Types;

{$I zLib.inc}

interface

uses
  Classes,
  SysUtils;

type
  TProc = reference to procedure;
  TProc<T> = reference to procedure (Arg1: T);
  TProc<T1, T2> = reference to procedure (Arg1: T1; Arg2: T2);
  TProc<T1, T2, T3> = reference to procedure (Arg1: T1; Arg2: T2; Arg3: T3);
  TProc<T1, T2, T3, T4> = reference to procedure (Arg1: T1; Arg2: T2; Arg3: T3; Arg4: T4);

  TFunc<TResult> = reference to function: TResult;
  TFunc<T, TResult> = reference to function (Arg1: T): TResult;
  TFunc<T1, T2, TResult> = reference to function (Arg1: T1; Arg2: T2): TResult;
  TFunc<T1, T2, T3, TResult> = reference to function (Arg1: T1; Arg2: T2; Arg3: T3): TResult;
  TFunc<T1, T2, T3, T4, TResult> = reference to function (Arg1: T1; Arg2: T2; Arg3: T3; Arg4: T4): TResult;

implementation

end.

