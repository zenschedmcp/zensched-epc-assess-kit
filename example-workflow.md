# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for a first week of operation, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

The business is **Ridgeway EPC**, a solo Domestic Energy Assessor (Owen Hale) in Bristol, British Summer Time (`+01:00` in September; UK/IE BST ends the last Sunday in October — 2026-10-25 — then GMT `+00:00`. Views stamp `settings.timezone_offset` onto `start_iso` / `end_iso`, so flip the setting first or every November shift is an hour late). IDs and responses are illustrative. ZenSched IDs are integers. Watch what does **not** cross to ZenSched: the occupants' names and phone numbers, the key-safe codes, UPRN, RRN, Owen's DEA number. ZenSched sees `EPC 14 Oak Lane`, a street address, and a photo Assessment Record.

This is **not** the official EPC register and **not** RdSAP / SAP / DEAP lodgement. The Assessment Record's A–G field is a working note, not the register band.

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = My EPC Assessor, timezone_offset = +00:00, country = UK,
    default_assessor_id = NULL, default_visit_minutes = 60,
    default_travel_buffer_minutes = 20, invoice_due_days = 30, invoice_prefix = INV,
    assessment_form_id = NULL
sqlite_query:   SELECT * FROM reports_to_export;     → (none)
sqlite_query:   SELECT * FROM assessments_today;     → (none)
```

## "We're Ridgeway EPC in Bristol, British Summer Time. It's just me, Owen Hale, owen@ridgewayepc.example, 0117 555 0144. DEA 1234, Elmhurst."

```
sqlite_execute: UPDATE settings SET value = 'Ridgeway EPC' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '+01:00' WHERE key = 'timezone_offset';
sqlite_execute: UPDATE settings SET value = 'UK' WHERE key = 'country';
```

Agent (first metered call this session, rule 11):

> Saved. I'll schedule everything in British Summer Time (+01:00). Since you're the assessor on the phone, I need to invite you to ZenSched as a worker so your visits show up in the app; that's a one-time $0.25. If your account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
worker_invite:
  email: "owen@ridgewayepc.example"
  first_name: "Owen"
  last_name: "Hale"
  idempotency_key: "worker-owen@ridgewayepc.example"
  → worker_id: 801, status: "invited", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.25 }

sqlite_execute:
  INSERT INTO assessors (assessor_name, email, phone, zensched_worker_id, is_owner,
                         accreditation_no, scheme_name)
  VALUES ('Owen Hale', 'owen@ridgewayepc.example', '0117 555 0144', 801, 1,
          'DEA 1234', 'Elmhurst');
  → lastInsertRowid = 1

sqlite_execute: UPDATE settings SET value = '1' WHERE key = 'default_assessor_id';
```

The DEA number is **not** sent to ZenSched. It lives only in `assessors.accreditation_no`.

> You're invited; install the app from the email. Your visits will land on your own phone. Your DEA number stays on your computer. Next, the Assessment Record: it's free to create and every visit comes back with property type, a working A–G note, up to four evidence photos, and a visit outcome. No signature — this is not the official EPC register and not RdSAP / DEAP lodgement. Want me to set it up now?

Owner: *"yes"*

```
form_create:
  title: "Assessment Record"
  idempotency_key: "form-assessment-record"
  fields_json: (the JSON below, passed as one string)
```

```json
[
  {"type": "section", "label": "Assessment record", "identifier": "sec_assessment",
   "text": "Internal visit record and evidence photos only. This form is NOT the official EPC register, not an RdSAP / SAP / DEAP calculation, and not lodgement. Lodge in Elmhurst, Quidos, Stroma, DEAP, or your scheme portal. The A-G field is a working note, not the register band. Do not write UPRN, RRN, occupant names, or access codes here."},
  {"type": "select", "label": "Property type", "identifier": "property_type", "required": true,
   "options": ["House", "Flat", "Bungalow", "Maisonette", "Park home", "Other"]},
  {"type": "select", "label": "Rating band", "identifier": "rating_band",
   "options": ["A", "B", "C", "D", "E", "F", "G"]},
  {"type": "photo", "label": "Evidence photos", "identifier": "evidence", "max_images": 4},
  {"type": "select", "label": "Visit outcome", "identifier": "visit_outcome", "required": true,
   "options": ["Completed", "No access", "Incomplete"]},
  {"type": "textarea", "label": "Notes", "identifier": "notes"}
]
```

```
  → form_id: 501, fields: [ ...6 fields echoed with identifiers... ]

sqlite_execute: UPDATE settings SET value = '501' WHERE key = 'assessment_form_id';
```

> Assessment Record form created. I'll attach it to every visit automatically. There is no signature step. Submitting it does not lodge a certificate, does not write to the official register, and is not RdSAP / DEAP.

Optional, if the owner wants a wider circle for mansion blocks:

```
policy_get: policy_id 0
policy_update:
  policy_id: 0
  settings_json: '{"geofence_enabled": true, "require_on_site": true, "checkin_radius_m": 150, "checkin_slack_min": 20, "checkout_reminder_min_after": 15}'
```

The radius is on the **policy**, not on any location.

## "Add Hartwell & Co as an estate agent, net 30, £85 a domestic, £35 trip. Contact Jan on 0117 555 0190, billing@hartwell.example."

```
sqlite_execute:
  INSERT INTO agencies (agency_name, agency_type, contact_name, contact_phone, billing_email,
                        payment_terms_days, default_fee, default_trip_fee)
  VALUES ('Hartwell & Co', 'estate_agent', 'Jan', '0117 555 0190', 'billing@hartwell.example',
          30, 85.00, 35.00);
  → lastInsertRowid = 1
```

> Added Hartwell & Co, estate agent, net 30, £85 domestic / £35 trip.

## "Hartwell just emailed — 14 Oak Lane, Redland, Bristol BS6 6UT, Thursday 2026-09-10 at 10, domestic £85. Occupant Priya Shah. Key safe 4419. Their ref HW-4412."

```
sqlite_query:   SELECT agency_id, default_fee, default_trip_fee FROM agencies WHERE agency_name LIKE '%Hartwell%';
  → 1, 85.00, 35.00

sqlite_query:   SELECT place_id, zensched_location_id FROM places
                WHERE normalized_address = '14 oak lane redland bristol bs6 6ut';
  → (none)

sqlite_execute:
  INSERT INTO places (normalized_address, address, city, region, postcode, country,
                      street_name, place_label, access_notes, is_repeat_site)
  VALUES ('14 oak lane redland bristol bs6 6ut', '14 Oak Lane', 'Redland', 'Bristol', 'BS6 6UT', 'UK',
          '14 Oak Lane', 'EPC 14 Oak Lane',
          'Key safe 4419.', 1);
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO assessments (agency_id, agency_ref, assessment_type, occupant_name, place_id,
                           scheduled_start, status)
  VALUES (1, 'HW-4412', 'domestic', 'Priya Shah', 1,
          '2026-09-10T10:00', 'confirmed');
  → lastInsertRowid = 1
  -- trigger: assessment_no → EPC-2026-0001
  -- trigger: duration_minutes → 60, assessor_id → 1, assessment_fee → 85, trip_fee → 35, other_fee → 0
```

Agent (metered geocode, rule 11):

> Creating 14 Oak Lane on ZenSched costs $0.03 for geocoding. If your account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
location_create:
  name: "EPC 14 Oak Lane"
  street_address: "14 Oak Lane, Redland, BS6 6UT"
  checkin_radius_m: 75
  idempotency_key: "loc-place-1"
  → location_id: 9201, lat: 51.4731, lng: -2.6038, pin_quality: "street"
    billing: { meter: "geocode", units: 1, price: 0.03 }

sqlite_execute: UPDATE places SET zensched_location_id = 9201 WHERE place_id = 1;
```

Priya's name and the key-safe code are **not** in `notes`. They live only in `assessments.occupant_name` and `places.access_notes`. `checkin_radius_m` on the location is informational; the enforced radius is the policy.

```
event_create:
  location_id: 9201
  title: "EPC EPC-2026-0001 - 14 Oak Lane"
  start_date: "2026-09-10"
  end_date:   "2026-09-10"          ← same-day event (well under the 60-day cap)
  idempotency_key: "event-epc-1"
  → event_id: 7301

form_assign:
  form_id: 501
  event_id: 7301
  idempotency_key: "assign-assessment-7301"
  → status: "assigned", form_id: 501, event_id: 7301, policy_id: 0

shift_create:
  event_id: 7301
  worker_id: 801
  start: "2026-09-10T10:00:00+01:00"
  end:   "2026-09-10T11:00:00+01:00"
  idempotency_key: "shift-epc-1"
  → shift_id: 89011, status: "scheduled", forms_installed: [501]

sqlite_execute:
  UPDATE assessments SET zensched_event_id = 7301, zensched_shift_id = 89011
  WHERE assessment_id = 1;
```

> Booked EPC-2026-0001 for Hartwell at 14 Oak Lane, Thu 10 Sep 10:00–11:00, £85 domestic. The Assessment Record is on your phone. Key safe 4419 and Priya's name stay on your computer. This is not the official EPC register and not RdSAP / DEAP lodgement. About $0.38 once you punch and I read the photo record (new address).

## "Add a one-off for Maya Chen (landlord) at Flat 3, 8 Harbour View, Portishead BS20 7HG, Friday 2026-09-11 at 14:00, £85. Keys with the neighbour at number 6."

Same pattern. The agent does not re-ask about the $0.03 (owner already approved geocoding this session). Agency type is `landlord`, terms 0 (cash / direct).

```
sqlite_execute:
  INSERT INTO agencies (agency_name, agency_type, contact_name, billing_email,
                        payment_terms_days, default_fee, default_trip_fee)
  VALUES ('Maya Chen', 'landlord', 'Maya Chen', 'maya.chen@example.com',
          0, 85.00, 35.00);
  → lastInsertRowid = 2

sqlite_execute:
  INSERT INTO places (normalized_address, address, city, region, postcode, country,
                      street_name, place_label, access_notes, is_repeat_site)
  VALUES ('flat 3 8 harbour view portishead bs20 7hg', 'Flat 3, 8 Harbour View', 'Portishead',
          'North Somerset', 'BS20 7HG', 'UK',
          '8 Harbour View', 'EPC 8 Harbour View',
          'Keys with neighbour at number 6.', 1);
  → lastInsertRowid = 2

sqlite_execute:
  INSERT INTO assessments (agency_id, assessment_type, occupant_name, place_id,
                           scheduled_start, status, assessment_fee)
  VALUES (2, 'domestic', 'Maya Chen', 2,
          '2026-09-11T14:00', 'confirmed', 85.00);
  → lastInsertRowid = 2
  -- trigger: assessment_no → EPC-2026-0002

location_create:
  name: "EPC 8 Harbour View"
  street_address: "Flat 3, 8 Harbour View, Portishead, BS20 7HG"
  checkin_radius_m: 75
  idempotency_key: "loc-place-2"
  → location_id: 9202

event_create:
  location_id: 9202
  title: "EPC EPC-2026-0002 - 8 Harbour View"
  start_date: "2026-09-11"
  end_date:   "2026-09-11"
  idempotency_key: "event-epc-2"
  → event_id: 7302

form_assign: form_id 501, event_id 7302, idempotency_key "assign-assessment-7302"

shift_create:
  event_id: 7302
  worker_id: 801
  start: "2026-09-11T14:00:00+01:00"
  end:   "2026-09-11T15:00:00+01:00"
  idempotency_key: "shift-epc-2"
  → shift_id: 89012

sqlite_execute:
  UPDATE assessments SET zensched_event_id = 7302, zensched_shift_id = 89012
  WHERE assessment_id = 2;
```

> Booked EPC-2026-0002 for Maya Chen at 8 Harbour View, Fri 11 Sep 14:00–15:00, £85 domestic. Neighbour-keys note is local only. Same Assessment Record — not the official register, not RdSAP / DEAP lodgement.

## Owen does the work

Thursday 09:52, at 14 Oak Lane, in the ZenSched app: **Check in** (GPS: 14 m from the pin, verified, $0.10). Walks the house. Opens **Assessment Record**: Property type = House; Rating band = C; four photos (front elevation, loft hatch, boiler, meter); Visit outcome = Completed; Notes = "Solid wall, original windows, loft 100 mm. Working band C." Submits (no signature). **Check out** 10:48 ($0.10).

Friday 13:58, 8 Harbour View: neighbour not in. Assessment Record: Property type = Flat; Rating band blank; one door photo; Visit outcome = No access; Notes = "Keys with neighbour — not home. Will need a revisit." Check out 14:06.

## "Record this week's assessments."

```
shift_list:
  date_from: "2026-09-10"
  date_to:   "2026-09-13"
  status:    "checked_out"
  → shifts: [
      { shift_id: 89011, event_id: 7301, worker_id: 801, date: "2026-09-10", start: "10:00", end: "11:00", status: "checked_out" },
      { shift_id: 89012, event_id: 7302, worker_id: 801, date: "2026-09-11", start: "14:00", end: "15:00", status: "checked_out" }
    ], count: 2

sqlite_query: SELECT assessment_id, status, report_dc_id FROM assessments
              WHERE zensched_shift_id IN (89011, 89012);
  → 1, confirmed, NULL
    2, confirmed, NULL
```

Agent (metered read, rule 11):

> There are 2 Assessment Records to pull, both with photos, so about $0.30 ($0.15 each). I'll read them once and keep the summaries locally. That's the last piece of the ~$0.35/visit meter (punches already billed when you checked in and out). OK?

Owner: *"go"*

```
form_export:
  form_id: 501
  since: "2026-09-10"
  until: "2026-09-13"
  format: "json"
  → row_count: 2, submissions: [
      { submission_id: 5501, worker_id: 801, event_id: 7301, submitted_at: "2026-09-10 10:44:12",
        property_type: "house", rating_band: "c", visit_outcome: "completed",
        notes: "Solid wall, original windows, loft 100 mm. Working band C.",
        media_urls: "https://cdn.zensched.com/m/.../o1.jpg;https://cdn.zensched.com/m/.../o2.jpg;https://cdn.zensched.com/m/.../o3.jpg;https://cdn.zensched.com/m/.../o4.jpg" },
      { submission_id: 5502, worker_id: 801, event_id: 7302, submitted_at: "2026-09-11 14:04:40",
        property_type: "flat", visit_outcome: "no_access",
        notes: "Keys with neighbour — not home. Will need a revisit.",
        media_urls: "https://cdn.zensched.com/m/.../h1.jpg" }
    ]
    billing: { form_media: { units: 2, unit_price: "$0.15" }, note: "Each submission bills once ever (replays are free)." }
  -- form_submissions media items (if reading one visit) are
  -- { field_id, cdn_url, thumbnail_url, original_filename }

shift_status: shift_id 89011
  → status "checked_out", actual_in "2026-09-10T09:52:10+01:00", actual_out "2026-09-10T10:48:05+01:00",
    punches: [ { type: "in", gps_verified: true, distance_from_site_m: 14 },
               { type: "out", gps_verified: true, distance_from_site_m: 11 } ]
(free)

sqlite_execute:
  UPDATE assessments SET status = 'completed', report_dc_id = 5501,
    checked_in_at = '2026-09-10T09:52:10+01:00', checked_out_at = '2026-09-10T10:48:05+01:00',
    gps_verified = 1, checkin_distance_m = 14,
    property_type = 'House', rating_band = 'C', visit_outcome = 'Completed',
    photo_count = 4,
    photo_urls = '["https://cdn.zensched.com/m/.../o1.jpg","https://cdn.zensched.com/m/.../o2.jpg","https://cdn.zensched.com/m/.../o3.jpg","https://cdn.zensched.com/m/.../o4.jpg"]',
    notes = 'Solid wall, original windows, loft 100 mm. Working band C.'
  WHERE assessment_id = 1;

sqlite_execute:
  UPDATE assessments SET status = 'no_access', report_dc_id = 5502,
    checked_in_at = '2026-09-11T13:58:02+01:00', checked_out_at = '2026-09-11T14:06:18+01:00',
    gps_verified = 1, checkin_distance_m = 22,
    property_type = 'Flat', rating_band = NULL, visit_outcome = 'No access',
    photo_count = 1,
    photo_urls = '["https://cdn.zensched.com/m/.../h1.jpg"]',
    notes = 'Keys with neighbour — not home. Will need a revisit.'
  WHERE assessment_id = 2;
```

> Recorded 2 visits, both GPS-verified.
>
> **Oak Lane (EPC-2026-0001):** House / working band **C** / Completed. 4 photos. Lodge this in Elmhurst / DEAP yourself — I do not lodge, and that C is not the register band.
>
> **Harbour View (EPC-2026-0002):** Flat / **No access** — neighbour not in. Trip £35. No band recorded (correct). Say the word if you want a Friday revisit on the same place (reuses the pin, no new geocode).

## "Export the Oak Lane pack."

```
sqlite_query: SELECT * FROM reports_to_export WHERE assessment_no = 'EPC-2026-0001';
  → EPC-2026-0001 | domestic | completed | 2026-09-10 | Hartwell & Co | HW-4412
    | 14 Oak Lane, Redland BS6 6UT | evt 7301 | shift 89011 | submission 5501
    | in 09:52 verified 14 m | House | C | Completed | 4 photos

sqlite_execute: UPDATE assessments SET exported_at = date('now') WHERE assessment_id = 1;
```

> Evidence pack for EPC-2026-0001 — **not the official EPC register, not RdSAP / DEAP lodgement**:
>
> ```
> Ridgeway EPC  —  evidence pack  —  EPC-2026-0001
> Agency: Hartwell & Co   Ref: HW-4412
> Property: 14 Oak Lane, Redland, Bristol BS6 6UT
> Visit: 10 Sep 2026  09:52–10:48  GPS verified (14 m from pin)
>
> Property type: House
> Working rating band: C
> Visit outcome: Completed
>
> Photos:
>   https://cdn.zensched.com/m/.../o1.jpg
>   https://cdn.zensched.com/m/.../o2.jpg
>   https://cdn.zensched.com/m/.../o3.jpg
>   https://cdn.zensched.com/m/.../o4.jpg
>
> Notes: Solid wall, original windows, loft 100 mm. Working band C.
>
> Lodge in Elmhurst / Quidos / DEAP / Landmark yourself. This pack is your file copy — not the register.
> ```
>
> Tell me the RRN when you've lodged and I'll store it locally only.

## "Draft invoices for everyone with uninvoiced work."

```
sqlite_query: SELECT * FROM receivables_by_agency;
  → Hartwell & Co | 1 completed | 85.00 | 2026-09-10
    Maya Chen     | 1 no_access | 35.00 | 2026-09-11

sqlite_execute:
  INSERT INTO invoices (agency_id, invoice_date, due_date, total_amount, line_items)
  SELECT b.agency_id, date('now'),
         date('now', '+' || g.payment_terms_days || ' days'),
         SUM(b.billable_total),
         json_group_array(json_object('assessment_id', b.assessment_id, 'assessment_no', b.assessment_no,
                                      'date', b.assessment_date, 'type', b.assessment_type,
                                      'ref', b.agency_ref, 'status', b.status,
                                      'amount', b.billable_total, 'shift_id', b.zensched_shift_id))
  FROM billable_assessments b JOIN agencies g ON g.agency_id = b.agency_id
  WHERE b.invoiced = 0 AND b.agency_id = 1
    AND b.status IN ('completed', 'no_access', 'cancelled') AND b.billable_total > 0
  GROUP BY b.agency_id;

sqlite_execute: UPDATE assessments SET invoiced = 1 WHERE invoiced = 0 AND agency_id = 1
                AND status IN ('completed', 'no_access', 'cancelled');
sqlite_query:   SELECT invoice_number, invoice_date, due_date, total_amount FROM invoices WHERE invoice_id = last_insert_rowid();
  → INV-2026-0001 | 2026-09-11 | 2026-10-11 | 85.00     (number assigned by trigger)

(same three statements for agency 2 → INV-2026-0002, 35.00, due same day because terms = 0)
```

The agent then writes the invoices out as text:

> Here are your two invoices. Paste each into an email or text.
>
> ```
> Ridgeway EPC
> Invoice INV-2026-0001
> To: Hartwell & Co (billing@hartwell.example)
> Date: Sep 11, 2026    Due: Oct 11, 2026
>
>   Sep 10    Domestic EPC, 14 Oak Lane (HW-4412)    £85.00
>
> Total due: £85.00
> Visit GPS-verified at the property.
> Visit record and evidence photos on file — official EPC / BER is lodged in your scheme software, not in ZenSched.
> ```
>
> ```
> Ridgeway EPC
> Invoice INV-2026-0002
> To: Maya Chen (maya.chen@example.com)
> Date: Sep 11, 2026    Due: Sep 11, 2026
>
>   Sep 11    Wasted journey, 8 Harbour View          £35.00
>
> Total due: £35.00
> Visit GPS-verified at the property (no access).
> Visit record and evidence photos on file — official EPC / BER is lodged in your scheme software, not in ZenSched.
> ```
>
> Say "sent" when they're out and I'll note the date. Want me to book the Harbour View revisit?

## "Sent. Hartwell already paid. Book the Harbour View revisit for Friday 18th at 14."

```
sqlite_execute: UPDATE invoices SET sent_date = date('now') WHERE invoice_number IN ('INV-2026-0001', 'INV-2026-0002');
sqlite_execute: UPDATE invoices SET paid = 1, paid_date = date('now') WHERE invoice_number = 'INV-2026-0001';

sqlite_execute:
  INSERT INTO assessments (agency_id, assessment_type, occupant_name, place_id,
                           scheduled_start, status, rescheduled_from)
  VALUES (2, 'revisit', 'Maya Chen', 2,
          '2026-09-18T14:00', 'confirmed', 2);
  → lastInsertRowid = 3
  -- trigger: assessment_no → EPC-2026-0003
  -- same place_id 2, zensched_location_id 9202 already set — no geocode

event_create:
  location_id: 9202
  title: "EPC EPC-2026-0003 - 8 Harbour View"
  start_date: "2026-09-18"
  end_date:   "2026-09-18"
  idempotency_key: "event-epc-3"
  → event_id: 7303

form_assign: form_id 501, event_id 7303, idempotency_key "assign-assessment-7303"

shift_create:
  event_id: 7303
  worker_id: 801
  start: "2026-09-18T14:00:00+01:00"
  end:   "2026-09-18T15:00:00+01:00"
  idempotency_key: "shift-epc-3"
  → shift_id: 89013

sqlite_execute:
  UPDATE assessments SET zensched_event_id = 7303, zensched_shift_id = 89013
  WHERE assessment_id = 3;
```

> Marked both invoices sent and INV-2026-0001 paid. Maya's £35 (INV-2026-0002) is outstanding, due today.
>
> Booked EPC-2026-0003, revisit at 8 Harbour View, Fri 18 Sep 14:00. Reused the existing pin — no new geocode. Neighbour-keys note is still local only.

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| Hartwell contact, £85 / £35, Maya as landlord, prices | SQLite | CRM; ZenSched does not model rates or agencies |
| Occupant names, key safe, neighbour keys, DEA number, UPRN, RRN | SQLite **only** | Privacy; never sent to ZenSched |
| Each property's GPS location | ZenSched (integer ID in `places`) | Needed for geofenced check-in; reused on revisit |
| Each visit's same-day event and shift | ZenSched (integer IDs on `assessments`) | Shifts hang off events; one event per visit, never a 60-day roll |
| The Assessment Record form | ZenSched (ID in `settings`) | Installed on the assessor's phone per shift |
| Owen, his invite, his app | ZenSched (integer ID in `assessors`) | Workforce and notifications |
| GPS punches, actual times | ZenSched only | Verified record; queried via `shift_status` |
| Two Assessment Records with photos | ZenSched (originals); summary + photo URLs in `assessments` | Read once (metered), then packs / invoices from SQLite |
| Two invoices, one paid; one revisit booked | SQLite | Billing + the next visit |
