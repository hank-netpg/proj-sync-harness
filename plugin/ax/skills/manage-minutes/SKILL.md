---
name: manage-minutes
description: 프로젝트의 회의록(Minutes)을 표준 양식으로 생성·관리할 때 사용. 사용자가 "회의록 작성", "회의록 빌드", "회의록 정리"를 요청하거나, 회의 데이터(yml)에서 양식 HWPX 회의록+md를 결정론적으로 생성할 때. revision/회의록/*.yml(SSOT) → md(리뷰·revision) + hwpx(납품·deliverables). 회의별 날짜별 시리즈.
version: 0.1.0
---

# 회의록 관리 (Minutes) — 양식 HWPX 를 스켈레톤 주입으로 생성

회의 데이터(`.yml`=SSOT)로부터 **양식 HWPX 회의록 + md 를 결정론적으로 생성**해 revision 축에서 관리한다. WBS/RTM 이 단일 canonical 인 것과 달리 회의록은 **회의마다 독립 문서가 쌓이는 날짜별 시리즈**(`{주제}_회의록_{YYYYMMDD}.{yml,md,hwpx}`).

## 원칙 — data(yml SSOT) → 파생(md + hwpx), 작업 ⊥ 납품
- **SSOT = `revision/회의록/{주제}_회의록_{YYYYMMDD}.yml`** (검토·교정 데이터). 서사형 개조식이라 yml(WBS/RTM 의 json 과 분기).
- **파생**: `md(리뷰) → revision/회의록/`, `hwpx(납품) → deliverables/회의록/`(Archive, git 추적). md·hwpx 는 파생물 — 손대지 말고 yml 을 고쳐 재생성.
- **엔진**: `minutes_to_hwpx.py` 가 양식 스켈레톤(`reference/form/회의록-양식.hwpx`)의 `section0.xml` 만 주입 편집 → 표 병합·열폭·서식 100% 보존(밑바닥 생성 아님).

## yml 스키마 (요지)
- `제목` · `회의일시` · `회의장소` · `작성자`
- `참석자[]`: `{구분, 명단[]}` — **구분(라벨)도 데이터에서** 나온다(과제별 기관 구성이 다름). 항목 수만큼 표 행이 자동 증감.
  ```yaml
  참석자:
    - 구분: 수행기관
      명단: [황한건 (연구책임자·PM)]
    - 구분: 공동연구개발기관
      명단: Dr. Antonino Ardilio (해외협력기관)
    - 구분: 위탁연구개발기관
      명단: 이영희 (건국대학교)
  ```
  - 하위 호환: `참석자{}` dict(`{구분: 명단}`)도 그대로 동작 — 키가 곧 라벨.
  - **금지**: 특정 발주처·업체명을 라벨로 고정(예: `발주처`·`주관사`). 회의별 참석 기관 조합에 맞춰 그때그때 기입.
- `안건내용[]`: `{안건, 회의내용[], 결정사항, 비고}`
- `합의내용[]`: `{합의내용, 합의전제, 비고}` — 발주처 합의·전제 기록(→ 사업 전제 Premise 의 근거로 연결).

## 절차
1. **회의별 yml 편집** — `revision/회의록/{주제}_회의록_{YYYYMMDD}.yml`(SSOT)에 회의 데이터를 넣는다(검토·교정).
2. **빌드** — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/minutes_build.sh"`(= `/ax:minutes`) → `.md`(리뷰) + `.hwpx`(납품, 양식 보존). `/ax:revision` 도 회의록 yml 있으면 함께 빌드.
3. **history 기록** — `revision/history.md` 에 오늘 항목.
4. **commit** — `git add -A && git commit -m "revision: 회의록 <오늘>"` (revision 축).

## 다른 관리와의 관계
- **manage-revision**: 회의록은 revision 4번째 항목(history·WBS·요구사항추적표·회의록). 같은 commit 리듬.
- **manage-premise**: 회의록의 `합의내용`·안건 결정사항은 **사업 전제(Premise)의 주요 근거** — 데이터범위·마일스톤·발주처 합의가 여기서 발원. 회의 후 `/ax:premise` 로 전제 증류.

## 출력
- "회의록 N건 빌드 → revision/회의록/*.md(리뷰) + deliverables/회의록/*.hwpx(납품). 양식 서식 보존."
- **추측 금지**: 회의 내용·결정사항은 실제 회의 자료에서만. 불명확하면 "확인 필요" 자리표시.

## 의존성
- **lxml · PyYAML** (`pip install --user lxml pyyaml`) — HWPX XML·yml 처리. revision 도구 stdlib 예외(ARCHITECTURE A6, 회의록·전제만).
