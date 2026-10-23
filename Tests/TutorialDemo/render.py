#!/usr/bin/env python3
"""Regenerate tutorial movies with production overlay drawing; no desktop or capture access.
Requires Swift and ffmpeg. Run from the repository root after a signed Debug build.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app-bundle', type=Path, required=True, help='Built app supplying localized toolbar strings')
parser.add_argument('--locales', nargs='+', default=['en', 'de', 'es', 'fr', 'ja', 'ko', 'tr', 'zh-Hans'])
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='scrollsnap-tutorial-') as scratch:
    root = Path(scratch)
    helper = root / 'Renderer.app' / 'Contents'
    (helper / 'MacOS').mkdir(parents=True)
    resources = helper / 'Resources'
    resources.mkdir()
    for locale in args.locales:
        shutil.copytree(args.app_bundle / 'Contents' / 'Resources' / f'{locale}.lproj', resources / f'{locale}.lproj')
    (helper / 'Info.plist').write_text('<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>render</string><key>CFBundleIdentifier</key><string>local.scrollsnap.tutorial-renderer</string></dict></plist>')
    binary = helper / 'MacOS' / 'render'
    sources = [REPO / 'ScrollSnap' / name for name in [
        'Utilities/Constants.swift', 'Utilities/LocalizationSupport.swift',
        'Views/OverlayView.swift', 'Views/SelectionRectangleView.swift', 'Views/MenuBarView.swift']]
    subprocess.run(['swiftc', '-module-cache-path', '/private/tmp/scrollsnap-tutorial-render-cache',
                    *map(str, sources), str(Path(__file__).with_name('main.swift')), '-o', str(binary)], check=True)
    output = REPO / 'ScrollSnap' / 'Resources' / 'TutorialDemo'
    output.mkdir(parents=True, exist_ok=True)
    for locale in args.locales:
        frames = root / locale
        subprocess.run([str(binary), str(frames), locale], check=True)
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-framerate', '24',
                        '-i', str(frames / '%04d.png'), '-c:v', 'libx264', '-crf', '23', '-pix_fmt', 'yuv420p',
                        '-movflags', '+faststart', str(output / f'{locale}.mp4')], check=True)
        shutil.copyfile(frames / '0090.png', output / f'{locale}.png')
        shutil.rmtree(frames)
        print(f'Rendered {locale}', flush=True)
