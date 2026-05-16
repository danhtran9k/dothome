import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { writeSessionEntry, cache } from "./session-manager.js";
import { debugLog, debugQuota } from "./status-debug.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const ZAI_QUOTA_QUERY_URL = "https://api.z.ai/api/monitor/usage/quota/limit";
const GLM_JSON_PATH = path.join(__dirname, "..", "env.glm.json");

/**
 * Reads env.glm.json and extracts authentication credentials.
 * @returns {{ key: string, token: string } | null} Object with key and token, or null if file doesn't exist/invalid.
 */
function readAuth() {
  if (!fs.existsSync(GLM_JSON_PATH)) {
    return null;
  }

  const glmContent = fs.readFileSync(GLM_JSON_PATH, "utf8");
  const glmConfig = JSON.parse(glmContent);
  const authToken = glmConfig?.env?.ANTHROPIC_AUTH_TOKEN;

  return authToken ?? null;
}

/**
 * @param {string} token - Second part of the auth token.
 * @returns {{ nextResetTime: number, percentage: number } | null}
 */
async function fetchQuota(token) {
  const response = await fetch(ZAI_QUOTA_QUERY_URL, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${token}`
    }
  });

  if (!response.ok) return null;

  const data = await response.json();
  const tokensLimit = data?.data?.limits?.find(
    (limit) => limit.type === "TOKENS_LIMIT"
  );

  if (!tokensLimit) return null;

  return {
    nextResetTime: tokensLimit?.nextResetTime ?? 0,
    percentage: tokensLimit?.percentage ?? 0
  };
}

/**
 * Appends or overwrites GLM_REFRESH and GLM_USED
 * @param {string} refreshTime - Time formatted as "hh:mm".
 * @param {number} percentage - Usage percentage value.
 * @returns {void}
 */
function saveToFile(refreshTime, percentage) {
  writeSessionEntry([
    ["GLM_REFRESH", refreshTime],
    ["GLM_USED", String(percentage)]
  ]);
}

/**
 * Main function to fetch GLM quota info and update session file.
 * @param {boolean} isForce - If true, bypass cache and force fetch. Defaults to false.
 * @returns {{ refreshTime: string, percentage: number } | null} Result object with refreshTime and percentage, or null on error.
 */
async function getGlm(isForce = false) {
  try {
    if (!isForce && cache.isFresh()) {
      debugLog("Cache fresh: " + cache.isFresh());
      return null;
    }

    const token = readAuth();
    if (!token) return null;

    const quota = await fetchQuota(token);
    if (!quota) return null;

    debugQuota(quota);

    const nextResetTime = quota.nextResetTime;
    const percentage = quota.percentage;
    saveToFile(String(nextResetTime), percentage);

    cache.setLastUpdate();

    return {
      nextResetTime,
      percentage
    };
  } catch (error) {
    console.error("Error:", error);
    return null;
  }
}

const isForce = process.argv.includes("--force");
getGlm(isForce);
