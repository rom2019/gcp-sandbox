-- =============================================================================
-- Sendbird Solution Comparison: DTS Dataset Copy Verification
-- Inspect transfer execution history, verify row parity, and check table schemas
-- =============================================================================

-- 1. Check Data Transfer Service execution history and status
SELECT
  transfer_config_id,
  run_time,
  state, -- 'SUCCEEDED', 'FAILED', 'RUNNING'
  error_status.message AS error_message
FROM `@PROJECT_ID@`.`region-@DEST_REGION@`.INFORMATION_SCHEMA.DATA_TRANSFER_RUNS
ORDER BY run_time DESC
LIMIT 10;

-- 2. Compare Source and Destination Table Row Counts
SELECT
  'SOURCE' AS location,
  COUNT(1) AS total_rows,
  COUNT(DISTINCT channel_url) AS unique_channels,
  COUNT(DISTINCT user_id) AS unique_users
FROM `@PROJECT_ID@.@SOURCE_DATASET@.chat_messages`
UNION ALL
SELECT
  'DESTINATION' AS location,
  COUNT(1) AS total_rows,
  COUNT(DISTINCT channel_url) AS unique_channels,
  COUNT(DISTINCT user_id) AS unique_users
FROM `@PROJECT_ID@.@DEST_DATASET@.chat_messages`;

-- 3. Verify Table Partitioning & Clustering in Destination Dataset
SELECT
  table_name,
  is_partitioning_column,
  clustering_ordinal_position
FROM `@PROJECT_ID@.@DEST_DATASET@.INFORMATION_SCHEMA.COLUMNS
WHERE table_name = 'chat_messages'
  AND (is_partitioning_column = 'YES' OR clustering_ordinal_position IS NOT NULL)
ORDER BY clustering_ordinal_position;
