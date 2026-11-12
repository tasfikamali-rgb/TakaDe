# 34. Packed group changes, nightly backups and a spare Supabase project

Status: accepted (Sabit, 2026-11-12: picked "Pack old changes into bundles", then "do
everything right now"). SQL and the refill script checked on a local PostgreSQL 16 with a
Supabase stand-in; app code checked by the CI build and tests, not yet on a phone; the backup
workflow has not run against the real project yet.

## Context
Supabase Free gives 500 MB, no backups and no automatic failover. Two live databases that
share traffic (active-active) aren't realistic on free plans: copies drift, sign-ins don't
carry over between services, and read replicas and load balancing are paid features. The
plan is one live project, a spare, and nightly locked copies (decision doc in the project
thread).

## 1. Packed changes (`20261112080000_pack_old_changes.sql`)
`sync_change` keeps every change as its own sealed row so a new member can build the group
from row one. Rows can't simply be deleted. Instead:

- Once a day per group, after a full sync with nothing waiting to upload, a member's phone
  asks `sync_pack_point`. If at least 200 rows are older than 10 minutes, it seals the whole
  group as it is on the phone (group, every expense including deleted ones, payments, meal
  counts; the same set as when a group is first shared) into one zlib-compressed AES-GCM
  bundle, bound to group id, bundle id and position, and calls `pack_sync_group`.
- The server keeps one bundle per group (`sync_bundle`) and deletes the rows up to that
  position in the same transaction. At most one pack per group every 6 hours. Rows from the
  last 10 minutes are never packed, so an upload still in progress isn't lost.
- A phone whose cursor is before the bundle (new member, or away a while) applies the bundle,
  sets its cursor to the bundle's position, then reads rows after it. Rows between that
  position and the packing phone's own cursor are replayed; every change is a whole entity,
  so the end state is the same.
- Applying a bundle writes, logs and announces only what is new or newer on that phone. The
  same checks as single changes apply: a bundle can't confirm a payment.
- If a pack lands while a phone is paging through a download, the phone goes back to where
  it started and reads the new bundle.
- Old app versions keep working on rows only; they never pack.

Estimated saving 2 to 3 times for busy groups (rows compress better together and per-row ids
and index entries go away). Not measured on real data yet.

What the server learns: when a group is packed and the bundle's size. A member of a group can
now make the server forget that group's older rows by uploading a bad bundle; every member's
phone still has the whole group, and sharing again rebuilds it.

## 2. Nightly backup (`.github/workflows/backup.yml`)
At 03:00 Dhaka time, GitHub Actions dumps roles, schema and data with the Supabase CLI,
encrypts the archive with GPG (AES-256, passphrase from a repository secret) and uploads it
to Cloudflare R2 (10 GB free). Copies older than 30 days are removed. Nothing is printed,
cached or kept as an artifact: the repository is public. Without its secrets the job only
prints a notice.

## 3. Spare project and the switch
A second free Supabase project, with every migration run on it, is refilled each night from
the same dump (`scripts/backup/refill-spare.sh`): every table in the dump is emptied and
reloaded in one transaction, so a failed refill leaves the spare as it was.

The app has both projects built in (`TAKADE_SUPABASE_SPARE_HOST` and its anon key). A public
file outside Supabase (`TAKADE_SERVER_SWITCH_URL`, for example in a public R2 bucket) says
`{"use":"main"}` or `{"use":"spare"}`. The app reads it on launch and uses the choice the next
time it opens. The file can only choose between the two built-in projects.

After a switch: shared groups carry on (guest sign-ins rejoin with their rejoin secrets),
anything uploaded after the last nightly copy is sent again from phones only if it is still
waiting there, and people may need to sign in again. Chat messages, new accounts and new
TakaDe IDs from that day are lost.

## Not done
- Automatic switching, live replication, load sharing across databases.
- The spare may pause after a week without API traffic; if so, restore it in the dashboard
  before switching.
