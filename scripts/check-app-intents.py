#!/usr/bin/env python3
"""Verify Shortcuts metadata and its compiled main-bundle localisation."""

import json
from pathlib import Path
import subprocess
import sys


def verify(app: Path) -> None:
    resources = app / "Contents/Resources"
    metadata = json.loads((resources / "Metadata.appintents/extract.actionsdata").read_text())
    strings = json.loads(subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-",
        str(resources / "en.lproj/Localizable.strings"),
    ], text=True))
    expected = {
        "SetFocusPriorityIntent": "setPriority",
        "StartFocusSessionIntent": "startSession",
        "FinishFocusSessionIntent": "finishSession",
    }
    actions = metadata["actions"]
    if set(actions) != set(expected):
        raise ValueError("the app must export exactly the three Focus actions")
    shortcuts = metadata["autoShortcuts"]
    if len(shortcuts) != 3 or {s["actionIdentifier"] for s in shortcuts} != set(expected):
        raise ValueError("every Focus action must have one discoverable app shortcut")

    def translated(value: dict, key: str) -> None:
        if value.get("key") != key:
            raise ValueError(f"metadata references the wrong key: expected {key}")
        text = strings.get(key)
        if not isinstance(text, str) or not text.strip() or text == key:
            raise ValueError(f"main-bundle translation missing: {key}")

    for identifier, verb in expected.items():
        action = actions[identifier]
        prefix = f"shell.intent.{verb}"
        translated(action["title"], prefix + ".title")
        translated(action["descriptionMetadata"]["descriptionText"], prefix + ".description")
        if action.get("openAppWhenRun") is not True or action.get("isDiscoverable") is not True:
            raise ValueError(f"{identifier} must be discoverable and launch the app")
        parameters = action["parameters"]
        if verb == "setPriority":
            if len(parameters) != 1 or parameters[0].get("name") != "priority" or parameters[0].get("isOptional") is not False:
                raise ValueError("Set Priority must require one priority parameter")
            translated(parameters[0]["title"], prefix + ".parameter")
        elif parameters:
            raise ValueError(f"{identifier} unexpectedly requires input")
        shortcut = next(s for s in shortcuts if s["actionIdentifier"] == identifier)
        translated(shortcut["shortTitle"], prefix + ".title")
        if not shortcut.get("phraseTemplates"):
            raise ValueError(f"{identifier} has no invocation phrase")
        print(f"ok   {identifier}: exported, translated, foreground execution")


if __name__ == "__main__":
    try:
        verify(Path(sys.argv[1]))
    except (IndexError, KeyError, ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"FAIL [App Intents] {error}", file=sys.stderr)
        sys.exit(1)
