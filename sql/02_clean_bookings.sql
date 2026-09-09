-- ============================================================
-- Tembo Hotel bookings: cleaning script (PostgreSQL)
--
-- Input : tembo_hotel.staging_bookingss  (286 raw rows, every column TEXT)
-- Output: tembo_hotel.bookings            (typed, constrained production table)
--         tembo_hotel.rejected_bookings   (rows that break a business rule)
--
-- Run 01_rebuild_dirty_data.sql first (or import data/tembo_hotel_dirty.csv
-- into staging_bookingss), then run this file top to bottom in pgAdmin (F5).
--
-- Working rule used throughout: the raw staging table is never touched.
-- All cleaning happens on a copy, so any step can be undone by copying
-- the original column back from staging.
-- ============================================================

SET search_path TO tembo_hotel;

-- ------------------------------------------------------------
-- 0. Fresh working copy
-- ------------------------------------------------------------
DROP TABLE IF EXISTS cleaning_bookings;
CREATE TABLE cleaning_bookings AS
SELECT * FROM staging_bookingss;


-- ------------------------------------------------------------
-- 1. Duplicate bookings
--    BK0006 appears twice with identical values in all 20 columns.
--    ctid (the row's physical position) is the only thing that
--    differs, so it is used to delete exactly one copy.
-- ------------------------------------------------------------
DELETE FROM cleaning_bookings
WHERE ctid IN (
    SELECT ctid
    FROM (
        SELECT ctid,
               ROW_NUMBER() OVER (PARTITION BY booking_id ORDER BY ctid) AS rn
        FROM cleaning_bookings
    ) d
    WHERE rn > 1
);


-- ------------------------------------------------------------
-- 2. Text columns: trim, fix case, standardise spellings
-- ------------------------------------------------------------
UPDATE cleaning_bookings
SET guest_name        = NULLIF(INITCAP(TRIM(guest_name)), ''),
    staff_name        = NULLIF(INITCAP(TRIM(staff_name)), ''),
    staff_department  = NULLIF(INITCAP(TRIM(staff_department)), ''),
    guest_nationality = NULLIF(INITCAP(TRIM(guest_nationality)), ''),
    booking_status    = NULLIF(INITCAP(TRIM(booking_status)), ''),
    service_used      = NULLIF(INITCAP(TRIM(service_used)), '');

-- guest_city: 'NAIROBI', 'kisumu' and 'Thikax' (typo for Thika)
UPDATE cleaning_bookings
SET guest_city = CASE
    WHEN INITCAP(TRIM(guest_city)) = 'Thikax' THEN 'Thika'
    ELSE NULLIF(INITCAP(TRIM(guest_city)), '')
END;

-- room_type: 8 spellings for 4 room types
UPDATE cleaning_bookings
SET room_type = CASE
    WHEN UPPER(TRIM(room_type)) IN ('DLX', 'DELUXE')   THEN 'Deluxe'
    WHEN UPPER(TRIM(room_type)) IN ('STD', 'STANDARD') THEN 'Standard'
    ELSE NULLIF(INITCAP(TRIM(room_type)), '')
END;

-- payment_method: 'mpesa' next to 'M-Pesa'
UPDATE cleaning_bookings
SET payment_method = CASE
    WHEN LOWER(REPLACE(TRIM(payment_method), '-', '')) = 'mpesa' THEN 'M-Pesa'
    ELSE NULLIF(INITCAP(TRIM(payment_method)), '')
END;


-- ------------------------------------------------------------
-- 3. Phone numbers: '+254756789012', '0745-678-901', 'Null', blanks
--    Keep digits only, convert the +254 country code to a leading 0,
--    and turn anything that is not a number into NULL.
-- ------------------------------------------------------------
UPDATE cleaning_bookings
SET guest_phone = REGEXP_REPLACE(guest_phone, '[^0-9]', '', 'g');

UPDATE cleaning_bookings
SET guest_phone = REGEXP_REPLACE(guest_phone, '^254', '0')
WHERE guest_phone LIKE '254%';

UPDATE cleaning_bookings
SET guest_phone = NULL
WHERE guest_phone = '';


-- ------------------------------------------------------------
-- 4. Money and counts stored as text: 'KES 34000', 'KES ,', ',', ''
--    Keep digits (and a decimal point) only; empty means unknown.
-- ------------------------------------------------------------
UPDATE cleaning_bookings
SET room_rate_per_night = NULLIF(REGEXP_REPLACE(room_rate_per_night, '[^0-9.]', '', 'g'), ''),
    staff_salary        = NULLIF(REGEXP_REPLACE(staff_salary,        '[^0-9.]', '', 'g'), ''),
    total_amount        = NULLIF(REGEXP_REPLACE(total_amount,        '[^0-9.]', '', 'g'), ''),
    service_price       = NULLIF(REGEXP_REPLACE(service_price,       '[^0-9.]', '', 'g'), '');

-- nights_stayed: one row holds '-3'. A negative stay is not a value,
-- it is a missing value, so it becomes NULL and is re-derived from the
-- dates in step 6.
UPDATE cleaning_bookings
SET nights_stayed = NULL
WHERE nights_stayed !~ '^[0-9]+$' OR nights_stayed::INTEGER <= 0;


-- ------------------------------------------------------------
-- 5. Dates in four formats
--    10/01/2024   slashes, day first
--    28-01-24     dashes, two-digit year
--    15-11-2024   dashes, four-digit year, day first (first part > 12)
--    01-12-2024   dashes, four-digit year, month first (everything left)
--
--    The separators identify the format, so they are never stripped.
--    Each format is converted on its own and the result is written back
--    as YYYY-MM-DD. Order matters: the "first part > 12" rule must run
--    before the catch-all, and the catch-all only touches rows that
--    still start with two digits (clean dates start with four).
-- ------------------------------------------------------------
UPDATE cleaning_bookings
SET check_in_date = TO_DATE(check_in_date, 'DD/MM/YYYY')::TEXT
WHERE check_in_date LIKE '%/%';

UPDATE cleaning_bookings
SET check_in_date = TO_DATE(check_in_date, 'DD-MM-YY')::TEXT
WHERE check_in_date ~ '^\d{2}-\d{2}-\d{2}$';

UPDATE cleaning_bookings
SET check_in_date = TO_DATE(check_in_date, 'DD-MM-YYYY')::TEXT
WHERE check_in_date ~ '^\d{2}-\d{2}-\d{4}$'
  AND SPLIT_PART(check_in_date, '-', 1)::INTEGER > 12;

UPDATE cleaning_bookings
SET check_in_date = TO_DATE(check_in_date, 'MM-DD-YYYY')::TEXT
WHERE check_in_date ~ '^\d{2}-\d{2}-\d{4}$';

UPDATE cleaning_bookings
SET check_out_date = TO_DATE(check_out_date, 'DD/MM/YYYY')::TEXT
WHERE check_out_date LIKE '%/%';

UPDATE cleaning_bookings
SET check_out_date = TO_DATE(check_out_date, 'DD-MM-YY')::TEXT
WHERE check_out_date ~ '^\d{2}-\d{2}-\d{2}$';

UPDATE cleaning_bookings
SET check_out_date = TO_DATE(check_out_date, 'DD-MM-YYYY')::TEXT
WHERE check_out_date ~ '^\d{2}-\d{2}-\d{4}$'
  AND SPLIT_PART(check_out_date, '-', 1)::INTEGER > 12;

UPDATE cleaning_bookings
SET check_out_date = TO_DATE(check_out_date, 'MM-DD-YYYY')::TEXT
WHERE check_out_date ~ '^\d{2}-\d{2}-\d{4}$';

-- This must return zero rows before going on.
SELECT booking_id, check_in_date, check_out_date
FROM cleaning_bookings
WHERE check_in_date  !~ '^\d{4}-\d{2}-\d{2}$'
   OR check_out_date !~ '^\d{4}-\d{2}-\d{2}$';


-- ------------------------------------------------------------
-- 6. Fill values that can be derived from other columns
-- ------------------------------------------------------------
-- nights from the two dates (only where nights is missing and the
-- dates make sense)
UPDATE cleaning_bookings
SET nights_stayed = (check_out_date::DATE - check_in_date::DATE)::TEXT
WHERE nights_stayed IS NULL
  AND check_out_date::DATE > check_in_date::DATE;

-- total = room rate x nights + service price (only where total is missing)
UPDATE cleaning_bookings
SET total_amount = (
        room_rate_per_night::NUMERIC * nights_stayed::NUMERIC
      + COALESCE(service_price::NUMERIC, 0)
    )::TEXT
WHERE total_amount IS NULL
  AND room_rate_per_night IS NOT NULL
  AND nights_stayed IS NOT NULL;


-- ------------------------------------------------------------
-- 7. Ratings: valid values are 1 to 5. '0', '6' and blanks become NULL.
-- ------------------------------------------------------------
UPDATE cleaning_bookings
SET guest_rating = CASE
    WHEN TRIM(guest_rating) IN ('1', '2', '3', '4', '5') THEN TRIM(guest_rating)
    ELSE NULL
END;


-- ------------------------------------------------------------
-- 8. Production table with real types and constraints
-- ------------------------------------------------------------
DROP TABLE IF EXISTS bookings;
DROP TABLE IF EXISTS rejected_bookings;

CREATE TABLE bookings (
    booking_id          VARCHAR(10)   PRIMARY KEY,
    guest_name          VARCHAR(100)  NOT NULL,
    guest_phone         VARCHAR(15),
    guest_city          VARCHAR(50),
    guest_nationality   VARCHAR(50),
    room_no             INTEGER,
    room_type           VARCHAR(20)   CHECK (room_type IN ('Standard', 'Deluxe', 'Suite', 'Penthouse')),
    room_rate_per_night NUMERIC(10,2) CHECK (room_rate_per_night > 0),
    check_in_date       DATE          NOT NULL,
    check_out_date      DATE          NOT NULL,
    nights_stayed       INTEGER       CHECK (nights_stayed > 0),
    staff_name          VARCHAR(100),
    staff_department    VARCHAR(50),
    staff_salary        NUMERIC(12,2),
    payment_method      VARCHAR(20),
    booking_status      VARCHAR(20),
    total_amount        NUMERIC(12,2),
    service_used        VARCHAR(50),
    service_price       NUMERIC(10,2),
    guest_rating        INTEGER       CHECK (guest_rating BETWEEN 1 AND 5),
    CONSTRAINT stay_dates_make_sense CHECK (check_out_date > check_in_date)
);

-- Rows that break a business rule are kept aside, not silently dropped.
-- In this file: two bookings whose check-out is before check-in.
CREATE TABLE rejected_bookings AS
SELECT *, 'check-out before check-in' AS reject_reason
FROM cleaning_bookings
WHERE check_out_date::DATE <= check_in_date::DATE;

INSERT INTO bookings
SELECT booking_id,
       guest_name,
       guest_phone,
       guest_city,
       guest_nationality,
       room_no::INTEGER,
       room_type,
       room_rate_per_night::NUMERIC,
       check_in_date::DATE,
       check_out_date::DATE,
       nights_stayed::INTEGER,
       staff_name,
       staff_department,
       staff_salary::NUMERIC,
       payment_method,
       booking_status,
       total_amount::NUMERIC,
       service_used,
       service_price::NUMERIC,
       guest_rating::INTEGER
FROM cleaning_bookings
WHERE booking_id NOT IN (SELECT booking_id FROM rejected_bookings);


-- ------------------------------------------------------------
-- 9. Final checks (see 03_checks.sql for the full set)
-- ------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM staging_bookingss)  AS raw_rows,
       (SELECT COUNT(*) FROM cleaning_bookings)  AS after_dedupe,
       (SELECT COUNT(*) FROM bookings)           AS loaded,
       (SELECT COUNT(*) FROM rejected_bookings)  AS rejected;
