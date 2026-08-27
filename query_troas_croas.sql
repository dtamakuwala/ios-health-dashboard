-- tROAS / cROAS by day, G1/G3/G7/G14/G30 windows, Product = MP iOS.
-- Formulas confirmed exact against Tableau (LPClientPerformance/ROAS) on 2026-01-01:
--   tROAS_G1  = 0.4 * (SUM(g1_revenue  * G7_tROAS)  / SUM(g1_revenue))
--   tROAS_G3  = 0.7 * (SUM(g3_revenue  * G7_tROAS)  / SUM(g3_revenue))
--   tROAS_G7  =        SUM(g7_revenue  * G7_tROAS)  / SUM(g7_revenue)
--   tROAS_G14 =        SUM(g14_revenue * G7_tROAS)  / SUM(g14_revenue)
--   tROAS_G30 =        SUM(g30_revenue * G30_tROAS) / SUM(g30_revenue)
--   cROAS_Gn  = SUM(CASE goal_type
--                 WHEN 'tROAS IAP'    THEN gN_spend
--                 WHEN 'tROAS IAA'    THEN gN_adrev
--                 WHEN 'tROAS Hybrid' THEN gN_spend + gN_adrev
--                 ELSE gN_spend END) / SUM(gN_revenue)

SELECT
  date,

  0.4 * (SUM(g1_revenue * G7_tROAS) / NULLIF(SUM(g1_revenue), 0)) AS g1_troas,
  0.7 * (SUM(g3_revenue * G7_tROAS) / NULLIF(SUM(g3_revenue), 0)) AS g3_troas,
  SUM(g7_revenue * G7_tROAS) / NULLIF(SUM(g7_revenue), 0) AS g7_troas,
  SUM(g14_revenue * G7_tROAS) / NULLIF(SUM(g14_revenue), 0) AS g14_troas,
  SUM(g30_revenue * G30_tROAS) / NULLIF(SUM(g30_revenue), 0) AS g30_troas,

  SUM(CASE
    WHEN goal_type = 'tROAS IAP' THEN COALESCE(g1_spend, 0)
    WHEN goal_type = 'tROAS IAA' THEN COALESCE(g1_adrev, 0)
    WHEN goal_type = 'tROAS Hybrid' THEN COALESCE(g1_spend, 0) + COALESCE(g1_adrev, 0)
    ELSE COALESCE(g1_spend, 0)
  END) / NULLIF(SUM(g1_revenue), 0) AS g1_croas,

  SUM(CASE
    WHEN goal_type = 'tROAS IAP' THEN COALESCE(g3_spend, 0)
    WHEN goal_type = 'tROAS IAA' THEN COALESCE(g3_adrev, 0)
    WHEN goal_type = 'tROAS Hybrid' THEN COALESCE(g3_spend, 0) + COALESCE(g3_adrev, 0)
    ELSE COALESCE(g3_spend, 0)
  END) / NULLIF(SUM(g3_revenue), 0) AS g3_croas,

  SUM(CASE
    WHEN goal_type = 'tROAS IAP' THEN COALESCE(g7_spend, 0)
    WHEN goal_type = 'tROAS IAA' THEN COALESCE(g7_adrev, 0)
    WHEN goal_type = 'tROAS Hybrid' THEN COALESCE(g7_spend, 0) + COALESCE(g7_adrev, 0)
    ELSE COALESCE(g7_spend, 0)
  END) / NULLIF(SUM(g7_revenue), 0) AS g7_croas,

  SUM(CASE
    WHEN goal_type = 'tROAS IAP' THEN COALESCE(g14_spend, 0)
    WHEN goal_type = 'tROAS IAA' THEN COALESCE(g14_adrev, 0)
    WHEN goal_type = 'tROAS Hybrid' THEN COALESCE(g14_spend, 0) + COALESCE(g14_adrev, 0)
    ELSE COALESCE(g14_spend, 0)
  END) / NULLIF(SUM(g14_revenue), 0) AS g14_croas,

  SUM(CASE
    WHEN goal_type = 'tROAS IAP' THEN COALESCE(g30_spend, 0)
    WHEN goal_type = 'tROAS IAA' THEN COALESCE(g30_adrev, 0)
    WHEN goal_type = 'tROAS Hybrid' THEN COALESCE(g30_spend, 0) + COALESCE(g30_adrev, 0)
    ELSE COALESCE(g30_spend, 0)
  END) / NULLIF(SUM(g30_revenue), 0) AS g30_croas

FROM playground.lp_client_performance_peter_3
WHERE date >= '2026-01-01'
  AND main_source = 'MP iOS'
GROUP BY date
ORDER BY date
