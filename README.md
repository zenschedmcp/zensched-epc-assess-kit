# ZenSched EPC Assessor Reference Kit

A copy-pasteable setup for a solo UK / Ireland Domestic Energy Assessor (DEA), or a 2–6 assessor shop that dispatches subcontracted DEAs / NDEAs, that wants an AI assistant to run booking intake, GPS-verified arrival at each property, an Assessment Record (property type, working rating band A–G, evidence photos), an evidence pack for your lodgement file, receivables from estate agents and landlords, and sub payouts. ZenSched handles the phone app, the GPS check-in at each property, the one-off event and shift per visit, and the Assessment Record. A small local database on your computer holds your agencies, the properties (places) you have been to, your assessments (with occupant names, key-safe codes, UPRN, and RRN), invoices, and payouts.

**You do not need to know how to program or write SQL to use this.** You paste an agent's instruction into your AI assistant ("Hartwell just sent this, book it"), ask "what's today", "record this week", "export the Oak Lane pack", "invoice Hartwell", "who owes me money", and the AI does the work using two tools you set up once. Setup takes about 15 minutes and is the only technical part.

If you *are* a developer, skip to [For developers](#for-developers).

## This is not official EPC lodgement — read this first

**What this kit is:** a way for an energy assessor to get every dwelling visit onto their phone from a pasted agent email, prove GPS-verified arrival at the property, record an Assessment Record (property type, a working A–G note — not the register band — up to 4 evidence photos, visit outcome), and turn those records into an evidence pack, invoices, receivables follow-up, and sub payouts, with an AI assistant doing the clerical work.

**What it is not:**

- **It is not the official EPC register, and it is not RdSAP / SAP / DEAP lodgement.** It does not submit a certificate to Landmark, the Scottish EPC Register, or the SEAI BER register. It does not produce an RdSAP / SAP / SBEM / DEAP calculation, a certificate PDF, an A–G register band, or a Report Reference Number / BER number. `reports_to_export` plus a `form_export` give you the photos and the GPS-verified times; you lodge in Elmhurst, Quidos, ECMK, Stroma, DEAP, or your scheme's portal the way you do today. If the owner later tells the AI an RRN or BER number, it is stored locally only.
- **It is not a lodgement audit trail.** The Assessment Record's A–G field is a working note from the visit, **not** the lodged register band. Do not treat a band C on the phone as "the EPC is C on the register." Never tell an auditor or an agent "it's on ZenSched."
- **It does not watermark photos.** ZenSched records the GPS punch coordinates and the upload time server-side; the exported image is **not** stamped with the date, time, and coordinates. If a scheme or a solicitor later wants a *readable* stamp on the image itself, shoot with your phone camera's timestamp / GPS overlay turned on and upload *that* image.
- **It is not a signed legal document.** The Assessment Record has no signature field. On ZenSched a signature field replaces the Submit button, so adding one would make every visit look like the assessor had signed or lodged something. Submitting the form is just submitting the form.

If any of those is a deal-breaker, this kit is not for you. If you want a phone schedule with GPS proof at the door, a photo record per visit, and receivables you can actually chase, read on.

## What lives where

**ZenSched (source of truth for where you were and when):**

- Locations (one per property, cached locally so a 10-year re-assessment reuses the pin; the check-in radius is a **policy** setting, not per location)
- Workers (you, in solo mode; you plus your subs in agency mode, each with the mobile app)
- Events (one single-day event per assessment visit; ZenSched caps events at 60 days — every event in this kit is one day)
- Shifts (one per assessment: the appointment window, 60 minutes by default, with a push notification to the assessor)
- GPS punches (check-in / check-out with distance-from-the-pin verification)
- The Assessment Record form (property type, rating band A–G, up to 4 evidence photos, visit outcome, notes) and every submission with its photos

**Local SQLite database (`epc-assess.db`, on your computer):**

- Agencies: estate agents, solicitors, landlords, housing associations, local authorities, developers, direct homeowners, with payment terms and default fees
- Places: every property address you have been sent to, normalized, with its ZenSched location id, UPRN, and access notes — **UPRN and access notes never leave your computer**
- Assessors: you (and your subs); DEA / NDEA accreditation number — **never leaves your computer**; payout split per sub
- Assessments: instruction ref, type, occupant name and phone (**never leave your computer**), property, time, fees, the ZenSched event/shift/submission ids, GPS arrival stamps copied once, a summary of the Assessment Record, RRN after you lodge
- Invoices per agency with aging; payouts per sub per assessment
- Your settings (timezone, country, default assessor, default visit length, invoice terms and prefix, Assessment Record form id)

**Never duplicated:** the live schedule, punches, and photos stay in ZenSched. The local database stores *references* to them plus the few facts you need to answer "was I on site", "export Oak Lane", and "who owes me" without paying to re-read records.

### Privacy note

Everything that identifies an occupant or an official register identifier lives only in the local database: `assessments.occupant_name`, `occupant_phone`, `access_notes`, `rrn`, `places.access_notes`, `places.uprn`, and `assessors.accreditation_no`. `SKILL.md` forbids the AI from putting any of them into any ZenSched field, including location names, event titles, notes, and cancellation reasons (subs see those). Location name is `EPC 14 Oak Lane`; event title is `EPC EPC-2026-0001 - 14 Oak Lane` — never the occupant. The Assessment Record form itself tells the assessor not to write names, codes, UPRN, or RRN in it. You are still responsible for your own privacy obligations (the local database, your email, your phone); this kit narrows what a third party sees, it does not make you compliant by itself.

## How it works day to day

Your AI assistant has two sets of tools:

1. **ZenSched tools** (`location_create`, `event_create`, `shift_create`, `shift_status`, `form_submissions`, `form_export`, ...) that talk to ZenSched over the internet.
2. **A SQLite tool** (`sqlite_query`, `sqlite_execute`) that reads and writes `epc-assess.db` on your computer.

When you paste an agent's email, the AI extracts the agency, instruction number, type, occupant, address, time, and fee; adds the agency if new; looks the address up in your `places` cache (a house you assessed years ago is reused, a new address is geocoded once); saves the assessment as `EPC-2026-0001`; creates a **same-day** event and a shift on ZenSched with the Assessment Record attached; and confirms in one line. You see the visit on your phone, check in at the door (GPS-verified), walk the property, fill in the Assessment Record (type, band, photos), and check out. In the evening you say "record this week" and the AI pulls your verified times and the records, updates each assessment, and tells you what is now receivable. "Export the Oak Lane pack" writes the evidence pack (GPS times + photo links) — still not lodgement. "Invoice Hartwell" produces a plain-text invoice under their terms; "who owes me money" ages what is open. In agency mode, "what do I owe Reese" lists their split per job. You never run SQL yourself. `SKILL.md` in this repo is the instruction sheet that teaches the AI how to do all of this; you paste it into your AI tool once.

A typical visit costs about **$0.35** on ZenSched (cached address): GPS in $0.10 + GPS out $0.10 + reading an Assessment Record that has photos $0.15. Geocoding a new property is $0.03 once. The AI states the cost before it spends.

## Setup

### 0. What you need

- **An AI tool that supports MCP.** These instructions use Claude Desktop (Windows or Mac). Cursor works too.
- **Node.js 20 or newer.** The SQLite tool runs on it. Download the LTS installer from [nodejs.org](https://nodejs.org/) and run it with the defaults. This is the only software install.
- You do **not** need the `sqlite3` command-line program, Python, or Git.

### 1. Make a folder for your data

Create a folder where the database will live and write down its full path. Examples:

- Windows: `C:\Users\YourName\epc-assess`
- Mac: `/Users/yourname/epc-assess`

The database file will be created automatically inside this folder the first time the AI uses it. This folder will contain occupant names and access codes; keep it on an encrypted, backed-up disk, not in a shared folder.

### 2. Add both tools to your AI's config file

Open the MCP configuration file for your AI tool:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json` (paste that into the File Explorer address bar)
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: Settings → Developer → Edit Config)
- **Cursor:** Settings → MCP → Add new global MCP server

Paste in the contents of `mcp.json.example` from this repo, then change one line, the `SQLITE_PATH`, to point at your folder from step 1 plus `\epc-assess.db` (Windows) or `/epc-assess.db` (Mac):

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "epc-assess-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/epc-assess/epc-assess.db" }
    }
  }
}
```

**Windows path gotcha:** inside a JSON file every backslash must be doubled. Write `"C:\\Users\\YourName\\epc-assess\\epc-assess.db"`, not `"C:\Users\..."`. A single backslash will silently break the config.

**Leave `zsc_your_key_here` exactly as it is for now.** You do not have a key yet. The ZenSched tools that create your account work without one, and you will fill this in during step 3.

Save the file and **fully quit and reopen** your AI tool (on Mac, Cmd-Q; on Windows, right-click the tray icon → Quit). It only reads this file on startup.

### 3. Create your ZenSched account

In a new chat, type:

> Call `zensched_guide`, then call `account_create` with org_name "My EPC Assessor" (use my real business name if I told you one). Show me the `zsc_` key it returns.

Copy the `zsc_` key. Go back to the config file from step 2, replace `zsc_your_key_here` with your real key, save, and fully quit and reopen the AI tool again.

Some clients can adopt the key mid-session with `account_use_key`; you can ask the AI to try that to keep going immediately, but still update the config file so the key survives restarts. Keep the key private; it is the password to your account.

### 4. Create the database tables

Open `schema.sql` from this repo in any text editor, copy the whole thing, and paste it into the chat with this message in front of it:

> Create these tables in my epc-assess database. Run each statement one at a time using the SQLite tool, then list the tables to confirm.

The AI will run the statements one at a time and confirm the tables exist. The `epc-assess.db` file now exists in your folder.

If you happen to have the `sqlite3` command-line tool, `sqlite3 epc-assess.db < schema.sql` does the same thing, but it is not required.

### 5. Teach the AI the workflow

Paste the contents of `SKILL.md` into your AI tool as standing instructions. In Claude Desktop, create a Project and put it in the project instructions; in Cursor, save it as a rule. Then tell it your basics once:

> My business is Ridgeway EPC in Bristol, British Summer Time. Save that in settings, invite me as the assessor, and set up the Assessment Record form.

It writes those to the `settings` table, invites you as a worker, creates the Assessment Record form on ZenSched (free), and saves the form id so every visit gets it automatically.

**Check-in radius.** The default pin uses `checkin_radius_m=75` on `location_create`, but ZenSched **enforces** the radius through the account's policy, not per property. With geofencing on it raises anything under 100 m to about 91 m (300 ft), so 75 behaves as roughly a house-and-driveway circle. For a mansion block, a gated development, or a pin that lands on the road, ask the AI to "set the check-in radius to 200 m" (`policy_update`) or to move the pin onto the building (`location_update`, free). Do not ask it to widen the radius "on that location" — that field is informational only.

### 6. Funding (only when asked)

The first 200 ZenSched tool calls per day are free. Some things are metered: creating a location (geocoding, $0.03), inviting an assessor ($0.25), each GPS-verified check-in or check-out ($0.10), and reading an Assessment Record ($0.05, or $0.15 when it has photos). When a metered call happens without funds, the AI will get a `payment_required` response and tell you how to add the $5 activation deposit, which is credited to your balance. You will not be charged without seeing this first.

A typical visit is about $0.35 (in + out + photo record) on a cached address, or $0.38 the first time you add the property. The AI states the cost before it spends.

## Using it

Everything after setup is plain English. Examples:

- "Add Hartwell & Co as an estate agent, net 30, £85 domestic, £35 trip."
- "Hartwell just emailed — 14 Oak Lane, Redland, Bristol BS6 6UT, Thursday 10th at 10, domestic £85, key safe 4419, occupant Priya Shah."
- "Book a commercial for North Somerset Housing at the depot on Winterstoke Road, Tuesday 11, £150."
- "What's today?"
- "Record this week's assessments."
- "Export the Oak Lane pack."
- "Draft invoices for everyone with uninvoiced work."
- "Who still owes me money?"
- "Hartwell paid INV-2026-0001."
- "No access at Harbour View — book a revisit Friday."

See `QUICKSTART.md` for the first-week walkthrough and `example-workflow.md` for exactly which tools the AI calls behind each of these.

### What "invoice" means here

"Draft an invoice" records the invoice in your database (number, date, due date, amount, which assessments) and the AI writes out a plain-text invoice you can paste into an email or text message, with a line per visit and a note that the visit was GPS-verified. It does **not** generate a PDF, email it for you, or collect payment. Invoices do not list rating bands, UPRN, RRN, or accreditation numbers unless you ask. Each invoice footer says the visit record is not official lodgement — the legal EPC / BER stays in scheme software. When the agency pays, tell the AI ("Hartwell paid INV-2026-0001") and it marks it paid. If you outgrow this, the invoice records are simple enough to import into any accounting tool. VAT is out of scope.

## Mobile app for assessors

- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [TestFlight](https://testflight.apple.com/join/Wp51m5Yq)

When you invite an assessor (including yourself), they get an email, install the app, and can immediately see their visits, check in and out with GPS verification, and fill in the Assessment Record with photos. The record is attached to each visit automatically. There is no signature step — they tap Submit.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| AI says it has no ZenSched tools | Config file not saved, or the app was not fully restarted | Check the JSON is valid (paste it into [jsonlint.com](https://jsonlint.com)), then quit and reopen the app |
| AI says it has no SQLite / `epc-assess-db` tools | Node.js not installed, or bad `SQLITE_PATH` | Install Node.js LTS; on Windows check every backslash is doubled |
| `SQLITE_PATH` points nowhere / "unable to open database" | Folder from step 1 does not exist | Create the folder; the file is created automatically but the folder is not |
| ZenSched tools return an auth error | Key still says `zsc_your_key_here`, or was pasted with a space | Re-paste the key, restart |
| `payment_required` | Metered call with no balance | Follow the instructions in the response; $5 deposit |
| AI creates shifts at the wrong hour | Timezone not set, or daylight saving changed and `settings.timezone_offset` is stale | "Set my timezone offset to +01:00" (BST) or `+00:00` (GMT / winter). Ireland uses the same. The stored offset is a fixed string and does not flip itself. UK/IE BST starts the last Sunday in March and ends the last Sunday in October (2026-10-25); after that, `+01:00` puts every shift an hour late. |
| Appointment not on my phone | Booked locally but the ZenSched shift was never created (`needs_shift = 1`) | "Put today's assessments on my phone"; the AI finishes the intake steps |
| Check-in not GPS-verified at a mansion block / gated development | You parked outside the policy radius, or the pin is on the road | "Set the check-in radius to 200 m" (`policy_update`), or "move the pin to the main entrance" (`location_update`, free; the cached place keeps it), or `location_refine` ($0.10). Do not ask to widen the radius "on that location". |
| App would not let me check in 15 minutes early | Early check-in window too small | "Allow check-in 20 minutes before the shift" (`checkin_slack_min`) |
| Forgot to check out | Shift still `checked_in` | Tell the AI the real time; ask for a 15-minute check-out reminder |
| Assessment Record not on the phone | Form not assigned to that visit's event before the shift was created | "Attach the Assessment Record to EPC-2026-0004" (`form_assign(form_id, event_id=…)`); it installs on the existing shift, no cancel/recreate. Recreating with the same `shift-epc-{id}` key would only replay the cancelled shift for 24 hours |
| Photos have no date/GPS printed on them | Working as intended | ZenSched does not burn a stamp onto the image. The punch record holds the GPS/time. Use a camera overlay if you need pixels stamped. |
| AI refuses to put the occupant's name, UPRN, RRN, or the key-safe code on ZenSched | Working as intended | Occupant PII, register ids, and access codes stay on your computer |
| Same property geocoded twice | Address typed differently ("Lane" vs "Ln", postcode on a new line) | Tell the AI it is the same place; it merges the `places` rows and keeps one location |
| Appointment moved to another day fails on `shift_update` | Events are single-day | The AI cancels the shift and creates a new assessment (`rescheduled_from`) with its own event; ask it to |
| Assessment numbers look like invoices | You numbered an assessment `INV-` | Assessments are `EPC-YYYY-0001`; invoices are `INV-YYYY-0001`. Leave `assessment_no` NULL and the trigger assigns `EPC-`. |
| AI offers to lodge the EPC, write an RRN, or produce a certificate PDF | It shouldn't | This kit is not the official register and not RdSAP / DEAP lodgement. Use your scheme software. |
| AI asks you to run SQL yourself | It does not have `SKILL.md` loaded | Re-paste `SKILL.md` as project instructions |

If something is confusing or broken in ZenSched itself, ask the AI to call `feedback_submit` with a description. It is free, needs no account, and a human reads every submission.

## For developers

**Architecture.** Two MCP servers, no application code. The agent is the integration layer; `SKILL.md` is the spec it follows. ZenSched is authoritative for operations (schedule, punches, form submissions); SQLite is authoritative for agencies, places (properties), roster, assessments (including all occupant PII, UPRN, RRN, and access codes), billing, and payouts; each side stores only the other's **integer** IDs, plus a per-assessment summary and the GPS stamps cached locally because submission reads are metered. The PII boundary is enforced by data placement (occupant / register columns exist only locally, and the views compute the ZenSched-safe `zensched_location_name` / `zensched_event_title` strings) and by `SKILL.md` rules 2–3; there is no technical control stopping a misbehaving agent, so review the rules if you swap models.

**Data model decisions.**

- **Hierarchy is agencies → places (properties) → assessment visits.** `agencies` is who pays. `places` is the address cache (one ZenSched **location** per property, permanent, `places.zensched_location_id` as an integer). `assessments` is the driving table: one row per visit.
- **One-off appointments, not recurring routes.** Lawn / pest kits expand a cadence onto a per-site event rolled every 60 days. EPC work is a dated appointment at a property (and a re-assessment about every 10 years), so there is no recurrence table and no event roll. Each assessment maps to exactly one `event_create(location_id, title, start_date=<date>, end_date=<date>, idempotency_key="event-epc-{assessment_id}")` and one `shift_create(event_id, worker_id, start, end, idempotency_key="shift-epc-{assessment_id}")`, with `form_assign(form_id, event_id=...)` in between so the shift installs the form on the phone. **Events are capped at 60 days by ZenSched**; this kit never approaches that because every event is one day. A revisit or a day-change is a new `assessments` row with its own event.
- **`places` is an address de-dup cache.** `places.normalized_address` is `UNIQUE`; the agent normalizes (lowercase, strip `,` `.` `#`, collapse whitespace, include city and postcode) and looks it up before any `location_create`. A hit reuses `zensched_location_id`, which saves the $0.03 geocode and, more importantly, preserves any hand-tuned pin (`location_update`) for a mansion block the assessor returns to. Normalization is done by the agent rather than a trigger because SQLite cannot collapse whitespace cleanly. Created with `location_create(name, street_address=..., checkin_radius_m=75, idempotency_key="loc-place-{place_id}")`. `checkin_radius_m` on `location_create` is informational; the enforced radius is `policy_update(0, '{"checkin_radius_m": N}')`, and with geofencing on the platform raises values under 100 m to 300 ft.
- **Solo mode is the default; agency mode is additive.** The owner is invited as a ZenSched worker (`worker_invite` with their own email, $0.25) and stored on `assessors` with `is_owner = 1`; `settings.default_assessor_id` points at that row and the `fill_assessment_defaults` trigger assigns it when `assessor_id` is left NULL. Subs are further `assessors` rows with `payout_type` `CHECK IN ('flat', 'percent')` and `payout_value`. `payouts_due` and `payouts_missing` exclude `is_owner = 1`.
- **Receivables and payouts, not timesheets.** Assessors are paid per certificate by the agency, often net 30, so the money model is per-assessment fees → `billable_assessments` → `invoices` with the agency's `payment_terms_days` → `invoices_outstanding` aging. Subs are paid per assessment (split), so `payouts` is per assessment, not hourly. `timesheet_export` appears in `SKILL.md` only as an optional free hours record. VAT is out of scope.
- **`billable_total` is computed in a view, not stored.** The fee columns on `assessments` (`assessment_fee`, `trip_fee`, `other_fee`) are snapshots filled by trigger from the agency's defaults when left NULL (`trip_fee` falls back to `assessment_fee` so a no-access still bills). Which of them are owed depends on `status`, and that rule lives once, in `billable_assessments`: `completed` → fee + other; `no_access` → trip + other; `cancelled` → `other_fee` only; everything else → 0. `receivables_by_agency`, the invoice `INSERT ... SELECT`, `payouts_due`, and the `fill_payout_amount` trigger all read from that view.
- **`assessment_no`** is assigned by trigger as `EPC-{YYYY of scheduled_start}-{assessment_id:04d}` when left NULL; an explicit value is kept. **Do not use `INV-`** — that prefix is `invoices.invoice_number` (`{prefix}-{YYYY}-{invoice_id:04d}`).
- **`scheduled_start` is local wall-clock time without an offset** (`2026-09-10T10:00`, `CHECK`-constrained to reject a trailing offset or `Z`). `assessments_today` / `assessments_upcoming` emit `start_iso` and `end_iso` by appending `settings.timezone_offset`, with `end_iso` via `datetime(..., '+N minutes')`. Day-based views use `date('now', 'localtime')` because the SQLite MCP server runs on the owner's computer, whose clock is in the business's time zone; `date('now')` would be UTC and would roll "today" over at midnight UTC.
- **No signature field on the form.** ZenSched replaces the Submit button with the signature pad when a form has a `signature` field. The assessor is alone in a dwelling and submits with a normal button. `evidence` is a `photo` field (`max_images: 4`); a submission with photos bills $0.15 instead of $0.05.
- **GPS stamps are copied once.** `checked_in_at`, `checked_out_at`, `gps_verified`, `checkin_distance_m` are filled from `shift_status` at close-out so "was I on site" and the evidence pack are answered locally. ZenSched remains the original.
- **`exported_at`** gates `reports_to_export`. The agent sets it after writing the evidence pack so the same visit does not keep appearing at session start.
- **Reschedules.** Same day → `shift_update` and update `scheduled_start`. Different day → the single-day event cannot move, so `shift_cancel`, mark the row `rescheduled`, insert a new row with `rescheduled_from` (self-referencing FK, `ON DELETE SET NULL`), and create a new event/shift. Only the new row bills.
- `assessments.zensched_shift_id`, `assessors.zensched_worker_id`, `payouts.assessment_id`, and `places.normalized_address` are `UNIQUE`. `PRAGMA foreign_keys = ON` is in `schema.sql` and `SKILL.md` tells the agent to run it per session. Deleting an agency cascades to assessments, invoices, and payouts; deleting an assessor sets `assessments.assessor_id` NULL and removes their payouts; `places` is `ON DELETE RESTRICT` while assessments reference it.

**Assessment Record form.** Created once with `form_create(title, fields_json, idempotency_key="form-assessment-record")`; the exact `fields_json` is in `SKILL.md` and `example-workflow.md` (byte-identical) and was validated against ZenSched's `_validate_fields`. Every field carries an explicit `identifier` so submission `data` keys are stable (`property_type`, `rating_band`, `evidence`, `visit_outcome`, `notes`; section `sec_assessment`). Option keys are derived by ZenSched from the labels (lowercase, non-alphanumerics → `_`, truncated at 30 characters): `house` / `flat` / `bungalow` / `maisonette` / `park_home` / `other`; `a`–`g`; `completed` / `no_access` / `incomplete`. Every option here is well under 30 characters, so nothing truncates. `rating_band` is not required so a no-access visit can submit without inventing a band — it is a working note, **not** the official register band. **No `signature` field.** The form section text states this is not the official EPC register and not RdSAP / DEAP lodgement. Attaching is `form_assign(form_id, event_id=...)` per assessment; a late assign installs on the existing shift (do not cancel and recreate).

**Idempotency keys.** Deterministic, derived from local IDs:

- location: `loc-place-{place_id}`
- event: `event-epc-{assessment_id}`
- shift: `shift-epc-{assessment_id}` (an assessor swap, a same-day extra, or any replacement after `shift_cancel` appends the next unused suffix: `-2`, then `-3`, … — never reuse a suffix, or the 24-hour replay returns the cancelled shift)
- assignment: `assign-assessment-{event_id}`
- cancel: `cancel-shift-{shift_id}`
- worker: `worker-{email}`
- form: `form-assessment-record`

ZenSched caches idempotent responses for 24 hours. The views emit `loc_idempotency_key`, `event_idempotency_key`, and `shift_idempotency_key` per row.

**Timestamps.** `shift_create` / `shift_update` take `start` and `end` in ISO 8601 with an explicit offset. Always use the business's local offset from `settings.timezone_offset` (e.g. `2026-09-10T10:00:00+01:00`), never `Z`. The views build these strings so the agent does not have to. The stored offset is a fixed string: UK/IE is `+01:00` (BST) from the last Sunday in March through the last Sunday in October, and `+00:00` (GMT) otherwise — update the setting at each clock change or every November shift is an hour off. `checked_in_at` / `checked_out_at` keep the offset ZenSched returns.

**Metered reads.** `form_submissions(form_id, event_id=...)` is the natural per-assessment read because every assessment has its own event; `form_export` covers a week or a single event in one call and is what "export Oak Lane" uses. Both bill $0.05 per submission ($0.15 with a photo), once per submission ever. `shift_list`, `shift_status`, `event_get`, and `timesheet_export(mode="hours"|"raw")` are free.

**Check-in policy.** The radius is enforced by `policy_update(0, '{"checkin_radius_m": N}')`, not by `location_create(checkin_radius_m=...)`, which is informational; with geofencing on, values under 100 m are raised to about 91 m. `checkin_slack_min` matters for assessors who arrive early. The kit's example sets 150 m / 20 min / 15 min check-out reminder.

**SQLite MCP server.** `mcp.json.example` uses [`easy-sqlite-mcp`](https://github.com/chenkumi/easy-sqlite-mcp) (Node, `better-sqlite3`, `SQLITE_PATH` env var). Its `sqlite_execute` calls `prepare()`, so it accepts **one statement per call**; `schema.sql` is written so every statement stands alone and is idempotent. `payouts_due` uses a window function (`SUM() OVER`), which needs SQLite ≥ 3.25 (2018); `better-sqlite3` bundles a current SQLite. Any SQLite MCP server with read and write tools will work; adjust the tool names in `SKILL.md`.

**Schema test.** The schema was verified by splitting the file into its 45 statements with `sqlite3.complete_statement` and executing each individually (as the MCP server does) twice for idempotency (seed rows not duplicated), then exercising: all 7 tables, 9 views, and 8 triggers present; every view on an empty database; `places.normalized_address`, `assessors.zensched_worker_id`, `assessments.zensched_shift_id`, and `payouts.assessment_id` `UNIQUE`; integer types on ZenSched ID columns; the `number_assessment` trigger (`EPC-YYYY-0001`, explicit number kept); `fill_assessment_defaults` (duration from settings and following a changed setting, assessor from `default_assessor_id`, fee from agency, trip from `default_trip_fee`, trip falling back to fee when the agency has no trip, explicit fee/duration kept); `assessments_today` / `assessments_upcoming` (`start_iso` / `end_iso` with offset for `HH:MM` and `HH:MM:SS` inputs and 60/90-minute durations, `needs_location` when the place has no location id, `needs_shift`, the three idempotency keys, `zensched_event_title` / `zensched_location_name` equal to `EPC` + street / `EPC {assessment_no} - {street}` with no occupant name, worker id from the default assessor, 7-day window bounds, cancelled excluded); `updated_at` triggers on agencies, places, assessors, and assessments; `needs_location` (includes unpinned places with open work, drops a place after `zensched_location_id` is set); `reports_to_export` (empty without `report_dc_id`, includes a completed House/C visit, empty after `exported_at`); `billable_assessments` for completed (85 = fee), no_access (trip only), cancelled (`other_fee` only), and confirmed (0); `receivables_by_agency` totals, counts, and the drop-off after invoicing; invoice numbering (auto `INV-2026-0001`, explicit number kept); `invoices_outstanding` aging buckets `90+` / `current` with `days_past_due` and paid excluded; `payouts_missing`; `payouts_due` math for flat (55) and percent (70% of 95 = 66.50), `needs_amount` for an assessor without a split, owner exclusion, paid rows dropping out; `rescheduled_from`; every `CHECK` (agency type, assessment type, status, `scheduled_start` format with offset and `Z` rejected, duration range, property type, rating band A–G, visit outcome, payout type, country); foreign keys rejecting an unknown agency or place, `RESTRICT` on places, `SET NULL` on assessor delete, and the full cascade on agency delete. Form payload validated against `_validate_fields` (6 fields, no signature, SKILL.md byte-identical to example-workflow.md, every option key ≤ 30 characters). 154 checks, all passing.

## Support

- ZenSched docs: <https://www.zensched.com/docs/>
- Tool reference: <https://www.zensched.com/docs/tools/>
- Feedback: ask your AI to call `feedback_submit` (categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`)

## License

MIT. See `LICENSE`.
