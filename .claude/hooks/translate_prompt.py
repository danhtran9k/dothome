#!/usr/bin/env python3
"""
UserPromptSubmit hook: Translate Vietnamese prompts to English for Claude,
show other language translations on stderr for language learning reference.

- Original Vietnamese prompt: replaced by English (never reaches Claude's context)
- Other languages: printed to stderr + logged to ~/.claude/translation_log.md
"""

import sys
import json
import re
import os
import urllib.request
from datetime import datetime

# Force UTF-8 output — needed on Windows (cp1252 default), harmless on Mac/Linux.
# reconfigure() is cleaner than replacing sys.stdout with a new TextIOWrapper.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

# === CONFIG ===
LEARN_LANGUAGES = ["French", "Korean", "Chinese", "Japanese"]   # Add/remove languages for learning
# Model, auth, base_url will be loaded from env.glm.json at runtime
LOG_FILE = os.path.expanduser("~/.claude/translation.log.md")


# === CREDENTIALS ===

def load_glm_credentials() -> dict:
    """Load GLM credentials from ~/.claude/env.glm.json"""
    glm_path = os.path.expanduser("~/.claude/env.glm.json")
    try:
        with open(glm_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            return {
                "auth_token": data.get("env", {}).get("ANTHROPIC_AUTH_TOKEN", ""),
                "base_url": data.get("env", {}).get("ANTHROPIC_BASE_URL", ""),
                "model": data.get("env", {}).get("ANTHROPIC_SMALL_FAST_MODEL", "glm-4.5-air"),
            }
    except Exception as e:
        print(f"[vi-translate] Failed to load env.glm.json: {e}", file=sys.stderr)
        return {"auth_token": "", "base_url": "", "model": "glm-4.5-air"}


# === VIETNAMESE DETECTION ===

def is_vietnamese(text: str) -> bool:
    """Detect Vietnamese by unique chars (đ, ơ, ư, ă) or tone-marked vowels."""
    unique_vi = set("đĐơƠưƯăĂ")
    vi_extended = re.compile(r"[\u1EA0-\u1EF9]")
    return any(c in unique_vi for c in text) or bool(vi_extended.search(text))


# === TRANSLATION ===

def translate(prompt: str, creds: dict) -> dict:
    api_key = creds.get("auth_token", "")
    if not api_key:
        print("[vi-translate] No auth token found in env.glm.json", file=sys.stderr)
        return {}

    base_url = creds.get("base_url", "")
    if not base_url:
        print("[vi-translate] No base_url found in env.glm.json", file=sys.stderr)
        return {}

    model = creds.get("model", "glm-4.5-air")

    all_langs = ["English"] + LEARN_LANGUAGES
    lang_list = ", ".join(all_langs)

    system = (
        f"You are a translation assistant. Translate the given Vietnamese text to: {lang_list}. "
        f'Return ONLY a valid JSON object with language names as keys. '
        f'Example: {{"English": "...", "Japanese": "..."}}'
    )

    payload = {
        "model": model,
        "max_tokens": 1024,
        "system": system,
        "messages": [{"role": "user", "content": prompt}],
    }

    url = base_url.rstrip("/") + "/v1/messages"

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            text = result["content"][0]["text"].strip()
            text = re.sub(r"^```(?:json)?\n?", "", text)
            text = re.sub(r"\n?```$", "", text)
            return json.loads(text)
    except Exception as e:
        print(f"[vi-translate] Error: {e}", file=sys.stderr)
        return {}


# === DISPLAY & LOG ===

FLAGS = {"English": "🇬🇧", "Japanese": "🇯🇵", "French": "🇫🇷", "Spanish": "🇪🇸", "Korean": "🇰🇷", "Chinese": "🇨🇳"}

def display(original: str, translations: dict):
    sep = "─" * 52
    print(f"\n{sep}", file=sys.stderr)
    print("📚  Language Learning Reference", file=sys.stderr)
    print(f"🇻🇳  VI: {original}", file=sys.stderr)
    print(sep, file=sys.stderr)
    for lang, text in translations.items():
        flag = FLAGS.get(lang, "🌐")
        print(f"{flag}  {lang}: {text}", file=sys.stderr)
    print(f"{sep}\n", file=sys.stderr)


def log(original: str, translations: dict):
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(f"\n## {datetime.now().strftime('%Y-%m-%d %H:%M')}\n\n")
            f.write(f"**🇻🇳 VI:** {original}\n\n")
            for lang, text in translations.items():
                flag = FLAGS.get(lang, "🌐")
                f.write(f"**{flag} {lang}:** {text}\n\n")
            f.write("---\n")
    except Exception:
        pass


# === MAIN ===

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    prompt = data.get("prompt", "").strip()
    if not prompt or not is_vietnamese(prompt):
        sys.exit(0)  # Not Vietnamese, pass through unchanged

    creds = load_glm_credentials()
    translations = translate(prompt, creds)
    if not translations:
        sys.exit(0)  # Translation failed, pass through original

    english = translations.get("English", "")
    if not english:
        sys.exit(0)

    display(prompt, translations)
    log(prompt, translations)

    # Inject English translation as discrete additionalContext.
    # IMPORTANT: The Vietnamese prompt is already in the user message, but we instruct Claude
    # to respond ONLY to the English translation below.
    output = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": (
                f"=== TRANSLATION NOTICE ===\n"
                f"The user's message is in Vietnamese. The English translation is:\n\n"
                f"<english_request>\n{english}\n</english_request>\n\n"
                f"INSTRUCTION: Respond ONLY to <english_request> above. "
                f"Do NOT respond to the Vietnamese text in the user's message. "
                f"Respond in English. This is critical.\n"
                f"=== END TRANSLATION NOTICE ===\n"
            ),
        }
    }
    print(json.dumps(output))


if __name__ == "__main__":
    main()
