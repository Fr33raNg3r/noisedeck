"""页面渲染：登录页与管理主页。全部内联 CSS / JS，不依赖任何外部资源。"""
from html import escape
from urllib.parse import quote

_CSS = """
:root{--bg:#f3f5fb;--card:#fff;--text:#1a2236;--muted:#6a7891;--border:#e2e7f1;
--primary:#4f6ef7;--primary2:#7a5cf5;--ok:#16a34a;--okbg:#e7f8ee;--off:#8a97ad;
--offbg:#eef1f6;--danger:#e5484d;--shadow:0 6px 24px rgba(30,45,90,.08);--radius:16px}
:root{color-scheme:light}
@media (prefers-color-scheme: dark){:root:not([data-theme=light]){@@DARK@@}}
:root[data-theme=dark]{@@DARK@@}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.6 -apple-system,
BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif}
.logo{width:36px;height:36px;border-radius:10px;display:grid;place-items:center;
background:linear-gradient(135deg,var(--primary),var(--primary2));color:#fff}
.logo svg{width:23px;height:23px}
button,.btn{font:inherit;cursor:pointer;border:1px solid var(--border);background:var(--card);
color:var(--text);padding:8px 16px;border-radius:10px;transition:.15s;text-decoration:none;
display:inline-block}
button:hover,.btn:hover{transform:translateY(-1px);box-shadow:var(--shadow)}
button:active,.btn:active{transform:none}
.primary{background:linear-gradient(135deg,var(--primary),var(--primary2));color:#fff;border:0}
.danger{color:var(--danger)}
.danger.solid{background:var(--danger);color:#fff;border:0}
input[type=text],input[type=password]{width:100%;font:inherit;padding:10px 14px;
border-radius:10px;border:1px solid var(--border);background:var(--bg);color:var(--text)}
input:focus,textarea:focus{outline:2px solid var(--primary);outline-offset:1px}
.login-wrap{min-height:100vh;display:grid;place-items:center;padding:16px}
.login{width:100%;max-width:380px;background:var(--card);border-radius:var(--radius);
box-shadow:var(--shadow);padding:32px 28px;border:1px solid var(--border)}
.login .logo{width:52px;height:52px;margin:0 auto 12px;border-radius:14px}
.login .logo svg{width:32px;height:32px}
.login h1{text-align:center;font-size:20px;margin:0 0 4px}
.login p.sub{text-align:center;color:var(--muted);margin:0 0 20px}
.login label{display:block;margin:12px 0 4px;color:var(--muted);font-size:13px}
.login button{width:100%;margin-top:20px;padding:11px}
.err{background:#fdecec;color:var(--danger);border-radius:10px;padding:8px 12px;margin-top:12px}
@media (prefers-color-scheme: dark){:root:not([data-theme=light]) .err{background:#3a1c22}}
:root[data-theme=dark] .err{background:#3a1c22}
header{position:sticky;top:0;z-index:5;background:var(--card);border-bottom:1px solid var(--border);
padding:12px 16px}
.bar{max-width:1080px;margin:0 auto;display:flex;align-items:center;gap:12px}
.bar h1{font-size:17px;margin:0;flex:1}
.bar .who{color:var(--muted);font-size:13px}
main{max-width:1080px;margin:0 auto;padding:20px 16px 48px}
.panel{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);
box-shadow:var(--shadow);padding:18px 20px;margin-bottom:20px}
.panel h2{margin:0 0 12px;font-size:15px}
.addform{display:flex;gap:10px;flex-wrap:wrap}
.addform input{flex:1;min-width:180px}
.hint{color:var(--muted);font-size:13px;margin:8px 0 0}
.flash{background:#fdecec;color:var(--danger);border-radius:12px;padding:10px 14px;margin-bottom:16px}
@media (prefers-color-scheme: dark){:root:not([data-theme=light]) .flash{background:#3a1c22}}
:root[data-theme=dark] .flash{background:#3a1c22}
.stats{color:var(--muted);margin:0 0 12px;font-size:14px}
.stats b{color:var(--text)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(290px,1fr));gap:16px}
.peer{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);
box-shadow:var(--shadow);padding:16px 18px;transition:.15s}
.peer:hover{transform:translateY(-2px)}
.peer .top{display:flex;align-items:center;gap:12px}
.avatar{width:40px;height:40px;border-radius:12px;display:grid;place-items:center;font-weight:700;
color:#fff;background:linear-gradient(135deg,var(--primary),var(--primary2));text-transform:uppercase}
.peer .name{font-weight:600;flex:1;word-break:break-all}
.badge{font-size:12px;padding:2px 10px;border-radius:99px;display:inline-flex;align-items:center;gap:6px}
.badge::before{content:"";width:7px;height:7px;border-radius:50%;background:currentColor}
.badge.on{background:var(--okbg);color:var(--ok)}
.badge.off{background:var(--offbg);color:var(--off)}
.meta{color:var(--muted);font-size:13px;margin:12px 0;display:grid;gap:2px}
.notice{background:var(--okbg);color:var(--ok);border-radius:12px;padding:10px 14px;margin-bottom:16px}
.field{display:block;margin:12px 0 4px;color:var(--muted);font-size:13px}
.modal form input[type=text]{margin-bottom:2px}
footer{max-width:1080px;margin:0 auto;display:flex;align-items:center;justify-content:center;
gap:8px;color:var(--muted);font-size:12px;padding:18px 16px 28px;border-top:1px solid var(--border)}
footer b{color:var(--text);font-weight:600;letter-spacing:.2px}
.flogo{width:20px;height:20px;border-radius:6px;display:grid;place-items:center;color:#fff;
background:linear-gradient(135deg,var(--primary),var(--primary2))}
.flogo svg{width:13px;height:13px}
.ver{padding:1px 9px;border-radius:999px;background:var(--offbg);font-variant-numeric:tabular-nums}
.rate{display:flex;gap:16px;font-weight:600;font-variant-numeric:tabular-nums;margin:-4px 0 4px}
.rate .up{color:var(--primary)}
.rate .down{color:var(--ok)}
.total{color:var(--muted);font-size:12.5px;margin-bottom:12px;font-variant-numeric:tabular-nums}
.actions{display:flex;gap:8px}
.actions button{flex:1;padding:7px 10px}
.empty{text-align:center;color:var(--muted);padding:48px 16px;border:2px dashed var(--border);
border-radius:var(--radius)}
.mask{position:fixed;inset:0;background:rgba(8,12,24,.55);display:none;align-items:center;
justify-content:center;padding:16px;z-index:20}
.mask.show{display:flex}
.modal{background:var(--card);border-radius:var(--radius);padding:22px;width:100%;max-width:720px;
max-height:92vh;overflow:auto;box-shadow:var(--shadow)}
.modal.small{max-width:380px}
.modal h3{margin:0 0 14px}
.cols{display:flex;gap:20px}
.qr{flex:0 0 240px;background:#fff;border-radius:12px;padding:10px;align-self:flex-start}
.qr svg{width:100%;height:auto;display:block}
.conf{flex:1;min-width:0}
textarea{width:100%;height:230px;font:12.5px/1.5 ui-monospace,Menlo,Consolas,monospace;
padding:10px;border-radius:10px;border:1px solid var(--border);background:var(--bg);
color:var(--text);resize:vertical}
.row{display:flex;gap:8px;flex-wrap:wrap;margin-top:12px;justify-content:flex-end}
.theme-fix{position:fixed;top:12px;right:12px;font-size:13px;padding:6px 12px}
#theme{white-space:nowrap}
@media (max-width:640px){.cols{flex-direction:column}.qr{flex-basis:auto;width:100%;max-width:260px;
align-self:center}.bar .who{display:none}}
"""

# 深色配色只写一份，分别用于“跟随系统”和“强制深色”两处
_DARK_VARS = ("color-scheme:dark;--bg:#0d1220;--card:#161f33;--text:#e8edf7;"
              "--muted:#8fa0bb;--border:#26324d;--okbg:#12301f;--off:#7d8aa3;"
              "--offbg:#1f2940;--shadow:0 6px 24px rgba(0,0,0,.35)")
_CSS = _CSS.replace("@@DARK@@", _DARK_VARS)

# 主题切换：跟随系统 → 浅色 → 深色。放在 <head> 里，渲染前就应用已保存的选择，避免闪烁；
# localStorage 不可用时只在当前页面生效
_THEME_JS = """(function(){var K='wg-theme',R=document.documentElement,L={auto:'◐ 跟随系统',light:'☀ 浅色',dark:'☾ 深色'};
function load(){try{var t=localStorage.getItem(K);return t==='light'||t==='dark'?t:'auto'}catch(e){return 'auto'}}
var cur=load();
function apply(){if(cur==='auto')R.removeAttribute('data-theme');else R.setAttribute('data-theme',cur);
var b=document.getElementById('theme');if(b)b.textContent=L[cur]}
window.cycleTheme=function(){cur={auto:'light',light:'dark',dark:'auto'}[cur];
try{if(cur==='auto')localStorage.removeItem(K);else localStorage.setItem(K,cur)}catch(e){}apply()};
apply();document.addEventListener('DOMContentLoaded',apply)})();"""

# Logo：字母 N（NoiseDeck），中间一撇画成平滑的波形（Noise）。一笔画成：
# 左竖线向上 → 波形斜线向下 → 右竖线向上。页面图标和浏览器标签图标共用同一图形
_LOGO_SHAPE = '<path d="M6 18V6C9.5 6 8.5 12 12 12S14.5 18 18 18V6"/>'
_LOGO = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" '
         'stroke-linecap="round" stroke-linejoin="round">' + _LOGO_SHAPE + '</svg>')
_FAVICON_SVG = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><defs>'
    '<linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#4f6ef7"/>'
    '<stop offset="1" stop-color="#7a5cf5"/></linearGradient></defs>'
    '<rect width="32" height="32" rx="8" fill="url(#g)"/>'
    '<g transform="translate(4 4)" fill="none" stroke="#fff" stroke-width="2.2" '
    'stroke-linecap="round" stroke-linejoin="round">' + _LOGO_SHAPE + '</g></svg>')
# 整段做百分号编码，data URI 里不会出现裸的 # 和 ://
_FAVICON = "data:image/svg+xml," + quote(_FAVICON_SVG, safe="")

_HEAD = ('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">'
         '<meta name="viewport" content="width=device-width,initial-scale=1">'
         '<link rel="icon" href="' + _FAVICON + '">'
         '<title>@@TITLE@@</title><style>' + _CSS + '</style>'
         '<script>' + _THEME_JS + '</script></head>')


def _head(title):
    # CSS 中含有百分号，不能用 % 格式化，改用占位符替换
    return _HEAD.replace("@@TITLE@@", title)


def render_login(error, csrf):
    err = f'<div class="err">{escape(error)}</div>' if error else ""
    return (_head("登录 - NoiseDeck") + f"""<body>
<button type="button" id="theme" class="theme-fix" onclick="cycleTheme()" title="切换主题">主题</button>
<div class="login-wrap">
<form class="login" method="post" action="/login">
<div class="logo">{_LOGO}</div><h1>NoiseDeck</h1><p class="sub">WireGuard 管理控制台 · 请登录后继续</p>
<label for="u">用户名</label><input id="u" type="text" name="username" autocomplete="username" autofocus required>
<label for="p">密码</label><input id="p" type="password" name="password" autocomplete="current-password" required>
{err}<button class="primary" type="submit">登 录</button></form></div></body></html>""")


_JS = """
const $=s=>document.querySelector(s);
function showMask(id,on){$(id).classList.toggle('show',on)}
function toast(t){const b=$('#copy');const o=b.dataset.o||b.textContent;b.dataset.o=o;
b.textContent=t;setTimeout(()=>b.textContent=o,1500)}
async function openView(name){
  $('#vname').textContent=name;$('#qr').innerHTML='加载中…';$('#conf').value='';
  showMask('#view',true);
  try{const r=await fetch('/clients/'+encodeURIComponent(name),{credentials:'same-origin'});
    if(r.status===401){location='/login';return}
    const d=await r.json();$('#qr').innerHTML=d.qr_svg;$('#conf').value=d.conf;
    $('#dl').href='/clients/'+encodeURIComponent(name)+'/download';
  }catch(e){$('#qr').textContent='加载失败'}
}
async function copyConf(){
  const t=$('#conf');
  try{if(navigator.clipboard&&window.isSecureContext){await navigator.clipboard.writeText(t.value);toast('已复制');return}}catch(e){}
  t.select();try{document.execCommand('copy');toast('已复制')}catch(e){toast('请手动复制')}
}
function openEdit(p){
  const n=p.dataset.name;
  $('#etitle').textContent=n;$('#ename').value=n;
  $('#edns').value=p.dataset.dns||'';$('#eroute').value=p.dataset.routes||'';
  $('#eform').action='/clients/'+encodeURIComponent(n)+'/edit';
  showMask('#edit',true);
}
function askDelete(name){
  $('#dname').textContent=name;
  $('#dform').action='/clients/'+encodeURIComponent(name)+'/delete';
  showMask('#del',true);
}
document.querySelectorAll('.mask').forEach(m=>m.addEventListener('click',e=>{
  if(e.target===m)m.classList.remove('show')}));
function fmtBytes(n){
  const u=['B','KB','MB','GB','TB'];let i=0;
  while(n>=1024&&i<4){n/=1024;i++}
  return (i?n.toFixed(n<10?2:1):Math.round(n))+' '+u[i];
}
function fmtRate(n){return fmtBytes(n)+'/s'}
const prev={};
async function refresh(){
  try{const r=await fetch('/api/status',{credentials:'same-origin'});
    if(r.status===401){location='/login';return}
    if(!r.ok)return;
    const d=await r.json();let on=0;const now=Date.now();
    document.querySelectorAll('.peer').forEach(p=>{
      const s=d[p.dataset.name];if(!s)return;
      if(s.online)on++;
      const b=p.querySelector('.badge');b.className='badge '+(s.online?'on':'off');
      b.textContent=s.online?'在线':'离线';
      p.querySelector('.ago').textContent=s.ago;
      // 速率 = 两次采样的累计字节差 / 实际间隔；首次采样或计数器回退时显示 —
      const n=p.dataset.name,pr=prev[n];prev[n]={t:now,rx:s.rx,tx:s.tx};
      const up=p.querySelector('.up'),dn=p.querySelector('.down');
      if(pr&&s.rx>=pr.rx&&s.tx>=pr.tx&&now>pr.t){
        const dt=(now-pr.t)/1000;
        up.textContent='↑ '+fmtRate((s.rx-pr.rx)/dt);
        dn.textContent='↓ '+fmtRate((s.tx-pr.tx)/dt);
      }else{up.textContent='↑ —';dn.textContent='↓ —'}
      p.querySelector('.total').textContent='累计 ↑ '+fmtBytes(s.rx)+'  ↓ '+fmtBytes(s.tx);
    });
    const o=$('#online');if(o)o.textContent=on;
  }catch(e){}
}
refresh();
setInterval(refresh, 3000);
"""


def _card(c):
    name = escape(c["name"], quote=True)
    online = bool(c["online"])
    dns = escape(c.get("dns", ""), quote=True)
    routes = escape(c.get("allowed_ips", ""), quote=True)
    return f"""<div class="peer" data-name="{name}" data-dns="{dns}" data-routes="{routes}">
<div class="top"><div class="avatar">{name[:1]}</div><div class="name">{name}</div>
<span class="badge {'on' if online else 'off'}">{'在线' if online else '离线'}</span></div>
<div class="meta"><div>内网 IP：{escape(c['ip'])}</div>
<div>最近握手：<span class="ago">{escape(c['ago'])}</span></div>
<div>创建时间：{escape(c['created'])}</div></div>
<div class="rate"><span class="up" title="上传速率（客户端发出）">↑ —</span><span class="down" title="下载速率（客户端接收）">↓ —</span></div>
<div class="total">累计 ↑ —  ↓ —</div>
<div class="actions"><button type="button" onclick="openView(this.closest('.peer').dataset.name)">查看</button>
<button type="button" onclick="openEdit(this.closest('.peer'))">编辑</button>
<button type="button" class="danger" onclick="askDelete(this.closest('.peer').dataset.name)">删除</button></div></div>"""


def render_index(clients, csrf, user, flash, version="", settings=None, notice=None):
    token = escape(csrf, quote=True)
    settings = settings or {"dns": "", "endpoint": "", "wg_port": ""}
    default_dns = escape(settings["dns"], quote=True)
    default_endpoint = escape(settings["endpoint"], quote=True)
    default_wg_port = escape(str(settings.get("wg_port", "")), quote=True)
    notice_html = f'<div class="notice">{escape(notice)}</div>' if notice else ""
    online = sum(1 for c in clients if c["online"])
    flash_html = f'<div class="flash">{escape(flash)}</div>' if flash else ""
    footer = (f'<footer><span class="flogo">{_LOGO}</span><b>NoiseDeck</b>'
              f'<span class="ver">v{escape(version)}</span></footer>') if version else ""
    if clients:
        body = (f'<p class="stats">在线 <b id="online">{online}</b> / 共 <b>{len(clients)}</b> 个客户端</p>'
                '<div class="grid">' + "".join(_card(c) for c in clients) + "</div>")
    else:
        body = '<div class="empty">还没有客户端<br>在上方输入名称并点击“添加”，即可创建第一个</div>'
    return (_head("NoiseDeck") + f"""<body>
<header><div class="bar"><div class="logo">{_LOGO}</div><h1>NoiseDeck</h1>
<span class="who">{escape(user)}</span>
<button type="button" id="theme" onclick="cycleTheme()" title="切换主题：跟随系统 / 浅色 / 深色">主题</button>
<button type="button" onclick="showMask('#settings',true)">全局设置</button>
<form method="post" action="/logout"><input type="hidden" name="csrf" value="{token}">
<button type="submit">退出</button></form></div></header>
<main>{notice_html}{flash_html}
<section class="panel"><h2>新增客户端</h2>
<form class="addform" method="post" action="/clients">
<input type="hidden" name="csrf" value="{token}">
<input type="text" name="name" placeholder="客户端名称，如 我的手机 或 my-phone" maxlength="32" required>
<button class="primary" type="submit">添加</button></form>
<p class="hint">名称可用汉字、字母、数字、下划线和短横线（最长 32 个字符）。添加后点击“查看”即可扫码或复制配置。</p>
</section>
{body}
</main>{footer}
<div class="mask" id="view"><div class="modal">
<h3>客户端配置 · <span id="vname"></span></h3>
<div class="cols"><div class="qr" id="qr"></div>
<div class="conf"><textarea id="conf" readonly spellcheck="false"></textarea>
<p class="hint">手机 WireGuard 应用扫描左侧二维码，或复制右侧配置导入。</p></div></div>
<div class="row"><button type="button" id="copy" onclick="copyConf()">复制配置</button>
<a class="btn" id="dl" href="#">下载 .conf</a>
<button type="button" class="primary" onclick="showMask('#view',false)">关闭</button></div>
</div></div>
<div class="mask" id="del"><div class="modal small"><h3>删除客户端</h3>
<p>确定要删除 <b id="dname"></b> 吗？删除后该设备将无法再连接。</p>
<form id="dform" method="post" action=""><input type="hidden" name="csrf" value="{token}">
<div class="row"><button type="button" onclick="showMask('#del',false)">取消</button>
<button type="submit" class="danger solid">确认删除</button></div></form></div></div>
<div class="mask" id="edit"><div class="modal small"><h3>编辑客户端 · <span id="etitle"></span></h3>
<form id="eform" method="post" action=""><input type="hidden" name="csrf" value="{token}">
<label class="field" for="ename">名称（可用汉字）</label>
<input id="ename" type="text" name="name" maxlength="32" required>
<label class="field" for="edns">DNS（可填多个，用英文逗号分隔）</label>
<input id="edns" type="text" name="dns" placeholder="留空使用默认：{default_dns}">
<label class="field" for="eroute">路由范围</label>
<input id="eroute" type="text" name="allowed_ips" placeholder="留空 = 全部流量走 VPN；仅访问内网填如 10.8.0.0/24, 192.168.1.0/24">
<p class="hint">名称只是显示标签，修改后不影响设备。修改 DNS 或路由范围后，需要让该设备重新扫码或导入配置才会生效。</p>
<div class="row"><button type="button" onclick="showMask('#edit',false)">取消</button>
<button type="submit" class="primary">保存</button></div></form></div></div>
<div class="mask" id="settings"><div class="modal small"><h3>全局设置</h3>
<form method="post" action="/settings"><input type="hidden" name="csrf" value="{token}">
<label class="field" for="sdns">默认 DNS（可填多个，用英文逗号分隔）</label>
<input id="sdns" type="text" name="dns" value="{default_dns}" required>
<label class="field" for="sendpoint">Endpoint（客户端连接地址，公网 IP 或域名）</label>
<input id="sendpoint" type="text" name="endpoint" value="{default_endpoint}" required>
<label class="field" for="swgport">WireGuard 端口（UDP，1024-65535）</label>
<input id="swgport" type="text" inputmode="numeric" name="wg_port" pattern="[0-9]{{4,5}}" maxlength="5" title="1024-65535 的数字" value="{default_wg_port}" required>
<p class="hint">新增客户端和未单独设置 DNS 的客户端使用这里的值；已有设备需重新扫码或导入配置才会生效。修改 WireGuard 端口会让在线设备短暂断开，且已有设备必须重新扫码或导入配置，也请先在防火墙放行新端口。VPN 网段不能在网页修改。</p>
<div class="row"><button type="button" onclick="showMask('#settings',false)">取消</button>
<button type="submit" class="primary">保存</button></div></form></div></div>
<script>{_JS}</script></body></html>""")
