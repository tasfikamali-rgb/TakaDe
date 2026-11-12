# 0022: Contact photos and mobile numbers for people added from Contacts

Status: accepted (Sabit, 2026-11-12).

## Decision
- When someone is added from Contacts (the searchable list or Apple's picker), TakaDe also reads their contact thumbnail photo and phone numbers. Only for the people picked: the searchable list still reads names only, and the extra fields are fetched by identifier when Add is tapped. No email, address, birthday or notes are read. The address book is never uploaded.
- **Name:** unchanged, exactly as Contacts shows it (as before).
- **Photo:** cropped to a 256 px square JPEG at `Application Support/MemberPhotos/<member id>.jpg` with `completeUntilFirstUserAuthentication` protection, and shown as the member's avatar on this phone. It isn't in the database, the export or the group sync, so other people in a shared group don't get it. Removing the person or Delete all my data deletes it.
- **Mobile number:** the first Bangladeshi mobile number (labelled mobile, iPhone or main first, then any other) is saved as the member's bKash payment handle, which already stays on this phone and isn't synced. Numbers from other countries are skipped. It can be deleted or changed in the person's sheet like any other number.
- The Contacts permission text now says names, photos and mobile numbers of the people picked are kept on this phone.

## Not done
- Member photos in shared groups. If they're ever synced, they go up encrypted on the phone like receipt photos (ADR 0019/0020), never in the clear.
- Guessing the wallet: the number is saved as bKash because that's the most common wallet; the app doesn't check that the number has a bKash account.
