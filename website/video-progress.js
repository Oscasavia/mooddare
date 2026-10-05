// Coverage, not elapsed replay time: rewatching the same segment adds no progress.
export class VideoProgress {
  ranges=[];
  add(start,end){
    if(!Number.isFinite(start)||!Number.isFinite(end)||end<=start)return;
    const ranges=[...this.ranges,[Math.max(0,start),end]].sort((a,b)=>a[0]-b[0]);
    this.ranges=[];
    for(const r of ranges){const previous=this.ranges.at(-1);if(previous&&r[0]<=previous[1]+.05)previous[1]=Math.max(previous[1],r[1]);else this.ranges.push([...r]);}
  }
  get watched(){return this.ranges.reduce((sum,[a,b])=>sum+b-a,0);}
}
