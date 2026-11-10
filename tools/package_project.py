"""Bundle the complete source project for transfer to a Mac, without temporary renders."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
output = root / "output"
output.mkdir(exist_ok=True)
archive = output / "FITeU-iOS.zip"
included = [".github", "Schedule.xcodeproj", "ScheduleApp", "ScheduleWidget", "Shared", "Configuration", "Tests", "tools"]
files = [root/name for name in ["README.md", "WINDOWS.md", "Package.swift", ".gitignore"]]
for folder in included:
    files.extend(p for p in (root/folder).rglob("*") if p.is_file() and "__pycache__" not in p.parts)
with ZipFile(archive, "w", ZIP_DEFLATED) as handle:
    for path in sorted(files):
        handle.write(path, Path("MezhduParami") / path.relative_to(root))
with ZipFile(archive) as handle:
    assert handle.testzip() is None
print(f"Packaged {len(files)} files: output/FITeU-iOS.zip ({archive.stat().st_size:,} bytes)")
