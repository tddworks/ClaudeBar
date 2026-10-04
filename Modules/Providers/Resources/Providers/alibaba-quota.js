// The Coding Plan quota from the API key's answer, or the console's — the
// cookie data source's last step.
function read(response, context) {
  function object(v) { return v != null && typeof v === 'object' && !Array.isArray(v); }
  function string(v) { return typeof v === 'string' && v.length ? v : null; }
  function integer(v) { if (typeof v === 'boolean') return v ? 1 : 0; if (typeof v === 'number' && isFinite(v)) return Math.trunc(v); if (typeof v === 'string' && /^[+-]?\d+$/.test(v)) return Number(v); return null; }
  function find(keys, value, convert) {
    if (!object(value)) return null;
    for (var i=0;i<keys.length;i++) { var found=convert(value[keys[i]]); if(found != null)return found; }
    var values=Object.keys(value);for(var i=0;i<values.length;i++){var found=find(keys,value[values[i]],convert);if(found!=null)return found;}
    return null;
  }
  function expanded(value) {
    if (!object(value)) return value;
    var result={};Object.keys(value).forEach(function(k){result[k]=value[k];});
    ['data','DataV2','successResponse','success_response'].forEach(function(k){if(object(value[k])) {var nested=expanded(value[k]);Object.keys(nested).forEach(function(key){if(result[key]==null)result[key]=nested[key];});}});
    return result;
  }
  function any(keys, value, convert) { for(var i=0;i<keys.length;i++){var v=convert(value[keys[i]]);if(v!=null)return v;}return null; }
  function date(v) { if(typeof v==='string'){if(/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:?\d{2})$/.test(v)){var d=Date.parse(v);if(isFinite(d))return d/1000;}if(v.trim()!==''&&isFinite(Number(v)))return Number(v);}if(typeof v==='number'&&isFinite(v))return v;return null; }
  function matching(value) {
    if(object(value)){if(['per5HourUsedQuota','per5HourTotalQuota','perWeekUsedQuota','perWeekTotalQuota'].some(function(k){return value[k]!=null;}))return value;var keys=Object.keys(value);for(var i=0;i<keys.length;i++){var q=matching(value[keys[i]]);if(q)return q;}}
    if(Array.isArray(value)){for(var i=0;i<value.length;i++){var q=matching(value[i]);if(q)return q;}}
    return null;
  }
  function quotaInfo(value) {return find(['codingPlanQuotaInfo','coding_plan_quota_info'],value,function(v){return object(v)?v:null;})||matching(value);}
  var data=response.json;
  // The cookie data source answers by step: the console's answer is the one.
  if(object(data)&&object(data.console)&&Object.keys(data).every(function(k){return k==='console'||k==='dashboard';}))data=data.console;
  else if(object(data)&&'console' in data&&typeof data.console==='string')return {error:{parseFailed:data.console.length?'Invalid JSON: malformed response':'Empty response body'}};
  if(!response.text.length)return {error:{parseFailed:'Empty response body'}};
  if(data==null)return {error:{parseFailed:'Invalid JSON: malformed response'}};
  if(!object(data))return {error:{parseFailed:'Unexpected payload format'}};
  var code=find(['code','status'],data,string),message=find(['message','msg'],data,string);
  if(code && /login/.test(code.toLowerCase()) || message && /log in|login/.test(message.toLowerCase()))return {error:{sessionExpired:'Re-authenticate in Alibaba Cloud console.'}};
  var statusCode=find(['statusCode','status_code'],data,integer);
  if(statusCode===401||statusCode===403)return {error:'authenticationRequired'};
  var payload=expanded(data),infos=find(['codingPlanInstanceInfos','coding_plan_instance_infos'],payload,function(v){return Array.isArray(v)?v:null;})||[],first=null,active=null;
  for(var i=0;i<infos.length;i++){var item=infos[i];if(!object(item))continue;if(!first)first=item;var status=any(['status','instanceStatus'],item,string);if(status&&/^(VALID|ACTIVE)$/.test(status.toUpperCase())){active=item;break;}}
  var quota=quotaInfo(active||first||{})||quotaInfo(payload);
  if(!quota)return {error:{parseFailed:'Missing coding plan quota data'}};
  var plan=null;
  for(var i=0;i<infos.length;i++){var item=infos[i];if(!object(item))continue;var status=any(['status','instanceStatus'],item,string);if(status==null||/^(VALID|ACTIVE)$/.test(status.toUpperCase())){plan=any(['planName','plan_name','instanceName','packageName'],item,string);if(plan)break;}}
  plan=plan||find(['planName','plan_name','packageName'],payload,string);
  var quotas=[];
  function add(type,usedKeys,totalKeys,resetKeys,window) {
    var used=any(usedKeys,quota,integer),total=any(totalKeys,quota,integer);
    if(used==null||total==null||total<=0)return;
    var q={type:type,percentRemaining:Math.max(0,total-used)/total*100,resetText:used+' / '+total+' used'};if(window)q.windowSeconds=window;if(type==='time')q.name='Monthly';var resets=any(resetKeys,quota,date);if(resets!=null)q.resetsAt=resets;
    // The billing month is the month that ends on its reset — its real length; none without a reset.
    if(type==='time'&&resets!=null){var end=new Date(resets*1000),start=new Date(end.getFullYear(),end.getMonth()-1,end.getDate(),end.getHours(),end.getMinutes(),end.getSeconds());q.windowSeconds=(end.getTime()-start.getTime())/1000;}
    quotas.push(q);
  }
  add('session',['per5HourUsedQuota','perFiveHourUsedQuota'],['per5HourTotalQuota','perFiveHourTotalQuota'],['per5HourQuotaNextRefreshTime','perFiveHourQuotaNextRefreshTime'],18000);
  add('weekly',['perWeekUsedQuota'],['perWeekTotalQuota'],['perWeekQuotaNextRefreshTime'],604800);
  add('time',['perBillMonthUsedQuota','perMonthUsedQuota'],['perBillMonthTotalQuota','perMonthTotalQuota'],['perBillMonthQuotaNextRefreshTime','perMonthQuotaNextRefreshTime'],null);
  if(!quotas.length)return {error:{parseFailed:'No quota windows found in payload'}};
  var result={quotas:quotas};if(plan)result.account={loginMethod:plan};return result;
}
