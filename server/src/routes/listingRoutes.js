import { Router } from 'express';
import { body, param, query as queryValidator } from 'express-validator';
import rateLimit from 'express-rate-limit';
import { getMapListings, getListingById, createListing, parseListingText } from '../controllers/listingController.js';
import { validateRequest } from '../middleware/validateMiddleware.js';
import { authenticateToken } from '../middleware/authMiddleware.js';

const router = Router();

const PROPERTY_TYPES = ['STUDIO', 'S_PLUS_1', 'S_PLUS_2', 'S_PLUS_3', 'S_PLUS_4', 'COLOCATION', 'HOUSE', 'VILLA'];
const TARGET_TENANTS = ['BOYS_ONLY', 'GIRLS_ONLY', 'STUDENT', 'FAMILY', 'ANY'];

const boundingBoxValidation = [
  queryValidator(['min_lat', 'max_lat']).isFloat({ min: -90, max: 90 }).withMessage('lat must be between -90 and 90'),
  queryValidator(['min_lng', 'max_lng']).isFloat({ min: -180, max: 180 }).withMessage('lng must be between -180 and 180'),
  queryValidator('property_type').optional().isIn(PROPERTY_TYPES),
  queryValidator('target_tenant').optional().isIn(TARGET_TENANTS),
  queryValidator('max_price').optional().isFloat({ min: 0 }),
];

// Loose enough for a legitimate agency bulk-listing several units, tight
// enough to blunt a script spamming fake listings.
const createListingLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  limit: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many listings created. Please try again later.' },
});

const createListingValidation = [
  body('title').trim().notEmpty().withMessage('Title is required'),
  body('description').optional({ values: 'null' }).isString(),
  body('price_tnd').isFloat({ min: 0 }).withMessage('price_tnd must be a non-negative number'),
  body('deposit_tnd').optional().isFloat({ min: 0 }).withMessage('deposit_tnd must be a non-negative number'),
  body('property_type').isIn(PROPERTY_TYPES).withMessage(`property_type must be one of: ${PROPERTY_TYPES.join(', ')}`),
  body('target_tenant').optional().isIn(TARGET_TENANTS),
  body('bedrooms').optional().isInt({ min: 0 }),
  body('bathrooms').optional().isInt({ min: 0 }),
  body('has_climatisation').optional().isBoolean(),
  body('has_chauffage_central').optional().isBoolean(),
  body('has_wifi').optional().isBoolean(),
  body('has_elevator').optional().isBoolean(),
  body('is_furnished').optional().isBoolean(),
  body('surface_m2').optional({ values: 'null' }).isInt({ min: 0 }),
  body('city').trim().notEmpty().withMessage('City is required'),
  body('delegation').trim().notEmpty().withMessage('Delegation is required'),
  body('address_text').optional({ values: 'null' }).isString(),
  body('latitude').isFloat({ min: -90, max: 90 }).withMessage('A valid latitude is required'),
  body('longitude').isFloat({ min: -180, max: 180 }).withMessage('A valid longitude is required'),
];

const parseTextLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests. Please try again later.' },
});

router.get('/map', boundingBoxValidation, validateRequest, getMapListings);
router.get('/:id', param('id').isUUID(), validateRequest, getListingById);
router.post('/', authenticateToken, createListingLimiter, createListingValidation, validateRequest, createListing);
router.post(
  '/parse-text',
  authenticateToken,
  parseTextLimiter,
  body('text').trim().notEmpty().isLength({ max: 5000 }).withMessage('text is required (max 5000 characters)'),
  validateRequest,
  parseListingText
);

export default router;
