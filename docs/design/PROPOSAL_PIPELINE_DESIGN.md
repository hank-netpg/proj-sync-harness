# DESIGN(제안축) — RFP→발표자료 제안 파이프라인 설계

> **제안축(제안→수주) 설계시점 전제.** revision 축(수행축=revision 형상관리)의 짝 문서.  
> A4(2축 생애주기)에서 **제안축**을 담당 — RFP 투입 → 제안서 발표자료 자동 생성.  
> 원칙은 A3·A4·D2·H2 준용 — 본문은 [`../ARCHITECTURE.md`](../ARCHITECTURE.md) §3, A1·A2·A6·A7 은 [`PRINCIPLES.md`](PRINCIPLES.md). **자체 GPU 대신 Claude Code 활용**(사용자 지침).  
> 프로토타입 근거: 내부 프로토타입 repo의 `propstudio_api`(FastAPI+EXAONE) + 프롬프트 4종 + 3-Agent 평가. 원안: `Claude Team Project.pdf`(Leader-Worker).

---

## O. 오케스트레이션 — Leader-Worker (원안 반영)

- **진술**(원안 PDF): **Leader 1**(전 프로젝트 revision/전제 **Aggregation**, 프로젝트별 전제 설립, 프로젝트 간 상호도움 검토) + **Worker N**(각자 다수 PROJECT 진행, 전제 확인, Issue 시 Leader 보고, 전제 Update, git/버전관리 필수).
- **매핑**: Leader = A7([`PRINCIPLES.md`](PRINCIPLES.md)) **registry 교차집계**의 실행 주체(관리 Agent) / Worker = 팀원별 Claude Code(스레드: 계정당 Claude ×10 검토). PROJECT = B1 "1 사업 = 1 폴더 = 1 repo".
- **PROJECT Phase**(원안): Phase 1 착수보고·2/3 중간보고 = 과제 범위 확정 → A4 SDLC축(수행중)과 정합.
- **제안축 위치**: 제안 파이프라인은 Worker가 **PROJECT 진입 전(제안 단계)** 실행 → 수주 시 수행축(revision)으로 인계.

---

## P. 제안 파이프라인 전제 (신규)

### P1. 6+1 스킬 — data-SSOT→파생 (D2 준용)
각 단계는 구조화 SSOT를 남기고 다음 단계가 소비. propstudio 프롬프트를 Claude 서브에이전트 시스템 프롬프트로 이식:

| 스킬 | 입력 → 출력(SSOT) | 이식 프롬프트(출처) | 유형 |
|---|---|---|---|
| `ax:rfp-extract` | RFP(hwpx/pdf) → `requirements.json` | `rfp_extractor.py:_REFINE_SYSTEM/_USER` | 인지(에이전트) |
| `ax:toc` | RFP → `toc.json`(+평가배점 매핑) | `toc_parser.py:_REFINE_SYSTEM/_USER` | 인지 |
| `ax:strategy` | requirements → `strategy.md`(5섹션) | `strategy_writer.py:_STRATEGY_SYSTEM/_USER` | 인지 |
| `ax:draft` | toc+req+전략+자산 → `pages/{id}.md`(v3 propdraft frontmatter) | `page_generator.py:_SYSTEM/_USER` | 인지 |
| `ax:evaluate` | pages → `eval/{round}.md`(감점 누적) + 반복 개선 | 3-Agent(신규 P3) | 인지 |
| `ax:build-deck` | pages/*.md → `발표자료.pptx` | 결정론 빌더(신규) | **부수효과(터미널)** |
| `ax:propose` | RFP → 발표자료 (위 오케스트레이션) | 신규 | 오케스트레이터 |

- **근거**: propstudio README 파이프라인(RFP→매트릭스→전략→자산→초안). `page_generator.py` 알고리즘(요건수집→RAG→전략발췌→LLM→frontmatter검증+retry).
- **A3 정합**: rfp-extract~evaluate = Claude 에이전트(인지) / build-deck = 터미널(부수효과). 파일시스템 핸드오프(pages/*.md).
- **A5 정합**: 산출물은 `reference/drafts/00_영업_제안`(제안 stage), 납품본 pptx는 `deliverables/`(E1·E2).

### P2. GPU → Claude Code 대체 (사용자 지침)
| propstudio(GPU) | 제안 파이프라인(Claude Code) |
|---|---|
| EXAONE 4.0.1-32B chat | Claude 서브에이전트(Task/subagent) |
| Polaris PDF 파서 | 로컬 파서(pypdf/hwpx XML, `parse_doc.py` 이식) + Claude Read |
| KURE 임베딩 + Qdrant RAG | **파일 컨텍스트 직접 주입**(자산 md를 에이전트 프롬프트에) + 선택적 경량 grep/BM25. 대규모 시 registry 차원 검색은 후속 |
| FastAPI 서버 구동 | 서버 불요 — Claude Code 스킬/서브에이전트로 인프로세스 |

- **근거**: `llm.py`가 이미 `LLMProvider` 추상화 + `LLM_PROVIDER` 교체 설계("EXAONE→Claude Sprint 2 fallback") → Claude provider 구현이 원설계와 정합.
- **효과**: A6(환경 동질성)과 정합 — GPU 서비스 의존 제거로 팀원 PC에서 동일 구동.

### P3. 3-Agent 평가 코드화 (프로토타입 대화형 → 결정론+에이전트)
- **진술**: `_FINAL_3AGENT_RESULT.md`의 즉흥 3-Agent를 스킬로 코드화. **평가위원 3 페르소나**(IT SI 20년+/응용SW 20년+/사업관리 20년+) × **만점기준 감점 누적** + **수정 agent 병렬** + **자동 반복**.
- **스키마**: `evaluation.json` — 항목(사업이해·추진전략·기술·운영·품질·보안·조직·사업관리·지원) × 위원 × 감점 × 근거. **RFP Ⅴ 평가배점**(본 사업: 기술90+가격10, 세부배점)으로 항목·가중 치환.
- **종료조건(무한루프 방지)**: `목표점수 도달 OR 라운드 상한 N OR 개선폭<ε`. (프로토타입은 76.5/80서 구조적 한계로 정지 — 상한 필요.)
- **H2 정합**: 사실(감점 계산)=결정론 스크립트, 서술(개선 지시)=에이전트, 발신=선택. 파일 핸드오프(eval/*.md).

### P4. 견고화 6항목 (프로토타입 취약점 1:1)
| # | 취약점(프로토타입) | 견고화 |
|---|---|---|
| 1 | `tools/apply_slideN_modifications.py` **95개 일회성** | 결정론 빌더(`build-deck`) + 에이전트 서술로 대체(A3·H2 동형) |
| 2 | 3-Agent 평가 **대화형 즉흥**(저장 프롬프트·오케스트레이션 부재) | P3 스킬로 코드화 |
| 3 | **GPU 의존**(EXAONE/Polaris/KURE) | P2 Claude Code 대체 |
| 4 | 제안/수행 **레포 혼재** | revision 축 담당자 Reply 3: 도구(proj-sync plugin) ⊥ 사업 데이터(사업 repo) 분리 |
| 5 | RFP→PPTX **end-to-end 미배선** | `ax:propose` 오케스트레이터 |
| 6 | 프로젝트 교차관리 부재 | O(Leader Aggregation) + 스케줄러(매일 자정 slack-pull+commit, Reply 4) + registry(A7) |

---

## Q. 기존 전제(ARCHITECTURE §3 · PRINCIPLES)와의 정합/분기
| 지점 | 원 전제 | 제안축에서 |
|---|---|---|
| A3 부수효과⊥인지 | 다운로드·push=터미널 / 분석·생성=에이전트 | **정합** — build-deck만 터미널, 나머지 에이전트 |
| A4 2축 생애주기 | SDLC는 수행중만 | **보완** — 제안축(제안→수주)에 파이프라인 신설, 수주 시 revision 인계 |
| D2 data-SSOT→파생 | WBS/RTM json, 회의록 yml | **정합** — requirements/toc=json, strategy/pages=md, 평가=json |
| A6 stdlib/무의존 | tools stdlib 전용 | **분기** — 파서·pptx 빌더는 의존 필요(회의록 lxml 예외와 동류) |
| A2 하이브리드 SSOT | md=git, 사무파일=Google Drive | **정합** — pages md=git, pptx 납품본=deliverables/(E2 예외) |

---

## R. 로드맵
- **P0**(스캐폴드+dogfooding): `ax:rfp-extract→toc→strategy→draft` 이식, **바이오 사업으로 검증**(요구사항 99건·참여사A 목차·전략 분석 이미 확보 → 즉시 dogfooding).
- **P1**: `ax:evaluate` 3-Agent 코드화(RFP Ⅴ 배점 반영).
- **P2**: `ax:build-deck`(md→PPTX 결정론 빌더).
- **P3**: 수행축 revision 머지(revision 축 담당자 `feat/revision-minutes-plugin`).
- **P4**: `ax:propose` + 스케줄러 + Leader Aggregation(registry 교차집계).

## S. 미확정·검증 필요
- RAG 대체(파일 컨텍스트 직접주입)의 대규모 자산 스케일 한계 — 경량검색/registry 차원 검색 시점 판단.
- 3-Agent 반복의 비용·상한(N)·목표점수 기본값.
- Leader-Worker 계정 부여(Claude ×10 vs 엔터프라이즈, Reply 5) — 인증 병목 회피 방식 revision 축 담당자와 합의.
- 제안/수행 레포 분리 경계 구체화.
