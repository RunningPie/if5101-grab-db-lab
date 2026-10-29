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

-- payments -> service_orders (relationship set paid by): fk_payments_order
-- will be added once service_orders is merged.
