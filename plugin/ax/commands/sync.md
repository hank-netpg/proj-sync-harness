---
description: "전체 동기화 오케스트레이션 — slack-pull → 분류 → github-push → (Google Drive 대용량) → (선택)notion-publish"
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/slack_download.sh:*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/github_push.sh:*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh:*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/gdrive_sync.sh:*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/office_to_md.sh:*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/notion_plan.sh:*)"]
---

프로젝트 전체를 동기화합니다. **run-sync 스킬의 절차를 그대로 수행**하세요 — 단계 순서·실패 정책·Google Drive E-code 해석표·최종 보고 형식의 SSOT 는 `run-sync` 스킬입니다.

요약 (상세는 run-sync 스킬 참조):

1. **doctor** → ✗ 있으면 중단·조치 안내 (Google Drive/Notion 한정 ✗ 는 해당 단계 스킵 예약 후 계속)
2. **slack-pull** (`slack_download.sh`) — 신규 파일 다운로드 + 오피스→md 자동 변환
3. **분류 보정** — 99_기타 있으면 `categorize-files` 스킬
4. **github-push** (`github_push.sh "proj-sync: 동기화"`) — secret-scan 차단 시 중단·보고
5. **Google Drive** (`gdrive_sync.sh push`, config.gdrive.enabled 시) — 종료코드 10~16 은 run-sync 의 E-code 표대로 스킵·보고.
   **E13(remote 미설정)**: `gdrive_sync.sh setup-remote` 1회 안내(본인 Google 계정·브라우저 인증). **E12(조직 정책 차단)**: Workspace 관리자에게 rclone 허용 요청 안내(재인증으로 안 풀림).
   **E16(충돌)**: 충돌 목록을 사용자에게 보고 → 승인 후에만 `PS_GDRIVE_YES=1` 로 재실행
6. **notion-publish** — notion-publish 스킬(MCP, 로그인 사용자 명의, 원문 전체). 커넥터 미연동·headless 면 스킵·보고(v1.21.0 — 팀 REST 경로 없음)
7. **완료 보고** — 성공/스킵 요약 + 미완 항목 재실행 명령

역할 분담(GitHub=텍스트 SSOT · Google Drive=사무파일 · Notion=게시본 · Slack=소통, 모두 로컬 기준 단방향 push)은 run-sync 스킬 참조.
