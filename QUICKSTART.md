# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

Before you start, read the "This is not official EPC lodgement" section of `README.md`. Short version: this kit puts each assessment on your phone, GPS-stamps arrival at the property, and collects a photo Assessment Record (property type, working rating band A–G, up to 4 evidence photos). It does **not** lodge a certificate with Landmark / the Scottish register / SEAI, does not run RdSAP, and does not burn a GPS stamp onto photos. Occupant names, key-safe codes, UPRN, RRN, and your DEA number stay on your computer; ZenSched only ever sees an `EPC 14 Oak Lane` label, a street address, and the Assessment Record.

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\epc-assess` (Windows) or `/Users/yourname/epc-assess` (Mac). Note the full path. It will hold occupant names and key-safe codes, so keep it on an encrypted, backed-up disk.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

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

- On Windows, double every backslash: `"C:\\Users\\YourName\\epc-assess\\epc-assess.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "Ridgeway EPC". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my epc-assess database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> My business is Ridgeway EPC in Bristol, British Summer Time. It's just me, Owen Hale, owen@ridgewayepc.example. Save that to settings, invite me as the assessor, and create the Assessment Record form.

The AI saves your settings, invites you as a worker ($0.25) so visits land on your phone, and calls `form_create` once (free) to build the Assessment Record: property type, rating band A–G, up to 4 evidence photos, visit outcome, notes. No signature. It stores the form id so every visit gets it.

## 6. Add your first two bookings

> Add Hartwell & Co as an estate agent, net 30, £85 a domestic, £35 trip. Then book 14 Oak Lane, Redland, Bristol BS6 6UT, Thursday 2026-09-10 at 10, domestic £85. Occupant Priya Shah. Key safe 4419.

> Add a one-off for Maya Chen (landlord) at Flat 3, 8 Harbour View, Portishead BS20 7HG, Friday 2026-09-11 at 14:00, £85. Keys with the neighbour at number 6.

Behind the scenes the AI inserts each agency and place, calls `location_create` (geocode, $0.03, may trigger the $5 activation deposit the first time), creates a **same-day** `event_create` for the visit (well under the 60-day cap), attaches the Assessment Record with `form_assign`, creates the shift, and saves the integer IDs. Occupant names and key notes go only into the local database. You just see a confirmation with an `EPC-2026-0001` number.

## 7. Check-in radius (optional)

> Set the check-in radius to 150 m and allow check-in 20 minutes early.

That is `policy_update` on the account policy — not "on that location". 75 m on `location_create` is informational; with geofencing on, values under 100 m are raised to about 91 m / 300 ft anyway.

## 8. Do the work

Install the app from the invite email ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [iOS TestFlight](https://testflight.apple.com/join/Wp51m5Yq)). Each booking appears on your phone. Check in at the door (GPS-verified), walk the property, fill in the Assessment Record (property type, band, up to 4 photos), tap Submit — there is no signature step — and check out.

## 9. After the visits

> Record this week's assessments, export the Oak Lane pack, then draft invoices for anyone with uninvoiced work.

The AI pulls the completed, GPS-verified shifts and the Assessment Records from ZenSched (reading records is metered, so it tells you the cost first), saves a per-visit summary, writes the evidence pack as text (not lodgement), creates invoice records, and writes out each invoice as text you can paste into an email.

> Hartwell paid INV-2026-0001.

Marks it paid.

## What next

- `README.md` for the full explanation, the lodgement boundary, troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above
