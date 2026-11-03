-- ============================================================================
-- MILESTONE 4: TRANSACTIONAL WRITE QUERIES (OLTP)
-- Domain Focus: trips, driver_assignments, vehicles, driver_partners
-- ============================================================================

-- W1: Create New Trip Record upon Order Confirmation
INSERT INTO trips (
    trip_id, started_at, completed_at, trip_status, order_id, start_location_id, end_location_id
) VALUES (
    'TRP9999001', NULL, NULL, 'SEARCHING', 'ORD0000001', 'LOC0000001', 'LOC0000002'
);

-- W2: Dispatch Assignment Ping to Nearby Driver
INSERT INTO driver_assignments (
    assignment_id, assigned_at, assignment_status, responded_at, ended_at, end_reason, trip_id, vehicle_id
) VALUES (
    'ASN9999001', CURRENT_TIMESTAMP, 'PENDING', NULL, NULL, NULL, 'TRP9999001', 'VEH0000001'
);

-- W3: Driver Accepts Assignment & Starts Trip (Transaction Block)
-- Transisi bertahap: SEARCHING -> ALLOCATED -> IN_PROGRESS sesuai trigger check_trip_status_transition()
BEGIN;

UPDATE driver_assignments
SET assignment_status = 'ACCEPTED', responded_at = CURRENT_TIMESTAMP
WHERE assignment_id = 'ASN9999001';

UPDATE trips
SET trip_status = 'ALLOCATED'
WHERE trip_id = 'TRP9999001';

UPDATE trips
SET trip_status = 'IN_PROGRESS', started_at = CURRENT_TIMESTAMP
WHERE trip_id = 'TRP9999001';

COMMIT;

-- W4: Driver Rejects Assignment / Expiry Handler
-- Menangani penolakan assignment pada trip terpisah (TRP9999002) agar W5 tetap bisa berjalan lancar
INSERT INTO trips (
    trip_id, started_at, completed_at, trip_status, order_id, start_location_id, end_location_id
) VALUES (
    'TRP9999002', NULL, NULL, 'SEARCHING', 'ORD0000002', 'LOC0000001', 'LOC0000002'
);

INSERT INTO driver_assignments (
    assignment_id, assigned_at, assignment_status, responded_at, ended_at, end_reason, trip_id, vehicle_id
) VALUES (
    'ASN9999002', CURRENT_TIMESTAMP, 'PENDING', NULL, NULL, NULL, 'TRP9999002', 'VEH0000002'
);

UPDATE driver_assignments
SET assignment_status = 'REJECTED', responded_at = CURRENT_TIMESTAMP, ended_at = CURRENT_TIMESTAMP, end_reason = 'Too far from pickup location'
WHERE assignment_id = 'ASN9999002';

-- W5: Complete Trip & Release Driver Availability (Transaction Block)
-- Transisi: IN_PROGRESS -> COMPLETED untuk menyelesaikan perjalanan TRP9999001
BEGIN;

UPDATE trips
SET trip_status = 'COMPLETED', completed_at = CURRENT_TIMESTAMP
WHERE trip_id = 'TRP9999001';

UPDATE driver_assignments
SET ended_at = CURRENT_TIMESTAMP
WHERE trip_id = 'TRP9999001' AND assignment_status = 'ACCEPTED';

UPDATE driver_partners
SET driver_status = 'ACTIVE'
WHERE driver_partner_id = (
    SELECT v.driver_partner_id 
    FROM vehicles v 
    JOIN driver_assignments da ON v.vehicle_id = da.vehicle_id 
    WHERE da.trip_id = 'TRP9999001' AND da.assignment_status = 'ACCEPTED'
    LIMIT 1
);

COMMIT;

-- Domain Focus: service_areas, locations, merchant_outlets, payments
-- ID baru memakai rentang 9999101 ke atas agar tidak bentrok dengan data generator maupun W1-W5.

-- W6: Onboard a New Service Area with Its Locations and Outlets
-- Mendaftarkan service area baru beserta lokasi dan outlet pertamanya dalam satu statement atomik.
-- Data-modifying CTE berantai (INSERT ... RETURNING) memastikan lokasi hanya dibuat jika area berhasil
-- dibuat, dan outlet hanya dibuat di lokasi yang baru saja dibuat. Format alamat mengikuti generator.
WITH new_area AS (
    INSERT INTO service_areas (service_area_id, area_name, city, area_status)
    VALUES ('SAR9999101', 'Cicendo', 'Bandung', 'ACTIVE')
    RETURNING service_area_id, area_name, city
),
new_locations AS (
    INSERT INTO locations (location_id, latitude, longitude, address, service_area_id)
    SELECT
        v.location_id,
        v.latitude,
        v.longitude,
        v.street || ', ' || na.area_name || ', ' || na.city,
        na.service_area_id
    FROM new_area na
    CROSS JOIN (VALUES
        ('LOC9999101', -6.905200, 107.596400, 'Jl. Pajajaran No. 12'),
        ('LOC9999102', -6.911800, 107.601700, 'Jl. Kebon Kawung No. 5'),
        ('LOC9999103', -6.899600, 107.589300, 'Jl. Pasirkaliki No. 88')
    ) AS v (location_id, latitude, longitude, street)
    RETURNING location_id
)
INSERT INTO merchant_outlets (merchant_outlet_id, outlet_name, outlet_status, location_id)
SELECT v.merchant_outlet_id, v.outlet_name, 'OPEN', nl.location_id
FROM new_locations nl
JOIN (VALUES
    ('OUT9999101', 'Warung Bu Sri', 'LOC9999101'),
    ('OUT9999102', 'Kedai Kopi Pak Dadang', 'LOC9999103')
) AS v (merchant_outlet_id, outlet_name, location_id) ON v.location_id = nl.location_id
RETURNING merchant_outlet_id, outlet_name, location_id;

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
-- Membatalkan order CONFIRMED yang trip-nya belum dimulai, dalam satu statement atomik: trip
-- SEARCHING/ALLOCATED menjadi CANCELLED, assignment PENDING/ACCEPTED ditutup, order menjadi CANCELLED,
-- lalu payment diselesaikan sesuai aturan tim: non-cash yang sudah PAID menjadi REFUNDED (paid_at
-- tetap) dan cash yang masih PENDING menjadi FAILED. Baris order dikunci (FOR UPDATE), dan order hanya
-- dibatalkan jika trip-nya benar-benar berhasil dibatalkan, sehingga bila driver memulai trip pada saat
-- yang sama tidak ada yang berubah. Dijalankan setelah W7; bila order sudah tidak CONFIRMED,
-- statement ini juga tidak mengubah apa pun.
WITH target AS (
    SELECT so.order_id
    FROM service_orders so
    WHERE so.order_id = 'ORD9999101'
      AND so.order_status = 'CONFIRMED'
      AND NOT EXISTS (
          SELECT 1
          FROM trips t
          WHERE t.order_id = so.order_id
            AND t.trip_status IN ('IN_PROGRESS', 'COMPLETED')
      )
    FOR UPDATE
),
cancelled_trips AS (
    UPDATE trips t
    SET trip_status = 'CANCELLED'
    FROM target
    WHERE t.order_id = target.order_id
      AND t.trip_status IN ('SEARCHING', 'ALLOCATED')
    RETURNING t.trip_id
),
cancelled_assignments AS (
    UPDATE driver_assignments da
    SET assignment_status = 'CANCELLED',
        ended_at = CURRENT_TIMESTAMP,
        end_reason = 'Cancelled by customer'
    FROM cancelled_trips ct
    WHERE da.trip_id = ct.trip_id
      AND da.assignment_status IN ('PENDING', 'ACCEPTED')
    RETURNING da.assignment_id
),
cancelled_order AS (
    UPDATE service_orders so
    SET order_status = 'CANCELLED'
    FROM target
    WHERE so.order_id = target.order_id
      AND EXISTS (SELECT 1 FROM cancelled_trips)
    RETURNING so.order_id
)
UPDATE payments p
SET payment_status = CASE p.payment_status
        WHEN 'PAID' THEN 'REFUNDED'::payment_status
        ELSE 'FAILED'::payment_status
    END
FROM cancelled_order co
WHERE p.order_id = co.order_id
  AND p.payment_status IN ('PAID', 'PENDING')
RETURNING p.payment_id, p.order_id, p.payment_method, p.payment_status, p.paid_at;

-- W9: Merchant Incident: Close an Outlet and Refund Its Completed Orders
-- Menangani insiden keamanan pangan di satu outlet: outlet yang masih OPEN ditutup sementara (CLOSED),
-- dan seluruh payment non-cash yang PAID dari food order COMPLETED di outlet tersebut dalam periode
-- insiden di-refund (PAID -> REFUNDED, paid_at tidak diubah), walaupun outlet sudah tidak OPEN.
-- Payment cash tidak di-refund karena mengikuti data dan aturan tim, refund hanya terjadi pada
-- pembayaran non-cash. Order yang masih berjalan tidak termasuk; batalkan lewat alur seperti W8.
-- Parameter dikumpulkan di CTE params.
WITH params AS (
    SELECT
        'OUT0000010'::entity_id AS outlet_id,
        TIMESTAMPTZ '2026-10-01 00:00:00+00' AS incident_from,
        TIMESTAMPTZ '2026-11-01 00:00:00+00' AS incident_to
),
closed_outlet AS (
    UPDATE merchant_outlets mo
    SET outlet_status = 'CLOSED'
    FROM params
    WHERE mo.merchant_outlet_id = params.outlet_id
      AND mo.outlet_status = 'OPEN'
    RETURNING mo.merchant_outlet_id
)
UPDATE payments p
SET payment_status = 'REFUNDED'
FROM params
JOIN food_orders f ON f.merchant_outlet_id = params.outlet_id
JOIN service_orders so ON so.order_id = f.order_id
WHERE p.order_id = f.order_id
  AND so.order_status = 'COMPLETED'
  AND so.created_at >= params.incident_from
  AND so.created_at < params.incident_to
  AND p.payment_status = 'PAID'
  AND p.payment_method <> 'CASH'
RETURNING p.payment_id, p.order_id, p.payment_method, p.amount, p.paid_at;

-- W10: Deactivate a Service Area and Delist Its Outlets
-- Menonaktifkan service area (dicari lewat kunci unik area_name + city), lalu menghitung ulang status
-- setiap outlet di seluruh lokasinya: outlet tanpa food order berjalan menjadi INACTIVE (tidak lagi
-- terdaftar), sedangkan outlet yang masih punya order PENDING, CONFIRMED, atau IN_PROGRESS menjadi
-- CLOSED (berhenti menerima order baru sambil menyelesaikan order yang ada). Karena status outlet
-- selalu dihitung dari order yang berjalan, statement ini aman dijalankan ulang: eksekusi berikutnya
-- mengubah outlet CLOSED menjadi INACTIVE setelah order-nya selesai, dan merapikan outlet yang
-- terlewat, misalnya karena order masuk bersamaan dengan eksekusi sebelumnya.
WITH params AS (
    SELECT 'Mergangsan'::VARCHAR(100) AS area_name, 'Yogyakarta'::VARCHAR(100) AS city
),
target_area AS (
    SELECT sa.service_area_id
    FROM service_areas sa
    JOIN params ON params.area_name = sa.area_name AND params.city = sa.city
),
deactivated_area AS (
    UPDATE service_areas sa
    SET area_status = 'INACTIVE'
    FROM target_area ta
    WHERE sa.service_area_id = ta.service_area_id
      AND sa.area_status = 'ACTIVE'
    RETURNING sa.service_area_id
),
outlet_changes AS (
    SELECT
        mo.merchant_outlet_id,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM food_orders f
                JOIN service_orders so ON so.order_id = f.order_id
                WHERE f.merchant_outlet_id = mo.merchant_outlet_id
                  AND so.order_status IN ('PENDING', 'CONFIRMED', 'IN_PROGRESS')
            ) THEN 'CLOSED'::outlet_status
            ELSE 'INACTIVE'::outlet_status
        END AS new_status
    FROM target_area ta
    JOIN locations l ON l.service_area_id = ta.service_area_id
    JOIN merchant_outlets mo ON mo.location_id = l.location_id
)
UPDATE merchant_outlets mo
SET outlet_status = oc.new_status
FROM outlet_changes oc
WHERE mo.merchant_outlet_id = oc.merchant_outlet_id
  AND mo.outlet_status <> oc.new_status
RETURNING mo.merchant_outlet_id, mo.outlet_name, mo.outlet_status;
