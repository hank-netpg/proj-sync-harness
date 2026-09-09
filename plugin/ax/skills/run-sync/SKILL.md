---
name: run-sync
description: 프로젝트 전체 동기화를 에이전트가 직접 끝까지 수행할 때 사용. PM/PL 에이전트가 오케스트레이션으로 호출하거나, 사용자가 "동기화 해줘", "싱크 돌려", "오늘 작업 백업", "자료 받아서 올려줘"를 요청할 때. doctor → slack-pull → 분류 → 변환 → github-push → Google Drive → Notion → Slack 완료보고.
version: 0.1.0
allowed-tools: ["Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/*.sh:*)", "Read", "Grep", "Glob"]
---

# 전체 동기화 실행 (에이전트 직접 수행)

터미널 `/ax:sync` 와 동일한 흐름을 **에이전트가 끝까지 직접 실행**한다. 사용자는 결과 요약만 받는다.

## 실행 원칙

- **부수효과는 `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<이름>.sh"` 엔트리포인트 또는 로그인한 사용자 명의의 claude.ai 커넥터(MCP)로만**. 서비스별 1순위 — Slack 발신·파일 = **AX-E 봇 스크립트** · git = 스크립트 · Google Drive = **rclone 스크립트(사용자 본인 Google 계정)** · Notion 게시 = **MCP(사용자 명의, notion-publish 스킬 — 판정은 `notion_plan.sh` 계획 JSON, 에이전트는 호출만)**. 인라인 curl·토큰 취급·즉흥 mount·`rm`/`mv`·force push 금지.
- **토큰은 스크립트가 내부 해석**(env → `~/.proj-sync/credentials` 캐시 → secrets repo). 이 스킬·에이전트는 토큰을 만지지 않는다. **Notion 에는 토큰이 없다** — 커넥터 OAuth 이며, 팀 토큰이 캐시에 있어도 REST 로 승격하지 않는다(v1.21.0). 하니스 분류기가 자격증명 단계를 차단하면 우회하지 않고 즉시 멈춰, 실행할 명령 1줄과 함께 사용자에게 위임한다 (auto 모드에서 차단은 정상).
- **멱등**: 어느 단계에서 끊겨도 전체 재실행이 안전하다 — slack-pull 은 `state.json`, github-push 는 "변경 없음 → 커밋 생략", Google Drive 는 rclone 체크섬(원격 md5), Notion 은 출처경로 매칭 갱신(계획기의 `update`).
- 사용자가 명시 요청한 동기화는 확인 없이 끝까지. 에이전트가 선제 제안한 경우에만 시작 전 1줄 확인.

## 단계 (순서 고정 — 각 단계 결과를 모아 마지막에 한 번에 보고)

| # | 단계 | 실행 | 실패 시 |
|---|---|---|---|
| 0 | preflight | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"` | ✗ 있으면 **원칙 중단** + 조치 안내. 예외: ✗ 가 Google Drive/Notion 에만 해당하면 해당 단계 "스킵 예약" 후 계속 |
| 1 | slack-pull | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/slack_download.sh"` | 토큰·인증 오류 → **중단** (후속 무의미). "신규 0건"은 정상 통과 |
| 2 | 분류 보정 | `slack-files/99_기타/` 에 파일이 있으면 **categorize-files 스킬** 적용 | 실패해도 **계속** (보고만) |
| 3 | 변환 | slack-pull 이 자동 변환. 잔여분만 `bash "${CLAUDE_PLUGIN_ROOT}/scripts/office_to_md.sh"` | graceful skip 내장 → **계속** |
| 4 | github-push | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/github_push.sh" "proj-sync: 동기화"` | secret-scan 차단·push 실패 → **중단** (텍스트 SSOT 핵심) + 파일명/조치 보고. "변경 없음"은 정상 |
| 5 | Google Drive | `config.gdrive.enabled=true` 면 `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdrive_sync.sh" push` | 비활성 → 자동 skip. E-code 별 **스킵·보고** (아래 표) |
| 6 | Notion | `config.notion.enabled=true` 면 — `notion-publish` 스킬(MCP, 원문 전체)을 그 절차대로 수행(`notion_plan.sh plan` → SQL 인덱스 → `plan --index` → create/update → verify → 스윕). MCP 도구가 없으면(커넥터 미연동·headless) 스킵·보고(v1.21.0 — 팀 REST 경로 없음). globs 미설정이면 계획기가 보고 → 설정 요청 | **스킵·보고** (치명 아님) |
| 7 | 완료 보고 | **`bash "${CLAUDE_PLUGIN_ROOT}/scripts/slack_post.sh" "<요약>"` (봇 발신)** 으로 `config.slack.channel_id` 에 요약 발송 (미완 항목은 `config.mentions` 담당자 멘션). 봇 경로가 불가할 때만 Slack MCP 로 폴백 — **아래 「발신 명의」 규정 준수** | 실패 → 로컬 보고만 |

### 발신 명의 (단계 7) — 순서를 바꾸지 말 것

두 경로는 **대체재가 아니다. 발신 주체가 다르다.**

| 경로 | 명의 | 읽는 사람에게 보이는 것 |
|---|---|---|
| `slack_post.sh` | **AX-E 봇** | 자동 보고임이 드러남 |
| Slack MCP | **개인 계정**(claude.ai 커넥터) | 사람이 쓰고 보낸 것으로 읽힘 |

○ **봇이 1순위다.** 자동 생성된 수치 보고가 사람 명의로 올라가면 받는 사람은 **그 사람이 검토·발신한 것**으로 읽는다. 자동 산출물은 자동이라는 게 드러나는 편이 낫다.
○ 2026-08-14 `#proj25-ai비전-공공ax-지재처` 에서 팀 보고가 실제로 개인 명의로 게시됐다. 봇이 `invalid_auth`(#20 의 `.env` 예시값)로 죽고 MCP 로 넘어간 경우였고, **어디에도 그 사실이 표시되지 않았다.**

**폴백할 때는 반드시 알린다 — 콘솔과 메시지 본문 양쪽에.** 조용한 폴백은 메시지를 살리지만 무엇이 바뀌었는지 알리지 않는다.

1. 콘솔(사용자에게 보고할 때):
   ```
   ⚠ 봇 발신 실패(<사유>) → 개인 계정 명의로 게시합니다
   ```
2. MCP 로 보낼 메시지 **말미에 한 줄**:
   ```
   (자동 보고 · 봇 발신 실패로 개인 계정 경유)
   ```

○ 이 한 줄이 없으면 나중에 **"이 보고는 자동인가 수동인가"를 메시지만 보고 판별할 수 없다.** 감사 추적이 거기서 끊긴다.
○ 봇 실패의 가장 흔한 원인은 `.env` 토큰 문제다 — 폴백을 보고할 때 `bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"` 를 함께 안내한다.

## Google Drive E-code 해석 (단계 5)

> 전송은 **rclone** 이 한다. claude.ai Drive 커넥터에는 로컬 경로 업로드가 없어 파일을 base64 로
> 컨텍스트에 **두 번**(스크립트 출력 → 도구 인자) 통과시켜야 하는데, 64KiB 가 약 70k 토큰·1MiB 는
> 약 1.1M 토큰이라 대용량이 이 저장소의 존재 이유인 이상 성립하지 않는다(v1.21.0 설계 실측).
> 커넥터는 조회·공유 링크 같은 보조에만 쓴다. 자격증명은 **사용자 본인 Google 계정**(팀 토큰 아님) —
> `setup-remote` 가 rclone 기본 client 로 remote 를 만든다(머신당 1회 · 브라우저 인증).

| exit | 의미 | 에이전트 행동 |
|---|---|---|
| 0 | 성공 / gdrive 비활성 | 계속 |
| 10 | rclone 미설치 | 스킵 + OS 별 설치 명령 안내 (mac: `brew install rclone`) |
| 11 | remote 도달·인증 불가 | 스킵 + "`rclone config reconnect <remote>:` 로 재인증" 안내 |
| 12 | **조직 정책 차단** — Workspace 관리자가 서드파티 앱(rclone)을 막음 | 스킵 + Workspace 관리자에게 rclone 허용 요청 안내. 재인증(11)·재생성으로는 풀리지 않는다 |
| 13 | remote·base_path 미설정 | 스킵 + "머신당 1회 `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdrive_sync.sh" setup-remote`" 안내 (브라우저 인증 1회 — 본인 Google 계정) |
| 14 | 쓰기 권한 실패 | 스킵 + `gdrive_sync.sh doctor` 로 상세 진단 안내 |
| 15 | (결번 — v1.21.0 에서 팀 자격증명 경로 삭제) | — |
| 16 | push 충돌 미해결 | **충돌 목록을 사용자에게 보고** → 사용자가 덮어쓰기 승인하면 `PS_GDRIVE_YES=1` 을 붙여 재실행, 아니면 `pull` 권장. **승인 없이 `PS_GDRIVE_YES=1` 금지** |

○ **10·13 은 머신 설정 문제**라 다른 사업에서도 같이 난다. 한 번 안내하면 이후 전 사업에서 해소된다.
○ 16 은 **다른 사람이 Drive 에서 고친 파일**을 덮어쓰려는 상황이다. 덮어쓰기 전 `.bak-<epoch>` 백업이
  남지만, 백업이 있다고 승인 없이 밀어붙이지 않는다.

## 최종 보고 형식 (이 틀 유지)

```
동기화 완료 (성공 N / 스킵 M)
✓ Slack 3건 수신 · 변환 2건
✓ GitHub push (abc1234)
⚠ Google Drive 스킵 (E10 rclone 미설치) → brew install rclone 후: bash …/gdrive_sync.sh push
⚠ Notion 스킵 — MCP 미연동
```

- Slack 완료 보고도 동일 요약 + 미완료 항목 담당자 멘션.
- 요청 시 "자세히" → 단계별 원문 로그 제시.

## 터미널 경로와의 관계

- 터미널 사용자는 기존대로 `/ax:sync` (동일 절차의 커맨드 래퍼). 이 스킬이 단계·실패 정책의 SSOT.
- 권한 프롬프트가 반복되면(allowed-tools 미전파 환경) 사용자 settings `permissions.allow` 에 `Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/*.sh:*)` 추가를 안내.
