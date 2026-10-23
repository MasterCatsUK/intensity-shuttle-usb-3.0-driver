"""Prepare the installer input from a clean source checkout and local builds."""
from pathlib import Path
import shutil
root=Path(__file__).resolve().parents[1]
stage=root/'build/release-source/shuttle-video-development'
if stage.exists():
 raise SystemExit('Staging already exists. Move build/release-source aside before rebuilding; it was not overwritten.')
stage.mkdir(parents=True)
ignore=shutil.ignore_patterns('build','.git','.DS_Store','__pycache__','*.o','*.log','*.app','*.driver','*.bundle','qa','DEVELOPMENT-48.md','DEVELOPMENT-49.md','DEVELOPMENT-50.md')
for path in root.iterdir():
 if path.name in ['build','.git','.DS_Store','qa','DEVELOPMENT-48.md','DEVELOPMENT-49.md','DEVELOPMENT-50.md'] or path.suffix in ('.log','.o'):continue
 target=stage/path.name
 if path.is_dir():shutil.copytree(path,target,ignore=ignore)
 else:shutil.copy2(path,target)
for source,target in [(root/'build/Shuttle Video.app',stage/'Shuttle Video.app'),(root/'audio/build/Shuttle Audio.driver',stage/'audio/Shuttle Audio.driver'),(root/'unified/premiere/build/Shuttle Transmit.bundle',stage/'unified/premiere/build/Shuttle Transmit.bundle')]:
 shutil.copytree(source,target)
print(stage)
