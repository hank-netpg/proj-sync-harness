#!/usr/bin/env node
/**
 * docquark — 문서(requirements.json·toc.json) → quarkify 동형 폴더 지식맵.
 * quarkify(코드 파서)의 문서 버전. RAG 대체: 에이전트가 ls/tree/cat 로 근거 target-jump.
 * 산출: knowledge/{quark,_mirror,_axon,ai_context_guide.txt}  ·  정합경고: knowledge/_UNMAPPED.md
 * 사용: node docquark.mjs [proposalDir=proposal] [outDir=knowledge]
 * 의존: Node.js v18+ (stdlib fs만).
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
async function symlink(target, link) {
  await mkdir(path.dirname(link));
  try { await fs.unlink(link); } catch {}
  const rel = path.relative(path.dirname(link), target);
  try { await fs.symlink(rel, link); } catch (e) { if (e.code !== 'EEXIST') throw e; }
}

async function main() {
  const req = await readJson(path.join(PROP, 'requirements.json'));
  let toc = { chapters: [] };
  try { toc = await readJson(path.join(PROP, 'toc.json')); } catch {}

  await fs.rm(OUT, { recursive: true, force: true });
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
    // _mirror
    if (it.category) await symlink(d, path.join(M, 'by_kind', slug(it.category), it.id));
    if (it.담당)     await symlink(d, path.join(M, 'by_담당', slug(it.담당), it.id));
    if (it.배점)     await symlink(d, path.join(M, 'by_배점', slug(it.배점), it.id));
  }

  // toc leaf(page) + _axon(page↔req)
  const unmapped = [];
  const reqTocFromToc = {};
  for (const ch of toc.chapters || []) for (const se of ch.sections || []) for (const pg of se.pages || []) {
    const d = path.join(Q, 'toc', `${ch.id}__${slug(ch.title)}`, `${se.id}__${slug(se.title)}`, `${pg.page_id}__${slug(pg.title)}`);
    await mkdir(d);
    await write(path.join(d, 'meta.md'),
      `담당: ${pg.담당 || '-'}\n협업: ${(pg.협업 || []).join(', ')}\n배점: ${se.배점 ?? '-'}\n스토리라인: ${pg.스토리라인 || ''}\n산출물: ${pg.산출물 || ''}`);
    for (const rid of pg.req_ids || []) {
      (reqTocFromToc[rid] ||= []).push(pg.page_id);
      if (reqDir[rid]) {
        await symlink(reqDir[rid], path.join(d, '_axon', `req__${rid}`));            // page→req
        await symlink(d, path.join(A, 'by_page', pg.page_id, `page`));               // page 노드
        await symlink(reqDir[rid], path.join(A, 'by_page', pg.page_id, `req__${rid}`));
      } else unmapped.push(`toc ${pg.page_id} → 없는 요구사항 ${rid}`);
    }
  }
  // 정합경고: req.toc_paths ↔ toc.req_ids 불일치 / 고아 req
  for (const it of req.items || []) {
    const declared = it.toc_paths || [];
    const actual = reqTocFromToc[it.id] || [];
    if (declared.length === 0 && actual.length === 0) unmapped.push(`요구사항 ${it.id} 목차 미배치(고아)`);
    for (const t of declared) if (!actual.includes(t)) unmapped.push(`요구사항 ${it.id}.toc_paths(${t}) ↔ toc.req_ids 불일치`);
  }

  await write(path.join(OUT, 'ai_context_guide.txt'),
`# 지식맵 사용법 (RAG 대신 폴더 탐색)
- 요구사항 근거:  cat ${OUT}/quark/req/{ID}__*/{summary,quote,detail}.md
- 목차 페이지가 덮는 요구사항:  ls ${OUT}/quark/toc/{장}/{절}/{page}/_axon/
- 담당사별:  ls ${OUT}/_mirror/by_담당/{주관사|참여사A|참여사B}/
- 배점 영역:  ls ${OUT}/_mirror/by_배점/
- 절대 원문 없는 인용 금지 — quote.md 문장만 인용.`);

  if (unmapped.length) await write(path.join(OUT, '_UNMAPPED.md'),
    `# 정합 경고 (HITL Q4 트리거)\n\n` + unmapped.map(x => `- ${x}`).join('\n'));

  const nReq = (req.items || []).length;
  const nPage = (toc.chapters || []).flatMap(c => c.sections || []).flatMap(s => s.pages || []).length;
  console.log(`[docquark] req ${nReq} · page ${nPage} · 미매핑/경고 ${unmapped.length} → ${OUT}/`);
  if (unmapped.length) console.log(`[docquark] ⚠ ${OUT}/_UNMAPPED.md 확인 (HITL 질문 대상)`);
}
main().catch(e => { console.error('[docquark] 실패:', e.message); process.exit(1); });
