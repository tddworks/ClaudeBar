// Keep Cursor's authoritative total and billing-cycle pacing for Auto/API.
function read(response) {
    let json;
    try { json=JSON.parse(response.text); } catch(e) { return {error:{parseFailed:'Invalid JSON: '+e.message}}; }
    if(!json || Array.isArray(json) || typeof json!=='object') return {error:{parseFailed:'Response is not a JSON object'}};
    const numeric=v=>typeof v==='number' && Number.isFinite(v);
    const integer=v=>numeric(v)?Math.trunc(v):(typeof v==='boolean'?Number(v):0);
    const date=v=>typeof v==='string' && /^\d{4}-\d\d-\d\dT/.test(v) && Number.isFinite(Date.parse(v))?new Date(v).toISOString():null;
    const end=date(json.billingCycleEnd), start=date(json.billingCycleStart);
    const duration=start && end && Date.parse(end)>Date.parse(start)?(Date.parse(end)-Date.parse(start))/1000:null;
    const quotas=[], individual=json.individualUsage||{}, plan=individual.plan||{};
    const quota=(label,remaining,resetText,resetsAt=end,windowDuration=null)=>{
        const q={type:"time",name:label,percentRemaining:Math.max(0,remaining)};
        if(resetText!=null)q.resetText=resetText;
        if(resetsAt!=null)q.resetsAt=Date.parse(resetsAt)/1000;
        if(windowDuration!=null)q.windowSeconds=windowDuration;
        quotas.push(q);
    };
    if(plan.enabled===true) {
        const used=integer(plan.used), limit=Math.max(integer(plan.limit),integer((plan.breakdown||{}).total));
        if(limit>0) {
            const total=plan.totalPercentUsed, authoritative=numeric(total);
            const effectiveUsed=authoritative?Math.floor(total*limit/100+0.5):used;
            quota('Monthly',authoritative?100-total:100*(limit-used)/limit,effectiveUsed+'/'+limit+' requests');
            [['Auto','autoPercentUsed'],['API','apiPercentUsed']].forEach(([label,key])=>{
                const value=plan[key]; if(numeric(value) && value>=0)quota(label,100-value,null,duration==null?null:end,duration);
            });
        }
    }
    const demand=(object,label,text)=>{
        if(!object || object.enabled!==true)return;
        const used=integer(object.used), limit=integer(object.limit);
        if(limit>0)quota(label,100*(limit-used)/limit,used+'/'+limit+' '+text);
    };
    demand(individual.onDemand,'On-Demand','on-demand');
    if(json.limitType==='team')demand((json.teamUsage||{}).onDemand,'Team','team credits');
    const member=typeof json.membershipType==='string'?json.membershipType:'unknown';
    // An unlimited plan has no ceiling to show: the plan, and no made-up 100% (the Left law).
    if(json.isUnlimited===true && !quotas.length)return {quotas:[],plan:member.toUpperCase()};
    if(!quotas.length)return {error:{parseFailed:'No usage data found in Cursor response'}};
    return {quotas,plan:member?member.toUpperCase():null};
}
