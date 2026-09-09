---
name: manage-premise
description: 프로젝트의 전제(Premise — 운영시점 사업 전제 레지스터)를 갱신·빌드할 때 사용. 사용자가 "전제 갱신", "전제 점검", "사업 전제", "premise 빌드"를 요청하거나, PM이 사업의 load-bearing 가정·합의·데이터범위·마일스톤을 revision 에서 증류·추적할 때. revision/전제/premise.yml(SSOT)에서 PREMISE.md를 파생하고 신선도(stale)를 자동 판정한다.
version: 0.1.0
---

# 전제 관리 (Premise) — revision 을 증류한 운영시점 사업 전제

프로젝트마다 `revision/전제/premise.yml` 에 **사업이 딛고 선 load-bearing 전제**를 둔다. revision 4항목(history·WBS·요구사항추적표·회의록)을 **주 1회 증류**해 데이터 범위·마일스톤·발주처 합의·기술제약 등을 하나로 모은다. 스코프 분쟁 때 가리키는 **사업 진실의 앵커**이자, risk·schedule 의 **상류**(전제 위반→위험, 합의 일정→진도 추적).

## 원칙 — 증류 + provenance + 상태 통합
- **증류**: 자유 메모가 아니라 revision 원재료에서 **load-bearing 한 것만** 골라 압축.
- **provenance 강제**: 각 전제는 반드시 **근거(revision 위치)로 역추적**된다 — 어디서 왔는지 없으면 전제 아님.
- **이슈=상태**: "이슈/할일"은 별도 축이 아니라 전제의 **상태**로 통합(상태≠합의 = 후속조치 필요).

## 스키마 (`revision/전제/premise.yml` — SSOT)
- `유형`: 데이터범위 · **마일스톤** · 인력 · 산출물 · 요구충족 · 기술제약 · 계약 · 보안 · 규정 … (사업 따라 확장)
- `진술`: 전제 한 문장.
- `근거[]` (provenance 2층, 복수 가능):
  - `위치`: 역추적 포인터 + **버전핀** (예: `revision/회의록/기술협상_회의록_20260715.yml#안건:기술 방향성`)
  - `유형`(구속력): **RFP·과업지시서=강제 / 회의록=양자합의 / 제안서=우리 가정 / 법령·지침=외생 / 발주처 구두=미확정**
  - `rev`: 인용·확인한 revision 버전(날짜/commit)
- `상태`: 합의 / 가정 / 미확정 / 위반위험
- `확인시점`: 마지막으로 확인한 revision 시점(YYYY-MM-DD) — 신선도 계산 기준.
- `파급[]`: 흔들리면 영향받는 곳(WBS task·산출물·일정·원가).
- `후속`: (상태≠합의) 확정까지 할 일 — schedule/risk 로 넘어가는 접점.

## 절차 (주간 리듬)
1. **증류** — 지난 `확인시점` 이후 revision 변경분(회의록·WBS·RTM·history)을 훑어 새/변경 전제를 추출. `premise.yml`(SSOT) 갱신(진술·근거·출처유형·상태·파급·후속). 확인한 전제는 `확인시점` 을 오늘로 갱신. **근거 없는 전제는 세우지 않는다.**
2. **빌드** — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/premise_build.sh"` → 최상위 `PREMISE.md`(리뷰 뷰).
   - 빌더가 **신선도 결정론 판정**: 각 전제 근거의 `git log` 최종수정 vs `확인시점` 비교 → 이후 갱신됐으면 **`재확인 필요`(stale)**.
3. **점검·연결** — `재확인 필요`·`미확정`·`위반위험` 전제를 우선 검토. 후속조치는 **risk(위험)·schedule(일정)** 로 넘긴다.
4. **commit** — `git add -A && git commit -m "revision: premise <오늘>"` (revision 축).

## 다른 관리와의 관계
- **manage-revision**: 전제는 revision 축의 항목 — 원재료 4항목의 **증류층**. 같은 commit 리듬(`/ax:revision` 도 premise.yml 있으면 신선도 재계산).
- **manage-risk**: 전제의 **상류** — `위반위험`·`미확정` 전제·stale 은 위험 신호. risk 가 대응방안을 잡는다.
- **manage-schedule**: **마일스톤 전제**(계약기간·납기)가 흔들리면 WBS `base_date`·일정 전체 파급. 합의된 일정 to-do 는 schedule 이 추적.

## 출력
- "전제 N건(합의·가정·미확정 집계) · ⚠️ 재확인 필요 K건 빌드 완료 → PREMISE.md. 미확정·stale 우선 검토 권장."
- **추측 금지**: 전제·상태·근거는 revision 실물에서만. 근거 없으면 전제로 세우지 말 것.

## 의존성
- **PyYAML** (`pip install --user pyyaml`) — revision 도구 중 첫 비-stdlib 예외(회의록과 같은 부류, ARCHITECTURE A6 예외). 미설치 시 빌드가 안내한다.
