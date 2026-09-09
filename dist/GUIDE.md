# proj-sync Setup Guide (비개발자용)

> 💡 받은 **`proj-sync.zip`** 의 **압축을 먼저 풀고**, 풀린 폴더 안에서
> **`proj-sync-setup.sh`** 를 실행하면 설치부터 토큰·작성자·동기화까지 한 번에 진행됩니다.
> 막히면 그 화면을 캡처해 담당자에게 보내세요.

---

## 🪟 [Windows 전용] 준비사항 — 압축 풀기 **전에** 먼저 설치

Windows는 아래 **3가지를 먼저 설치**해야 합니다. (Mac은 준비 없이 바로 "0단계"로)

| # | 설치할 것 | 받는 곳 | 설치 방법 |
|---|-----------|---------|-----------|
| 1 | **Git for Windows** | https://git-scm.com/download/win | 더블클릭 → 계속 **Next** → **Install** (설정 기본값 그대로). ※ `curl`·`unzip`·터미널(Git Bash)이 함께 깔립니다 |
| 2 | **Python** | https://python.org/downloads | 설치 시 **"Add Python to PATH" 체크** 필수 |
| 3 | **Claude Code** | https://claude.ai/code | 안내대로 설치 |

> ✔️ 이 3가지만 깔면 됩니다. `curl`·`unzip` 은 1번(Git Bash)에 포함되어 **따로 설치 안 함**.
> (선택) GitHub CLI·Git LFS 가 없어도 시작되며, 필요할 때 실행 화면이 링크로 안내합니다.

> 💡 잘 모르겠으면 위 3개 링크만 순서대로 설치하고 "0단계"로 넘어가세요.
> 실행하면 스크립트가 **빠진 도구를 다시 확인해 알려줍니다.**

---

## ✅ 0단계. 압축 풀기 (먼저)
1. 받은 **`proj-sync.zip`** 을 **작업할 사업 폴더**에 둡니다.
2. **압축을 풉니다.** (Windows: 우클릭 → "압축 풀기" / Mac: 더블클릭)
3. 풀면 **`proj-sync`** 폴더가 생기고, 그 안에 아래가 보입니다:
   - **`proj-sync-setup.sh`** ← 이걸 실행
   - **`GUIDE.md`** ← 지금 보는 문서
   - `proj-sync/` ← (설치에 쓰임, 건드리지 마세요)

## ⚠️ 가장 중요한 규칙
- Claude Code **채팅창에 "실행해줘"라고 시키지 마세요.** (보안 기능이 막습니다.)
- 아래처럼 **VS Code 터미널에 직접** 입력해야 합니다.

---

# 🪟 Windows 사용자 — 실행하기

> ※ 위 **[Windows 전용] 준비사항**(Git for Windows·Python·Claude Code)을 먼저 끝내고,
>   **0단계(압축 풀기)** 까지 했다는 전제입니다.

## 1단계. VS Code 터미널을 "Git Bash"로 바꾸기
1. VS Code에서 **`proj-sync-setup.sh` 가 있는 폴더**를 엽니다 (`File → Open Folder`)
2. **`Ctrl`** + **`` ` ``** (백틱, 숫자 1 왼쪽) → 아래에 터미널이 열림
3. 터미널 오른쪽 위 **`∨`** 클릭 → **`Select Default Profile`** → **`Git Bash`** 선택
4. 터미널 **🗑️(휴지통)** 으로 닫고, 다시 **`Ctrl`** + **`` ` ``** 로 새 터미널 열기

> ✔️ **성공 확인**: 줄 맨 앞이 `$` 로 시작하면 Git Bash입니다.
> 파란 `PS C:\…>` 면 아직 PowerShell이니 3번부터 다시.

## 2단계. 실행
터미널에 **아래 한 줄을 복사·붙여넣고 Enter** (붙여넣기: 마우스 **오른쪽 클릭**):

```bash
bash proj-sync-setup.sh
```

### ❗ 빨간 오류(`$'\r'` 또는 `command not found`)가 나면
파일 줄바꿈이 깨진 것입니다. 아래로 대신 실행하세요(동일 동작):

```bash
bash <(tr -d '\r' < proj-sync-setup.sh)
```

---

# 🍎 Mac 사용자

별도 터미널 준비 없이 바로 됩니다. (git·curl·unzip·python 은 macOS 기본 포함)

> 전제: **Claude Code** 만 설치돼 있으면 됩니다 (없으면 https://claude.ai/code).
> 누락 도구가 있으면 실행 시 **Homebrew 로 자동 설치할지** 물어봅니다.

1. VS Code에서 **`proj-sync-setup.sh` 가 있는 폴더**를 엽니다 (`File → Open Folder`)
2. **`Ctrl`** + **`` ` ``** 로 터미널 열기
3. 아래 한 줄 붙여넣고 Enter (붙여넣기: **`Cmd` + `V`**):

```bash
bash proj-sync-setup.sh
```

---

# 공통: 실행 후 진행

## 실행하면 가장 먼저: 사전 점검

실행하면 **필요한 도구가 깔려 있는지 먼저 확인**합니다.

```
[사전 점검] 실행에 필요한 도구를 확인합니다
  ✓ claude
  ✓ git
  ✗ python3 — https://python.org (Windows는 PATH 등록)   ← 없는 건 이렇게 표시
  ...
```

- **✗(없음)** 표시가 나오면, 그 줄의 **링크로 설치**한 뒤 다시 실행하세요.
- **macOS**: 누락분을 **Homebrew로 지금 설치할지** 물어봅니다 → `Y` 누르면 자동 설치.
- **Windows**: 링크(특히 **Git for Windows**)로 직접 설치 → 그 후 다시 실행.
- **필수 도구(claude·git·curl·unzip·python)** 가 없으면 여기서 **멈춥니다**(설치 후 재실행).
  선택 도구(gh·git-lfs)만 없으면 경고만 하고 계속 진행합니다.

## 메뉴

```
무엇을 할까요?     (작성자: 미설정)
  1) 초기 세팅 …
  2) Slack 다운로드/분류
  3) Slack 파일 업로드 (작성자 식별)
  4) GitHub 동기화 (push)
  5) doctor 재점검
  q) 종료
선택 [1]:
```

처음이면 **`1` 입력 후 Enter** → 순서대로 진행됩니다.
플러그인이 없으면 같은 폴더의 `proj-sync/` 로 **자동 설치**합니다.

## 입력 항목 (순서대로 물어봄)

| 순서 | 항목 | 어떻게 |
|------|------|--------|
| ① | **GitHub 토큰** | 본인이 직접 발급 (아래 "GitHub 토큰 발급" 참고) |
| ② | **Slack 봇** | 담당자가 준 `xoxb-…` 붙여넣기 |
| ③ | **Notion** | (구버전) 이제 입력하지 않음 — 각자의 claude.ai Notion 커넥터가 게시 (v1.21.0) |
| ④ | **Google Drive** | 터미널에서 `rclone config` 1회 — 브라우저로 Google 로그인 (사무파일 hwp/ppt/xls 저장소) |
| ⑤ | **본인 이름** | 회사 Slack 명단에서 **검색 → 번호 선택** |

- 토큰은 폴더 안 `.env`(권한 600, git 제외)에 저장됩니다.
- ④ 이름은 한 번 고르면 저장돼 다음부터 안 물어봅니다. → Slack 업로드 `[이름]`, Notion 작성자에 공통 사용.
- **플러그인(`/ax:*`) 경로는 다릅니다 (v1.21.0)** — 위 표는 레거시 설치기 기준입니다. 플러그인에서는 ② Slack 봇 토큰은 자동 조회(`/ax:auth`), ③ Notion 은 **각자의 claude.ai Notion 커넥터**(토큰 없음), ④ Google Drive 는 `gdrive_sync.sh setup-remote`(본인 Google 계정 · 브라우저 인증 1회) 입니다. 자세한 것은 `docs/notion/onboarding-guide.md`.

## ⑤ 본인 이름 — 명단에서 고르기
```
이름 검색: 황          ← 본인 성/이름 일부
   4) 황한건  (엔지니어링팀 리드)   ← 본인
번호 선택: 4
✓ 선택됨: 황한건
```

---

## 🔑 GitHub 토큰 발급 (본인 1회, 약 2분)

GitHub 계정이 없으면 먼저 **github.com** 가입 후, 담당자에게 본인 아이디를 알려 **조직(ax-harness) 초대**를 받으세요.

1. 로그인 후 **https://github.com/settings/tokens** 이동
2. **`Generate new token`** → **`Generate new token (classic)`** 선택
3. **`Note`** 에 이름 입력 (예: `proj-sync`)
4. **`Expiration`** → `No expiration` (또는 `90 days`)
5. **`Select scopes`** 에서 **2개 체크**:
   - ☑ **`repo`** (맨 위 큰 항목)
   - ☑ **`read:org`** (`admin:org` 안에 있음)
6. 맨 아래 **`Generate token`** 클릭
7. **`ghp_…` 로 시작하는 글자**가 나오면 **📋 복사** → 터미널 GitHub 입력 칸에 붙여넣고 Enter
   > ⚠️ 이 화면을 벗어나면 다시 못 봅니다. 놓쳤으면 1번부터 다시.

✔️ 터미널에 `✓ 로그인 성공: 본인아이디` 가 보이면 끝.
`✗ 로그인 실패` 면 → 5번 권한 체크를 빠뜨린 것. 다시 발급하세요.

---

# 🔄 새 버전이 나오면 — 업데이트

도구(에이전트)가 고도화되면 담당자가 **새 `proj-sync.zip`** 을 보내줍니다. 업데이트는 **처음 설치와 똑같이** 하면 됩니다.

1. 받은 **새 `proj-sync.zip`** 의 압축을 풉니다. (어디서 풀어도 됩니다)
2. 풀린 폴더에서 터미널을 열고 (Windows=Git Bash):
   ```bash
   bash proj-sync-setup.sh
   ```
   또는 설치만 빠르게: `bash proj-sync/install.sh`
3. **Claude Code 를 재시작**하면 새 버전이 적용됩니다.

> ✔️ **여러 번 실행해도 안전**합니다. 이미 깔린 경우 **자동으로 최신 버전으로 갱신**됩니다. (토큰·설정은 그대로 유지)
> ✔️ 사업 폴더(파일·자료)는 건드리지 않습니다 — 도구만 갱신됩니다.

> 💡 (선택·고급) 마켓플레이스를 **사내 git-url 로 등록한 경우**에만, 압축을 풀 필요 없이 아래 한 줄로 갱신됩니다:
> ```bash
> claude plugin marketplace update ax-harness && claude plugin update ax@ax-harness
> ```
> 실행 후 Claude Code 재시작.
> ※ zip(`proj-sync.zip`)으로 설치했다면 이 명령은 GitHub 최신본을 못 가져옵니다 — **새 zip 재실행**(위 1~3단계)을 쓰세요. git-url 등록 방법은 담당자(README)에 있습니다.

---

# 🆘 자주 막히는 곳

| 증상 | 해결 |
|------|------|
| 파란 `PS C:\…>` (Windows) | Git Bash가 아님 → Windows **2단계** 다시 |
| `bash: command not found` (Windows) | Git for Windows 미설치 → Windows **1단계** |
| 빨간 `$'\r'` / `syntax error` | `bash <(tr -d '\r' < proj-sync-setup.sh)` |
| `gh` 로그인이 안 바뀜 | `unset GITHUB_TOKEN GH_TOKEN` 입력 후 다시 |
| "분류기가 차단" 메시지 | Claude 채팅 말고 **터미널에서 직접** 실행 |
| 그래도 안 됨 | 화면 **캡처**해서 담당자에게 |
