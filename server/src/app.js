import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import dotenv from 'dotenv';
import listingRoutes from './routes/listingRoutes.js';
import authRoutes from './routes/authRoutes.js';
import pointsRoutes from './routes/pointsRoutes.js';
import imageRoutes from './routes/imageRoutes.js';
import adminRoutes from './routes/adminRoutes.js';
import { UPLOADS_DIR } from './middleware/uploadMiddleware.js';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 5000;

app.use(helmet());
app.use(cors());
app.use(express.json());

// Uploaded listing photos. The image proxy at /api/images/:imageId is the
// only thing meant to consume this directly (it self-fetches an image_url
// that may point here); this static mount just makes that URL fetchable.
app.use('/uploads', express.static(UPLOADS_DIR));

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', service: 'Dar-TN API', timestamp: new Date() });
});

// Mounting API Routes
app.use('/api/auth', authRoutes);
app.use('/api/listings', listingRoutes);
app.use('/api/points', pointsRoutes);
app.use('/api/images', imageRoutes);
app.use('/api/admin', adminRoutes);

app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Something went wrong on the server!' });
});

app.listen(PORT, () => {
  console.log(`🚀 Server running on http://localhost:${PORT}`);
});
