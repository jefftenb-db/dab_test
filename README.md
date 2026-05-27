# dab_test

A tiny Streamlit app that demonstrates the **Databricks Asset Bundle (DAB) dev/prod deployment pattern**
while sourcing **all** Python dependencies from a Unity Catalog Volume (no pypi at runtime).

| | dev | prod |
|---|---|---|
| App name | `dab-test-dev` | `dab-test-prod` |
| Wheel volume | `/Volumes/tenbosch/app_dev/py_libs/app/py_libs/` | `/Volumes/tenbosch/app_prod/py_libs/app/py_libs/` |

Both apps run side-by-side in the same workspace: `https://fevm-classic-stable-2te8jp.cloud.databricks.com`.

## How it works

1. `requirements.txt.tpl` is the single source of truth for dependencies. It uses `__CATALOG__` /
   `__SCHEMA__` placeholders and a `--no-index --find-links /Volumes/.../py_libs/app/py_libs/` directive
   so pip never reaches out to pypi.
2. `scripts/build_requirements.sh` substitutes those placeholders for the target env and writes
   `app/requirements.txt`. That file gets synced to the workspace by DAB and used by the app at
   install time.
3. `scripts/stage_wheels.sh` runs `pip download` locally (linux/x86_64, py3.11) for everything in
   the template, then uploads the wheels to the UC Volume the app will install from.
4. `databricks bundle deploy` syncs `app/` to a target-specific workspace folder and creates/updates
   the `dab-test-{dev,prod}` app resource.

## Prerequisites

- Databricks CLI authenticated to `fevm-classic-stable-2te8jp` (default profile or `DATABRICKS_CONFIG_PROFILE`).
- Schemas `tenbosch.app_dev` and `tenbosch.app_prod` exist.
- Volume `py_libs` exists in both schemas, with a writable subdir `app/py_libs/`.
- The app's service principal has `READ VOLUME` on each volume. If not, app startup fails at pip install:
  ```sql
  -- run in each env
  GRANT READ VOLUME ON VOLUME tenbosch.app_dev.py_libs TO `<app-service-principal>`;
  GRANT READ VOLUME ON VOLUME tenbosch.app_prod.py_libs TO `<app-service-principal>`;
  ```

## Deploy

```bash
# 1. Stage wheels into each env's UC Volume (one-time, repeat whenever requirements.txt.tpl changes)
./scripts/stage_wheels.sh tenbosch app_dev
./scripts/stage_wheels.sh tenbosch app_prod

# 2. Build the env-specific requirements.txt + deploy + start, for dev
./scripts/build_requirements.sh tenbosch app_dev
databricks bundle deploy -t dev
databricks bundle run -t dev dab_test_app          # starts/refreshes dab-test-dev

# 3. Same for prod
./scripts/build_requirements.sh tenbosch app_prod
databricks bundle deploy -t prod
databricks bundle run -t prod dab_test_app         # starts/refreshes dab-test-prod
```

The `bundle deploy` step prints the synced workspace path; `bundle run` prints the app URL.

## Verify

1. Hit the dev URL — page shows `Target: DEV`, the cowsay output, and the dev volume path.
2. Hit the prod URL — same page, `Target: PROD`, prod volume path.
3. Open the workspace path `~/.bundle/dab_test/dev/files/app/requirements.txt` and confirm
   `__CATALOG__` / `__SCHEMA__` were substituted with `tenbosch` / `app_dev`. Repeat for prod.
4. Independence: change the cowsay message in `app/app.py`, run only the dev deploy, refresh both
   URLs — only dev shows the new message.
5. (Optional) Negative test: revoke `READ VOLUME` on the dev volume and redeploy → `dab-test-dev`
   fails to start with a pip error referencing the volume path; `dab-test-prod` keeps working.

## Adding a new dependency

1. Add the package name on its own line in `requirements.txt.tpl`.
2. Re-run `./scripts/stage_wheels.sh` for both envs.
3. Redeploy.

## Layout

```
.
├── databricks.yml            # bundle config (targets, variables, app resource)
├── requirements.txt.tpl      # templated reqs (single source of truth)
├── app/
│   ├── app.py                # streamlit app
│   └── app.yaml              # apps runtime config
└── scripts/
    ├── build_requirements.sh # .tpl → app/requirements.txt for a given env
    └── stage_wheels.sh       # pip download → UC Volume upload
```
