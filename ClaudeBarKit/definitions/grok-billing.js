// Billing fields and time windows are server reported, with no host I/O.
// The answers come by step name: `billing`, and `settings` when it answered.
function read(response, context) {
    const object=v=>v && typeof v==='object' && !Array.isArray(v);
    const answers=object(response.json)?response.json:{};
    const root=answers.billing;
    if(!object(root)) return {error:{parseFailed:'Failed to parse billing response as JSON'}};
    const config=object(root.config)?root.config:root;
    const date=s=>typeof s==='string' && Number.isFinite(Date.parse(s))?Date.parse(s)/1000:null;
    // The current period, or else the billing period — never one's start with the other's end.
    const current=config.currentPeriod||{};
    const period=date(current.end)!=null?current:{type:current.type,start:config.billingPeriodStart,end:config.billingPeriodEnd};
    const start=date(period.start), end=date(period.end), window=start!=null && end!=null && end>start?end-start:null;
    const seconds=end==null?null:end-context.now;
    let resetText=null;
    if(seconds>0) {
        const days=Math.floor(seconds/86400),hours=Math.floor((seconds%86400)/3600),minutes=Math.floor((seconds%3600)/60);
        resetText=days>0?'Resets in '+days+'d '+hours+'h '+minutes+'m':hours>0?'Resets in '+hours+'h '+minutes+'m':minutes>0?'Resets in '+minutes+'m':'Resets soon';
    }
    const type=typeof period.type==='string'?period.type:'';
    // The period the server names; one it doesn't is just "Usage".
    const weekly=type.includes('WEEKLY'), label=type.includes('MONTHLY')?'Monthly':type.includes('DAILY')?'Daily':null;
    const numeric=v=>typeof v==='number' && Number.isFinite(v)?v:typeof v==='boolean'?Number(v):null;
    const quotas=[];
    const add=(type,name,remaining)=>{
        const q={type,percentRemaining:Math.max(-100,remaining)};
        if(name!=null)q.name=name;
        if(end!=null)q.resetsAt=end;
        if(window!=null)q.windowSeconds=window;
        if(resetText!=null)q.resetText=resetText;
        quotas.push(q);
    };
    const total=numeric(config.creditUsagePercent);
    if(total!=null)add(weekly?'weekly':'time',weekly?null:(label==null?'Usage':label),100-total);
    const products=Array.isArray(config.productUsage) && config.productUsage.every(p=>p && typeof p==='object' && !Array.isArray(p))?config.productUsage:[];
    products.forEach(p=>{
        const used=numeric(p.usagePercent);
        if(typeof p.product!=='string' || used==null)return;
        let name=p.product.startsWith('Grok') && p.product.length>4?p.product.slice(4):p.product;
        name=name.replace(/([a-z])([A-Z])/g,'$1 $2');
        add('model',name,100-used);
    });
    // The cap's unit isn't stated (dollars or cents), so it stays a share of the cap.
    const cap=numeric((config.onDemandCap||{}).val),used=numeric((config.onDemandUsed||{}).val)||0;
    if(cap!=null && cap>0)add('time','On-Demand',100-used/cap*100);
    // USD cents; an empty object is zero. An empty wallet is left out, never shown depleted.
    const prepaid=object(config.prepaidBalance)?Number(config.prepaidBalance.val):NaN;
    if(Number.isFinite(prepaid) && prepaid>0)quotas.push({type:'model',name:'Prepaid',left:{money:String(prepaid/100),currency:'USD'}});
    // No usage reported is no quota — never a made-up 100% (the Left law).
    const result={quotas,account:{email:context.credential.email||null}};
    const settings=object(answers.settings)?answers.settings:{};
    const plan=planName(settings.subscription_tier_display)||planName(config.subscriptionTier)||planName(root.subscriptionTier);
    if(plan)result.plan=plan;
    return result;
}

// Grok's tier as people know it: SUPERGROK_HEAVY and supergrok read as SuperGrok Heavy and SuperGrok.
function planName(raw) {
    const text=typeof raw==='string'?raw.trim():'';
    if(!text)return null;
    const compact=text.toLowerCase().replace(/[^a-z]/g,'');
    return compact==='supergrokheavy'||compact==='heavy'?'SuperGrok Heavy':compact==='supergrok'?'SuperGrok':text;
}
