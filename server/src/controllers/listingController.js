import { query } from '../config/db.js';

// Fetch listings within a map viewport (bounding box), with optional filters.
// IMPORTANT: the bounding box is compared against `location` as geography
// (`::geography` on the envelope, not `::geometry` on the column) so Postgres
// can use the GiST index on listings.location. Casting the column instead
// forces a sequential scan as the table grows.
export const getMapListings = async (req, res) => {
  try {
    const { min_lat, min_lng, max_lat, max_lng, property_type, target_tenant, max_price } = req.query;

    let sql = `
      SELECT
        id, title, price_tnd, property_type, target_tenant,
        has_climatisation, is_furnished, city, delegation,
        ST_Y(location::geometry) AS latitude,
        ST_X(location::geometry) AS longitude,
        is_verified_by_agency, created_at
      FROM listings
      WHERE status = 'ACTIVE'
        AND location && ST_MakeEnvelope($1, $2, $3, $4, 4326)::geography
    `;

    const params = [parseFloat(min_lng), parseFloat(min_lat), parseFloat(max_lng), parseFloat(max_lat)];
    let paramIndex = 5;

    if (property_type) {
      sql += ` AND property_type = $${paramIndex}`;
      params.push(property_type);
      paramIndex++;
    }

    if (target_tenant) {
      sql += ` AND target_tenant = $${paramIndex}`;
      params.push(target_tenant);
      paramIndex++;
    }

    if (max_price) {
      sql += ` AND price_tnd <= $${paramIndex}`;
      params.push(parseFloat(max_price));
      paramIndex++;
    }

    sql += ` ORDER BY created_at DESC LIMIT 100;`;

    const result = await query(sql, params);
    res.json({ count: result.rows.length, listings: result.rows });

  } catch (error) {
    console.error('Get map listings error:', error);
    res.status(500).json({ error: 'Failed to retrieve listings for map.' });
  }
};
