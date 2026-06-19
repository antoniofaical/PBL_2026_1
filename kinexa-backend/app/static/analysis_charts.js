const KX_CHART_THEME = {
  paper_bgcolor: "#121212",
  plot_bgcolor: "#191919",
  font: { color: "#ffffff", family: "JetBrains Mono, Consolas, monospace", size: 11 },
  xaxis: { gridcolor: "rgba(255,255,255,0.06)", zerolinecolor: "rgba(255,255,255,0.1)" },
  yaxis: { gridcolor: "rgba(255,255,255,0.06)", zerolinecolor: "rgba(255,255,255,0.1)" },
  legend: { bgcolor: "rgba(0,0,0,0)", orientation: "h", y: 1.14 },
  margin: { l: 52, r: 20, t: 40, b: 44 },
};

const EVENT_COLORS = {
  initial_contact: "#E30613",
  toe_off: "#FF8C00",
  mid_swing: "#F1C40F",
  manual: "#2ECC71",
  manual_marker: "#2ECC71",
};

const EVENT_LABELS = {
  initial_contact: "Contato inicial",
  toe_off: "Retirada do pé",
  mid_swing: "Meio do balanço",
  manual: "Marcação manual",
  manual_marker: "Marcação manual",
};

const DETECTION_STATUS_LABELS = {
  ok: "OK",
  no_metrics: "Sem métricas",
  insufficient_peaks: "Poucos ciclos",
  low_confidence: "Baixa confiança",
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

function fmt1(n) {
  return Number(n).toFixed(1);
}

function fmt2(n) {
  return Number(n).toFixed(2);
}

function fmt3(n) {
  return Number(n).toFixed(3);
}

function eventLabel(type) {
  return EVENT_LABELS[type] || type.replace(/_/g, " ");
}

function formatMeanStd(mean, std, unit = "", decimals = 0) {
  if (mean == null) return "—";
  if (decimals <= 0) {
    const m = Math.round(Number(mean));
    if (std != null && Number(std) > 0) return `${m} ± ${Math.round(Number(std))}${unit}`;
    return `${m}${unit}`;
  }
  const m = Number(mean).toFixed(decimals);
  if (std != null && Number(std) > 0) return `${m} ± ${Number(std).toFixed(decimals)}${unit}`;
  return `${m}${unit}`;
}

function nearestIndex(tArr, tSec) {
  if (!tArr.length) return 0;
  let best = 0;
  let bestDist = Math.abs(tArr[0] - tSec);
  for (let i = 1; i < tArr.length; i += 1) {
    const d = Math.abs(tArr[i] - tSec);
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
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

function saturationLimitShapes(rangeDps, tMin, tMax) {
  if (!rangeDps || !Number.isFinite(rangeDps)) return [];
  const base = {
    type: "line",
    x0: tMin,
    x1: tMax,
    line: { color: "rgba(241, 196, 15, 0.65)", width: 1.2, dash: "dash" },
    layer: "below",
  };
  return [
    { ...base, y0: rangeDps, y1: rangeDps },
    { ...base, y0: -rangeDps, y1: -rangeDps },
  ];
}

function chartShapes(windowSel, recEndS, chartData) {
  const t = chartData.t || [];
  const tMin = t.length ? t[0] : windowSel.startS;
  const tMax = t.length ? t[t.length - 1] : windowSel.endS;
  return [
    ...windowShapes(windowSel.startS, windowSel.endS, recEndS),
    ...saturationLimitShapes(chartData.gyro_range_dps, tMin, tMax),
  ];
}

function eventMarkerTraces(events, chartData) {
  const t = chartData.t;
  const axis = chartData.detection_axis || "gy";
  const ySeries = chartData.gyro[axis];
  const groups = {
    initial_contact: { x: [], y: [], text: [] },
    toe_off: { x: [], y: [], text: [] },
    mid_swing: { x: [], y: [], text: [] },
    manual: { x: [], y: [], text: [] },
  };

  const origin = chartData.t_origin_ms || 0;
  for (const ev of events) {
    const tSec = (ev.t_ms - origin) / 1000;
    const idx = nearestIndex(t, tSec);
    const y = ySeries[idx];
    const bucket = ev.source === "manual" ? "manual" : ev.type;
    const g = groups[bucket] || groups.manual;
    g.x.push(tSec);
    g.y.push(y);
    g.text.push(eventLabel(ev.type));
  }

  const traces = [];
  const specs = [
    ["initial_contact", "triangle-down", 11],
    ["toe_off", "square", 9],
    ["mid_swing", "triangle-up", 11],
    ["manual", "diamond", 10],
  ];
  for (const [key, symbol, size] of specs) {
    const g = groups[key];
    if (!g.x.length) continue;
    traces.push({
      x: g.x,
      y: g.y,
      mode: "markers",
      name: EVENT_LABELS[key],
      marker: {
        color: EVENT_COLORS[key],
        size,
        symbol,
        line: { color: "#121212", width: 1 },
      },
      text: g.text,
      hovertemplate: "%{text}<br>%{x:.3f} s · %{y:.1f} °/s<extra></extra>",
      showlegend: true,
    });
  }
  return traces;
}

function yRangeForSeries(yArr, satRangeDps) {
  if (!yArr.length) return undefined;
  let ymin = Infinity;
  let ymax = -Infinity;
  for (const v of yArr) {
    if (!Number.isFinite(v)) continue;
    ymin = Math.min(ymin, v);
    ymax = Math.max(ymax, v);
  }
  if (!Number.isFinite(ymin)) return undefined;
  if (satRangeDps) {
    ymin = Math.min(ymin, -satRangeDps);
    ymax = Math.max(ymax, satRangeDps);
  }
  const span = ymax - ymin;
  const pad = Math.max(25, span * 0.12 || 25);
  return [ymin - pad, ymax + pad];
}

function updateSatMeter(pct) {
  const fill = document.getElementById("sat-meter-fill");
  const label = document.getElementById("stat-sat");
  const val = pct != null ? Math.max(0, Math.min(100, Number(pct))) : 0;
  if (fill) {
    const width = Math.min(100, val * 20);
    fill.style.width = `${width}%`;
    fill.classList.toggle("sat-meter-warn", val > 2);
  }
  if (label) {
    const rangeEl = document.getElementById("stat-sat-range");
    const rangeText = rangeEl?.textContent?.trim() || "±1000 °/s";
    label.textContent = `${val}% @ ${rangeText}`;
  }
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
  const flt = analysis.flight_time;
  const lit = analysis.literature_validation;

  const set = (id, val) => {
    const el = document.getElementById(id);
    if (el) el.textContent = val ?? "—";
  };

  set("stat-duration", q.duration_s != null ? fmt1(q.duration_s) : "—");
  set("stat-samples", q.sample_count ?? "—");
  const gapsEl = document.getElementById("stat-gaps");
  if (gapsEl) gapsEl.textContent = q.gap_count ?? "0";
  set("stat-cadence", cad ? formatMeanStd(cad.cadence_spm, cad.cadence_std_spm, " spm") : "—");
  set("stat-gct", gct?.mean_ms != null ? formatMeanStd(gct.mean_ms, gct.std_ms, " ms") : "—");
  set("stat-flt", flt?.mean_ms != null ? formatMeanStd(flt.mean_ms, flt.std_ms, " ms") : "—");
  updateSatMeter(q.gyro_saturation_pct);

  const badge = document.getElementById("window-mode-badge");
  if (badge) badge.textContent = win.is_windowed ? "Trecho selecionado" : "Coleta completa";

  set("det-axis", det.axis ?? "—");
  set("det-status", DETECTION_STATUS_LABELS[det.status] || det.status || "—");
  set("det-confidence", det.confidence != null ? `${Math.round(det.confidence * 100)}%` : "—");
  set("det-midswing", det.mid_swing_count ?? "—");
  set("det-midswing-raw", det.mid_swing_count_raw ?? "—");
  set("det-steps", cad?.steps_detected ?? "—");

  const axisLabel = document.getElementById("detection-axis-label");
  if (axisLabel && det.axis) axisLabel.textContent = det.axis;

  const gctWarn = document.getElementById("gct-warn");
  if (gctWarn) gctWarn.hidden = !(gct && gct.status === "low_confidence");

  if (lit && cad) {
    const litCad = document.getElementById("lit-cadence-val");
    if (litCad) litCad.textContent = formatMeanStd(cad.cadence_spm, cad.cadence_std_spm, " spm");
    const litGct = document.getElementById("lit-gct-val");
    if (litGct && gct) litGct.textContent = formatMeanStd(gct.mean_ms, gct.std_ms, " ms");
    const litFlt = document.getElementById("lit-flt-val");
    if (litFlt && flt) litFlt.textContent = formatMeanStd(flt.mean_ms, flt.std_ms, " ms");
  }
}

function renderEventTableBody(events) {
  if (!events.length) {
    return '<p class="empty-state">Nenhum evento nesta categoria.</p>';
  }
  const rows = events
    .map((ev) => {
      const conf = ev.confidence != null ? `${Math.round(ev.confidence * 100)}%` : "—";
      return `<tr>
        <td>${eventLabel(ev.type)}</td>
        <td>${fmt3(ev.t_ms / 1000)}</td>
        <td>${conf}</td>
      </tr>`;
    })
    .join("");
  return `<div class="table-wrap">
    <table class="data-table">
      <thead>
        <tr><th>Tipo</th><th>Tempo (s)</th><th>Conf.</th></tr>
      </thead>
      <tbody>${rows}</tbody>
    </table>
  </div>`;
}

function renderEventsTables(events) {
  const auto = events.filter((e) => e.source === "auto");
  const manual = events.filter((e) => e.source === "manual");
  const autoEl = document.getElementById("events-auto-content");
  const manualEl = document.getElementById("events-manual-content");
  const autoCount = document.getElementById("events-auto-count");
  const manualCount = document.getElementById("events-manual-count");
  if (autoEl) autoEl.innerHTML = renderEventTableBody(auto);
  if (manualEl) manualEl.innerHTML = renderEventTableBody(manual);
  if (autoCount) autoCount.textContent = `(${auto.length})`;
  if (manualCount) manualCount.textContent = `(${manual.length})`;
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
  const axisLabel = axis === "gy" ? "Ωp (gy)" : axis;

  const traces = [
    {
      x: t,
      y: chartData.gyro[axis],
      name: axisLabel,
      line: { color: "#E30613", width: 1.5 },
    },
  ];
  if (axis !== "gx") {
    traces.push({
      x: t,
      y: chartData.gyro.gx,
      name: "gx",
      visible: "legendonly",
      line: { color: "rgba(255,118,118,0.45)", width: 1 },
    });
  }
  if (axis !== "gy") {
    traces.push({
      x: t,
      y: chartData.gyro.gy,
      name: "gy",
      visible: "legendonly",
      line: { color: "rgba(255,67,78,0.45)", width: 1 },
    });
  }
  if (axis !== "gz") {
    traces.push({
      x: t,
      y: chartData.gyro.gz,
      name: "gz",
      visible: "legendonly",
      line: { color: "rgba(155,89,182,0.45)", width: 1 },
    });
  }
  traces.push(...eventMarkerTraces(events, chartData));

  const zoom = preserveZoom ? savedAxisRanges(plotDiv) : { xaxis: {}, yaxis: {} };
  const satRange = chartData.gyro_range_dps || 1000;
  const yAuto = preserveZoom && zoom.yaxis.range
    ? {}
    : { range: yRangeForSeries(chartData.gyro[axis], satRange) };

  const layout = {
    ...KX_CHART_THEME,
    title: { text: "Velocidade angular (°/s)", font: { size: 12, color: "#aaaaaa" } },
    shapes: chartShapes(windowSel, recEndS, chartData),
    hovermode: "x unified",
    dragmode: "zoom",
    yaxis: { ...KX_CHART_THEME.yaxis, title: "°/s", ...yAuto, ...zoom.yaxis },
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
        shapes: chartShapes(this.state.windowSel, this.recEndS(), this.state.chartData),
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
      renderEventsTables(this.state.events);
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

  renderEventsTables(events);
  const qual = parseJson("analysis-quality", {});
  updateSatMeter(qual.gyro_saturation_pct);
  await refreshChart(events, windowSel, chartData);
  chartHandles = new ChartWindowHandles(state);

  if (!isFullWindow(startS, endS, recStartS, recEndS)) {
    setTimeout(() => chartHandles.applyWindow(), 150);
  }
}

document.addEventListener("DOMContentLoaded", renderCharts);
