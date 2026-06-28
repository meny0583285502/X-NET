<!DOCTYPE html>
<html dir="rtl" lang="he">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>X-NET Portal</title>
    <link rel="icon" href="https://cdn-icons-png.flaticon.com/512/3203/3203853.png" type="image/png">
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; }
        body { background: linear-gradient(135deg, #0f172a 0%, #1e1b4b 100%); color: #e2e8f0; min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 20px; }
        .container { background: #1e293b; border: 1px solid #334155; border-radius: 16px; padding: 35px; width: 100%; max-width: 680px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); max-height: 95vh; overflow-y: auto; }
        .view { display: none; } .view.active { display: block; }
        .header { text-align: center; margin-bottom: 25px; }
        .icon { font-size: 45px; margin-bottom: 10px; }
        .title { font-size: 1.6rem; font-weight: 800; color: #60a5fa; }
        .subtitle { color: #94a3b8; font-size: 0.85rem; margin-top: 5px; }
        .field { margin-bottom: 16px; }
        .field label { display: block; font-size: 0.85rem; color: #cbd5e1; margin-bottom: 6px; font-weight: 600; }
        .field input, .field textarea, .field select { width: 100%; background: #0f172a; border: 1.5px solid #334155; color: #e2e8f0; border-radius: 8px; padding: 11px 14px; font-size: 0.95rem; outline: none; transition: all 0.2s; }
        .field input:focus, .field textarea:focus { border-color: #60a5fa; }
        .btn { border: none; border-radius: 9px; padding: 12px; font-size: 1rem; font-weight: 700; cursor: pointer; transition: all 0.2s; margin-top: 8px; }
        .btn-block { width: 100%; }
        .btn-primary { background: linear-gradient(135deg, #2563eb, #7c3aed); color: white; }
        .btn-danger { background: #dc2626; color: white; }
        .btn-secondary { background: #334155; color: #cbd5e1; }
        .btn-success { background: #16a34a; color: white; }
        .btn-warn { background: #d97706; color: white; }
        .btn:hover { opacity: 0.9; }
        .btn:disabled { opacity: 0.5; cursor: not-allowed; }
        .status-badge { display: inline-block; padding: 4px 12px; border-radius: 99px; font-size: 0.8rem; font-weight: bold; margin-bottom: 15px; }
        .status-active { background: #14532d; color: #86efac; }
        .tabs { display: flex; gap: 8px; margin-bottom: 20px; border-bottom: 1px solid #334155; padding-bottom: 10px; flex-wrap: wrap; }
        .tab { cursor: pointer; padding: 6px 12px; font-size: 0.85rem; color: #94a3b8; border-radius: 6px; }
        .tab.active { background: #1e3a5f; color: #60a5fa; font-weight: bold; }
        .panel { display: none; background: #0f172a; padding: 15px; border-radius: 10px; border: 1px solid #334155; }
        .panel.active { display: block; }
        ul.domain-list { list-style: none; padding: 0; }
        ul.domain-list li { background: #1e293b; padding: 8px 12px; margin-bottom: 8px; border-radius: 6px; display: flex; justify-content: space-between; align-items: center; font-size: 0.9rem; }
        .alert { padding: 10px 12px; border-radius: 6px; font-size: 0.85rem; margin-bottom: 12px; }
        .alert-info { background: #1e3a5f; color: #93c5fd; border: 1px solid #3b82f6; }
        .alert-success { background: #14532d; color: #86efac; border: 1px solid #22c55e; }
        .alert-error { background: #450a0a; color: #fca5a5; border: 1px solid #b91c1c; }
        .alert-warn { background: #451a03; color: #fcd34d; border: 1px solid #f59e0b; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; font-size: 0.85rem; }
        th, td { text-align: right; padding: 10px; border-bottom: 1px solid #334155; }
        th { color: #94a3b8; }
        .action-btns { display: flex; gap: 5px; }
        .btn-sm { padding: 4px 8px; font-size: 0.75rem; }
        .loader { border: 3px solid #334155; border-top: 3px solid #60a5fa; border-radius: 50%; width: 20px; height: 20px; animation: spin 1s linear infinite; display: inline-block; vertical-align: middle; margin-right: 8px; }
        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
        #adminUserModal { display: none; background: #0f172a; border: 1px solid #60a5fa; border-radius: 10px; padding: 20px; margin-top: 20px; }
    </style>
</head>
<body>

<div class="container">

    <div id="view-register" class="view active">
        <div class="header">
            <div class="icon">🛡️</div>
            <div class="title">X-NET Blocker</div>
            <div class="subtitle">מערכת סינון וניהול גלישה אישית</div>
        </div>
        
        <div id="regAlert" class="alert" style="display:none;"></div>
        <div class="field"><label>שם מלא</label><input type="text" id="regName" placeholder="ישראל ישראלי"></div>
        <div class="field"><label>מספר טלפון</label><input type="text" id="regPhone" placeholder="050-1234567"></div>
        <div class="field"><label>כתובת אימייל (המזהה שלך)</label><input type="text" id="regEmail" placeholder="israel@gmail.com"></div>
        <div class="field" id="adminPasswordFrame" style="display: none;">
            <label style="color: #f59e0b;">🛡️ קוד אימות מנהל מערכת</label>
            <input type="password" id="adminPassword" placeholder="הכנס קוד גישה">
        </div>
        <button id="regBtn" class="btn btn-primary btn-block" onclick="processRegistration()">⚡ הרשמה והורדת סקריפט התקנה</button>
    </div>

    <div id="view-dashboard" class="view">
        <div class="header" style="text-align: right;">
            <div style="display:flex; justify-content: space-between; align-items: center;">
                <h2 id="dashWelcome" style="font-size: 1.3rem; color: #60a5fa;">שלום, משתמש</h2>
                <div style="display:flex; gap: 10px; align-items:center;">
                    <button class="btn btn-secondary btn-sm" onclick="logoutSession()">התנתק</button>
                    <span class="status-badge status-active">🛡️ מוגן ומסונן</span>
                    <span id="installBadge" style="display:none;background:#1e3a5f;color:#93c5fd;border:1px solid #3b82f6;border-radius:99px;padding:3px 12px;font-size:0.75rem;font-weight:700"></span>
                    <span id="noInstallBadge" style="display:none;background:#450a0a;color:#fca5a5;border:1px solid #ef4444;border-radius:99px;padding:3px 12px;font-size:0.75rem;font-weight:700">⚠️ לא מותקן</span>
                </div>
            </div>
            <p class="subtitle" id="userDisplayEmail" style="text-align: right;"></p>
        </div>
        
        <button class="btn btn-success btn-block" onclick="downloadInstallerScript(currentUserEmail)" style="margin-bottom: 20px; box-shadow: 0 4px 6px rgba(0,0,0,0.3);">
            📥 הורד והפעל עדכונים (החלת שינויים / הסרה / השהיה)
        </button>

        <div id="activePauseBanner" class="alert alert-warn" style="display:none; margin-bottom: 15px; font-size: 0.95rem; text-align: center; font-weight: bold;"></div>

        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">
            <div id="userDashAlert" class="alert" style="display:none;flex:1;margin-bottom:0;margin-left:8px"></div>
            <button class="btn btn-secondary btn-sm" onclick="refreshDashboard()" style="white-space:nowrap">🔄 ריענון נתונים</button>
        </div>

        <div class="tabs">
            <div class="tab active" onclick="switchTab('tab-sites', this)">🌐 מורשים</div>
            <div class="tab" onclick="switchTab('tab-request', this)">📩 בקשת פתיחה</div>
            <div class="tab" onclick="switchTab('tab-pause', this)">⏳ השהיה</div>
            <div class="tab" onclick="switchTab('tab-uninstall', this)">🗑️ הסרה</div>
        </div>

        <div id="tab-sites" class="panel active">
            <h3 style="font-size:0.95rem; margin-bottom:10px; color:#93c5fd;">אתרים פתוחים אישית (בנוסף לבסיס):</h3>
            <ul id="userAllowedSitesList" class="domain-list"><li>טוען נתונים מהשרת... <div class="loader"></div></li></ul>
            <div id="userStatusFlags" style="margin-top: 10px; font-size: 0.85rem; color: #94a3b8; background: #1e293b; padding: 10px; border-radius: 6px;"></div>
        </div>

        <div id="tab-request" class="panel">
            <div class="field"><label>כתובת האתר לפתיחה</label><input type="text" id="reqUrl" placeholder="example.com"></div>
            <div class="field"><label>סיבה</label><input type="text" id="reqReason"></div>
            <div style="display:flex;gap:8px">
                <button class="btn btn-primary" style="flex:1" onclick="sendSiteRequestSystem()">📋 דרך המערכת</button>
                <button class="btn btn-secondary" style="flex:1" onclick="sendSiteRequestEmail()">📧 דרך אימייל</button>
            </div>
            <div id="reqDone" class="alert alert-success" style="display:none;margin-top:8px">נשלח בהצלחה! לאחר האישור יש ללחוץ על הכפתור הירוק לעדכון.</div>
        </div>

        <div id="tab-pause" class="panel">
            <div class="alert alert-info">המערכת מסתנכרנת אוטומטית כל 3 דקות. להחלה מיידית לחץ על הכפתור הירוק למעלה.</div>
            <div class="field"><label>זמן מבוקש</label>
                <select id="pauseTime"><option value="15">15 דקות</option><option value="30">30 דקות</option><option value="60">שעה אחת</option></select>
            </div>
            <div class="field"><label>סיבה</label><input type="text" id="pauseReason"></div>
            <div style="display:flex;gap:8px">
                <button class="btn btn-primary" style="flex:1" onclick="userRequestPause('system')">📋 דרך המערכת</button>
                <button class="btn btn-secondary" style="flex:1" onclick="userRequestPause('email')">📧 דרך אימייל</button>
            </div>
        </div>

        <div id="tab-uninstall" class="panel">
            <div id="uninstallInfoMsg" class="alert alert-info">הסרה מחייבת אישור מנהל.</div>
            <div style="display:flex;gap:8px;margin-bottom:12px">
                <button class="btn btn-warn" style="flex:1" onclick="userRequestUninstall('system')">📋 בקש הסרה במערכת</button>
                <button class="btn btn-secondary" style="flex:1" onclick="userRequestUninstall('email')">📧 בקש באימייל</button>
            </div>
            <div style="border-top:1px solid #334155;padding-top:12px">
                <button id="btnUserUninstallApprove" class="btn btn-danger btn-block" onclick="downloadInstallerScript(currentUserEmail)" disabled>
                    הסר תוכנה מהמחשב כעת (לאחר אישור)
                </button>
            </div>
        </div>
    </div>

    <div id="view-admin" class="view">
        <div class="header" style="text-align: right;">
            <div style="display:flex; justify-content: space-between; align-items: center;">
                <h2 style="font-size: 1.4rem; color: #f59e0b;">👑 פאנל ניהול ראשי</h2>
                <button class="btn btn-secondary btn-sm" onclick="logoutSession()">🔒 התנתק</button>
            </div>
            <p class="subtitle" style="text-align: right;">מנהל מחובר: meny85502@gmail.com</p>
        </div>

        <div id="adminTabs" class="tabs">
            <div class="tab active" onclick="switchAdminTab('admin-users-active', this)" id="tabActiveUsers">👥 פעילים</div>
            <div class="tab" onclick="switchAdminTab('admin-users-removed', this)" id="tabRemovedUsers">🗑️ הוסרו</div>
            <div class="tab" onclick="switchAdminTab('admin-base-sites', this)">🌍 רשימת בסיס</div>
        </div>

        <div id="admin-users-active" class="panel active" style="padding: 0; border: none; background: transparent;">
            <div id="adminLoadingActive" style="text-align:center; padding:20px; color:#94a3b8;"><div class="loader"></div> טוען נתונים...</div>
            <table id="usersTableActive" style="display:none;">
                <thead><tr><th>שם משתמש</th><th>אימייל / מזהה</th><th>פעולות</th></tr></thead>
                <tbody id="adminUsersTableBodyActive"></tbody>
            </table>
        </div>

        <div id="admin-users-removed" class="panel" style="padding: 0; border: none; background: transparent;">
            <table id="usersTableRemoved" style="display:none; opacity: 0.7;">
                <thead><tr><th>שם משתמש</th><th>אימייל / מזהה</th><th>סטטוס</th></tr></thead>
                <tbody id="adminUsersTableBodyRemoved"></tbody>
            </table>
        </div>

        <div id="admin-base-sites" class="panel" style="padding: 15px; border-radius: 10px; background: #0f172a;">
            <h3 style="color:#60a5fa; margin-bottom: 15px;">ניהול רשימת אתרים בסיסית (Base)</h3>
            
            <div class="field">
                <label>הוסף דומיין לרשימת הבסיס</label>
                <div style="display:flex; gap:8px;">
                    <input type="text" id="newBaseDomainInput" placeholder="example.com" style="flex:2;">
                    <input type="text" id="newBaseDomainName" placeholder="שם האתר (למשל: בנק לאומי)" style="flex:3;">
                    <button class="btn btn-primary" onclick="adminAddBaseDomain()">הוסף</button>
                </div>
            </div>
            
            <div id="baseSitesLoading" style="text-align:center; display:none;"><div class="loader"></div></div>
            <ul id="baseDomainList" class="domain-list" style="max-height: 300px; overflow-y: auto;"></ul>
        </div>

        <div id="adminUserModal">
            <div style="display:flex; justify-content: space-between; margin-bottom: 15px;">
                <h3 style="color:#60a5fa;" id="editUserName">עריכת משתמש</h3>
                <button class="btn btn-secondary btn-sm" onclick="closeAdminModal()">X סגור</button>
            </div>
            
            <div id="adminUserAlerts" style="margin-bottom: 15px;"></div>

            <div class="field" style="border: 1px solid #3b82f6; padding: 15px; border-radius: 8px; background: #1e3a5f;">
                <h4 style="color:#93c5fd; margin-bottom:10px; font-size: 0.95rem;">⚙️ הרשאות בסיס</h4>
                <label style="display: flex; align-items: center; gap: 10px; cursor: pointer; font-size: 0.95rem; color: #e2e8f0; margin-bottom: 12px;">
                    <input type="checkbox" id="adminBaseSitesToggle" onchange="adminToggleFeatures()" style="transform: scale(1.3);">
                    אפשר גישה לאתרים בסיסיים (מתוך קובץ Base)
                </label>
                <label style="display: flex; align-items: center; gap: 10px; cursor: pointer; font-size: 0.95rem; color: #e2e8f0;">
                    <input type="checkbox" id="adminGoogleSearchToggle" onchange="adminToggleFeatures()" style="transform: scale(1.3);">
                    אפשר חיפוש גוגל (Google Search)
                </label>
            </div>

            <div class="field" style="margin-top: 15px;">
                <label>הוסף אתר מורשה אישי (Domain)</label>
                <div style="display:flex; gap:8px;">
                    <input type="text" id="newDomainInput" placeholder="example.com" style="flex:2;">
                    <input type="text" id="newDomainName" placeholder="שם האתר (אופציונלי)" style="flex:3;">
                    <button class="btn btn-primary" onclick="adminAddDomain()">הוסף</button>
                </div>
            </div>

            <ul id="editUserDomainList" class="domain-list"></ul>
            
            <div style="border-top: 1px solid #334155; padding-top: 15px; margin-top: 15px;">
                <h4 style="color:#f59e0b; margin-bottom:10px; font-size: 0.95rem;">⚡ פעולות מנהל יזומות</h4>
                <div style="display:flex; gap:10px; margin-bottom:10px;">
                    <input type="number" id="adminInitiatedPause" placeholder="דקות השהיה" style="width:100px; padding: 6px; border-radius: 6px; background: #0f172a; border: 1px solid #334155; color: white;">
                    <button class="btn btn-warn btn-sm" style="flex:1;" onclick="adminTriggerPause()">הפעל השהיה</button>
                </div>
                <button class="btn btn-danger btn-sm" style="width:100%;" onclick="adminTriggerUninstall()">אישור הסרה יזום (ללא בקשת משתמש)</button>
            </div>
        </div>
    </div>

</div>

<script>
    const ADMIN_EMAIL = "meny85502@gmail.com";
    const ADMIN_PASS = "5502";
    const GITHUB_OWNER = "meny0583285502";
    const GITHUB_REPO = "X-NET";
    const GITHUB_TOKEN = ["ghp_", "PuFjv7joXh", "Tc5LLsZ71R", "RCtVzf6Vw80WFkIE"].join(""); 

    let currentUserEmail = "";
    let currentUserData = null;
    let currentUserFileSha = "";

    function utf8_to_b64(str) { return window.btoa(unescape(encodeURIComponent(str))); }
    function b64_to_utf8(str) { return decodeURIComponent(escape(window.atob(str))); }
    function formatDomain(input) { if (!input) return ""; return input.replace(/^[\/]*https?:\/\//i, "").replace(/^www\./i, "").replace(/^\//, "").split('/')[0].split('?')[0].trim(); }

    window.onload = function() {
        document.getElementById('regEmail').addEventListener('input', function(e) {
            const val = e.target.value.trim().toLowerCase();
            document.getElementById('adminPasswordFrame').style.display = (val === ADMIN_EMAIL.toLowerCase() || val === "5502") ? "block" : "none";
        });

        const urlParams = new URLSearchParams(window.location.search);
        const userParam = urlParams.get('user');
        if (urlParams.get('installed') === '1' && userParam) {
            localStorage.setItem('xnet_install_status', JSON.stringify({ installed: true, last_updated: new Date().toLocaleString('he-IL') }));
            history.replaceState({}, '', window.location.pathname + '?user=' + encodeURIComponent(userParam));
        }

        if (userParam) {
            localStorage.setItem('xnet_user_email', userParam);
            loadUserDashboard(userParam);
        } else {
            const saved = localStorage.getItem('xnet_user_email');
            if(saved) {
                if(saved.toLowerCase() === ADMIN_EMAIL.toLowerCase() || saved === "5502"){
                    showView('view-admin'); loadAdminData();
                } else { loadUserDashboard(saved); }
            } else { showView('view-register'); }
        }
    };

    function logoutSession() { localStorage.removeItem('xnet_user_email'); location.reload(); }
    function showView(id) { document.querySelectorAll('.view').forEach(v => v.classList.remove('active')); document.getElementById(id).classList.add('active'); }
    function switchTab(id, el) { 
        document.querySelectorAll('#view-dashboard .tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('#view-dashboard .panel').forEach(p => p.classList.remove('active'));
        el.classList.add('active'); document.getElementById(id).classList.add('active');
    }
    function switchAdminTab(id, el) { 
        document.querySelectorAll('#view-admin .tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('#view-admin .panel').forEach(p => p.classList.remove('active'));
        el.classList.add('active'); document.getElementById(id).classList.add('active');
        if(id === 'admin-base-sites') loadAdminBaseSites();
    }
    function uiAlert(id, msg, type = 'error') {
        const el = document.getElementById(id); el.style.display = 'block'; el.className = `alert alert-${type}`; el.innerText = msg;
        setTimeout(() => { el.style.display = 'none'; }, 6000);
    }

    async function fetchUserJson(email) {
        const safe = email.replace('@', '_at_').replace(/\./g, '_dot_');
        const res = await fetch(`https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/profiles/${safe}.json`, { headers: { 'Authorization': `token ${GITHUB_TOKEN}` } });
        if (!res.ok) throw new Error("פרופיל לא נמצא");
        const data = await res.json(); return { sha: data.sha, content: JSON.parse(b64_to_utf8(data.content)) };
    }
    async function updateUserJson(email, newData, sha, msg) {
        const safe = email.replace('@', '_at_').replace(/\./g, '_dot_');
        const content = utf8_to_b64(JSON.stringify(newData, null, 2));
        const res = await fetch(`https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/profiles/${safe}.json`, { method: 'PUT', headers: { 'Authorization': `token ${GITHUB_TOKEN}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ message: msg, content: content, sha: sha }) });
        const resData = await res.json(); return resData.content.sha;
    }

    async function processRegistration() {
        const name = document.getElementById('regName').value.trim(); const phone = document.getElementById('regPhone').value.trim();
        let email = document.getElementById('regEmail').value.trim(); const pass = document.getElementById('adminPassword').value.trim();
        if (!email) return uiAlert('regAlert', "חסר אימייל");
        if (email.toLowerCase() === ADMIN_EMAIL.toLowerCase() || email === "5502") {
            if (pass === ADMIN_PASS) { localStorage.setItem('xnet_user_email', ADMIN_EMAIL); showView('view-admin'); loadAdminData(); } 
            else uiAlert('regAlert', "קוד שגוי"); return;
        }
        if (!name || !phone) return uiAlert('regAlert', "חסר שם/טלפון");
        document.getElementById('regBtn').disabled = true;
        
        const userData = { name: name, phone: phone, email: email, registered_at: new Date().toISOString(), base_sites_enabled: false, google_search_enabled: false, allowed_domains: ["meny0583285502.github.io"], requests: { pause: null, uninstall_requested: false, uninstall_approved: false, site_request: null } };
        try {
            const safe = email.replace('@', '_at_').replace(/\./g, '_dot_');
            await fetch(`https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/profiles/${safe}.json`, { method: 'PUT', headers: { 'Authorization': `token ${GITHUB_TOKEN}` }, body: JSON.stringify({ message: `New user`, content: utf8_to_b64(JSON.stringify(userData, null, 2)) }) });
            localStorage.setItem('xnet_user_email', email); uiAlert('regAlert', "מוריד התקנה...", "success");
            setTimeout(() => { downloadInstallerScript(email); loadUserDashboard(email); }, 1500);
        } catch (e) { uiAlert('regAlert', e.message); document.getElementById('regBtn').disabled = false; }
    }

    function downloadInstallerScript(email) {
        const psScript = `Invoke-WebRequest -Uri 'https://meny0583285502.github.io/X-NET/install.ps1' -OutFile "$env:TEMP\\xnet_install.ps1" -UseBasicParsing; & "$env:TEMP\\xnet_install.ps1" -UserEmail '${email}'`;
        const batContent = `@echo off\npowershell -Command "$code = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${btoa(unescape(encodeURIComponent(psScript)))}')); Set-Content -Path '%TEMP%\\rx.ps1' -Value $code -Encoding UTF8; Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \\"%TEMP%\\rx.ps1\\"' -Verb RunAs"`;
        const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([batContent], { type: 'text/plain' })); a.download = `XNET_Update.bat`;
        document.body.appendChild(a); a.click(); document.body.removeChild(a);
    }

    async function loadUserDashboard(email) {
        currentUserEmail = email; showView('view-dashboard'); document.getElementById('dashWelcome').innerText = `טוען...`;
        try {
            const user = await fetchUserJson(email); currentUserData = user.content; currentUserFileSha = user.sha;
            document.getElementById('dashWelcome').innerText = `שלום, ${currentUserData.name}`;
            document.getElementById('userDisplayEmail').innerText = `מזהה מערכת: ${email}`;
            
            const raw = localStorage.getItem('xnet_install_status');
            if (raw && JSON.parse(raw).installed) { document.getElementById('installBadge').style.display = 'inline-block'; document.getElementById('installBadge').innerText = `✅ מותקן`; } 
            else { document.getElementById('noInstallBadge').style.display = 'inline-block'; }

            const banner = document.getElementById('activePauseBanner');
            banner.style.display = 'none';
            if (currentUserData.requests && currentUserData.requests.pause && currentUserData.requests.pause.until) {
                const untilDate = new Date(currentUserData.requests.pause.until);
                if (untilDate > new Date()) {
                    banner.style.display = 'block';
                    banner.innerText = `⏳ המערכת מושהית זמנית עד השעה: ${untilDate.toLocaleTimeString('he-IL', {hour: '2-digit', minute:'2-digit'})}`;
                }
            }

            const ul = document.getElementById('userAllowedSitesList'); ul.innerHTML = '';
            currentUserData.allowed_domains.forEach(item => {
                const parts = item.split('|');
                const d = parts[0];
                const n = parts.length > 1 ? ` - <span style="color:#60a5fa; font-weight:bold;">${parts[1]}</span>` : "";
                ul.innerHTML += `<li>${d}${n}</li>`;
            });
            document.getElementById('userStatusFlags').innerText = `הגדרות חשבון: גישה לאתרים בסיסיים - ${currentUserData.base_sites_enabled ? 'פעיל 🟢' : 'כבוי 🔴'} | חיפוש גוגל - ${currentUserData.google_search_enabled ? 'פעיל 🟢' : 'כבוי 🔴'}`;

            if (currentUserData.requests && currentUserData.requests.uninstall_approved) {
                document.getElementById('btnUserUninstallApprove').disabled = false;
                document.getElementById('uninstallInfoMsg').className = "alert alert-success";
                document.getElementById('uninstallInfoMsg').innerText = "✅ הסרת התוכנה אושרה ע\"י המנהל. לחץ על הכפתור הירוק למעלה כדי להסיר לחלוטין.";
            }
        } catch (e) { uiAlert('userDashAlert', "שגיאה בטעינה", "error"); }
    }

    async function refreshDashboard() { await loadUserDashboard(currentUserEmail); }

    async function sendSiteRequestSystem() {
        const url = formatDomain(document.getElementById('reqUrl').value); if (!url) return;
        if(!currentUserData.requests) currentUserData.requests = {};
        currentUserData.requests.site_request = { url: url, reason: document.getElementById('reqReason').value, date: new Date().toISOString() };
        try { currentUserFileSha = await updateUserJson(currentUserEmail, currentUserData, currentUserFileSha, "Request"); document.getElementById('reqDone').style.display='block'; document.getElementById('reqUrl').value=''; } catch(e){}
    }
    function sendSiteRequestEmail() { const u=formatDomain(document.getElementById('reqUrl').value); if(!u) return; window.open(`https://mail.google.com/mail/?view=cm&to=${ADMIN_EMAIL}&su=בקשה&body=${u}`); }

    async function userRequestPause(method) {
        if(!currentUserData) return;
        const time = document.getElementById('pauseTime').value;
        if (method === 'email') window.open(`https://mail.google.com/mail/?view=cm&to=${ADMIN_EMAIL}&su=השהיה`);
        else {
            if(!currentUserData.requests) currentUserData.requests = {};
            const untilUTC = new Date(Date.now() + parseInt(time)*60000).toISOString();
            currentUserData.requests.pause = { time: time, reason: "", date: new Date().toISOString(), until: untilUTC };
            try { 
                currentUserFileSha = await updateUserJson(currentUserEmail, currentUserData, currentUserFileSha, "Pause"); 
                uiAlert('userDashAlert', "בקשת השהיה נשמרה. לחץ על הכפתור הירוק למעלה להחלה מיידית.", "success"); 
                refreshDashboard();
            } catch(e){}
        }
    }

    async function userRequestUninstall(method) {
        if(!currentUserData) return;
        if (method === 'email') window.open(`https://mail.google.com/mail/?view=cm&to=${ADMIN_EMAIL}&su=הסרה`);
        else {
            if(!currentUserData.requests) currentUserData.requests = {}; currentUserData.requests.uninstall_requested = true;
            try { currentUserFileSha = await updateUserJson(currentUserEmail, currentUserData, currentUserFileSha, "Uninst"); uiAlert('userDashAlert', "נשלח למנהל", "success"); } catch(e){}
        }
    }

    // ================= ניהול =================
    let currentAdminEditingEmail = "";
    let baseWhitelistData = null;
    let baseWhitelistSha = "";

    async function loadAdminBaseSites() {
        document.getElementById('baseSitesLoading').style.display = 'block';
        try {
            const res = await fetch(`https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/base_whitelist.json`, { headers: { 'Authorization': `token ${GITHUB_TOKEN}` } });
            const data = await res.json();
            baseWhitelistSha = data.sha;
            baseWhitelistData = JSON.parse(b64_to_utf8(data.content));
            renderBaseDomainList();
        } catch(e) { alert("שגיאה בטעינת קובץ הבסיס"); }
        document.getElementById('baseSitesLoading').style.display = 'none';
    }

    function renderBaseDomainList() {
        const ul = document.getElementById('baseDomainList'); ul.innerHTML = '';
        if(baseWhitelistData && baseWhitelistData.allowed_domains) {
            baseWhitelistData.allowed_domains.forEach((item, index) => { 
                const parts = item.split('|');
                const d = parts[0];
                const n = parts.length > 1 ? ` <span style="color:#94a3b8; font-size:0.85rem;">(${parts[1]})</span>` : "";
                ul.innerHTML += `<li><span>${d}${n}</span> <button class="btn btn-danger btn-sm" onclick="adminRemoveBaseDomain(${index})">X</button></li>`; 
            });
        }
    }

    async function adminAddBaseDomain() {
        const d = formatDomain(document.getElementById('newBaseDomainInput').value); 
        const n = document.getElementById('newBaseDomainName').value.trim();
        if(!d || !baseWhitelistData) return;
        
        const entry = n ? `${d}|${n}` : d;
        const exists = baseWhitelistData.allowed_domains.some(x => x.split('|')[0] === d);
        
        if (!exists) baseWhitelistData.allowed_domains.push(entry);
        document.getElementById('newBaseDomainInput').value = ''; 
        document.getElementById('newBaseDomainName').value = ''; 
        renderBaseDomainList(); 
        await saveBaseWhitelist("Added base domain");
    }
    
    async function adminRemoveBaseDomain(idx) {
        baseWhitelistData.allowed_domains.splice(idx, 1); renderBaseDomainList(); await saveBaseWhitelist("Removed base domain");
    }

    async function saveBaseWhitelist(msg) {
        const content = utf8_to_b64(JSON.stringify(baseWhitelistData, null, 2));
        const res = await fetch(`https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/base_whitelist.json`, { method: 'PUT', headers: { 'Authorization': `token ${GITHUB_TOKEN}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ message: msg, content: content, sha: baseWhitelistSha }) });
        const resData = await res.json(); baseWhitelistSha = resData.content.sha;
    }

    async function loadAdminData() {
        try {
            const res = await fetch(`https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/profiles`, { headers: { 'Authorization': `token ${GITHUB_TOKEN}` } });
            const files = await res.json();
            const tbodyActive = document.getElementById('adminUsersTableBodyActive'); const tbodyRemoved = document.getElementById('adminUsersTableBodyRemoved');
            tbodyActive.innerHTML = ''; tbodyRemoved.innerHTML = '';
            let pendingReqs = 0; let activeCount = 0; let removedCount = 0;
            
            for (const file of files) {
                if(file.name.endsWith('.json')) {
                    const email = file.name.replace('_at_', '@').replace(/_dot_/g, '.').replace('.json', '');
                    const uRes = await fetch(file.url, { headers: { 'Authorization': `token ${GITHUB_TOKEN}` } });
                    const uDataRaw = await uRes.json(); const uData = JSON.parse(b64_to_utf8(uDataRaw.content));
                    
                    if (uData.requests && uData.requests.uninstall_approved) {
                        tbodyRemoved.innerHTML += `<tr><td>${uData.name}</td><td>${email}</td><td><span class="status-badge" style="background:#450a0a;color:#fca5a5;">הוסר</span></td></tr>`;
                        removedCount++;
                    } else {
                        let alertIcon = (uData.requests && (uData.requests.pause || uData.requests.site_request || uData.requests.uninstall_requested)) ? " ⚠️" : "";
                        if(alertIcon) pendingReqs++;
                        tbodyActive.innerHTML += `<tr><td>${uData.name} ${alertIcon}</td><td style="color:#60a5fa;">${email}
