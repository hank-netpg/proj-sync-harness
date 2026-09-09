---
description: "Slack 채널 전 파일 다운로드 → 카테고리 분류 + CSV 매니페스트 (멱등)"
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/slack_download.sh:*)"]
---

config의 Slack 채널에서 모든 파일을 받아 `slack-files/<카테고리>/<FILEID>__<이름>` 로 저장하고 `FILE_INVENTORY.csv` 를 갱신합니다. 이미 받은 파일(state.json)은 건너뜁니다.

```!
bash ${CLAUDE_PLUGIN_ROOT}/scripts/slack_download.sh
```

다운로드 후, 99_기타로 분류된 파일이 있으면 `categorize-files` 스킬로 재분류를 제안하세요.
