---
name: draft
description: 목차 페이지별로 제안서 본문(proposal/pages/{page_id}.md, v3 propdraft)을 생성한다. 요구사항 근거는 knowledge/ 지식맵(quark 폴더)에서 target-jump로 가져온다(RAG 불요). "본문 작성", "페이지 생성", "초안 작성" 시 사용. 제안축 4단계.
version: 0.1.0
---

# 제안서 본문 생성 (draft) — 제안축 4단계

toc.json의 각 page → **v3 propdraft 본문 `proposal/pages/{page_id}.md`**. 원 propstudio `page_generator` 이식. **RAG 대신 knowledge/ quark 폴더 탐색**(환각 0·토큰 90%↓).

## 알고리즘 (page 단위, 담당·배점 우선순위)
1. toc.json에서 page.req_ids 확인.
2. **근거 수집(RAG 아님)**: `cat knowledge/quark/req/{rid}__*/{summary,quote,detail}.md` — 해당 page의 요구사항 폴더만.
3. 전략 발췌: strategy.md에서 page.장 관련 섹션.
4. 자산: `ls knowledge/_axon/by_page/{page_id}/asset__*` (링크된 자산만).
5. **생성(인지)**: `Read "${CLAUDE_PLUGIN_ROOT}/skills/draft/prompt.md"` → 그 규칙으로 **직접** v3 propdraft md(frontmatter propdraft/governance 3-5/subtitle + 개조식 700~1500자) 작성(인라인; 다수 페이지 병렬 시 Agent 도구로 서브에이전트 분할 선택).
6. frontmatter 검증 실패 시 1회 retry, 그래도 실패면 raw 저장 + error 표기.
7. `proposal/pages/{page_id}.md` 저장.

## 원칙
- quote.md에 있는 원문 문장만 인용(환각 방지). 벤더 중립. 컨텍스트는 해당 page의 req 폴더만(토큰 최소).
