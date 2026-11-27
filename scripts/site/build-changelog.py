#!/usr/bin/python3 -I
"""Renders CHANGELOG.md as site/changelog/index.html.

The changelog is the single source for release notes; the page is generated from it and committed, and
scripts/check/site.sh fails when the two disagree. Only released versions appear. The format contract is the one
documented in docs/development/releasing.md: `## <version> — <Month D, YYYY>`, `### <Section>`, `- ` bullets.

usage: build-changelog.py [--check]   (without --check the page is written)
"""
import datetime
import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "CHANGELOG.md"
TARGET = ROOT / "site" / "changelog" / "index.html"
HEADING = re.compile(r"^## (\d+\.\d+\.\d+) — (\w+ \d{1,2}, \d{4})$")


def inline(text):
    """Escapes, then renders the only inline markup the changelog uses: **bold** and `code`."""
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    return re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)


def parse(markdown):
    releases = []
    for line in markdown.splitlines():
        if line.startswith("## "):
            match = HEADING.match(line)
            releases.append({"version": match[1], "date": match[2], "intro": [], "sections": []} if match else None)
        elif releases and releases[-1] is not None:
            current = releases[-1]
            if line.startswith("### "):
                current["sections"].append((line[4:].strip(), []))
            elif line.startswith("- ") and current["sections"]:
                current["sections"][-1][1].append(line[2:].strip())
            elif line.strip() and not current["sections"]:
                current["intro"].append(line.strip())
    return [r for r in releases if r]


def iso(date_text):
    return datetime.datetime.strptime(date_text, "%B %d, %Y").strftime("%Y-%m-%d")


def render(releases):
    latest = releases[0]["version"]
    blocks = []
    for release in releases:
        version = release["version"]
        parts = [f'      <section class="release" id="v{version.replace(".", "-")}">',
                 f'        <h2>{version} <time datetime="{iso(release["date"])}">{release["date"]}</time></h2>']
        parts += [f"        <p>{inline(text)}</p>" for text in release["intro"]]
        for title, items in release["sections"]:
            parts.append(f"        <h3>{html.escape(title)}</h3>")
            parts.append("        <ul>")
            parts += [f"          <li>{inline(item)}</li>" for item in items]
            parts.append("        </ul>")
        parts.append("      </section>")
        blocks.append("\n".join(parts))
    body = "\n".join(blocks)
    return f"""<!doctype html>
<!-- Generated from CHANGELOG.md by scripts/site/build-changelog.py. Do not edit by hand. -->
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Changelog – MacPocket</title>
  <meta name="description" content="Release notes for every MacPocket version: new features, improvements, changes, fixes and security updates.">
  <meta name="theme-color" content="#0a5cff">
  <link rel="icon" href="/assets/logo.png" type="image/png">
  <link rel="canonical" href="https://macpocket.app/changelog/">
  <link rel="stylesheet" href="/style.css">
</head>
<body>
  <a class="skip" href="#main">Skip to content</a>
  <header class="top">
    <div class="wrap">
      <a class="brand" href="/"><img src="/assets/logo.png" alt="" width="32" height="32">MacPocket</a>
      <nav class="top-nav" aria-label="Main">
        <a href="/#features">Features</a>
        <a href="/#privacy">Privacy</a>
        <a href="/#about">About</a>
        <a href="https://github.com/doancan/MacPocket">GitHub</a>
        <a href="/tr/" hreflang="tr" lang="tr">Türkçe</a>
      </nav>
    </div>
  </header>

  <main id="main" class="wrap prose">
    <h1>Changelog</h1>
    <p class="sub">What changed in each release. The latest version is {latest}; MacPocket also offers new versions itself: choose MacPocket › Check for Updates.</p>
    <p><a class="button primary" href="https://github.com/doancan/MacPocket/releases/latest/download/MacPocket-macOS-arm64.dmg">Download {latest}</a></p>
{body}
  </main>

  <footer>
    <div class="wrap">
      <span>© 2026 MacPocket contributors. MIT License.</span>
      <ul>
        <li><a href="https://github.com/doancan/MacPocket/releases">Releases</a></li>
        <li><a href="https://github.com/doancan/MacPocket/blob/main/CHANGELOG.md">Changelog source</a></li>
        <li><a href="https://github.com/doancan/MacPocket/blob/main/SECURITY.md">Security</a></li>
        <li><a href="https://github.com/doancan/MacPocket/blob/main/LICENSE">License</a></li>
      </ul>
    </div>
  </footer>
</body>
</html>
"""


def main():
    releases = parse(SOURCE.read_text(encoding="utf-8"))
    if not releases:
        sys.exit("build-changelog: no released version found in CHANGELOG.md")
    page = render(releases)
    if "--check" in sys.argv:
        current = TARGET.read_text(encoding="utf-8") if TARGET.exists() else ""
        if current != page:
            sys.exit("site/changelog/index.html is out of date; run `make site-changelog` and commit the result")
        print(f"site changelog: {len(releases)} releases, up to date")
        return
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(page, encoding="utf-8")
    print(f"wrote {TARGET.relative_to(ROOT)} ({len(releases)} releases)")


if __name__ == "__main__":
    main()
