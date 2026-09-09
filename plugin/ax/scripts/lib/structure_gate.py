#!/usr/bin/env python3
"""proj-sync: 구조 보존 게이트 — md → Notion 블록 변환이 구조를 잃지 않았는가.

출처
----
설계(결정론 게이트 · 실패코드를 안정 API 로 두는 방식 · heading_lost / heading_absorbed
이름)는 im-not-ai 의 `scripts/checks.py` 에서 가져왔다(MIT).
    https://github.com/epoko77-ai/im-not-ai — Copyright (c) epoko77-ai, MIT License

**전부 옮기지 않았다.** 원본은 "윤문 전후 텍스트" 대조용이라 `하였_injection`·
`colloquial_erased` 같은 문체 축이 함께 있는데, 이쪽 경로는 문체를 건드리지 않으므로
해당 축은 영원히 0이다. 검사가 아무것도 잡지 못하면 통과가 통과라는 뜻을 잃는다.

축을 실측으로 골랐다 (2026-08-28, 산출물 401파일):

    축          근거                                    채택
    헤딩        md헤딩 1,514개. 수정 전 368개(24.3%) 소실   ✅
    표          표 행 1,795개                            ✅
    코드블록     79개 (mermaid 포함)                       ✅
    각주        **0개** — 산출물에 각주를 쓰지 않는다        ❌ 제외

각주 축은 쓰이기 시작하면 그때 넣는다. 지금 넣으면 상시 0인 검사가 하나 늘 뿐이다.

실패코드 (안정 API — 테스트가 이 이름을 참조한다):
    heading_lost      md 헤딩 수 > Notion heading 블록 수
    heading_absorbed  헤딩이 문단으로 흡수돼 `#` 가 본문에 리터럴로 남음
    table_lost        md 표 수 > table 블록 수
    code_lost         md 코드블록 수 > code 블록 수

사용:
    from structure_gate import check_blocks
    failures = check_blocks(md_text, blocks)   # 빈 리스트 = 통과

    python3 structure_gate.py <file.md>        # CLI. 위반 시 종료코드 1
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sanitize import scrub  # noqa: E402

_FENCE = re.compile(r"^\s*```")
_HEADING = re.compile(r"^#{1,6}\s+\S")
_TABLE_ROW = re.compile(r"^\s*\|")
_TABLE_SEP = re.compile(r"^\s*\|?[\s:|-]+\|?\s*$")


def _outside_fences(md):
    """코드블록 **밖의** 줄만. 안쪽의 `# 주석`·`| pipe` 는 구조가 아니다."""
    out, inside = [], False
    for ln in md.split("\n"):
        if _FENCE.match(ln):
            inside = not inside
            continue
        if not inside:
            out.append(ln)
    return out


def count_md(md):
    """원문의 구조 요소 수 → dict."""
    md = scrub(md)
    lines = _outside_fences(md)
    headings = sum(1 for ln in lines if _HEADING.match(ln.strip()))
    # 표 = 구분행(|---|)을 가진 블록의 개수. 행 수가 아니라 표의 개수를 센다.
    tables = 0
    for i in range(len(lines) - 1):
        if _TABLE_ROW.match(lines[i]) and _TABLE_SEP.match(lines[i + 1]) \
                and not _TABLE_SEP.match(lines[i]):
            if i == 0 or not _TABLE_ROW.match(lines[i - 1]):
                tables += 1
    codes = sum(1 for ln in md.split("\n") if _FENCE.match(ln)) // 2
    return {"heading": headings, "table": tables, "code": codes}


def count_blocks(blocks):
    """변환 결과의 구조 요소 수 → dict. 흡수된 헤딩 텍스트도 함께 돌려준다."""
    n = {"heading": 0, "table": 0, "code": 0}
    absorbed = []
    for b in blocks:
        t = b.get("type", "")
        if t.startswith("heading_"):
            n["heading"] += 1
        elif t == "table":
            n["table"] += 1
        elif t == "code":
            n["code"] += 1
        elif t == "paragraph":
            txt = "".join(r.get("text", {}).get("content", "")
                          for r in b.get("paragraph", {}).get("rich_text", []))
            if _HEADING.match(txt.strip()):
                absorbed.append(txt.strip()[:60])
    return n, absorbed


def check_blocks(md, blocks):
    """[(실패코드, 설명), …]. 빈 리스트면 통과."""
    want = count_md(md)
    got, absorbed = count_blocks(blocks)
    fails = []
    # 표 계속 안내(`— 표 계속 (i/n) —`)로 한 표가 여러 블록이 될 수 있다 — 초과는 정상.
    for key, code in (("heading", "heading_lost"),
                      ("table", "table_lost"),
                      ("code", "code_lost")):
        if got[key] < want[key]:
            fails.append((code, "원문 %d개 → 블록 %d개 (%d개 소실)"
                          % (want[key], got[key], want[key] - got[key])))
    for txt in absorbed:
        fails.append(("heading_absorbed", "문단에 헤딩이 리터럴로 남음: %r" % txt))
    return fails


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        raise SystemExit(__doc__)
    import md_to_notion
    rc = 0
    for path in argv:
        with open(path, encoding="utf-8") as f:
            md = f.read()
        fails = check_blocks(md, md_to_notion.md_to_blocks(md))
        for code, why in fails:
            sys.stderr.buffer.write(
                ("  ↳ %s: %s — %s\n" % (path, code, why)).encode("utf-8"))
            rc = 1
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
