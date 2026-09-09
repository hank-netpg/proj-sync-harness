---
name: manage-schedule
description: 사업 일정·진도를 점검·관리할 때 사용. PM 에이전트가 오케스트레이션으로 호출하거나, 사용자가 "일정 점검", "진도 관리", "지연된 작업", "번다운"을 요청할 때. WBS task의 일정 대비 진척을 Agile(번다운)+V-Model(단계 게이트)로 분석한다. 읽기·분석 중심.
version: 0.1.0
---

# 일정·진도관리 (Schedule Management) — Agile + V-Model

전자정부 4대 관리 중 **일정·진도관리**. PM 에이전트가 호출하는 전문 스킬.
방법론: **Agile**(번다운·벨로시티) + **V-Model**(단계 게이트).

## 입력 (근거)
- `.proj-sync/config.json` 의 `wbs.tasks[]` (확장 스키마 v1.4: `phase·level·owner·start_w·end_w·effort·due?·status`). **WBS 단일 SSOT** — revision 문서와 공유.
  - `due` 없으면 `config.wbs.base_date + end_w`(주→날짜)로 파생해 지연·마감 계산. leaf(level 3) 기준으로 진척 집계, 레벨1·2 는 롤업.
- `reference/management/schedule/` 의 일정 문서(있으면). 표준 WBS 문서는 `revision/wbs/WBS.md`(작업·리뷰)·`deliverables/WBS.xlsx`(납품) (→ `/ax:revision` 빌드).

## 분석 (결정론적 — 추측 금지)
### Agile — 진도 가시화
- `status`(미착수/진행중/검토중/완료) 집계 → **완료율·잔여작업**(번다운).
- 담당자별 진척 (`owner` ↔ `wbs.owners`).

### Agile — 지연 탐지 (파생 계산)
- **지연 = `status≠완료 AND due<오늘`** (status 값 아님, 계산).
- 마감 임박 = `due ≤ 오늘+7일 AND status≠완료`.

### V-Model — 단계 게이트
- stage 순서(착수→분석→설계→구현→종료). 앞 단계 산출물 미완 시 다음 단계 진입 경고.
  - 예: "설계 산출물 미완 → 테스트(구현) 단계 진입 불가".
- B2G-과제(R&D)는 단계 게이트 대신 **연차/단계 마일스톤**(ANNUAL_REPORT·MILESTONE_REPORT) 기준.

## 점검 절차
1. WBS task를 읽는다. 없으면 "WBS 미정의 — 사업 초기 정의 필요".
2. 완료율·지연·마감임박을 계산.
3. V-Model 단계 게이트 위반 점검.
4. **지연·임박 우선** 보고 (가장 급한 것부터).
5. 결과는 PM에게 반환.

## 출력
- 완료율 + 지연 N건 + 마감 임박 Top 3.
- 근거: "task 2.1 due 2026-06-20 < 오늘 → 지연 8일".
- **방법론 분리**: 대외 산출물 일정은 V-Model 단계 준수, 내부 진도는 Agile 반복.
