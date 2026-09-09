---
name: manage-report
description: 주간보고(Weekly Report)를 생성·발신할 때 사용. PM 에이전트가 오케스트레이션으로 호출하거나, 사용자가 "주간보고", "주간 보고서", "이번 주 보고", "리포트 발송"을 요청할 때, 또는 매주 스케줄(claude -p "/ax:report")에서. revision(전제·WBS·RTM·history)을 증류한 발신면 — 진행 사항 + 리스크를 결정론 계산(build_report.py)한 뒤 PM 이 총평을 얹어 Slack 게시.
version: 0.1.0
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/report_build.sh:*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/slack_post.sh:*)", "Bash(git status:*)", "Bash(git add:*)", "Bash(git commit:*)", "Bash(git log:*)", "Read", "Grep", "Glob", "Edit"]
---

# 주간보고 (Weekly Report) — revision 발신면(發信面)

revision 축(history·WBS·요구사항추적표·회의록·전제)을 **주간 증류**해 프로젝트의 **진행 사항 + 리스크**를 매주 한 장으로 알린다. 전제(manage-premise)가 revision 을 증류한 **내부 레지스터**라면, 주간보고는 그 위에서 진행·리스크를 **밖으로 발신**하는 면이다. (DESIGN §H)

## 원칙 — 사실 ⊥ 서술 ⊥ 발신 (A3 준용)
- **사실(결정론)**: `build_report.py` 가 완료율·지연·마감임박·마일스톤·전제 위반위험/stale·미확정·RTM 충족도·별표2 누락을 **계산**. 추측 없음.
- **서술(판단)**: PM 이 사실 위에 **한 줄 총평 + "지금 가장 급한 것"**만 얹는다. 사실을 바꾸지 않고, 과장하지 않는다.
- **발신(부수효과)**: `slack_post.sh` 가 채널 게시·담당 멘션. 파일시스템으로만 핸드오프(reports/*.md).

## 절차
1. **빌드(사실)** — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/report_build.sh"` → `reference/management/reports/주간보고_{YYYYMMDD}.md`.
   - 맨 위 **📮 Slack 발신본**(리스크 먼저 · 👤담당 · 완료율 추이) + 5섹션(🔴리스크 · 📊진척·일정 · ✅금주/차주 · 🟡결정 · 📦산출물·누락).
   - 데이터 부재 시(WBS/RTM/전제 미정의) 해당 섹션은 자동 축소 — 크래시 없음.
2. **교차 심화(선택)** — 필요하면 전문 스킬로 사실을 보강: 산출물 별표2·V-Model 짝은 `manage-deliverable`, 일정·번다운은 `manage-schedule`, 위험관리대장은 `manage-risk`, 전제 신선도는 `manage-premise`. 결과를 해당 섹션에 **근거(개수)**로만 반영.
3. **서술** — `주간보고_*.md` 를 읽고, **📮 Slack 발신본 블록** 위에 PM **한 줄 총평**(가장 급한 것 1개)만 Edit 로 덧붙인다. 섹션 사실은 손대지 않는다(파생물).
4. **발신** — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/slack_post.sh" "<총평 + 📮 Slack 발신본 블록>"`.
   - **담당 지목**: 발신본 `👤 담당` 의 owner(Slack UID)를 `config.mentions` 로 멘션(`@이름`은 스크립트가 자동 확장). "누가·무엇을·언제까지".
   - 선택: `notion-publish` 로 팀 게시.
5. **commit(선택)** — `git add -A && git commit -m "revision: 주간보고 <오늘>"` (revision 축 리듬).

## 헤드리스(스케줄) 실행 — 자동 행위 2가지로 한정 (inbox 규약 준용)
매주 `claude -p "/ax:report"` 로 무인 실행될 때 허용되는 자동 행위는 **① Slack 발신본 게시(`slack_post.sh`) ② `reports/주간보고_*.md` 기록** 뿐이다. 그 외(부수효과·config 수정·push)는 하지 않는다. 총평은 사실에서 결정론적으로 도출 가능한 1줄만(불명확하면 생략).

## 출력
- 사용자에게는 **총평 1줄 + Top3**만 일상어로. 상세는 `주간보고_*.md` 링크.
- **추측 금지**: 모든 수치는 build_report.py 사실에서만. 근거 없으면 "확인 필요".

## 다른 관리와의 관계
- **manage-premise**: 전제(위반위험·미확정·stale)가 §1 리스크·§4 결정의 **상류**. 주간보고는 전제를 **소비**(재생산 아님).
- **manage-schedule / manage-risk / manage-deliverable**: 4대 관리의 결정론 사실을 주간보고가 **한 장으로 종합·발신**하는 면.
- **manage-revision**: 주간보고는 revision **파생물(SSOT 없음)** — `config.wbs`·`premise.yml`·`rtm.data.json`·`history.md` 편집 후 재빌드.

## 의존성
- **PyYAML** (premise.yml) — 회의록·전제와 동일. 미설치 시 `build_report.py` 가 안내한다.
