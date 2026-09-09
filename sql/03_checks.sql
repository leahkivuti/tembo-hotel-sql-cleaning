-- ============================================================
-- Tembo Hotel bookings: data-quality checks
-- Run after 02_clean_bookings.sql. Every "should be zero" query
-- returns no rows when the cleaning worked.
-- ============================================================

SET search_path TO tembo_hotel;

-- Row accounting: 286 raw -> 285 unique -> 283 loaded + 2 rejected
SELECT (SELECT COUNT(*) FROM staging_bookingss) AS raw_rows,
       (SELECT COUNT(*) FROM cleaning_bookings) AS unique_rows,
       (SELECT COUNT(*) FROM bookings)          AS loaded,
       (SELECT COUNT(*) FROM rejected_bookings) AS rejected;

-- Should be zero: duplicate booking ids
SELECT booking_id, COUNT(*)
FROM bookings
GROUP BY booking_id
HAVING COUNT(*) > 1;

-- Should be zero: nights that disagree with the dates
SELECT booking_id, check_in_date, check_out_date, nights_stayed
FROM bookings
WHERE check_out_date - check_in_date <> nights_stayed;

-- Should be zero: phone numbers that are not 10 digits starting with 0
SELECT booking_id, guest_phone
FROM bookings
WHERE guest_phone IS NOT NULL
  AND guest_phone !~ '^0[0-9]{9}$';

-- Exactly four room types, four payment methods, three statuses
SELECT room_type,      COUNT(*) FROM bookings GROUP BY 1 ORDER BY 2 DESC;
SELECT payment_method, COUNT(*) FROM bookings GROUP BY 1 ORDER BY 2 DESC;
SELECT booking_status, COUNT(*) FROM bookings GROUP BY 1 ORDER BY 2 DESC;

-- Worth a look, not an error: totals that differ from rate x nights + service
SELECT booking_id, room_rate_per_night, nights_stayed, service_price, total_amount,
       room_rate_per_night * nights_stayed + COALESCE(service_price, 0) AS expected_total
FROM bookings
WHERE total_amount <> room_rate_per_night * nights_stayed + COALESCE(service_price, 0);

-- The rows that were kept aside, with the reason
SELECT booking_id, check_in_date, check_out_date, nights_stayed, reject_reason
FROM rejected_bookings;

-- Missing values that remain (they were missing in the source, not lost in cleaning)
SELECT COUNT(*) FILTER (WHERE guest_phone  IS NULL) AS phone_missing,
       COUNT(*) FILTER (WHERE guest_city   IS NULL) AS city_missing,
       COUNT(*) FILTER (WHERE staff_salary IS NULL) AS salary_missing,
       COUNT(*) FILTER (WHERE guest_rating IS NULL) AS rating_invalid_or_missing
FROM bookings;
