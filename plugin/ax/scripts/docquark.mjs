#!/usr/bin/env node
/**
 * docquark — 문서(requirements.json·toc.json) → quarkify 동형 폴더 지식맵.
 * quarkify(코드 파서)의 문서 버전. RAG 대체: 에이전트가 ls/tree/cat 로 근거 target-jump.
 * 산출: knowledge/{quark,_mirror,_axon,ai_context_guide.txt}  ·  정합경고: knowledge/_UNMAPPED.md
 * 사용: node docquark.mjs [proposalDir=proposal] [outDir=knowledge]
 * 의존: Node.js v18+ (stdlib fs만).
 *
 * 간선은 **양방향**이다:
 *   page → req :  quark/toc/…/<page>/_axon/req__<ID>
 *   req  → page:  quark/req/<ID>__…/_axon/toc__<page_id>
 * 한쪽만 있으면 "요구사항 X 를 덮는 페이지가 어디인가" 에 답하려고 전체 페이지를 훑어야 한다.
 * SPEC §지식맵은 처음부터 양방향으로 적혀 있었으나 구현이 page→req 만 만들고 있었다.
 *
 * 링크 모드 (symlink | file):
 *   심볼릭 링크는 POSIX 전용이다. 윈도우는 개발자 모드/관리자 권한이 없으면 만들지 못한다.
 *   이 저장소는 윈도우 설치 스크립트를 함께 배포하므로(A6 환경 동질성), 심링크를 못 만드는
 *   환경에서는 **대상 상대경로를 담은 `<이름>.link` 일반 파일**로 떨어뜨린다.
 *   모드는 시작 시 1회 프로브해 전체에 일관 적용한다 — 섞이면 순회 규칙이 둘이 된다.
 *   판정 결과는 knowledge/_LINKMODE 에 남긴다(doctor 가 읽는다).
 */
import { promises as fs } from 'node:fs';
import path from 'node:path';

const PROP = process.argv[2] || 'proposal';
const OUT  = process.argv[3] || 'knowledge';

const slug = (s = '') =>
  String(s).trim().replace(/[\/\s:·,()]+/g, '_').replace(/[^\w가-힣_-]/g, '').slice(0, 40) || 'x';

const readJson = async (p) => JSON.parse(await fs.readFile(p, 'utf8'));
const mkdir = (p) => fs.mkdir(p, { recursive: true });
const write = (p, s) => fs.writeFile(p, s, 'utf8');

let LINKMODE = 'symlink';

/** 심링크 생성 가능 여부를 1회 프로브한다. 실패하면 파일 모드로 내려간다. */
async function probeLinkMode(root) {
  const d = path.join(root, '.linkprobe');
  try {
    await mkdir(d);
    await write(path.join(d, 'target'), 'x');
    await fs.symlink('target', path.join(d, 'link'));
    return 'symlink';
  } catch {
    return 'file';
  } finally {
    try { await fs.rm(d, { recursive: true, force: true }); } catch {}
  }
}

/** 간선 1개. symlink 모드면 심링크, file 모드면 상대경로를 담은 <이름>.link 파일. */
async function link(target, linkPath) {
  await mkdir(path.dirname(linkPath));
  const rel = path.relative(path.dirname(linkPath), target);
  if (LINKMODE === 'symlink') {
    try { await fs.unlink(linkPath); } catch {}
    try { await fs.symlink(rel, linkPath); return; } catch (e) { if (e.code !== 'EEXIST') throw e; return; }
  }
  await write(`${linkPath}.link`, `${rel}\n`);
}

async function main() {
  const req = await readJson(path.join(PROP, 'requirements.json'));
  let toc = { chapters: [] };
  try { toc = await readJson(path.join(PROP, 'toc.json')); } catch {}

  await fs.rm(OUT, { recursive: true, force: true });
  await mkdir(OUT);
  LINKMODE = await probeLinkMode(OUT);

  const Q = path.join(OUT, 'quark'), M = path.join(OUT, '_mirror'), A = path.join(OUT, '_axon');

  // req_id → dir 경로(quark)
  const reqDir = {};
  for (const it of req.items || []) {
    const d = path.join(Q, 'req', `${it.id}__${slug(it.summary)}`);
    reqDir[it.id] = d;
    await mkdir(d);
    await write(path.join(d, 'summary.md'), it.summary || '');
    if (it.quote) await write(path.join(d, 'quote.md'), it.quote);
    if (it.detail?.length) await write(path.join(d, 'detail.md'), it.detail.map(x => `- ${x}`).join('\n'));
    if (it.category) await mkdir(path.join(d, `kind__${slug(it.category)}`));
    if (it.담당)     await mkdir(path.join(d, `담당__${slug(it.담당)}`));
    if (it.성격)     await mkdir(path.join(d, `성격__${slug(it.성격)}`));
    // _mirror (역인덱스)
    if (it.category) await link(d, path.join(M, 'by_kind', slug(it.category), it.id));
    if (it.담당)     await link(d, path.join(M, 'by_담당', slug(it.담당), it.id));
    if (it.배점)     await link(d, path.join(M, 'by_배점', slug(it.배점), it.id));
  }

  // toc leaf(page) + _axon(page↔req)
  const unmapped = [];
  const reqTocFromToc = {};   // req_id → [{page_id, dir}]
  for (const ch of toc.chapters || []) for (const se of ch.sections || []) for (const pg of se.pages || []) {
    const d = path.join(Q, 'toc', `${ch.id}__${slug(ch.title)}`, `${se.id}__${slug(se.title)}`, `${pg.page_id}__${slug(pg.title)}`);
    await mkdir(d);
    await write(path.join(d, 'meta.md'),
      `담당: ${pg.담당 || '-'}\n협업: ${(pg.협업 || []).join(', ')}\n배점: ${se.배점 ?? '-'}\n스토리라인: ${pg.스토리라인 || ''}\n산출물: ${pg.산출물 || ''}`);
    for (const rid of pg.req_ids || []) {
      (reqTocFromToc[rid] ||= []).push({ page_id: pg.page_id, dir: d });
      if (reqDir[rid]) {
        await link(reqDir[rid], path.join(d, '_axon', `req__${rid}`));                 // page→req
        await link(d, path.join(A, 'by_page', pg.page_id, 'page'));                    // page 노드
        await link(reqDir[rid], path.join(A, 'by_page', pg.page_id, `req__${rid}`));
        await link(d, path.join(reqDir[rid], '_axon', `toc__${pg.page_id}`));          // req→page (역간선)
      } else unmapped.push(`toc ${pg.page_id} → 없는 요구사항 ${rid}`);
    }
  }
  // 정합경고: req.toc_paths ↔ toc.req_ids 불일치 / 고아 req
  for (const it of req.items || []) {
    const declared = it.toc_paths || [];
    const actual = (reqTocFromToc[it.id] || []).map(x => x.page_id);
    if (declared.length === 0 && actual.length === 0) unmapped.push(`요구사항 ${it.id} 목차 미배치(고아)`);
    for (const t of declared) if (!actual.includes(t)) unmapped.push(`요구사항 ${it.id}.toc_paths(${t}) ↔ toc.req_ids 불일치`);
  }

  await write(path.join(OUT, '_LINKMODE'), `${LINKMODE}\n`);

  const linkNote = LINKMODE === 'symlink'
    ? '- 간선은 심볼릭 링크다. `ls` 로 따라간다.'
    : '- 이 환경은 심링크를 만들지 못해 간선이 `<이름>.link` 파일이다. 대상 경로는 `cat <이름>.link`.';

  await write(path.join(OUT, 'ai_context_guide.txt'),
`# 지식맵 사용법 (RAG 대신 폴더 탐색)
- 요구사항 근거:  cat ${OUT}/quark/req/{ID}__*/{summary,quote,detail}.md
- 목차 페이지가 덮는 요구사항:  ls ${OUT}/quark/toc/{장}/{절}/{page}/_axon/
- 요구사항을 덮는 목차 페이지:  ls ${OUT}/quark/req/{ID}__*/_axon/
- 담당사별:  ls ${OUT}/_mirror/by_담당/{주관사|참여사A|참여사B}/
- 배점 영역:  ls ${OUT}/_mirror/by_배점/
${linkNote}
- 절대 원문 없는 인용 금지 — quote.md 문장만 인용.`);

  if (unmapped.length) await write(path.join(OUT, '_UNMAPPED.md'),
    `# 정합 경고 (HITL Q4 트리거)\n\n` + unmapped.map(x => `- ${x}`).join('\n'));

  const nReq = (req.items || []).length;
  const nPage = (toc.chapters || []).flatMap(c => c.sections || []).flatMap(s => s.pages || []).length;
  console.log(`[docquark] req ${nReq} · page ${nPage} · 미매핑/경고 ${unmapped.length} · link=${LINKMODE} → ${OUT}/`);
  if (LINKMODE === 'file') console.log('[docquark] ℹ 심링크 미지원 환경 — 간선을 .link 파일로 생성했습니다');
  if (unmapped.length) console.log(`[docquark] ⚠ ${OUT}/_UNMAPPED.md 확인 (HITL 질문 대상)`);
}
main().catch(e => { console.error('[docquark] 실패:', e.message); process.exit(1); });
