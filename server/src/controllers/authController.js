import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { query } from '../config/db.js';

const SALT_ROUNDS = 12;

// Normalize Tunisian phone numbers to a consistent +216XXXXXXXX form.
// Called as an express-validator sanitizer, so validation below always
// runs against the normalized value, not whatever the user typed.
export const formatTNPhone = (phone) => {
  const cleaned = phone.replace(/[\s-]/g, '');
  if (cleaned.startsWith('+216')) return cleaned;
  if (cleaned.startsWith('216')) return '+' + cleaned;
  if (cleaned.length === 8) return '+216' + cleaned;
  return cleaned;
};

const signToken = (user) =>
  jwt.sign(
    { id: user.id, phone_number: user.phone_number, role: user.role },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN }
  );

export const registerUser = async (req, res) => {
  try {
    const { phone_number, full_name, password, role } = req.body;
    const password_hash = await bcrypt.hash(password, SALT_ROUNDS);

    let newUser;
    try {
      newUser = await query(
        `INSERT INTO users (phone_number, full_name, password_hash, role)
         VALUES ($1, $2, $3, $4)
         RETURNING id, phone_number, full_name, role, points_balance, is_phone_verified, created_at`,
        [phone_number, full_name, password_hash, role || 'TENANT']
      );
    } catch (err) {
      // Let the DB's UNIQUE constraint be the source of truth instead of a
      // separate SELECT-then-INSERT, which has a race window between the
      // check and the insert under concurrent registrations.
      if (err.code === '23505') {
        return res.status(409).json({ error: 'Phone number is already registered.' });
      }
      throw err;
    }

    const user = newUser.rows[0];

    await query(
      `INSERT INTO point_transactions (user_id, amount, type, description)
       VALUES ($1, $2, 'BONUS_SIGNUP', 'Welcome bonus points')`,
      [user.id, user.points_balance]
    );

    const token = signToken(user);
    res.status(201).json({ message: 'Registration successful!', token, user });

  } catch (error) {
    console.error('Register error:', error);
    res.status(500).json({ error: 'Server error during registration.' });
  }
};

export const loginUser = async (req, res) => {
  try {
    const { phone_number, password } = req.body;

    const result = await query(
      'SELECT id, phone_number, full_name, password_hash, role, points_balance, is_phone_verified FROM users WHERE phone_number = $1',
      [phone_number]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Invalid phone number or password.' });
    }

    const user = result.rows[0];
    const isMatch = await bcrypt.compare(password, user.password_hash);
    if (!isMatch) {
      return res.status(401).json({ error: 'Invalid phone number or password.' });
    }

    delete user.password_hash;
    const token = signToken(user);
    res.json({ message: 'Login successful!', token, user });

  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Server error during login.' });
  }
};

export const getMe = async (req, res) => {
  try {
    const result = await query(
      'SELECT id, phone_number, full_name, email, role, points_balance, is_phone_verified, profile_image_url, created_at FROM users WHERE id = $1',
      [req.user.id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found.' });
    }

    res.json({ user: result.rows[0] });
  } catch (error) {
    console.error('GetMe error:', error);
    res.status(500).json({ error: 'Server error retrieving profile.' });
  }
};
