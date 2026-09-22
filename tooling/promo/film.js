// Deterministic Canvas film. Each exported frame is rendered at an exact time.
const canvas = document.querySelector('#film');
const ctx = canvas.getContext('2d');
const portrait = new URLSearchParams(location.search).has('portrait');
canvas.width = portrait ? 1080 : 1920;
canvas.height = portrait ? 1920 : 1080;
const W=canvas.width,H=canvas.height;
const ink='#0d0e14', lavender='#c5b4ff', paper='#f4f2ed', muted='#aaa8b1';
const images={};
window.ready=Promise.all(['wordmark','discover','dare'].map(name=>new Promise((resolve,reject)=>{
 const im=new Image(); im.onload=()=>{images[name]=im;resolve()};im.onerror=reject;im.src=`/website/assets/${name==='wordmark'?'wordmark':name}.png`;
})));
// Generated from the app's MoodWinkGeometry at export time; never redraw the logo.
let geometry;
window.ready=Promise.all([window.ready,fetch('/tooling/promo/geometry.json').then(r=>r.json()).then(g=>geometry=g)]);
const clamp=x=>Math.max(0,Math.min(1,x));
const ease=x=>{x=clamp(x);return 1-Math.pow(1-x,3)};
const smooth=x=>{x=clamp(x);return x*x*(3-2*x)};
function round(x,y,w,h,r,fill){ctx.beginPath();ctx.roundRect(x,y,w,h,r);ctx.fillStyle=fill;ctx.fill()}
function text(s,x,y,size,color=paper,weight=500,align='left'){
 ctx.font=`${weight} ${size}px "Helvetica Neue", Helvetica, Arial, sans-serif`;ctx.fillStyle=color;ctx.textAlign=align;ctx.textBaseline='alphabetic';ctx.fillText(s,x,y);
}
function pathFor(wink){
 const right=geometry.openEye.map((a,i)=>a.map((v,j)=>v+(geometry.winkEye[i][j]-v)*wink));
 const p=new Path2D(); for(const commands of [geometry.face,geometry.leftEye,right,geometry.smile])for(const c of commands){if(!c.length)p.closePath();else if(c.length===2)p.moveTo(...c);else p.bezierCurveTo(...c)}return p;
}
function face(x,y,size,wink,color=lavender,rotation=0){ctx.save();ctx.translate(x,y);ctx.rotate(rotation);ctx.scale(size/100,size/100);ctx.translate(-50,-50);ctx.fillStyle=color;ctx.fill(pathFor(wink),'evenodd');ctx.restore()}
function winkAt(t,start){const d=t-start;return d<0||d>.85?0:d<.22?smooth(d/.22):d<.4?1:1-smooth((d-.4)/.45)}
function logo(x,y,width,alpha=1){ctx.save();ctx.globalAlpha*=alpha;const im=images.wordmark;ctx.drawImage(im,x-width/2,y,width,width*im.height/im.width);ctx.restore()}
function eyebrow(s,x,y,color=muted,align='left'){text(s,x,y,portrait?23:22,color,600,align)}
function phone(name,x,y,h,rotation=0,scale=1){
 const im=images[name], w=h*im.width/im.height;
 ctx.save();ctx.translate(x,y);ctx.rotate(rotation);ctx.scale(scale,scale);
 ctx.shadowColor='#0008';ctx.shadowBlur=65;ctx.shadowOffsetY=30;
 round(-w/2-11,-h/2-11,w+22,h+22,52,'#303039');ctx.shadowColor='transparent';
 round(-w/2-5,-h/2-5,w+10,h+10,46,ink);
 ctx.save();ctx.beginPath();ctx.roundRect(-w/2,-h/2,w,h,40);ctx.clip();ctx.drawImage(im,-w/2,-h/2,w,h);ctx.restore();ctx.restore();
}
function topBrand(){logo(portrait?190:208,portrait?92:75,portrait?230:216)}
function scene0(t){
 const pop=ease(t/.7); const y=portrait?660:440;
 face(W/2,y+35*(1-pop), (portrait?350:300)*(.86+.14*pop),winkAt(t,1.22),lavender,0);
 ctx.save();ctx.globalAlpha=smooth((t-.15)/.7);
 text('A little curious?',W/2,portrait?1070:720,portrait?87:100,paper,500,'center');
 eyebrow('GOOD. YOU’RE IN THE RIGHT PLACE.',W/2,portrait?1150:795,muted,'center');ctx.restore();
 logo(W/2,portrait?1490:925,portrait?260:230,smooth((t-.8)/.6));
}
function scene1(t){
 topBrand();const enter=ease(t/.85);
 if(portrait){
  eyebrow('01 / START WITH A FEELING',80,260);
  text('Pick your',80,382,100,paper,500);text('mood.',80,493,100,lavender,500);
  phone('discover',W/2,1122+70*(1-enter),1040,0,.96+.04*enter);
  text('Chill. Creative. Curious. You.',W/2,1750,34,muted,400,'center');
 }else{
  eyebrow('01 / START WITH A FEELING',146,338);
  text('Pick your',140,478,116,paper,500);text('mood.',140,602,116,lavender,500);
  text('A little dare for every kind of day.',146,686,32,muted,400);
  phone('discover',1350+80*(1-enter),550,850, -.028*(1-enter));
  const labels=['Chill','Creative','Curious'];let x=146;
  labels.forEach((s,i)=>{const active=Math.floor(Math.max(0,t-1.1)/1.1)%3===i;round(x,770,148,55,27,active?'#c5b4ff':'#202029');text(s,x+74,806,22,active?ink:muted,500,'center');x+=162});
 }
}
function scene2(t){
 topBrand();const enter=ease(t/.8);
 if(portrait){
  eyebrow('02 / TRY SOMETHING DIFFERENT',80,260);
  text('Small dare.',80,382,91,paper,500);text('Good story.',80,487,91,lavender,500);
  phone('dare',W/2,1120+70*(1-enter),1040,0,.96+.04*enter);
  text('See where a little creativity takes you.',W/2,1750,32,muted,400,'center');
 }else{
  phone('dare',515-65*(1-enter),550,850,.025*(1-enter));
  eyebrow('02 / TRY SOMETHING DIFFERENT',940,336);
  text('Small dare.',932,478,105,paper,500);text('Good story.',932,598,105,lavender,500);
  text('See where a little creativity takes you.',940,690,30,muted,400);
  ctx.strokeStyle='#c5b4ff';ctx.lineWidth=3;ctx.lineCap='round';ctx.beginPath();ctx.moveTo(943,765);ctx.bezierCurveTo(1000,780,1065,725,1138,755);ctx.stroke();
 }
}
function scene3(t){
 topBrand();const enter=ease(t/.7);
 const cx=portrait?W/2:1350,cy=portrait?1120:535;
 ctx.save();ctx.translate(cx,cy+50*(1-enter));ctx.rotate(-.035+.015*smooth(t/3.8));
 ctx.shadowColor='#0006';ctx.shadowBlur=65;ctx.shadowOffsetY=24;
 const cw=portrait?710:565,ch=portrait?785:670;
 round(-cw/2,-ch/2,cw,ch,48,'#bfaaff');ctx.shadowColor='transparent';
 face(0,-25,portrait?370:300,winkAt(t,.9),ink);
 text('Your moment.',0,ch/2-68,portrait?45:37,ink,500,'center');
 ctx.restore();
 if(portrait){eyebrow('03 / MAKE IT YOURS',80,260);text('Make it',80,382,102,paper,500);text('a moment.',80,497,102,lavender,500);text('Worth keeping. Worth sharing.',W/2,1715,35,muted,400,'center')}
 else{eyebrow('03 / MAKE IT YOURS',146,340);text('Make it',140,480,112,paper,500);text('a moment.',140,602,112,lavender,500);text('Worth keeping. Worth sharing.',146,688,32,muted,400)}
}
function scene4(t){
 const pop=ease(t/.65);
 face(W/2,portrait?615:326,portrait?295:230,winkAt(t,1.1),lavender,0);
 ctx.save();ctx.globalAlpha=pop;logo(W/2,portrait?881:520,portrait?640:590);
 text('A little dare. A great story.',W/2,portrait?1124:747,portrait?52:49,paper,400,'center');
 round(W/2-(portrait?150:134),portrait?1265:838,portrait?300:268,portrait?70:60,30,'#25222f');
 text('Coming soon',W/2,portrait?1311:878,portrait?30:26,lavender,500,'center');
 text('Android + iOS',W/2,portrait?1402:961,portrait?25:23,muted,400,'center');ctx.restore();
}
const starts=[0,3.4,8.6,13.4,17.2], scenes=[scene0,scene1,scene2,scene3,scene4];
window.renderFrame=function(t){
 ctx.globalAlpha=1;ctx.fillStyle=ink;ctx.fillRect(0,0,W,H);
 // A restrained pool of lavender light, with no decorative starbursts.
 const glow=ctx.createRadialGradient(W*.63,H*.38,0,W*.63,H*.38,W*.7);
 glow.addColorStop(0,'#252033');glow.addColorStop(1,ink);ctx.fillStyle=glow;ctx.fillRect(0,0,W,H);
 let i=starts.findLastIndex(s=>t>=s); if(i<0)i=0;
 const local=t-starts[i];const transition=.38;
 if(i>0&&local<transition){ctx.save();ctx.globalAlpha=1-smooth(local/transition);scenes[i-1](t-starts[i-1]);ctx.restore()}
 ctx.save();ctx.globalAlpha=i===0?1:smooth(local/transition);scenes[i](local);ctx.restore();
};
window.ready.then(()=>renderFrame(0));
