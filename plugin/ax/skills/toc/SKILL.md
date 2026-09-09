---
name: toc
description: RFP 제안서 작성요령·평가배점과 확정 목차를 파싱해 proposal/toc.json(SSOT)을 생성한다. 요구사항을 목차 페이지에 매핑하고 담당사(R&R)·배점을 결합. "목차 생성", "제안서 목차", "요구사항 매핑" 시 사용. 제안축 2단계.
version: 0.1.0
---

# 제안서 목차 생성 (toc) — 제안축 2단계

RFP 목차·평가배점 + 확정 목차(예: 발주사 목차) + 요구사항(requirements.json) → **`proposal/toc.json`(SSOT)**. 페이지(leaf) 단위로 요구사항 ID·담당사(R&R)·배점을 결합. 원 propstudio `toc_parser` 이식.

## 입력
- RFP `_extracted/rfp.txt`(Ⅳ 작성요령·Ⅴ 평가배점), 확정 목차(있으면), `proposal/requirements.json`.

## 절차
1. **1차 정규식**: `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/toc_regex.py"` → chapter>section 후보.
2. **정제(인지)**: `Read "${CLAUDE_PLUGIN_ROOT}/skills/toc/prompt.md"` → 그 규칙으로 **직접** chapter>section>page(leaf) 트리 + 평가배점 생성(호출 에이전트 인라인, Agent 도구 시 서브에이전트 선택).
3. **요구사항 매핑**: 각 page에 `req_ids`(requirements 커버) + `담당`(R&R) 결합. 미매핑 요구사항 → `knowledge/_UNMAPPED.md` + HITL Q4.
4. **검증·저장**: `schema.json` 대조 → `proposal/toc.json`. `docquark.mjs` 재빌드.
5. **보고**: 장·절·페이지 수, 배점 합(=100 검증), 미매핑 건수 + "다음: `/ax:strategy`".

## 산출 (SSOT)
- `proposal/toc.json` — chapters[].sections[].pages[]{page_id,title,req_ids,담당,협업,스토리라인,산출물} + 평가배점.
