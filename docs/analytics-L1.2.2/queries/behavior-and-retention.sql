-- BigQuery Standard SQL. NOT EXECUTED: console/export access unavailable.
-- Replace YOUR_PROJECT.YOUR_DATASET; named parameters:
-- @scan_start/@scan_end: STRING YYYYMMDD (daily export table range),
-- @analysis_end: DATE, @report_timezone: STRING (e.g. Asia/Seoul),
-- @cohort_version: STRING (1.2.2), @action_releases: ARRAY<STRING>
-- (include L1.2.2 and future compatible releases such as L1.2.3 so upgrades
-- do not turn retained users into false churn).
-- Exclude recent immature dates; choose an explicit late-arrival lookback.
-- Results describe observed SDK instances, not people or all silent users.
-- release_unknown is not proof of Production: additionally exclude known
-- internal/TestFlight cohorts before publishing a production report.
CREATE TEMP FUNCTION str(p ANY TYPE, k STRING) AS (
  (SELECT value.string_value FROM UNNEST(p) WHERE key = k LIMIT 1)
);
CREATE TEMP FUNCTION num(p ANY TYPE, k STRING) AS (
  (SELECT value.int_value FROM UNNEST(p) WHERE key = k LIMIT 1)
);

CREATE TEMP TABLE normalized AS
SELECT
  user_pseudo_id, event_name, event_timestamp,
  COALESCE(num(event_params, 'occurred_at_ms'), DIV(event_timestamp, 1000)) AS action_ms,
  str(event_params, 'event_id') AS action_id,
  str(event_params, 'source') AS source,
  str(event_params, 'action') AS action,
  str(event_params, 'result') AS result,
  str(event_params, 'storage_stage') AS stage,
  str(event_params, 'type') AS content_type,
  num(event_params, 'is_premium') AS is_premium,
  CASE WHEN str(event_params, 'origin_app_version') = 'unknown_legacy' THEN 'unknown_legacy'
       ELSE COALESCE(str(event_params, 'origin_release'), str(event_params, 'analytics_release'))
  END AS action_release,
  app_info.version AS sdk_app_version,
  event_params
FROM `YOUR_PROJECT.YOUR_DATASET.events_*`
WHERE _TABLE_SUFFIX BETWEEN @scan_start AND @scan_end
  AND user_pseudo_id IS NOT NULL
  AND COALESCE(str(event_params, 'telemetry_environment'), '') NOT IN ('debug', 'sandbox')
  AND COALESCE(str(event_params, 'origin_environment'), '') NOT IN ('debug', 'sandbox')
  AND COALESCE(num(event_params, 'debug_mode'), 0) != 1
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY user_pseudo_id, event_name,
    COALESCE(str(event_params, 'event_id'),
      CONCAT(CAST(event_timestamp AS STRING), ':',
        COALESCE(CAST(event_bundle_sequence_id AS STRING), ''), ':',
        COALESCE(CAST(batch_event_index AS STRING), '')))
  ORDER BY event_timestamp
) = 1;

-- An original pending action is retained only after a matching successful
-- durable card-file stage. A missing commit is UNOBSERVED, not failed.
-- Legacy additions without a matching UUID remain outside this confirmed set.
CREATE TEMP TABLE actions AS
SELECT n.*,
  DATE(TIMESTAMP_MILLIS(n.action_ms), @report_timezone) AS action_day,
  IF(n.source IN ('live_activity', 'dynamic_island', 'widget', 'shortcut',
                 'intent', 'siri', 'action_button'), 'outside',
     IF(n.event_name = 'shortcut_quick_add', 'outside', 'inside')) AS channel
FROM normalized n
WHERE n.action_release IN UNNEST(@action_releases)
  AND (
    (n.event_name IN ('todo_created', 'memo_created', 'todo_completed', 'shortcut_quick_add')
      AND n.result = 'success')
    OR (n.event_name = 'l122_content_mutation'
      AND n.action IN ('edited', 'deleted', 'undone') AND n.result = 'success')
  )
  AND (COALESCE(n.stage, '') != 'pending_saved' OR EXISTS (
    SELECT 1 FROM normalized c
    WHERE c.user_pseudo_id = n.user_pseudo_id AND c.action_id = n.action_id
      AND c.event_name = 'l122_external_commit' AND c.result = 'success'
      AND c.stage = 'card_file'
      AND c.action = IF(n.event_name = 'shortcut_quick_add', 'add', 'complete')
  ))
  AND DATE(TIMESTAMP_MILLIS(n.action_ms), @report_timezone) <= @analysis_end;

-- Panel 1: original-action-day meaningful users, NOT Firebase's default DAU.
SELECT action_day, action_release, channel, COUNT(DISTINCT user_pseudo_id) AS meaningful_users,
  COUNTIF(event_name = 'todo_completed') AS completed_actions,
  COUNTIF(event_name IN ('todo_created', 'memo_created', 'shortcut_quick_add')) AS created_actions
FROM actions
GROUP BY action_day, action_release, channel ORDER BY action_day, action_release, channel;

-- Panel 2: distribution of meaningful days per observed user/week.
-- An instance can occur in both channels; do not add channel user counts.
WITH user_week AS (
  SELECT DATE_TRUNC(action_day, WEEK(MONDAY)) AS week,
    user_pseudo_id, COUNT(DISTINCT action_day) AS meaningful_days
  FROM actions GROUP BY week, user_pseudo_id
)
SELECT week, meaningful_days, COUNT(*) AS users
FROM user_week GROUP BY week, meaningful_days ORDER BY week, meaningful_days;

-- Panel 3: exact-day retention, not rolling retention. Each N has a mature
-- denominator. Cohorts include only first_open observed in the scanned range.
-- New-vs-existing local release_cohort is diagnostic, not a first_open substitute.
WITH cohorts AS (
  SELECT user_pseudo_id,
    MIN(DATE(TIMESTAMP_MICROS(event_timestamp), @report_timezone)) AS cohort_day
  FROM normalized
  WHERE event_name = 'first_open' AND sdk_app_version = @cohort_version
    AND user_pseudo_id IN (
      SELECT user_pseudo_id FROM normalized
      WHERE event_name = 'l122_release_observed'
        AND str(event_params, 'cohort') = 'new_observed'
    )
  GROUP BY user_pseudo_id
), days AS (
  SELECT DISTINCT user_pseudo_id, action_day FROM actions
), eligible AS (
  SELECT c.*, n FROM cohorts c CROSS JOIN UNNEST([1, 3, 7, 14, 30]) AS n
  WHERE DATE_ADD(cohort_day, INTERVAL n DAY) <= @analysis_end
)
SELECT cohort_day, n AS retention_day,
  COUNT(*) AS mature_users,
  COUNTIF(d.user_pseudo_id IS NOT NULL) AS returned_users,
  SAFE_DIVIDE(COUNTIF(d.user_pseudo_id IS NOT NULL), COUNT(*)) AS observed_retention
FROM eligible e LEFT JOIN days d ON d.user_pseudo_id = e.user_pseudo_id
  AND d.action_day = DATE_ADD(e.cohort_day, INTERVAL e.n DAY)
GROUP BY cohort_day, n ORDER BY cohort_day, n;

-- Panel 4: external success coverage and forwarding delay. One event can be
-- replayed; normalized already deduplicates name + random action UUID.
WITH commits AS (
  SELECT DISTINCT user_pseudo_id, action_id FROM normalized
  WHERE event_name = 'l122_external_commit' AND result = 'success'
    AND action_id IS NOT NULL
)
SELECT n.event_name, n.source, COUNT(*) AS pending_actions,
  COUNTIF(c.action_id IS NOT NULL) AS confirmed_card_file_actions,
  APPROX_QUANTILES(
    (num(n.event_params, 'forwarded_at_ms') - n.action_ms) / 3600000.0, 100
  )[OFFSET(95)] AS p95_forwarding_hours
FROM normalized n LEFT JOIN commits c
  ON c.user_pseudo_id = n.user_pseudo_id AND c.action_id = n.action_id
WHERE n.stage = 'pending_saved' AND n.action_release IN UNNEST(@action_releases)
GROUP BY n.event_name, n.source;

-- Revenue deliberately absent. Use ASC proceeds + AdMob actual earnings,
-- normalized currency/window/refunds, divided by 30 calendar days.
-- Never SUM Firebase quoted price/value/purchase_started as business revenue.
