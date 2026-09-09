#!/usr/bin/env bash
# proj-sync 공통 — 사업 폴더 스캐폴드. init.sh(신규 생성)와 config_migrate.sh(누락분 보강)가 **같은 코드**를 쓴다.
#   복붙하면 드리프트가 확정된다: 실제로 v1.5.0 에서 reference/drafts 개명 후 init 스캐폴드가 빠져
#   신규 프로젝트도 규약대로 생기지 않았고, 15개 사업 중 14개에서 산출물 집계가 0건이 됐다(2026-08-02 실측).
#
# 불변식 — **있는 파일은 절대 건드리지 않는다.** 없는 것만 만든다. 그래서 반복 실행이 안전하고,
#   doctor 가 자동으로 호출할 수 있다.
# 사용: ps_scaffold_project <ROOT>   → 이번에 만든 항목이 PS_SCAFFOLD_NEW 에 남는다(없으면 빈 문자열).

ps_scaffold_project() {
  local ROOT="$1" TPL
  [ -n "$ROOT" ] || return 1
  TPL="$(ps_plugin_root)/templates"
  PS_SCAFFOLD_NEW=""
  _sc_add() { PS_SCAFFOLD_NEW="${PS_SCAFFOLD_NEW:+$PS_SCAFFOLD_NEW · }$1"; }

  # .env 템플릿 (없으면)
  [ -f "$ROOT/.env" ] || { cp "$TPL/env.template" "$ROOT/.env" && _sc_add ".env"; }
  # .gitignore
  [ -f "$ROOT/.gitignore" ] || { cp "$TPL/gitignore.template" "$ROOT/.gitignore" && _sc_add ".gitignore"; }
  grep -q '^\.env$' "$ROOT/.gitignore" || echo ".env" >> "$ROOT/.gitignore"
  # 기존 사업에도 소급 적용(멱등) — .env 와 같은 관용구. 개인 Claude 설정은 공유 대상이 아니다.
  grep -q '^\.claude/settings\.local\.json$' "$ROOT/.gitignore" \
    || echo ".claude/settings.local.json" >> "$ROOT/.gitignore"
  # VSCode tasks (없으면) — $HOME 셔임 경유라 설치 경로 무관, 팀 repo 커밋 가능
  if [ ! -f "$ROOT/.vscode/tasks.json" ]; then
    mkdir -p "$ROOT/.vscode"
    cp "$TPL/vscode-tasks.template.json" "$ROOT/.vscode/tasks.json" && _sc_add ".vscode/tasks.json"
  fi

  # revision 축 — 매일 commit-push 하는 버전관리(history·WBS·요구사항추적표).
  #   WBS 는 config.wbs(SSOT), RTM 은 rtm.data.json(SSOT) → revision_build.sh 가 md(작업)·xlsx(납품) 로 빌드.
  mkdir -p "$ROOT/revision/wbs" "$ROOT/revision/요구사항추적표"
  [ -f "$ROOT/revision/요구사항추적표/rtm.data.json" ] || { printf '%s\n' '{
  "_comment": "요구사항추적표(RTM) SSOT. requirements[] 편집 후 revision_build.sh(또는 /ax:revision) 로 md+xlsx 재생성. 스키마: {group,subgroup,id,text,evidence,level(완전/부분/미흡/해당없음),plan}.",
  "requirements": []
}' > "$ROOT/revision/요구사항추적표/rtm.data.json"; _sc_add "revision/요구사항추적표/rtm.data.json"; }
  if [ ! -f "$ROOT/revision/history.md" ]; then
    printf '%s\n' '# Revision History' '' '> 프로젝트마다 **매일 한 일을 commit-push**. 각 날짜 항목 = 하루치 revision.' '> WBS 는 config.wbs(SSOT), 요구사항추적표는 rtm.data.json(SSOT) → `/ax:revision` 으로 md+xlsx 재생성.' '' "## $(date +%Y-%m-%d)" '- 프로젝트 초기화 — revision 축 생성.' > "$ROOT/revision/history.md"
    _sc_add "revision/history.md"
  fi

  # 회의록(Minutes) — 회의별 yml(SSOT) → md(리뷰·revision)+hwpx(납품·deliverables). 양식 스켈레톤 배치.
  mkdir -p "$ROOT/revision/회의록" "$ROOT/reference/form"
  [ -f "$ROOT/reference/form/회의록-양식.hwpx" ] || \
    { cp "$TPL/회의록-양식.hwpx" "$ROOT/reference/form/회의록-양식.hwpx" 2>/dev/null && _sc_add "reference/form/회의록-양식.hwpx"; } || true

  # 전제(Premise) — revision 을 증류한 운영시점 사업 전제 레지스터(→ PREMISE.md, /ax:premise).
  mkdir -p "$ROOT/revision/전제"
  [ -f "$ROOT/revision/전제/premise.yml" ] || \
    { cp "$TPL/premise.yml" "$ROOT/revision/전제/premise.yml" && _sc_add "revision/전제/premise.yml"; }

  # deliverables 축 — 납품 Archive(고객 as-is 최종본). 전부 git 추적(gitignore !deliverables/**).
  mkdir -p "$ROOT/deliverables"
  [ -f "$ROOT/deliverables/README.md" ] || { printf '%s\n' '# deliverables — 납품 Archive' '' '고객에게 그대로 납품하는 **최종본**. 전부 git 추적(사무파일 포함, A2 예외).' '- WBS·요구사항추적표 xlsx = `/ax:revision` 산출(납품본, 손 수정 금지 — SSOT 는 config.wbs·rtm.data.json).' '- 사무파일(hwp·ppt·pdf) 최종본은 여기 직접. 작업 초안(md)은 `reference/drafts/`.' > "$ROOT/deliverables/README.md"; _sc_add "deliverables/README.md"; }

  # reference/drafts 축 — 작업 초안(단계별). deliverables/(납품) 와 짝을 이룬다.
  #   구 경로 reference/deliverables/ 는 폐기. 스캐폴드로 규약을 도구가 강제한다.
  local _st
  for _st in 00_영업_제안 10_착수 20_분석 30_설계 40_구현_시험 50_종료_인도 99_아카이브; do
    mkdir -p "$ROOT/reference/drafts/$_st"
    [ -f "$ROOT/reference/drafts/$_st/.gitkeep" ] || : > "$ROOT/reference/drafts/$_st/.gitkeep"
  done
  [ -f "$ROOT/reference/drafts/README.md" ] || { printf '%s\n' \
    '# reference/drafts — 작업 초안 (단계별)' '' \
    '표준 산출물의 **작업본(md)** 을 단계 폴더에 둔다. 파일명은 `templates/deliverables.json` 의' \
    '표준 명칭을 그대로 쓴다(임의 명칭 금지) — 그래야 `/ax:deliverable` 이 완료를 셀 수 있다.' '' \
    '| 폴더 | 단계 |' '|---|---|' \
    '| `00_영업_제안` | 영업·제안 |' '| `10_착수` | 착수 |' '| `20_분석` | 분석 |' \
    '| `30_설계` | 설계 |' '| `40_구현_시험` | 구현·시험 |' '| `50_종료_인도` | 종료·인도 |' \
    '| `99_아카이브` | 대체본이 생긴 구 문서(삭제 금지, 이동) |' '' \
    '납품 최종본(고객 as-is)은 `deliverables/` 에 둔다. **구 경로 `reference/deliverables/` 는 폐기됨.**' \
    > "$ROOT/reference/drafts/README.md"; _sc_add "reference/drafts/README.md"; }

  # reference/management 축 — templates/deliverables.json 의 support_dirs 와 1:1.
  #   「산출물 외 관리 문서(4대 관리). 단계와 무관하게 사업 전체 관리」가 마스터의 정의다.
  local _sd
  for _sd in schedule risk config reports; do
    mkdir -p "$ROOT/reference/management/$_sd"
    [ -f "$ROOT/reference/management/$_sd/.gitkeep" ] || : > "$ROOT/reference/management/$_sd/.gitkeep"
  done
  [ -f "$ROOT/reference/management/README.md" ] || { printf '%s\n' \
    '# reference/management — 관리 문서 (4대 관리)' '' \
    '**산출물이 아니다.** 단계에 귀속되지 않고 사업 내내 계속 갱신하는 **대장·기록**만 둔다.' '' \
    '| 폴더 | 관리 축 | 예 |' '|---|---|---|' \
    '| `schedule` | 일정관리 | 일정 진척·대조표 |' \
    '| `risk` | 위험관리 | 위험관리대장 |' \
    '| `config` | 형상관리 | 형상·phase 판정 기록 |' \
    '| `reports` | 회의·보고 | 주간보고·점검 리포트 |' '' \
    '## 산출물과 헷갈리기 쉬운 것' '' \
    '**계획서·보고서는 산출물이다.** 별표2에 등재돼 있고 단계에 귀속되며 제출물이다.' \
    '`reference/drafts/<단계>/` 에 둔다 — `management/` 가 아니다.' '' \
    '| 산출물 (1회 작성·제출) | 관리 문서 (계속 갱신) |' '|---|---|' \
    '| 위험관리**계획서**(착수) | 위험관리**대장** `risk/` |' \
    '| 사업수행계획서(착수) | 일정 진척 `schedule/` |' \
    '| 품질보증계획서(착수) | 형상관리 기록 `config/` |' \
    '| 완료·단계실적보고서(종료) | 주간·점검 리포트 `reports/` |' '' \
    '빌드 원본(WBS·요구사항추적표·전제·회의록)은 **`revision/`** 이다. 여기 두지 않는다.' \
    > "$ROOT/reference/management/README.md"; _sc_add "reference/management/README.md"; }

  # 9원칙 + 프로젝트 지침 — 모든 사업 기본 적용.
  #   reference/9원칙.md = 원칙 본문(각 원칙의 위반 신호·확인 방법 포함). 개인 전역 규칙
  #     (~/.claude/rules)에 기대지 않고 배포본을 저장소에 둔다 — 팀원이 clone 해도 같아야 한다.
  #   CLAUDE.md = 프로젝트별 슬롯(1순위·회귀게이트·SSOT·자원격리·레슨로그). 비면 원칙이 절반만 작동한다.
  #   프로젝트명은 config.json 에서 읽되(없으면 폴더명), 이미 파일이 있으면 손대지 않는다(위 불변식).
  [ -f "$ROOT/reference/9원칙.md" ] || \
    { cp "$TPL/nine-principles.md" "$ROOT/reference/9원칙.md" && _sc_add "reference/9원칙.md"; }
  # 치환은 sed 가 아니라 python 으로 한다. sed 는 치환문에서 & 를 **전체 매치**로 해석하고
  #   | 는 구분자, \ 는 이스케이프로 먹는다 — 'A&B 정보화' 같은 실제 사업명이 들어오면
  #   {{PROJECT_NAME}} 이 그대로 남은 CLAUDE.md 가 조용히 생성된다.
  if [ ! -f "$ROOT/CLAUDE.md" ]; then
    "$PS_PY" - "$ROOT" "$TPL/CLAUDE.md.template" <<'PY' && _sc_add "CLAUDE.md"
import json, os, pathlib, sys
root, tpl = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
try:
    name = (json.loads((root / ".proj-sync" / "config.json").read_text(encoding="utf-8"))
            .get("project", {}).get("name") or "")
except Exception:
    name = ""                      # config 이 아직 없거나 깨진 경우 → 폴더명으로 대체
# 1순위 정의·회귀 게이트는 /ax:init 대화가 물어 env 로 넘긴다(issue #25).
# 안 넘어오면 종전의 「미정」을 그대로 둔다 — 비대화형 마이그레이션 경로를 깨지 않기 위해서다.
UNSET = "_(미정 — 채울 것)_"
slots = {
    "{{PROJECT_NAME}}":     name or root.name,
    "{{PRIORITY1}}":        os.environ.get("PS_PRIORITY1", "").strip() or UNSET,
    "{{REGRESSION_GATE}}":  os.environ.get("PS_REGRESSION_GATE", "").strip() or UNSET,
}
body = tpl.read_text(encoding="utf-8")
# str.replace 로 하나씩 — 리터럴 교체다. sed 는 & · | · \\ 를 해석해 사업명을 깨뜨린다.
for k, v in slots.items():
    body = body.replace(k, v)
(root / "CLAUDE.md").write_text(body, encoding="utf-8")
PY
  fi

  # 스캐폴드 README 는 게시 대상이 아니다(issue #12) — 게시 제외는 config.notion.publish.exclude_globs 가 정한다.
  return 0
}
