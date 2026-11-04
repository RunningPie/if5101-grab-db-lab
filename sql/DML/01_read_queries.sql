-- R1: Driver Performance & Acceptance Rate Analysis
-- Menganalisis tingkat penerimaan tawaran trip (Acceptance Rate) dari semesta keputusan aktif driver (ACCEPTED dan REJECTED).
SELECT 
    dp.driver_partner_id,
    dp.full_name,
    COUNT(CASE WHEN da.assignment_status = 'ACCEPTED' THEN 1 END) AS total_accepted,
    COUNT(CASE WHEN da.assignment_status = 'REJECTED' THEN 1 END) AS total_rejected,
    COUNT(CASE WHEN da.assignment_status = 'EXPIRED' THEN 1 END) AS total_expired,
    ROUND(
        (COUNT(CASE WHEN da.assignment_status = 'ACCEPTED' THEN 1 END)::NUMERIC / 
        NULLIF(COUNT(CASE WHEN da.assignment_status IN ('ACCEPTED', 'REJECTED') THEN 1 END), 0)) * 100, 2
    ) AS acceptance_rate_percentage
FROM driver_partners dp
JOIN vehicles v ON dp.driver_partner_id = v.driver_partner_id
JOIN driver_assignments da ON v.vehicle_id = da.vehicle_id
GROUP BY dp.driver_partner_id, dp.full_name
HAVING COUNT(CASE WHEN da.assignment_status IN ('ACCEPTED', 'REJECTED') THEN 1 END) >= 5
ORDER BY acceptance_rate_percentage DESC, total_accepted DESC;

-- R2: Top 10 Drivers by Cumulative Trip Duration & Completed Trips
-- Menampilkan 10 driver partner teratas berdasarkan total durasi perjalanan dan jumlah trip yang telah diselesaikan.
SELECT 
    dp.driver_partner_id,
    dp.full_name,
    COUNT(t.trip_id) AS total_completed_trips,
    ROUND(SUM(EXTRACT(EPOCH FROM (t.completed_at - t.started_at)) / 60)::NUMERIC, 2) AS total_duration_minutes,
    ROUND(AVG(EXTRACT(EPOCH FROM (t.completed_at - t.started_at)) / 60)::NUMERIC, 2) AS avg_duration_per_trip_minutes
FROM driver_partners dp
JOIN vehicles v ON dp.driver_partner_id = v.driver_partner_id
JOIN driver_assignments da ON v.vehicle_id = da.vehicle_id
JOIN trips t ON da.trip_id = t.trip_id
WHERE da.assignment_status = 'ACCEPTED'
  AND t.trip_status = 'COMPLETED'
GROUP BY dp.driver_partner_id, dp.full_name
ORDER BY total_duration_minutes DESC
LIMIT 10;

-- R3: Vehicle Type Utilization across Hourly Peak Times
-- Menganalisis jumlah transaksi trip dan jumlah unik kendaraan yang beroperasi per jenis kendaraan pada tiap jam.
SELECT 
    v.vehicle_type,
    EXTRACT(HOUR FROM t.started_at) AS trip_hour,
    COUNT(t.trip_id) AS total_trips,
    COUNT(DISTINCT v.vehicle_id) AS unique_vehicles_used
FROM vehicles v
JOIN driver_assignments da ON v.vehicle_id = da.vehicle_id
JOIN trips t ON da.trip_id = t.trip_id
WHERE da.assignment_status = 'ACCEPTED'
  AND t.trip_status IN ('COMPLETED', 'IN_PROGRESS')
GROUP BY v.vehicle_type, EXTRACT(HOUR FROM t.started_at)
ORDER BY trip_hour ASC, total_trips DESC;

-- R4: Re-assignment History Analysis (High Allocation Churn Trips)
-- Mengidentifikasi trip dengan tingkat alokasi tinggi (>2 kali penugasan driver) yang pada akhirnya berhasil diselesaikan.
WITH trip_assignment_counts AS (
    SELECT 
        trip_id,
        COUNT(assignment_id) AS total_attempts,
        COUNT(CASE WHEN assignment_status = 'ACCEPTED' THEN 1 END) AS has_accepted
    FROM driver_assignments
    GROUP BY trip_id
)
SELECT 
    t.trip_id,
    t.order_id,
    t.trip_status,
    tac.total_attempts,
    t.started_at,
    t.completed_at
FROM trips t
JOIN trip_assignment_counts tac ON t.trip_id = tac.trip_id
WHERE tac.total_attempts > 2
  AND tac.has_accepted > 0
ORDER BY tac.total_attempts DESC, t.started_at DESC;

-- R5: Total Trips per Service Area
-- Menganalisis total volume perjalanan yang dimulai dari tiap service area untuk pemetaan permintaan operasional.
SELECT 
    sa.service_area_id,
    sa.area_name,
    sa.city,
    COUNT(t.trip_id) AS total_trips
FROM service_areas sa
JOIN locations l ON sa.service_area_id = l.service_area_id
JOIN trips t ON l.location_id = t.start_location_id
GROUP BY sa.service_area_id, sa.area_name, sa.city
ORDER BY total_trips DESC;

-- R6: Revenue and Refunds per Service Area
-- Menghitung pendapatan bersih (payment PAID), nilai refund, dan tingkat refund per service area.
-- Area sebuah order diambil dari lokasi pickup trip-nya. Satu order seharusnya hanya punya satu trip,
-- tetapi skema tidak memaksanya (W1 dan W4 menambah trip kedua), sehingga CTE first_trip memilih satu
-- trip per order agar pembayaran tidak terhitung dua kali.
WITH first_trip AS (
    SELECT order_id, MIN(trip_id) AS trip_id
    FROM trips
    GROUP BY order_id
)
SELECT
    sa.city,
    sa.area_name,
    COUNT(*) AS settled_payments,
    COALESCE(SUM(p.amount) FILTER (WHERE p.payment_status = 'PAID'), 0) AS net_revenue,
    COALESCE(SUM(p.amount) FILTER (WHERE p.payment_status = 'REFUNDED'), 0) AS refunded_amount,
    ROUND(100.0 * COUNT(*) FILTER (WHERE p.payment_status = 'REFUNDED') / COUNT(*), 2) AS refund_rate_pct
FROM payments p
JOIN first_trip ft ON ft.order_id = p.order_id
JOIN trips t ON t.trip_id = ft.trip_id
JOIN locations l ON l.location_id = t.start_location_id
JOIN service_areas sa ON sa.service_area_id = l.service_area_id
WHERE p.payment_status IN ('PAID', 'REFUNDED')
GROUP BY sa.service_area_id, sa.city, sa.area_name
ORDER BY net_revenue DESC;

-- R7: Monthly Payment Summary per Payment Method
-- Merangkum pembayaran tiap metode per bulan order (UTC): jumlah payment per status, persentase
-- payment yang berhasil dibayar dari payment yang sudah selesai (bukan PENDING), pendapatan bersih,
-- dan rata-rata waktu settlement dari order dibuat hingga paid_at. Untuk CASH, status FAILED berarti
-- order dibatalkan sebelum dibayar, bukan pembayaran yang ditolak.
SELECT
    date_trunc('month', so.created_at AT TIME ZONE 'UTC')::date AS order_month,
    p.payment_method,
    COUNT(*) AS total_payments,
    COUNT(*) FILTER (WHERE p.payment_status = 'PAID') AS paid,
    COUNT(*) FILTER (WHERE p.payment_status = 'REFUNDED') AS refunded,
    COUNT(*) FILTER (WHERE p.payment_status = 'FAILED') AS failed,
    COUNT(*) FILTER (WHERE p.payment_status = 'PENDING') AS pending,
    ROUND(100.0 * COUNT(*) FILTER (WHERE p.payment_status = 'PAID')
          / NULLIF(COUNT(*) FILTER (WHERE p.payment_status <> 'PENDING'), 0), 2) AS paid_pct,
    COALESCE(SUM(p.amount) FILTER (WHERE p.payment_status = 'PAID'), 0) AS net_revenue,
    ROUND(AVG(EXTRACT(EPOCH FROM p.paid_at - so.created_at) / 60)::NUMERIC, 1) AS avg_settle_minutes
FROM payments p
JOIN service_orders so ON so.order_id = p.order_id
GROUP BY order_month, p.payment_method
ORDER BY order_month, net_revenue DESC;

-- R8: Top 10 Merchant Outlets by Food Revenue
-- Menampilkan 10 outlet dengan pendapatan bersih tertinggi dari food order yang selesai (COMPLETED),
-- dilengkapi lokasi outlet, jumlah order, rata-rata nilai order, dan tingkat refund.
SELECT
    mo.merchant_outlet_id,
    mo.outlet_name,
    mo.outlet_status,
    sa.city,
    sa.area_name,
    COUNT(*) AS completed_orders,
    COALESCE(SUM(p.amount) FILTER (WHERE p.payment_status = 'PAID'), 0) AS net_revenue,
    ROUND(AVG(p.amount), 2) AS avg_order_value,
    ROUND(100.0 * COUNT(*) FILTER (WHERE p.payment_status = 'REFUNDED') / COUNT(*), 2) AS refund_rate_pct
FROM merchant_outlets mo
JOIN locations l ON l.location_id = mo.location_id
JOIN service_areas sa ON sa.service_area_id = l.service_area_id
JOIN food_orders f ON f.merchant_outlet_id = mo.merchant_outlet_id
JOIN service_orders so ON so.order_id = f.order_id
JOIN payments p ON p.order_id = f.order_id
WHERE so.order_status = 'COMPLETED'
GROUP BY mo.merchant_outlet_id, mo.outlet_name, mo.outlet_status, sa.city, sa.area_name
ORDER BY net_revenue DESC, mo.merchant_outlet_id
LIMIT 10;

-- R9: Outlet Supply vs Food Demand per Service Area (October 2026)
-- Membandingkan pasokan outlet (jumlah outlet dan yang masih OPEN) dengan permintaan food order pada
-- bulan terakhir periode dataset (Oktober 2026) per service area. orders_per_open_outlet adalah beban
-- rata-rata tiap outlet yang masih buka, sehingga area dengan nilai tertinggi paling kekurangan outlet.
-- Outlet dan order dihitung di CTE terpisah agar jumlahnya tidak berlipat saat di-join, lalu LEFT JOIN
-- membuat area tanpa outlet atau tanpa order tetap muncul.
WITH area_outlets AS (
    SELECT
        l.service_area_id,
        COUNT(*) AS total_outlets,
        COUNT(*) FILTER (WHERE mo.outlet_status = 'OPEN') AS open_outlets
    FROM merchant_outlets mo
    JOIN locations l ON l.location_id = mo.location_id
    GROUP BY l.service_area_id
),
area_orders AS (
    SELECT
        l.service_area_id,
        COUNT(*) AS food_orders
    FROM food_orders f
    JOIN service_orders so ON so.order_id = f.order_id
    JOIN merchant_outlets mo ON mo.merchant_outlet_id = f.merchant_outlet_id
    JOIN locations l ON l.location_id = mo.location_id
    WHERE so.created_at >= '2026-10-01 00:00:00+00'
      AND so.created_at < '2026-11-01 00:00:00+00'
    GROUP BY l.service_area_id
)
SELECT
    sa.city,
    sa.area_name,
    sa.area_status,
    COALESCE(ao.total_outlets, 0) AS total_outlets,
    COALESCE(ao.open_outlets, 0) AS open_outlets,
    COALESCE(od.food_orders, 0) AS food_orders,
    ROUND(od.food_orders::NUMERIC / NULLIF(ao.open_outlets, 0), 2) AS orders_per_open_outlet
FROM service_areas sa
LEFT JOIN area_outlets ao ON ao.service_area_id = sa.service_area_id
LEFT JOIN area_orders od ON od.service_area_id = sa.service_area_id
ORDER BY orders_per_open_outlet DESC NULLS LAST, sa.city, sa.area_name;

-- R10: Open Merchant Outlets in a Service Area (Operational Query)
-- Query operasional: mengambil halaman pertama (20 outlet) daftar outlet yang sedang OPEN di satu
-- service area aktif, beserta alamat dan koordinatnya, seperti yang ditampilkan aplikasi saat customer
-- di Tebet, Jakarta membuka menu pesan makanan. Berbeda dengan R6-R9 yang merangkum data, query ini
-- hanya membaca baris yang dibutuhkan untuk satu permintaan pengguna dan dijalankan sangat sering.
SELECT
    mo.merchant_outlet_id,
    mo.outlet_name,
    l.address,
    l.latitude,
    l.longitude
FROM service_areas sa
JOIN locations l ON l.service_area_id = sa.service_area_id
JOIN merchant_outlets mo ON mo.location_id = l.location_id
WHERE sa.area_name = 'Tebet'
  AND sa.city = 'Jakarta'
  AND sa.area_status = 'ACTIVE'
  AND mo.outlet_status = 'OPEN'
ORDER BY mo.outlet_name, mo.merchant_outlet_id
LIMIT 20;
