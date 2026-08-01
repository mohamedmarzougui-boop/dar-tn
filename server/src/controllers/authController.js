import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { query } from '../config/db.js';

// Clean and normalize Tunisian phone numbers to standard format (+216XXXXXX)
const formatTNPhone = (phone) => {
  let cleaned = phone.replace(/\s+/g, '').replace(/-/g, '');
  if (cleaned.startsWith('216')) {
    cleaned = '+' + cleaned;
  } else if (!cleaned.startsWith('+216') && cleaned.length === 8) {
    cleaned = '+216' + cleaned;
  }
  return cleaned;
};

export const registerUser = async (req, res) => {
  try {
    const { phone_number, full_name, password, role } = req.body;
    const formattedPhone = formatTNPhone(phone_number);

    // Check if phone number is already registered
    const userCheck = await query('SELECT id FROM users WHERE phone_number = $1', [formattedPhone]);
    if (userCheck.rows.length > 0) {
      return res.status(400).json({ error: 'Phone number is already registered.' });
    }

    // Hash Password
    const salt = await bcrypt.genSalt(10);
    const password_hash = await bcrypt.hash(password, salt);

    // Insert User with default 15 points
    const newUser = await query(
      `INSERT INTO users (phone_number, full_name, password_hash, role, points_balance)
       VALUES ($1, $2, $3, $4, 15)
       RETURNING id, phone_number, full_name, role, points_balance, is_phone_verified, created_at`,
      [formattedPhone, full_name, password_hash, role || 'TENANT']
    );

    const user = newUser.rows[0];

    // Record Bonus Signup Transaction
    await query(
      `INSERT INTO point_transactions (user_id, amount, type, description)
       VALUES ($1, 15, 'BONUS_SIGNUP', 'Welcome bonus points')`,
      [user.id]
    );

    // Generate JWT Token
    const token = jwt.sign(
      { id: user.id, phone_number: user.phone_number, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN }
    );

    res.status(201).json({
      message: 'Registration successful!',
      token,
      user
    });

  } catch (error) {
    console.error('Register error:', error);
    res.status(500).json({ error: 'Server error during registration.' });
  }
};

export const loginUser = async (req, res) => {
  try {
    const { phone_number, password } = req.body;
    const formattedPhone = formatTNPhone(phone_number);

    // Find User
    const result = await query(
      'SELECT id, phone_number, full_name, password_hash, role, points_balance, is_phone_verified FROM users WHERE phone_number = $1',
      [formattedPhone]
    );

    if (result.rows.length === 0) {
      return res.status(400).json({ error: 'Invalid phone number or password.' });
    }

    const user = result.rows[0];

    // Verify Password
    const isMatch = await bcrypt.compare(password, user.password_hash);
    if (!isMatch) {
      return res.status(400).json({ error: 'Invalid phone number or password.' });
    }

    // Generate JWT Token
    const token = jwt.sign(
      { id: user.id, phone_number: user.phone_number, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN }
    );

    delete user.password_hash;

    res.json({
      message: 'Login successful!',
      token,
      user
    });

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