import { Router } from 'express';
import { param, query as queryValidator } from 'express-validator';
import { getMapListings, getListingById } from '../controllers/listingController.js';
import { validateRequest } from '../middleware/validateMiddleware.js';

const router = Router();

const boundingBoxValidation = [
  queryValidator(['min_lat', 'max_lat']).isFloat({ min: -90, max: 90 }).withMessage('lat must be between -90 and 90'),
  queryValidator(['min_lng', 'max_lng']).isFloat({ min: -180, max: 180 }).withMessage('lng must be between -180 and 180'),
  queryValidator('property_type').optional().isIn([
    'STUDIO', 'S_PLUS_1', 'S_PLUS_2', 'S_PLUS_3', 'S_PLUS_4', 'COLOCATION', 'HOUSE', 'VILLA'
  ]),
  queryValidator('target_tenant').optional().isIn(['BOYS_ONLY', 'GIRLS_ONLY', 'STUDENT', 'FAMILY', 'ANY']),
  queryValidator('max_price').optional().isFloat({ min: 0 }),
];

router.get('/map', boundingBoxValidation, validateRequest, getMapListings);
router.get('/:id', param('id').isUUID(), validateRequest, getListingById);

export default router;
