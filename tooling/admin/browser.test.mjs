import {build} from 'esbuild';
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { makeServer } from '../../website/tooling/serve.mjs';

let server, browser, profile, base, cdp, session;
let denied=false,removed=false,actions=[];
const errors = [];
const artifacts = fileURLToPath(new URL('../../test-results/admin/', import.meta.url));

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
  const output=await build({entryPoints:[fileURLToPath(new URL('./src.js',import.meta.url))],bundle:true,write:false,format:'esm',plugins:[{name:'fake-auth',setup(build){
    build.onResolve({filter:/^firebase\/(auth|app)$/},args=>({path:args.path,namespace:'test'}));
    build.onLoad({filter:/.*/,namespace:'test'},()=>({contents:`
      export const initializeApp=()=>({});
      const user={getIdToken:async()=> 'test-token'},auth={currentUser:null};let callback;
      export const getAuth=()=>auth;export const browserSessionPersistence={};export const setPersistence=async()=>{};
      export class GoogleAuthProvider{};
      export const onAuthStateChanged=(auth,cb)=>{callback=cb;cb(null);};
      export const signInWithPopup=async()=>{auth.currentUser=user;await callback(user);};
      export const signOut=async()=>{auth.currentUser=null;await callback(null);};
    `,loader:'js'}));
  }}]});
  server = makeServer();
  const original=server.listeners('request')[0];server.removeAllListeners('request');
  server.on('request',async(req,res)=>{
    if(req.url==='/admin/app.js'){res.setHeader('Content-Type','text/javascript');res.end(output.outputFiles[0].text);return;}
    if(req.url.startsWith('/admin-api/')){
      let raw='';for await(const chunk of req)raw+=chunk;
      const body=raw?JSON.parse(raw):null;const route=req.url.split('?')[0].split('/').at(-1);
      res.setHeader('Content-Type','application/json');
      if(denied){res.writeHead(403);res.end(JSON.stringify({error:'This account does not have moderation access.'}));return;}
      const report={id:'report',postId:'post',reason:'<img src=x onerror=alert(1)>',createdAt:{_seconds:1800000000},review:{status:removed?'resolved':'pending'}};
      let value={};
      if(route==='reports')value={items:[report],cursor:null};
      if(route==='history')value={items:actions.map((x,i)=>({id:'action'+i,...x,status:'done'})),cursor:null};
      if(route==='detail')value={report,path:'posts/post',content:{dareText:'Share a little joy',authorId:'author',mediaType:'image'},removed,review:{},author:{id:'author',username:'sunshine'},restriction:{}};
      if(route==='action'){actions.push(body);removed=body.action==='remove';value={status:'done'};}
      res.end(JSON.stringify(value));return;
    }
    original(req,res);
  });
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


test('admin login is private, readable and responsive',async()=>{
 for(const width of [360,1440]){await visit('/admin/',width);assert.equal(await evaluate(`document.querySelector('#workspace').hidden`),true);assert.ok(await evaluate(`document.documentElement.scrollWidth<=innerWidth`));await screenshot('login-'+width);}
});
test('unapproved account sees denial without reports',async()=>{
 denied=true;await evaluate(`document.querySelector('#signin').click()`);await until(`document.querySelector('#status').textContent.includes('does not have')`);assert.equal(await evaluate(`document.querySelector('#workspace').hidden`),true);await evaluate(`document.querySelector('#signout').click()`);denied=false;
});
test('queue, report details and cancel do not execute an action; reported markup stays text',async()=>{
 await evaluate(`document.querySelector('#signin').click()`);await until(`document.querySelectorAll('#queue .card').length===1`);
 assert.equal(await evaluate(`document.querySelectorAll('#queue img').length`),0);
 await evaluate(`document.querySelector('#queue .card').click()`);await until(`document.querySelector('#detail h2')?.textContent==='@sunshine'`);
 await evaluate(`[...document.querySelectorAll('#detail button')].find(b=>b.textContent==='Remove content').click()`);await until(`document.querySelector('dialog').open`);
 await evaluate(`document.querySelector('dialog button[value=cancel]').click()`);assert.equal(actions.length,0);
 await screenshot('queue-desktop');
});
test('confirmed removal requires a reason and exposes restore; history and filtering work',async()=>{
 await evaluate(`[...document.querySelectorAll('#detail button')].find(b=>b.textContent==='Remove content').click()`);
 await evaluate(`document.querySelector('#confirm-submit').click()`);assert.equal(actions.length,0);
 await evaluate(`document.querySelector('#reason').value='Reviewed community rules violation';document.querySelector('#confirm-submit').click()`);
 await until(`[...document.querySelectorAll('#detail button')].some(b=>b.textContent==='Restore content')`);assert.equal(actions.length,1);assert.equal(actions[0].action,'remove');assert.ok(actions[0].operationId);
 await evaluate(`document.querySelector('#filter').value='pending';document.querySelector('#filter').dispatchEvent(new Event('change'))`);await until(`document.querySelector('#queue').textContent.includes('No reports')`);
 await evaluate(`document.querySelector('#history').click()`);await until(`document.querySelector('#queue').textContent.includes('remove')`);
 assert.equal(await evaluate(`document.querySelector('#filter').disabled`),true);
});
test('mobile review fits and sign-out clears the workspace',async()=>{
 await cdp.send('Emulation.setDeviceMetricsOverride',{width:360,height:800,deviceScaleFactor:1,mobile:true});assert.ok(await evaluate(`document.documentElement.scrollWidth<=innerWidth`));await screenshot('queue-mobile');
 await evaluate(`document.querySelector('#signout').click()`);await until(`document.querySelector('#workspace').hidden`);assert.equal(await evaluate(`document.querySelector('#queue').children.length`),0);
 assert.deepEqual(errors.filter(e=>!e.includes('403 (Forbidden)')),[]);
});
