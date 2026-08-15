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
        u.full_name AS owner_name,
        COALESCE(
          (SELECT json_agg(li.id ORDER BY li.is_primary DESC, li.display_order ASC)
           FROM listing_images li WHERE li.listing_id = l.id),
          '[]'::json
        ) AS image_ids
      FROM listings l
      LEFT JOIN users u ON l.owner_id = u.id
      WHERE l.id = $1;
    `;

    const result = await query(sql, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Listing not found.' });
    }

    const listing = result.rows[0];
    // Images are proxied through our own API, not linked to the source CDN
    // directly: Flutter web's default renderer needs CORS headers to load
    // cross-origin image bytes, and cdn.tayara.tn doesn't send any - the
    // image displays fine in a plain <img> tag or opened directly, but
    // Image.network() fails silently. Proxying through an endpoint we
    // control (and that already has CORS enabled) fixes that.
    const imageIds = listing.image_ids;
    delete listing.image_ids;
    listing.images = imageIds.map((imageId) => `${req.protocol}://${req.get('host')}/api/images/${imageId}`);

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

// Streams an image by its listing_images id, never by a client-supplied URL -
// accepting an arbitrary URL to fetch server-side would be an SSRF vector
// (an attacker could point it at internal services). Looking it up by an id
// we already stored ourselves means the client only ever picks from images
// we already know are safe to fetch.
export const getListingImage = async (req, res) => {
  try {
    const { imageId } = req.params;

    const result = await query('SELECT image_url FROM listing_images WHERE id = $1', [imageId]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Image not found.' });
    }

    const upstream = await fetch(result.rows[0].image_url);
    if (!upstream.ok) {
      return res.status(502).json({ error: 'Failed to fetch image from source.' });
    }

    res.set('Content-Type', upstream.headers.get('content-type') || 'image/jpeg');
    res.set('Cache-Control', 'public, max-age=86400');
    // helmet() defaults Cross-Origin-Resource-Policy to same-origin, which
    // would block Flutter web (a different origin/port) from loading this
    // even with CORS otherwise satisfied - CORP is a separate browser
    // security layer from CORS. This endpoint's whole purpose is serving
    // images cross-origin, so it needs an explicit override.
    res.set('Cross-Origin-Resource-Policy', 'cross-origin');
    res.send(Buffer.from(await upstream.arrayBuffer()));
  } catch (error) {
    console.error('Get listing image error:', error);
    res.status(502).json({ error: 'Failed to fetch image.' });
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

// Best-effort field extraction from pasted listing text (e.g. copied from a
// Facebook post), so a user can prefill the create-listing form instead of
// typing everything by hand. Nothing here gets published automatically - the
// client still has to submit the reviewed/edited fields through createListing.
export const parseListingText = async (req, res) => {
  try {
    const response = await fetch(`${AI_SERVICE_URL}/api/ai/parse-listing-text`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: req.body.text }),
    });

    if (!response.ok) {
      return res.status(502).json({ error: 'Text parsing service returned an error.' });
    }

    res.json(await response.json());
  } catch (error) {
    console.error('Parse listing text error:', error);
    res.status(502).json({ error: 'Text parsing service is unavailable.' });
  }
};
