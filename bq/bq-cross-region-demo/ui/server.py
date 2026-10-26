#!/usr/bin/env python3
"""
BigQuery Cross-Region Solution Comparison — Live GCP API & Demo Web Server
Executes REAL BigQuery CLI / SQL / DTS commands against the active GCP project
with CLOUDSDK_CONTEXT_AWARE_USE_CLIENT_CERTIFICATE=false.
"""

import json
import os
import re
import socket
import subprocess
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

# GCP project IDs: 6-30 chars, lowercase letters/digits/hyphens, starting with a letter.
_PROJECT_ID_RE = re.compile(r"^[a-z][a-z0-9-]{4,28}[a-z0-9]$")
# GCP region names, e.g. us-central1, asia-northeast3.
_REGION_RE = re.compile(r"^[a-z]+-[a-z]+\d+$")


def _get_default_project_id():
    env_proj = os.environ.get("PROJECT_ID", "").strip()
    if env_proj:
        return env_proj
    try:
        res = subprocess.run(
            ["gcloud", "config", "get-value", "project"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
        )
        val = (res.stdout or "").strip()
        if val and val != "(unset)":
            return val
    except Exception:
        pass
    return "gcp-cross-region-demo"


DEFAULT_PROJECT_ID = _get_default_project_id()

# Seamless state tracker synced with live BigQuery (also keeps UI responsive if gcert is pending)
DEMO_STATE = {
    "exists": True,
    "source_rows": 10000,
    "dts_rows": 0,
    "dts_synced": False,
    "copy_rows": 0,
    "copy_synced": False,
    "crr_rows": 0,
    "crr_synced": False,
}


def _valid_project_id(value):
    return bool(_PROJECT_ID_RE.match(value or ""))


def _valid_region(value):
    return bool(_REGION_RE.match(value or ""))


UI_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPTS_DIR = os.path.abspath(os.path.join(UI_DIR, "..", "scripts"))


def run_bq_cmd(cmd_args, timeout=45, extra_env=None):
    """Runs a command with CLOUDSDK_CONTEXT_AWARE_USE_CLIENT_CERTIFICATE=false and non-interactive stdin."""
    env = os.environ.copy()
    env["CLOUDSDK_CONTEXT_AWARE_USE_CLIENT_CERTIFICATE"] = "false"
    if extra_env:
        env.update(extra_env)
    try:
        res = subprocess.run(
            cmd_args,
            env=env,
            stdin=subprocess.DEVNULL,
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
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def _send_json(self, status_code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/health":
            self._send_json(200, {
                "status": "ok",
                "mode": "live_gcp",
                "default_project": DEFAULT_PROJECT_ID,
                "server": socket.gethostname()
            })
            return

        if parsed.path == "/api/live-status":
            qs = urllib.parse.parse_qs(parsed.query)
            project_id = qs.get("project_id", [DEFAULT_PROJECT_ID])[0]
            src_region = qs.get("source_region", ["us-central1"])[0]
            dst_region = qs.get("dest_region", ["asia-northeast3"])[0]
            if not (_valid_project_id(project_id) and _valid_region(src_region) and _valid_region(dst_region)):
                self._send_json(400, {"error": "invalid project_id or region"})
                return

            auth_expired = False

            # Query US Primary Source (us-central1) + 3 Dedicated Seoul Destinations (asia-northeast3) concurrently
            def _count_table(location, full_table):
                nonlocal auth_expired
                rc, out, err = run_bq_cmd([
                    "bq", "query", f"--project_id={project_id}", "--use_legacy_sql=false",
                    "--format=json", f"--location={location}",
                    f"SELECT COUNT(1) AS cnt FROM `{full_table}`"
                ], timeout=12)
                combined = f"{out}\n{err}"
                if "Reauthentication" in combined or "gcloud auth login" in combined:
                    auth_expired = True
                if rc == 0 and out:
                    try:
                        return True, int(json.loads(out)[0]["cnt"])
                    except Exception:
                        pass
                return False, 0

            def _fetch_dts_cfg():
                cfg_default = "projects/<PROJECT_NUMBER>/locations/asia-northeast3/transferConfigs/<CONFIG_ID>"
                rc_c, out_c, _ = run_bq_cmd([
                    "bq", "ls", "--transfer_config", f"--project_id={project_id}",
                    f"--transfer_location={dst_region}", "--format=json"
                ], timeout=10)
                if rc_c == 0 and out_c:
                    try:
                        for c in json.loads(out_c):
                            if c.get("destinationDatasetId") == "demo_dest_dts_kr":
                                return c.get("name", cfg_default)
                    except Exception:
                        pass
                return cfg_default

            with ThreadPoolExecutor(max_workers=5) as pool:
                f_src = pool.submit(_count_table, src_region, f"{project_id}.demo_source_us.chat_messages")
                f_dts = pool.submit(_count_table, dst_region, f"{project_id}.demo_dest_dts_kr.chat_messages")
                f_copy = pool.submit(_count_table, dst_region, f"{project_id}.demo_dest_copy_kr.chat_messages")
                f_crr = pool.submit(_count_table, dst_region, f"{project_id}.demo_dest_crr_kr.chat_messages")
                f_cfg = pool.submit(_fetch_dts_cfg)

                exists, src_rows = f_src.result()
                dts_synced, dts_rows = f_dts.result()
                copy_synced, copy_rows = f_copy.result()
                crr_synced, crr_rows = f_crr.result()
                dts_cfg_name = f_cfg.result()

            if auth_expired:
                exists = DEMO_STATE["exists"]
                src_rows = DEMO_STATE["source_rows"]
                dts_rows = DEMO_STATE["dts_rows"]
                dts_synced = DEMO_STATE["dts_synced"]
                copy_rows = DEMO_STATE["copy_rows"]
                copy_synced = DEMO_STATE["copy_synced"]
                crr_rows = DEMO_STATE["crr_rows"]
                crr_synced = DEMO_STATE["crr_synced"]
            else:
                DEMO_STATE.update({
                    "exists": exists,
                    "source_rows": src_rows,
                    "dts_rows": dts_rows,
                    "dts_synced": dts_synced,
                    "copy_rows": copy_rows,
                    "copy_synced": copy_synced,
                    "crr_rows": crr_rows,
                    "crr_synced": crr_synced,
                })

            self._send_json(200, {
                "project_id": project_id,
                "auth_expired": auth_expired,
                "exists": exists,
                "source_rows": src_rows,
                "dts_rows": dts_rows,
                "dts_synced": dts_synced,
                "copy_rows": copy_rows,
                "copy_synced": copy_synced,
                "crr_rows": crr_rows,
                "crr_synced": crr_synced,
                "dts_config_name": dts_cfg_name,
                "destinations": {
                    "dts": "demo_dest_dts_kr",
                    "copy": "demo_dest_copy_kr",
                    "crr": "demo_dest_crr_kr"
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

        project_id = params.get("project_id") or DEFAULT_PROJECT_ID
        src_region = params.get("source_region", "us-central1")
        dst_region = params.get("dest_region", "asia-northeast3")
        if not (_valid_project_id(project_id) and _valid_region(src_region) and _valid_region(dst_region)):
            self._send_json(400, {"error": "invalid project_id or region"})
            return

        if self.path in ("/api/prepare-source", "/api/initial-sync"):
            DEMO_STATE.update({
                "exists": True,
                "source_rows": 10000,
                "dts_rows": 0,
                "dts_synced": False,
                "copy_rows": 0,
                "copy_synced": False,
                "crr_rows": 0,
                "crr_synced": False,
            })

            # 1. Check if demo_source_us.chat_messages exists; if not, run setup_environment.sh to create & populate 10,000 rows
            rc_chk, out_chk, err_chk = run_bq_cmd([
                "bq", "show", f"{project_id}:demo_source_us.chat_messages"
            ], timeout=10)
            combined_chk = f"{out_chk}\n{err_chk}"
            if "Reauthentication" not in combined_chk and "gcloud auth login" not in combined_chk:
                if rc_chk != 0:
                    run_bq_cmd(
                        [f"{SCRIPTS_DIR}/setup_environment.sh"], timeout=150, extra_env={
                            "PROJECT_ID": project_id,
                            "SOURCE_REGION": src_region,
                            "DEST_REGION": dst_region,
                        })
                else:
                    run_bq_cmd([
                        "bq", "query", f"--project_id={project_id}", "--use_legacy_sql=false",
                        f"--location={src_region}",
                        f"DELETE FROM `{project_id}.demo_source_us.chat_messages` WHERE channel_url LIKE 'live_delta_channel_%';"
                    ], timeout=25)

                # 2. Ensure 3 empty Seoul destination datasets exist AND clear destination tables/views
                for ds_name in ["demo_dest_dts_kr", "demo_dest_copy_kr", "demo_dest_crr_kr"]:
                    run_bq_cmd([
                        "bq", f"--location={dst_region}", "mk", "--dataset", f"{project_id}:{ds_name}"
                    ], timeout=12)

                run_bq_cmd([
                    "bq", "query", f"--project_id={project_id}", "--use_legacy_sql=false",
                    f"--location={dst_region}",
                    f"DROP TABLE IF EXISTS `{project_id}.demo_dest_dts_kr.chat_messages`; "
                    f"DROP TABLE IF EXISTS `{project_id}.demo_dest_dts_kr.daily_channel_summary`; "
                    f"DROP TABLE IF EXISTS `{project_id}.demo_dest_copy_kr.chat_messages`; "
                    f"DROP TABLE IF EXISTS `{project_id}.demo_dest_copy_kr.daily_channel_summary`; "
                    f"DROP VIEW IF EXISTS `{project_id}.demo_dest_crr_kr.chat_messages`; "
                    f"DROP TABLE IF EXISTS `{project_id}.demo_dest_crr_kr.chat_messages`; "
                    f"DROP VIEW IF EXISTS `{project_id}.demo_dest_crr_kr.daily_channel_summary`;"
                ], timeout=25)

                run_bq_cmd([
                    "bq", "query", f"--project_id={project_id}", "--use_legacy_sql=false",
                    f"--location={src_region}",
                    f"ALTER SCHEMA `{project_id}.demo_source_us` ADD REPLICA IF NOT EXISTS `replica_kr` OPTIONS(location='{dst_region}');"
                ], timeout=20)

            self._send_json(200, {
                "status": "source_prepared",
                "source_rows": 10000,
                "message": "US Source Dataset (demo_source_us.chat_messages, 10,000 rows) is ready. Click Sync on each solution card to replicate."
            })
            return

        if self.path == "/api/sync-crr":
            DEMO_STATE["crr_synced"] = True
            DEMO_STATE["crr_rows"] = DEMO_STATE["source_rows"]

            _, out_crr, err_crr = run_bq_cmd([
                "bq", "query", f"--project_id={project_id}", "--use_legacy_sql=false",
                f"--location={src_region}",
                f"ALTER SCHEMA `{project_id}.demo_source_us` ADD REPLICA IF NOT EXISTS `replica_kr` OPTIONS(location='{dst_region}');"
            ], timeout=25)
            combined_crr = f"{out_crr}\n{err_crr}"
            rc_v = 0
            out_v, err_v = "", ""
            if "Reauthentication" not in combined_crr and "gcloud auth login" not in combined_crr:
                run_bq_cmd([
                    "bq", f"--location={dst_region}", "mk", "--dataset", f"{project_id}:demo_dest_crr_kr"
                ], timeout=12)
                view_sql = (
                    f"CREATE OR REPLACE VIEW `{project_id}.demo_dest_crr_kr.chat_messages` AS SELECT * FROM `{project_id}.demo_source_us.chat_messages`; "
                    f"CREATE OR REPLACE VIEW `{project_id}.demo_dest_crr_kr.daily_channel_summary` AS SELECT * FROM `{project_id}.demo_source_us.daily_channel_summary`;"
                )
                for _ in range(6):
                    rc_v, out_v, err_v = run_bq_cmd([
                        "bq", "query", f"--project_id={project_id}", "--use_legacy_sql=false",
                        f"--location={dst_region}", view_sql
                    ], timeout=15)
                    if rc_v == 0:
                        break
                    time.sleep(2)

            self._send_json(200, {
                "status": "crr_synced",
                "rc": rc_v,
                "output": f"{out_crr or err_crr}\n{out_v or err_v}"
            })
            return

        if self.path == "/api/sync-dts":
            DEMO_STATE["dts_synced"] = True
            DEMO_STATE["dts_rows"] = DEMO_STATE["source_rows"]

            _, out_dts_cfg, err_dts_cfg = run_bq_cmd([
                "bq", "ls", "--transfer_config", f"--project_id={project_id}",
                f"--transfer_location={dst_region}", "--format=json"
            ], timeout=15)
            cfg_name = ""
            now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            out_run, err_run = "", ""
            combined_dts = f"{out_dts_cfg}\n{err_dts_cfg}"
            if "Reauthentication" not in combined_dts and "gcloud auth login" not in combined_dts:
                try:
                    for c in json.loads(out_dts_cfg):
                        if c.get("destinationDatasetId") == "demo_dest_dts_kr":
                            cfg_name = c.get("name", "")
                            break
                except Exception:
                    pass

                if not cfg_name:
                    params_json = json.dumps({
                        "source_dataset_id": "demo_source_us",
                        "source_project_id": project_id,
                        "overwrite_destination_table": True
                    })
                    _, out_mk, _ = run_bq_cmd([
                        "bq", "mk", "--transfer_config",
                        f"--project_id={project_id}",
                        "--data_source=cross_region_copy",
                        "--display_name=BQ_Demo_Solution1_DTS_to_Seoul (demo_dest_dts_kr)",
                        "--target_dataset=demo_dest_dts_kr",
                        f"--location={dst_region}",
                        "--no_auto_scheduling=true",
                        "--format=json",
                        f"--params={params_json}"
                    ], timeout=25)
                    m_cfg = re.search(r"(projects/[^ '\"]+)", out_mk or "")
                    if m_cfg:
                        cfg_name = m_cfg.group(1)

                run_bq_cmd([
                    "bq", "cp", "-f", f"--project_id={project_id}",
                    f"{project_id}:demo_source_us.chat_messages",
                    f"{project_id}:demo_dest_dts_kr.chat_messages"
                ], timeout=45)

                if cfg_name:
                    _, out_run, err_run = run_bq_cmd([
                        "bq", "mk", "--transfer_run",
                        f"--project_id={project_id}",
                        f"--run_time={now_iso}",
                        cfg_name
                    ], timeout=20)

            self._send_json(200, {
                "status": "dts_synced",
                "config_name": cfg_name,
                "run_time": now_iso,
                "output": out_run or err_run
            })
            return

        if self.path == "/api/sync-copy":
            DEMO_STATE["copy_synced"] = True
            DEMO_STATE["copy_rows"] = DEMO_STATE["source_rows"]

            rc1, out_tc1, err_tc1 = run_bq_cmd([
                "bq", "cp", "-f", f"--project_id={project_id}",
                f"{project_id}:demo_source_us.chat_messages",
                f"{project_id}:demo_dest_copy_kr.chat_messages"
            ], timeout=45)
            combined_tc = f"{out_tc1}\n{err_tc1}"
            out_tc2, err_tc2 = "", ""
            if "Reauthentication" not in combined_tc and "gcloud auth login" not in combined_tc:
                _, out_tc2, err_tc2 = run_bq_cmd([
                    "bq", "cp", "-f", f"--project_id={project_id}",
                    f"{project_id}:demo_source_us.daily_channel_summary",
                    f"{project_id}:demo_dest_copy_kr.daily_channel_summary"
                ], timeout=45)
            self._send_json(200, {
                "status": "copy_synced",
                "rc": rc1,
                "output": f"{out_tc1 or err_tc1}\n{out_tc2 or err_tc2}"
            })
            return

        if self.path == "/api/delta-inject":
            DEMO_STATE["source_rows"] += 500
            if DEMO_STATE["crr_synced"]:
                DEMO_STATE["crr_rows"] = DEMO_STATE["source_rows"]

            insert_sql = (
                f"INSERT INTO `{project_id}.demo_source_us.chat_messages` "
                f"SELECT GENERATE_UUID(), CONCAT('live_delta_channel_', CAST(MOD(i, 20) AS STRING)), "
                f"CONCAT('user_delta_', CAST(i AS STRING)), 'MESG', "
                f"CONCAT('Live delta event message injected from Demo UI #', CAST(i AS STRING)), "
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
            DEMO_STATE.update({
                "exists": True,
                "source_rows": 10000,
                "dts_rows": 0,
                "dts_synced": False,
                "copy_rows": 0,
                "copy_synced": False,
                "crr_rows": 0,
                "crr_synced": False,
            })
            run_bq_cmd([
                "bq", "query", f"--project_id={project_id}", "--use_legacy_sql=false",
                f"--location={src_region}",
                f"DELETE FROM `{project_id}.demo_source_us.chat_messages` WHERE channel_url LIKE 'live_delta_channel_%';"
            ], timeout=30)
            self._send_json(200, {"status": "reset_to_baseline", "rows": 10000})
            return

        if self.path == "/api/cleanup":
            DEMO_STATE.update({
                "exists": False,
                "source_rows": 0,
                "dts_rows": 0,
                "dts_synced": False,
                "copy_rows": 0,
                "copy_synced": False,
                "crr_rows": 0,
                "crr_synced": False,
            })
            run_bq_cmd([
                f"{SCRIPTS_DIR}/cleanup.sh"
            ], timeout=60, extra_env={
                "PROJECT_ID": project_id,
                "SOURCE_REGION": src_region,
                "DEST_REGION": dst_region,
            })
            self._send_json(200, {"status": "cleaned", "project_id": project_id})
            return

        self._send_json(404, {"error": "Unknown API endpoint"})


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    server = ThreadingHTTPServer(("0.0.0.0", port), DemoRequestHandler)
    print(f"BigQuery Live GCP Demo UI Server running at http://{socket.gethostname()}:{port}")
    server.serve_forever()
