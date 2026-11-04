# Config

`dataset_profile.yaml` sets what the generated data depends on. Behaviour rates, such as cancellations and payment methods, are constants in `scripts/generate_data.py`.

| Key | Value | Rationale |
| --- | --- | --- |
| `seed` | `42` | A fixed seed makes every machine generate the same data, so teammates rebuild a profile instead of sharing dumps. |
| `period` | 2026-05-01 to 2026-11-01 | Six months gives daily and monthly queries enough history. Fixed dates keep the data from changing with the day it is generated. The dataset is a snapshot at `end`. |
| `profiles` | small, medium, large | Each profile is ten times the previous one, so benchmarks show how query time grows with volume. |
| `order_distribution` | mobility 32%, food 32%, delivery 36% | The share of each order subtype. It is the same for all profiles. |

Every profile keeps the same ratios, so profiles differ only in size, not in the shape of their data:

| Ratio | Value |
| --- | --- |
| Orders per customer | 10 |
| Orders per driver | 20 |
| Locations per customer | 2, so pickups and drop-offs vary |
| Food orders per outlet | about 11 |

Keep these ratios when adding a profile. Changing any value here changes the generated data, so rebuild the affected databases (see `scripts/README.md`).
