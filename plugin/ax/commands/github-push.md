---
description: "로컬 → GitHub 동기화 (LFS + secret-scan + commit + push). 사용: /ax:github-push [메시지]"
argument-hint: "[커밋 메시지]"
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/github_push.sh:*)"]
---

GitHub = SSOT 단방향. LFS 설정 후 시크릿 스캔을 거쳐 커밋·push 합니다. 원격 repo가 없으면 config 기준으로 생성합니다.

```!
bash ${CLAUDE_PLUGIN_ROOT}/scripts/github_push.sh "$ARGUMENTS"
```

시크릿 스캔에 걸리면(✗) 절대 강제하지 말고, 해당 파일을 .gitignore에 추가하도록 안내하세요.
