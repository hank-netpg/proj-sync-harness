#!/usr/bin/env python3
"""proj-sync: Slack 근거 검증 게이트 — 「답글까지 봤는가」를 기계가 확인한다.

## 왜 필요한가

팀 규약에 「`reply_count > 0` 인 스레드는 반드시 `conversations.replies` 로 답글까지
확인한 뒤에만 '메시지 없음'·'미회신'을 결론 낼 것」이 있다. 그런데 이 규약은 사람·에이전트가
**기억해야만** 지켜졌고, 실제로 두 번 깨졌다.

- 2026-07-26 proj-alpha — top-level 만 보고 "인용이 실존하지 않는다"고 오판, 리포트에
  "근거 위조"로까지 증폭
- 2026-08-02 proj-beta — `--all-threads` 로 **수집은 했으나 출력에서 본문만 보고**
  「담당자 무응답·결론 없음」이라고 보고. 실제로는 답글에 결론이 다 있었다
  (상용 재무DB → 오픈데이터 변경 확정 / 발주처 미통보 확인 / WBS 전달)

수집했는지가 아니라 **판단에 반영했는지**가 문제였다. 그래서 결론을 내기 전에 통과해야 하는
게이트를 둔다.

## 무엇을 막는가

1. **답글 미수집 상태의 결론** — reply_count>0 인데 threads 가 없으면 EXIT 2
2. **본문만 본 최종활동일** — 답글이 더 최근이면 그 값을 쓰도록 강제
3. **조용한 수집 실패** — count=0 인데 채널에 이력이 있으면 경고
4. **미회신 단정** — 마지막 발화가 우리 쪽이면 "미회신", 상대면 "회신 있음"을 기계가 판정

## 사용

  slack_inbox.sh poll --dry-run --all-threads --oldest 0 > /tmp/ch.json
  slack_evidence.py /tmp/ch.json                 # 검증 + 병합 타임라인 요약
  slack_evidence.py /tmp/ch.json --timeline 20   # 최근 20건 (본문·답글 통합 시계열)
  slack_evidence.py /tmp/ch.json --json          # 기계 판독용

종료코드: 0 통과 · 2 게이트 위반(결론 금지) · 1 입력 오류
"""
import json, sys, datetime

KST = datetime.timezone(datetime.timedelta(hours=9))


def ts(t):
    return datetime.datetime.fromtimestamp(float(t), KST).strftime("%Y-%m-%d %H:%M")


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def merge(d):
    """본문 + 답글을 하나의 시계열로. 이 함수를 거치지 않은 판단은 규약 위반이다."""
    items = []
    for m in d.get("messages", []):
        items.append({"ts": m["ts"], "user": m.get("user", ""),
                      "text": m.get("text", "") or "", "kind": "본문",
                      "reply_count": m.get("reply_count", 0)})
    for parent, replies in (d.get("threads") or {}).items():
        for r in replies:
            if r.get("ts") == parent:
                continue
            items.append({"ts": r["ts"], "user": r.get("user", ""),
                          "text": r.get("text", "") or "", "kind": "답글",
                          "reply_count": 0})
    items.sort(key=lambda x: float(x["ts"]))
    return items


def gate(d, items):
    """통과해야 결론을 낼 수 있다. (violations, warnings)"""
    v, w = [], []
    th = d.get("threads") or {}
    need = [m for m in d.get("messages", []) if m.get("reply_count", 0) > 0]
    missing = [m for m in need if m["ts"] not in th]
    if missing:
        v.append(f"답글 미수집 {len(missing)}건 (reply_count>0 인데 threads 에 없음) "
                 f"— `--all-threads` 로 재수집 전까지 '메시지 없음·미회신' 결론 금지")
    if not d.get("messages") and not th:
        w.append("수집 결과 0건 — 커서·oldest 설정이나 429 무경고 실패를 의심할 것 "
                 "(`--oldest 0` 으로 전기간 재확인)")
    tops = [m for m in d.get("messages", [])]
    reps = [i for i in items if i["kind"] == "답글"]
    if tops and reps:
        lt = max(float(m["ts"]) for m in tops)
        lr = max(float(r["ts"]) for r in reps)
        if lr > lt:
            w.append(f"최종 활동이 **답글**이다 ({ts(lr)} > 본문 {ts(lt)}) "
                     f"— 본문 기준으로 '정지'라고 쓰면 틀린다")
    return v, w


def summarize(d, items):
    tops = [i for i in items if i["kind"] == "본문"]
    reps = [i for i in items if i["kind"] == "답글"]
    out = {
        "channel": d.get("channel"),
        "top_level": len(tops), "replies": len(reps), "total": len(items),
        "first": ts(items[0]["ts"]) if items else None,
        "last": ts(items[-1]["ts"]) if items else None,
        "last_kind": items[-1]["kind"] if items else None,
        "last_user": items[-1]["user"] if items else None,
    }
    if items:
        days = (datetime.datetime.now(KST)
                - datetime.datetime.fromtimestamp(float(items[-1]["ts"]), KST)).days
        out["idle_days"] = days
    return out


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    path = sys.argv[1]
    try:
        d = load(path)
    except Exception as e:
        print(f"[evidence] 입력 오류: {e}", file=sys.stderr)
        raise SystemExit(1)

    items = merge(d)
    v, w = gate(d, items)
    s = summarize(d, items)

    if "--json" in sys.argv:
        json.dump({"summary": s, "violations": v, "warnings": w},
                  sys.stdout, ensure_ascii=False, indent=1)
        print()
        raise SystemExit(2 if v else 0)

    print(f"[evidence] {s['channel']} — 본문 {s['top_level']} · 답글 {s['replies']} "
          f"· 합계 {s['total']}")
    if s["last"]:
        print(f"  최초 {s['first']} · **최종 {s['last']} ({s['last_kind']})** "
              f"· 정지 {s.get('idle_days')}일")
    for x in v:
        print(f"  ✗ {x}")
    for x in w:
        print(f"  ⚠ {x}")
    if not v:
        print("  ✅ 게이트 통과 — 본문·답글을 합친 근거로 결론 가능")

    if "--timeline" in sys.argv:
        n = int(sys.argv[sys.argv.index("--timeline") + 1])
        print(f"\n최근 {n}건 (본문·답글 통합 시계열):")
        for i in items[-n:]:
            mark = "  " if i["kind"] == "본문" else "  ↳"
            print(f"{mark}[{ts(i['ts'])}] ({i['kind']}) {i['user']}: "
                  f"{' '.join(i['text'].split())[:110]}")

    raise SystemExit(2 if v else 0)


if __name__ == "__main__":
    main()
