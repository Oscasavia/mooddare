import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {readFile,writeFile,mkdir,mkdtemp,rm} from 'node:fs/promises';
import {resolve,join,extname} from 'node:path';
import {tmpdir} from 'node:os';
const root=resolve(import.meta.dirname,'../..');
const baseDir=process.env.PROMO_WORK || '/private/tmp/mooddare-promo';
const storyboard=JSON.parse(await readFile(join(root,'design/promo/mooddare-first-look/storyboard.json')));
const dart=await readFile(join(root,'lib/core/branding/mood_wink.dart'),'utf8');
const geometry={};for(const name of ['face','leftEye','openEye','winkEye','smile']){
 const match=dart.match(new RegExp(`static const ${name} = <List<double>>(\\[[\\s\\S]*?\\n  \\]);`));
 if(!match)throw new Error(`Missing app contour ${name}`);
 geometry[name]=JSON.parse(match[1].replace(/,\s*]/g,']'));
}
await writeFile(join(root,'tooling/promo/geometry.json'),JSON.stringify(geometry));
const server=createServer(async(req,res)=>{try{
 const path=resolve(root,'.'+new URL(req.url,'http://localhost').pathname);
 if(!path.startsWith(root+'/')){res.writeHead(403).end();return}
 const data=await readFile(path);res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.json':'application/json','.png':'image/png'})[extname(path)]||'application/octet-stream');res.end(data);
}catch{res.writeHead(404).end()}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const profile=await mkdtemp(join(tmpdir(),'mooddare-promo-chrome-'));
const browser=spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',['--headless=new','--no-sandbox','--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-sync','--remote-debugging-port=0',`--user-data-dir=${profile}`,'about:blank'],{stdio:['ignore','ignore','pipe']});
let socket;
try{
 const endpoint=await new Promise((resolve,reject)=>{let out='';const timeout=setTimeout(()=>reject(new Error('Chrome startup timeout')),20000);browser.stderr.on('data',data=>{out+=data;const m=out.match(/DevTools listening on (ws:\/\/[^\s]+)/);if(m){clearTimeout(timeout);resolve(m[1])}});browser.on('error',reject)});
 socket=new WebSocket(endpoint);await new Promise(r=>socket.addEventListener('open',r,{once:true}));
 let next=0,session;const pending=new Map();
 socket.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);if(!p)return;pending.delete(m.id);m.error?p.reject(new Error(JSON.stringify(m.error))):p.resolve(m.result)}});
 function send(method,params={},sid=session){return new Promise((resolve,reject)=>{const id=++next;pending.set(id,{resolve,reject});socket.send(JSON.stringify({id,method,params,...(sid?{sessionId:sid}:{})}))})}
 async function evaluate(expression){const r=await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw new Error(JSON.stringify(r.exceptionDetails));return r.result.value}
 const {targetId}=await send('Target.createTarget',{url:'about:blank'},null);session=(await send('Target.attachToTarget',{targetId,flatten:true},null)).sessionId;
 await send('Page.enable');await send('Runtime.enable');
 for(const format of ['landscape','portrait']){
  const folder=join(baseDir,format);await mkdir(folder,{recursive:true});
  await send('Emulation.setDeviceMetricsOverride',{width:format==='portrait'?1080:1920,height:format==='portrait'?1920:1080,deviceScaleFactor:1,mobile:false});
  await send('Page.navigate',{url:`http://127.0.0.1:${server.address().port}/tooling/promo/preview.html${format==='portrait'?'?portrait':''}`});
  for(let i=0;i<100;i++){if(await evaluate(`!!window.ready && document.readyState==='complete'`))break;await new Promise(r=>setTimeout(r,50))}
  await evaluate('window.ready.then(()=>true)');
  const samples=process.argv.includes('--samples');
  const frames=samples?[45,180,315,453,576]:Array.from({length:storyboard.duration*storyboard.fps},(_,i)=>i);
  for(const i of frames){const data=await evaluate(`renderFrame(${i/storyboard.fps});document.querySelector('canvas').toDataURL('image/jpeg',.96).split(',')[1]`);await writeFile(join(folder,`${String(i).padStart(5,'0')}.jpg`),Buffer.from(data,'base64'));if(i%90===0)console.log(`${format}: ${i}/${storyboard.duration*storyboard.fps}`)}
  console.log(`${format}: ${samples?'samples':'frames'} ready in ${folder}`);
 }
}finally{socket?.close();const exited=new Promise(r=>browser.once('exit',r));browser.kill('SIGTERM');await exited;await new Promise(r=>server.close(r));await rm(profile,{recursive:true,force:true,maxRetries:5,retryDelay:200})}
