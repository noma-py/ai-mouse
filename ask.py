"""Point the mouse at something, run this, ask a question, get an explanation.

Screenshot includes the cursor, so the model sees what you're pointing at.
BACKEND "local" runs via Ollama; "claude" runs via Claude Code on your subscription.
"""
import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request

BACKEND = "local"  # "local" or "claude"
MODEL = "gemma4"  # any Ollama model with "vision" in `ollama show <model>`
OLLAMA = "http://localhost:11434/api/chat"
# Shortcuts runs with a bare PATH, so fall back to the default install location
CLAUDE = shutil.which("claude") or os.path.expanduser("~/.local/bin/claude")
SYSTEM = (
    "You are a helpful assistant. The screenshot shows the user's screen; "
    "the mouse cursor marks what they are pointing at. Answer their question "
    "about it in plain language, briefly (under 150 words). No markdown."
)


def show(text):
    print(text, flush=True)  # Hammerspoon shows stdout in a panel by the cursor


def ask_model(question, image_b64):
    body = json.dumps({
        "model": MODEL,
        "stream": False,
        "think": False,  # ponytail: off for speed; set True for harder questions
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": question, "images": [image_b64]},
        ],
    }).encode()
    req = urllib.request.Request(OLLAMA, body, {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.load(r)["message"]["content"].strip()


def ask_claude(question, image_path):
    r = subprocess.run(
        [CLAUDE, "-p", f"Read the screenshot at {image_path}, then answer: {question}",
         "--append-system-prompt", SYSTEM,
         "--allowedTools", "Read",
         "--strict-mcp-config",  # skip MCP servers: faster startup
         "--no-session-persistence"],
        capture_output=True, text=True, timeout=300,
        cwd=tempfile.gettempdir(),  # keep project CLAUDE.md files out of it
    )
    if r.returncode != 0:
        raise OSError(r.stderr.strip() or r.stdout.strip())
    return r.stdout.strip()


def main():
    img = os.path.join(tempfile.gettempdir(), "ai_mouse.jpg")
    # -C includes the cursor, -x no shutter sound; sips shrinks Retina shots so the model runs faster
    if subprocess.run(["screencapture", "-C", "-x", "-t", "jpg", img]).returncode != 0:
        subprocess.run(["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"])
        show("No Screen Recording permission. Turn on \"Hammerspoon\" (or Terminal, if you ran "
             "this from there) in the settings window that just opened, then try again.")
        return
    subprocess.run(["sips", "-Z", "1568", img], check=True, capture_output=True)
    print("ready", flush=True)  # screenshot taken: Hammerspoon can now show the question box

    question = "Explain what I'm pointing at."
    if "--explain" not in sys.argv:  # one-press mode skips the question
        line = sys.stdin.readline()  # Hammerspoon sends the question here
        if not line:  # stdin closed: question box cancelled
            return
        question = line.strip() or question

    if BACKEND == "claude":
        try:
            show(ask_claude(question, img) or "(no answer)")
        except (OSError, subprocess.TimeoutExpired) as e:
            show(f"Claude Code failed: {e}")
        return

    with open(img, "rb") as f:
        data = base64.standard_b64encode(f.read()).decode()

    try:
        show(ask_model(question, data) or "(no answer)")
    except OSError as e:  # URLError is an OSError: Ollama not running, timeout, etc.
        show(f"Couldn't reach Ollama ({e}). Is it running? Try: ollama serve")


if __name__ == "__main__":
    main()
