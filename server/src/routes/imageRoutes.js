import { Router } from 'express';
import { param } from 'express-validator';
import { getListingImage } from '../controllers/listingController.js';
import { validateRequest } from '../middleware/validateMiddleware.js';

const router = Router();

router.get('/:imageId', param('imageId').isUUID(), validateRequest, getListingImage);

export default router;
