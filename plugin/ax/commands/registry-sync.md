---
description: "수행 프로젝트 레지스트리 현행화 — Notion 수행 프로젝트 DB → GitHub registry.json 미러 재생성·push"
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/registry.sh:*)", "Bash(cd:*)", "Bash(git:*)", "Bash(python3:*)", "Bash(gh:*)"]
---

Notion **수행 프로젝트 DB**(사람용 SSOT)를 GitHub **`registry.json`**(기계용 미러)으로 동기화합니다. 프로젝트를 추가/수정/상태변경한 뒤 실행하세요.

## 절차
1. claude.ai Notion MCP로 수행 프로젝트 DB를 조회합니다.
   - data_source: `1c0806c9-66d1-438c-9969-8ac98e7398be` (DB명 "수행 프로젝트 DB")
   - `notion-fetch` 로 스키마 확인 후, 뷰를 `notion-query-database-view` 로 전체 행을 읽습니다.
2. 각 행을 registry.json 스키마로 매핑합니다(빈 값은 `null`/`[]`):
   ```jsonc
   { "id": project_id, "name": 프로젝트명, "team": 담당팀[], "client": 발주처,
     "status": 상태,   // Notion '상태' 6값: 제안 / 수주 / 수행중 / 완료 / 보류 / 실주 (= config.lifecycle.phase 도메인)
     "github": { "org":…, "repo":…, "visibility":"private" },   // github_repo "org/repo" 분해
     "slack":  { "team_id":…, "channel_id":… },                 // slack_ch "team/channel" 분해, 없으면 null
     "notion": { "data_source_id": 문서함_ds, "root_page_title": root_page } }  // 없으면 null
   ```
   > 정합: registry.json `status` ↔ 각 사업 로컬 `config.lifecycle.phase` 는 **같은 5값 도메인**. Notion DB 가 SSOT 이므로, DB 상태 변경 시 clone/start 한 로컬 config 의 phase 도 갱신 권장(현재는 init 시점 스냅샷).
3. `version:1`, `updated:<오늘>`, `projects:[…]` 형태의 완성 JSON을 만듭니다.
4. 레지스트리 repo를 클론하여 `registry.json`을 덮어쓰고 commit·push 합니다:
   ```
   git clone https://github.com/hankeon/proj-sync-harness-registry.git /tmp/psr
   # registry.json 갱신 후
   cd /tmp/psr && git add -A && git commit -m "registry: Notion DB 동기화" && git push
   ```
5. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/registry.sh list` 로 결과를 확인해 사용자에게 보고합니다.

> ⚠️ Slack 봇 토큰 등 자격증명은 registry.json에 **절대 기록 금지**(각 로컬 `.env`에만). `project_id`는 init 매칭 키이므로 변경하지 마세요.
