import { Router } from 'express';
import { getMapListings, getListingById, createListing } from '../controllers/listingController.js';
import { authenticateToken } from '../middleware/authMiddleware.js';

const router = Router();

// Public routes
router.get('/map', getMapListings);
router.get('/:id', getListingById);

// Protected routes (Requires Auth Token)
router.post('/', authenticateToken, createListing);

export default router;
