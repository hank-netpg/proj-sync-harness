---
name: build-deck
description: 제안서 본문(proposal/pages/*.md, v3 propdraft)을 발표자료 PPTX로 빌드한다. toc.json 순서로 슬라이드를 구성. "발표자료 생성", "PPTX 빌드", "덱 생성" 시 사용. 제안축 6단계(최종 산출).
version: 0.1.0
---

# 발표자료 PPTX 빌드 (build-deck) — 제안축 6단계

`proposal/pages/*.md`(v3 propdraft) → **`proposal/build/발표자료.pptx`**. 결정론 빌더(A3 부수효과 = 스크립트). 인지 에이전트 개입 없음.

## 절차
1. `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/build_deck.py"` — toc.json 순서로 페이지 정렬 → 슬라이드(표지 + 페이지별 제목·governance·본문 요약) 생성.
2. 산출 `proposal/build/발표자료.pptx` → 납품은 `deliverables/`로 이관(E2, git 추적).
3. 보고: 슬라이드 수·누락(frontmatter 무효) 페이지.

## 의존
- python-pptx·PyYAML (회의록 lxml에 이은 비-stdlib 예외).
