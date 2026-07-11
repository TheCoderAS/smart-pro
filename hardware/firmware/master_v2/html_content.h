#pragma once
// Auto-generated - do not edit directly

static const char SETTINGS_HTML[] PROGMEM = R"SETHTML(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<title>Settings - Unisync</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
<style>
:root{
  --bg:#0a0a0f;--bg2:#111118;--bg3:#1a1a24;--bg4:#22222e;
  --border:#ffffff0f;--border2:#ffffff18;
  --text:#f0f0f5;--text2:#9090a8;--text3:#5a5a72;
  --accent:#6366f1;--accent2:#818cf8;--accentbg:#6366f11a;
  --green:#22c55e;--greenbg:#22c55e1a;
  --red:#ef4444;--redbg:#ef44441a;
  --r8:8px;--r12:12px;--r16:16px;
}
*{box-sizing:border-box;margin:0;padding:0}
html,body{background:var(--bg);color:var(--text);
  font-family:'Inter',system-ui,sans-serif;min-height:100vh;font-size:15px}
.app{max-width:480px;margin:0 auto;padding:20px 16px 60px}
.back{display:flex;align-items:center;gap:6px;color:var(--accent);
  font-size:13px;text-decoration:none;margin-bottom:24px;
  width:fit-content}
.back:hover{color:var(--accent2)}
h1{font-size:22px;font-weight:600;margin-bottom:4px}
.sub{font-size:13px;color:var(--text3);margin-bottom:28px}
.card{background:var(--bg2);border-radius:var(--r16);
  border:1px solid var(--border);padding:20px;margin-bottom:12px}
.card-label{font-size:11px;font-weight:600;letter-spacing:0.1em;
  color:var(--text3);text-transform:uppercase;margin-bottom:16px}
.info-row{display:flex;justify-content:space-between;align-items:center;
  padding:10px 0;border-bottom:1px solid var(--border)}
.info-row:last-child{border:none}
.info-key{font-size:13px;color:var(--text3)}
.info-val{font-size:13px;color:var(--text);font-family:monospace}
.file-zone{border:1px dashed var(--border2);border-radius:var(--r12);
  padding:24px;text-align:center;cursor:pointer;transition:all 0.2s;
  margin-bottom:14px;color:var(--text3);font-size:13px}
.file-zone:hover{border-color:var(--accent);color:var(--accent);
  background:var(--accentbg)}
.file-zone.has-file{border-color:#22c55e;color:#22c55e;background:var(--greenbg)}
.fname{font-size:11px;color:var(--text3);margin-top:6px}
.btn{width:100%;padding:13px;border:none;border-radius:var(--r12);
  font-size:14px;font-weight:600;cursor:pointer;font-family:inherit;
  margin-bottom:8px;transition:all 0.15s}
.btn.primary{background:var(--accent);color:#fff}
.btn.primary:hover{background:var(--accent2)}
.btn.primary:disabled{background:var(--bg4);color:var(--text3);cursor:not-allowed}
.btn.ghost{background:var(--bg3);color:var(--text2);border:1px solid var(--border)}
.btn.danger{background:var(--redbg);color:var(--red);border:1px solid #ef444430}
.prog-wrap{display:none;margin-bottom:8px}
.prog-bar{height:4px;background:var(--bg3);border-radius:2px;overflow:hidden}
.prog-fill{height:100%;background:var(--accent);width:0%;
  border-radius:2px;transition:width 0.3s}
.status{font-size:12px;color:var(--text3);margin-top:8px;text-align:center}
.ok{color:var(--green)} .err{color:var(--red)}
.mesh-status{font-size:13px;padding:10px 14px;border-radius:var(--r8);
  margin-bottom:14px}
.mesh-status.active{background:var(--greenbg);color:var(--green)}
.mesh-status.inactive{background:var(--bg3);color:var(--text3)}
.sheet-input{width:100%;padding:12px 14px;background:var(--bg3);
  border:1px solid var(--border);border-radius:var(--r12);color:var(--text);
  font-size:18px;letter-spacing:8px;font-family:monospace;text-align:center;
  outline:none;margin-bottom:12px;transition:border-color 0.15s}
.sheet-input:focus{border-color:var(--accent)}
</style>
</head>
<body>
<div class="app">
  <a href="/" class="back">&#8592; Back</a>
  <h1>Settings</h1>
  <div class="sub" id="sub">Loading...</div>

  <div class="card">
    <div class="card-label">Device info</div>
    <div id="info"><div style="color:var(--text3);font-size:13px">Loading...</div></div>
  </div>

  <div class="card">
    <div class="card-label">Firmware update</div>
    <p style="font-size:13px;color:var(--text3);margin-bottom:16px;line-height:1.6">
      Upload a compiled .bin file to update over the air.
      Device restarts automatically after a successful update.
    </p>
    <div class="file-zone" id="drop-zone" onclick="document.getElementById('fw').click()">
      Tap to select firmware .bin
      <div class="fname" id="fname">No file selected</div>
    </div>
    <input type="file" id="fw" accept=".bin" style="display:none" onchange="filePicked(this)"/>
    <button class="btn primary" id="ubtn" disabled onclick="startOTA()">Upload firmware</button>
    <div class="prog-wrap" id="pwrap">
      <div class="prog-bar"><div class="prog-fill" id="pfill"></div></div>
      <div class="status" id="ostatus">Preparing...</div>
    </div>
  </div>

  <div class="card">
    <div class="card-label">Mesh network</div>
    <div class="mesh-status inactive" id="mesh-status">Not in any mesh</div>
    <div id="mesh-join-section">
      <p style="font-size:13px;color:var(--text3);margin-bottom:14px;line-height:1.6">
        On the existing master tap <b style="color:var(--text)">Invite Master</b>
        and enter the PIN and MAC shown there.
      </p>
      <div style="margin-bottom:10px">
        <label style="font-size:10px;font-weight:600;letter-spacing:0.1em;
               color:var(--text3);text-transform:uppercase;display:block;
               margin-bottom:6px">6-digit PIN</label>
        <input class="sheet-input" id="mesh-pin" type="text"
               inputmode="numeric" maxlength="6" placeholder="123456"/>
      </div>
      <div style="margin-bottom:14px">
        <label style="font-size:10px;font-weight:600;letter-spacing:0.1em;
               color:var(--text3);text-transform:uppercase;display:block;
               margin-bottom:6px">Master MAC (12 hex chars, no colons)</label>
        <input class="sheet-input" id="mesh-mac" type="text"
               inputmode="text" maxlength="12" placeholder="AABBCCDDEEFF"
               style="letter-spacing:3px;font-size:15px"/>
      </div>
      <button class="btn primary" id="join-btn" onclick="joinMesh()">Join mesh</button>
        </div>
    <button class="btn danger" id="leave-btn" onclick="leaveMesh()"
      style="display:none">Leave mesh</button>
    <div class="status" id="mesh-msg"></div>
  </div>
</div>

<script>
var selFile=null;

function uptime(s){
  if(s<60)return s+'s';
  if(s<3600)return Math.floor(s/60)+'m '+s%60+'s';
  return Math.floor(s/3600)+'h '+Math.floor((s%3600)/60)+'m';
}

function loadInfo(){
  var xhr=new XMLHttpRequest();
  xhr.open('GET','/api/info',true);
  xhr.onload=function(){
    var d=JSON.parse(xhr.responseText);
    document.getElementById('sub').textContent='192.168.4.1 | Uptime: '+uptime(d.uptime);
    document.getElementById('info').innerHTML=
      row('Firmware','v8.5')+
      row('Free heap',d.free_heap.toLocaleString()+' bytes')+
      row('Master UID',d.uid)+
      row('IP address','192.168.4.1');
  };
  xhr.send();
}

function row(k,v){
  return '<div class="info-row">'+
    '<span class="info-key">'+k+'</span>'+
    '<span class="info-val">'+v+'</span></div>';
}

function filePicked(input){
  if(!input.files.length)return;
  selFile=input.files[0];
  document.getElementById('fname').textContent=
    selFile.name+' ('+Math.round(selFile.size/1024)+' KB)';
  document.getElementById('drop-zone').classList.add('has-file');
  document.getElementById('ubtn').disabled=false;
}

function startOTA(){
  if(!selFile)return;
  var btn=document.getElementById('ubtn');
  btn.disabled=true;btn.textContent='Uploading...';
  document.getElementById('pwrap').style.display='block';
  var xhr=new XMLHttpRequest();
  xhr.open('POST','/api/ota/master',true);
  xhr.upload.onprogress=function(e){
    if(e.lengthComputable){
      var p=Math.round(e.loaded/e.total*100);
      document.getElementById('pfill').style.width=p+'%';
      document.getElementById('ostatus').textContent='Uploading '+p+'%';
    }
  };
  xhr.onload=function(){
    if(xhr.status===200){
      document.getElementById('pfill').style.width='100%';
      document.getElementById('ostatus').innerHTML=
        '<span class="ok">Done! Restarting...</span>';
      setTimeout(function(){
        document.getElementById('ostatus').innerHTML=
          '<span class="ok">Restarted. <a href="/" style="color:var(--accent)">Go back</a></span>';
      },8000);
    } else {
      document.getElementById('ostatus').innerHTML=
        '<span class="err">Failed: '+xhr.responseText+'</span>';
      btn.disabled=false;btn.textContent='Upload firmware';
    }
  };
  xhr.onerror=function(){
    document.getElementById('ostatus').innerHTML=
      '<span class="ok">Restarting... <a href="/" style="color:var(--accent)">Back in 10s</a></span>';
  };
  var fd=new FormData();
  fd.append('firmware',selFile);
  xhr.send(fd);
}

function loadMesh(){
  var xhr=new XMLHttpRequest();
  xhr.open('GET','/api/mesh/status',true);
  xhr.onload=function(){
    var d=JSON.parse(xhr.responseText);
    var ms=document.getElementById('mesh-status');
    var lb=document.getElementById('leave-btn');
    var js=document.getElementById('mesh-join-section');
    if(d.active){
      ms.className='mesh-status active';
      ms.textContent='In mesh - '+d.peer_count+
        ' peer'+(d.peer_count!==1?'s':'')+' online';
      lb.style.display='block';
      js.style.display='none';
    } else {
      ms.className='mesh-status inactive';
      ms.textContent='Not in any mesh';
      lb.style.display='none';
      js.style.display='block';
    }
  };
  xhr.send();
}

async function joinMesh(){
  var pin=document.getElementById('mesh-pin').value.trim();
  var mac=document.getElementById('mesh-mac').value.trim().replace(/:/g,'').toUpperCase();
  var msg=document.getElementById('mesh-msg');
  if(pin.length!==6){
    msg.innerHTML='<span class="err">PIN must be 6 digits</span>';return;
  }
  if(mac.length!==12){
    msg.innerHTML='<span class="err">MAC must be 12 hex characters (no colons)</span>';return;
  }
  var btn=document.getElementById('join-btn');
  btn.disabled=true;btn.textContent='Joining...';
  msg.innerHTML='<span style="color:var(--text3)">Connecting to master 1...</span>';
  try {
    var r=await fetch('/api/mesh/join?pin='+pin+'&mac='+mac,{method:'POST'});
    var d=await r.json();
    if(r.ok&&d.status==='pending'){
      msg.innerHTML='<span style="color:var(--accent2)">Request sent. Waiting for approval...</span>';
      /* Poll until mesh_active */
      var poll=setInterval(async function(){
        try{
          var sr=await fetch('/api/mesh/status');
          var sd=await sr.json();
          if(sd.active){
            clearInterval(poll);
            msg.innerHTML='<span class="ok">Joined mesh!</span>';
            btn.textContent='Join mesh';btn.disabled=false;
            loadMesh();
          }
        }catch(e){}
      },2000);
      setTimeout(function(){
        clearInterval(poll);
        if(!document.getElementById('join-btn').disabled) return;
        msg.innerHTML='<span class="err">Timed out. Check PIN, MAC and try again.</span>';
        btn.textContent='Join mesh';btn.disabled=false;
      },60000);
    } else {
      msg.innerHTML='<span class="err">'+(d.error||'Failed')+'</span>';
      btn.disabled=false;btn.textContent='Join mesh';
    }
  } catch(e){
    msg.innerHTML='<span class="err">Network error: '+e.message+'</span>';
    btn.disabled=false;btn.textContent='Join mesh';
  }
}

function openMaster1(){
  /* Open Master 1 with pre-filled params so it can approve this join */
  var url='http://192.168.4.1/settings?approve_mac='+joinMyMac+
          '&approve_uid='+joinMyUid+'&approve_pin='+joinPin;
  window.open(url,'_blank');
}

function leaveMesh(){
  if(!confirm('Leave the mesh? This board will operate independently.'))return;
  var xhr=new XMLHttpRequest();
  xhr.open('POST','/api/mesh/leave',true);
  xhr.onload=function(){
    document.getElementById('mesh-msg').innerHTML='<span class="ok">Left mesh.</span>';
    loadMesh();
  };
  xhr.send();
}

loadInfo();
loadMesh();

/* Auto-fill PIN and MAC from URL params */
(function(){
  var params=new URLSearchParams(window.location.search);
  var pin=params.get('pin');
  var mac=params.get('mac');
  if(pin&&mac){
    var pinInput=document.getElementById('mesh-pin');
    var macInput=document.getElementById('mesh-mac');
    if(pinInput) pinInput.value=pin;
    if(macInput) macInput.value=mac;
    /* Scroll to mesh section */
    var section=document.getElementById('mesh-join-section');
    if(section) setTimeout(function(){
      section.scrollIntoView({behavior:'smooth',block:'center'});
    },400);
    /* Highlight inputs */
    var style='border-color:var(--accent);box-shadow:0 0 0 3px rgba(99,102,241,0.2)';
    if(pinInput) pinInput.style.cssText+=style;
    if(macInput) macInput.style.cssText+=style;
    /* Show hint */
    var msg=document.getElementById('mesh-msg');
    if(msg) msg.innerHTML=
      '<span style="color:var(--accent2)">PIN and MAC pre-filled. Tap Join mesh.</span>';
  }
})();
</script>
</body>
</html>
)SETHTML";

static const char HTML[] PROGMEM = R"MAINHTML(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<title>Unisync</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
<style>
:root{
  --bg:#0a0a0f;--bg2:#111118;--bg3:#1a1a24;--bg4:#22222e;
  --border:#ffffff0f;--border2:#ffffff18;
  --text:#f0f0f5;--text2:#9090a8;--text3:#5a5a72;
  --accent:#6366f1;--accent2:#818cf8;--accentbg:#6366f11a;
  --green:#22c55e;--greenbg:#22c55e1a;
  --red:#ef4444;--redbg:#ef44441a;
  --yellow:#f59e0b;--yellowbg:#f59e0b1a;
  --r8:8px;--r12:12px;--r16:16px;--r20:20px;
}
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
html,body{background:var(--bg);color:var(--text);font-family:'Inter',system-ui,sans-serif;
  min-height:100vh;font-size:15px;line-height:1.5}
/* Scrollbar */
::-webkit-scrollbar{width:4px}
::-webkit-scrollbar-track{background:transparent}
::-webkit-scrollbar-thumb{background:var(--border2);border-radius:4px}

/* Layout */
.app{max-width:480px;margin:0 auto;padding:20px 16px 100px}

/* Topbar */
.topbar{display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:28px}
.topbar-left{}
.app-name{font-size:11px;font-weight:600;letter-spacing:0.12em;color:var(--text3);
  text-transform:uppercase;margin-bottom:4px}
.master-title{font-size:22px;font-weight:600;color:var(--text);cursor:pointer;
  display:flex;align-items:center;gap:6px}
.master-title:hover .edit-icon{opacity:1}
.edit-icon{opacity:0;color:var(--text3);font-size:14px;transition:opacity 0.2s}
.conn-row{display:flex;align-items:center;gap:6px;margin-top:4px}
.conn-dot{width:6px;height:6px;border-radius:50%;background:var(--text3);
  transition:background 0.4s,box-shadow 0.4s}
.conn-dot.on{background:var(--green);box-shadow:0 0 6px var(--green)}
.conn-label{font-size:12px;color:var(--text3)}
.topbar-actions{display:flex;gap:8px;align-items:center;padding-top:4px}
.icon-btn{width:36px;height:36px;border-radius:var(--r8);border:1px solid var(--border);
  background:var(--bg2);display:flex;align-items:center;justify-content:center;
  cursor:pointer;color:var(--text2);font-size:16px;transition:all 0.15s;text-decoration:none}
.icon-btn:hover{background:var(--bg3);border-color:var(--border2);color:var(--text)}
.icon-btn.active{background:var(--accentbg);border-color:var(--accent);color:var(--accent)}

/* Section header */
.section-header{display:flex;align-items:center;justify-content:space-between;
  margin-bottom:12px}
.section-label{font-size:11px;font-weight:600;letter-spacing:0.1em;
  color:var(--text3);text-transform:uppercase}
.section-action{font-size:12px;color:var(--accent);cursor:pointer;
  padding:4px 10px;border-radius:var(--r8);border:1px solid var(--border)}
.section-action:hover{background:var(--accentbg)}

/* Master card (accordion) */
.master-card{background:var(--bg2);border-radius:var(--r16);
  border:1px solid var(--border);margin-bottom:10px;overflow:hidden;
  transition:border-color 0.2s}
.master-card:hover{border-color:var(--border2)}
.master-card.offline{opacity:0.5}
.master-header{display:flex;align-items:center;justify-content:space-between;
  padding:14px 16px;cursor:pointer;user-select:none}
.master-header-left{display:flex;align-items:center;gap:10px}
.master-icon{width:32px;height:32px;border-radius:var(--r8);
  display:flex;align-items:center;justify-content:center;font-size:15px;
  flex-shrink:0}
.master-icon.self{background:var(--accentbg);color:var(--accent)}
.master-icon.peer{background:var(--bg3);color:var(--text2)}
.master-info{}
.master-name{font-size:14px;font-weight:500;color:var(--text)}
.master-meta{font-size:11px;color:var(--text3);margin-top:1px}
.master-header-right{display:flex;align-items:center;gap:8px}
.status-pill{font-size:10px;font-weight:600;padding:3px 8px;border-radius:20px;
  letter-spacing:0.05em}
.pill-self{background:var(--accentbg);color:var(--accent2)}
.pill-online{background:var(--greenbg);color:var(--green)}
.pill-offline{background:var(--redbg);color:var(--red)}
.chevron{color:var(--text3);font-size:12px;transition:transform 0.25s;margin-left:2px}
.chevron.open{transform:rotate(90deg)}

/* Switch grid */
.master-body{display:none;padding:0 12px 14px}
.master-body.open{display:block}
.sw-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}

/* Switch card */
.sw-card{background:var(--bg3);border-radius:var(--r12);padding:14px;
  border:1px solid var(--border);position:relative;
  border-left:3px solid var(--border);transition:border-color 0.2s,opacity 0.2s}
.sw-card.offline{opacity:0.4;pointer-events:none}
.sw-card.reorder{border-style:dashed}
.sw-name{font-size:12px;font-weight:500;color:var(--text2);margin-bottom:10px;
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis;
  display:flex;align-items:center;justify-content:space-between}
.sw-menu-btn{background:none;border:none;color:var(--text3);cursor:pointer;
  font-size:16px;padding:0;line-height:1;flex-shrink:0;margin-left:4px}
.sw-menu-btn:hover{color:var(--text)}
.sw-dropdown{position:absolute;right:10px;top:36px;background:var(--bg4);
  border:1px solid var(--border2);border-radius:var(--r12);min-width:130px;
  z-index:20;overflow:hidden;display:none;box-shadow:0 8px 24px #00000040}
.sw-dropdown.show{display:block}
.sw-dropdown-item{padding:10px 14px;font-size:13px;cursor:pointer;color:var(--text)}
.sw-dropdown-item:hover{background:var(--bg3)}
.sw-dropdown-item.danger{color:var(--red)}

/* Toggle button */
.toggle{width:100%;padding:11px 0;border:none;border-radius:var(--r8);
  font-size:13px;font-weight:600;cursor:pointer;transition:all 0.15s;
  position:relative;letter-spacing:0.02em}
.toggle.on{background:var(--accent);color:#fff}
.toggle.on:active{background:var(--accent2)}
.toggle.off{background:var(--bg4);color:var(--text3);border:1px solid var(--border)}
.toggle.off:hover{background:var(--bg3);color:var(--text2)}
.toggle:active{transform:scale(0.97)}
.toggle:disabled{cursor:not-allowed;opacity:0.5;transform:none}
.toggle .spinner{display:none;width:13px;height:13px;border:2px solid rgba(255,255,255,0.2);
  border-top-color:#fff;border-radius:50%;animation:spin 0.5s linear infinite;margin:0 auto}
.toggle.loading .spinner{display:block}
.toggle.loading .lbl{display:none}

/* Move buttons */
.move-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:3px;margin-top:8px}
.move-btn{background:var(--bg4);border:1px solid var(--border);color:var(--text3);
  padding:5px;border-radius:6px;font-size:11px;cursor:pointer;text-align:center}
.move-btn:hover{background:var(--bg3);color:var(--text)}
.move-btn.blank{background:none;border:none;pointer-events:none}

/* Mesh action bar */
.mesh-bar{display:flex;justify-content:center;margin-top:6px;gap:8px}
.mesh-btn{font-size:12px;font-weight:500;padding:8px 16px;border-radius:var(--r8);
  cursor:pointer;border:1px solid var(--border);background:var(--bg2);
  color:var(--text2);transition:all 0.15s;display:flex;align-items:center;gap:6px}
.mesh-btn:hover{border-color:var(--border2);color:var(--text);background:var(--bg3)}
.mesh-btn.primary{border-color:var(--accent);color:var(--accent);background:var(--accentbg)}
.mesh-btn.primary:hover{background:var(--accent);color:#fff}

/* Empty state */
.empty-state{text-align:center;padding:32px 16px}
.empty-icon{font-size:32px;color:var(--text3);margin-bottom:10px}
.empty-title{font-size:15px;font-weight:500;color:var(--text2);margin-bottom:6px}
.empty-sub{font-size:13px;color:var(--text3)}

/* Boot overlay */
.boot-overlay{display:none;position:fixed;inset:0;background:#0a0a0fcc;
  backdrop-filter:blur(12px);z-index:200;align-items:center;
  justify-content:center;flex-direction:column;gap:16px}
.boot-overlay.show{display:flex}
.boot-ring{width:40px;height:40px;border:2px solid var(--border2);
  border-top-color:var(--accent);border-radius:50%;animation:spin 0.7s linear infinite}
.boot-text{font-size:13px;color:var(--text3);text-align:center}

/* Modals */
.overlay{display:none;position:fixed;inset:0;background:#00000080;
  z-index:100;align-items:flex-end;justify-content:center;padding:0}
.overlay.show{display:flex}
.sheet{background:var(--bg2);border-radius:var(--r20) var(--r20) 0 0;
  padding:24px 20px 40px;width:100%;max-width:480px;
  border-top:1px solid var(--border);max-height:85vh;overflow-y:auto}
.sheet-handle{width:36px;height:4px;background:var(--border2);
  border-radius:2px;margin:0 auto 20px;display:block}
.sheet h2{font-size:17px;font-weight:600;color:var(--text);margin-bottom:4px}
.sheet .subtitle{font-size:13px;color:var(--text3);margin-bottom:20px}
.sheet-input{width:100%;padding:12px 14px;background:var(--bg3);
  border:1px solid var(--border);border-radius:var(--r12);color:var(--text);
  font-size:15px;outline:none;font-family:inherit;margin-bottom:12px;
  transition:border-color 0.15s}
.sheet-input:focus{border-color:var(--accent)}
.sheet-select{width:100%;padding:12px 14px;background:var(--bg3);
  border:1px solid var(--border);border-radius:var(--r12);color:var(--text);
  font-size:13px;outline:none;font-family:inherit;margin-bottom:10px}
.btn-row{display:flex;gap:10px}
.btn{flex:1;padding:12px;border:none;border-radius:var(--r12);
  font-size:14px;font-weight:600;cursor:pointer;font-family:inherit}
.btn.primary{background:var(--accent);color:#fff}
.btn.primary:hover{background:var(--accent2)}
.btn.ghost{background:var(--bg3);color:var(--text2);border:1px solid var(--border)}
.btn.ghost:hover{background:var(--bg4);color:var(--text)}
.btn.danger{background:var(--redbg);color:var(--red);border:1px solid var(--red)30}

/* Ext item in batch modal */
.ext-item{background:var(--bg3);border-radius:var(--r12);padding:14px;
  margin-bottom:10px;border:1px solid var(--border)}
.ext-uid{font-family:monospace;font-size:10px;color:var(--text3);margin-bottom:10px}
.sw-inputs{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:10px}
.sw-inputs label{font-size:11px;color:var(--text3);margin-bottom:4px;display:block;
  font-weight:500;text-transform:uppercase;letter-spacing:0.06em}
.ext-actions{display:flex;gap:8px;margin-top:10px}

/* PIN display */
.pin-display{font-size:40px;font-weight:700;letter-spacing:10px;
  color:var(--accent);text-align:center;padding:20px 0;font-family:monospace}
.pin-timer{font-size:12px;color:var(--text3);text-align:center}
.pin-bar{height:3px;background:var(--border);border-radius:2px;
  margin-top:12px;overflow:hidden}
.pin-fill{height:100%;background:var(--accent);border-radius:2px;
  transition:width 1s linear}

/* Scan button animation */
@keyframes spin{to{transform:rotate(360deg)}}
@keyframes scan-pulse{0%,100%{opacity:1;transform:scale(1)}
  50%{opacity:0.6;transform:scale(0.95)}}
.scanning{animation:scan-pulse 1s ease-in-out infinite}
</style>
</head>
<body>
<div class="app">

<!-- Boot overlay -->
<div class="boot-overlay" id="boot-overlay">
  <div class="boot-ring"></div>
  <div class="boot-text">Connecting to switches</div>
</div>

<!-- Batch modal (bottom sheet) -->
<div class="overlay" id="batch-overlay">
  <div class="sheet">
    <span class="sheet-handle"></span>
    <h2>New extensions found</h2>
    <div class="subtitle" id="batch-subtitle"></div>
    <div id="batch-list"></div>
    <button class="btn ghost" onclick="closeBatchModal()" style="width:100%;margin-top:4px">Done</button>
  </div>
</div>

<!-- Rename modal -->
<div class="overlay" id="rename-overlay">
  <div class="sheet">
    <span class="sheet-handle"></span>
    <h2 id="rename-title">Rename</h2>
    <input class="sheet-input" id="rename-input" type="text" maxlength="23"/>
    <div class="btn-row">
      <button class="btn ghost" onclick="closeRenameModal()">Cancel</button>
      <button class="btn primary" onclick="submitRename()">Save</button>
    </div>
  </div>
</div>

<!-- Mesh PIN modal -->
<div class="overlay" id="pin-overlay">
  <div class="sheet">
    <span class="sheet-handle"></span>
    <h2>Invite new master</h2>
    <div class="subtitle">On the new master go to Settings &gt; Mesh &gt; Join and enter these details</div>
    <div style="margin-bottom:14px">
      <div style="font-size:10px;font-weight:600;letter-spacing:0.1em;color:var(--text3);text-transform:uppercase;margin-bottom:6px">PIN</div>
      <div style="display:flex;align-items:center;gap:10px">
        <div style="font-size:34px;font-weight:700;letter-spacing:8px;color:var(--accent);font-family:monospace;flex:1" id="pin-display">------</div>
        <button class="btn ghost" onclick="copyPin()" id="copy-pin-btn" style="flex:none;padding:8px 14px;font-size:12px">Copy</button>
      </div>
    </div>
    <div style="margin-bottom:14px">
      <div style="font-size:10px;font-weight:600;letter-spacing:0.1em;color:var(--text3);text-transform:uppercase;margin-bottom:6px">This master MAC</div>
      <div style="display:flex;align-items:center;gap:10px">
        <div style="font-size:14px;font-weight:600;letter-spacing:2px;color:var(--text2);font-family:monospace;flex:1" id="pin-mac">------------</div>
        <button class="btn ghost" onclick="copyMac()" id="copy-mac-btn" style="flex:none;padding:8px 14px;font-size:12px">Copy</button>
      </div>
    </div>
    <div class="pin-timer" id="pin-timer">Valid for 5m 0s</div>
    <div class="pin-bar" style="margin-bottom:16px"><div class="pin-fill" id="pin-fill" style="width:100%"></div></div>
    <div style="margin-bottom:12px">
      <div style="font-size:10px;font-weight:600;letter-spacing:0.1em;color:var(--text3);text-transform:uppercase;margin-bottom:6px">Join link for new master</div>
      <div style="font-size:11px;color:var(--text2);background:var(--bg3);border:1px solid var(--border2);border-radius:8px;padding:10px;font-family:monospace;word-break:break-all;margin-bottom:8px" id="join-link-display">--</div>
      <button class="btn primary" onclick="copyJoinLink()" id="copy-link-btn" style="width:100%">Copy join link</button>
    </div>
    <div style="font-size:11px;color:var(--text3);margin-bottom:12px;line-height:1.6">
      1. Copy the link above<br>
      2. Switch WiFi to new master (Unisync-XXYY)<br>
      3. Paste link in browser   PIN and MAC auto-fill
    </div>
    <button class="btn ghost" onclick="closePinModal()" style="width:100%">Close</button>
  </div>
</div>
<!-- Topbar -->
<div class="topbar">
  <div class="topbar-left">
    <div class="app-name">Unisync</div>
    <div class="master-title" onclick="renameMaster()">
      <span id="master-title-text">Master 1</span>
      <span class="edit-icon">&#9998;</span>
    </div>
    <div class="conn-row">
      <div class="conn-dot" id="conn-dot"></div>
      <span class="conn-label" id="conn-label">Connecting...</span>
    </div>
  </div>
  <div class="topbar-actions">
    <button class="icon-btn" id="scan-btn" onclick="startScan()" title="Scan for extensions">
      &#9685;
    </button>
    <button class="icon-btn" id="reorder-btn" onclick="toggleReorder()" title="Reorder switches">
      &#8661;
    </button>
    <button class="icon-btn" id="save-btn" onclick="saveOrder()"
      style="display:none;border-color:#6366f1;color:#6366f1" title="Save order">&#10003;</button>
    <button class="icon-btn" id="cancel-btn" onclick="cancelReorder()"
      style="display:none" title="Cancel">&#10005;</button>
    <a href="/settings" class="icon-btn" title="Settings">&#9881;</a>
  </div>
</div>

<!-- Main content -->
<div id="root"></div>

</div>

<script>
var ws,reconnTimer=null;
var allData={};
var reorderMode=false,reorderList=[];
var expandedMaster=null;
var renameTarget=null,renameType=null;
var pendingToggles={};
var pinTimer=null,pinInterval=null;
var currentPin='';

document.addEventListener('click',function(e){
  if(!e.target.closest('.sw-card'))
    document.querySelectorAll('.sw-dropdown.show')
      .forEach(function(d){d.classList.remove('show');});
});

function uptime(s){
  if(s<60)return s+'s';
  if(s<3600)return Math.floor(s/60)+'m';
  return Math.floor(s/3600)+'h '+Math.floor((s%3600)/60)+'m';
}

function swCard(sw,idx,isMesh,mUid){
  var off=!sw.online;
  var key=sw.id+'_'+mUid;
  var menu='';
  if(!reorderMode)
    menu='<button class="sw-menu-btn" onclick="swMenu(\''+key+'\',event)">&#8942;</button>'+
      '<div class="sw-dropdown" id="drop-'+key+'">'+
        '<div class="sw-dropdown-item" onclick="renameSw(\''+sw.id+'\',\''+
          sw.name.replace(/'/g,"\\'")+'\''+(isMesh?(',\''+mUid+'\''):'')+')">Rename</div>'+
      '</div>';
  var clickFn=isMesh?
    'meshToggle(\''+mUid+'\',\''+sw.id+'\','+sw.ch+')':
    'localToggle(\''+sw.id+'\')';
  var moves='';
  if(reorderMode&&!isMesh)
    moves='<div class="move-grid">'+
      '<div class="move-btn blank"></div>'+
      '<div class="move-btn" onclick="mUp('+idx+')">&#8593;</div>'+
      '<div class="move-btn blank"></div>'+
      '<div class="move-btn" onclick="mLeft('+idx+')">&#8592;</div>'+
      '<div class="move-btn blank"></div>'+
      '<div class="move-btn" onclick="mRight('+idx+')">&#8594;</div>'+
      '<div class="move-btn blank"></div>'+
      '<div class="move-btn" onclick="mDown('+idx+')">&#8595;</div>'+
      '<div class="move-btn blank"></div></div>';
  return '<div class="sw-card'+(off?' offline':'')+(reorderMode?' reorder':'')+
    '" style="border-left-color:'+(sw.color||'#444')+'">'+
    '<div class="sw-name">'+
      '<span style="overflow:hidden;text-overflow:ellipsis">'+sw.name+'</span>'+
      menu+
    '</div>'+
    '<button class="toggle '+(sw.state?'on':'off')+'" id="btn-'+key+'"'+
      ((off||reorderMode)?' disabled':'')+' onclick="'+clickFn+'">'+
      '<span class="lbl">'+(sw.state?'ON':'OFF')+'</span>'+
      '<div class="spinner"></div>'+
    '</button>'+moves+
  '</div>';
}

function render(d){
  allData=d;
  document.getElementById('boot-overlay').classList.toggle('show',!d.boot_complete);
  document.getElementById('master-title-text').textContent=d.master_name||'Master 1';
  document.getElementById('scan-btn').classList.toggle('scanning',!!d.scan_active);

  var sws=d.switches||[];
  sws.forEach(function(sw){ confirmToggle(sw.id+'_'+d.self_uid,sw.state); });

  if(!expandedMaster) expandedMaster=d.self_uid;

  /* Build sections */
  var secs=[];
  var localSws=reorderMode?reorderList:sws;
  var localBody='';
  if(!localSws.length)
    localBody='<div class="empty-state">'+
      '<div class="empty-icon">&#9711;</div>'+
      '<div class="empty-title">No switches yet</div>'+
      '<div class="empty-sub">Tap the scan button to find extensions</div></div>';
  else {
    var g='';
    localSws.forEach(function(sw,i){
      if(!sw||!sw.id||!sw.name)return;
      g+=swCard(sw,i,false,d.self_uid);
    });
    localBody='<div class="sw-grid">'+g+'</div>';
  }
  secs.push({uid:d.self_uid,name:d.master_name||'Master 1',
    online:true,isSelf:true,count:sws.length,body:localBody});

  var peers=(d.mesh_peers||[]).filter(function(p){return p.name&&p.name.length>0;})
    .sort(function(a,b){return a.name.localeCompare(b.name);});
  peers.forEach(function(p){
    var pb='';
    if(!p.online) pb='<div class="empty-state" style="padding:20px">'+
      '<div class="empty-sub">This master is offline</div></div>';
    else {
      var pg='';
      (p.switches||[]).forEach(function(sw,i){
        confirmToggle(sw.id+'_'+p.uid,sw.state);
        pg+=swCard(sw,i,true,p.uid);
      });
      pb='<div class="sw-grid">'+pg+'</div>';
    }
    secs.push({uid:p.uid,name:p.name,online:p.online,
      isSelf:false,count:(p.switches||[]).length,body:pb});
  });

  /* Render sections */
  var html='';

  if(secs.length>1){
    var lbl='<div class="section-header">'+
      '<span class="section-label">Boards</span></div>';
    html+=lbl;
  }

  secs.forEach(function(sec){
    var open=(sec.uid===expandedMaster);
    var pill=sec.isSelf?
      '<span class="status-pill pill-self">Here</span>':
      (sec.online?'<span class="status-pill pill-online">Online</span>':
        '<span class="status-pill pill-offline">Offline</span>');
    var icon=sec.isSelf?
      '<div class="master-icon self">&#9670;</div>':
      '<div class="master-icon peer">&#9671;</div>';
    html+='<div class="master-card'+((!sec.online&&!sec.isSelf)?' offline':'')+'">'+
      '<div class="master-header" onclick="toggleAcc(\''+sec.uid+'\')">'+
        '<div class="master-header-left">'+
          icon+
          '<div class="master-info">'+
            '<div class="master-name">'+sec.name+'</div>'+
            '<div class="master-meta">'+sec.count+' switch'+(sec.count!==1?'es':'')+'</div>'+
          '</div>'+
        '</div>'+
        '<div class="master-header-right">'+
          pill+
          '<span class="chevron'+(open?' open':'')+'" id="chv-'+sec.uid+'">&#9654;</span>'+
        '</div>'+
      '</div>'+
      '<div class="master-body'+(open?' open':'')+'" id="body-'+sec.uid+'">'+
        sec.body+
      '</div>'+
    '</div>';
  });

  /* Mesh action */
  html+='<div class="mesh-bar">';
  if(d.mesh_active)
    html+='<button class="mesh-btn primary" onclick="showInvite()">'+
      '&#10010; Invite master</button>';
  else
    html+='<button class="mesh-btn" onclick="createMesh()">'+
      '&#9670; Create mesh</button>';
  html+='</div>';

  document.getElementById('root').innerHTML=html;

  /* Batch modal */
  var pend=d.pending||[];
  var bov=document.getElementById('batch-overlay');
  if(pend.length>0&&!bov.classList.contains('show'))
    renderBatch(pend,d.offline_slots||[]);
  else if(pend.length===0)
    bov.classList.remove('show');
}

function toggleAcc(uid){
  if(reorderMode)return;
  expandedMaster=(expandedMaster===uid)?null:uid;
  document.querySelectorAll('.master-body').forEach(function(el){
    var id=el.id.replace('body-','');
    var open=(id===expandedMaster);
    el.classList.toggle('open',open);
    var c=document.getElementById('chv-'+id);
    if(c)c.classList.toggle('open',open);
  });
}

function localToggle(id){
  var uid=allData.self_uid||'';
  var k=id+'_'+uid;
  var btn=document.getElementById('btn-'+k);
  if(!btn||btn.disabled)return;
  var on=btn.classList.contains('on');
  btn.classList.remove('on','off');btn.classList.add(on?'off':'on','loading');
  btn.querySelector('.lbl').textContent=on?'OFF':'ON';
  btn.disabled=true;
  var t=setTimeout(function(){
    btn.classList.remove('loading');btn.classList.remove(on?'off':'on');
    btn.classList.add(on?'on':'off');
    btn.querySelector('.lbl').textContent=on?'ON':'OFF';
    btn.disabled=false;delete pendingToggles[k];
  },1000);
  pendingToggles[k]={t:t,exp:!on};
  var ch=id.split('_')[1];
  fetch('/api/relay?id='+id+'&ch='+ch,{method:'POST'}).catch(function(){
    clearTimeout(t);btn.classList.remove('loading');
    btn.classList.remove(on?'off':'on');btn.classList.add(on?'on':'off');
    btn.querySelector('.lbl').textContent=on?'ON':'OFF';
    btn.disabled=false;delete pendingToggles[k];
  });
}

function meshToggle(pUid,swId,ch){
  var k=swId+'_'+pUid;
  var btn=document.getElementById('btn-'+k);
  if(!btn||btn.disabled)return;
  var on=btn.classList.contains('on');
  btn.classList.remove('on','off');btn.classList.add(on?'off':'on','loading');
  btn.querySelector('.lbl').textContent=on?'OFF':'ON';
  btn.disabled=true;
  var t=setTimeout(function(){
    btn.classList.remove('loading');btn.classList.remove(on?'off':'on');
    btn.classList.add(on?'on':'off');
    btn.querySelector('.lbl').textContent=on?'ON':'OFF';
    btn.disabled=false;delete pendingToggles[k];
  },1000);
  pendingToggles[k]={t:t,exp:!on};
  fetch('/api/mesh/relay?peer_uid='+pUid+'&sw_id='+swId+'&ch='+ch,{method:'POST'}).catch(function(){
    clearTimeout(t);btn.classList.remove('loading');
    btn.classList.remove(on?'off':'on');btn.classList.add(on?'on':'off');
    btn.querySelector('.lbl').textContent=on?'ON':'OFF';
    btn.disabled=false;delete pendingToggles[k];
  });
}

function confirmToggle(k,actual){
  if(!pendingToggles[k])return;
  clearTimeout(pendingToggles[k].t);
  var btn=document.getElementById('btn-'+k);
  if(btn){
    btn.classList.remove('loading','on','off');
    btn.classList.add(actual?'on':'off');
    btn.querySelector('.lbl').textContent=actual?'ON':'OFF';
    btn.disabled=false;
  }
  delete pendingToggles[k];
}

/* Reorder */
function toggleReorder(){
  reorderMode=true;reorderList=(allData.switches||[]).slice();
  if(!expandedMaster)expandedMaster=allData.self_uid;
  document.getElementById('reorder-btn').style.display='none';
  document.getElementById('save-btn').style.display='flex';
  document.getElementById('cancel-btn').style.display='flex';
  render(allData);
}
function cancelReorder(){
  reorderMode=false;reorderList=[];
  document.getElementById('reorder-btn').style.display='flex';
  document.getElementById('save-btn').style.display='none';
  document.getElementById('cancel-btn').style.display='none';
  render(allData);
}
function swap(a,i,j){if(i<0||j<0||i>=a.length||j>=a.length)return false;
  var t=a[i];a[i]=a[j];a[j]=t;return true;}
function mUp(i){if(swap(reorderList,i,i-2))render(allData);}
function mDown(i){if(swap(reorderList,i,i+2))render(allData);}
function mLeft(i){if(swap(reorderList,i,i-1))render(allData);}
function mRight(i){if(swap(reorderList,i,i+1))render(allData);}
async function saveOrder(){
  var order=reorderList.map(function(s){return s.id;}).join(',');
  await fetch('/api/switch/reorder',{method:'POST',
    headers:{'Content-Type':'text/plain'},body:order});
  reorderMode=false;
  document.getElementById('reorder-btn').style.display='flex';
  document.getElementById('save-btn').style.display='none';
  document.getElementById('cancel-btn').style.display='none';
  render(allData);
}

/* Menus */
function swMenu(key,e){
  e.stopPropagation();
  var d=document.getElementById('drop-'+key);
  var was=d.classList.contains('show');
  document.querySelectorAll('.sw-dropdown.show').forEach(function(x){x.classList.remove('show');});
  if(!was)d.classList.add('show');
}

/* Rename */
function renameMaster(){
  renameTarget=null;renameType='master';
  document.getElementById('rename-title').textContent='Rename board';
  document.getElementById('rename-input').value=
    document.getElementById('master-title-text').textContent;
  document.getElementById('rename-overlay').classList.add('show');
  setTimeout(function(){document.getElementById('rename-input').focus();},200);
}
function renameSw(id,cur,pUid){
  document.querySelectorAll('.sw-dropdown.show').forEach(function(d){d.classList.remove('show');});
  renameTarget={id:id,pUid:pUid||null};renameType='switch';
  document.getElementById('rename-title').textContent='Rename switch';
  document.getElementById('rename-input').value=cur;
  document.getElementById('rename-overlay').classList.add('show');
  setTimeout(function(){document.getElementById('rename-input').focus();},200);
}
function closeRenameModal(){
  document.getElementById('rename-overlay').classList.remove('show');
  renameTarget=null;renameType=null;
}
async function submitRename(){
  var name=document.getElementById('rename-input').value.trim();
  if(!name)return;
  if(renameType==='master'){
    await fetch('/api/master/rename?name='+encodeURIComponent(name),{method:'POST'});
    document.getElementById('master-title-text').textContent=name;
  } else {
    await fetch('/api/switch/rename?id='+renameTarget.id+
      '&name='+encodeURIComponent(name),{method:'POST'});
  }
  closeRenameModal();
}

/* Scan */
async function startScan(){await fetch('/api/scan',{method:'POST'});}

/* Mesh */
async function createMesh(){
  if(!confirm('Create a new mesh with this as the first board?'))return;
  await fetch('/api/mesh/create',{method:'POST'});
}
async function showInvite(){
  var r=await fetch('/api/mesh/invite',{method:'POST'});
  var d=await r.json();
  currentPin=d.pin;
  document.getElementById('pin-display').textContent=d.pin;
  document.getElementById('pin-mac').textContent=d.mac||'--';
  document.getElementById('pin-overlay').classList.add('show');
  var rem=300;
  document.getElementById('pin-fill').style.width='100%';
  document.getElementById('pin-timer').textContent='Valid for 5m 0s';
  /* Build join link */
  var joinMac=d.mac||'';
  var joinUrl='http://192.168.4.1/settings?pin='+d.pin+'&mac='+joinMac;
  var linkEl=document.getElementById('join-link-display');
  if(linkEl) linkEl.textContent=joinUrl;
  /* Also update mac display */
  var macEl=document.getElementById('pin-mac');
  if(macEl&&joinMac) macEl.textContent=joinMac;
  if(pinInterval)clearInterval(pinInterval);
  pinInterval=setInterval(function(){
    rem--;
    var mins=Math.floor(rem/60),secs=rem%60;
    document.getElementById('pin-timer').textContent=
      'Valid for '+(mins>0?mins+'m ':'')+secs+'s';
    document.getElementById('pin-fill').style.width=(rem/300*100)+'%';
    if(rem<=0){clearInterval(pinInterval);
      document.getElementById('pin-overlay').classList.remove('show');}
  },1000);
}
async function createMesh(){
  if(!confirm('Create a new mesh with this as the first board?'))return;
  await fetch('/api/mesh/create',{method:'POST'});
}

function copyToClip(text,btnId,label){
  function done(){var btn=document.getElementById(btnId);
    if(btn){btn.textContent='Copied!';setTimeout(function(){btn.textContent=label;},2000);}}
  if(navigator.clipboard){navigator.clipboard.writeText(text).then(done);}
  else{var ta=document.createElement('textarea');ta.value=text;
    ta.style.cssText='position:fixed;opacity:0';document.body.appendChild(ta);
    ta.select();document.execCommand('copy');document.body.removeChild(ta);done();}
}
function copyPin(){
  var p=document.getElementById('pin-display').textContent.trim();
  if(p==='------')return;copyToClip(p,'copy-pin-btn','Copy');
}
function copyMac(){
  var m=document.getElementById('pin-mac').textContent.trim();
  if(!m)return;
  copyToClip(m,'copy-mac-btn','Copy');
}
function copyJoinLink(){
  var link=document.getElementById('join-link-display');
  if(!link)return;
  var txt=link.textContent.trim();
  if(!txt||txt==='--'||txt===''){
    /* Fallback: rebuild from displayed PIN and MAC */
    var pin=document.getElementById('pin-display').textContent.trim();
    var mac=document.getElementById('pin-mac').textContent.trim();
    txt='http://192.168.4.1/settings?pin='+pin+'&mac='+mac;
    link.textContent=txt;
  }
  copyToClip(txt,'copy-link-btn','Copy join link');
}
function closePinModal(){
  document.getElementById('pin-overlay').classList.remove('show');
  if(pinInterval)clearInterval(pinInterval);
  currentPin='';
}

/* Batch modal */
function renderBatch(pend,offSlots){
  var list=document.getElementById('batch-list');
  document.getElementById('batch-subtitle').textContent=
    pend.length+' new extension'+(pend.length>1?'s':'')+' found';
  list.innerHTML=pend.map(function(p){
    var opts=offSlots.map(function(s){
      return '<option value="replace:'+s.slot+'">Replace slot '+(s.slot+1)+'</option>';
    }).join('');
    return '<div class="ext-item">'+
      '<div class="ext-uid">'+p.uid+'</div>'+
      '<div class="sw-inputs">'+
        '<div><label>Switch 1</label>'+
          '<input class="sheet-input" id="sw1-'+p.uid+'" '+
            'style="margin:0" type="text" placeholder="Living room light" maxlength="23"/></div>'+
        '<div><label>Switch 2</label>'+
          '<input class="sheet-input" id="sw2-'+p.uid+'" '+
            'style="margin:0" type="text" placeholder="Bedroom fan" maxlength="23"/></div>'+
      '</div>'+
      '<select class="sheet-select" id="act-'+p.uid+'">'+
        '<option value="new">Add as new</option>'+opts+'</select>'+
      '<div class="ext-actions">'+
        '<button class="btn danger" onclick="ignoreExt(\''+p.uid+'\')">Ignore</button>'+
        '<button class="btn primary" onclick="assignExt(\''+p.uid+'\')">Add</button>'+
      '</div>'+
    '</div>';
  }).join('');
  document.getElementById('batch-overlay').classList.add('show');
}
function closeBatchModal(){document.getElementById('batch-overlay').classList.remove('show');}
async function assignExt(uid){
  var sw1=document.getElementById('sw1-'+uid).value.trim()||'Switch';
  var sw2=document.getElementById('sw2-'+uid).value.trim()||'Switch';
  var act=document.getElementById('act-'+uid).value;
  var slot=-1;
  if(act.startsWith('replace:')){
    slot=parseInt(act.split(':')[1]);
    if(!confirm('Replace offline slot '+(slot+1)+'?'))return;
    await fetch('/api/replace?uid='+uid+'&slot='+slot,{method:'POST'});
  } else {
    var r=await fetch('/api/assign?uid='+uid,{method:'POST'});
    var d=await r.json();slot=d.slot!==undefined?d.slot:-1;
  }
  if(slot>=0){
    await fetch('/api/switch/rename?id=ext'+slot+'_1&name='+encodeURIComponent(sw1),{method:'POST'});
    await fetch('/api/switch/rename?id=ext'+slot+'_2&name='+encodeURIComponent(sw2),{method:'POST'});
  }
  var pd=(allData.pending||[]).filter(function(p){return p.uid!==uid;});
  if(pd.length===0)closeBatchModal();else renderBatch(pd,allData.offline_slots||[]);
}
async function ignoreExt(uid){
  await fetch('/api/reject?uid='+uid,{method:'POST'});
  var pd=(allData.pending||[]).filter(function(p){return p.uid!==uid;});
  if(pd.length===0)closeBatchModal();else renderBatch(pd,allData.offline_slots||[]);
}

/* WebSocket */
function connect(){
  if(reconnTimer){clearTimeout(reconnTimer);reconnTimer=null;}
  ws=new WebSocket('ws://192.168.4.1:81');
  ws.onopen=function(){
    document.getElementById('conn-dot').classList.add('on');
    document.getElementById('conn-label').textContent='192.168.4.1';
    document.getElementById('boot-overlay').classList.add('show');
  };
  ws.onmessage=function(e){
    try{render(JSON.parse(e.data));}
    catch(err){console.error('Render:',err);}
  };
  ws.onclose=function(){
    document.getElementById('conn-dot').classList.remove('on');
    document.getElementById('conn-label').textContent='Reconnecting...';
    reconnTimer=setTimeout(connect,2000);
  };
  ws.onerror=function(){ws.close();};
}
connect();
</script>
</body>
</html>
)MAINHTML";
