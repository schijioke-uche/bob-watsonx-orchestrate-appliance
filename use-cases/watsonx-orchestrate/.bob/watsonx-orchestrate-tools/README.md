# WXA Tools Guide

This folder contains local guidance and helper utilities for IBM Bob watsonx Orchestrate Agent (WXA).

## Mandatory ADK policy

For any request to build, import, export, package, deploy, validate, or test IBM watsonx Orchestrate agents, tools, agentic workflows, connections, knowledge bases, or channels, WXA must use IBM ADK in a Python virtual environment named `wxo-adk-env`.

Run or instruct Bob to run:

```bash
.bob/watsonx-orchestrate-tools/ensure-wxo-adk-env.sh
```

## Artifact routing

| Artifact | Route |
|---|---|
| Architecture, governance, design, security review | `bob-watsonx-orchestrate-designs/<normalized-name>/` |
| Agent YAML/JSON/Python definitions | `bob-watsonx-orchestrate-store/<normalized-name>/agents/` |
| Python tools | `bob-watsonx-orchestrate-store/<normalized-name>/tools/python/` |
| OpenAPI tools | `bob-watsonx-orchestrate-store/<normalized-name>/tools/openapi/` |
| Agentic workflows | `bob-watsonx-orchestrate-store/<normalized-name>/flows/` |
| Knowledge bases | `bob-watsonx-orchestrate-store/<normalized-name>/knowledge_bases/` |
| Connection templates | `bob-watsonx-orchestrate-store/<normalized-name>/connections/` |
| Evaluation tests | `bob-watsonx-orchestrate-store/<normalized-name>/tests/` |

## Safety

Never hardcode secrets in agents, tools, flows, connection files, manifests, tests, or README files. Use placeholders and `.env` variables only.
