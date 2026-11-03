# Data Dictionary

This is our contract for what each table looks like, like an API contract but for the database. DDL, the data generator and queries should all follow it. If you change a column that someone else uses, agree on it with them first and update this file in the same PR.

## Shared rules

- IDs are `VARCHAR(10)`: a 3-letter prefix and 7 digits, like `PAY0000001`. The data generator assigns them, and they never change.
- Times are `TIMESTAMPTZ` in UTC+0.
- Money is `NUMERIC(12,2)` in rupiah.
- Fixed value lists (statuses, methods) are PostgreSQL `ENUM` types named after their column, with uppercase values like `E_WALLET`.
- **Required: yes** means the column can never be empty (`NOT NULL`).

## service_areas

An area where the platform operates. Owner: Nabil.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `service_area_id` | `VARCHAR(10)` | yes | Primary key | `SAR0000001` |
| `area_name` | `VARCHAR(100)` | yes | Unique together with `city` | `Menteng` |
| `city` | `VARCHAR(100)` | yes | | `Jakarta` |
| `area_status` | `area_status` (enum) | yes | `ACTIVE` or `INACTIVE`. Default `ACTIVE` | `ACTIVE` |

## locations

A point on the map with an address. Owner: Nabil.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `location_id` | `VARCHAR(10)` | yes | Primary key | `LOC0000001` |
| `latitude` | `NUMERIC(9,6)` | yes | From -90 to 90 | `-6.195000` |
| `longitude` | `NUMERIC(9,6)` | yes | From -180 to 180 | `106.830000` |
| `address` | `VARCHAR(255)` | yes | | `Jl. Teuku Umar No. 1` |
| `service_area_id` | `VARCHAR(10)` | yes | Must exist in `service_areas` | `SAR0000001` |

## merchant_outlets

A merchant's physical outlet. Owner: Nabil.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `merchant_outlet_id` | `VARCHAR(10)` | yes | Primary key | `OUT0000001` |
| `outlet_name` | `VARCHAR(100)` | yes | | `Warung Bu Sri` |
| `outlet_status` | `outlet_status` (enum) | yes | `OPEN`, `CLOSED` or `INACTIVE`. Default `OPEN` | `OPEN` |
| `location_id` | `VARCHAR(10)` | yes | Must exist in `locations`. Several outlets can share one location | `LOC0000001` |

## payments

The payment for one service order. Owner: Nabil.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `payment_id` | `VARCHAR(10)` | yes | Primary key | `PAY0000001` |
| `payment_method` | `payment_method` (enum) | yes | `CASH`, `E_WALLET`, `CARD` or `PAYLATER` | `E_WALLET` |
| `payment_status` | `payment_status` (enum) | yes | `PENDING`, `PAID`, `FAILED` or `REFUNDED`. Default `PENDING` | `PAID` |
| `amount` | `NUMERIC(12,2)` | yes | More than 0 | `45000.00` |
| `paid_at` | `TIMESTAMPTZ` | when `PAID` or `REFUNDED` | Must be empty when `PENDING` or `FAILED` | `2026-10-29 03:15:00+00` |
| `order_id` | `VARCHAR(10)` | yes | Must exist in `service_orders`. One payment per order | `ORD0000001` |

What each `payment_status` means:

| Status | Meaning |
| --- | --- |
| `PENDING` | The payment isn't finished yet. A cash payment stays `PENDING` until the trip is completed. |
| `PAID` | The payment has been received, and `paid_at` records when. |
| `FAILED` | The payment failed, or a pending cash payment failed because the order was cancelled. |
| `REFUNDED` | A `PAID` payment was returned. `paid_at` keeps the time of the original payment. |

A payment's status can only change like this: `PENDING` → `PAID` or `FAILED`, `FAILED` → `PENDING` (retry), and `PAID` → `REFUNDED`. A refund keeps the original `paid_at`.

## customers

Representing user entities who can create service orders. Owner: Dama.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `customer_id` | `VARCHAR(10)` | yes | Primary key | `CUS0000001` |
| `full_name` | `VARCHAR(100)` | yes | | `Nama Lengkap` |
| `phone_number` | `VARCHAR(16)` | no | must be valid phone number | `+621234123412345` |
| `email` | `VARCHAR(100)` | no | must be valid email | `john.doe@example.com` |

name is stored as full name, not split into first and last name following what we actually see in Grab's app.

phone number and email validation will use PostgreSQL CHECK statements with REGEX.

## service_orders

Representing a commission to fulfill a request made by a user (customer). Owner: Dama.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `order_id` | `VARCHAR(10)` | yes | Primary key | `ORD0000001` |
| `created_at` | `TIMESTAMPTZ` | yes | | `2026-10-30 19:37:00+00` |
| `order_status` | order_status (ENUM) | yes | either: `PENDING`, `CONFIRMED`, `IN_PROGRESS`, `COMPLETED`, `CANCELLED`, or `FAILED` | `COMPLETED` |
| `total_amount` | `NUMERIC(12,2)` | yes | must be >= 0 | `45000.00` |
| `customer_id` | `VARCHAR(10)` | yes | foreign key reference to customers table | `CUS0000001` |

What each `order_status` means:

| Status | Meaning |
| --- | --- |
| `PENDING` | The order has been placed but isn't confirmed yet, or it is waiting for the result of a non-cash payment. |
| `CONFIRMED` | The order and its payment method are confirmed. The trip may still be looking for a driver (`SEARCHING`) or already have one (`ALLOCATED`). |
| `IN_PROGRESS` | The trip has started and the service is under way. |
| `COMPLETED` | The trip and the service are finished. |
| `CANCELLED` | The order was cancelled after it was confirmed, before or during the trip. |
| `FAILED` | The order failed, for example because a non-cash payment failed. |

order_status have valid transition constraints that will need to be upheld. The state transitions are:
- pending: can go to confirmed or failed
- confirmed: can go to in_progress or cancelled
- in_progress: can go to completed or cancelled
- cancelled: can only go to failed
- failed: can't go anywhere

### Specialization constraint

Every service order must belong to exactly one of `food_orders`,
`mobility_orders`, or `delivery_orders`. The specialization is total
and disjoint: an order cannot belong to none or to more than one
subtype. Foreign keys alone do not enforce this constraint.

## food_orders

A specialization subtable from service_orders that contain info specifically for service_orders related to food. Owner: Dama.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `order_id` | `VARCHAR(10)` | yes | Primary key, Foreign Key to service_orders | `ORD0000001` |
| `preparation_status` | preparation_status (ENUM) | yes | either: `PENDING`, `PREPARING`, or `READY` | `PREPARING` |
| `delivery_notes` | `VARCHAR(100)` | no | - | `make the food delicious` |
| `merchant_outlet_id` | `VARCHAR(10)` | yes | foreign key reference to merchant_outlet | `OUT0000001` |

preparation_status differs from order_status. preparation_status focuses more on the status of food prep by the merchant.
Valid state transitions for preparation_status, are only:
pending → preparing → ready

## delivery_orders

A specialization subtable from service_orders that contain info specifically for delivery_orders related to packages. Owner: Dama.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `order_id` | `VARCHAR(10)` | yes | Primary key, Foreign Key to service_orders | `ORD0000001` |
| `package_description` | `VARCHAR(100)` | yes | - | `this package contains clothes` |
| `package_weight` | `NUMERIC(5,2)` | yes | - | `100.23` |
| `recipient_name` | `VARCHAR(100)` | yes | - | `Myself` |
| `recipient_contact` | `VARCHAR(16)` | yes | must be valid phone number | `+621234123412345` |

pickup and dropoff points will be handled in different table.
package weights are in kilograms.
why no sender info? already stored via customer_id FK in parent (service_orders)

## mobility_orders

A specialization subtable from service_orders that contain info specifically for mobility_orders related to ride hailing. Owner: Dama.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `order_id` | `VARCHAR(10)` | yes | Primary key, Foreign Key to service_orders | `ORD0000001` |
| `ride_type` | ride_type (ENUM) | yes | either: `GrabCar`, `GrabCarPlus`, `GrabBike`, `GrabElectric`, `GrabTaxi` | `GrabCarPlus` |
| `passenger_count` | `INTEGER` | yes | must at least be 1 | `1` |
| `pickup_notes` | `VARCHAR(100)` | no | - | `I'll be waiting by the gate` |

pickup and dropoff points will be handled in different table.

## Not written yet

Owners, please add these using the same table format.

## driver_partners

Representing driver partner entities who execute trips. Owner: Ishak.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `driver_partner_id` | `VARCHAR(10)` | yes | Primary key | `DRV0000001` |
| `full_name` | `VARCHAR(100)` | yes | | `Budi Santoso` |
| `phone_number` | `VARCHAR(16)` | yes | Unique, must be valid phone number | `+6281234567890` |
| `email` | `VARCHAR(100)` | yes | Unique, must be valid email | `budi.driver@example.com` |
| `driver_status` | `driver_status` (enum) | yes | `ACTIVE`, `INACTIVE`, or `SUSPENDED`. Default `ACTIVE` | `ACTIVE` |

Phone number and email validation use PostgreSQL `CHECK` statements with regex.

## vehicles

A vehicle registered by a driver partner to fulfill trips. Owner: Ishak.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `vehicle_id` | `VARCHAR(10)` | yes | Primary key | `VEH0000001` |
| `plate_number` | `VARCHAR(15)` | yes | Unique | `B 1234 ABC` |
| `vehicle_type` | `VARCHAR(30)` | yes | Type/Model of vehicle | `Motorcycle` |
| `vehicle_status` | `vehicle_status` (enum) | yes | `ACTIVE`, `INACTIVE`, or `UNDER_MAINTENANCE`. Default `ACTIVE` | `ACTIVE` |
| `driver_partner_id` | `VARCHAR(10)` | yes | Foreign key reference to `driver_partners` | `DRV0000001` |

Represents the internal aggregation (`registers`) with `driver_partners`.

## trips

The execution of a service order. Owner: Ishak.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `trip_id` | `VARCHAR(10)` | yes | Primary key | `TRP0000001` |
| `started_at` | `TIMESTAMPTZ` | no | | `2026-10-30 19:40:00+00` |
| `completed_at` | `TIMESTAMPTZ` | when `COMPLETED` | Must be present when `trip_status` is `COMPLETED` | `2026-10-30 20:05:00+00` |
| `trip_status` | `trip_status` (enum) | yes | `SEARCHING`, `ALLOCATED`, `IN_PROGRESS`, `COMPLETED`, or `CANCELLED`. Default `SEARCHING` | `COMPLETED` |
| `order_id` | `VARCHAR(10)` | yes | Foreign key reference to `service_orders` | `ORD0000001` |
| `start_location_id` | `VARCHAR(10)` | yes | Foreign key reference to `locations` (pickup/origin) | `LOC0000001` |
| `end_location_id` | `VARCHAR(10)` | yes | Foreign key reference to `locations` (destination) | `LOC0000002` |

Valid state transitions for `trip_status`:
- `SEARCHING`: can go to `ALLOCATED` or `CANCELLED`
- `ALLOCATED`: can go to `IN_PROGRESS` or `CANCELLED`
- `IN_PROGRESS`: can go to `COMPLETED` or `CANCELLED`
- `COMPLETED` / `CANCELLED`: final states

## driver_assignments

Assignment attempts connecting trips to vehicles and driver partners. Owner: Ishak.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `assignment_id` | `VARCHAR(10)` | yes | Primary key | `ASN0000001` |
| `assigned_at` | `TIMESTAMPTZ` | yes | Default `CURRENT_TIMESTAMP` | `2026-10-30 19:38:00+00` |
| `assignment_status` | `assignment_status` (enum) | yes | `PENDING`, `ACCEPTED`, `REJECTED`, `EXPIRED`, or `CANCELLED`. Default `PENDING` | `ACCEPTED` |
| `responded_at` | `TIMESTAMPTZ` | no | Timestamp when driver responds | `2026-10-30 19:39:00+00` |
| `ended_at` | `TIMESTAMPTZ` | no | Timestamp when assignment ends | `2026-10-30 20:05:00+00` |
| `end_reason` | `VARCHAR(100)` | no | Reason if rejected/cancelled/expired | `Driver unreachable` |
| `trip_id` | `VARCHAR(10)` | yes | Foreign key reference to `trips` | `TRP0000001` |
| `vehicle_id` | `VARCHAR(10)` | yes | Foreign key reference to `vehicles` | `VEH0000001` |

Represents the `fulfills` relationship set connecting `trips` with the `vehicles` + `driver_partners` aggregation.