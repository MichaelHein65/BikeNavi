"""Configure the installed development app without embedding keys in its bundle."""
import argparse
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("device", help="Device identifier from xcrun devicectl list devices")
args = parser.parse_args()
settings = dict(line.split("=", 1) for line in (ROOT / ".env").read_text().splitlines()
                if "=" in line and not line.startswith("#"))
token = settings.get("BIKENAVI_TOKEN", "").strip().strip('"').strip("'")
server_url = settings.get("BIKENAVI_SERVER_URL", "").strip().strip('"').strip("'")
if len(token) < 32:
    raise SystemExit("In .env fehlt ein gültiger BIKENAVI_TOKEN.")
if not server_url.startswith("https://"):
    raise SystemExit("In .env fehlt eine gültige BIKENAVI_SERVER_URL mit https://.")
environment = dict(os.environ)
environment["DEVICECTL_CHILD_BIKENAVI_SERVER"] = server_url
environment["DEVICECTL_CHILD_BIKENAVI_TOKEN"] = token
environment["DEVICECTL_CHILD_BIKENAVI_CONFIGURE"] = "1"
result = subprocess.run([
    "xcrun", "devicectl", "device", "process", "launch", "--quiet",
    "--device", args.device, "--terminate-existing", "de.michaelhein.BikeNavi",
], env=environment, capture_output=True)
if result.returncode:
    # CoreDevice errors may contain the environment; never print those unfiltered.
    output = (result.stdout + result.stderr).decode(errors="replace").replace(token, "[REDACTED]")
    print(output)
    raise SystemExit(result.returncode)
print("BikeNavi gestartet. Der App-Zugang wird im iPhone-Schlüsselbund gespeichert und der Pi geprüft.")
