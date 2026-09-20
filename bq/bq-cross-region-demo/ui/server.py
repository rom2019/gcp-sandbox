#!/usr/bin/env python3
"""
Sendbird BigQuery Solution Comparison — Live GCP API & Hybrid Demo Web Server
Executes REAL BigQuery CLI / SQL / DTS commands against GCP project
`test-sendbird-cross-region-cp` with CLOUDSDK_CONTEXT_AWARE_USE_CLIENT_CERTIFICATE=false.
"""

import json
import os
import subprocess
import time
import urllib.parse
from http.server import HTTPServer, SimpleHTTPRequestHandler

UI_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPTS_DIR = os.path.abspath(os.path.join(UI_DIR, "..", "scripts"))


def run_bq_cmd(cmd_args, timeout=45):
    """Runs a command with CLOUDSDK_CONTEXT_AWARE_USE_CLIENT_CERTIFICATE=false."""
    env = os.environ.copy()
    env["CLOUDSDK_CONTEXT_AWARE_USE_CLIENT_CERTIFICATE"] = "false"
    env["PROJECT_ID"] = "test-sendbird-cross-region-cp"
    try:
        res = subprocess.run(
            cmd_args,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout
        )
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "Command timed out (running asynchronously in GCP)"
    except Exception as e:
        return 1, "", str(e)


class DemoRequestHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=UI_DIR, **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def _send_json(self, status_code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/health":
            self._send_json(200, {
                "status": "ok",
                "mode": "live_gcp",
                "default_project": "test-sendbird-cross-region-cp",
                "server": "romij.c.googlers.com"
            })
            return

        if parsed.path == "/api/live-status":
            qs = urllib.parse.parse_qs(parsed.query)
            project_id = qs.get("project_id", ["test-sendbird-cross-region-cp"])[0]
            src_region = qs.get("source_region", ["us-central1"])[0]
            dst_region = qs.get("dest_region", ["asia-northeast3"])[0]

            # 1. Query US Primary Source Row Count (us-central1) + 3 Dedicated Seoul Destinations (asia-northeast3)
            rc_us, out_us, _ = run_bq_cmd([
                "bq", "query", f"--project_id={project_id}", "--use_legacy_sql=false",
                "--format=json", f"--location={src_region}",
                f"SELECT COUNT(1) AS cnt FROM `{project_id}.sendbird_source_us.chat_messages`"
            ], timeout=15)
            src_rows = 0
            exists = False
            if rc_us == 0 and out_us:
                try:
                    src_rows = int(json.loads(out_us)[0]["cnt"])
                    exists = True
                except Exception:
                    pass

            dts_rows = 0
            copy_rows = 0
            crr_rows = 0
            if exists:
                rc1, out_counts, _ = run_bq_cmd([
                    "bq", "query", f"--project_id={project_id}", "--use_legacy_sql=false",
                    "--format=json", f"--location={dst_region}",
                    f"SELECT 'dts' AS ds, COUNT(1) AS cnt FROM `{project_id}.sendbird_dest_dts_kr.chat_messages` "
                    f"UNION ALL SELECT 'copy', COUNT(1) FROM `{project_id}.sendbird_dest_copy_kr.chat_messages` "
                    f"UNION ALL SELECT 'crr', COUNT(1) FROM `{project_id}.sendbird_source_us.chat_messages`"
                ], timeout=15)
                if rc1 == 0 and out_counts:
                    try:
                        for row in json.loads(out_counts):
                            if row["ds"] == "dts":
                                dts_rows = int(row["cnt"])
                            elif row["ds"] == "copy":
                                copy_rows = int(row["cnt"])
                            elif row["ds"] == "crr":
                                crr_rows = int(row["cnt"])
                    except Exception:
                        pass
                else:
                    # Query each individually if one of the 3 datasets/replicas is still being created
                    for key, tbl_path in [
                        ("dts", f"`{project_id}.sendbird_dest_dts_kr.chat_messages`"),
                        ("copy", f"`{project_id}.sendbird_dest_copy_kr.chat_messages`"),
                        ("crr", f"`{project_id}.sendbird_source_us.chat_messages`")
                    ]:
                        r_i, o_i, _ = run_bq_cmd([
                            "bq", "query", f"--project_id={project_id}", "--use_legacy_sql=false",
                            "--format=json", f"--location={dst_region}",
                            f"SELECT COUNT(1) AS cnt FROM {tbl_path}"
                        ], timeout=10)
                        if r_i == 0 and o_i:
                            try:
                                val = int(json.loads(o_i)[0]["cnt"])
                                if key == "dts": dts_rows = val
                                elif key == "copy": copy_rows = val
                                elif key == "crr": crr_rows = val
                            except Exception:
                                pass

            self._send_json(200, {
                "project_id": project_id,
                "exists": exists,
                "source_rows": src_rows,
                "dts_rows": dts_rows,
                "copy_rows": copy_rows,
                "crr_rows": crr_rows,
                "destinations": {
                    "dts": "sendbird_dest_dts_kr",
                    "copy": "sendbird_dest_copy_kr",
                    "crr": "sendbird_dest_crr_kr"
                }
            })
            return

        return super().do_GET()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw_body = self.rfile.read(length).decode("utf-8") if length > 0 else "{}"
        try:
            params = json.loads(raw_body)
        except Exception:
            params = {}

        project_id = params.get("project_id", "test-sendbird-cross-region-cp")
        src_region = params.get("source_region", "us-central1")
        dst_region = params.get("dest_region", "asia-northeast3")

        if self.path == "/api/initial-sync":
            # 0. Check if sendbird_source_us.chat_messages exists; if deleted by Cleanup, recreate source + 3 dest datasets!
            rc_chk, _, _ = run_bq_cmd([
                "bq", "show", f"{project_id}:sendbird_source_us.chat_messages"
            ], timeout=10)
            if rc_chk != 0:
                run_bq_cmd([f"{SCRIPTS_DIR}/setup_environment.sh"], timeout=90)

            # Ensure 3 dedicated Seoul destination datasets exist
            for ds_name in ["sendbird_dest_dts_kr", "sendbird_dest_copy_kr", "sendbird_dest_crr_kr"]:
                run_bq_cmd([
                    "bq", f"--location={dst_region}", "mk", "--dataset", f"{project_id}:{ds_name}"
                ], timeout=15)

            # 1. Ensure DTS Config exists for sendbird_dest_dts_kr or trigger manual run
            _, out_dts_cfg, _ = run_bq_cmd([
                "bq", "ls", "--transfer_config", f"--project_id={project_id}",
                f"--transfer_location={dst_region}", "--format=json"
            ], timeout=15)
            cfg_name = ""
            try:
                cfgs = json.loads(out_dts_cfg)
                for c in cfgs:
                    if c.get("destinationDatasetId") == "sendbird_dest_dts_kr":
                        cfg_name = c.get("name", "")
                        break
            except Exception:
                pass

            if not cfg_name:
                params_json = json.dumps({
                    "source_dataset_id": "sendbird_source_us",
                    "source_project_id": project_id,
                    "overwrite_destination_table": True
                })
                _, out_mk, err_mk = run_bq_cmd([
                    "bq", "mk", "--transfer_config",
                    f"--project_id={project_id}",
                    "--data_source=cross_region_copy",
                    "--display_name=Sendbird_Solution1_DTS_to_Seoul (sendbird_dest_dts_kr)",
                    "--target_dataset=sendbird_dest_dts_kr",
                    f"--location={dst_region}",
                    f"--params={params_json}"
                ], timeout=25)
                dts_log = f"[Real GCP DTS Created -> sendbird_dest_dts_kr]\n{out_mk or err_mk}"
            else:
                now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
                _, out_run, err_run = run_bq_cmd([
                    "bq", "mk", "--transfer_run",
                    f"--project_id={project_id}",
                    f"--run_time={now_iso}",
                    cfg_name
                ], timeout=20)
                dts_log = f"[Real GCP DTS Run Triggered -> sendbird_dest_dts_kr]\n{cfg_name}\n{out_run or err_run}"

            # Also copy initial baseline into sendbird_dest_dts_kr so table exists immediately while DTS run queues
            run_bq_cmd([
                "bq", "cp", "-f", f"--project_id={project_id}",
                f"{project_id}:sendbird_source_us.chat_messages",
                f"{project_id}:sendbird_dest_dts_kr.chat_messages"
            ], timeout=45)

            # 2. Trigger Real Cross-Region Table Copy into sendbird_dest_copy_kr
            _, out_tc1, err_tc1 = run_bq_cmd([
                "bq", "cp", "-f",
                f"--project_id={project_id}",
                f"{project_id}:sendbird_source_us.chat_messages",
                f"{project_id}:sendbird_dest_copy_kr.chat_messages"
            ], timeout=45)
            _, out_tc2, err_tc2 = run_bq_cmd([
                "bq", "cp", "-f",
                f"--project_id={project_id}",
                f"{project_id}:sendbird_source_us.daily_channel_summary",
                f"{project_id}:sendbird_dest_copy_kr.daily_channel_summary"
            ], timeout=45)
            tc_log = f"[Real GCP Copy Jobs Triggered -> sendbird_dest_copy_kr]\n{out_tc1 or err_tc1}\n{out_tc2 or err_tc2}"

            # 3. Ensure CRR Replica Exists + sendbird_dest_crr_kr views
            _, out_crr, err_crr = run_bq_cmd([
                "bq", "query", f"--project_id={project_id}", "--use_legacy_sql=false",
                f"--location={src_region}",
                f"ALTER SCHEMA `{project_id}.sendbird_source_us` ADD REPLICA IF NOT EXISTS `replica_kr` OPTIONS(location='{dst_region}');"
            ], timeout=25)
            run_bq_cmd([
                "bq", "query", f"--project_id={project_id}", "--use_legacy_sql=false",
                f"--location={dst_region}",
                f"CREATE OR REPLACE VIEW `{project_id}.sendbird_dest_crr_kr.chat_messages` AS SELECT * FROM `{project_id}.sendbird_source_us.chat_messages`; "
                f"CREATE OR REPLACE VIEW `{project_id}.sendbird_dest_crr_kr.daily_channel_summary` AS SELECT * FROM `{project_id}.sendbird_source_us.daily_channel_summary`;"
            ], timeout=20)
            crr_log = f"[Real GCP CRR Active -> sendbird_source_us@asia-northeast3 & sendbird_dest_crr_kr]\n{out_crr or err_crr}"

            self._send_json(200, {
                "status": "triggered",
                "logs": {
                    "dts": dts_log,
                    "tc": tc_log,
                    "crr": crr_log
                }
            })
            return

        if self.path == "/api/delta-inject":
            # Insert 500 real chat message rows into sendbird_source_us.chat_messages ONLY!
            # CRR (sendbird_dest_crr_kr) automatically reflects +500 rows, while DTS (sendbird_dest_dts_kr)
            # and Table Copy (sendbird_dest_copy_kr) stay at previous row count until re-triggered!
            insert_sql = (
                f"INSERT INTO `{project_id}.sendbird_source_us.chat_messages` "
                f"SELECT GENERATE_UUID(), CONCAT('sendbird_live_delta_', CAST(MOD(i, 20) AS STRING)), "
                f"CONCAT('user_delta_', CAST(i AS STRING)), 'MESG', "
                f"CONCAT('Live delta message injected from Demo UI #', CAST(i AS STRING)), "
                f"PARSE_JSON('{{\"live_delta\": true}}'), CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP() "
                f"FROM UNNEST(GENERATE_ARRAY(1, 500)) AS i;"
            )
            rc, out_ins, err_ins = run_bq_cmd([
                "bq", "query", f"--project_id={project_id}", "--use_legacy_sql=false",
                f"--location={src_region}", insert_sql
            ], timeout=30)

            self._send_json(200, {
                "status": "delta_inserted",
                "inserted_rows": 500,
                "bq_output": out_ins or err_ins
            })
            return

        if self.path == "/api/reset":
            # Reset US source and Seoul destinations back to clean 10,000 rows baseline (delete live_delta rows)
            run_bq_cmd([
                "bq", "query", f"--project_id={project_id}", "--use_legacy_sql=false",
                f"--location={src_region}",
                f"DELETE FROM `{project_id}.sendbird_source_us.chat_messages` WHERE channel_url LIKE 'sendbird_live_delta_%';"
            ], timeout=30)
            run_bq_cmd([
                "bq", "query", f"--project_id={project_id}", "--use_legacy_sql=false",
                f"--location={dst_region}",
                f"DELETE FROM `{project_id}.sendbird_dest_dts_kr.chat_messages` WHERE channel_url LIKE 'sendbird_live_delta_%'; "
                f"DELETE FROM `{project_id}.sendbird_dest_copy_kr.chat_messages` WHERE channel_url LIKE 'sendbird_live_delta_%';"
            ], timeout=30)
            self._send_json(200, {"status": "reset_to_baseline", "rows": 10000})
            return

        if self.path == "/api/cleanup":
            run_bq_cmd([
                f"{SCRIPTS_DIR}/cleanup.sh"
            ], timeout=60)
            self._send_json(200, {"status": "cleaned", "project_id": project_id})
            return

        self._send_json(404, {"error": "Unknown API endpoint"})


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    server = HTTPServer(("0.0.0.0", port), DemoRequestHandler)
    print(f"Sendbird BigQuery Live GCP Demo UI Server running at http://romij.c.googlers.com:{port}")
    server.serve_forever()
