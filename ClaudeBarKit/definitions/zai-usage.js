function read(response) {
    const failure=message=>({error:{parseFailed:message}});
    let json;try{json=JSON.parse(response.text);}catch(e){return failure('Invalid JSON: '+e.message);}
    const object=v=>v && typeof v==='object' && !Array.isArray(v);
    if(!object(json) || (json.data!=null && !object(json.data)))return failure('Invalid JSON: Invalid quota response');
    const limits=json.data && json.data.limits;
    if(limits==null || (Array.isArray(limits)&&!limits.length))return failure('No quota limits found');
    if(!Array.isArray(limits))return failure('Invalid JSON: Invalid limits');
    const quotas=[];
    for(const entry of limits) {
        if(!object(entry)||typeof entry.type!=='string'||typeof entry.percentage!=='number'||!Number.isFinite(entry.percentage)||(entry.unit!=null && (!Number.isInteger(entry.unit)))||(entry.nextResetTime!=null && typeof entry.nextResetTime!=='string' && !Number.isInteger(entry.nextResetTime)))return failure('Invalid JSON: Invalid limit');
        // Only the units Z.ai documents state a window: 3 is 5 hours, 6 is a
        // week. Anything else states none, rather than a guessed week.
        let type,name,windowSeconds=null;
        if(entry.type==='TIME_LIMIT'){type='time';name='MCP';}
        else if(entry.type==='TOKENS_LIMIT'||entry.type==='CREDIT_LIMIT') {
            if(entry.unit==null||entry.unit===3){type='session';windowSeconds=18000;}
            else if(entry.unit===6){type='weekly';windowSeconds=604800;}
            else {type='model';name=entry.unit===7?'Monthly':(entry.type==='TOKENS_LIMIT'?'Tokens':'Credits')+' (unit '+entry.unit+')';}
        } else continue;
        let resetsAt=null;
        if(typeof entry.nextResetTime==='number')resetsAt=entry.nextResetTime/1000;
        else if(typeof entry.nextResetTime==='string') {
            const date=Date.parse(entry.nextResetTime);
            // Numeric strings are seconds, not milliseconds or calendar years.
            if(entry.nextResetTime.trim()!=='' && Number.isFinite(Number(entry.nextResetTime)))resetsAt=Number(entry.nextResetTime);
            else if(Number.isFinite(date))resetsAt=date/1000;
        }
        quotas.push({type,name,percentRemaining:100-Math.max(0,Math.min(100,entry.percentage)),resetsAt,windowSeconds});
    }
    return quotas.length?{quotas}:failure('No recognized quota types found');
}
