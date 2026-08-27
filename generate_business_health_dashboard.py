#!/usr/bin/env python3
"""Regenerates business_health_dashboard.html — recreation of the reference iOS
Business Health Dashboard, populated from data/raw_full_metrics.json and
data/raw_troas_croas.json (both from Databricks).

The Economy Optimization Progress section is intentionally omitted: it's
unrelated manually-tracked data not sourced from Databricks.

Usage: python3 generate_business_health_dashboard.py
"""
import json
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_PATH = os.path.join(BASE_DIR, "data", "raw_full_metrics.json")
TROAS_PATH = os.path.join(BASE_DIR, "data", "raw_troas_croas.json")
OUT_PATH = os.path.join(BASE_DIR, "business_health_dashboard.html")
LIB_DIR = os.path.join(BASE_DIR, "lib")

POINTS_PER_DOLLAR = 750  # ⚠️ working assumption pending team confirmation


def read_lib(name):
    with open(os.path.join(LIB_DIR, name)) as f:
        return f.read()


def to_num(v):
    return float(v) if v is not None else 0.0


def short_date(iso):
    y, m, d = iso.split("-")
    return f"{int(m)}/{int(d)}"


def main():
    with open(DATA_PATH) as f:
        raw = json.load(f)
    with open(TROAS_PATH) as f:
        troas_by_date = json.load(f)

    records = []
    for r in raw:
        troas_src = troas_by_date.get(r["dates"], {})
        g7_troas = float(troas_src["g7_troas"]) if troas_src.get("g7_troas") is not None else None
        g7_croas = float(troas_src["g7_croas"]) if troas_src.get("g7_croas") is not None else None
        g7_delivery_rate = (g7_croas / g7_troas) if (g7_croas is not None and g7_troas) else None
        install_revenue = to_num(r["install_revenue"])
        game_pass_revenue = to_num(r["game_pass_revenue"])
        survey_revenue = to_num(r["survey_revenue"])
        gc_cost = to_num(r["gc_cost"])
        ua_cost = to_num(r["ua_cost"])
        iap_spend = to_num(r["lp_iap_spend_usd"])
        client_ad_rev = to_num(r["client_ad_revenue"])
        game_installs = to_num(r["game_installs"])
        total_points_rewarded = to_num(r["total_points_rewarded"])
        pts_redeemed_gc = to_num(r["pts_redeemed_gc"])
        pts_redeemed_sweeps = to_num(r["pts_redeemed_sweeps"])
        pts_redeemed_th = abs(to_num(r["pts_redeemed_th"]))  # stored as a point debit
        pts_redeemed_total = pts_redeemed_gc + pts_redeemed_sweeps + pts_redeemed_th
        pts_unredeemed_gap = total_points_rewarded - pts_redeemed_total

        total_rev = install_revenue + game_pass_revenue + survey_revenue

        gc_pct_of_revenue = (gc_cost / total_rev * 100) if total_rev else None
        margin_pct_gc_basis = (100 - (gc_cost + game_pass_revenue) / total_rev * 100) if total_rev else None
        gc_per_iap_dollar = (gc_cost / iap_spend) if iap_spend else None
        points_cost_dollars = total_points_rewarded / POINTS_PER_DOLLAR
        reward_cost_pct_points_basis = (points_cost_dollars / total_rev * 100) if total_rev else None
        margin_pct_points_basis = (100 - reward_cost_pct_points_basis) if reward_cost_pct_points_basis is not None else None
        arpg = (total_rev / game_installs) if game_installs else None

        records.append({
            "date": short_date(r["dates"]),
            "total_rev": total_rev,
            "gc_cost": gc_cost,
            "game_pass_rev": game_pass_revenue,
            "points_balance": to_num(r["liabilities_points"]),
            "total_points_rewarded": total_points_rewarded,
            "pts_redeemed_gc": pts_redeemed_gc,
            "pts_redeemed_sweeps": pts_redeemed_sweeps,
            "pts_redeemed_th": pts_redeemed_th,
            "pts_redeemed_total": pts_redeemed_total,
            "pts_unredeemed_gap": pts_unredeemed_gap,
            "iap_spend": iap_spend,
            "client_ad_rev": client_ad_rev,
            "ua_cost": ua_cost,
            "new_users": to_num(r["new_users"]),
            "dau": to_num(r["dau"]),
            "game_installs": game_installs,
            "arpg": arpg,
            "gc_per_iap_dollar": gc_per_iap_dollar,
            "gc_pct_of_revenue": gc_pct_of_revenue,
            "margin_pct_gc_basis": margin_pct_gc_basis,
            "points_cost_dollars": points_cost_dollars,
            "reward_cost_pct_points_basis": reward_cost_pct_points_basis,
            "margin_pct_points_basis": margin_pct_points_basis,
            "g7_troas": g7_troas,
            "g7_croas": g7_croas,
            "delivery_rate": g7_delivery_rate,
        })

    n = len(records)
    date_range_label = f"{raw[0]['dates']} – {raw[-1]['dates']}"

    chartjs = read_lib("chartjs_inline.txt")
    css = read_lib("dashboard_base.css.txt")
    header_shell = read_lib("header_shell.html.txt")
    helpers = read_lib("chart_helpers.js.txt")
    tooltip_engine = read_lib("tooltip_engine.txt")

    header_shell = header_shell.replace(
        "iOS Business Health Dashboard",
        "iOS Business Health Dashboard",
    ).replace(
        "Jan 1 – Aug 19, 2026 · Last 3 days masked where GC cost lags · Margin basis: pending group alignment",
        f"{date_range_label} · Last 3 days masked where GC cost lags · Databricks (2026 YTD) · Margin (points basis) pending 750pts=$1 confirmation",
    ).replace(
        '<option value="231" selected>YTD</option>',
        f'<option value="{n}" selected>YTD</option>',
    )

    build_js = BUILD_JS_TEMPLATE

    html = (
        chartjs + "\n" +
        css + "\n" +
        header_shell + "\n" +
        "<script>\n" +
        "// ── RAW DATA ──\n" +
        "const RAW = " + json.dumps(records) + ";\n" +
        helpers + "\n" +
        build_js + "\n" +
        "</script>\n" +
        tooltip_engine
    )

    with open(OUT_PATH, "w") as f:
        f.write(html)
    print(f"Wrote {OUT_PATH} ({n} days, {raw[0]['dates']}..{raw[-1]['dates']})")


BUILD_JS_TEMPLATE = r"""
// ── MAIN BUILD ──────────────────────────────────────────────────────────────
function build() {
  destroyAll();
  const n = parseInt(document.getElementById('rangeSelect').value);
  const sm = parseInt(document.getElementById('smoothSelect').value);

  const data = RAW.slice(-n);

  const MASK = 3;
  const masked = (arr) => arr.map((v, i) => (i >= arr.length - MASK ? null : v));

  const labels = data.map(r => r.date);
  const smooth = (arr) => movingAvg(arr, sm);

  const revSeries      = data.map(r => r.total_rev);
  const gcSeries        = data.map(r => r.gc_cost);
  const iapSeries       = data.map(r => r.iap_spend);
  const adRevSeries     = data.map(r => r.client_ad_rev);
  const gcPerIapSeries  = masked(data.map(r => r.gc_per_iap_dollar));
  const drSeries        = data.map(r => r.delivery_rate);

  const marginPctGCSeries  = masked(data.map(r => r.margin_pct_gc_basis));
  const marginPctPtsSeries = masked(data.map(r => r.margin_pct_points_basis));
  const g7TROASSeries       = data.map(r => r.g7_troas != null ? r.g7_troas * 100 : null);
  const g7CROASSeries       = data.map(r => r.g7_croas != null ? r.g7_croas * 100 : null);

  const ptsRewardedSeries = data.map(r => r.total_points_rewarded);
  const ptsGCSeries       = data.map(r => r.pts_redeemed_gc);
  const ptsSweepSeries    = data.map(r => r.pts_redeemed_sweeps);
  const ptsTHSeries       = data.map(r => r.pts_redeemed_th);
  const ptsGapSeries      = data.map(r => r.pts_unredeemed_gap);

  const uaCostSeries     = data.map(r => r.ua_cost);
  const dauSeries        = data.map(r => r.dau);
  const dnuSeries        = data.map(r => r.new_users);
  const installsSeries   = data.map(r => r.game_installs);
  const arpgSeries       = data.map(r => r.arpg);

  const ytdRev      = ytdSum(data, 'total_rev');
  const ytdGC       = ytdSum(data, 'gc_cost');
  const ytdIAP      = ytdSum(data, 'iap_spend');
  const ytdAdRev    = ytdSum(data, 'client_ad_rev');
  const ytdUA       = ytdSum(data, 'ua_cost');
  const ytdInstalls = ytdSum(data, 'game_installs');
  const ytdPtsRew   = ytdSum(data, 'total_points_rewarded');
  const ytdPtsGC    = ytdSum(data, 'pts_redeemed_gc');
  const ytdPtsSw    = ytdSum(data, 'pts_redeemed_sweeps');
  const ytdPtsTH    = ytdSum(data, 'pts_redeemed_th');
  const ytdPtsGap   = ytdPtsRew - ytdPtsGC - ytdPtsSw - ytdPtsTH;
  const ytdGcPerIAP = ytdGC / ytdIAP;

  const latMarPctGC  = lastVal(data.filter((_,i)=>i<data.length-MASK), 'margin_pct_gc_basis');
  const latMarPctPts = lastVal(data.filter((_,i)=>i<data.length-MASK), 'margin_pct_points_basis');
  const latDR     = lastVal(data, 'delivery_rate');
  const latDRDate = lastValDate(data, 'delivery_rate');
  const latG7TROAS = lastVal(data, 'g7_troas') != null ? lastVal(data, 'g7_troas') * 100 : null;
  const latG7CROAS = lastVal(data, 'g7_croas') != null ? lastVal(data, 'g7_croas') * 100 : null;
  const latDAU  = lastVal(data, 'dau');
  const latDNU  = lastVal(data, 'new_users');
  const latARPG = lastVal(data, 'arpg');

  function delta(series, higherGood=true) {
    const nonNull = series.filter(x => x!=null);
    const w = Math.min(7, Math.floor(nonNull.length/2));
    if (!w) return null;
    const rec = nonNull.slice(-w), prev = nonNull.slice(-w*2,-w);
    if (!prev.length) return null;
    const rA = rec.reduce((a,b)=>a+b,0)/rec.length;
    const pA = prev.reduce((a,b)=>a+b,0)/prev.length;
    return { pct: ((rA-pA)/Math.abs(pA))*100, higherGood };
  }
  function deltaHTML(d) {
    if (!d) return '';
    const sign = d.pct > 0 ? '+' : '';
    const good = (d.higherGood && d.pct > 0) || (!d.higherGood && d.pct < 0);
    const cls = good ? 'up' : 'down';
    const arr = d.pct > 0 ? '▲' : '▼';
    return `<span class="${cls}">${arr} ${sign}${d.pct.toFixed(1)}%</span> vs prior period`;
  }

  const root = document.getElementById('root');
  root.innerHTML = '';

  function section(label, html) {
    const s = document.createElement('div');
    s.className = 'section';
    const key = 'sec_collapsed_' + label.replace(/[^a-z0-9]/gi, '_');
    let collapsed = false;
    try { collapsed = localStorage.getItem(key) === '1'; } catch(e) {}
    const toggle = document.createElement('div');
    toggle.className = 'section-label section-toggle';
    toggle.innerHTML = '<span class="section-chevron">' + (collapsed ? '▶' : '▼') + '</span> ' + label;
    const body = document.createElement('div');
    body.className = 'section-body';
    body.style.display = collapsed ? 'none' : 'block';
    body.innerHTML = html;
    toggle.addEventListener('click', function() {
      const isCollapsed = body.style.display === 'none';
      body.style.display = isCollapsed ? 'block' : 'none';
      toggle.querySelector('.section-chevron').textContent = isCollapsed ? '▼' : '▶';
      try { localStorage.setItem(key, isCollapsed ? '0' : '1'); } catch(e) {}
    });
    s.appendChild(toggle);
    s.appendChild(body);
    root.appendChild(s);
  }

  function card(id, label, val, deltaD, color, badge='', badgeColor='', desc='') {
    const badgeHTML = badge ? `<span class="card-badge" style="background:${badgeColor}22;color:${badgeColor};">${badge}</span>` : '';
    const descHTML = desc ? `<span class="metric-tooltip">${desc}</span>` : '';
    return `<div class="card">
      <div class="card-top">
        <div class="card-label-wrap">
          <span class="card-label">${label}</span>
          ${desc ? '<span class="info-icon">?</span>' : ''}
          ${descHTML}
        </div>${badgeHTML}
      </div>
      <div class="card-val" style="color:${color}">${val}</div>
      <div class="card-delta">${deltaHTML(deltaD)}</div>
      <div class="card-chart-wrap"><canvas id="${id}"></canvas></div>
    </div>`;
  }

  const DESCS = {
    'c-rev':    'Total dollars earned by Mistplay from all iOS sources: install revenue (IAP+IAA share), Game Pass, and surveys. YTD cumulative.',
    'c-iap':    'In-App Purchase spend by users inside partner games (client $, not Mistplay revenue). Tracked as a signal of user quality. YTD cumulative.',
    'c-adrev':  'Ad revenue earned inside partner games by the publisher (client $, not Mistplay revenue). YTD cumulative.',
    'c-gc':     'Dollar cost of gift cards redeemed by users. Last 3 days masked — GC reporting lags by design. YTD cumulative.',
    'c-margin-gc':     '(GC Cost + Game Pass Revenue) ÷ Total Revenue × 100, subtracted from 100. Understates true reward cost since it excludes non-GC point rewards. Last 3 days masked.',
    'c-margin-points': '(Total Points Rewarded ÷ 750) ÷ Total Revenue × 100, subtracted from 100. ⚠️ 750 pts = $1 is a working assumption pending team confirmation. Last 3 days masked.',
    'c-gciap':  'GC Cost ÷ IAP Spend. Cents of gift-card cost incurred per $1 of in-app purchase a user makes inside a partner game. Lower is better. Last 3 days masked.',
    'c-dr':     'G7 cROAS ÷ tROAS (both from playground.lp_client_performance_peter_3, Product = MP iOS). 100% = on target; above = over-delivering; below = under-delivering. Needs 7 full days to mature, so the shown value lags today by up to ~7 days.',
    'c-g7troas': 'G7 tROAS = revenue-weighted target ROAS the offer is bidding toward. G7 cROAS = actual realized ROAS (client IAP spend or ad revenue, per offer goal type, ÷ our revenue). When tROAS > cROAS, spend is efficient but pricing/delivery has not caught up yet.',
    'c-ua':     'Total user acquisition spend — paid media costs to bring new users onto the Mistplay platform. YTD cumulative.',
    'c-inst':   'Number of partner game installs driven by Mistplay users. YTD cumulative.',
    'c-arpg':   'Total Revenue ÷ Game Installs for the latest day. Higher is better.',
    'c-dau':    'Unique users active on the Mistplay platform on the latest day.',
    'c-dnu':    'First-time users registering on Mistplay on the latest day.',
  };

  const sec1 = `<div class="cards-grid cols-3">
    ${card('c-rev', 'Total Revenue', fmtUSD(ytdRev), delta(revSeries,true), 'var(--blue)', 'YTD', '', DESCS['c-rev'])}
    ${card('c-gc', 'GC Cost', fmtUSD(ytdGC), delta(masked(gcSeries),false), 'var(--red)', 'YTD', '', DESCS['c-gc'])}
    ${card('c-dr','G7 Delivery Rate', latDR != null ? fmtPct(latDR * 100) : '—', delta(drSeries.map(v => v == null ? null : v * 100), true), (latDR||0) >= 1 ? 'var(--green)' : 'var(--red)', latDRDate ? 'as of ' + latDRDate : '', '', DESCS['c-dr'])}
  </div>`;
  section('📈 Revenue & Client Spend', sec1);

  const sec2 = `<div class="cards-grid cols-3">
    ${card('c-margin-gc', 'Margin % (GC basis)', fmtPct(latMarPctGC||0), delta(marginPctGCSeries,true), 'var(--green)', '35% cap', '', DESCS['c-margin-gc'])}
    ${card('c-margin-pts', 'Margin % (Points ⚠️)', fmtPct(latMarPctPts||0), delta(marginPctPtsSeries,true), 'var(--teal)', '35% cap', '', DESCS['c-margin-points'])}
    ${card('c-g7troas', 'G7 tROAS vs cROAS', (latG7TROAS != null ? latG7TROAS.toFixed(1) + '% tROAS' : '—'), delta(g7TROASSeries, true), latG7TROAS != null && latG7TROAS >= latG7CROAS ? 'var(--green)' : 'var(--yellow)', latG7CROAS != null ? 'cROAS ' + latG7CROAS.toFixed(1) + '%' : '', '', DESCS['c-g7troas'])}
  </div>`;
  section('📊 Margin', sec2);

  const sec3 = `<div class="cards-grid cols-3">
    ${card('c-gciap', 'GC Cost per $1 IAP', fmtRatio(ytdGcPerIAP), delta(gcPerIapSeries,false), 'var(--yellow)', '↓ better', '', DESCS['c-gciap'])}
    ${card('c-iap', 'IAP Spend (Client)', fmtUSD(ytdIAP), delta(iapSeries,true), 'var(--teal)', 'Client $', '', DESCS['c-iap'])}
    ${card('c-adrev', 'Client Ad Revenue', fmtUSD(ytdAdRev), delta(adRevSeries,true), 'var(--purple)', 'Client $', '', DESCS['c-adrev'])}
  </div>`;
  section('⚙️ Efficiency Ratios', sec3);

  const ytdPtsRedeemed = ytdPtsGC + ytdPtsSw + ytdPtsTH;
  const ptsGapPct = ytdPtsRew ? (ytdPtsGap / ytdPtsRew * 100).toFixed(1) : '0.0';
  const ptsRedeemedPct = ytdPtsRew ? (ytdPtsRedeemed / ytdPtsRew * 100).toFixed(1) : '0.0';
  const ptsRedeemedTotalSeries = data.map(r => (r.pts_redeemed_gc||0) + (r.pts_redeemed_sweeps||0) + (r.pts_redeemed_th||0));

  const sec4 = `<div class="big-card">
    <div class="big-card-top">
      <div class="big-card-label-wrap">
        <span class="big-card-label">Points Rewarded vs. Redeemed</span>
        <span class="info-icon">?</span>
        <span class="metric-tooltip">Total Points Rewarded = all points issued across reward types (quick games, trivia, surveys, loyalty play, daily streak, promo codes, tournaments, treasure hunt, IAP offers, referrals, welcome bonus, failed-install comp, CS comp).<br><br>Total Redeemed = gift cards + sweepstakes + treasure hunt keys.<br><br>Unredeemed Gap = issued but not yet cashed out.</span>
      </div>
      <div class="big-card-kpis">
        <div class="big-kpi"><div class="big-kpi-label">Total Rewarded</div><div class="big-kpi-val" style="color:var(--blue)">${fmtPts(ytdPtsRew)}</div></div>
        <div class="big-kpi"><div class="big-kpi-label">Total Redeemed</div><div class="big-kpi-val" style="color:var(--green)">${fmtPts(ytdPtsRedeemed)}</div><div class="big-kpi-sub">${ptsRedeemedPct}% of rewarded</div></div>
        <div class="big-kpi"><div class="big-kpi-label">🔓 Unredeemed Gap</div><div class="big-kpi-val" style="color:var(--yellow)">${fmtPts(ytdPtsGap)}</div><div class="big-kpi-sub">${ptsGapPct}% outstanding</div></div>
      </div>
    </div>
    <div style="padding:0 8px 8px;height:180px;">
      <canvas id="c-pts"></canvas>
    </div>
  </div>`;
  section('🪙 Points Rewarded & Redeemed', sec4);

  const sec5 = `<div class="cards-grid cols-3">
    ${card('c-ua', 'UA Cost', fmtUSD(ytdUA), delta(uaCostSeries,false), 'var(--orange)', 'YTD', '', DESCS['c-ua'])}
    ${card('c-inst', 'Game Installs', fmtNum(ytdInstalls), delta(installsSeries,true), 'var(--blue)', 'YTD', '', DESCS['c-inst'])}
    ${card('c-arpg', 'ARPG', '$' + (latARPG||0).toFixed(2), delta(arpgSeries,true), 'var(--green)', 'Latest', '', DESCS['c-arpg'])}
  </div>`;
  section('🎯 UA & Acquisition', sec5);

  const sec6 = `<div class="cards-grid cols-2">
    ${card('c-dau', 'Daily Active Users', fmtNum(latDAU), delta(dauSeries,true), 'var(--blue)', 'Latest', '', DESCS['c-dau'])}
    ${card('c-dnu', 'New Users (DNU)', fmtNum(latDNU), delta(dnuSeries,true), 'var(--teal)', 'Latest', '', DESCS['c-dnu'])}
  </div>`;
  section('👥 Engagement', sec6);

  root.insertAdjacentHTML('beforeend', '<div style="height:32px;"></div>');

  const toMini = (id, series, color, fmt, spanGaps=true) => {
    makeMiniChart(id, labels, smooth(series), color, color + '22', fmt, spanGaps);
  };

  toMini('c-rev',   revSeries,   '#4f8ef7', fmtUSD);
  toMini('c-iap',   iapSeries,   '#2dd4bf', fmtUSD);
  toMini('c-adrev', adRevSeries, '#a78bfa', fmtUSD);
  toMini('c-gc',    masked(gcSeries), '#f87171', fmtUSD);
  toMini('c-margin-gc',  marginPctGCSeries,  '#059669', v => fmtPct(v));
  toMini('c-margin-pts', marginPctPtsSeries, '#0d9488', v => fmtPct(v));
  toMini('c-g7troas',   g7TROASSeries,  '#fbbf24', v => fmtPct(v));
  toMini('c-dr',    drSeries.map(v => v == null ? null : v * 100), (latDR||0) >= 1 ? '#34d399' : '#f87171', v => fmtPct(v), false);
  toMini('c-gciap', gcPerIapSeries, '#fbbf24', v => '$' + (v||0).toFixed(3));
  toMini('c-ua',    uaCostSeries,   '#fb923c', fmtUSD);
  toMini('c-inst',  installsSeries, '#4f8ef7', v => fmtNum(v));
  toMini('c-arpg',  arpgSeries,     '#34d399', v => '$' + (v||0).toFixed(2));
  toMini('c-dau',   dauSeries,      '#4f8ef7', v => fmtNum(v));
  toMini('c-dnu',   dnuSeries,      '#2dd4bf', v => fmtNum(v));

  const ptsFmt = v => fmtPts(v);
  makeBigChart('c-pts', labels, [
    { label: 'Total Rewarded', data: smooth(ptsRewardedSeries),      color: '#4f8ef7', width: 2,   fmt: ptsFmt },
    { label: 'Total Redeemed', data: smooth(ptsRedeemedTotalSeries), color: '#34d399', width: 1.5, fmt: ptsFmt },
    { label: 'Unredeemed Gap', data: smooth(ptsGapSeries),           color: '#fbbf24', width: 1.5, fmt: ptsFmt, dash: [4,2] },
  ]);
}

document.getElementById('rangeSelect').addEventListener('change', build);
document.getElementById('smoothSelect').addEventListener('change', build);

build();
"""

if __name__ == "__main__":
    main()
