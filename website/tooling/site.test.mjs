import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { makeServer } from './serve.mjs';

let server, browser, profile, base, cdp, session;
const errors = [];
const artifacts = fileURLToPath(new URL('../../test-results/website/', import.meta.url));

class CDP {
  constructor(socket) {
    this.socket = socket;
    this.id = 0;
    this.pending = new Map();
    socket.addEventListener('message', event => {
      const message = JSON.parse(event.data);
      if (message.id) {
        const entry = this.pending.get(message.id);
        if (!entry) return;
        this.pending.delete(message.id);
        message.error ? entry.reject(new Error(JSON.stringify(message.error))) : entry.resolve(message.result);
      }
      if (message.method === 'Runtime.exceptionThrown') errors.push(message.params.exceptionDetails.text);
      if (message.method === 'Log.entryAdded' && message.params.entry.level === 'error') errors.push(message.params.entry.text);
    });
  }
  send(method, params = {}, sessionId = session) {
    const id = ++this.id;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.socket.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
    });
  }
}

async function evaluate(expression) {
  const result = await cdp.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
  return result.result.value;
}

async function until(expression, timeout = 10000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    if (await evaluate(expression)) return;
    await new Promise(resolve => setTimeout(resolve, 40));
  }
  throw new Error(`Timed out waiting for ${expression}`);
}

async function visit(path = '/', width = 1440, height = 1000) {
  await cdp.send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: width < 600 });
  await cdp.send('Page.navigate', { url: base + path });
  await until(`location.href === ${JSON.stringify(base + path)} && document.readyState === 'complete'`);
  await evaluate(`document.querySelectorAll('img').forEach(img => img.loading = 'eager'); document.fonts.ready.then(() => true)`);
  await until(`[...document.querySelectorAll('img[src]')].every(img => img.complete && img.naturalWidth > 0)`);
}

async function screenshot(name) {
  const { cssContentSize } = await cdp.send('Page.getLayoutMetrics');
  const { data } = await cdp.send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true, clip: { x: 0, y: 0, width: cssContentSize.width, height: cssContentSize.height, scale: 1 } });
  await writeFile(join(artifacts, name + '.png'), Buffer.from(data, 'base64'));
  const viewport = await cdp.send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
  await writeFile(join(artifacts, name + '-hero.png'), Buffer.from(viewport.data, 'base64'));
}

before(async () => {
  const binary = process.env.CHROME_BIN || [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser',
  ].find(existsSync);
  assert.ok(binary, 'Install Chrome/Chromium or set CHROME_BIN.');
  profile = await mkdtemp(join(tmpdir(), 'mooddare-site-chrome-'));
  await mkdir(artifacts, { recursive: true });
  server = makeServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
  browser = spawn(binary, ['--headless=new', '--no-sandbox', '--no-first-run', '--no-default-browser-check', '--disable-background-networking', '--disable-component-update', '--disable-sync', '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank'], { stdio: ['ignore', 'ignore', 'pipe'] });
  const endpoint = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Chrome did not start')), 20000);
    let output = '';
    browser.stderr.on('data', data => {
      output += data;
      const match = output.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (match) { clearTimeout(timer); resolve(match[1]); }
    });
    browser.on('error', error => { clearTimeout(timer); reject(error); });
  });
  const socket = new WebSocket(endpoint);
  await new Promise((resolve, reject) => { socket.addEventListener('open', resolve, { once: true }); socket.addEventListener('error', reject, { once: true }); });
  cdp = new CDP(socket);
  const { targetId } = await cdp.send('Target.createTarget', { url: 'about:blank' }, null);
  ({ sessionId: session } = await cdp.send('Target.attachToTarget', { targetId, flatten: true }, null));
  await cdp.send('Page.enable');
  await cdp.send('Runtime.enable');
  await cdp.send('Log.enable');
});

after(async () => {
  cdp?.socket.close();
  if (browser && browser.exitCode === null) {
    const exited = new Promise(resolve => browser.once('exit', resolve));
    browser.kill('SIGTERM');
    await exited;
  }
  if (server) await new Promise(resolve => server.close(resolve));
  if (profile) await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
});

for (const width of [320, 390, 480, 768, 1024, 1280, 1440, 1920]) {
  test(`landing fits ${width}px and loads every local image`, async () => {
    await visit('/', width);
    const dimensions = await evaluate(`({viewport:innerWidth, content:document.documentElement.scrollWidth})`);
    assert.ok(dimensions.content <= dimensions.viewport, JSON.stringify(dimensions));
    assert.equal(await evaluate(`document.querySelectorAll('h1').length`), 1);
    assert.equal(await evaluate(`document.querySelector('#android-download').disabled && document.querySelector('#ios-download').disabled`), true);
    assert.equal(await evaluate(`document.querySelector('video').controls && !document.querySelector('video').autoplay && document.querySelector('video').preload === 'none'`), true);
    if ([390, 1440].includes(width)) await screenshot(width === 390 ? 'mobile' : 'desktop');
  });
}

for (const width of [390, 1440]) {
  test(`floating header stays visible and anchor targets clear it at ${width}px`, async () => {
    await visit('/', width);
    await evaluate(`window.scrollTo({top: 650, behavior: 'instant'})`);
    const header = await evaluate(`(() => {
      const rect = document.querySelector('.site-header').getBoundingClientRect();
      return {top: rect.top, bottom: rect.bottom, left: rect.left, right: rect.right};
    })()`);
    assert.ok(header.top >= 8 && header.top <= 20, JSON.stringify(header));
    assert.ok(header.left > 0 && header.right < width, 'Header floats inside the viewport.');
    const destination = await evaluate(`Math.min(
      document.querySelector('#downloads').getBoundingClientRect().top + scrollY - parseFloat(getComputedStyle(document.documentElement).scrollPaddingTop),
      document.documentElement.scrollHeight - innerHeight
    )`);
    await evaluate(`document.querySelector('.site-header a[href="#downloads"]').click()`);
    await until(`Math.abs(scrollY - ${destination}) < 2`);
    assert.equal(await evaluate(`document.querySelector('#downloads').getBoundingClientRect().top > document.querySelector('.site-header').getBoundingClientRect().bottom`), true);
  });
}

test('approved wordmark contains visible lettering, not a blank export', async () => {
  await visit('/');
  const visiblePixels = await evaluate(`(() => {
    const img = document.querySelector('.brand img');
    const canvas = document.createElement('canvas');
    canvas.width = img.naturalWidth; canvas.height = img.naturalHeight;
    const context = canvas.getContext('2d'); context.drawImage(img, 0, 0);
    const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
    let visible = 0;
    for (let i = 3; i < pixels.length; i += 4) if (pixels[i] > 128) visible++;
    return visible;
  })()`);
  assert.ok(visiblePixels > 1000, 'Wordmark must have visible lettering.');
});

test('mood sampler updates the prompt and accessible selection', async () => {
  await visit('/');
  await evaluate(`document.querySelector('[data-mood="chill"]').click()`);
  assert.equal(await evaluate(`document.querySelector('#sample-text').textContent`), 'Find a little patch of nature and photograph it.');
  assert.equal(await evaluate(`document.querySelectorAll('[data-mood][aria-pressed="true"]').length`), 1);
  assert.equal(await evaluate(`document.querySelector('[data-mood="creative"]').getAttribute('aria-pressed')`), 'false');
  assert.equal(await evaluate(`document.querySelector('.mood-playground').dataset.activeMood`), 'chill');
  await until(`getComputedStyle(document.querySelector('.sample-dare')).backgroundColor === 'rgb(220, 230, 222)'`);
  await evaluate(`document.querySelector('[data-mood="happy"]').click()`);
  assert.match(await evaluate(`document.querySelector('#sample-text').textContent`), /smile today/);
  assert.equal(await evaluate(`document.querySelector('.mood-playground').dataset.activeMood`), 'happy');
  await evaluate(`document.querySelector('[data-mood="curious"]').click()`);
  assert.equal(await evaluate(`document.querySelector('#sample-text').textContent`), 'Photograph an interesting shadow.');
  await evaluate(`document.querySelector('[data-mood="creative"]').click()`);
  assert.equal(await evaluate(`document.querySelector('#sample-text').textContent`), 'Draw your mood without lifting your pen.');
  await until(`getComputedStyle(document.querySelector('.sample-dare')).backgroundColor === 'rgb(229, 222, 237)'`);
});

test('all screenshots enlarge, close with Escape/button and restore keyboard focus', async () => {
  await visit('/', 390);
  for (const screen of ['discover', 'dare', 'welcome']) {
    await evaluate(`{const button = document.querySelector('[data-screen="${screen}"]');button.focus();button.click();}`);
    assert.equal(await evaluate(`document.querySelector('#screen-dialog').open`), true);
    assert.equal(await evaluate(`document.body.classList.contains('dialog-open')`), true);
    assert.match(await evaluate(`document.querySelector('#screen-image').src`), new RegExp(`${screen}\\.png$`));
    await cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 });
    await cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 });
    await until(`!document.querySelector('#screen-dialog').open && !document.body.classList.contains('dialog-open')`);
    assert.equal(await evaluate(`document.activeElement.dataset.screen`), screen);
  }
  await evaluate(`document.querySelector('[data-screen="discover"]').click();document.querySelector('.dialog-close').click()`);
  await until(`!document.querySelector('#screen-dialog').open`);
});

test('FAQ works and local links have real destinations', async () => {
  await visit('/');
  await evaluate(`document.querySelector('summary').click()`);
  assert.equal(await evaluate(`document.querySelector('details').open`), true);
  const links = await evaluate(`[...new Set([...document.querySelectorAll('a[href]')].map(a => a.getAttribute('href')))]`);
  for (const href of links) {
    if (href.startsWith('#')) assert.equal(await evaluate(`!!document.getElementById(${JSON.stringify(href.slice(1))})`), true, href);
    else if (!href.startsWith('mailto:')) assert.equal((await fetch(new URL(href, base))).status, 200, href);
  }
});

test('privacy and terms load offline-style without scripts at narrow widths', async () => {
  for (const page of ['privacy', 'terms']) {
    await visit(`/${page}.html`, 320);
    assert.equal(await evaluate(`document.documentElement.scrollWidth <= innerWidth`), true);
    assert.equal(await evaluate(`document.querySelectorAll('script').length`), 0);
    assert.match(await evaluate(`document.body.textContent`), /MoodDare team/);
    assert.match(await evaluate(`document.body.textContent`), /Last updated September 22, 2026/);
  }
});

test('invalid release URLs stay disabled; valid HTTPS URLs enable downloads and a non-autoplay video', async () => {
  await visit('/');
  await evaluate(`import('./app.js').then(m => m.applyReleaseConfig({androidUrl:'javascript:alert(1)',iosUrl:'http://example.com',promoVideoUrl:'data:text/html,unsafe'}))`);
  assert.equal(await evaluate(`document.querySelectorAll('.store-link:disabled').length`), 2);
  assert.equal(await evaluate(`document.querySelector('video').src.endsWith('assets/promo/mooddare-landscape.mp4')`), true);
  await evaluate(`import('./app.js').then(m => m.applyReleaseConfig({androidUrl:'https://example.com/android',iosUrl:'https://example.com/ios',promoVideoUrl:'https://example.com/promo.mp4'}))`);
  assert.equal(await evaluate(`document.querySelector('#android-download').tagName`), 'A');
  assert.equal(await evaluate(`document.querySelector('#ios-download').href`), 'https://example.com/ios');
  assert.equal(await evaluate(`document.querySelector('video').controls && !document.querySelector('video').autoplay && document.querySelector('video').preload === 'none'`), true);
});

for (const width of [390, 1440]) {
  test(`promo plays, seeks and loads captions at ${width}px without autoplay`, async () => {
    await visit('/', width);
    const portrait = width < 600;
    assert.equal(await evaluate(`document.querySelector('video').src.endsWith('mooddare-${portrait ? 'portrait' : 'landscape'}.mp4')`), true);
    assert.equal(await evaluate(`document.querySelector('video').paused && !document.querySelector('video').muted && document.querySelector('video').playsInline`), true);
    assert.equal(await evaluate(`document.querySelector('video').networkState`), 1);
    const poster = await evaluate(`document.querySelector('video').poster`);
    assert.equal((await fetch(poster)).status, 200);
    await evaluate(`document.querySelector('#film').scrollIntoView({behavior:'instant',block:'center'})`);
    await cdp.send('Runtime.evaluate', {
      expression: `document.querySelector('video').play().then(()=>true)`,
      userGesture: true, awaitPromise: true, returnByValue: true,
    });
    await until(`document.querySelector('video').currentTime > .15`);
    assert.equal(await evaluate(`Math.abs(document.querySelector('video').duration - 22) < .1`), true);
    assert.equal(await evaluate(`document.querySelector('video').videoWidth`), portrait ? 1080 : 1920);
    await evaluate(`document.querySelector('video').pause(); document.querySelector('video').currentTime=10; document.querySelector('video').textTracks[0].mode='showing'`);
    await until(`!document.querySelector('video').seeking && document.querySelector('video').currentTime >= 10`);
    await until(`document.querySelector('video').textTracks[0].cues?.length === 8`);
    assert.equal(await evaluate(`document.querySelector('video').textTracks[0].activeCues[0]?.text`), 'Try something different.');
    await screenshot(portrait ? 'film-mobile' : 'film-desktop');
    const original = await evaluate(`document.querySelector('video').src`);
    await cdp.send('Emulation.setDeviceMetricsOverride', { width: portrait ? 1440 : 390, height: 1000, deviceScaleFactor: 1, mobile: !portrait });
    assert.equal(await evaluate(`document.querySelector('video').src`), original, 'Resizing does not replace playback.');
    assert.equal(await evaluate(`document.querySelector('video').currentTime >= 10`), true);
  });
}

test('local media server supports seeking and serves captions with correct content types', async () => {
  const url=base+'/assets/promo/mooddare-landscape.mp4';
  const response=await fetch(url, { headers: { Range: 'bytes=0-31' } });
  assert.equal(response.status,206);
  assert.equal(response.headers.get('content-type'),'video/mp4');
  assert.equal((await response.arrayBuffer()).byteLength,32);
  const suffix=await fetch(url, { headers: { Range: 'bytes=-32' } });
  assert.equal(suffix.status,206);
  assert.equal((await suffix.arrayBuffer()).byteLength,32);
  assert.equal((await fetch(url,{headers:{Range:'bytes=999999999-'}})).status,416);
  const captions=await fetch(base+'/assets/promo/captions-en.vtt');
  assert.match(captions.headers.get('content-type'),/text\/vtt/);
  assert.match(await captions.text(),/^WEBVTT/);
});

test('reduced motion and JavaScript-free content remain usable', async () => {
  await cdp.send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] });
  await visit('/', 390);
  assert.equal(await evaluate(`getComputedStyle(document.documentElement).scrollBehavior`), 'auto');
  await cdp.send('Emulation.setScriptExecutionDisabled', { value: true });
  try {
    await visit('/', 390);
    assert.match(await evaluate(`document.querySelector('h1').textContent`), /great story/);
    assert.equal(await evaluate(`document.querySelector('#android-download').disabled`), true);
    assert.equal(await evaluate(`document.querySelector('video').controls && !!document.querySelector('video track')`), true);
  } finally {
    await cdp.send('Emulation.setScriptExecutionDisabled', { value: false });
    await cdp.send('Emulation.setEmulatedMedia', { features: [] });
  }
  assert.deepEqual(errors, []);
});
