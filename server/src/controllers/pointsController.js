import { query } from '../config/db.js';

// Cost in points to unlock landlord contact info
const CONTACT_UNLOCK_COST = 5;

// 1. Unlock Landlord Phone Number
export const unlockContact = async (req, res) => {
  const tenantId = req.user.id;
  const { listing_id } = req.body;

  if (!listing_id) {
    return res.status(400).json({ error: 'listing_id is required.' });
  }

  try {
    // Check if tenant has ALREADY unlocked this listing before
    const existingUnlock = await query(
      `SELECT * FROM unlocked_contacts WHERE tenant_id = $1 AND listing_id = $2`,
      [tenantId, listing_id]
    );

    // If already unlocked, return the phone number WITHOUT deducting points again
    if (existingUnlock.rows.length > 0) {
      const landlordInfo = await query(
        `SELECT u.phone_number, u.full_name 
         FROM listings l 
         JOIN users u ON l.owner_id = u.id 
         WHERE l.id = $1`,
        [listing_id]
      );

      return res.json({
        message: 'Contact already unlocked previously.',
        already_unlocked: true,
        contact: landlordInfo.rows[0] || { phone_number: '+216 22 000 000', full_name: 'Propriétaire Scraped' }
      });
    }

    // Check user's current point balance
    const userResult = await query(`SELECT points_balance FROM users WHERE id = $1`, [tenantId]);
    const currentBalance = userResult.rows[0]?.points_balance || 0;

    if (currentBalance < CONTACT_UNLOCK_COST) {
      return res.status(402).json({
        error: 'Insufficient points balance.',
        points_balance: currentBalance,
        required: CONTACT_UNLOCK_COST,
        message: 'Please recharge your account via Flouci or D17 to view contact details.'
      });
    }

    // Transaction Block: Deduct 5 points & log unlock record
    await query('BEGIN');

    // 1. Deduct points from user
    const updatedUser = await query(
      `UPDATE users 
       SET points_balance = points_balance - $1 
       WHERE id = $2 
       RETURNING points_balance`,
      [CONTACT_UNLOCK_COST, tenantId]
    );

    // 2. Log in point_transactions table
    await query(
      `INSERT INTO point_transactions (user_id, amount, type, description)
       VALUES ($1, $2, 'CONTACT_UNLOCK', $3)`,
      [tenantId, -CONTACT_UNLOCK_COST, `Unlocked contact for listing ${listing_id}`]
    );

    // 3. Record in unlocked_contacts table
    await query(
      `INSERT INTO unlocked_contacts (tenant_id, listing_id, points_spent)
       VALUES ($1, $2, $3)`,
      [tenantId, listing_id, CONTACT_UNLOCK_COST]
    );

    await query('COMMIT');

    // Retrieve owner contact info
    const landlordInfo = await query(
      `SELECT u.phone_number, u.full_name 
       FROM listings l 
       JOIN users u ON l.owner_id = u.id 
       WHERE l.id = $1`,
      [listing_id]
    );

    res.json({
      message: 'Contact unlocked successfully!',
      points_spent: CONTACT_UNLOCK_COST,
      new_points_balance: updatedUser.rows[0].points_balance,
      contact: landlordInfo.rows[0] || { phone_number: '+216 22 000 000', full_name: 'Propriétaire Scraped' }
    });

  } catch (error) {
    await query('ROLLBACK');
    console.error('Unlock contact error:', error);
    res.status(500).json({ error: 'Failed to unlock contact.' });
  }
};

// 2. Get User Points Balance & History
export const getPointsHistory = async (req, res) => {
  try {
    const tenantId = req.user.id;

    const userRes = await query(`SELECT points_balance FROM users WHERE id = $1`, [tenantId]);
    const txRes = await query(
      `SELECT id, amount, type, description, created_at 
       FROM point_transactions 
       WHERE user_id = $1 
       ORDER BY created_at DESC LIMIT 20`,
      [tenantId]
    );

    res.json({
      points_balance: userRes.rows[0]?.points_balance || 0,
      transactions: txRes.rows
    });
  } catch (error) {
    console.error('Points history error:', error);
    res.status(500).json({ error: 'Failed to retrieve points history.' });
  }
};