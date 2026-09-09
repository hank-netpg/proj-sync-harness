#!/usr/bin/env bash
# proj-sync lib: 사본 ↔ 릴리즈 최신 버전 판정 (issue #18)
#
# 왜 lib 인가 —
#   종전에는 이 판정이 doctor.sh 0.2절에만 있었다. 훅(hooks/version_notice.sh)이 같은 일을
#   해야 하는데 로직을 한 벌 더 만들면 **곧 갈린다**(원칙: 판정 지식은 한 곳에).
#   doctor 와 훅이 이 파일을 함께 쓴다.
#
# 전제: lib/config.sh 가 먼저 source 되어 ps_plugin_root·ps_plugin_version 이 있어야 한다.

PS_PLUGIN_REPO_DEFAULT="hankeon/proj-sync-harness"

# 캐시 위치 — 세션마다 GitHub API 를 때리면 레이트리밋에 걸린다.
ps_release_cache_file() {
  local d="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/ax}"
  mkdir -p "$d" 2>/dev/null || true
  echo "$d/release_check"
}

# gh 호출이 세션을 붙잡지 못하게 한다. macOS 에는 coreutils 의 timeout 이 없을 수 있어
# gtimeout → timeout → (없으면) 그대로 순으로 고른다. 훅에서 이게 없으면 오프라인 상태에서
# 세션 시작이 늘어질 수 있다.
_ps_run_limited() {
  local secs="$1"; shift
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"
  elif command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"
  else "$@"; fi
}

# 릴리즈 최신 버전을 얻는다. 못 얻으면 **빈 문자열**(오류가 아니라 「모름」).
#   $1 = 캐시 TTL(초). 0 이면 캐시를 쓰지 않는다(doctor 는 0 — 진단은 항상 실측).
#   PS_PLUGIN_REPO 로 대상 저장소를 바꿀 수 있다.
ps_latest_release_version() {
  local ttl="${1:-86400}" repo cache now stamp ver
  repo="${PS_PLUGIN_REPO:-$PS_PLUGIN_REPO_DEFAULT}"
  cache="$(ps_release_cache_file)"
  now="$(date +%s)"

  if [ "$ttl" -gt 0 ] && [ -f "$cache" ]; then
    IFS=$'\t' read -r stamp ver < "$cache" 2>/dev/null
    case "$stamp" in ''|*[!0-9]*) stamp=0 ;; esac
    if [ $((now - stamp)) -lt "$ttl" ]; then echo "$ver"; return 0; fi
  fi

  # gh 미설치·미인증·오프라인이면 조용히 「모름」. 판정을 못 한다고 호출부를 막지 않는다.
  command -v gh >/dev/null 2>&1 || { echo ""; return 0; }
  _ps_run_limited 5 gh api user --jq .login >/dev/null 2>&1 || { echo ""; return 0; }
  ver="$(_ps_run_limited 5 gh api "repos/$repo/releases/latest" --jq .tag_name 2>/dev/null | sed 's/^v//')"

  # 조회에 실패했으면 캐시를 쓰지 않는다 — 빈 값을 캐시하면 하루 동안 판정이 죽는다.
  [ -n "$ver" ] && printf '%s\t%s\n' "$now" "$ver" > "$cache" 2>/dev/null
  echo "$ver"
}

# 실행 사본과 릴리즈를 비교해 한 낱말로 답한다.
#   current  = 같음 · outdated = 사본이 낡음 · ahead = 사본이 앞섬(미배포 개발본) · unknown = 판정 불가
ps_version_state() {
  local run="$1" latest="$2"
  if [ -z "$run" ] || [ "$run" = "unknown" ] || [ -z "$latest" ]; then echo "unknown"; return 0; fi
  if [ "$run" = "$latest" ]; then echo "current"; return 0; fi
  if [ "$(printf '%s\n%s\n' "$run" "$latest" | sort -V | head -1)" = "$run" ]; then
    echo "outdated"
  else
    echo "ahead"
  fi
}
