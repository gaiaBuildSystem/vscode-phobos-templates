#!/usr/bin/env node

import { DeviceDetection } from "apollox";
import { writeFile } from "fs/promises";

async function main() {
    var ix = 0;
    // disable console.log
    const _clTmp = console.log;
    console.log = function() {};

    // show the devices found in async mode
    const nets = await DeviceDetection.GetPhobOSDevices((dev) => {
        // the wait animation keeps redrawing the line where the cursor is,
        // so walk down below the devices already listed, print the new one
        // and walk back up, keeping the animation pinned on its line.
        // \n (instead of cursor down) is used so the terminal scrolls if needed
        const down = ix + 1;
        process.stdout.write(
            `${"\n".repeat(down)}\r\x1b[2K\t\t ${ix} ➡️  ${dev.Description}\x1b[${down}A\r`
        );
        ix++;
    });

    // enable console.log
    console.log = _clTmp;

    // save the nets as json at the /home/user/.tcd/scan.json
    await writeFile(
        `${process.env.HOME}/.tcd/scan.json`,
        JSON.stringify(nets, null, 2)
    );
}

main();
