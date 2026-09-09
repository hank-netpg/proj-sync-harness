---
name: manage-config
description: 산출물의 버전·변경 이력(형상관리)을 점검할 때 사용. PM 에이전트가 오케스트레이션으로 호출하거나, 사용자가 "형상관리", "변경 이력", "버전 점검"을 요청할 때. GitHub commit/diff를 형상관리 엔진으로 삼아 산출물 baseline·변경을 추적한다. 읽기 전용(git 조회).
version: 0.1.0
---

# 형상관리 (Configuration Management) — GitHub 기반

전자정부 4대 관리 중 **형상관리**. PM 에이전트가 호출하는 전문 스킬.
방법론: **방법론 무관** — GitHub commit/diff가 Agile·V-Model 양쪽의 baseline 추적을 충족.

## 핵심 원칙
- **GitHub가 형상관리 엔진**: commit=버전, diff=변경, repo=baseline, tag=마일스톤.
- 별도 형상관리대장을 만들지 않는다 (git이 이미 SSOT).

> ⚠️ **git 형상관리 ⊥ 문서 내 개정이력 — 둘은 다른 것이다.**
> git 은 **내부** 형상관리다. 발주처에 내는 산출물은 **문서 자체에** 표지 Version·개정일자와
> 개정이력 표가 있어야 한다 — 방법론 서식이 그렇고 **감리가 그것을 본다**.
> 「git 이 있으니 됐다」로 넘기면 제출 직전에 버전이 v1 에 멈춘 문서를 내게 된다.
> 2026-08-03 실측: `reference/drafts` md 138건 중 **114건(82%)이 버전 표기 전무**였고,
> 같은 날 통합안을 만들면서도 개정이력 갱신을 빠뜨렸다.
>
> ```bash
> python3 ${CLAUDE_PLUGIN_ROOT}/scripts/doc_version.py check --standard-only
> python3 ${CLAUDE_PLUGIN_ROOT}/scripts/doc_version.py fix --dry-run
> ```
> 점검 절차에 **반드시 포함**한다(아래 4번).

## 입력 (근거, 읽기 전용)
- git 로그·diff (read-only Bash: `git log`·`git diff`·`git show` — **부수효과 없음**).
- `reference/drafts/` 의 산출물(작업 초안) 변경 이력.
- `reference/management/config/` 의 형상 기록(있으면).

## 분석 (결정론적)
- 산출물별 **최근 변경 시점**(`git log -1 --format=%ci <file>`).
- baseline 이후 **변경된 산출물** 목록(`git diff --name-only <tag>..HEAD`).
- 미커밋 변경(`git status --short`) → "백업 안 된 산출물" 경고.
- 산출물 버전 식별: tag 또는 commit 해시.

## 점검 절차
1. 표준 폴더 산출물의 git 추적 상태 확인.
2. 미커밋(백업 안 됨) 산출물 → push 필요 경고 (push 자체는 터미널 안내).
3. baseline(직전 tag) 이후 변경 산출물 요약.
4. **문서 내 버전 표기 점검**(필수) — `doc_version.py check --standard-only`.
   누락은 **제출 결함**이므로 git 추적 상태와 별도로 보고한다.
   - 표준 형식: 상단 `**문서버전** vX.Y · **개정일자** YYYY-MM-DD` + `## 개정이력` 표
   - 사무파일(xlsx·hwpx)은 서식을 따른다 — 표지 Version·개정일자 + 개정이력 시트/표.
     **스크립트가 자동 보정하지 않으므로 사람이 확인**한다
   - **문서를 고쳤으면 개정이력에 행을 추가**한다. 발주처·감리 의견을 받은 것도 개정 사유다
4. 결과는 PM에게 반환.

## 권한 경계 (중요)
- **read-only git 조회만** (`git log/diff/show/status`). `git add/commit/push` 등 **부수효과는 절대 안 함** → 터미널(`bash proj-sync-setup.sh` → GitHub 동기화) 안내.
- 분류기 차단 회피: 쓰기 git 명령을 호출하지 않는다.

## 출력
- "산출물 5개 중 2개 미커밋(백업 필요), baseline 이후 변경 3건".
- 근거: git log/diff 출력. 추측 금지.
