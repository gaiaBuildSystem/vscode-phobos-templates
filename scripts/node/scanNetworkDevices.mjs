#!/usr/bin/env node

import { DeviceDetection } from "apollox";
import { writeFile } from "fs/promises";

const SCAN_FILE = `${process.env.HOME}/.tcd/scan.json`;

// devices found so far, so the user can stop the scan at any time and still
// get what was already listed
const found = [];
let finishing = false;

async function finish(nets) {
    if (finishing) return;
    finishing = true;

    if (process.stdin.isTTY) {
        process.stdin.setRawMode(false);
    }
    process.stdin.pause();

    // save the nets as json at the /home/user/.tcd/scan.json
    await writeFile(SCAN_FILE, JSON.stringify(nets, null, 2));

    // the discovery sockets/timers may still be alive if the user stopped it
    process.exit(0);
}

function listenForStop() {
    if (process.stdin.isTTY) {
        // raw mode: read single keys and also receive Ctrl+C as a key instead
        // of a SIGINT (that would also hit the parent xonsh and abort it)
        process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.on("data", (key) => {
            const k = key.toString();
            // Enter, q/Q, Esc or Ctrl+C stop the scan
            if (k === "\r" || k === "\n" || k === "q" || k === "Q" ||
                k === "\x1b" || k === "\x03") {
                finish(found);
            }
        });
    } else {
        process.on("SIGINT", () => finish(found));
    }
}

async function main() {
    var ix = 0;
    // disable console.log
    const _clTmp = console.log;
    console.log = function() {};

    listenForStop();

    // show the devices found in async mode
    const nets = await DeviceDetection.GetPhobOSDevices((dev) => {
        found.push(dev);

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

    await finish(nets);
}

main();
