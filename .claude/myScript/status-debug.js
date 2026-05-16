import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { cache } from "./session-manager.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const DEBUG_LOG_PATH = path.join(__dirname, ".", "getGlm.dump.log");

export function debugLog(message) {
  const now = new Date();
  const hh = String(now.getHours()).padStart(2, "0");
  const mm = String(now.getMinutes()).padStart(2, "0");
  const ss = String(now.getSeconds()).padStart(2, "0");
  const ms = String(now.getMilliseconds()).padStart(3, "0");
  const timestamp = `${hh}:${mm}:${ss}.${ms}`;
  fs.appendFileSync(DEBUG_LOG_PATH, `[${timestamp}] ${message}\n`);
}

export function debugQuota(quota) {
  const lastUpdate = cache.getLastUpdate();
  let delta = 0;
  if (lastUpdate !== null) {
    const now = Date.now();
    const secondsSinceLastUpdate = Math.ceil((now - lastUpdate) / 1000);
    delta = Math.ceil(secondsSinceLastUpdate / 60);
  }
  debugLog("quota: " + JSON.stringify({ ...quota, delta }));
}
