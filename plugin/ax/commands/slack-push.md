---
description: "파일을 Slack 채널에 업로드 (+@멘션). 사용: /ax:slack-push <파일> [메시지]"
argument-hint: "<파일경로> [메시지 (@이름 멘션 가능)]"
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/slack_upload.sh:*)"]
---

지정 파일을 config의 Slack 채널에 업로드합니다. 메시지의 `@이름` 은 config.mentions 역매핑으로 `<@UID>` 멘션이 됩니다.

```!
bash ${CLAUDE_PLUGIN_ROOT}/scripts/slack_upload.sh $ARGUMENTS
```

업로드 후 `slack_read_channel` 로 게시 결과를 확인해 사용자에게 보고하세요.
