import { query } from '../config/db.js';
import pool from '../config/db.js';

const CONTACT_UNLOCK_COST = 5;

// Unlock a listing owner's phone number, spending CONTACT_UNLOCK_COST points.
//
// Runs as a single atomic transaction on one client (pool.query() alone would
// hand out a different connection per statement, making BEGIN/COMMIT/ROLLBACK
// no-ops - a real bug the previous version of this had). The unlock record is
// inserted first with ON CONFLICT DO NOTHING: that turns "has this tenant
// already unlocked this listing" into a single atomic check via the DB's own
// UNIQUE constraint, instead of a separate SELECT-then-INSERT that leaves a
// race window for concurrent requests to both pass the check and double-charge.
export const unlockContact = async (req, res) => {
  const tenantId = req.user.id;
  const { listing_id } = req.body;

  const client = await pool.connect();
  try {
    const listingResult = await client.query(
      `SELECT l.owner_id, u.phone_number, u.full_name
       FROM listings l
       LEFT JOIN users u ON l.owner_id = u.id
       WHERE l.id = $1`,
      [listing_id]
    );

    if (listingResult.rows.length === 0) {
      return res.status(404).json({ error: 'Listing not found.' });
    }

    const { owner_id, phone_number, full_name } = listingResult.rows[0];
    if (!owner_id || !phone_number) {
      return res.status(409).json({ error: 'This listing has no contact information available yet.' });
    }
    const contact = { phone_number, full_name };

    await client.query('BEGIN');

    const claim = await client.query(
      `INSERT INTO unlocked_contacts (tenant_id, listing_id, points_spent)
       VALUES ($1, $2, $3)
       ON CONFLICT (tenant_id, listing_id) DO NOTHING
       RETURNING id`,
      [tenantId, listing_id, CONTACT_UNLOCK_COST]
    );

    if (claim.rows.length === 0) {
      // Already unlocked in a prior transaction - don't charge again.
      await client.query('COMMIT');
      return res.json({ message: 'Contact already unlocked previously.', already_unlocked: true, contact });
    }

    // The balance check happens in the UPDATE itself (points_balance >= cost)
    // so there's no separate read-then-check race: either this statement
    // atomically deducts the points, or it matches zero rows.
    const deduction = await client.query(
      `UPDATE users
       SET points_balance = points_balance - $1
       WHERE id = $2 AND points_balance >= $1
       RETURNING points_balance`,
      [CONTACT_UNLOCK_COST, tenantId]
    );

    if (deduction.rows.length === 0) {
      await client.query('ROLLBACK');
      const balanceResult = await query('SELECT points_balance FROM users WHERE id = $1', [tenantId]);
      return res.status(402).json({
        error: 'Insufficient points balance.',
        points_balance: balanceResult.rows[0]?.points_balance ?? 0,
        required: CONTACT_UNLOCK_COST,
        message: 'Please recharge your account via Flouci or D17 to view contact details.',
      });
    }

    await client.query(
      `INSERT INTO point_transactions (user_id, amount, type, description)
       VALUES ($1, $2, 'CONTACT_UNLOCK', $3)`,
      [tenantId, -CONTACT_UNLOCK_COST, `Unlocked contact for listing ${listing_id}`]
    );

    await client.query('COMMIT');

    res.json({
      message: 'Contact unlocked successfully!',
      points_spent: CONTACT_UNLOCK_COST,
      new_points_balance: deduction.rows[0].points_balance,
      contact,
    });

  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Unlock contact error:', error);
    res.status(500).json({ error: 'Failed to unlock contact.' });
  } finally {
    client.release();
  }
};

export const getPointsHistory = async (req, res) => {
  try {
    const tenantId = req.user.id;

    const userRes = await query('SELECT points_balance FROM users WHERE id = $1', [tenantId]);
    const txRes = await query(
      `SELECT id, amount, type, description, created_at
       FROM point_transactions
       WHERE user_id = $1
       ORDER BY created_at DESC LIMIT 20`,
      [tenantId]
    );

    res.json({
      points_balance: userRes.rows[0]?.points_balance ?? 0,
      transactions: txRes.rows,
    });
  } catch (error) {
    console.error('Points history error:', error);
    res.status(500).json({ error: 'Failed to retrieve points history.' });
  }
};
