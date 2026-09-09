---
description: "Slack 봇 토큰 1회 설정 — private repo에서 자동 조회(토큰 입력 불필요). gh 인증=조직 멤버만 접근. Notion·Drive 는 팀 토큰이 아님(각자 계정)."
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/auth.sh:*)", "Bash(gh:*)"]
---

Slack 동기화에 쓰는 **팀 공용 봇 토큰(AX-E)** 을 이 PC에 1회 설정합니다. **토큰을 직접 입력할 필요 없이** 가져옵니다(이미 GitHub 로그인되어 있으면 끝).

> 보통은 `/ax:setup` 이 이 단계까지 자동으로 수행하므로 이 명령을 따로 부를 필요는 없습니다. 토큰이 빠졌거나 회전됐을 때 쓰세요.

> **Notion 과 Google Drive 는 여기서 다루지 않습니다 (v1.21.0).** Claude Code 계정이 개인 단위이므로
> Notion 게시는 **로그인한 사용자의 claude.ai Notion 커넥터**(각자 1회 연동, `/mcp` 로 확인)가 하고,
> Google Drive 는 **rclone(사용자 본인 Google 계정)** 이 합니다. 팀 자격증명은 Slack 봇 토큰 하나뿐이며,
> secrets repo 에 다른 키가 남아 있어도 읽는 코드가 없습니다.

## 기본 — 자동 가져오기
```!
bash ${CLAUDE_PLUGIN_ROOT}/scripts/auth.sh fetch
```
- 토큰은 배포 zip에 들어있지 않고, **private repo(`<your-org>/proj-sync-secrets`)에 보관**되어 **조직 멤버(gh 로그인)만** 가져올 수 있습니다.
- 가져온 토큰은 `~/.proj-sync/credentials`(본인 PC, 0600)에 1회 캐시 → 모든 프로젝트에서 자동 사용. **커밋 위험 없음**(어떤 repo 밖).

판정은 **Slack 봇 토큰 하나**입니다(`✓ Slack 봇 토큰`). 없으면 종료코드 1.

현재 상태만 보려면:
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/auth.sh show
```

## 실패 시
- "gh 로그인 필요" → 사용자에게 `gh auth login` 안내(브라우저 인증) 후 다시 fetch.
- 접근 권한 없음 → 관리자에게 `ax-harness` org 멤버 추가 요청. 확인: `gh api user/memberships/orgs/ax-harness --jq .state`
- **조직이 classic PAT(`ghp_`)을 차단하는 경우** → fine-grained PAT 을 키체인에 등록하면 자동 승계됩니다(macOS):
  ```
  security add-generic-password -a "$USER" -s github-fine-grained-token -w '<github_pat_…>' -U
  ```
  탐색 서비스명은 `PS_GH_TOKEN_KEYCHAIN` 으로 바꿀 수 있습니다(기본: `github-fine-grained-token github-token-ax-harness`).
- 정 안 되면 수동(관리자에게 토큰 1회 전달받아): `bash ${CLAUDE_PLUGIN_ROOT}/scripts/auth.sh set xoxb-…` — 캐시의 다른 키는 보존됩니다.

## 참고
- 토큰 해석 순서: 환경변수 → 프로젝트 `.env` → `~/.proj-sync/credentials` → private 자동 fetch(gh 기본 인증 → 키체인 fine-grained PAT).
- `/ax:setup`·`/ax:init`·`/ax:doctor`·`/ax:sync`(Slack 단계)가 토큰이 없으면 **자동으로 이 fetch를 시도**하므로, 보통은 이 명령을 따로 부를 필요도 없습니다.
- Notion 은 `/ax:auth` 와 무관합니다 — 게시는 각자의 claude.ai Notion 커넥터가 하며, 팀 REST 경로는 v1.21.0 에서 삭제됐습니다.
- 토큰 회전(보안 사고 등): 관리자가 `proj-sync-secrets` 의 `credentials` 1곳만 교체하면 전원에 반영됩니다(각자 `/ax:auth` 재캐시).
