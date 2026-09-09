---
description: "사전 도구(git·curl·gh·Git LFS·Python) 점검 + GitHub 로그인 확인 + Slack 팀 토큰 자동 조회 (머신당 1회). Notion·Drive 는 각자 계정."
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh:*)", "Bash(gh auth login:*)"]
---

이 PC에 proj-sync 실행에 필요한 사전 도구가 갖춰졌는지 점검하고, **이어서 Slack 팀 토큰까지 한 번에 확보**합니다 (프로젝트 설정 전, 머신당 1회).

```!
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh
```

결과를 보고:
- **도구 ✓ + 토큰 ✓ 이면** → 바로 `/ax:start`(기존 합류) 또는 `/ax:init`(신규)으로 진행하라고 안내. **토큰 입력 단계는 없습니다.**
  - 출력의 `ℹ Notion` / `ℹ Google Drive` 는 안내입니다(v1.21.0): Notion 은 **각자 claude.ai Notion 커넥터 1회 연동**(`/mcp` 로 확인), Google Drive 는 **rclone(본인 Google 계정)** — 회사 계정이면 사업 폴더에서 `/ax:doctor` 가 안내하는 `setup-remote` 1회.
- **"GitHub 로그인 필요"가 나오면** → `gh auth login` 을 실행하도록 안내하고(브라우저 인증이라 Claude가 대신할 수 없음), 끝나면 `/ax:setup` 재실행. 재실행 시 Slack 토큰이 자동으로 조회됩니다.
- **"Slack 봇 토큰 조회 실패"가 나오면** → 출력된 ↳ 안내 순서대로 조치:
  1. `gh api user/memberships/orgs/ax-harness --jq .state` 로 조직 멤버십 확인
  2. 조직이 classic PAT(`ghp_`)을 차단하는 경우 fine-grained PAT 을 키체인에 등록하면 자동 승계됨
  3. 그래도 안 되면 `/ax:auth` → 수동 저장
- **✗(누락)이 있으면** → VS Code + Claude Code 환경에서는 **직접 설치해 충족시키는 것을 기본으로** 합니다(안내만 하지 말 것):
  - **macOS**: 누락 도구를 **바로 자동 설치 제안** → 사용자가 동의하면 실행(권한 프롬프트가 곧 동의):
    ```
    bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh --install
    ```
    - 이 명령이 누락분(gh·git-lfs·python 등)을 Homebrew로 설치하고 `git lfs install`(LFS 훅 등록)까지 처리합니다.
    - **Homebrew 자체가 없으면**: 설치 스크립트는 sudo 비밀번호가 필요해 Claude가 대신 입력할 수 없습니다 → 사용자에게 아래 한 줄을 **직접 터미널에 붙여넣어 실행**하도록 안내하고, 끝나면 `--install` 재시도:
      ```
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      ```
  - **Linux**: 동의 시 패키지매니저로 직접 설치(예: `sudo apt install -y git-lfs gh python3 && git lfs install`). sudo 비밀번호가 필요하면 사용자에게 실행을 안내.
  - **Windows(Git Bash)**: 자동 설치 대신 안내된 링크로 직접 설치하도록 설명. 모든 스크립트는 **Git Bash** 에서 실행.

설치 후 `/ax:setup` 재실행으로 모두 ✓ 인지 확인하세요.
