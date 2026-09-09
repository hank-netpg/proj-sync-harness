#!/usr/bin/env python3
"""proj-sync: Notion 게시 대상 집합 — publish.globs 로 모으고 publish.exclude_globs 로 뺀다.

MCP 경로(notion_plan.sh plan)의 대상 집합 SSOT — (구 REST 경로도 v1.21.0 삭제 전까지 같은 집합을
쓰게 하려고 한 파일로 뺐다. 두 경로가 각자 glob 을 돌리면 언젠가 어긋나고, 어긋난 날의 게시는
한쪽에서만 「대상 아님」이 된다.

제외가 필요한 이유: reference/management/ 에는 살아있는 관리 문서(위험관리대장·WBS·서식규정)와
시점 기록(reports/ 의 주간·점검 리포트)이 함께 있다. 전자는 관리 대상, 후자는 아니다.
포함 glob 만으로는 이 둘을 가를 수 없다.

사용:  notion_targets.py <root> '<globs JSON>' '<exclude_globs JSON>'
출력:  절대경로 1줄 1건(정렬·중복 제거). 대상이 없으면 빈 출력.
       마지막 개행 필수 — 없으면 bash `while read` 가 마지막 항목을 버린다
       (2026-08-02 실측: 15개 프로젝트 전부에서 마지막 1건씩 총 13건 누락).
"""
import json
import pathlib
import sys


def list_targets(root, globs, excl):
    root = pathlib.Path(root)
    drop = set()
    for g in excl:
        drop |= {str(p) for p in root.glob(g) if p.is_file()}
    seen = []
    for g in globs:
        for p in sorted(root.glob(g)):
            s = str(p)
            if p.is_file() and s not in drop and s not in seen:
                seen.append(s)
    return seen


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) < 2:
        sys.stderr.write("사용: notion_targets.py <root> '<globs JSON>' ['<exclude_globs JSON>']\n")
        return 2
    root = argv[0]
    globs = json.loads(argv[1])
    excl = json.loads(argv[2]) if len(argv) > 2 and argv[2] else []
    seen = list_targets(root, globs, excl)
    sys.stdout.write("\n".join(seen) + ("\n" if seen else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
