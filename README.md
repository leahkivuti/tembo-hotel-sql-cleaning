# Tembo Hotel: cleaning 286 messy bookings in PostgreSQL

A hotel's booking export, 286 rows and 20 columns, dirty in almost every one of them: names in capitals, phone numbers with `+254` and dashes, `mpesa` next to `M-Pesa`, guest ratings of 0 and 6, one duplicate booking, and dates in four different formats. This project loads it into PostgreSQL, cleans it column by column, and ends with a typed, constrained `bookings` table.

I wrote the full story up as an article: **[DDL and DML in PostgreSQL: Cleaning 286 Messy Hotel Bookings](https://dev.to/leahkivuti/ddl-and-dml-in-postgresql-cleaning-286-messy-hotel-bookings-3l26)** on dev.to.

## What's in this repository

`data/tembo_hotel_dirty.csv` is the raw export exactly as it arrived (the same data is in `data/tembo_hotel_dirty.xlsx` if you'd rather open it in Excel).

`sql/01_rebuild_dirty_data.sql` creates the schema and a staging table, and inserts all 286 raw rows, so you can reproduce the project without importing the CSV. Run it once in pgAdmin.

`sql/02_clean_bookings.sql` is the cleaning script. It makes a working copy of the staging table, removes the duplicate, standardises every text column, fixes phone numbers and money fields, converts the four date formats one at a time, fills nights and totals that can be derived from other columns, and finally creates the production `bookings` table with real types and CHECK constraints. Two bookings whose check-out is before check-in are kept aside in `rejected_bookings` rather than silently dropped.

`sql/03_checks.sql` is the set of queries I run afterwards. Each "should be zero" query returns no rows when the cleaning worked.

`screenshots/` shows the key moments in pgAdmin: the eight spellings of four room types, the duplicate check, the 44 rows with dates in the wrong format, the eight date fixes running, the same check returning zero rows, and the DELETE of the duplicate.

## Result

| | rows |
|---|---|
| Raw export | 286 |
| After removing the duplicate (BK0006) | 285 |
| Loaded into `bookings` | 283 |
| Kept aside in `rejected_bookings` | 2 |

Four room types instead of eight spellings. Four payment methods instead of five. Every date in `YYYY-MM-DD`. Every phone number ten digits starting with 0, or NULL. Nights always equal to check-out minus check-in. Ratings only 1 to 5.

## The part that took longest: dates

The date columns held `10/01/2024`, `28-01-24`, `01-12-2024` and `15-11-2024` in the same column. My first attempt stripped all the separators so I could convert once, which destroyed the only information that said which format each value was in. The fix was the opposite: use the separator and the length to identify each format, convert only those rows, and run a query that should return zero rows afterwards. For the ambiguous ones (`01-12-2024` could be 12 January or 1 December) the `nights_stayed` column settled it: only one reading made check-out minus check-in equal the nights.

## How to run it

Open pgAdmin's Query Tool on any database and run the three SQL files in order: `01_rebuild_dirty_data.sql`, then `02_clean_bookings.sql`, then `03_checks.sql`. Nothing else is needed. The scripts create and use a schema called `tembo_hotel` and are safe to re-run.

## Tools

PostgreSQL 16, pgAdmin 4.
