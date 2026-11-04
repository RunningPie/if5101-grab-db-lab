-- Domain Focus: trips, driver_assignments, vehicles, driver_partners

-- W1: Create New Trip Record upon Order Confirmation
-- Membuat record trip baru berstatus SEARCHING untuk order berstatus CONFIRMED yang belum memiliki trip.
-- Data generator tidak punya order seperti itu, sehingga order cash baru ORD9999001 dikonfirmasi lebih
-- dulu dalam transaksi yang sama, dan INSERT trip memilih order tersebut.
BEGIN;

INSERT INTO service_orders (order_id, created_at, order_status, total_amount, customer_id)
VALUES ('ORD9999001', CURRENT_TIMESTAMP, 'CONFIRMED', 15000.00, 'CUS0000001');

INSERT INTO mobility_orders (order_id, ride_type, passenger_count, pickup_notes)
VALUES ('ORD9999001', 'GrabBike', 1, NULL);

INSERT INTO payments (payment_id, payment_method, payment_status, amount, paid_at, order_id)
VALUES ('PAY9999001', 'CASH', 'PENDING', 15000.00, NULL, 'ORD9999001');

INSERT INTO trips (trip_id, started_at, completed_at, trip_status, order_id, start_location_id, end_location_id)
SELECT
    'TRP9999001',
    NULL,
    NULL,
    'SEARCHING',
    so.order_id,
    'LOC0000001',
    'LOC0000002'
FROM service_orders so
WHERE so.order_status = 'CONFIRMED'
  AND NOT EXISTS (SELECT 1 FROM trips t WHERE t.order_id = so.order_id)
LIMIT 1;

COMMIT;

-- W2: Dispatch Assignment Ping to Nearby Driver
-- Mengalokasikan tawaran trip (assignment) berstatus PENDING ke driver yang sedang aktif.
INSERT INTO driver_assignments (assignment_id, assigned_at, assignment_status, responded_at, ended_at, end_reason, trip_id, vehicle_id)
SELECT 
    'ASN9999001',
    CURRENT_TIMESTAMP,
    'PENDING',
    NULL,
    NULL,
    NULL,
    'TRP9999001',
    v.vehicle_id
FROM vehicles v
WHERE v.driver_partner_id IS NOT NULL
LIMIT 1;

-- W3: Driver Accepts Assignment & Starts Trip
-- Mengubah status assignment menjadi ACCEPTED serta memperbarui status trip dari ALLOCATED ke IN_PROGRESS.
BEGIN;

UPDATE driver_assignments
SET assignment_status = 'ACCEPTED', 
    responded_at = CURRENT_TIMESTAMP
WHERE assignment_id = 'ASN9999001';

UPDATE trips
SET trip_status = 'ALLOCATED'
WHERE trip_id = 'TRP9999001';

UPDATE trips
SET trip_status = 'IN_PROGRESS', 
    started_at = CURRENT_TIMESTAMP
WHERE trip_id = 'TRP9999001';

COMMIT;

-- W4: Driver Rejects Assignment / Expiry Handler
-- Menangani skenario penolakan tawaran trip oleh driver dengan mencatat end_reason.
-- Seperti W1, order cash baru ORD9999002 dikonfirmasi lebih dulu agar trip TRP9999002 punya order.
BEGIN;

INSERT INTO service_orders (order_id, created_at, order_status, total_amount, customer_id)
VALUES ('ORD9999002', CURRENT_TIMESTAMP, 'CONFIRMED', 15000.00, 'CUS0000001');

INSERT INTO mobility_orders (order_id, ride_type, passenger_count, pickup_notes)
VALUES ('ORD9999002', 'GrabBike', 1, NULL);

INSERT INTO payments (payment_id, payment_method, payment_status, amount, paid_at, order_id)
VALUES ('PAY9999002', 'CASH', 'PENDING', 15000.00, NULL, 'ORD9999002');

COMMIT;

INSERT INTO trips (trip_id, started_at, completed_at, trip_status, order_id, start_location_id, end_location_id)
SELECT 
    'TRP9999002',
    NULL,
    NULL,
    'SEARCHING',
    so.order_id,
    'LOC0000001',
    'LOC0000002'
FROM service_orders so
WHERE so.order_status = 'CONFIRMED'
  AND so.order_id <> 'ORD0000001'
  AND NOT EXISTS (SELECT 1 FROM trips t WHERE t.order_id = so.order_id)
LIMIT 1;

INSERT INTO driver_assignments (assignment_id, assigned_at, assignment_status, responded_at, ended_at, end_reason, trip_id, vehicle_id)
SELECT 
    'ASN9999002',
    CURRENT_TIMESTAMP,
    'PENDING',
    NULL,
    NULL,
    NULL,
    'TRP9999002',
    v.vehicle_id
FROM vehicles v
LIMIT 1 OFFSET 1;

UPDATE driver_assignments
SET assignment_status = 'REJECTED', 
    responded_at = CURRENT_TIMESTAMP, 
    ended_at = CURRENT_TIMESTAMP, 
    end_reason = 'Too far from pickup location'
WHERE assignment_id = 'ASN9999002';

-- W5: Complete Trip & Release Driver Availability
-- Menyelesaikan trip (COMPLETED) dan mengembalikan status ketersediaan driver menjadi ACTIVE.
BEGIN;

UPDATE trips
SET trip_status = 'COMPLETED', 
    completed_at = CURRENT_TIMESTAMP
WHERE trip_id = 'TRP9999001';

UPDATE driver_assignments
SET ended_at = CURRENT_TIMESTAMP
WHERE trip_id = 'TRP9999001' 
  AND assignment_status = 'ACCEPTED';

UPDATE driver_partners
SET driver_status = 'ACTIVE'
WHERE driver_partner_id = (
    SELECT v.driver_partner_id 
    FROM vehicles v 
    JOIN driver_assignments da ON v.vehicle_id = da.vehicle_id 
    WHERE da.trip_id = 'TRP9999001' 
      AND da.assignment_status = 'ACCEPTED'
    LIMIT 1
);

COMMIT;

-- Domain Focus: service_areas, locations, merchant_outlets, payments
-- ID baru memakai rentang 9999101 ke atas agar tidak bentrok dengan data generator maupun W1-W5.

-- W6: Onboard a New Service Area with Its Locations and Outlets
-- Mendaftarkan service area baru beserta lokasi dan outlet pertamanya dalam satu transaksi, sehingga
-- area, lokasi, dan outlet tersimpan bersama atau tidak sama sekali. Format alamat mengikuti generator.
BEGIN;

INSERT INTO service_areas (service_area_id, area_name, city, area_status)
VALUES ('SAR9999101', 'Cicendo', 'Bandung', 'ACTIVE');

INSERT INTO locations (location_id, latitude, longitude, address, service_area_id)
VALUES
    ('LOC9999101', -6.905200, 107.596400, 'Jl. Pajajaran No. 12, Cicendo, Bandung', 'SAR9999101'),
    ('LOC9999102', -6.911800, 107.601700, 'Jl. Kebon Kawung No. 5, Cicendo, Bandung', 'SAR9999101'),
    ('LOC9999103', -6.899600, 107.589300, 'Jl. Pasirkaliki No. 88, Cicendo, Bandung', 'SAR9999101');

INSERT INTO merchant_outlets (merchant_outlet_id, outlet_name, outlet_status, location_id)
VALUES
    ('OUT9999101', 'Warung Bu Sri', 'OPEN', 'LOC9999101'),
    ('OUT9999102', 'Kedai Kopi Pak Dadang', 'OPEN', 'LOC9999103');

COMMIT;

-- W7: Checkout with Non-Cash Payment Retry
-- Membuat mobility order beserta payment E_WALLET, menolak pembayaran pertama, lalu retry hingga PAID
-- dan order CONFIRMED. Transisi mengikuti trigger check_payment_status_transition():
-- PENDING -> FAILED -> PENDING -> PAID, sehingga retry dipecah menjadi dua UPDATE terpisah.
-- Order, subtype, dan payment dibuat dalam satu transaksi karena trigger spesialisasi (deferred)
-- baru diperiksa saat COMMIT. Membutuhkan lokasi dari W6.
BEGIN;

INSERT INTO service_orders (order_id, created_at, order_status, total_amount, customer_id)
VALUES ('ORD9999101', CURRENT_TIMESTAMP, 'PENDING', 20000.00, 'CUS0000001');

INSERT INTO mobility_orders (order_id, ride_type, passenger_count, pickup_notes)
VALUES ('ORD9999101', 'GrabCar', 2, 'Saya tunggu di lobi');

INSERT INTO payments (payment_id, payment_method, payment_status, amount, paid_at, order_id)
SELECT 'PAY9999101', 'E_WALLET', 'PENDING', so.total_amount, NULL, so.order_id
FROM service_orders so
WHERE so.order_id = 'ORD9999101';

COMMIT;

-- Payment gateway menolak percobaan pertama.
UPDATE payments
SET payment_status = 'FAILED'
WHERE payment_id = 'PAY9999101'
  AND payment_status = 'PENDING';

-- Retry berhasil: payment PAID, order dikonfirmasi, dan trip mulai mencari driver.
BEGIN;

UPDATE payments
SET payment_status = 'PENDING'
WHERE payment_id = 'PAY9999101'
  AND payment_status = 'FAILED';

UPDATE payments
SET payment_status = 'PAID', paid_at = CURRENT_TIMESTAMP
WHERE payment_id = 'PAY9999101'
  AND payment_status = 'PENDING';

UPDATE service_orders so
SET order_status = 'CONFIRMED'
FROM payments p
WHERE p.order_id = so.order_id
  AND so.order_id = 'ORD9999101'
  AND so.order_status = 'PENDING'
  AND p.payment_status = 'PAID';

INSERT INTO trips (trip_id, started_at, completed_at, trip_status, order_id, start_location_id, end_location_id)
SELECT 'TRP9999101', NULL, NULL, 'SEARCHING', so.order_id, 'LOC9999101', 'LOC9999102'
FROM service_orders so
WHERE so.order_id = 'ORD9999101'
  AND so.order_status = 'CONFIRMED';

COMMIT;

-- W8: Customer Cancels Before Pickup with Payment Settlement
-- Customer membatalkan order yang masih CONFIRMED, artinya trip-nya masih SEARCHING atau ALLOCATED dan
-- belum dijemput. Dalam satu transaksi: order menjadi CANCELLED, trip dan assignment-nya dibatalkan,
-- lalu payment diselesaikan sesuai aturan tim: yang sudah PAID (non-cash) di-refund dengan paid_at
-- tetap, dan yang masih PENDING (cash) menjadi FAILED. Langkah setelah UPDATE pertama hanya mengubah
-- data bila order benar-benar dibatalkan, sehingga order yang sudah IN_PROGRESS tidak berubah.
-- Dijalankan setelah W7.
BEGIN;

UPDATE service_orders
SET order_status = 'CANCELLED'
WHERE order_id = 'ORD9999101'
  AND order_status = 'CONFIRMED';

UPDATE trips t
SET trip_status = 'CANCELLED'
FROM service_orders so
WHERE so.order_id = t.order_id
  AND so.order_id = 'ORD9999101'
  AND so.order_status = 'CANCELLED'
  AND t.trip_status IN ('SEARCHING', 'ALLOCATED');

UPDATE driver_assignments da
SET assignment_status = 'CANCELLED',
    ended_at = CURRENT_TIMESTAMP,
    end_reason = 'Cancelled by customer'
FROM trips t
WHERE t.trip_id = da.trip_id
  AND t.order_id = 'ORD9999101'
  AND t.trip_status = 'CANCELLED'
  AND da.assignment_status IN ('PENDING', 'ACCEPTED');

UPDATE payments p
SET payment_status = 'REFUNDED'
FROM service_orders so
WHERE so.order_id = p.order_id
  AND so.order_id = 'ORD9999101'
  AND so.order_status = 'CANCELLED'
  AND p.payment_status = 'PAID';

UPDATE payments p
SET payment_status = 'FAILED'
FROM service_orders so
WHERE so.order_id = p.order_id
  AND so.order_id = 'ORD9999101'
  AND so.order_status = 'CANCELLED'
  AND p.payment_status = 'PENDING';

COMMIT;

-- W9: Deactivate a Service Area and Delist Its Outlets
-- Menonaktifkan service area Mergangsan (Yogyakarta) beserta outlet di seluruh lokasinya. Outlet yang
-- tidak punya food order berjalan (PENDING, CONFIRMED, atau IN_PROGRESS) langsung menjadi INACTIVE
-- (tidak lagi terdaftar). Outlet yang masih OPEN setelah itu pasti masih punya order berjalan, sehingga
-- hanya ditutup (CLOSED) agar order-nya tetap bisa diselesaikan.
BEGIN;

UPDATE service_areas
SET area_status = 'INACTIVE'
WHERE area_name = 'Mergangsan'
  AND city = 'Yogyakarta'
  AND area_status = 'ACTIVE';

UPDATE merchant_outlets mo
SET outlet_status = 'INACTIVE'
FROM locations l
JOIN service_areas sa ON sa.service_area_id = l.service_area_id
WHERE mo.location_id = l.location_id
  AND sa.area_name = 'Mergangsan'
  AND sa.city = 'Yogyakarta'
  AND mo.outlet_status <> 'INACTIVE'
  AND mo.merchant_outlet_id NOT IN (
      SELECT f.merchant_outlet_id
      FROM food_orders f
      JOIN service_orders so ON so.order_id = f.order_id
      WHERE so.order_status IN ('PENDING', 'CONFIRMED', 'IN_PROGRESS')
  );

UPDATE merchant_outlets mo
SET outlet_status = 'CLOSED'
FROM locations l
JOIN service_areas sa ON sa.service_area_id = l.service_area_id
WHERE mo.location_id = l.location_id
  AND sa.area_name = 'Mergangsan'
  AND sa.city = 'Yogyakarta'
  AND mo.outlet_status = 'OPEN';

COMMIT;

-- W10: Complete a Cash Ride and Collect the Payment (Transactional Query)
-- Query transaksional: driver menyelesaikan ride tunai dan menerima uang dari customer. Trip, order, dan
-- payment harus berubah bersama, sehingga ketiganya diubah dalam satu transaksi: trip dan order menjadi
-- COMPLETED, dan payment cash yang PENDING menjadi PAID. Jika salah satu UPDATE gagal, misalnya ditolak
-- trigger transisi status karena order sudah dibatalkan, seluruh transaksi batal sehingga tidak ada ride
-- yang tercatat selesai tanpa pembayaran. Transaksi pertama menyiapkan ride tunai yang sedang berjalan di
-- lokasi dari W6, karena status order hasil generator berbeda di setiap profil.
BEGIN;

INSERT INTO service_orders (order_id, created_at, order_status, total_amount, customer_id)
VALUES ('ORD9999102', CURRENT_TIMESTAMP - INTERVAL '30 minutes', 'IN_PROGRESS', 18000.00, 'CUS0000001');

INSERT INTO mobility_orders (order_id, ride_type, passenger_count, pickup_notes)
VALUES ('ORD9999102', 'GrabBike', 1, NULL);

INSERT INTO payments (payment_id, payment_method, payment_status, amount, paid_at, order_id)
VALUES ('PAY9999102', 'CASH', 'PENDING', 18000.00, NULL, 'ORD9999102');

INSERT INTO trips (trip_id, started_at, completed_at, trip_status, order_id, start_location_id, end_location_id)
VALUES ('TRP9999102', CURRENT_TIMESTAMP - INTERVAL '20 minutes', NULL, 'IN_PROGRESS', 'ORD9999102',
        'LOC9999102', 'LOC9999103');

COMMIT;

-- Ride selesai: trip, order, dan payment diperbarui bersama dalam satu transaksi.
BEGIN;

UPDATE trips
SET trip_status = 'COMPLETED', completed_at = CURRENT_TIMESTAMP
WHERE trip_id = 'TRP9999102';

UPDATE service_orders
SET order_status = 'COMPLETED'
WHERE order_id = 'ORD9999102';

UPDATE payments
SET payment_status = 'PAID', paid_at = CURRENT_TIMESTAMP
WHERE order_id = 'ORD9999102'
  AND payment_method = 'CASH';

COMMIT;
