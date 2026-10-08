"""Regressions against the pinned native source, without mutating the build tree."""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = Path('flutter/android/app/src/main')
KOTLIN_ROOT = SOURCE_ROOT / 'kotlin/com/carriez/flutter_hbb'


def replace_once(text, old, new, description):
    if text.count(old) != 1:
        raise AssertionError('Pinned source anchor changed: ' + description)
    return text.replace(old, new, 1)


class OverlayTest(unittest.TestCase):
    def test_actual_source_generation_and_recovery_wiring(self):
        spec = importlib.util.spec_from_file_location('xixi_overlay', PROJECT / 'mobile/build-support/unattended_overlay.py')
        overlay = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(overlay)
        with tempfile.TemporaryDirectory(prefix='xixi-recovery-overlay-') as directory:
            stage = Path(directory)
            names = ('MainService.kt', 'MainActivity.kt', 'InputService.kt', 'BootReceiver.kt')
            for name in names:
                target = stage / KOTLIN_ROOT / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(PROJECT / 'upstream/rustdesk-1.5.0' / KOTLIN_ROOT / name, target)
            xml = stage / SOURCE_ROOT / 'res/xml/accessibility_service_config.xml'
            xml.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(PROJECT / 'upstream/rustdesk-1.5.0' / SOURCE_ROOT / 'res/xml/accessibility_service_config.xml', xml)
            changed = overlay.apply_unattended(PROJECT, stage, replace_once)
            self.assertEqual(len(changed), 7)
            self.assertEqual((stage / KOTLIN_ROOT / 'XixiRecoveryPolicy.kt').read_bytes(),
                             (PROJECT / 'mobile/android/XixiRecoveryPolicy.kt').read_bytes())
            activity = (stage / KOTLIN_ROOT / 'MainActivity.kt').read_text(encoding='utf-8')
            service = (stage / KOTLIN_ROOT / 'MainService.kt').read_text(encoding='utf-8')
            input_service = (stage / KOTLIN_ROOT / 'InputService.kt').read_text(encoding='utf-8')
            enabled_init = activity.split('"init_service" -> {', 1)[1].split('Intent(activity, MainService', 1)[0]
            self.assertIn('XixiUnattended.enabled(this)', enabled_init)
            self.assertIn('return@setMethodCallHandler', enabled_init)
            self.assertNotIn('requestMediaProjection()', enabled_init)
            self.assertNotIn('retry = true', enabled_init, 'Automatic init cannot extend the recovery window')
            explicit_retry = activity.split('"xixi_retry_unattended" -> {', 1)[1].split('"xixi_enable_unattended"', 1)[0]
            self.assertIn('XixiUnattended.enabled(this) && XixiUnattended.start(this, retry = true)', explicit_retry)
            self.assertNotIn('setEnabled', explicit_retry)
            self.assertNotIn('requestMediaProjection', explicit_retry)
            self.assertIn('XixiUnattended.start(this, retry = true)', activity)
            self.assertIn('intent == null && XixiUnattended.enabled(this)', service)
            self.assertIn('XixiUnattended.onHostServiceStarted(this)', service)
            self.assertIn('if (!XixiUnattended.running || resumeCapture && !isStart)', service)
            self.assertIn('private val xixiCaptureDemand = XixiCaptureDemand()', service)
            self.assertIn('val resumeCapture = xixiCaptureDemand.needsResume(isStart)', service)
            self.assertIn('xixiCaptureDemand.pausedAfterStop(resumeCapture)', service)
            stop_capture = service.split('fun stopCapture() {', 1)[1].split('fun destroy()', 1)[0]
            self.assertIn('xixiCaptureDemand.stopped()', stop_capture)
            self.assertIn('"stop_capture" ->', service)
            self.assertIn('XixiUnattended.onHostServiceDestroyed(this)', service)
            self.assertEqual(input_service.count('if (ctx === this)'), 2)
            self.assertNotIn('disableSelf()', input_service)
            self.assertEqual(activity.count('disableSelf()'), 1, 'Only the original explicit stop_input can revoke accessibility')
            self.assertNotIn('Settings.Secure.put', activity + input_service + service)
            self.assertNotIn('requestRebind', activity + input_service + service)


if __name__ == '__main__':
    unittest.main()
