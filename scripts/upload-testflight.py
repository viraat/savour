#!/usr/bin/env python3
"""Upload a signed Savour archive using a locally configured App Store Connect key."""

import argparse
import json
from pathlib import Path
import plistlib
import shlex
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="Path to Savour.xcarchive")
    parser.add_argument("--config", type=Path,
                        default=Path.home() / ".config/savour-release/app-store-connect.json")
    parser.add_argument("--export-path", type=Path)
    parser.add_argument("--dry-run", action="store_true", help="Validate inputs without uploading")
    args = parser.parse_args()

    try:
        config = json.loads(args.config.expanduser().read_text())
        required = ("key_id", "issuer_id", "private_key_path", "team_id", "bundle_id")
        if any(not isinstance(config.get(key), str) or not config[key].strip() for key in required):
            raise ValueError("Config must supply: " + ", ".join(required))
        key_path = Path(config["private_key_path"]).expanduser().resolve()
        if not key_path.is_file():
            raise ValueError(f"Private key not found: {key_path}")
        archive = args.archive.expanduser().resolve()
        with (archive / "Info.plist").open("rb") as source:
            properties = plistlib.load(source)["ApplicationProperties"]
        if properties["CFBundleIdentifier"] != config["bundle_id"]:
            raise ValueError("Archive bundle identifier does not match the configured app")
        if properties.get("Team") != config["team_id"]:
            raise ValueError("Archive signing team does not match the configured team")
        version = properties["CFBundleShortVersionString"]
        build = properties["CFBundleVersion"]
    except (OSError, ValueError, KeyError, TypeError, plistlib.InvalidFileException) as error:
        parser.error(str(error))

    export_path = (args.export_path or archive.parent / "upload").expanduser().resolve()
    options = {
        "method": "app-store-connect",
        "destination": "upload",
        "teamID": config["team_id"],
        "signingStyle": "automatic",
        "manageAppVersionAndBuildNumber": False,
        "uploadSymbols": True,
        "iCloudContainerEnvironment": "Production",
    }
    # The private key is read by Xcode; its contents never enter arguments or Git.
    with tempfile.TemporaryDirectory(prefix="savour-testflight-") as directory:
        options_path = Path(directory) / "UploadOptions.plist"
        options_path.write_bytes(plistlib.dumps(options))
        command = [
            "xcodebuild", "-exportArchive", "-archivePath", str(archive),
            "-exportPath", str(export_path), "-exportOptionsPlist", str(options_path),
            "-allowProvisioningUpdates", "-authenticationKeyPath", str(key_path),
            "-authenticationKeyID", config["key_id"],
            "-authenticationKeyIssuerID", config["issuer_id"],
        ]
        print(f"Savour {version} ({build}) — {config['bundle_id']}", flush=True)
        if args.dry_run:
            print(shlex.join(command))
            return 0
        return subprocess.run(command, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
