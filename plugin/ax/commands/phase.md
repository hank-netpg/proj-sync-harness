---
description: "사업 단계(생애주기) 전환 — config.lifecycle.phase 변경 + Notion 수행프로젝트DB 상태 동기화 안내. 사용: /ax:phase <제안|수주|수행중|완료|보류|실주>"
argument-hint: "<제안|수주|수행중|완료|보류|실주>"
allowed-tools: ["Read", "Edit", "Bash(cat:*)", "Bash(ls:*)"]
---

사업의 생애주기 단계를 전환합니다. 단계는 Notion 수행 프로젝트 DB의 `상태` 6값과 동일합니다: **제안 · 수주 · 수행중 · 완료 · 보류 · 실주**.

## 절차
1. `$ARGUMENTS` 로 받은 새 단계가 6값 중 하나인지 확인. 아니면 목록을 보여주고 중단.
2. `.proj-sync/config.json` 의 `lifecycle.phase` 를 새 값으로 변경 (Edit).
   - 현재 phase → 새 phase 를 사용자에게 1줄 보고.
3. **수행중으로 전환 시**: PM 에이전트(`@agent-ax:pm`)에게 "WBS·표준 산출물 전개"를 제안. (수행 단계부터 산출물 추적 시작)
4. **Notion 동기화 안내** (Notion 이 사업 상태의 SSOT):
   - claude.ai Notion MCP 로 수행 프로젝트 DB(`data_source_id`)에서 이 사업 행을 찾아 `상태` 를 동일 값으로 업데이트할지 사용자에게 확인.
   - DB 갱신은 사람용 SSOT 반영 → registry-sync 로 registry.json 까지 미러됨.
5. 단계 전환 사실을 Slack 채널에 알릴지 PM 에이전트에게 위임 (소통 창구).

## 원칙
- **3곳 정합**: Notion `상태`(SSOT) ↔ config `lifecycle.phase`(로컬) ↔ registry `status`(미러). 가능하면 함께 갱신.
- phase 외 값(예: SDLC stage)은 이 커맨드가 다루지 않음 — 그건 `wbs.tasks[].stage`(PM 관리).
- 복잡성 숨김: 사용자에겐 "○○ 단계로 바꿨어요. Notion에도 반영할까요?" 수준으로 간결히.
