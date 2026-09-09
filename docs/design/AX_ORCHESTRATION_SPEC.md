# SPEC(오케스트레이션) — 구현 명세

> `AX_ORCHESTRATION_DESIGN.md`(개념·전제)의 **구현 계약**. 폴더 레이아웃·JSON 스키마·스킬 I/O·docquark 어댑터·3-Agent 오케스트레이션·dispatch 규칙·human-in-loop 트리거·registry 스키마를 못박는다.  
> 원칙: A3 부수효과⊥인지 · A5/quarkify "everything is a folder" · D2 data-SSOT→파생 · GPU 대신 Claude Code.

---

## 1. 사업 repo 폴더 레이아웃 (통합)

```
{project}/                              # 1사업=1폴더=1repo (B1)
├── .proj-sync/config.json              # 허브 (phase·profile·wbs·report)
├── inbox/                              # ★ 드롭존 — 사용자가 자료 올리는 특정 위치 (§5)
├── slack-files/                        # slack-pull 원본 (부수효과 산출)
├── knowledge/                          # ★ docquark 지식맵 (§3, RAG 대체)
│   ├── quark/  _mirror/  _axon/  ai_context_guide.txt
├── proposal/                           # ★ 제안축 SSOT + 산출물 (§4)
│   ├── requirements.json  toc.json  strategy.md
│   ├── pages/{page_id}.md              # v3 propdraft 초안
│   ├── eval/{round}.json               # 3-Agent 평가 (§6)
│   └── build/발표자료.pptx              # 납품 파생 → deliverables/ 링크
├── revision/                           # 수행축 (§D~H): history·wbs·rtm·회의록·전제
├── reference/drafts/00_영업_제안 … 50_종료_인도   # 별표2 작업본 (A5)
│   ├── form/  management/{schedule,risk,config,reports}
├── deliverables/                       # 납품 Archive (전부 git, E2)
├── tools/                              # 결정론 빌더 (build_*.py, docquark.mjs)
└── PREMISE.md  (파생)
```

- **경계**: `proposal/`=제안 phase 산출 / `revision/`=수행 phase 산출 / `knowledge/`=양 phase 공용 근거맵. phase가 어느 폴더를 활성화할지 결정(§O).

---

## 2. config.json 확장 (신규 필드)

```jsonc
{
  "lifecycle": { "phase": "제안", "sdlc_stages": ["착수","분석","설계","구현","종료"],
                 "audit_gate": true },          // 감리=수행중 내부 게이트 (결정1)
  "proposal": {                                  // ★ 신규 (제안축)
    "rfp_files": ["inbox/1__제안요청서.hwpx"],
    "eval": { "target_score": 90, "max_rounds": 5, "min_delta": 0.5,
              "rubric_ref": "toc.json#평가배점" },
    "consortium": [ {"id":"WERT","지분":0.44}, {"id":"TNP","지분":0.46},
                    {"id":"SNU","지분":0.10} ]
  },
  "knowledge": { "engine": "quarkify", "quark_dir": "knowledge",
                 "asset_globs": ["reference/실적/**/*.md"] },
  "dispatch": { "auto": true, "confidence_threshold": 0.75 },  // §5 게이트
  "authorization": { "worker_account": "self", "leader_registry": "<your-org>/proj-sync-registry" } // 결정2
}
```

---

## 3. docquark 어댑터 (문서 → quark 트리) — self-critique 해소

- **문제**: quarkify는 소스코드 파서(TS/JS/Py/Java). 문서(RFP·요구사항·목차)→quark는 직접 미지원.
- **해결**: `tools/docquark.mjs` — 구조화 SSOT(requirements.json·toc.json)를 입력받아 quarkify와 **동형 레이아웃**(quark/_mirror/_axon/ai_context_guide.txt)을 materialize하는 경량 어댑터. (quarkify 본체는 개발시점 코드맵에만, 런타임 문서맵은 docquark.)

```
knowledge/
├── quark/
│   ├── req/
│   │   └── SFR-001__지능형문헌분석/
│   │       ├── summary.md            # 1줄 개조식
│   │       ├── quote.md              # RFP 원문 핵심 인용
│   │       ├── detail.md             # 세부요구 5개
│   │       ├── kind__기능/           # (빈 마커 폴더=분류)
│   │       ├── 담당__주관사/
│   │       └── _axon/ → toc__III-1-1, 배점__기능15
│   └── toc/
│       └── III__기술및기능/1__기능요구사항/1-1__R&D지식탐색/
│           └── _axon/ → req__SFR-001 … req__SFR-008, PLR-001..005
├── _mirror/
│   ├── by_kind/{기획,설계,기능,데이터,보안,임상,사업화,…}/ → symlink to quark/req/*
│   ├── by_담당/{주관사,참여사A,참여사B,공동}/
│   └── by_배점/{기능15,데이터10,보안3,…}/
├── _axon/  by_page/  (page_id → req·전략·자산 역링크)
└── ai_context_guide.txt   # "요구사항 근거는 ls knowledge/quark/req/{ID}__*/, 목차는 knowledge/quark/toc/…"
```

- **draft 에이전트 사용법**(RAG 없이): `tree knowledge/quark/toc/III__기술및기능/1__기능요구사항/1-1__*/_axon` → 링크된 req 확인 → `cat knowledge/quark/req/SFR-001__*/{summary,quote,detail}.md` → `ls _mirror/by_담당/주관사` → 본문 작성. **환각 0%(실물 폴더)·토큰 90%↓(target-jump)**.
- **부수효과⊥인지(A3)**: `docquark.mjs`(폴더 생성=스크립트) ⊥ draft 에이전트(탐색·작성=인지).

---

## 4. 제안축 스킬 I/O 계약

### 4-1. requirements.json (rfp-extract 산출, SSOT)
```jsonc
{ "project":"bio-global-ai", "count":99,
  "items":[ { "id":"SFR-001", "category":"기능", "성격":"핵심",
    "summary":"지능형 문헌 분석·데이터 마이닝 에이전트",
    "quote":"방대한 논문·특허를 자연어 질의로 분석…",   // 원문 1문장
    "detail":["PubMed 다중소스","섹션 구조화","환각방지 답변▶근거▶소스"],
    "담당":"주관사", "toc_paths":["III-1-1"], "배점":"기능요구사항(15)",
    "kpi":["출력정확도75%"] } ] }
```
- 프롬프트: `rfp_extractor._REFINE_SYSTEM/_USER`(JSON 배열, category/summary/quote). 배치 30건. Claude 서브에이전트.

### 4-2. toc.json (toc 산출, SSOT) — 참여사A 목차 3레벨 + 평가배점
```jsonc
{ "chapters":[ { "id":"III", "title":"기술 및 기능",
   "sections":[ { "id":"III-1", "title":"기능 요구사항", "배점":15,
     "pages":[ { "page_id":"III-1-1", "title":"R&D 지식탐색 에이전트군",
       "req_ids":["SFR-001","SFR-002","SFR-003"], "담당":"주관사",
       "협업":["참여사A(기획)"], "스토리라인":"문헌 병목 해소 로직",
       "산출물":"구조 설계서" } ] } ] } ],
  "평가배점":{ "전략방법론":23,"기술기능":30,"성능품질":11,"관리":6,"지원":10,"실적":6,"신용":4,"가격":10 } }
```
- 프롬프트: `toc_parser._REFINE_SYSTEM/_USER`. **입력 = 참여사A 목차(확정본) + RFP Ⅴ 배점** → page 단위 leaf + req 매핑 + 담당(우리 R&R).

### 4-3. strategy.md (strategy 산출)
- 프롬프트: `strategy_writer._STRATEGY_SYSTEM/_USER`. 입력 requirements.json → 5섹션(사업본질·차별화5·평가최대화·위험·톤앤매너). frontmatter(generated_at·model·project).

### 4-4. pages/{page_id}.md (draft 산출)
- 프롬프트: `page_generator._SYSTEM/_USER`. 입력 = toc page + req(quark) + strategy 발췌 + knowledge quark. 출력 v3 propdraft(frontmatter propdraft/governance 3-5/subtitle + 개조식 본문 700-1500자). frontmatter 검증+1회 retry.
- **알고리즘**(page_generator 이식, RAG→quark): ① toc.json에서 page의 req_ids ② `knowledge/quark/req/{id}` cat ③ strategy 발췌 ④ Claude 서브에이전트 ⑤ frontmatter 검증 ⑥ 저장.

### 4-5. 스킬 정의 형식 (proj-sync/ax skills/{name}/SKILL.md)
```
skills/rfp-extract/
├── SKILL.md          # description·trigger·절차(스크립트 호출 + 서브에이전트 프롬프트)
├── prompt.md         # 이식 system/user 프롬프트 (SSOT)
└── schema.json       # 산출 JSON 스키마 (검증용)
```

---

## 5. 자율주행 dispatch (결정론 규칙)

### 5-1. 흐름
`inbox/ 또는 Slack 신규` → `slack-pull.sh`(부수효과) → `categorize-files`(분류) → **dispatch 판정**(PM 에이전트, 결정론표) → 스킬 실행.

### 5-2. dispatch 규칙표 (phase × 파일유형)
| phase | 파일유형(categorize) | dispatch | 게이트 |
|---|---|---|---|
| 제안 | RFP(hwpx 제안요청서) | `rfp-extract`→`toc` | 신규 RFP 확인 |
| 제안 | 목차/분담(xlsx) | `toc` 갱신 | — |
| 제안 | 회사자산·실적(pdf/md) | docquark 재빌드(`asset`) | — |
| 수행중 | 회의록·WBS·RTM(yml/xlsx) | `revision` 빌더 | — |
| * | 분류 불확실(conf<τ) | **정지→§6 질문** | 사용자 확인 |
| 제안≠파일 | phase 불일치(수행중에 RFP) | **정지→질문** | phase 전환? |

- **오판 방지**: `confidence_threshold`(config 0.75) 미달 또는 phase 불일치 → 자동 실행 안 함, human-in-loop 질문. (자율 ≠ 맹목)

---

## 6. human-in-the-loop 질문 트리거 (결정론 소스)

| # | 트리거(결정론 탐지) | 소스 | 질문 예 | 반영 |
|---|---|---|---|---|
| 1 | 전제 `상태≠합의`(가정/미확정/위반위험) | `revision/전제/premise.yml` | "PR-06 NPU 확정?" | premise.yml→rebuild |
| 2 | 전제 stale(신선도, git 커밋>확인시점) | build_premise | "회의록 갱신됨—전제 재확인?" | 확인시점 갱신 |
| 3 | WBS 지연(status≠완료 & due<오늘) | wbs.data.json | "지연 task 만회계획?" | wbs 갱신 |
| 4 | 요구사항 모호·담당 미정 | requirements.json | "요구사항 X 담당·범위?" | requirements 갱신 |
| 5 | 평가 규정 미확인(SW특칙·배점) | toc.json#평가배점 | "SW특칙 적용? 발주처 질의?" | 질의서 트리거 |
| 6 | dispatch 분류 불확실/phase 불일치 | §5 | "이 자료 제안용/수행용?" | phase·dispatch |

- **구현**: PM 에이전트가 매 트리거를 결정론 탐지→`AskUserQuestion`(옵션 제시)→피드백을 SSOT(premise.yml/config/requirements)에 반영→빌더 재실행. "1줄 확인" 원칙의 선제 질문 확장.

---

## 7. 3-Agent 평가 오케스트레이션 (ax:evaluate)

### 7-1. evaluation.json 스키마
```jsonc
{ "round":1, "score":67.6, "target":90,
  "위원":[ {"id":"A","역할":"IT SI 20년+","감점":-27.5,
    "항목":[ {"key":"기술적합성","배점":15,"감점":-5.5,"근거":"아키텍처 구체성 부족","개선지시":"TRM 도식 추가"} ] } ],
  "종합":73.2, "개선_dispatch":["III-3 보안 RACI 보강","IV-2 SLA 실측 추가"] }
```
- **항목 = RFP Ⅴ 평가배점**(toc.json#평가배점, 본 사업 기술90+가격10 세부)로 치환. 위원 3 페르소나(IT SI/응용SW/사업관리 20년+, evaluation_2026.md 근거).

### 7-2. 반복 루프 (Workflow 의사코드, 종료조건)
```
round=0; score=baseline
while score < target and round < max_rounds:
    findings = parallel(위원A,위원B,위원C 독립 감점)          # 인지, 병렬
    score = 집계(findings)                                    # 결정론
    if score >= target: break
    if Δscore < min_delta: break                             # 정체→정지(무한루프 방지)
    fixes = 수정agent 병렬(findings.개선_dispatch)            # pages/*.md 갱신
    round++
report(evaluation.json + Δ추이)
```
- 종료: `score≥target OR round≥max_rounds OR Δ<min_delta`. (프로토타입 76.5/80 구조적 정지 → 상한·정체 감지 필수.)
- **판정=결정론(집계)⊥개선=에이전트⊥발신=선택**(H2). 파일 핸드오프(eval/*.json, pages/*.md).

---

## 8. Leader-Worker registry 스키마 (계정별 — 결정2)

- **Worker**(팀원 계정별 Claude): 각자 담당 사업 폴더에서 revision 매일 commit-push. Issue를 registry에 push.
- **Leader**(registry aggregation): `<your-org>/proj-sync-registry`의 `registry.json` 확장 — 프로젝트별 요약 aggregation.
```jsonc
{ "projects":[ { "id":"bio-global-ai", "repo":"ax-harness/ax-bio-global-ai-doc",
    "phase":"제안", "worker":"worker1",
    "summary":{ "진척":0.12, "리스크_top":["예정가격 미확인"], "미확정전제":2,
      "마감":"2026-08-03T11:00" }, "updated":"2026-07-26" } ] }
```
- **갱신**: Worker의 `registry-sync`가 사업별 주간보고(build_report) 요약을 registry에 반영 → Leader가 전 사업 교차 조망(리스크·마감 D-day·정체). A7 인증 경계(org 멤버십) 유지, 단 Worker 계정별 토큰(병목 해소).

---

## 9. P0 실행 계약 (구체)
1. `proposal/` 스킬 4종(rfp-extract·toc·strategy·draft) SKILL.md+prompt.md+schema.json 스캐폴드.
2. `tools/docquark.mjs`(문서→quark) MVP.
3. **바이오 dogfooding**: 기존 `제안요청서분석서.md`(99건)→`requirements.json`, 참여사A 목차(확정)+우리 R&R→`toc.json`, docquark→`knowledge/quark/`, draft 1페이지(III-1-1) 실증.
4. 설계서 2건(DESIGN·SPEC) proj-sync `feat/proposal-orchestration` PR.

## 10. 미해결 (정밀화 후 잔여)
- docquark _axon 자동 링크 규칙(req↔toc 매핑 신뢰도) — toc.json req_ids 기반이라 결정론이나, 신규 매핑은 §6-4 질문.
- quarkify 개발시점 코드맵의 out 위치·갱신 주기(코드 변경 시 재quark).
- 3-Agent 위원 페르소나 프롬프트 원문(프로토타입 대화형이라 저장본 없음) — 신규 작성.
- pptx 빌더(build-deck) 세부는 P2.
