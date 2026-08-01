import pkg from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const { Pool } = pkg;

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max: 20, // Max concurrent connections
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

pool.on('connect', () => {
  console.log('⚡ Connected to PostgreSQL / PostGIS database successfully');
});

pool.on('error', (err) => {
  console.error('❌ Unexpected DB error:', err);
});

export const query = (text, params) => pool.query(text, params);
export default pool;