import { Router } from 'express';
import { body } from 'express-validator';
import rateLimit from 'express-rate-limit';
import { registerUser, loginUser, getMe, formatTNPhone } from '../controllers/authController.js';
import { validateRequest } from '../middleware/validateMiddleware.js';
import { authenticateToken } from '../middleware/authMiddleware.js';

const router = Router();

// Throttle auth endpoints specifically - they're the most attractive target
// for credential-stuffing / brute-force, unlike the rest of the public API.
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many attempts. Please try again later.' },
});

// Sanitize before validating so "22 111 222" (a completely normal way to
// type a phone number) passes instead of being rejected for whitespace
// the formatter would have stripped anyway.
const phoneValidation = body('phone_number')
  .notEmpty().withMessage('Phone number is required')
  .customSanitizer(formatTNPhone)
  .matches(/^\+216[2-9]\d{7}$/).withMessage('Valid Tunisian phone number required (8 digits starting with 2-9)');

router.post(
  '/register',
  authLimiter,
  [
    phoneValidation,
    body('full_name').trim().notEmpty().withMessage('Full name is required'),
    body('password').isLength({ min: 8 }).withMessage('Password must be at least 8 characters'),
    body('role').optional().isIn(['TENANT', 'OWNER', 'AGENCY']).withMessage('Invalid role choice'),
  ],
  validateRequest,
  registerUser
);

router.post(
  '/login',
  authLimiter,
  [
    phoneValidation,
    body('password').notEmpty().withMessage('Password is required'),
  ],
  validateRequest,
  loginUser
);

router.get('/me', authenticateToken, getMe);

export default router;
