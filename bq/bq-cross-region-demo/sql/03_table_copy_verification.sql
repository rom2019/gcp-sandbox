-- =============================================================================
-- Sendbird Solution Comparison: Cross-Region Table Copy Verification
-- Verify BigQuery Copy Job completion, byte sizes, and checksum parity
-- =============================================================================

-- 1. Check recent COPY jobs across regions in INFORMATION_SCHEMA
SELECT
  job_id,
  project_id,
  job_type,
  state,
  start_time,
  end_time,
  TIMESTAMP_DIFF(end_time, start_time, SECOND) AS elapsed_seconds,
  error_result.message AS error_message
FROM `@PROJECT_ID@`.`region-@SOURCE_REGION@`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE job_type = 'COPY'
ORDER BY creation_time DESC
LIMIT 5;

-- 2. Validate Row Parity and Hash Checksum between Source and Copied Table
WITH source_summary AS (
  SELECT
    COUNT(1) AS row_count,
    SUM(FARM_FINGERPRINT(message_id)) AS checksum_hash,
    MIN(created_at) AS min_ts,
    MAX(created_at) AS max_ts
  FROM `@PROJECT_ID@.@SOURCE_DATASET@.chat_messages`
),
dest_summary AS (
  SELECT
    COUNT(1) AS row_count,
    SUM(FARM_FINGERPRINT(message_id)) AS checksum_hash,
    MIN(created_at) AS min_ts,
    MAX(created_at) AS max_ts
  FROM `@PROJECT_ID@.@DEST_DATASET@.chat_messages`
)
SELECT
  'SOURCE' AS location, s.* FROM source_summary s
UNION ALL
SELECT
  'DESTINATION' AS location, d.* FROM dest_summary d;

-- 3. Verify Table Copy for Daily Summary Table
SELECT
  'SOURCE_SUMMARY' AS dataset_location,
  COUNT(1) AS total_channels,
  SUM(total_messages) AS sum_messages
FROM `@PROJECT_ID@.@SOURCE_DATASET@.daily_channel_summary`
UNION ALL
SELECT
  'DEST_SUMMARY' AS dataset_location,
  COUNT(1) AS total_channels,
  SUM(total_messages) AS sum_messages
FROM `@PROJECT_ID@.@DEST_DATASET@.daily_channel_summary`;
