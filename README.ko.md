# proj-sync (ax) — 프로젝트 동기화 도구

비개발자 팀원이 **GitHub · Slack · Notion · Google Drive** 를 한 번에 동기화하도록 모듈화한 사업관리 도구.

> ⚠️ **이 레포는 도구만 담는다.** 특정 사업(sample-b2g 등)의 config·산출물·인벤토리는 **각 사업 레포**에 둔다.

## 구성

| 경로 | 내용 |
|------|------|
| `src/proj-sync-onboard.sh` | 온보딩 실행 스크립트 (→ 배포 시 `proj-sync-setup.sh`) |
| `build.sh` | 배포본 `proj-sync.zip` 빌드 (레포 내 `plugin/` 사용, 자기완결) |
| `plugin/ax/` | 플러그인 본체 (scripts·agents·commands·skills) |
| `GUIDE.md` | 설치·온보딩 가이드 (팀원용) |
| `MANUAL.md` | 설치 후 사업관리 매뉴얼 |
| `dist/ARCHITECTURE.md` | 동작 구조 (Mermaid 17) |
| `proj-sync.zip` · `proj-sync-dist.zip` | 배포 산출물 |

## 빌드 (담당자)

```bash
bash build.sh        # → proj-sync.zip (plugin/ 본체 사용)
```

본체는 **레포 내 `plugin/` 만** 사용한다(자기완결). 외부 사본(`~/.claude/marketplaces-local/…`)으로 폴백하지 않는다 — 그 자리에는 옛 zip 설치본이 남아 있을 수 있어 구버전이 배포본에 섞인다.

> ⚠️ **zip 은 git 에 추적하지 않는다** (빌드 산출물). 배포본은 아래 Release 로 호스팅한다.

## 커밋 메시지 규약

**코드가 「무엇」을 말하니 커밋은 「왜」를 말한다.**
[Conventional Commits v1.0.0](https://www.conventionalcommits.org/ko/v1.0.0/) + git 72칸 규칙 —
상세는 [plugin/ax/COMMIT_CONVENTION.md](plugin/ax/COMMIT_CONVENTION.md).

```bash
git config core.hooksPath .githooks   # 1회 — 위반 커밋을 로컬에서 막는다
```

- 형식: `type(scope): 설명` · type 11종 · 릴리즈는 `chore(release):`
- 길이는 **문자 수가 아니라 표시 폭** — 한글은 한 자가 2칸이다(72칸 ≈ 한글 36자)
- 스쿼시 머지라 **PR 제목이 곧 커밋 제목**이다. `lint.yml` 의 `commit-title` 잡이 막는다

## 릴리즈 (담당자) — 배포본 호스팅

### 자동 (권장) — 태그 push 하면 GitHub Actions 가 빌드·릴리즈

```bash
# 1) 버전 올리기: plugin/ax/.claude-plugin/plugin.json 의 version 수정
# 2) 버전 라벨 동기화: dist/ARCHITECTURE.md (헤더 1행 + 'ax 플러그인' subgraph)
#    ↳ 빠뜨리면 lint·release 가 막는다(게이트). 이 파일은 proj-sync-dist.zip 에 실려 팀원에게 간다.
# 2-1) 게시본 현행화: docs/notion/whats-new.md 를 이번 릴리즈 내용으로 갱신
#      + docs/notion/{overview,onboarding-guide,proposal-pipeline-guide,secrets-admin}.md 의 버전 라벨
#      ↳ 게이트가 없는 수동 단계다. 빠뜨리면 팀원이 보는 Notion 문서함이 옛 버전에 머문다
#        (실제로 v1.16.0 게시본이 4개 릴리즈 뒤처졌다 — 2026-08-28 확인). 게시는 notion-publish.
# 3) 커밋·push
# 4) 같은 버전으로 태그 push → .github/workflows/release.yml 가 자동 실행
VER=$(grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' plugin/ax/.claude-plugin/plugin.json | head -1)
git tag "v$VER" && git push origin "v$VER"
```

워크플로(`release.yml`)가 **태그·plugin.json 버전 일치 검증 → manifest 검증 → build.sh → dist zip → Release 생성/갱신**을 수행한다. (태그가 plugin.json 버전과 다르면 실패)

### 수동 (폴백)

```bash
bash build.sh                                   # proj-sync.zip 생성
cp proj-sync.zip dist/proj-sync.zip             # dist 동기화
( cd dist && zip -qX ../proj-sync-dist.zip ARCHITECTURE.md 0_READ_FIRST.md GUIDE.md MANUAL.md proj-sync.zip )
VER=$(grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' plugin/ax/.claude-plugin/plugin.json | head -1)
gh release create "v$VER" proj-sync.zip proj-sync-dist.zip --title "v$VER" --notes "ax v$VER"
# 이미 있으면:  gh release upload "v$VER" proj-sync.zip proj-sync-dist.zip --clobber
```

## 배포 (팀원)

- **최초 설치**: 담당자가 보낸 (또는 Releases 에서 받은) `proj-sync.zip` → 압축 풀고 → `bash proj-sync-setup.sh` → 메뉴 1) 초기 세팅
- **업데이트(zip 방식, 기본)**: 새 `proj-sync.zip` 재실행 → Claude Code 재시작
- **업데이트(git-url 방식)**: 마켓플레이스를 **사내 git-url 로 등록한 경우에만** 동작 —
  ```bash
  claude plugin marketplace add hank-netpg/proj-sync-harness   # 최초 1회 (PRIVATE repo: gh 인증 필요)
  claude plugin install ax@ax-harness                  # 설치
  # 이후 업데이트:  claude plugin marketplace update ax-harness && claude plugin update ax@ax-harness
  ```
  > ⚠️ zip 의 `install.sh` 로 설치한 경우 마켓플레이스 소스가 **로컬 디렉토리**라 위 `update` 가 GitHub 최신본을 못 가져온다. git-url 자동 업데이트를 쓰려면 위 `add hank-netpg/proj-sync-harness` 로 **다시 등록**해야 한다.

자세한 절차는 [GUIDE.md](GUIDE.md) · [MANUAL.md](MANUAL.md) 참고.
