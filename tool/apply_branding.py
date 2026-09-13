#!/usr/bin/env python3
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / 'android/app/src/main/res'
BRANDING = ROOT / 'branding/android'
MANIFEST = ROOT / 'android/app/src/main/AndroidManifest.xml'

for src_dir in BRANDING.glob('mipmap-*'):
    dst = RES / src_dir.name
    dst.mkdir(parents=True, exist_ok=True)
    for src in src_dir.glob('*'):
        shutil.copy2(src, dst / src.name)

text = MANIFEST.read_text(encoding='utf-8')
text = re.sub(r'android:label="[^"]*"', 'android:label="Delta Peak"', text, count=1)
if 'android:icon=' not in text:
    text = text.replace(
        'android:name="${applicationName}">',
        'android:name="${applicationName}"\n        android:icon="@mipmap/ic_launcher">',
        1,
    )
else:
    text = re.sub(r'android:icon="[^"]*"', 'android:icon="@mipmap/ic_launcher"', text, count=1)
MANIFEST.write_text(text, encoding='utf-8')

assert 'android:label="Delta Peak"' in text
assert 'android:icon="@mipmap/ic_launcher"' in text
print('Delta Peak branding restored: label + launcher icons')
