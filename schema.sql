-- ZenSched EPC Assessor Local Database Schema
-- SQLite database for agencies (estate agents, solicitors, landlords,
-- housing associations), a cache of properties (places), the assessor
-- roster, one-off assessment visits, agency invoices / receivables, and
-- subcontractor payouts.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, timesheets).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my epc-assess database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 epc-assess.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.
--
-- THIS FORM IS NOT THE OFFICIAL EPC REGISTER, NOT RdSAP / SAP / DEAP
-- LODGEMENT, AND NOT A SOURCE OF RRN / BER NUMBERS. Nothing here submits
-- a certificate to Landmark, the Scottish EPC Register, or the SEAI BER
-- register. Nothing here is RdSAP / SAP / SBEM / DEAP calculation software.
-- The Assessment Record is property type + a working A-G note (not the
-- register band) + evidence photos. You still lodge in Elmhurst, Quidos,
-- ECMK, Stroma, DEAP, or your scheme's portal.
--
-- PRIVACY: occupant names, occupant phones, access notes (key-safe codes,
-- lockbox, "keys with neighbour"), assessor accreditation numbers, UPRN,
-- and RRN live ONLY in this file on your computer: assessments.occupant_name,
-- assessments.occupant_phone, assessments.access_notes, places.access_notes,
-- assessors.accreditation_no, places.uprn, assessments.rrn. ZenSched
-- receives, per assessment, a location label made of "EPC" and the street
-- ("EPC 14 Oak Lane"), the street address for the GPS pin, a matching
-- event title ("EPC EPC-2026-0001 - 14 Oak Lane"), and the Assessment
-- Record the assessor fills in on the phone. SKILL.md forbids the agent
-- from putting any local-only column into a ZenSched field.
--
-- PHOTOS: ZenSched stores the upload and the GPS punch separately. It does
-- NOT burn a date, time, or GPS stamp onto the image pixels.
--
-- EVENTS: one ZenSched event per assessment visit, start_date = end_date =
-- the visit date (one day). ZenSched caps events at 60 days; a one-day
-- event is well under that. There is no 60-day event roll on a property —
-- EPC visits are appointments, not a route. A 10-year re-assessment is a
-- new assessments row that reuses the cached place (and its pin).

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE to work. SKILL.md tells the agent to run it
-- at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session (timezone, defaults, business name, form id).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My EPC Assessor');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '+00:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('country', 'UK');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_assessor_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_visit_minutes', '60');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_travel_buffer_minutes', '20');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '30');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');
INSERT OR IGNORE INTO settings (key, value) VALUES ('assessment_form_id', NULL);

-- Agencies: who books you and who pays you. An estate agent, a solicitor,
-- a private landlord, a housing association, a local authority, a developer,
-- or a homeowner booking direct. payment_terms_days drives invoice due dates;
-- default_fee / default_trip_fee are copied onto the assessment when the
-- instruction does not state a fee.
CREATE TABLE IF NOT EXISTS agencies (
  agency_id INTEGER PRIMARY KEY AUTOINCREMENT,
  agency_name TEXT NOT NULL,
  agency_type TEXT NOT NULL DEFAULT 'estate_agent'
    CHECK (agency_type IN ('estate_agent', 'solicitor', 'landlord', 'housing_assoc', 'local_authority', 'developer', 'direct', 'other')),
  contact_name TEXT,                                -- LOCAL ONLY: booker / AP
  contact_phone TEXT,
  billing_email TEXT,
  payment_terms_days INTEGER NOT NULL DEFAULT 30,   -- net 30; direct / cash = 0
  default_fee REAL,                                 -- £ per completed assessment
  default_trip_fee REAL,                            -- £ wasted journey / no access
  notes TEXT,
  is_active INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Places: a cache of properties (dwellings / premises) -> ZenSched location
-- ids. The same house is re-assessed about every 10 years (or on a sale),
-- so the pin must survive. normalized_address is the de-dup key: the agent
-- builds it as lowercase(address + city + postcode) with commas, periods,
-- and '#' removed and whitespace collapsed to single spaces (SQLite cannot
-- collapse whitespace, so the agent does it). The agent looks here FIRST
-- and only calls location_create (geocode, $0.03) on a miss. Hand-tuned
-- pins (location_update) therefore survive for mansion blocks and gated
-- developments. street_name (house number + street, no occupant) feeds
-- location and event titles. access_notes and uprn are LOCAL ONLY.
CREATE TABLE IF NOT EXISTS places (
  place_id INTEGER PRIMARY KEY AUTOINCREMENT,
  normalized_address TEXT NOT NULL UNIQUE,
  address TEXT NOT NULL,
  city TEXT,
  region TEXT,                                      -- county / local authority
  postcode TEXT,                                    -- UK postcode or IE Eircode
  country TEXT NOT NULL DEFAULT 'UK'
    CHECK (country IN ('UK', 'IE')),
  street_name TEXT,                                 -- '14 Oak Lane' (number + street); used in titles
  place_label TEXT,                                 -- sent to ZenSched: 'EPC 14 Oak Lane'
  uprn TEXT,                                        -- LOCAL ONLY: Unique Property Reference Number
  zensched_location_id INTEGER,                     -- from location_create (permanent; integer)
  access_notes TEXT,                                -- LOCAL ONLY: key safe, lockbox, 'keys with neighbour'
  is_repeat_site INTEGER DEFAULT 1,                 -- 1 = expect a later re-assessment at this address
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Assessors: in solo mode this is one row (you, is_owner = 1) whose
-- zensched_worker_id came from inviting yourself. In agency mode add a row
-- per subcontracted DEA / NDEA with payout_type/payout_value
-- ('flat' = £ per assessment, 'percent' = % of the billable total).
-- accreditation_no (DEA / NDEA / scheme number) is LOCAL ONLY.
CREATE TABLE IF NOT EXISTS assessors (
  assessor_id INTEGER PRIMARY KEY AUTOINCREMENT,
  assessor_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  zensched_worker_id INTEGER UNIQUE,                -- from worker_invite (integer)
  is_owner INTEGER DEFAULT 0,                       -- 1 = the business owner (no payouts)
  accreditation_no TEXT,                            -- LOCAL ONLY: DEA / NDEA / scheme number
  scheme_name TEXT,                                 -- Elmhurst, Quidos, ECMK, Stroma, ...
  payout_type TEXT
    CHECK (payout_type IS NULL OR payout_type IN ('flat', 'percent')),
  payout_value REAL,                                -- £ (flat) or % (percent)
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Assessments: THE driving table. One row per assessment visit. Each row
-- maps to exactly one ZenSched event (start_date = end_date = the visit
-- date — one event per visit, well under the 60-day cap) and one shift
-- (the appointment window). There is no recurrence and no 60-day event
-- roll on the place. A no-access callback is a new assessments row
-- (rescheduled_from) with its own event.
--
-- assessment_no is EPC-YYYY-0001 (INV- is reserved for invoices).
--
-- scheduled_start is LOCAL wall-clock time as 'YYYY-MM-DDTHH:MM' or
-- 'YYYY-MM-DDTHH:MM:SS' with NO offset and no 'Z'; the views append
-- settings.timezone_offset to produce start_iso / end_iso for shift_create.
--
-- Fees are per-visit snapshots. Leave them NULL on insert and the
-- fill_assessment_defaults trigger copies the agency's default_fee /
-- default_trip_fee (trip falls back to fee so a no-access still bills
-- unless they set a lower trip). Which fees are billable depends on
-- status; see the billable_assessments view.
--
-- occupant_name, occupant_phone, access_notes, rrn are LOCAL ONLY and
-- never reach ZenSched. Report summary columns and GPS stamps are copied
-- from form_submissions / shift_status once, so "export Oak Lane" is
-- answered from SQLite after the first metered read.
CREATE TABLE IF NOT EXISTS assessments (
  assessment_id INTEGER PRIMARY KEY AUTOINCREMENT,
  assessment_no TEXT UNIQUE,                        -- 'EPC-2026-0001', filled by trigger if NULL
  agency_id INTEGER NOT NULL,
  agency_ref TEXT,                                  -- agent's instruction / works order
  assessment_type TEXT NOT NULL DEFAULT 'domestic'
    CHECK (assessment_type IN ('domestic', 'new_build', 'commercial', 'revisit')),
  occupant_name TEXT,                               -- LOCAL ONLY
  occupant_phone TEXT,                              -- LOCAL ONLY
  place_id INTEGER NOT NULL,
  scheduled_start TEXT NOT NULL                     -- local 'YYYY-MM-DDTHH:MM[:SS]', no offset
    CHECK (scheduled_start GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-2][0-9]:[0-5][0-9]*'
           AND scheduled_start NOT GLOB '*T*[+-]*'
           AND scheduled_start NOT GLOB '*Z'),
  duration_minutes INTEGER                          -- NULL -> settings.default_visit_minutes
    CHECK (duration_minutes IS NULL OR duration_minutes BETWEEN 15 AND 480),
  assessor_id INTEGER,                              -- NULL -> settings.default_assessor_id (trigger)
  status TEXT NOT NULL DEFAULT 'confirmed'
    CHECK (status IN ('requested', 'confirmed', 'completed', 'no_access', 'cancelled', 'rescheduled')),
  assessment_fee REAL,                              -- NULL -> agency default_fee (trigger)
  trip_fee REAL,                                    -- NULL -> agency default_trip_fee, else fee (trigger)
  other_fee REAL,                                   -- late-cancel, wait, extra visit
  access_notes TEXT,                                -- LOCAL ONLY: key-safe for this visit
  rrn TEXT,                                         -- LOCAL ONLY: Report Reference Number after YOU lodge
  zensched_event_id INTEGER,                        -- one same-day event per assessment
  zensched_shift_id INTEGER UNIQUE,                 -- one shift per assessment
  report_dc_id INTEGER,                             -- Assessment Record submission_id
  checked_in_at TEXT,                               -- from shift_status (ISO with offset)
  checked_out_at TEXT,
  gps_verified INTEGER,                             -- 1 if the check-in punch was on site
  checkin_distance_m INTEGER,
  property_type TEXT                                -- form option label
    CHECK (property_type IS NULL OR property_type IN ('House', 'Flat', 'Bungalow', 'Maisonette', 'Park home', 'Other')),
  rating_band TEXT                                  -- form option label; NULL when not surveyed
    CHECK (rating_band IS NULL OR rating_band IN ('A', 'B', 'C', 'D', 'E', 'F', 'G')),
  visit_outcome TEXT                                -- form option label
    CHECK (visit_outcome IS NULL OR visit_outcome IN ('Completed', 'No access', 'Incomplete')),
  photo_count INTEGER,
  photo_urls TEXT,                                  -- JSON array of CDN URLs, filled on the one read
  notes TEXT,
  invoiced INTEGER DEFAULT 0,
  paid_out INTEGER DEFAULT 0,                       -- 1 = sub payout done (agency mode)
  exported_at TEXT,                                 -- when the evidence pack was produced
  rescheduled_from INTEGER,                         -- previous assessment_id when this row is the reschedule
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (agency_id) REFERENCES agencies(agency_id) ON DELETE CASCADE,
  FOREIGN KEY (place_id) REFERENCES places(place_id) ON DELETE RESTRICT,
  FOREIGN KEY (assessor_id) REFERENCES assessors(assessor_id) ON DELETE SET NULL,
  FOREIGN KEY (rescheduled_from) REFERENCES assessments(assessment_id) ON DELETE SET NULL
);

-- Invoices: one per agency per billing run. invoice_number is filled by
-- trigger if left NULL (INV-YYYY-0001 — different prefix from assessment_no).
-- due_date is invoice_date + the agency's payment_terms_days. line_items is
-- a JSON array with one object per assessment so the invoice can be
-- regenerated. Never put occupant name, UPRN, RRN, or accreditation numbers
-- in line_items.
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  agency_id INTEGER NOT NULL,
  invoice_number TEXT UNIQUE,                       -- 'INV-2026-0001'
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,
  paid_date TEXT,
  sent_date TEXT,
  line_items TEXT,                                  -- JSON array
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (agency_id) REFERENCES agencies(agency_id) ON DELETE CASCADE
);

-- Payouts: what you owe a subcontracted assessor for one assessment
-- (agency mode). One row per assessment. amount is filled by trigger when
-- left NULL: flat -> assessors.payout_value; percent -> billable_total *
-- payout_value / 100. Never insert a payout for the owner row.
CREATE TABLE IF NOT EXISTS payouts (
  payout_id INTEGER PRIMARY KEY AUTOINCREMENT,
  assessor_id INTEGER NOT NULL,
  assessment_id INTEGER NOT NULL UNIQUE,
  amount REAL,                                      -- trigger fills if NULL
  paid INTEGER DEFAULT 0,
  paid_date TEXT,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (assessor_id) REFERENCES assessors(assessor_id) ON DELETE CASCADE,
  FOREIGN KEY (assessment_id) REFERENCES assessments(assessment_id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_places_location ON places(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_assessments_start ON assessments(scheduled_start);
CREATE INDEX IF NOT EXISTS idx_assessments_status_start ON assessments(status, scheduled_start);
CREATE INDEX IF NOT EXISTS idx_assessments_agency ON assessments(agency_id, invoiced);
CREATE INDEX IF NOT EXISTS idx_assessments_place ON assessments(place_id);
CREATE INDEX IF NOT EXISTS idx_assessments_assessor ON assessments(assessor_id, paid_out);
CREATE INDEX IF NOT EXISTS idx_assessments_event ON assessments(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_assessments_export ON assessments(status, report_dc_id, exported_at);
CREATE INDEX IF NOT EXISTS idx_invoices_agency ON invoices(agency_id);
CREATE INDEX IF NOT EXISTS idx_invoices_paid ON invoices(paid, due_date);
CREATE INDEX IF NOT EXISTS idx_payouts_assessor ON payouts(assessor_id, paid);

-- Which fees are billable depends on what happened. This is the single place
-- that rule lives; receivables, invoicing, and payouts all read billable_total
-- from here rather than re-deriving it.
--   completed  -> assessment + trip is unused + other
--   no_access  -> trip_fee + other                 (wasted journey)
--   cancelled  -> other_fee only                   (a late-cancel fee the owner puts in other_fee)
--   requested / confirmed / rescheduled -> 0
CREATE VIEW IF NOT EXISTS billable_assessments AS
SELECT
  a.assessment_id,
  a.assessment_no,
  a.agency_id,
  a.agency_ref,
  a.assessment_type,
  a.status,
  date(a.scheduled_start)                          AS assessment_date,
  a.scheduled_start,
  a.assessor_id,
  a.assessment_fee,
  a.trip_fee,
  a.other_fee,
  CASE a.status
    WHEN 'completed' THEN round(COALESCE(a.assessment_fee, 0) + COALESCE(a.other_fee, 0), 2)
    WHEN 'no_access' THEN round(COALESCE(a.trip_fee, 0) + COALESCE(a.other_fee, 0), 2)
    WHEN 'cancelled' THEN round(COALESCE(a.other_fee, 0), 2)
    ELSE 0
  END                                              AS billable_total,
  a.invoiced,
  a.paid_out,
  a.zensched_shift_id,
  a.report_dc_id,
  a.place_id
FROM assessments a;

-- Keep updated_at current
CREATE TRIGGER IF NOT EXISTS update_agency_timestamp
AFTER UPDATE ON agencies
BEGIN
  UPDATE agencies SET updated_at = datetime('now') WHERE agency_id = NEW.agency_id;
END;

CREATE TRIGGER IF NOT EXISTS update_place_timestamp
AFTER UPDATE ON places
BEGIN
  UPDATE places SET updated_at = datetime('now') WHERE place_id = NEW.place_id;
END;

CREATE TRIGGER IF NOT EXISTS update_assessor_timestamp
AFTER UPDATE ON assessors
BEGIN
  UPDATE assessors SET updated_at = datetime('now') WHERE assessor_id = NEW.assessor_id;
END;

CREATE TRIGGER IF NOT EXISTS update_assessment_timestamp
AFTER UPDATE OF agency_id, agency_ref, assessment_type, occupant_name, occupant_phone,
                place_id, scheduled_start, duration_minutes, assessor_id, status,
                assessment_fee, trip_fee, other_fee, access_notes, rrn,
                zensched_event_id, zensched_shift_id, report_dc_id,
                checked_in_at, checked_out_at, gps_verified, checkin_distance_m,
                property_type, rating_band, visit_outcome, photo_count, photo_urls,
                notes, invoiced, paid_out, exported_at, rescheduled_from
ON assessments
BEGIN
  UPDATE assessments SET updated_at = datetime('now') WHERE assessment_id = NEW.assessment_id;
END;

-- Auto-number assessments: EPC-2026-0001, EPC-2026-0002, ... (year of the
-- appointment, sequence = assessment_id). Do NOT use INV- — that is invoices.
CREATE TRIGGER IF NOT EXISTS number_assessment
AFTER INSERT ON assessments
WHEN NEW.assessment_no IS NULL
BEGIN
  UPDATE assessments
  SET assessment_no = 'EPC-' || strftime('%Y', NEW.scheduled_start) || '-' || printf('%04d', NEW.assessment_id)
  WHERE assessment_id = NEW.assessment_id;
END;

-- Fill defaults the agent left NULL:
--   duration_minutes <- settings.default_visit_minutes (else 60)
--   assessor_id      <- settings.default_assessor_id (solo mode: you)
--   assessment_fee   <- agency's default_fee, else 0
--   trip_fee         <- agency's default_trip_fee, else default_fee, else 0
--   other_fee        <- 0
-- Fees are snapshots: changing an agency's defaults later never rewrites history.
CREATE TRIGGER IF NOT EXISTS fill_assessment_defaults
AFTER INSERT ON assessments
BEGIN
  UPDATE assessments
  SET duration_minutes = COALESCE(NEW.duration_minutes,
                                  (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_visit_minutes'),
                                  60),
      assessor_id = COALESCE(NEW.assessor_id,
                             (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_assessor_id' AND value IS NOT NULL)),
      assessment_fee = COALESCE(NEW.assessment_fee,
                                (SELECT default_fee FROM agencies WHERE agency_id = NEW.agency_id),
                                0),
      trip_fee = COALESCE(NEW.trip_fee,
                          (SELECT default_trip_fee FROM agencies WHERE agency_id = NEW.agency_id),
                          (SELECT default_fee FROM agencies WHERE agency_id = NEW.agency_id),
                          0),
      other_fee = COALESCE(NEW.other_fee, 0)
  WHERE assessment_id = NEW.assessment_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- Payout amount from the assessor's split when the agent leaves it NULL.
-- flat    -> payout_value
-- percent -> billable_total * payout_value / 100, rounded to pence
-- If the assessor has no payout_type the amount stays NULL and payouts_due flags it.
CREATE TRIGGER IF NOT EXISTS fill_payout_amount
AFTER INSERT ON payouts
WHEN NEW.amount IS NULL
BEGIN
  UPDATE payouts
  SET amount = (SELECT CASE s.payout_type
                         WHEN 'flat'    THEN s.payout_value
                         WHEN 'percent' THEN round(b.billable_total * s.payout_value / 100.0, 2)
                       END
                FROM assessors s
                JOIN billable_assessments b ON b.assessment_id = NEW.assessment_id
                WHERE s.assessor_id = NEW.assessor_id)
  WHERE payout_id = NEW.payout_id;
END;

-- Today's assessments (local date of the computer running the database),
-- open statuses only. One row = one visit to put on the phone. start_iso /
-- end_iso carry settings.timezone_offset and are ready for shift_create.
-- The three idempotency keys and the ZenSched names are ready too.
--   needs_location = 1 -> the place has no ZenSched location yet
--   needs_shift    = 1 -> the assessment has no ZenSched shift yet
-- zensched_location_name / zensched_event_title are "EPC" + street
-- ("EPC 14 Oak Lane") with no occupant name. Event title also carries
-- the assessment number.
CREATE VIEW IF NOT EXISTS assessments_today AS
SELECT
  a.assessment_id,
  a.assessment_no,
  a.status,
  a.assessment_type,
  a.scheduled_start,
  a.duration_minutes,
  strftime('%Y-%m-%dT%H:%M:%S', a.scheduled_start)
    || (SELECT value FROM settings WHERE key = 'timezone_offset')                 AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(a.scheduled_start, '+' || a.duration_minutes || ' minutes'))
    || (SELECT value FROM settings WHERE key = 'timezone_offset')                 AS end_iso,
  g.agency_id,
  g.agency_name,
  g.agency_type,
  a.agency_ref,
  a.occupant_name,
  a.occupant_phone,
  p.place_id,
  p.address,
  p.city,
  p.region,
  p.postcode,
  p.country,
  p.address || COALESCE(', ' || p.city, '') || COALESCE(' ' || p.postcode, '')     AS street_address,
  'EPC ' || COALESCE(p.street_name, p.place_label, p.address)                     AS zensched_location_name,
  'EPC ' || a.assessment_no || ' - ' || COALESCE(p.street_name, p.place_label, p.address) AS zensched_event_title,
  p.access_notes                                                                  AS place_access_notes,
  a.access_notes,
  p.uprn,
  p.is_repeat_site,
  p.zensched_location_id,
  CASE WHEN p.zensched_location_id IS NULL THEN 1 ELSE 0 END                      AS needs_location,
  a.zensched_event_id,
  a.zensched_shift_id,
  CASE WHEN a.zensched_shift_id IS NULL THEN 1 ELSE 0 END                         AS needs_shift,
  a.assessor_id,
  s.assessor_name,
  s.zensched_worker_id,
  a.assessment_fee,
  a.trip_fee,
  a.notes,
  'loc-place-' || p.place_id                                                      AS loc_idempotency_key,
  'event-epc-' || a.assessment_id                                                 AS event_idempotency_key,
  'shift-epc-' || a.assessment_id                                                 AS shift_idempotency_key
FROM assessments a
JOIN agencies g ON g.agency_id = a.agency_id
JOIN places p ON p.place_id = a.place_id
LEFT JOIN assessors s ON s.assessor_id = a.assessor_id
WHERE a.status IN ('requested', 'confirmed')
  AND date(a.scheduled_start) = date('now', 'localtime')
ORDER BY a.scheduled_start;

-- Same columns, next 7 days (today through today + 6).
CREATE VIEW IF NOT EXISTS assessments_upcoming AS
SELECT
  a.assessment_id,
  a.assessment_no,
  a.status,
  a.assessment_type,
  a.scheduled_start,
  a.duration_minutes,
  strftime('%Y-%m-%dT%H:%M:%S', a.scheduled_start)
    || (SELECT value FROM settings WHERE key = 'timezone_offset')                 AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(a.scheduled_start, '+' || a.duration_minutes || ' minutes'))
    || (SELECT value FROM settings WHERE key = 'timezone_offset')                 AS end_iso,
  g.agency_id,
  g.agency_name,
  g.agency_type,
  a.agency_ref,
  a.occupant_name,
  a.occupant_phone,
  p.place_id,
  p.address,
  p.city,
  p.region,
  p.postcode,
  p.country,
  p.address || COALESCE(', ' || p.city, '') || COALESCE(' ' || p.postcode, '')     AS street_address,
  'EPC ' || COALESCE(p.street_name, p.place_label, p.address)                     AS zensched_location_name,
  'EPC ' || a.assessment_no || ' - ' || COALESCE(p.street_name, p.place_label, p.address) AS zensched_event_title,
  p.access_notes                                                                  AS place_access_notes,
  a.access_notes,
  p.uprn,
  p.is_repeat_site,
  p.zensched_location_id,
  CASE WHEN p.zensched_location_id IS NULL THEN 1 ELSE 0 END                      AS needs_location,
  a.zensched_event_id,
  a.zensched_shift_id,
  CASE WHEN a.zensched_shift_id IS NULL THEN 1 ELSE 0 END                         AS needs_shift,
  a.assessor_id,
  s.assessor_name,
  s.zensched_worker_id,
  a.assessment_fee,
  a.trip_fee,
  a.notes,
  'loc-place-' || p.place_id                                                      AS loc_idempotency_key,
  'event-epc-' || a.assessment_id                                                 AS event_idempotency_key,
  'shift-epc-' || a.assessment_id                                                 AS shift_idempotency_key
FROM assessments a
JOIN agencies g ON g.agency_id = a.agency_id
JOIN places p ON p.place_id = a.place_id
LEFT JOIN assessors s ON s.assessor_id = a.assessor_id
WHERE a.status IN ('requested', 'confirmed')
  AND date(a.scheduled_start) BETWEEN date('now', 'localtime') AND date('now', 'localtime', '+6 days')
ORDER BY a.scheduled_start;

-- Places that still need a ZenSched pin, limited to ones with an open
-- assessment so a leftover empty row does not clutter the list.
CREATE VIEW IF NOT EXISTS needs_location AS
SELECT
  p.place_id,
  p.address,
  p.city,
  p.postcode,
  p.country,
  p.street_name,
  p.place_label,
  p.address || COALESCE(', ' || p.city, '') || COALESCE(' ' || p.postcode, '')     AS street_address,
  p.access_notes,
  p.zensched_location_id,
  'loc-place-' || p.place_id                                                      AS loc_idempotency_key,
  COUNT(a.assessment_id)                                                          AS open_assessment_count,
  MIN(a.scheduled_start)                                                          AS first_scheduled_start,
  MIN(a.assessment_type)                                                          AS first_assessment_type
FROM places p
JOIN assessments a ON a.place_id = p.place_id
                  AND a.status IN ('requested', 'confirmed')
WHERE p.zensched_location_id IS NULL
GROUP BY p.place_id
ORDER BY first_scheduled_start;

-- Completed assessments whose Assessment Record is on file but has not yet
-- been turned into an evidence pack for the agency (or for your own lodgement
-- file). "Export Oak Lane" reads this, calls form_export + shift_status,
-- then sets exported_at. This pack is NOT lodgement.
CREATE VIEW IF NOT EXISTS reports_to_export AS
SELECT
  a.assessment_id,
  a.assessment_no,
  a.assessment_type,
  a.status,
  date(a.scheduled_start)                          AS assessment_date,
  a.scheduled_start,
  g.agency_id,
  g.agency_name,
  g.billing_email,
  a.agency_ref,
  p.place_id,
  p.street_name,
  p.address || COALESCE(', ' || p.city, '') || COALESCE(' ' || p.postcode, '')     AS street_address,
  a.zensched_event_id,
  a.zensched_shift_id,
  a.report_dc_id,
  a.checked_in_at,
  a.checked_out_at,
  a.gps_verified,
  a.checkin_distance_m,
  a.property_type,
  a.rating_band,
  a.visit_outcome,
  a.photo_count,
  a.exported_at,
  s.assessor_name
FROM assessments a
JOIN agencies g ON g.agency_id = a.agency_id
JOIN places p ON p.place_id = a.place_id
LEFT JOIN assessors s ON s.assessor_id = a.assessor_id
WHERE a.status = 'completed'
  AND a.report_dc_id IS NOT NULL
  AND a.exported_at IS NULL
ORDER BY a.scheduled_start;

-- Uninvoiced billable work grouped by agency, with the billing contact and
-- terms. Completed assessments bill the fee; no-access bills trip; cancellations
-- bill other_fee only (see billable_assessments).
CREATE VIEW IF NOT EXISTS receivables_by_agency AS
SELECT
  g.agency_id,
  g.agency_name,
  g.agency_type,
  g.contact_name,
  g.billing_email,
  g.payment_terms_days,
  COUNT(b.assessment_id)                           AS assessment_count,
  SUM(CASE WHEN b.status = 'completed' THEN 1 ELSE 0 END) AS completed_count,
  SUM(CASE WHEN b.status = 'no_access' THEN 1 ELSE 0 END) AS no_access_count,
  SUM(b.billable_total)                            AS total_billable,
  MIN(b.assessment_date)                           AS first_date,
  MAX(b.assessment_date)                           AS last_date
FROM billable_assessments b
JOIN agencies g ON g.agency_id = b.agency_id
WHERE b.invoiced = 0
  AND b.status IN ('completed', 'no_access', 'cancelled')
  AND b.billable_total > 0
GROUP BY g.agency_id
ORDER BY total_billable DESC;

-- Unpaid invoices with aging. days_past_due is negative while not yet due.
--   current : not yet due
--   30      : 1-30 days past due
--   60      : 31-60 days past due
--   90+     : more than 60 days past due (chase now)
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  inv.invoice_id,
  inv.invoice_number,
  g.agency_id,
  g.agency_name,
  g.agency_type,
  g.contact_name,
  g.billing_email,
  g.payment_terms_days,
  inv.invoice_date,
  inv.due_date,
  inv.sent_date,
  inv.total_amount,
  CAST(julianday(date('now', 'localtime')) - julianday(inv.due_date) AS INTEGER) AS days_past_due,
  CASE
    WHEN julianday(date('now', 'localtime')) - julianday(inv.due_date) <= 0  THEN 'current'
    WHEN julianday(date('now', 'localtime')) - julianday(inv.due_date) <= 30 THEN '30'
    WHEN julianday(date('now', 'localtime')) - julianday(inv.due_date) <= 60 THEN '60'
    ELSE '90+'
  END                                              AS aging_bucket,
  CASE WHEN inv.due_date < date('now', 'localtime') THEN 1 ELSE 0 END AS overdue
FROM invoices inv
JOIN agencies g ON g.agency_id = inv.agency_id
WHERE inv.paid = 0
ORDER BY inv.due_date;

-- Agency mode: unpaid sub payouts, one row per assessment, with a running
-- total per assessor (assessor_total_due). Owner rows never appear.
-- needs_amount = 1 means the assessor has no payout_type; ask the owner.
CREATE VIEW IF NOT EXISTS payouts_due AS
SELECT
  p.payout_id,
  s.assessor_id,
  s.assessor_name,
  s.email,
  s.payout_type,
  s.payout_value,
  a.assessment_id,
  a.assessment_no,
  date(a.scheduled_start)                          AS assessment_date,
  a.assessment_type,
  a.status,
  b.billable_total,
  p.amount,
  CASE WHEN p.amount IS NULL THEN 1 ELSE 0 END     AS needs_amount,
  SUM(p.amount) OVER (PARTITION BY s.assessor_id)  AS assessor_total_due,
  a.invoiced                                       AS agency_invoiced
FROM payouts p
JOIN assessors s ON s.assessor_id = p.assessor_id
JOIN assessments a ON a.assessment_id = p.assessment_id
JOIN billable_assessments b ON b.assessment_id = a.assessment_id
WHERE p.paid = 0
  AND s.is_owner = 0
ORDER BY s.assessor_name, a.scheduled_start;

-- Agency mode: completed / no-access assessments worked by a sub that have
-- no payouts row yet. The agent inserts one per row when recording completion.
CREATE VIEW IF NOT EXISTS payouts_missing AS
SELECT
  a.assessment_id,
  a.assessment_no,
  a.status,
  date(a.scheduled_start)                          AS assessment_date,
  a.assessment_type,
  s.assessor_id,
  s.assessor_name,
  s.payout_type,
  s.payout_value,
  b.billable_total
FROM assessments a
JOIN assessors s ON s.assessor_id = a.assessor_id AND s.is_owner = 0
JOIN billable_assessments b ON b.assessment_id = a.assessment_id
WHERE a.status IN ('completed', 'no_access')
  AND NOT EXISTS (SELECT 1 FROM payouts p WHERE p.assessment_id = a.assessment_id)
ORDER BY a.scheduled_start;
