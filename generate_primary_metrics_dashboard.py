#!/usr/bin/env python3
"""Regenerates primary_metrics_dashboard.html from data/raw_grand_total.json.

Usage: python3 generate_primary_metrics_dashboard.py
"""
import json
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_PATH = os.path.join(BASE_DIR, "data", "raw_grand_total.json")
OUT_PATH = os.path.join(BASE_DIR, "primary_metrics_dashboard.html")

METRICS = [
    ("ua_cost", "UA Cost", "usd"),
    ("new_users", "New Users", "num"),
    ("dau", "DAU", "num"),
    ("install_revenue", "Install Revenue", "usd"),
    ("iap_install_revenue", "IAP Install Revenue", "usd"),
    ("client_ad_revenue", "Client Ad Revenue", "usd"),
    ("game_pass_revenue", "Game Pass Revenue", "usd"),
    ("survey_revenue", "Survey Revenue", "usd"),
    ("gc_cost", "GC Cost", "usd"),
    ("pending_gc_cost", "Pending GC Cost", "usd"),
    ("game_installs", "Game Installs", "num"),
]

ROAS_WINDOWS = ["g1", "g3", "g7", "g14", "g30"]
ROAS_METRICS = []
for w in ROAS_WINDOWS:
    label = w.upper().replace("G", "G")
    ROAS_METRICS.append((f"{w}_troas", f"{label} tROAS", "roas_pct"))
    ROAS_METRICS.append((f"{w}_croas", f"{label} cROAS", "roas_pct"))
    ROAS_METRICS.append((f"{w}_delivery_rate", f"{label} Delivery Rate", "ratio_x"))

ALL_METRICS = METRICS + ROAS_METRICS


def to_num(v):
    if v is None:
        return None
    return float(v)


def main():
    with open(DATA_PATH) as f:
        raw = json.load(f)

    for r in raw:
        for k in list(r.keys()):
            if k == "dates":
                continue
            if k in {key for key, _, _ in METRICS}:
                r[k] = to_num(r[k]) or 0.0
            else:
                r[k] = to_num(r[k])

    dates = [r["dates"] for r in raw]

    grand_totals = {key: sum(r[key] for r in raw) for key, _, _ in METRICS}
    for key, _, _ in ROAS_METRICS:
        vals = [r[key] for r in raw if r.get(key) is not None]
        grand_totals[key] = (sum(vals) / len(vals)) if vals else None

    html = HTML_TEMPLATE.replace("__RAW_JSON__", json.dumps(raw))
    html = html.replace("__METRICS_JSON__", json.dumps(ALL_METRICS))
    html = html.replace("__PRIMARY_KEYS_JSON__", json.dumps([key for key, _, _ in METRICS]))
    html = html.replace("__GRAND_TOTALS_JSON__", json.dumps(grand_totals))
    html = html.replace("__LAST_REFRESH__", raw[-1]["dates"] if raw else "")
    html = html.replace("__DATE_RANGE__", f"{dates[0]} to {dates[-1]}" if dates else "")

    with open(OUT_PATH, "w") as f:
        f.write(html)
    print(f"Wrote {OUT_PATH} ({len(raw)} days, {dates[0]}..{dates[-1]})")


HTML_TEMPLATE = """<title>iOS Primary Metrics</title>
<style>
  :root {
    --purple: #6b5bd6;
    --bg: #f7f7fb;
    --card-bg: #ffffff;
    --border: #e6e6ee;
    --text: #1f1f2e;
    --muted: #7a7a90;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    background: var(--bg);
    color: var(--text);
  }
  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 20px 32px;
    border-bottom: 1px solid var(--border);
    background: var(--card-bg);
  }
  header .brand { font-weight: 700; color: var(--purple); font-size: 15px; }
  header h1 { font-size: 24px; margin: 0; text-align: center; flex: 1; }
  header .meta { text-align: right; font-size: 12px; color: var(--muted); }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: 16px;
    padding: 24px 32px;
  }
  .card {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 16px 18px;
  }
  .card .label { font-size: 12px; color: var(--muted); text-transform: uppercase; letter-spacing: .04em; }
  .card .value { font-size: 22px; font-weight: 700; margin: 4px 0 10px; }
  .card svg { display: block; width: 100%; height: 48px; }
  .card .axis { display: flex; justify-content: space-between; font-size: 9px; color: var(--muted); margin-top: 2px; }
  .section-title {
    padding: 24px 32px 0;
    font-size: 13px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: .05em;
    color: var(--muted);
  }
  .footer-note {
    padding: 8px 32px 32px;
    font-size: 12px;
    color: var(--muted);
  }
</style>
<header>
  <div class="brand">MISTPLAY</div>
  <h1>iOS Primary Metrics</h1>
  <div class="meta">Data through __LAST_REFRESH__<br>Range: __DATE_RANGE__</div>
</header>
<div class="section-title">Business Health</div>
<div class="grid" id="cards-primary"></div>
<div class="section-title">tROAS / cROAS / Delivery Rate</div>
<div class="grid" id="cards-roas"></div>
<div class="footer-note">
  Grand totals and daily trend, __DATE_RANGE__. Country / Acquisition Source / Media Source filters not yet wired up (dimensional query is being phased in). ROAS/delivery-rate cROAS lags ~7-10 days behind tROAS by design (cumulative revenue attribution catches up over time). Data refreshed from Databricks.
</div>
<script>
const RAW = __RAW_JSON__;
const METRICS = __METRICS_JSON__;
const GRAND_TOTALS = __GRAND_TOTALS_JSON__;
const PRIMARY_KEYS = new Set(__PRIMARY_KEYS_JSON__);

function fmt(v, kind) {
  if (v === null || v === undefined || Number.isNaN(v)) return "—";
  if (kind === "usd") return "$" + Math.round(v).toLocaleString();
  if (kind === "roas_pct") return (v * 100).toFixed(1) + "%";
  if (kind === "ratio_x") return (v * 100).toFixed(1) + "%";
  return Math.round(v).toLocaleString();
}

const W = 280, H = 48, PAD = 2;

function sparklineGeometry(rawValues) {
  const pts = rawValues
    .map((v, i) => [i, v])
    .filter(([, v]) => v !== null && v !== undefined && !Number.isNaN(v));
  if (pts.length < 2) return null;
  const vals = pts.map(p => p[1]);
  const min = Math.min(0, ...vals), max = Math.max(...vals);
  const range = (max - min) || 1;
  const n = rawValues.length - 1 || 1;
  const toXY = (i, v) => [
    PAD + (i / n) * (W - PAD * 2),
    H - PAD - ((v - min) / range) * (H - PAD * 2),
  ];
  return { pts, min, max, range, n, toXY };
}

function sparklineSVG(rawValues) {
  const geo = sparklineGeometry(rawValues);
  if (!geo) return `<svg viewBox="0 0 ${W} ${H}"></svg>`;
  const coords = geo.pts.map(([i, v]) => geo.toXY(i, v).map(n => n.toFixed(1)).join(","));
  const linePath = "M" + coords.join(" L");
  const areaPath = linePath + ` L${coords[coords.length - 1].split(",")[0]},${H - PAD} L${coords[0].split(",")[0]},${H - PAD} Z`;
  return `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">
    <path d="${areaPath}" fill="rgba(107,91,214,0.10)" stroke="none"></path>
    <path d="${linePath}" fill="none" stroke="#6b5bd6" stroke-width="1.5" vector-effect="non-scaling-stroke"></path>
    <line class="hover-line" x1="0" y1="0" x2="0" y2="${H}" stroke="#6b5bd6" stroke-width="1" stroke-dasharray="2,2" opacity="0" vector-effect="non-scaling-stroke"></line>
    <circle class="hover-dot" r="3" fill="#6b5bd6" stroke="#fff" stroke-width="1" opacity="0"></circle>
  </svg>`;
}

function axisLabelsHTML(dateArr) {
  if (dateArr.length < 2) return "";
  const first = dateArr[0];
  const mid = dateArr[Math.floor((dateArr.length - 1) / 2)];
  const last = dateArr[dateArr.length - 1];
  return `<div class="axis"><span>${first}</span><span>${mid}</span><span>${last}</span></div>`;
}

const containerPrimary = document.getElementById("cards-primary");
const containerRoas = document.getElementById("cards-roas");

const tooltip = document.createElement("div");
tooltip.style.cssText = "position:fixed;pointer-events:none;background:#1f1f2e;color:#fff;padding:6px 10px;border-radius:6px;font-size:12px;line-height:1.5;display:none;z-index:1000;box-shadow:0 4px 12px rgba(0,0,0,0.18);white-space:nowrap;";
document.body.appendChild(tooltip);

const dates = RAW.map(r => r.dates);

METRICS.forEach(([key, label, kind]) => {
  const card = document.createElement("div");
  card.className = "card";
  const total = GRAND_TOTALS[key];
  const values = RAW.map(r => r[key]);
  card.innerHTML = `
    <div class="label">${label}</div>
    <div class="value">${fmt(total, kind)}</div>
    ${sparklineSVG(values)}
    ${axisLabelsHTML(dates)}
  `;
  (PRIMARY_KEYS.has(key) ? containerPrimary : containerRoas).appendChild(card);

  const geo = sparklineGeometry(values);
  const svgEl = card.querySelector("svg");
  if (!geo || !svgEl) return;
  const hoverLine = svgEl.querySelector(".hover-line");
  const hoverDot = svgEl.querySelector(".hover-dot");
  svgEl.style.cursor = "crosshair";

  function showAt(clientX, clientY) {
    const rect = svgEl.getBoundingClientRect();
    const relX = Math.min(Math.max((clientX - rect.left) / rect.width, 0), 1);
    const hoverIdx = relX * geo.n;
    let best = geo.pts[0], bestDist = Infinity;
    for (const p of geo.pts) {
      const d = Math.abs(p[0] - hoverIdx);
      if (d < bestDist) { bestDist = d; best = p; }
    }
    const [idx, v] = best;
    const [x, y] = geo.toXY(idx, v);
    hoverLine.setAttribute("x1", x); hoverLine.setAttribute("x2", x); hoverLine.setAttribute("opacity", "0.5");
    hoverDot.setAttribute("cx", x); hoverDot.setAttribute("cy", y); hoverDot.setAttribute("opacity", "1");
    const scaleX = rect.width / W, scaleY = rect.height / H;
    tooltip.style.display = "block";
    tooltip.style.left = (rect.left + x * scaleX + 12) + "px";
    tooltip.style.top = (rect.top + y * scaleY - 30) + "px";
    tooltip.innerHTML = `<strong>${dates[idx]}</strong><br>${label}: ${fmt(v, kind)}`;
  }

  svgEl.addEventListener("mousemove", (e) => showAt(e.clientX, e.clientY));
  svgEl.addEventListener("mouseleave", () => {
    hoverLine.setAttribute("opacity", "0");
    hoverDot.setAttribute("opacity", "0");
    tooltip.style.display = "none";
  });
});
</script>
"""

if __name__ == "__main__":
    main()
