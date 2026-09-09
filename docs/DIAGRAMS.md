# ax 도식 명세서 (Diagram Specification)

| 항목 | 내용 |
|---|---|
| 문서명 | ax 아키텍처 도식 명세서 |
| 버전 | v1.8.0 |
| 작성일 | 2026-07-26 |
| 근거 | [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) · [`docs/design/`](design/) |
| 대상 | 설계 검토·유지보수·팀 온보딩 |

> 본 명세서는 ax 도구의 **시스템·컴포넌트·데이터·프로세스·상태·일정**을 표준 도식으로 정리한다. 각 도식은 **목적 → 도해 → 설명**으로 구성한다. (본문 흐름도 4종은 `ARCHITECTURE.md` §1·§2·§6 참조)

## 도식 목록
| No | 명칭 | 유형 |
|---|---|---|
| D-1 | 시스템 구성도 | Context |
| D-2 | 4-스택 SSOT 배포 구성도 | Deployment |
| D-3 | 플러그인 컴포넌트 구성도 | Component |
| D-4 | 데이터 흐름도(DFD Lv.1) | DFD |
| D-5 | 데이터 모델(ERD) | ERD |
| D-6 | 시퀀스 — 제안 파이프라인 | Sequence |
| D-7 | 시퀀스 — 자율 dispatch + HITL | Sequence |
| D-8 | 시퀀스 — 주간보고 발신 | Sequence |
| D-9 | 상태 전이도 — 평가 반복 | State |
| D-10 | 개발 로드맵 | Gantt |

---

## D-1. 시스템 구성도 (Context)

**목적**: 사용자 환경·ax 플러그인·외부 서비스·사업 폴더의 전체 관계.

```mermaid
flowchart TB
    U([팀원 · PM/엔지니어])
    subgraph CLIENT["사용자 환경 · VSCode + Claude Code"]
        subgraph AX["ax 플러그인 v1.8.0"]
            AG["에이전트<br/>pm · pl · pp"]
            SK["스킬 16+<br/>제안축·수행축·공통"]
            SCR["스크립트<br/>bash · python · node"]
        end
        PROJ[("사업 폴더<br/>1사업 = 1repo")]
    end
    subgraph EXT["외부 서비스 · ax-harness org"]
        GH[("GitHub<br/>텍스트 SSOT")]
        GD[("Google Drive<br/>사무파일 SSOT")]
        SL["Slack<br/>유입 · 발신"]
        NT["Notion<br/>게시본"]
    end
    U --> AG
    AG --> SK --> SCR
    AG <--> PROJ
    SCR <-->|"files·git·API"| GH
    SCR <--> GD
    SCR <--> SL
    SCR <--> NT
    PROJ <--> GH
    classDef ax fill:#e8f0ff,stroke:#2f6fd0
    classDef ext fill:#eef7ea,stroke:#2b7a4b
    class AG,SK,SCR ax
    class GH,GD,SL,NT ext
```

**설명**: 인증 경계는 **ax-harness org 멤버십**(A7). 부수효과(git·API)는 스크립트만 수행하고, 에이전트는 사업 폴더(SSOT)와 파일로만 상호작용한다(A3).

---

## D-2. 4-스택 SSOT 배포 구성도 (Deployment)

**목적**: 자료 유형별 SSOT 소재와 핸드오프 경로.

```mermaid
flowchart LR
    SL["Slack<br/>(유입 단일 진입점)"] -->|slack_download| LOC["사업 폴더<br/>slack-files/·inbox/"]
    LOC -->|office_to_md·docquark| MD["텍스트·지식맵"]
    MD -->|github_push| GH[("GitHub<br/>= 텍스트/소스 SSOT")]
    LOC -->|gdrive_sync| GD[("Google Drive<br/>= 사무파일 SSOT")]
    GH -->|"notion-publish 스킬(MCP)"| NT["Notion<br/>= 사람이 읽는 게시본"]
    GH -->|build_report → slack_post| SL2["Slack<br/>(발신 · 주간보고)"]
    classDef ssot fill:#eef7ea,stroke:#2b7a4b
    class GH,GD ssot
```

**설명**: `.md`·소스는 GitHub, 대용량 사무파일(hwp·ppt·xls·pdf)은 Google Drive 가 SSOT(하이브리드, A2). 중복은 rclone 체크섬으로 멱등 제거. GitHub↔Notion은 게시, GitHub→Slack은 주간보고 발신(역방향).

---

## D-3. 플러그인 컴포넌트 구성도 (Component)

**목적**: `plugin/ax/` 모듈 구조와 의존.

```mermaid
flowchart TB
    subgraph AGENTS["agents/"]
        PM[pm]; PL[pl]; PP[pp]
    end
    subgraph SKILLS["skills/"]
        direction LR
        S_PROP["제안축<br/>rfp-extract·toc·strategy<br/>draft·evaluate·build-deck·dispatch"]
        S_EXEC["수행축<br/>manage-schedule·risk·deliverable·config<br/>manage-revision·minutes·premise·report"]
        S_COM["공통<br/>categorize-files·inbox·run-sync·notion-publish·start-from-notion"]
    end
    subgraph SCRIPTS["scripts/"]
        SC_EFF["부수효과<br/>slack·github·gdrive·office_to_md"]
        SC_BLD["빌더(결정론)<br/>build_wbs·rtm·minutes·premise·report<br/>docquark.mjs·build_deck·evaluate_aggregate·dispatch·hitl_scan·registry_aggregate"]
    end
    TPL["templates/<br/>deliverables.json·config·회의록양식.hwpx·schedule.crontab"]
    PP --> S_PROP
    PM --> S_EXEC
    PM --> S_COM
    S_PROP --> SC_BLD
    S_EXEC --> SC_BLD
    S_PROP --> SC_EFF
    SC_BLD -. 참조 .-> TPL
    classDef prop fill:#fff2e0,stroke:#e08a2e
    classDef exec fill:#e8f0ff,stroke:#2f6fd0
    class PP,S_PROP prop
    class PM,PL,S_EXEC exec
```

**설명**: 에이전트→스킬→스크립트 단방향 호출. 인지 스킬은 `prompt.md`+`schema.json`을 동반. 부수효과는 엔트리포인트 스크립트로만.

---

## D-4. 데이터 흐름도 (DFD Level-1)

**목적**: 외부 입력 → 처리(빌더) → 데이터 저장소(SSOT) → 파생 산출.

```mermaid
flowchart LR
    RFP[/RFP·회의·자산/]:::inp
    RFP --> P1(("정제·목차<br/>rfp-extract·toc"))
    P1 --> D1[("requirements.json<br/>toc.json")]:::store
    D1 --> P2(("docquark"))
    P2 --> D2[("knowledge/quark")]:::store
    D1 --> P3(("전략·본문·평가"))
    D2 --> P3
    P3 --> D3[("strategy.md·pages/·eval/")]:::store
    D3 --> P4(("build_deck"))
    P4 --> OUT1[/발표자료.pptx/]:::out

    MIN[/회의·진행/]:::inp --> P5(("revision 빌더"))
    P5 --> D4[("wbs.data.json·rtm·premise.yml·회의록.yml")]:::store
    D4 --> P6(("build_report"))
    P6 --> OUT2[/주간보고·xlsx·hwpx/]:::out
    OUT1 --> ARC[("deliverables/<br/>납품 Archive")]:::store
    OUT2 --> ARC
    classDef inp fill:#f5f5f5,stroke:#888
    classDef store fill:#eef7ea,stroke:#2b7a4b
    classDef out fill:#fff2e0,stroke:#e08a2e
```

**설명**: 구조화 데이터(json/yml)가 SSOT, 빌더가 md(리뷰)+납품본(pptx/xlsx/hwpx)을 파생(D2). 작업본 ⊥ 납품본 경로 분리.

---

## D-5. 데이터 모델 (ERD)

**목적**: 제안축·수행축 SSOT 엔티티 관계.

```mermaid
erDiagram
    REQUIREMENT ||--o{ TOC_PAGE : "req_ids 매핑"
    CHAPTER ||--|{ SECTION : 포함
    SECTION ||--|{ TOC_PAGE : 포함
    TOC_PAGE ||--o{ PAGE_MD : 생성
    PAGE_MD ||--o{ EVAL_FINDING : 채점
    RUBRIC ||--o{ EVAL_FINDING : 기준
    REQUIREMENT {
        string id
        string category
        string summary
        string quote
        string owner
    }
    TOC_PAGE {
        string page_id
        string owner
        int score
    }
    WBS_TASK ||--o{ RTM_ITEM : 커버
    PREMISE ||--o{ WBS_TASK : "흔들면 파급"
    MINUTES ||--o{ PREMISE : "근거(provenance)"
    WBS_TASK {
        string id
        int level
        string status
        string due
    }
    PREMISE {
        string id
        string status
        string confirmedAt
    }
```

**설명**: 제안축(REQUIREMENT↔TOC↔PAGE↔EVAL)과 수행축(WBS↔RTM, PREMISE←MINUTES)의 참조 관계. PREMISE는 회의록을 증류하며 신선도(확인시점 vs git 커밋)로 stale 판정.

---

## D-6. 시퀀스 — 제안 파이프라인

**목적**: RFP 투입부터 발표자료까지 에이전트·스크립트·파일 상호작용.

```mermaid
sequenceDiagram
    actor U as 사용자
    participant PP as pp
    participant SC as 스크립트
    participant SUB as 서브에이전트
    participant FS as 파일 SSOT
    U->>PP: "이 RFP로 제안서 초안"
    PP->>SC: parse_doc·rfp_regex (부수효과)
    SC->>FS: rfp.txt·cards.json
    PP->>SUB: prompt.md로 정제 (병렬/인라인)
    SUB->>FS: requirements.json
    PP->>SC: node docquark.mjs
    SC->>FS: knowledge/quark
    PP->>SUB: 전략·본문 (quark target-jump)
    SUB->>FS: strategy.md·pages/*.md
    loop 목표점수 미달 & 상한 이내
        PP->>SUB: 위원 A·B·C 채점(병렬)
        SUB->>FS: eval/w_*.json
        PP->>SC: evaluate_aggregate.py agg
        SC-->>PP: 종합점수·종료판정
        PP->>SUB: 페이지 수정
    end
    PP->>SC: build_deck.py
    SC->>FS: 발표자료.pptx → deliverables/
    PP-->>U: 완료 요약 + 잔여 감점 Top
```

---

## D-7. 시퀀스 — 자율 dispatch + HITL

**목적**: 드롭 자료 자동 라우팅과 사용자 확인(자율 ≠ 맹목).

```mermaid
sequenceDiagram
    participant CR as 스케줄러/inbox
    participant SC as dispatch.py
    participant PM as pm
    actor U as 사용자
    CR->>SC: slack-pull → 신규 파일
    SC->>SC: categorize (신뢰도·phase)
    alt 신뢰도≥0.75 & phase 정합
        SC-->>PM: action=<스킬>
        PM->>PM: 해당 스킬 실행 → 커밋
    else 신뢰도<0.75 or phase 불일치
        SC-->>PM: action=ask
        PM->>U: AskUserQuestion(옵션)
        U-->>PM: 선택/피드백
        PM->>PM: SSOT 반영 → 재판정
    end
```

---

## D-8. 시퀀스 — 주간보고 발신 (H2)

**목적**: 결정론(사실) ⊥ 서술 ⊥ 발신 분리 입증.

```mermaid
sequenceDiagram
    participant CR as 매주 스케줄
    participant BR as build_report.py
    participant PM as pm
    participant SP as slack_post.sh
    participant CH as Slack 채널
    CR->>BR: revision·config 증류
    BR->>BR: 완료율·지연·D-day·전제 stale (결정론)
    BR-->>PM: 주간보고 md(사실)
    PM->>PM: 한 줄 총평 (서술)
    PM->>SP: 📮 발신본 + 담당 UID
    SP->>CH: 게시 + owner 멘션
```

---

## D-9. 상태 전이도 — 평가 반복 (evaluate)

**목적**: 3-Agent 평가 루프의 종료조건(무한루프 방지).

```mermaid
stateDiagram-v2
    [*] --> 채점
    채점 --> 집계 : 위원 A·B·C findings
    집계 --> 판정
    판정 --> 종료 : score≥목표
    판정 --> 종료 : round≥상한
    판정 --> 종료 : Δ<정체임계
    판정 --> 수정 : 그 외
    수정 --> 채점 : pages 갱신·round++
    종료 --> [*]
```

---

## D-10. 개발 로드맵 (Gantt)

**목적**: P0~P5 진행과 후속 일정(표현용).

```mermaid
gantt
    title ax 제안축·오케스트레이션 로드맵
    dateFormat YYYY-MM-DD
    axisFormat %m/%d
    section 완료 (v1.8.0)
    P0 스캐폴드·설계        :done, 2026-07-24, 2026-07-26
    P1~P2 평가·PPTX         :done, 2026-07-26, 1d
    P3~P5 자율·감리·registry :done, 2026-07-26, 1d
    리뷰·통합테스트·근본수정  :done, 2026-07-26, 1d
    릴리스 v1.8.0           :milestone, done, 2026-07-26, 0d
    section 예정
    실호출 통합검증(새 세션)  :active, 2026-07-27, 3d
    자율 dispatch 임계 튜닝   :2026-07-30, 5d
    registry 대시보드 고도화  :2026-08-05, 7d
    제안축 Beta 해제         :milestone, 2026-08-12, 0d
```

---

*본 명세서의 도식은 GitHub 마크다운(Mermaid)에서 자동 렌더된다. 수정 시 `ARCHITECTURE.md`와 정합을 유지한다.*
