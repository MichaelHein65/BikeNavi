"""Package the selected artwork as an opaque 1024px iOS app icon."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
catalog = ROOT / "ios/BikeNavi/Assets.xcassets"
icon = catalog / "AppIcon.appiconset"
icon.mkdir(parents=True, exist_ok=True)
subprocess.run(["sips", "--resampleHeightWidth", "1024", "1024",
                str(ROOT / "design/AppIcon-source.png"), "--out", str(icon / "AppIcon.png")], check=True)
info = {"author": "xcode", "version": 1}
(catalog / "Contents.json").write_text(json.dumps({"info": info}, indent=2) + "\n")
(icon / "Contents.json").write_text(json.dumps({"images": [
    {"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
], "info": info}, indent=2) + "\n")
