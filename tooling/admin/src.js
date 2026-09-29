import {initializeApp} from 'firebase/app';
import {getAuth,GoogleAuthProvider,signInWithPopup,signOut,setPersistence,browserSessionPersistence,onAuthStateChanged} from 'firebase/auth';
import {config} from './firebase-config.js';
const auth=getAuth(initializeApp(config));
await setPersistence(auth,browserSessionPersistence);
const $=id=>document.getElementById(id);
let rows=[],cursor=null,mode='reports',selected=null,blob=null,generation=0,busy=false;
const text=(tag,value,cls)=>{const el=document.createElement(tag);el.textContent=value;if(cls)el.className=cls;return el;};
const date=v=>v?new Date((v._seconds??v.seconds)*1000).toLocaleString():'';
function status(message){$('status').textContent=message;}
async function api(route,body){
 const token=await auth.currentUser?.getIdToken();if(!token)throw Error('Please sign in.');
 const response=await fetch(`/admin-api/${route}`,{method:body?'POST':'GET',headers:{Authorization:`Bearer ${token}`,...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});
 if(!response.ok){const error=await response.json();throw Error(error.error||'Unable to complete the request.');}
 return route.startsWith('media?')?response.blob():response.json();
}
$('signin').onclick=async()=>{try{await signInWithPopup(auth,new GoogleAuthProvider());}catch{status('Sign-in did not finish. Please try again.');}};
$('signout').onclick=()=>signOut(auth);
onAuthStateChanged(auth,async user=>{
 ++generation;clearMedia();rows=[];selected=null;$('queue').replaceChildren();$('detail').replaceChildren();$('workspace').hidden=true;$('login').hidden=false;$('signout').hidden=!user;
 if(!user){status('');return;}
 try{await api('session');$('workspace').hidden=false;$('login').hidden=true;await load(false);}catch(e){status(e.message);}
});
function clearMedia(){if(blob){URL.revokeObjectURL(blob);blob=null;}}
async function load(more=false){
 if(busy)return;busy=true;status('Loading…');
 try{const data=await api(`${mode}${more&&cursor?'?cursor='+encodeURIComponent(cursor):''}`);rows=more?[...rows,...data.items]:data.items;cursor=data.cursor;render();status('');}catch(e){status(e.message);}finally{busy=false;}
}
function render(){
 const q=$('search').value.toLowerCase(),filter=$('filter').value;
 const list=rows.filter(r=>JSON.stringify(r).toLowerCase().includes(q)&&(mode==='history'||filter==='all'||(r.review?.status||'pending')===filter));
 $('queue').replaceChildren();
 for(const r of list){const card=text('button','', 'card');card.append(text('strong',mode==='history'?`${r.action} · ${r.status}`:(r.commentId?(r.isReply?'Reply report':'Comment report'):r.userId?'Account report':'Moment report')),text('span',r.reason||''),text('span',date(r.createdAt)),text('span',mode==='history'?`Reviewer: ${r.staff}`:`${r.review?.status==='resolved'?'Resolved':'Needs review'} · ${r.userId||r.postId}`));card.onclick=()=>open(r.reportId||r.id);$('queue').append(card);
 if(mode==='history'&&['retry','processing','pending'].includes(r.status)){const retry=text('button','Retry incomplete action');retry.onclick=async()=>{try{retry.disabled=true;await api('retry',{operationId:r.id});await load();}catch(e){status(e.message);}finally{retry.disabled=false;}};$('queue').append(retry);}}
 if(!list.length)$('queue').append(text('p','No reports to show.','muted'));
 $('more').hidden=!cursor;
}
async function open(reportId){
 const current=++generation;selected=reportId;clearMedia();$('detail').replaceChildren(text('p','Loading report…'));
 try{const data=await api(`detail?id=${encodeURIComponent(reportId)}`);if(current!==generation)return;
 const area=$('detail');area.replaceChildren(text('span',data.removed?'Removed':data.review.status==='resolved'?'Reviewed':'Needs review','badge'),text('h2',data.author?.username?`@${data.author.username}`:'Reported content'),text('p',`Reason reported: ${data.report.reason}`));
 if(data.content){area.append(text('p',data.content.text||data.content.dareText||data.content.bio||'Account report','content'));if(data.path.startsWith('posts/')&&data.path.split('/').length===2){const button=text('button','Load reported media');button.onclick=async()=>{button.disabled=true;try{const file=await api(`media?id=${encodeURIComponent(reportId)}`);if(current!==generation)return;clearMedia();blob=URL.createObjectURL(file);const el=document.createElement(data.content.mediaType==='video'?'video':'img');el.className='media';el.src=blob;if(el.tagName==='VIDEO'){el.controls=true;el.preload='metadata';}else el.alt='Reported moment';button.replaceWith(el);}catch(e){status(e.message);button.disabled=false;}};area.append(button);}}
 else area.append(text('p','This content is no longer available.'));
 if(data.restriction.status&&data.restriction.status!=='active')area.append(text('p',`Account: ${data.restriction.status}${data.restriction.until?' until '+date(data.restriction.until):''}`));
 area.append(text('p',`Report ID: ${reportId}`,'muted'));
 if(data.review.reason)area.append(text('p',`Last decision: ${data.review.reason}`,'muted'));
 const actions=text('div','','actions');
 const choices=[];
 if(!data.path.startsWith('users/')&&data.content)choices.push([data.removed?'restore':'remove',data.removed?'Restore content':'Remove content']);
 choices.push(['dismiss','Dismiss report']);
 if(data.author)choices.push(['suspend','Suspend for 7 days'],['ban','Ban account'],['reinstate','Lift restriction']);
 for(const [action,label] of choices){const b=text('button',label,['remove','ban'].includes(action)?'danger':'');b.onclick=()=>confirmAction(action,label,reportId);actions.append(b);}area.append(actions);
 }catch(e){if(current===generation){$('detail').replaceChildren(text('p',e.message));status(e.message);}}
}
function confirmAction(action,label,reportId){
 $('confirm-title').textContent=label;$('reason').value='';
 $('confirm-description').textContent=action==='remove'?'Content will become unavailable in MoodDare. It can be restored after review.':action==='ban'?'This prevents this account from using MoodDare until you lift the restriction. Existing content is reviewed separately.':action==='suspend'?'This account will be restricted for seven days. The reason will be visible to its owner.':'Your decision and reason will be saved in the action history.';
 const dialog=$('confirm');dialog.returnValue='';dialog.showModal();
 dialog.onclose=async()=>{if(dialog.returnValue!=='confirm')return;const operationId=crypto.randomUUID();status('Applying action…');$('detail').querySelectorAll('button').forEach(b=>b.disabled=true);
 try{const result=await api('action',{operationId,reportId,action,reason:$('reason').value});status(result.status==='done'?'Decision saved.':'Action is processing. Check Action history.');await open(reportId);await load();}catch(e){status(e.message);await open(reportId);}};
}
$('refresh').onclick=()=>load();$('more').onclick=()=>load(true);$('search').oninput=render;$('filter').onchange=render;
for(const tab of ['reports','history'])$(tab).onclick=()=>{if(busy)return;mode=tab;$('reports').setAttribute('aria-pressed',String(tab==='reports'));$('history').setAttribute('aria-pressed',String(tab==='history'));$('filter').disabled=tab==='history';cursor=null;load();};
