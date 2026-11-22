#!/usr/bin/env python3
"""把 App 版本固定为 2.1.0，并让 versionCode 从 2010000 起自动递增。

首次运行（当前 1.2.0）会重置为 2.1.0 / 2010000；
之后每次打包只增加 versionCode，versionName 保持 2.1.0。
"""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
APP_JSON = ROOT / 'AppScope' / 'app.json5'
BASE_NAME = '2.1.0'
BASE_CODE = 2010000

text = APP_JSON.read_text(encoding='utf-8')
name_match = re.search(r'"versionName"\s*:\s*"([^"]+)"', text)
code_match = re.search(r'"versionCode"\s*:\s*(\d+)', text)

if not name_match or not code_match:
    raise SystemExit('app.json5 缺少 versionName / versionCode')

current_name = name_match.group(1)
current_code = int(code_match.group(1))

if current_name != BASE_NAME:
    new_name = BASE_NAME
    new_code = BASE_CODE
else:
    new_name = BASE_NAME
    new_code = max(current_code, BASE_CODE - 1) + 1

text = re.sub(r'"versionCode"\s*:\s*\d+', f'"versionCode": {new_code}', text, count=1)
text = re.sub(r'"versionName"\s*:\s*"[^"]+"', f'"versionName": "{new_name}"', text, count=1)
APP_JSON.write_text(text, encoding='utf-8')

print(f'versionName={new_name} versionCode={new_code}')
