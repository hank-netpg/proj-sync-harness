#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""회의록 빌더 — revision/회의록/*.yml(SSOT) → .md(리뷰) + .hwpx(납품).

작업 ⊥ 납품: 리뷰 md 는 revision/회의록/, 납품 hwpx 는 deliverables/회의록/(Archive)
로 경로 분리 출력한다(WBS/RTM 이 md→revision·xlsx→deliverables 로 가르는 것과 동형).

회의록은 날짜별 시리즈 — 회의마다 {주제}_회의록_{YYYYMMDD}.yml 을 revision/회의록/ 에 두면
각 건이 같은 stem 으로 파생 생성된다(단일 canonical 인 WBS/RTM 과 다른 점).

엔진은 minutes_to_hwpx.py. 양식 스켈레톤은 reference/form/회의록-양식.hwpx(init 스캐폴드).
의존성 lxml·PyYAML — revision 도구 중 stdlib 를 벗어나는 예외.

경로: env PS_ROOT(프로젝트 루트) 사용. 단독 실행 시 CWD 상위에서 .proj-sync/config.json 탐색.
사용:
  python3 build_minutes.py            # revision/회의록/*.yml 전부 빌드
  python3 build_minutes.py <a.yml>    # 특정 yml 한 건만
"""
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)                    # 같은 scripts/ 의 엔진 import
import minutes_to_hwpx as engine            # noqa: E402  (import 시 lxml·PyYAML 확인)


def _find_root():
    r = os.environ.get("PS_ROOT")
    if r and os.path.isfile(os.path.join(r, ".proj-sync", "config.json")):
        return r
    d = os.getcwd()
    while True:
        if os.path.isfile(os.path.join(d, ".proj-sync", "config.json")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    sys.exit("[build_minutes] .proj-sync/config.json 를 찾지 못함 (PS_ROOT 미설정)")


def build_one(root, yml):
    """yml 한 건 → revision/회의록/{stem}.md + deliverables/회의록/{stem}.hwpx. 엔진 반환코드 전달."""
    stem = os.path.splitext(os.path.basename(yml))[0]
    md = os.path.join(root, "revision", "회의록", stem + ".md")        # 리뷰  → revision/
    hwpx = os.path.join(root, "deliverables", "회의록", stem + ".hwpx")  # 납품  → deliverables/
    skel = os.path.join(root, "reference", "form", "회의록-양식.hwpx")
    return engine.main([yml, "--md", md, "--hwpx", hwpx, "--skeleton", skel]) or 0


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    root = _find_root()
    src_dir = os.path.join(root, "revision", "회의록")
    deliv_dir = os.path.join(root, "deliverables", "회의록")
    skel = os.path.join(root, "reference", "form", "회의록-양식.hwpx")
    os.makedirs(src_dir, exist_ok=True)
    os.makedirs(deliv_dir, exist_ok=True)
    if not os.path.exists(skel):
        sys.exit("스켈레톤 없음: reference/form/회의록-양식.hwpx (init 스캐폴드/`/ax:doctor` 확인)")
    ymls = argv if argv else sorted(glob.glob(os.path.join(src_dir, "*.yml")))
    if not ymls:
        sys.exit("빌드할 yml 없음: revision/회의록/*.yml (회의별 yml 을 먼저 두세요)")
    worst = 0
    for y in ymls:
        worst = max(worst, build_one(root, y))
    print(f"[회의록] {len(ymls)}건 빌드 → revision/회의록/*.md(리뷰) + deliverables/회의록/*.hwpx(납품)")
    return worst


if __name__ == "__main__":
    raise SystemExit(main())
