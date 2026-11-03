-- Supporting indexes (PostgreSQL does not index FK columns automatically;
-- payments(order_id) is already indexed by its UNIQUE constraint)
CREATE INDEX idx_locations_service_area    ON locations (service_area_id);
CREATE INDEX idx_locations_coordinates     ON locations (latitude, longitude);
CREATE INDEX idx_merchant_outlets_location ON merchant_outlets (location_id);
CREATE INDEX idx_service_orders_customer ON service_orders (customer_id);
CREATE INDEX idx_food_orders_outlet ON food_orders (merchant_outlet_id);


CREATE INDEX idx_vehicles_driver_partner   ON vehicles (driver_partner_id);
CREATE INDEX idx_trips_order               ON trips (order_id);
CREATE INDEX idx_trips_start_location      ON trips (start_location_id);
CREATE INDEX idx_trips_end_location        ON trips (end_location_id);
CREATE INDEX idx_driver_assignments_trip   ON driver_assignments (trip_id);
CREATE INDEX idx_driver_assignments_veh    ON driver_assignments (vehicle_id);

-- Composite/Filter Indexes untuk Optimasi Query Analitis
CREATE INDEX idx_service_orders_status_date ON service_orders (order_status, created_at);
CREATE INDEX idx_trips_status               ON trips (trip_status);
CREATE INDEX idx_driver_assignments_status  ON driver_assignments (assignment_status);