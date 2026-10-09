#!/usr/bin/env python3
"""BOB2-45 terminal-only retrieval rendering; never rewrites MCP/model input.

Structured bob run output: suppress Browse/Search/knowledgebase tool-result bodies
by correlated tool IDs. Native chat/resume: retain Bob and a PTY; collapse the
observed status-header plus balanced JSON/array grammar, including library
metadata. Recognizable unframed retrieval envelopes are also withheld. Normal
answers, citations, approvals and non-retrieval execution output stay visible.
No raw transcript/cache files are created. This is not a universal TUI emulator
or a replacement for the explicit project-wide retrieval display policy.
"""
from __future__ import annotations
import codecs
import errno
import fcntl
import json
import os
import pty
import re
import selectors
import signal
import struct
import subprocess
import sys
import termios
import time
import tty
from pathlib import Path
from terminal_style import SgrState, NativeCyanAccent, styled_header, accent_enabled, positions

MAX_RECORD = 16 * 1024 * 1024
MAX_DEPTH = 256
ANSI = re.compile(r'\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(?:\x07|\x1b\\)|(?![\[\]])[ -/]*[0-~])')
HEADER = re.compile(
    r'^\s*(?:[\u2500-\u27ff\u2800-\u28ff*+>\-]\s*)?'
    r'(?P<label>Browse\s+documentation(?:\s+libraries)?|Search\b[^\r\n]*?|'
    r'Knowledge[\s_-]*base(?:\s+information)?\s+(?:retrieval|used)|'
    r'Retrieve\s+knowledge[\s_-]*base\s+information)\s*'
    r'\((?P<status>completed|complete|success|succeeded|failed|error|cancelled|canceled|timed out|executing\.\.\.|executing|running|in progress|started|pending)\)\s*(?P<tail>.*)$', re.I)
STATUS_SUCCESS = {'success', 'completed', 'complete', 'ok', 'succeeded'}
STATUS_FAILURE = {'error', 'failed', 'failure', 'cancelled', 'canceled', 'timeout', 'timed_out', 'rejected'}
KB_PATTERN = re.compile(r'knowledge[\s_/-]*base|(?:^|[\s_/:.\-])kb(?:$|[\s_/:.\-])', re.I)


class DisplayError(Exception):
    pass


class RelayTermination(Exception):
    def __init__(self, signum: int):
        self.signum = signum


def termination_handlers() -> dict:
    def terminate(signum, unused_frame):
        raise RelayTermination(signum)
    return {sig: signal.signal(sig, terminate) for sig in (signal.SIGTERM, signal.SIGHUP)}


def restore_handlers(handlers: dict) -> None:
    for sig, handler in handlers.items():
        signal.signal(sig, handler)


def clean(text: str) -> str:
    return ANSI.sub('', text)


def redact(text: str, env: dict[str, str]) -> str:
    for key in ('BOB_API_KEY', 'BOBSHELL_API_KEY'):
        value = env.get(key, '')
        if value:
            text = text.replace(value, '[REDACTED]')
    return text


def safe_phrase(text: str, maximum: int = 180) -> str:
    """A bounded single-line label from request metadata, NEVER result content."""
    text = clean(text)
    text = ''.join(c for c in text if c.isprintable() or c in '\n\r\t')
    text = re.sub(r'\s+', ' ', text).strip()
    # Hide common credential assignments even in a mistakenly secret-bearing query.
    text = re.sub(r'(?i)\b(api[_ -]?key|access[_ -]?token|password|secret)\s*[:=]\s*[^ ,;]+', r'\1=[REDACTED]', text)
    text = re.sub(r'(?i)\bbearer\s+[^ ,;]+', 'Bearer [REDACTED]', text)
    return text if len(text) <= maximum else text[:maximum-3].rstrip() + '...'


def search_label(phrase: str) -> str:
    phrase = safe_phrase(phrase)
    phrase = re.sub(r'^Search\s+', '', phrase, flags=re.I)
    phrase = re.sub(r'\s*\((?:completed|failed|cancelled)\)\s*$', '', phrase, flags=re.I)
    phrase = re.sub(r'(?:^|\s+)documentation\s*$', '', phrase, flags=re.I).strip()
    return 'Search ' + (phrase + ' ' if phrase else '') + 'documentation'


def header_label(value: str) -> str:
    if value.lower().startswith('browse'):
        return 'Browse documentation libraries'
    if value.lower().startswith('search'):
        return search_label(value)
    if KB_PATTERN.search(value):
        return 'Knowledgebase information retrieval'
    return search_label(value)


def status_suffix(status: str) -> str:
    status = status.lower().replace(' ', '_')
    if status in STATUS_SUCCESS:
        return 'completed'
    if status in {'cancelled', 'canceled'}:
        return 'cancelled'
    if status in STATUS_FAILURE or status == 'timed_out':
        return 'failed'
    return 'status unrecognized'


def envelope_kind(text: str) -> str:
    """Recognize retrieval envelopes, including escaped MCP text wrappers.

    This is a conservative display signature, not a query/content classifier.
    Ordinary application JSON with no retrieval schema remains visible.
    """
    plain = clean(text).replace('\\"', '"')
    if re.search(r'"(?:indices|documentation_libraries)"\s*:', plain):
        return 'browse'
    if re.search(r'"libraries"\s*:', plain) and re.search(r'"(?:description|documentation|name)"\s*:', plain):
        return 'browse'
    if re.search(r'"(?:knowledgebase_results|knowledge_base_results|retrieval_results)"\s*:', plain):
        return 'knowledgebase'
    if re.search(r'"(?:documents|matches|chunks)"\s*:', plain) and re.search(r'"(?:content|text|metadata|score|source)"\s*:', plain):
        return 'knowledgebase'
    if re.search(r'"results"\s*:', plain) and re.search(r'"(?:query|content|snippet|metadata|score|rerank_score|section_path)"\s*:', plain):
        return 'search'
    if re.search(r'"name"\s*:\s*"docs[_-]', plain) and re.search(r'"description"\s*:',plain):
        return 'browse'
    if re.search(r'"(?:score|rerank_score)"\s*:',plain) and re.search(r'"(?:content|snippet)"\s*:',plain):
        return 'search'
    return ''


def object_envelope_kind(value) -> str:
    if isinstance(value,str):
        return envelope_kind(value)
    if isinstance(value,dict):
        if set(value) & {'indices','documentation_libraries'}:return 'browse'
        if set(value) & {'knowledgebase_results','knowledge_base_results','retrieval_results','documents','matches','chunks'}:return 'knowledgebase'
        if 'results' in value:return 'search'
        # A shallow inspection of MCP text wrappers; do not serialize/cache bodies.
        parts=value.get('content',[])
        if isinstance(parts,list):
            for part in parts[:32]:
                if isinstance(part,dict) and isinstance(part.get('text'),str):
                    category=envelope_kind(part['text'])
                    if category:return category
    return ''


class RetrievalTextFilter:
    """Incremental native/stderr display filter with bounded transient memory.

    Recognized tool-status headers arm complete JSON/array suppression, irrespective
    of schema. Outside those headers, balanced JSON is buffered and recognizable
    retrieval envelopes are withheld. Input, MCP and Bob context are untouched.
    """
    def __init__(self, accent=None):
        self.source_sgr = SgrState()
        self.display_sgr = SgrState()
        self.accent = accent or NativeCyanAccent()
        self.pending = ''
        self.state = 'normal'
        self.stack: list[str] = []
        self.quoted = False
        self.escaped = False
        self.ansi = ''
        self.bytes_hidden = 0
        self.omitted = 0
        self.in_fence = False
        self.capture: list[str] = []
        self.capturing = False
        self.fence = ''

    def _start(self, text: str, capture: bool = False) -> str:
        self.state = 'json'
        self.stack = []
        self.quoted = self.escaped = False
        self.ansi = ''
        self.bytes_hidden = 0
        self.capture = []
        self.capturing = capture
        return self._consume_json(text)

    def _consume_json(self, text: str) -> str:
        for i, ch in enumerate(text):
            self.bytes_hidden += 1
            if self.bytes_hidden > MAX_RECORD:
                raise DisplayError('Retrieval display block exceeds the supported size; raw output withheld.')
            if self.ansi:
                self.ansi += ch
                if len(self.ansi) == 2 and ch not in '[]':
                    self.ansi = ''
                elif self.ansi.startswith('\x1b[') and len(self.ansi) > 2 and '@' <= ch <= '~':
                    self.ansi = ''
                elif self.ansi.startswith('\x1b]') and (ch == '\x07' or self.ansi.endswith('\x1b\\')):
                    self.ansi = ''
                elif len(self.ansi) > 4096:
                    raise DisplayError('Unsupported escape sequence inside retrieval output; raw output withheld.')
                continue
            if ch == '\x1b':
                self.ansi = ch
                continue
            if self.quoted:
                if self.escaped:
                    self.escaped = False
                elif ch == '\\':
                    self.escaped = True
                elif ch == '"':
                    self.quoted = False
                continue
            if ch == '"':
                self.quoted = True
            elif ch in '{[':
                self.stack.append(ch)
                if len(self.stack) > MAX_DEPTH:
                    raise DisplayError('Retrieval nesting exceeds the display limit; raw output withheld.')
            elif ch in '}]':
                if not self.stack or self.stack[-1] != {'}':'{', ']':'['}[ch]:
                    raise DisplayError('Unbalanced retrieval display block; raw output withheld.')
                self.stack.pop()
                if not self.stack:
                    if self.capturing:
                        self.capture.append(text[:i+1])
                    body = ''.join(self.capture) if self.capturing else ''
                    hide = not self.capturing or bool(envelope_kind(body))
                    self.capture = []
                    self.capturing = False
                    self.state = 'after-payload' if hide else 'normal'
                    if hide:
                        self.omitted += 1
                        self.fence = ''
                        visible = ''
                    else:
                        visible, self.fence = self.fence + body, ''
                    tail = text[i+1:]
                    # Raw transport tail goes through the same grammar, never blindly printed.
                    return visible + (self._line(tail) if tail else '')
        if self.capturing:
            self.capture.append(text)
        return ''

    def _line(self, text: str) -> str:
        if self.state == 'json':
            return self._consume_json(text)
        plain = clean(text)
        if self.state == 'after-payload':
            if not plain.strip() or (self.in_fence and plain.strip() == '```'):
                if plain.strip() == '```':
                    self.in_fence = False
                return ''
            # Inspect additional envelopes, but preserve a requested final JSON
            # artifact that is not a retrieval payload.
            if plain.lstrip().startswith(('{', '[')):
                return self._start(text, capture=True)
            self.state = 'normal'
        if self.state == 'after-header':
            if not plain.strip():
                return ''
            if plain.strip().lower() in ('```json', '```'):
                self.in_fence = True
                return ''
            if plain.lstrip().startswith(('{', '[')):
                return self._start(text)
            # Keep answers and interactive approval questions visible. Unframed,
            # non-JSON prose cannot safely be classified as result vs. answer here.
            self.state = 'normal'
        match = HEADER.match(plain.rstrip('\r\n'))
        if match:
            self.state = 'after-header'
            self.stack = []
            self.quoted = self.escaped = False
            status = match.group('status').lower()
            # Preserve native progress and status styling; never claim completion
            # for an executing operation. Canonical labels change text, not SGR.
            suffix = status if status in {'executing...', 'executing', 'running', 'in progress', 'started', 'pending'} else status_suffix(status)
            line, raw_tail = styled_header(text, match, header_label(match.group('label')), suffix)
            tail = match.group('tail')
            if tail.startswith(('{', '[')):
                return line + self._start(raw_tail)
            return line
        # Buffer a possible fenced raw envelope, without changing normal code fences.
        if plain.strip().lower() == '```json' and not self.fence:
            self.fence = text
            self.in_fence = True
            return ''
        candidate = plain.lstrip()
        if candidate.startswith('{') or re.match(r'^\[\s*(?:\{|\[|"|\]|$)', candidate):
            return self._start(text, capture=True)
        prefix, self.fence = self.fence, ''
        if plain.strip() == '```':
            self.in_fence = False
        return prefix + text

    def _dispatch(self, text: str) -> str:
        initial = self.source_sgr.clone()
        rendered = self._line(text)
        rendered = self.accent.apply(rendered, initial)
        self.source_sgr.apply(text)
        self.display_sgr.apply(rendered)
        if self.source_sgr.values != self.display_sgr.values:
            # Hidden payloads can contain a reset or style change needed by the
            # next native footer. Replay state, never OSC controls or body text.
            restore = self.source_sgr.restore()
            rendered += restore
            self.display_sgr.apply(restore)
        return rendered

    def feed(self, text: str) -> str:
        self.pending += text
        result = []
        while '\n' in self.pending:
            line, self.pending = self.pending.split('\n', 1)
            result.append(self._dispatch(line + '\n'))
        if len(self.pending) > MAX_RECORD:
            raise DisplayError('Terminal output line exceeds the display limit; raw output withheld.')
        return ''.join(result)

    def idle(self) -> str:
        """Flush ordinary non-newline approval prompts, never partial retrieval data."""
        if not self.pending:
            return ''
        plain = clean(self.pending).lstrip()
        if not plain:
            return ''
        if self.pending.count('\x1b') > len(ANSI.findall(self.pending)):
            return ''
        if self.accent.hold_partial(self.pending):
            return ''
        if self.state == 'json':
            return ''
        if self.state in {'after-header','after-payload'} and (not plain or plain.startswith(('{','[','```'))):
            return ''
        if plain.startswith(('{','```')) or '```'.startswith(plain) or re.match(r'^\[\s*(?:\{|\[|"|\]|$)', plain):
            return ''
        label = re.sub(r'^[\u2500-\u27ff\u2800-\u28ff*+>\-]\s*','',plain).lower()
        for start in ('search','browse','knowledgebase','knowledge base','retrieve knowledge'):
            if label and (label.startswith(start) or start.startswith(label)):
                return ''
        value, self.pending = self.pending, ''
        return self._dispatch(value)

    def finish(self) -> str:
        value, self.pending = self.pending, ''
        result = self._dispatch(value) if value else ''
        if self.state == 'json' or self.stack:
            raise DisplayError('Output ended inside a retrieval/JSON block; raw output withheld.')
        result += self.fence
        self.fence = ''
        trailing = self.accent.flush()
        self.display_sgr.apply(trailing)
        result += trailing
        if self.source_sgr.values != self.display_sgr.values:
            result += self.source_sgr.restore()
        return result


# Compatibility for callers/tests importing the Patch43 class name.
SearchTextFilter = RetrievalTextFilter


def scrub_assistant(text: str) -> str:
    """Remove result envelopes, not the colors of the surrounding answer."""
    plain = clean(text)
    decoder = json.JSONDecoder()
    spans = []
    offset = 0
    for match in re.finditer(r'[\{\[]', plain):
        start = match.start()
        if start < offset:
            continue
        try:
            _, consumed = decoder.raw_decode(plain[start:])
        except (ValueError, RecursionError):
            continue
        end = start + consumed
        if envelope_kind(plain[start:end]):
            spans.append((start,end))
            offset = end
    points = positions(text)
    for start,end in reversed(spans):
        a,b = points[start],points[end-1]+1
        before = SgrState();before.apply(text[:a])
        after = before.clone();after.apply(text[a:b])
        restore = after.restore() if before.values != after.values else ''
        text = text[:a]+restore+text[b:]
    if envelope_kind(clean(text)):
        return ''
    # Empty fences are harmless formatting; never strip ANSI across the answer.
    text = re.sub(r'```(?:json)?\s*```', '', text, flags=re.I)
    view = RetrievalTextFilter()
    try:
        return view.feed(text) + view.finish()
    except DisplayError:
        return ''


def _mapping(value) -> dict:
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except (ValueError, RecursionError):
            return {}
    return value if isinstance(value, dict) else {}


def _request_layers(event: dict) -> list[dict]:
    layers = [event]
    for layer in list(layers):
        for key in ('parameters','input','arguments','args'):
            child = _mapping(layer.get(key))
            if child:
                layers.append(child)
    # MCP arguments may be JSON encoded once or twice; do not inspect output.
    for _ in range(3):
        extra = []
        for layer in layers:
            for key in ('parameters','input','arguments','args'):
                child = _mapping(layer.get(key))
                if child and child not in layers and child not in extra:
                    extra.append(child)
        if not extra:
            break
        layers.extend(extra)
    return layers[:32]


def query_phrase(layers: list[dict]) -> str:
    for layer in reversed(layers):
        for key in ('query','search_phrase','search_query','searchTerm','search_term','phrase','question','regex','pattern'):
            value = layer.get(key)
            if isinstance(value,str) and value.strip():
                return safe_phrase(value)
        for key in ('queries','questions','search_queries'):
            values = layer.get(key)
            if isinstance(values, list):
                phrases = []
                for item in values[:3]:
                    value = item if isinstance(item,str) else item.get('query','') if isinstance(item,dict) else ''
                    if isinstance(value,str) and value.strip():
                        phrases.append(safe_phrase(value))
                if phrases:
                    return safe_phrase('; '.join(phrases))
    return ''


def tool_metadata(event: dict, config: dict) -> tuple[bool, str]:
    """Classify operation identities/paths separately from the searched phrase."""
    layers = _request_layers(event)
    identities = []
    paths = []
    for layer in layers:
        for key in ('tool_name','server_name','name','display_name','title'):
            value = layer.get(key)
            if isinstance(value,str):
                identities.append(value)
        for key in ('path','uri','url','resource','file','file_path'):
            value = layer.get(key)
            if isinstance(value,str):
                paths.append(value)
        for key in ('paths','files'):
            value = layer.get(key)
            if isinstance(value,list):
                for item in value:
                    if isinstance(item,str):paths.append(item)
                    elif isinstance(item,dict):
                        paths.extend(v for k,v in item.items() if k in ('path','uri') and isinstance(v,str))
    identity = ' '.join(identities)
    normalized = re.sub(r'(?<=[a-z])(?=[A-Z])', '_', identity).lower()
    normalized = re.sub(r'[^a-z0-9]+',' ',normalized).strip()
    # A known documentation server is a retrieval provider, even when a generic
    # MCP wrapper calls list_indices, read_resource, get_document, show_sections.
    docs = bool(re.search(r'\b(?:docs?|documentation|wxdocs|manuals?)\b',normalized))
    browse = bool(re.search(r'\b(?:browse|list|enumerate|discover)\b',normalized) and docs) or bool(re.search(r'\b(?:list|get|enumerate|discover)\b',normalized) and re.search(r'\b(?:indices|indexes|libraries|collections|sources|catalogs)\b',normalized))
    if browse:
        return True,'Browse documentation libraries'
    shell_kb = any(isinstance(layer.get('command'),str) and KB_PATTERN.search(layer['command']) and re.search(r'\b(?:cat|head|tail|sed|rg|grep|search|query|retrieve|lookup|read)\b',layer['command']) for layer in layers)
    kb = bool(KB_PATTERN.search(identity) or KB_PATTERN.search(' '.join(paths)) or shell_kb)
    if kb:
        return True,'Knowledgebase information retrieval'
    search = bool(re.search(r'\b(?:search|lookup|retrieve|retrieval|query|grep)\b',normalized))
    if search:
        phrase = query_phrase(layers)
        if not phrase:
            title = next((event.get(k) for k in ('display_name','title') if isinstance(event.get(k),str) and event[k].lower().startswith('search ')), '')
            if title:
                phrase=title
            elif re.search(r'watsonx|\bwxo\b|wxdocs',normalized):phrase='IBM Watsonx'
            elif 'openshift' in normalized:phrase='Red Hat OpenShift'
            elif 'ansible' in normalized:phrase='Red Hat Ansible'
            elif re.search(r'software hub|\bcpd\b',normalized):phrase='IBM Software Hub'
            elif 'terraform' in normalized:phrase='Terraform'
            elif 'websphere' in normalized:phrase='IBM WebSphere'
            else:phrase=config.get('search_label','')
        return True,search_label(phrase)
    if docs and re.search(r'\b(?:read|get|fetch|show|list|access|use|open)\b',normalized):
        return True,'Knowledgebase information retrieval'
    return False,''


class EventRenderer:
    def __init__(self, config: dict, env: dict, write, error):
        self.config, self.env, self.write, self.error = config, env, write, error
        self.calls: dict[str, tuple[bool, str]] = {}
        self.done: set[str] = set()
        self.status_lines: set[str] = set()
        self.last_assistant = ''
        self.final = False
        self.final_success = False
        self.failed = False
        self.unknown = 0

    def say(self, value, diagnostic=False, status=False):
        if not isinstance(value,str) or not value.strip():
            return
        value = redact(scrub_assistant(value),self.env)
        if not status:
            value = '\n'.join(line for line in value.splitlines() if clean(line).strip() not in self.status_lines)
        if not value.strip():
            return
        if status:
            self.status_lines.add(clean(value).strip())
            if accent_enabled(self.env, sys.stdout.isatty()):
                label, sep, ending = value.rpartition(' (')
                if sep:
                    shade = '\x1b[31m' if ending.startswith(('failed', 'cancelled')) else '\x1b[90m'
                    value = '\x1b[36m' + label + '\x1b[39m (' + shade + ending + '\x1b[0m'
        (self.error if diagnostic else self.write)(value.rstrip('\n') + '\n')

    def event(self,row: dict) -> None:
        kind=row.get('type')
        if not isinstance(kind,str):
            raise DisplayError('NDJSON event has no type; raw output withheld.')
        if isinstance(row.get('data'),dict):
            row=dict(row,**{k:v for k,v in row['data'].items() if k != 'type'})
        if kind=='tool_use':
            ident=str(row.get('tool_id',''))
            if not ident:
                raise DisplayError('Tool event has no tool_id; raw output withheld.')
            if ident in self.calls:
                raise DisplayError('Duplicate tool identity in stream; raw output withheld.')
            if len(self.calls)>=10000:
                raise DisplayError('Too many tool calls for the display session.')
            self.calls[ident]=tool_metadata(row,self.config)
        elif kind=='tool_result':
            ident=str(row.get('tool_id',''))
            if ident in self.done:
                return
            match=self.calls.get(ident)
            if match is None:
                self.unknown+=1
                return  # Never print an unpaired result or guess it succeeded.
            self.done.add(ident)
            status=str(row.get('status','')).lower()
            output=row.get('output')
            if row.get('is_error') is True or (isinstance(output,dict) and output.get('isError') is True):
                status='error'
            retrieval,label=match
            if not retrieval and object_envelope_kind(output):
                # Unknown wrapper returned a recognizable result envelope. Use a
                # safe category, never reconstruct a query from retrieved content.
                category=object_envelope_kind(output)
                label='Browse documentation libraries' if category=='browse' else 'Knowledgebase information retrieval' if category=='knowledgebase' else search_label('')
                retrieval=True
            if retrieval:
                suffix=status_suffix(status)
                self.say(label+' ('+suffix+')',status=True)
                if suffix!='completed':self.failed=True
                return  # Result body stays within Bob, never rewritten here.
            if status in STATUS_FAILURE:
                self.failed=True
                self.say(row.get('error') or 'Tool execution failed.',diagnostic=True)
            elif isinstance(output,str):
                self.say(output)
        elif kind=='message':
            if row.get('role')!='assistant' or row.get('isReasoning'):
                return
            text=row.get('content','')
            if isinstance(text,list):
                text='\n'.join(p.get('text','') for p in text if isinstance(p,dict) and p.get('type')=='text' and isinstance(p.get('text'),str))
            if isinstance(text,str) and text.strip():
                self.say(text);self.last_assistant=text
        elif kind=='error':
            self.failed=True
            self.say(row.get('message') or 'Bob reported an execution error.',diagnostic=True)
        elif kind=='result':
            self.final=True
            status=str(row.get('status','')).lower()
            self.final_success=status in STATUS_SUCCESS
            if not self.final_success:self.failed=True
            text=row.get('last_message','')
            if text!=self.last_assistant:self.say(text)
        else:
            self.unknown+=1


def stop(process: subprocess.Popen) -> None:
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()


def emit(text: str, stream=sys.stdout) -> None:
    if text:
        stream.write(text)
        stream.flush()


def run_stream(command: list[str], root: Path, env: dict, config: dict) -> int:
    """Consume stdout AFTER Bob's agent has received its complete tool results."""
    process = subprocess.Popen(command, cwd=str(root), env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True)
    renderer = EventRenderer(config, env, emit, lambda t: emit(t, sys.stderr))
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ, 'out')
    selector.register(process.stderr, selectors.EVENT_READ, 'err')
    decoders = {key:codecs.getincrementaldecoder('utf-8')('replace') for key in ('out','err')}
    pending = ''
    errors = RetrievalTextFilter()
    handlers = termination_handlers()
    try:
        while selector.get_map():
            ready = selector.select(0.1)
            if not ready:
                emit(redact(errors.idle(), env), sys.stderr)
            for key, _ in ready:
                data = os.read(key.fileobj.fileno(), 65536)
                channel = key.data
                text = decoders[channel].decode(data, final=not data)
                if channel == 'err':
                    emit(redact(errors.feed(text), env), sys.stderr)
                else:
                    pending += text
                    while '\n' in pending:
                        line, pending = pending.split('\n', 1)
                        if len(line) > MAX_RECORD:
                            raise DisplayError('NDJSON record exceeds the display limit.')
                        if not line.strip():
                            continue
                        try:
                            row = json.loads(line)
                        except ValueError as exc:
                            raise DisplayError('Bob returned non-NDJSON stdout; raw output withheld. Check bob run --help for stream-json support.') from exc
                        if not isinstance(row, dict):
                            raise DisplayError('Invalid NDJSON event object; raw output withheld.')
                        renderer.event(row)
                    if len(pending) > MAX_RECORD:
                        raise DisplayError('NDJSON record exceeds the display limit.')
                if not data:
                    selector.unregister(key.fileobj)
                    key.fileobj.close()
        if pending.strip():
            try:
                row = json.loads(pending)
            except ValueError as exc:
                raise DisplayError('Truncated NDJSON event; raw output withheld.') from exc
            if not isinstance(row, dict):
                raise DisplayError('Invalid final NDJSON event.')
            renderer.event(row)
        emit(redact(errors.finish(), env), sys.stderr)
        rc = process.wait()
        if not renderer.final:
            emit('[BOB2-45] No final result event received; completion is not verified.\n', sys.stderr)
        if renderer.unknown:
            emit(f'[BOB2-45] Withheld {renderer.unknown} unclassified event(s); no raw fallback.\n', sys.stderr)
        return rc if rc else (2 if not renderer.final else 0 if renderer.final_success else 1)
    except RelayTermination as exc:
        stop(process)
        return 128 + exc.signum
    except DisplayError as exc:
        emit('[BOB2-45] DISPLAY ERROR: ' + str(exc) + '\n', sys.stderr)
        stop(process)
        return 2
    finally:
        restore_handlers(handlers)
        selector.close()
        stop(process)


def chat_terminal(command: list[str], root: Path, env: dict, config: dict | None = None) -> int:
    """Native chat stays native: same argv, stdin, approvals, resume and workspace.

    A PTY is used only when the caller has a terminal. All non-retrieval bytes pass
    through; resize and input are relayed. Terminal state is restored on exits.
    """
    interactive = sys.stdin.isatty() and sys.stdout.isatty()
    saved = None
    master = slave = None
    selector = selectors.DefaultSelector()
    old_winch = None
    proc = None
    view = RetrievalTextFilter(NativeCyanAccent(config, accent_enabled(env, interactive)))
    decoder = codecs.getincrementaldecoder('utf-8')('replace')
    handlers = termination_handlers()
    try:
        if interactive:
            master, slave = pty.openpty()
            stdin_fd = sys.stdin.fileno()
            saved = termios.tcgetattr(stdin_fd)
            def resize(*unused):
                try:
                    size = fcntl.ioctl(stdin_fd, termios.TIOCGWINSZ, bytes(8))
                    fcntl.ioctl(master, termios.TIOCSWINSZ, size)
                except OSError:
                    pass
            resize()
            def session():
                os.setsid()
                fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
            proc = subprocess.Popen(command, cwd=str(root), env=env, stdin=slave,
                                    stdout=slave, stderr=slave, preexec_fn=session)
            os.close(slave); slave = None
            old_winch = signal.signal(signal.SIGWINCH, resize)
            tty.setraw(stdin_fd)
            selector.register(stdin_fd, selectors.EVENT_READ, 'input')
            output = master
        else:
            proc = subprocess.Popen(command, cwd=str(root), env=env, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, start_new_session=True)
            output = proc.stdout.fileno()
        selector.register(output, selectors.EVENT_READ, 'output')
        eof = False
        while not eof:
            ready = selector.select(0.04)
            if not ready:
                emit(redact(view.idle(), env))
                if proc.poll() is not None:
                    # Drain any final data before considering the child finished.
                    ready = selector.select(0)
                    if not ready:
                        break
            for key, _ in ready:
                if key.data == 'input':
                    data = os.read(key.fd, 65536)
                    if not data:
                        selector.unregister(key.fd)
                        os.write(master, b'\x04')
                    else:
                        offset = 0
                        while offset < len(data):
                            offset += os.write(master, data[offset:])
                    continue
                try:
                    data = os.read(key.fd, 65536)
                except OSError as exc:
                    if exc.errno != errno.EIO:
                        raise
                    data = b''
                if not data:
                    eof = True
                emit(redact(view.feed(decoder.decode(data, final=not data)), env))
        emit(redact(view.finish(), env))
        return proc.wait()
    except RelayTermination as exc:
        if proc:
            stop(proc)
        return 128 + exc.signum
    except DisplayError as exc:
        emit('\n[BOB2-45] DISPLAY ERROR: ' + str(exc) + '\n', sys.stderr)
        if proc:
            stop(proc)
        return 2
    finally:
        restore_handlers(handlers)
        if saved is not None:
            termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, saved)
        if old_winch is not None:
            signal.signal(signal.SIGWINCH, old_winch)
        selector.close()
        if proc:
            stop(proc)
        if master is not None:
            os.close(master)
        if slave is not None:
            os.close(slave)
