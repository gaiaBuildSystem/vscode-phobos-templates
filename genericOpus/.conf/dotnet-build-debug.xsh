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
from torizon_templates_utils.args import get_arg_not_empty
from torizon_templates_utils.colors import Color,BgColor,print
from torizon_templates_utils.errors import Error,Error_Out

_TORIZON_ARCHS = [
    "arm64",
    "aarch64",
    "armhf",
    "amd64"
]

_torizon_to_dotnet_map = {
    "arm64": "linux-arm64",
    "aarch64": "linux-arm64",
    "armhf": "linux-arm",
    "amd64": "linux-x64"
}

_torizon_arch = get_arg_not_empty(1)
_csproj_path = get_arg_not_empty(2)

if _torizon_arch not in _TORIZON_ARCHS:
    Error_Out(
        f"Undefined target architecture: {_torizon_arch}.",
        Error.EUSER
    )

dotnet \
    publish @(_csproj_path) \
    /property:GenerateFullPaths=true \
    -c Debug \
    -r @(_torizon_to_dotnet_map[_torizon_arch]) \
    --self-contained
