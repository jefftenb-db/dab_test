# dab_test

A tiny Streamlit app that demonstrates the **Databricks Asset Bundle (DAB) dev/prod deployment
pattern** when the app is **sourced directly from a Git repo** and pulls **all** Python
dependencies from a Unity Catalog Volume (no pypi at runtime).

| | dev | prod |
|---|---|---|
| App name | `dab-test-dev` | `dab-test-prod` |
| UC Volume | `tenbosch.app_dev.py_libs` | `tenbosch.app_prod.py_libs` |
| Wheel path | `/Volumes/tenbosch/app_dev/py_libs/` | `/Volumes/tenbosch/app_prod/py_libs/` |

Both apps run side-by-side in the same workspace: `https://fevm-classic-stable-2te8jp.cloud.databricks.com`.

## How it works (native-install pattern)

The repo holds a single static `app/requirements.txt` with just package names — same file for
both apps. The per-env wheel source is supplied to pip via pip-native env variables, set in
`app.yaml`:

```yaml
env:
  - name: PIP_NO_INDEX
    value: "1"
  - name: PIP_FIND_LINKS
    valueFrom: py_lib_volume       # resolves to /Volumes/<cat>/<sch>/py_libs
```

`valueFrom: py_lib_volume` references the `uc_securable` resource bound to the app in
`databricks.yml`. DAB substitutes `${var.py_lib_catalog}` / `${var.py_lib_schema}` per target,
so dev binds `tenbosch.app_dev.py_libs` and prod binds `tenbosch.app_prod.py_libs`. The env var
ends up resolving to the env-specific volume path at runtime.

Databricks Apps' built-in deploy step runs `pip install -r requirements.txt`. Pip reads
`PIP_NO_INDEX` and `PIP_FIND_LINKS` from the env (pip-native flags), so the install pulls from
the bound UC Volume — never pypi.

**Important layout constraint:** wheels must live at the **root** of the volume
(`/Volumes/<cat>/<sch>/py_libs/`, not a sub-directory). The `valueFrom` UC volume binding
resolves to the volume root path with no sub-path support, so the wheels and the env var have
to agree.

## Prerequisites

- Databricks CLI authenticated to `fevm-classic-stable-2te8jp` (profile `fevm-classic-stable-2te8jp`).
- Schemas `tenbosch.app_dev` and `tenbosch.app_prod` exist.
- Volume `py_libs` exists in both schemas.
- Each app's service principal has **Git credentials** configured to read this GitHub repo.
  This is a one-time setup per app SP in the workspace UI (App → Git integration).
- The app SP also needs `READ VOLUME` on the bound volume. The bundle requests `READ_VOLUME` as
  part of the `uc_securable` binding, but if you pre-create the apps or the grant fails:
  ```sql
  GRANT READ VOLUME ON VOLUME tenbosch.app_dev.py_libs  TO `<dab-test-dev-sp>`;
  GRANT READ VOLUME ON VOLUME tenbosch.app_prod.py_libs TO `<dab-test-prod-sp>`;
  ```

## Deploy

```bash
# 1. One-time per env (and after every change to app/requirements.txt):
#    Download wheels locally and push them to the volume root.
./scripts/stage_wheels.sh tenbosch app_dev
./scripts/stage_wheels.sh tenbosch app_prod

# 2. Push code — the apps pull from GitHub, not from your laptop.
git push origin main

# 3. Create / update the dev app and ship the current main:
databricks bundle deploy -t dev
databricks bundle run    -t dev dab_test_app     # dab-test-dev

# 4. Same for prod:
databricks bundle deploy -t prod
databricks bundle run    -t prod dab_test_app    # dab-test-prod
```

To pin prod to a tag or commit, set `git_branch` (or extend `databricks.yml` to use `tag` / `commit`):
`databricks bundle deploy -t prod --var="git_branch=release-2026.05"`.

## Verify

1. After deploy, open each app URL printed by `bundle run`:
   - `dab-test-dev` → page shows `Target: DEV`, `UC catalog/schema: tenbosch / app_dev`,
     `PIP_FIND_LINKS: /Volumes/tenbosch/app_dev/py_libs`, the cowsay output, and a streamlit version.
   - `dab-test-prod` → same page, `Target: PROD`, prod volume path.
2. In the app's **Logs** during deploy/startup, the `pip install -r requirements.txt` output
   should reference only the volume path, with no pypi network calls.
3. Independence check: bump the cowsay message in `app/app.py`, `git push`, then run
   `databricks bundle run -t dev dab_test_app` only → only dev shows the new message.
4. Negative test: revoke `READ VOLUME` on the dev volume and redeploy → `dab-test-dev` fails at
   the `pip install` step with the volume path in the error; prod keeps working.

## Adding / removing a dependency

1. Edit `app/requirements.txt`.
2. `./scripts/stage_wheels.sh tenbosch app_dev` (and `app_prod`).
3. `git push` + `databricks bundle run -t {dev,prod} dab_test_app`.

## Layout

```
.
├── databricks.yml         # bundle: variables, targets, app resource + UC volume binding
├── app.py                 # streamlit page (Databricks Apps source_code_path: ./)
├── app.yaml               # env vars (PIP_NO_INDEX, PIP_FIND_LINKS via valueFrom) + start command
├── requirements.txt       # static list of packages — pip uses env-supplied --find-links
└── scripts/
    └── stage_wheels.sh    # pip download → upload wheels to volume root
```

Databricks Apps git source pulls from the **root** of this repo (`source_code_path: ./`), so the app files live alongside the bundle config rather than in a subdirectory. The Apps runtime appears to ignore non-root `source_code_path` values in some configurations — keeping the entry-point files at the repo root avoids that.

## Trade-offs

- **Wheels must live at the volume root, not in a sub-directory.** `valueFrom` on a UC volume
  binding only exposes the root path. If you also want to keep other content in the volume,
  put it in a different volume.
- **`requirements.txt` is just package names** — no `--no-index` / `--find-links` directives.
  Those come from env vars at install time. Don't add `--find-links` directly to
  `requirements.txt`; env-variable substitution inside `requirements.txt` is not supported by
  Databricks Apps.
- **Git credentials are app-SP-scoped.** Each app's SP needs a working credential for this repo.
  Switching `git_repository` later resets these credentials.
