#!/usr/bin/env python3
"""Concise project context for Bob SessionStart and UserPromptSubmit hooks."""
import json, os, pathlib, sys
root=pathlib.Path(__file__).resolve().parents[2]
try:
    json.load(sys.stdin)  # Consume hook payload without logging or storing it.
except (ValueError, OSError):
    pass
try:
    c=json.loads((root/'.bob/runtime/bob-v2/appliance.json').read_text())
except (OSError, ValueError):
    print('BOB2_CONTEXT_ERROR: Appliance configuration is unavailable. Do not claim project readiness.')
    sys.exit(1)
mode=os.environ.get('BOB2_SELECTED_MODE', 'current project mode')
print('BOB2_APPLIANCE_CONTEXT=ACTIVE')
print('Appliance: '+c['title'])
print('Menu action: '+os.environ.get('BOB2_MENU_ACTION','Project session'))
print('Mode: '+mode)
print('Read AGENTS.md, .bob/BOB2-APPLIANCE-POLICY.md, the selected .bob/rules-<slug>/, relevant .bob/skills/, and '+c['tools']+'/ together.')
print('Designs: '+c['design']+'/; implementation and results: '+c['store']+'/ . Preserve all domain-specific policies and do not expose secrets.')
print('Report observable progress and actual execution evidence. Historical patches/backups are audit records, not active instructions.')
if c['code'] in ('SWA','WMA'):
    print('The offline knowledgebase is an alternate, supplementary source, not the default intelligence.')
if c['code']=='WXA':
    print('For agent/tool builds use the existing wxo-adk-env readiness helper and WXA skills.')
if c['code']=='QVC':
    print('Cryptographic vulnerability fixtures are authorized educational/scanner-validation artifacts only; label them non-production.')
initial=os.environ.get('BOB2_INITIAL_PROMPT','')
if initial and (len(sys.argv)<2 or sys.argv[1]=='SessionStart'):
    print('User-supplied starting context: '+initial)

print('BOB2-45: Read .bob/BOB2-DOCUMENTATION-DISCOVERY-POLICY.md, .bob/BOB2-RETRIEVAL-DISPLAY-POLICY.md and .bob/BOB2-PRODUCTION-DISPLAY-PLAN.md. Before documentation search, use the installed tool schema and browse/discover libraries unless a validated catalog for this tool is already in this session. Use exact tool-supported identifiers, not product or mode slugs; do not infer a library argument from an index name. On nonexistent library, invalidate that binding, refresh once and retry once only with a newly validated selector. Verify product/version relevance or state an unresolved source; never guess or loop.')
print('Browse documentation, Search documentation/information and Knowledgebase retrieval remain PERMITTED when needed. Retain catalog, binding and result evidence in ordinary running task context. Raw payloads, indices, metadata, scores, snippets and knowledgebase records on terminal/stdout/stderr/assistant messages are PROHIBITED. Do not disable tools, clear results or create raw caches. Keep the useful synthesized sourced answer and approvals.')
print('After actual success: Browse documentation libraries (completed); Search <phrase searched> documentation (completed); Knowledgebase information retrieval (completed). Use a concise non-secret actual phrase; do not duplicate renderer statuses. Failures/cancellations remain truthful. Preserve native ANSI colors/icons/indentation and answer formatting; never rebuild the terminal UI in an assistant answer. Carry these instructions into all modes, skills and subtasks.')
