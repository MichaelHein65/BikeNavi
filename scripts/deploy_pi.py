"""Deploy only this application's files to its dedicated directory on pi5."""
from pathlib import Path
import json
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
TARGET = "pi5"
REMOTE = "/srv/bikenavi"


def ssh(command, **kwargs):
    return subprocess.run(["ssh", "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", TARGET, command],
                          check=True, **kwargs)


if not (ROOT / ".env").exists():
    raise SystemExit("Zuerst .env anlegen.")
config = json.loads(ssh("tailscale serve status --json", capture_output=True, text=True).stdout)
for host, web in config.get("Web", {}).items():
    if host.endswith(":10443") and web.get("Handlers", {}).get("/", {}).get("Proxy") != "http://127.0.0.1:8093":
        raise SystemExit("Tailscale-Port 10443 ist bereits anderweitig belegt.")
ssh("if test -e /srv/bikenavi; then test -f /srv/bikenavi/.bikenavi-owned; else sudo -n install -d -m 700 -o pi -g pi /srv/bikenavi; fi")
ssh("touch /srv/bikenavi/.bikenavi-owned")
archive = ROOT / "build/bikenavi-deploy.tar.gz"
archive.parent.mkdir(exist_ok=True)
with tarfile.open(archive, "w:gz") as tar:
    for relative in ["compose.yaml", "ops/bikenavi-ipv6.sh", "server/Dockerfile", "server/.dockerignore", "server/requirements.lock", "server/pyproject.toml"]:
        tar.add(ROOT / relative, arcname=relative)
    for path in sorted((ROOT / "server/bikenavi").glob("*.py")):
        tar.add(path, arcname=path.relative_to(ROOT))
subprocess.run(["scp", "-q", str(archive), f"{TARGET}:{REMOTE}/release.tar.gz"], check=True)
subprocess.run(["scp", "-q", str(ROOT / ".env"), f"{TARGET}:{REMOTE}/.env"], check=True)
ssh("chmod 600 /srv/bikenavi/.env && cd /srv/bikenavi && tar xzf release.tar.gz && sudo -n sh ops/bikenavi-ipv6.sh --install && docker compose up --build -d")
ssh("sudo -n tailscale serve --bg --https=10443 http://127.0.0.1:8093")
print("BikeNavi wurde als eigenes Compose-Projekt bereitgestellt.")
