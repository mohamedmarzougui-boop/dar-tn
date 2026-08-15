import os
from contextlib import asynccontextmanager
from enum import Enum

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from psycopg_pool import ConnectionPool
from pydantic import BaseModel

from text_parser import parse_listing_text

load_dotenv()

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5433")
DB_NAME = os.getenv("DB_NAME", "dartn_db")
DB_USER = os.getenv("DB_USER", "dartn_admin")
DB_PASSWORD = os.getenv("DB_PASSWORD")

CONNINFO = f"host={DB_HOST} port={DB_PORT} dbname={DB_NAME} user={DB_USER} password={DB_PASSWORD}"

# Minimum comparable listings required before trusting a location-level average
# over the broader city-level (or hardcoded) fallback.
MIN_COMPARABLES = 3

pool = ConnectionPool(conninfo=CONNINFO, min_size=1, max_size=10, open=False)


@asynccontextmanager
async def lifespan(app: FastAPI):
    pool.open()
    yield
    pool.close()


app = FastAPI(title="Dar-TN AI Price Estimation Service", lifespan=lifespan)


class PropertyType(str, Enum):
    STUDIO = "STUDIO"
    S_PLUS_1 = "S_PLUS_1"
    S_PLUS_2 = "S_PLUS_2"
    S_PLUS_3 = "S_PLUS_3"
    S_PLUS_4 = "S_PLUS_4"
    COLOCATION = "COLOCATION"
    HOUSE = "HOUSE"
    VILLA = "VILLA"


class PriceEstimateRequest(BaseModel):
    city: str
    delegation: str
    property_type: PropertyType
    price_tnd: float
    has_climatisation: bool = False
    is_furnished: bool = False


DEFAULT_BENCHMARKS = {
    PropertyType.STUDIO: 450.0,
    PropertyType.S_PLUS_1: 650.0,
    PropertyType.S_PLUS_2: 950.0,
    PropertyType.S_PLUS_3: 1300.0,
    PropertyType.S_PLUS_4: 1600.0,
    PropertyType.COLOCATION: 250.0,
    PropertyType.HOUSE: 1200.0,
    PropertyType.VILLA: 2500.0,
}


def fetch_comparables(cursor, city: str, property_type: PropertyType, delegation: str | None):
    """Average price + sample size for ACTIVE listings matching city/type,
    optionally narrowed to a delegation. Exact matches only — the schema
    stores clean canonical city/delegation names, so no need for ILIKE."""
    if delegation:
        cursor.execute(
            """
            SELECT AVG(price_tnd), COUNT(*)
            FROM listings
            WHERE status = 'ACTIVE' AND city = %s AND delegation = %s AND property_type = %s
            """,
            (city, delegation, property_type.value),
        )
    else:
        cursor.execute(
            """
            SELECT AVG(price_tnd), COUNT(*)
            FROM listings
            WHERE status = 'ACTIVE' AND city = %s AND property_type = %s
            """,
            (city, property_type.value),
        )
    avg_price, count = cursor.fetchone()
    return (float(avg_price) if avg_price else None), count


@app.get("/health")
def health():
    return {"status": "ok", "service": "Dar-TN AI Price Estimation Service"}


class ParseTextRequest(BaseModel):
    text: str


@app.post("/api/ai/parse-listing-text")
def parse_listing_text_endpoint(data: ParseTextRequest):
    return parse_listing_text(data.text)


@app.post("/api/ai/estimate-price")
def estimate_fair_price(data: PriceEstimateRequest):
    try:
        with pool.connection() as conn:
            with conn.cursor() as cursor:
                # Prefer delegation-level comparables (same neighborhood); a citywide
                # average is too coarse in cities like Tunis where price varies
                # hugely by delegation. Fall back to city-level, then a static
                # benchmark, whenever there isn't enough data to trust the average.
                avg_price, count = fetch_comparables(cursor, data.city, data.property_type, data.delegation)
                basis = "delegation"

                if not avg_price or count < MIN_COMPARABLES:
                    city_avg, city_count = fetch_comparables(cursor, data.city, data.property_type, None)
                    if city_avg and city_count >= MIN_COMPARABLES:
                        avg_price, count = city_avg, city_count
                        basis = "city"

        if not avg_price or count < MIN_COMPARABLES:
            avg_price = DEFAULT_BENCHMARKS[data.property_type]
            count = 0
            basis = "benchmark"

        # Adjust estimated price based on features (AC +10%, Furnished +15%)
        adjusted_estimated_price = avg_price
        if data.has_climatisation:
            adjusted_estimated_price *= 1.10
        if data.is_furnished:
            adjusted_estimated_price *= 1.15

        price_diff_percent = ((data.price_tnd - adjusted_estimated_price) / adjusted_estimated_price) * 100

        if price_diff_percent > 10:
            status = "OVERPRICED"
            badge = f"🔴 Price is +{price_diff_percent:.1f}% higher than average for {data.city}"
        elif price_diff_percent < -15:
            status = "UNDERPRICED_WARNING"
            badge = f"🟡 Price is unusually low ({abs(price_diff_percent):.1f}% below market average). Check for scams."
        else:
            status = "FAIR_PRICE"
            badge = f"🟢 Fair Price (Matches {data.city} market average)"

        return {
            "actual_price_tnd": data.price_tnd,
            "estimated_market_price_tnd": round(adjusted_estimated_price, 2),
            "difference_percentage": round(price_diff_percent, 1),
            "status": status,
            "badge_label": badge,
            "valuation_basis": basis,
            "comparable_sample_size": count,
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
