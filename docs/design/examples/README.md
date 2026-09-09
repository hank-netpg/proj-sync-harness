# 제안축 파이프라인 예제 (바이오 사업 dogfood)

P0 스캐폴드 실증용 샘플. `docquark.mjs`로 지식맵 생성 검증.

```bash
mkdir -p demo/proposal && cp bio_*.sample.json demo/proposal/  # requirements.json·toc.json 로 이름변경
cd demo && node <plugin>/scripts/docquark.mjs proposal knowledge
# → knowledge/{quark,_mirror,_axon,ai_context_guide.txt}
tree knowledge/_mirror/by_담당        # 담당사별 요구사항
ls knowledge/_axon/by_page/III-1-1    # 페이지가 덮는 요구사항 target-jump
cat knowledge/quark/req/SFR-001__*/quote.md   # 원문 근거(환각0)
```

실증 결과(2026-07-26): req 6 · page 5 · 정합경고 0 · `_mirror`(by_kind/담당/배점)·`_axon/by_page` 정상.
