---
description: "프로젝트 시작 — 수행 프로젝트 DB(레지스트리)에서 먼저 확인해 있으면 선택, 없을 때만 신규 생성"
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/registry.sh:*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/init.sh:*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh:*)", "Bash(gh repo list:*)", "Bash(gh repo view:*)", "Bash(gh search repos:*)", "Bash(ls:*)", "Bash(pwd:*)"]
---

**반드시 레지스트리(수행 프로젝트 DB 미러)를 먼저 확인합니다.** 아래 목록이 자동으로 출력됩니다 — 곧장 수동 입력을 받지 마세요.

```!
bash ${CLAUDE_PLUGIN_ROOT}/scripts/registry.sh list
```

위 목록을 사용자에게 보여주고 **반드시 먼저 물으세요**: "이 중에 합류할 프로젝트가 있나요, 아니면 새 사업인가요?"

## A) 목록에 있음 → 기존 프로젝트 합류 (대부분 이 경우)
새 repo·채널을 만들지 말고 **clone** 합니다(설정·문서 자동 확보). `/ax:start` 와 동일:
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/registry.sh clone <id>
```
- 이미 이 폴더에 config만 만들고 싶으면: `PS_FROM_REGISTRY=<id> bash ${CLAUDE_PLUGIN_ROOT}/scripts/init.sh`
- 이후 `/ax:doctor` → `/ax:sync`.

### A-1) 선택한 프로젝트에 Slack 채널이 없으면 — 대화형 보강
`registry.sh get <id>` 의 `PS_SLACK_CH` 또는 clone된 config의 `slack.channel_id` 가 **비어 있으면**, 곧장 슬랙 동기화가 안 되므로 **사용자에게 대화형으로 채널을 받아 반영**하세요:
1. 질문: *"이 프로젝트의 Slack 채널 ID(`C…`)를 알려주세요. (Slack에서 채널명 클릭 → 하단 '채널 ID' 복사)"*
2. 받은 값을 **세 곳에 반영**:
   - **로컬 config**: `.proj-sync/config.json` 의 `slack.channel_id`(필요 시 `slack.team_id`) 수정 → 바로 동기화 가능.
   - **Notion 수행 프로젝트 DB(사람용 SSOT)**: Notion MCP로 data_source `1c0806c9-66d1-438c-9969-8ac98e7398be` 에서 `project_id=<id>` 행을 찾아 `slack_ch`(team/channel)·`Slack`(URL) 갱신. ⚠️ *SSOT라 반드시 반영 — 안 하면 다음 `registry-sync` 때 registry.json이 DB 기준으로 재생성되며 채널이 지워짐.*
   - **미러**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/registry.sh setch <id> <C…>` 로 registry.json 즉시 갱신.
3. 그 채널에 **`@AX-E` 봇 초대**(`/invite @AX-E`) 안내.

> Notion DB 편집 권한이 없는 팀원이면: 채널 ID를 PM/관리자에게 전달해 DB에 반영 요청(로컬 config만 임시 수정해 진행). SSOT는 Notion DB입니다.

## B) 목록에 없음 → 신규 사업 (PM만)
목록에 정말 없을 때만 새로 만듭니다.

### B-0) 작업 디렉터리 청결 점검 (질문 시작 전 필수)
> init.sh는 **현재 디렉터리(CWD)에 `.proj-sync/`·`.gitignore`·`.vscode`·`CLAUDE.md`·`reference/9원칙.md`·(이후 `.git`)를 그대로 스캐폴드**합니다. 엉뚱한 폴더에서 실행하면 남의 프로젝트/홈 디렉터리를 오염시키므로, **질문을 시작하기 전에 CWD가 깨끗한지 먼저 확인**하세요.
```
pwd            # 지금 이 경로가 이 신규 사업 전용 폴더가 맞는지 확인
ls -A          # 숨김 포함 폴더 내용
```
결과에 따라:
- **`.proj-sync/` 이미 있음** → 이미 초기화된 폴더. 🛑 **중단** — 재설정이 목적이면 `PS_FORCE=1` 안내, 아니면 새 빈 폴더로 이동.
- **`.git/` 이미 있음** → 이미 다른 repo. 🛑 **중단** — 신규 사업은 빈 폴더에서 시작. 잘못된 위치일 가능성 큼(사용자에게 경로 확인).
- **폴더가 비어있지 않음(다른 파일 존재)** → ⚠️ **경고**: *"현재 폴더가 비어있지 않습니다(`<파일 목록>`). 계속하면 여기에 `.git`·`.proj-sync`가 생성됩니다. 이 위치가 맞습니까? 보통은 **빈 폴더**에서 실행합니다."* — 명시적 확인을 받기 전엔 진행하지 마세요.
- **비어있음(또는 무해한 파일뿐)** → ✅ 통과, B-1로 진행.

**⚠️ 값을 한 번에 나열해 받지 마세요.** 아래 순서대로 **한 항목씩 질문 → 답을 받아 저장 → 다음 항목**으로 진행하며 모읍니다. 각 항목마다:
- 사용자가 이미 앞 대화/인자에서 준 값이 있으면 그 항목은 건너뜁니다.
- 기본값이 있는 항목은 질문에 기본값을 제시하고, 빈 답이면 기본값 채택.
- 모든 항목을 다 모은 뒤 **마지막 단계에서 한 번만** `init.sh` 를 호출합니다.

### B-1) 순차 질문 순서 (한 번에 하나씩)
1. **project_id** — 영문 짧은 id (init 매칭 키, 이후 변경 금지) → `PS_PROJECT_ID`
2. **프로젝트명** → `PS_PROJECT_NAME`
3. **발주처(client)** → 등록 JSON `client`
4. **담당팀(team)** — 쉼표로 여러 개 가능, 없으면 빈값 → 등록 JSON `team[]`
5. **GitHub org** — 기본 `ax-harness` → `PS_GH_ORG`
6. **GitHub repo** — **반드시 `-doc`로 끝나는 문서 repo.** 곧장 받지 말고 아래 **B-1a**(gh 중복·재사용 점검)를 거쳐 결정 → `PS_GH_REPO`
7. **visibility** — `private`/`public`, 기본 `private` → `PS_GH_VIS`
8. **Slack team_id** — `T…` → `PS_SLACK_TEAM`
9. **Slack channel_id** — `C…` (없으면 빈값, A-1처럼 나중에 보강 가능) → `PS_SLACK_CH`
10. **phase(생애주기)** — 제안/수주/수행중/완료/보류/실주, 기본 `제안` → `PS_PHASE`
11. **profile(산출물 세트)** — b2g/b2b/internal, 기본 `b2g` → `PS_PROFILE`
12. **(선택) Notion 문서함 data_source_id** → `PS_NOTION_DS`, **root_page** 기본 `[Proj]<id>` → `PS_ROOT_PAGE`. 게시는 **각자의 claude.ai Notion 커넥터**가 하므로 토큰 입력은 없습니다(v1.21.0, `provider` 기본 `claude_ai_mcp`).
13. **(선택) Google Drive 대용량** — `PS_GDRIVE_TEAM`(팀 폴더) · `PS_GDRIVE_REMOTE`(기본 `gdrive`) · 공유 드라이브면 `PS_GDRIVE_TEAM_DRIVE_ID`. 자격증명은 rclone(본인 Google 계정)이 보관하므로 `.env` 불요. remote 는 사업 폴더에서 `gdrive_sync.sh setup-remote` 1회(브라우저 인증). 안 쓰면 건너뜀.
14. **1순위 정의** — 이 사업이 9원칙보다 위에 두는 가치 → `PS_PRIORITY1`
15. **회귀 게이트** — 변경 전후 반드시 돌릴 명령과 합격 기준 → `PS_REGRESSION_GATE`

> 12·13은 선택이므로 "Notion 문서함/Google Drive 설정할까요?"로 한 번 물어 원치 않으면 통째로 건너뜁니다.

### B-1b) 14·15 는 왜 묻는가 — 안 물으면 슬롯이 빈 채로 남는다 (issue #25)

`reference/9원칙.md` §0 은 우선순위를 이렇게 규정합니다:

```
[1순위]  <이 프로젝트의 핵심 가치>   ← 프로젝트별로 정의. 미정의면 2순위가 최상위
[2순위]  9원칙 전부
[3순위]  시간·비용 효율
```

그리고 §7 은 **"비어 있으면 이 문서는 절반만 작동한다"** 고 못박습니다.
스캐폴드는 두 슬롯을 `_(미정 — 채울 것)_` 로 만들 뿐이라, **묻지 않으면 아무도 채우지 않습니다.**
즉 질문을 빼면 **설계상 절반만 작동하는 상태가 기본값**이 됩니다.

**14. 1순위 정의** — 선택지를 제시하고 고르게 하세요(직접 입력도 허용):

> *"이 사업이 9원칙보다도 위에 두어야 할 가치는 무엇입니까?
> (a) 데이터 정확성 (b) 응답 지연 (c) 규정 준수 (d) 사용자 안전 (e) 직접 입력"*

- 공공 사업이면 대개 **(c) 규정 준수** 또는 **(a) 데이터 정확성** 입니다. 다만 **대신 고르지 말고 확인**받으세요.

**15. 회귀 게이트** — **"없음"도 유효한 답**입니다:

> *"변경 전후에 반드시 돌려야 할 명령과 합격 기준이 있습니까?
> 사업 초기라 없으면 '없음'이라고 답해 주세요 — 왜 없는지만 함께 적습니다."*

- 있으면 명령과 합격 기준을 그대로 적습니다 (예: `bash tests/run.sh` → 전건 통과).
- 없으면 **"없음 — 사업 초기로 회귀 대상 코드 없음"** 처럼 **이유까지** 적습니다. 템플릿 주석이 그렇게 지시합니다.

> SSOT 위치는 표준값이 이미 채워져 있으므로 묻지 않습니다.

### B-1a) GitHub repo 이름 결정 — gh로 중복·재사용 점검 (step 6 세부)
> 🔒 **철칙: 문서 SSOT repo는 이름이 `-doc`로 끝나는 것만 사용/생성.** `-doc`로 끝나지 않는 repo는 **개발 repo**이므로 절대 문서용으로 쓰지 마세요.
> 컨벤션: `ax-<slug>-doc` (예: `ax-ipanal-doc`, `ax-kita-trade-platform-doc`).

1. **후보 이름 제안** — `PS_GH_ORG`/`project_id`·프로젝트명으로 `ax-<slug>-doc` 형태 후보를 만들어 제시.
2. **조직의 기존 `-doc` repo 목록 조회** (재사용 후보 파악):
   ```
   gh repo list <org> --limit 300 --json name,description,visibility \
     -q '.[] | select(.name|endswith("-doc")) | "\(.name)\t\(.description // "")"'
   ```
   목록을 사용자에게 보여주고, **이미 이 사업에 맞는 `-doc` repo가 있으면 그걸 재사용**할지 물으세요.
3. **⚠️ 관련 repo 경고** — slug로 조직 전체를 검색해 **이름이 겹치는 다른 repo**(특히 `-doc`가 아닌 **개발 repo**)가 있으면 경고합니다:
   ```
   gh search repos --owner <org> "<slug>" --limit 50 --json name,description \
     -q '.[] | "\(.name)\t\(.description // "")"'
   ```
   - **비-`doc` repo(개발 repo)가 검색되면** → ⚠️ *"이 사업 관련 개발 repo(예: `ax-<slug>`, `ax-<slug>-app`)가 이미 있습니다. 사업이 이미 진행 중일 수 있으니 (a) 문서 repo 이름을 개발 repo와 **slug를 맞춰** `-doc`로 만들고, (b) 정말 신규인지 PM에게 확인하세요."* 라고 사용자에게 알립니다. (개발 repo를 문서용으로 쓰지는 않음 — 경고·정렬 목적)
   - **유사 `-doc` repo가 있으면** → 오타·중복 생성 위험이므로 재사용/이름차이를 재확인.
   - 겹치는 repo가 없으면 조용히 통과.
4. **결정한 이름의 존재 여부 확인**:
   ```
   gh repo view <org>/<repo> --json name,visibility -q '.name'   # 있으면 이름 출력, 없으면 비정상종료
   ```
   결과에 따라 분기:
   - **없음 + `-doc`로 끝남** → ✅ 신규 문서 repo로 생성 진행. `PS_GH_REPO=<repo>` 확정. (repo 생성은 init.sh/후속 push 흐름이 처리)
   - **있음 + `-doc`로 끝남** → ♻️ 기존 문서 repo. "이 `-doc` repo를 재사용할까요?"로 확인 후 `PS_GH_REPO`·`PS_GH_VIS`를 기존 값에 맞춤. (A 경로 clone이 더 적절할 수 있음 — 이미 이 사업의 repo라면 신규 생성 대신 합류 권유)
   - **있음 + `-doc` 아님** → ⛔ **개발 repo**. 문서용 금지. `-doc`가 붙은 다른 이름을 제안해 1번으로 복귀.
   - **입력 이름이 `-doc`로 안 끝남** → ⛔ 거부하고 `-doc`를 붙인 이름으로 유도.
5. 확정된 `PS_GH_REPO`(항상 `-doc` 접미사)를 들고 나머지 step(7~)을 계속.

### B-2) 수집한 값 확인 후 생성
모은 값을 **한 번 요약해 보여주고 확인**받은 뒤 init.sh 호출:
```
PS_PROJECT_ID=… PS_PROJECT_NAME=… PS_GH_ORG=ax-harness PS_GH_REPO=… PS_GH_VIS=private \
PS_SLACK_TEAM=… PS_SLACK_CH=… PS_PHASE=제안 PS_PROFILE=b2g \
PS_PRIORITY1='…' PS_REGRESSION_GATE='…' \
bash ${CLAUDE_PLUGIN_ROOT}/scripts/init.sh
```
> 생성 후 `wbs.tasks`·세부 단계는 **PM 에이전트(`@agent-ax:pm`)가 profile 기준 표준 산출물을 자동 전개·추적**. 사용자는 phase·profile 만 정하면 됨.

### B-3) 레지스트리 등록
생성 후 **반드시 레지스트리에 등록**(다음 사람이 선택할 수 있도록):
1. 입력값으로 프로젝트 1건 JSON 작성(스키마: id·name·team·client·status·github·slack·notion — registry.json 참고)
2. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/registry.sh append <project.json>`
3. Notion **수행 프로젝트 DB**에도 행 추가 권장(`/ax:registry-sync` 또는 직접).

## 공통 마무리
`.env` 토큰은 입력 불필요(Slack 자동조회 · Notion 은 각자 커넥터 · Drive 는 rclone) → `/ax:doctor` → `/ax:sync`.

> ℹ️ 목록(레지스트리 `registry.json`)은 Notion **수행 프로젝트 DB**의 미러입니다. 비어 보이면 `/ax:registry-sync`로 최신화하거나 gh 로그인(조직 멤버)·repo 접근을 확인하세요.
