# GitHub Secrets & Variables Setup Guide

All sensitive values are stored as **GitHub Actions Secrets** (encrypted).
Non-sensitive config goes in **Repository Variables** (plain text, visible in logs).

---

## Required Secrets

Navigate to: `Repo → Settings → Secrets and variables → Actions → New repository secret`

### LoadRunner Infrastructure
| Secret Name              | Description                                       | Example Value               |
|--------------------------|---------------------------------------------------|-----------------------------|
| `LR_LICENSE_SERVER`      | Hostname/IP of the LR License Server              | `lr-license.corp.internal`  |
| `LR_CONTROLLER_HOST`     | Hostname of the LR Controller machine             | `lr-ctrl-01.corp.internal`  |
| `LR_SCRIPT_USERNAME`     | Default service account for LR Controller auth    | `svc_loadrunner`            |
| `LR_SCRIPT_PASSWORD`     | Password for the default service account          | `***`                       |

### Per-User Credentials (Individual Logins for Test Scripts)
For scripts requiring individual user sessions (OAuth, MFA, per-user data):
```
LR_USER_1_USERNAME   →  testuser001@example.com
LR_USER_1_PASSWORD   →  ***
LR_USER_2_USERNAME   →  testuser002@example.com
LR_USER_2_PASSWORD   →  ***
...
LR_USER_50_USERNAME  →  testuser050@example.com
LR_USER_50_PASSWORD  →  ***
```
> These are injected into the LoadRunner parameter file at runtime and cycle across VUsers.
> Provision users in your test environment's IAM/AD before running tests.

### Target Environment URLs
| Secret Name           | Description                  |
|-----------------------|------------------------------|
| `TARGET_URL_DEV`      | Base URL for dev environment |
| `TARGET_URL_STAGING`  | Base URL for staging         |
| `TARGET_URL_PROD`     | Base URL for production      |

### Dynatrace
| Secret Name         | Description                                       |
|---------------------|---------------------------------------------------|
| `DT_ENVIRONMENT_ID` | Your Dynatrace environment ID (e.g. `abc12345`)   |
| `DT_API_TOKEN`      | API token with `metrics.ingest`, `events.ingest`  |

**Dynatrace API Token Scopes required:**
- `metrics.ingest`
- `events.ingest`
- `DataExport` (for reading back metrics in dashboards)

### AppDynamics
| Secret Name                  | Description                             |
|------------------------------|-----------------------------------------|
| `APPDYNAMICS_CONTROLLER_URL` | Full controller URL (no trailing slash) |
| `APPDYNAMICS_ACCOUNT_NAME`   | AppDynamics account name                |
| `APPDYNAMICS_API_KEY`        | AppDynamics API key                     |
| `APPDYNAMICS_APP_ID`         | Numeric Application ID                  |

### Notifications
| Secret Name        | Description                          |
|--------------------|--------------------------------------|
| `SLACK_WEBHOOK_URL`| Incoming webhook URL for Slack alerts|

---

## Repository Variables (non-sensitive)

Navigate to: `Repo → Settings → Secrets and variables → Actions → Variables tab`

| Variable Name          | Description                         | Default   |
|------------------------|-------------------------------------|-----------|
| `DEFAULT_VUSERS`       | Default VUser count                 | `50`      |
| `DEFAULT_DURATION_MIN` | Default test duration (minutes)     | `10`      |
| `DASHBOARD_PUBLIC_URL` | Public URL of your GitHub Pages site| *(set me)*|

---

## Self-Hosted Runner Setup

LoadRunner requires a Windows runner with LoadRunner installed.

### Runner Labels Required
```
self-hosted, loadrunner, windows
```

### Installation
```powershell
# On your Windows LR machine:
# 1. Go to Repo → Settings → Actions → Runners → New self-hosted runner
# 2. Select Windows, copy the config commands
# 3. During ./config.cmd, enter labels: self-hosted,loadrunner,windows
# 4. Install as a service: ./svc.sh install && ./svc.sh start

# Required environment variables on the runner machine:
[System.Environment]::SetEnvironmentVariable("LR_INSTALL_DIR", "C:\Program Files\Micro Focus\LoadRunner", "Machine")
```

### Runner machine requirements
- Windows Server 2019+ or Windows 10+
- LoadRunner 2023+ installed and licensed
- PowerShell 5.1+
- Python 3.9+ (for result parsing scripts)
- Network access to LR Controller and License Server
- Outbound HTTPS to Dynatrace and AppDynamics

---

## Dashboard Access (Public / No Login Required)

The performance dashboard is published to **GitHub Pages** — no authentication needed.

```
https://<org>.github.io/<repo>/dashboard/
```

Enable GitHub Pages:
1. Repo → Settings → Pages
2. Source: Deploy from a branch
3. Branch: `gh-pages` / root

The `dashboard/data.json` file is committed by the workflow after each run and the
static HTML dashboard reads it via `fetch()` on load — no backend required.
