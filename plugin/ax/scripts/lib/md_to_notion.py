#!/usr/bin/env python3
"""proj-sync: 마크다운 → Notion 블록 변환 (공용).

easypatent 의 scripts/notion_sync.py 에서 검증된 변환기를 플러그인 공용으로 이식했다.
종전 REST 게시기(notion_publish.sh — v1.21.0 삭제)는 각 줄을 paragraph 로 밀어넣고 100블록에서 잘라, 표·코드블록·
mermaid 가 붕괴하고 긴 문서는 60% 이상 유실됐다.

지원: ATX 헤딩(#~######, h4+ 는 heading_3 으로 접음) · 불릿/번호 리스트 · 인용(>)
      · 구분선 · 코드블록(mermaid 포함) · GFM 표 · 인라인(굵게·코드·링크)

입력은 sanitize.scrub 을 거친다 — 복사돼 들어온 제로폭·BOM·bidi 문자가 그대로 게시되면
제목이 눈에 같아 보여도 다른 키가 되어 멱등이 깨진다(#21 과 같은 부류).

사용:
  md_to_notion.py <file.md>              # 블록 JSON 을 stdout 으로
  md_to_notion.py <file.md> --chunk 100  # 100개씩 나눈 배열의 배열
"""
import json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sanitize import scrub  # noqa: E402  (같은 lib/ 디렉터리)

_INLINE = re.compile(r"(\*\*.+?\*\*|`[^`]+`|\[[^\]]+\]\([^)]+\))")

# 표 셀 안의 이스케이프 파이프(`\|`)를 분해 중에 지키기 위한 자리표시자 (issue #29).
# 마크다운 원문에 나타날 수 없는 제어문자를 쓴다 — 본문과 충돌하면 그게 새 버그가 된다.
_PIPE_SENTINEL = "\x00PIPE\x00"

def _rich_text(text: str) -> list:
    if not text:
        return []
    out = []
    for part in _INLINE.split(text):
        if not part:
            continue
        anno, content, link = {}, part, None
        if part.startswith("**") and part.endswith("**"):
            anno = {"bold": True}
            content = part[2:-2]
        elif part.startswith("`") and part.endswith("`"):
            anno = {"code": True}
            content = part[1:-1]
        else:
            m = re.match(r"\[([^\]]+)\]\(([^)]+)\)", part)
            if m:
                content, url = m.group(1), m.group(2)
                # Notion link는 절대 URL(http/https/mailto)만 허용.
                # 상대경로·#앵커·wiki링크는 링크 없이 텍스트로(코드 스타일) 표기.
                if re.match(r"^(https?://|mailto:)", url):
                    link = url
                else:
                    content = f"{content} ({url})"
        # Notion rich_text 항목당 2000자 제한
        for i in range(0, len(content), 1900):
            chunk = content[i:i + 1900]
            rt = {"type": "text", "text": {"content": chunk}}
            if link:
                rt["text"]["link"] = {"url": link}
            if anno:
                rt["annotations"] = anno
            out.append(rt)
    return out or [{"type": "text", "text": {"content": text[:1900]}}]


def _para(text: str) -> dict:
    return {"object": "block", "type": "paragraph",
            "paragraph": {"rich_text": _rich_text(text)}}


def _table_block(rows: list[list[str]]) -> dict:
    """GFM 표 → Notion table 블록 (헤더 행 포함)."""
    width = max(len(r) for r in rows)
    children = []
    for r in rows:
        cells = [(_rich_text(c.strip())) for c in r]
        cells += [[] for _ in range(width - len(cells))]
        children.append({"object": "block", "type": "table_row",
                         "table_row": {"cells": cells}})
    return {"object": "block", "type": "table",
            "table": {"table_width": width, "has_column_header": True,
                      "has_row_header": False, "children": children}}


def md_to_blocks(md: str) -> list:
    """마크다운 본문 → Notion 블록 리스트. mermaid/코드/표/리스트/헤딩/인용/구분선."""
    md = scrub(md)   # 보이지 않는 문자를 먼저 걷어낸다 (제로폭·BOM·bidi)
    blocks: list = []
    lines = md.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # 코드블록 (``` 또는 ```lang, mermaid 포함)
        if stripped.startswith("```"):
            lang = stripped[3:].strip() or "plain text"
            body = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
                body.append(lines[i])
                i += 1
            i += 1  # 닫는 ```
            code = "\n".join(body)
            # Notion code 언어값 정규화 (mermaid 지원)
            notion_lang = "mermaid" if lang.lower() == "mermaid" else (
                lang if lang in _NOTION_LANGS else "plain text")
            # code rich_text 2000자 분할
            rt = [{"type": "text", "text": {"content": code[j:j + 1900]}}
                  for j in range(0, max(len(code), 1), 1900)]
            blocks.append({"object": "block", "type": "code",
                           "code": {"rich_text": rt, "language": notion_lang}})
            continue

        # 표 (| ... | 행이 2줄 이상 연속, 2번째가 구분행)
        if stripped.startswith("|") and i + 1 < len(lines) and re.match(
                r"^\s*\|?[\s:|-]+\|?\s*$", lines[i + 1]):
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                # 이스케이프된 파이프(`\|`)는 **셀 안의 리터럴**이지 구분자가 아니다(마크다운 명세).
                # 종전에는 raw.split("|") 이 이것까지 구분자로 소비해, 셀에 `\|` 가 하나 있으면
                # 그 행이 여러 셀로 쪼개지고 **표 전체의 열 수가 늘어났다**(issue #29).
                # 나머지 행에는 빈 셀이 붙고, 그 행의 `**볼드**` 도 리터럴로 남았다.
                # 「A | B | C」 형태의 서식·스키마·CSV 헤더를 인용하는 문서에서 자주 나온다.
                #
                # ⚠ 치환은 strip("|") 보다 **먼저** — 셀이 `\|` 로 끝나는 경우를 위해서다.
                raw = lines[i].strip().replace(r"\|", _PIPE_SENTINEL).strip("|")
                if not re.match(r"^[\s:|-]+$", raw):  # 구분행 스킵
                    # 복원은 `\|` 가 아니라 `|` 로 — Notion 셀은 plain text 라 이스케이프가 불필요하다.
                    rows.append([c.replace(_PIPE_SENTINEL, "|") for c in raw.split("|")])
                i += 1
            if rows:
                blocks.append(_table_block(rows))
            continue

        # 헤딩
        #   Notion 은 heading_1~3 만 있다. 종전 정규식이 `#{1,3}` 이라 **h4 이상이 헤딩으로
        #   인식조차 되지 않고** 아래 문단 분기로 떨어져, 게시본에 `#### 제목` 이 리터럴로
        #   남았다(문서 구조 소실).
        #     실측(2026-08-28): 제안서 본문 370파일 중 168파일 · md헤딩 1,406개 중 368개(26.2%)
        #   h4+ 는 heading_3 으로 접는다 — 계층은 잃지만 제목이라는 사실은 지킨다. 문단으로
        #   떨어뜨리는 것보다 손실이 작다. tests/test_structure_gate.sh 가 보존을 지킨다.
        m = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if m:
            lvl = min(len(m.group(1)), 3)
            blocks.append({"object": "block", "type": f"heading_{lvl}",
                           f"heading_{lvl}": {"rich_text": _rich_text(m.group(2))}})
            i += 1
            continue

        # 구분선
        if re.match(r"^---+$", stripped):
            blocks.append({"object": "block", "type": "divider", "divider": {}})
            i += 1
            continue

        # 인용
        if stripped.startswith(">"):
            blocks.append({"object": "block", "type": "quote",
                           "quote": {"rich_text": _rich_text(stripped[1:].strip())}})
            i += 1
            continue

        # 번호 리스트
        m = re.match(r"^\d+\.\s+(.*)$", stripped)
        if m:
            blocks.append({"object": "block", "type": "numbered_list_item",
                           "numbered_list_item": {"rich_text": _rich_text(m.group(1))}})
            i += 1
            continue

        # 불릿 리스트
        m = re.match(r"^[-*]\s+(.*)$", stripped)
        if m:
            blocks.append({"object": "block", "type": "bulleted_list_item",
                           "bulleted_list_item": {"rich_text": _rich_text(m.group(1))}})
            i += 1
            continue

        # 빈 줄 스킵
        if not stripped:
            i += 1
            continue

        # 일반 문단
        blocks.append(_para(stripped))
        i += 1
    return blocks


# Notion code 블록이 받는 언어 (자주 쓰는 것만; 그 외 plain text)
_NOTION_LANGS = {
    "bash", "shell", "python", "javascript", "typescript", "json", "sql",
    "yaml", "markdown", "mermaid", "diff", "docker", "go", "rust", "java",
}

# ── Notion API 한계 보정 ────────────────────────────────────
# 표 자식 100행 초과 → 400 (body.children[n].table.children.length should be ≤ 100)
# 요청 바디 과대 → "Request body too large"
# 2026-08-02 npe-watch 게시에서 실제 발생(WBS 266행·요구사항추적표 160행).
MAX_TABLE_ROWS = 100
MAX_TABLE_BYTES = 60_000


def clamp_tables(blocks):
    """표를 Notion 한계에 맞게 **분할**한다 (자르지 않는다).

    두 한계를 동시에 본다.
      · 표 자식 100행 초과 → 400
      · 블록 하나가 과대(수십~수백 KB) → "Request body too large"
        (ipanal 요구사항추적표: 단일 표 132KB)

    행수·바이트 둘 다 기준으로 조각내고, 2번째 조각부터는 헤더 행을 복제해
    각 조각이 단독으로 읽히게 한다. 조각 사이에 「(N/M 계속)」 문단을 넣어
    이어짐을 명시한다. **내용을 버리지 않는 것이 원칙.**
    """
    out = []
    for b in blocks:
        if b.get("type") != "table":
            out.append(b)
            continue
        rows = b["table"].get("children", [])
        has_hdr = bool(b["table"].get("has_column_header"))
        hdr = rows[0] if (has_hdr and rows) else None
        body = rows[1:] if hdr else rows
        # 조각 크기: 행수 100 이내 + 바이트 60KB 이내
        chunks, cur, cur_bytes = [], [], 0
        for r in body:
            rb = len(json.dumps(r, ensure_ascii=False))
            if cur and (len(cur) >= MAX_TABLE_ROWS - 1 or cur_bytes + rb > MAX_TABLE_BYTES):
                chunks.append(cur); cur, cur_bytes = [], 0
            cur.append(r); cur_bytes += rb
        if cur:
            chunks.append(cur)
        if not chunks:
            out.append(b); continue
        total = len(chunks)
        for i, ch in enumerate(chunks, 1):
            nb = json.loads(json.dumps(b, ensure_ascii=False))
            nb["table"]["children"] = ([hdr] + ch) if hdr else ch
            out.append(nb)
            if total > 1 and i < total:
                out.append(_para(f"— 표 계속 ({i}/{total}) —"))
    return out


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    md = open(sys.argv[1], encoding="utf-8").read()
    blocks = clamp_tables(md_to_blocks(md))
    # 구조 소실을 **말한다.** 이 저장소의 게시 결함(#9·#31)은 전부 "조용히 유실"이었다.
    # 게시를 막지는 않는다 — 헤딩 하나 때문에 문서 전체를 못 올리는 쪽이 더 나쁘다.
    from structure_gate import check_blocks
    for code, why in check_blocks(md, blocks):
        sys.stderr.buffer.write(
            ("⚠ 구조 소실 %s — %s\n" % (code, why)).encode("utf-8"))
    if "--chunk" in sys.argv:
        n = int(sys.argv[sys.argv.index("--chunk") + 1])
        out = [blocks[i:i + n] for i in range(0, len(blocks), n)]
    else:
        out = blocks
    # sys.stdout 으로 쓰면 로케일 인코딩(한국어 Windows=cp949)이 걸려 한글이 깨진다.
    # ensure_ascii=True 로 피하지 않는 이유: clamp_tables 의 조각 크기 산정(MAX_TABLE_BYTES)이
    # ensure_ascii=False 기준이라, 여기서 \uXXXX 로 부풀리면 Notion 요청이 한도를 넘을 수 있다.
    # 바이트를 직접 써서 크기는 그대로 두고 인코딩만 고정한다.
    sys.stdout.buffer.write(json.dumps(out, ensure_ascii=False).encode("utf-8"))


if __name__ == "__main__":
    main()
