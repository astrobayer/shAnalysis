#!/usr/bin/env python3
"""help_audit: enforce complete in-file documentation (v3.0.2).

Every public function and class method must document, in its help text:
  - every positional input (name mentioned),
  - every name-value option WITH its default value,
  - an Outputs section naming every output with a size or type token,
  - an Example (in-file, or registered in docs/apiExamples.json).

Structural rules on the help block itself (v3.0.2), added after 13 files
were found carrying two sections of the same kind - a generated block
appended below a hand-written one, with the two disagreeing about the
returned struct fields. Presence checks alone cannot see that:
  - a section heading of the house vocabulary appears AT MOST ONCE,
  - no section heading appears after the provenance footer (the doc
    builder and the audit's own section parser stop reading there),
  - headings use the house spelling exactly (Outputs, not Output; Example,
    not Examples; Error identifiers, not Errors; Options, not
    "Name/value options").

Runs in CI before the test suite; nonzero exit on any finding.

Developed by Matthias Weigelt with the help of Claude (Fable 5),
2026-08-10 (v3.0.1); structural section rules 2026-09-08 (v3.0.2).
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TYPEWORDS = r"(double|string|logical|struct|table|cell|char|graphics|function|datetime|shCoefficients|shSeries|shClimatology|matlab\.[\w.]+)"
SIZE = r"\(\s*[\w:,+\- ]+\s*x\s*[\w:,+\- ]+\s*\)|\([\w ]+,\s*[\w: ]+\)"

def join_cont(lines):
    out, buf = [], ""
    for L in lines:
        s = L.rstrip("\n")
        if s.rstrip().endswith("..."):
            buf += s.rstrip()[:-3] + " "
        else:
            out.append(buf + s); buf = ""
    if buf: out.append(buf)
    return out

def parse_file(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()
    return parse_from(lines, 0, os.path.basename(path)[:-2])

def parse_from(lines, i0, expect):
    """parse one function starting at/after i0; returns dict or None"""
    fre = re.compile(r"^\s*function\s+(?:(\[[^\]]*\]|\w+)\s*=\s*)?(\w+)\s*\(([^)]*)\)")
    i = i0
    while i < len(lines) and not fre.match(lines[i]): i += 1
    if i >= len(lines): return None
    m = fre.match(lines[i])
    outs = []
    if m.group(1):
        outs = re.findall(r"\w+", m.group(1))
    ins = [a.strip() for a in m.group(3).split(",") if a.strip()]
    # help
    j = i + 1; help_lines = []
    while j < len(lines) and lines[j].lstrip().startswith("%"):
        help_lines.append(lines[j].lstrip().lstrip("%").rstrip("\n")); j += 1
    # arguments (stop at nested function)
    args = []
    jl = join_cont(lines[j:j + 200])
    for k, L in enumerate(jl):
        if re.match(r"^\s*function\s", L): break
        if L.strip() == "arguments":
            for L2 in jl[k + 1:]:
                s = L2.strip()
                if s == "end": break
                if not s or s.startswith("%"): continue
                mm = re.match(r"(?:opts\.)?(\w+)\b(.*)$", s)
                if not mm: continue
                nm = mm.group(1); rest = mm.group(2)
                nv = s.startswith("opts.")
                dm = re.search(r"=\s*(.+?)(?:\s*%.*)?$", rest)
                default = dm.group(1).strip() if dm else ""
                args.append({"name": nm, "nv": nv, "default": default})
            break
    # the source of THIS function only: a class file holds many methods, and
    # a variable named 'op' or 'info' in a sibling method is not this one's
    # (that leak invented 57 findings before it was noticed)
    ind = len(re.match(r"^(\s*)", lines[i]).group(1))
    end = len(lines)
    for k in range(i + 1, len(lines)):
        mf = re.match(r"^(\s*)function\b", lines[k])
        if mf and len(mf.group(1)) <= ind:
            end = k
            break
    # In a classdef file the local functions after the class body are part
    # of the implementation - shSeries.mean builds its info struct in
    # meanWindowInfo - so a method's source has to include them. But only
    # the ones it actually REACHES: appending all of them to every method
    # made every method with an `info` output inherit every other's
    # fields, and the moment a second method grew one (removeGIA, WP5 5c)
    # that produced ten false findings naming meanWindowInfo's fields.
    # Same shape as A12's "a class method's source is not the whole class
    # file", one level out. Reachability, transitively, as A21a does for
    # identifiers.
    local = ""
    if any(re.match(r"^classdef\b", L) for L in lines[:40]):
        locs, start, curname = {}, None, None
        for k, L in enumerate(lines):
            if re.match(r"^function\s", L):
                if start is not None and curname:
                    locs[curname] = "".join(lines[start:k])
                mm = re.match(
                    r"^function\s+(?:(?:\[[^\]]*\]|\w+)\s*=\s*)?(\w+)", L)
                curname = mm.group(1) if mm else None
                start = k
        if start is not None and curname:
            locs[curname] = "".join(lines[start:])
        want, frontier = set(), ["".join(lines[i:end])]
        while frontier:
            body = re.sub(r"%[^\n]*", "", frontier.pop())
            for nm, sub in locs.items():
                if nm in want:
                    continue
                if re.search(r"\b%s\s*\(" % re.escape(nm), body):
                    want.add(nm)
                    frontier.append(sub)
        local = "".join(locs[n] for n in sorted(want))
    return {"name": m.group(2), "outs": outs, "ins": ins,
            "help": "\n".join(help_lines), "args": args, "line": i,
            "src": "".join(lines[i:end]) + local}

def norm(s):
    return re.sub(r"[\s'\"]+", "", s)

# House section vocabulary. A heading is a help line that is nothing but the
# name (with an optional colon); anything else on the line is prose.
SECTIONS = ("Inputs", "Outputs", "Options", "Example", "Error identifiers",
            "References")
# Near-misses that the section parsers silently do not recognise.
NEAR_MISS = {"Output": "Outputs", "Input": "Inputs", "Examples": "Example",
             "Errors": "Error identifiers", "Error Identifiers":
             "Error identifiers", "Name/value options": "Options",
             "Name-value options": "Options", "Option": "Options",
             "Outputs Arguments": "Outputs", "Output Arguments": "Outputs",
             "Input Arguments": "Inputs"}
HEAD_RE = re.compile(r"^\s{2,6}([A-Za-z][A-Za-z/\- ]*?)\s*:?\s*$")
PROV_RE = re.compile(r"^\s*Developed by ", re.I)

def structure(help_text, label):
    """duplicate / misplaced / misspelt section headings"""
    probs = []
    seen = {}
    prov = None
    for k, L in enumerate(help_text.split("\n")):
        if prov is None and PROV_RE.match(L):
            prov = k
        m = HEAD_RE.match(L.rstrip())
        if not m:
            continue
        name = m.group(1).strip()
        if name in NEAR_MISS:
            probs.append("%s: section '%s' should be spelt '%s' (the house "
                         "vocabulary; other spellings are invisible to the "
                         "section parsers)" % (label, name, NEAR_MISS[name]))
            continue
        if name not in SECTIONS:
            continue          # free prose sub-heading inside a description
        if name in seen:
            probs.append("%s: section '%s' appears twice (help lines %d and "
                         "%d); one authority per section" %
                         (label, name, seen[name] + 1, k + 1))
        else:
            seen[name] = k
        if prov is not None and k > prov:
            probs.append("%s: section '%s' comes after the provenance "
                         "footer, where the doc builder stops reading" %
                         (label, name))
    return probs

# --- default markers outside the Options section (v5.23.2) ----------------
# fix_help.py documented a missing default by writing " (<default>)" after
# the FIRST mention of the option anywhere in the help, not in its Options
# row. From v3.0.1 to v5.23.1 that left 125 markers in syntax lines and
# prose: `setup_shAnalysis(Permanent (false) = true)` is not a MATLAB call,
# and `Convert to another (GM (NaN), R (NaN)) reference` is not a sentence.
# The default check below was satisfied by them, since it only asks that
# the default appear on SOME line naming the option. The marker belongs to
# the option's own row: a row of the Options section, or - for the blocks
# that list options under Inputs or with an `opts.` prefix - a row that
# STARTS with the option. `Name (default)` followed by `=` is call syntax
# and is wrong everywhere.
def options_rows(help_lines):
    """indices of the help lines inside an Options section"""
    rows, cur = set(), None
    for k, L in enumerate(help_lines):
        if PROV_RE.match(L):
            cur = None
        m = HEAD_RE.match(L.rstrip())
        if m and m.group(1).strip() in SECTIONS:
            cur = m.group(1).strip()
        elif cur == "Options":
            rows.add(k)
    return rows


def misplaced_defaults(help_text, args, label):
    """'<Opt> (<default>)' written into a syntax line or into prose"""
    probs = []
    H = help_text.split("\n")
    inopt = options_rows(H)
    for a in args:
        if not a["nv"]:
            continue
        tok = a["name"] + " (" + (a["default"] or '""') + ")"
        for k, L in enumerate(H):
            if tok not in L:
                continue
            call = re.search(re.escape(tok) + r"\s*=", L)
            row = k in inopt or re.match(
                r"^\s*(opts\.)?" + re.escape(tok), L)
            if call or not row:
                probs.append("%s: help line %d carries the default marker "
                             "'%s' outside the option's row%s" % (
                                 label, k + 1, tok,
                                 " - as call syntax it is not MATLAB"
                                 if call else ""))
    return probs


# --- struct output fields (A12) -------------------------------------------
# help_audit checked that every OUTPUT VARIABLE appears in the Outputs
# section. It never checked the FIELDS a struct output promises, so
# `readTN14` documented `tn.t` (there is none), `shAnalysisGrid` documented
# `info.condest` for `condEst` (MATLAB field names are case-sensitive: a
# user following the help got an error), and `mcPropagate` documented
# percentiles it does not compute. Eight such lies were found by hand.
#
# A prose field list cannot be parsed apart from its description, so the
# house form is a LIST: the struct row ends with the word "fields", and
# each field is one deeper-indented continuation line beginning with its
# name. A struct built by another function is declared delegated instead.
STRUCT_ROW = re.compile(r"^(\s{2,10})(\w+)\s{2,}(.*?\bstruct\b.*)$")
# both spellings are in the tree already; the leading dot is the older one
FIELD_ROW = re.compile(r"^(\s+)\.?([A-Za-z_]\w*"
                       r"(?:\s*[,/]\s*\.?[A-Za-z_]\w*)*)"
                       r"(?:\s+(.*))?$")
# A struct built by ANOTHER function is documented there, not here. The
# marker has to be explicit and name that function: a bare "from" or
# "see" appears in ordinary prose ("removed from the file", "from the
# ocean-fit residual") and silently excused five rows that were in fact
# documented here and verifiable.
DELEGATED = re.compile(
    r"\b(?:as returned by|as documented by|output of|built by|"
    r"as in)\s+(?:shLowLevel\.)?\w+"
    r"|\bfrom\s+shLowLevel\.\w+"
    r"|\bthe\s+shLowLevel\.\w+\s+(?:report|struct|output)"
    r"|\bshLowLevel\.\w+\s+(?:returns|documents)\b", re.I)
ENDS_FIELDS = re.compile(r"\bfields\s*:?\s*$", re.I)
SECTION_END = re.compile(r"^\s*(Inputs?|Options?|Example|Error identifiers|"
                         r"References|Developed by)\b")


def struct_field_docs(help_text):
    """[(var, [field, ...], delegated, line)] for every struct output row."""
    lines = help_text.split("\n")
    heads = [k for k, L in enumerate(lines)
             if re.match(r"^\s*Outputs\s*$", L)]
    if not heads:
        return []
    out = []
    k = heads[0] + 1
    while k < len(lines):
        L = lines[k]
        if not L.strip() or SECTION_END.match(L):
            break
        m = STRUCT_ROW.match(L.rstrip())
        if not m:
            k += 1
            continue
        indent, var, desc = len(m.group(1)), m.group(2), m.group(3)
        # "as returned by shLowLevel.synthesisMatrix" often wraps, so the
        # delegation marker is looked for across the row and the two lines
        # under it, not on the row alone
        window = " ".join([desc] + [x.strip() for x in lines[k + 1:k + 3]])
        delegated = bool(DELEGATED.search(window))
        # The marker is the first line ending in "fields", which may be
        # the row itself or the last line of a short preamble ("...the
        # PHYSICAL state is the first block. Fields"). Everything after
        # it, indented deeper, is the list.
        fields, j = [], k + 1
        marked = bool(ENDS_FIELDS.search(desc))
        while not marked and j < len(lines):
            L2 = lines[j]
            if not L2.strip() or SECTION_END.match(L2):
                break
            m2 = re.match(r"^(\s+)", L2)
            if not m2 or len(m2.group(1)) <= indent:
                break
            j += 1
            if ENDS_FIELDS.search(L2):
                marked = True
                break
        if not marked:
            j = k + 1
        if marked:
            while j < len(lines):
                L2 = lines[j]
                if not L2.strip() or SECTION_END.match(L2):
                    break
                m2 = FIELD_ROW.match(L2.rstrip())
                if not m2 or len(m2.group(1)) <= indent:
                    break
                fields += re.findall(r"[A-Za-z_]\w*", m2.group(2))
                j += 1
                # continuation of THIS field's description: deeper again
                while j < len(lines) and lines[j].strip() and \
                        not SECTION_END.match(lines[j]) and \
                        re.match(r"^(\s+)", lines[j]) and \
                        len(re.match(r"^(\s+)", lines[j]).group(1)) > \
                        len(m2.group(1)):
                    j += 1
        out.append((var, fields, delegated, k + 1))
        k = max(j, k + 1)
    return out


def _is_transpose(src, i):
    """In MATLAB ' is transpose after a value, a quote otherwise.

    struct('areaFraction', w' * mask, 'nGridPoints', ...) - the ' in w'
    is an operator. Reading it as a string delimiter desynchronises
    everything after it, which hid three of basinKernel's four fields
    and would have made a correct help block look wrong.
    """
    k = i - 1
    while k >= 0 and src[k] in " \t":
        k -= 1
    return k >= 0 and (src[k].isalnum() or src[k] in "_)]}.'")


def struct_field_names(args):
    """'name' literals at depth 0 of a struct() argument list.

    Nested calls carry their own quoted arguments - struct(..., 'created',
    string(datetime('now', 'Format', 'yyyy-MM-dd'))) is one field, not
    three - so anything inside a nested paren is skipped.
    """
    # struct() alternates name, value, name, value: only the EVEN
    # depth-0 arguments are field names. Without this, the "zeroField" in
    # struct(..., 'stoppedBy', "zeroField", ...) looked like a field of
    # its own - a phantom that weakens both directions of the check.
    names, depth, i, arg = set(), 0, 0, 0
    while i < len(args):
        c = args[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            arg += 1
        elif c in "'\"":
            if c == "'" and _is_transpose(args, i):
                i += 1
                continue
            j = i + 1
            while True:
                j = args.find(c, j)
                if j < 0:
                    break
                if j + 1 < len(args) and args[j + 1] == c:   # '' escape
                    j += 2
                    continue
                break
            if j < 0:
                break
            if depth == 0:
                lit = args[i + 1:j]
                k = j + 1
                while k < len(args) and args[k] in " \t\r\n.":
                    k += 1
                if arg % 2 == 0 and re.fullmatch(r"[A-Za-z_]\w*", lit) \
                        and k < len(args) and args[k] == ",":
                    names.add(lit)
            i = j
        i += 1
    return names


def struct_call_args(src):
    """text inside every struct( ... ), paren-matched (calls nest and wrap)"""
    out = []
    for m in re.finditer(r"\bstruct\s*\(", src):
        depth, i = 1, m.end()
        while i < len(src) and depth:
            if src[i] == "(":
                depth += 1
            elif src[i] == ")":
                depth -= 1
            i += 1
        out.append(src[m.end():i - 1])
    return out


def fields_assigned_to(src, var):
    """fields the source writes on THIS variable specifically"""
    v = re.escape(var)
    names = set(re.findall(r"\b" + v + r"(?:\([^)]*\))?\.(\w+)\s*"
                           r"(?:\([^)]*\))?\s*=(?!=)", src))
    for m in re.finditer(r"\b" + v + r"\s*=\s*struct\s*\(", src):
        depth, i = 1, m.end()
        while i < len(src) and depth:
            if src[i] == "(":
                depth += 1
            elif src[i] == ")":
                depth -= 1
            i += 1
        names.update(struct_field_names(src[m.end():i - 1]))
    return names


def assigned_fields(src):
    """field names the source actually writes on any struct"""
    names = set(re.findall(r"\b\w+\.(\w+)\s*(?:\([^)]*\))?\s*=(?!=)", src))
    for call in struct_call_args(src):
        names.update(struct_field_names(call))
    names.update(re.findall(r"setfield\s*\([^,]+,\s*['\"](\w+)['\"]", src))
    # dynamic assignment: s.(fld) = ... with fld from a literal list
    if re.search(r"\.\(\w+\)\s*=", src):
        names.update(re.findall(r"['\"](\w+)['\"]", src))
    return names


def outputs_section(help_text):
    m = re.search(r"^\s*Outputs\s*$(.*?)(?=^\s*(?:Inputs?|Options?|Example|"
                  r"Error identifiers|References|Developed by)\b|\Z)",
                  help_text, re.M | re.S)
    return m.group(1) if m else ""


def struct_fields(help_text, src, label, outs, stats=None):
    """Two directions, and each says how far it reached.

    B (documented => assigned) needs the field list in list form, so it runs
    only where the help gives one; STATS carries how many rows that was, so
    the gate can report its own coverage instead of implying it checked all.
    A (assigned => documented) is a substring test and runs everywhere.
    """
    probs = []
    have = assigned_fields(src)
    sec = outputs_section(help_text)
    for var, fields, delegated, line in struct_field_docs(help_text):
        if var not in outs:
            continue                    # a struct INPUT mentioned in Outputs
        if delegated:
            if stats is not None:
                stats["delegated"] += 1
            continue                    # built elsewhere; that file documents it
        # --- A: nothing the file writes on this struct may go unmentioned
        for f in sorted(fields_assigned_to(src, var)):
            if not re.search(r"\b" + re.escape(f) + r"\b", sec):
                probs.append("%s: assigns '%s.%s' but the Outputs section "
                             "never mentions it (help line %d)"
                             % (label, var, f, line))
        # --- B: nothing the help promises may be missing from the file
        if not fields:
            if stats is not None:
                stats["prose"] += 1
            continue
        if stats is not None:
            stats["listed"] += 1
        for f in fields:
            if f not in have:
                probs.append("%s: help promises field '%s.%s', which the file "
                             "never assigns (help line %d)"
                             % (label, var, f, line))
    return probs


def audit(entry, label, examples):
    H = entry["help"]; probs = []
    if not H.strip():
        return [label + ": no help text"]
    probs += structure(H, label)
    probs += misplaced_defaults(H, entry["args"], label)
    if entry.get("src"):
        probs += struct_fields(H, entry["src"], label, set(entry["outs"]),
                               STRUCT_STATS)
    Hn = norm(H)
    # positional inputs (skip obj/varargin/opts)
    for a in entry["ins"]:
        if a in ("obj", "tc", "testCase", "varargin", "opts"): continue
        if not re.search(r"\b" + re.escape(a) + r"\b", H, re.I):
            probs.append(label + ": input '%s' undocumented" % a)
    # options with defaults
    for a in entry["args"]:
        if not a["nv"]: continue
        segs = re.findall(r"^.*\b" + re.escape(a["name"]) + r"\b.*$", H, re.M)
        if not segs:
            probs.append(label + ": option '%s' undocumented" % a["name"])
            continue
        dn = norm(a["default"])
        ok = any(("(" in seg) and (dn == "" or dn[:18] in norm(seg) or
                                   "default" in seg.lower()) for seg in segs)
        if not ok:
            probs.append(label + ": option '%s' documented without its "
                         "default (%s)" % (a["name"], a["default"] or "?"))
    # outputs
    if entry["outs"] and entry["outs"] != ["varargout"]:
        mo = re.search(r"^\s*Outputs?\s*:?\s*$(.*?)(?=^\s*(Example|Developed|See also|$\s*$))",
                       H, re.M | re.S)
        if not mo:
            probs.append(label + ": no Outputs section")
        else:
            sec = mo.group(0)
            for o in entry["outs"]:
                if not re.search(r"\b" + re.escape(o) + r"\b", sec):
                    probs.append(label + ": output '%s' missing from Outputs" % o)
            if not (re.search(SIZE, sec) or re.search(TYPEWORDS, sec)):
                probs.append(label + ": Outputs lack size/type annotations")
    # example
    has_ex = re.search(r"^\s*Examples?\b", H, re.M) is not None
    if not has_ex and label not in examples:
        probs.append(label + ": no Example (in-file or apiExamples.json)")
    return probs

STRUCT_STATS = {"listed": 0, "prose": 0, "delegated": 0}


def main():
    examples = set()
    jp = os.path.join(ROOT, "docs", "apiExamples.json")
    if os.path.isfile(jp):
        with open(jp, encoding="utf-8") as fh:
            J = json.load(fh)
        ents = J["entries"] if isinstance(J, dict) and "entries" in J else J
        examples = {e["name"] for e in ents if e.get("example")}
    probs = []
    pkg = os.path.join(ROOT, "+shLowLevel")
    for f in sorted(os.listdir(pkg)):
        if not f.endswith(".m"): continue
        e = parse_file(os.path.join(pkg, f))
        if e: probs += audit(e, "shLowLevel." + e["name"], examples)
    for f in ["setup_shAnalysis.m", "runAllTests.m", "demo_shAnalysis.m"]:
        p = os.path.join(ROOT, f)
        if os.path.isfile(p):
            e = parse_file(p)
            if e: probs += audit(e, e["name"], examples)
    for cls in ["shCoefficients.m", "shSeries.m", "shClimatology.m"]:
        p = os.path.join(ROOT, cls)
        if not os.path.isfile(p): continue
        with open(p, encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
        # walk methods blocks, tracking each block's Access/Hidden attrs;
        # a block opened by '<ind>methods...' closes at '<ind>end'
        i = 0; seen = set()
        while i < len(lines):
            mb = re.match(r"^(\s*)methods\b(.*)$", lines[i])
            if not mb:
                i += 1; continue
            ind, attrs = mb.group(1), mb.group(2)
            public = not (re.search(r"Access\s*=\s*'?(private|protected)",
                                    attrs) or "Hidden" in attrs)
            j = i + 1
            endre = re.compile("^" + ind + r"end\b")
            while j < len(lines) and not endre.match(lines[j]):
                if public and re.match(r"^\s*function\s", lines[j]):
                    e = parse_from(lines, j, "")
                    if e and e["name"] not in seen:
                        seen.add(e["name"])
                        probs += audit(e, cls[:-2] + "." + e["name"], examples)
                j += 1
            i = j + 1
    if probs:
        print("help_audit: %d finding(s)" % len(probs))
        for p in probs: print("  -", p)
        sys.exit(1)
    print("help_audit: 0 findings - all public help complete "
          "(struct outputs: %d field lists verified against the source, "
          "%d delegated, %d still prose - see CLAUDE.md A12)"
          % (STRUCT_STATS["listed"], STRUCT_STATS["delegated"],
             STRUCT_STATS["prose"]))

if __name__ == "__main__":
    main()
