import json
import sys
from shutil import copyfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
dist = root / "docs"
copyfile(root / "ScheduleApp/Resources/schedule.json", dist / "schedule.json")
db = json.loads((dist / "schedule.json").read_text(encoding="utf-8"))
core = (dist / "core.js").read_text(encoding="utf-8")
template = (root / "tools/widget-template.js").read_text(encoding="utf-8")
target = dist / "widgets"
target.mkdir(exist_ok=True)
site = (sys.argv[1] if len(sys.argv) > 1 else "https://mezhdu-parami-fiteu.artisticjuice.chatgpt.site").rstrip("/") + "/"

for group in db["groups"]:
    def js(value):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    script = "\n".join([f"const group = {js(group)};", f"const weeks = {js(db['weeks'])};",
                        f"const siteURL = {js(site)};", core, template])
    package = {"name": "Пары " + group["id"], "script": script,
               "icon": {"color": "deep-green", "glyph": "calendar-alt"},
               "share_sheet_inputs": [], "always_run_in_app": False}
    (target / (group["id"] + ".scriptable")).write_text(js(package), encoding="utf-8")
