-- Domain Focus: trips, driver_assignments, vehicles, driver_partners

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


-- Domain Focus: service_areas, locations, merchant_outlets, payments

-- R6: Net Revenue per Service Area with City Subtotals
-- Menghitung pendapatan bersih (PAID) dan refund per service area beserta subtotal per kota dan
-- grand total (ROLLUP), lalu pangsa pendapatan area terhadap kotanya dan peringkat area di kotanya.
-- Area order diambil dari lokasi pickup trip. Aturan tim menetapkan satu order paling banyak punya
-- satu trip, tetapi skema tidak memaksanya (W1 dan W4 menambah trip kedua), sehingga DISTINCT ON
-- mengambil trip pertama per order agar pembayaran tidak terhitung ganda.
WITH order_pickup AS (
    SELECT DISTINCT ON (t.order_id)
        t.order_id,
        t.start_location_id
    FROM trips t
    ORDER BY t.order_id, t.trip_id
),
settled_payments AS (
    SELECT
        sa.city,
        sa.area_name,
        p.payment_method,
        p.payment_status,
        p.amount
    FROM payments p
    JOIN order_pickup op ON op.order_id = p.order_id
    JOIN locations l ON l.location_id = op.start_location_id
    JOIN service_areas sa ON sa.service_area_id = l.service_area_id
    WHERE p.payment_status IN ('PAID', 'REFUNDED')
),
area_rollup AS (
    SELECT
        city,
        area_name,
        GROUPING(city) AS is_grand_total,
        GROUPING(area_name) AS is_subtotal,
        COUNT(*) AS settled_payments,
        SUM(amount) AS gross_amount,
        COALESCE(SUM(amount) FILTER (WHERE payment_status = 'REFUNDED'), 0) AS refunded_amount,
        COALESCE(SUM(amount) FILTER (WHERE payment_status = 'PAID'), 0) AS net_revenue,
        COUNT(*) FILTER (WHERE payment_status = 'REFUNDED') AS refunded_payments,
        COALESCE(SUM(amount) FILTER (WHERE payment_status = 'PAID' AND payment_method = 'CASH'), 0) AS cash_revenue
    FROM settled_payments
    GROUP BY ROLLUP (city, area_name)
)
SELECT
    CASE WHEN is_grand_total = 1 THEN 'ALL CITIES' ELSE city END AS city,
    CASE
        WHEN is_grand_total = 1 THEN 'GRAND TOTAL'
        WHEN is_subtotal = 1 THEN 'SUBTOTAL'
        ELSE area_name
    END AS area_name,
    settled_payments,
    gross_amount,
    refunded_amount,
    net_revenue,
    ROUND(100.0 * refunded_payments / settled_payments, 2) AS refund_rate_pct,
    ROUND(100.0 * cash_revenue / NULLIF(net_revenue, 0), 2) AS cash_share_pct,
    CASE WHEN is_subtotal = 0 THEN
        ROUND(100.0 * net_revenue / NULLIF(MAX(net_revenue) FILTER (WHERE is_subtotal = 1)
                                           OVER (PARTITION BY city), 0), 2)
    END AS share_of_city_pct,
    CASE WHEN is_subtotal = 0 THEN
        RANK() OVER (PARTITION BY city, is_subtotal ORDER BY net_revenue DESC)
    END AS rank_in_city
FROM area_rollup
ORDER BY is_grand_total, city, is_subtotal, net_revenue DESC;

-- R7: Monthly Payment Method KPIs with Month-over-Month Growth
-- Menganalisis hasil pembayaran tiap metode per bulan (UTC) dalam periode dataset. Payment yang sudah
-- selesai (bukan PENDING) dibagi menjadi PAID, REFUNDED, gagal bayar (non-cash FAILED), dan batal tanpa
-- dibayar (cash FAILED karena order dibatalkan), sehingga keempat persentase berjumlah 100 dan
-- pembatalan tidak terhitung sebagai kegagalan pembayaran. Dilengkapi pendapatan bersih, pangsanya per
-- bulan, pertumbuhan bulan ke bulan (LAG), serta median dan persentil ke-90 waktu settlement (dari
-- order dibuat hingga paid_at). Batas periode di params mengikuti config/dataset_profile.yaml.
WITH params AS (
    SELECT
        TIMESTAMPTZ '2026-05-01 00:00:00+00' AS period_start,
        TIMESTAMPTZ '2026-11-01 00:00:00+00' AS period_end
),
monthly AS (
    SELECT
        date_trunc('month', so.created_at AT TIME ZONE 'UTC')::date AS order_month,
        p.payment_method,
        COUNT(*) AS payments,
        COUNT(*) FILTER (WHERE p.payment_status = 'PENDING') AS pending,
        COUNT(*) FILTER (WHERE p.payment_status <> 'PENDING') AS resolved,
        COUNT(*) FILTER (WHERE p.payment_status = 'PAID') AS paid,
        COUNT(*) FILTER (WHERE p.payment_status = 'REFUNDED') AS refunded,
        COUNT(*) FILTER (WHERE p.payment_status = 'FAILED' AND p.payment_method <> 'CASH') AS payment_failed,
        COUNT(*) FILTER (WHERE p.payment_status = 'FAILED' AND p.payment_method = 'CASH') AS cancelled_unpaid,
        COALESCE(SUM(p.amount) FILTER (WHERE p.payment_status = 'PAID'), 0) AS net_revenue,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM p.paid_at - so.created_at))
            FILTER (WHERE p.paid_at IS NOT NULL) AS p50_settle_seconds,
        percentile_cont(0.9) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM p.paid_at - so.created_at))
            FILTER (WHERE p.paid_at IS NOT NULL) AS p90_settle_seconds
    FROM payments p
    JOIN service_orders so ON so.order_id = p.order_id
    CROSS JOIN params
    WHERE so.created_at >= params.period_start
      AND so.created_at < params.period_end
    GROUP BY order_month, p.payment_method
)
SELECT
    order_month,
    payment_method,
    payments,
    pending,
    ROUND(100.0 * paid / NULLIF(resolved, 0), 2) AS paid_pct,
    ROUND(100.0 * refunded / NULLIF(resolved, 0), 2) AS refunded_pct,
    ROUND(100.0 * payment_failed / NULLIF(resolved, 0), 2) AS payment_failed_pct,
    ROUND(100.0 * cancelled_unpaid / NULLIF(resolved, 0), 2) AS cancelled_unpaid_pct,
    net_revenue,
    ROUND(100.0 * net_revenue / NULLIF(SUM(net_revenue) OVER (PARTITION BY order_month), 0), 2)
        AS share_of_month_pct,
    ROUND(100.0 * (net_revenue - LAG(net_revenue) OVER w)
          / NULLIF(LAG(net_revenue) OVER w, 0), 2) AS mom_growth_pct,
    ROUND(p50_settle_seconds::numeric / 60, 1) AS p50_settle_minutes,
    ROUND(p90_settle_seconds::numeric / 60, 1) AS p90_settle_minutes
FROM monthly
WINDOW w AS (PARTITION BY payment_method ORDER BY order_month)
ORDER BY order_month, net_revenue DESC;

-- R8: Top 3 Merchant Outlets per City by Food Revenue
-- Meranking outlet di setiap kota berdasarkan pendapatan bersih dari food order yang selesai
-- (DENSE_RANK, sehingga outlet dengan nilai sama mendapat peringkat sama), dilengkapi rata-rata
-- nilai order, tingkat refund, dan pangsa pendapatan outlet terhadap service area-nya.
WITH outlet_sales AS (
    SELECT
        mo.merchant_outlet_id,
        mo.outlet_name,
        mo.outlet_status,
        sa.city,
        sa.area_name,
        COUNT(*) AS completed_orders,
        COALESCE(SUM(p.amount) FILTER (WHERE p.payment_status = 'PAID'), 0) AS net_revenue,
        AVG(p.amount) AS avg_order_value,
        COUNT(*) FILTER (WHERE p.payment_status = 'REFUNDED') AS refunded_orders
    FROM merchant_outlets mo
    JOIN locations l ON l.location_id = mo.location_id
    JOIN service_areas sa ON sa.service_area_id = l.service_area_id
    JOIN food_orders f ON f.merchant_outlet_id = mo.merchant_outlet_id
    JOIN service_orders so ON so.order_id = f.order_id
    JOIN payments p ON p.order_id = f.order_id
    WHERE so.order_status = 'COMPLETED'
    GROUP BY mo.merchant_outlet_id, sa.service_area_id
),
ranked AS (
    SELECT
        os.*,
        DENSE_RANK() OVER (PARTITION BY city ORDER BY net_revenue DESC) AS city_rank,
        ROUND(100.0 * net_revenue / NULLIF(SUM(net_revenue) OVER (PARTITION BY city, area_name), 0), 2)
            AS share_of_area_pct
    FROM outlet_sales os
)
SELECT
    city,
    city_rank,
    merchant_outlet_id,
    outlet_name,
    outlet_status,
    area_name,
    completed_orders,
    net_revenue,
    ROUND(avg_order_value, 2) AS avg_order_value,
    ROUND(100.0 * refunded_orders / completed_orders, 2) AS refund_rate_pct,
    share_of_area_pct
FROM ranked
WHERE city_rank <= 3
ORDER BY city, city_rank, merchant_outlet_id;

-- R9: Outlet Supply vs Food Demand per Service Area (Last 30 Days)
-- Membandingkan pasokan outlet (jumlah lokasi dan outlet per status) dengan permintaan food order
-- 30 hari terakhir periode dataset per service area (params.as_of mengikuti akhir periode di
-- config/dataset_profile.yaml). Permintaan dihitung di level area, termasuk order ke outlet yang kini
-- CLOSED/INACTIVE, lalu dibagi jumlah outlet yang saat ini OPEN, yaitu beban yang harus ditanggung
-- outlet yang masih buka. Setiap sisi diagregasi terpisah sebelum LEFT JOIN agar tidak terjadi fan-out
-- dan area tanpa outlet/order tetap muncul. Rasio area dibandingkan dengan rasio kota (hanya area
-- ACTIVE) untuk menandai area yang kekurangan atau kelebihan pasokan.
WITH params AS (
    SELECT TIMESTAMPTZ '2026-11-01 00:00:00+00' AS as_of
),
area_locations AS (
    SELECT service_area_id, COUNT(*) AS location_count
    FROM locations
    GROUP BY service_area_id
),
area_outlets AS (
    SELECT
        l.service_area_id,
        COUNT(*) FILTER (WHERE mo.outlet_status = 'OPEN') AS open_outlets,
        COUNT(*) FILTER (WHERE mo.outlet_status = 'CLOSED') AS closed_outlets,
        COUNT(*) FILTER (WHERE mo.outlet_status = 'INACTIVE') AS inactive_outlets
    FROM merchant_outlets mo
    JOIN locations l ON l.location_id = mo.location_id
    GROUP BY l.service_area_id
),
area_demand AS (
    SELECT
        l.service_area_id,
        COUNT(*) AS food_orders,
        COUNT(*) FILTER (WHERE so.order_status IN ('CANCELLED', 'FAILED')) AS lost_orders
    FROM food_orders f
    JOIN service_orders so ON so.order_id = f.order_id
    JOIN merchant_outlets mo ON mo.merchant_outlet_id = f.merchant_outlet_id
    JOIN locations l ON l.location_id = mo.location_id
    CROSS JOIN params
    WHERE so.created_at >= params.as_of - INTERVAL '30 days'
      AND so.created_at < params.as_of
    GROUP BY l.service_area_id
),
area_stats AS (
    SELECT
        sa.service_area_id,
        sa.city,
        sa.area_name,
        sa.area_status,
        COALESCE(al.location_count, 0) AS location_count,
        COALESCE(ao.open_outlets, 0) AS open_outlets,
        COALESCE(ao.closed_outlets, 0) AS closed_outlets,
        COALESCE(ao.inactive_outlets, 0) AS inactive_outlets,
        COALESCE(ad.food_orders, 0) AS food_orders_30d,
        COALESCE(ad.lost_orders, 0) AS lost_orders_30d
    FROM service_areas sa
    LEFT JOIN area_locations al ON al.service_area_id = sa.service_area_id
    LEFT JOIN area_outlets ao ON ao.service_area_id = sa.service_area_id
    LEFT JOIN area_demand ad ON ad.service_area_id = sa.service_area_id
),
with_city_ratio AS (
    SELECT
        ast.*,
        food_orders_30d::numeric / NULLIF(open_outlets, 0) AS orders_per_open_outlet,
        SUM(food_orders_30d) FILTER (WHERE area_status = 'ACTIVE') OVER (PARTITION BY city)::numeric
            / NULLIF(SUM(open_outlets) FILTER (WHERE area_status = 'ACTIVE') OVER (PARTITION BY city), 0)
            AS city_orders_per_open_outlet
    FROM area_stats ast
)
SELECT
    city,
    area_name,
    area_status,
    location_count,
    open_outlets,
    closed_outlets,
    inactive_outlets,
    food_orders_30d,
    ROUND(100.0 * lost_orders_30d / NULLIF(food_orders_30d, 0), 2) AS lost_order_pct,
    ROUND(orders_per_open_outlet, 2) AS orders_per_open_outlet,
    ROUND(city_orders_per_open_outlet, 2) AS city_orders_per_open_outlet,
    CASE
        WHEN area_status = 'INACTIVE' AND open_outlets > 0 THEN 'INACTIVE_AREA_HAS_OPEN_OUTLETS'
        WHEN area_status = 'INACTIVE' THEN 'NOT_SERVED'
        WHEN open_outlets = 0 THEN 'NO_OPEN_OUTLETS'
        WHEN orders_per_open_outlet > 1.25 * city_orders_per_open_outlet THEN 'UNDER_SUPPLIED'
        WHEN orders_per_open_outlet < 0.75 * city_orders_per_open_outlet THEN 'OVER_SUPPLIED'
        ELSE 'BALANCED'
    END AS supply_flag
FROM with_city_ratio
ORDER BY city, orders_per_open_outlet DESC NULLS LAST;

-- R10: Top Destination Areas per Origin Area for Completed Rides
-- Membangun matriks asal-tujuan antar service area untuk mobility order yang selesai. Jarak garis
-- lurus pickup ke drop-off dihitung dengan rumus haversine dari koordinat lokasi, lalu dihitung
-- rata-rata durasi, tarif (total_amount order), tarif per km, dan pangsa rute terhadap seluruh ride
-- dari area asal. Hanya trip COMPLETED milik order COMPLETED yang dihitung, satu trip per order
-- (lihat R6). CTE completed_rides sengaja MATERIALIZED agar penyaringan trip berjalan paralel
-- terpisah dari join ke locations; jika digabung, parallel hash join pada profil large melebihi
-- /dev/shm container Docker (64MB). Ditampilkan 3 peringkat tujuan teratas per area asal; RANK
-- memberi peringkat sama pada jumlah ride yang sama, sehingga satu area asal bisa menampilkan
-- lebih dari 3 baris.
WITH completed_rides AS MATERIALIZED (
    SELECT DISTINCT ON (t.order_id)
        t.start_location_id,
        t.end_location_id,
        so.total_amount AS amount,
        EXTRACT(EPOCH FROM t.completed_at - t.started_at) / 60 AS duration_minutes
    FROM trips t
    JOIN service_orders so ON so.order_id = t.order_id
    JOIN mobility_orders m ON m.order_id = t.order_id
    WHERE t.trip_status = 'COMPLETED'
      AND so.order_status = 'COMPLETED'
    ORDER BY t.order_id, t.trip_id
),
ride_distances AS (
    SELECT
        sl.service_area_id AS origin_area_id,
        el.service_area_id AS destination_area_id,
        cr.amount,
        cr.duration_minutes,
        2 * 6371 * ASIN(LEAST(1, SQRT(
            POWER(SIN(RADIANS(el.latitude - sl.latitude) / 2), 2)
            + COS(RADIANS(sl.latitude)) * COS(RADIANS(el.latitude))
              * POWER(SIN(RADIANS(el.longitude - sl.longitude) / 2), 2)
        ))) AS straight_km
    FROM completed_rides cr
    JOIN locations sl ON sl.location_id = cr.start_location_id
    JOIN locations el ON el.location_id = cr.end_location_id
),
routes AS (
    SELECT
        o.city,
        o.area_name AS origin_area,
        d.area_name AS destination_area,
        COUNT(*) AS rides,
        AVG(rd.straight_km) AS avg_straight_km,
        AVG(rd.duration_minutes) AS avg_duration_minutes,
        AVG(rd.amount) AS avg_fare,
        SUM(rd.amount) / NULLIF(SUM(rd.straight_km)::numeric, 0) AS fare_per_km,
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY o.service_area_id) AS share_of_origin_pct,
        RANK() OVER (PARTITION BY o.service_area_id ORDER BY COUNT(*) DESC) AS destination_rank
    FROM ride_distances rd
    JOIN service_areas o ON o.service_area_id = rd.origin_area_id
    JOIN service_areas d ON d.service_area_id = rd.destination_area_id
    GROUP BY o.service_area_id, d.service_area_id
)
SELECT
    city,
    origin_area,
    destination_rank,
    destination_area,
    rides,
    ROUND(share_of_origin_pct, 2) AS share_of_origin_pct,
    ROUND(avg_straight_km::numeric, 2) AS avg_straight_km,
    ROUND(avg_duration_minutes, 1) AS avg_duration_minutes,
    ROUND(avg_fare, 0) AS avg_fare,
    ROUND(fare_per_km, 0) AS fare_per_km
FROM routes
WHERE destination_rank <= 3
ORDER BY city, origin_area, destination_rank, destination_area;
