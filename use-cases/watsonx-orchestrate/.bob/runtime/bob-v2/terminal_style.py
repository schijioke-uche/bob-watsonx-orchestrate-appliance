#!/usr/bin/env python3
"""ANSI-preserving text surgery and narrowly scoped native Bob cyan accents.

Not a terminal emulator or a Bob theme configuration. Preserve upstream bytes
except the explicit label/status replacement and the three requested UI accents.
Never promote escape/control sequences from a hidden retrieval payload to text.
"""
from __future__ import annotations
import re

ANSI = re.compile(r'\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(?:\x07|\x1b\\)|(?![\[\]])[ -/]*[0-~])')
SGR = re.compile(r'\x1b\[([0-9:;]*)m')
CYAN = '\x1b[36m'


def clean(text: str) -> str:
    return ANSI.sub('', text)


class SgrState:
    """Track common ECMA-48 attributes, including indexed and RGB colors."""
    def __init__(self):
        self.values: dict[str, str] = {}

    def clone(self):
        result = SgrState()
        result.values = dict(self.values)
        return result

    def apply(self, text: str) -> None:
        for match in SGR.finditer(text):
            params = match.group(1).split(';')
            i = 0
            while i < len(params):
                value = params[i] or '0'
                try:
                    code = int(value.split(':', 1)[0])
                except ValueError:
                    i += 1
                    continue
                if code in (38, 48, 58) and ':' not in value and i+1 < len(params):
                    count = 2 if params[i+1] == '5' else 4 if params[i+1] == '2' else 0
                    if count and i+count < len(params):
                        value = ';'.join(params[i:i+count+1])
                        i += count
                if code == 0:
                    self.values.clear()
                elif code in (38, 48, 58):
                    self.values[{38:'fg',48:'bg',58:'underline-color'}[code]] = value
                elif 30 <= code <= 37 or 90 <= code <= 97:
                    self.values['fg'] = value
                elif 40 <= code <= 47 or 100 <= code <= 107:
                    self.values['bg'] = value
                elif code in (39,49,59):
                    self.values.pop({39:'fg',49:'bg',59:'underline-color'}[code],None)
                elif code in (1,2,3,4,5,6,7,8,9,20,21,26,51,52,53):
                    name={1:'bold',2:'faint',3:'italic',4:'underline',5:'blink',6:'blink',7:'inverse',8:'conceal',9:'strike',20:'font-style',21:'underline',26:'proportional',51:'frame',52:'frame',53:'overline'}[code]
                    if value == '4:0':self.values.pop(name,None)
                    else:self.values[name]=value
                elif code in (22,23,24,25,27,28,29,50,54,55):
                    names={22:('bold','faint'),23:('italic','font-style'),24:('underline',),25:('blink',),27:('inverse',),28:('conceal',),29:('strike',),50:('proportional',),54:('frame',),55:('overline',)}[code]
                    for name in names:self.values.pop(name,None)
                elif 10 <= code <= 19:
                    if code==10:self.values.pop('font',None)
                    else:self.values['font']=value
                elif 60 <= code <= 65:
                    if code==65:self.values.pop('ideogram',None)
                    else:self.values['ideogram']=value
                # Unsupported SGR stays intact in visible output, but is not
                # replayed from hidden data. This is not a full terminal emulator.
                i += 1

    def restore(self) -> str:
        return '\x1b[0m' + ('\x1b['+';'.join(self.values.values())+'m' if self.values else '')

    def foreground(self) -> str:
        return '\x1b['+self.values.get('fg','39')+'m'


def positions(text: str) -> list[int]:
    indices = []
    cursor = 0
    for match in ANSI.finditer(text):
        indices.extend(range(cursor,match.start()))
        cursor = match.end()
    indices.extend(range(cursor,len(text)))
    return indices


def splice(text: str, start: int, end: int, replacement: str) -> str:
    """Replace visible characters, retaining their ANSI transitions for the suffix."""
    points = positions(text)
    if not 0 <= start <= end <= len(points):
        raise ValueError('Invalid visible span')
    if start==end:
        at=points[start] if start<len(points) else len(text)
        return text[:at]+replacement+text[at:]
    a,b=points[start],points[end-1]+1
    if clean(text[a:b]) == replacement:
        return text
    controls=''.join(ANSI.findall(text[a:b]))
    return text[:a]+replacement+controls+text[b:]


def styled_header(text: str, match, label: str, status: str) -> tuple[str,str]:
    """Normalize only the two semantic fields; leave icons/spacing/styles alone.

    Split an inline payload before trimming or normalizing, so no result characters
    are passed through as part of the styled heading. ANSI suffixes are retained.
    """
    tail=match.group('tail')
    if tail:
        points=positions(text)
        at=points[match.start('tail')]
        heading,raw_tail=text[:at],text[at:]
        # Raw payload may finish the line; give the status its original newline.
        heading=heading.rstrip(' \t')+'\n'
    else:
        heading,raw_tail=text,''
    for name,replacement in (('status',status),('label',label)):
        heading=splice(heading,match.start(name),match.end(name),replacement)
    return heading,raw_tail


def recolor_span(text: str, start: int, end: int, initial: SgrState) -> str:
    """Change foreground only. Keep background/bold/cursors/hyperlinks and suffix."""
    if start==end:return text
    points=positions(text)
    if not 0 <= start < end <= len(points):return text
    a,b=points[start],points[end-1]+1
    state=initial.clone();state.apply(text[:a])
    result=[text[:a],CYAN]
    cursor=a
    for match in ANSI.finditer(text,a,b):
        result.append(text[cursor:match.end()])
        state.apply(match.group())
        if SGR.fullmatch(match.group()):result.append(CYAN)
        cursor=match.end()
    result.extend([text[cursor:b],state.foreground(),text[b:]])
    return ''.join(result)


class NativeCyanAccent:
    """Only known mode footer titles, the Build Anything chevron and colored rules.

    No global purple-to-cyan replacement. No renaming or changes to mode behavior.
    A no-color terminal or native override receives no added color sequences.
    """
    def __init__(self, config: dict | None = None, enabled: bool = False):
        self.enabled=enabled
        self.names=tuple((config or {}).get('mode_names',{}).values())
        self.fenced=False
        self.pending_border = None
        self.after_input = False

    def hold_partial(self, text: str) -> bool:
        """Do not flush half a native title/border before it can be recognized."""
        if not self.enabled or self.fenced:return False
        plain=clean(text).lstrip()
        if plain and re.fullmatch(r'[\u2500\u2501\u254c\u254d\u2550]+',plain):
            return True  # Native border lines end with LF.
        for name in self.names:
            target=name+' Mode'
            if plain and target.startswith(plain) and plain!=target:return True
        match=re.match(r'^[>\u203a\u276f\u279c]\s*(?:\u2588|\u258c|\u258e|\u258f|\u2592|\u2591|\u2593)?\s*(.*)$',plain)
        if match:
            rest=match.group(1)
            hint='Build Anything, @ for context, / for commands, $ for skills'
            if hint.startswith(rest) and rest!=hint:return True
        return False

    def flush(self) -> str:
        if self.pending_border is None:return ''
        text,_,_=self.pending_border
        self.pending_border=None
        return text  # Unconfirmed top border remains native, not recolored.

    def apply(self,text: str,initial: SgrState) -> str:
        if not self.enabled or not text:return text
        plain=clean(text)
        prompt=re.search(r'^\s*([>\u203a\u276f\u279c])(?=\s*(?:\u2588|\u258c|\u258e|\u258f|\u2592|\u2591|\u2593)?\s*Build Anything,\s*@ for context,\s*/ for commands,\s*\$ for skills)',plain)
        prefix=''
        if self.pending_border is not None:
            border,span,state=self.pending_border
            self.pending_border=None
            prefix=recolor_span(border,*span,state) if prompt and not self.fenced else border
        if plain.lstrip().startswith('```'):
            self.fenced=not self.fenced
            self.after_input=False
            return prefix+text
        if self.fenced:return prefix+text
        rule=re.fullmatch(r'(\s*)([\u2500\u2501\u254c\u254d\u2550]{8,})(\s*)',plain)
        if rule:
            before=initial.clone();pts=positions(text);before.apply(text[:pts[rule.start(2)]])
            fg=before.values.get('fg','')
            candidate=fg in ('35','36','95','96','38;5;5','38;5;6','38;5;13','38;5;14') or fg.startswith(('38;2;','38:2:'))
            if candidate:
                if self.after_input:
                    self.after_input=False
                    return prefix+recolor_span(text,rule.start(2),rule.end(2),initial)
                self.pending_border=(text,(rule.start(2),rule.end(2)),initial.clone())
                return prefix
        self.after_input=bool(prompt)
        if prompt:
            return prefix+recolor_span(text,prompt.start(1),prompt.end(1),initial)
        # Only registered titles followed by literal Mode belong to this footer.
        for name in self.names:
            if not isinstance(name,str) or not name:continue
            match=re.search(r'(?m)^\s*('+re.escape(name)+r')(?=\s+Mode\b)',plain)
            if match:return prefix+recolor_span(text,match.start(1),match.end(1),initial)
        return prefix+text


def accent_enabled(env: dict, interactive: bool) -> bool:
    return bool(interactive and env.get('TERM','') != 'dumb' and not env.get('NO_COLOR')
                and env.get('BOB2_UI_ACCENT','cyan').lower() == 'cyan')
