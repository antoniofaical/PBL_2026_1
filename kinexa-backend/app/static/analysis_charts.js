const KX_CHART_THEME = {
  paper_bgcolor: "#121212",
  plot_bgcolor: "#191919",
  font: { color: "#ffffff", family: "JetBrains Mono, Consolas, monospace", size: 11 },
  xaxis: { gridcolor: "rgba(255,255,255,0.06)", zerolinecolor: "rgba(255,255,255,0.1)" },
  yaxis: { gridcolor: "rgba(255,255,255,0.06)", zerolinecolor: "rgba(255,255,255,0.1)" },
  legend: { bgcolor: "rgba(0,0,0,0)", orientation: "h", y: 1.12 },
  margin: { l: 52, r: 20, t: 44, b: 44 },
};

const EVENT_COLORS = {
  initial_contact: "#E30613",
  toe_off: "#FF434E",
  mid_swing: "#F1C40F",
  manual: "#2ECC71",
};

const QUALITY_LABELS = {
  good: "Boa",
  acceptable: "Aceitável",
  poor: "Ruim",
  unknown: "—",
};

const MIN_WINDOW_S = 3;

let chartHandles = null;

function parseJson(id, fallback) {
  const el = document.getElementById(id);
  if (!el) return fallback;
  try {
    return JSON.parse(el.textContent);
  } catch {
    return fallback;
  }
}

function plotArea(plotDiv) {
  const size = plotDiv._fullLayout._size;
  return { l: size.l, r: size.r, t: size.t, b: size.b, w: size.w, h: size.h };
}

function xAxisRange(plotDiv) {
  const xa = plotDiv._fullLayout.xaxis;
  return xa.range || xa._rl;
}

function xDataToPixel(plotDiv, xVal) {
  const area = plotArea(plotDiv);
  const range = xAxisRange(plotDiv);
  const span = range[1] - range[0] || 1;
  return area.l + ((xVal - range[0]) / span) * area.w;
}

function xPixelToData(plotDiv, px) {
  const area = plotArea(plotDiv);
  const range = xAxisRange(plotDiv);
  const span = range[1] - range[0] || 1;
  const ratio = (px - area.l) / area.w;
  return range[0] + ratio * span;
}

function eventShapes(events, tOriginMs) {
  const origin = tOriginMs || 0;
  return events.map((ev) => {
    const tSec = (ev.t_ms - origin) / 1000;
    const color = EVENT_COLORS[ev.type] || EVENT_COLORS[ev.source] || "#A0A0A0";
    return {
      type: "line",
      x0: tSec,
      x1: tSec,
      y0: 0,
      y1: 1,
      yref: "paper",
      line: { color, width: 1.5, dash: ev.source === "manual" ? "dot" : "solid" },
    };
  });
}

function windowShapes(startS, endS, recEndS) {
  const shapes = [];
  if (startS > 0) {
    shapes.push({
      type: "rect",
      x0: 0,
      x1: startS,
      y0: 0,
      y1: 1,
      yref: "paper",
      fillcolor: "rgba(0,0,0,0.45)",
      line: { width: 0 },
      layer: "below",
    });
  }
  shapes.push({
    type: "rect",
    x0: startS,
    x1: endS,
    y0: 0,
    y1: 1,
    yref: "paper",
    fillcolor: "rgba(227,6,19,0.08)",
    line: { color: "rgba(227,6,19,0.55)", width: 1 },
    layer: "below",
  });
  if (recEndS != null && endS < recEndS) {
    shapes.push({
      type: "rect",
      x0: endS,
      x1: recEndS,
      y0: 0,
      y1: 1,
      yref: "paper",
      fillcolor: "rgba(0,0,0,0.45)",
      line: { width: 0 },
      layer: "below",
    });
  }
  return shapes;
}

function allShapes(events, windowSel, tOriginMs, recEndS) {
  return [
    ...windowShapes(windowSel.startS, windowSel.endS, recEndS),
    ...eventShapes(events, tOriginMs),
  ];
}

function baseLayout(title, events, windowSel, tOriginMs, recEndS) {
  return {
    ...KX_CHART_THEME,
    title: { text: title, font: { size: 12, color: "#aaaaaa" } },
    shapes: allShapes(events, windowSel, tOriginMs, recEndS),
    hovermode: "x unified",
    dragmode: "zoom",
  };
}

function fmt1(n) {
  return Number(n).toFixed(1);
}

function fmt2(n) {
  return Number(n).toFixed(2);
}

function fmt3(n) {
  return Number(n).toFixed(3);
}

function isFullWindow(startS, endS, recStartS, recEndS) {
  return startS <= recStartS + 0.05 && endS >= recEndS - 0.05;
}

function updateWindowLabels(startS, endS) {
  const dur = endS - startS;
  const startEl = document.getElementById("window-start-label");
  const endEl = document.getElementById("window-end-label");
  const durEl = document.getElementById("window-duration-label");
  const startTag = document.getElementById("handle-start-tag");
  const endTag = document.getElementById("handle-end-tag");
  if (startEl) startEl.textContent = fmt2(startS);
  if (endEl) endEl.textContent = fmt2(endS);
  if (durEl) durEl.textContent = `(${fmt1(dur)} s)`;
  if (startTag) startTag.textContent = fmt2(startS);
  if (endTag) endTag.textContent = fmt2(endS);
}

function setWindowStatus(text, isError) {
  const el = document.getElementById("window-status");
  if (!el) return;
  el.textContent = text;
  el.classList.toggle("window-status-error", Boolean(isError));
}

function updateSummary(analysis) {
  const q = analysis.quality || {};
  const cad = analysis.cadence;
  const gct = analysis.gct;
  const det = analysis.detection || {};
  const win = analysis.window || {};

  const set = (id, val) => {
    const el = document.getElementById(id);
    if (el) el.textContent = val ?? "—";
  };

  set("stat-duration", q.duration_s != null ? fmt1(q.duration_s) : "—");
  set("stat-samples", q.sample_count ?? "—");
  set("stat-fs", q.mean_fs_hz != null ? Number(q.mean_fs_hz).toFixed(1) : "—");
  set("stat-cadence", cad?.cadence_spm ?? "—");
  set("stat-gct", gct?.mean_ms != null ? Math.round(gct.mean_ms) : "—");

  const qualEl = document.getElementById("stat-quality");
  if (qualEl) {
    qualEl.textContent = QUALITY_LABELS[q.quality_status] || "—";
    qualEl.className = `stat-badge stat-badge-${q.quality_status || "unknown"}`;
  }
  set("stat-gaps", `Qualidade · gaps ${q.gap_count ?? 0}`);

  const badge = document.getElementById("window-mode-badge");
  if (badge) badge.textContent = win.is_windowed ? "Trecho selecionado" : "Coleta completa";

  set("det-axis", det.axis ?? "—");
  set("det-status", det.status ?? "—");
  set("det-confidence", det.confidence != null ? `${Math.round(det.confidence * 100)}%` : "—");
  set("det-midswing", det.mid_swing_count ?? "—");
  set("det-steps", cad?.steps_detected ?? "—");

  const axisLabel = document.getElementById("detection-axis-label");
  if (axisLabel && det.axis) axisLabel.textContent = det.axis;

  const gctWarn = document.getElementById("gct-warn");
  if (gctWarn) gctWarn.hidden = !(gct && gct.status === "low_confidence");
}

function renderEventsTable(events) {
  const section = document.getElementById("events-content");
  if (!section) return;

  if (!events.length) {
    section.innerHTML =
      '<p class="empty-state" id="events-empty">Nenhum evento detectado no trecho — sinal pode não permitir detecção confiável.</p>';
    return;
  }

  const rows = events
    .map((ev) => {
      const conf = ev.confidence != null ? `${Math.round(ev.confidence * 100)}%` : "—";
      return `<tr>
        <td><code>${ev.type}</code></td>
        <td>${ev.t_ms}</td>
        <td>${fmt3(ev.t_ms / 1000)}</td>
        <td>${conf}</td>
        <td><span class="badge badge-${ev.source}">${ev.source}</span></td>
      </tr>`;
    })
    .join("");

  section.innerHTML = `<div class="table-wrap">
    <table class="data-table">
      <thead>
        <tr><th>Tipo</th><th>ms</th><th>s</th><th>Conf.</th><th>Fonte</th></tr>
      </thead>
      <tbody id="events-tbody">${rows}</tbody>
    </table>
  </div>`;
}

function savedAxisRanges(plotDiv) {
  if (!plotDiv?._fullLayout) return { xaxis: {}, yaxis: {} };
  const xaxis = {};
  const yaxis = {};
  const xRange = plotDiv._fullLayout.xaxis?.range;
  const yRange = plotDiv._fullLayout.yaxis?.range;
  if (xRange) xaxis.range = xRange.slice();
  if (yRange) yaxis.range = yRange.slice();
  return { xaxis, yaxis };
}

async function refreshChart(events, windowSel, chartData, preserveZoom = false) {
  if (!window.Plotly) return null;
  const plotDiv = document.getElementById("chart-gyro");
  const t = chartData.t;
  const recEndS = t.length ? t[t.length - 1] : windowSel.endS;
  const axis = chartData.detection_axis || "gy";
  const axisLabel = axis === "gy" ? "gy (Ωp)" : axis;

  const traces = [
    { x: t, y: chartData.gyro[axis], name: axisLabel, line: { color: "#E30613", width: 1.5 } },
  ];
  if (axis !== "gx") {
    traces.push({ x: t, y: chartData.gyro.gx, name: "gx", line: { color: "rgba(255,118,118,0.45)", width: 1 } });
  }
  if (axis !== "gy") {
    traces.push({ x: t, y: chartData.gyro.gy, name: "gy", line: { color: "rgba(255,67,78,0.45)", width: 1 } });
  }
  if (axis !== "gz") {
    traces.push({ x: t, y: chartData.gyro.gz, name: "gz", line: { color: "rgba(155,89,182,0.45)", width: 1 } });
  }

  const zoom = preserveZoom ? savedAxisRanges(plotDiv) : { xaxis: {}, yaxis: {} };
  const layout = {
    ...baseLayout("Velocidade angular (°/s) — método Falbriard", events, windowSel, chartData.t_origin_ms, recEndS),
    yaxis: { ...KX_CHART_THEME.yaxis, title: "°/s", ...zoom.yaxis },
    xaxis: { ...KX_CHART_THEME.xaxis, title: "tempo (s)", fixedrange: false, ...zoom.xaxis },
  };

  const config = { responsive: true, displayModeBar: true, displaylogo: false, scrollZoom: true };
  if (plotDiv.data) {
    await Plotly.react(plotDiv, traces, layout, config);
  } else {
    await Plotly.newPlot(plotDiv, traces, layout, config);
  }

  return plotDiv;
}

function syncUrlParams(startS, endS, recStartS, recEndS) {
  const url = new URL(window.location.href);
  if (isFullWindow(startS, endS, recStartS, recEndS)) {
    url.searchParams.delete("t0");
    url.searchParams.delete("t1");
  } else {
    url.searchParams.set("t0", fmt2(startS));
    url.searchParams.set("t1", fmt2(endS));
  }
  window.history.replaceState({}, "", url);
}

class ChartWindowHandles {
  constructor(state) {
    this.state = state;
    this.startS = state.startS;
    this.endS = state.endS;
    this.plotDiv = document.getElementById("chart-gyro");
    this.handleStart = document.getElementById("handle-start");
    this.handleEnd = document.getElementById("handle-end");
    this.dragging = null;
    this.applyTimer = null;
    this.init();
  }

  recEndS() {
    const t = this.state.chartData.t;
    return t.length ? t[t.length - 1] : this.endS;
  }

  clampWindow(startS, endS, anchor) {
    const { recStartS, recEndS } = this.state;
    startS = Math.max(recStartS, Math.min(startS, recEndS));
    endS = Math.max(recStartS, Math.min(endS, recEndS));
    if (endS - startS < MIN_WINDOW_S) {
      if (anchor === "start") startS = endS - MIN_WINDOW_S;
      else endS = startS + MIN_WINDOW_S;
      startS = Math.max(recStartS, startS);
      endS = Math.min(recEndS, endS);
    }
    return { startS, endS };
  }

  setWindow(startS, endS, anchor = "end", { relayout = true } = {}) {
    ({ startS, endS } = this.clampWindow(startS, endS, anchor));
    this.startS = startS;
    this.endS = endS;
    this.state.windowSel = { startS, endS };
    updateWindowLabels(startS, endS);

    if (relayout && this.plotDiv._fullLayout) {
      Plotly.relayout(this.plotDiv, {
        shapes: allShapes(
          this.state.events,
          this.state.windowSel,
          this.state.chartData.t_origin_ms,
          this.recEndS(),
        ),
      });
    }
    this.positionHandles();
  }

  positionHandles() {
    if (!this.plotDiv._fullLayout) return;
    const area = plotArea(this.plotDiv);
    const range = xAxisRange(this.plotDiv);
    const place = (el, xVal, offScreen) => {
      if (!el) return;
      let px = xDataToPixel(this.plotDiv, xVal);
      const clamped = px < area.l || px > area.l + area.w;
      px = Math.max(area.l, Math.min(area.l + area.w, px));
      el.style.left = `${px}px`;
      el.style.top = `${area.t}px`;
      el.style.height = `${area.h}px`;
      el.classList.toggle("chart-handle-offscreen", clamped || offScreen);
    };

    place(this.handleStart, this.startS, this.startS < range[0] - 0.01);
    place(this.handleEnd, this.endS, this.endS > range[1] + 0.01);
  }

  pointerToTime(clientX) {
    const rect = this.plotDiv.getBoundingClientRect();
    const px = clientX - rect.left;
    const { recStartS, recEndS } = this.state;
    const t = xPixelToData(this.plotDiv, px);
    return Math.max(recStartS, Math.min(recEndS, t));
  }

  bindHandle(el, anchor) {
    if (!el) return;

    const onMove = (e) => {
      if (this.dragging !== anchor) return;
      e.preventDefault();
      e.stopPropagation();
      const t = this.pointerToTime(e.clientX);
      if (anchor === "start") this.setWindow(t, this.endS, anchor);
      else this.setWindow(this.startS, t, anchor);
    };

    const onEnd = (e) => {
      if (this.dragging !== anchor) return;
      e.preventDefault();
      e.stopPropagation();
      this.dragging = null;
      el.classList.remove("chart-handle-active");
      document.body.classList.remove("chart-handle-dragging");
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onEnd);
      window.removeEventListener("pointercancel", onEnd);
      this.scheduleApply();
    };

    el.addEventListener("pointerdown", (e) => {
      e.preventDefault();
      e.stopPropagation();
      this.dragging = anchor;
      el.classList.add("chart-handle-active");
      document.body.classList.add("chart-handle-dragging");
      el.setPointerCapture?.(e.pointerId);
      window.addEventListener("pointermove", onMove);
      window.addEventListener("pointerup", onEnd);
      window.addEventListener("pointercancel", onEnd);
    });

    el.addEventListener("keydown", (e) => {
      const step = e.shiftKey ? 0.01 : 0.1;
      if (anchor === "start") {
        if (e.key === "ArrowLeft") { e.preventDefault(); this.setWindow(this.startS - step, this.endS, anchor); this.scheduleApply(); }
        if (e.key === "ArrowRight") { e.preventDefault(); this.setWindow(this.startS + step, this.endS, anchor); this.scheduleApply(); }
      } else {
        if (e.key === "ArrowLeft") { e.preventDefault(); this.setWindow(this.startS, this.endS - step, anchor); this.scheduleApply(); }
        if (e.key === "ArrowRight") { e.preventDefault(); this.setWindow(this.startS, this.endS + step, anchor); this.scheduleApply(); }
      }
    });
  }

  scheduleApply() {
    clearTimeout(this.applyTimer);
    this.applyTimer = setTimeout(() => this.applyWindow(), 350);
  }

  async applyWindow() {
    const { recStartS, recEndS, runId } = this.state;
    const { startS, endS } = this;

    if (endS - startS < MIN_WINDOW_S) {
      setWindowStatus("Trecho muito curto (mín. 3 s).", true);
      return;
    }

    setWindowStatus("Recalculando…", false);

    try {
      const url = `/api/runs/${runId}/analysis/window?start_s=${startS}&end_s=${endS}`;
      const resp = await fetch(url);
      const payload = await resp.json();
      if (!resp.ok) throw new Error(payload.detail || "Falha ao analisar trecho.");

      this.state.events = payload.events || [];
      updateSummary(payload);
      renderEventsTable(this.state.events);
      await refreshChart(this.state.events, this.state.windowSel, this.state.chartData, true);
      syncUrlParams(startS, endS, recStartS, recEndS);
      setWindowStatus("Trecho aplicado.", false);
      this.plotDiv = document.getElementById("chart-gyro");
      this.positionHandles();
    } catch (err) {
      setWindowStatus(err.message || "Erro ao analisar trecho.", true);
    }
  }

  resetToFull() {
    const { recStartS, recEndS } = this.state;
    this.setWindow(recStartS, recEndS, "end");
    this.scheduleApply();
  }

  init() {
    this.bindHandle(this.handleStart, "start");
    this.bindHandle(this.handleEnd, "end");

    this.plotDiv.on("plotly_relayout", () => this.positionHandles());
    this.plotDiv.on("plotly_redraw", () => this.positionHandles());
    this.plotDiv.on("plotly_afterplot", () => this.positionHandles());
    window.addEventListener("resize", () => this.positionHandles());

    document.getElementById("window-reset-btn")?.addEventListener("click", () => this.resetToFull());

    this.setWindow(this.startS, this.endS, "end", { relayout: false });
    requestAnimationFrame(() => this.positionHandles());
  }
}

async function renderCharts() {
  const chartData = parseJson("chart-data", null);
  const events = parseJson("events-data", []);
  const windowMeta = parseJson("window-data", {});
  const runMeta = parseJson("run-meta", {});
  if (!chartData || !window.Plotly) return;

  const t = chartData.t;
  const recStartS = t.length ? t[0] : 0;
  const recEndS = t.length ? t[t.length - 1] : 0;

  const params = new URLSearchParams(window.location.search);
  let startS = windowMeta.start_s ?? recStartS;
  let endS = windowMeta.end_s ?? recEndS;
  if (params.has("t0") && params.has("t1")) {
    startS = Number(params.get("t0"));
    endS = Number(params.get("t1"));
  }

  startS = Math.max(recStartS, Math.min(startS, recEndS));
  endS = Math.max(startS + MIN_WINDOW_S, Math.min(endS, recEndS));

  const windowSel = { startS, endS };
  const state = {
    runId: runMeta.run_id,
    chartData,
    events,
    windowSel,
    recStartS,
    recEndS,
    startS,
    endS,
  };

  await refreshChart(events, windowSel, chartData);
  chartHandles = new ChartWindowHandles(state);

  if (!isFullWindow(startS, endS, recStartS, recEndS)) {
    setTimeout(() => chartHandles.applyWindow(), 150);
  }
}

document.addEventListener("DOMContentLoaded", renderCharts);
