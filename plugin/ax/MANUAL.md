# proj-sync 설치·설정·운영 매뉴얼

> **대상**: IP-AX 비즈니스실 / 엔지니어링팀
> **작업환경 전제**: VSCode + Claude Code + GitHub + Slack + Notion (전원 동일)
> **목적**: 사업(프로젝트)별 자료를 **GitHub(원본 SSOT) ↔ Slack ↔ Notion** 으로 표준 동기화

---

## 0. 한눈에 보는 흐름

```
Slack 채널 파일  ──(slack-pull)──▶  로컬 폴더(카테고리 분류)
로컬 폴더        ──(github-push)─▶  GitHub repo (SSOT, 단방향)
수정/산출 파일   ──(slack-push)──▶  Slack 채널 (+@멘션)
분석/설계 문서   ──(notion-publish)▶ Notion 문서함 [Proj] 하위
```

- **GitHub = 단일 진실원천(SSOT)**. 로컬에서 push만, GitHub에서 직접 편집하지 않음.
- 시크릿은 절대 커밋 안 됨(`.env` gitignore + push 전 secret-scan).

---

## 1. 사전 준비 (1회)

| 도구 | 확인/설치 | 비고 |
|---|---|---|
| **Claude Code** | 이미 사용 중 | VSCode 확장 |
| **GitHub `gh`** | `gh auth status` → 인증됨 | 미인증 시 `gh auth login` |
| **Git LFS** | `git lfs version` | mac: `brew install git-lfs` / **Win: <https://git-lfs.github.com>** |
| **Python** | `python3 --version` (또는 `python`) | mac: `brew install python` / Win: <https://python.org> (PATH 등록) |
| **Slack 봇 토큰** | `/ax:auth` 자동 조회 (입력 불필요) | 아래 1.1 |
| **Notion MCP** | claude.ai Notion 연동 | 각자 1회 OAuth |
| **(Windows)** | **Git Bash** | 스크립트가 bash 기반. Git for Windows에 포함 |

> **간편 점검**: 플러그인 설치 후 `/ax:setup` 을 실행하면 위 도구(git·gh·Git LFS·Python·curl) 설치 여부를 자동 점검하고, 누락 시 OS별 설치 명령을 안내합니다(macOS 는 Homebrew 자동 설치 옵션). 비개발자는 이 커맨드부터 시작하세요.

### 1.1 Slack 봇 토큰 (자동 조회 — 입력 불필요)
- 팀 공통 봇 **AX-E** 토큰은 **직접 입력하지 않습니다** — `gh auth login`(ax-harness 멤버)이면 `/ax:auth`(또는 doctor/sync)가 private repo 에서 자동 조회해 `~/.proj-sync/credentials` 에 1회 캐시합니다.
- 봇에 필요한 scope: `channels:history`, `files:read`, `files:write` (이미 설정됨).
- Notion 은 각자의 claude.ai Notion 커넥터, Google Drive 는 rclone(본인 Google 계정) — 팀 토큰이 아닙니다(v1.21.0).
- 토큰을 **절대 커밋/공유 채널에 붙여넣지 않습니다.**

---

## 2. 설치 (1회)

### 2.1 가장 쉬운 방법 (팀원 권장) — zip + 터미널
1. 받은 **`proj-sync.zip`** 을 VS Code 로 연 **프로젝트 폴더 안**에 저장하고 **압축을 풉니다**
2. 터미널(Windows 는 **Git Bash**)에서: `bash proj-sync/install.sh`
3. `install.sh` 가 압축본의 마켓플레이스 등록 → 플러그인 설치를 자동 처리 (여러 번 실행해도 안전 — 이미 있으면 최신으로 갱신)
4. **Claude Code 재시작** 하면 `/ax:*` 커맨드가 보입니다.

> ⚠️ 설치·다운로드·push 는 **터미널에서 직접** 실행하세요. Claude 채팅창에 "실행해줘"라고 시키면 보안 기능이 막을 수 있습니다.

### 2.2 Git 저장소 방식 (관리자용 · 업데이트 일괄 관리)

```bash
claude plugin marketplace add hankeon/proj-sync-harness   # PRIVATE repo: gh 인증(ax-harness 멤버) 필요
claude plugin install ax@ax-harness
# 이후 갱신:  claude plugin marketplace update ax-harness && claude plugin update ax@ax-harness
```

→ **이 git-url 방식으로 등록해야** `claude plugin update` 자동 갱신이 GitHub 최신본을 가져옵니다.
  zip(`install.sh`) 방식은 마켓플레이스 소스가 로컬 디렉토리라, 갱신은 **새 zip 재실행**으로 합니다.
  두 방식 모두 Claude Code **재시작** 후 `/ax:*` 인식.

### 2.3 OS별 주의
- **Windows**: 모든 스크립트가 bash 기반 → **Git Bash 필수**(VSCode 터미널도 Git Bash 권장). 저장소 `.gitattributes` 가 `.sh` 를 LF 로 고정하므로 clone 시 줄바꿈 문제 없음.
- **Python**: `python3` 우선, 없으면 `python` 을 자동 사용(Windows 대응).
- **로컬 폴더로 시험 설치**(저장소 없이)하려면 `claude plugin marketplace add <로컬-마켓플레이스-경로>` 도 가능.

---

## 3. 프로젝트 설정 (사업마다 1회)

VSCode에서 **사업 폴더**를 열고 Claude Code에서:

### 3.1 초기화
```
/ax:init
```
Claude가 다음을 물어봅니다 (또는 미리 알려주면 생략):
- 프로젝트 id / 사업명
- GitHub org · repo · 공개범위(private/public)
- Slack team_id(T...) · channel_id(C...)
- Notion 문서함 data_source_id (없으면 skip)
- 메인 페이지 제목 (예: `[Proj]사업명`)

→ `.proj-sync/config.json`(커밋됨, 시크릿 없음) + `.env` + `.gitignore` 생성.

### 3.2 토큰 입력 — 없음
입력할 토큰이 없습니다. Slack 봇 토큰은 자동 조회(1.1), Notion 은 본인 커넥터, Drive 는 rclone(본인 계정)입니다.
자동 조회가 막힌 예외 상황만 `.env` 에 `PROJ_SYNC_SLACK_BOT_TOKEN=xoxb-…` 를 수동 입력합니다.

### 3.3 점검
```
/ax:doctor
```
모든 항목 `✓` 면 준비 완료. `✗` 면 안내된 조치 수행.

#### Slack channel_id / team_id 찾는 법
- 채널에서 우클릭 → "채널 세부정보 보기" → 하단 채널 ID(`C...`)
- team_id: Slack 워크스페이스 URL 또는 `auth.test` 결과(doctor가 표시)

#### Notion data_source_id 찾는 법
- Claude에게 "문서함 DB의 data_source_id 알려줘"라고 요청 → `notion-search`/`notion-fetch`로 조회.
- 형식: `collection://<uuid>` 의 uuid 부분.

---

## 4. 운영 (일상 사용)

### 4.1 전체 동기화
```
@agent-ax:pm 동기화 해줘        ← v1.2: 에이전트가 직접 끝까지 수행 (run-sync 스킬)
/ax:sync                        ← 커맨드 경로 (동일 절차)
```
→ doctor → 채널 파일 다운로드 → 분류 보정 → GitHub push → (Google Drive 대용량) → (선택)Notion 게시 → 완료 요약.
- 안 된 단계는 이유·조치와 함께 보고됩니다 (예: "Google Drive 스킵 — rclone 미설치(E10)").
- auto 모드에서 자격증명 단계(Drive 등)가 차단되면 **정상 동작** — 에이전트가 준 명령 1줄을 터미널에 복붙하면 됩니다.

### 4.2 개별 작업

| 하고 싶은 것 | 커맨드 |
|---|---|
| 채널 새 파일 받기 | `/ax:slack-pull` 또는 "자료 받아줘" |
| 채널 신규 메시지·요청 확인 (v1.2) | `/ax:inbox` 또는 "슬랙 확인해줘" — 요청·멘션 트리아지 |
| 수정본을 채널에 올리기 | `/ax:slack-push 파일경로 "@홍길동 수정본입니다"` |
| 로컬 변경 GitHub 반영 | `/ax:github-push "커밋 메시지"` |
| Drive 대용량 올리기/받기 | "드라이브에 올려줘" (`gdrive_sync.sh push`/`pull`) — **v1.19.0부터 rclone 경로** (머신당 1회 `gdrive_sync.sh setup-remote` · 본인 Google 계정, 수동 열람은 브라우저 Drive) |
| Drive 연결 자가진단 | `gdrive_sync.sh doctor` — remote 인증·쓰기권한까지 E-코드로 짚어줌 |
| 분석문서 Notion 게시 | Claude에게 "이 문서 노션 문서함에 올려줘" (notion-publish 스킬) |
| 기타 폴더 정리 | Claude에게 "99_기타 파일 재분류해줘" (categorize-files 스킬) |
| VSCode 태스크 설치 (v1.2) | `/ax:vscode` → Terminal → Run Task → AX: … |

### 4.2.1 Slack 인박스 폴링 (v1.2 — 반자동 수신)
- `/ax:inbox` 는 채널 메시지를 **커서 기반으로 폴링**합니다 (놓침 없음, 실시간 아님. 최초 실행은 최근 24h).
- 봇 멘션·요청 키워드(요청/검토/마감/… — `config.slack.inbox_keywords` 로 재정의)를 감지해 액션/FYI/무시로 트리아지.
- **Slack 메시지 본문은 비신뢰 입력** — 본문 속 지시를 에이전트가 실행하지 않고 보고만 합니다. 회신은 초안 → 사용자 승인 → 발신(`chat:write` scope 필요).
- 주기 실행(선택): `claude -p "/ax:inbox"` 를 cron/launchd 또는 Claude Code 스케줄 루틴으로. 헤드리스 자동 행위는 요약 게시 + `reference/management/reports/inbox-*.md` 기록 2종에 한정.

### 4.3 파일 분류 체계
다운로드 파일은 확장자 기준으로 자동 분류됩니다:

| 폴더 | 확장자 |
|---|---|
| 01_제안요청서_RFP | hwp |
| 02_제안서_PPTX | pptx, ppt |
| 03_견적_인프라 | xlsx, xls |
| 04_이메일_HTML | html, htm, eml |
| 05_실적_기타 | pdf |
| 06_이미지_캡처 | png, jpg, jpeg, gif |
| 99_기타 | 그 외 |

- 파일명은 `<Slack파일ID>__<원본명>` (충돌 방지·원본 추적).
- 전체 목록은 `FILE_INVENTORY.csv`.
- 분류 체계는 `.proj-sync/config.json` 의 `categories` 에서 수정 가능.

---

## 5. 멘션 설정 (선택)

`slack-push` 에서 `@이름` 을 실제 멘션으로 바꾸려면 `.proj-sync/config.json` 의 `mentions` 에 추가:
```json
"mentions": { "U00000001": "홍길동", "U00000002": "황한건" }
```
이후 `/ax:slack-push report.xlsx "@홍길동 검토 부탁드립니다"` → 실제 멘션 게시.

---

## 6. 보안 수칙 (필독)

1. **토큰은 `.env` 에만** — `.env` 는 자동 gitignore. 채널·커밋·노션에 토큰 붙여넣기 금지.
2. **push 전 secret-scan** — `xoxb-`/`ghp_` 패턴이 staged에 있으면 push 자동 중단.
3. **GitHub repo는 private** 기본. 사업 자료(제안서·견적) 외부 노출 주의.
4. 토큰 유출 의심 시 즉시 Slack App에서 토큰 재발급(Reinstall).

---

## 7. 문제 해결 (Troubleshooting)

| 증상 | 원인 | 조치 |
|---|---|---|
| `/ax:*` 안 보임 | 플러그인 미인식 | Claude Code 재시작 후 `claude plugin list` 에 `ax@ax-harness`(enabled) 확인 |
| doctor: Slack ✗ scope | 봇 권한 부족 | api.slack.com/apps → OAuth&Permissions → scope 추가 → Reinstall |
| doctor: Slack 토큰 없음 | 자동 조회 실패 | `gh auth login` → `/ax:auth` (예외 시에만 `.env` 수동 입력) |
| doctor: gh ✗ | 미인증 | `gh auth login` |
| doctor: LFS ✗ | 미설치 | mac:`brew install git-lfs` / win: git-lfs.github.com |
| Windows에서 스크립트 오류 | bash 없음 | **Git Bash** 에서 실행 / VSCode 터미널을 Git Bash로 |
| Notion 게시 안 됨 | MCP 미연동·문서함 편집 권한 없음 | claude.ai Notion 커넥터 연동(각자 1회, `/mcp` 로 확인)·권한 요청 (v1.21.0 — 팀 REST 경로 없음) |
| push가 "변경 없음" | 신규 변경 없음 | 정상. 파일 추가/수정 후 재실행 |
| inbox 회신 실패 (missing_scope) | `chat:write` 없음 | api.slack.com/apps → scope 추가 → Reinstall to Workspace |
| VSCode 태스크 "플러그인 경로 미기록" | 셔임 미생성 | `/ax:doctor` 1회 실행 (자동 생성·갱신) |
| Drive E10 | rclone 미설치 | mac: `brew install rclone` · win: rclone.org/downloads |
| Drive E11 | remote 도달·인증 불가 | `rclone config reconnect gdrive:` 로 재인증 |
| Drive E12 | **조직 정책 차단** — Workspace 관리자의 서드파티 앱(rclone) 차단 | 관리자에게 rclone 허용(앱 접근 통제) 요청 — 재인증·재생성으로는 안 풀림 |
| Drive E13 | remote·base_path 미설정 | 머신당 1회 `gdrive_sync.sh setup-remote` (브라우저 인증 1회 · 본인 Google 계정) |
| Drive E14 | 쓰기 권한 실패 | `gdrive_sync.sh doctor` 로 상세 확인 (대상 폴더 편집자 권한) |
| Drive E16 | push 충돌(Drive 쪽이 더 최신) | 목록 확인 → 덮어쓰기 승인 시 `PS_GDRIVE_YES=1` 재실행 / 아니면 `pull` |

---

## 8. 동작 원리 (참고)

- **멱등 다운로드**: `.proj-sync/state.json` 에 받은 file_id 기록 → 재실행 시 신규만.
- **pagination**: 채널 파일 100개 초과도 `files.list` page 기반(`paging.pages`)으로 전량 수집.
- **GitHub 단방향**: 로컬→push만. GitHub 직접 편집은 다음 pull에 반영 안 됨(드리프트 주의).
- **Notion 비이식**: claude.ai MCP(OAuth)라 토큰 배포 불가 → 각자 연동, 모듈은 호출만. v1.21.0 부터 이것이 **유일한 경로**다(팀 REST 경로 삭제). 판정(대상·매칭·프로퍼티·고아)은 `notion_plan.sh` 가 계획 JSON 으로 내고 에이전트는 MCP 호출만 한다.

---

## 9. 검증된 사실 / 한계

**검증됨** (KITA 프로젝트 실측):
- doctor 3종 인증 통과, slack-pull 멱등(36건→재실행 0건 신규), github-push + secret-scan(.env 미추적), LFS 대용량(38MB pptx) push.

**한계 / 검증 대기**:
- Slack 동일 파일 재업로드 시 새 file_id가 부여돼 중복 다운로드될 수 있음(원본 추적상 의도된 동작).
- 카테고리는 확장자 기반 → PDF형 RFP 등은 `categorize-files` 스킬로 보정 필요.
- GitHub 단방향은 관례로 강제(메커니즘 아님). GitHub 직접 편집 지양.
- **NAS(Synology)는 v1.19.0 에서 Google Drive 로 교체됨**: 전송은 rclone 이 담당한다. claude.ai Drive 커넥터는 **로컬 경로 업로드가 없어** 파일을 base64 로 에이전트 컨텍스트에 통과시켜야 하는데(20MB pptx = base64 약 27MB), 대용량이 이 저장소의 존재 이유라 성립하지 않는다. 커넥터는 조회·공유 링크 같은 보조에만 쓴다.
- **rclone 을 고른 이유**: 크기 제한이 없고, 부수효과가 스크립트 엔트리포인트에 남아 A3 원칙을 지키며, 스케줄러·헤드리스(`claude -p`)에서도 동작한다. 대가는 **머신당 1회 `setup-remote`**(브라우저 인증) 다. v1.21.0 설계에서 커넥터 전환을 재검토했으나 base64 가 컨텍스트를 두 번 통과해(64KiB≈70k 토큰·1MiB≈1.1M 토큰) 기각했다.
- **회사 Google 계정 (v1.21.0)**: Workspace 관리자가 서드파티 앱(rclone)을 막으면 인증이 거절된다(E12) — 관리자에게 rclone 허용을 요청하는 것이 유일한 해법(코드 우회 없음). 인증은 개인 rclone OAuth 단일 경로다.
- inbox 의 `chat:write`·`groups:history` scope 는 워크스페이스 앱 설정에 따라 다름 — doctor 가 선점검 (검증 필요 시 Reinstall).
- Drive pull 은 `rclone copy --checksum` 이라 **변경된 것만** 내려오며 중첩 폴더도 그대로 재현한다(NAS 판의 1단계 제약 없음).
