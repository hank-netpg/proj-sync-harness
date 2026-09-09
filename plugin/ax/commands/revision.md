---
description: "revision 빌드·커밋 — config.wbs·rtm.data.json(SSOT) → WBS·요구사항추적표 md(revision·작업)+xlsx(deliverables·납품) 재생성, 매일 commit-push"
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/revision_build.sh:*)", "Bash(git status:*)", "Bash(git add:*)", "Bash(git commit:*)", "Bash(git push:*)", "Bash(git log:*)"]
---

프로젝트의 **revision**(버전관리 축 — history · WBS · 요구사항추적표 · 회의록)을 갱신·기록합니다. 절차 SSOT 는 **manage-revision 스킬**입니다.

요약 (상세는 manage-revision 스킬 참조):

1. **빌드** — `bash ${CLAUDE_PLUGIN_ROOT}/scripts/revision_build.sh` (작업 ⊥ 납품 경로 분리)
   - `config.wbs`(SSOT) → `revision/wbs/WBS.md`(작업) + `deliverables/WBS.xlsx`(납품·4시트: 개요·상세·Gantt·커버리지)
   - `revision/요구사항추적표/rtm.data.json`(SSOT) → `.md`(작업) + `deliverables/요구사항추적표.xlsx`(납품·2시트)
   - **편집은 SSOT 에서** — md·xlsx 는 파생물(손으로 수정 금지).
2. **history 기록** — `revision/history.md` 에 오늘 항목 추가(무엇을 바꿨는지 1~2줄).
3. **commit·push** — `git add -A && git commit -m "revision: <오늘>" && git push` (매일 commit-push 전제). 대용량·시크릿 push 는 기존 `github-push` 경로/정책을 따른다.

> WBS 를 바꾸려면 `config.wbs.tasks`(leaf=레벨3)를, RTM 을 바꾸려면 `rtm.data.json` 을 편집한 뒤 1) 빌드를 다시 실행하세요. 롤업·일정(주→날짜)·Gantt·커버리지·충족도집계는 빌더가 자동 재계산합니다.

> **회의록(Minutes)**: `revision/회의록/*.yml` 이 있으면 revision 빌드가 `md`(리뷰)+`hwpx`(납품, 양식 보존)도 함께 생성합니다. 회의록 작성·빌드는 **`/ax:minutes`**(→ manage-minutes 스킬)로. lxml·PyYAML 필요.

> **전제(Premise)**: `revision/전제/premise.yml` 이 있으면 revision 빌드가 `PREMISE.md`(사업 전제·신선도)도 함께 갱신합니다. 전제 증류·갱신은 **`/ax:premise`**(→ manage-premise 스킬)로. PyYAML 필요.
