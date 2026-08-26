# Brand assets

Source of truth is the SVG in `assets/brand/`:

| file | purpose |
| --- | --- |
| `icon.svg` | full app icon (dark rounded square + ticket mark) |
| `icon_foreground.svg` | Android adaptive-icon foreground (ticket only, inside the safe zone) |
| `notification.svg` | Android status-bar glyph (white silhouette, V cut out) |

The mark is a member's passbook/ticket — the perforated card of a village bank
meeting — in the monochrome, rounded-card style of the app.

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
