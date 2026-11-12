# 0020: Group photos and group colour

Status: accepted (Sabit, 2026-11-12).

## Decision
- **Photo:** a group can have an optional photo. It's picked with the system photo picker, which needs no photo library permission. It's cropped to a 640 px square JPEG and saved at `Application Support/GroupPhotos/<group id>.jpg` with `completeUntilFirstUserAuthentication` protection. It's not in the database or the export, and Delete all my data removes it.
- **Colour:** the photo's most prominent colour is the hue that covers most of the photo, with colourful pixels weighted over grey ones. It's saved on the group as `accentHex` (migration `v8_group_accent`). Screens never use it raw: `GroupTint` turns the hue into HSB saturation 0.24, brightness 0.93 in light mode and saturation 0.40, brightness 0.30 in dark mode. The usual ink text stays well above 4.5:1 contrast on both. Mostly grey photos keep the standard lilac.
- **Shared groups:** the colour travels in the encrypted group change. The photo doesn't yet. Carrying it means encrypted, compressed upload, as with receipt photos, and that is left to the shared-groups work (ADR 0019).
