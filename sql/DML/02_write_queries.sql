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