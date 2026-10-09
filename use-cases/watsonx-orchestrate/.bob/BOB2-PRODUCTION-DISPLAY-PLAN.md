# BOB2-45 Production Retrieval Display Plan

The authoritative instruction is `.bob/BOB2-RETRIEVAL-DISPLAY-POLICY.md`.
This plan supersedes the Search-only presentation plan from Patch 43.

1. Plan and perform authorized Browse documentation, Search documentation or
   information, and Knowledgebase retrieval as needed. All three remain permitted.
   Do not turn off tools/MCP or skip knowledge acquisition to keep the display clean.
2. Let the running Bob session receive and retain the full result in task context.
   Use that evidence internally. Do not change the MCP/model input or clear results
   before use. No new raw-results file/cache is created for display suppression.
3. Suppress raw retrieval output on stdout, stderr and assistant messages: library
   catalogs/indices/descriptions, JSON/arrays, source chunks, snippets, scores,
   metadata, retrieved pages and knowledgebase records must not be dumped.
4. Show the corresponding status once after real success:
   `Browse documentation libraries (completed)`;
   `Search <phrase searched> documentation (completed)`;
   `Knowledgebase information retrieval (completed)`.
   Use a concise actual non-secret phrase. Failed/cancelled operations use truthful
   statuses instead, never a fabricated completion. Do not repeat renderer statuses.
5. Use the retained evidence to produce the requested synthesized answer, design,
   code and validation with necessary citations. Keep approvals, safe actionable
   failures and useful non-retrieval execution output visible.
6. Carry this policy into every rule, skill, mode, policy, plan and delegated task.
   Preserve the original menu, benchmark auth/TLS, mode names, tool permissions,
   environment, domain intelligence, stores and existing source-selection policies.

Launcher integration uses structured bob run events and the tested native
status-header/JSON terminal grammar. Direct Bob/IDE launches bypass the renderer;
model instructions still apply. Unrecognized native layouts require acceptance
validation, not a change to the permit-retrieval/prohibit-raw-display policy.
Bob session history and context limits are unchanged: retention is not guaranteed
forever or RAM-only, and no native history or logs are erased by this patch.

## Patch 45 discovery and styling repair
Before the first relevant search, resolve a current tool-supported documentation
selector through discovery and the actual installed schema. Reuse validated
session context and apply bounded missing-library recovery. Read the dedicated
discovery policy. The adapter does not invent or rewrite MCP arguments.

Recognized retrieval headers retain original ANSI, prefix icons and indentation.
SGR state omitted inside hidden bodies is reconciled without printing the bodies.
Native input borders, the Build Anything chevron and registered appliance-mode
footer title use cyan, while red warnings and all ordinary answer formatting remain
native. This is a targeted display adapter, not a global Bob theme change.
`BOB2_UI_ACCENT=native` opts out of the cyan overlay, not payload filtering.
`NO_COLOR` or `TERM=dumb` disables added colors. Nonterminal output adds no colors.
One-shot sessions retain the Patch43 structured renderer; this patch does not
claim to recreate every aspect of native `--format pretty` output.

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
