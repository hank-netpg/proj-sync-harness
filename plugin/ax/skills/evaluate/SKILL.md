---
name: evaluate
description: 제안서 본문(pages/*.md)을 평가위원 3 페르소나(IT SI·응용SW·사업관리)로 감점 채점하고, 목표 점수에 도달할 때까지 자동 개선을 반복한다. RFP 평가배점을 rubric으로 사용. "평가", "채점", "제안서 점검", "개선 반복" 시 사용. 제안축 5단계.
version: 0.1.0
---

# 제안서 3-Agent 평가 (evaluate) — 제안축 5단계

`proposal/pages/*.md` → **평가보고 `proposal/eval/{round}.json`** + 자동 개선 반복. 원 propstudio 3-Agent 방식(수정 병렬 + 평가 독립) 코드화. Claude 서브에이전트.

## 입력
- `proposal/toc.json#평가배점`(→ `rubric.json`), `proposal/pages/*.md`, `config.proposal.eval`(target_score·max_rounds·min_delta).

## 절차 (반복 루프)
1. **rubric 생성**(결정론): toc.json#평가배점 → `proposal/eval/rubric.json`(항목·배점·만점조건·감점카탈로그).
2. **위원 3 채점(인지)**: `Read "${CLAUDE_PLUGIN_ROOT}/skills/evaluate/prompt.md"` → 위원 A·B·C 페르소나로 pages를 독립 감점. `Agent` 도구 보유 시 3위원 **병렬 서브에이전트**(권장), 없으면 순차 인라인. → findings(항목·감점·근거·개선지시·page_id) 를 `proposal/eval/w_{A,B,C}.json` 저장.
3. **집계(결정론)**: `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/evaluate_aggregate.py"` → 종합점수(만점−감점), `eval/{round}.json` 저장.
4. **종료 판정**: `score≥target` OR `round≥max_rounds` OR `Δ<min_delta`(정체) → 종료. (무한루프 방지.)
5. **미달 시 수정(인지)**: findings를 page_id별로 묶어 각 페이지를 prompt(개선지시 반영) 로 재작성(인라인 또는 Agent 도구 시 페이지별 병렬 서브에이전트) → `pages/*.md` 갱신 → round++ → 2로.
6. **보고**: 점수 진화(라운드별 Δ) + 잔여 감점 Top + `eval/_FINAL.md`.

## 원칙 (H2)
- **감점 계산=결정론**(집계 스크립트), **채점·수정=에이전트**(위원·수정), **발신=선택**. 파일 핸드오프(eval·pages).
- 위원은 만점에서 시작해 **비판적으로 감점**(관대 금지). 개선지시는 구체적(무엇을 추가/수정).
