-- Supporting indexes (PostgreSQL does not index FK columns automatically;
-- payments(order_id) is already indexed by its UNIQUE constraint)
CREATE INDEX idx_locations_service_area    ON locations (service_area_id);
CREATE INDEX idx_locations_koordinat       ON locations (latitude, longitude);
CREATE INDEX idx_merchant_outlets_location ON merchant_outlets (location_id);
