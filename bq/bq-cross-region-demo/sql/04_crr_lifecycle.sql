-- =============================================================================
-- BigQuery Solution Comparison: BigQuery CRR (Cross-Region Dataset Replication) Lifecycle
-- Demonstrates Replica Creation, Sync Monitoring, Read-only Querying, Failover, & Teardown
-- =============================================================================

-- -----------------------------------------------------------------------------
-- STEP 1: Enable Cross-Region Replication on the Dataset
-- Adds a secondary replica in the destination region (e.g. asia-northeast3)
-- -----------------------------------------------------------------------------
ALTER SCHEMA `@PROJECT_ID@.@SOURCE_DATASET@`
ADD REPLICA `@REPLICA_NAME@`
OPTIONS (
  location = '@DEST_REGION@'
);

-- -----------------------------------------------------------------------------
-- STEP 2: Monitor Replication Progress & Sync Status
-- Check replica state, sync status, and latest replicated timestamp
-- -----------------------------------------------------------------------------
SELECT
  catalog_name AS project_id,
  schema_name AS dataset_id,
  replica_name,
  location AS replica_region,
  creation_time,
  creation_complete,
  TO_JSON_STRING(sync_status) AS sync_status_json
FROM `@PROJECT_ID@`.`region-@DEST_REGION@`.INFORMATION_SCHEMA.SCHEMATA_REPLICAS
WHERE schema_name = '@SOURCE_DATASET@';

-- -----------------------------------------------------------------------------
-- STEP 3: Execute Read-Only Analytical Query Against the Secondary Replica
-- Run this query specifying the job location as the secondary region (@DEST_REGION@)
-- -----------------------------------------------------------------------------
SELECT
  channel_url,
  COUNT(1) AS message_count,
  COUNT(DISTINCT user_id) AS active_users,
  MAX(created_at) AS latest_message_time
FROM `@PROJECT_ID@.@SOURCE_DATASET@.chat_messages`
WHERE created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY channel_url
ORDER BY message_count DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- STEP 4: Insert New Records in Primary Region to Test Continuous Replication Lag
-- -----------------------------------------------------------------------------
INSERT INTO `@PROJECT_ID@.@SOURCE_DATASET@.chat_messages` (
  message_id, channel_url, user_id, message_type, message_text, payload_json, created_at, updated_at
)
VALUES (
  GENERATE_UUID(),
  'app_group_channel_live_test',
  'user_vip_999',
  'MESG',
  'Real-time replication probe message to verify CRR replication lag',
  PARSE_JSON('{"probe_event": true, "environment": "solution_comparison_poc"}'),
  CURRENT_TIMESTAMP(),
  CURRENT_TIMESTAMP()
);

-- Check row count in replica after short delay:
SELECT
  COUNT(1) AS replica_row_count,
  COUNTIF(channel_url = 'app_group_channel_live_test') AS live_probe_count
FROM `@PROJECT_ID@.@SOURCE_DATASET@.chat_messages`;

-- -----------------------------------------------------------------------------
-- STEP 5: Disaster Recovery Simulation: Promote Secondary Replica to Primary
-- Switches primary role to the replica region (e.g. asia-northeast3)
-- -----------------------------------------------------------------------------
ALTER SCHEMA `@PROJECT_ID@.@SOURCE_DATASET@`
SET OPTIONS (
  primary_replica = '@DEST_REGION@'
);

-- Verify the promotion: only the current primary is writable.
INSERT INTO `@PROJECT_ID@.@SOURCE_DATASET@.chat_messages` (
  message_id, channel_url, user_id, message_type, message_text, payload_json, created_at, updated_at
)
VALUES (
  GENERATE_UUID(), 'promotion_write_test', 'system_check', 'ADMN',
  'Write-access probe to confirm which replica is currently primary',
  PARSE_JSON('{"probe": "primary_check"}'), CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()
);

-- -----------------------------------------------------------------------------
-- STEP 6: Revert Promotion (Optional: Switch back to original Primary)
-- -----------------------------------------------------------------------------
ALTER SCHEMA `@PROJECT_ID@.@SOURCE_DATASET@`
SET OPTIONS (
  primary_replica = '@SOURCE_REGION@'
);

-- -----------------------------------------------------------------------------
-- STEP 7: Teardown / Drop Replica
-- Removes the secondary replica to stop ongoing replication charges
-- -----------------------------------------------------------------------------
ALTER SCHEMA `@PROJECT_ID@.@SOURCE_DATASET@`
DROP REPLICA IF EXISTS `@REPLICA_NAME@`;
