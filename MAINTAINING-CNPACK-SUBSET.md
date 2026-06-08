# Maintaining the bundled CnPack subset (boss-installability)

**Read this before touching `CnPack/`, releasing a new tag, or running the fork-sync.**

## Why this fork exists

`freitasjca/Delphi-Cross-Socket` is a fork of
[`winddriver/Delphi-Cross-Socket`](https://github.com/winddriver/Delphi-Cross-Socket)
whose **only reason to exist is to be installable with [Boss](https://github.com/HashLoad/boss)**
(the Delphi package manager). Two upstreams block that:

- **`winddriver/Delphi-Cross-Socket`** ships no `boss.json`.
- **CnPack / [`cnpack/cnvcl`](https://github.com/cnpack/cnvcl)** — a *dependency* of
  Delphi-Cross-Socket's SSL/crypto layer — also has no `boss.json` and is a huge repo.

So this fork adds (a) a `boss.json`, (b) the **minimal CnPack subset** that
Delphi-Cross-Socket actually needs, vendored under `CnPack/`, and (c) the mTLS additions
(`Net/Net.CrossSslSocket.{Base,OpenSSL}.pas`). A consumer (e.g.
[`horse-provider-crosssocket`](https://github.com/freitasjca/horse-provider-crosssocket))
can then `boss install` this fork and compile **without ever touching cnvcl**.

> The `boss.json` `description` currently says *"adds Boss package manifest only. Zero source
> changes"* — that is **stale**: the fork also vendors the CnPack subset and the mTLS patches.
> Update it when convenient.

## The invariant — what must always hold

The vendored subset **must be a complete, self-contained transitive closure** so the package
compiles standalone:

1. **`CnPack/Common/CnPack.inc` must be present.** Every Cn unit begins with `{$I CnPack.inc}`;
   without it nothing compiles.
2. **Every unit named in any `uses` clause of a bundled unit must also be bundled.** If you add
   a Crypto unit that pulls in a new `Cn*` dependency, that dependency has to be copied in too.
3. The split mirrors cnvcl's own layout: foundation units in `CnPack/Common/`, crypto in
   `CnPack/Crypto/`.

### Current inventory (18 files — keep this list and the fork-sync in step)

```
CnPack/Common/   CnPack.inc  CnConsts.pas  CnFloat.pas  CnStrings.pas  CnWideStrings.pas
CnPack/Crypto/   CnAES.pas  CnBase64.pas  CnDES.pas  CnKDF.pas  CnMD5.pas  CnNative.pas
                 CnPemUtils.pas  CnRandom.pas  CnSHA1.pas  CnSHA2.pas  CnSHA3.pas
                 CnSM3.pas  CnSM4.pas
```

> History: earlier releases kept everything under `CnPack/Crypto/` (14 units). cnvcl later
> moved the foundation units to `Source/Common/` and added `CnStrings`, `CnWideStrings`,
> `CnSM4`; the v1.0.3 re-sync follows that — hence the `Common/` directory.

## Re-syncing the subset when cnvcl updates

1. Update your local cnvcl: `cd cnvcl && git pull --ff-only origin master`.
2. Copy the units above from cnvcl into the fork:
   - `cnvcl/Source/Common/{CnPack.inc,CnConsts,CnFloat,CnStrings,CnWideStrings}` → `CnPack/Common/`
   - `cnvcl/Source/Crypto/{the 13 crypto units}.pas` → `CnPack/Crypto/`
   - (verify the cnvcl source-side paths — cnvcl occasionally relocates units between
     `Source/Common` and `Source/Crypto`.)
3. **Re-validate the closure** — the only authoritative check (the CnPack sources are
   **GBK/ANSI-encoded**, which defeats `grep`-based scans): `boss install` this fork into a
   throwaway project, or build `horse-provider-crosssocket` against it, and confirm a clean
   compile with **no missing `Cn*` unit**. If the compiler reports a missing unit, copy it in
   and repeat.
4. Commit the subset change on its own (`git add -A CnPack/` so renames register), separate
   from version bumps and `.gitattributes` changes.

## ⚠️ Keep the fork-sync automation in step — or it reverts the subset

The fork-sync (`crosssocket-fork-sync-action/` → deployed to the fork's `master` as a daily
GitHub Action) **resets `master` to upstream's tip and re-layers the CnPack subset from a
hardcoded list**. If that list doesn't match the inventory above, the next nightly run
**silently restores the wrong subset and breaks the boss build.** Two files must be updated
together with any subset change:

- `.github/workflows/sync-upstream.yml` — the `Clone CnPack (cnvcl) and copy required files`
  step (the actual `cp` list + the `mkdir CnPack/Common CnPack/Crypto`).
- `.sync/README.md` — the human-readable manifest table (fork path ← cnvcl source path).

Optionally pin `CNVCL_REF` in `sync-upstream.yml` to a validated cnvcl tag/sha instead of
`master`, so a surprise upstream cnvcl change can't break a nightly sync.

## Consumer-side note

Because the foundation units live in `CnPack/Common/`, any consuming project's search path must
include **both** `CnPack/Common` **and** `CnPack/Crypto` (see the "Required search paths" list
in `horse-provider-crosssocket`'s README). Adding only `Crypto/` will fail to resolve
`CnConsts`/`CnFloat`/`CnStrings`/`CnWideStrings`.

## Don't track build/IDE artifacts

`.dcu`, `.res`, `.dproj.local`, `.dsv`, `__history/` must stay out of the repo (they bloat it
and create false "modified" churn). They are covered by `.gitignore`; if any are already
tracked, `git rm --cached` them.

## Endgame

The mTLS additions are pending an upstream PR. Once upstream merges them **and** a boss-friendly
distribution of Delphi-Cross-Socket + CnPack exists, this fork (and this whole subset-maintenance
burden) can be retired. Until then, every cnvcl bump is a re-sync chore — keep this doc, the
inventory, and the fork-sync manifest aligned.
