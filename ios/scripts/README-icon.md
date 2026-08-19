# App icon

`icon-source.png` is Ryan's original artwork, kept as the source of truth.
Everything shipped is derived from it, so the original design is what ships.

`make-app-icon.swift` produces the App Store icon from it:

```sh
swiftc -O -o /tmp/mkicon scripts/make-app-icon.swift
/tmp/mkicon scripts/icon-source.png \
  Mellophone/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png \
  render 0.191 0.012 0.638
```

## Why it is not used as-is

Three things about the FILE, none about the design:

1. It is **900x900**. App Store icons must be exactly **1024x1024**.
2. It has an **alpha channel**. Apple rejects transparency in an app icon.
3. The **rounded corners and black surround are baked in**. iOS applies its own
   mask, so the result would be a shrunken icon inside a dark frame.

The script measures the artwork inside the black margin, then crops into it,
framed on the horn, and writes an opaque 1024 square. The crop also puts the
"HONK IT UP!" text below the frame, which is wanted: the app's name already
appears under the icon on the home screen, and at 60 points the lettering is an
unreadable smudge. Cropping in also makes the horn bigger, which is exactly what
reads at small sizes.

The three numbers are fractions of the artwork square: left offset, top offset,
and side length. They were tuned by rendering and looking, including at 180px,
which is what a 60pt icon looks like at 3x.
