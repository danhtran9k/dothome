import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const SESSION_INFO_PATH = path.join(__dirname, "..", "session.log.txt");
const CACHE_DURATION_MS = 5 * 60 * 1000; // 5 minutes in milliseconds

/**
 * Writes key-value pairs to the session file, overwriting existing entries with the same keys.
 * @param {Array<[string, string]>} entries - Array of [key, value] pairs to write.
 * @returns {void}
 */
export function writeSessionEntry(entries) {
  let sessionContent = "";
  if (fs.existsSync(SESSION_INFO_PATH)) {
    sessionContent = fs.readFileSync(SESSION_INFO_PATH, "utf8");
  }

  const lines = sessionContent.split("\n").filter((line) => line.trim());
  let filteredLines = lines;

  for (const [key, value] of entries) {
    filteredLines = filteredLines.filter((line) => !line.startsWith(`${key}=`));
    filteredLines.push(`${key}=${value}`);
  }

  fs.writeFileSync(SESSION_INFO_PATH, filteredLines.join("\n") + "\n");
}

export const cache = {
  /**
   * Reads the last update timestamp from session info file.
   * @returns {number | null} Last update timestamp in milliseconds, or null if not found.
   */
  getLastUpdate() {
    if (!fs.existsSync(SESSION_INFO_PATH)) {
      return null;
    }
    const content = fs.readFileSync(SESSION_INFO_PATH, "utf8");
    const match = content.match(/GLM_LAST_UPDATE=(\d+)/);
    if (!match) return null;
    const timestamp = parseInt(match[1], 10);
    return isNaN(timestamp) ? null : timestamp;
  },

  setLastUpdate() {
    const now = Date.now();
    writeSessionEntry([["GLM_LAST_UPDATE", String(now)]]);
  },

  isFresh() {
    const lastUpdate = this.getLastUpdate();
    if (lastUpdate === null) {
      return false;
    }
    const now = Date.now();
    return now - lastUpdate < CACHE_DURATION_MS;
  },
};
