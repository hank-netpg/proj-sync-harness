#!/usr/bin/env bash
# proj-sync: Slack 봇 토큰 1회 설정 — 기본은 private repo에서 자동 가져오기(토큰 입력 불필요).
#   fetch        : hankeon/proj-sync-harness-secrets 에서 가져와 ~/.proj-sync/credentials 에 캐시 (gh 인증 필요)
#   set <xoxb-…> : 수동 입력값을 캐시에 저장 (자동이 막힐 때만). 캐시의 다른 키는 보존한다.
#   show         : 캐시 여부 확인
#
#   판정 대상은 **Slack 봇 토큰 하나**다(v1.21.0) — proj-sync 의 유일한 팀 자격증명.
#   Notion 게시는 로그인한 사용자의 claude.ai Notion 커넥터, Slack 개인 조회는 claude.ai Slack 커넥터,
#   Google Drive 는 rclone(본인 Google 계정)이 담당한다. 캐시에 다른 키가 남아 있어도 읽는 코드가 없다.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"

cmd="${1:-fetch}"; shift || true
case "$cmd" in
  fetch)
    if ps_fetch_team_token; then
      echo "[proj-sync] 팀 토큰을 가져와 저장했습니다 → $PS_GLOBAL_CRED"
      s="$(ps_global_token PROJ_SYNC_SLACK_BOT_TOKEN)"
      [ -n "$s" ] && echo "  ✓ Slack 봇 토큰" || echo "  ✗ Slack 봇 토큰 없음(secrets repo 에 키 부재)"
      echo "  이제 토큰 입력 없이 /ax:sync 가 동작합니다. Notion 게시는 각자의 claude.ai Notion 커넥터가 담당합니다."
      [ -n "$s" ] || exit 1
    else
      echo "[proj-sync] 자동 가져오기 실패." >&2
      echo "  · gh 로그인 확인:  gh auth login" >&2
      echo "  · 또는 $PS_SECRETS_REPO 접근 권한(ax-harness 멤버) 확인" >&2
      echo "  · 조직이 classic PAT(ghp_)을 차단하는 경우 fine-grained PAT 을 키체인에 등록:" >&2
      echo "      security add-generic-password -a \"\$USER\" -s github-fine-grained-token -w '<github_pat_…>' -U" >&2
      echo "  · 수동 저장:  bash auth.sh set xoxb-…" >&2
      exit 1
    fi
    ;;
  set)
    tok="${1:-}"; [ -z "$tok" ] && { printf '봇 토큰(xoxb-…) 붙여넣기: '; read -r tok; }
    if [ "${tok#xoxb-}" = "$tok" ]; then echo "[proj-sync] xoxb- 로 시작하는 봇 토큰이 아닙니다." >&2; exit 1; fi
    ps_cred_set PROJ_SYNC_SLACK_BOT_TOKEN "$tok"
    echo "[proj-sync] 토큰을 저장했습니다 → $PS_GLOBAL_CRED (다른 키는 보존)"
    ;;
  show|status)
    s="$(ps_global_token PROJ_SYNC_SLACK_BOT_TOKEN)"
    if [ ! -f "$PS_GLOBAL_CRED" ]; then
      echo "[proj-sync] 캐시 없음 — bash auth.sh fetch 실행"; exit 1
    fi
    echo "[proj-sync] 캐시: $PS_GLOBAL_CRED"
    [ -n "$s" ] && echo "  ✓ Slack 봇 토큰   ${s:0:10}…" || echo "  ✗ Slack 봇 토큰 없음"
    [ -n "$s" ] || exit 1
    ;;
  *) echo "사용: auth.sh fetch | set <xoxb-…> | show" >&2; exit 1 ;;
esac
