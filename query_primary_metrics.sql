WITH

first_af_id AS (
  SELECT
    ROW_NUMBER() OVER (PARTITION BY uid ORDER BY partition_dt ASC) AS rn_uid,
    appsflyer_id,
    uid
  FROM datalake_prd.silver.ios_appsflyer_id_map
  QUALIFY row_number() over (partition by uid order by partition_dt asc) = 1
),

af_installs AS (
  SELECT
    appsflyer_id,
    media_source,
    LOWER(campaign_name) AS campaign_name
  FROM datalake_prd.silver.slv_appsflyer_ios__installs
  WHERE install_type = 'install'
),

af_users AS (
  SELECT
    uid,
    first_af_id.appsflyer_id,
    af_installs.media_source,
    media_source_cleansed,
    CASE
        WHEN af_installs.media_source = 'Apple Search Ads' THEN 'Apple Search Ads'
        WHEN media_source_cleansed IS NULL THEN 'organic'
        ELSE media_source_cleansed
    END AS media_source_final,
    CASE
      WHEN af_installs.media_source IS NULL THEN 'organic'
      WHEN af_installs.media_source = 'organic' THEN 'organic'
      WHEN af_installs.media_source = 'af_app_invites' THEN 'organic'
      ELSE 'paid'
    END AS acquisition_source,
    campaign_name,
    CASE
      WHEN campaign_name LIKE '%troas%' THEN 'spender'
      WHEN campaign_name LIKE '%iap%' THEN 'spender'
      WHEN campaign_name LIKE '%install%' THEN 'install'
      WHEN campaign_name LIKE '%cpi%' THEN 'install'
      WHEN campaign_name LIKE '%cpe%' THEN 'install'
      WHEN campaign_name LIKE '%cpa%' THEN 'install'
      WHEN campaign_name LIKE '%referral%' THEN 'null'
      WHEN campaign_name IS NULL THEN 'null'
      ELSE 'other'
    END AS campaign_type
  FROM datalake_prd.silver.ios_users
  LEFT JOIN first_af_id USING (uid)
  LEFT JOIN af_installs USING (appsflyer_id)
  LEFT JOIN datalake_prd.playground.media_source_taxonomy ON media_source_taxonomy.media_source = af_installs.media_source
),

user_country AS (
  SELECT
    uid,
    CASE
      WHEN UPPER(country) = 'USA' THEN 'US'
      WHEN UPPER(country) = 'US' THEN 'US'
      WHEN UPPER(country) = 'CA' THEN 'CA'
      WHEN UPPER(country) = 'GB' THEN 'GB'
      WHEN UPPER(country) = 'JP' THEN 'JP'
      ELSE 'Other'
    END AS country
  FROM silver.ios_users
),

ua_cost AS (
  --appsflyer costs
  SELECT
    DATE(date) AS dates,
    'false' AS blocked,
    CASE
        WHEN slv_appsflyer__cost.media_source = 'Apple Search Ads' THEN 'Apple Search Ads'
        WHEN media_source_cleansed IS NULL THEN 'organic'
        ELSE media_source_cleansed
    END AS media_source,
    CASE
      WHEN slv_appsflyer__cost.media_source IS NULL THEN 'organic'
      WHEN slv_appsflyer__cost.media_source = 'organic' THEN 'organic'
      WHEN slv_appsflyer__cost.media_source = 'af_app_invites' THEN 'organic'
      ELSE 'paid'
    END AS acquisition_source,
    CASE
      WHEN campaign_name LIKE '%troas%' THEN 'spender'
      WHEN campaign_name LIKE '%iap%' THEN 'spender'
      WHEN campaign_name LIKE '%install%' THEN 'install'
      WHEN campaign_name LIKE '%cpi%' THEN 'install'
      WHEN campaign_name LIKE '%cpe%' THEN 'install'
      WHEN campaign_name LIKE '%cpa%' THEN 'install'
      WHEN campaign_name LIKE '%referral%' THEN 'null'
      WHEN campaign_name IS NULL THEN 'null'
      ELSE 'other'
    END AS campaign_type,
    CASE
      WHEN UPPER(country_code) = 'USA' THEN 'US'
      WHEN UPPER(country_code) = 'US' THEN 'US'
      WHEN UPPER(country_code) = 'CA' THEN 'CA'
      WHEN UPPER(country_code) = 'GB' THEN 'GB'
      WHEN UPPER(country_code) = 'JP' THEN 'JP'
      ELSE 'Other'
    END AS country,
    SUM(cost) as ua_cost
FROM datalake_prd.silver.slv_appsflyer__cost
LEFT JOIN datalake_prd.playground.media_source_taxonomy ON media_source_taxonomy.media_source = slv_appsflyer__cost.media_source
WHERE app_id IN ( 'id6739352969')
  AND date >= '2026-01-01'
GROUP BY ALL

UNION ALL

--tinuiti costs
  SELECT
    date,
    'false' AS blocked,
    CASE
      WHEN media_source = 'linear' THEN 'tinuiti_linear'
      WHEN media_source = 'audio' THEN 'tinuiti_audio'
      WHEN media_source = 'parallel' THEN 'tinuiti_parallel'
    END AS media_source,
    'organic' AS acquisition_source,
    'null' AS campaign_type,
    UPPER(country) AS country,
    SUM(cost) AS ua_cost
  FROM datalake_prd.playground.direct_buy_daily_platform
  WHERE platform = 'ios'
    AND date <= CURRENT_DATE()
    AND date >= '2026-01-01'
    AND ingested_at = (SELECT max(ingested_at) FROM datalake_prd.playground.direct_buy_daily_platform)
  GROUP BY ALL
),

users AS (
  SELECT
    date(ios_users.created_at) AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(af_users.acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(user_country.country, 'Other') AS country,
    COUNT(distinct ios_users.uid) AS DNU
  FROM datalake_prd.silver.ios_users
  LEFT JOIN af_users ON ios_users.uid = af_users.uid
  LEFT JOIN silver.lp_users ON lp_users.host_uid = ios_users.uid
  LEFT JOIN user_country ON ios_users.uid = user_country.uid
  WHERE date(ios_users.created_at) >= '2026-01-01'
  GROUP BY ALL
),

att_accepted AS (
  SELECT
    date(ios_att_accepted.created_at) AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(user_country.country, 'Other') AS country,
    COUNT(DISTINCT CASE WHEN status = 'accepted' THEN ios_att_accepted.uid END) AS num_att_accepted,
    COUNT(DISTINCT CASE WHEN status = 'declined' THEN ios_att_accepted.uid END) AS num_att_declined,
    COUNT(DISTINCT CASE WHEN status = 'accepted' THEN ios_att_accepted.uid END)
      - COUNT(DISTINCT CASE WHEN status = 'declined' THEN ios_att_accepted.uid END) AS net_att_accepted
  FROM datalake_prd.silver.ios_att_accepted
  LEFT JOIN af_users ON ios_att_accepted.uid = af_users.uid
  LEFT JOIN silver.lp_users ON lp_users.host_uid = ios_att_accepted.uid
  LEFT JOIN user_country ON ios_att_accepted.uid = user_country.uid
  WHERE date(ios_att_accepted.created_at) >= '2026-01-01'
  GROUP BY ALL
),

precise_geolocation AS (
  SELECT
    te.partition_dt AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(user_country.country, 'Other') AS country,
    COUNT(DISTINCT te.uid) AS num_precise_geolocation
  FROM datalake_prd.silver.mistplay_telemetry_ios_events as te
  LEFT JOIN af_users ON te.uid = af_users.uid
  LEFT JOIN silver.lp_users ON lp_users.host_uid = te.uid
  LEFT JOIN user_country ON te.uid = user_country.uid
  WHERE type = 'PRECISE_GEOLOCATION'
    AND te.partition_dt >= '2026-03-19'
    AND te.partition_dt < CURRENT_DATE
    AND env = 'prd'
  GROUP BY ALL
),

push_notifications AS (
  SELECT
    te.uid,
    MAX(te.partition_dt) AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(user_country.country, 'Other') AS country,
    CASE when type = 'ALLOW_NOTIFICATIONS' THEN true
            when type = 'UPDATE_NOTIFICATIONS' AND try_cast(context:['is_token_enabled'] as boolean) is true then true
            when type = 'UPDATE_NOTIFICATIONS' AND try_cast(context:['is_token_enabled'] as boolean) is false then false
            when type = 'UPDATE_PUSH_NOTIFICATION_SETTINGS' and try_cast(context:['is_notifications_enabled'] as boolean) is true then true
            when type = 'UPDATE_PUSH_NOTIFICATION_SETTINGS' and try_cast(context:['is_notifications_enabled'] as boolean) is false then false
    ELSE null
    END as allow_notifications
  FROM datalake_prd.silver.mistplay_telemetry_ios_events as te
  LEFT JOIN af_users ON te.uid = af_users.uid
  LEFT JOIN silver.lp_users ON lp_users.host_uid = te.uid
  LEFT JOIN user_country ON te.uid = user_country.uid
  WHERE type IN ('ALLOW_NOTIFICATIONS', 'UPDATE_PUSH_NOTIFICATION_SETTINGS', 'UPDATE_NOTIFICATIONS')
    AND te.partition_dt >= '2026-03-18'
    AND te.partition_dt < CURRENT_DATE
    AND env = 'prd'
  GROUP BY ALL
),

push_notification_permissions AS (
  SELECT
    dates,
    blocked,
    media_source,
    acquisition_source,
    campaign_type,
    country,
    COUNT(DISTINCT CASE WHEN allow_notifications IS TRUE THEN uid END) AS num_push_notifications_permissions_allowed,
    COUNT(DISTINCT CASE WHEN allow_notifications IS FALSE THEN uid END) AS num_push_notifications_permissions_declined,
    COUNT(DISTINCT CASE WHEN allow_notifications IS TRUE THEN uid END) - COUNT(DISTINCT CASE WHEN allow_notifications IS FALSE THEN uid END)
      AS net_push_notification_permissions
  FROM push_notifications
  GROUP BY ALL
),

dau AS (
SELECT
  DATE(session_start) AS dates,
  COALESCE(lp_users.blocked, false) AS blocked,
  COALESCE(af_users.media_source_final, 'organic') AS media_source,
  COALESCE(acquisition_source, 'organic') AS acquisition_source,
  COALESCE(campaign_type, 'null') AS campaign_type,
  COALESCE(user_country.country, 'Other') AS country,
        COUNT(DISTINCT full_table.uid) AS DAU
FROM (
  SELECT uid,
         session_start,
         session_end
  FROM silver.ios_user_activity
  UNION ALL
  SELECT uid,
         DATE_ADD(session_start, 1) AS session_start,
         session_end
  FROM silver.ios_user_activity
  WHERE DATE(session_start) < DATE(session_end)
) full_table
LEFT JOIN af_users ON full_table.uid = af_users.uid
LEFT JOIN silver.lp_users ON lp_users.host_uid = full_table.uid
LEFT JOIN user_country ON full_table.uid = user_country.uid
WHERE date(session_start) >= '2026-01-01'
GROUP BY ALL
),

active_users AS (
  SELECT DISTINCT
    DATE(session_start) AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    full_table.uid,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(user_country.country, 'Other') AS country
  FROM (
    SELECT uid,
           session_start,
           session_end
    FROM silver.ios_user_activity
    UNION ALL
    SELECT uid,
           DATE_ADD(session_start, 1) AS session_start,
           session_end
    FROM silver.ios_user_activity
    WHERE DATE(session_start) < DATE(session_end)
  ) full_table
  LEFT JOIN af_users ON full_table.uid = af_users.uid
  LEFT JOIN silver.lp_users ON lp_users.host_uid = full_table.uid
  LEFT JOIN user_country ON full_table.uid = user_country.uid
  WHERE DATE(session_start) >= '2026-01-01'
),

user_cumulative_points AS (
  SELECT
    active_users.dates,
    active_users.blocked,
    active_users.uid,
    media_source,
    acquisition_source,
    campaign_type,
    country,
    SUM(ios_view_rewards.points) AS cumulative_points
  FROM active_users
  LEFT JOIN silver.ios_view_rewards
    ON active_users.uid = ios_view_rewards.uid
    AND DATE(ios_view_rewards.earned_at) <= active_users.dates
  GROUP BY ALL
),

dau_with_cumulative_points AS (
  SELECT
    dates,
    blocked,
    media_source,
    acquisition_source,
    campaign_type,
    country,
    SUM(COALESCE(cumulative_points, 0)) AS total_cumulative_points_balance
  FROM user_cumulative_points
  GROUP BY ALL
),

rewards AS (
  SELECT
    DATE(earned_at) AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(user_country.country, 'Other') AS country,
    SUM(CASE WHEN source = 'QUICK_GAME' THEN trophies ELSE 0 END) AS quick_games_trophies_rewarded,
    SUM(CASE WHEN source = 'QUICK_GAME' THEN points ELSE 0 END) AS quick_games_points_rewarded,
    SUM(CASE WHEN source = 'GAME_TRIVIA' THEN trophies ELSE 0 END) AS game_trivia_trophies_rewarded,
    SUM(CASE WHEN source = 'GAME_TRIVIA' THEN points ELSE 0 END) AS game_trivia_points_rewarded,
    SUM(CASE WHEN source = 'SURVEY' THEN trophies ELSE 0 END) AS surveys_trophies_rewarded,
    SUM(CASE WHEN source = 'SURVEY' THEN points ELSE 0 END) AS surveys_points_rewarded,
    SUM(CASE WHEN source = 'LOYALTY_PLAY' THEN trophies ELSE 0 END) AS loyalty_play_trophies_rewarded,
    SUM(CASE WHEN source = 'LOYALTY_PLAY' THEN points ELSE 0 END) AS loyalty_play_points_rewarded,
    SUM(CASE WHEN source = 'DAILY_STREAK' THEN points ELSE 0 END) AS daily_streak_points_rewarded,
    SUM(CASE WHEN source = 'PROMO_CODES_REDEEMED' THEN points ELSE 0 END) AS promo_code_points_rewarded,
    SUM(CASE WHEN source = 'TOURNAMENTS' THEN points ELSE 0 END) AS tournaments_points_rewarded,
    SUM(CASE WHEN source = 'TREASURE_HUNT_CHEST_OPEN' THEN points ELSE 0 END) AS treasure_hunt_points_rewarded,
    SUM(CASE WHEN source = 'TREASURE_HUNT_KEY_PURCHASE' THEN points ELSE 0 END) AS treasure_hunt_points_redeemed,
    SUM(CASE WHEN source = 'IAP_TASKS' THEN points ELSE 0 END) AS iap_offers_points_rewarded,
    SUM(CASE WHEN source = 'REFERRAL_REFEREE_BONUS' OR source = 'REFERRAL_REFERRER_BONUS' THEN points ELSE 0 END) AS referral_points_rewarded,
    SUM(CASE WHEN source = 'WELCOME_BONUS' THEN points ELSE 0 END) AS welcome_bonus_points_rewarded,
    SUM(CASE WHEN source = 'RETARGETED_INSTALL' THEN points ELSE 0 END) AS failed_install_points_rewarded,
    SUM(CASE WHEN source = 'CUSTOMER_SUPPORT_COMPENSATION' THEN points ELSE 0 END) AS cs_comped_points_rewarded
  FROM datalake_prd.silver.ios_view_rewards
  LEFT JOIN af_users ON ios_view_rewards.uid = af_users.uid
  LEFT JOIN silver.lp_users ON lp_users.host_uid = ios_view_rewards.uid
  LEFT JOIN user_country ON ios_view_rewards.uid = user_country.uid
  WHERE date(earned_at) >= '2026-01-01'
  GROUP BY ALL
),

surveys AS (
  SELECT
    DATE(earned_at) AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(user_country.country, 'Other') AS country,
    SUM(revenue) AS total_survey_revenue,
    COUNT(*) AS num_surveys_completed
  FROM datalake_prd.silver.ios_surveys
  LEFT JOIN af_users ON ios_surveys.uid = af_users.uid
  LEFT JOIN silver.lp_users ON lp_users.host_uid = ios_surveys.uid
  LEFT JOIN user_country ON ios_surveys.uid = user_country.uid
  WHERE date(earned_at) >= '2026-01-01'
  GROUP BY ALL
),

users_completing_surveys_numbered AS (
  SELECT
    distinct ios_surveys.uid,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(user_country.country, 'Other') AS country,
    DATE(earned_at) AS dates,
    ROW_NUMBER() OVER(PARTITION BY ios_surveys.uid ORDER BY earned_at) AS survey_row_number
  FROM datalake_prd.silver.ios_surveys
  LEFT JOIN af_users ON ios_surveys.uid = af_users.uid
  LEFT JOIN silver.lp_users ON lp_users.host_uid = ios_surveys.uid
  LEFT JOIN user_country ON ios_surveys.uid = user_country.uid
  WHERE date(earned_at) >= '2026-01-01'
),

users_completing_surveys AS (
  SELECT
    dates,
    blocked,
    COALESCE(media_source, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(country, 'Other') AS country,
    COUNT(DISTINCT CASE WHEN survey_row_number = 1 THEN uid END) AS num_users_completed_profile_survey,
    COUNT(DISTINCT CASE WHEN survey_row_number > 1 THEN uid END) AS num_users_completed_survey
  FROM users_completing_surveys_numbered
  GROUP BY ALL
),

mistoffers AS (
  SELECT
    pid,
    MMP,
    goal_type,
    CASE
      WHEN goal_type LIKE '%IAP%' THEN 'IAP'
      WHEN goal_type LIKE '%IAA%' THEN 'IAA'
      ELSE 'Other'
    END AS offer_type
  FROM silver.slv_mistoffers__daily
  WHERE goal_type NOT LIKE '%Manual%'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY pid ORDER BY date DESC) = 1
),

lp_revenue AS (
  SELECT
    DATE(converted_at) AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(user_country.country, 'Other') AS country,
    COUNT(*) AS num_lp_game_installs,
    COUNT(CASE WHEN mistoffers.offer_type = 'IAP' THEN lp_installs.pid END) AS num_iap_installs,
    COUNT(CASE WHEN mistoffers.offer_type = 'IAA' THEN lp_installs.pid END) AS num_iaa_installs,
    SUM(revenue * revenue_split) AS total_lp_revenue,
    SUM(CASE WHEN mistoffers.offer_type = 'IAP' THEN revenue * revenue_split END) AS iap_install_revenue,
    SUM(CASE WHEN mistoffers.offer_type = 'IAA' THEN revenue * revenue_split END) AS iaa_install_revenue
  FROM silver.lp_installs
  LEFT JOIN silver.lp_users ON lp_installs.uid = lp_users.uid
  LEFT JOIN af_users ON lp_users.host_uid = af_users.uid
  LEFT JOIN user_country ON lp_users.host_uid = user_country.uid
  LEFT JOIN mistoffers ON mistoffers.pid = lp_installs.pid
  WHERE lp_installs.host_id = 'com.481studios.pocketup'
  AND converted_at IS NOT NULL
  AND date(converted_at) >= '2026-01-01'
  GROUP BY ALL
),

lp_iaa_revenue AS (
  SELECT
    DATE(lp_iaa.created_at) AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(user_country.country, 'Other') AS country,
    SUM(amount_usd) AS total_lp_iaa_revenue
  FROM silver.lp_iaa
  LEFT JOIN silver.lp_users ON lp_iaa.uid = lp_users.uid
  LEFT JOIN af_users ON lp_users.host_uid = af_users.uid
  LEFT JOIN user_country ON lp_users.host_uid = user_country.uid
  WHERE lp_iaa.host_id = 'com.481studios.pocketup'
    AND date(lp_iaa.created_at) >= '2026-01-01'
  GROUP BY ALL
),

lp_users AS (
  SELECT
    DATE(created_at) AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(user_country.country, 'Other') AS country,
    COUNT(DISTINCT lp_users.uid) AS num_new_lp_users
  FROM silver.lp_users
  LEFT JOIN af_users ON lp_users.host_uid = af_users.uid
  LEFT JOIN user_country ON lp_users.host_uid = user_country.uid
  WHERE host_id = 'com.481studios.pocketup'
  AND date(created_at) >= '2026-01-01'
  GROUP BY ALL
),

lp_dau AS (
    SELECT
        DATE(lp_user_sessions.created_at) AS dates,
        COALESCE(lp_users.blocked, false) AS blocked,
        COALESCE(af_users.media_source_final, 'organic') AS media_source,
        COALESCE(acquisition_source, 'organic') AS acquisition_source,
        COALESCE(campaign_type, 'null') AS campaign_type,
        COALESCE(user_country.country, 'Other') AS country,
        COUNT(distinct lp_user_sessions.uid) AS lp_dau
    FROM silver.lp_user_sessions
    LEFT JOIN silver.lp_users ON lp_users.uid = lp_user_sessions.uid
    LEFT JOIN af_users ON lp_users.host_uid = af_users.uid
    LEFT JOIN user_country ON lp_users.host_uid = user_country.uid
    WHERE LOWER(lp_user_sessions.host_id) = 'com.481studios.pocketup'
    AND date(lp_user_sessions.created_at) >= '2026-01-01'
    GROUP BY ALL
),

lp_iap AS (
  SELECT
    DATE(lp_iap.created_at) AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(user_country.country, 'Other') AS country,
    SUM(amount_usd) AS lp_iap_spend_usd
  FROM silver.lp_iap
  LEFT JOIN silver.lp_users ON lp_users.uid = lp_iap.uid
  LEFT JOIN af_users ON lp_users.host_uid = af_users.uid
  LEFT JOIN user_country ON lp_users.host_uid = user_country.uid
  WHERE lp_iap.host_id = 'com.481studios.pocketup'
  AND date(lp_users.created_at) >= '2026-01-01'
  GROUP BY ALL
),

failed_installs AS (
  SELECT
    DATE(rewarded_at) AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(user_country.country, 'Other') AS country,
    COUNT(*) AS num_failed_installs_rewarded,
    COUNT(DISTINCT ios_retargeted_installs_fact.uid) AS num_users_rewarded_for_failed_installs
  FROM silver.ios_retargeted_installs_fact
  LEFT JOIN silver.lp_users ON lp_users.host_uid = ios_retargeted_installs_fact.uid
  LEFT JOIN af_users ON ios_retargeted_installs_fact.uid = af_users.uid
  LEFT JOIN user_country ON ios_retargeted_installs_fact.uid = user_country.uid
  WHERE date(rewarded_at) >= '2026-01-01'
  GROUP BY ALL
),

purchases AS (
  SELECT
    DATE(purchased_at) AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    CASE
      WHEN UPPER(ios_view_purchases.country) IN ('CA', 'GB', 'JP', 'US') THEN UPPER(country)
      ELSE 'Other'
    END AS country,
    SUM(CASE WHEN reward_type = 'card' THEN cost_in_usd END) AS gc_cost,
    SUM(CASE WHEN reward_type = 'card' THEN price END) AS gc_points_redeemed,
    SUM(CASE WHEN reward_type = 'sweepstakes' THEN price END) AS sweepstakes_points_redeemed
  FROM datalake_prd.silver.ios_view_purchases
  LEFT JOIN af_users ON ios_view_purchases.uid = af_users.uid
  LEFT JOIN silver.lp_users ON lp_users.host_uid = ios_view_purchases.uid
  WHERE date(purchased_at) >= '2026-01-01'
    AND order_status = 'completed'
  GROUP BY ALL
),

pending_gc_cost AS (
  SELECT
    DATE(datetime) AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    CASE
      WHEN UPPER(mistplayshoppurchases.country) IN ('CA', 'GB', 'JP', 'US') THEN UPPER(country)
      ELSE 'Other'
    END AS country,
    SUM(valueInUsd) AS pending_gc_cost
  FROM silver.mistplayshoppurchases
  LEFT JOIN af_users ON mistplayshoppurchases.uid = af_users.uid
  LEFT JOIN silver.lp_users ON lp_users.host_uid = mistplayshoppurchases.uid
  WHERE order_status = 'pending'
    AND package_id = 'com.481studios.pocketup'
    AND reward_type = 'card'
    AND date(datetime) >= '2026-01-01'
  GROUP BY ALL
),

subscriptions AS (
  SELECT
    DATE(subscription_start_date) AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(user_country.country, 'Other') AS country,
    SUM(price_usd) AS game_pass_revenue
  FROM silver.ios_gamepass_subscriptions
  LEFT JOIN af_users ON ios_gamepass_subscriptions.uid = af_users.uid
  LEFT JOIN silver.lp_users ON lp_users.host_uid = ios_gamepass_subscriptions.uid
  LEFT JOIN user_country ON ios_gamepass_subscriptions.uid = user_country.uid
  WHERE env = 'prd'
    AND date(subscription_start_date) >= '2026-01-01'
  GROUP BY ALL
),

game_pass_renewals AS (
  SELECT
    DATE(event_timestamp) AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(user_country.country, 'Other') AS country,
    SUM(COALESCE(price_usd, price)) as game_pass_renewal_revenue
  FROM datalake_prd.silver.ios_gamepass_subscription_fact
  LEFT JOIN af_users ON ios_gamepass_subscription_fact.uid = af_users.uid
  LEFT JOIN silver.lp_users ON lp_users.host_uid = ios_gamepass_subscription_fact.uid
  LEFT JOIN user_country ON ios_gamepass_subscription_fact.uid = user_country.uid
  WHERE type = 'GAMEPASS_RENEWAL'
  AND env = 'prd'
  AND date(event_timestamp) >= '2026-01-01'
  GROUP BY ALL
),

quick_games_cohorted AS (
  SELECT
    DATE(ios_users.created_at) AS dates,
    COALESCE(lp_users.blocked, false) AS blocked,
    COALESCE(af_users.media_source_final, 'organic') AS media_source,
    COALESCE(af_users.acquisition_source, 'organic') AS acquisition_source,
    COALESCE(campaign_type, 'null') AS campaign_type,
    COALESCE(user_country.country, 'Other') AS country,
    COUNT(DISTINCT CASE WHEN DATE(ios_users.created_at) > DATE(NOW())- interval 0 day then NULL WHEN DATE_DIFF(DAY, ios_users.created_at,ios_game_rewards.earned_at) <= 0 then ios_game_rewards.uid else NULL END) as d0_quick_game_players,
    COUNT(DISTINCT CASE WHEN DATE(ios_users.created_at) > DATE(NOW())- interval 1 day then NULL WHEN DATE_DIFF(DAY, ios_users.created_at, ios_game_rewards.earned_at) <= 1 then ios_game_rewards.uid else NULL END) as d1_quick_game_players,
    COUNT(DISTINCT CASE WHEN DATE(ios_users.created_at) > DATE(NOW())- interval 7 day then NULL WHEN DATE_DIFF(DAY, ios_users.created_at, ios_game_rewards.earned_at) <= 7 then ios_game_rewards.uid else NULL END) as d7_quick_game_players,
    COUNT(DISTINCT CASE WHEN DATE(ios_users.created_at) > DATE(NOW())- interval 30 day then NULL WHEN DATE_DIFF(DAY, ios_users.created_at, ios_game_rewards.earned_at) <= 30 then ios_game_rewards.uid else NULL END) as d30_quick_game_players
  FROM datalake_prd.silver.ios_users
  LEFT JOIN datalake_prd.silver.ios_game_rewards ON ios_users.uid = ios_game_rewards.uid
  LEFT JOIN af_users ON ios_users.uid = af_users.uid
  LEFT JOIN silver.lp_users ON lp_users.host_uid = ios_users.uid
  LEFT JOIN user_country ON user_country.uid = ios_users.uid
  WHERE date(ios_users.created_at) >= '2026-01-01'
  GROUP BY ALL
),

users_dxx AS (
    SELECT
        DATE(ios_users_dxx.created_at) AS dates,
        COALESCE(lp_users.blocked, false) AS blocked,
        COALESCE(af_users.media_source_final, 'organic') AS media_source,
        COALESCE(acquisition_source, 'organic') AS acquisition_source,
        COALESCE(campaign_type, 'null') AS campaign_type,
        COALESCE(user_country.country, 'Other') AS country,
        COUNT(distinct ios_users_dxx.uid) as num_users,
        SUM(is_D0_ret) AS d0_retention,
        SUM(is_D1_ret) AS d1_retention,
        SUM(is_D7_ret) AS d7_retention,
        SUM(is_D30_ret) AS d30_retention,
        SUM(is_D60_ret) AS d60_retention,
        SUM(is_D90_ret) AS d90_retention,
        SUM(D0_revenue) AS d0_revenue,
        SUM(D1_revenue) AS d1_revenue,
        SUM(D7_revenue) AS d7_revenue,
        SUM(D30_revenue) AS d30_revenue,
        SUM(D60_revenue) AS d60_revenue,
        SUM(D90_revenue) AS d90_revenue,
        SUM(D0_cost) AS d0_cost,
        SUM(D1_cost) AS d1_cost,
        SUM(D7_cost) AS d7_cost,
        SUM(D30_cost) AS d30_cost,
        SUM(D60_cost) AS d60_cost,
        SUM(D90_cost) AS d90_cost,
        SUM(D0_n_installs) AS d0_n_installs,
        SUM(D1_n_installs) AS d1_n_installs,
        SUM(D7_n_installs) AS d7_n_installs,
        SUM(D30_n_installs) AS d30_n_installs,
        SUM(D60_n_installs) AS d60_n_installs,
        SUM(D90_n_installs) AS d90_n_installs,
        SUM(CASE WHEN D0_n_installs IS NULL THEN NULL WHEN D0_n_installs >= 1 then 1 ELSE 0 END) AS d0_n_installers,
        SUM(CASE WHEN D1_n_installs IS NULL THEN NULL WHEN D1_n_installs >= 1 then 1 ELSE 0 END) AS d1_n_installers,
        SUM(CASE WHEN D7_n_installs IS NULL THEN NULL WHEN D7_n_installs >= 1 then 1 ELSE 0 END) AS d7_n_installers,
        SUM(CASE WHEN D30_n_installs IS NULL THEN NULL WHEN D30_n_installs >= 1 then 1 ELSE 0 END) AS d30_n_installers,
        SUM(CASE WHEN D60_n_installs IS NULL THEN NULL WHEN D60_n_installs >= 1 then 1 ELSE 0 END) AS d60_n_installers,
        SUM(CASE WHEN D90_n_installs IS NULL THEN NULL WHEN D90_n_installs >= 1 then 1 ELSE 0 END) AS d90_n_installers,
        SUM(D0_iap_spend) AS d0_spend,
        SUM(D1_iap_spend) AS d1_spend,
        SUM(D7_iap_spend) AS d7_spend,
        SUM(D30_iap_spend) AS d30_spend,
        SUM(D60_iap_spend) AS d60_spend,
        SUM(D90_iap_spend) AS d90_spend,
        SUM(CASE
          WHEN is_D0_ret IS NULL THEN NULL
          WHEN is_D0_ret > 0 OR is_D0_game_ret > 0 THEN 1
          ELSE 0 END)
        AS d0_hybrid_retention,
        SUM(CASE
          WHEN is_D1_ret IS NULL THEN NULL
          WHEN is_D1_ret > 0 OR is_D1_game_ret > 0 THEN 1
          ELSE 0 END)
        AS d1_hybrid_retention,
        SUM(CASE
          WHEN is_D7_ret IS NULL THEN NULL
          WHEN is_D7_ret > 0 OR is_D7_game_ret > 0 THEN 1
          ELSE 0 END)
        AS d7_hybrid_retention,
        SUM(CASE
          WHEN is_D30_ret IS NULL THEN NULL
          WHEN is_D30_ret > 0 OR is_D30_game_ret > 0 THEN 1
          ELSE 0 END)
        AS d30_hybrid_retention,
        SUM(CASE
          WHEN is_D60_ret IS NULL THEN NULL
          WHEN is_D60_ret > 0 OR is_D60_game_ret > 0 THEN 1
          ELSE 0 END)
        AS d60_hybrid_retention,
        SUM(CASE
          WHEN is_D90_ret IS NULL THEN NULL
          WHEN is_D90_ret > 0 OR is_D90_game_ret > 0 THEN 1
          ELSE 0 END)
        AS d90_hybrid_retention,
        SUM(D0_points_rewarded) AS d0_points_rewarded,
        SUM(D1_points_rewarded) AS d1_points_rewarded,
        SUM(D7_points_rewarded) AS d7_points_rewarded,
        SUM(D30_points_rewarded) AS d30_points_rewarded,
        SUM(D60_points_rewarded) AS d60_points_rewarded,
        SUM(D90_points_rewarded) AS d90_points_rewarded
    FROM silver.ios_users_dxx
    LEFT JOIN af_users ON ios_users_dxx.uid = af_users.uid
    LEFT JOIN silver.lp_users ON lp_users.host_uid = ios_users_dxx.uid
    LEFT JOIN user_country ON ios_users_dxx.uid = user_country.uid
    WHERE date(ios_users_dxx.created_at) >= '2026-01-01'
    GROUP BY ALL
),

staging AS (
  SELECT
    dates,
    blocked,
    media_source,
    acquisition_source,
    campaign_type,
    country,
    COALESCE(ua_cost, 0) AS ua_cost,
    COALESCE(DNU, 0) AS DNU,
    COALESCE(net_att_accepted, 0) AS net_att_accepted,
    COALESCE(num_precise_geolocation, 0) AS num_precise_geolocation,
    COALESCE(net_push_notification_permissions, 0) AS net_push_notification_permissions,
    COALESCE(dau, 0) AS DAU,
    COALESCE(total_cumulative_points_balance, 0) AS total_cumulative_points_balance,
    COALESCE(quick_games_trophies_rewarded, 0) AS quick_games_trophies_rewarded,
    COALESCE(quick_games_points_rewarded, 0) AS quick_games_points_rewarded,
    COALESCE(game_trivia_trophies_rewarded, 0) AS game_trivia_trophies_rewarded,
    COALESCE(game_trivia_points_rewarded, 0) AS game_trivia_points_rewarded,
    COALESCE(surveys_trophies_rewarded, 0) AS surveys_trophies_rewarded,
    COALESCE(surveys_points_rewarded, 0) AS surveys_points_rewarded,
    COALESCE(loyalty_play_trophies_rewarded, 0) AS loyalty_play_trophies_rewarded,
    COALESCE(loyalty_play_points_rewarded, 0) AS loyalty_play_points_rewarded,
    COALESCE(daily_streak_points_rewarded, 0) AS daily_streak_points_rewarded,
    COALESCE(promo_code_points_rewarded, 0) AS promo_code_points_rewarded,
    COALESCE(tournaments_points_rewarded, 0) AS tournaments_points_rewarded,
    COALESCE(treasure_hunt_points_rewarded, 0) AS treasure_hunt_points_rewarded,
    COALESCE(treasure_hunt_points_redeemed, 0) AS treasure_hunt_points_redeemed,
    COALESCE(iap_offers_points_rewarded, 0) AS iap_offers_points_rewarded,
    COALESCE(referral_points_rewarded, 0) AS referral_points_rewarded,
    COALESCE(welcome_bonus_points_rewarded, 0) AS welcome_bonus_points_rewarded,
    COALESCE(failed_install_points_rewarded, 0) AS failed_install_points_rewarded,
    COALESCE(cs_comped_points_rewarded, 0) AS cs_comped_points_rewarded,
    COALESCE(total_survey_revenue, 0) AS total_survey_revenue,
    COALESCE(num_surveys_completed, 0) AS num_surveys_completed,
    COALESCE(num_users_completed_profile_survey, 0) AS num_users_completed_profile_survey,
    COALESCE(num_users_completed_survey, 0) AS num_users_completed_survey,
    COALESCE(num_lp_game_installs, 0) AS num_lp_game_installs,
    COALESCE(num_iap_installs, 0) AS num_iap_installs,
    COALESCE(num_iaa_installs, 0) AS num_iaa_installs,
    COALESCE(total_lp_revenue, 0) AS total_lp_revenue,
    COALESCE(iap_install_revenue, 0) AS iap_install_revenue,
    COALESCE(iaa_install_revenue, 0) AS iaa_install_revenue,
    COALESCE(total_lp_iaa_revenue, 0) AS total_lp_iaa_revenue,
    COALESCE(num_new_lp_users, 0) AS num_new_lp_users,
    COALESCE(lp_dau, 0) AS lp_dau,
    COALESCE(lp_iap_spend_usd, 0) AS lp_iap_spend_usd,
    COALESCE(num_failed_installs_rewarded, 0) AS num_failed_installs_rewarded,
    COALESCE(num_users_rewarded_for_failed_installs, 0) AS num_users_rewarded_for_failed_installs,
    COALESCE(gc_cost, 0) AS gc_cost,
    COALESCE(gc_points_redeemed, 0) AS gc_points_redeemed,
    COALESCE(sweepstakes_points_redeemed, 0) AS sweepstakes_points_redeemed,
    COALESCE(pending_gc_cost, 0) AS pending_gc_cost,
    COALESCE(game_pass_revenue, 0) AS game_pass_revenue,
    COALESCE(game_pass_renewal_revenue, 0) AS game_pass_renewal_revenue,
    COALESCE(users_dxx.num_users, 0) AS num_users,
    users_dxx.d0_retention,
    users_dxx.d1_retention,
    users_dxx.d7_retention,
    users_dxx.d30_retention,
    users_dxx.d60_retention,
    users_dxx.d90_retention,
    users_dxx.d0_revenue,
    users_dxx.d1_revenue,
    users_dxx.d7_revenue,
    users_dxx.d30_revenue,
    users_dxx.d60_revenue,
    users_dxx.d90_revenue,
    users_dxx.d0_cost,
    users_dxx.d1_cost,
    users_dxx.d7_cost,
    users_dxx.d30_cost,
    users_dxx.d60_cost,
    users_dxx.d90_cost,
    users_dxx.d0_n_installs,
    users_dxx.d1_n_installs,
    users_dxx.d7_n_installs,
    users_dxx.d30_n_installs,
    users_dxx.d60_n_installs,
    users_dxx.d90_n_installs,
    users_dxx.d0_n_installers,
    users_dxx.d1_n_installers,
    users_dxx.d7_n_installers,
    users_dxx.d30_n_installers,
    users_dxx.d60_n_installers,
    users_dxx.d90_n_installers,
    users_dxx.d0_spend,
    users_dxx.d1_spend,
    users_dxx.d7_spend,
    users_dxx.d30_spend,
    users_dxx.d60_spend,
    users_dxx.d90_spend,
    users_dxx.d0_hybrid_retention,
    users_dxx.d1_hybrid_retention,
    users_dxx.d7_hybrid_retention,
    users_dxx.d30_hybrid_retention,
    users_dxx.d60_hybrid_retention,
    users_dxx.d90_hybrid_retention,
    users_dxx.d0_points_rewarded,
    users_dxx.d1_points_rewarded,
    users_dxx.d7_points_rewarded,
    users_dxx.d30_points_rewarded,
    users_dxx.d60_points_rewarded,
    users_dxx.d90_points_rewarded,
    NULLIF(d0_quick_game_players, 0) as d0_quick_game_players,
    NULLIF(d1_quick_game_players, 0) as d1_quick_game_players,
    NULLIF(d7_quick_game_players, 0) as d7_quick_game_players,
    NULLIF(d30_quick_game_players, 0) as d30_quick_game_players
  FROM
    users
    FULL JOIN ua_cost USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN att_accepted USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN precise_geolocation USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN push_notification_permissions USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN dau USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN dau_with_cumulative_points USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN rewards USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN surveys USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN users_completing_surveys USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN lp_revenue USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN lp_iaa_revenue USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN lp_users USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN lp_dau USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN lp_iap USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN failed_installs USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN purchases USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN pending_gc_cost USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN subscriptions USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN game_pass_renewals USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN users_dxx USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
    FULL JOIN quick_games_cohorted USING (dates, blocked, media_source, acquisition_source, campaign_type, country)
)

SELECT * FROM staging
