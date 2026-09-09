# DESIGN(오케스트레이션) — 전 생애주기 자율주행 사업 에이전트

> **ax 최상위 오케스트레이션 설계.** revision 축 담당자 `DESIGN.md`(§A~H, 시스템·revision 전제)의 상위 바인딩 문서.
> ⚠️ 원본 `DESIGN.md` 는 회수되지 않았다. A1·A2·A6·A7 본문은 [`PRINCIPLES.md`](PRINCIPLES.md)(역추적 재작성), A3·A4·A5·D2·H2 는 [`../ARCHITECTURE.md`](../ARCHITECTURE.md) §3 을 보라 — issue #26.  
> 북극성: **RFP 투입 → 제안서 발표자료 → 수주 → 착수 → 수행 → 감리 → 완료**까지 전 생애주기를 정확히 동작하는 자율주행 오케스트레이터.  
> 원칙: A3(부수효과⊥인지) · A4(2축 생애주기) · A5(결정론폴더) · D2(data-SSOT→파생) · H2(결정론⊥서술⊥발신) 준용 — 본문은 [`../ARCHITECTURE.md`](../ARCHITECTURE.md) §3.  
> 지침: **자체 GPU 대신 Claude Code 활용.** 근거: propstudio(내부 프로토타입 repo) · 원안 `Claude Team Project.pdf`(Leader-Worker) · ax v1.3.x 기존 골격.

---

## O. 전 생애주기 상태기계 (phase × 축)

- **진술**: 사업은 `lifecycle.phase`(제안→수주→수행중→감리→완료, +보류/실주)로 상태를 갖고, **각 phase가 서로 다른 파이프라인을 활성화**한다. 오케스트레이터는 phase를 읽어 해당 축의 스킬을 dispatch한다.
- **phase ↔ 축 매핑**:

| phase | 활성 파이프라인 | 주 스킬 |
|---|---|---|
| 제안 | **제안축**(§P) | rfp-extract→toc→strategy→draft→evaluate→build-deck |
| 수주 | 인계 | proposal→revision 시드(요구사항·전제 이관) |
| 수행중 | **수행축**(revision, §D~H) | manage-schedule·risk·deliverable + revision 빌더 |
| **감리**(신규) | 감리 게이트 | 감리대응 산출물(감리수행결과·시정조치확인) + V-Model 짝 |
| 완료 | 인도·종료 | 최종 산출물 Archive·인수인계 |

- **감리 모델(미확정)**: 수행중 내부 **게이트**(단계 전환 시 감리 대응) vs 독립 phase. → 전자 권고(A4 SDLC축의 게이트로 편입, deliverables.json에 감리 산출물 추가). 확정 필요.
- **기존 정합**: `lifecycle.phase`·`phase` 커맨드·PM 에이전트 상태판정 재사용. 감리만 신규 편입.

---

## P. 제안축 파이프라인 (신규 — propstudio 이식, Claude Code)

### P1. 6+1 스킬 (data-SSOT→파생, D2)
| 스킬 | 입력→출력(SSOT) | 이식 프롬프트 | 유형 |
|---|---|---|---|
| `ax:rfp-extract` | RFP(hwpx/pdf)→`requirements.json` | rfp_extractor `_REFINE_SYSTEM/_USER` | 인지 |
| `ax:toc` | RFP→`toc.json`(+평가배점 매핑) | toc_parser `_REFINE_SYSTEM/_USER` | 인지 |
| `ax:strategy` | requirements→`strategy.md`(5섹션) | strategy_writer `_STRATEGY_SYSTEM/_USER` | 인지 |
| `ax:draft` | toc+req+전략+자산→`pages/{id}.md`(v3 propdraft) | page_generator `_SYSTEM/_USER` | 인지 |
| `ax:evaluate` | pages→`eval/{r}.json`(감점) + 반복개선 | 3-Agent(P3) | 인지 |
| `ax:build-deck` | pages/*.md→`발표자료.pptx` | 결정론 빌더 | **터미널** |
| `ax:propose` | RFP→발표자료 오케스트레이션 | 신규 | 오케스트레이터 |

### P2. GPU → Claude Code
| propstudio(GPU) | ax(Claude Code) |
|---|---|
| EXAONE chat | Claude 서브에이전트 |
| Polaris PDF | 로컬 파서(pypdf/hwpx XML) + Claude Read |
| KURE+Qdrant RAG | **Quarkify 지식맵**(everything-is-a-folder) — 자산·코드를 물리 폴더 트리로 materialize → 에이전트가 `ls`/`tree`/`fd`/`rg`로 target-jump(임베딩·벡터DB 불요) |
| FastAPI 구동 | 서버 불요 — 인프로세스 스킬/서브에이전트 |
- 근거: `llm.py` `LLMProvider` 추상 + `LLM_PROVIDER` 교체("Claude Sprint 2 fallback")가 원설계와 정합. A6(무GPU 동질환경) 강화.

### P2-1. Quarkify 지식맵 (RAG 대체 — companyjupiter/quarkify)
- **진술**: RAG(임베딩·Qdrant)를 **Quarkify 물리 폴더 토폴로지 맵**으로 대체. 소스·자산을 `quark/`·`_mirror/`(by_kind/role/file)·`_axon/`(의존성)로 materialize → Claude 에이전트가 CLI로 정확 target-jump. **토큰 90%↓·환각 0%**(실물 폴더라 스키마 오해 불가).
- **정합**: ax **A5 결정론 폴더** = quarkify **"Everything is a folder"** 동일 철학 · **A3**(스크립트가 맵 생성=부수효과, 에이전트가 탐색=인지, 파일 핸드오프) · **GPU 대신 Claude Code** 지침(local-first·CLI·무GPU) 정확 부합.
- **2대 적용**:
  1. **개발시점(도구 구축)**: propstudio·ax plugin 소스를 quark-map → ax 오케스트레이터를 만드는 에이전트가 거대 코드베이스를 저토큰·무환각으로 탐색.
  2. **런타임(제안 파이프라인)**: RFP 요구사항·목차(N.N.N)·회사 자산을 **quark 트리로 materialize** → `ax:draft` 에이전트가 RAG 없이 `tree`/`ls`로 해당 요구사항·근거 폴더로 직행. quarkization(계층 평면 분해) = 목차 3레벨·D2 data-SSOT 분해 철학과 동형.
- **의존**: Node.js v22.12+, `node quarkify.mjs configs/{proj}.mjs`. config는 srcDir·sourceFiles(glob)·guessRole. tools 비-stdlib 예외(회의록 lxml·전제 PyYAML에 이은 Node 도구).

### P3. 3-Agent 평가 코드화 (대화형→결정론+에이전트)
- 평가위원 3 페르소나(IT SI/응용SW/사업관리 20년+) × **만점기준 감점 누적** + 수정 agent 병렬 + 자동 반복.
- **RFP Ⅴ 평가배점으로 항목·가중 치환**(본 사업 기술90+가격10 세부배점).
- **종료조건(무한루프 방지)**: 목표점수 도달 OR 라운드 상한 N OR 개선폭<ε. (프로토타입 76.5/80서 구조적 정지 → 상한 필수.)
- H2 정합: 감점 계산=결정론, 개선 지시=에이전트, 발신=선택. 파일 핸드오프(eval/*.json).

---

## Q. 자율주행 — 드롭존 ingestion → dispatch (신규)

- **진술**: 사용자가 **특정 위치**(Slack 채널=A1 단일 진입점 / 사업 폴더 inbox)에 사업별 자료를 올리면, watcher가 감지 → 분류 → **phase 판정 후 해당 파이프라인 자동 dispatch**.
- **흐름**: `slack-pull`(부수효과)→`categorize-files`(분류)→phase 근거로 dispatch: 제안이면 `rfp-extract`(신규 RFP 감지 시), 수행중이면 revision 갱신(회의록 yml·WBS·RTM).
- **트리거**: ① 스케줄러(revision 축 담당자 Reply4 — 매일 자정 slack-pull+commit) ② inbox 폴링(기존 스킬). watcher/pull=결정론 스크립트(A3 부수효과), 분류·분석·dispatch=PM 에이전트(인지). 파일시스템 핸드오프.
- **오판 방지(중요)**: 자동 dispatch 전 **분류 신뢰도 임계 + phase 정합 검증**. 신뢰도 낮거나 phase 불일치(예: 수행중에 신규 RFP)면 **§R 능동 질문**으로 전환(자율≠맹목).
- 재사용: `inbox`·`categorize-files`·`run-sync`·`slack-pull` 그대로. 신규 = dispatch 규칙 + 스케줄러 배선.

---

## R. 능동 human-in-the-loop (전 축 공통)

- **진술**: 에이전트는 막히거나 결정이 필요할 때 **능동적으로 사용자에게 질문**하고, 피드백을 전제/config에 반영해 재수행한다. "묻지 않고 추측"과 "다 물어봄"의 중간 — **결정 필요 지점만 선별 질문**.
- **질문 트리거(결정론 탐지)**:

| 축 | 트리거 소스 | 질문 예 |
|---|---|---|
| 평가 | 평가배점 미확인·SW특칙 적용 여부 | "감리 발주주체·1TB/2TB 발주처 확인?" |
| 위험 | 전제 `위반위험`·stale(신선도) | "PR-06 NPU 확정?"(premise) |
| 진도 | WBS 지연·마감임박·크리티컬패스 | "지연 task 만회계획 승인?" |
| 산출물 | 누락·미흡·모호 요구사항 | "요구사항 X 담당·범위 확정?" |
| 자율 dispatch | 분류 신뢰도 낮음·phase 불일치 | "이 자료 제안용인가 수행용인가?" |

- **구현**: PM 에이전트의 "선제 실행 1줄 확인" 원칙을 **선제 질문**으로 확장. 미확정 전제(§G premise.yml `상태≠합의`)가 1차 질문 소스. AskUserQuestion 패턴, 피드백→premise.yml/config 갱신→빌더 재실행.
- **A3 정합**: 질문·판단=에이전트, 갱신 반영(commit)=스크립트.

---

## S. 재사용 매핑 (기존 ax ↔ 신규 — 재발명 0)
| 요구 | 기존 ax(재사용) | 신규(고도화) |
|---|---|---|
| 생애주기 | `lifecycle.phase`·`phase` 커맨드·PM 상태판정 | 감리 phase·축 dispatch |
| 자율 ingestion | `inbox`·`categorize-files`·`slack-pull`·`run-sync` | dispatch 규칙·스케줄러 |
| 제안 작성 | (없음) | 제안축 6+1(§P) |
| 위험/진도/산출물 | `manage-risk`·`manage-schedule`·`manage-deliverable` | `evaluate`(평가) 추가 |
| 능동 질문 | PM "1줄 확인" + premise 상태 | 선제 질문 트리거(§R) |
| 산출물 작성 | `pl` 에이전트 | 제안축 draft가 pl 확장 |
| 조율 | `registry-sync` | Leader Aggregation(§아래) |

---

## T. 견고화·로드맵

### 견고화 6항목 (프로토타입 취약점 1:1)
1. `tools/apply_slideN` 95개 일회성 → 결정론 빌더+에이전트 서술(A3·H2)
2. 3-Agent 평가 대화형 즉흥 → P3 스킬 코드화(종료조건)
3. GPU 의존 → Claude Code(P2)
4. 제안/수행 레포 혼재 → 도구(proj-sync plugin)⊥사업 데이터(사업 repo) 분리(revision 축 담당자 Reply3)
5. RFP→PPTX 미배선 → `ax:propose`
6. 프로젝트 교차관리 부재 → **Leader-Worker**(원안): Leader 1(전 프로젝트 revision/전제 Aggregation·조율)+Worker N(팀원별 다수 프로젝트·Issue 보고), registry(A7) 교차집계 = Leader 실체

### 로드맵
- **P0** 제안축 스캐폴드(rfp-extract→toc→strategy→draft) + **바이오 dogfooding**(요구사항 99건·목차·전략 확보 → 즉시 검증)
- **P1** `ax:evaluate` 3-Agent(RFP Ⅴ 배점)
- **P2** `ax:build-deck`(md→PPTX)
- **P3** 자율 ingestion→dispatch + 스케줄러
- **P4** 감리 phase + human-in-loop(§R) 강화
- **P5** revision 머지(revision 축 담당자 feat) + Leader-Worker registry 교차집계

## U. 미확정·검증 필요
- 자율 dispatch 오판(분류 신뢰도·phase 정합 게이트) — §Q 반영했으나 임계값 실측 필요
- 3-Agent 반복 비용·상한 N·목표점수 기본값
- 감리 phase 모델(게이트 vs 독립축) 확정
- Leader-Worker 계정/인증(Claude×10 vs 엔터프라이즈, Reply5) 병목 회피
- RAG 대체(파일 직접주입) 대규모 스케일 한계
- 제안/수행 레포 분리 경계 · 설계서 배치(proj-sync feat PR)
