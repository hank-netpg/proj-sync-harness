---
description: "전제(Premise) 빌드·갱신 — revision/전제/premise.yml(SSOT) → 최상위 PREMISE.md(사업 전제 레지스터·신선도). 절차 SSOT 는 manage-premise 스킬"
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/premise_build.sh:*)", "Bash(git status:*)", "Bash(git add:*)", "Bash(git commit:*)", "Bash(git log:*)"]
---

프로젝트의 **전제(Premise)** — revision(history·WBS·요구사항추적표·회의록)을 증류한 **운영시점 사업 전제 레지스터**를 갱신·빌드합니다. 절차 SSOT 는 **manage-premise 스킬**입니다.

요약 (상세는 manage-premise 스킬 참조):

1. **증류(주간)** — revision 변경분을 훑어 사업 전제(데이터 범위·마일스톤·발주처 합의·기술제약 등)를 `revision/전제/premise.yml`(SSOT)에 갱신. 각 전제 = 진술 + 출처(근거위치+버전핀 / 출처유형=구속력) + 상태 + 확인시점 + 파급 + 후속.
2. **빌드** — `bash ${CLAUDE_PLUGIN_ROOT}/scripts/premise_build.sh` → 최상위 `PREMISE.md`(리뷰 뷰). 근거 문서가 확인시점 이후 갱신됐으면 **`재확인 필요`(stale)** 자동 표기.
3. **commit** — `git add -A && git commit -m "revision: premise <오늘>"` (revision 축 commit 리듬).

> **편집은 SSOT(premise.yml)에서** — `PREMISE.md` 는 파생물(손 수정 금지). 상태·신선도 집계는 빌더가 재계산.
> **의존성**: PyYAML (`pip install --user pyyaml`) — revision 도구 중 첫 비-stdlib. 미설치 시 빌드가 안내한다.
> 전제는 risk/schedule 의 **상류** — `미확정`·`위반위험`·stale 전제는 위험·일정 후속으로 연결.
