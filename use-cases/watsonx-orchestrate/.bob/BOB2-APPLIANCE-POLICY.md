# IBM Bob watsonx Orchestrate Agent (WXA) - Bob Shell 2.x integration policy

Release: BOB2-41.0.0. The supplied working BQCA v2.0.5 appliance is the runtime design benchmark, not a source of unrelated quantum policies.

## Authority and relationships

`xLaunchpad.sh` selects the managed `bob-watsonx-orchestrate-v<installed-Bob-version>.sh` launcher. The launcher loads trusted project environment once, uses `.bob/runtime/bob-v2/runtime.py`, validates Bob 2.x capabilities, and routes into the selected domain custom mode. `AGENTS.md`, `.bob/settings.json` hooks, general rules, mode rules, skills and `.bob/watsonx-orchestrate-tools/` supply the appliance identity together.

All pre-existing domain rules, skill bodies, role definitions, validation gates and artifact boundaries remain authoritative. This integration policy supersedes only incompatible Bob 1.x command examples, malformed custom-mode schema/slugs, and the old authentication/launcher glue. It does not authorize unrelated actions or override the user's current request.

## Artifacts and execution

Designs: `bob-watsonx-orchestrate-designs/`. Code, deployment artifacts and execution evidence: `bob-watsonx-orchestrate-store/`. Do not merge these stores, overwrite pre-existing user artifacts, modify Terraform state, or alter cpd-cli workspaces. For implementation requests, use existing domain tools and create actual files; for design-only requests, create the requested design. Execute only when the request and domain policy authorize it. Report observable progress, outputs, validation results and failures, not private reasoning. Never claim an unexecuted workload passed.

## Runtime contract

Use `bob chat --mode <project-slug> --trust` for interactive work and `bob run --mode <project-slug> --workspace <this-appliance> --trust --accept-license <prompt>` for one-shot work. `--accept-license` is a flag, not a `true`-valued option. Use a matched real user task for resume. Never emit the obsolete top-level chat-mode, allowed-tools, approval-mode, include-directories, prompt-interactive, hide-intermediary-output, or list-sessions switches. Do not silently fall back to a generic mode.

Trusted chat uses session auto-approval by default, matching the supplied benchmark; `BOB2_CHAT_AUTO_APPROVE=0` restores approval prompts. `bob run` pre-approves tools. Neither behavior is a filesystem sandbox: preserve safety gates, avoid destructive/external changes without explicit authorization, and protect credentials. Do not change global Bob settings or shell profiles. Bob itself may manage its own native authentication/trust state.

## Authentication and confidentiality

Use `BOB_API_KEY`, plus `BOB_TEAM_ID` when required by the key. Do not create legacy token/config files. API probes are isolated outside the appliance, and are not user work. Keep `.env` unchanged; never copy its contents into prompts, artifacts, logs or reports. Keep TLS verification enabled and respect enterprise CA configuration. The existing `.bob/bob-v2.env` optional override file is local operator configuration.

## Patch boundary

Current controls belong at repository-root `patches/WXA/` and `patches/BOB2/`; they target `use-cases/watsonx-orchestrate/`. `.bob/patch-backups/` stores rollback evidence; `.bob/patches-applied/` records installed patches. `patches-0/`, `post-upgrade/`, and `bob-parking-lot/` are not part of the active launch chain and must not be applied automatically.

Use the existing `.bob/watsonx-orchestrate-tools/ensure-wxo-adk-env.sh` helper and `wxo-adk-env` for agent/tool builds. WXO Agent Architect is exposed as `wxo-agent-architect`, without replacing its instructions.

<!-- BOB2-45-DISCOVERY-DISPLAY:BEGIN -->
## Discover first; use evidence internally; preserve production presentation
Read `.bob/BOB2-DOCUMENTATION-DISCOVERY-POLICY.md`,
`.bob/BOB2-RETRIEVAL-DISPLAY-POLICY.md` and
`.bob/BOB2-PRODUCTION-DISPLAY-PLAN.md` in every mode, skill and subtask.
Browse documentation libraries, Search documentation/information, and Knowledgebase
retrieval remain PERMITTED when needed. Do not disable tools/MCP or change source
precedence, authorization, local-skill-first, artifact-routing or safety policies.
BEFORE searching, inspect the actual tool schema and discover its libraries unless
a validated catalog for that tool is already held in this running session. Use
only an exact tool-supported selector. Never derive it from a product/mode name or
assume a catalog index name is a library argument. No guessed slug conversion.
On a nonexistent-library error, invalidate that binding, refresh discovery once,
and retry once only with a newly validated selector; never repeat the rejected ID
or loop. Verify product/version relevance. Use an alternate authorized source or
report an unresolved source when no valid binding exists; never fabricate evidence.
Hold catalogs, resolved bindings and retrieval results in the running Bob task
context and use the evidence for the requested answer/design/code/verification.
Raw retrieval payload display is strictly PROHIBITED on terminal/stdout/stderr or
in assistant text: no indices, descriptions, metadata, scores, snippets, pages,
query/result dumps or knowledgebase records. Do not bypass via echo/cat/tee/logs
or another tool/subagent. Do not clear or modify evidence before the agent uses it.
After actual success show only the corresponding status:
`Browse documentation libraries (completed)`;
`Search <phrase searched> documentation (completed)`;
`Knowledgebase information retrieval (completed)`.
Use the actual concise non-secret searched phrase. Preserve original ANSI colors,
icons, indentation, input UI, warning colors and answer formatting. Do not output
literal ANSI instructions, rebuild Bob's footer, or duplicate renderer statuses.
Failures/cancellations remain truthful; give a synthesized sourced answer and keep
approvals/non-retrieval work visible. No extra raw-result cache/log is needed.
Normal Bob context/history limits apply. Mode names/slugs and tool permissions
remain those in `.bob/BOB2-MODE-MAP.json` and the current mode registry.
<!-- BOB2-45-DISCOVERY-DISPLAY:END -->
