'use strict';
const {FieldPath, FieldValue, Timestamp} = require('firebase-admin/firestore');
const DAY = 86400000;
function weekId(now) {
  const d = new Date(now);
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - ((d.getUTCDay()+6)%7)*DAY).toISOString().slice(0,10);
}
function activeWeek(id, data, now) {
  if (!data || !/^\d{4}-\d{2}-\d{2}$/.test(id)) return false;
  const start = data.startsAt?.toMillis?.(), end = data.endsAt?.toMillis?.();
  return Number.isFinite(start) && Number.isFinite(end) && weekId(start) === id
    && start === Date.parse(id+'T00:00:00Z') && end-start === 7*DAY
    && now >= start && now < end
    && ['title','dareText','moodId','moodName'].every(k => typeof data[k] === 'string' && data[k].trim().length > 0)
    && data.title.length <= 80 && data.dareText.length <= 500 && data.moodId.length <= 128
    && !data.moodId.includes('/') && data.moodName.length <= 80;
}
// A bounded, checkpointed page on each Monday tick. Retries and overlapping
// invocations cannot recreate notifications or reset their read state.
async function announceWeek(db, {now=()=>Date.now(), pageSize=100, maxPages=5}={}) {
  const time=now();
  if(new Date(time).getUTCDay() !== 1) return 0;
  const id=weekId(time), weekRef=db.doc(`weeklyDares/${id}`), job=db.doc(`notificationCampaigns/${id}`);
  const week=await weekRef.get();
  if(!activeWeek(id,week.data(),time)) return 0;
  let sent=0;
  for(let pageNumber=0;pageNumber<maxPages;pageNumber++) {
    const state=await job.get();
    if(state.data()?.complete) break;
    const cursor=state.data()?.cursor ?? null;
    let query=db.collection('users').orderBy(FieldPath.documentId()).limit(pageSize);
    if(cursor) query=query.startAfter(cursor);
    const page=await query.get();
    const count=await db.runTransaction(async tx=> {
      const refs=[job,weekRef];
      for(const user of page.docs) refs.push(user.ref, user.ref.collection('preferences').doc('notifications'),user.ref.collection('notifications').doc(`weekly_${id}`));
      const docs=await tx.getAll(...refs);
      if(docs[0].data()?.complete || (docs[0].data()?.cursor ?? null)!==cursor) return -1;
      const current=now();
      if(new Date(current).getUTCDay()!==1 || !activeWeek(id,docs[1].data(),current)) return -1;
      let created=0;
      for(let i=0;i<page.docs.length;i++) {
        const [user,prefs,existing]=docs.slice(2+i*3,5+i*3);
        if(!user.exists || existing.exists || prefs.data()?.weeklyDares===false) continue;
        // This announces the rollover, rather than backfilling new accounts.
        if(user.data().createdAt?.toMillis?.()>docs[1].data().startsAt.toMillis()) continue;
        tx.create(existing.ref,{kind:'weekly',recipientId:user.id,weeklyDareId:id,read:false,
          createdAt:FieldValue.serverTimestamp(),expiresAt:Timestamp.fromMillis(current+30*DAY)});
        created++;
      }
      tx.set(job,{cursor:page.docs.at(-1)?.id ?? cursor,complete:page.size<pageSize,updatedAt:FieldValue.serverTimestamp()});
      return created;
    });
    if(count<0) break;
    sent+=count;
    if(page.size<pageSize) break;
  }
  return sent;
}
module.exports={weekId,activeWeek,announceWeek};
