const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

const NOTICE = 'Lenzorium Player does not provide any content. Use it only with content you are legally allowed to access.';

const shell = (title, body) => `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)} · Lenzorium</title>
<style>
:root{--bg:#0A0C10;--s:#141820;--s2:#1C2230;--line:#262D3B;--t:#F2F4F8;--m:#9AA3B5;--a:#6B5BFF}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--t);font:16px/1.5 Inter,system-ui,-apple-system,Segoe UI,sans-serif}
main{max-width:560px;margin:0 auto;padding:40px 20px}
.brand{display:flex;align-items:center;gap:10px;font-weight:600;font-size:20px;margin-bottom:32px}
h1{font-size:32px;line-height:1.15;margin:0 0 8px;letter-spacing:-.02em}p{color:var(--m);margin:0 0 20px}
label{display:block;font-size:14px;color:var(--m);margin:14px 0 6px}
input,select{width:100%;height:50px;padding:0 14px;border-radius:10px;border:1px solid var(--line);background:var(--s);color:var(--t);font:inherit}
input:focus,select:focus,button:focus-visible{outline:3px solid #fff;outline-offset:2px}
.row{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.plans{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:16px}
.plan{display:block;border:1px solid var(--line);background:var(--s);border-radius:12px;padding:14px;cursor:pointer;margin:0;color:var(--t)}
.plan input{width:auto;height:auto;margin-right:8px}
button{margin-top:22px;width:100%;height:54px;border:0;border-radius:12px;background:var(--a);color:#fff;font:600 17px/1 inherit;cursor:pointer}
button[disabled]{opacity:.6}
.msg{margin-top:16px;padding:12px 14px;border-radius:10px;background:var(--s2);display:none}.msg.show{display:block}
.err{color:#FF8A8A}.ok{color:#7BE0A8}
small{display:block;color:#8A93A6;margin-top:28px}
</style></head><body><main>
<div class="brand"><svg width="30" height="30" viewBox="0 0 36 36" aria-hidden="true"><circle cx="18" cy="18" r="16" fill="none" stroke="#F2F4F8" stroke-width="2.5"/><circle cx="18" cy="18" r="9" fill="#6B5BFF"/><circle cx="21.5" cy="14.5" r="2.6" fill="#F2F4F8"/></svg>Lenzorium Player</div>
${body}
<small>${NOTICE}</small>
</main></body></html>`;

const deviceFields = (device) => `
<div class="row">
  <div><label for="deviceId">Device ID</label><input id="deviceId" name="deviceId" required autocomplete="off" placeholder="A4:3F:9C:21:7E:B0" value="${esc(device)}"></div>
  <div><label for="deviceKey">Device key</label><input id="deviceKey" name="deviceKey" required inputmode="numeric" autocomplete="off" placeholder="482 917"></div>
</div>`;

const submitScript = (endpoint, onOk) => `
<script>
const f=document.querySelector('form'),m=document.querySelector('.msg'),b=f.querySelector('button');
f.addEventListener('submit',async e=>{e.preventDefault();b.disabled=true;m.className='msg';
 const data=Object.fromEntries(new FormData(f));
 try{const r=await fetch('${endpoint}',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
  const j=await r.json();if(!r.ok)throw new Error(j.error||'Something went wrong');${onOk}}
 catch(err){m.textContent=err.message;m.className='msg show err';b.disabled=false}});
</script>`;

export function activatePage({ device = '', done = false, devActivate = false } = {}) {
  if (done) {
    return shell('Thank you', `<h1>Payment received</h1><p>Your device unlocks within a few seconds. If the TV still shows the activation screen, press “I’ve paid — check now”.</p>`);
  }
  return shell(
    'Activate',
    `<h1>Activate your device</h1>
<p>Enter the device ID and key shown on your TV, choose a plan and pay. The app unlocks within seconds.</p>
<form>
${deviceFields(device)}
<label for="email">Email for your receipt</label><input id="email" name="email" type="email" autocomplete="email">
<div class="plans">
  <label class="plan"><input type="radio" name="plan" value="yearly" checked>Yearly · 1 device<br><strong>[PRICE]</strong></label>
  <label class="plan"><input type="radio" name="plan" value="lifetime">Lifetime · 1 device<br><strong>[PRICE]</strong></label>
</div>
<button type="submit">${devActivate ? 'Activate (test mode)' : 'Continue to payment'}</button>
<div class="msg" role="status"></div>
</form>
<p style="margin-top:28px">Want to type your playlist here instead of with the remote? <a style="color:#A79CFF" href="/setup?device=${encodeURIComponent(device)}">Send a playlist to your TV</a></p>
${submitScript('/api/checkout', "if(j.url){location.href=j.url}else{m.textContent='Activated. Your TV unlocks within a few seconds.';m.className='msg show ok'}")}`,
  );
}

export function setupPage({ device = '' } = {}) {
  return shell(
    'Send playlist',
    `<h1>Send a playlist to your TV</h1>
<p>Type the details from your TV provider here. Your TV picks them up within a few seconds. They are deleted from our server as soon as your TV has them.</p>
<form>
${deviceFields(device)}
<label for="name">Playlist name</label><input id="name" name="name" value="Home">
<label for="type">Type</label>
<select id="type" name="type" onchange="document.getElementById('x').style.display=this.value==='xtream'?'block':'none';document.getElementById('urlLabel').textContent=this.value==='xtream'?'Server URL':'Playlist link (M3U URL)'">
  <option value="xtream">Xtream Codes login</option><option value="m3uUrl">M3U link</option>
</select>
<label for="url" id="urlLabel">Server URL</label><input id="url" name="url" inputmode="url" autocomplete="off" required>
<div id="x"><div class="row">
  <div><label for="username">Username</label><input id="username" name="username" autocomplete="off"></div>
  <div><label for="password">Password</label><input id="password" name="password" type="password" autocomplete="off"></div>
</div></div>
<label for="epgUrl">TV guide link (optional)</label><input id="epgUrl" name="epgUrl" inputmode="url" autocomplete="off">
<button type="submit">Send to my TV</button>
<div class="msg" role="status"></div>
</form>
${submitScript('/api/device/playlist', "m.textContent='Sent. Your TV adds it within a few seconds.';m.className='msg show ok';b.disabled=false")}`,
  );
}
