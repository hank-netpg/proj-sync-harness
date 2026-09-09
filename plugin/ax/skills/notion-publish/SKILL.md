---
name: notion-publish
description: proj-sync 프로젝트의 분석·설계 문서를 Notion 문서함 DB에 게시할 때 사용. 사용자가 "노션에 올려줘", "문서함에 작성", "[Proj] 하위 문서 추가"를 요청할 때. 게시는 로그인한 사용자의 claude.ai Notion 커넥터(MCP)가 원문 전체를 올린다 — 판정(대상·매칭·프로퍼티·고아)은 notion_plan.sh 가 결정론으로 낸다.
version: 0.2.0
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/notion_plan.sh:*)", "Read", "Write", "mcp__claude_ai_Notion__notion-fetch", "mcp__claude_ai_Notion__notion-query-data-sources", "mcp__claude_ai_Notion__notion-create-pages", "mcp__claude_ai_Notion__notion-update-page"]
---

# Notion 문서 게시 (문서함 DB)

git 레포의 분석 문서(reference/*.md 등)를 **문서함 데이터베이스**에 게시하고, 사업 메인 `[Proj]` 페이지의 하위로 연결한다.

**누가 게시하나 (v1.21.0)** — Claude Code 계정이 사용자마다 개인 계정이므로, 게시는 **로그인한 사용자의
claude.ai Notion 커넥터(MCP)** 가 한다. 게시본의 `작성자`(person) 는 그 사용자가 된다. 팀 REST 경로는
v1.21.0 에서 삭제됐다 — 게시 경로는 이 스킬(MCP) 하나다.

**무엇을 올리나** — **원문 전체**. 요약본·재서술 금지. 판정 규칙(대상 집합·페이지 매칭·프로퍼티·고아)은
`notion_plan.sh` 가 계획 JSON 으로 내고, 이 스킬은 그 action 을 MCP 호출로 옮긴다. 규칙을 에이전트가
즉흥으로 재구성하지 않는다 — 이 저장소의 Notion 사고는 전부 판정 로직에서 났다(#21·#22·#31·#52·#53).

## 게시 대상은 config 가 정한다 (임의 선택 금지)

**`config.notion.publish.globs` 가 게시 대상 집합이다.** 이 값이 없으면 아무것도 게시하지 말고
사용자에게 설정을 요청한다(`notion_plan.sh plan` 이 exit 3). **v1.15.0 부터 `init.sh` 가 아래 블록을
기본으로 써 넣는다** — 신규 사업은 손댈 필요 없고, 손댄 값은 재init 해도 보존된다.

```jsonc
"notion": {
  "enabled": true,
  "data_source_id": "bf6c317e-…",          // 문서함
  "project_tag": "유효특허DB",               // = 수행 프로젝트 DB 의 notion_tag
  "root_page_id": "390ef4ce-…",            // [Proj] 페이지 — 상위 항목 타깃 (비면 제목으로 해석)
  "publish": {
    "globs": ["reference/drafts/**/*.md", "reference/management/**/*.md"],
    "exclude_globs": [
      "reference/management/reports/**/*.md",   // 주간·점검 리포트 = 시점 기록
      "reference/drafts/README.md",             // init 스캐폴드 안내문 = 산출물 아님
      "reference/management/README.md"
    ],
    "type": "기술문서", "status": "작성중"
  }
}
```

**경로가 유형·상태를 정한다** — `type`·`status` 는 사업 단위 기본값이고, 아래가 우선한다(계획기가 적용).

| 경로 | 유형 | 상태 | 왜 |
|---|---|---|---|
| `**/99_아카이브/**` | 기본값 | **아카이브** | **게시에서 빼지 않는다.** 빼면 문서함에서 사라져 관리 대상에서 누락된다. 프로젝트 태그는 유지해 사업별 뷰에 계속 잡히게 한다 |
| `reference/management/**` | **현황** | **현행화문서** | 산출물이 아니라 살아있는 관리 문서(위험관리대장·WBS·서식규정·소관표) |
| 그 외 | `publish.type` | `publish.status` | |

`reference/management/reports/` 는 시점 기록이므로 `exclude_globs` 로 뺀다. 소급 갱신 대상이 아니다.

**스캐폴드 안내문은 게시 대상이 아니다** — `init.sh` 가 만드는 `reference/drafts/README.md` ·
`reference/management/README.md` 두 건은 폴더 규약 안내이지 사업 산출물이 아니다. 정확 경로로 제외하므로
사람이 만든 하위 README 는 계속 게시된다. *(2026-08-07 실측, issue #12.)*

> ⚠️ **2026-08-02 근본원인.** 종전에는 대상 규칙이 어디에도 없어 **아무도 대상을 정하지 않았고, 동기화를
> 돌려도 아무것도 올라가지 않았다.** 실측: 15개 사업 GitHub 산출물 439건 중 Notion 반영이 사실상 부재.

## 계획기가 지키는 규칙 (에이전트가 바꾸지 않는다)

- **같은 파일은 `출처경로` 로 찾아 id 를 보존한 채 본문만 교체**한다(중복 페이지·하위 고아화 방지).
  제목이 아니라 출처경로가 1순위 키다 — 「착수신고서」·「보안서약서」 같은 표준 산출물이 사업 간에 충돌해
  **다른 사업 페이지를 덮어쓴다**(2026-08-02 실제 발생). 출처경로는 `<project.id>/<repo 상대경로>` · NFC.
- 2순위(이행 호환): 출처경로가 **비어 있는** 동명 페이지만 잇는다. 다른 파일의 출처경로가 박힌 페이지는 남의 것이다.
- **갱신 시 `유형`·`상태` 는 건드리지 않는다**(#52) — 문서 단위 판단이다. `프로젝트`·`출처경로`·`문서명` 은 분류 키라 매번 재적용.
- **`상위 항목` 은 비어 있을 때만 채우고, 루트 페이지 자신에게는 넣지 않는다**(#53 — `A block cannot be its own parent`).
- **고아 보존** — 원본이 사라지거나 대상에서 빠진 게시본은 `상태`=`아카이브` 로 표시한다. **삭제하지 않는다.**
  가드: ① 출처경로 빈 페이지 제외 ② 이 사업 `project.id` 접두가 아닌 출처경로 제외 ③ keep 이 비면 중단
  ④ 고아가 과반이면 중단(#31, `NP_SWEEP_FORCE=1` 로만 해제). 게시가 1건이라도 실패하면 스윕은 돌지 않는다.

## 절차 (MCP 기본 경로)

도구가 없으면(커넥터 미연동·headless) **1단계에서 멈추고** 「Notion 스킵 — claude.ai Notion 커넥터 미연동
(각자 1회 연결 · `/mcp` 로 확인)」 으로 보고한다. 우회하지 않는다.

1. **커넥터·스키마 확인** — `notion-fetch` 로 `config.notion.data_source_id` 를 연다. 응답의 스키마에
   `문서명`·`상태`·`유형`·`프로젝트`·`출처경로`·`상위 항목` 이 있는지 본다(없으면 중단·보고).
   `collection://…` URL 을 기억한다(계획의 `collection_url` 과 같아야 한다).
2. **계획** — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/notion_plan.sh" plan` → 출력의 계획 파일 경로를 Read.
   exit 3 = `publish.globs` 미설정 → 설정 요청 후 종료.
3. **인덱스** — 계획의 `lookup_sql` 을 `notion-query-data-sources`(SQL 모드, `data_source_urls: [collection_url]`) 로
   실행한다. `has_more` 가 true 면 `… ORDER BY url LIMIT 100 OFFSET n` 으로 끝까지 읽어 `results` 를 합친다.
   결과 객체를 **그대로** `<stage_dir>/index.json` 에 Write → `notion_plan.sh plan --index <stage_dir>/index.json`
   → 계획 파일을 다시 Read (`action`·`properties`·`orphans`·`abort` 가 채워진다).
4. **루트** — `root.id` 가 null 이면 경고(「[Proj] 페이지를 못 찾음 — 평면 게시」)하고 계속한다(REST 와 동일).
5. **문서마다 순서대로** (`docs[]`, `action` 이 `skip` 이면 사유와 함께 건너뜀):
   - `body_path` 를 Read 한다 — 이것이 본문 **전체**다(살균·h4 접기 완료본). 요약·수정 금지.
     `body_bytes` 가 200,000 을 넘으면 `⚠ 대용량 — 실패 시 분할 게시 또는 GitHub 원문 안내` 를 미리 적는다.
   - `create` → `notion-create-pages` `{parent:{type:"data_source_id", data_source_id:<data_source_id>},
     pages:[{properties:<properties>, content:<본문>}]}`
   - `update` → `notion-update-page` `{page_id, command:"replace_content", new_str:<본문>, allow_deleting_content:true}`
     → `notion-update-page` `{page_id, command:"update_properties", properties:<properties>}`
     (`properties` 는 계획이 준 것만. `유형`·`상태` 를 임의로 더하지 않는다)
   - **검증** — `notion-fetch` 로 그 페이지를 다시 읽어 마크다운을 `<stage_dir>/fetched_<n>.md` 에 Write →
     `bash "${CLAUDE_PLUGIN_ROOT}/scripts/notion_plan.sh" verify "<key>" <stage_dir>/fetched_<n>.md --plan <계획>`.
     exit 1 이면 `replace_content` 를 **1회** 재시도 후 다시 verify. 그래도 실패면 그 문서는 `⚠`.
   - 로그 1줄(REST 와 같은 형식): `✅(신규|갱신) <key> → H<n>/T<n>/C<n> · <url>` / `⚠(…) <key> → <소실 코드>` / `✗ <key> → <사유>`
6. **고아 스윕** — `✗`·`⚠` 가 0건일 때만. 계획의 `abort` 가 있으면 **아무것도 바꾸지 않고** 사유를 보고한다.
   없으면 `orphans[]` 마다 `notion-update-page` `{page_id, command:"update_properties", properties:{"상태":"아카이브"}}`
   → `📦 아카이브: <title> ← <src>`. 실패는 `✗ 아카이브 실패: …` 로 남긴다.
7. **집계** — `성공 N(그중 검증실패 M) · 실패 K · 아카이브 A` + 페이지 URL 목록. `⚠` 가 하나라도 있으면
   「게시본이 원문과 다르다」 는 뜻이므로 그렇게 말한다.

### 실패는 반드시 사유와 함께 보고된다 — 조용한 유실 금지

| 줄 | 뜻 |
|---|---|
| `✅(신규/갱신) <key> → H/T/C · <url>` | 게시됨 · 구조 검증 통과 |
| `⚠(…) <key> → heading_lost …` | **게시본이 원문과 다르다** — 재시도 후에도 구조 소실. 원문은 GitHub 에 온전히 있다 |
| `✗ <key> → …` | 그 문서는 건너뜀(도구 오류·권한). **중복 생성 방지를 위해 재시도하지 않는다** |

권한 오류(문서함 편집 권한 없음)는 사용자에게 「문서함 DB 편집 권한 요청」 을 안내한다 — `notion-fetch` 가
되는 것과 쓰기가 되는 것은 다르다.

## 한계 (알고 쓴다)

- **보관(is_archived) 된 옛 게시본은 인덱스에 나오지 않는다** → 같은 출처경로의 새 페이지가 생길 수 있다.
  중복이 의심되면 Notion 휴지통에서 복원 후 재게시한다.
- Notion-flavored markdown 렌더는 REST 변환기(`md_to_notion.py`)와 다를 수 있다. 헤딩·표·코드 **개수**는
  verify 가 지키지만, 100행 초과 표의 분할 형태는 실측으로 확인한다.
- NFD 레거시 출처경로는 재게시(update)가 NFC 로 재기록한다. **중복 병합 자동화는 없다**(v1.21.0 — REST 전용
  `notion_normalize.sh` 삭제) — 중복 발견 시 낡은 쪽을 수동 아카이브한다.

## 원칙 (사용자 전역지침 준수)
- 개조식, 약점/리스크 우선 → 강점/근거 → 권고 구조.
- 검증 불가 항목은 "검증 필요" 명시.
- 중복 페이지 생성 금지: 계획의 `update` 를 따르고, `✗` 문서는 재시도하지 않는다.
