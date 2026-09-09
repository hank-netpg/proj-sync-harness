# 통합 테스트 결과 (PR 리뷰 반영 + 스킬 통합)

실행 2026-07-26 · 실 바이오 RFP(`1__제안요청서.hwpx`) 기준.

## A. PR 리뷰 반영 (self-review)
| 점검 | 결과 |
|---|---|
| A1 SKILL.md↔스크립트/프롬프트/스키마 참조 정합·경로(PLUGIN_ROOT·하드코딩 0) | PASS |
| A2 정적점검(py_compile·node --check·bash -n·JSON 유효) 전 스크립트 | PASS |
| A3 이슈 수정: evaluate 감점 키 명확화 · registry risks 연산자 버그 | 수정·커밋 |

## B. 스킬 통합 테스트
| 단계 | 검증 | 결과 |
|---|---|---|
| B1 | 신규 7스킬 frontmatter(name↔폴더·description·version·중복0) | PASS 7/7 |
| B2 | 파이프라인 7단계 체이닝·핸드오프 스키마 검증 | **PASS 7/0** |
| B3 | 자율 dispatch 라우팅 + HITL 스캔 통합 | PASS |

### B2 단계별 핸드오프 (실 데이터)
1. rfp-extract: parse_doc(131KB)→rfp_regex(99+1)→[agent 정제]→requirements.json ↔ schema ✓
2. toc: 평가배점 합=100 · req_ids 연결 ✓
3. docquark: req+toc→knowledge(quark/_mirror/_axon/guide) + 정합경고(HITL) ✓
4~5. strategy(5섹션)·draft(v3 propdraft frontmatter) ✓
6. evaluate: toc.배점→rubric→위원3→집계 18.67/90→개선 dispatch ✓
7. build-deck: pages+toc→발표자료.pptx ✓

### B3 자율 오케스트레이션
- 제안요청서.hwpx(conf 0.8)→**rfp-extract 자동** / 회의록@제안(phase불일치)·미분류→**HITL ask**
- hitl_scan: 요구사항_미매핑 자동탐지

## 결론
전 파이프라인·에이전트·자율 오케스트레이션이 실 데이터에서 설계(SPEC·DETAIL)대로 통합 동작. 리뷰 이슈 2건 수정 반영.

## 잔여(통합환경 검증 필요)
- 실제 `/ax:*` 슬래시 호출(스킬 로더의 프롬프트 주입) — 스킬 설치 Claude Code 세션에서 최종 확인
- jsonschema·PyYAML·python-pptx·Node 의존 — doctor 프리플라이트에 추가 권고

---

## C. 스킬 설치 세션 통합 확인 (근본·우선, 2026-07-26)

### C1. 근본 이슈 발견
- **pm·pl 에이전트 tools에 `Agent`/`Task` 도구 없음**(Read·Grep·Glob·Bash·Write·Edit·Notion·Slack만). 기존 스킬도 서브에이전트 스폰 패턴 없음.
- → 제안축 **인지 스킬이 "서브에이전트 필수"로 설계되면 pm/pl 오케스트레이션 경로에서 실행 불가**. (사용자 직접 `/ax:*`는 메인 에이전트가 Agent 도구 보유해 가능하나, PM 흡수 원칙과 상충.)

### C2. 해결 — 인라인 우선 보강
- 인지 스킬 5종(rfp-extract·toc·strategy·draft·evaluate) SKILL.md를 **"호출 에이전트가 `prompt.md` 지침으로 직접 수행(인라인)"** + **명시적 `Read ${CLAUDE_PLUGIN_ROOT}/skills/<name>/prompt.md`** + **병렬 필요·Agent 도구 보유 시 서브에이전트 선택**으로 재작성.
- 결과: 도구 세트(pm/pl vs 메인)와 무관하게 실행 가능. 병렬은 능력 있는 에이전트에서 가속(선택).

### C3. 인라인 실행 실증
- 보강 SKILL.md를 지시로 삼아 **서브에이전트 없이 인라인 정제** 5건(PLR-001·SFR-013·ECR-001·QUR-001·VVR-004) → schema required 충족·category 라벨 강제·quote 원문 정합(환각0). **pm/pl도 실행 가능 확인.**

### C4. 잔여 (새 세션 필요)
- 실제 `/ax:rfp-extract` 슬래시 호출은 **스킬 레지스트리 재로드(플러그인 업데이트 후 새 세션)** 필요 — 본 세션에서 미실행. 단 C2 보강으로 **tool-set 무관 실행이 보장**되어 리스크는 해소.
- 설치: 정규 플러그인 업데이트(`build.sh` → 마켓플레이스/`install.sh`) 경로. 사용자 설치본 미변경(PR 머지 후 반영).

## 후속 — doctor 의존성 프리플라이트 (통합 확인 후 착수)
- 확정 런타임: **Node.js v18+**(docquark), **python-pptx**(build-deck), **PyYAML**(hitl_scan·build_deck), **jsonschema**(선택, 스키마 검증), **lxml**(회의록). → `doctor.sh`에 존재 점검 + 누락 시 설치 안내.
