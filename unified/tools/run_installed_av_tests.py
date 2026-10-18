#!/usr/bin/env python3
# GPL-2.0-or-later. Explicit native output diagnostics; never changes audio defaults.
"""Validate installed20 helper-first availability, singleton modes and native A/V.

Run only when capture and Final Cut output are stopped. This intentionally sends
video and a quiet tone through the Shuttle. It never starts Final Cut, changes
Mac audio defaults, installs drivers or alters system-extension activation.
"""
import json
import os
import plistlib
import re
import subprocess
import time
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
APP = Path('/Applications/Shuttle Camera.app')
HELPER = APP / 'Contents/MacOS/ShuttlePlayback'
SINK = BASE / 'sink-test'
PROBE = BASE / 'format-probe'
TONE = BASE / 'audio-output-test'
MODES = ['576i50', '1080i50', '1080p25', '480i5994', '1080i5994', '1080p2997']
REPORT_PATH = BASE / 'installed20-native-av-results.json'
SUMMARY_PATH = BASE / 'installed20-native-av-tests.log'
WAIT_SECONDS = 8.0


def require_installed20():
    extensions = APP / 'Contents/Library/SystemExtensions'
    bundles = [
        (APP, 'local.shuttle.camera', '20'),
        (extensions / 'local.shuttle.camera.extension.systemextension', 'local.shuttle.camera.extension', '15'),
        (extensions / 'local.shuttle.output.extension.systemextension', 'local.shuttle.output.extension', '8'),
        (Path('/Library/Audio/Plug-Ins/HAL/Shuttle Audio.driver'), 'local.shuttle.audio', '3'),
    ]
    for path, identifier, version in bundles:
        with (path / 'Contents/Info.plist').open('rb') as source:
            info = plistlib.load(source)
        if (info.get('CFBundleIdentifier'), info.get('CFBundleVersion')) != (identifier, version):
            raise RuntimeError(f'Unexpected installed bundle: {path}')
    for binary in [HELPER, SINK, PROBE, TONE]:
        if not binary.is_file() or not os.access(binary, os.X_OK):
            raise RuntimeError(f'Missing executable: {binary}')
    # Do not attach to, stop or replace somebody else's playback session.
    for name in ['ShuttlePlayback', 'Final Cut Pro']:
        result = subprocess.run(['/usr/bin/pgrep', '-x', name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode == 0:
            raise RuntimeError(f'{name} is already running; close output before this explicit native test')
        if result.returncode != 1:
            raise RuntimeError(f'Could not check whether {name} is running')


def poll_probe(arguments, log, sender=None):
    """Every check is read-only; wait boundedly for CMIO publish/remove events."""
    start = time.monotonic()
    deadline = start + WAIT_SECONDS
    last = ''
    attempts = 0
    while time.monotonic() < deadline:
        if sender is not None and sender.poll() is not None:
            raise RuntimeError(f'USB helper exited before expected mode was ready ({sender.returncode})')
        remaining = deadline - time.monotonic()
        attempts += 1
        try:
            result = subprocess.run([str(PROBE), *arguments], text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=max(0.1, min(2.0, remaining)))
            last = result.stdout
            log.write(f'--- Probe attempt {attempts}; exit {result.returncode} ---\n{last}')
            log.flush()
            if result.returncode == 0:
                return dict(passed=True, attempts=attempts, elapsed_seconds=round(time.monotonic() - start, 3))
        except subprocess.TimeoutExpired as error:
            last = str(error)
            log.write(f'Probe timeout: {last}\n')
            log.flush()
        time.sleep(min(0.1, max(0.0, deadline - time.monotonic())))
    raise RuntimeError(f'Expected CMIO availability was not reached within {WAIT_SECONDS:g}s: {arguments}; {last[-1000:]}')


def stop_owned(process):
    if process is None:
        return None
    if process.poll() is None:
        process.terminate()
    try:
        return process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=3)
        raise RuntimeError('Owned diagnostic process did not stop after termination')


def run_native(mode_index):
    mode = MODES[mode_index]
    relative = mode_index in (2, 3, 5)
    prefix = BASE / ('installed20-' + mode)
    sender = tone = None
    client_exit = helper_exit = tone_exit = None
    ready = removed = None
    with open(str(prefix) + '-usb.log', 'w') as usb_log, \
         open(str(prefix) + '-tone.log', 'w') as tone_log, \
         open(str(prefix) + '-client.log', 'w') as client_log, \
         open(str(prefix) + '-format.log', 'w') as format_log:
        sender = subprocess.Popen([str(HELPER), '--sink', mode, 'live'], stdout=usb_log, stderr=subprocess.STDOUT)
        try:
            # Output8 derives its one advertised format from the ready helper;
            # writing a CMIO format before the helper exists is intentionally absent.
            ready = poll_probe(['--expect-mode', mode], format_log, sender)
            tone = subprocess.Popen([str(TONE), '4'], stdout=tone_log, stderr=subprocess.STDOUT)
            time.sleep(0.55)  # Existing explicit-tone preroll for HAL3's 256ms buffering.
            env = os.environ.copy()
            if relative:
                env['SHUTTLE_TEST_RELATIVE_PTS'] = '1'
            else:
                env.pop('SHUTTLE_TEST_RELATIVE_PTS', None)
            # Singleton list index0 resolves its wire profile from FormatName.
            client = subprocess.run([str(SINK), '0', '2'], env=env, stdout=client_log,
                                    stderr=subprocess.STDOUT, timeout=8)
            client_exit = client.returncode
        finally:
            try:
                helper_exit = stop_owned(sender)
            finally:
                if tone is not None:
                    try:
                        tone_exit = tone.wait(timeout=6)
                    except subprocess.TimeoutExpired:
                        stop_owned(tone)
                        raise RuntimeError('Explicit audio tone did not stop on schedule')
            removed = poll_probe(['--absent'], format_log)
    data = Path(str(prefix) + '-usb.log').read_text()
    audio = re.search(r'HDMI audio: (\d+) samples received; (\d+)/(\d+) requested', data)
    video = re.search(r'CMIO transport: (\d+) complete frames received; (\d+) playback acknowledgements', data)
    errors = re.search(r'transfer errors: (\d+); packet errors: (\d+); cancellation complete: (\w+)', data)
    row = dict(mode=mode, singleton_index=0, relative_pts=relative, ready=ready, removed=removed,
               client_exit=client_exit, helper_exit=helper_exit, tone_exit=tone_exit,
               audio=list(map(int, audio.groups())) if audio else None,
               video=list(map(int, video.groups())) if video else None,
               errors=list(errors.groups()) if errors else None)
    row['passed'] = (client_exit == helper_exit == tone_exit == 0 and bool(audio and video and errors)
                     and int(audio[2]) == int(audio[3]) and int(audio[3]) > 80000
                     and int(video[1]) == int(video[2]) and errors.groups() == ('0', '0', 'yes'))
    return row


def run_readiness_cycle(cycle, mode):
    """Publish/remove repeatedly without a CMIO stream client or Core Audio I/O."""
    prefix = BASE / f'installed20-readiness-{cycle}-{mode}'
    with open(str(prefix) + '-usb.log', 'w') as usb_log, open(str(prefix) + '-format.log', 'w') as format_log:
        idle = poll_probe(['--absent'], format_log)
        sender = subprocess.Popen([str(HELPER), '--sink', mode, 'live'], stdout=usb_log, stderr=subprocess.STDOUT)
        try:
            ready = poll_probe(['--expect-mode', mode], format_log, sender)
        finally:
            helper_exit = stop_owned(sender)
            removed = poll_probe(['--absent'], format_log)
    data = Path(str(prefix) + '-usb.log').read_text()
    errors = re.search(r'transfer errors: (\d+); packet errors: (\d+); cancellation complete: (\w+)', data)
    row = dict(cycle=cycle, mode=mode, idle=idle, ready=ready, removed=removed, helper_exit=helper_exit,
               errors=list(errors.groups()) if errors else None)
    row['passed'] = helper_exit == 0 and bool(errors) and errors.groups() == ('0', '0', 'yes')
    return row


def main():
    report = dict(release='0.1.20', intended_versions=dict(host=20, camera=15, output=8, hal=3),
                  idle_absence=None, native_av=[], readiness_enumeration=[], passed=False)
    with SUMMARY_PATH.open('w') as summary:
        def emit(value):
            line = json.dumps(value)
            print(line, flush=True)
            summary.write(line + '\n')
            summary.flush()
        try:
            require_installed20()
            with (BASE / 'installed20-idle-format.log').open('w') as log:
                report['idle_absence'] = poll_probe(['--absent'], log)
            emit(dict(idle_absence=report['idle_absence']))
            for index in range(len(MODES)):
                row = run_native(index)
                report['native_av'].append(row)
                emit(row)
                if not row['passed']:
                    raise RuntimeError(f'Native A/V verification failed for {MODES[index]}')
            # Two complete passes check repeated starts of the same formats and
            # transitions across PAL/NTSC, HD/SD, interlaced/progressive modes.
            for cycle in range(1, 3):
                for mode in MODES:
                    row = run_readiness_cycle(cycle, mode)
                    report['readiness_enumeration'].append(row)
                    emit(row)
                    if not row['passed']:
                        raise RuntimeError(f'Readiness cycle {cycle} failed for {mode}')
            report['passed'] = True
        except Exception as error:
            report['error'] = f'{type(error).__name__}: {error}'
            emit(dict(error=report['error']))
        finally:
            REPORT_PATH.write_text(json.dumps(report, indent=2) + '\n')
            emit(dict(passed=report['passed'], report=str(REPORT_PATH)))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
