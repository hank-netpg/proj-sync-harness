---
name: dispatch
description: 드롭존(inbox·Slack)에 올라온 자료를 분류·신뢰도 판정해 phase에 맞는 파이프라인으로 자동 라우팅한다. 신뢰도 낮거나 phase 불일치면 사용자에게 질문(HITL). "자료 처리", "드롭 분석", "자동 실행" 시 또는 스케줄러가 호출.
version: 0.1.0
---

# 자율 dispatch (dispatch) — 자율주행 오케스트레이션

드롭된 자료 → **결정론 판정**(`dispatch.py`) → phase별 스킬 실행 or HITL 질문. SPEC §5.

## 절차
1. **수집(부수효과)**: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/slack_download.sh"` → `slack-files/`·`inbox/`.
2. **판정(결정론)**: `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/dispatch.py" <파일...>` → 파일별 {category·confidence·action}.
3. **라우팅(PM 에이전트, 인지)**:
   - `action=<스킬>` (신뢰도≥τ & phase 정합) → 해당 스킬 실행(제안=rfp-extract/toc…, 수행중=manage-*).
   - `action=ask` (신뢰도<τ or phase 불일치) → **AskUserQuestion**(옵션): "이 자료 제안용/수행용/기타?" → 피드백 반영 후 재판정.
4. **커밋(부수효과)**: 처리분 `github_push.sh`.

## 자율성 안전장치
- 자율 ≠ 맹목: 신뢰도 임계(config.dispatch.confidence_threshold, 기본 0.75)·phase 정합 미달 시 반드시 사용자 확인(HITL).
## 스케줄러
- `templates/schedule.crontab.template` — 매일 자정 slack-pull+commit(사업 폴더별 crontab 1행).
