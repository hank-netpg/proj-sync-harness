---
name: manage-revision
description: 프로젝트의 revision(버전관리 축 — history·WBS·요구사항추적표)을 갱신·기록할 때 사용. 사용자가 "revision 빌드", "WBS 갱신", "요구사항추적표 갱신", "일일 커밋"을 요청하거나 PM이 WBS/RTM 표준화를 오케스트레이션할 때. config.wbs·rtm.data.json(SSOT)에서 md+xlsx를 파생 생성하고 매일 commit-push한다.
version: 0.1.0
---

# revision 관리 (Revision) — 매일 commit-push 하는 버전관리 축

프로젝트마다 `revision/` 에 **history · WBS · 요구사항추적표 · 회의록**을 두고 **매일 한 일을 commit-push** 한다. 각 커밋 = 하루치 revision. 나중에 모든 프로젝트의 revision 을 모아 **교차 관리**한다(registry 연계).

> **전제(Premise)**: 이 원재료를 **주 1회 증류**한 운영시점 사업 전제 레지스터(`revision/전제/premise.yml` → `PREMISE.md`)를 별도 항목으로 둔다 — 절차는 **manage-premise 스킬**(`/ax:premise`). WBS/RTM 과 같은 commit 리듬(revision 빌드가 premise.yml 있으면 신선도도 재계산).

## 원칙 — data(SSOT) → 파생(md+xlsx)

- **WBS SSOT** = `.proj-sync/config.json` 의 `wbs`(`tasks`·`base_date`·`meta`).
- **RTM SSOT** = `revision/요구사항추적표/rtm.data.json`.
- **파생(작업 ⊥ 납품)**: `md → revision/{wbs,요구사항추적표}/`(작업·리뷰), `xlsx → deliverables/{WBS.xlsx,요구사항추적표.xlsx}`(납품 Archive). **손으로 수정 금지** — SSOT 를 고치고 다시 빌드.
- **md = 리뷰용**(git diff), **xlsx = 납품용**(정부 제출 형식). `deliverables/`(Archive)는 A2(사무파일→Google Drive)의 **대폭 예외**로 전부 git 추적(`!deliverables/**`, gitignore).

## 입력 (근거)

- `config.wbs.tasks[]`(확장 스키마): `{wbs, level, name, phase, stage?, output, deliverable_keys[]?, req_id, rtm_req_id, arch, owner, start_w, end_w, effort, pred, due?, status}`. **레벨3(leaf)만 상세**, 레벨1·2 는 name 만 — 롤업은 빌더가 계산.
- `config.wbs.base_date`(YYYY-MM-DD): W1 기준일. 있으면 일정(주→날짜) 파생, 없으면 주 표기만.
- `config.wbs.meta`: WBS 개요(사업명·목표완료·공식결과물 등) → xlsx 개요 시트.
- `rtm.data.json.requirements[]`: `{group, subgroup, id, text, evidence, level(완전/부분/미흡/해당없음), plan}`.

## 절차

1. **SSOT 편집** — WBS 는 `config.wbs`(PM 이 `manage-schedule`/`start-from-notion` 으로 채우거나 사용자 입력), RTM 은 `rtm.data.json`.
2. **빌드** — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/revision_build.sh"` 직접 실행. 결과: WBS 4시트 + RTM 2시트 + 각 md.
   - 빌더가 **결정론적 재계산**: 롤업(레벨1·2 시작/종료/공수), 일정(주→날짜), Gantt(주간 바), 요구사항 커버리지(req_id↔WBS), 충족도 집계(완전/부분/미흡 비율, '해당없음' 제외).
3. **history 기록** — `revision/history.md` 에 오늘 날짜 항목으로 무엇을 바꿨는지 1~2줄.
4. **commit·push** — 매일 commit-push. `git add -A && git commit -m "revision: <오늘>" && git push`. 시크릿·대용량은 기존 `github-push`(secret-scan) 정책 준수.

## 다른 관리와의 관계

- **manage-minutes**(회의록) 는 revision 4번째 항목 — 회의 yml(SSOT) → md(리뷰)+hwpx(납품, 양식 보존). `/ax:minutes`. 회의 `합의내용`·결정사항은 전제(Premise)의 근거.
- **manage-premise**(사업 전제) 는 revision 원재료(history·WBS·RTM·회의록)를 증류한 **운영시점 사업 전제 레지스터**(`PREMISE.md`) — `/ax:premise`. 같은 commit 리듬, risk/schedule 의 상류(전제 위반→위험, 마일스톤 전제→일정 파급).
- **manage-schedule**(일정·진도) 는 같은 `config.wbs.tasks` 를 읽는다 — revision 은 그 **표준 산출물(WBS 문서) 생성**, schedule 은 **진척·지연 분석**. 데이터는 하나(config.wbs), 관점만 다름.
- **manage-deliverable**(별표2 산출물) 은 `reference/drafts/`(작업 초안) 축 — revision/ 은 그와 **별개의 버전관리 축**(A5 정합). 납품 최종본은 `deliverables/`(Archive).

## 출력

- "WBS 세부 N건(롤업 M) · 커버리지 K종 / RTM R건(완전·부분·미흡 집계) 빌드 완료 → revision/. history 기록·커밋 권장."
