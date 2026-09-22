"""Native process-restart check, restricted to an Android emulator.

Run under Firebase Auth emulators:exec with project demo-mooddare and
firebase.auth-test.json. Builds a test APK; rebuild the regular app afterward.
No production Firebase project or personal account is used.
"""
import os
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SERIAL = os.environ.get('MOODDARE_TEST_EMULATOR', 'emulator-5554')
if not re.fullmatch(r'emulator-\d+', SERIAL):
    raise SystemExit('This test only accepts emulator serials.')
ADB = Path(os.environ.get('ANDROID_HOME', str(Path.home() / 'Library/Android/sdk'))) / 'platform-tools/adb'
PACKAGE = 'com.example.mooddare'


def adb(*args):
    return subprocess.check_output([str(ADB), '-s', SERIAL, *args], text=True)


def screen():
    adb('shell', 'uiautomator', 'dump', '/data/local/tmp/mooddare-auth-probe.xml')
    return ET.fromstring(adb('exec-out', 'cat', '/data/local/tmp/mooddare-auth-probe.xml'))


def wait_for(label):
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        root = screen()
        for node in root.iter('node'):
            if label in node.get('text', '') or label in node.get('content-desc', ''):
                return node
        time.sleep(.2)
    raise AssertionError(f'Missing state: {label}')


def restart():
    adb('shell', 'am', 'force-stop', PACKAGE)
    adb('shell', 'am', 'start', '-n', f'{PACKAGE}/.MainActivity')


def sign_out():
    node = wait_for('Sign out test account')
    left, top, right, bottom = map(int, re.findall(r'\d+', node.attrib['bounds']))
    adb('shell', 'input', 'tap', str((left + right) // 2), str((top + bottom) // 2))
    wait_for('SESSION_SIGNED_OUT')


# Check exclusions for both backup APIs: device-bound encrypted preferences
# must never travel to a new installation through cloud restore or D2D transfer.
resources = ROOT / 'android/app/src/main/res/xml'
old = ET.parse(resources / 'backup_rules.xml').getroot()
new = ET.parse(resources / 'data_extraction_rules.xml').getroot()
for policy in [old, new.find('cloud-backup'), new.find('device-transfer')]:
    assert policy is not None
    assert any(node.get('domain') == 'sharedpref' and node.get('path') == '.'
               for node in policy.findall('exclude'))

subprocess.run(['flutter', 'build', 'apk', '--debug', '--target-platform', 'android-arm64',
                '--target', 'integration_test/auth_persistence_probe.dart'], cwd=ROOT, check=True)
adb('install', '-r', str(ROOT / 'build/app/outputs/flutter-apk/app-debug.apk'))
restart()
# Start with an explicit sign-out even if a previous probe left a session.
sign_out()
restart()
wait_for('SESSION_CREATED')
for _ in range(2):
    restart()
    wait_for('SESSION_RESTORED')
sign_out()
restart()
wait_for('SESSION_CREATED')
sign_out()
print('PASS: native session survives two process restarts; explicit sign-out persists; backup exclusions verified.', flush=True)
