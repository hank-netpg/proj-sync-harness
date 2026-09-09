#!/usr/bin/env bash
# proj-sync: GitHub 동기화 (LFS 설정 → secret-scan → commit → repo 생성/push)
# 사용: github_push.sh ["커밋 메시지"]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"
ps_load_config || exit 1
cd "$PS_ROOT"

command -v gh >/dev/null 2>&1 || { echo "[proj-sync] gh CLI 미설치. cli.github.com"; exit 1; }
# 인증 판정은 실제 API 호출로 — `gh auth status` 는 등록된 계정 중 **하나라도** 토큰이 만료면
#   exit 1 을 내므로, 활성 계정이 멀쩡해도 push 가 통째로 막혔다(2026-08-07 실측).
gh api user --jq .login >/dev/null 2>&1 || { echo "[proj-sync] gh 미인증(또는 활성 계정 토큰 만료). 'gh auth login' 먼저 — 계정이 여럿이면 'gh auth switch' 로 활성 계정 확인."; exit 1; }

# config 3개 값을 python 1회 호출로 모음
{ IFS= read -r ORG; IFS= read -r REPO; IFS= read -r VIS; } \
  < <(ps_cfg_get '.github.org' '.github.repo' '.github.visibility')
[ -z "$VIS" ] && VIS="private"
# 기본 메시지도 커밋 규약을 따른다 — 종전 `proj-sync: 동기화 …` 는 Conventional Commits
# 의 type 이 아니었고, 사업 저장소의 동기화 커밋 전부가 그 형태였다.
#   근거: Conventional Commits v1.0.0 · 상세는 플러그인 루트 COMMIT_CONVENTION.md
MSG="${1:-chore(sync): 동기화 $(date +%Y-%m-%d)}"

# LFS 설정 (멱등)
bash "$HERE/github_setup_lfs.sh"

# .gitignore 보장 (.env 등 시크릿 제외)
if [ ! -f "$PS_ROOT/.gitignore" ]; then
  cp "$HERE/../templates/gitignore.template" "$PS_ROOT/.gitignore" 2>/dev/null || true
fi
grep -q '^\.env$' "$PS_ROOT/.gitignore" 2>/dev/null || echo ".env" >> "$PS_ROOT/.gitignore"
grep -q '^\.proj-sync/state.json$' "$PS_ROOT/.gitignore" 2>/dev/null || echo ".proj-sync/state.json" >> "$PS_ROOT/.gitignore"

# ── 정책: GitHub = 마크다운(.md)·소스코드만. 사무파일(hwp/doc/ppt/xls/pdf 등)은 Google Drive 전담 → .gitignore 제외 ──
OFFICE_EXTS="$(ps_cfg '.github.office_exts')"
if [ -n "$OFFICE_EXTS" ] && [ "$OFFICE_EXTS" != "[]" ]; then
  if ! grep -q '# proj-sync: 사무파일은 Google Drive' "$PS_ROOT/.gitignore" 2>/dev/null; then
    echo "" >> "$PS_ROOT/.gitignore"
    echo "# proj-sync: 사무파일은 Google Drive(대용량 저장소)로 — GitHub 에는 .md·소스만" >> "$PS_ROOT/.gitignore"
    printf '%s' "$OFFICE_EXTS" | "$PS_PY" -c "import json,sys
for e in json.load(sys.stdin): print('*.'+e); print('*.'+e.upper())" >> "$PS_ROOT/.gitignore" 2>/dev/null || true
  fi
fi

[ -d .git ] || git init -q
git branch -M main 2>/dev/null || true

# ── 원격 최신 반영(pull --rebase): 다른 팀원이 먼저 push 했을 때 non-fast-forward 로
#    push 가 거부되는 것을 방지. 원격/​main 이 있을 때만 시도, 충돌 시 중단(수동 해결). ──
if git remote get-url origin >/dev/null 2>&1 \
   && git ls-remote --heads origin main 2>/dev/null | grep -q .; then
  echo "[proj-sync] 원격 최신 반영: git pull --rebase origin main"
  git pull --rebase --autostash origin main \
    || { echo "[proj-sync] ⚠️ git pull --rebase 충돌 → 수동 해결 후 재시도."; exit 1; }
fi

git add -A

# ── secret-scan: staged 파일에 토큰 패턴 있으면 중단 ──
LEAK="$(git diff --cached --name-only | while read -r f; do
  [ -f "$f" ] || continue
  if grep -lE 'xox[baprse]-[0-9A-Za-z-]{10,}|xapp-[0-9A-Za-z-]{10,}|gh[pousr]_[0-9A-Za-z]{20,}|github_pat_[0-9A-Za-z_]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|ntn_[0-9A-Za-z]{40,}|secret_[0-9A-Za-z]{40,}' "$f" >/dev/null 2>&1; then echo "$f"; fi
done)"
if [ -n "$LEAK" ]; then
  echo "[proj-sync] ⚠️ 시크릿 추정 패턴 발견 → push 중단. 해당 파일:"; echo "$LEAK"
  echo "→ .gitignore 에 추가하거나 토큰을 제거 후 재시도."
  exit 1
fi

# ── revision/history.md 미갱신 경고 (세션 연속성) ────────────────────────
# 다른 머신·다른 팀원이 이어받을 근거는 history.md 뿐이다(SessionStart 훅이 이걸 주입한다).
# 오늘 한 일이 안 적히면 다음 사람은 커밋 제목만 보고 추측해야 한다.
#
# **차단하지 않는다.** 동기화를 막으면 팀원이 플러그인을 끈다 — version_notice.sh 와 같은 판단이다.
# **사람이 쓴 변경이 있을 때만** 말한다. slack-files·_extracted·인벤토리·.proj-sync 만 바뀐
#   기계적 동기화까지 매번 경고하면 사람이 무시하는 법을 배운다.
# -c core.quotepath=false: 없으면 한글 경로가 "\354\204\244…" 로 나와 사람이 못 읽는다.
HUMAN_CHANGES="$(git -c core.quotepath=false diff --cached --name-only | grep -vE '^(slack-files/|reference/_extracted/|FILE_INVENTORY\.csv$|\.proj-sync/)' | head -5)"
if [ -n "$HUMAN_CHANGES" ] && [ -f "$PS_ROOT/revision/history.md" ]; then
  if ! grep -q "^## $(date +%Y-%m-%d)" "$PS_ROOT/revision/history.md" 2>/dev/null; then
    echo "[proj-sync] ℹ️ revision/history.md 에 오늘($(date +%Y-%m-%d)) 항목이 없습니다 — 다음 사람이 이어받을 근거가 비어 있습니다."
    echo "$HUMAN_CHANGES" | sed 's/^/     · /'
    echo "     ↳ 한 일을 2~3줄 적어두세요:  /ax:revision   (또는 revision/history.md 에 '## $(date +%Y-%m-%d)' 절 추가)"
  fi
fi

# ── 사본 버전을 커밋에 남긴다 (issue #19) ────────────────────────────────
# 「누가·언제」는 git 이 이미 남긴다. 없는 것은 **「어느 사본으로」** 다.
#   _init.plugin_version(#14)은 init·migrate 시점만 기록하므로, 동기화만 하는 팀원의 사본은
#   알 길이 없다. 팀장이 마이그레이션을 일괄 적용하면 전 사업 _init 이 같은 값으로 덮여
#   그마저도 무의미해진다(2026-08-09 실측: 17개 사업이 전부 1.16.0).
#
# 왜 파일이 아니라 커밋 메시지인가 —
#   상태 파일(.proj-sync/state.json)은 :29 에서 gitignore 되고, 커밋되는 파일에 쓰면
#   **매 동기화마다 그 파일이 바뀌어** 팀원 간 pull --rebase 충돌을 만든다.
#   트레일러는 새 파일이 없고 충돌 면이 없으며, git log 한 번으로 사람·시점·버전이 나온다.
#     git log --format='%an %ad %(trailers:key=ax-version,valueonly)'
PS_VER="$(ps_plugin_version)"
GH_LOGIN="$(gh api user --jq .login 2>/dev/null || true)"
# 트레일러는 본문과 빈 줄로 분리해야 git 이 트레일러로 인식한다.
# 사용자가 메시지를 인자로 준 경우에도 붙인다 — 기록의 목적이 「빠짐없이 남는 것」이므로.
COMMIT_MSG="$MSG

ax-version: $PS_VER
ax-by: ${GH_LOGIN:-unknown}"

# 규약 검사 — **경고만 한다. 막지 않는다.**
#   동기화를 막으면 팀원이 플러그인을 끈다(version_notice·history 알림과 같은 판단).
#   커밋 훅과 다른 이유: 여기서 막히면 사람이 고칠 대상은 메시지가 아니라 「동기화 자체」가
#   된다. 규약을 강제하는 자리는 commit-msg 훅과 PR 제목이다.
if [ -f "$HERE/lint_commit_msg.sh" ]; then
  printf '%s\n' "$MSG" | bash "$HERE/lint_commit_msg.sh" - >/dev/null 2>&1 || {
    echo "[proj-sync] ℹ️ 커밋 메시지가 규약과 다릅니다 — 커밋은 그대로 진행합니다."
    printf '%s\n' "$MSG" | bash "$HERE/lint_commit_msg.sh" - 2>&1 | sed 's/^/     /' || true
  }
fi

git diff --cached --quiet && { echo "[proj-sync] 변경 없음 (커밋 생략)"; } || git commit -q -m "$COMMIT_MSG"

# 원격 없으면 생성+push, 있으면 push
if git remote get-url origin >/dev/null 2>&1; then
  git push origin main
else
  gh repo create "$ORG/$REPO" --"$VIS" --source=. --remote=origin --push
fi
echo "[proj-sync] ✅ GitHub 동기화 완료: https://github.com/$ORG/$REPO"
