#!/usr/bin/env python3
"""proj-sync: Notion MCP 게시 계획기 — 토큰 없음 · 네트워크 없음 · **판정만** 한다.

왜 있나
-------
기본 경로(claude_ai_mcp)에서는 로그인한 사용자의 claude.ai Notion 커넥터(MCP)가 게시한다.
그런데 이 저장소의 Notion 결함은 전부 **판정 로직**에서 났다:
  · NFD/NFC 가 갈려 현행 문서를 고아로 오판(#21·#22)
  · 제목만으로 찾아 타 사업·타 파일 페이지를 덮어씀(2026-08-02)
  · 스윕이 과반을 아카이브(#31)
  · 루트가 자기 자신을 상위로 실어 PATCH 전체 거절(#53)
  · 사업 기본값이 문서 단위 유형/상태를 덮음(#52)
이 규칙을 스킬 산문으로 옮기면 에이전트가 매번 재구성하고 회귀 테스트가 불가능하다.
그래서 규칙은 여기 두고, 에이전트는 계획 JSON 의 action 을 그대로 MCP 호출로 옮긴다.
REST 경로(notion_publish.sh)와 **같은 판정**을 낸다 — 두 경로가 어긋나면 안 된다.

사용
----
  notion_plan.py plan   --root R --config C [--index idx.json] [--stage-dir D] [--force-sweep]
  notion_plan.py verify --root R --config C <key> <fetched.md> [--plan plan.json]

`plan` 은 계획 JSON 을 파일로 쓰고(stdout 에는 경로와 요약만) 종료코드 0 · globs 미설정 3.
`--index` 는 에이전트가 `lookup_sql` 을 notion-query-data-sources 로 실행해 저장한 결과다
(도구 응답 그대로 `{"results":[...]}` 또는 행 배열). 주면 action(create/update)·고아까지 채운다.

계획 JSON 의 action
-------------------
  create : properties 전체(문서명·프로젝트·유형·상태·출처경로·상위 항목). 루트 문서 자신이면 상위 항목 없음.
  update : page_id + properties = 문서명·프로젝트·출처경로 (+ 유형/상태는 기존 값이 **비어 있을 때만**,
           상위 항목은 기존 값이 비어 있고 page≠root 일 때만). 기존 유형/상태는 보존한다(#52).
  본문은 두 경우 모두 body_path 의 파일 **전체**를 content 로 넣는다(요약 금지).
"""
import argparse
import json
import os
import re
import sys
import tempfile
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from sanitize import scrub            # noqa: E402
from structure_gate import count_md   # noqa: E402
from notion_targets import list_targets  # noqa: E402

ARCHIVED = "아카이브"
_HEX32 = re.compile(r"([0-9a-f]{32})")
_H4 = re.compile(r"^(#{4,})(\s+)")


def nfc(s):
    return unicodedata.normalize("NFC", s or "")


def page_id_of(v):
    """URL·대시 있는 id·32hex 어느 형태든 32hex 로."""
    if not v:
        return ""
    v = str(v).replace("-", "")
    m = list(_HEX32.finditer(v))
    return m[-1].group(1) if m else ""


def cfg_get(cfg, path, default=None):
    cur = cfg
    for k in path.split("."):
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return default if cur in (None, "", "null") else cur


def sql_quote(s):
    return "'" + str(s).replace("'", "''") + "'"


def fold_h4(md):
    """h4+ → ### . Notion 은 heading_1~3 만 있다 — 계층은 잃지만 제목이라는 사실은 지킨다(md_to_notion 과 동일)."""
    out, inside = [], False
    for ln in md.split("\n"):
        if ln.strip().startswith("```"):
            inside = not inside
        if not inside and _H4.match(ln):
            ln = _H4.sub("###\\2", ln, count=1)
        out.append(ln)
    return "\n".join(out)


def doc_title(text, path):
    for ln in text.split("\n"):
        if ln.startswith("# "):
            return ln[2:].strip()
    return os.path.splitext(os.path.basename(path))[0]


def path_rules(rel, base_type, base_status):
    """경로가 유형·상태를 정한다 — notion_publish.sh 의 case 문과 동일."""
    typ, st = base_type, base_status
    parts = rel.split("/")
    if "99_아카이브" in parts[:-1]:
        st = ARCHIVED
    if rel.startswith("reference/management/"):
        typ, st = "현황", "현행화문서"
    return typ, st


# ── 인덱스(문서함 SQL 결과) ────────────────────────────────────────────
def load_index(path, P):
    raw = json.load(open(path, encoding="utf-8"))
    rows = raw.get("results", raw) if isinstance(raw, dict) else raw
    if not isinstance(rows, list):
        raise ValueError("인덱스는 {'results':[...]} 또는 행 배열이어야 합니다")
    out, seen = [], set()
    for r in rows:
        if not isinstance(r, dict):
            continue
        pid = page_id_of(r.get("url") or r.get("id"))
        if not pid or pid in seen:      # 커서 중복 등으로 같은 페이지가 두 번 오면 한 번만 센다(#31 분모)
            continue
        seen.add(pid)
        parent_raw = r.get(P["parent"]) or ""
        try:
            pj = json.loads(parent_raw) if isinstance(parent_raw, str) and parent_raw.startswith(("[", "\"")) else parent_raw
        except Exception:
            pj = parent_raw
        if isinstance(pj, list):
            pj = pj[0] if pj else ""
        out.append({
            "id": pid,
            "url": r.get("url") or "",
            "title": nfc(r.get(P["title"]) or ""),
            "src": nfc(r.get(P["source"]) or ""),
            "status": r.get(P["status"]) or "",
            "type": r.get(P["type"]) or "",
            "parent": page_id_of(pj),
        })
    return out


def match_page(doc, index, root_id):
    """1순위 출처경로 완전일치 → 2순위 제목 일치이되 그 페이지 출처경로가 비어 있을 때만."""
    for r in index:
        if r["src"] and r["src"] == doc["src"]:
            return r
    for r in index:
        if r["title"] == nfc(doc["title"]) and not r["src"]:
            return r
    return None


# ── plan ───────────────────────────────────────────────────────────────
def cmd_plan(a):
    cfg = json.load(open(a.config, encoding="utf-8"))
    root = os.path.abspath(a.root)
    ds = cfg_get(cfg, "notion.data_source_id", "")
    if not ds:
        sys.stderr.write("[notion-plan] config.notion.data_source_id 미설정\n")
        return 2
    globs = cfg_get(cfg, "notion.publish.globs")
    if not globs:
        sys.stderr.write("[notion-plan] config.notion.publish.globs 미설정 — 게시 대상이 정의되지 않았습니다.\n"
                         "  예:  \"publish\": { \"globs\": [\"reference/drafts/**/*.md\"] }\n")
        return 3
    excl = cfg_get(cfg, "notion.publish.exclude_globs", []) or []
    P = {
        "title": cfg_get(cfg, "notion.properties.title", "문서명"),
        "type": cfg_get(cfg, "notion.properties.type", "유형"),
        "status": cfg_get(cfg, "notion.properties.status", "상태"),
        "project": cfg_get(cfg, "notion.properties.project", "프로젝트"),
        "parent": cfg_get(cfg, "notion.properties.parent", "상위 항목"),
        "source": cfg_get(cfg, "notion.properties.source", "출처경로"),
    }
    tag = cfg_get(cfg, "notion.project_tag", "")
    base_type = cfg_get(cfg, "notion.publish.type", "기술문서")
    base_status = cfg_get(cfg, "notion.publish.status", "작성중")
    # 문서명 고정(선택) — {"<repo 상대경로>": "<문서명>"}. 기본은 H1(없으면 파일명).
    #   문서함에 큐레이션된 제목([도구]ax — …)이 있는 문서를 H1 로 덮어쓰지 않기 위한 것.
    #   REST 경로의 `publish <file> [제목]` 인자에 해당한다.
    titles = cfg_get(cfg, "notion.publish.titles", {}) or {}
    titles = {nfc(k): v for k, v in titles.items()} if isinstance(titles, dict) else {}
    project_id = cfg_get(cfg, "project.id") or os.path.basename(root)
    root_title = cfg_get(cfg, "project.root_page_title", "")
    root_id = page_id_of(cfg_get(cfg, "notion.root_page_id", ""))
    coll = "collection://" + ds if not str(ds).startswith("collection://") else ds

    stage = a.stage_dir or os.path.join(tempfile.gettempdir(), "proj-sync-notion-%s" % re.sub(r"[^\w.-]", "_", project_id))
    os.makedirs(stage, exist_ok=True)

    cols = ", ".join('"%s"' % c for c in ("url", P["title"], P["status"], P["type"], P["source"], P["parent"]))
    where = ('"%s" LIKE %s' % (P["project"], sql_quote('%"' + tag + '"%'))) if tag else "1=1"
    lookup_sql = 'SELECT %s FROM "%s" WHERE %s' % (cols, coll, where)

    docs, keep = [], []
    for i, f in enumerate(list_targets(root, globs, excl), 1):
        rel = os.path.relpath(f, root)
        try:
            raw = open(f, encoding="utf-8").read()
        except Exception as e:
            docs.append({"key": rel, "error": "읽기 실패: %s" % e, "action": "skip"})
            continue
        body = fold_h4(scrub(raw))
        title = titles.get(nfc(rel)) or doc_title(body, f)
        src = nfc("%s/%s" % (project_id, rel))
        typ, st = path_rules(rel, base_type, base_status)
        bp = os.path.join(stage, "%04d.md" % i)
        with open(bp, "w", encoding="utf-8") as fh:
            fh.write(body)
        is_root = bool(root_title) and title == root_title
        docs.append({
            "key": rel, "title": title, "src": src, "type": typ, "status": st,
            "is_root_doc": is_root,
            "body_path": bp, "body_bytes": len(body.encode("utf-8")),
            "expect": count_md(body),
            "action": None,
        })
        keep.append(src)

    plan = {
        "version": 1, "data_source_id": ds, "collection_url": coll,
        "project_id": project_id, "project_tag": tag, "props": P,
        "root": {"id": root_id or None, "title": root_title},
        "lookup_sql": lookup_sql,
        "stage_dir": stage, "docs": docs, "keep_srcs": keep,
        "orphans": [], "abort": None, "index_loaded": False,
    }

    if a.index:
        index = load_index(a.index, P)
        plan["index_loaded"] = True
        plan["index_rows"] = len(index)
        # 루트 해석 — config 에 없으면 인덱스에서 제목으로 찾는다(REST 의 ps_notion_resolve_root 와 동일).
        if not root_id and root_title:
            for r in index:
                if r["title"] == nfc(root_title):
                    root_id = r["id"]
                    plan["root"]["id"] = root_id
                    plan["root"]["resolved_from"] = "index"
                    break
        for d in docs:
            if d.get("action") == "skip":
                continue
            row = match_page(d, index, root_id)
            props = {P["title"]: d["title"], P["source"]: d["src"]}
            if tag:
                props[P["project"]] = [tag]
            if row is None:
                props[P["type"]] = d["type"]
                props[P["status"]] = d["status"]
                if root_id and not d["is_root_doc"]:
                    props[P["parent"]] = [root_id]
                d["action"] = "create"
            else:
                d["action"] = "update"
                d["page_id"] = row["id"]
                d["page_url"] = row["url"]
                d["matched_by"] = "source" if row["src"] else "title"
                # 문서 단위 판단 보존(#52): 기존 값이 있으면 넣지 않는다 → 그대로 남는다.
                if not row["type"]:
                    props[P["type"]] = d["type"]
                if not row["status"]:
                    props[P["status"]] = d["status"]
                # 계층 보존 + 자기-상위 금지(#53): 상위가 비어 있고 루트 자신이 아닐 때만.
                if root_id and not row["parent"] and row["id"] != root_id:
                    props[P["parent"]] = [root_id]
            d["properties"] = props

        # 고아 — 출처경로 있는 페이지만(가드 ①), keep 에 없고 아직 아카이브가 아닌 것.
        #   추가 가드(REST 보다 엄격): 출처경로 접두가 **이 사업의 project.id** 인 페이지만 후보다.
        #   태그가 같아도 남의 사업 파일에서 온 페이지를 우리가 아카이브하면 안 된다 — 이 계획기는
        #   에이전트가 실행하므로 조회 범위가 SQL 한 줄에 좌우되고, 그 한 줄이 느슨해질 때의 보험이다.
        keep_set = set(keep)
        prefix = project_id + "/"
        seen = [r for r in index if r["src"]]
        cand = [r for r in seen
                if r["src"].startswith(prefix) and r["src"] not in keep_set and r["status"] != ARCHIVED]
        plan["orphans"] = [{"page_id": r["id"], "page_url": r["url"], "title": r["title"], "src": r["src"]} for r in cand]
        plan["sweep_seen"] = len(seen)
        if not tag:
            plan["abort"] = {"code": "no_tag", "detail": "project_tag 미설정 — 전 사업 범위를 훑을 수 없어 스윕 생략"}
        elif not keep:
            plan["abort"] = {"code": "keep_empty", "detail": "게시 대상 0건 — 남은 게시본 전건이 고아가 되므로 스윕 중단"}
        elif len(cand) * 2 > len(seen) and not a.force_sweep:
            plan["abort"] = {"code": "majority",
                             "detail": "고아 %d/%d 건으로 과반 — 판정 규칙 오류로 봄. 의도한 축소면 --force-sweep" % (len(cand), len(seen))}

    out = a.out or os.path.join(stage, "plan.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(plan, fh, ensure_ascii=False, indent=1)
    n_c = sum(1 for d in docs if d.get("action") == "create")
    n_u = sum(1 for d in docs if d.get("action") == "update")
    n_s = sum(1 for d in docs if d.get("action") == "skip")
    print("[notion-plan] 계획: %s" % out)
    print("[notion-plan] 대상 %d건 · 신규 %d · 갱신 %d · 건너뜀 %d · 고아 후보 %d · 루트 %s" % (
        len(docs), n_c, n_u, n_s, len(plan["orphans"]), plan["root"]["id"] or "(미해석 — 평면 게시)"))
    if plan["abort"]:
        print("[notion-plan] ⚠ 스윕 중단: %s" % plan["abort"]["detail"])
    if not a.index:
        print("[notion-plan] 다음: lookup_sql 을 notion-query-data-sources 로 실행해 저장 → plan --index <파일>")
    return 0


# ── verify ─────────────────────────────────────────────────────────────
def cmd_verify(a):
    plan_path = a.plan
    if not plan_path:
        cfg = json.load(open(a.config, encoding="utf-8"))
        project_id = cfg_get(cfg, "project.id") or os.path.basename(os.path.abspath(a.root))
        plan_path = os.path.join(tempfile.gettempdir(), "proj-sync-notion-%s" % re.sub(r"[^\w.-]", "_", project_id), "plan.json")
    plan = json.load(open(plan_path, encoding="utf-8"))
    doc = next((d for d in plan["docs"] if d.get("key") == a.key), None)
    if doc is None:
        sys.stderr.write("[notion-plan] 계획에 없는 key: %s\n" % a.key)
        return 2
    got = count_md(open(a.fetched, encoding="utf-8").read())
    want = doc["expect"]
    fails = []
    for k, code in (("heading", "heading_lost"), ("table", "table_lost"), ("code", "code_lost")):
        if got.get(k, 0) < want.get(k, 0):
            fails.append("%s: 원문 %d → 게시본 %d (%d 소실)" % (code, want[k], got[k], want[k] - got[k]))
    if fails:
        print("✗ %s — %s" % (a.key, " · ".join(fails)))
        return 1
    print("✓ %s — H%d/T%d/C%d" % (a.key, want["heading"], want["table"], want["code"]))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog="notion_plan.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan")
    p.add_argument("--root", required=True); p.add_argument("--config", required=True)
    p.add_argument("--index"); p.add_argument("--stage-dir"); p.add_argument("--out")
    p.add_argument("--force-sweep", action="store_true", default=os.environ.get("NP_SWEEP_FORCE") == "1")
    v = sub.add_parser("verify")
    v.add_argument("--root", required=True); v.add_argument("--config", required=True)
    v.add_argument("key"); v.add_argument("fetched"); v.add_argument("--plan")
    a = ap.parse_args(argv)
    return cmd_plan(a) if a.cmd == "plan" else cmd_verify(a)


if __name__ == "__main__":
    sys.exit(main())
