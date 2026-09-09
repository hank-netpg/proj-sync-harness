---
description: "VSCode 태스크 설치 — .vscode/tasks.json 스캐폴드 + ~/.proj-sync/bin/ax 셔임 점검 (기존 프로젝트용)"
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh:*)", "Read", "Write", "Edit"]
---

기존 프로젝트에 VSCode 태스크(Terminal → Run Task → AX: …)를 설치합니다. (`/ax:init` 신규 프로젝트는 자동 생성됨)

1. **셔임 점검**: `~/.proj-sync/bin/ax` 와 `~/.proj-sync/plugin_root` 존재 확인.
   - 없으면 `bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh` 를 실행 (doctor 가 셔임을 자동 생성·갱신).
2. **tasks.json 설치**:
   - `.vscode/tasks.json` **없으면**: `${CLAUDE_PLUGIN_ROOT}/templates/vscode-tasks.template.json` 내용으로 생성.
   - **이미 있으면**: 기존 태스크를 보존하고 `label` 이 `AX: ` 로 시작하는 항목만 병합(중복 label 은 갱신). `inputs` 의 `commitMsg` 도 없으면 추가. 사용자 태스크는 절대 삭제·수정하지 않는다.
3. **안내**: "VSCode 에서 ⇧⌘P → Tasks: Run Task → AX: Doctor 로 확인하세요. 태스크는 `~/.proj-sync/bin/ax` 셔임을 호출하므로 플러그인 업데이트에 영향받지 않습니다."
   - Windows 는 Git Bash 를 기본 셸로 설정해야 함을 함께 안내 (`terminal.integrated.defaultProfile.windows`).
