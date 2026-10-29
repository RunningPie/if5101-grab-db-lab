-- Enum types and tables with PK, UNIQUE, CHECK, and DEFAULT constraints.
-- Foreign keys are in 02_foreign_keys.sql, so tables can be created in any order.

-- 1. service_areas (entity set Service Areas)
CREATE TYPE area_status AS ENUM ('ACTIVE', 'INACTIVE');

CREATE TABLE service_areas (
    service_area_id  VARCHAR(10)   PRIMARY KEY,
    area_name        VARCHAR(100)  NOT NULL,
    city             VARCHAR(100)  NOT NULL,
    area_status      area_status   NOT NULL DEFAULT 'ACTIVE',
    CONSTRAINT uq_service_areas_nama_kota UNIQUE (area_name, city)
);

-- 2. locations (entity set Locations + relationship set contains)
CREATE TABLE locations (
    location_id      VARCHAR(10)   PRIMARY KEY,
    latitude         NUMERIC(9,6)  NOT NULL,
    longitude        NUMERIC(9,6)  NOT NULL,
    address          VARCHAR(255)  NOT NULL,
    service_area_id  VARCHAR(10)   NOT NULL,
    CONSTRAINT chk_locations_latitude  CHECK (latitude  BETWEEN -90  AND 90),
    CONSTRAINT chk_locations_longitude CHECK (longitude BETWEEN -180 AND 180)
);

-- 3. merchant_outlets (entity set Merchant Outlets + relationship set located at)
CREATE TYPE outlet_status AS ENUM ('OPEN', 'CLOSED', 'INACTIVE');

CREATE TABLE merchant_outlets (
    merchant_outlet_id  VARCHAR(10)    PRIMARY KEY,
    outlet_name         VARCHAR(100)   NOT NULL,
    outlet_status       outlet_status  NOT NULL DEFAULT 'OPEN',
    location_id         VARCHAR(10)    NOT NULL
);

-- 4. payments (entity set Payments + relationship set paid by, one-to-one)
CREATE TYPE payment_method AS ENUM ('CASH', 'E_WALLET', 'CARD', 'PAYLATER');
CREATE TYPE payment_status AS ENUM ('PENDING', 'PAID', 'FAILED', 'REFUNDED');

CREATE TABLE payments (
    payment_id      VARCHAR(10)     PRIMARY KEY,
    payment_method  payment_method  NOT NULL,
    payment_status  payment_status  NOT NULL DEFAULT 'PENDING',
    amount          NUMERIC(12,2)   NOT NULL,
    paid_at         TIMESTAMP,
    order_id        VARCHAR(10)     NOT NULL,
    CONSTRAINT uq_payments_order UNIQUE (order_id),
    CONSTRAINT chk_payments_amount CHECK (amount > 0),
    CONSTRAINT chk_payments_paid_at CHECK (
        (payment_status IN ('PAID', 'REFUNDED') AND paid_at IS NOT NULL) OR
        (payment_status IN ('PENDING', 'FAILED') AND paid_at IS NULL)
    )
);
