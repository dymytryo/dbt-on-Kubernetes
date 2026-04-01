# dbt on Kubernetes: CronJob-Based ELT Orchestration

A production dbt-snowflake project running 37 scheduled CronJobs on Kubernetes, orchestrated via Helm, with credentials injected from Consul and AWS Secrets Manager.

This repository demonstrates a complete ELT pipeline architecture: CI/CD builds a Docker image containing the dbt project, packages it as a Helm chart, and deploys CronJobs to Kubernetes that execute dbt transformations on configurable schedules.

---

## Architecture Overview

```
GitLab CI (merge to main)
    |
    |--> Build Docker image (Python 3.9 + dbt-snowflake 1.2)
    |--> Build Helm chart from .pkg/app/dbt/helm/values.yaml
    |--> Deploy Helm chart to Kubernetes (namespace: data)
    |
    v
Kubernetes CronJobs (37 total)
    |
    |--> Each CronJob runs a container from the built image
    |--> envconsul injects env vars from Consul (prefix: data/dbt/)
    |--> Container runs: entrypoint.sh <job_name>
    |--> entrypoint.sh generates profiles.yml from AWS Secrets Manager
    |--> dbt run/snapshot/test/run-operation executes against Snowflake
    |
    v
Snowflake Data Warehouse
    |--> ~1,000 models across ~50 schemas
    |--> 13 snapshots (SCD Type 2)
    |--> Scheduled macro operations (exports, maintenance)
```

---

## Background Concepts

### Docker

Docker packages an application and all its dependencies into a portable unit called an "image." When you run an image, it becomes a "container" - an isolated process that behaves the same regardless of where it runs.

The Dockerfile at `.pkg/app/Dockerfile` defines the image:

```dockerfile
FROM <ecr-registry>/python-base:3.9.6
WORKDIR /app/
RUN apt-get update && apt-get install -y --no-install-recommends openssl
COPY .pkg/app/requirements.txt .
RUN pip3 install -r requirements.txt    # dbt-snowflake, boto3, etc.
COPY . ./                               # all dbt models, macros, lib/
COPY .pkg/app/entrypoint.sh .
RUN chmod +x entrypoint.sh
CMD bash
```

Every CronJob pulls this same image. A single merge to main updates all 37 jobs because they all share the same image tag (the CI pipeline ID).

### Kubernetes

Kubernetes (K8s) runs containers across a cluster of machines. You describe what you want in YAML, and Kubernetes makes it happen.

Key concepts for this project:

- **Cluster**: A set of machines (nodes) managed by Kubernetes
- **Namespace**: A logical partition within a cluster. All jobs run in the `data` namespace
- **Pod**: The smallest K8s unit - one or more containers running together. Each dbt run creates one Pod
- **CronJob**: Creates Pods on a cron schedule. This is the core orchestration mechanism
- **Job**: A one-time run. A CronJob creates a Job each time it fires, and the Job creates a Pod

The lifecycle of a single dbt run:

```
CronJob (schedule fires)
  --> Job (created by CronJob)
    --> Pod (created by Job)
      --> Container starts from dbt Docker image
      --> envconsul loads env vars from Consul
      --> entrypoint.sh runs dbt commands
      --> Container exits (success or failure)
    --> Pod terminates, Job records result
```

### Helm

Helm is a package manager for Kubernetes - like apt for Ubuntu or brew for macOS, but for deploying apps to a K8s cluster.

Without Helm, you'd write raw Kubernetes YAML for each CronJob (37 separate files, lots of repetition). Helm solves this with:

- **Chart**: A package of templated K8s YAML files (the recipe)
- **Values file**: Variables injected into templates (the customization)
- **Release**: A deployed instance of a chart
- **Templates**: YAML with Go template syntax that reads from the values file

This project provides only the values file. Shared chart templates (from a platform team repo) know how to turn each entry under `deployables:` into a Kubernetes CronJob.

```
values.yaml (this repo)  +  Chart templates (shared)
                          |
                    helm package
                          |
                          v
                    Helm chart (.tgz)
                          |
                    helm upgrade --install
                          |
                          v
              37 CronJob resources in Kubernetes
```

### Consul / envconsul

Consul is a service discovery and key-value store running on every cluster node. `envconsul` is a CLI tool that reads key-value pairs from Consul and injects them as environment variables before running a command.

Each CronJob container runs:

```bash
envconsul -consul-addr=$(NODE_IP):8500 -prefix=data/dbt/ ./entrypoint.sh <job_name>
```

This loads all keys under `data/dbt/` as env vars, then runs the entrypoint. The Consul keys provide:

| Key | Value | Purpose |
|---|---|---|
| `DATABASE` | `<warehouse_name>` | Target Snowflake database |
| `SECRET_NAME` | `<secret-id>` | AWS Secrets Manager secret to fetch credentials from |
| `DBT_PROFILES_DIR` | `./` | Where dbt looks for profiles.yml |

### Cron Expressions

Cron expressions define schedules. Format: `minute hour day-of-month month day-of-week`

```
 ┌───────────── minute (0-59)
 │ ┌───────────── hour (0-23)
 │ │ ┌───────────── day of month (1-31)
 │ │ │ ┌───────────── month (1-12)
 │ │ │ │ ┌───────────── day of week (0-6, 0=Sunday)
 │ │ │ │ │
 * * * * *
```

Examples from this project:

| Expression | Meaning |
|---|---|
| `0 */2 * * *` | Every 2 hours, on the hour |
| `15 0 * * *` | Daily at 00:15 UTC |
| `20 0-1,13-23 * * 1-5` | Mon-Fri, at :20 past hours 0, 1, 13-23 |
| `10 * * * 0,6` | Every hour on Saturday and Sunday |
| `0 2 3 1,4,7,10 *` | Quarterly: 02:00 UTC on the 3rd of Jan/Apr/Jul/Oct |

---

## How the Pipeline Works

### CI/CD Pipeline (`.gitlab-ci.yml`)

On merge to main, GitLab CI runs:

```
1. unit_tests        - Python unit tests
2. build_image       - Build Docker image, push to ECR
3. build_helm_chart  - Package Helm chart with new image tag
4. deploy_prd        - Deploy chart to production K8s cluster
5. deploy_docs       - Compile dbt docs, upload to S3
```

The image tag is the CI pipeline ID, so every merge creates a uniquely tagged image.

### The Entrypoint Script

`entrypoint.sh` is the job dispatcher. Every CronJob calls it with a job name. It always starts with:

```bash
python3 lib/dbt_profile.py   # Generate profiles.yml from AWS Secrets Manager
dbt deps                      # Install dbt packages
```

Then matches the argument to dbt commands using three patterns:

**Pattern 1 - Tag-based** (runs all models with a tag):
```bash
if [[ $1 == business_hours ]]; then
  dbt run --profiles-dir ./ --models tag:business_hours
fi
```

**Pattern 2 - Explicit model list** (runs specific models in order):
```bash
if [[ $1 == spend_activity ]]; then
  dbt run --profiles-dir ./ --models spend_activity_current
  dbt run --profiles-dir ./ --models spend_activity
  dbt run --profiles-dir ./ --models merchant
fi
```

**Pattern 3 - Mixed** (models + snapshots + operations):
```bash
if [[ $1 == every_morning ]]; then
  dbt run --profiles-dir ./ --models tag:every_morning
  dbt run-operation --profiles-dir ./ table_storage_snapshot
  dbt snapshot --profiles-dir ./ -s opportunity_snapshot
fi
```

Cleanup always runs at the end:
```bash
python3 lib/log_read.py    # Process logs
rm profiles.yml             # Remove credentials
```

### Credential Flow

```
AWS Secrets Manager                Consul (on K8s node)
  |                                  |
  | secret: <credentials>            | key: data/dbt/DATABASE
  | contains: account, user,         | key: data/dbt/SECRET_NAME
  |   password, role, warehouse      |
  |                                  |
  v                                  v
         dbt_profile.py
           |
           | 1. envconsul already set DATABASE, SECRET_NAME as env vars
           | 2. Detects prod AWS account
           | 3. Fetches credentials from Secrets Manager
           | 4. Writes profiles.yml with Snowflake connection config
           v
        profiles.yml --> dbt connects to Snowflake
```

---

## Project Structure

```
.
├── .gitlab-ci.yml                    # CI/CD pipeline
├── .pkg/
│   └── app/
│       ├── Dockerfile                # Container image definition
│       ├── entrypoint.sh             # Job dispatcher script
│       ├── requirements.txt          # Python/dbt dependencies
│       └── dbt/
│           ├── helm/
│           │   └── values.yaml       # All 37 CronJob definitions
│           └── consul/
│               └── prd/
│                   └── config.ctmpl  # Consul key-value template
├── dbt_project.yml                   # dbt project configuration
├── packages.yml                      # dbt package dependencies
├── models/
│   ├── sources.yml                   # Source definitions
│   ├── staging/                      # Source views (tag: data_lake)
│   ├── dimensions/                   # Dimension tables
│   ├── facts/                        # Fact tables
│   ├── risk/                         # Risk/portfolio models
│   └── reports/                      # Reporting models
├── macros/                           # SQL macros (exports, maintenance)
├── snapshots/                        # SCD Type 2 snapshots
├── lib/
│   ├── dbt_profile.py                # Runtime profile generator
│   ├── custom_alerts.py              # Alert notifications
│   └── helpers/
│       ├── aws_secrets.py            # AWS Secrets Manager client
│       └── snowflake_connection.py   # Snowflake connection helper
└── tests/                            # Data quality tests
```

### Model Organization

Models are organized by layer, with each directory mapping to a Snowflake schema:

| Directory | Schema | Materialization | Description |
|---|---|---|---|
| `models/staging/` | staging | view | Source views over raw data (lightweight) |
| `models/dimensions/` | dim | table (transient) | Dimension tables with PII masking |
| `models/facts/` | fact | table (transient) | Fact tables |
| `models/risk/` | risk | table (transient) | Risk/portfolio monitoring (dedicated warehouse) |
| `models/reports/` | reports | table (transient) | Reporting aggregations |

"Transient" in Snowflake means no Fail-safe period - cheaper storage but no 7-day recovery after Time Travel expires.

Several schemas apply PII masking post-hooks: `{{ apply_data_masking(columns=get_pii_columns()) }}` which runs Snowflake dynamic data masking policies after each model build.

---

## All 37 CronJobs

### CronJob Definition (values.yaml)

Each entry under `deployables:` becomes a Kubernetes CronJob:

```yaml
dbt-nightly:                          # K8s CronJob name
  controller: cronjob                 # Resource type
  schedule: "15 0 * * *"             # When to run (cron, UTC)
  concurrencyPolicy: Forbid           # Don't overlap with previous run
  startingDeadlineSeconds: 600        # Skip if >10min late
  backoffLimit: 1                     # Retry once on failure
  suspend: false                      # false = active, true = paused
  command: [/bin/bash, -ec]
  args:
    - envconsul ... ./entrypoint.sh nightly
  resources:
    requests: { cpu: 100m }           # 0.1 CPU minimum
    limits: { cpu: 500m }             # 0.5 CPU maximum
  restartPolicy: Never
```

The `global:` section applies to all jobs (namespace, image, node affinity).

### Tag-Based Jobs

Models opt into a schedule by adding a tag in their config: `{{ config(tags=["every_3_hours"]) }}`. A model can have multiple tags to run on multiple schedules.

| CronJob | Schedule (UTC) | Tag | Models | Notes |
|---|---|---|---|---|
| dbt-business-hours | `20 0-1,13-23 * * 1-5` | business_hours | ~20 | Weekday business + evening hours |
| dbt-week-nights | `10 2-12 * * 1-5` | week_nights | ~18 | Weekday off-peak hours |
| dbt-weekends | `10 * * * 0,6` | weekends | ~18 | Hourly on Sat/Sun |
| dbt-nightly | `15 0 * * *` | nightly | 1 | + 3 snapshots |
| dbt-every-1-hour | `50 * * * *` | every_1_hour | 0 | Runs exports + alerts only |
| dbt-every-3-hours | `30 */3 * * *` | every_3_hours | ~13 | Core dimensions |
| dbt-every-6-hours | `15 */6 * * *` | every_6_hours | ~31 | Transaction history chain |
| dbt-every-12-hours | `0 0,12 * * *` | every_12_hours | 2 | |
| dbt-every-morning | `0 11 * * *` | every_morning | ~29 | + 4 exports + 6 snapshots |
| dbt-risk-daily | `0 7 * * *` | risk_daily | 8 | Portfolio monitoring |
| dbt-saturday-morning | `10 * * * 6` | saturday_morning | ~15 | Hourly on Saturday |
| dbt-marketing | `0 03 * * *` | marketing | ~36 | Marketing platform models |
| dbt-data-lake | `0 07,13,18 * * *` | data_lake | ~760 | All source views, 3x/day |
| dbt-view | `15 07 * * 0` | view | ~92 | Weekly view refresh |
| dbt-risk-quarterly | `0 2 3 1,4,7,10 *` | risk_quarterly | 1 | Quarterly risk data |
| dbt-monthly-report | `0 22 16,18 * *` | monthly_report | 1 | Mid-month reporting |
| dbt-warehouse-spend | `30 10 * * *` | warehouse_spend | ~4 | Warehouse cost tracking |
| dbt-observability | `0 20 * * *` | observability | 1 | dbt observability package |

### Explicit Model List Jobs

These run specific models in a fixed order (dependencies require sequencing).

| CronJob | Schedule (UTC) | Models |
|---|---|---|
| dbt-spend-activity | `0 */2 * * *` | spend_activity chain (6 models) |
| dbt-spend-activity-weekly | `0 0 * * 0` | Historical spend backfill (5 year-partitioned models) |
| dbt-delinquency-afternoon | `0 15 * * *` | Delinquency events + billing performance (4 models) |
| dbt-risk-scoring | `0 0 * * *` | Risk scoring pipeline (5 models) |
| dbt-uuid-validation | `0 11 * * *` | 9 UUID validation models |
| dbt-underwriting | `0 11 * * *` | Underwriting history chain (4 models) |
| dbt-payments | `15 */2 * * *` | Payment processing chain (4 models) |
| dbt-late-evening | `0 04 * * *` | Single fraud accrual model |
| dbt-early-evening | `0 02 * * *` | CRM + product analytics tags + 3 snapshots |
| dbt-user-snapshots | `0 17 * * *` | User snapshot only |

### Macro Execution Jobs (run-operations)

These execute SQL macros directly - maintenance tasks and data exports, not model builds.

| CronJob | Schedule (UTC) | Operations | Purpose |
|---|---|---|---|
| dbt-delete-soft-deleted | `0,30 * * * *` | 4 delete macros | Hard-delete CDC soft-deleted rows |
| dbt-historical-billing | `40 12 * * *` | billing_history | Billing history macro |
| dbt-credit-snapshot | `0 10 * * *` | credit_line_snapshot | Credit line state capture |

### Utility Jobs (Python, not dbt)

| CronJob | Schedule (UTC) | Script | Purpose |
|---|---|---|---|
| dbt-cleanup-dev-dbs | `30 14 * * 1-5` | `lib/delete_old_dev_databases.py` | Clean up old dev database clones |
| dbt-refresh-test-db | `30 9 * * 1-5` | `lib/refresh_stage_database.py` | Refresh test database from prod |
| dbt-warehouse-scale-up | `35 13 * * 1-5` | `lib/modify_warehouse.py increase` | Scale up warehouse (SUSPENDED) |
| dbt-warehouse-scale-down | `55 23 * * 1-5` | `lib/modify_warehouse.py decrease` | Scale down warehouse (SUSPENDED) |

### Test Job

| CronJob | Schedule (UTC) | Purpose |
|---|---|---|
| dbt-all-tests | `18 */6 * * *` | `dbt test` with `--store-failures` (every 6 hours) |

---

## ETL Shutdown Procedures

Three approaches, from safest to most permanent.

### Option 1: Suspend via kubectl (instant, reversible)

Patches live K8s resources directly. Takes effect immediately but resets on next Helm deploy.

```bash
# List all CronJobs
kubectl get cronjobs -n data

# Suspend ALL at once
kubectl get cronjobs -n data -o name | xargs -I {} kubectl patch {} -n data -p '{"spec":{"suspend":true}}'

# Verify (SUSPEND column = True)
kubectl get cronjobs -n data | awk '{print $1, $5}'

# Resume one if needed
kubectl patch cronjob <name> -n data -p '{"spec":{"suspend":false}}'
```

### Option 2: Suspend via values.yaml (persists across deploys)

```bash
# Set suspend: true on all jobs
sed -i 's/suspend: false/suspend: true/g' .pkg/app/dbt/helm/values.yaml

# Commit and deploy via CI
git commit -am "Suspend all CronJobs"
git push
```

### Option 3: Delete the Helm release (permanent)

```bash
helm list -n data
helm uninstall <release-name> -n data
```

### Recommended sequence

1. Option 1 to stop jobs immediately
2. Option 2 MR so it persists across deploys
3. Monitor for downstream impact
4. Option 3 once confirmed safe

---

## Impact Assessment

Things that stop working when the ETL is shut down:

1. **Downstream consumers** - Dashboards and applications reading from the warehouse see stale data
2. **Data exports** - Scheduled exports to S3/external systems stop (revenue, compliance, enterprise datasets)
3. **Alerts** - Custom alert notifications stop firing
4. **CDC cleanup** - Soft-deleted rows from CDC ingestion accumulate in source tables
5. **Snapshots** - 13 SCD Type 2 tables stop tracking historical changes
6. **Test database** - Developer test database stops refreshing from production
7. **Data quality tests** - Automated test runs stop

---

## Useful Commands

```bash
# --- Kubernetes ---
kubectl get cronjobs -n data                              # List CronJobs
kubectl get jobs -n data | grep <name> | tail -5          # Recent runs
kubectl get pods -n data | grep <name> | tail -5          # Recent pods
kubectl logs <pod-name> -n data                           # Read run logs
kubectl describe cronjob <name> -n data                   # Full CronJob details
kubectl create job --from=cronjob/<name> manual-run -n data  # Manual trigger

# --- Helm ---
helm list -n data                                         # List releases
helm get manifest <release> -n data                       # Rendered K8s YAML
helm history <release> -n data                            # Deploy history
helm rollback <release> <revision> -n data                # Rollback
```

---

## Tech Stack

| Component | Technology |
|---|---|
| Transformation | dbt-snowflake 1.2.0 |
| Data Warehouse | Snowflake |
| Orchestration | Kubernetes CronJobs |
| Packaging | Helm |
| CI/CD | GitLab CI |
| Container Runtime | Docker |
| Config Management | HashiCorp Consul + envconsul |
| Secrets | AWS Secrets Manager |
| Container Registry | AWS ECR |
| Observability | elementary-data |
