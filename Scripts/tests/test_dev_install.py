#!/usr/bin/env python3
"""Exercise dev bundle publication using temporary files, never installed apps."""
import importlib.util
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEV_ID = "com.chiakey.inputmethod.ChiaKeyDev"
spec = importlib.util.spec_from_file_location("replace_dev_bundle", ROOT / "Scripts/replace-dev-bundle.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class DevInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def bundle(self, name, version, identifier=DEV_ID):
        path = self.root / name
        (path / "Contents").mkdir(parents=True)
        (path / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": identifier, "CFBundleVersion": version,
        }))
        return path

    def version(self, path):
        return plistlib.loads((path / "Contents/Info.plist").read_bytes())["CFBundleVersion"]

    def test_first_install_and_atomic_upgrade(self):
        stage = self.bundle("stage.app", "1")
        installed = self.root / "installed.app"
        release = self.bundle("release.app", "release", "com.chiakey.inputmethod.ChiaKey")
        publisher.replace(stage, installed, DEV_ID)
        self.assertEqual(self.version(installed), "1")
        self.assertFalse(stage.exists())
        stage = self.bundle("stage.app", "2")
        publisher.replace(stage, installed, DEV_ID)
        self.assertEqual(self.version(installed), "2")
        self.assertEqual(self.version(stage), "1")
        self.assertEqual(self.version(release), "release")

    def test_rejects_incomplete_identity_and_symlink_without_losing_install(self):
        installed = self.bundle("installed.app", "1")
        stage = self.bundle("stage.app", "2", "com.chiakey.inputmethod.ChiaKey")
        with self.assertRaises(ValueError):
            publisher.replace(stage, installed, DEV_ID)
        self.assertEqual(self.version(installed), "1")
        valid = self.bundle("valid.app", "3")
        link = self.root / "link.app"
        link.symlink_to(installed)
        with self.assertRaises(ValueError):
            publisher.replace(valid, link, DEV_ID)
        self.assertEqual(self.version(installed), "1")
        self.assertEqual(self.version(valid), "3")

    def test_install_prepares_identity_and_signature_before_publication(self):
        output = subprocess.check_output([
            "bash", str(ROOT / "Scripts/dev-install-local.sh"), "--skip-build", "--dry-run"
        ], text=True, encoding="utf-8", errors="replace")
        publish = output.index("/Scripts/replace-dev-bundle.py")
        self.assertLess(output.index("CFBundleIdentifier"), publish)
        self.assertLess(output.index("/usr/bin/codesign --force --deep --sign"), publish)
        install = output.index("install --wait-for-approval")
        self.assertGreater(install, publish)
        # A relaunch from the pre-swap bundle must not survive the install.
        self.assertIn("pkill", output[publish:install])
        for line in output.splitlines():
            if "/bin/rm -rf" in line:
                self.assertNotIn("/ChiaKeyDev.app", line)
        self.assertNotIn("pkill", output[install:])


if __name__ == "__main__":
    unittest.main()
