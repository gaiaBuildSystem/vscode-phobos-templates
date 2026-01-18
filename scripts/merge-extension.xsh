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
$RAISE_SUBPROC_ERROR = True

import os
import json
import yaml
from torizon_templates_utils.args import get_arg_not_empty
from torizon_templates_utils.colors import Color,BgColor,print
from torizon_templates_utils.errors import Error,Error_Out

_extension_name = get_arg_not_empty(1)

# load the extension configuration
_extension_path = f"${os.environ['HOME']}/.apollox/scripts/extensions/${_extension_name}"
if os.path.exists(_extension_path):
    with open(_extension_path, "r") as _ext_file:
        _ext_config = yaml.safe_load(_ext_file)
else:
    Error_Out(
        f"Extension configuration file extensions/{_extension_name}/extension.json not found.",
        Error.EINVAL
    )


# custom.yaml
if os.path.exists("custom.yaml"):
    print("Applying to custom.yaml ...")

    with open("custom.yaml", "r") as _custom_yaml:
        _yaml_obj = yaml.safe_load(_custom_yaml)

# now that we have the two
# merge it
    for section in _ext_config:
        if section in _yaml_obj:
            if isinstance(_yaml_obj[section], list):
                # append the new items to the list
                _yaml_obj[section].extend(_ext_config[section])
            elif isinstance(_yaml_obj[section], dict):
                # merge the dictionaries
                _yaml_obj[section].update(_ext_config[section])
            else:
                # unsupported type
                Error_Out(
                    f"Unsupported type for section '{section}' in custom.yaml.",
                    Error.EINVAL
                )
        else:
            # add the new section
            _yaml_obj[section] = _ext_config[section]

    # write back the merged configuration
    with open("custom.yaml", "w") as _custom_yaml:
        yaml.dump(_yaml_obj, _custom_yaml, default_flow_style=False)

    print(
        f"✅ custom.yaml updated successfully with extension '{_extension_name}'",
        color=Color.GREEN
    )
else:
    Error_Out(
        "custom.yaml file not found in the current directory.",
        Error.ENOENT
    )
