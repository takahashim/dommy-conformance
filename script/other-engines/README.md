# Checking a divergence in an engine other than Chromium

`rake oracle` compares Dommy against headless Chromium. When a divergence is one
where **Dommy follows the spec and Chromium does not**, one engine is not enough
to decide anything: the question is whether the spec text or the shipping
engines are the odd one out.

## WebKit

`webkit2gtk-driver` installs WebKitGTK — the same WebCore and JavaScriptCore
Safari is built on, driven through WebKitWebDriver. It is not Safari itself (a
different port and release train), but for DOM-level semantics it is the same
code.

```sh
sudo apt-get install -y --no-install-recommends webkit2gtk-driver xvfb
python3 script/other-engines/webkit.py
```

## Gecko

There is no Linux build to install here — Ubuntu's `firefox` package is a snap
transitional stub, and Mozilla's own downloads are not reachable from this
environment. Read the source instead; for the record-order questions it is
short and unambiguous:

- `dom/base/Text.cpp` — `Text::SplitText`
- `dom/base/nsINode.cpp` — `nsINode::Normalize`

```sh
curl -sS https://raw.githubusercontent.com/mozilla/gecko-dev/master/dom/base/Text.cpp
```

## Real Safari / Firefox

Nothing here substitutes for running `record-order-probe.js` in a shipping
browser. Paste it into the console (Safari needs Develop mode enabled first:
Settings → Advanced → "Show features for web developers").
