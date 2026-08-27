# Brand assets

Source of truth is the SVG in `assets/brand/`:

| file | purpose |
| --- | --- |
| `icon.svg` | full app icon (dark rounded square + the landmark glyph) |
| `icon_foreground.svg` | Android adaptive-icon foreground (glyph only, inside the safe zone) |
| `notification.svg` | Android status-bar glyph (white landmark silhouette) |

The mark replicates the welcome page (Get started / Restore from backup): a
dark rounded square (radius ¼ of the side) with Lucide's `landmark` glyph at
half the side, in the app's monochrome style. The website favicon,
`docs/icon-192.png` and `docs/store/play-icon-512.png` are resized copies of
`icon_1024.png`.

## Regenerate

```sh
# rasterize (ImageMagick)
convert -background none -density 300 assets/brand/icon.svg            -resize 1024x1024 assets/brand/icon_1024.png
convert -background none -density 300 assets/brand/icon_foreground.svg -resize 1024x1024 assets/brand/icon_foreground_1024.png
for d in mdpi:24 hdpi:36 xhdpi:48 xxhdpi:72 xxxhdpi:96; do
  convert -background none -density 300 assets/brand/notification.svg -resize ${d##*:}x${d##*:} \
    android/app/src/main/res/drawable-${d%%:*}/ic_stat_vbank.png
done

# launcher icons for Android (adaptive + monochrome), iOS, web, macOS, Windows
dart run flutter_launcher_icons
```

Linux has no launcher-icon convention in the Flutter template; distribute a
`.desktop` file pointing at `assets/brand/icon_1024.png` when packaging.
