#!/usr/bin/env python3
"""proj-sync: 산출물 문서버전·개정이력 점검 — 「제출물의 버전은 문서 안에 있어야 한다」

## 왜 필요한가

`manage-config` 는 **git 을 형상관리 엔진**으로 삼는다(commit=버전, tag=baseline).
그것은 **내부 형상관리**로는 맞다. 그런데 발주처에 내는 산출물은 **문서 자체에**
표지 Version·개정일자와 개정이력 표가 있어야 한다 — 방법론 서식이 그렇고 감리가 그걸 본다.

이 둘을 같은 것으로 보아 「git 이 있으니 됐다」로 넘어가면, 제출 직전에 버전이 v1 에
멈춰 있는 문서를 내게 된다. 2026-08-03 실측: `reference/drafts` md 138건 중
**114건(82%)이 버전 표기 전무**였고, 표기가 있는 24건도 형식이 3가지로 갈려 있었다.

## 표준 형식

    # 문서명

    > **문서버전** v1.0 · **개정일자** 2026-08-03 · **작성자** 홍길동

    …본문…

    ## 개정이력

    | 버전 | 일자 | 내용 | 작성자 |
    |---|---|---|---|
    | 1.0 | 2026-08-03 | 최초 작성 | 홍길동 |

- **상단 버전 라인**과 **개정이력 절** 중 최소 하나는 있어야 한다(둘 다 권장)
- 사무파일은 서식을 따른다 — xlsx 는 `개정이력` 시트, hwpx 는 개정이력 표

## 사용

    doc_version.py check [경로…]        # 기본 reference/drafts
    doc_version.py check --standard-only  # 별표2 표준 산출물만
    doc_version.py fix [경로…]          # 누락분에 버전 블록·개정이력 삽입
    doc_version.py fix --dry-run

종료코드: 0 정상 · 1 누락 있음 · 2 실행 오류
"""
import argparse, datetime, json, os, re, subprocess, sys, zipfile

# 상단 버전 라인 — 관행 3종을 모두 인정한다(기존 문서를 억지로 고치게 하지 않는다)
RX_VER = re.compile(
    r'\*\*(문서\s*)?버전\*\*'                # **문서버전** v1.0 / **버전**: v0.1
    r'|^\s*>?\s*\*\*v\d+\.\d+'               # > **v1.1 (2026-07-21)**
    r'|^\s*>?\s*(문서\s*)?버전\s*[:：]'       # > 문서버전: v1.0
    r'|^version:\s*\S+',                     # frontmatter
    re.M)
# 메타 블록 = H1 직후의 인용(>) 또는 굵은글씨 메타 라인들. 여기에 버전을 끼워 넣는다.
RX_META = re.compile(r'^\s*(>|\*\*[^*]+\*\*\s*[:：])')
RX_HIST = re.compile(r'^#{1,4}\s*.*(개정\s*이력|변경\s*이력|Revision\s*History)', re.M | re.I)
HEAD_N = 3000            # 상단 판정 범위
SKIP_DIRS = ("99_아카이브", "/reports/", "/_extracted/", "/slack-files/")
SKIP_NAMES = ("README.md",)


def _git(root, *a):
    try:
        return subprocess.run(["git", "-C", root, *a], capture_output=True,
                              text=True, timeout=20).stdout.strip()
    except Exception:
        return ""


def std_names(root):
    """별표2 표준 산출물 명칭 집합 — profile 에 맞는 것만."""
    here = os.path.dirname(os.path.abspath(__file__))
    mp = os.path.join(here, "..", "templates", "deliverables.json")
    cp = os.path.join(root, ".proj-sync", "config.json")
    try:
        m = json.load(open(mp, encoding="utf-8"))
        prof = (json.load(open(cp, encoding="utf-8")).get("wbs") or {}).get("profile")
        keys = m["profiles"].get(prof) or []
        if isinstance(keys, dict):
            keys = keys.get("deliverables", [])
        return {m["deliverables"][k]["name"] for k in keys
                if k in m["deliverables"] and m["deliverables"][k].get("name")}
    except Exception:
        return set()


def scan_md(path):
    """(has_version, has_history)"""
    try:
        s = open(path, encoding="utf-8").read()
    except Exception:
        return (False, False)
    return (bool(RX_VER.search(s[:HEAD_N])), bool(RX_HIST.search(s)))


def scan_office(path):
    """사무파일 — xlsx 는 개정이력 시트, hwpx 는 본문에 개정이력 표기."""
    try:
        if path.lower().endswith((".xlsx", ".xlsm")):
            with zipfile.ZipFile(path) as z:
                wb = z.read("xl/workbook.xml").decode("utf-8", "ignore")
            return (bool(re.search(r'name="[^"]*개정\s*이력[^"]*"', wb)),) * 2
        if path.lower().endswith(".hwpx"):
            with zipfile.ZipFile(path) as z:
                txt = "".join(z.read(n).decode("utf-8", "ignore")
                              for n in z.namelist() if n.startswith("Contents/section"))
            return (bool(re.search(r'개정\s*이력', txt)),) * 2
    except Exception:
        pass
    return (False, False)


def collect(root, paths, standard_only):
    names = std_names(root) if standard_only else None
    out = []
    for base in paths:
        b = os.path.join(root, base) if not os.path.isabs(base) else base
        if not os.path.isdir(b):
            continue
        for dp, _, fs in os.walk(b):
            for f in fs:
                p = os.path.join(dp, f)
                rel = os.path.relpath(p, root)
                # 오피스 잠금 임시파일(~$…)·숨김파일은 산출물이 아니다
                if f.startswith("~$") or f.startswith("."):
                    continue
                if f in SKIP_NAMES or any(s in "/" + rel for s in SKIP_DIRS):
                    continue
                if not f.lower().endswith((".md", ".xlsx", ".xlsm", ".hwpx")):
                    continue
                if names is not None and os.path.splitext(f)[0] not in names:
                    continue
                out.append((rel, p))
    return sorted(out)


def do_check(root, paths, standard_only):
    items = collect(root, paths, standard_only)
    bad = []
    for rel, p in items:
        hv, hh = scan_md(p) if p.lower().endswith(".md") else scan_office(p)
        if not (hv or hh):
            bad.append(rel)
    scope = "표준 산출물" if standard_only else "전체"
    print(f"[doc-version] {scope} {len(items)}건 중 버전 표기 누락 {len(bad)}건")
    for r in bad[:40]:
        print(f"  ✗ {r}")
    if len(bad) > 40:
        print(f"  … 외 {len(bad)-40}건")
    if bad:
        print("  → doc_version.py fix 로 버전 블록·개정이력을 삽입할 수 있습니다")
    return 1 if bad else 0


def do_fix(root, paths, standard_only, dry):
    items = [(r, p) for r, p in collect(root, paths, standard_only) if p.endswith(".md")]
    today = datetime.date.today().isoformat()
    n = 0
    for rel, p in items:
        hv, hh = scan_md(p)
        if hv or hh:
            continue
        try:
            s = open(p, encoding="utf-8").read()
        except Exception:
            continue
        # 최초 일자는 git 이력에서. **작성자는 채우지 않는다** —
        # git 사용자명은 계정명(예: hankeon)이라 산출물의 작성자 실명과 다르다.
        first = (_git(root, "log", "--reverse", "--format=%ad", "--date=short",
                      "--", rel).split("\n") or [""])[0] or today
        lines = s.split("\n")
        i = next((k for k, l in enumerate(lines) if l.startswith("# ")), -1)
        ver = f"**문서버전** v0.1 · **개정일자** {first}"

        # 기존 메타 블록이 있으면 그 **끝에 이어 붙인다**. 위에 새 줄을 얹으면
        # 「> 문서버전」과 「> 작성일」이 따로 놀아 메타가 두 덩이로 갈린다.
        j = i + 1 if i >= 0 else 0
        while j < len(lines) and lines[j].strip() == "":
            j += 1
        k = j
        while k < len(lines) and RX_META.match(lines[k]):
            k += 1
        if k > j:                                  # 메타 블록 존재 → 그 끝에 삽입
            quoted = lines[k - 1].lstrip().startswith(">")
            lines[k:k] = [("> " if quoted else "") + ver]
        elif i >= 0:                               # 메타 없음 → H1 아래 새 블록
            lines[i + 1:i + 1] = ["", "> " + ver]
        else:
            lines[0:0] = ["> " + ver, ""]

        body = "\n".join(lines).rstrip() + "\n"
        if not RX_HIST.search(body):
            body += ("\n## 개정이력\n\n| 버전 | 일자 | 내용 | 작성자 |\n|---|---|---|---|\n"
                     f"| 0.1 | {first} | 최초 작성 |  |\n")
        if dry:
            print(f"  [dry] {rel}")
        else:
            open(p, "w", encoding="utf-8").write(body)
            print(f"  ✓ {rel}")
        n += 1
    print(f"[doc-version] {'보정 예정' if dry else '보정'} {n}건"
          + ("  (사무파일은 서식상 수동 — 표지 Version·개정이력 시트 확인)" if n else ""))
    return 0


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("cmd", choices=["check", "fix"])
    ap.add_argument("paths", nargs="*", default=None)
    ap.add_argument("--standard-only", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--root", default=".")
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    paths = a.paths or ["reference/drafts", "deliverables"]
    if a.cmd == "check":
        sys.exit(do_check(root, paths, a.standard_only))
    sys.exit(do_fix(root, paths, a.standard_only, a.dry_run))


if __name__ == "__main__":
    main()
