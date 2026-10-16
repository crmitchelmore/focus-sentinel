#!/usr/bin/env python3
"""Socket-free checks of release-train publication configuration."""

import argparse
import base64
import importlib.util
import os
import pathlib
import shlex
import subprocess
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location(
    "release_train", pathlib.Path(__file__).with_name("release-train.py")
)
release_train = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release_train)


class ReleaseConfigurationTests(unittest.TestCase):
    def configuration(self, train, tag):
        manifest = {
            "train": train,
            "version": "0.1.0",
            "build": 7,
            "source": "a" * 40,
            "minimumSystemVersion": "26.0",
        }
        with mock.patch.object(release_train, "read_manifest", return_value=manifest), \
                mock.patch.object(release_train, "write_env") as write_env:
            release_train.cmd_configure(argparse.Namespace(tag=tag))
        return write_env.call_args.args[0]

    def test_alpha_enclosure_uses_the_public_immutable_build(self):
        values = self.configuration("alpha", "alpha-build-7")
        self.assertEqual(values["DOWNLOAD_TAG"], "alpha-build-7")
        self.assertEqual(values["XCODE_CONFIGURATION"], "Alpha")
        self.assertEqual(
            values["FEED_URL"], release_train.TRAINS["alpha"]["feedURL"]
        )

    def test_stable_enclosure_uses_the_public_version_not_the_draft_candidate(self):
        values = self.configuration("stable", "stable-candidate-3")
        self.assertEqual(values["RELEASE_TAG"], "stable-candidate-3")
        self.assertEqual(values["DOWNLOAD_TAG"], "v0.1.0")
        self.assertEqual(values["XCODE_CONFIGURATION"], "Release")
        self.assertEqual(
            values["FEED_URL"], release_train.TRAINS["stable"]["feedURL"]
        )

    def test_signing_secret_flags_are_available_before_step_conditions(self):
        workflow = (
            pathlib.Path(__file__).resolve().parent.parent
            / ".github/workflows/release-mac.yml"
        ).read_text()
        job, steps = workflow.split("    steps:", 1)
        for flag, secret in [
            ("HAS_P12", "APPLE_DEVELOPER_ID_APPLICATION"),
            ("HAS_KEY", "APP_STORE_CONNECT_API_KEY"),
        ]:
            with self.subTest(flag=flag):
                declaration = f"{flag}: ${{{{ secrets.{secret} != '' }}}}"
                self.assertIn(declaration, job)
                self.assertNotIn(declaration, steps)
                self.assertIn(f"env.{flag} == 'true'", steps)

    def test_release_steps_stop_before_claiming_success_after_an_error(self):
        workflow = (
            pathlib.Path(__file__).resolve().parent.parent
            / ".github/workflows/release-mac.yml"
        ).read_text()
        for name in [
            "Source lints", "The product is the train it claims", "Package the disk image",
            "Sign the appcast", "Upload and write the receipt",
        ]:
            with self.subTest(step=name):
                step = workflow.split(f"- name: {name}\n", 1)[1].split("\n      - ", 1)[0]
                self.assertIn("run: |\n          set -e -o pipefail\n", step)
        self.assertIn("persist-credentials: true", workflow)

    def test_verified_receipts_require_nonempty_uploaded_assets(self):
        for failure in ["missing", "empty", "changed", "incomplete", None]:
            with self.subTest(failure=failure), \
                    tempfile.TemporaryDirectory(prefix="focus-receipt-test-") as directory:
                root = pathlib.Path(directory)
                image = root / "FocusSentinel.dmg"
                appcast = root / "appcast.xml"
                image.write_bytes(b"image")
                appcast.write_bytes(b"" if failure == "empty" else b"appcast")
                remote_dir = root / "remote"
                remote_dir.mkdir()

                def downloaded(tag, name, into):
                    if failure == "missing":
                        return None
                    remote = remote_dir / name
                    content = (root / name).read_bytes()
                    remote.write_bytes(content + (b"changed" if failure == "changed" else b""))
                    return remote

                args = argparse.Namespace(
                    tag="alpha-build-13", status="verified",
                    asset=[str(image)] if failure == "incomplete" else [str(image), str(appcast)],
                )
                with mock.patch.object(release_train, "download_asset", side_effect=downloaded), \
                        mock.patch.object(release_train, "upload") as upload:
                    if failure:
                        with self.assertRaises(SystemExit):
                            release_train.cmd_receipt(args)
                        upload.assert_not_called()
                    else:
                        release_train.cmd_receipt(args)
                        upload.assert_called_once()

    def test_codesigning_helper_preserves_executable_search_path(self):
        script = pathlib.Path(__file__).with_name("sign-and-notarise.sh").read_text()
        body = script.split("sign() {\n", 1)[1].split("\n}\n", 1)[0]
        with tempfile.TemporaryDirectory(prefix="focus-sign-test-") as directory:
            tool = pathlib.Path(directory) / "codesign"
            tool.write_text('#!/bin/sh\nexit 0\n')
            tool.chmod(0o700)
            result = subprocess.run(
                [
                    "/bin/zsh", "-fc",
                    f"sign() {{\n{body}\n}}\n"
                    f"PATH={shlex.quote(directory)}:/usr/bin:/bin\n"
                    "APP=/tmp/Example.app\nIDENTITY=test\nsign /tmp/Example.app",
                ],
                capture_output=True, text=True, check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("signed", result.stdout)

    def test_appcast_signing_uses_a_temporary_key_and_rejects_failed_signatures(self):
        script = pathlib.Path(__file__).with_name("generate-appcast.sh").resolve()
        signature = base64.b64encode(bytes(64)).decode()
        for source, output, status in [
            ("keychain", signature, 0),
            ("export", signature, 0),
            ("keychain", "fixture-private-key", 1),
            ("keychain", "invalid-signature", 0),
        ]:
            with self.subTest(source=source, status=status, output=output), \
                    tempfile.TemporaryDirectory(prefix="focus-appcast-test-") as directory:
                root = pathlib.Path(directory)
                signer = root / "SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
                signer.parent.mkdir(parents=True)
                signer.write_text(
                    '#!/bin/sh\n'
                    'test "$1" = "--ed-key-file" && test -s "$2" || exit 2\n'
                    'printf "%s" "$2" > "$SIGN_TEST_KEY_PATH"\n'
                    'printf "%s" "$SIGN_TEST_OUTPUT"\n'
                    'exit "$SIGN_TEST_STATUS"\n'
                )
                signer.chmod(0o700)
                reader = root / "swift"
                reader.write_text(
                    '#!/bin/sh\n'
                    'test "$1" = "scripts/read-sparkle-key.swift" || exit 2\n'
                    'printf "%s" "fixture-private-key"\n'
                )
                reader.chmod(0o700)
                dmg = root / "fixture.dmg"
                dmg.write_bytes(b"fixture archive")
                key_path = root / "key-path"
                env = os.environ.copy()
                env.update({
                    "PATH": f"{directory}:/usr/bin:/bin",
                    "FOCUS_DERIVED_DATA": directory,
                    "SIGN_TEST_KEY_PATH": str(key_path),
                    "SIGN_TEST_OUTPUT": output,
                    "SIGN_TEST_STATUS": str(status),
                })
                if source == "export":
                    env["SPARKLE_PRIVATE_KEY"] = "fixture-private-key"
                else:
                    env.pop("SPARKLE_PRIVATE_KEY", None)
                result = subprocess.run(
                    ["/bin/zsh", str(script), "0.1.0", "9", str(dmg),
                     "https://example.test/feed", "https://example.test/archive"],
                    env=env, capture_output=True, text=True, check=False,
                )
                if output == signature:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn(f'sparkle:edSignature="{signature}"', result.stdout)
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("<rss", result.stdout)
                self.assertNotIn("fixture-private-key", result.stdout + result.stderr)
                self.assertFalse(pathlib.Path(key_path.read_text()).exists())


if __name__ == "__main__":
    unittest.main()
