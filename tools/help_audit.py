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
    return {"name": m.group(2), "outs": outs, "ins": ins,
            "help": "\n".join(help_lines), "args": args, "line": i}

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

def audit(entry, label, examples):
    H = entry["help"]; probs = []
    if not H.strip():
        return [label + ": no help text"]
    probs += structure(H, label)
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
    print("help_audit: 0 findings - all public help complete")

if __name__ == "__main__":
    main()
