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
let denied=false,removed=false,actions=[],manyReports=false,releaseReports=null;
let reportsGate=null,paged=false,failRoute=null,incomplete=false;
const retries=[];
const requests=[];
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
  const viewport = await cdp.send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
  await writeFile(join(artifacts, name + '-hero.png'), Buffer.from(viewport.data, 'base64'));
  const { cssContentSize } = await cdp.send('Page.getLayoutMetrics');
  const { data } = await cdp.send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true, clip: { x: 0, y: 0, width: cssContentSize.width, height: cssContentSize.height, scale: 1 } });
  await writeFile(join(artifacts, name + '.png'), Buffer.from(data, 'base64'));
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
    build.onResolve({filter:/analytics-source\.js$/},()=>({path:'analytics-fixture',namespace:'analytics-test'}));
    build.onLoad({filter:/.*/,namespace:'analytics-test'},()=>({contents:`export async function loadAnalytics({rangeDays}) { window.analyticsRequests = [...(window.analyticsRequests || []), rangeDays]; const result = window.analyticsFixture || {status:'not-connected'}; await window.analyticsDelay; if(window.analyticsError) throw Error('Insights could not be loaded.'); return result; }`,loader:'js'}));
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
      requests.push(req.url);
      let raw='';for await(const chunk of req)raw+=chunk;
      const body=raw?JSON.parse(raw):null;const route=req.url.split('?')[0].split('/').at(-1);
      res.setHeader('Content-Type','application/json');
      if(denied){res.writeHead(403);res.end(JSON.stringify({error:'This account does not have moderation access.'}));return;}
      if(route===failRoute){res.writeHead(503);res.end(JSON.stringify({error:'Temporary service issue. Please try again.'}));return;}
      const report={id:'report',postId:'post',reason:'<img src=x onerror=alert(1)>',createdAt:{_seconds:1800000000},review:{status:removed?'resolved':'pending'}};
      let value={};
      if(route==='reports'){
        if(reportsGate) await reportsGate;
        value={items:manyReports ? [report,...['Harassment or bullying','Spam or misleading content','Privacy concern','Inappropriate content','Other concern'].map((reason,i)=>({...report,id:'report'+i,postId:'post'+i,reason,review:{status:i===3?'resolved':'pending'}}))] : [report],cursor:null};
      }
      if(route==='reports'&&paged){if(req.url.includes('cursor='))value={items:[{...report,id:'next-report',reason:'A concern on the next page'}],cursor:null};else value.cursor='next';}
      if(route==='history')value={items:[...actions.map((x,i)=>({id:'action'+i,...x,status:'done'})),...(incomplete?[{id:'incomplete',reportId:'report',action:'remove',status:'retry',reason:'A previous incomplete decision',staff:'staff'}]:[])],cursor:null};
      if(route==='retry'){retries.push(body);incomplete=false;value={status:'done'};}
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
 await evaluate(`document.querySelector('#filter').value='pending';document.querySelector('#filter').dispatchEvent(new Event('change'))`);await until(`document.querySelector('#queue').textContent.includes('No matching')`);
 await evaluate(`document.querySelector('#history').click()`);await until(`document.querySelector('#queue').textContent.includes('Remove content')`);
 assert.equal(await evaluate(`document.querySelector('#filter').disabled`),true);
});
test('desktop queue exposes selection, honest counts and complete keyboard-accessible decisions',async()=>{
 manyReports=true; await evaluate(`document.querySelector('#reports').click()`);
 await until(`document.querySelectorAll('#queue .card').length===6`);
 assert.equal(await evaluate(`document.querySelector('#metric-value-3').textContent`),'6');
 assert.equal(await evaluate(`document.querySelector('#scope-note').textContent`),'Loaded reports only');
 await evaluate(`document.querySelectorAll('#queue .card')[1].click()`);
 await until(`document.querySelector('#detail h2')?.textContent==='@sunshine'`);
 assert.equal(await evaluate(`document.querySelectorAll('#queue .card[aria-pressed=true]').length`),1);
 assert.equal(await evaluate(`document.querySelectorAll('#detail img.media, #detail video').length`),0);
 await evaluate(`document.querySelector('#detail details').open=true`);
 for(const label of ['Suspend for 7 days','Ban account','Lift restriction']) {
   assert.equal(await evaluate(`[...document.querySelectorAll('#detail button')].some(b=>b.textContent===${JSON.stringify(label)} && b.getBoundingClientRect().height>=44)`),true);
 }
 await screenshot('workspace-desktop');
});
test('analytics disconnected state makes no collection calls and never fabricates zeros',async()=>{
 const before=requests.length;
 await evaluate(`document.querySelector('#analytics').click()`);
 await until(`document.querySelector('#analytics-state').textContent==='Not connected'`);
 assert.equal(requests.length,before);
 assert.equal(await evaluate(`document.querySelector('#analytics-selections').textContent`),'—');
 assert.equal(await evaluate(`document.querySelector('#analytics-notice').hidden`),false);
 await screenshot('analytics-disconnected-desktop');
});
const snapshot={status:'ready',schemaVersion:1,rangeDays:30,generatedAt:'2026-10-05T12:00:00Z',startDate:'2026-09-06T00:00:00Z',endDate:'2026-10-06T00:00:00Z',metrics:{moodSelections:640,communityParticipants:46,communityMoments:68},moods:[{id:'creative',name:'Creative',selections:230},{id:'chill',name:'Chill',selections:175},{id:'curious',name:'Curious',selections:125},{id:'energized',name:'Energized',selections:110},{id:'brave',name:'Brave',selections:0}],communityDares:[{id:'w1',title:'Find a little wonder in the everyday',participants:32,moments:43},{id:'w2',title:'Share a moment of unexpected kindness',participants:21,moments:25}]};
test('analytics adapter renders aggregates, includes zero moods and reverses sorting',async()=>{
 await evaluate(`window.analyticsFixture=${JSON.stringify(snapshot)};document.querySelector('#refresh').click()`);
 await until(`document.querySelector('#analytics-state').textContent==='Connected'`);
 assert.equal(await evaluate(`document.querySelector('#analytics-participants').textContent`),'46');
 assert.equal(await evaluate(`document.querySelector('#mood-results li:first-child').textContent`),'Creative230');
 assert.equal(await evaluate(`document.querySelectorAll('#community-results tbody tr').length`),2);
 await screenshot('analytics-connected-desktop-fixture');
 await evaluate(`document.querySelector('#mood-sort').value='least';document.querySelector('#mood-sort').dispatchEvent(new Event('change'))`);
 assert.equal(await evaluate(`document.querySelector('#mood-results li:first-child').textContent`),'Brave0');
 assert.equal(await evaluate(`document.querySelector('#mood-results progress').getAttribute('aria-label')`),'Brave: 0 selections');
});
test('analytics period changes, real zero values and recovery from failures',async()=>{
 await evaluate(`window.analyticsFixture={...window.analyticsFixture,rangeDays:7,startDate:'2026-09-29T00:00:00Z',metrics:{moodSelections:0,communityParticipants:0,communityMoments:0},moods:[],communityDares:[]};document.querySelector('#analytics-range').value='7';document.querySelector('#analytics-range').dispatchEvent(new Event('change'))`);
 await until(`document.querySelector('#analytics-selections').textContent==='0'`);
 assert.equal(await evaluate(`window.analyticsRequests.at(-1)`),7);
 assert.equal(await evaluate(`document.querySelector('#mood-results').textContent.includes('No mood data')`),true);
 await evaluate(`window.analyticsError=true;document.querySelector('#refresh').click()`);
 await until(`document.querySelector('#analytics-state').textContent==='Unavailable'`);
 assert.equal(await evaluate(`document.querySelector('#analytics-selections').textContent`),'—');
 assert.equal(await evaluate(`document.querySelector('#refresh').disabled`),false);
 await evaluate(`window.analyticsError=false;window.analyticsFixture={...window.analyticsFixture,metrics:{moodSelections:-1,communityParticipants:0,communityMoments:0}};document.querySelector('#refresh').click()`);
 await until(`document.querySelector('#status').textContent.includes('could not be read')`);
 await evaluate(`window.analyticsFixture={...${JSON.stringify(snapshot)},rangeDays:7,startDate:'2026-09-29T00:00:00Z',moods:[{id:'unsafe',name:'<img src=x onerror=alert(1)>',selections:640}]};document.querySelector('#refresh').click()`);
 await until(`document.querySelector('#analytics-state').textContent==='Connected'`);
 assert.equal(await evaluate(`document.querySelectorAll('#mood-results img').length`),0);
 assert.equal(await evaluate(`document.querySelector('#mood-results li').textContent.includes('<img')`),true);
});
test('analytics and review work on small phones with an actual back control',async()=>{
 await evaluate(`window.analyticsFixture={...${JSON.stringify(snapshot)},rangeDays:7,startDate:'2026-09-29T00:00:00Z'};document.querySelector('#refresh').click()`);
 await until(`document.querySelector('#analytics-state').textContent==='Connected'`);
 for(const width of [320,390,768]) {
   await cdp.send('Emulation.setDeviceMetricsOverride',{width,height:844,deviceScaleFactor:1,mobile:true});
   assert.ok(await evaluate(`document.documentElement.scrollWidth<=innerWidth`));
   assert.ok(await evaluate(`[...document.querySelectorAll('nav button')].every(b=>b.getBoundingClientRect().height>=44)`));
   await screenshot('analytics-'+width+'-fixture');
 }
 await cdp.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
 await evaluate(`document.querySelector('#reports').click()`);
 await until(`document.querySelectorAll('#queue .card').length===6`);
 await screenshot('inbox-mobile');
 await evaluate(`document.querySelector('#queue .card').click()`);
 await until(`document.querySelector('#detail h2')?.textContent==='@sunshine'`);
 assert.equal(await evaluate(`getComputedStyle(document.querySelector('.queue-panel')).display`),'none');
 assert.equal(await evaluate(`getComputedStyle(document.querySelector('#detail')).display`),'block');
 assert.equal(await evaluate(`document.activeElement.id`),'detail');
 assert.ok(await evaluate(`document.querySelector('#detail .back-to-queue').getBoundingClientRect().top >= document.querySelector('.sidebar').getBoundingClientRect().bottom`),'Back control must be below sticky navigation');
 await screenshot('report-mobile');
 await evaluate(`document.querySelector('#detail .back-to-queue').click()`);
 assert.notEqual(await evaluate(`getComputedStyle(document.querySelector('.queue-panel')).display`),'none');
 assert.equal(await evaluate(`document.activeElement.classList.contains('card')`),true);
 assert.ok(await evaluate(`document.documentElement.scrollWidth<=innerWidth`));
});
test('pagination preserves filters and reports load failures without losing results',async()=>{
 paged=true;await evaluate(`document.querySelector('#reports').click()`);
 await until(`!document.querySelector('#more').hidden`);
 await evaluate(`document.querySelector('#search').value='next page';document.querySelector('#search').dispatchEvent(new Event('input'))`);
 assert.equal(await evaluate(`document.querySelectorAll('#queue .card').length`),0);
 await evaluate(`document.querySelector('#more').click()`);
 await until(`document.querySelectorAll('#queue .card').length===1`);
 assert.equal(await evaluate(`document.querySelector('#metric-value-3').textContent`),'7');
 assert.equal(await evaluate(`document.querySelector('#more').hidden`),true);
 failRoute='reports';await evaluate(`document.querySelector('#refresh').click()`);
 await until(`document.querySelector('#status').textContent.includes('Temporary service')`);
 assert.equal(await evaluate(`document.querySelectorAll('#queue .card').length`),1);
 assert.equal(await evaluate(`document.querySelector('#refresh').disabled`),false);
 failRoute=null;paged=false;
});
test('failed moderation leaves the report usable and incomplete history actions can retry',async()=>{
 await evaluate(`document.querySelector('#reports').click()`);
 await until(`document.querySelectorAll('#queue .card').length===6`);
 await evaluate(`document.querySelector('#queue .card').click()`);
 await until(`document.querySelector('#detail h2')?.textContent==='@sunshine'`);
 failRoute='action';const before=actions.length;
 await evaluate(`[...document.querySelectorAll('#detail button')].find(b=>b.textContent==='Dismiss report').click();document.querySelector('#reason').value='Review complete with context';document.querySelector('#confirm-submit').click()`);
 await until(`document.querySelector('#status').textContent.includes('Temporary service') && !document.querySelector('#refresh').disabled`);
 await until(`[...document.querySelectorAll('#detail button')].some(b=>b.textContent==='Dismiss report' && !b.disabled)`);
 assert.equal(actions.length,before);failRoute=null;
 incomplete=true;await evaluate(`document.querySelector('#history').click()`);
 await until(`document.querySelector('#queue').textContent.includes('Retry incomplete action')`);
 await evaluate(`[...document.querySelectorAll('#queue button')].find(b=>b.textContent==='Retry incomplete action').click()`);
 await until(`!document.querySelector('#queue').textContent.includes('Retry incomplete action') && !document.querySelector('#refresh').disabled`);
 assert.deepEqual(retries,[{operationId:'incomplete'}]);
});
test('late analytics response cannot overwrite another view or a signed-out session',async()=>{
 await evaluate(`window.analyticsDelay=new Promise(resolve=>window.releaseAnalytics=resolve);document.querySelector('#analytics').click()`);
 await until(`document.querySelector('#analytics-state').textContent==='Loading insights'`);
 await evaluate(`document.querySelector('#reports').click();window.releaseAnalytics()`);
 await until(`document.querySelectorAll('#queue .card').length===6`);
 assert.equal(await evaluate(`document.querySelector('#analytics-view').hidden`),true);
 await evaluate(`window.analyticsDelay=new Promise(resolve=>window.releaseAnalytics=resolve);document.querySelector('#analytics').click()`);
 await until(`document.querySelector('#analytics-state').textContent==='Loading insights'`);
 await evaluate(`document.querySelector('#signout').click();window.releaseAnalytics()`);
 await until(`document.querySelector('#workspace').hidden`);
 assert.equal(await evaluate(`document.querySelector('#analytics-selections').textContent`),'—');
 await evaluate(`window.analyticsDelay=null;document.querySelector('#signin').click()`);
 await until(`document.querySelectorAll('#queue .card').length===6`);
});
test('late report responses cannot repopulate signed-out workspace',async()=>{
 reportsGate=new Promise(resolve=>releaseReports=resolve);
 await evaluate(`document.querySelector('#refresh').click()`);
 await until(`document.querySelector('#status').textContent==='Loading results…'`);
 await evaluate(`document.querySelector('#signout').click()`);
 releaseReports();reportsGate=null;
 await new Promise(resolve=>setTimeout(resolve,100));
 assert.equal(await evaluate(`document.querySelector('#queue').children.length`),0);
 assert.equal(await evaluate(`document.querySelector('#workspace').hidden`),true);
 await evaluate(`document.querySelector('#signin').click()`);
 await until(`document.querySelectorAll('#queue .card').length===6`);
});
test('mobile review fits and sign-out clears the workspace',async()=>{
 await cdp.send('Emulation.setDeviceMetricsOverride',{width:360,height:800,deviceScaleFactor:1,mobile:true});assert.ok(await evaluate(`document.documentElement.scrollWidth<=innerWidth`));await screenshot('queue-mobile');
 await evaluate(`document.querySelector('#signout').click()`);await until(`document.querySelector('#workspace').hidden`);assert.equal(await evaluate(`document.querySelector('#queue').children.length`),0);
 assert.deepEqual(errors.filter(e=>!e.includes('403 (Forbidden)')&&!e.includes('503 (Service Unavailable)')),[]);
});

 test('live analytics contract shows coverage and growth on desktop and mobile',async()=>{
 const live={...snapshot,schemaVersion:2,trackingStartedAt:'2026-10-05T00:00:00Z',metrics:{...snapshot.metrics,signups:12,accountDeletions:2,currentProfiles:53,posts:100,creators:50,likes:230}};
 for(const width of [1440,390]){
  await visit('/admin/',width,1000);await evaluate(`document.querySelector('#signin').click()`);await until(`!document.querySelector('#workspace').hidden`);
  await evaluate(`window.analyticsFixture=${JSON.stringify(live)};document.querySelector('#analytics').click()`);await until(`document.querySelector('#analytics-state').textContent==='Connected'`);
  assert.equal(await evaluate(`document.querySelector('#analytics-signups').textContent`),'12');
  assert.equal(await evaluate(`document.querySelector('#analytics-accountDeletions').textContent`),'2');
  assert.ok(await evaluate(`document.querySelector('#analytics-coverage').textContent.includes('Earlier activity is not available')`));
  assert.equal(await evaluate(`getComputedStyle(document.querySelector('#signout')).paddingLeft`),width===1440?'17px':'10px');
  assert.ok(await evaluate(`document.documentElement.scrollWidth<=innerWidth`));
  await screenshot(`analytics-connected-v2-fixture-${width}`);
 }
});
