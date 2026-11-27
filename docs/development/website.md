# Website

The public site is plain static HTML and CSS in `site/`, with no build step on the server and no
JavaScript. English lives at `/`, Turkish at `/tr/`.

| Path | Purpose |
| --- | --- |
| `site/index.html`, `site/tr/index.html` | The two language versions of the landing page |
| `site/style.css` | Shared styles, light and dark |
| `site/_headers` | Security and cache headers served by Cloudflare Pages |
| `site/changelog/index.html` | **Generated** from `CHANGELOG.md` by `scripts/site/build-changelog.py` (`make site-changelog`) and committed. English only; the Turkish pages link to it |
| `site/404.html` | Not-found page |
| `site/assets/` | **Not committed.** Copied from `docs/assets` at build time so each image has one source |

## Preview locally

```sh
make site   # http://localhost:8000
```

## Deployment

The site is deployed by Cloudflare Pages through its GitHub integration, so there is no
workflow or secret in this repository. Every push to `main` publishes; pull requests
get a preview URL.

Pages project settings:

| Setting | Value |
| --- | --- |
| Production branch | `main` |
| Build command | `cp -R docs/assets site/assets` |
| Build output directory | `site` |
| Root directory | `/` |

The site is served at <https://macpocket.app>. The custom domain is attached under the project's
*Custom domains*; Cloudflare creates the DNS record because the domain's DNS is already on Cloudflare.
The canonical URLs, `hreflang` links and `sitemap.xml` use that domain, so change them together if it ever moves.

## Editing

- Keep both languages in step: a change to a section in one file belongs in the other.
- `scripts/check/site.sh` (part of `make verify`) fails when the changelog page is stale or the download link
  stops matching the release workflow's asset name. Release commits regenerate the page; never edit it by hand.
- Apart from the generated changelog, do not copy version numbers into the site. The download button points at
  `releases/latest/download/MacPocket-macOS-arm64.dmg`, a version-less copy of the disk image that the
  release workflow attaches to every release, so the link always downloads the newest build.
- The Sparkle update feed stays on GitHub Releases (`SUFeedURL` in `Resources/Info.plist`);
  moving it to the domain would orphan installed copies.
