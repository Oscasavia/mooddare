import {VideoProgress} from './video-progress.js';
// First-party, tab-session analytics. Never send URLs, referrers or free text.
const allowed = new Set(['/','/index.html','/privacy.html','/terms.html','/delete-data.html','/moment/']);
const page = location.pathname.startsWith('/moment/') ? '/moment/' : location.pathname;
const enabled = allowed.has(page) && navigator.doNotTrack !== '1' && navigator.globalPrivacyControl !== true;
const id=()=>globalThis.crypto?.randomUUID?.() || 'event-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2);
let session = enabled ? id() : null;
if(enabled) try { session = sessionStorage.getItem('md-metrics-session') || session; sessionStorage.setItem('md-metrics-session',session); } catch {}
let queue=[], busy=false;
export function track(name,properties={}) {
  if(!enabled) return;
  queue.push({id:id(),name,at:Date.now(),page,...properties});
  if(queue.length>100) queue.shift();
}
export async function flush() {
  queue=queue.filter(e=>e.at>=Date.now()-86400000);
  if(busy||!queue.length) return;
  busy=true;
  const events=queue.slice(0,20);
  try {
    const response=await fetch('/website-metrics',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({session,events}),keepalive:true});
    if(response.ok) {const ids=new Set(events.map(e=>e.id));queue=queue.filter(e=>!ids.has(e.id));}
  } catch {} finally {busy=false;}
}
export function watchVideo(video,videoId) {
  if(!videoId) return;
  let last=0,wall=0;
  const progress=new VideoProgress();
  const sent=new Set();
  const send=name=>{if(!sent.has(name)){sent.add(name);track(name,{videoId});}};
  video.addEventListener('playing',()=>{last=video.currentTime;wall=performance.now();send('video_start');});
  video.addEventListener('seeking',()=>{last=video.currentTime;wall=performance.now();});
  video.addEventListener('timeupdate',()=>{
    const now=performance.now(),delta=video.currentTime-last,elapsed=(now-wall)/1000;
    if(!video.seeking&&!video.paused&&!document.hidden&&delta>0&&delta<=2&&delta<=elapsed*video.playbackRate+0.25) progress.add(last,video.currentTime);
    last=video.currentTime;wall=now;
    if(Number.isFinite(video.duration)&&video.duration>0) for(const n of [25,50,75]) if(progress.watched/video.duration>=n/100)send('video_'+n);
  });
  video.addEventListener('ended',()=>{if(progress.watched>=video.duration*.9)send('video_complete');});
  video.addEventListener('error',()=>send('video_error'));
}
if(enabled) {
  track('page_view');
  setInterval(flush,4000);
  document.addEventListener('visibilitychange',()=>{if(document.hidden)flush();});
  window.addEventListener('pagehide',flush);
  document.addEventListener('click',event=>{
    const el=event.target.closest('a,[data-mood],[data-screen]');if(!el)return;
    if(el.dataset.mood){track('mood_demo',{target:el.dataset.mood});return;}
    if(el.hasAttribute('data-screen')){track('screenshot_open');return;}
    if(el.id==='android-download'||el.id==='ios-download'){track('download_click',{target:el.id.split('-')[0]});return;}
    const href=el.getAttribute('href')||'';
    if(href.startsWith('mailto:'))track('contact_click',{target:'support'});
    else {
      const url=new URL(href,location.href);
      if(url.origin!==location.origin)return;
      const targets={'/':'home','/index.html':'home','/privacy.html':'privacy','/terms.html':'terms','/delete-data.html':'delete-data'};
      const target=url.hash.slice(1)||targets[url.pathname];
      if(['how-it-works','inside','film','downloads','home','privacy','terms','delete-data'].includes(target))track('navigation_click',{target});
    }
  });
  for(const details of document.querySelectorAll('details')) details.addEventListener('toggle',()=>{if(details.open)track('faq_open',{target:'faq'});});
}
