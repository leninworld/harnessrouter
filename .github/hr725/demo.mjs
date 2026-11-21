// Drives the real console (tested standalone build, loopback, auth gate off, no provider keys) in front
// of the real gateway. Every runtime-risk step is inside one diagnostic try, so a failure always leaves
// demo-result.json (with the step that failed) and, once a page exists, no-notice.png.
// Exit codes: 70 console page not served, 71 browser did not start, 72 harness not created,
// 73 settings view, directory input or notice failed, 74 a notice appeared but not the expected text.
import { chromium } from 'playwright';
import { writeFileSync } from 'node:fs';
const URL = 'http://127.0.0.1:3000';
const BAD = '{"name": "x"';                 // must match the fixture demo.sh writes
const state = { step: 'launch' };
const say = (o) => writeFileSync('/out/demo-result.json', JSON.stringify({ ...state, ...o }, null, 2));
let browser, page, code = 0;
try {
  browser = await chromium.launch();
  page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  state.step = 'console';
  const first = await page.goto(URL + '/studio', { timeout: 30000 });
  if (!first || first.status() >= 500) { code = 70; throw new Error(`console status ${first?.status()}`); }
  // The expected parser detail comes from the same Chromium that runs the console's JSON.parse.
  state.detail = await page.evaluate((s) => { try { JSON.parse(s); return null; } catch (e) { return e.message; } }, BAD);
  state.wantText = `Its plugin.json is not valid JSON. ${state.detail}`;
  // One synthetic harness through the console's own BFF route (/api/harness/[...path] -> gateway /v1/harnesses).
  state.step = 'create';
  const made = await page.evaluate(async () => {
    const r = await fetch('/api/harness/v1/harnesses', { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ name: 'Plugin notice demo', base: 'claude-code', memory: 'none' }) });
    const d = await r.json().catch(() => ({}));
    return { status: r.status, id: d.id || null };
  });
  Object.assign(state, { createStatus: made.status, id: made.id });
  if (made.status !== 200 || !made.id) { code = 72; throw new Error('harness not created'); }
  state.step = 'settings';
  await page.goto(`${URL}/studio/${encodeURIComponent(made.id)}?tab=settings&layer=caps&cap=plugin`, { timeout: 30000 });
  state.step = 'input';
  await page.locator('input[webkitdirectory]').setInputFiles('/fixture/bad-plugin', { timeout: 20000 });
  // ToastHost (ui/src/components/hrui/toast.tsx) renders exactly the message in div.toast[role=status]
  // and hides it after 2.6 s, so the screenshot is taken as soon as the expected text is there.
  state.step = 'notice';
  const notice = page.locator('div.toast[role="status"]:not([hidden])').first();
  await notice.waitFor({ timeout: 20000 });
  state.seen = await notice.textContent();
  if (state.seen !== state.wantText) { code = 74; throw new Error('unexpected notice text'); }
  await page.screenshot({ path: '/out/corrected-toast.png' });
  state.step = 'done';
  say({ ok: true, browser: browser.version() });
} catch (e) {
  if (!code) code = state.step === 'launch' ? 71 : 73;
  if (page) await page.screenshot({ path: '/out/no-notice.png' }).catch(() => {});
  say({ ok: false, error: String(e && e.message || e).slice(0, 500), exitCode: code });
} finally {
  if (browser) await browser.close().catch(() => {});
}
process.exit(code);
