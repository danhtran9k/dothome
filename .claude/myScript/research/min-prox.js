#!/usr/bin/env node

import { execSync } from "child_process";
import fs from "fs";
import path from "path";
import os from "os";
import readline from "readline";

// Default models — used as fallback if server is unreachable
const DEFAULT_MODELS = {
  opus: "claude-opus-4-6",
  sonnet: "claude-sonnet-4-6",
  haiku: "claude-haiku-4-5-20251001"
};

async function fetchModelsFromServer() {
  try {
    console.log("🔄 Fetching latest model config from server...");
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000); // 5s timeout

    const res = await fetch("https://pro-x.io.vn/api/config", {
      signal: controller.signal
    });
    clearTimeout(timeout);

    if (!res.ok) throw new Error(`Server returned ${res.status}`);

    const data = await res.json();

    if (
      data.models &&
      data.models.opus &&
      data.models.sonnet &&
      data.models.haiku
    ) {
      console.log("✅ Got latest models from server");
      return data.models;
    }
    throw new Error("Invalid config format");
  } catch (error) {
    console.warn("⚠️  Could not fetch config from server:", error.message);
    console.log("📋 Using default model config");
    return DEFAULT_MODELS;
  }
}

function getProXConfig(authToken, models) {
  return {
    env: {
      ANTHROPIC_AUTH_TOKEN: authToken,
      ANTHROPIC_BASE_URL: "https://pro-x.io.vn/",
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
      ANTHROPIC_DEFAULT_OPUS_MODEL: models.opus,
      ANTHROPIC_DEFAULT_SONNET_MODEL: models.sonnet,
      ANTHROPIC_DEFAULT_HAIKU_MODEL: models.haiku,
      CLAUDE_CODE_SUBAGENT_MODEL: models.sonnet,
      CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS: "0",
      API_TIMEOUT_MS: "3000000"
    },
    permissions: {
      allow: [],
      deny: []
    },
    skipDangerousModePermissionPrompt: true,
    model: "opus"
  };
}

function getConfigPath() {
  const homeDir = os.homedir();
  const configDir = path.join(homeDir, ".claude");
  return path.join(configDir, "settings.json");
}

function promptAuthToken() {
  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });

    rl.question("🔑 Nhập Auth Token của bạn: ", (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

function detectOS() {
  const platform = os.platform();
  if (platform === "win32") return "windows";
  if (platform === "darwin") return "macos";
  return "linux";
}

function ensureConfigDir() {
  const homeDir = os.homedir();
  const configDir = path.join(homeDir, ".claude");
  if (!fs.existsSync(configDir)) {
    fs.mkdirSync(configDir, { recursive: true });
  }
}

function updateConfig(authToken, models) {
  console.log("⚙️  Updating configuration...");

  ensureConfigDir();
  const configPath = getConfigPath();

  let existingConfig = {};
  if (fs.existsSync(configPath)) {
    try {
      existingConfig = JSON.parse(fs.readFileSync(configPath, "utf8"));
    } catch (error) {
      console.warn("⚠️  Could not parse existing config, will overwrite");
    }
  }

  const proxConfig = getProXConfig(authToken, models);
  const mergedConfig = {
    ...existingConfig,
    ...proxConfig,
    env: {
      ...existingConfig.env,
      ...proxConfig.env
    }
  };

  // Xóa ANTHROPIC_API_KEY nếu có để tránh conflict với ANTHROPIC_AUTH_TOKEN
  if (mergedConfig.env) delete mergedConfig.env.ANTHROPIC_API_KEY;

  fs.writeFileSync(configPath, JSON.stringify(mergedConfig, null, 2));
  console.log("✅ Configuration updated at:", configPath);
}

async function setEnvCommand(osType, authToken) {
  console.log("\n🔧 Thiết lập biến môi trường vĩnh viễn...");

  try {
    if (osType === "windows") {
      // Chạy PowerShell để thiết lập biến môi trường
      const ps1 = `
        [System.Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', $null, 'User');
        [System.Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', '${authToken}', 'User');
        [System.Environment]::SetEnvironmentVariable('ANTHROPIC_BASE_URL', 'https://pro-x.io.vn/', 'User');
        Write-Host '✅ Đã thiết lập biến môi trường'
      `;
      execSync(`powershell -Command "${ps1.replace(/\n/g, " ")}"`, {
        shell: true
      });
    } else if (osType === "macos") {
      const home = os.homedir();
      const rcFiles = [".zshrc", ".bash_profile", ".profile"].map((f) =>
        path.join(home, f)
      );
      const tokenLine = `export ANTHROPIC_AUTH_TOKEN="${authToken}"`;
      const urlLine = `export ANTHROPIC_BASE_URL="https://pro-x.io.vn/"`;

      // Xóa cả ANTHROPIC_API_KEY và ANTHROPIC_AUTH_TOKEN khỏi tất cả rc files
      for (const f of rcFiles) {
        execSync(`sed -i '' '/ANTHROPIC_API_KEY/d' ${f} 2>/dev/null || true`, {
          shell: true
        });
        execSync(
          `sed -i '' '/ANTHROPIC_AUTH_TOKEN/d' ${f} 2>/dev/null || true`,
          { shell: true }
        );
        execSync(`sed -i '' '/ANTHROPIC_BASE_URL/d' ${f} 2>/dev/null || true`, {
          shell: true
        });
      }
      // Chỉ ghi vào .zshrc
      execSync(`echo '${tokenLine}' >> ${rcFiles[0]}`, { shell: true });
      execSync(`echo '${urlLine}' >> ${rcFiles[0]}`, { shell: true });
    } else if (osType === "linux") {
      const home = os.homedir();
      const rcFiles = [".bashrc", ".bash_profile", ".profile"].map((f) =>
        path.join(home, f)
      );
      const tokenLine = `export ANTHROPIC_AUTH_TOKEN="${authToken}"`;
      const urlLine = `export ANTHROPIC_BASE_URL="https://pro-x.io.vn/"`;

      // Xóa cả ANTHROPIC_API_KEY và ANTHROPIC_AUTH_TOKEN khỏi tất cả rc files
      for (const f of rcFiles) {
        execSync(`sed -i '/ANTHROPIC_API_KEY/d' ${f} 2>/dev/null || true`, {
          shell: true
        });
        execSync(`sed -i '/ANTHROPIC_AUTH_TOKEN/d' ${f} 2>/dev/null || true`, {
          shell: true
        });
        execSync(`sed -i '/ANTHROPIC_BASE_URL/d' ${f} 2>/dev/null || true`, {
          shell: true
        });
      }
      // Chỉ ghi vào .bashrc
      execSync(`echo '${tokenLine}' >> ${rcFiles[0]}`, { shell: true });
      execSync(`echo '${urlLine}' >> ${rcFiles[0]}`, { shell: true });
    }
    console.log("✅ Thiết lập biến môi trường thành công!");
    if (osType !== "windows") {
      console.log(
        "💡 Vui lòng khởi động lại Terminal hoặc chạy: source ~/.zshrc (macOS) / source ~/.bashrc (Linux)"
      );
    }
  } catch (error) {
    console.warn(
      "⚠️  Không thể thiết lập biến môi trường tự động:",
      error.message
    );
    console.log("💡 Bạn cần chạy thủ công với quyền Administrator");
  }
}

function removeProXConfig() {
  console.log("⚙️  Removing Pro-X configuration...");
  const configPath = getConfigPath();

  if (!fs.existsSync(configPath)) {
    console.log("ℹ️  No config file found, skipping");
    return;
  }

  try {
    const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
    const proxEnvKeys = [
      "ANTHROPIC_AUTH_TOKEN",
      "ANTHROPIC_API_KEY",
      "ANTHROPIC_BASE_URL",
      "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
      "ANTHROPIC_DEFAULT_OPUS_MODEL",
      "ANTHROPIC_DEFAULT_SONNET_MODEL",
      "ANTHROPIC_DEFAULT_HAIKU_MODEL",
      "CLAUDE_CODE_SUBAGENT_MODEL",
      "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS",
      "API_TIMEOUT_MS"
    ];

    if (config.env) {
      proxEnvKeys.forEach((key) => delete config.env[key]);
      if (Object.keys(config.env).length === 0) delete config.env;
    }
    delete config.permissions;
    delete config.skipDangerousModePermissionPrompt;
    delete config.model;

    if (Object.keys(config).length === 0) {
      fs.unlinkSync(configPath);
      console.log("✅ Config file removed");
    } else {
      fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
      console.log("✅ Pro-X config removed, other settings preserved");
    }
  } catch (error) {
    console.warn("⚠️  Could not update config:", error.message);
  }
}

async function removeEnvVars(osType) {
  console.log("🔧 Xóa biến môi trường...");
  try {
    if (osType === "windows") {
      const ps1 = `
        [System.Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', $null, 'User');
        [System.Environment]::SetEnvironmentVariable('ANTHROPIC_BASE_URL', $null, 'User');
        Write-Host '✅ Đã xóa biến môi trường'
      `;
      execSync(`powershell -Command "${ps1.replace(/\n/g, " ")}"`, {
        shell: true
      });
    } else if (osType === "macos") {
      const rcFiles = [".zshrc", ".bash_profile", ".profile"].map((f) =>
        path.join(os.homedir(), f)
      );
      for (const f of rcFiles) {
        execSync(`sed -i '' '/ANTHROPIC_API_KEY/d' ${f} 2>/dev/null || true`, {
          shell: true
        });
        execSync(
          `sed -i '' '/ANTHROPIC_AUTH_TOKEN/d' ${f} 2>/dev/null || true`,
          { shell: true }
        );
        execSync(`sed -i '' '/ANTHROPIC_BASE_URL/d' ${f} 2>/dev/null || true`, {
          shell: true
        });
      }
      console.log("💡 Khởi động lại Terminal hoặc chạy: source ~/.zshrc");
    } else if (osType === "linux") {
      const rcFiles = [".bashrc", ".bash_profile", ".profile"].map((f) =>
        path.join(os.homedir(), f)
      );
      for (const f of rcFiles) {
        execSync(`sed -i '/ANTHROPIC_API_KEY/d' ${f} 2>/dev/null || true`, {
          shell: true
        });
        execSync(`sed -i '/ANTHROPIC_AUTH_TOKEN/d' ${f} 2>/dev/null || true`, {
          shell: true
        });
        execSync(`sed -i '/ANTHROPIC_BASE_URL/d' ${f} 2>/dev/null || true`, {
          shell: true
        });
      }
      console.log("💡 Khởi động lại Terminal hoặc chạy: source ~/.bashrc");
    }
    console.log("✅ Đã xóa biến môi trường");
  } catch (error) {
    console.warn("⚠️  Không thể xóa biến môi trường tự động:", error.message);
  }
}

async function uninstall() {
  console.log("🗑️  Pro-X Claude Uninstaller");

  const osType = detectOS();

  removeProXConfig();
  await removeEnvVars(osType);

  console.log("✨ Gỡ cài đặt hoàn tất!");
}

async function main() {
  const command = process.argv[2];

  if (command === "uninstall") {
    await uninstall();
    return;
  }

  console.log("🚀 Pro-X Claude Setup");

  const authToken = await promptAuthToken();

  if (!authToken) {
    console.error("❌ Auth Token is required");
    process.exit(1);
  }

  const models = await fetchModelsFromServer();

  // updateConfig(authToken, models);
  // await setEnvCommand(detectOS(), authToken);
  console.log("✨ Setup complete!");
}

main();
