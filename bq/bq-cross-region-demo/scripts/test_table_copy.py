#!/usr/bin/env python3
"""
Sendbird BigQuery Solution Comparison: Cross-Region Table Copy Test Runner
Measures performance, elapsed time, and validates row parity across regions.
"""

import argparse
import sys
import time
from google.cloud import bigquery

def parse_args():
    parser = argparse.ArgumentParser(description="Test BigQuery Cross-Region Table Copy")
    parser.add_argument("--project_id", required=True, help="Google Cloud Project ID")
    parser.add_argument("--source_dataset", default="sendbird_source_us", help="Source dataset name")
    parser.add_argument("--source_table", default="chat_messages", help="Source table name")
    parser.add_argument("--dest_dataset", default="sendbird_dest_copy_kr", help="Destination dataset name")
    parser.add_argument("--dest_table", default="chat_messages_copied", help="Destination table name")
    parser.add_argument("--source_region", default="us-central1", help="Source region (e.g. us-central1)")
    parser.add_argument("--dest_region", default="asia-northeast3", help="Destination region (e.g. asia-northeast3)")
    return parser.parse_args()

def main():
    args = parse_args()
    print("=" * 70)
    print(" BigQuery Cross-Region Table Copy Performance Test")
    print(f" Project:      {args.project_id}")
    print(f" Source:       {args.source_dataset}.{args.source_table} ({args.source_region})")
    print(f" Destination:  {args.dest_dataset}.{args.dest_table} ({args.dest_region})")
    print(" Launch Stage: PREVIEW")
    print("=" * 70)

    # Initialize client with location set to source region
    client = bigquery.Client(project=args.project_id, location=args.source_region)

    source_table_ref = f"{args.project_id}.{args.source_dataset}.{args.source_table}"
    dest_table_ref = f"{args.project_id}.{args.dest_dataset}.{args.dest_table}"

    # 1. Fetch Source Table Metadata
    print("\n[Step 1] Fetching source table metadata...")
    source_table = client.get_table(source_table_ref)
    source_num_rows = source_table.num_rows
    source_num_bytes = source_table.num_bytes
    print(f"  - Source Rows:  {source_num_rows:,}")
    print(f"  - Source Bytes: {source_num_bytes / (1024 * 1024):.2f} MB ({source_num_bytes:,} bytes)")

    # 2. Configure Copy Job
    job_config = bigquery.CopyJobConfiguration()
    job_config.write_disposition = bigquery.WriteDisposition.WRITE_TRUNCATE

    print(f"\n[Step 2] Initiating Cross-Region Table Copy Job ({args.source_region} -> {args.dest_region})...")
    start_time = time.time()

    copy_job = client.copy_table(
        source_table_ref,
        dest_table_ref,
        job_config=job_config,
        location=args.source_region
    )
    print(f"  - Job ID: {copy_job.job_id}")
    print("  - Waiting for copy job completion...")

    # 3. Wait for Job Completion
    copy_job.result()  # Blocks until job completes
    end_time = time.time()
    elapsed_seconds = max(0.001, end_time - start_time)

    print("\n[Step 3] Copy Job Finished Successfully!")
    print(f"  - Elapsed Time: {elapsed_seconds:.2f} seconds")
    mb_transferred = source_num_bytes / (1024 * 1024)
    throughput_mb_s = mb_transferred / elapsed_seconds
    print(f"  - Effective Throughput: {throughput_mb_s:.2f} MB/s")

    # 4. Verify Destination Table
    print("\n[Step 4] Verifying destination table...")
    dest_client = bigquery.Client(project=args.project_id, location=args.dest_region)
    dest_table = dest_client.get_table(dest_table_ref)
    dest_num_rows = dest_table.num_rows
    dest_num_bytes = dest_table.num_bytes

    print(f"  - Dest Rows:  {dest_num_rows:,}")
    print(f"  - Dest Bytes: {dest_num_bytes / (1024 * 1024):.2f} MB")

    if source_num_rows == dest_num_rows:
        print("\n[RESULT: PASS] Row count matches perfectly between Source and Destination!")
    else:
        print(f"\n[RESULT: FAIL] Row count mismatch! Source: {source_num_rows}, Dest: {dest_num_rows}", file=sys.stderr)
        sys.exit(1)

    print("=" * 70)

if __name__ == "__main__":
    main()
