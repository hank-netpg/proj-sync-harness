# 커밋 메시지 규약

> 근거: [Conventional Commits v1.0.0](https://www.conventionalcommits.org/ko/v1.0.0/) + git 관례(72칸 규칙)

## 원칙 한 줄

**코드가 「무엇」을 말하니 커밋은 「왜」를 말한다.**

`git diff` 를 보면 무엇이 바뀌었는지는 안다. 커밋이 그것을 다시 적으면 두 벌이 된다.
6개월 뒤 이 줄을 `git blame` 하는 사람에게 필요한 것은 **그때 무엇이 문제였는가** 다.

```
✗ md_to_notion.py 의 정규식을 #{1,3} 에서 #{1,6} 으로 바꿈
    → diff 를 읽으면 아는 것을 반복한다

✓ h4+ 헤딩이 게시본에서 문단으로 떨어지던 문제
    실측: 제안서 370파일 중 168파일 · 헤딩 368개(26.2%) 소실
    Notion 은 heading_1~3 만 있으므로 h4+ 는 heading_3 으로 접는다 —
    계층 한 단계는 잃지만 제목이라는 사실은 지킨다
    → 왜 고쳤고 왜 그 방법을 골랐는지가 남는다
```

## 형식

```
<type>(<scope>)<!>: <설명>
                      ← 빈 줄
<본문 — 왜>
                      ← 빈 줄
<꼬리말>
```

### type (11종)

| type | 쓸 때 | 버전 영향 |
|---|---|---|
| `feat` | 기능 추가 | MINOR |
| `fix` | 결함 수정 | PATCH |
| `docs` | 문서만 | — |
| `refactor` | 동작 변화 없는 구조 변경 | — |
| `perf` | 성능 | PATCH |
| `test` | 테스트만 | — |
| `build` | 빌드·배포 산출물 | — |
| `ci` | 워크플로 | — |
| `chore` | 그 외 잡무 | — |
| `style` | 서식만(동작 무관) | — |
| `revert` | 되돌리기 | — |

- **릴리즈는 `release:` 가 아니다.** 스펙에 없는 type 이다 → `chore(release): v1.2.3 — 요약`
- 破壞적 변경은 `feat(api)!: …` 또는 꼬리말 `BREAKING CHANGE: <이유>`

### scope

바뀐 영역. 이 저장소에서 쓰는 값: `notion` · `slack` · `gdrive` · `init` · `win` ·
`release` · `hook` · `architecture` · `commit`. 없으면 생략한다.

## 길이 — 한글은 **표시 폭**으로 잰다

72는 **문자 수가 아니라 표시 폭**이다. `git log` 는 본문을 4칸 들여쓰므로 80칸 터미널
기준 76이 상한이고, 관례로 72를 쓴다. **한글·CJK 는 한 자가 2칸**이므로 72칸 ≈ 한글 36자다.

| 대상 | 상한 | 권장 |
|---|---|---|
| 제목 | **72칸** | 50칸 |
| PR 제목 | **64칸** | — |
| 본문 각 줄 | **72칸** | — |

> **PR 제목이 64칸인 이유** — 이 저장소는 **스쿼시 머지**라 PR 제목이 그대로 커밋 제목이
> 된다. GitHub 이 뒤에 ` (#123)` 을 붙이므로, 64칸을 넘기면 최종 커밋 제목이 72칸을 넘는다.

문자 수로만 재면 한글 커밋은 전부 통과하면서 터미널에서는 접힌다.

```
실측 (2026-08-30, 최근 60커밋)
  제목  문자 수 기준 위반 0건  →  표시 폭 기준 17건 (최대 90칸)
  본문  54/60 커밋 · 342줄이 72칸 초과 (최대 220칸)
        269줄이 80칸 터미널에서 접힘
```

## 본문 — 무엇을 적나

- **왜 고쳤나** — 어떤 증상이 있었고 누가 겪었나
- **왜 이 방법인가** — 다른 선택지를 왜 버렸나
- **실측** — 수치가 있으면 넣는다. `26.2%`, `370파일 중 168파일`
- **한계** — 이 수정이 덮지 못하는 것

`feat` · `fix` · `refactor` · `perf` 는 **본문을 반드시 적는다.** 나머지는 제목이
자명하면 생략해도 된다.

## 꼬리말

```
Closes #38                      이슈 종료 (GitHub 자동 연결)
Refs #21                        관련 이슈
BREAKING CHANGE: <이유>          破壞적 변경 — MAJOR
Co-Authored-By: 이름 <메일>
```

## 검사 — 자동으로 막는다

### 로컬 (커밋 시점)

```bash
git config core.hooksPath .githooks     # 1회
```

위반하면 커밋이 **차단**된다. 동기화 훅과 달리 막는 이유는, 커밋 메시지는 로컬에서
즉시 고칠 수 있고 한 번 push 되면 되돌리는 데 히스토리 재작성이 필요하기 때문이다.

- 한 번만 건너뛰기: `git commit --no-verify`
- 직접 실행: `bash plugin/ax/scripts/lint_commit_msg.sh <메시지파일>`

### 사업 저장소에 설치 (팀원)

이 규약은 **사업 저장소의 커밋에도 적용**된다. 훅 템플릿이 플러그인에 함께 배포된다.

```bash
AX="$(ls -d ~/.claude/plugins/*/ax 2>/dev/null | head -1)"   # 플러그인 사본 경로
mkdir -p .githooks && cp "$AX/templates/commit-msg" .githooks/
chmod +x .githooks/commit-msg
git config core.hooksPath .githooks
```

검사기를 못 찾으면 훅은 **조용히 통과**한다 — 도구가 없다는 이유로 커밋을 막으면
그 사람은 훅을 꺼 버린다.

`/ax:github-push` 의 기본 메시지는 `chore(sync): 동기화 YYYY-MM-DD` 다. 직접 준 메시지가
규약과 다르면 **알리기만 하고 커밋은 진행**한다 — 동기화를 막으면 팀원이 플러그인을 끈다.
규약을 강제하는 자리는 commit-msg 훅과 PR 제목이다.

### CI (PR 시점 — 실제 게이트)

스쿼시 머지라 **PR 제목이 곧 커밋 제목**이다. `lint.yml` 의 `commit-title` 잡이 PR 제목을
검사한다. 로컬 훅을 켜지 않은 사람도 여기서 걸린다.

```bash
bash plugin/ax/scripts/lint_commit_msg.sh --title "fix(notion): 제목"
```

## 예시

```
fix(notion): 재게시가 게시본을 불리던 문제

갱신 시 기존 블록 삭제가 `?page_size=100` 한 페이지만 돌았다. 100블록을 넘는
문서는 앞 100개만 지워지고 나머지는 남은 채 전량이 다시 append 되어, 같은
문단이 두 번씩 쌓였다.

  실측: dist/ARCHITECTURE.md(143블록) 게시본이 308블록까지 자랐다

로그는 매번 ✅(갱신) 이라 눈치챌 수 없었고, 100블록 이하 문서에서는 증상이
없어 오래 숨어 있었다.

남은 것: curl 경로가 큰 문서에서 간헐적 403 을 받는다 — 원인 미확정.

Closes #46
```

---

*출처: `scripts/lint_commit_msg.sh` · `scripts/lib/commit_lint.py` · `templates/commit-msg` · 도구 레포 `.githooks/commit-msg` · `.github/workflows/lint.yml`*
