# vBank website

Static, dependency-free GitHub Pages site for the vBank app. No build step, no
framework — plain HTML and one stylesheet.

```
index.html      landing page: what it is, features, screenshots, how it works, FAQ, support
guide.html      full user guide (16 sections, troubleshooting table)
privacy.html    privacy policy (Play Data Safety / App Store privacy compliant)
terms.html      terms of use + EULA incl. Apple's required minimum terms
404.html        not-found page
styles.css      the whole design system (zinc palette, light/dark aware)
screenshots/    full-resolution device screenshots (1080x2340)
screenshots/web 540px-wide copies used by the pages
store/          store-ready assets (see below)
```

## Publishing

The site is deployed by `.github/workflows/pages.yml` on every push to `main`
that touches `website/**`: enable **Settings → Pages → Build and deployment →
Source: GitHub Actions** once, and it serves at
`https://<user>.github.io/<repo>/`.

Alternatives if you prefer no Actions:

* **Branch deploy** — move these files to the repository root or to `/docs`, then
  set Settings → Pages → Source: *Deploy from a branch*.
* **Custom domain** — add a `CNAME` file containing the domain (e.g.
  `vbank.zm`), point a DNS `CNAME` at `<user>.github.io`, and update the URLs in
  `sitemap.xml` and `robots.txt`.

`.nojekyll` is present so files and folders starting with `_` are served as-is.

## Before going live

* Replace `support@vbank.zm` / `privacy@vbank.zm` with real, monitored addresses
  (they appear in both legal pages, the footer and the support section).
* Confirm the governing-law and liability-cap wording in `terms.html` suits you;
  have a lawyer read it if the app will be distributed commercially.
* Add the APK/store links to the hero once the listings are live.

## Store assets

| Folder | Size | Use |
|---|---|---|
| `store/play-phone/` | 1080×1920 | Google Play phone screenshots (8) |
| `store/ios-6.7/` | 1290×2796 | App Store 6.7" iPhone screenshots (8) |
| `store/ios-6.5/` | 1284×2778 | App Store 6.5" iPhone screenshots (8) |
| `store/play-feature-graphic-1024x500.png` | 1024×500 | Play listing feature graphic |

Screenshots were captured from a real device (Samsung SM-A175F, 1080×2340) and
letterboxed onto the store canvases with the app's own background colour, so
nothing is stretched. The iOS sets are up-scaled from Android captures — replace
them with genuine iOS captures before submitting to Apple.
