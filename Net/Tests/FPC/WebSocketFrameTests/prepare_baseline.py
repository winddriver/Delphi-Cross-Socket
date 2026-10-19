"""从固定 Git 基线导出基准所需源码到忽略目录，不切换工作区。"""
from pathlib import Path, PurePosixPath
import subprocess,tarfile,io
T=Path(__file__).resolve().parent; R=T.parents[3]
REF='a2447766434b560e9265f92752e6ff2b3ca9e382'
def prepare():
    dest=T/'bin/baseline'; marker=dest/'.revision'
    if dest.exists():
        if not marker.exists() or marker.read_text().strip()!=REF:
            raise RuntimeError('基线目录已存在但版本标记不符，请另行保存该目录后重试')
        return dest
    data=subprocess.check_output(['git','archive',REF,'Net','Utils','DelphiToFPC','zLib.inc'],cwd=R)
    dest.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for item in archive:
            rel=PurePosixPath(item.name)
            if not item.isfile() or rel.is_absolute() or '..' in rel.parts:continue
            if rel.suffix.lower() not in ('.pas','.inc'):continue
            if any(part in ('Demos','Tests','Tools','bin','lib','__history') for part in rel.parts[:-1]):continue
            path=dest.joinpath(*rel.parts)
            if not path.resolve().is_relative_to(dest.resolve()):raise RuntimeError('无效基线路径')
            path.parent.mkdir(parents=True,exist_ok=True)
            with path.open('xb') as f:f.write(archive.extractfile(item).read())
    marker.write_text(REF+'\n',encoding='utf-8')
    return dest
if __name__=='__main__':print(prepare())
