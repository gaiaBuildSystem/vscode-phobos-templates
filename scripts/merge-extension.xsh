#!/usr/bin/env xonsh

# Copyright (c) 2025 Toradex
# SPDX-License-Identifier: MIT

##
# This script is used to merge an application extension to a custom.yaml
# opus configuration file.
##

# use the xonsh environment to update the OS environment
$UPDATE_OS_ENVIRON = True
# Get the full log of error
$XONSH_SHOW_TRACEBACK = True
# always return if a cmd fails
$XONSH_SUBPROC_CMD_RAISE_ERROR = True

import os
import json
from ruamel.yaml import YAML
from torizon_templates_utils.args import get_arg_not_empty
from torizon_templates_utils.colors import Color,BgColor,print
from torizon_templates_utils.errors import Error,Error_Out

# Initialize YAML with round-trip mode to preserve comments
yaml = YAML()
yaml.preserve_quotes = True
yaml.default_flow_style = False

_extension_name = get_arg_not_empty(1)

# load the extension configuration
_extension_path = f"{os.environ['HOME']}/.apollox/scripts/extensions/{_extension_name}/{_extension_name}.yaml"
if os.path.exists(_extension_path):
    with open(_extension_path, "r") as _ext_file:
        _ext_config = yaml.load(_ext_file)
else:
    Error_Out(
        f"Extension configuration file {_extension_path} not found.",
        Error.EINVAL
    )


# helper function for deep merging
def deep_merge(original, new):
    """Recursively merge new into original, preserving original values"""
    if isinstance(original, dict) and isinstance(new, dict):
        result = dict(original)
        for key, new_value in new.items():
            if key in result:
                result[key] = deep_merge(result[key], new_value)
            else:
                result[key] = new_value
        return result
    elif isinstance(original, list) and isinstance(new, list):
        # Preserve original list items and add new ones that aren't already there
        result = list(original)
        for item in new:
            if item not in result:
                result.append(item)
        return result
    else:
        # For scalar values, new value overwrites
        return new


# custom.yaml
if os.path.exists("custom.yaml"):
    print("Applying to custom.yaml ...")

    with open("custom.yaml", "r") as _custom_yaml:
        _yaml_obj = yaml.load(_custom_yaml)

    # now that we have the two, merge it
    for section in _ext_config:
        if section in _yaml_obj:
            _yaml_obj[section] = deep_merge(_yaml_obj[section], _ext_config[section])
        else:
            # add the new section
            _yaml_obj[section] = _ext_config[section]

    # write back the merged configuration
    with open("custom.yaml", "w") as _custom_yaml:
        yaml.dump(_yaml_obj, _custom_yaml)

    print(
        f"✅ custom.yaml updated successfully with extension '{_extension_name}'",
        color=Color.GREEN
    )

    # also we need to copy the extension files
    _extension_files_path = f"{os.environ['HOME']}/.apollox/scripts/extensions/{_extension_name}"
    if os.path.exists(_extension_files_path):
        print("Copying extension files ...")
        cp -r @(f"{_extension_files_path}") .

        print(
            f"✅ Extension files from '{_extension_name}' copied successfully.",
            color=Color.GREEN
        )
    else:
        Error_Out(
            f"No extension files found to copy for '{_extension_name}'",
            Error.ENOENT
        )
else:
    Error_Out(
        "custom.yaml file not found in the current directory.",
        Error.ENOENT
    )
