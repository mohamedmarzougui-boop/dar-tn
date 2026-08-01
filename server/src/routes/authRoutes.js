import { Router } from 'express';
import { body } from 'express-validator';
import { registerUser, loginUser, getMe } from '../controllers/authController.js';
import { validateRequest } from '../middleware/validateMiddleware.js';
import { authenticateToken } from '../middleware/authMiddleware.js';

const router = Router();

router.post(
  '/register',
  [
    body('phone_number')
      .notEmpty()
      .withMessage('Phone number is required')
      .matches(/^(\+216|216)?[2-9]\d{7}$/)
      .withMessage('Valid Tunisian phone number required (8 digits starting with 2, 4, 5, 7, 9)'),
    body('full_name').notEmpty().withMessage('Full name is required'),
    body('password').isLength({ min: 6 }).withMessage('Password must be at least 6 characters'),
    body('role').optional().isIn(['TENANT', 'OWNER', 'AGENCY']).withMessage('Invalid role choice')
  ],
  validateRequest,
  registerUser
);

router.post(
  '/login',
  [
    body('phone_number').notEmpty().withMessage('Phone number is required'),
    body('password').notEmpty().withMessage('Password is required')
  ],
  validateRequest,
  loginUser
);

router.get('/me', authenticateToken, getMe);

export default router;