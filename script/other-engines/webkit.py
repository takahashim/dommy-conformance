#!/usr/bin/env python3
"""Run record-order-probe.js in WebKitGTK — the same WebCore / JavaScriptCore
Safari ships, driven through WebKitWebDriver rather than Safari itself.

    sudo apt-get install -y --no-install-recommends webkit2gtk-driver xvfb
    python3 script/other-engines/webkit.py

Prints the probe's JSON. Chromium's answer comes from `rake oracle:chromium`;
for Gecko there is no Linux-installable build here, so read
dom/base/Text.cpp / dom/base/nsINode.cpp in mozilla-central instead.
"""
import json, os, subprocess, sys, time, urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PROBE = open(os.path.join(HERE, "record-order-probe.js")).read()
BASE = "http://127.0.0.1:4444"
MINIBROWSER = "/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1/MiniBrowser"


def rq(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        print("HTTP", e.code, e.read().decode()[:800], file=sys.stderr)
        raise


xvfb = subprocess.Popen(["Xvfb", ":99", "-screen", "0", "1024x768x24"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
driver = subprocess.Popen(["WebKitWebDriver", "--port=4444"],
                          env=dict(os.environ, DISPLAY=":99"),
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    for _ in range(60):
        try:
            urllib.request.urlopen(BASE + "/status", timeout=2)
            break
        except Exception:
            time.sleep(0.5)

    session = rq("POST", "/session", {"capabilities": {"alwaysMatch": {
        "browserName": "MiniBrowser",
        "webkitgtk:browserOptions": {"binary": MINIBROWSER, "args": ["--automation"]},
    }}})
    sid = session["value"]["sessionId"]
    rq("POST", f"/session/{sid}/url",
       {"url": "data:text/html,<!doctype html><html><body></body></html>"})
    # `return` followed by a comment line is ASI — it returns undefined before
    # ever reaching the probe. Bind the value first.
    result = rq("POST", f"/session/{sid}/execute/sync",
                {"script": "var __r = " + PROBE + "; return __r;", "args": []})
    print(json.dumps(result["value"], indent=2))
    rq("DELETE", f"/session/{sid}")
finally:
    driver.terminate()
    xvfb.terminate()
