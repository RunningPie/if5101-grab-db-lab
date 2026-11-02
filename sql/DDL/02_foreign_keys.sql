-- Foreign keys. Run after 01_tables.sql.

-- locations -> service_areas (relationship set contains)
ALTER TABLE locations
    ADD CONSTRAINT fk_locations_service_area
        FOREIGN KEY (service_area_id) REFERENCES service_areas (service_area_id)
        ON UPDATE CASCADE ON DELETE RESTRICT;

-- merchant_outlets -> locations (relationship set located at)
ALTER TABLE merchant_outlets
    ADD CONSTRAINT fk_merchant_outlets_location
        FOREIGN KEY (location_id) REFERENCES locations (location_id)
        ON UPDATE CASCADE ON DELETE RESTRICT;


ALTER TABLE service_orders
    ADD CONSTRAINT fk_service_orders_customer FOREIGN KEY (customer_id) REFERENCES customers (customer_id);
ALTER TABLE food_orders
    ADD CONSTRAINT fk_food_orders_order FOREIGN KEY (order_id) REFERENCES service_orders (order_id),
    ADD CONSTRAINT fk_food_orders_outlet FOREIGN KEY (merchant_outlet_id) REFERENCES merchant_outlets (merchant_outlet_id);
ALTER TABLE delivery_orders
    ADD CONSTRAINT fk_delivery_orders_order FOREIGN KEY (order_id) REFERENCES service_orders (order_id);
ALTER TABLE mobility_orders
    ADD CONSTRAINT fk_mobility_orders_order FOREIGN KEY (order_id) REFERENCES service_orders (order_id);
ALTER TABLE payments
    ADD CONSTRAINT fk_payments_order FOREIGN KEY (order_id) REFERENCES service_orders (order_id);

-- driver_assignments -> trips & vehicles (relationship set assigned & fulfills)
ALTER TABLE driver_assignments
    ADD CONSTRAINT fk_assignments_trip
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    ADD CONSTRAINT fk_assignments_vehicle
        FOREIGN KEY (vehicle_id) REFERENCES vehicles (vehicle_id)
        ON UPDATE CASCADE ON DELETE RESTRICT;

-- trips -> service_orders & locations (relationship set generates, starts at, ends at)
ALTER TABLE trips
    ADD CONSTRAINT fk_trips_service_order
        FOREIGN KEY (order_id) REFERENCES service_orders (order_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    ADD CONSTRAINT fk_trips_start_location
        FOREIGN KEY (start_location_id) REFERENCES locations (location_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    ADD CONSTRAINT fk_trips_end_location
        FOREIGN KEY (end_location_id) REFERENCES locations (location_id)
        ON UPDATE CASCADE ON DELETE RESTRICT;

-- vehicles -> driver_partners (relationship set registers)
ALTER TABLE vehicles
    ADD CONSTRAINT fk_vehicles_driver_partner
        FOREIGN KEY (driver_partner_id) REFERENCES driver_partners (driver_partner_id)
        ON UPDATE CASCADE ON DELETE RESTRICT;

