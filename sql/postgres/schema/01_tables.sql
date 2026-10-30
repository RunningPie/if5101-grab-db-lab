-- Enum types and tables with PK, UNIQUE, CHECK, and DEFAULT constraints.
-- Foreign keys are in 02_foreign_keys.sql, so tables can be created in any order.

-- Shared identifier format; primary keys additionally provide NOT NULL.
CREATE DOMAIN entity_id AS VARCHAR(10)
    CHECK (VALUE ~ '^[A-Z]{3}[0-9]{7}$');

-- 1. service_areas (entity set Service Areas)
CREATE TYPE area_status AS ENUM ('ACTIVE', 'INACTIVE');

CREATE TABLE service_areas (
    service_area_id  entity_id   PRIMARY KEY,
    area_name        VARCHAR(100)  NOT NULL,
    city             VARCHAR(100)  NOT NULL,
    area_status      area_status   NOT NULL DEFAULT 'ACTIVE',
    CONSTRAINT uq_service_areas_nama_kota UNIQUE (area_name, city)
);

-- 2. locations (entity set Locations + relationship set contains)
CREATE TABLE locations (
    location_id      entity_id   PRIMARY KEY,
    latitude         NUMERIC(9,6)  NOT NULL,
    longitude        NUMERIC(9,6)  NOT NULL,
    address          VARCHAR(255)  NOT NULL,
    service_area_id  entity_id   NOT NULL,
    CONSTRAINT chk_locations_latitude  CHECK (latitude  BETWEEN -90  AND 90),
    CONSTRAINT chk_locations_longitude CHECK (longitude BETWEEN -180 AND 180)
);

-- 3. merchant_outlets (entity set Merchant Outlets + relationship set located at)
CREATE TYPE outlet_status AS ENUM ('OPEN', 'CLOSED', 'INACTIVE');

CREATE TABLE merchant_outlets (
    merchant_outlet_id  entity_id    PRIMARY KEY,
    outlet_name         VARCHAR(100)   NOT NULL,
    outlet_status       outlet_status  NOT NULL DEFAULT 'OPEN',
    location_id         entity_id    NOT NULL
);

-- 4. payments (entity set Payments + relationship set paid by, one-to-one)
CREATE TYPE payment_method AS ENUM ('CASH', 'E_WALLET', 'CARD', 'PAYLATER');
CREATE TYPE payment_status AS ENUM ('PENDING', 'PAID', 'FAILED', 'REFUNDED');

CREATE TABLE payments (
    payment_id      entity_id     PRIMARY KEY,
    payment_method  payment_method  NOT NULL,
    payment_status  payment_status  NOT NULL DEFAULT 'PENDING',
    amount          NUMERIC(12,2)   NOT NULL,
    paid_at         TIMESTAMPTZ,
    order_id        entity_id     NOT NULL,
    CONSTRAINT uq_payments_order UNIQUE (order_id),
    CONSTRAINT chk_payments_amount CHECK (amount > 0),
    CONSTRAINT chk_payments_paid_at CHECK (
        (payment_status IN ('PAID', 'REFUNDED') AND paid_at IS NOT NULL) OR
        (payment_status IN ('PENDING', 'FAILED') AND paid_at IS NULL)
    )
);

-- 5. customers
CREATE TABLE customers (
    customer_id  entity_id PRIMARY KEY,
    full_name    VARCHAR(100) NOT NULL,
    phone_number VARCHAR(16),
    email        VARCHAR(100),
    CONSTRAINT chk_customers_phone CHECK (phone_number ~ '^\+?[0-9]{7,15}$'),
    CONSTRAINT chk_customers_email CHECK (email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$')
);

-- 6. service_orders
CREATE TYPE order_status AS ENUM ('PENDING', 'CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'FAILED');
CREATE TABLE service_orders (
    order_id     entity_id PRIMARY KEY,
    created_at   TIMESTAMPTZ NOT NULL,
    order_status order_status NOT NULL,
    total_amount NUMERIC(12,2) NOT NULL,
    customer_id  entity_id NOT NULL,
    CONSTRAINT chk_service_orders_total CHECK (total_amount >= 0)
);

-- 7. food_orders
CREATE TYPE preparation_status AS ENUM ('PENDING', 'PREPARING', 'READY');
CREATE TABLE food_orders (
    order_id           entity_id PRIMARY KEY,
    preparation_status preparation_status NOT NULL,
    delivery_notes     VARCHAR(100),
    merchant_outlet_id entity_id NOT NULL
);

-- 8. delivery_orders
CREATE TABLE delivery_orders (
    order_id            entity_id PRIMARY KEY,
    package_description VARCHAR(100) NOT NULL,
    package_weight      NUMERIC(5,2) NOT NULL,
    recipient_name      VARCHAR(100) NOT NULL,
    recipient_contact   VARCHAR(16) NOT NULL,
    CONSTRAINT chk_delivery_orders_contact CHECK (recipient_contact ~ '^\+?[0-9]{7,15}$')
);

-- 9. mobility_orders. These enum labels follow the explicit dictionary values.
CREATE TYPE ride_type AS ENUM ('GrabCar', 'GrabCarPlus', 'GrabBike', 'GrabElectric', 'GrabTaxi');
CREATE TABLE mobility_orders (
    order_id        entity_id PRIMARY KEY,
    ride_type       ride_type NOT NULL,
    passenger_count INTEGER NOT NULL,
    pickup_notes    VARCHAR(100),
    CONSTRAINT chk_mobility_orders_passengers CHECK (passenger_count >= 1)
);
