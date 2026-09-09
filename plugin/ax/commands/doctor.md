---
description: "proj-sync 프리플라이트 — GitHub/Slack/LFS/Notion 인증·scope 점검 (누락 도구는 자동 설치 제안)"
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh:*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh:*)", "Bash(gh:*)", "Bash(git:*)"]
---

프로젝트 동기화 전 도구·인증을 점검합니다.

```!
bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh
```

> doctor 는 점검 전에 **config 마이그레이션을 자동 적용**합니다(v1.16.0~) — 없는 키·스캐폴드만 추가하고 기존 값은 건드리지 않습니다. 그래서 팀원은 플러그인만 업데이트하면 되고 **재init 이 필요 없습니다**. 적용한 항목은 출력에 남습니다. 끄려면 `PS_NO_MIGRATE=1`.
> `ℹ 플러그인 사본이 낡았습니다` 가 뜨면 `claude plugin update ax@ax-harness` 를 실행하도록 안내하세요 — 낡은 사본으로 init 하면 스캐폴드가 통째로 빠집니다.
> v1.17.0~ 부터 이 마이그레이션이 **`CLAUDE.md`(프로젝트 지침)와 `reference/9원칙.md`(원칙 본문)도 생성**합니다. **기존 사업이 9원칙을 받는 경로는 이 doctor 뿐**입니다 — 신규 사업만 `/ax:init` 으로 받습니다. 생성됐다면 사용자에게 **`CLAUDE.md` 의 프로젝트별 슬롯 5개**(1순위 정의·회귀 게이트·SSOT 위치·자원 격리·레슨 로그)를 채우도록 안내하세요. 비워 두면 원칙이 절반만 작동합니다.
> 출력에 `⚠ 스캐폴드 실패` 가 보이면 **조용히 넘기지 마세요** — 사유(템플릿 누락·권한)가 함께 찍힙니다. 대개 낡은/깨진 사본이므로 `claude plugin update` 후 재실행이 답입니다.

✗ 항목이 있으면 **유형에 따라** 처리하세요. VS Code + Claude Code 환경이므로 **설치로 해결되는 건 직접 설치**합니다(안내만 하고 끝내지 말 것):

- **도구 미설치**(Git LFS·gh·Python 등) → **자동 설치 제안**. 사용자 동의 시 바로 실행 후 doctor 재점검:
  ```
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --install      # macOS(Homebrew): 누락분 일괄 설치 + git lfs install
  ```
  - Homebrew 자체가 없으면(sudo 필요) 사용자에게 Homebrew 설치 한 줄을 직접 실행하도록 안내 후 재시도. Linux는 `sudo apt install -y …`, Windows는 Git Bash + 링크 설치.
- **GitHub 로그인 필요** → 사용자에게 `gh auth login` 실행 안내(브라우저 인증, Claude가 대신 못 함).
- **Slack 봇 토큰 미설정** → `gh auth login` 후 `/ax:auth`(secrets repo 자동 조회). 정 안 되면 `.env` 의 `PROJ_SYNC_SLACK_BOT_TOKEN=` 에 `xoxb-…` 입력 안내(자격증명이라 사용자가 입력).
- **Notion 커넥터(개인 OAuth)** → 게시는 로그인한 사용자의 claude.ai Notion 커넥터가 합니다(v1.21.0 — 팀 REST 경로 없음). 이 세션에서 `mcp__claude_ai_Notion__notion-fetch` 로 `config.notion.data_source_id` 를 열어 접근을 확인하세요. 도구 자체가 없으면 커넥터 미연동 → claude.ai 커넥터 설정(각자 1회, `/mcp` 로 확인) 안내. 열리지만 쓰기 권한이 없을 수 있으므로 게시 실패 시 문서함 편집 권한 요청을 안내. doctor.sh 가 `provider=notion_api 잔존` ✗ 를 내면 config 에서 그 키를 지우도록 안내하세요.
- **Slack 커넥터(개인 OAuth · 선택)** → 이 세션에 `mcp__claude_ai_Slack__*` 도구(예: `slack_search_channels`)가 보이는지 확인하세요. 없으면 claude.ai Slack 커넥터 미연동 — `/mcp` 에서 연결을 안내합니다(개인 명의 조회·인박스 보조용 선택 기능. AX-E 봇 발신 `slack_post.sh` 와는 별개라 doctor.sh 의 봇 토큰 ✓ 에 영향 없음).
- **Google Drive E13(remote 미설정)** → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/gdrive_sync.sh setup-remote` 를 사용자가 실행(본인 Google 계정 · 브라우저 인증 1회, Claude 가 대신 못 함). **E12(조직 정책 차단)** → Workspace 관리자에게 rclone(서드파티 앱) 허용을 요청해야 합니다 — 재인증·재생성으로는 풀리지 않습니다.

조치 후 `/ax:doctor` 를 재실행해 모두 ✓ 인지 확인하세요.
