# 0020: Group photos and group colour

Status: accepted (Sabit, 2026-11-12).

## Decision
- **Photo:** a group can have an optional photo. It's picked with the system photo picker, which needs no photo library permission. It's cropped to a 640 px square JPEG and saved at `Application Support/GroupPhotos/<group id>.jpg` with `completeUntilFirstUserAuthentication` protection. It's not in the database or the export, and Delete all my data removes it.
- **Colour:** the photo's most prominent colour is the hue that covers most of the photo, with colourful pixels weighted over grey ones. It's saved on the group as `accentHex` (migration `v8_group_accent`). Screens never use it raw: `GroupTint` turns the hue into HSB saturation 0.12, brightness 0.96 in light mode and saturation 0.35, brightness 0.20 in dark mode. Checked for every hue, muted text (`inkMuted`) stays at or above 4.6:1 in light and 4.9:1 in dark, and ink text well above that. The first values (0.24/0.93 and 0.40/0.30) let muted text drop to about 3.8:1 on blue and 3.3:1 on yellow. Mostly grey photos keep the standard lilac.
- **Shared groups:** the colour travels in the encrypted group change. The photo doesn't yet. Carrying it means encrypted, compressed upload, as with receipt photos, and that is left to the shared-groups work (ADR 0019).
