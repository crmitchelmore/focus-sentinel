#!/usr/bin/env python3
"""Socket-free checks of release-train publication configuration."""

import argparse
import importlib.util
import pathlib
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


if __name__ == "__main__":
    unittest.main()
