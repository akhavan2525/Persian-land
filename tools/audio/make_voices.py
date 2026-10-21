"""Voices the Persian battle lines with ElevenLabs (Persian text, `eleven_v4`).

    python make_voices.py voice_lines.json <out dir> [--force]

The API key is not read here: the session's network proxy adds it to requests to
api.elevenlabs.io. On a normal computer, set the `xi-api-key` header yourself.
Existing files are skipped unless --force is given, so re-running only fills gaps.
"""
import json
import os
import subprocess
import sys
import urllib.request

SRC, OUT = sys.argv[1], sys.argv[2]
force = "--force" in sys.argv
os.makedirs(OUT, exist_ok=True)
data = json.load(open(SRC, encoding="utf-8"))
headers = {"Content-Type": "application/json"}
if os.environ.get("ELEVENLABS_API_KEY"):
    headers["xi-api-key"] = os.environ["ELEVENLABS_API_KEY"]
for line in data["lines"]:
    path = os.path.join(OUT, line["id"] + ".ogg")
    if os.path.exists(path) and not force:
        continue
    voice = data["voices"][line["voice"]]
    body = json.dumps({"text": line["text"], "model_id": "eleven_v4", "language_code": "fa"}).encode()
    req = urllib.request.Request(
        "https://api.elevenlabs.io/v1/text-to-speech/%s?output_format=mp3_44100_128" % voice,
        data=body, headers=headers)
    mp3 = urllib.request.urlopen(req, timeout=120).read()
    tmp = path + ".mp3"
    open(tmp, "wb").write(mp3)
    # mono Ogg Vorbis, trimmed of leading silence, keeps the game small
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-ac", "1", "-ar", "32000",
                    "-af", "silenceremove=start_periods=1:start_threshold=-45dB",
                    "-c:a", "libvorbis", "-q:a", "4", path], check=True)
    os.remove(tmp)
    print("voiced", line["id"])
