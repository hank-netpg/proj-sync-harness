# proj-sync 설치 (팀원용)

> 설치·다운로드·push 같은 작업은 **터미널에서 직접** 실행합니다.
> (Claude **채팅창에 "실행해줘"라고 시키면 보안 기능이 막을 수 있습니다.**)

1. 받은 **`proj-sync.zip`** 을 VS Code 로 연 **프로젝트 폴더 안**에 저장하고 **압축을 풉니다**.
2. VS Code 터미널(Windows 는 **Git Bash**)에서 풀린 폴더로 이동해 실행합니다:

   ```bash
   bash proj-sync/install.sh
   ```

3. `install.sh` 가 마켓플레이스 등록 → 플러그인 설치를 자동 처리합니다 (여러 번 실행해도 안전 — 이미 설치돼 있으면 최신으로 갱신).
4. **Claude Code 를 재시작**하면 `/ax:*` 커맨드가 보입니다.
5. 첫 사용 순서:
   - **`/ax:setup`** (사전 도구 1회 점검)
   - **기존 사업 합류(팀원)**: **`/ax:start`** → 수행 프로젝트 DB에서 선택 → repo clone → `.env` 토큰 → `/ax:doctor` → `/ax:sync` → 업무 시작
   - **새 사업 시작(PM)**: **`/ax:init`** (config 생성 + 레지스트리 등록)

> 비개발자용 단계별 그림 설명은 **GUIDE.md** 참고 (`proj-sync-setup.sh` 메뉴 방식도 안내).
> Windows 는 모든 스크립트를 **Git Bash** 에서 실행해야 합니다.
