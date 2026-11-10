"""Draw the app's simple geometric calendar icon (Pillow required only to regenerate)."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1] / "ScheduleApp/Assets.xcassets"
folder = root / "AppIcon.appiconset"
folder.mkdir(parents=True, exist_ok=True)
image = Image.new("RGB", (1024, 1024), "#192b29")
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((188, 225, 836, 807), radius=66, fill="#f2f3e9")
draw.rounded_rectangle((188, 225, 836, 386), radius=66, fill="#d1ef8c")
draw.rectangle((188, 302, 836, 386), fill="#d1ef8c")
for x in (340, 684):
    draw.rounded_rectangle((x-25, 168, x+25, 289), radius=25, fill="#f2f3e9")
for y in (470, 565, 660):
    draw.rounded_rectangle((260, y, 307, y+47), radius=12, fill="#2b634b")
    draw.rounded_rectangle((354, y+11, 691 if y==565 else 755, y+35), radius=12, fill="#192b29")
image.save(folder/"AppIcon.png")
(folder/"Contents.json").write_text(json.dumps({"images":[{"filename":"AppIcon.png", "idiom":"universal", "platform":"ios", "size":"1024x1024"}], "info":{"author":"xcode","version":1}}, indent=2))
(root/"Contents.json").write_text(json.dumps({"info":{"author":"xcode","version":1}}, indent=2))
print("App icon created: 1024 x 1024, RGB, opaque")
