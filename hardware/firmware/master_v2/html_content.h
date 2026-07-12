#pragma once
// Auto-generated - do not edit directly

static const char SETTINGS_HTML[] PROGMEM = R"SETHTML(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<title>Settings - Unisync</title>
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
  font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',system-ui,sans-serif;min-height:100vh;font-size:15px}
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
  font-weight:600;cursor:pointer;font-family:inherit;
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
.field-label{font-size:10px;font-weight:600;letter-spacing:0.1em;color:var(--text3);text-transform:uppercase;display:block;margin-bottom:6px}
.mesh-status.inactive{background:var(--bg3);color:var(--text3)}
.sheet-input{width:100%;background:var(--bg3);border:1.5px solid var(--border2);border-radius:10px;color:var(--text);font-size:16px;padding:12px 14px;margin-bottom:14px;outline:none;box-sizing:border-box;letter-spacing:normal;-webkit-appearance:none}
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

    <!-- When IN mesh: rename + password + leave -->
    <div id="mesh-active-section" style="display:none">

      <div style="margin-bottom:14px">
        <label class="field-label">Mesh name (WiFi network name)</label>
        <input class="sheet-input" id="mesh-name-edit" type="text"
               maxlength="31" placeholder="Mesh name" style="width:100%;margin-bottom:8px"/>
        <button class="btn primary" onclick="renameMeshNetwork()"
                style="width:100%">Save</button>
        <div id="rename-mesh-msg" style="font-size:11px;margin-top:6px"></div>
      </div>

      <div style="margin-bottom:14px">
        <label class="field-label">Current WiFi password</label>
        <div style="display:flex;gap:8px;align-items:center">
          <input class="sheet-input" id="mesh-pass-old" type="password"
                 maxlength="63" placeholder="Current password"
                 style="margin:0;flex:1;letter-spacing:normal;border:none;cursor:pointer;
                         color:var(--text3);padding:0 6px;font-size:18px"
                  id="eye-old">&#128065;</button>
        </div>
        <label class="field-label" style="margin-top:10px">New WiFi password (min 8 chars)</label>
        <div style="display:flex;gap:8px;align-items:center">
          <input class="sheet-input" id="mesh-pass-new" type="password"
                 maxlength="63" placeholder="New password"
                 style="margin:0;flex:1;letter-spacing:normal;border:none;cursor:pointer;
                         color:var(--text3);padding:0 6px;font-size:18px"
                  id="eye-new">&#128065;</button>
        </div>
        <button class="btn primary" onclick="changeMeshPass()"
                style="width:100%;margin-top:10px">Change password on all masters</button>
        <div id="change-pass-msg" style="font-size:11px;margin-top:6px"></div>
      </div>

      <button class="btn danger" onclick="leaveMesh()" style="width:100%">Leave mesh</button>
    </div>

    <!-- When NOT in mesh: instruction only -->
    <div id="mesh-inactive-section">
      <p style="font-size:13px;color:var(--text3);line-height:1.6">
        Open the main screen on an existing mesh master and tap
        <b style="color:var(--text)">+ Invite Master</b>.
        Follow the steps   you will be directed here automatically.
      </p>
    </div>

    <div class="status" id="mesh-msg" style="margin-top:8px"></div>
  </div>

<script>
var selFile=null;

function toggleVis(inputId, btnId){
  var inp=document.getElementById(inputId);
  var btn=document.getElementById(btnId);
  if(inp.type==='password'){inp.type='text';btn.innerHTML='&#128683;';}
  else{inp.type='password';btn.innerHTML='&#128065;';}
}

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
      row('Firmware','v10.6')+
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
  fetch('/api/mesh/status').then(function(r){return r.json();}).then(function(d){
    var ms=document.getElementById('mesh-status');
    var as=document.getElementById('mesh-active-section');
    var is=document.getElementById('mesh-inactive-section');
    var ni=document.getElementById('mesh-name-edit');
    if(d.active){
      ms.className='mesh-status active';
      ms.textContent='In mesh - '+d.peer_count+
        ' peer'+(d.peer_count!==1?'s':'')+' online';
      as.style.display='block';
      is.style.display='none';
      if(ni&&d.mesh_name) ni.value=d.mesh_name;
    } else {
      ms.className='mesh-status inactive';
      ms.textContent='Not in any mesh';
      as.style.display='none';
      is.style.display='block';
    }
  });
}

async function renameMeshNetwork(){
  var name=document.getElementById('mesh-name-edit').value.trim();
  var msg=document.getElementById('rename-mesh-msg');
  if(!name){msg.innerHTML='<span style="color:var(--red)">Name required</span>';return;}
  msg.innerHTML='<span style="color:var(--text3)">Saving...</span>';
  var r=await fetch('/api/mesh/rename?name='+encodeURIComponent(name),{method:'POST'});
  var d=await r.json();
  if(d.ok){
    msg.innerHTML='<span style="color:var(--green)">Saved. WiFi name is now: '+name+'</span>';
    setTimeout(function(){msg.innerHTML='';},4000);
  } else {
    msg.innerHTML='<span style="color:var(--red)">Failed</span>';
  }
}

async function changeMeshPass(){
  var oldp=document.getElementById('mesh-pass-old').value;
  var newp=document.getElementById('mesh-pass-new').value;
  var msg=document.getElementById('change-pass-msg');
  if(oldp.length<8){msg.innerHTML='<span style="color:var(--red)">Enter current password</span>';return;}
  if(newp.length<8){msg.innerHTML='<span style="color:var(--red)">New password min 8 chars</span>';return;}
  msg.innerHTML='<span style="color:var(--text3)">Verifying and changing on all masters...</span>';
  var r=await fetch('/api/mesh/passwd?old='+encodeURIComponent(oldp)+
                    '&pass='+encodeURIComponent(newp),{method:'POST'});
  var d=await r.json();
  if(d.ok){
    msg.innerHTML='<span style="color:var(--green)">Done. Reconnect with new password.</span>';
    document.getElementById('mesh-pass-old').value='';
    document.getElementById('mesh-pass-new').value='';
  } else {
    msg.innerHTML='<span style="color:var(--red)">'+(d.error||'Failed')+'</span>';
  }
}

function leaveMesh(){
  if(!confirm('Leave mesh? This board will operate standalone.'))return;
  fetch('/api/mesh/leave',{method:'POST'}).then(function(){
    document.getElementById('mesh-msg').innerHTML='<span class="ok">Left mesh.</span>';
    loadMesh();
  });
}

loadInfo();
loadMesh();


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
html,body{background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',system-ui,sans-serif;
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
.edit-icon{opacity:0;color:var(--text3);transition:opacity 0.2s}
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
.master-name{font-weight:500;color:var(--text)}
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
.sheet-input{width:100%;background:var(--bg3);border:1.5px solid var(--border2);border-radius:10px;color:var(--text);font-size:16px;padding:12px 14px;margin-bottom:14px;outline:none;box-sizing:border-box;letter-spacing:normal;-webkit-appearance:none}
.sheet-input:focus{border-color:var(--accent)}
.sheet-select{width:100%;padding:12px 14px;background:var(--bg3);
  border:1px solid var(--border);border-radius:var(--r12);color:var(--text);
  font-size:13px;outline:none;font-family:inherit;margin-bottom:10px}
.btn-row{display:flex;gap:10px}
.btn{flex:1;padding:12px;border:none;border-radius:var(--r12);
  font-weight:600;cursor:pointer;font-family:inherit}
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

<!-- Create mesh modal -->
<div class="overlay" id="create-mesh-overlay">
  <div class="sheet">
    <span class="sheet-handle"></span>
    <h2>Create mesh network</h2>
    <div class="subtitle">This name becomes your WiFi network name. Use something unique to avoid conflicts with nearby Unisync installations.</div>
    <div style="background:var(--yellowbg);border:1px solid #f59e0b30;border-radius:8px;
         padding:10px 14px;margin-bottom:16px;font-size:12px;color:var(--yellow)">
      &#9888; Choose a unique name. If neighbours also use Unisync,
      same names will cause confusion.
    </div>
    <label style="font-size:10px;font-weight:600;letter-spacing:0.1em;
           color:var(--text3);text-transform:uppercase;display:block;margin-bottom:6px">
      Mesh name (becomes WiFi name)
    </label>
    <input class="sheet-input" id="mesh-name-input" type="text"
           maxlength="31" placeholder="e.g. Home, Office, Floor 2"/>
    <div id="create-mesh-err"
         style="font-size:11px;color:var(--red);margin-bottom:8px"></div>
    <div class="btn-row">
      <button class="btn ghost" onclick="closeCreateMesh()">Cancel</button>
      <button class="btn primary" id="create-mesh-btn"
              onclick="submitCreateMesh()">Create mesh</button>
    </div>
  </div>
</div>

<!-- Mesh invite modal -->
<div class="overlay" id="pin-overlay">
  <div class="sheet">
    <span class="sheet-handle"></span>
    <div id="invite-step-1">
      <h2>Add new master</h2>
      <div class="subtitle">Two steps to add a master to your mesh</div>
      <div style="display:flex;flex-direction:column;gap:14px;margin:20px 0">
        <div style="display:flex;gap:12px;align-items:flex-start">
          <div style="width:28px;height:28px;border-radius:50%;background:var(--accent);
               color:#fff;font-size:13px;font-weight:700;display:flex;align-items:center;
               justify-content:center;flex-shrink:0">1</div>
          <div>
            <div style="font-weight:500;color:var(--text)">Switch phone WiFi to the new master</div>
            <div style="font-size:13px;font-weight:700;color:var(--accent);
                 font-family:monospace;margin-top:4px" id="invite-target-ssid">Unisync-????</div>
            <div style="font-size:11px;color:var(--text3);margin-top:2px">Password: same as this mesh</div>
          </div>
        </div>
        <div style="display:flex;gap:12px;align-items:flex-start">
          <div style="width:28px;height:28px;border-radius:50%;background:var(--accent);
               color:#fff;font-size:13px;font-weight:700;display:flex;align-items:center;
               justify-content:center;flex-shrink:0">2</div>
          <div>
            <div style="font-weight:500;color:var(--text)">Come back to this tab and tap below</div>
            <div style="font-size:11px;color:var(--text3);margin-top:2px">Keep this tab open while switching</div>
          </div>
        </div>
      </div>
      <div class="pin-timer" id="pin-timer">Valid for 5m 0s</div>
      <div class="pin-bar" style="margin-bottom:16px">
        <div class="pin-fill" id="pin-fill" style="width:100%"></div>
      </div>
      <button class="btn primary" onclick="inviteStep2()" style="width:100%;margin-bottom:8px">I switched WiFi &mdash; Add to mesh &#8594;</button>
      <button class="btn ghost" onclick="closePinModal()" style="width:100%">Cancel</button>
    </div>
    <div id="invite-step-2" style="display:none">
      <h2>Adding master...</h2>
      <div class="subtitle" id="invite-status-msg">Connecting to new master</div>
      <div style="display:flex;justify-content:center;padding:32px 0">
        <div style="width:44px;height:44px;border:3px solid var(--border2);
             border-top-color:var(--accent);border-radius:50%;
             animation:spin 0.7s linear infinite"></div>
      </div>
      <button class="btn ghost" onclick="closePinModal()" style="width:100%">Cancel</button>
    </div>
    <div id="invite-step-3" style="display:none">
      <h2 id="invite-done-title">Master added!</h2>
      <div style="text-align:center;padding:24px 0">
        <div style="font-size:44px;margin-bottom:14px">&#10003;</div>
        <div style="font-size:13px;color:var(--text2);line-height:1.8" id="invite-done-msg">Switch back to your mesh WiFi to control all masters.</div>
      </div>
      <button class="btn primary" onclick="closePinModal()" style="width:100%">Done</button>
    </div>
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
function createMesh(){
  /* Show create mesh modal */
  document.getElementById('create-mesh-overlay').classList.add('show');
  setTimeout(function(){document.getElementById('mesh-name-input').focus();},200);
}

async function submitCreateMesh(){
  var name=document.getElementById('mesh-name-input').value.trim();
  if(!name){
    document.getElementById('create-mesh-err').textContent='Please enter a name.';
    return;
  }
  document.getElementById('create-mesh-err').textContent='';
  document.getElementById('create-mesh-btn').disabled=true;
  document.getElementById('create-mesh-btn').textContent='Creating...';
  await fetch('/api/mesh/create?name='+encodeURIComponent(name),{method:'POST'});
  document.getElementById('create-mesh-overlay').classList.remove('show');
  document.getElementById('create-mesh-btn').disabled=false;
  document.getElementById('create-mesh-btn').textContent='Create mesh';
  document.getElementById('mesh-name-input').value='';
}

function closeCreateMesh(){
  document.getElementById('create-mesh-overlay').classList.remove('show');
}
var invitePin='';
var inviteMac='';
var invitePollTimer=null;

async function showInvite(){
  var r=await fetch('/api/mesh/invite',{method:'POST'});
  var d=await r.json();
  invitePin=d.pin; inviteMac=d.mac||'';

  /* Derive new master SSID hint from our own MAC last 4 -- user needs to find it */
  var ssidEl=document.getElementById('invite-target-ssid');
  if(ssidEl) ssidEl.textContent='Unisync-XXYY (unique per board)';

  document.getElementById('invite-step-1').style.display='block';
  document.getElementById('invite-step-2').style.display='none';
  document.getElementById('invite-step-3').style.display='none';
  if(document.getElementById('invite-done-title'))
    document.getElementById('invite-done-title').style.color='';
  document.getElementById('pin-overlay').classList.add('show');

  var rem=300;
  document.getElementById('pin-fill').style.width='100%';
  document.getElementById('pin-timer').textContent='Valid for 5m 0s';
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

async function inviteStep2(){
  document.getElementById('invite-step-1').style.display='none';
  document.getElementById('invite-step-2').style.display='block';
  var msg=document.getElementById('invite-status-msg');
  msg.textContent='Calling new master at 192.168.4.1...';
  try {
    var url='/api/mesh/join?pin='+encodeURIComponent(invitePin)+
            '&mac='+encodeURIComponent(inviteMac);
    var r=await fetch(url,{method:'POST'});
    var d=await r.json();
    if(!r.ok){
      showInviteError(d.error||'Join failed. PIN may have expired.');
      return;
    }
    msg.textContent='Waiting for mesh handshake...';
    var attempts=0;
    invitePollTimer=setInterval(async function(){
      attempts++;
      try{
        var sr=await fetch('/api/mesh/status');
        var sd=await sr.json();
        if(sd.active){clearInterval(invitePollTimer);showInviteDone();}
      }catch(e){}
      if(attempts>25){clearInterval(invitePollTimer);
        showInviteError('Timed out. Make sure you switched to the new master WiFi.');}
    },2000);
  } catch(e){
    showInviteError('Could not reach new master. Did you switch WiFi?');
  }
}

function showInviteError(msg){
  clearInterval(invitePollTimer);
  document.getElementById('invite-step-2').style.display='none';
  document.getElementById('invite-step-3').style.display='block';
  document.getElementById('invite-done-title').textContent='Something went wrong';
  document.getElementById('invite-done-title').style.color='var(--red)';
  document.getElementById('invite-done-msg').textContent=msg;
}

function showInviteDone(){
  document.getElementById('invite-step-2').style.display='none';
  document.getElementById('invite-step-3').style.display='block';
  document.getElementById('invite-done-title').textContent='Master added!';
  document.getElementById('invite-done-title').style.color='var(--green)';
  var mn=(allData&&allData.mesh_name)||'your mesh';
  document.getElementById('invite-done-msg').innerHTML=
    'Switch back to <b style="color:var(--accent)">'+mn+
    '</b> WiFi to control all masters together.';
}

function closePinModal(){
  document.getElementById('pin-overlay').classList.remove('show');
  if(pinInterval)clearInterval(pinInterval);
  if(invitePollTimer)clearInterval(invitePollTimer);
  invitePin=''; inviteMac='';
  document.getElementById('invite-step-1').style.display='block';
  document.getElementById('invite-step-2').style.display='none';
  document.getElementById('invite-step-3').style.display='none';
}

function connectWS(){
  var host=location.hostname;
  ws=new WebSocket('ws://'+host+':81/ws');
  ws.onopen=function(){
    var dot=document.getElementById('conn-dot');
    var lbl=document.getElementById('conn-label');
    if(dot) dot.style.background='var(--green)';
    if(lbl) lbl.textContent='192.168.4.1';
  };
  ws.onmessage=function(e){
    try{render(JSON.parse(e.data));}catch(ex){console.error('render err',ex);}
  };
  ws.onclose=function(){
    var dot=document.getElementById('conn-dot');
    var lbl=document.getElementById('conn-label');
    if(dot) dot.style.background='var(--red)';
    if(lbl) lbl.textContent='Reconnecting...';
    clearTimeout(reconnTimer);
    reconnTimer=setTimeout(connectWS,2000);
  };
  ws.onerror=function(){ws.close();};
}
connectWS();
</script>
</body>
</html>
)MAINHTML";
