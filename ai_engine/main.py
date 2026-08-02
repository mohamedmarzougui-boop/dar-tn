from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import os
import psycopg
from dotenv import load_dotenv

# Load environment variables
load_dotenv(dotenv_path="../server/.env")

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5433")
DB_NAME = os.getenv("DB_NAME", "dartn_db")
DB_USER = os.getenv("DB_USER", "dartn_admin")
DB_PASSWORD = os.getenv("DB_PASSWORD", "dartn_secret_password")

app = FastAPI(title="Dar-TN AI Price Estimation Service")

class PriceEstimateRequest(BaseModel):
    city: str
    delegation: str
    property_type: str
    price_tnd: float
    has_climatisation: bool = False
    is_furnished: bool = False

def get_db_connection():
    return psycopg.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )

@app.post("/api/ai/estimate-price")
def estimate_fair_price(data: PriceEstimateRequest):
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cursor:
                # Query average price for similar properties in the same delegation/city
                query = """
                SELECT AVG(price_tnd) 
                FROM listings 
                WHERE city ILIKE %s 
                  AND property_type = %s;
                """
                cursor.execute(query, (f"%{data.city}%", data.property_type))
                result = cursor.fetchone()
                
                avg_price = float(result[0]) if result and result[0] else None

        # Fallback benchmark prices if database historical data is still small
        if not avg_price:
            default_benchmarks = {
                "S_PLUS_1": 650.0,
                "S_PLUS_2": 950.0,
                "S_PLUS_3": 1300.0,
                "COLOCATION": 250.0,
                "STUDIO": 450.0
            }
            avg_price = default_benchmarks.get(data.property_type, 700.0)

        # Adjust estimated price based on features (AC +10%, Furnished +15%)
        adjusted_estimated_price = avg_price
        if data.has_climatisation:
            adjusted_estimated_price *= 1.10
        if data.is_furnished:
            adjusted_estimated_price *= 1.15

        price_diff_percent = ((data.price_tnd - adjusted_estimated_price) / adjusted_estimated_price) * 100

        # Determine Fairness Status Badge
        if price_diff_percent > 10:
            status = "OVERPRICED"
            badge = "🔴 Price is +{:.1f}% higher than average for {}".format(price_diff_percent, data.city)
        elif price_diff_percent < -15:
            status = "UNDERPRICED_WARNING"
            badge = "🟡 Price is unusually low ({:.1f}% below market average). Check for scams.".format(abs(price_diff_percent))
        else:
            status = "FAIR_PRICE"
            badge = "🟢 Fair Price (Matches {} market average)".format(data.city)

        return {
            "actual_price_tnd": data.price_tnd,
            "estimated_market_price_tnd": round(adjusted_estimated_price, 2),
            "difference_percentage": round(price_diff_percent, 1),
            "status": status,
            "badge_label": badge
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)