"""Static project integrity checks; does not replace xcodebuild."""
from pathlib import Path
import json
import plistlib
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
paths = [*root.glob("**/*.plist"), *root.glob("**/*.entitlements"), *root.glob("**/*.xcprivacy")]
for path in paths:
    values = plistlib.loads(path.read_bytes())
    if path.suffix == ".entitlements":
        assert not values, "Sideload build must not require extra entitlements"
ET.parse(root/"Schedule.xcodeproj/xcshareddata/xcschemes/ScheduleApp.xcscheme")
for path in root.glob("ScheduleApp/Assets.xcassets/**/Contents.json"):
    contents = json.loads(path.read_text())
    for image in contents.get("images", []):
        assert (path.parent/image["filename"]).exists()
project = (root/"Schedule.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
for path in re.findall(r'path = "([^"]+)";', project):
    if not path.endswith((".app", ".appex")):
        assert (root/path).exists(), path
definitions = set(re.findall(r'([0-9A-F]{24}) = \{', project))
all_ids = set(re.findall(r'\b[0-9A-F]{24}\b', project))
assert all_ids <= definitions, all_ids-definitions
assert project.count('isa = "PBXNativeTarget"') == 2
assert project.count('isa = "PBXSourcesBuildPhase"') == 2
assert 'name = "Embed App Extensions"' in project
print(f"Validated {len(paths)} plists, scheme XML, assets, file paths and {len(definitions)} Xcode object references.")
