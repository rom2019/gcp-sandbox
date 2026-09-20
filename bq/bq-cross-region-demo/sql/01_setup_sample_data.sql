-- =============================================================================
-- Sendbird Solution Comparison: Sample Data Setup
-- Simulates Sendbird chat messages and channel events for Cross-Region testing
-- Source Dataset: e.g. sendbird_us (us-central1)
-- =============================================================================

-- 1. Create Sendbird Chat Messages Table (Partitioned & Clustered)
CREATE TABLE IF NOT EXISTS `@PROJECT_ID@.@SOURCE_DATASET@.chat_messages` (
  message_id STRING NOT NULL,
  channel_url STRING NOT NULL,
  user_id STRING NOT NULL,
  message_type STRING, -- 'MESG', 'FILE', 'ADMN'
  message_text STRING,
  payload_json JSON,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP
)
PARTITION BY DATE(created_at)
CLUSTER BY channel_url, user_id
OPTIONS (
  description = "Sendbird simulated chat messages partitioned by day and clustered by channel and user"
);

-- 2. Insert realistic sample data (10,000 chat messages across 100 channels)
INSERT INTO `@PROJECT_ID@.@SOURCE_DATASET@.chat_messages`
SELECT
  GENERATE_UUID() AS message_id,
  CONCAT('sendbird_group_channel_', CAST(MOD(ABS(FARM_FINGERPRINT(CAST(i AS STRING))), 100) AS STRING)) AS channel_url,
  CONCAT('user_', CAST(MOD(ABS(FARM_FINGERPRINT(CAST(i * 3 AS STRING))), 500) AS STRING)) AS user_id,
  CASE MOD(i, 10)
    WHEN 0 THEN 'FILE'
    WHEN 1 THEN 'ADMN'
    ELSE 'MESG'
  END AS message_type,
  CONCAT('Test chat message content for Sendbird scale benchmark #', CAST(i AS STRING)) AS message_text,
  PARSE_JSON(FORMAT('{"device": "%s", "client_version": "v4.1.2", "reactions_count": %d}', 
    CASE MOD(i, 3) WHEN 0 THEN 'iOS' WHEN 1 THEN 'Android' ELSE 'Web' END,
    MOD(i, 7)
  )) AS payload_json,
  TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL MOD(i, 7) DAY) AS created_at,
  CURRENT_TIMESTAMP() AS updated_at
FROM UNNEST(GENERATE_ARRAY(1, 10000)) AS i;

-- 3. Create Daily Aggregated Channel Summary Table (Ideal for Table Copy testing)
CREATE TABLE IF NOT EXISTS `@PROJECT_ID@.@SOURCE_DATASET@.daily_channel_summary` AS
SELECT
  DATE(created_at) AS event_date,
  channel_url,
  COUNT(1) AS total_messages,
  COUNT(DISTINCT user_id) AS active_users,
  COUNTIF(message_type = 'FILE') AS file_shares,
  CURRENT_TIMESTAMP() AS aggregation_calculated_at
FROM `@PROJECT_ID@.@SOURCE_DATASET@.chat_messages`
GROUP BY event_date, channel_url;

-- 4. Verify loaded sample records
SELECT 
  'chat_messages' AS table_name,
  COUNT(1) AS row_count,
  MIN(created_at) AS earliest_event,
  MAX(created_at) AS latest_event
FROM `@PROJECT_ID@.@SOURCE_DATASET@.chat_messages`
UNION ALL
SELECT 
  'daily_channel_summary' AS table_name,
  COUNT(1) AS row_count,
  TIMESTAMP(MIN(event_date)) AS earliest_event,
  TIMESTAMP(MAX(event_date)) AS latest_event
FROM `@PROJECT_ID@.@SOURCE_DATASET@.daily_channel_summary`;
