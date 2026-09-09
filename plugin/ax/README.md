# proj-sync

프로젝트 **사업관리 동기화** Claude Code 플러그인 — **GitHub(SSOT) ↔ Slack ↔ Notion** 을 표준 절차로 묶습니다.

Slack 채널의 사업 파일을 로컬로 받아 정리하고, GitHub에 단방향 동기화하며, 수정본을 Slack에 올리고, 분석 문서를 Notion 문서함에 게시하는 흐름을 슬래시 커맨드 + 스킬로 모듈화했습니다.

> 전체 설치·설정·운영은 **[MANUAL.md](./MANUAL.md)** 참고.

## 빠른 시작

```
1. 설치:  claude plugin marketplace add <사내-git-url>
          claude plugin install ax@ax-harness   → Claude Code 재시작
2. /ax:setup                       → 사전 도구 점검·설치 (머신당 1회)
3. 프로젝트 폴더에서  /ax:init     → config·.env 생성
4. 토큰 입력 없음 — Slack 봇 토큰은 자동 조회(/ax:auth), Notion 은 각자 claude.ai 커넥터,
   Google Drive 는 gdrive_sync.sh setup-remote (본인 Google 계정 · 브라우저 1회)
5. /ax:doctor                      → 인증 점검 (✓ 모두여야 함)
6. /ax:sync                        → 전체 동기화
```

## 커맨드

| 커맨드 | 역할 |
|---|---|
| `/ax:setup` | 사전 도구(git·gh·LFS·Python) 점검 + 설치 안내 (머신당 1회) |
| `/ax:init` | 프로젝트 초기화 (config·.env·.gitignore·.vscode/tasks.json) |
| `/ax:doctor` | GitHub/Slack/LFS/Notion/Drive 인증·scope 점검 + 셔임 갱신 |
| `/ax:slack-pull` | 채널 전 파일 다운로드 + 카테고리 분류 + CSV |
| `/ax:slack-push <파일> [메시지]` | 파일 업로드 (+@멘션) |
| `/ax:github-push [메시지]` | LFS + secret-scan + commit + push |
| `/ax:sync` | 위 전체 오케스트레이션 (run-sync 스킬과 동일 절차) |
| `/ax:inbox` | Slack 신규 메시지 폴링 → 요청 트리아지 (v1.2) |
| `/ax:vscode` | 기존 프로젝트에 VSCode 태스크 설치 (v1.2) |
| `/ax:phase` `/ax:auth` `/ax:start` `/ax:registry-sync` | 단계 전환 / 토큰 1회 설정 / 프로젝트 합류 / 레지스트리 현행화 |

## 스킬 (Claude 판단 필요)

| 스킬 | 역할 |
|---|---|
| `run-sync` | **전체 동기화를 에이전트가 직접 끝까지 수행** — "동기화 해줘" (v1.2) |
| `inbox` | Slack 인바운드 폴링·트리아지 (커서 기반, 본문=비신뢰 입력) (v1.2) |
| `categorize-files` | 99_기타·오분류 파일을 내용 기반 재분류 |
| `notion-publish` | 문서를 Notion 문서함 `[Proj]` 하위에 게시 |
| `start-from-notion` | Notion 통합 사업 DB → 프로젝트 기반 생성 |
| `manage-deliverable`·`manage-schedule`·`manage-risk`·`manage-config` | PM 4대 관리 전문 스킬 (read-only) |

## 설계 원칙

- **GitHub = SSOT, 단방향**: 로컬→push. Slack/Notion은 git 문서 기준 게시. 사무파일 대용량은 Google Drive.
- **Google Drive 는 rclone 으로 (v1.19.0)**: 마운트 없이 rclone 단일 경로 — OS 무관, 크기 제한 없음, 헤드리스 동작. claude.ai Drive 커넥터는 로컬 경로 업로드가 없어(base64 가 컨텍스트를 두 번 통과 — 1MiB≈1.1M 토큰) 대용량에 쓸 수 없다 — 커넥터는 조회·공유 보조. remote 는 `setup-remote` 가 rclone 기본 client 로 만든다(본인 Google 계정 · 머신당 1회 브라우저 인증, v1.21.0).
- **에이전트 직접 실행 (v1.2)**: PM/PL 이 부수효과 작업을 수행하되, **`scripts/*.sh` 엔트리포인트 또는 로그인 사용자 명의의 claude.ai 커넥터(MCP)로만** — 인라인 curl·토큰 취급·`rm`/`mv`·force push 금지. Notion 게시는 MCP(판정은 `notion_plan.sh` 계획 JSON), Slack·git·Drive 는 스크립트.
- **시크릿 분리 (v1.21.0 — 사용자 개인 계정 체제)**: GitHub=기존 `gh auth` / Slack=**팀 봇 토큰**(secrets repo 자동조회, 유일한 팀 토큰) / Drive=rclone 보관(본인 Google 계정) / Notion=claude.ai 커넥터(각자 OAuth, 명의=본인 — 팀 REST 경로는 v1.21.0 에서 삭제). 토큰은 스크립트가 내부 해석 — 에이전트는 만지지 않음.
- **멱등**: state.json(다운로드)·"변경 없음 커밋 생략"(push)·rclone 체크섬(Drive) — 어느 단계 재실행도 안전.
- **9원칙 기본 탑재 (v1.17.0)**: 모든 사업에 `reference/9원칙.md`(원칙 본문)·`CLAUDE.md`(프로젝트 슬롯)를 스캐폴드. 각 원칙에 **위반 신호·확인 방법**을 병기 — 원칙은 선언이 아니라 **감지 방법**이 있어야 지켜진다. 개인 전역 설정이 아니라 저장소에 두므로 clone 한 팀원에게도 동일 적용.

## 요구 환경

VSCode + Claude Code(개인 계정) + GitHub(`gh`) + Slack(팀 봇 토큰) + Notion(각자 claude.ai 커넥터) + Google Drive(rclone, 본인 계정). macOS/Linux는 기본 bash, **Windows는 Git Bash** 필요 (MANUAL 참고).
