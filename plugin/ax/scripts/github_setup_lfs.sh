#!/usr/bin/env bash
# proj-sync: Git LFS 설정 — config.github.lfs_extensions 로 .gitattributes 생성 + git lfs install
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"
ps_load_config || exit 1
cd "$PS_ROOT"

EXTS="$(ps_cfg '.github.lfs_extensions')"   # JSON 배열 문자열

# 정책: 사무파일은 Google Drive 전담 → 기본 lfs_extensions=[] (LFS 불필요). 빈 배열이면 git-lfs 없어도 graceful skip.
if [ -z "$EXTS" ] || [ "$EXTS" = "[]" ]; then
  echo "[proj-sync] LFS 대상 없음 (사무파일은 Google Drive 전담, GitHub=.md·소스만) — LFS 설정 생략"
  exit 0
fi
command -v git-lfs >/dev/null 2>&1 || { echo "[proj-sync] git-lfs 미설치. (mac: brew install git-lfs / win: git-lfs.github.com)"; exit 1; }

ATTR="$PS_ROOT/.gitattributes"
"$PS_PY" - "$EXTS" "$ATTR" <<'PY'
import json,sys
exts=json.loads(sys.argv[1] or "[]")
lines=["# Git LFS — proj-sync 자동 생성"]
for e in exts:
    lines.append(f"*.{e} filter=lfs diff=lfs merge=lfs -text")
open(sys.argv[2],"w").write("\n".join(lines)+"\n")
print("[proj-sync] .gitattributes 생성:", ", ".join(exts))
PY

[ -d "$PS_ROOT/.git" ] || git init -q
git lfs install --local 2>&1 | head -1
