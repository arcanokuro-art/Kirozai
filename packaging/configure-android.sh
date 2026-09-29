#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path

gradle = Path('android/app/build.gradle.kts')
text = gradle.read_text()
expected_id = 'applicationId = "com.arcanokuro.kirozai"'
debug_signing = 'signingConfig = signingConfigs.getByName("debug")'
if expected_id not in text or text.count(debug_signing) != 1:
    raise SystemExit('La plantilla Android generada cambió; revisar la firma antes de compilar.')

config = '''    signingConfigs {
        create("kirozaiDev") {
            storeFile = file("../../packaging/kirozai-dev.keystore")
            storePassword = "android"
            keyAlias = "kirozai-dev"
            keyPassword = "android"
        }
    }

'''
marker = '    buildTypes {'
if text.count(marker) != 1:
    raise SystemExit('No se encontró el bloque de compilación Android esperado.')
text = text.replace(marker, config + marker, 1)
text = text.replace(debug_signing,
                    'signingConfig = signingConfigs.getByName("kirozaiDev")', 1)
gradle.write_text(text)
PY
