"""Scrapes rental real estate listings from tayara.tn's public "immobilier"
category and ingests them into PostGIS as SCRAPED_UNVERIFIED listings.

Usage:
    python tayara_scraper.py --max-listings 20

This targets a specific site deliberately, not sites in general: before
writing this, robots.txt for tayara.tn was checked and found fully
permissive (`Allow: /`, published sitemaps, no bot-specific disallow rules) -
unlike tunisie-annonce.com (refused the connection outright) and mubawab.tn
(robots.txt explicitly disallows all bots, ClaudeBot included, from its ad
directories). This scraper still checks robots.txt itself at startup as a
safety net in case that changes.

Respectful-scraping choices baked in:
- Honest, identifying User-Agent (not spoofing a browser).
- Rate-limited: a delay between every request, not just listing pages.
- Bounded by --max-listings (default 20) - no unbounded crawling.
- Only fetches the immobilier category and individual /item/ pages, the
  paths actually needed - nothing else on the site.

Sale listings ("A Vendre") are skipped: this platform's price_tnd column
models monthly rent, and a schema-changing sale price (e.g. 161 000 DT)
would corrupt the AI valuation engine's price comparisons if inserted
as if it were rent.
"""

import argparse
import json
import re
import sys
import time
import urllib.robotparser
from urllib.parse import urljoin

import psycopg
import requests
from dotenv import load_dotenv
from geopy.geocoders import Nominatim
import os

from location_matching import resolve_location

geolocator = Nominatim(user_agent="dar_tn_tayara_scraper_v1")


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

load_dotenv()

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5433")
DB_NAME = os.getenv("DB_NAME", "dartn_db")
DB_USER = os.getenv("DB_USER", "dartn_admin")
DB_PASSWORD = os.getenv("DB_PASSWORD")

BASE_URL = "https://www.tayara.tn"
CATEGORY_URL = f"{BASE_URL}/ads/c/immobilier/"
USER_AGENT = "DarTnBot/1.0 (+https://github.com/mohamedmarzougui-boop/dar-tn; rental-listings-import)"
REQUEST_DELAY_SECONDS = 2

NEXT_DATA_PATTERN = re.compile(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', re.DOTALL)
ITEM_LINK_PATTERN = re.compile(r'href="(/item/[^"]+/([a-f0-9]{24})/)"')

PROPERTY_TYPE_KEYWORDS = [
    ("colocation", "COLOCATION"), ("coloc", "COLOCATION"),
    ("studio", "STUDIO"), ("villa", "VILLA"), ("maison", "HOUSE"),
]
SPLUS_PATTERN = re.compile(r"\bs\s*\+\s*([1-4])\b", re.IGNORECASE)
TARGET_TENANT_KEYWORDS = [
    ("filles", "GIRLS_ONLY"), ("garcons", "BOYS_ONLY"),
    ("etudiant", "STUDENT"), ("famille", "FAMILY"),
]


def check_robots_allowed():
    # Not using RobotFileParser.read(): it fetches robots.txt with Python's
    # generic default User-Agent and has no way to override that, and that
    # generic UA gets a 403 from tayara.tn's bot-defense - which read() then
    # (correctly, per its own documented behavior) interprets as "disallow
    # everything", even though the real robots.txt (fetched honestly, like
    # the rest of this scraper does) says `Allow: /`. Fetching it ourselves
    # and feeding the text into parse() avoids that false negative.
    rp = urllib.robotparser.RobotFileParser()
    rp.parse(fetch(f"{BASE_URL}/robots.txt").splitlines())
    for url in (CATEGORY_URL, f"{BASE_URL}/item/test/test/test/test/000000000000000000000000/"):
        if not rp.can_fetch(USER_AGENT, url):
            print(f"robots.txt disallows fetching {url} for this User-Agent. Aborting.")
            sys.exit(1)


def get_db_connection():
    return psycopg.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD)


def fetch(url):
    response = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=15)
    response.raise_for_status()
    return response.text


def extract_next_data(html):
    match = NEXT_DATA_PATTERN.search(html)
    return json.loads(match.group(1)) if match else None


def guess_property_type(text):
    normalized = text.lower()
    for keyword, value in PROPERTY_TYPE_KEYWORDS:
        if keyword in normalized:
            return value
    splus = SPLUS_PATTERN.search(normalized)
    return f"S_PLUS_{splus.group(1)}" if splus else "S_PLUS_1"  # DB requires a value; S+1 is the most common fallback


def guess_target_tenant(text):
    normalized = text.lower()
    for keyword, value in TARGET_TENANT_KEYWORDS:
        if keyword in normalized:
            return value
    return "ANY"


def resolve_scraper_location(governorate, delegation):
    """More permissive than the CSV importer's resolve_location: a scraped
    delegation name not in our canonical list (there are real gaps, e.g.
    "Les Berges du Lac" was missing until it showed up in testing) falls
    back to the source's raw name rather than dropping otherwise-legitimate
    inventory. The governorate itself must still match - that's what the
    AI valuation's city-level comparables grouping relies on."""
    city, delegation_match, errors = resolve_location(governorate, delegation)
    if not city:
        return None, None
    return city, delegation_match or delegation.strip()


def collect_candidates(max_listings):
    """Walks search-result pages, returns a list of (id, item_url, hit) until
    max_listings candidates are collected or pages run out."""
    candidates = []
    page = 1
    while len(candidates) < max_listings:
        url = f"{CATEGORY_URL}?page={page}"
        print(f"Fetching search page {page}...")
        html = fetch(url)
        time.sleep(REQUEST_DELAY_SECONDS)

        data = extract_next_data(html)
        hits = data["props"]["pageProps"]["searchedListingsAction"]["newHits"] if data else []
        if not hits:
            break

        url_by_id = {m.group(2): urljoin(BASE_URL, m.group(1)) for m in ITEM_LINK_PATTERN.finditer(html)}

        for hit in hits:
            item_url = url_by_id.get(hit["id"])
            if item_url:
                candidates.append((hit["id"], item_url))
            if len(candidates) >= max_listings:
                break

        page += 1
        if page > 20:  # hard safety cap regardless of --max-listings
            break

    return candidates


def scrape_listing(conn, item_url):
    """Returns 'inserted', 'sale_skipped', 'no_price', 'bad_location', or 'duplicate'."""
    html = fetch(item_url)
    data = extract_next_data(html)
    ad = data["props"]["pageProps"]["adDetails"] if data else None
    if not ad:
        return "parse_error"

    params = {p["label"]: p["value"] for p in ad.get("adParams", [])}
    if params.get("Type de transaction", "").strip().lower() != "à louer":
        return "sale_skipped"

    # Some posts leave price unset (0) - happens on the source site itself,
    # not an extraction bug. Importing that as 0 TND rent would look like a
    # free listing and skew the AI valuation's price averages, so skip it.
    if not ad.get("price"):
        return "no_price"

    city, delegation = resolve_scraper_location(ad["location"]["governorate"], ad["location"]["delegation"])
    if not city:
        return "bad_location"

    text_for_keywords = f"{ad['title']} {ad.get('description', '')}"
    lat, lng = geocode(city, delegation)
    time.sleep(REQUEST_DELAY_SECONDS)  # Nominatim's usage policy caps requests at 1/sec.

    try:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO listings (
                    owner_id, title, description, price_tnd, property_type, target_tenant,
                    bedrooms, bathrooms, surface_m2, city, delegation,
                    location, status, scraped_source_url, scraped_contact_phone
                ) VALUES (
                    NULL, %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s,
                    ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography, 'SCRAPED_UNVERIFIED', %s, %s
                ) RETURNING id
                """,
                (
                    ad["title"].strip()[:255], ad.get("description", "").strip() or None,
                    float(ad["price"]), guess_property_type(text_for_keywords), guess_target_tenant(text_for_keywords),
                    int(params.get("Chambres", 1) or 1), int(params.get("Salles de bains", 1) or 1),
                    int(params["Superficie"]) if params.get("Superficie", "").strip().isdigit() else None,
                    city, delegation,
                    lng, lat,
                    item_url, ad.get("phone"),
                ),
            )
            listing_id = cursor.fetchone()[0]

            for i, image_url in enumerate(ad.get("images", [])):
                cursor.execute(
                    "INSERT INTO listing_images (listing_id, image_url, is_primary, display_order) VALUES (%s, %s, %s, %s)",
                    (listing_id, image_url, i == 0, i),
                )

            conn.commit()
            return "inserted"
    except psycopg.errors.UniqueViolation:
        conn.rollback()
        return "duplicate"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--max-listings", type=int, default=20, help="Maximum number of listings to scrape (default 20)")
    args = parser.parse_args()

    check_robots_allowed()

    conn = get_db_connection()
    try:
        candidates = collect_candidates(args.max_listings)
        print(f"Found {len(candidates)} candidate listings, checking each for rental status...\n")

        counts = {"inserted": 0, "sale_skipped": 0, "bad_location": 0, "duplicate": 0, "parse_error": 0}
        for listing_id, item_url in candidates:
            time.sleep(REQUEST_DELAY_SECONDS)
            outcome = scrape_listing(conn, item_url)
            counts[outcome] = counts.get(outcome, 0) + 1
            print(f"  {item_url} -> {outcome}")

        print(f"\nDone: {counts['inserted']} inserted as SCRAPED_UNVERIFIED, "
              f"{counts['sale_skipped']} for-sale skipped, {counts.get('no_price', 0)} skipped for missing price, "
              f"{counts['bad_location']} unrecognized location, "
              f"{counts['duplicate']} already scraped previously, {counts['parse_error']} failed to parse.")

    finally:
        conn.close()


if __name__ == "__main__":
    main()
