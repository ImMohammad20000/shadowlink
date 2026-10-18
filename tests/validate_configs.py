#!/usr/bin/env python3
"""Smoke-test Shadowlink configs against the release binaries."""

import argparse
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import tarfile
import tempfile
import uuid
import zipfile


ROOT = Path(__file__).resolve().parents[1]


def run(*args, cwd=None, env=None):
    return subprocess.run(args, cwd=cwd, env=env, check=True, text=True,
                          capture_output=True).stdout


def check_config(xray, source, replacements, cwd, output):
    config = source.read_text()
    for old, new in replacements.items():
        config = config.replace(old, new)
    json.loads(config)
    output.write_text(config)
    run(str(xray), "run", "-test", "-config", str(output), cwd=cwd)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--panel-archive", type=Path, required=True)
    parser.add_argument("--xray-zip", type=Path, required=True)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as temp:
        work = Path(temp)
        with tarfile.open(args.panel_archive) as archive:
            archive.extractall(work / "panel", filter="data")
        with zipfile.ZipFile(args.xray_zip) as archive:
            archive.extractall(work / "core")

        panel = work / "panel/x-ui"
        panel_xray = panel / "bin/xray-linux-amd64"
        core_xray = work / "core/xray"
        core_xray.chmod(0o755)
        version = run(str(panel / "x-ui"), "-v").strip()
        if not re.match(r"^(?:[3-9]|[1-9]\d+)\.", version):
            raise RuntimeError(f"3x-ui v3 or newer is required: {version}")

        db_dir = work / "db"
        env = {**os.environ, "XUI_DB_FOLDER": str(db_dir)}
        run(str(panel / "x-ui"), "setting", "-username", "shadowlink",
            "-password", "test-password-123456", "-port", "7092",
            "-webBasePath", "/shadowlink/", env=env)
        with sqlite3.connect(db_dir / "x-ui.db") as db:
            settings = dict(db.execute("SELECT key, value FROM settings"))
            assert settings["webPort"] == "7092"
            assert settings["webBasePath"] == "/shadowlink/"
            user, password = db.execute("SELECT username, password FROM users").fetchone()
            assert user == "shadowlink" and password != "test-password-123456"
            # Fresh v3 databases can defer creation of this setting until use.
            db.execute("INSERT INTO settings (key, value) VALUES (?, ?)",
                       ("xrayTemplateConfig",
                        (ROOT / "server/assets/3x-ui.json.sample").read_text()))
            assert db.execute("SELECT value FROM settings WHERE key = ?",
                              ("xrayTemplateConfig",)).fetchone()[0]

        keys = run(str(core_xray), "vlessenc")
        x25519 = keys.split("Authentication: X25519, not Post-Quantum\n", 1)[1]
        decryption = json.loads("{" + x25519.splitlines()[0] + "}")["decryption"]
        encryption = json.loads("{" + x25519.splitlines()[1] + "}")["encryption"]
        tunnel_uuid = str(uuid.uuid4())

        panel_config = ROOT / "server/assets/3x-ui.json.sample"
        server_config = ROOT / "server/assets/tunnel_server.json.sample"
        client_config = ROOT / "client/sample_config.json"
        panel_data = json.loads(panel_config.read_text())
        server_data = json.loads(server_config.read_text())
        assert panel_data["outbounds"][0]["settings"]["vnext"][0]["port"] == 7094
        assert server_data["inbounds"][1]["port"] == 7094
        assert server_data["inbounds"][1]["listen"] == "127.0.0.1"

        check_config(panel_xray, panel_config,
                     {"reverse_tunnel_uuid": tunnel_uuid}, panel / "bin",
                     work / "panel.json")
        check_config(core_xray, server_config,
                     {"reverse_tunnel_uuid": tunnel_uuid,
                      "reverse_tunnel_decryption": decryption}, work / "core",
                     work / "server.json")
        check_config(core_xray, client_config,
                     {"iran_internet_ipv4": "127.0.0.1",
                      "starlink_ipv4": "127.0.0.1",
                      "bridge_server": "127.0.0.1",
                      "encryption_key": encryption,
                      '"uuid"': f'"{tunnel_uuid}"'}, work / "core",
                     work / "client.json")
        print(f"3x-ui {version}: panel CLI, schema, and all Xray configs OK")


if __name__ == "__main__":
    main()
