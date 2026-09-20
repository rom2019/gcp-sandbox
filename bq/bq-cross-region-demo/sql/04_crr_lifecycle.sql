-- =============================================================================
-- Sendbird Solution Comparison: BigQuery CRR (Cross-Region Dataset Replication) Lifecycle
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
  replica_type,      -- 'PRIMARY' or 'SECONDARY'
  sync_status,       -- 'SYNCED', 'SYNCING', 'NOT_SYNCED'
  replication_time,  -- Latest timestamp up to which data is replicated
  creation_time
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
  'sendbird_group_channel_live_test',
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
  COUNTIF(channel_url = 'sendbird_group_channel_live_test') AS live_probe_count
FROM `@PROJECT_ID@.@SOURCE_DATASET@.chat_messages`;

-- -----------------------------------------------------------------------------
-- STEP 5: Disaster Recovery Simulation: Promote Secondary Replica to Primary
-- Switches primary role to the replica region (e.g. asia-northeast3)
-- -----------------------------------------------------------------------------
ALTER SCHEMA `@PROJECT_ID@.@SOURCE_DATASET@`
SET OPTIONS (
  primary_replica = '@DEST_REGION@'
);

-- Verify that the replica in @DEST_REGION@ is now PRIMARY:
SELECT
  schema_name,
  replica_name,
  location,
  replica_type
FROM `@PROJECT_ID@`.`region-@DEST_REGION@`.INFORMATION_SCHEMA.SCHEMATA_REPLICAS
WHERE schema_name = '@SOURCE_DATASET@';

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
