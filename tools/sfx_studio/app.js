"use strict";
/* =============================================================================
   音效调音台 · 逻辑
   -----------------------------------------------------------------------------
   它是什么：`scripts/audio/SfxProfile.gd` 的网页操作面。逐条试听 / 调音量 / 开关，
   点「保存并写入游戏」就把结果写进 `user://sfx_profile.json` —— 游戏下次启动（以及下次
   `Sfx.setup()`）按这份配置发声。

   三条硬规矩（都有对应的游戏侧实现，别在页面里"发明"第二种语义）：
   1) 「关闭」= 游戏里真的不播：Sfx._peek() 直接返回空，连节流记账都不做。
      所以关闭的那一行**在页面上也点不响** —— 这不是 bug，是让你先听见"关掉的样子"。
   2) 音量是**偏移**（dB），不是绝对音量。实际听到的 =
      总音量（Master 总线）+ 分类音量 + 音色基准音量（SfxSynth.SPECS）+ 本页的单条偏移。
      页面上两个数字都给：左边是偏移，右边是"实际"。
   3) 音量范围与记录条数上限来自 manifest.json（由 tools/sfx_studio_export.gd 从
      SfxProfile 的常量导出），页面不自己写死，改了 GDScript 重导一次即可。

   两种运行方式：
   · start.ps1 / serve.py 起本地服务 → 能读能写 user:// 里的真文件（推荐，保存即进游戏）。
   · 直接双击 index.html（file://）→ 退化成 localStorage 暂存 + 导出 JSON 手动放过去；
     连音频也会退化成 <audio> 播放（fetch 在 file:// 下取不到素材），页面会提示。
   ============================================================================= */

/* 中文显示名。fallback 是 id 本身，所以漏一行不会出错，只是那一行显示成英文 id。
   与 scripts/audio/SfxSynth.gd 的 SPECS 注释一一对应。 */
const LABELS = {
  hit_light: "轻击命中", hit_heavy: "重击命中", hit_crit: "会心一击", proj_impact: "投射物命中",
  parry: "弹反成功", parry_reflect: "弹返投射物",
  dodge: "闪避", perfect_dodge: "完美闪避",
  step_a: "脚步（左）", step_b: "脚步（右）", step_heavy: "沉重脚步", jump: "起跳", land: "落地",
  hoof_a: "马蹄（前）", hoof_b: "马蹄（后）",
  hurt: "受击闷哼", roar: "二阶段怒吼", poise_break: "破防",
  sword_wave: "剑气出手", charge_full: "蓄力蓄满",
  warn_parry: "预警：可弹反", warn_danger: "预警：不可弹反",
  encounter: "遭遇弹出", order: "行军号角", battle_start: "战斗开始",
  result_win: "胜利", result_lose: "战败", ui_back: "撤退 / 返回",
};
const CAT_LABELS = { combat: "打击", parry: "弹反", move: "移动", voice: "人声", ui: "界面" };
const CAT_ORDER = ["combat", "parry", "move", "voice", "ui"];
const BGM_LABELS = { map: "大地图", battle: "战斗" };
const LS_KEY = "warband.sfx_studio.profile";
const MAX_VOICES = 12;

const $ = (id) => document.getElementById(id);

/* 全部页面状态。
   state 是**完整**状态（每个字段都有值，便于计算与比较）；
   写进文件的却是**稀疏**状态（sparseState()）—— 只记你真正动过的条目，
   这样以后新增音色或改工程默认音量时，老配置不会把它们钉在 0 dB。 */
const M = {
  manifest: null,
  mode: "local",        // "server" | "local"
  server: null,
  state: null,
  records: [],
  undo: null,           // { at, state }：上一次回滚之前的状态，可撤销
  dirty: false,
  filter: { cat: "all", q: "", onlyOff: false, onlyTuned: false },
  rows: new Map(),      // id -> 行内 DOM 引用
};
let seq = 0;            // 本次会话的保存序号（记录命名用）

/* ---------------------------------------------------------------- 小工具 */
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const r1 = (v) => Math.round(v * 10) / 10;
const num = (v, d) => (typeof v === "number" && isFinite(v) ? v : d);
const bool = (v, d) => (typeof v === "boolean" ? v : d);
const eq = (a, b) => Math.abs(a - b) < 0.05;
const dbToGain = (db) => Math.pow(10, db / 20);
const fmt = (db) => (db > 0 ? "+" : "") + db.toFixed(1) + " dB";
const pad = (n) => String(n).padStart(2, "0");

function nowStr() {
  const d = new Date();
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + " " +
         pad(d.getHours()) + ":" + pad(d.getMinutes()) + ":" + pad(d.getSeconds());
}
function stamp() {
  return nowStr().replace(/[-: ]/g, "");
}
let toastTimer = null;
function toast(msg, kind) {
  const t = $("toast");
  t.textContent = msg;
  t.className = "toast" + (kind ? " " + kind : "");
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, 3200);
}
function banner(html, kind) {
  const b = $("banner");
  if (!html) { b.hidden = true; return; }
  b.innerHTML = html;
  b.className = "banner" + (kind ? " " + kind : "");
  b.hidden = false;
}
function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

/* ---------------------------------------------------------------- 音频 */
let AC = null;
const buffers = new Map();   // url -> Promise<AudioBuffer>
const fallbackVoices = [];   // file:// 模式下的 <audio> 播放器
const voices = [];
let bgm = null;              // { url, src, gain, rate }

function ctx() {
  if (!AC) {
    const C = window.AudioContext || window.webkitAudioContext;
    if (!C) throw new Error("这个浏览器没有 Web Audio（试听需要 Chrome / Edge / Firefox）");
    AC = new C();
  }
  if (AC.state === "suspended") AC.resume();
  return AC;
}

/* 取音频素材并解码；同一个文件只解一次 */
function buffer(url) {
  if (buffers.has(url)) return buffers.get(url);
  const pr = fetch(url, { cache: "force-cache" })
    .then((r) => {
      if (!r.ok) throw new Error(url + " → HTTP " + r.status);
      return r.arrayBuffer();
    })
    .then((ab) => new Promise((ok, no) => {
      // Safari 老版本只认回调形式，这里两种都给
      const p = ctx().decodeAudioData(ab, ok, no);
      if (p && p.then) p.then(ok, no);
    }));
  buffers.set(url, pr);
  pr.catch(() => buffers.delete(url));
  return pr;
}

/* 一次性播放（试听）。g 是线性增益，rate 是 playbackRate。 */
async function playOnce(url, db, rate) {
  const gain = dbToGain(db);
  stopVoiceOf(url);
  try {
    const buf = await buffer(url);
    const c = ctx();
    const src = c.createBufferSource();
    src.buffer = buf;
    src.playbackRate.value = rate || 1;
    const g = c.createGain();
    g.gain.value = gain;
    src.connect(g).connect(c.destination);
    const rec = { url, src, g };
    src.onended = () => {
      const i = voices.indexOf(rec);
      if (i >= 0) voices.splice(i, 1);
    };
    voices.push(rec);
    trimVoices();
    src.start();
    return rec;
  } catch (e) {
    // file:// 直接打开时 fetch 会被拦（origin null）：退回 <audio>。
    // 音量只能 0..1，>0 dB 的增益体现不出来 —— 页面顶部横幅里会说明。
    const a = new Audio(url);
    a.volume = Math.min(1, gain);
    a.playbackRate = rate || 1;
    fallbackVoices.push(a);
    a.onended = () => { const i = fallbackVoices.indexOf(a); if (i >= 0) fallbackVoices.splice(i, 1); };
    await a.play();
    return { url, el: a };
  }
}
function stopVoiceOf(url) {
  for (let i = voices.length - 1; i >= 0; i--) {
    if (voices[i].url === url) { try { voices[i].src.stop(); } catch (e) {} voices.splice(i, 1); }
  }
}
function trimVoices() {
  while (voices.length > MAX_VOICES) {
    const v = voices.shift();
    try { v.src.stop(); } catch (e) {}
  }
}
function stopAll() {
  for (const v of voices.splice(0)) { try { v.src.stop(); } catch (e) {} }
  for (const a of fallbackVoices.splice(0)) { try { a.pause(); } catch (e) {} }
  stopBgm();
}
function stopBgm() {
  if (!bgm) return;
  try { bgm.src.stop(); } catch (e) {}
  bgm = null;
  for (const [, r] of M.rows) r.row.classList.remove("playing");
}

/* ---------------------------------------------------------------- 配置读写 */
function specOf(id) { return M.manifest.byId[id]; }
function catRest(cat) {
  const c = M.manifest.catById[cat];
  return c ? c.rest_db : 0;
}
function bgmDef(track) {
  const b = M.manifest.bgmById[track];
  return b || { db: 0, fade: 1 };
}
function entry(id) {
  return M.state.sfx[id] || { enabled: true, db: 0 };
}
function isOn(id) { return entry(id).enabled; }

/* 实际听到的音量（不含调用方的 extra） */
function finalDb(id) {
  const s = specOf(id);
  return r1(M.state.master_db + M.state.categories[s.cat] + s.db + entry(id).db);
}

/* 把任意来源的 state 补成完整状态 */
function normState(raw) {
  const d = M.manifest.defaults;
  const rs = (raw && raw.state) ? raw.state : (raw || {});
  const out = {
    master_db: num(rs.master_db, d.master_db),
    categories: {},
    bgm: {},
    sfx: {},
  };
  const rc = rs.categories || {};
  for (const c of CAT_ORDER) out.categories[c] = num(rc[c], catRest(c));
  const rb = rs.bgm || {};
  for (const t in M.manifest.bgmById) {
    const one = rb[t] || {};
    out.bgm[t] = { db: num(one.db, bgmDef(t).db), enabled: bool(one.enabled, true) };
  }
  const rx = rs.sfx || {};
  for (const p of M.manifest.sfx) {
    const one = rx[p.id];
    if (one === undefined) { out.sfx[p.id] = { enabled: true, db: 0 }; continue; }
    if (typeof one === "boolean") { out.sfx[p.id] = { enabled: one, db: 0 }; continue; }
    out.sfx[p.id] = { enabled: bool(one.enabled, true), db: num(one.db, 0) };
  }
  return out;
}

/* 只有非默认值才写进文件。实现在下方 sparseOf()（记录回滚时也要重新稀疏化）。 */
function sparseState() {
  return sparseOf(M.state);
}
function payload() {
  return {
    schema: M.manifest.profile_schema,
    version: 1,
    saved_at: nowStr(),
    generator: "tools/sfx_studio (web)",
    records: M.records.map((r) => ({ id: r.id, saved_at: r.saved_at, name: r.name, summary: r.summary, state: r.state })),
    undo: M.undo ? { at: M.undo.at, state: M.undo.state } : null,
    state: sparseState(),
  };
}
/* ---------------------------------------------------------------- 读盘 */
async function loadManifest() {
  const r = await fetch("manifest.json", { cache: "no-store" });
  if (!r.ok) throw new Error("读不到 manifest.json（HTTP " + r.status + "）—— 先跑 tools/sfx_studio/start.ps1");
  M.manifest = await r.json();
  buildIndex();
}
function buildIndex() {
  const m = M.manifest;
  m.byId = {}; for (const p of m.sfx) m.byId[p.id] = p;
  m.catById = {}; for (const c of m.categories) m.catById[c.id] = c;
  m.bgmById = {}; for (const b of m.bgm) m.bgmById[b.id] = b;
  M.lim = { master: m.limits.master, category: m.limits.category, sfx: m.limits.sfx };
}

async function loadProfile() {
  try {
    const r = await fetch("api/health", { cache: "no-store" });
    if (r.ok) { M.server = await r.json(); M.mode = "server"; }
  } catch (e) { M.mode = "local"; }
  if (M.mode === "server") {
    const r = await fetch("api/profile", { cache: "no-store" });
    if (!r.ok) throw new Error("读配置失败（HTTP " + r.status + "）");
    const j = await r.json();
    M.state = normState(j.profile || {});
    M.records = normRecords(j.profile && j.profile.records);
    M.undo = normUndo(j.profile && j.profile.undo);
    return j;
  }
  let raw = null;
  try { raw = JSON.parse(localStorage.getItem(LS_KEY) || "null"); } catch (e) { raw = null; }
  M.state = normState(raw || {});
  M.records = normRecords(raw && raw.records);
  M.undo = normUndo(raw && raw.undo);
  return { exists: !!raw, path: null };
}

function normRecords(list) {
  const out = [];
  if (!Array.isArray(list)) return out;
  for (const r of list) {
    if (!r || typeof r !== "object" || !r.state) continue;
    out.push({
      id: String(r.id || "rec_" + out.length),
      saved_at: String(r.saved_at || ""),
      name: String(r.name || "未命名"),
      summary: String(r.summary || ""),
      state: sparseOf(normState(r.state)),
    });
    if (out.length >= M.manifest.record_limit) break;
  }
  return out;
}
function normUndo(u) {
  if (!u || typeof u !== "object" || !u.state) return null;
  return { at: String(u.at || ""), state: sparseOf(normState(u.state)) };
}

async function persist() {
  const body = payload();
  if (M.mode === "server") {
    const r = await fetch("api/profile", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok || !j.ok) throw new Error(j.error || ("写入失败（HTTP " + r.status + "）"));
    M.dirty = false;
    return j.path || (M.server && M.server.profilePath) || "";
  }
  localStorage.setItem(LS_KEY, JSON.stringify(body));
  M.dirty = false;
  return "";
}

/* ---------------------------------------------------------------- 差异摘要 */
function fmtSigned(v) { return (v > 0 ? "+" : "") + v.toFixed(1); }
function short(arr) {
  return arr.length <= 3 ? arr.join("、") : arr.slice(0, 2).join("、") + "…共 " + arr.length + " 条";
}
function diffSummary(before, after) {
  const a = normState(before || {});
  const b = normState(after || {});
  const off = [], on = [], tuned = [];
  for (const p of M.manifest.sfx) {
    const x = a.sfx[p.id], y = b.sfx[p.id];
    if (x.enabled !== y.enabled) (y.enabled ? on : off).push(p.id);
    if (!eq(x.db, y.db)) tuned.push(p.id + " " + fmtSigned(x.db) + "→" + fmtSigned(y.db));
  }
  const parts = [];
  if (off.length) parts.push("关闭 " + off.length + " 条（" + short(off) + "）");
  if (on.length) parts.push("打开 " + on.length + " 条（" + short(on) + "）");
  if (tuned.length) parts.push("音量 " + tuned.length + " 条（" + short(tuned) + "）");
  const dm = r1(b.master_db - a.master_db);
  if (dm) parts.push("总音量 " + fmt(dm));
  let dc = 0;
  for (const c of CAT_ORDER) if (!eq(a.categories[c], b.categories[c])) dc++;
  if (dc) parts.push("分类音量 " + dc + " 档");
  let dg = 0;
  for (const t in b.bgm) {
    if (a.bgm[t].enabled !== b.bgm[t].enabled || !eq(a.bgm[t].db, b.bgm[t].db)) dg++;
  }
  if (dg) parts.push("背景音乐 " + dg + " 项");
  return parts.length ? parts.join("；") : "与上一条相同";
}

/* ---------------------------------------------------------------- 渲染 */
function renderChips() {
  const box = $("catFilter");
  box.innerHTML = "";
  const mk = (key, label, n) => {
    const b = document.createElement("span");
    b.className = "chip" + (M.filter.cat === key ? " on" : "");
    b.innerHTML = esc(label) + '<span class="n">' + n + "</span>";
    b.onclick = () => { M.filter.cat = key; renderChips(); renderSfx(); };
    box.appendChild(b);
  };
  mk("all", "全部", M.manifest.sfx.length);
  const counts = {};
  for (const p of M.manifest.sfx) counts[p.cat] = (counts[p.cat] || 0) + 1;
  for (const c of CAT_ORDER) if (counts[c]) mk(c, CAT_LABELS[c] || c, counts[c]);
}

function pass(p) {
  if (M.filter.cat !== "all" && p.cat !== M.filter.cat) return false;
  const q = M.filter.q.trim().toLowerCase();
  if (q) {
    const hay = (p.id + " " + (LABELS[p.id] || "") + " " + (CAT_LABELS[p.cat] || "")).toLowerCase();
    if (hay.indexOf(q) < 0) return false;
  }
  const e = entry(p.id);
  if (M.filter.onlyOff && e.enabled) return false;
  if (M.filter.onlyTuned && eq(e.db, 0)) return false;
  return true;
}

function renderSfx() {
  const list = $("sfxList");
  list.innerHTML = "";
  M.rows.clear();
  const items = M.manifest.sfx.filter(pass).sort((a, b) => a.order - b.order);
  $("listCount").textContent = "显示 " + items.length + " / " + M.manifest.sfx.length + " 条音效";
  if (!items.length) {
    const d = document.createElement("div");
    d.className = "empty";
    d.textContent = "没有符合条件的音效（换个分类或清空搜索）";
    list.appendChild(d);
    return;
  }
  for (const p of items) list.appendChild(makeRow(p));
  refreshAll();
}

function makeRow(p) {
  const row = document.createElement("div");
  row.className = "row";
  row.dataset.id = p.id;

  const tog = document.createElement("button");
  tog.className = "tog";
  tog.title = "开 / 关：关闭 = 游戏里真的不播";
  tog.onclick = () => toggleSfx(p.id);

  const meta = document.createElement("div");
  meta.className = "meta";
  const nm = document.createElement("span");
  nm.className = "name";
  nm.textContent = LABELS[p.id] || p.id;
  const idc = document.createElement("code");
  idc.className = "id";
  idc.textContent = p.id;
  const tags = document.createElement("span");
  tags.className = "tags";
  const t1 = document.createElement("span");
  t1.className = "tag cat-" + p.cat;
  t1.textContent = CAT_LABELS[p.cat] || p.cat;
  tags.appendChild(t1);
  if (p.variants.length) {
    const t2 = document.createElement("span");
    t2.className = "tag";
    t2.textContent = p.variants.length + " 个录音变体";
    t2.title = "游戏里随机取一个变体播放（SfxFoley）";
    tags.appendChild(t2);
  }
  const t3 = document.createElement("span");
  t3.className = "tag";
  t3.textContent = "基准 " + fmtSigned(p.db) + " dB";
  t3.title = "SfxSynth.SPECS 里的设计音量，改动请改代码（这是「本来该多响」的基准）";
  tags.appendChild(t3);
  if (p.gap > 0) {
    const t4 = document.createElement("span");
    t4.className = "tag";
    t4.textContent = "间隔 " + Math.round(p.gap * 1000) + "ms";
    t4.title = "游戏里的同音最短间隔（Sfx._peek 节流）；试听不受它限制";
    tags.appendChild(t4);
  }
  meta.append(nm, idc, tags);

  const rng = document.createElement("input");
  rng.type = "range";
  rng.min = M.lim.sfx[0];
  rng.max = M.lim.sfx[1];
  rng.step = 0.5;
  rng.title = "这条音效的音量偏移（dB）；双击回到 0";
  rng.oninput = () => setDb(p.id, parseFloat(rng.value));
  rng.ondblclick = () => setDb(p.id, 0);

  const outOff = document.createElement("output");
  outOff.className = "num off";

  const outFin = document.createElement("span");
  outFin.className = "final";

  const play = document.createElement("button");
  play.className = "play";
  play.textContent = "▶";
  play.title = "试听";
  play.onclick = () => preview(p.id);

  const rst = document.createElement("button");
  rst.className = "mini";
  rst.textContent = "↺";
  rst.title = "这一条恢复工程默认（打开 + 0 dB）";
  rst.style.padding = "4px 0";
  rst.onclick = () => resetSfx(p.id);

  row.append(tog, meta, rng, outOff, outFin, play, rst);

  if (p.variants.length) {
    const v = document.createElement("div");
    v.className = "variants";
    const lab = document.createElement("span");
    lab.className = "lab";
    lab.textContent = "逐个变体：";
    v.appendChild(lab);
    p.variants.forEach((url, i) => {
      const c = document.createElement("span");
      c.className = "vchip";
      c.textContent = "#" + (i + 1);
      c.title = url;
      c.onclick = () => preview(p.id, i);
      v.appendChild(c);
    });
    row.appendChild(v);
  }

  M.rows.set(p.id, { row, tog, rng, outOff, outFin, play, rst });
  return row;
}

function refreshRow(id) {
  const r = M.rows.get(id);
  if (!r) return;
  const p = specOf(id), e = entry(id), on = e.enabled;
  r.tog.textContent = on ? "开" : "关";
  r.tog.classList.toggle("on", on);
  r.row.classList.toggle("disabled", !on);
  if (document.activeElement !== r.rng) r.rng.value = e.db;
  r.rng.disabled = !on;
  r.outOff.textContent = on ? fmtSigned(e.db) : "—";
  const fin = finalDb(id);
  r.outFin.textContent = "实际 " + fmt(fin);
  r.outFin.classList.toggle("hot", fin > 0);
  r.play.disabled = !on;
  r.play.title = on ? "试听" : "已关闭：游戏里不会播放，这里也听不到";
  r.rst.disabled = on && eq(e.db, 0);
  const vbox = r.row.querySelector(".variants");
  if (vbox) {
    vbox.style.opacity = on ? "1" : ".4";
    vbox.style.pointerEvents = on ? "auto" : "none";
  }
}

function refreshAll() {
  for (const id of M.rows.keys()) refreshRow(id);
  $("masterRange").value = M.state.master_db;
  $("masterOut").textContent = fmt(M.state.master_db);
  renderCatVolumes();
  renderBgm();
  refreshDirty();
}

function renderCatVolumes() {
  const box = $("catVolumes");
  box.innerHTML = "";
  for (const c of CAT_ORDER) {
    const row = document.createElement("div");
    row.className = "catrow";
    const lab = document.createElement("span");
    lab.textContent = CAT_LABELS[c] || c;
    const rng = document.createElement("input");
    rng.type = "range";
    rng.min = M.lim.category[0]; rng.max = M.lim.category[1]; rng.step = 0.5;
    rng.value = M.state.categories[c];
    rng.oninput = () => { M.state.categories[c] = parseFloat(rng.value); out.textContent = fmtSigned(M.state.categories[c]); M.dirty = true; refreshRowsOnly(); };
    const out = document.createElement("output");
    out.className = "num";
    out.textContent = fmtSigned(M.state.categories[c]);
    const rst = document.createElement("button");
    rst.className = "mini";
    rst.textContent = "↺";
    rst.style.padding = "3px 0";
    rst.title = "回到工程默认 " + fmtSigned(catRest(c)) + " dB";
    rst.onclick = () => { M.state.categories[c] = catRest(c); M.dirty = true; refreshAll(); };
    row.append(lab, rng, out, rst);
    box.appendChild(row);
  }
}

/* 只更新"实际 dB"这类派生数字：拖分类 / 总音量滑杆时全量重渲染会打断拖动 */
function refreshRowsOnly() {
  for (const id of M.rows.keys()) {
    const r = M.rows.get(id);
    const fin = finalDb(id);
    r.outFin.textContent = "实际 " + fmt(fin);
    r.outFin.classList.toggle("hot", fin > 0);
  }
  refreshDirty();
}

function renderBgm() {
  const box = $("bgmList");
  box.innerHTML = "";
  for (const b of M.manifest.bgm) {
    const v = M.state.bgm[b.id];
    const row = document.createElement("div");
    row.className = "bgmrow";
    const lab = document.createElement("span");
    lab.textContent = BGM_LABELS[b.id] || b.id;
    const tog = document.createElement("button");
    tog.className = "tog" + (v.enabled ? " on" : "");
    tog.textContent = v.enabled ? "开" : "关";
    tog.style.width = "34px";
    tog.onclick = () => { M.state.bgm[b.id].enabled = !M.state.bgm[b.id].enabled; M.dirty = true; renderBgm(); refreshDirty(); };
    const rng = document.createElement("input");
    rng.type = "range";
    rng.min = M.lim.master[0]; rng.max = M.lim.master[1]; rng.step = 0.5;
    rng.value = v.db;
    rng.disabled = !v.enabled;
    const out = document.createElement("output");
    out.className = "num";
    out.textContent = fmtSigned(v.db);
    rng.oninput = () => { M.state.bgm[b.id].db = parseFloat(rng.value); out.textContent = fmtSigned(M.state.bgm[b.id].db); M.dirty = true; refreshDirty(); };
    const play = document.createElement("button");
    play.className = "play";
    play.textContent = "▶";
    play.disabled = !v.enabled || !b.exists;
    play.title = b.exists ? "循环试听这首曲子" : "素材缺失：" + b.path;
    play.onclick = () => previewBgm(b.id);
    const rst = document.createElement("button");
    rst.className = "mini";
    rst.textContent = "↺";
    rst.style.padding = "3px 0";
    rst.onclick = () => { M.state.bgm[b.id].db = bgmDef(b.id).db; M.state.bgm[b.id].enabled = true; M.dirty = true; renderBgm(); refreshDirty(); };
    row.append(lab, tog, rng, out, play, rst);
    box.appendChild(row);
  }
}

function renderRecords() {
  const box = $("recordList");
  box.innerHTML = "";
  $("recordCount").textContent = "（" + M.records.length + " / " + M.manifest.record_limit + " 条）";
  if (M.undo) {
    const d = document.createElement("div");
    d.className = "rec cur";
    const a = document.createElement("span");
    a.className = "idx";
    a.textContent = "↩";
    const w = document.createElement("span");
    w.className = "when";
    w.textContent = M.undo.at || "";
    const t = document.createElement("span");
    t.className = "what";
    t.textContent = "回滚前的状态（点右边可撤销这次回滚）";
    const ops = document.createElement("span");
    ops.className = "ops";
    const b = document.createElement("button");
    b.className = "mini";
    b.textContent = "撤销回滚";
    b.onclick = () => undoRollback();
    ops.appendChild(b);
    d.append(a, w, t, ops);
    box.appendChild(d);
  }
  if (!M.records.length) {
    const e = document.createElement("div");
    e.className = "empty";
    e.textContent = "还没有保存记录。调好之后点下面的「保存并写入游戏」——每次保存记一条，最多 10 条。";
    box.appendChild(e);
    return;
  }
  const cur = JSON.stringify(sparseState());
  M.records.forEach((r, i) => {
    const d = document.createElement("div");
    d.className = "rec" + (JSON.stringify(r.state) === cur ? " cur" : "");
    const idx = document.createElement("span");
    idx.className = "idx";
    idx.textContent = "#" + (i + 1);
    const w = document.createElement("span");
    w.className = "when";
    w.textContent = r.saved_at;
    const t = document.createElement("span");
    t.className = "what";
    const n = document.createElement("span");
    n.className = "nm";
    n.textContent = r.name;
    t.append(n, document.createTextNode(r.summary || ""));
    t.title = r.summary || "";
    const ops = document.createElement("span");
    ops.className = "ops";
    const rb = document.createElement("button");
    rb.className = "mini";
    rb.textContent = "回滚";
    rb.title = "把这一条记录的全部设置搬回当前状态（并立刻写入游戏）";
    rb.onclick = () => rollback(i);
    const del = document.createElement("button");
    del.className = "mini";
    del.textContent = "删除";
    del.onclick = () => { M.records.splice(i, 1); renderRecords(); persist().then(() => toast("已删除第 #" + (i + 1) + " 条记录", "ok")).catch(errToast); };
    ops.append(rb, del);
    d.append(idx, w, t, ops);
    box.appendChild(d);
  });
}
/* ---------------------------------------------------------------- 动作 */
function errToast(e) { toast(String(e && e.message ? e.message : e), "err"); }

function flash(id) {
  const r = M.rows.get(id);
  if (!r) return;
  r.row.classList.add("playing");
  setTimeout(() => r.row.classList.remove("playing"), 280);
}

function toggleSfx(id) {
  const e = entry(id);
  M.state.sfx[id] = { enabled: !e.enabled, db: e.db };
  M.dirty = true;
  refreshRow(id);
  refreshDirty();
  renderRecords();
}

function setDb(id, v) {
  const lim = M.lim.sfx;
  const e = entry(id);
  M.state.sfx[id] = { enabled: e.enabled, db: r1(clamp(v, lim[0], lim[1])) };
  M.dirty = true;
  refreshRow(id);
  refreshDirty();
  renderRecords();
}

function resetSfx(id) {
  M.state.sfx[id] = { enabled: true, db: 0 };
  M.dirty = true;
  refreshRow(id);
  refreshDirty();
  renderRecords();
}

async function preview(id, variantIdx) {
  const p = specOf(id);
  if (!isOn(id)) { toast("「" + (LABELS[id] || id) + "」已被关闭：游戏里不会播放，所以这里也听不到", "err"); return; }
  let url = p.preview;
  if (p.variants.length) {
    url = (variantIdx === undefined)
      ? p.variants[Math.floor(Math.random() * p.variants.length)]
      : p.variants[variantIdx];
  }
  const db = finalDb(id);
  try {
    await playOnce(url, db, p.pitch || 1);
    flash(id);
  } catch (e) { errToast(e); }
}

async function previewBgm(id) {
  const b = M.manifest.bgmById[id];
  if (bgm && bgm.id === id) { stopBgm(); toast("已停止试听背景音乐"); return; }
  stopBgm();
  const v = M.state.bgm[id];
  if (!v.enabled) { toast("「" + (BGM_LABELS[id] || id) + "」已在背景音乐里关闭", "err"); return; }
  // 音乐三层：Master 总线（总音量）+ Music 总线（bgm_db）+ 单曲偏移（bgm_map_db / bgm_battle_db）
  const db = r1(M.state.master_db + num(M.manifest.defaults.bgm_db, 0) + v.db);
  const gain = dbToGain(db);
  try {
    const buf = await buffer(b.path);
    const c = ctx();
    const src = c.createBufferSource();
    src.buffer = buf;
    src.loop = true;
    const g = c.createGain();
    g.gain.value = gain;
    src.connect(g).connect(c.destination);
    src.start();
    bgm = { id, src, g };
    toast("循环试听「" + (BGM_LABELS[id] || id) + "」 " + fmt(db) + "（再点一次停止）", "ok");
  } catch (e) {
    try {
      const a = new Audio(b.path);
      a.loop = true;
      a.volume = Math.min(1, gain);
      await a.play();
      bgm = { id, el: a };
      toast("循环试听「" + (BGM_LABELS[id] || id) + "」（<audio> 兜底）", "ok");
    } catch (e2) { errToast(e2); }
  }
}

/* 只有非默认值才写进文件；对任意"完整状态"都适用（记录回滚时也要重新稀疏化） */
function sparseOf(st) {
  const s = { master_db: r1(st.master_db), categories: {}, bgm: {}, sfx: {} };
  for (const c of CAT_ORDER) {
    if (!eq(st.categories[c], catRest(c))) s.categories[c] = r1(st.categories[c]);
  }
  for (const t in st.bgm) {
    const v = st.bgm[t];
    if (!eq(v.db, bgmDef(t).db) || !v.enabled) s.bgm[t] = { db: r1(v.db), enabled: v.enabled };
  }
  for (const p of M.manifest.sfx) {
    const v = st.sfx[p.id] || { enabled: true, db: 0 };
    if (!v.enabled || !eq(v.db, 0)) s.sfx[p.id] = { enabled: v.enabled, db: r1(v.db) };
  }
  return s;
}

async function saveRecord() {
  const typed = $("saveName").value.trim();
  const prev = M.records.length ? M.records[0].state : null;
  seq++;
  const st = sparseState();
  const rec = {
    id: "rec_" + stamp() + "_" + seq,
    saved_at: nowStr(),
    name: typed || ("第 " + seq + " 次保存"),
    summary: diffSummary(prev, st),
    state: st,
  };
  M.records.unshift(rec);
  while (M.records.length > M.manifest.record_limit) M.records.pop();
  $("saveName").value = "";
  $("saveBtn").classList.add("busy");
  try {
    const path = await persist();
    renderRecords();
    refreshDirty();
    toast(path ? ("已保存并写入游戏：" + path) : "已保存（浏览器暂存；未连服务，游戏读不到）", "ok");
  } catch (e) {
    errToast(e);
  } finally {
    $("saveBtn").classList.remove("busy");
  }
}

async function rollback(i) {
  const r = M.records[i];
  if (!r) return;
  M.undo = { at: nowStr(), state: sparseState() };
  M.state = normState(r.state);
  try {
    await persist();
    refreshAll();
    renderRecords();
    toast("已回滚到 #" + (i + 1) + "「" + r.name + "」并写入游戏", "ok");
  } catch (e) { errToast(e); }
}

async function undoRollback() {
  if (!M.undo) return;
  M.state = normState(M.undo.state);
  M.undo = null;
  try {
    await persist();
    refreshAll();
    renderRecords();
    toast("已撤销上一次回滚", "ok");
  } catch (e) { errToast(e); }
}

function exportJson() {
  const blob = new Blob([JSON.stringify(payload(), null, 2)], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "sfx_profile.json";
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 4000);
  toast("已导出 sfx_profile.json（放到游戏 user:// 目录即可生效）", "ok");
}

function importJson(file) {
  const fr = new FileReader();
  fr.onload = async () => {
    let raw = null;
    try { raw = JSON.parse(String(fr.result)); } catch (e) { errToast(new Error("这个文件不是合法 JSON")); return; }
    if (!raw || typeof raw !== "object" || !raw.state) { errToast(new Error("JSON 里没有 state 字段，不像是调音台导出的配置")); return; }
    M.state = normState(raw.state);
    M.records = normRecords(raw.records);
    M.undo = normUndo(raw.undo);
    try {
      await persist();
      refreshAll();
      renderRecords();
      toast("已导入并写入游戏（记录 " + M.records.length + " 条）", "ok");
    } catch (e) { errToast(e); }
  };
  fr.onerror = () => errToast(new Error("读文件失败"));
  fr.readAsText(file, "utf-8");
}

function refreshDirty() {
  $("dirtyBadge").hidden = !M.dirty;
  $("saveHint").textContent = M.dirty ? "改动还没保存 —— 点左边按钮写入游戏（会记一条）" : "";
}

/* ---------------------------------------------------------------- 接线 */
function wire() {
  $("masterRange").oninput = (ev) => {
    M.state.master_db = r1(parseFloat(ev.target.value));
    $("masterOut").textContent = fmt(M.state.master_db);
    M.dirty = true;
    refreshRowsOnly();
  };
  $("masterReset").onclick = () => {
    M.state.master_db = num(M.manifest.defaults.master_db, 0);
    M.dirty = true;
    refreshAll();
  };
  $("search").oninput = (ev) => { M.filter.q = ev.target.value; renderSfx(); };
  $("onlyOff").onchange = (ev) => { M.filter.onlyOff = ev.target.checked; renderSfx(); };
  $("onlyTuned").onchange = (ev) => { M.filter.onlyTuned = ev.target.checked; renderSfx(); };
  $("allOn").onclick = () => {
    for (const p of M.manifest.sfx) M.state.sfx[p.id] = { enabled: true, db: entry(p.id).db };
    M.dirty = true;
    refreshAll();
    renderRecords();
  };
  $("allOff").onclick = () => {
    for (const p of M.manifest.sfx) M.state.sfx[p.id] = { enabled: false, db: entry(p.id).db };
    M.dirty = true;
    refreshAll();
    renderRecords();
  };
  $("resetAll").onclick = () => {
    if (!confirm("把全部音效恢复工程默认（开关 + 音量，含分类与总音量）？\n保存记录不会被删除。")) return;
    M.state = normState({});
    M.dirty = true;
    refreshAll();
    renderRecords();
    toast("已恢复工程默认（记得点保存写入游戏）");
  };
  $("stopAll").onclick = () => { stopAll(); toast("已停止试听"); };
  $("saveBtn").onclick = () => { saveRecord(); };
  $("exportBtn").onclick = () => exportJson();
  $("importBtn").onclick = () => $("importFile").click();
  $("importFile").onchange = (ev) => {
    const f = ev.target.files && ev.target.files[0];
    if (f) importJson(f);
    ev.target.value = "";
  };
  document.addEventListener("keydown", (ev) => {
    if (ev.key === "Escape") { stopAll(); toast("已停止试听"); }
  });
  window.addEventListener("beforeunload", (ev) => {
    if (!M.dirty) return;
    ev.preventDefault();
    ev.returnValue = "";
  });
}

/* ---------------------------------------------------------------- 启动 */
async function init() {
  try {
    await loadManifest();
  } catch (e) {
    banner("<b>打不开清单 manifest.json</b>：" + esc(e && e.message ? e.message : e) +
      "<br>先在工程根目录跑一次 <code>tools/sfx_studio/start.ps1</code>（它会顺带导出清单）。", "err");
    errToast(e);
    return;
  }
  const m = M.manifest;
  $("projectName").textContent = m.project || "";
  $("engineInfo").textContent = "Godot " + (m.engine || "?") + " · " + m.sfx.length + " 条音效 · 采样率 " + m.sfx_rate + " Hz";
  $("masterRange").min = M.lim.master[0];
  $("masterRange").max = M.lim.master[1];
  wire();

  let info = null;
  try {
    info = await loadProfile();
  } catch (e) { errToast(e); }

  $("connBadge").textContent = M.mode === "server" ? "本地服务已连接" : "浏览器暂存";
  $("connBadge").className = "badge " + (M.mode === "server" ? "ok" : "warn");

  if (M.mode === "server") {
    const path = (info && info.path) || (M.server && M.server.profilePath) || "?";
    banner("<b>已连上本地服务</b>：保存会写入 <code>" + esc(path) + "</code>，" +
      ((info && info.exists) ? "已载入现有配置。" : "目前还没有配置文件（保存后生成）。") +
      " 游戏下次启动即按这份配置发声。", "ok");
  } else {
    banner("<b>没有连上本地服务</b> —— 现在只能暂存在这个浏览器里，保存不会进游戏。<br>" +
      "要真正写进游戏：关掉本页，在工程根目录运行 <code>tools\\sfx_studio\\start.ps1</code>，" +
      "再从它打开的地址使用（也可 <code>python tools/sfx_studio/serve.py --open</code>）。<br>" +
      "手动兜底：点「导出 JSON」，把 <code>sfx_profile.json</code> 放进 <code>%APPDATA%\\Godot\\app_userdata\\" +
      esc(m.project || "") + "\\</code>。");
  }
  renderChips();
  renderSfx();
  renderRecords();
  refreshAll();
  refreshDirty();
}

document.addEventListener("DOMContentLoaded", init);