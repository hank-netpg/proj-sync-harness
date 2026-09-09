---
description: "수행 프로젝트 합류 — 레지스트리에서 기존 프로젝트 선택 → repo clone → 동기화 → 업무 시작 (팀원 온보딩)"
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/registry.sh:*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh:*)", "Bash(cd:*)", "Bash(gh:*)"]
---

AX실원이 **기존 수행 프로젝트에 합류**하는 온보딩 흐름입니다. 빈 작업 폴더에서 실행하세요. (완전히 새 사업을 *시작*하는 PM은 `/ax:init` 사용)

## 1단계 — 레지스트리에서 프로젝트 선택 (목록 자동 출력)
```!
bash ${CLAUDE_PLUGIN_ROOT}/scripts/registry.sh list
```
위 목록을 사용자에게 보여주고 합류할 프로젝트의 `id` 를 고르게 하세요. (목록에 없으면 새 사업 → `/ax:init` B 경로)

## 2단계 — repo clone (config·문서 일괄 확보)
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/registry.sh clone <id>
```
- GitHub repo가 clone되며 **`.proj-sync/config.json`(설정)과 텍스트 산출물**이 함께 받아집니다 → 별도 init 불필요.
- 폴더명은 repo 이름으로 생성됩니다(다른 이름은 `clone <id> <dir>`).
- clone 후 사용자에게 **해당 폴더를 VS Code로 열도록** 안내하세요.

## 3단계 — 자격증명 (토큰 입력 불필요)
- **GitHub**: `gh auth login` 1회(브라우저). 레지스트리·clone·push·**Slack 토큰 자동조회**까지 공용.
- **Slack 봇 토큰**: 직접 입력하지 않습니다. `/ax:auth`(또는 doctor/sync가 자동)가 private repo에서 가져와 `~/.proj-sync/credentials`에 캐시 → 조직 멤버면 끝.
  - 자동조회가 막히면(권한 등) `/ax:auth` 안내를 따르거나, 관리자에게 토큰 1회 전달받아 `auth.sh set xoxb-…`.
- **Notion**: 입력할 토큰이 없습니다 — 게시는 **본인의 claude.ai Notion 커넥터**(각자 1회 연동, `/mcp` 로 확인)가 합니다.
- **Google Drive**: rclone(본인 Google 계정) — 사업 폴더에서 `gdrive_sync.sh setup-remote` 1회(브라우저 인증). 미설정이면 `/ax:doctor` 가 안내합니다.

## 4단계 — 검증 & 동기화
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh     # 인증·도구 점검 (모두 ✓ 확인)
```
이어서 **`/ax:sync`** 로 Slack 최신 파일까지 받아 최신화하면 **업무 시작 준비 완료**입니다.

> ⚠️ 대용량 바이너리(slack-files·발표자료)는 하이브리드 정책상 GitHub가 아닌 Google Drive/Slack에 있습니다. clone은 텍스트 SSOT를 받고, 필요한 첨부는 `/ax:sync`(slack-pull)로 받습니다.

## 요약(사용자 안내용)
1. `/ax:setup` (도구 1회 점검) → 2. **`/ax:start`** (이 명령: 선택→clone) → 3. `/ax:auth`(자동 — 입력 없음) → 4. `/ax:doctor` → 5. `/ax:sync` → **업무 시작**
