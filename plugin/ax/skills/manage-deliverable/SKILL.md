---
name: manage-deliverable
description: 사업 산출물의 작성·완료 상태를 점검·관리할 때 사용. PM 에이전트가 오케스트레이션으로 호출하거나, 사용자가 "산출물 점검", "산출물 상태", "뭐 만들어야 해"를 요청할 때. profile별 표준 산출물 목록과 표준 폴더의 실제 파일을 대조하고, V-Model 짝(검증/확인)을 결정론적으로 점검한다. 읽기·분석 중심.
version: 0.1.0
---

# 산출물관리 (Deliverable Management) — V-Model 추적성 + Agile

전자정부 4대 관리 중 **산출물관리**. PM 에이전트가 호출하는 전문 스킬.
방법론: **V-Model**(설계↔테스트 짝 추적성) + **Agile**(반복 작성·증분).

## 입력 (근거)
- `${CLAUDE_PLUGIN_ROOT}/templates/deliverables.json` — 표준 산출물 마스터(`profiles`·`deliverables`·`stage_dirs`·`profile_map`).
- `.proj-sync/config.json` 의 `wbs.profile`(b2g/b2g_rnd/b2b/internal) 과 `tasks[].deliverable_keys`(확장 스키마 v1.4에서 **선택 필드** — 별표2 산출물 매핑 유지). WBS 상세 문서는 `revision/`(별개 축).
- 표준 폴더 `reference/drafts/{00_영업_제안~50_종료_인도}/` 의 실제 .md 파일(작업 초안). 납품 최종본은 `deliverables/`(Archive).

## 산출물 ⊥ 관리 문서 — 경계 (마스터가 SSOT)

`deliverables.json` 이 두 축을 이미 나눠 두고 있다. **이 경계를 임의로 옮기지 않는다.**

| | 산출물 (`deliverables` 34건) | 관리 문서 (`support_dirs`) |
|---|---|---|
| 성격 | **단계에 귀속** · 특정 시점 **제출·납품** | **단계 무관** · 사업 내내 **계속 갱신** |
| 별표2 등재 | ○ | × |
| 경로 | `reference/drafts/<단계>/` → `deliverables/` | `reference/management/{schedule,risk,config,reports}/` |

⚠️ **사업관리 문서 대부분은 산출물이다.** 착수 6건 중 5건(사업수행계획서·품질보증계획서·
위험관리계획서·착수신고서·보안서약서), 종료 9건 전부가 관리성인데 **전부 별표2 산출물**이다.
`management/` 에 남는 것은 그 계획을 실행하며 갱신하는 **짝**뿐이다.

| 산출물 (1회 작성·제출) | 관리 문서 (계속 갱신) |
|---|---|
| 위험관리**계획서**(착수) | 위험관리**대장** `risk/` |
| 사업수행계획서(착수) | 일정 진척 `schedule/` |
| 품질보증계획서(착수) | 형상관리 기록 `config/` |
| 완료·단계실적보고서(종료) | 주간·점검 리포트 `reports/` |

- **빌드 원본**(WBS·요구사항추적표·전제·회의록)은 `revision/` — 위 둘 어느 쪽도 아니다.
  표준 WBS 정본은 `revision/wbs/WBS.md` → `deliverables/WBS.xlsx`(`/ax:revision` 산출).
- 판단이 갈리면 **「단계에 귀속되는가 · 제출물인가」** 두 질문으로 가른다.

## 분석 (결정론적 — 추측 금지)
### 완료/미착수 집계
- `profiles[profile]` 의 산출물 키 목록 ↔ 표준 폴더(`stage_dirs[stage]`)의 `name`.md 존재 여부.
- 있으면 완료, 없으면 미착수. **개수로** 판정.

### V-Model 짝 추적 (kind:design/test 인 profile 만 — b2g/b2b)
- 설계(`kind:design`) 완료 → `verified_by` 테스트 존재? 없으면 **누락**.
- 테스트(`kind:test`)의 `verifies[]`(N:1) 설계가 모두 작성됐는지 역점검.
- `vv`: validation(사용자 확인)/verification(개발자 검증).

### profile별 차이
- **b2g**(용역): 별표2 27개, V-Model 짝 점검 적용.
- **b2g_rnd**(과제): 연구계획·연차/최종보고·연구노트 중심. V-Model 대신 **마일스톤 충족** 점검.
- **b2b/internal**: 축소 세트.

## 점검 절차
1. config의 `profile` → 마스터에서 표준 산출물 목록 전개.
2. 표준 폴더에서 실제 파일 존재 확인 → 완료/미착수.
3. V-Model 짝 누락 점검(해당 profile만).
4. **구조 감사**(문서 10건 이상이면 필수):
   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/doc_audit.py reference/drafts
   ```
   완전 동일(sha1)·겹침(J≥0.7)·구조이상·**빈껍데기**를 판정한다. 빈껍데기(헤딩만 있고 본문 부족)는
   **파일이 있어도 완료로 세지 않는다** — 존재 여부만 보면 껍데기를 완료로 오집계한다.
   상세 기준·아카이브 3축은 `audit-doc-tree` 스킬이 SSOT.
5. **버전 표기 점검**(필수):
   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/doc_version.py check --standard-only
   ```
   **버전·개정이력이 없는 산출물은 제출할 수 없으므로 완료로 세지 않는다** — 빈껍데기와 같은 층위다.
   발주처 제출물은 문서 자체에 표지 Version·개정일자·개정이력이 있어야 하고 감리가 그것을 본다.
   git 커밋 이력은 **내부** 형상관리라 이를 대신하지 못한다(`manage-config` 참조).
   `doc_version.py fix` 로 md 는 자동 보정되나, **사무파일은 서식상 사람이 채운다**.
5. **미착수·누락 우선** 보고. 작성이 필요하면 PL 위임 제안.
6. 결과는 PM에게 반환.

## 출력
- "27개 중 5개 완료, 미착수 22 / V-Model 누락 1(논리ERD 완료·통합테스트 없음)".
- 구조 감사 결과를 함께 — "완전동일 2쌍(정본 정리 필요) · 빈껍데기 3건(완료 집계 제외)".
- 산출물 폴더·파일명은 표준(stage_dirs)이 결정 — 사용자는 신경 안 씀.
