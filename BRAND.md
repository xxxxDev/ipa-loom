# Brand assets

The IPA Loom logo belongs to [V-AX](https://v-ax.com) and is not included in the MIT license for the integration code. Brand rights are reserved.

Both README translations use the horizontal logo in a theme-aware `<picture>`: `docs/assets/logo/ipa-loom-lockup-primary.svg` by default and `docs/assets/logo/ipa-loom-lockup-on-dark.svg` for dark mode. Their rounded symbol and lettering are vector paths, with no embedded bitmap, external font, or remote resource.

## Presentation

- Both SVGs have transparent backgrounds and a blue core (`#0866FF`). The primary version uses dark-ink shell and lettering for light surfaces; the on-dark version uses white (`#FFFFFF`) for dark surfaces. Both README translations select the on-dark version with `prefers-color-scheme: dark` and use primary otherwise. Presentation backgrounds belong to the page or preview, not to the logo assets.
- Preserve the 1920 × 600 viewBox and aspect ratio. The artwork occupies 1620 × 340 units, with 150 units of clear space on each side and 130 above and below.
- The lettering is approximately 62% of the symbol's height. Keep the selected symbol-to-wordmark proportions and spacing together; do not stretch or separately resize them.
- README displays the asset centered at 640 pixels wide (200 pixels high), scaling down to fit narrower screens. Do not crop its clear space or bake a background into it.

You may keep the logo in copies of this repository and use it to refer to IPA Loom. Use your own name and artwork for a separately branded fork or product; do not imply endorsement by V-AX.

Both SVGs are included in the public text-file inventory. Concept images, rendering previews, and private design working files are not part of the public source.
