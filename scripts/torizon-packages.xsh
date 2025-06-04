#!/usr/bin/env xonsh

# Copyright (c) 2025 Toradex
# SPDX-License-Identifier: MIT

##
# This script is used to apply the Debian packages that was set in the
# torizon-packages.json file. This is useful to define the packages once
# and apply then for the right target architecture on the multiple Dockerfile
##

# use the xonsh environment to update the OS environment
$UPDATE_OS_ENVIRON = True
# Get the full log of error
$XONSH_SHOW_TRACEBACK = True
# always return if a cmd fails
$RAISE_SUBPROC_ERROR = True

import os
import json
import yaml
from torizon_templates_utils.args import get_arg_not_empty
from torizon_templates_utils.colors import Color,BgColor,print
from torizon_templates_utils.errors import Error,Error_Out

_TORIZON_ARCHS = [
    "arm64",
    "aarch64",
    "armhf",
    "amd64",
    "riscv"
]

_torizon_arch = get_arg_not_empty(1)

if _torizon_arch not in _TORIZON_ARCHS:
    Error_Out(
        f"Undefined target architecture: {_torizon_arch}.",
        Error.EUSER
    )


def _add_dep_string(value):
    # If the arch of the package has been explicitly specified, don't add the target arch in the end
    if ":" in value:
        return f"    {value} \\\n"
    else:
        # There are certain packages which have "all" as architecture
        value_arch = $(apt-cache show @(value) | sed -n '/^Architecture:/ {s/^Architecture: //; p; q}')
        if value_arch.strip() == "all":
            return f"    {value}:all \\\n"
        else:
            return f"    {value}:{_torizon_arch} \\\n"


def _replace_section(file_lines, section):
    start_ix = None
    end_ix = None
    new_file_content = []

    for ix, line in enumerate(file_lines):
        if f"__{section}_start__" in line:
            start_ix = ix
        if f"__{section}_end__" in line:
            end_ix = ix

    stop_add = False

    for ix, line in enumerate(file_lines):
        if ix == start_ix:
            new_file_content.append(line)
            stop_add = True

            with open("torizonPackages.json") as f:
                json_data = json.load(f)

            build_packs = json_data.get("buildDeps", [])

            if "devRuntimeDeps" in json_data:
                dev_packs = json_data["devRuntimeDeps"]
            else:
                dev_packs = json_data.get("devDeps", [])

            if "prodRuntimeDeps" in json_data:
                prod_packs = json_data["prodRuntimeDeps"]
            else:
                prod_packs = json_data.get("deps", [])

            if "build" in section:
                for pack in build_packs:
                    new_file_content.append(_add_dep_string(pack))
            elif "dev" in section:
                for pack in dev_packs:
                    new_file_content.append(_add_dep_string(pack))
            elif "prod" in section:
                for pack in prod_packs:
                    new_file_content.append(_add_dep_string(pack))

        if ix == end_ix:
            stop_add = False

        if not stop_add:
            new_file_content.append(line)

    return new_file_content

print("Applying torizonPackages.json: ")

# Dockerfile.debug
if os.path.exists("Dockerfile.debug"):
    print("Applying to Dockerfile.debug ...")

    _dockerfile_debug = open("Dockerfile.debug", "r")
    _dockerfile_debug_lines = _dockerfile_debug.readlines()
    _dockerfile_debug.close()

    _dockerfile_debug_lines = _replace_section(
        _dockerfile_debug_lines,
        "torizon_packages_dev"
    )

    # write back to the file
    _dockerfile_debug = open("Dockerfile.debug", "w")
    _dockerfile_debug.write("".join(_dockerfile_debug_lines))
    _dockerfile_debug.close()

    print("✅ Dockerfile.debug", color=Color.GREEN)

# Dockerfile.sdk
if os.path.exists("Dockerfile.sdk"):
    print("Applying to Dockerfile.sdk ...")

    _dockerfile_sdk = open("Dockerfile.sdk", "r")
    _dockerfile_sdk_lines = _dockerfile_sdk.readlines()
    _dockerfile_sdk.close()

    _dockerfile_sdk_lines = _replace_section(
        _dockerfile_sdk_lines,
        "torizon_packages_build"
    )

    # write back to the file
    _dockerfile_sdk = open("Dockerfile.sdk", "w")
    _dockerfile_sdk.write("".join(_dockerfile_sdk_lines))
    _dockerfile_sdk.close()

    print("✅ Dockerfile.sdk", color=Color.GREEN)

# Dockerfile
if os.path.exists("Dockerfile"):
    # All project templates has a Dockerfile
    print("Applying to Dockerfile ...")

    _dockerfile_ = open("Dockerfile", "r")
    _dockerfile_lines = _dockerfile_.readlines()
    _dockerfile_.close()

    # Dockerfile can have multi-stage for build
    _dockerfile_lines = _replace_section(
        _dockerfile_lines,
        "torizon_packages_prod"
    )

    _dockerfile_lines = _replace_section(
        _dockerfile_lines,
        "torizon_packages_build"
    )

    # write back to the file
    _dockerfile_ = open("Dockerfile", "w")
    _dockerfile_.write("".join(_dockerfile_lines))
    _dockerfile_.close()

    print("✅ Dockerfile", color=Color.GREEN)



class CustomArrayDumper(yaml.Dumper):
    """
    Custom YAML Dumper to handle arrays with a specific format.
    """
    def increase_indent(self, flow=False, *args, **kwargs):
        return super().increase_indent(flow=flow, indentless=False)


# custom.yaml
if os.path.exists("custom.yaml"):
    print("Applying to custom.yaml ...")

    with open("custom.yaml", "r") as _custom_yaml:
        _yaml_obj = yaml.safe_load(_custom_yaml)

    _phobos_ip = os.environ.get("PHOBOS_IP", "0.0.0.0")
    _phobos_port = os.environ.get("PHOBOS_PORT", "22")

    # update the data on the image.debug.device.ip
    if "image" in _yaml_obj and "debug" in _yaml_obj["image"]:
        _yaml_obj["image"]["debug"]["device"]["ip"] = _phobos_ip

    # update the data on the image.debug.device.port
    if "image" in _yaml_obj and "debug" in _yaml_obj["image"]:
        _yaml_obj["image"]["debug"]["device"]["port"] = int(_phobos_port)

    # update the image.apt.install
    if "image" in _yaml_obj:
        with open("torizonPackages.json") as f:
            json_data = json.load(f)

        build_packs = json_data.get("buildDeps", [])
        dev_packs = json_data.get("devRuntimeDeps", [])
        prod_packs = json_data.get("prodRuntimeDeps", [])

        if "apt" in _yaml_obj["image"]:
            if "install" in _yaml_obj["image"]["apt"] and len(build_packs) > 0:
                _yaml_obj["image"]["apt"]["install"] = []

            if "install_debug" in _yaml_obj["image"]["apt"] and len(dev_packs) > 0:
                _yaml_obj["image"]["apt"]["install_debug"] = []

        # if there is no apt key added it
        if "apt" not in _yaml_obj["image"]:
            _yaml_obj["image"]["apt"] = {
                "install": [],
                "install_debug": []
            }

        # add the packages to the apt.install
        for pack in build_packs:
            _yaml_obj["image"]["apt"]["install"].append(pack)

        for pack in dev_packs:
            _yaml_obj["image"]["apt"]["install_debug"].append(pack)


    # now try to get the MARS_OSTREE_REPO_BRANCH
    _phobos_machine = $(
        ssh -p @(f"{_phobos_port}") \
            -o UserKnownHostsFile=/dev/null \
            -o StrictHostKeyChecking=no \
            -o LogLevel=ERROR \
            @(f"root@{_phobos_ip}") \
            "echo $MARS_OSTREE_REPO_BRANCH"
    )

    if _phobos_machine != "":
        # update the data on the image.machine
        if "image" in _yaml_obj:
            _yaml_obj["image"]["machine"] = _phobos_machine
    else:
        Error_Out(
            f"❌ Error: Unable to get the MARS_OSTREE_REPO_BRANCH from the phobos machine at {_phobos_ip}:{_phobos_port}",
            Error.EABORT
        )

    # write back to the file
    with open("custom.yaml", "w") as _custom_yaml:
        yaml.dump(
            _yaml_obj,
            _custom_yaml,
            indent=2,
            sort_keys=False,
            default_flow_style=False,
            allow_unicode=True,
            Dumper=CustomArrayDumper
        )


    print("✅ custom.yaml", color=Color.GREEN)


print("torizonPackages.json applied")
