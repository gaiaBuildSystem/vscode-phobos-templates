import { exit } from "process";

// default time to wait for a remote command before giving up
export const REMOTE_TIMEOUT_MS = 20000;

/**
 * Race a promise against a timeout. Some of the apollox remote calls only
 * settle when the remote command writes something to stdout, so if the
 * command outputs nothing they hang forever. This makes them fail instead.
 */
export function withTimeout(promise, what, ms = REMOTE_TIMEOUT_MS) {
    let timer;
    const timeout = new Promise((_, reject) => {
        timer = setTimeout(
            () => reject(new Error(`timeout after ${ms / 1000}s waiting for ${what}`)),
            ms
        );
    });

    return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

export function fail(msg) {
    console.error(msg);
    exit(1);
}
