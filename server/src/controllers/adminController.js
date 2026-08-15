import { query } from '../config/db.js';

// Listings awaiting moderation: PENDING (CSV bulk-import) and
// SCRAPED_UNVERIFIED (tayara.tn scraper). Neither shows up on the public
// map until an admin approves it.
export const getModerationQueue = async (req, res) => {
  try {
    const result = await query(
      `SELECT
         l.id, l.title, l.price_tnd, l.property_type, l.city, l.delegation,
         l.status, l.scraped_source_url, l.created_at,
         u.full_name AS owner_name,
         COALESCE(
           (SELECT json_agg(li.id ORDER BY li.is_primary DESC, li.display_order ASC)
            FROM listing_images li WHERE li.listing_id = l.id),
           '[]'::json
         ) AS image_ids
       FROM listings l
       LEFT JOIN users u ON l.owner_id = u.id
       WHERE l.status IN ('PENDING', 'SCRAPED_UNVERIFIED')
       ORDER BY l.created_at ASC
       LIMIT 50`
    );

    const listings = result.rows.map((listing) => {
      const imageIds = listing.image_ids;
      delete listing.image_ids;
      listing.images = imageIds.map((imageId) => `${req.protocol}://${req.get('host')}/api/images/${imageId}`);
      return listing;
    });

    res.json({ count: listings.length, listings });
  } catch (error) {
    console.error('Get moderation queue error:', error);
    res.status(500).json({ error: 'Failed to retrieve moderation queue.' });
  }
};

// Approve (-> ACTIVE) or reject (-> ARCHIVED) a listing awaiting moderation.
// Only listings currently in PENDING/SCRAPED_UNVERIFIED can be moderated
// here - this endpoint is a review gate, not a general status editor for
// already-published listings (e.g. marking a listing RENTED is a separate
// owner-side action, not part of this).
export const moderateListing = async (req, res) => {
  try {
    const { id } = req.params;
    const { status } = req.body;

    const result = await query(
      `UPDATE listings
       SET status = $1
       WHERE id = $2 AND status IN ('PENDING', 'SCRAPED_UNVERIFIED')
       RETURNING id, title, status`,
      [status, id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Listing not found or not awaiting moderation.' });
    }

    res.json({ message: 'Listing moderated successfully.', listing: result.rows[0] });
  } catch (error) {
    console.error('Moderate listing error:', error);
    res.status(500).json({ error: 'Failed to moderate listing.' });
  }
};
