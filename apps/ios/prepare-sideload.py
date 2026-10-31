#!/usr/bin/env python3
"""Generate an unsigned, model-free personal build; leave upstream CI spec intact."""
from pathlib import Path
import plistlib
import yaml

APP = Path(__file__).resolve().parent / "OuraApp"


def main():
    project = yaml.safe_load((APP / "project-ci.yml").read_text())
    settings = project["settings"]["base"]
    settings["PRODUCT_BUNDLE_IDENTIFIER"] = "org.hatemaljandali.openhealth"
    settings["DEVELOPMENT_TEAM"] = ""
    settings["CODE_SIGNING_ALLOWED"] = False
    settings["CODE_SIGNING_REQUIRED"] = False
    settings.pop("CODE_SIGN_ENTITLEMENTS", None)
    target_settings = project["targets"]["OuraApp"]["settings"]["base"]
    target_settings["INFOPLIST_FILE"] = "Info-sideload.plist"

    with (APP / "Info.plist").open("rb") as source:
        info = plistlib.load(source)
    info["CFBundleDisplayName"] = "Open Health"
    info["CFBundleName"] = "Open Health"
    info["OpenOuraHealthExportDisabled"] = True
    info.pop("NSHealthShareUsageDescription", None)
    info.pop("NSHealthUpdateUsageDescription", None)
    with (APP / "Info-sideload.plist").open("wb") as output:
        plistlib.dump(info, output)
    (APP / "project-sideload.yml").write_text(yaml.safe_dump(project, sort_keys=False))
    print("Generated model-free sideload project for org.hatemaljandali.openhealth")


if __name__ == "__main__":
    main()
