---
description: "회의록(Minutes) 빌드 — revision/회의록/*.yml(SSOT) → md(리뷰·revision) + hwpx(납품·deliverables, 양식 보존). 절차 SSOT 는 manage-minutes 스킬"
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/minutes_build.sh:*)", "Bash(git status:*)", "Bash(git add:*)", "Bash(git commit:*)", "Bash(git log:*)"]
---

프로젝트의 **회의록(Minutes)** — 회의 데이터(yml)에서 **양식 HWPX 회의록 + md** 를 결정론적으로 생성합니다. 절차 SSOT 는 **manage-minutes 스킬**입니다.

요약 (상세는 manage-minutes 스킬 참조):

1. **회의별 yml** — `revision/회의록/{주제}_회의록_{YYYYMMDD}.yml`(SSOT)에 회의 데이터를 넣는다(안건·결정사항·합의내용). 회의마다 새 파일 = **날짜별 시리즈**.
2. **빌드** — `bash ${CLAUDE_PLUGIN_ROOT}/scripts/minutes_build.sh` → `revision/회의록/*.md`(리뷰) + `deliverables/회의록/*.hwpx`(납품). 엔진이 양식 스켈레톤을 주입 편집해 **표 병합·서식 100% 보존**(밑바닥 생성 아님).
3. **commit** — `git add -A && git commit -m "revision: 회의록 <오늘>"` (revision 축 commit 리듬).

> **편집은 SSOT(yml)에서** — `.md`·`.hwpx` 는 파생물(손 수정 금지). 양식 마스터는 `reference/form/회의록-양식.hwpx`.
> **의존성**: lxml · PyYAML (`pip install --user lxml pyyaml`) — HWPX·yml 처리. 미설치 시 빌드가 안내.
> 회의록의 `합의내용`·결정사항은 **사업 전제(Premise)의 근거** — 회의 후 `/ax:premise` 로 전제를 증류하세요.
