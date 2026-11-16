import * as fs from "fs";
import { exit } from "process";
import { RemoteShellCommand } from "apollox";
import { withTimeout, fail } from "./utils.mjs";

const args = process.argv.slice(2);

async function main() {
    const _ip = args[0];
    const _login = args[1];
    const _password = args[2];

    // get the hash of ostree deployment
    const _hash = await withTimeout(RemoteShellCommand.getOSTreeDeploymentHash(
        {
            Description: "",
            Hostname: _ip,
            Ip: _ip,
            SshPort: 22
        },
        _password,
        _login
    ), "the ostree deployment hash (is this a Torizon OS device?)");

    if (_hash == null || _hash.trim() === "") {
        fail("Could not detect the ostree deployment hash of the target device");
    }

    // get the list of overlays
    const overlays = await withTimeout(RemoteShellCommand.getDeviceTreeOverlayList(
        {
            Description: "",
            Hostname: _ip,
            Ip: _ip,
            SshPort: 22
        },
        _password,
        _login,
        _hash
    ), "the device tree overlay list");

    console.log(JSON.stringify(overlays));
    exit(0);
}

main().catch((err) => fail(err.message ?? String(err)));
