# Website

The public site is plain static HTML and CSS in `site/`, with no build step and no
JavaScript. English lives at `/`, Turkish at `/tr/`.

| Path | Purpose |
| --- | --- |
| `site/index.html`, `site/tr/index.html` | The two language versions of the landing page |
| `site/style.css` | Shared styles, light and dark |
| `site/_headers` | Security and cache headers served by Cloudflare Pages |
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
- Do not copy version numbers into the site. The download button points at
  `releases/latest`, which always resolves to the newest release.
- The Sparkle update feed stays on GitHub Releases (`SUFeedURL` in `Resources/Info.plist`);
  moving it to the domain would orphan installed copies.
