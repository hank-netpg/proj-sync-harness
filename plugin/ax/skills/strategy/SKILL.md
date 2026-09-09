---
name: strategy
description: 요구사항 매트릭스에서 제안 전략·접근법 문서(proposal/strategy.md, 5섹션)를 생성한다. "전략 생성", "제안 전략", "차별화 포인트" 시 사용. 제안축 3단계.
version: 0.1.0
---

# 제안 전략 생성 (strategy) — 제안축 3단계

`proposal/requirements.json` → **전략 분석 문서 `proposal/strategy.md`**(5섹션). 원 propstudio `strategy_writer` 이식. Claude 서브에이전트.

## 절차
1. requirements.json 요약(id·category·summary) + 분류별 분포 집계(결정론).
2. `Read "${CLAUDE_PLUGIN_ROOT}/skills/strategy/prompt.md"` → 그 규칙으로 **직접** 5섹션 markdown(사업 본질·차별화 5·평가 점수 최대화·위험·톤앤매너) 작성(호출 에이전트 인라인).
3. frontmatter(generated_at·model·project·requirements_count) 부착 → `proposal/strategy.md` 저장.
4. 보고 1~3줄 + "다음: `/ax:draft`".

## 산출
- `proposal/strategy.md` — 5섹션(개조식, 벤더 중립). draft가 페이지별로 발췌 소비.
