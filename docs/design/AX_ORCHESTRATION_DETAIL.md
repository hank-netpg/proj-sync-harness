# DETAIL — 4부 세밀 설계 (docquark · 3-Agent · dispatch/HITL · 스킬 실물)

> `AX_ORCHESTRATION_SPEC.md`의 4개 지점을 구현 직전 수준으로 정밀화. 스키마는 SPEC 참조.

---

## A. docquark 어댑터 (문서 → quark 트리)

### A1. 변환 알고리즘 (결정론, `tools/docquark.mjs`)
입력 `proposal/requirements.json` + `proposal/toc.json` → 출력 `knowledge/{quark,_mirror,_axon,ai_context_guide.txt}`.

```
1) slug(s)  = s.trim().replace(/[\/\s:·]+/g,'_').replace(/[^\w가-힣_-]/g,'').slice(0,40)
2) for req in requirements.items:
     dir = quark/req/{req.id}__{slug(req.summary)}/
     write dir/summary.md  = req.summary
     write dir/quote.md    = req.quote
     write dir/detail.md   = "- " + req.detail.join("\n- ")
     mkdir dir/kind__{req.category}/          # 빈 마커(분류)
     mkdir dir/담당__{req.담당}/
     mkdir dir/성격__{req.성격}/
3) for ch in toc.chapters, se in ch.sections, pg in se.pages:
     dir = quark/toc/{ch.id}__{slug(ch.title)}/{se.id}__{slug(se.title)}/{pg.page_id}__{slug(pg.title)}/
     write dir/meta.md  = {담당,협업,스토리라인,산출물,배점:se.배점}
     for rid in pg.req_ids: ln -s ../../../../req/{rid}__* dir/_axon/req__{rid}
4) _mirror:  for req: ln -s quark/req/{id}__* _mirror/by_kind/{category}/
                       ln -s … _mirror/by_담당/{담당}/  ; by_배점/{배점}/ (via toc)
5) _axon/by_page/{page_id}  = 역링크(page→req, page→strategy 섹션)
6) ai_context_guide.txt (A3)
```

### A2. _axon 링크 규칙 (req ↔ toc ↔ 자산)
- **req→toc**: `req.toc_paths`(requirements.json) — 결정론.
- **toc→req**: `pg.req_ids`(toc.json) — 결정론. 양방향 일치 검증(불일치 시 A4 경고).
- **req→자산**: 자산 md의 요구사항 ID 태그(frontmatter `covers:[SFR-001]`) grep → `_axon/req__{id}/asset__{file}`. 태그 없으면 미링크(자산은 by_role만).
- **req→배점**: req의 toc_path → se.배점 역참조.

### A3. ai_context_guide.txt (에이전트 내비 지침)
```
# 이 지식맵 사용법 (RAG 대신 폴더 탐색)
- 요구사항 근거:  cat knowledge/quark/req/{ID}__*/{summary,quote,detail}.md
- 목차 한 페이지가 덮는 요구사항:  ls knowledge/quark/toc/{장}/{절}/{page}/_axon/
- 담당사별 요구사항:  ls knowledge/_mirror/by_담당/{주관사|참여사A|참여사B}/
- 배점 큰 영역:  ls knowledge/_mirror/by_배점/기능15/
- 절대 원문 없는 인용 금지 — quote.md에 있는 문장만 인용.
```

### A4. 증분 재빌드 + 정합 경고
- **멱등 전체 재빌드** 기본(수백 quark라 저비용, sha256(requirements.json+toc.json) 변화 시만 실행).
- **정합 경고**(HITL C 연동): ① req.toc_paths ↔ toc.req_ids 불일치 ② toc_path 없는 req(고아) ③ req_ids에 없는 ID. → `knowledge/_UNMAPPED.md`에 적재 + dispatch가 §HITL Q4 질문 트리거.
- **quarkify 코드맵(개발시점)은 별개**: `node quarkify.mjs configs/ax.mjs` → `_codemap/`(gitignore). 코드 변경 커밋 훅에서 재quark(선택).

---

## B. 3-Agent 평가

### B1. 평가위원 3 페르소나 (system prompt 원문 — 신규 작성)
공통 접두(3인 공유):
```
당신은 한국 공공 SW 제안서 평가위원이다. 만점(배점한도)에서 시작해 결함을 비판적으로 탐색하여 감점한다.
관대하게 보지 말고, 평가위원 관점에서 "구체성·실현가능성·근거"가 부족한 지점을 집요하게 찾는다.
출력은 JSON만: [{"항목키","배점","감점","근거(무엇이 왜 부족)","개선지시(무엇을 추가/수정)","page_id"}].
```
| 위원 | 전문 | 감점 집중 |
|---|---|---|
| **A** | IT SI 20년+ | 아키텍처 구체성·통합/연계·기술 실현가능성·표준프레임워크·확장성. "그림만 있고 방식 없음" 탐지 |
| **B** | 응용SW 20년+ | 기능 구현 방안·데이터 설계/검증·품질(환각·정확도)·보안 전단계 내재화. "요구 나열만, 구현 how 없음" 탐지 |
| **C** | 사업관리 20년+ | 일정/WBS 현실성·인력 적합성·위험 대응·산출물 완결성·인수인계. "선언적·정량근거 없음" 탐지 |

### B2. 채점 rubric (RFP Ⅴ 배점 → 항목별 감점 기준)
`proposal/rubric.json` (toc.json#평가배점에서 생성):
```jsonc
{ "항목":[
  {"key":"기능요구사항","배점":15,"만점조건":"32개 SFR 각 구현방안+차별성+경쟁사대비",
   "감점카탈로그":[{"사유":"구현 how 부재","감점":-1.0/건},{"사유":"차별성 없음","감점":-0.5}]},
  {"key":"데이터요구사항","배점":10,"만점조건":"VectorDB/KG 설계+전환·검증+오류처리","감점카탈로그":[…]},
  {"key":"추진전략","배점":8,"만점조건":"위험·보안 고려 대안 구체","…":[]}
 ], "총점":90, "가격":10 }
```
- 감점 상한 = 항목 배점. 위원별 감점 합산 후 **최고·최저 위원 제외 없이 3인 평균**(프로토타입 방식) 또는 가중.

### B3. 반복 오케스트레이션 (Workflow 의사코드)
```js
let round=0, score=baseline(pages), hist=[score];
while (round < cfg.max_rounds) {
  const findings = await parallel([A,B,C].map(p => () =>
     agent(`${persona[p]}\n대상 pages:\n${pagesDigest}`, {schema:FINDINGS})));   // 위원 병렬(인지)
  score = 집계(findings, rubric);                                               // 결정론
  write(`proposal/eval/${round}.json`, {round,score,findings});
  if (score >= cfg.target) break;                                              // 목표 도달
  if (round>0 && score - hist.at(-1) < cfg.min_delta) break;                   // 정체(무한루프 방지)
  hist.push(score);
  const byPage = group(findings.flatMap(f=>f.개선지시), 'page_id');            // 페이지별 묶음
  await parallel(Object.entries(byPage).map(([pid,fixes]) => () =>
     agent(`page ${pid} 아래 지적 반영해 재작성:\n${fixes}\n원본:\n${read(pid)}`,
           {schema:PAGE_V3}).then(md=>write(`proposal/pages/${pid}.md`, md))));  // 수정 병렬
  round++;
}
report(`proposal/eval/_FINAL.md`, {진화:hist, 잔여감점:top(findings)});
```
- **종료 3조건**: `score≥target` OR `round≥max_rounds` OR `Δ<min_delta`. 정체 감지가 프로토타입 76.5/80 구조적 한계 대응.
- H2: 집계=결정론 / 위원·수정=에이전트 / 파일 핸드오프(eval·pages).

---

## C. 자율 dispatch + HITL

### C1. categorize 신뢰도 산정 (0~1)
`categorize-files` 확장 — 3신호 가중:
```
conf = 0.4·ext_match + 0.4·filename_kw + 0.2·content_signal
 ext_match     : 확장자↔카테고리 규칙 적중(hwp/hwpx→RFP, xlsx→목차/예산, yml→회의록) = 1/0
 filename_kw   : 파일명 키워드(제안요청서·목차·회의록·WBS·요구사항) 적중 = 1/0
 content_signal: 첫 2KB에 카테고리 시그니처(RFP="제안요청"·"과업내용" / 회의록="안건"·"참석") = 1/0
```
- `conf ≥ 0.75` → 자동 dispatch. `< 0.75` → C3 질문. (임계값 config.dispatch.confidence_threshold, P3 실측 튜닝.)

### C2. dispatch 상태기계
```
idle →(신규 파일/스케줄)→ ingesting(slack-pull.sh) → classifying(categorize, conf)
 → [conf≥τ & phase정합] dispatching → executing(스킬) → committing(github-push) → idle
 → [conf<τ | phase불일치 | 정합경고] awaiting_user(AskUserQuestion) →(피드백)→ dispatching
```
- watcher/pull/commit = 스크립트(부수효과) / classify·dispatch 판정 = PM 에이전트(인지). A3.

### C3. HITL 6종 — 결정론 술어 + 질문 + 반영
| # | 탐지 술어(결정론) | 질문(옵션 제시) | 반영(SSOT) |
|---|---|---|---|
| 1 | `premise.status ∈ {가정,미확정,위반위험}` | "PR-06 NPU 확정/미정/보류?" | premise.yml→build_premise |
| 2 | `git_log1(근거파일).date > premise.확인시점` | "근거 회의록 갱신됨 — 전제 재확인?" | premise.확인시점 |
| 3 | `wbs.leaf: status≠완료 AND due<today` | "지연 task 만회/재일정/수용?" | wbs.data.json→build_wbs |
| 4 | docquark `_UNMAPPED.md ≠ ∅` (고아 req/불일치) | "요구사항 X 목차 어디 배치?" | toc.json.req_ids |
| 5 | `rubric.항목.규정 ∈ 미확인`(SW특칙·배점·예정가) | "SW특칙 적용? 발주처 질의?" | 질의서 draft + config |
| 6 | `conf < τ OR phase≠파일유형` | "이 자료 제안용/수행용/기타?" | dispatch 경로·phase |
- **질문 형식**: 옵션형(사용자 "결정은 내가" — 항상 선택지 + 권장 1). 자유입력 허용. 피드백 → SSOT write → 관련 빌더 재실행 → 재개(상태기계 dispatching 복귀).
- **묶음 질문**: 한 트리거 사이클에서 다수 발생 시 AskUserQuestion 최대 4개 배치(과도한 질문 방지).

---

## D. 제안축 스킬 실물

### D1. `skills/rfp-extract/SKILL.md` (실행가능 정의)
```markdown
---
name: rfp-extract
description: RFP(hwpx/pdf)에서 요구사항을 추출해 requirements.json(SSOT) 생성. "요구사항 추출","RFP 분석","제안요청서 분해" 시 사용.
---
1. 파싱(부수효과): `bash ${ROOT}/scripts/parse_doc.sh {rfp}` → `proposal/_extracted/rfp.txt`(hwpx=lxml, pdf=pypdf)
2. 1차 정규식 추출: `python3 ${ROOT}/tools/rfp_regex.py` → cards(id/context)
3. 정제(인지): cards를 30건 배치로 서브에이전트에 전달, prompt.md 적용 → JSON 배열
4. 병합·검증: schema.json 대조, requirements.json 저장
5. docquark: `node tools/docquark.mjs` → knowledge/ 갱신
6. 요약 보고(1~3줄) + 다음 스킬(toc) 제안
```
- `prompt.md` = `rfp_extractor._REFINE_SYSTEM/_USER` 이식(JSON 배열, category/summary/quote, category_choices).
- `schema.json` = SPEC §4-1.

### D2. 서브에이전트 호출 계약 (A3 인지 격리)
- 인지 스킬(rfp-extract·toc·strategy·draft)은 **Task/서브에이전트**로 LLM 호출 — 인라인 API·토큰 없음(GPU 없음, Claude Code).
- 부수효과(parse·docquark·git)는 **스크립트 엔트리포인트**만. 스킬 절차가 스크립트↔에이전트를 **파일로 핸드오프**.

### D3. `ax:draft` page_generator 알고리즘 (quark 치환 상세)
```
for pg in toc.pages (담당·배점 우선순위 정렬):
  reqs   = [read(knowledge/quark/req/{rid}__*/) for rid in pg.req_ids]   # RAG 아님, 폴더 cat
  strat  = read(strategy.md, section matching pg.장)                     # 발췌
  assets = ls(knowledge/_axon/by_page/{pg.page_id}/asset__*)             # 링크된 자산만
  md = agent(page_generator._SYSTEM,
             _USER.format(page=pg, requirements=reqs, strategy=strat, assets=assets),
             {schema:PAGE_V3})                                            # Claude 서브에이전트
  if not valid_frontmatter(md): md = retry(once)                         # 검증+1회
  write(proposal/pages/{pg.page_id}.md, md)
```
- 입력 컨텍스트가 **해당 page의 req 폴더만**(전체 아님) → 토큰 최소·환각 0(quote.md 원문만 인용).

### D4. 스킬 배치 위치 (레포 분리 — 결정3)
- 스킬 정의(SKILL.md·prompt.md·schema.json)·스크립트·빌더 = **도구 repo**(hankeon/proj-sync-harness plugin `src/`).
- 산출 데이터(requirements.json·pages·knowledge) = **사업 repo**(ax-{proj}-doc). 도구는 CWD 사업 폴더에 산출(B1).

---

## E. 검증 대조 (실 데이터)
- requirements.json SFR-001 ↔ 제안요청서분석서(정확도75%·PubMed) ✓
- toc.json III-1-1 ↔ 참여사A 목차 III.1.1.1(SFR-001~008) ✓ · 평가배점 23/30/11/6/10/6/4/10 ↔ RFP Ⅴ ✓
- 위원 페르소나 ↔ evaluation_2026.md(IT SI/응용SW/사업관리 20년+) ✓ · 76.5/80 ↔ _FINAL_3AGENT_RESULT ✓
- quark/_mirror/_axon/ai_context_guide ↔ quarkify 출력 레이아웃 ✓
- 프롬프트 4종 출처(propstudio) 정확 ✓
