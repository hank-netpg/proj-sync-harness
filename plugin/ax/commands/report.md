---
description: "주간보고 빌드·발신 — revision(전제·config.wbs·RTM·history) 증류 → reference/management/reports/주간보고_{날짜}.md(진척+리스크 5섹션·맨 위 Slack 발신본) → Slack 게시. 절차 SSOT 는 manage-report 스킬"
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/report_build.sh:*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/slack_post.sh:*)", "Bash(git status:*)", "Bash(git add:*)", "Bash(git commit:*)", "Bash(git log:*)", "Read", "Edit"]
---

프로젝트의 **주간보고(Weekly Report)** — revision 축을 증류한 **발신면(發信面)**(진행 사항 + 리스크)을 생성·발신합니다. 절차 SSOT 는 **manage-report 스킬**입니다.

요약 (상세는 manage-report 스킬 참조):

1. **빌드(사실)** — `bash ${CLAUDE_PLUGIN_ROOT}/scripts/report_build.sh` → `reference/management/reports/주간보고_{날짜}.md`. WBS `status`/`due`·전제 상태·RTM 충족도·history·별표2 를 결정론 증류: 맨 위 **📮 Slack 발신본**(리스크 먼저·담당 지목) + 5섹션(🔴리스크 · 📊진척·일정 · ✅금주·차주 · 🟡결정 · 📦산출물·누락).
2. **서술(판단)** — PM 이 사실 위에 **한 줄 총평·"지금 가장 급한 것"**만 얹는다(과장 없이 근거대로). 산출물 별표2·V-Model 심화는 `manage-deliverable`, 일정·리스크 심화는 `manage-schedule`·`manage-risk` 로 교차 종합.
3. **발신** — `bash ${CLAUDE_PLUGIN_ROOT}/scripts/slack_post.sh "<📮 Slack 발신본 + 총평>"` 로 `config.slack.channel_id` 게시(담당 `config.mentions` 멘션). 선택: `notion-publish` 로 게시.
4. **commit(선택)** — `git add -A && git commit -m "revision: 주간보고 <날짜>"` (revision 축 리듬).

> **편집은 revision(SSOT)에서** — `주간보고_*.md` 는 **파생물(SSOT 없음)**. 손대지 말고 `config.wbs`·`premise.yml`·`rtm.data.json`·`history.md` 를 고쳐 재빌드.
> **의존성**: PyYAML(premise.yml). 미설치 시 빌드가 안내한다.
> **주기 실행**: 매주 `claude -p "/ax:report"` 스케줄 가능 — 헤드리스 자동 행위는 **① Slack 게시 ② reports 기록** 2가지로 한정(inbox 규약 준용, MANUAL.md).
