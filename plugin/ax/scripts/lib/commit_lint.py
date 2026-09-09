#!/usr/bin/env python3
"""커밋 메시지 규약 검사기 — Conventional Commits v1.0.0 + git 72칸 규칙.

근거
----
- Conventional Commits v1.0.0 — https://www.conventionalcommits.org/ko/v1.0.0/
- git 관례 72칸 — `git log` 가 본문을 4칸 들여쓰므로 80칸 터미널 기준 76이 상한,
  관례로 72를 쓴다.

원칙: **코드가 「무엇」을 말하니 커밋은 「왜」를 말한다.**

한글은 표시 폭으로 잰다
----------------------
72는 문자 수가 아니라 **표시 폭**이다. 한글·CJK 는 한 자가 2칸이므로 72칸 ≈ 한글 36자다.
문자 수로 재면 한글 커밋은 전부 통과하면서 터미널에서는 접힌다.
  실측(2026-08-30, 최근 60커밋): 문자 수 기준 제목 위반 0건 → 표시 폭 기준 17건.

stdin 으로 메시지를 받아 위반을 stderr 에 출력한다. 위반이 있으면 종료코드 1.
`--title` 은 제목 한 줄만 검사한다(스쿼시 머지 = PR 제목이 커밋 제목이 된다).
"""
import re
import sys
import unicodedata

TYPES = ("feat", "fix", "docs", "style", "refactor", "perf",
         "test", "build", "ci", "chore", "revert")
# 본문 없이 「왜」를 생략해도 되는 유형 — 변경 자체가 자명한 것들.
BODY_REQUIRED = ("feat", "fix", "refactor", "perf")

SUBJECT_MAX = 72          # 상한 (git 관례)
SUBJECT_SOFT = 50         # 권장
BODY_MAX = 72
# GitHub 스쿼시 머지가 붙이는 ` (#123)` 을 감안한 PR 제목 상한
TITLE_MAX = 64

HEADER = re.compile(
    r"^(?P<type>[a-z]+)(?:\((?P<scope>[^()]+)\))?(?P<bang>!)?: (?P<desc>.+)$")
FOOTER = re.compile(r"^(BREAKING CHANGE: |[A-Za-z][A-Za-z-]*: |[A-Za-z][A-Za-z-]* #)")
# GitHub 이 스쿼시 시 덧붙이는 PR 번호 — 사람이 쓴 것이 아니므로 형식 검사에서 제외한다.
PR_SUFFIX = re.compile(r"\s*\(#\d+\)$")


def width(s):
    """터미널 표시 폭. CJK 전각은 2칸."""
    return sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in s)


def check_subject(subject, is_title=False):
    out = []
    core = PR_SUFFIX.sub("", subject)
    m = HEADER.match(core)
    if not m:
        out.append(("E", "제목이 `type(scope): 설명` 형식이 아니다: %r" % core[:60]))
        out.append(("i", "  허용 type: " + " · ".join(TYPES)))
        out.append(("i", "  릴리즈는 `release:` 가 아니라 `chore(release): v1.2.3 — 요약`"))
        return out, None
    t = m.group("type")
    if t not in TYPES:
        out.append(("E", "`%s` 는 허용되지 않는 type 이다" % t))
        out.append(("i", "  허용: " + " · ".join(TYPES)))
        if t == "release":
            out.append(("i", "  → `chore(release): ...` 로 쓴다"))
    desc = m.group("desc")
    if desc.endswith("."):
        out.append(("E", "제목은 마침표로 끝내지 않는다"))
    if desc[:1].isupper() and desc[:1].isascii():
        out.append(("W", "제목 설명은 소문자로 시작하는 것이 관례다"))
    w = width(subject)
    limit = TITLE_MAX if is_title else SUBJECT_MAX
    if w > limit:
        why = " (스쿼시 시 ` (#123)` 이 붙어 72칸을 넘는다)" if is_title else ""
        out.append(("E", "제목 표시 폭 %d칸 > %d칸%s" % (w, limit, why)))
        out.append(("i", "  한글은 한 자가 2칸이다 — %d칸 ≈ 한글 %d자" % (limit, limit // 2)))
    elif w > SUBJECT_SOFT and not is_title:
        out.append(("W", "제목 표시 폭 %d칸 — 권장 %d칸" % (w, SUBJECT_SOFT)))
    return out, t


def check_body(lines, ctype):
    out = []
    if not lines:
        if ctype in BODY_REQUIRED:
            out.append(("E", "`%s` 는 본문에 **왜** 를 적는다 — 코드가 「무엇」을 말한다" % ctype))
        return out
    if lines[0].strip():
        out.append(("E", "제목과 본문 사이에 빈 줄이 있어야 한다"))
    over = [(i, l) for i, l in enumerate(lines, 2) if width(l) > BODY_MAX]
    for i, l in over[:5]:
        out.append(("E", "%d행 표시 폭 %d칸 > %d칸: %s…" % (i, width(l), BODY_MAX, l[:34])))
    if len(over) > 5:
        out.append(("i", "  … 외 %d줄 더" % (len(over) - 5)))
    if over:
        out.append(("i", "  한글은 한 자가 2칸 — %d칸 ≈ 한글 %d자에서 줄을 바꾼다"
                    % (BODY_MAX, BODY_MAX // 2)))
    return out


def main(argv):
    is_title = "--title" in argv
    raw = sys.stdin.read()
    # 주석 줄(#)과 스크롤 안내는 git 이 붙인 것 — 검사 대상이 아니다.
    lines = [l for l in raw.split("\n") if not l.startswith("#")]
    while lines and not lines[-1].strip():
        lines.pop()
    if not lines or not lines[0].strip():
        sys.stderr.write("[commit-lint] ✗ 메시지가 비었다\n")
        return 1
    subject, body = lines[0], lines[1:]
    findings, ctype = check_subject(subject, is_title)
    if not is_title and ctype:
        findings += check_body(body, ctype)
    errs = [f for f in findings if f[0] == "E"]
    if not findings:
        return 0
    sys.stderr.write("[commit-lint] %s\n" % ("✗ 규약 위반" if errs else "⚠ 권고"))
    for lvl, msg in findings:
        mark = {"E": "  ✗", "W": "  ⚠", "i": "   "}[lvl]
        sys.stderr.write("%s %s\n" % (mark, msg))
    if errs:
        sys.stderr.write("   근거: Conventional Commits v1.0.0 · git 72칸 규칙\n")
        sys.stderr.write("   상세: COMMIT_CONVENTION.md (플러그인 루트)\n")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
