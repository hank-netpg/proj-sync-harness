# ax-harness 플러그인 마켓플레이스

AX 팀 내부용 Claude Code 플러그인 마켓플레이스입니다. 현재 **`proj-sync`** (GitHub↔Slack↔Notion 사업관리 동기화) 1종을 제공합니다.

## 설치 — 가장 쉬운 방법 (팀원 권장)

1. 받은 **`proj-sync.zip`** 을 VS Code 로 연 **프로젝트 폴더 안**에 저장하고 **압축을 풉니다**
2. 터미널(Windows 는 **Git Bash**)에서:  `bash proj-sync/install.sh`
3. `install.sh` 가 마켓플레이스 등록 → 플러그인 설치를 자동 처리 (여러 번 실행해도 안전)
4. **Claude Code 재시작** → `/ax:setup` → **`/ax:start`**(기존 사업 합류: DB 선택→clone→동기화) 또는 `/ax:init`(새 사업)

자세한 안내: [INSTALL.md](INSTALL.md)

> ⚠️ 설치·다운로드·push 는 **터미널에서 직접** 실행하세요. Claude 채팅창에 "실행해줘"라고 시키면 보안 기능이 막을 수 있습니다.

## 설치 — Git 저장소 방식 (관리자/업데이트 일괄 관리용)

```bash
claude plugin marketplace add hankeon/proj-sync-harness   # PRIVATE repo: gh 인증(ax-harness 멤버) 필요
claude plugin install ax@ax-harness
# 이후 업데이트:  claude plugin marketplace update ax-harness && claude plugin update ax@ax-harness
```

> 레포 루트 `.claude-plugin/marketplace.json` 이 이 git-url 등록을 지원한다 (`source: ./plugin/ax`).
> 이 방식으로 등록해야 `claude plugin update` 자동 업데이트가 GitHub 최신본을 가져온다.

## OS별 주의

| 항목 | Mac/Linux | Windows |
|---|---|---|
| 셸 | 기본 bash | **Git Bash 필수** (VSCode 터미널도 Git Bash 권장) |
| Python | `python3` | `python3` 없으면 `python` 자동 사용 |
| Git LFS | `brew install git-lfs` | <https://git-lfs.github.com> |
| 줄바꿈 | — | 저장소 `.gitattributes` 가 `.sh` 를 LF 로 고정(자동) |

## 구조

```
.
├─ .claude-plugin/marketplace.json   # 마켓플레이스 매니페스트 (plugins 목록)
├─ .gitattributes                    # .sh = LF 고정 (Windows CRLF 방지)
└─ proj-sync/                        # 플러그인 본체
   ├─ .claude-plugin/plugin.json
   ├─ commands/  skills/  scripts/  templates/
   └─ MANUAL.md                      # 설치·설정·운영 상세
```

플러그인 사용법 상세는 [proj-sync/MANUAL.md](proj-sync/MANUAL.md) 참고.
