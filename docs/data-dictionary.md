# Data Dictionary

This is our contract for what each table looks like, like an API contract but for the database. DDL, the data generator and queries should all follow it. If you change a column that someone else uses, agree on it with them first and update this file in the same PR.

## Shared rules

- IDs are `VARCHAR(10)`: a 3-letter prefix and 7 digits, like `PAY0000001`. The data generator assigns them, and they never change.
- Times are `TIMESTAMP` in UTC.
- Money is `NUMERIC(12,2)` in rupiah.
- Fixed value lists (statuses, methods) are uppercase, like `E_WALLET`.
- **Required: yes** means the column can never be empty (`NOT NULL`).

## service_areas

An area where the platform operates. Owner: Nabil.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `service_area_id` | `VARCHAR(10)` | yes | Primary key | `SAR0000001` |
| `area_name` | `VARCHAR(100)` | yes | Unique together with `city` | `Menteng` |
| `city` | `VARCHAR(100)` | yes | | `Jakarta` |
| `area_status` | `VARCHAR(20)` | yes | `ACTIVE` or `INACTIVE`. Default `ACTIVE` | `ACTIVE` |

Every service area must have at least one location.

## locations

A point on the map with an address. Owner: Nabil.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `location_id` | `VARCHAR(10)` | yes | Primary key | `LOC0000001` |
| `latitude` | `NUMERIC(9,6)` | yes | From -90 to 90 | `-6.195000` |
| `longitude` | `NUMERIC(9,6)` | yes | From -180 to 180 | `106.830000` |
| `address` | `VARCHAR(255)` | yes | | `Jl. Teuku Umar No. 1` |
| `service_area_id` | `VARCHAR(10)` | yes | Must exist in `service_areas` | `SAR0000001` |

You can't delete an area's last location or move it to another area.

## merchant_outlets

A merchant's physical outlet. Owner: Nabil.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `merchant_outlet_id` | `VARCHAR(10)` | yes | Primary key | `OUT0000001` |
| `outlet_name` | `VARCHAR(100)` | yes | | `Warung Bu Sri` |
| `outlet_status` | `VARCHAR(20)` | yes | `OPEN`, `CLOSED` or `INACTIVE`. Default `OPEN` | `OPEN` |
| `location_id` | `VARCHAR(10)` | yes | Must exist in `locations`. Several outlets can share one location | `LOC0000001` |

## payments

The payment for one service order. Owner: Nabil.

| Column | Type | Required | Rules | Example |
| --- | --- | --- | --- | --- |
| `payment_id` | `VARCHAR(10)` | yes | Primary key | `PAY0000001` |
| `payment_method` | `VARCHAR(20)` | yes | `CASH`, `E_WALLET`, `CARD` or `PAYLATER` | `E_WALLET` |
| `payment_status` | `VARCHAR(20)` | yes | `PENDING`, `PAID`, `FAILED` or `REFUNDED`. Default `PENDING` | `PAID` |
| `amount` | `NUMERIC(12,2)` | yes | More than 0 | `45000.00` |
| `paid_at` | `TIMESTAMP` | when `PAID` or `REFUNDED` | Must be empty when `PENDING` or `FAILED` | `2026-10-29 03:15:00` |
| `order_id` | `VARCHAR(10)` | yes | Must exist in `service_orders`. One payment per order | `ORD0000001` |

A payment's status can only change like this: `PENDING` → `PAID` or `FAILED`, `FAILED` → `PENDING` (retry), and `PAID` → `REFUNDED`. A refund keeps the original `paid_at`.

## Not written yet

Owners, please add these using the same table format.

- **Dama:** `customers`, `service_orders`, `food_orders`, `mobility_orders`, `delivery_orders`. `service_orders.order_id` must be `VARCHAR(10)`, because `payments.order_id` points to it.
- **Ishak:** `trips`, `driver_assignments`, `driver_partners`, `vehicles`.
