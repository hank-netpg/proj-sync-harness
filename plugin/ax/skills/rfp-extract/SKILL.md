---
name: rfp-extract
description: RFP(제안요청서 hwpx/pdf)에서 요구사항을 추출해 proposal/requirements.json(SSOT)을 생성한다. 사용자가 "요구사항 추출", "RFP 분석", "제안요청서 분해"를 요청하거나, 제안 phase에서 신규 RFP가 드롭되면 사용. 제안축 파이프라인 1단계.
version: 0.1.0
---

# RFP 요구사항 추출 (rfp-extract) — 제안축 1단계

RFP 원문 → **요구사항 매트릭스(`proposal/requirements.json`, SSOT)**. 이후 toc·strategy·draft가 소비. GPU 없이 **Claude 서브에이전트**로 정제(원 propstudio `rfp_extractor` 이식).

## 원칙 (A3 부수효과⊥인지)
- **파싱·정규식·저장**(부수효과) = 스크립트 엔트리포인트만.
- **분류·요약·인용 정제**(인지) = 호출 에이전트가 `prompt.md` 지침으로 **직접 수행(인라인)**. 병렬이 필요하고 `Agent`(Task) 도구 보유 시 서브에이전트로 배치 분할 가능(선택). 인라인 LLM API·토큰 직접취급 금지.
- 파일시스템으로만 핸드오프.

## 입력
- `.proj-sync/config.json`의 `proposal.rfp_files[]` (없으면 `inbox/`의 hwpx/pdf 자동 탐지).
- `lifecycle.phase == 제안`(아니면 §HITL Q6 — "제안용/수행용?" 질문).

## 절차
1. **파싱**: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/parse_doc.sh" <rfp>` → `proposal/_extracted/rfp.txt` (hwpx=lxml XML 추출, pdf=pypdf, 실패 시 사용자에 PDF 재업로드 요청).
2. **1차 정규식 추출**: `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/rfp_regex.py"` → 요구사항 카드(id·context) 후보.
3. **정제(인지)**: `Read "${CLAUDE_PLUGIN_ROOT}/skills/rfp-extract/prompt.md"` → 그 system 규칙에 따라 카드를 **직접 정제**(호출 에이전트 인라인, 30건 배치 단위). `Agent`(Task) 도구 보유 시 배치를 서브에이전트 병렬로 분할 가능(선택). → JSON 배열(id·category·summary·quote), category는 RFP 구분 라벨 중 하나로 강제.
4. **병합·검증**: `schema.json` 대조. 실패 배치는 정규식 결과 유지(전체 진행 방해 X). `proposal/requirements.json` 저장.
5. **지식맵 갱신**: `node "${CLAUDE_PLUGIN_ROOT}/scripts/docquark.mjs"` → `knowledge/quark|_mirror|_axon` 재빌드.
6. **보고**: 추출 건수·구분 분포 1~3줄 + "다음: `/ax:toc`" 제안. 고아 요구사항(목차 미매핑) 있으면 HITL Q4로 확인.

## 산출 (SSOT)
- `proposal/requirements.json` — 스키마: `schema.json`. 예: `{"id":"SFR-001","category":"기능","summary":"…","quote":"원문 1문장","detail":[…],"toc_paths":[],"담당":null}`.

## 벤더 중립·품질
- 자사명·특정 제품명 노출 금지("수행업체" 일반화). 원문에 없는 인용 금지(quote는 원문 문장 그대로).
