import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import http from 'node:http';
import http2 from 'node:http2';

const args=process.argv.slice(2), mode=args.shift();
function option(name, fallback) { const i=args.indexOf(`--${name}`); return i<0?fallback:args[i+1]; }
const directory=path.resolve(option('directory','/private/tmp/dhoop-remote-buzz-test'));
const privateFile=path.join(directory,'private-config.json');
async function save(file,value){await fs.writeFile(file,JSON.stringify(value,null,2)+'\n',{mode:0o600,flag:'wx'});}
if(mode==='prepare') {
  await fs.mkdir(directory,{recursive:true,mode:0o700});
  const until=Math.floor(Date.now()/1000)+7200;
  const configuration={installationId:crypto.randomUUID(),secret:crypto.randomBytes(32).toString('base64'),
    apiToken:crypto.randomBytes(32).toString('hex'),expiresAt:until,topic:'com.devkunjadia.zhoop.loshi.noop'};
  await save(privateFile,configuration);
  // Swift Codable Date uses seconds since 2001 unless a different date strategy is selected.
  await save(path.join(directory,'dhoop-remote-buzz-setup.json'),{
    installationId:configuration.installationId,secret:configuration.secret,expiresAt:until-978307200});
  console.log('Prepared private test configuration and phone setup. Test expires in two hours. No secrets printed.');
} else if(mode==='configure') {
  const config=JSON.parse(await fs.readFile(privateFile,'utf8'));
  const registration=JSON.parse(await fs.readFile(option('registration'),'utf8'));
  if(registration.installationId!==config.installationId || registration.topic!==config.topic || registration.environment!=='sandbox')throw Error('Registration does not match this test');
  const keyId=option('key-id'),keyFile=option('apns-key');
  if(!/^[A-Z0-9]{10}$/.test(keyId??''))throw Error('APNs Key ID required');
  const key=await fs.readFile(keyFile,'utf8');crypto.createPrivateKey(key);
  await save(path.join(directory,'server-env.json'),{
    DHOOP_BUZZ_TEST_TOKEN:config.apiToken,DHOOP_BUZZ_SECRET:config.secret,
    DHOOP_BUZZ_INSTALLATION_ID:config.installationId,DHOOP_BUZZ_DEVICE_TOKEN:registration.token,
    DHOOP_BUZZ_TEST_UNTIL:String(config.expiresAt),APNS_TEAM_ID:'8MSX699Z2T',APNS_KEY_ID:keyId,APNS_PRIVATE_KEY:key});
  console.log('Prepared server secrets locally. No push sent and no secrets printed.');
} else if(mode==='serve') {
  const env=JSON.parse(await fs.readFile(path.join(directory,'server-env.json'),'utf8'));
  const seconds=Number(env.DHOOP_BUZZ_TEST_UNTIL)-Math.floor(Date.now()/1000);
  if(seconds<=0 || seconds>7200)throw Error('Test expired or invalid');
  const module=await import(new URL('file://'+path.resolve(option('life-repo','/Users/devkunjadia/Developer/life'),'lib/dhoop-buzz.ts')));
  // Node HTTP/2 adapter; Cloudflare's deployed API uses its native fetch implementation.
  function appleFetch(url,options) { return new Promise((resolve,reject)=>{
    const target=new URL(url),client=http2.connect(target.origin);
    const stream=client.request({':method':'POST',':path':target.pathname,...options.headers});
    const cleanup=()=>client.close();
    options.signal?.addEventListener('abort',()=>{stream.close();cleanup();reject(Error('APNs timeout'));},{once:true});
    stream.on('response',headers=>{stream.resume();stream.on('end',()=>{cleanup();resolve(new Response(null,{status:Number(headers[':status'])}));});});
    stream.on('error',e=>{cleanup();reject(e);});client.on('error',reject);stream.end(options.body);
  }); }
  const server=http.createServer(async(req,res)=>{
    const reply=(status,body)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(body));};
    const expected=Buffer.from(`Bearer ${env.DHOOP_BUZZ_TEST_TOKEN}`),provided=Buffer.from(req.headers.authorization??'');
    if(req.method!=='POST'||req.url!=='/buzz')return reply(404,{error:'not_found'});
    if(expected.length!==provided.length||!crypto.timingSafeEqual(expected,provided))return reply(401,{error:'unauthorized'});
    try { let text='';for await(const chunk of req){text+=chunk;if(Buffer.byteLength(text)>1024)throw Error('Too large');}
      const body=JSON.parse(text);if(Object.keys(body).length!==1)throw Error('Invalid payload');
      reply(200,await module.sendBuzzTest(env,body.eventId,Math.floor(Date.now()/1000),appleFetch));
    } catch {reply(503,{error:'test_failed'});}
  });
  server.listen(Number(option('port','8799')),'127.0.0.1',()=>console.log('Test API listening on localhost:8799/buzz. Automatic shutdown before test expiry.'));
  const deadline=setTimeout(()=>server.close(),Math.min(seconds,5400)*1000);
  server.on('close',()=>clearTimeout(deadline));
} else if(mode==='call') {
  const config=JSON.parse(await fs.readFile(privateFile,'utf8'));
  const endpoint=option('endpoint','http://127.0.0.1:8799/buzz');const target=new URL(endpoint);
  if(target.protocol!=='https:'&&!['127.0.0.1','localhost'].includes(target.hostname))throw Error('HTTPS required');
  const eventId=crypto.randomUUID();
  const response=await fetch(endpoint,{method:'POST',headers:{authorization:`Bearer ${config.apiToken}`,'content-type':'application/json'},body:JSON.stringify({eventId}),signal:AbortSignal.timeout(15000)});
  console.log(JSON.stringify({eventId,httpStatus:response.status,...await response.json()}));
} else {console.log('Modes: prepare, configure --registration FILE --apns-key FILE --key-id ID, serve, call. Every mode accepts --directory DIR.');}
