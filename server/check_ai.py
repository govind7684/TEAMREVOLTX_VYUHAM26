"""Checks which AI the server will use and that it really answers.

Run it in the same terminal where you set the key variables (never put a key in a file):
    python check_ai.py

Claude:  ANTHROPIC_API_KEY (+ ANTHROPIC_MODEL; leave the model unset to list what your key can use)
Gemini:  GEMINI_API_KEY + GEMINI_MODEL
"""
import json
import os
import sys
import urllib.request

PROMPT = "Reply with exactly: ready"


def claude():
    key = os.getenv("ANTHROPIC_API_KEY")
    if not key:
        return False
    try:
        from anthropic import Anthropic
    except ImportError:
        print("The anthropic package is missing. Run: python -m pip install -r requirements.txt")
        return True
    client = Anthropic(api_key=key)
    model = os.getenv("ANTHROPIC_MODEL")
    if not model:
        try:
            ids = [m.id for m in client.models.list(limit=50).data]
        except Exception as exc:  # noqa: BLE001 - show the reason, whatever it is
            print("Could not list models:", exc.__class__.__name__, exc)
            return True
        print("Models your key can use (copy one into ANTHROPIC_MODEL):")
        for i in ids:
            print("  ", i)
        return True
    try:
        r = client.messages.create(model=model, max_tokens=20,
                                   messages=[{"role": "user", "content": PROMPT}])
        text = "".join(getattr(b, "text", "") for b in r.content).strip()
        print(f"Claude OK. Model {model} answered: {text!r}")
    except Exception as exc:  # noqa: BLE001
        print(f"Claude FAILED with model {model}:", exc.__class__.__name__, exc)
    return True


def gemini():
    key, model = os.getenv("GEMINI_API_KEY"), os.getenv("GEMINI_MODEL")
    if not key:
        return False
    if not model:
        req = urllib.request.Request(
            "https://generativelanguage.googleapis.com/v1beta/models?pageSize=100",
            headers={"x-goog-api-key": key})
        data = json.load(urllib.request.urlopen(req, timeout=30))
        print("Models your key can use (copy one into GEMINI_MODEL):")
        for m in data.get("models", []):
            if "generateContent" in m.get("supportedGenerationMethods", []):
                print("  ", m["name"].split("/")[-1])
        return True
    body = json.dumps({"contents": [{"role": "user", "parts": [{"text": PROMPT}]}]}).encode()
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
        data=body, headers={"Content-Type": "application/json", "x-goog-api-key": key})
    try:
        data = json.load(urllib.request.urlopen(req, timeout=60))
        parts = data["candidates"][0]["content"]["parts"]
        print(f"Gemini OK. Model {model} answered: {''.join(p.get('text', '') for p in parts).strip()!r}")
    except Exception as exc:  # noqa: BLE001
        print(f"Gemini FAILED with model {model}:", exc.__class__.__name__, exc)
    return True


if __name__ == "__main__":
    found = claude()
    found = gemini() or found
    if not found:
        print("No key found. Set ANTHROPIC_API_KEY (Claude) or GEMINI_API_KEY (Gemini) in this terminal first.")
        sys.exit(1)
