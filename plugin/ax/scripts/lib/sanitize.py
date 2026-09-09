#!/usr/bin/env python3
"""proj-sync: 텍스트 위생(sanitize) — 눈에 안 보이면서 실제로 어긋나게 만드는 문자 제거.

출처
----
규칙과 설계는 im-not-ai 의 `scripts/sanitize_text.py` 에서 가져왔다(MIT).
    https://github.com/epoko77-ai/im-not-ai — Copyright (c) epoko77-ai, MIT License
NFD→NFC 정규화는 **가져오지 않았다** — proj-sync 에 이미 있다
(`slack_download.sh`·`gdrive_sync.sh`). 중복 구현은
서로 어긋날 때 어느 쪽이 맞는지 알 수 없게 만든다.

왜 필요한가
-----------
자료가 Slack·Notion·웹에서 **복사돼** 회의록 yml·전제 yml·초안 md 로 들어온다.
그 경로에서 다음이 딸려 온다:

  - 제로폭 문자(U+200B~U+200D)·BOM(U+FEFF)·소프트하이픈(U+00AD)
    눈에 보이지 않으면서 글자수를 부풀리고, 검색·정렬·중복제거를 어긋나게 한다.
    같은 문장인데 grep 이 못 찾고, 같은 제목인데 Notion 이 다른 페이지로 만든다.
  - 양방향 제어 문자(U+202A~U+202E·U+2066~U+2069)
    보이는 순서와 저장된 순서를 다르게 만든다. 사업명·금액이 뒤집혀 보일 수 있다.

이 파일은 **문자만 걷어낸다.** 맞춤법·문체·줄바꿈은 손대지 않는다 — 산출물의
내용을 바꾸는 처리는 이 계층의 일이 아니다.

사용:
    from sanitize import scrub, scan          # 라이브러리
    python3 sanitize.py <file> [--check]      # CLI (--check: 검출만, 종료코드 1)
"""
import sys

# 제거 대상 — 코드포인트: 왜 지우는지
_ZERO_WIDTH = {
    "​": "zero width space",
    "‌": "zero width non-joiner",
    "‍": "zero width joiner",
    "⁠": "word joiner",
    "﻿": "BOM / zero width no-break space",
    "­": "soft hyphen",
}
# 양방향 제어 — 보이는 순서를 바꾼다. 한국어 문서에 정당한 쓰임이 없다.
_BIDI = {
    "‪": "LRE", "‫": "RLE", "‬": "PDF",
    "‭": "LRO", "‮": "RLO",
    "⁦": "LRI", "⁧": "RLI", "⁨": "FSI", "⁩": "PDI",
}
_STRIP = dict(_ZERO_WIDTH)
_STRIP.update(_BIDI)

# ⚠ U+200D(ZWJ)는 이모지 결합(👨‍👩‍👦·🏳️‍🌈)에도 쓰인다. 산출물 문서에는 결합 이모지를
#   쓰지 않으므로 지우는 쪽이 맞지만, 지운 사실은 scan() 이 보고하므로 확인할 수 있다.

_TABLE = {ord(c): None for c in _STRIP}


def scrub(text):
    """제로폭·BOM·소프트하이픈·bidi 제어문자를 제거한 문자열을 돌려준다."""
    return text.translate(_TABLE)


def scan(text):
    """검출 결과를 [(문자이름, 코드포인트, 건수), …] 로. 깨끗하면 빈 리스트."""
    hits = []
    for ch, name in _STRIP.items():
        n = text.count(ch)
        if n:
            hits.append((name, "U+%04X" % ord(ch), n))
    return sorted(hits, key=lambda t: -t[2])


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    check = "--check" in argv
    if check:
        argv.remove("--check")
    if not argv:
        raise SystemExit(__doc__)
    path = argv[0]
    with open(path, encoding="utf-8") as f:
        text = f.read()
    hits = scan(text)
    if check:
        for name, cp, n in hits:
            # 경로가 사업명(한글)일 수 있다 — stderr 도 바이트로 고정한다.
            sys.stderr.buffer.write(
                ("  ↳ %s: %s(%s) %d건\n" % (path, name, cp, n)).encode("utf-8"))
        return 1 if hits else 0
    sys.stdout.buffer.write(scrub(text).encode("utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
