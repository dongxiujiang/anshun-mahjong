(() => {
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  let latestRelease = null;
  let allRooms = [];
  let lookupMode = false;

  function formatUptime(sec) {
    const s = Math.max(0, Number(sec) || 0);
    const d = Math.floor(s / 86400);
    const h = Math.floor((s % 86400) / 3600);
    const m = Math.floor((s % 3600) / 60);
    if (d > 0) return `${d}天 ${h}小时`;
    if (h > 0) return `${h}小时 ${m}分`;
    return `${m}分 ${s % 60}秒`;
  }

  async function apiFetch(url, options = {}) {
    const resp = await fetch(url, { cache: "no-store", ...options });
    const text = await resp.text();
    let data = {};
    try {
      data = JSON.parse(text);
    } catch {
      data = { raw: text };
    }
    return { ok: resp.ok, status: resp.status, data };
  }

  function applyLatestRelease(rel) {
    latestRelease = rel;
    const dlBtn = $("primary-download-btn");
    const dlSize = $("primary-download-size");
    if (!rel) {
      $("meta-version").textContent = "待发布";
      dlSize.textContent = "";
      dlBtn.href = "#download";
      return;
    }
    $("hero-version-tag").textContent = `v${rel.version} · 协议 ${rel.protocol || 4}`;
    $("meta-version").textContent = `v${rel.version}${rel.version_code ? ` (Build ${rel.version_code})` : ""}`;
    $("meta-downloads").textContent = `${rel.downloads ?? 0} 次`;
    dlBtn.href = rel.download_url;
    dlSize.textContent = `v${rel.version} · ${rel.size_mb} MB`;
    if (rel.sha256) {
      $("meta-sha256").textContent = rel.sha256;
      $("hero-hash-box").style.display = "inline-flex";
    }
  }

  async function loadStatus() {
    try {
      const { ok, data } = await apiFetch("/v1/status");
      if (!ok) throw new Error(data.error || "status error");
      $("header-dot").className = "dot online";
      $("header-status-text").textContent = `服务在线 · ${data.rooms_active}/${data.rooms_max} 房`;
      $("stat-health").textContent = "运行正常";
      $("stat-health").style.color = "var(--jade)";
      $("stat-host").textContent = `${data.public_host} · 协议 ${data.protocol}`;
      $("stat-rooms").textContent = `${data.rooms_active} / ${data.rooms_max}`;
      $("stat-players").textContent = `${data.players_online} 人`;
      $("stat-voice").textContent = data.voice_configured ? "在线语音已就绪" : "基础语音可用";
      $("stat-records").textContent = `${data.records_archived} 局`;
      const bm = data.records_by_mode || {};
      $("stat-records-sub").textContent = `在线 ${bm.online || 0} · 单机 ${bm.solo || 0} · 历史 ${bm.lan || 0}`;
      $("stat-downloads").textContent = `${data.downloads_total ?? 0} 次`;
      $("stat-uptime").textContent = `运行时长：${formatUptime(data.uptime_seconds)}`;
      if (data.latest_release) applyLatestRelease(data.latest_release);
    } catch (err) {
      $("header-dot").className = "dot offline";
      $("header-status-text").textContent = "服务暂不可达";
      $("stat-health").textContent = "连接异常";
      $("stat-health").style.color = "var(--crimson-soft)";
    }
  }

  function renderRooms(rooms) {
    const box = $("rooms-container");
    if (!rooms || rooms.length === 0) {
      box.innerHTML = `<div class="empty-state" style="grid-column:1/-1">当前茶馆虚席以待，点击右侧「立即创建在线房间」即可开一桌新局。</div>`;
      return;
    }
    const winds = ["东", "南", "西", "北"];
    box.innerHTML = rooms.map((room) => {
      const seats = Array.isArray(room.seats) ? room.seats : [];
      const seatsHtml = [0, 1, 2, 3].map((i) => {
        const s = seats[i];
        const human = s && s.player_id;
        const name = human ? `${winds[i]} · ${esc(s.nickname || "牌友")}` : `${winds[i]} · 空座/人机`;
        return `<div class="seat-chip ${human ? "" : "empty"}">${name}</div>`;
      }).join("");
      const badge = room.started
        ? `<span class="tag playing">激战中</span>`
        : `<span class="tag">等待入座</span>`;
      return `
        <div class="room-card">
          <div class="room-head">
            <span class="room-name">${esc(room.name || "麻将局")}</span>
            ${badge}
          </div>
          <div class="room-meta">
            房号 <strong style="color:var(--gold-bright)">${esc(room.number)}</strong> · ${room.players}/4 真人 · ${esc(room.host)}:${room.port}
          </div>
          <div class="seats-row">${seatsHtml}</div>
        </div>
      `;
    }).join("");
  }

  async function loadRooms() {
    if (lookupMode) return;
    try {
      const { ok, data } = await apiFetch("/v1/rooms");
      if (!ok) throw new Error(data.error || "failed");
      allRooms = data.rooms || [];
      renderRooms(allRooms);
      const now = new Date();
      $("rooms-updated-at").textContent = `更新于 ${now.toTimeString().slice(0, 8)}`;
    } catch {
      $("rooms-container").innerHTML = `<div class="empty-state" style="grid-column:1/-1">房间列表读取失败，请点击「刷新房间」重试。</div>`;
    }
  }

  async function loadReleases() {
    const box = $("releases-container");
    try {
      const { ok, data } = await apiFetch("/v1/releases");
      if (!ok) throw new Error(data.error || "failed");
      const list = data.releases || [];
      if (list.length > 0 && !latestRelease) applyLatestRelease(list[0]);
      if (list.length === 0) {
        box.innerHTML = `<div class="empty-state">暂未上传客户端安装包，服务端上传 APK 后将自动显示在此处。</div>`;
        return;
      }
      box.innerHTML = list.map((rel, idx) => {
        const notes = (rel.changelog || []).map((line) => `<li>${esc(line)}</li>`).join("");
        return `
          <div class="release-item">
            <div>
              <h3>东秀麻将 v${esc(rel.version)} ${idx === 0 ? '<span class="tag" style="margin-left:8px;vertical-align:middle">推荐最新</span>' : ""}</h3>
              <div class="release-meta">
                <span>文件：<strong>${esc(rel.filename)}</strong></span>
                <span>大小：<strong>${rel.size_mb} MB</strong></span>
                <span>架构：<strong>${esc(rel.architecture)}</strong></span>
                <span>发布时间：<strong>${esc(rel.published_at || "-")}</strong></span>
                <span>下载：<strong>${rel.downloads ?? 0} 次</strong></span>
              </div>
              ${rel.sha256 ? `<div style="margin-top:6px;font-size:0.78rem;color:var(--muted);word-break:break-all">SHA-256：<code>${esc(rel.sha256)}</code></div>` : ""}
              ${notes ? `<ul class="changelog">${notes}</ul>` : ""}
            </div>
            <div style="display:flex;flex-direction:column;gap:8px;min-width:168px">
              <a class="btn ${idx === 0 ? "btn-primary" : ""}" href="${esc(rel.download_url)}">⬇ 下载 APK</a>
              <span style="font-size:0.76rem;color:var(--muted);text-align:center">${esc(rel.min_os)} · 协议 ${rel.protocol || 4}</span>
            </div>
          </div>
        `;
      }).join("");
    } catch {
      box.innerHTML = `<div class="empty-state">版本清单读取失败，请刷新页面重试。</div>`;
    }
  }

  async function lookupRoom() {
    const num = $("lookup-room-input").value.trim();
    const resBox = $("lookup-result");
    if (!/^[0-9]{4,8}$/.test(num)) {
      resBox.className = "form-result err";
      resBox.textContent = "请输入 4 至 8 位纯数字房间号。";
      return;
    }
    resBox.className = "form-result";
    const { ok, data } = await apiFetch(`/v1/rooms/${encodeURIComponent(num)}`);
    if (!ok) {
      resBox.className = "form-result err";
      resBox.textContent = data.error || "未找到该房间。";
      return;
    }
    lookupMode = true;
    $("clear-lookup-btn").style.display = "inline-flex";
    resBox.className = "form-result ok";
    resBox.textContent = `已找到房间 ${data.room.number}（${data.room.name}），当前 ${data.room.players}/4 真人在线。`;
    renderRooms([data.room]);
  }

  async function createRoom(event) {
    event.preventDefault();
    const btn = $("create-room-submit");
    const box = $("create-room-result");
    const name = $("room-name-input").value.trim();
    const number = $("room-number-input").value.trim();
    const difficulty = $("room-difficulty").value;
    const discardSec = Number($("room-discard-sec").value) || 15;
    const responseSec = Number($("room-response-sec").value) || 10;

    btn.disabled = true;
    btn.textContent = "正在拉起权威牌桌…";
    box.className = "form-result";
    try {
      const payload = {
        name,
        number,
        settings: {
          difficulty,
          discard_ms: Math.min(120000, Math.max(1000, Math.round(discardSec * 1000))),
          response_ms: Math.min(120000, Math.max(1000, Math.round(responseSec * 1000))),
        },
      };
      const { ok, status, data } = await apiFetch("/v1/rooms", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      if (!ok) {
        box.className = "form-result err";
        box.textContent = `创建失败（HTTP ${status}）：${data.error || "请检查参数后重试"}`;
      } else {
        const room = data.room;
        box.className = "form-result ok";
        box.innerHTML = `
          房间创建成功！房号：<strong style="font-size:1.15em;color:#fff">${esc(room.number)}</strong>
          （${esc(room.host)}:${room.port}）<br>
          请在手机端打开「东秀麻将」→「加入房间」输入房号即可入座。
        `;
        lookupMode = false;
        $("clear-lookup-btn").style.display = "none";
        await Promise.all([loadRooms(), loadStatus()]);
      }
    } catch (err) {
      box.className = "form-result err";
      box.textContent = "网络请求失败，请确认服务端在线。";
    } finally {
      btn.disabled = false;
      btn.textContent = "立即创建在线房间";
    }
  }

  async function inspectEndpoint(path, headers = {}) {
    $("api-result-title").textContent = `GET ${path}`;
    $("api-status-badge").textContent = "请求中…";
    $("api-status-badge").className = "tag";
    const t0 = performance.now();
    try {
      const { ok, status, data } = await apiFetch(path, { headers });
      const ms = Math.round(performance.now() - t0);
      $("api-status-badge").textContent = `HTTP ${status} · ${ms}ms`;
      $("api-status-badge").className = ok ? "tag" : "tag playing";
      $("api-json-output").textContent = JSON.stringify(data, null, 2);
    } catch (err) {
      $("api-status-badge").textContent = "网络错误";
      $("api-status-badge").className = "tag playing";
      $("api-json-output").textContent = JSON.stringify({ error: String(err) }, null, 2);
    }
  }

  // Event bindings
  $("refresh-rooms-btn").addEventListener("click", () => {
    lookupMode = false;
    $("clear-lookup-btn").style.display = "none";
    $("lookup-result").className = "form-result";
    loadRooms();
    loadStatus();
  });
  $("lookup-room-btn").addEventListener("click", lookupRoom);
  $("lookup-room-input").addEventListener("keydown", (e) => { if (e.key === "Enter") lookupRoom(); });
  $("clear-lookup-btn").addEventListener("click", () => {
    lookupMode = false;
    $("lookup-room-input").value = "";
    $("lookup-result").className = "form-result";
    $("clear-lookup-btn").style.display = "none";
    loadRooms();
  });
  $("create-room-form").addEventListener("submit", createRoom);

  $("copy-hash-btn").addEventListener("click", async () => {
    if (!latestRelease || !latestRelease.sha256) return;
    try {
      await navigator.clipboard.writeText(latestRelease.sha256);
      $("copy-hash-btn").textContent = "已复制";
      setTimeout(() => { $("copy-hash-btn").textContent = "复制"; }, 1600);
    } catch {
      $("copy-hash-btn").textContent = "请手动复制";
    }
  });

  document.querySelectorAll("[data-api]").forEach((btn) => {
    btn.addEventListener("click", () => inspectEndpoint(btn.getAttribute("data-api")));
  });
  $("query-records-btn").addEventListener("click", () => {
    const token = $("records-token-input").value.trim();
    inspectEndpoint("/v1/records?limit=10", token ? { Authorization: `Bearer ${token}` } : {});
  });

  // Lightbox
  const lightbox = $("lightbox");
  document.querySelectorAll(".shot-card").forEach((card) => {
    card.addEventListener("click", () => {
      $("lightbox-img").src = card.getAttribute("data-full");
      $("lightbox-caption").textContent = card.getAttribute("data-caption") || "";
      lightbox.classList.add("open");
    });
  });
  lightbox.addEventListener("click", () => lightbox.classList.remove("open"));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") lightbox.classList.remove("open"); });

  // Initial load & polling
  loadStatus();
  loadRooms();
  loadReleases();
  setInterval(() => { loadStatus(); loadRooms(); }, 8000);
})();
