"""Bulk-import a CSV of an agency's own listings into the platform.

Usage:
    python pipeline.py --csv path/to/listings.csv --owner-phone 22111222

Every row is attributed to an existing registered user (looked up by phone
number) - there is no anonymous/unowned bulk import, matching how every
other listing-creation path in this app requires an accountable owner.
Rows are inserted as PENDING, not ACTIVE: this bypasses the per-listing
validation and rate limiting that the authenticated API endpoint
(POST /api/listings) applies, so a human should review a batch before it
goes live rather than trusting a spreadsheet at face value.

See sample_listings.csv for the expected columns.
"""

import argparse
import csv
import os
import sys
import time

import psycopg
from dotenv import load_dotenv
from geopy.geocoders import Nominatim

from location_matching import resolve_location

load_dotenv()

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5433")
DB_NAME = os.getenv("DB_NAME", "dartn_db")
DB_USER = os.getenv("DB_USER", "dartn_admin")
DB_PASSWORD = os.getenv("DB_PASSWORD")

PROPERTY_TYPES = {"STUDIO", "S_PLUS_1", "S_PLUS_2", "S_PLUS_3", "S_PLUS_4", "COLOCATION", "HOUSE", "VILLA"}
TARGET_TENANTS = {"BOYS_ONLY", "GIRLS_ONLY", "STUDENT", "FAMILY", "ANY"}
BOOLEAN_COLUMNS = ["has_climatisation", "has_chauffage_central", "has_wifi", "has_elevator", "is_furnished"]

geolocator = Nominatim(user_agent="dar_tn_bulk_import_v1")


def get_db_connection():
    return psycopg.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD)


def parse_bool(value):
    return str(value).strip().lower() in ("1", "true", "yes", "y", "oui")


def geocode(city, delegation):
    query_address = f"{delegation}, {city}, Tunisia"
    try:
        location = geolocator.geocode(query_address, timeout=10)
        if location:
            return location.latitude, location.longitude
        fallback = geolocator.geocode(f"{city}, Tunisia", timeout=10)
        if fallback:
            return fallback.latitude, fallback.longitude
    except Exception as e:
        print(f"  Geocoding warning for '{query_address}': {e}")
    return 36.8065, 10.1815  # Tunis city center as a last-resort fallback


def validate_row(row):
    """Returns (canonical_city, canonical_delegation, errors). errors is
    empty when the row is valid; city/delegation may be None if unresolved."""
    errors = []

    for field in ("title", "price_tnd", "city", "delegation"):
        if not row.get(field, "").strip():
            errors.append(f"missing required field '{field}'")

    if row.get("price_tnd"):
        try:
            if float(row["price_tnd"]) < 0:
                errors.append("price_tnd must be non-negative")
        except ValueError:
            errors.append(f"price_tnd '{row['price_tnd']}' is not a number")

    property_type = row.get("property_type", "").strip().upper()
    if not property_type:
        errors.append("missing required field 'property_type'")
    elif property_type not in PROPERTY_TYPES:
        errors.append(f"property_type '{property_type}' must be one of {sorted(PROPERTY_TYPES)}")

    target_tenant = row.get("target_tenant", "").strip().upper()
    if target_tenant and target_tenant not in TARGET_TENANTS:
        errors.append(f"target_tenant '{target_tenant}' must be one of {sorted(TARGET_TENANTS)}")

    city, delegation = None, None
    if row.get("city", "").strip():
        city, delegation, location_errors = resolve_location(row["city"], row.get("delegation", ""))
        errors.extend(location_errors)

    return city, delegation, errors


def insert_listing(conn, owner_id, row, city, delegation):
    lat_str, lng_str = row.get("latitude", "").strip(), row.get("longitude", "").strip()
    if lat_str and lng_str:
        lat, lng = float(lat_str), float(lng_str)
    else:
        lat, lng = geocode(city, delegation)
        time.sleep(1)  # Nominatim's usage policy caps requests at 1/sec.

    with conn.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO listings (
                owner_id, title, description, price_tnd, deposit_tnd,
                property_type, target_tenant, bedrooms, bathrooms,
                has_climatisation, has_chauffage_central, has_wifi, has_elevator, is_furnished,
                surface_m2, city, delegation, address_text,
                location, status
            ) VALUES (
                %s, %s, %s, %s, %s,
                %s, %s, %s, %s,
                %s, %s, %s, %s, %s,
                %s, %s, %s, %s,
                ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography, 'PENDING'
            ) RETURNING id;
            """,
            (
                owner_id, row["title"].strip(), row.get("description", "").strip() or None,
                float(row["price_tnd"]), float(row.get("deposit_tnd") or 0),
                row["property_type"].strip().upper(), row.get("target_tenant", "").strip().upper() or "ANY",
                int(row.get("bedrooms") or 1), int(row.get("bathrooms") or 1),
                *(parse_bool(row.get(col, "")) for col in BOOLEAN_COLUMNS),
                int(row["surface_m2"]) if row.get("surface_m2", "").strip() else None,
                city, delegation, row.get("address_text", "").strip() or None,
                lng, lat,
            ),
        )
        listing_id = cursor.fetchone()[0]
        conn.commit()
        return listing_id


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", required=True, help="Path to the CSV file to import")
    parser.add_argument("--owner-phone", required=True, help="Phone number of the registered user these listings belong to")
    args = parser.parse_args()

    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT id, full_name FROM users WHERE phone_number = %s", (args.owner_phone,))
            owner = cursor.fetchone()
        if not owner:
            print(f"No registered user found with phone number '{args.owner_phone}'. "
                  f"They must register in the app first - bulk import doesn't create accounts.")
            sys.exit(1)
        owner_id, owner_name = owner
        print(f"Importing listings for {owner_name} ({args.owner_phone})...")

        inserted, skipped = 0, []
        with open(args.csv, newline="", encoding="utf-8") as f:
            for i, row in enumerate(csv.DictReader(f), start=2):  # row 1 is the header
                city, delegation, errors = validate_row(row)
                if errors:
                    skipped.append((i, errors))
                    print(f"  Row {i}: skipped - {'; '.join(errors)}")
                    continue

                listing_id = insert_listing(conn, owner_id, row, city, delegation)
                inserted += 1
                print(f"  Row {i}: inserted as {listing_id} (status=PENDING)")

        print(f"\nDone: {inserted} inserted as PENDING, {len(skipped)} skipped.")
        if skipped:
            print("Fix the skipped rows and re-run with just those rows to import them.")

    finally:
        conn.close()


if __name__ == "__main__":
    main()
