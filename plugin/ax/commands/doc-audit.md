---
description: "산출물 문서 구조 감사 — 트리분해로 중복·구조이상·아카이브 대상 판정"
allowed-tools: ["Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/doc_audit.py:*)", "Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/doc_tree.py:*)", "Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/doc_tree_md.py:*)", "Bash(git:*)", "Bash(grep:*)", "Read", "Glob"]
---

산출물 문서군을 **헤딩 스택 경로**로 정규화해 구조를 감사합니다. **`audit-doc-tree` 스킬의 절차를 그대로 수행**하세요 — 판정 기준·아카이브 3축·주의사항의 SSOT 는 그 스킬입니다.

요약:

1. `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/doc_audit.py <대상> --json /tmp/audit.json`
   - 대상 기본값: `reference/drafts`(작업 초안, `manage-deliverable` 표준 경로)
   - 함께 볼 것 — `deliverables/`(납품 최종본) · `docs/`(기술문서 계열이 있는 프로젝트)
   - 초안↔최종본을 **한 번에** 감사하면 「초안만 고치고 최종본은 옛 판」 같은 어긋남이 겹침 판정으로 드러난다
2. **완전 동일**(sha1) → 정본 1개만 남김 · **겹침 J≥0.7** → 통합 · **구조이상** → 교정
3. 아카이브 후보는 **3축 동시 충족**일 때만 — 오래됨(git 이력) + inbound 참조 0 + 대체본 존재
4. 반영은 **이동**(삭제 금지). git 은 `archive/`, Notion 은 `상태=아카이브`
5. 개조식 보고 — 판정 건수 → 조치 대상 → 사용자 확인 필요 항목

> ⚠️ 파일 mtime·Notion `last_edited_time` 을 최종수정일로 쓰지 마세요. clone·일괄편집이 전건을 덮어씁니다. git `--name-only` 이력과 `created_time` 을 쓰세요.
