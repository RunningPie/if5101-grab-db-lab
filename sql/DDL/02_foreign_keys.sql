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
