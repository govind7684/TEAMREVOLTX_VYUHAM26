# Assistant server (hackathon prototype)

Keeps the Claude key off the phone. Run on a laptop on the same Wi-Fi as the phone.
Never commit the key; set it in the terminal only.

```powershell
cd server
python -m pip install -r requirements.txt
$env:ANTHROPIC_API_KEY = "<key from the organisers>"
$env:ANTHROPIC_MODEL   = "<exact model id from the organisers>"
$env:ASSIST_TOKEN      = "choose-a-password"     # optional but recommended
python app.py
```

Find the laptop's address with `ipconfig` (IPv4, e.g. 192.168.1.23). In the app:
More > Settings > AI assistant: enter `http://192.168.1.23:8787` and the password, tap Test.
Allow Python through Windows Firewall (private networks) when asked.

What is sent: report description text, and aggregate counts for the briefing. Not names, emails or
exact locations. Prototype only: not for production, no HTTPS, works only while this laptop runs.

## Without the organisers' key: Google Gemini free tier

Make a key at aistudio.google.com (Google account, no card). Do not link a billing account to that project, so it stays free.

```powershell
$env:GEMINI_API_KEY = "<your free key>"
$env:GEMINI_MODEL   = "<a model that shows a free tier in AI Studio and accepts images>"
$env:ASSIST_TOKEN   = "choose-a-password"
python app.py
```

/health shows which provider is active. Free-tier data may be used by Google to improve its products, so only use test photos and test text; do not send real citizens' data. Free limits are low, so expect "Too many requests" if you hammer it.

## Check which AI is used (works with any Claude model)

`python check_ai.py` lists the models your key can use, or tests the one you set.
With Claude: set `ANTHROPIC_API_KEY` only, run `python check_ai.py`, copy a model name it prints into
`ANTHROPIC_MODEL`, run it again to see "Claude OK", then start `python app.py`.
The server sends only a plain message with a system prompt, so any current Claude model works.
