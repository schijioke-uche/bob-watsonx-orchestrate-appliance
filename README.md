# IBM Bob watsonx Orchestrate Appliance

**Appliance:** IBM Bob watsonx Orchestrate Agent (WXA)  
**Author:** Dr. Jeffrey Chijioke-Uche, IBM Computer Scientist (Inventor: Quantum Computing Qiskit Connector - https://pypi.org/project/qiskit-connector/) 
**Runtime:** Bob Shell 2.x  

---

## Overview

The **WXA appliance** is an IBM Bob–powered agent specialized for **IBM watsonx Orchestrate**. It provides domain-specific AI assistance for designing, building, testing, deploying, and governing production-grade watsonx Orchestrate agents using the IBM Agent Development Kit (ADK) across all supported deployment targets.

### What WXA Does

- **Design** — Agent architecture, agentic workflow blueprints, multi-agent topologies, tool strategy, connection patterns, governance frameworks, security reviews → saved to `bob-watsonx-orchestrate-designs/`
- **Build** — Agent YAML/JSON/Python specs, Python tools, OpenAPI tools, agentic workflows, knowledge base configs, connection templates, evaluation tests, CI/CD assets using IBM ADK in the `wxo-adk-env` virtual environment → saved to `bob-watsonx-orchestrate-store/`
- **Operate** — Deployment, promotion, observability, evaluation, governance, rollback, and platform lifecycle management across SaaS and self-managed targets

---

## Prerequisites

| Requirement | Notes |
|---|---|
| **Bob Shell 2.x CLI** | `bob` must be on your `PATH` — verify with `bob --version` |
| **Python 3.11+** | Required for the IBM ADK virtual environment (`wxo-adk-env`) |
| **Bash** | Version 4+ recommended |
| **Bob API Key** | Obtain from your IBM Bob account or team lead |
| **IBM ADK** | Installed automatically by `ensure-wxo-adk-env.sh` into `wxo-adk-env`; package: `ibm-watsonx-orchestrate` |
| **Deployment target credentials** | IBM Cloud API key, MCSP key, or Software Hub/CPD credentials depending on your target (see `.env.example`) |

**Client workstation tools** (used in generated runbooks): `orchestrate` (ADK CLI), `python3`, `pip`, `oc`, `podman`, `skopeo`, `helm`, `jq`, `yq`, `git`

---

## Getting Started

### Step 1 — Clone / Open the Project

Open the `use-cases/watsonx-orchestrate/` directory in your terminal or IDE (e.g., VS Code with the IBM Bob extension).

```bash
cd use-cases/watsonx-orchestrate
```

### Step 2 — Configure Your Environment

Copy the provided example file to create your local `.env`:

```bash
cp .env.example .env
```

Then open `.env` and fill in your credentials. At minimum set your Bob API key and deployment target:

```bash
# Required: your IBM Bob API key
BOB_API_KEY="<your-api-key-here>"

# Optional: only needed for general-scope API keys (not inference-scope)
# BOB_TEAM_ID="<your-team-id>"

# Deployment target — choose one
WXO_TARGET="local"   # local | ibm-cloud-saas | aws-saas | govcloud | software-hub | cpd | openshift
WXO_ENVIRONMENT_NAME="dev"   # dev | test | uat | prod
```

Then fill in the section matching your target deployment:

**IBM Cloud SaaS:**
```bash
IBM_CLOUD_API_KEY=""
IBM_CLOUD_REGION="us-south"
WXO_IBM_CLOUD_SERVICE_INSTANCE_ID=""
```

**AWS SaaS / MCSP / GovCloud:**
```bash
WXO_MCSP_API_KEY=""
WXO_MCSP_REGION=""
WXO_MCSP_SERVICE_URL=""
```

**IBM Software Hub / CPD / Self-managed OpenShift:**
```bash
SOFTWARE_HUB_URL=""
SOFTWARE_HUB_ADMIN_USER=""
SOFTWARE_HUB_ADMIN_PASSWORD=""
OPENSHIFT_API_URL=""
OPENSHIFT_TOKEN=""
```

**Local ADK development:**
```bash
WXO_ADK_ENV_NAME="wxo-adk-env"
WXO_ADK_PYTHON_BIN="python3"
WXO_ADK_MIN_PYTHON="3.11"
WXO_DEVELOPER_EDITION_ENABLED="false"
```

Additional `.env.example` sections cover: private registry / airgap settings, agent metadata, repository structure paths, tool and toolkit configuration, external connections (ServiceNow, Salesforce, Workday, Microsoft Graph, Jira, GitHub, Databases), knowledge base configuration, agentic workflow and scheduling settings, channel exposure, CI/CD and evaluation settings, and governance/compliance controls.

> **Security:** `.env` is listed in `.gitignore`. Never commit it. Never hardcode secrets in agents, tools, flows, connection files, manifests, tests, or README files. Use `.env` variable placeholders only.

### Step 3 — Ensure the ADK Environment

Before any build, import, export, deploy, test, or package operation, ensure the IBM ADK virtual environment is ready:

```bash
bash .bob/watsonx-orchestrate-tools/ensure-wxo-adk-env.sh
```

This creates (or verifies) the `wxo-adk-env` Python virtual environment and installs the `ibm-watsonx-orchestrate` ADK package.

### Step 4 — Authenticate

Run the authentication script to validate your Bob API key against the Bob Shell 2.x backend:

```bash
bash bob-auth.sh
```

A successful run prints:

```
Bob Shell <version> Backend Authentication Validated Successfully!
```

If authentication fails, verify:
- `BOB_API_KEY` is set correctly in `.env`
- Network/TLS connectivity to `https://api.us-east.bob.ibm.com`
- If using a general-scope key, `BOB_TEAM_ID` must also be set in `.env`

---

## Launching with xLaunchpad

[`xLaunchpad.sh`](xLaunchpad.sh) is the official managed entry point for the WXA appliance. It automatically locates and delegates to the correct versioned launcher (`bob-watsonx-orchestrate-v<version>.sh`), loads the trusted project environment, and routes into the selected mode.

### Interactive Chat Session

```bash
bash xLaunchpad.sh
```

### Launch with a Specific Mode

```bash
bash xLaunchpad.sh --mode wxo-agent-architect   # Full agent architecture, ADK build, governance (primary mode)
bash xLaunchpad.sh --mode ask                   # WXO documentation, concepts, best practices
bash xLaunchpad.sh --mode code                  # Agent specs, Python/OpenAPI tools, workflows, tests
bash xLaunchpad.sh --mode advance               # Enterprise WXO platform architecture
bash xLaunchpad.sh --mode plan                  # Implementation plans and rollout sequences
```

### One-Shot Task (Non-Interactive)

```bash
bash xLaunchpad.sh --mode wxo-agent-architect "Design a Python tool for querying ServiceNow incidents and save the design"
```

---

## Available Modes

| Mode slug | Name | Use for |
|---|---|---|
| `wxo-agent-architect` | IBM Bob watsonx Orchestrate WXO Agent Architect Appliance | **Primary mode** — full agent architecture, ADK development, tool/workflow design, deployment, governance |
| `ask` | IBM Bob watsonx Orchestrate Ask Appliance | WXO documentation, concepts, best practices, diagnostics, production readiness |
| `code` | IBM Bob watsonx Orchestrate Code Appliance | Agent YAML/JSON/Python specs, Python tools, OpenAPI tools, workflows, tests, packaging |
| `advance` | IBM Bob watsonx Orchestrate Advance Appliance | Enterprise WXO architecture: SaaS, Software Hub, airgap, tools, connections, KBs, channels, evaluation |
| `plan` | IBM Bob watsonx Orchestrate Plan Appliance | Structured implementation plans, patching, agent design, and platform rollout |
| `orchestrator` | IBM Bob watsonx Orchestrate Orchestrator Appliance | Multi-step WXA execution across planning, implementation, testing, documentation, and validation |
| `general-ask` | IBM Bob watsonx Orchestrate General Ask Appliance | WXA question answering with grounded, enterprise-aware guidance |
| `general-code` | IBM Bob watsonx Orchestrate General Code Appliance | WXA implementation artifacts: agent specs, tools, flows, KB configs, connection templates, CI/CD |
| `general-advance` | IBM Bob watsonx Orchestrate General Advance Appliance | Complex enterprise WXO architectures and operating models |
| `watsonx-orchestrate-intelligence` | IBM Bob watsonx Orchestrate Intelligence Appliance | Deep WXO platform intelligence and service analysis |
| `watsonx-orchestrate-advanced` | IBM Bob watsonx Orchestrate Advanced Appliance | Advanced WXO platform and agentic systems design |

In the IBM Bob IDE extension, select the matching project custom mode from the mode selector — the same rules and skills apply.

---

## Project Structure

```
use-cases/watsonx-orchestrate/
├── .env.example                               # Template — copy to .env and fill in credentials and target config
├── .env                                       # Your local credentials and settings (git-ignored)
├── xLaunchpad.sh                              # Managed entry point — always use this to launch
├── bob-auth.sh                                # API key authentication validator
├── bob-watsonx-orchestrate-v<x.y.z>.sh       # Versioned launcher (selected automatically by xLaunchpad)
├── tls-control.sh                             # TLS/CA configuration
├── bob-watsonx-orchestrate-designs/           # Design artifacts (architecture, governance, security reviews)
│   └── quantum-computing-agent-design.md
├── bob-watsonx-orchestrate-store/             # Implementation artifacts (agents, tools, flows, KBs)
├── AGENTS.md                                  # Appliance context for the Bob agent
├── bob-auth.md                                # Authentication flow documentation
└── .bob/
    ├── custom_modes.yaml                      # Project custom modes
    ├── settings.json                          # Bob IDE settings and hooks
    ├── watsonx-orchestrate-tools/             # ADK env helper, documentation links, source analysis
    │   ├── ensure-wxo-adk-env.sh              # ADK virtual environment bootstrap
    │   ├── watsonx-orchestrate-documentation-links.md
    │   └── watsonx-orchestrate-source-analysis.md
    ├── skills/                                # WXA-focused Bob skills
    └── rules-<slug>/                          # Per-mode rules loaded automatically
```

### Artifact Routing

| What you create | Where it goes |
|---|---|
| Architecture, governance plans, security reviews, design documents | `bob-watsonx-orchestrate-designs/<normalized-name>/` |
| Agent YAML/JSON/Python definitions | `bob-watsonx-orchestrate-store/<normalized-name>/agents/` |
| Python tools | `bob-watsonx-orchestrate-store/<normalized-name>/tools/python/` |
| OpenAPI tools | `bob-watsonx-orchestrate-store/<normalized-name>/tools/openapi/` |
| Agentic workflows / flows | `bob-watsonx-orchestrate-store/<normalized-name>/flows/` |
| Knowledge bases | `bob-watsonx-orchestrate-store/<normalized-name>/knowledge_bases/` |
| Connection templates | `bob-watsonx-orchestrate-store/<normalized-name>/connections/` |
| Evaluation tests | `bob-watsonx-orchestrate-store/<normalized-name>/tests/` |

---

## Supported Deployment Targets

| Target | Description |
|---|---|
| `local` | Local ADK development environment using `wxo-adk-env` |
| `ibm-cloud-saas` | IBM watsonx Orchestrate on IBM Cloud (IAM auth, IBM Cloud API key) |
| `aws-saas` | IBM watsonx Orchestrate on AWS via MCSP (MCSP API key / token) |
| `govcloud` | GovCloud-style deployment (MCSP credentials, restricted region) |
| `software-hub` | IBM Software Hub 5.3.x self-managed deployment on OpenShift |
| `cpd` | IBM Cloud Pak for Data deployment |
| `openshift` | Self-managed OpenShift cluster deployment |

---

## Supported Agent Kinds and Tool Types

**Agent kinds:** `native` | `external` | `custom` | `supervisor` | `collaborator`

**Tool types:** `python` | `openapi` | `workflow` | `langflow` | `mcp` | `prebuilt`

**Connection auth types:** `api_key` | `oauth` | `bearer` | `basic` | `client_credentials` | `service_account`

**Knowledge base types:** `built-in` | `milvus` | `elasticsearch` | `uploaded-documents`

**Channel types:** Web Chat, Embedded Chat, API, Phone, Voice

---

## Available Skills

| Skill | Purpose |
|---|---|
| `bob-watsonx-orchestrate-skill` | Core WXA identity — routing, safety, and ADK-first development |
| `ibm-watsonx-orchestrate-agent-design` | Enterprise agent architecture, model strategy, collaboration patterns |
| `ibm-watsonx-orchestrate-adk` | IBM ADK development: agent specs, build, import/export, package, deploy |
| `ibm-watsonx-orchestrate-tool-development` | Python tools, OpenAPI tools, toolkits, MCP server integration |
| `ibm-watsonx-orchestrate-agentic-workflows` | Agentic workflow design, human approval, multi-agent collaboration, scheduling |
| `ibm-watsonx-orchestrate-connections` | External system connections: ServiceNow, Salesforce, Workday, MS Graph, Jira, DB |
| `ibm-watsonx-orchestrate-knowledge-bases` | Knowledge base configuration: built-in, Milvus, Elasticsearch, document upload |
| `ibm-watsonx-orchestrate-deployment` | Deployment, promotion, CI/CD, environment management across all targets |
| `ibm-watsonx-orchestrate-evaluation` | Evaluation, testing, tracing with Langfuse, observability, and quality gates |
| `ibm-watsonx-orchestrate-governance` | Governance, safety controls, compliance, risk reviews, rollback packages |
| `ibm-watsonx-orchestrate-docs-index` | Official IBM watsonx Orchestrate documentation link lookup |
| `ibm-watsonx-orchestrate-governance` | Governance framework, safety, compliance, data classification |
| `create-plan` | Structured planning before implementation |
| `create-skill` | Reusable Bob skill creation |
| `create-mode` | Custom mode creation and validation |
| `configure-mcp` | MCP server setup or diagnosis |
| `build-mcp-server` | Custom MCP server design and scaffolding |
| `mcp-tool-guard` | MCP tool safety guidance |
| `xlsx-insights` | Excel workbook analysis and extraction |
| `git-version-control` | Git command, workflow, branching, recovery, and release guidance |

---

## TLS / Enterprise CA

If your environment uses a custom enterprise certificate authority, set the path in `.env` before authenticating:

```bash
BOB_NODE_EXTRA_CA_CERTS="/path/to/your/enterprise-ca.crt"
WXO_CA_CERT_FILE="/path/to/your/enterprise-ca.crt"
WXO_VERIFY_TLS="true"
```

TLS verification is **always enabled** in this appliance.

---

## Quick-Start Summary

```bash
# 1. Copy and configure credentials and target settings
cp .env.example .env
#    → edit .env: set BOB_API_KEY (and BOB_TEAM_ID if needed)
#    → edit .env: set WXO_TARGET and credentials for your deployment target

# 2. Ensure IBM ADK environment
bash .bob/watsonx-orchestrate-tools/ensure-wxo-adk-env.sh

# 3. Authenticate
bash bob-auth.sh

# 4. Launch
bash xLaunchpad.sh
```
