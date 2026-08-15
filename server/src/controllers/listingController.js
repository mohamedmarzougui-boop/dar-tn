import { query } from '../config/db.js';

const AI_SERVICE_URL = process.env.AI_SERVICE_URL || 'http://127.0.0.1:8000';

// Ask the Python AI microservice for a fair-price valuation. The map/listing
// experience must keep working even if that service is down, so failures
// degrade to `null` here rather than failing the whole request.
const fetchAIEstimate = async (listing) => {
  try {
    const response = await fetch(`${AI_SERVICE_URL}/api/ai/estimate-price`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        city: listing.city,
        delegation: listing.delegation,
        property_type: listing.property_type,
        price_tnd: parseFloat(listing.price_tnd),
        has_climatisation: Boolean(listing.has_climatisation),
        is_furnished: Boolean(listing.is_furnished),
      }),
    });

    if (!response.ok) {
      console.warn(`AI engine returned HTTP ${response.status}`);
      return null;
    }

    return await response.json();
  } catch (error) {
    console.warn('AI engine offline or unreachable:', error.message);
    return null;
  }
};

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

// Fetch a single listing for the map bottom sheet, merged with an AI fair-price
// valuation. Deliberately does NOT select the owner's phone number - that stays
// behind the points-unlock paywall (Phase 6).
export const getListingById = async (req, res) => {
  try {
    const { id } = req.params;

    const sql = `
      SELECT
        l.id, l.title, l.description, l.price_tnd, l.deposit_tnd,
        l.property_type, l.target_tenant, l.bedrooms, l.bathrooms,
        l.has_climatisation, l.has_chauffage_central, l.has_wifi,
        l.has_elevator, l.is_furnished, l.surface_m2, l.city, l.delegation,
        ST_Y(l.location::geometry) AS latitude,
        ST_X(l.location::geometry) AS longitude,
        l.status, l.is_verified_by_agency, l.created_at,
        u.full_name AS owner_name
      FROM listings l
      LEFT JOIN users u ON l.owner_id = u.id
      WHERE l.id = $1;
    `;

    const result = await query(sql, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Listing not found.' });
    }

    const listing = result.rows[0];
    const aiValuation = await fetchAIEstimate(listing);

    res.json({
      listing,
      ai_valuation: aiValuation || { status: 'UNAVAILABLE', badge_label: '✨ Price valuation pending' },
    });

  } catch (error) {
    console.error('Get listing by id error:', error);
    res.status(500).json({ error: 'Failed to retrieve listing details.' });
  }
};

// Create a listing owned by the authenticated user. owner_id always comes
// from the JWT, never the request body, so a user can't attribute a listing
// to someone else.
export const createListing = async (req, res) => {
  try {
    const {
      title, description, price_tnd, deposit_tnd,
      property_type, target_tenant, bedrooms, bathrooms,
      has_climatisation, has_chauffage_central, has_wifi,
      has_elevator, is_furnished, surface_m2, city, delegation, address_text,
      latitude, longitude,
    } = req.body;

    const sql = `
      INSERT INTO listings (
        owner_id, title, description, price_tnd, deposit_tnd,
        property_type, target_tenant, bedrooms, bathrooms,
        has_climatisation, has_chauffage_central, has_wifi,
        has_elevator, is_furnished, surface_m2, city, delegation, address_text,
        location, status
      ) VALUES (
        $1, $2, $3, $4, $5,
        $6, $7, $8, $9,
        $10, $11, $12, $13, $14, $15, $16, $17, $18,
        ST_SetSRID(ST_MakePoint($19, $20), 4326)::geography, 'ACTIVE'
      ) RETURNING
        id, title, description, price_tnd, deposit_tnd, property_type, target_tenant,
        bedrooms, bathrooms, has_climatisation, has_chauffage_central, has_wifi,
        has_elevator, is_furnished, surface_m2, city, delegation, address_text,
        ST_Y(location::geometry) AS latitude, ST_X(location::geometry) AS longitude,
        status, created_at;
    `;

    // Nullish coalescing, not ||: an explicit 0 (e.g. a studio with zero
    // separate bedrooms) is a valid value and must not be overwritten by
    // the default the way `0 || 1` would silently do.
    const values = [
      req.user.id, title, description ?? null, price_tnd, deposit_tnd ?? 0,
      property_type, target_tenant ?? 'ANY', bedrooms ?? 1, bathrooms ?? 1,
      has_climatisation ?? false, has_chauffage_central ?? false, has_wifi ?? false,
      has_elevator ?? false, is_furnished ?? false, surface_m2 ?? null, city, delegation, address_text ?? null,
      longitude, latitude,
    ];

    const result = await query(sql, values);
    res.status(201).json({ message: 'Listing created successfully!', listing: result.rows[0] });

  } catch (error) {
    console.error('Create listing error:', error);
    res.status(500).json({ error: 'Failed to create listing.' });
  }
};
