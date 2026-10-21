# airgap-wxo — Implementation Store

Implementation artifacts for the **watsonx Orchestrate Air-Gap Deployment**.

Design: `bob-watsonx-orchestrate-designs/airgap-wxo-deployment-design.md`

## Directory Structure

```
airgap-wxo/
├── agents/
│   ├── supervisor/          Supervisor (router) agent YAML
│   ├── hr-agent/            HR & Finance domain agent YAML
│   └── ops-agent/           Operations / ERP domain agent YAML
├── tools/
│   ├── leave_balance_tool/  Python tool — HR leave balance
│   ├── policy_search_tool/  Python tool — KB semantic search
│   └── db2_query_tool/      Python tool — Db2 read-only query
├── knowledge-bases/         KB YAML specs
├── connections/             Connection YAML specs (no secrets)
├── ocp-config/              OpenShift manifests (ICSP, namespace)
├── tests/                   Test cases and evaluation prompts
└── README.md                This file
```

## Prerequisites

- IBM Software Hub 5.4 installed on OCP 4.14+
- watsonx Orchestrate service deployed (air-gap)
- watsonx.ai Runtime 2.4 service deployed (local LLM)
- HashiCorp Vault agent sidecar configured
- wxo-adk-env Python virtual environment with ADK (offline)

## Build & Deploy

```bash
# Ensure ADK environment (offline pip mirror)
.bob/watsonx-orchestrate-tools/ensure-wxo-adk-env.sh

# Activate
source wxo-adk-env/bin/activate

# Validate all agents
wxo agent validate --all

# Import to dev
wxo agent import --file agents/ --env $WXO_ENV_DEV

# Import knowledge bases
wxo kb import --file knowledge-bases/ --env $WXO_ENV_DEV

# Run test suite
wxo agent test --suite tests/
```
