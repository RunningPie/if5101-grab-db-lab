-- ============================================================================
-- MILESTONE 4: ANALYTICAL READ QUERIES (OLAP)
-- Domain Focus: trips, driver_assignments, vehicles, driver_partners
-- ============================================================================

-- ----------------------------------------------------------------------------
-- R1: Driver Performance & Acceptance Rate Analysis
-- Menghitung rasio penerimaan tawaran trip (Acceptance Rate) per driver partner.
-- ----------------------------------------------------------------------------
SELECT 
    dp.driver_partner_id,
    dp.full_name,
    COUNT(da.assignment_id) AS total_assignments_received,
    COUNT(CASE WHEN da.assignment_status = 'ACCEPTED' THEN 1 END) AS total_accepted,
    COUNT(CASE WHEN da.assignment_status = 'REJECTED' THEN 1 END) AS total_rejected,
    COUNT(CASE WHEN da.assignment_status = 'EXPIRED' THEN 1 END) AS total_expired,
    ROUND(
        (COUNT(CASE WHEN da.assignment_status = 'ACCEPTED' THEN 1 END)::NUMERIC / 
        NULLIF(COUNT(da.assignment_id), 0)) * 100, 2
    ) AS acceptance_rate_percentage
FROM driver_partners dp
JOIN vehicles v ON dp.driver_partner_id = v.driver_partner_id
JOIN driver_assignments da ON v.vehicle_id = da.vehicle_id
GROUP BY dp.driver_partner_id, dp.full_name
HAVING COUNT(da.assignment_id) >= 5
ORDER BY acceptance_rate_percentage DESC, total_accepted DESC;

-- ----------------------------------------------------------------------------
-- R2: Top 10 Drivers by Cumulative Trip Duration & Completed Trips
-- Menampilkan 10 driver paling produktif berdasarkan akumulasi durasi perjalanan.
-- ----------------------------------------------------------------------------
SELECT 
    dp.driver_partner_id,
    dp.full_name,
    v.plate_number,
    v.vehicle_type,
    COUNT(t.trip_id) AS total_completed_trips,
    ROUND(SUM(EXTRACT(EPOCH FROM (t.completed_at - t.started_at)) / 60)::NUMERIC, 2) AS total_duration_minutes,
    ROUND(AVG(EXTRACT(EPOCH FROM (t.completed_at - t.started_at)) / 60)::NUMERIC, 2) AS avg_duration_per_trip_minutes
FROM driver_partners dp
JOIN vehicles v ON dp.driver_partner_id = v.driver_partner_id
JOIN driver_assignments da ON v.vehicle_id = da.vehicle_id
JOIN trips t ON da.trip_id = t.trip_id
WHERE da.assignment_status = 'ACCEPTED'
  AND t.trip_status = 'COMPLETED'
GROUP BY dp.driver_partner_id, dp.full_name, v.plate_number, v.vehicle_type
ORDER BY total_duration_minutes DESC
LIMIT 10;

-- ----------------------------------------------------------------------------
-- R3: Vehicle Type Utilization across Hourly Peak Times
-- Menganalisis tingkat penggunaan armada berdasarkan tipe kendaraan per jam transaksi.
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- R4: Re-assignment History Analysis (High Allocation Churn Trips)
-- Mencari trip yang memerlukan lebih dari 2 kali pengalokasian driver sebelum dipenuhi.
-- ----------------------------------------------------------------------------
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
ORDER BY tac.total_attempts DESC, t.started_at DESC;

-- ----------------------------------------------------------------------------
-- R5: Service Area Dispatch Efficiency Metric
-- Menghitung durasi rata-rata waktu dari pencarian hingga trip dimulai per Service Area.
-- ----------------------------------------------------------------------------
SELECT 
    sa.service_area_id,
    sa.area_name,
    sa.city,
    COUNT(t.trip_id) AS total_trips,
    ROUND(
        AVG(EXTRACT(EPOCH FROM (t.started_at - da.assigned_at)))::NUMERIC, 2
    ) AS avg_dispatch_to_start_seconds
FROM service_areas sa
JOIN locations l ON sa.service_area_id = l.service_area_id
JOIN trips t ON l.location_id = t.start_location_id
JOIN driver_assignments da ON t.trip_id = da.trip_id
WHERE da.assignment_status = 'ACCEPTED'
  AND t.started_at IS NOT NULL
GROUP BY sa.service_area_id, sa.area_name, sa.city
ORDER BY avg_dispatch_to_start_seconds ASC;