# proj-sync 받았어요 — 무엇부터 볼까요?

받으신 파일입니다. **순서대로** 보시면 됩니다.

| 순서 | 파일 | 언제 봄 |
|------|------|---------|
| 1 | **GUIDE.md** | **설치할 때** — 준비물·압축풀기·실행 (비개발자용 그림 설명) |
| 2 | **proj-sync.zip** | GUIDE 보면서 **압축 풀고 실행** |
| 3 | **MANUAL.md** | **설치 끝난 뒤** — 실제 사업관리 사용법 (PM·PL 에이전트) |
| (참고) | **ARCHITECTURE.md** | 전체 동작 방식·흐름을 그림(다이어그램)으로 보고 싶을 때 |

---

## 30초 요약

### 설치 (GUIDE.md 참고)
1. **Windows 만**: Git for Windows · Python · Claude Code 먼저 설치
2. `proj-sync.zip` **압축 풀기**
3. 풀린 폴더에서 터미널 열고 (Windows=Git Bash): `bash proj-sync-setup.sh`
4. 메뉴 **1) 초기 세팅** — 토큰·NAS·단계 입력

### 사용 (MANUAL.md 참고)
- `@agent-ax:pm 진도 점검` — 사업 관리·점검
- `@agent-ax:pl 이 문서 분석` — 문서 분석·초안 작성
- 터미널 메뉴 — 파일 다운로드·동기화

---

## 담당자에게 미리 받을 것 — 없음 (v1.21.0)
- **Slack 봇 토큰**: GitHub 로그인(`gh auth login`, ax-harness 멤버)이면 자동 조회 — 받을 것 없음
- **Notion**: 각자 claude.ai Notion 커넥터 1회 연동 — 토큰 없음
- **Google Drive**: 본인 Google 계정으로 rclone 인증(`setup-remote` 1회) — 토큰 없음
- (GitHub 토큰은 **본인이 직접 발급** — GUIDE 에 방법 있음)

막히면 그 화면을 **캡처해서 담당자에게** 보내세요.
