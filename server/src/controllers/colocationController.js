import { query } from '../config/db.js';

// 1. Search Roommate/Colocation Listings
export const getColocationListings = async (req, res) => {
  try {
    const { target_tenant, city, max_budget_tnd, has_climatisation, is_furnished } = req.query;

    let sql = `
      SELECT 
        l.id, l.title, l.description, l.price_tnd, l.target_tenant,
        l.has_climatisation, l.is_furnished, l.city, l.delegation,
        ST_Y(l.location::geometry) AS latitude,
        ST_X(l.location::geometry) AS longitude,
        l.created_at,
        u.full_name AS poster_name
      FROM listings l
      LEFT JOIN users u ON l.owner_id = u.id
      WHERE l.property_type = 'COLOCATION'
        AND l.status IN ('ACTIVE', 'SCRAPED_UNVERIFIED')
    `;

    const params = [];
    let paramIndex = 1;

    // Filter by Target Tenant (BOYS_ONLY / GIRLS_ONLY / STUDENT)
    if (target_tenant) {
      sql += ` AND l.target_tenant = $${paramIndex}`;
      params.push(target_tenant);
      paramIndex++;
    }

    // Filter by City
    if (city) {
      sql += ` AND l.city ILIKE $${paramIndex}`;
      params.push(`%${city}%`);
      paramIndex++;
    }

    // Filter by Max Budget per Roommate
    if (max_budget_tnd) {
      sql += ` AND l.price_tnd <= $${paramIndex}`;
      params.push(parseFloat(max_budget_tnd));
      paramIndex++;
    }

    if (has_climatisation === 'true') {
      sql += ` AND l.has_climatisation = TRUE`;
    }

    if (is_furnished === 'true') {
      sql += ` AND l.is_furnished = TRUE`;
    }

    sql += ` ORDER BY l.created_at DESC LIMIT 50;`;

    const result = await query(sql, params);

    res.json({
      type: 'COLOCATION_SEARCH',
      count: result.rows.length,
      colocations: result.rows
    });

  } catch (error) {
    console.error('Colocation search error:', error);
    res.status(500).json({ error: 'Failed to retrieve colocation listings.' });
  }
};

// 2. Post a Roommate Request ("Searching for a Roommate")
export const createColocationPost = async (req, res) => {
  try {
    const {
      title, description, price_per_person_tnd,
      target_tenant, has_climatisation, is_furnished,
      city, delegation, latitude, longitude
    } = req.body;

    const sql = `
      INSERT INTO listings (
        owner_id, title, description, price_tnd,
        property_type, target_tenant,
        has_climatisation, is_furnished, city, delegation,
        location, status
      ) VALUES (
        $1, $2, $3, $4,
        'COLOCATION', $5,
        $6, $7, $8, $9,
        ST_SetSRID(ST_MakePoint($10, $11), 4326)::geography, 'ACTIVE'
      ) RETURNING id, title, price_tnd, target_tenant, created_at;
    `;

    const values = [
      req.user.id,
      title,
      description,
      price_per_person_tnd,
      target_tenant || 'STUDENT',
      has_climatisation || false,
      is_furnished || true,
      city,
      delegation,
      parseFloat(longitude),
      parseFloat(latitude)
    ];

    const result = await query(sql, values);

    res.status(201).json({
      message: 'Colocation post created successfully!',
      colocation: result.rows[0]
    });

  } catch (error) {
    console.error('Create colocation error:', error);
    res.status(500).json({ error: 'Failed to create colocation post.' });
  }
};