import os
import re
import time
import psycopg
from geopy.geocoders import Nominatim
from dotenv import load_dotenv

# Load environment variables from server/.env
load_dotenv(dotenv_path="../server/.env")

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5433")
DB_NAME = os.getenv("DB_NAME", "dartn_db")
DB_USER = os.getenv("DB_USER", "dartn_admin")
DB_PASSWORD = os.getenv("DB_PASSWORD", "dartn_secret_password")

geolocator = Nominatim(user_agent="dar_tn_scraper_v1")

def get_db_connection():
    return psycopg.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )

def parse_price(price_str):
    if not price_str:
        return 0
    cleaned = re.sub(r'[^\d]', '', price_str)
    return float(cleaned) if cleaned else 0

def geocode_tunisian_location(delegation, city="Tunisia"):
    query_address = f"{delegation}, {city}, Tunisia"
    try:
        location = geolocator.geocode(query_address, timeout=10)
        if location:
            print(f"📍 Geocoded '{query_address}' -> Lat: {location.latitude}, Lng: {location.longitude}")
            return location.latitude, location.longitude
        else:
            fallback = geolocator.geocode(f"{city}, Tunisia", timeout=10)
            if fallback:
                return fallback.latitude, fallback.longitude
    except Exception as e:
        print(f"⚠️ Geocoding warning for {query_address}: {e}")
    
    # Default fallback: Tunis City
    return 36.8065, 10.1815

def insert_scraped_listing(listing_data):
    lat, lng = geocode_tunisian_location(listing_data['delegation'], listing_data['city'])
    
    with get_db_connection() as conn:
        with conn.cursor() as cursor:
            query = """
            INSERT INTO listings (
                title, description, price_tnd, property_type, target_tenant,
                has_climatisation, is_furnished, city, delegation,
                location, status, scraped_source_url
            ) VALUES (
                %s, %s, %s, %s, %s,
                %s, %s, %s, %s,
                ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography, 'SCRAPED_UNVERIFIED', %s
            ) RETURNING id;
            """

            cursor.execute(query, (
                listing_data['title'],
                listing_data['description'],
                listing_data['price_tnd'],
                listing_data['property_type'],
                listing_data['target_tenant'],
                listing_data['has_climatisation'],
                listing_data['is_furnished'],
                listing_data['city'],
                listing_data['delegation'],
                lng, lat,  # PostGIS takes Point(lng, lat)
                listing_data['source_url']
            ))

            listing_id = cursor.fetchone()[0]
            conn.commit()
            print(f"✅ Successfully inserted listing '{listing_data['title']}' with ID: {listing_id}")
            return listing_id


if __name__ == "__main__":
    print("🚀 Starting Scraper Pipeline Test...")
    
    mock_listings = [
        {
            "title": "Magnifique S+1 meublé à La Soukra",
            "description": "Charmant appartement S+1 avec climatisation près des écoles.",
            "price_tnd": parse_price("750 DT/mois"),
            "property_type": "S_PLUS_1",
            "target_tenant": "STUDENT",
            "has_climatisation": True,
            "is_furnished": True,
            "city": "Ariana",
            "delegation": "La Soukra",
            "source_url": "https://example-tunisia-rent.tn/item/101"
        },
        {
            "title": "Colocation pour filles à Monastir près du Campus",
            "description": "Chambre individuelle dans un S+3 équipé pour étudiants.",
            "price_tnd": parse_price("250 DT"),
            "property_type": "COLOCATION",
            "target_tenant": "GIRLS_ONLY",
            "has_climatisation": False,
            "is_furnished": True,
            "city": "Monastir",
            "delegation": "Monastir Ville",
            "source_url": "https://example-tunisia-rent.tn/item/102"
        }
    ]

    for item in mock_listings:
        insert_scraped_listing(item)
        time.sleep(1)