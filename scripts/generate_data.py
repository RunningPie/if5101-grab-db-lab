"""
Every order is simulated from creation to its outcome and then observed at the
snapshot time, the end of the configured period. Orders still running at that
moment get in-flight order, payment, trip and assignment states that agree.
"""

from __future__ import annotations

import argparse
from contextlib import ExitStack
import csv
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, time
import heapq
from itertools import accumulate
import math
from pathlib import Path
import random
import re
import shutil
import string
import tempfile
from typing import Any, BinaryIO, Iterator, NamedTuple

from faker import Faker
import yaml

ROOT = Path(__file__).resolve().parent.parent
CONFIG_FILE = ROOT / 'config' / 'dataset_profile.yaml'
PROFILES = ('small', 'medium', 'large')

# Columns of each table, in an order that satisfies the foreign keys when loaded.
TABLES = {
    'service_areas': ('service_area_id', 'area_name', 'city', 'area_status'),
    'locations': ('location_id', 'latitude', 'longitude', 'address', 'service_area_id'),
    'merchant_outlets': ('merchant_outlet_id', 'outlet_name', 'outlet_status', 'location_id'),
    'customers': ('customer_id', 'full_name', 'phone_number', 'email'),
    'driver_partners': ('driver_partner_id', 'full_name', 'phone_number', 'email', 'driver_status'),
    'vehicles': ('vehicle_id', 'plate_number', 'vehicle_type', 'vehicle_status', 'driver_partner_id'),
    'service_orders': ('order_id', 'created_at', 'order_status', 'total_amount', 'customer_id'),
    'food_orders': ('order_id', 'preparation_status', 'delivery_notes', 'merchant_outlet_id'),
    'delivery_orders': ('order_id', 'package_description', 'package_weight', 'recipient_name',
                        'recipient_contact'),
    'mobility_orders': ('order_id', 'ride_type', 'passenger_count', 'pickup_notes'),
    'payments': ('payment_id', 'payment_method', 'payment_status', 'amount', 'paid_at', 'order_id'),
    'trips': ('trip_id', 'started_at', 'completed_at', 'trip_status', 'order_id',
              'start_location_id', 'end_location_id'),
    'driver_assignments': ('assignment_id', 'assigned_at', 'assignment_status', 'responded_at',
                           'ended_at', 'end_reason', 'trip_id', 'vehicle_id'),
}

# (city, area, latitude, longitude, status) of each service area's centre.
SERVICE_AREAS = (
    ('Jakarta', 'Menteng', -6.1950, 106.8320, 'ACTIVE'),
    ('Jakarta', 'Tanah Abang', -6.2000, 106.8130, 'ACTIVE'),
    ('Jakarta', 'Kebayoran Baru', -6.2430, 106.7990, 'ACTIVE'),
    ('Jakarta', 'Kelapa Gading', -6.1580, 106.9080, 'ACTIVE'),
    ('Jakarta', 'Cengkareng', -6.1500, 106.7350, 'ACTIVE'),
    ('Jakarta', 'Pasar Minggu', -6.2850, 106.8430, 'ACTIVE'),
    ('Jakarta', 'Tebet', -6.2260, 106.8530, 'ACTIVE'),
    ('Jakarta', 'Cilandak', -6.2900, 106.8000, 'ACTIVE'),
    ('Bandung', 'Coblong', -6.8870, 107.6130, 'ACTIVE'),
    ('Bandung', 'Sukajadi', -6.8850, 107.5960, 'ACTIVE'),
    ('Bandung', 'Lengkong', -6.9300, 107.6250, 'ACTIVE'),
    ('Bandung', 'Buahbatu', -6.9480, 107.6390, 'ACTIVE'),
    ('Surabaya', 'Gubeng', -7.2750, 112.7500, 'ACTIVE'),
    ('Surabaya', 'Tegalsari', -7.2650, 112.7370, 'ACTIVE'),
    ('Surabaya', 'Wonokromo', -7.3000, 112.7350, 'ACTIVE'),
    ('Surabaya', 'Sukolilo', -7.2900, 112.7900, 'ACTIVE'),
    ('Yogyakarta', 'Gondokusuman', -7.7830, 110.3850, 'ACTIVE'),
    ('Yogyakarta', 'Mergangsan', -7.8100, 110.3720, 'ACTIVE'),
    ('Yogyakarta', 'Kotagede', -7.8260, 110.4000, 'ACTIVE'),
    ('Medan', 'Medan Baru', 3.5750, 98.6600, 'ACTIVE'),
    ('Medan', 'Medan Petisah', 3.5900, 98.6650, 'INACTIVE'),
    ('Denpasar', 'Denpasar Selatan', -8.7000, 115.2200, 'ACTIVE'),
    ('Denpasar', 'Denpasar Utara', -8.6300, 115.2100, 'INACTIVE'),
)
AREA_RADIUS = 0.015  # degrees around an area's centre, roughly 1.7 km
ROAD_FACTOR = 1.3  # road distance relative to the straight line
PLATE_REGIONS = ('B', 'D', 'L', 'AB', 'BK', 'DK', 'F')

# Extra orders placed in the hour before the snapshot, so some are still running.
LAST_HOUR_SHARE = 0.02
# Orders from the last day only use active areas, open outlets and active drivers.
CURRENT_WINDOW = 24 * 3600

OUTLET_STATUSES = {'OPEN': 0.80, 'CLOSED': 0.15, 'INACTIVE': 0.05}
DRIVER_STATUSES = {'ACTIVE': 0.85, 'INACTIVE': 0.10, 'SUSPENDED': 0.05}
VEHICLE_STATUSES = {'ACTIVE': 0.88, 'INACTIVE': 0.08, 'UNDER_MAINTENANCE': 0.04}
VEHICLE_TYPES = {'Motorcycle': 0.55, 'Electric Motorcycle': 0.05, 'Car': 0.25,
                 'Premium Car': 0.07, 'Electric Car': 0.04, 'Taxi': 0.04}
PAYMENT_METHODS = {'E_WALLET': 0.45, 'CASH': 0.30, 'PAYLATER': 0.15, 'CARD': 0.10}
RIDE_TYPES = {'GrabBike': 0.45, 'GrabCar': 0.33, 'GrabCarPlus': 0.10, 'GrabElectric': 0.06,
              'GrabTaxi': 0.06}
PASSENGERS = {1: 0.60, 2: 0.25, 3: 0.10, 4: 0.05}
# Minimum fare and rate per km of each ride type, in rupiah.
FARES = {'GrabBike': (10_000, 2_500), 'GrabElectric': (22_000, 4_000), 'GrabCar': (20_000, 4_500),
         'GrabCarPlus': (28_000, 6_000), 'GrabTaxi': (15_000, 4_200)}

# Vehicle types that can serve each ride type, food order and parcel.
BIKES = ('Motorcycle', 'Electric Motorcycle')
SERVICE_VEHICLES = {'GrabBike': BIKES, 'GrabCar': ('Car',), 'GrabCarPlus': ('Premium Car',),
                    'GrabElectric': ('Electric Car',), 'GrabTaxi': ('Taxi',),
                    'food': BIKES, 'parcel': BIKES, 'bulky parcel': ('Car',)}
BULKY_PARCEL_KG = 10

# What happens to an order once its payment is confirmed.
OUTCOMES = {'COMPLETED': 0.885, 'NO_DRIVER': 0.03, 'CANCELLED_WHILE_SEARCHING': 0.03,
            'CANCELLED_BEFORE_PICKUP': 0.05, 'CANCELLED_DURING_TRIP': 0.005}
PAYMENT_FAILURE_RATE = 0.03  # non-cash payments only
REFUND_RATE = 0.015  # completed non-cash orders
MISSED_ATTEMPTS = {0: 0.60, 1: 0.25, 2: 0.10, 3: 0.05}  # before a driver accepts
ASSIGNMENT_TIMEOUT = 30  # seconds a driver has to answer

OUTLET_KINDS = ('Warung', 'Rumah Makan', 'Kedai Kopi', 'Bakso', 'Sate', 'Ayam Geprek', 'Mie Ayam',
                'Nasi Goreng', 'Martabak', 'Soto', 'Bakmi', 'Gudeg', 'Pempek', 'Seblak')
FOOD_NOTES = ('Sambal dipisah', 'Tidak pakai bawang', 'Pedas level 3', 'Tidak pakai sayur',
              'Kuah dipisah', 'Tolong bawa alat makan', 'Titip di satpam', 'Taruh di depan pagar')
PICKUP_NOTES = ('Saya tunggu di lobi', 'Di depan gerbang', 'Dekat minimarket', 'Di seberang halte',
                'Pintu keluar selatan', 'Pakai baju merah', 'Telepon kalau sudah sampai')
# Package description with its lightest and heaviest weight in kg.
PARCELS = (('Dokumen kantor', 0.1, 1.0), ('Pakaian', 0.5, 5.0), ('Makanan kering', 0.5, 5.0),
           ('Kue ulang tahun', 1.0, 3.0), ('Buku', 0.5, 8.0), ('Obat-obatan', 0.1, 2.0),
           ('Elektronik kecil', 0.3, 6.0), ('Sparepart motor', 1.0, 15.0),
           ('Peralatan dapur', 2.0, 20.0), ('Galon air mineral', 19.0, 20.0))
REJECT_REASONS = ('Driver rejected the request', 'Pickup too far', 'Vehicle issue')
CANCEL_REASONS = ('Cancelled by customer', 'Cancelled by driver')


class Place(NamedTuple):
    location_id: str
    latitude: float
    longitude: float
    city: str
    active: bool  # in an active service area


@dataclass
class Timeline:
    """Event times of one order in Unix seconds; None for events that never happen."""

    confirmed: float | None = None
    failed: float | None = None
    prep_start: float | None = None
    ready: float | None = None
    accepted: float | None = None
    started: float | None = None
    completed: float | None = None
    cancelled: float | None = None
    cancel_reason: str | None = None
    # (vehicle_id, assigned_at, outcome, responded_at, ended_at, end_reason) per driver request.
    attempts: list[tuple] = field(default_factory=list)


def make_id(prefix: str, number: int) -> str:
    return f'{prefix}{number:07d}'


def stamp(seconds: float | None) -> str | None:
    """Format a Unix time as a UTC timestamp, to the second."""
    return None if seconds is None else datetime.fromtimestamp(round(seconds), UTC).isoformat(' ')


def utc_seconds(day: date) -> float:
    return datetime.combine(day, time(), UTC).timestamp()


def weighted(rng: random.Random, options: dict) -> Any:
    return rng.choices(tuple(options), tuple(options.values()))[0]


def spread(rng: random.Random, start: float, end: float, count: int) -> Iterator[float]:
    """Yield count increasing times that cover start to end evenly."""
    step = (end - start) / max(count, 1)
    for index in range(count):
        yield start + (index + rng.random()) * step


def road_km(a: Place, b: Place) -> float:
    lat_a, lat_b = math.radians(a.latitude), math.radians(b.latitude)
    h = (math.sin((lat_b - lat_a) / 2) ** 2 + math.cos(lat_a) * math.cos(lat_b)
         * math.sin(math.radians(b.longitude - a.longitude) / 2) ** 2)
    return max(ROAD_FACTOR * 12742 * math.asin(math.sqrt(h)), 0.5)


def by_city(places: list[Place]) -> dict[str, list[Place]]:
    groups: dict[str, list[Place]] = {}
    for place in places:
        groups.setdefault(place.city, []).append(place)
    return groups


class Generator:
    """Writes the rows of every table, keeping in memory only what later rows refer to."""

    def __init__(self, profile: str, writers: dict[str, Any]) -> None:
        config = yaml.safe_load(CONFIG_FILE.read_text(encoding='utf-8'))
        self.sizes = config['profiles'][profile]
        missing = {'customers', 'service_orders', 'driver_partners', 'locations',
                   'merchant_outlets'} - set(self.sizes)
        if missing:
            raise ValueError(f"Profile '{profile}' is missing: {', '.join(sorted(missing))}")
        self.order_kinds = config['order_distribution']
        self.start = utc_seconds(config['period']['start'])
        self.now = utc_seconds(config['period']['end'])
        self.rng = random.Random(config['seed'])
        self.faker = Faker('id_ID')
        self.faker.seed_instance(config['seed'])
        self.writers = writers
        self.counts = dict.fromkeys(TABLES, 0)
        self.phones: set[str] = set()
        self.plates: set[str] = set()

    def run(self) -> dict[str, int]:
        self.add_places()
        self.add_outlets()
        self.add_customers()
        self.add_fleet()
        for number, created in enumerate(self.order_times(), start=1):
            self.add_order(number, created)
        return self.counts

    def write(self, table: str, row: tuple) -> None:
        self.writers[table].writerow(row)
        self.counts[table] += 1

    def seen(self, moment: float | None) -> bool:
        """Whether an event has happened by the snapshot time."""
        return moment is not None and moment <= self.now

    def person(self, number: int) -> tuple[str, str]:
        """Return a full name and an email address that is unique for this number."""
        first, last = self.faker.first_name(), self.faker.last_name()
        local = '.'.join(re.sub('[^a-z0-9]', '', part.lower()) for part in (first, last))
        return f'{first} {last}', f'{local}{number}@{self.faker.free_email_domain()}'

    def full_name(self) -> str:
        return f'{self.faker.first_name()} {self.faker.last_name()}'

    def mobile_number(self) -> str:
        # +628 and 9 to 11 more digits, the shape the phone CHECK constraints accept.
        return f'+628{self.rng.randrange(10 ** 8, 10 ** 11)}'

    def unique_mobile_number(self) -> str:
        while (phone := self.mobile_number()) in self.phones:
            pass
        self.phones.add(phone)
        return phone

    def plate_number(self) -> str:
        rng = self.rng
        while True:
            letters = ''.join(rng.choices(string.ascii_uppercase, k=rng.randint(1, 3)))
            plate = f'{rng.choice(PLATE_REGIONS)} {rng.randint(1, 9999)} {letters}'
            if plate not in self.plates:
                self.plates.add(plate)
                return plate

    def add_places(self) -> None:
        areas = []
        for number, (city, name, latitude, longitude, status) in enumerate(SERVICE_AREAS, start=1):
            area_id = make_id('SAR', number)
            self.write('service_areas', (area_id, name, city, status))
            areas.append((area_id, name, city, latitude, longitude, status == 'ACTIVE'))
        self.places: list[Place] = []
        for number in range(1, self.sizes['locations'] + 1):
            area_id, name, city, latitude, longitude, active = self.rng.choice(areas)
            place = Place(make_id('LOC', number),
                          round(latitude + self.rng.uniform(-AREA_RADIUS, AREA_RADIUS), 6),
                          round(longitude + self.rng.uniform(-AREA_RADIUS, AREA_RADIUS), 6),
                          city, active)
            address = f'{self.faker.street_address()}, {name}, {city}'
            self.write('locations', (place.location_id, f'{place.latitude:.6f}',
                                     f'{place.longitude:.6f}', address, area_id))
            self.places.append(place)
        # Pools are keyed by whether an order is current (placed in the last day).
        self.place_pool = {False: self.places,
                           True: [place for place in self.places if place.active] or self.places}
        self.city_pool = {current: by_city(pool) for current, pool in self.place_pool.items()}

    def add_outlets(self) -> None:
        outlets, open_outlets = [], []
        for number in range(1, self.sizes['merchant_outlets'] + 1):
            outlet_id, place = make_id('OUT', number), self.rng.choice(self.places)
            owner = self.rng.choice(('Bu', 'Pak', None))
            if owner == 'Bu':
                owner = f'Bu {self.faker.first_name_female()}'
            elif owner == 'Pak':
                owner = f'Pak {self.faker.first_name_male()}'
            else:
                owner = self.faker.first_name()
            # Outlets in an area the platform no longer serves are not listed.
            status = weighted(self.rng, OUTLET_STATUSES) if place.active else 'INACTIVE'
            self.write('merchant_outlets', (outlet_id, f'{self.rng.choice(OUTLET_KINDS)} {owner}',
                                            status, place.location_id))
            outlets.append((outlet_id, place))
            if status == 'OPEN' and place.active:
                open_outlets.append((outlet_id, place))
        self.outlet_pool = {False: outlets, True: open_outlets or outlets}

    def add_customers(self) -> None:
        count = self.sizes['customers']
        self.customer_ids = [make_id('CUS', number) for number in range(1, count + 1)]
        for number, customer_id in enumerate(self.customer_ids, start=1):
            full_name, email = self.person(number)
            phone = self.unique_mobile_number() if self.rng.random() < 0.95 else None
            self.write('customers', (customer_id, full_name, phone,
                                     email if self.rng.random() < 0.75 else None))
        # Some customers order far more often than others.
        self.customer_weights = list(accumulate(self.rng.lognormvariate(0, 1) for _ in range(count)))
        # When each customer's latest ride ends, so nobody is in two rides at once.
        self.riding_until = [0.0] * count

    def add_fleet(self) -> None:
        vehicles = []  # (vehicle_id, driver index, vehicle_type, available now)
        count = self.sizes['driver_partners']
        # When each driver's latest trip ends, so nobody drives two trips at once.
        self.busy_until = [0.0] * count
        for number in range(1, count + 1):
            driver_id = make_id('DRV', number)
            full_name, email = self.person(number)
            driver_status = weighted(self.rng, DRIVER_STATUSES)
            self.write('driver_partners', (driver_id, full_name, self.unique_mobile_number(), email,
                                           driver_status))
            for _ in range(2 if self.rng.random() < 0.1 else 1):
                vehicle_id = make_id('VEH', len(vehicles) + 1)
                vehicle_type = weighted(self.rng, VEHICLE_TYPES)
                vehicle_status = weighted(self.rng, VEHICLE_STATUSES)
                self.write('vehicles', (vehicle_id, self.plate_number(), vehicle_type, vehicle_status,
                                        driver_id))
                vehicles.append((vehicle_id, number - 1, vehicle_type,
                                 driver_status == 'ACTIVE' and vehicle_status == 'ACTIVE'))
        every_vehicle = [(vehicle_id, driver) for vehicle_id, driver, _, _ in vehicles]
        self.vehicle_pool = {}
        for service, types in SERVICE_VEHICLES.items():
            for current in (False, True):
                matching = [(vehicle_id, driver) for vehicle_id, driver, vehicle_type, available in vehicles
                            if vehicle_type in types and (available or not current)]
                self.vehicle_pool[current, service] = matching or every_vehicle

    def order_times(self) -> Iterator[float]:
        total = self.sizes['service_orders']
        last_hour = round(total * LAST_HOUR_SHARE)
        return heapq.merge(spread(self.rng, self.start, self.now, total - last_hour),
                           spread(self.rng, self.now - 3600, self.now, last_hour))

    def destination(self, origin: Place, current: bool) -> Place:
        """Pick another location in the origin's city."""
        candidates = self.city_pool[current].get(origin.city) or self.city_pool[False][origin.city]
        while (place := self.rng.choice(candidates)) is origin and len(candidates) > 1:
            pass
        return place

    def pick_customer(self, riding_from: float | None) -> int:
        """Pick a customer index weighted by activity; for a ride, one who is not riding then."""
        for _ in range(100):
            customer = self.rng.choices(range(len(self.customer_ids)),
                                        cum_weights=self.customer_weights)[0]
            if riding_from is None or self.riding_until[customer] <= riding_from:
                return customer
        raise ValueError('The profile has too few customers for its number of rides')

    def free_vehicle(self, vehicles: list[tuple[str, int]], at: float,
                     asked: set[int]) -> tuple[str, int] | None:
        """Pick a vehicle whose driver is free at `at` and was not asked for this trip yet."""
        for _ in range(50):
            vehicle_id, driver = self.rng.choice(vehicles)
            if driver not in asked and self.busy_until[driver] <= at:
                asked.add(driver)
                return vehicle_id, driver
        return None

    def simulate(self, created: float, kind: str, service: str, method: str, km: float,
                 vehicles: list[tuple[str, int]]) -> Timeline:
        """Run an order to its outcome, ignoring the snapshot time."""
        rng, timeline = self.rng, Timeline()
        decided = created + rng.uniform(5, 60)
        if method != 'CASH' and rng.random() < PAYMENT_FAILURE_RATE:
            timeline.failed = decided
            return timeline
        timeline.confirmed = decided
        outcome = weighted(rng, OUTCOMES)
        if kind == 'food':
            timeline.prep_start = decided + rng.uniform(30, 180)
            timeline.ready = timeline.prep_start + rng.uniform(480, 1200)

        at = decided + rng.uniform(2, 10)
        asked: set[int] = set()
        misses = rng.randint(2, 4) if outcome == 'NO_DRIVER' else weighted(rng, MISSED_ATTEMPTS)
        vehicle = self.free_vehicle(vehicles, at, asked)
        for _ in range(misses):
            if vehicle is None:
                break
            if rng.random() < 0.6:
                ended = at + rng.uniform(3, 20)
                timeline.attempts.append((vehicle[0], at, 'REJECTED', ended, ended,
                                          rng.choice(REJECT_REASONS)))
            else:
                ended = at + ASSIGNMENT_TIMEOUT
                timeline.attempts.append((vehicle[0], at, 'EXPIRED', None, ended, 'Driver unreachable'))
            at = ended + rng.uniform(1, 5)
            vehicle = self.free_vehicle(vehicles, at, asked)
        # The search fails when nobody accepts or no free driver is left to ask.
        if outcome == 'NO_DRIVER' or vehicle is None:
            timeline.cancelled = at
            return timeline
        vehicle_id, driver = vehicle
        if outcome == 'CANCELLED_WHILE_SEARCHING':
            timeline.cancelled = at + rng.uniform(3, ASSIGNMENT_TIMEOUT - 5)
            timeline.attempts.append((vehicle_id, at, 'CANCELLED', None, timeline.cancelled,
                                      'Cancelled by customer'))
            return timeline

        timeline.accepted = at + rng.uniform(3, 20)
        timeline.attempts.append((vehicle_id, at, 'ACCEPTED', timeline.accepted, None, None))
        pickup = timeline.accepted + rng.uniform(180, 720)
        if timeline.ready is not None:
            pickup = max(pickup, timeline.ready) + rng.uniform(60, 240)
        if outcome == 'CANCELLED_BEFORE_PICKUP':
            timeline.cancelled = rng.uniform(timeline.accepted, pickup)
            timeline.cancel_reason = rng.choice(CANCEL_REASONS)
        else:
            timeline.started = pickup
            speed = 25 if SERVICE_VEHICLES[service] == BIKES else 20  # km/h in city traffic
            duration = km / speed * 3600 + rng.uniform(60, 300)
            if outcome == 'CANCELLED_DURING_TRIP':
                timeline.cancelled = pickup + rng.uniform(0.1, 0.9) * duration
                timeline.cancel_reason = rng.choice(CANCEL_REASONS)
            else:
                timeline.completed = pickup + duration
        # The driver is engaged from accepting the request until the trip ends.
        self.busy_until[driver] = timeline.cancelled or timeline.completed
        return timeline

    def add_order(self, number: int, created: float) -> None:
        rng, seen = self.rng, self.seen
        current = created >= self.now - CURRENT_WINDOW
        order_id, payment_id = make_id('ORD', number), make_id('PAY', number)
        kind = weighted(rng, self.order_kinds)
        method = weighted(rng, PAYMENT_METHODS)
        customer = self.pick_customer(created if kind == 'mobility' else None)

        if kind == 'food':
            outlet_id, origin = rng.choice(self.outlet_pool[current])
        else:
            origin = rng.choice(self.place_pool[current])
        destination = self.destination(origin, current)
        km = road_km(origin, destination)
        if kind == 'mobility':
            service = weighted(rng, RIDE_TYPES)
            minimum, per_km = FARES[service]
            amount = max(minimum, per_km * km)
        elif kind == 'food':
            service = 'food'
            basket = min(max(rng.lognormvariate(math.log(45_000), 0.6), 10_000), 750_000)
            amount = basket + 5_000 + 2_000 * km
        else:
            description, lightest, heaviest = rng.choice(PARCELS)
            weight = round(rng.uniform(lightest, heaviest), 2)
            service = 'bulky parcel' if weight > BULKY_PARCEL_KG else 'parcel'
            amount = 10_000 + 2_500 * km + 1_500 * weight
        amount = f'{math.ceil(amount / 500) * 500:.2f}'
        timeline = self.simulate(created, kind, service, method, km,
                                 self.vehicle_pool[current, service])
        if kind == 'mobility':
            self.riding_until[customer] = timeline.completed or timeline.cancelled or timeline.failed

        if timeline.failed is not None:
            order_status = 'FAILED' if seen(timeline.failed) else 'PENDING'
        elif not seen(timeline.confirmed):
            order_status = 'PENDING'
        elif seen(timeline.cancelled):
            order_status = 'CANCELLED'
        elif seen(timeline.completed):
            order_status = 'COMPLETED'
        elif seen(timeline.started):
            order_status = 'IN_PROGRESS'
        else:
            order_status = 'CONFIRMED'
        self.write('service_orders', (order_id, stamp(created), order_status, amount,
                                      self.customer_ids[customer]))

        if kind == 'food':
            # Cooking stops when the order is cancelled.
            moment = min(self.now, timeline.cancelled or self.now)
            if timeline.prep_start is None or moment < timeline.prep_start:
                preparation = 'PENDING'
            elif moment < timeline.ready:
                preparation = 'PREPARING'
            else:
                preparation = 'READY'
            note = rng.choice(FOOD_NOTES) if rng.random() < 0.4 else None
            self.write('food_orders', (order_id, preparation, note, outlet_id))
        elif kind == 'mobility':
            passengers = 1 if SERVICE_VEHICLES[service] == BIKES else weighted(rng, PASSENGERS)
            note = rng.choice(PICKUP_NOTES) if rng.random() < 0.3 else None
            self.write('mobility_orders', (order_id, service, passengers, note))
        else:
            self.write('delivery_orders', (order_id, description, f'{weight:.2f}', self.full_name(),
                                           self.mobile_number()))

        # Non-cash orders are paid on confirmation, cash orders when the trip completes.
        paid_at = None
        if timeline.failed is not None:
            payment_status = 'FAILED' if seen(timeline.failed) else 'PENDING'
        elif method == 'CASH':
            if seen(timeline.completed):
                payment_status, paid_at = 'PAID', timeline.completed
            else:
                payment_status = 'FAILED' if seen(timeline.cancelled) else 'PENDING'
        elif seen(timeline.confirmed):
            paid_at = timeline.confirmed
            refunded = seen(timeline.cancelled) or (seen(timeline.completed)
                                                    and rng.random() < REFUND_RATE)
            payment_status = 'REFUNDED' if refunded else 'PAID'
        else:
            payment_status = 'PENDING'
        self.write('payments', (payment_id, method, payment_status, amount, stamp(paid_at), order_id))

        # A trip exists once the order is confirmed.
        if not seen(timeline.confirmed):
            return
        if seen(timeline.cancelled):
            trip_status = 'CANCELLED'
        elif seen(timeline.completed):
            trip_status = 'COMPLETED'
        elif seen(timeline.started):
            trip_status = 'IN_PROGRESS'
        elif seen(timeline.accepted):
            trip_status = 'ALLOCATED'
        else:
            trip_status = 'SEARCHING'
        trip_id = make_id('TRP', self.counts['trips'] + 1)
        self.write('trips', (trip_id, stamp(timeline.started if seen(timeline.started) else None),
                             stamp(timeline.completed if seen(timeline.completed) else None),
                             trip_status, order_id, origin.location_id, destination.location_id))

        for vehicle_id, assigned, outcome, responded, ended, reason in timeline.attempts:
            if not seen(assigned):
                break
            if not seen(responded if outcome == 'ACCEPTED' else ended):
                outcome, responded, ended, reason = 'PENDING', None, None, None
            elif outcome == 'ACCEPTED' and seen(timeline.cancelled):
                outcome, ended, reason = 'CANCELLED', timeline.cancelled, timeline.cancel_reason
            elif outcome == 'ACCEPTED' and seen(timeline.completed):
                ended = timeline.completed
            self.write('driver_assignments', (
                make_id('ASN', self.counts['driver_assignments'] + 1), stamp(assigned), outcome,
                stamp(responded), stamp(ended), reason, trip_id, vehicle_id))


def generate(profile: str, directory: Path) -> dict[str, int]:
    """Write one CSV file with a header row per table into directory; return the row counts."""
    with ExitStack() as stack:
        writers = {}
        for table, columns in TABLES.items():
            file = stack.enter_context(open(directory / f'{table}.csv', 'w', newline='',
                                            encoding='utf-8'))
            writers[table] = csv.writer(file, lineterminator='\n')
            writers[table].writerow(columns)
        return Generator(profile, writers).run()


def write_seed_script(profile: str, out: BinaryIO) -> None:
    """Write a psql script that loads the dataset with COPY ... FROM STDIN, then runs ANALYZE."""
    with tempfile.TemporaryDirectory() as directory:
        generate(profile, Path(directory))
        for table, columns in TABLES.items():
            out.write(f"COPY {table} ({', '.join(columns)}) FROM STDIN WITH (FORMAT csv, HEADER true);\n"
                      .encode())
            with open(Path(directory) / f'{table}.csv', 'rb') as data:
                shutil.copyfileobj(data, out)
            out.write(b'\\.\n')
    out.write(b'ANALYZE;\n')


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description='Write the synthetic dataset as one CSV file per table.')
    parser.add_argument('--profile', required=True, choices=PROFILES)
    parser.add_argument('--output-dir', required=True, type=Path)
    args = parser.parse_args(argv)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for table, count in generate(args.profile, args.output_dir).items():
        print(f'{table}: {count}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
