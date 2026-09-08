#!/usr/bin/env python3
"""make_refpages: one MathWorks-shaped reference page per public entity.

WP6. The help block is the authority (R1): every page here is DERIVED from
api_data.py, which api_extract.py parses out of the sources. Nothing on a
page is written by hand, so nothing on a page can drift from the help.

Page skeleton, in MathWorks order:
    Syntax - Description - Examples - Input Arguments -
    Name-Value Arguments - Output Arguments - Error Identifiers -
    Version History - See Also
Every page carries every section; a section with nothing to say says so,
because a missing section and an empty one are different claims.

Two WP6 premises did not survive measurement and are recorded in
CLAUDE.md rather than papered over:
  - per-entity Version History from CHANGELOG.md by name match: the
    pre-registered bar was a match rate > 80%. A loose match reaches 81%
    but matches `filter` against releases that never mention it; a match
    anchored on the qualified name reaches 74%. Below the bar either way,
    so every page links the changelog instead of claiming a history.
  - "Functions by the existing tag categories": there are no tag
    categories in the data. Deriving them from helptoc.xml mapped 163 of
    198 entities and put 75 in one catch-all, so the index groups by what
    IS derivable - class, class methods, package functions, root
    functions - and topic categories wait for an editorial decision.

Usage: python3 tools/dev/make_refpages.py [--check]
       --check writes nothing and exits non-zero if any page is stale.

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-08.
"""
import html as H
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
API_DATA = os.environ.get("SHX_API_DATA", os.path.join(HERE, "api_data.py"))
OUTDIR = os.path.join(ROOT, "html", "ref")
PROV = ("Developed by Matthias Weigelt with the help of Claude (Fable 5).")

SECTIONS = ["Syntax", "Description", "Examples", "Input Arguments",
            "Name-Value Arguments", "Output Arguments", "Error Identifiers",
            "Version History", "See Also"]


def toolbox_version():
    """VERSION is parsed from Contents.m - never hardcode it."""
    with open(os.path.join(ROOT, "Contents.m"), encoding="utf-8") as fh:
        txt = fh.read()
    m = re.search(r"^%\s*Version\s+(\S+).*?(\d{2}-\w{3}-\d{4})\s*$",
                  txt, re.M)
    if not m:
        raise SystemExit("make_refpages: no Version line in Contents.m")
    return m.group(1), m.group(2)


def load_api():
    ns = {}
    with open(API_DATA, encoding="utf-8") as fh:
        exec(fh.read(), ns)                                   # noqa: S102
    return ns["API"]


def entities(api):
    """[(qualified name, kind, entry)] - the order pages are emitted in"""
    out = []
    for c in api["classes"]:
        out.append((c["name"], "class", c))
        for m in c["methods"]:
            out.append((c["name"] + "." + m["name"], "method", m))
    for f in api["shLowLevel"]:
        out.append(("shLowLevel." + f["name"], "package", f))
    for f in api["root"]:
        out.append((f["name"], "root", f))
    return out


def page_id(name):
    return name.replace(".", "_")


def esc(s):
    return H.escape(str(s))


def syntax_lines(name, e):
    """one call form per line, positional then the Name=Value form"""
    outs = e.get("outputs") or []
    lhs = ""
    if len(outs) == 1:
        lhs = outs[0] + " = "
    elif len(outs) > 1:
        lhs = "[" + ", ".join(outs) + "] = "
    pos = [a["name"] for a in e.get("args", []) if not a.get("nv")]
    if not pos:
        pos = [a for a in (e.get("inputs") or []) if a != "opts"]
    nv = [a for a in e.get("args", []) if a.get("nv")]
    call = name
    lines = ["%s%s(%s)" % (lhs, call, ", ".join(pos))]
    if nv:
        shown = ", ".join("%s=%s" % (a["name"], a.get("default") or "...")
                          for a in nv[:3])
        more = ", ..." if len(nv) > 3 else ""
        lines.append("%s%s(%s%s%s)" % (lhs, call, ", ".join(pos),
                                       ", " if pos else "", shown + more))
    return lines


def arg_table(args, nv, known):
    rows = []
    for a in args:
        if bool(a.get("nv")) != nv:
            continue
        default = a.get("default") or ""
        if not nv and not default:
            default = "required"
        rows.append(
            "<tr><td><code>%s</code></td><td>%s</td><td>%s</td>"
            "<td><code>%s</code></td><td class=\"desc\">%s</td></tr>"
            % (esc(a["name"]), esc(a.get("size") or "-"),
               esc(a.get("cls") or "-"), esc(default or "-"),
               linkify(a.get("desc") or "", known)))
    if not rows:
        return None
    return ("<table><tr><th>Name</th><th>Size</th><th>Type</th>"
            "<th>Default</th><th>Description</th></tr>%s</table>"
            % "".join(rows))


NAME_RE = None


def build_name_re(known):
    global NAME_RE
    names = sorted(known, key=len, reverse=True)
    NAME_RE = re.compile(r"\b(" + "|".join(re.escape(n) for n in names)
                         + r")\b")


def linkify(text, known, self_name=None):
    """turn every entity mentioned in the text into a link to its page"""
    def sub(m):
        n = m.group(1)
        if n == self_name:
            return esc(n)
        return '<a href="%s.html"><code>%s</code></a>' % (page_id(n), esc(n))
    parts, last = [], 0
    for m in NAME_RE.finditer(text):
        parts.append(esc(text[last:m.start()]))
        parts.append(sub(m))
        last = m.end()
    parts.append(esc(text[last:]))
    return "".join(parts)


def mentioned(text, known, self_name):
    return [n for n in NAME_RE.findall(text or "") if n != self_name]


def example_block(name, e, examples):
    ex = e.get("example") or ""
    reg = examples.get(name) or examples.get(name.split(".")[-1]) or ""
    blocks = []
    if ex.strip():
        blocks.append(("From the help block", ex))
    if reg.strip() and reg.strip() != ex.strip():
        blocks.append(("Runnable (docs/apiExamples.json)", reg))
    if not blocks:
        return None
    out = []
    for title, body in blocks:
        out.append('<details class="example"><summary>%s</summary>'
                   '<div><pre><code>%s</code></pre></div></details>'
                   % (esc(title), esc(body.rstrip())))
    return "".join(out)


def render(name, kind, e, known, examples, version, vdate):
    ident = page_id(name)
    body = [
        '<nav class="crumb"><a href="../shAnalysis.html">shAnalysis</a> '
        '&rsaquo; <a href="index.html">Reference</a> &rsaquo; %s</nav>'
        % esc(name),
        "<h1>%s</h1>" % esc(name),
    ]
    if e.get("h1"):
        body.append('<p class="h1line">%s</p>' % esc(e["h1"]))

    body.append("<h2>Syntax</h2>")
    if kind == "class":
        body.append('<div class="syntax"><code>%s</code></div>'
                    % esc("obj = " + name + "(...)"))
    else:
        body.append('<div class="syntax">%s</div>'
                    % "".join("<code>%s</code>" % esc(s)
                              for s in syntax_lines(name, e)))

    body.append("<h2>Description</h2>")
    desc = e.get("desc") or ""
    if desc.strip():
        body.append("<p>%s</p>" % linkify(desc, known, name))
    else:
        body.append('<p class="none">No description beyond the summary '
                    'line above.</p>')

    body.append("<h2>Examples</h2>")
    exb = example_block(name, e, examples)
    body.append(exb if exb else
                '<p class="none">None registered for this entity.</p>')

    body.append("<h2>Input Arguments</h2>")
    t = arg_table(e.get("args", []), False, known)
    body.append(t if t else '<p class="none">None.</p>')

    body.append("<h2>Name-Value Arguments</h2>")
    t = arg_table(e.get("args", []), True, known)
    body.append(t if t else '<p class="none">None.</p>')

    body.append("<h2>Output Arguments</h2>")
    od = e.get("outdocs") or []
    if od:
        rows = "".join('<tr><td><code>%s</code></td><td class="desc">%s</td>'
                       "</tr>" % (esc(o[0]), linkify(o[1], known, name))
                       for o in od)
        body.append("<table><tr><th>Name</th><th>Description</th></tr>%s"
                    "</table>" % rows)
    elif e.get("outputs"):
        body.append("<p><code>%s</code></p>" % esc(", ".join(e["outputs"])))
    else:
        body.append('<p class="none">None.</p>')

    body.append("<h2>Error Identifiers</h2>")
    ed = e.get("errdocs") or []
    if ed:
        rows = "".join('<tr><td><code>%s</code></td><td class="desc">%s</td>'
                       "</tr>" % (esc(x[0]), esc(x[1])) for x in ed)
        body.append("<table><tr><th>Identifier</th><th>Raised when</th></tr>"
                    "%s</table>" % rows)
    else:
        body.append('<p class="none">None documented in the help block. '
                    'Argument validation raises the <code>MATLAB:*</code> '
                    'identifiers of the <code>arguments</code> block.</p>')

    body.append("<h2>Version History</h2>")
    body.append('<p>Releases are described in <a href="../../CHANGELOG.md">'
                "CHANGELOG.md</a>, which is the authority. Per-entity "
                "history is not reproduced here: matching entity names "
                "against the changelog reaches 74&ndash;81&nbsp;% depending "
                "on how loosely it matches, below the bar set for the "
                "measurement, so a per-page history would be part guess."
                "</p>")

    body.append("<h2>See Also</h2>")
    seen, links = set(), []
    for n in list(e.get("seealso") or []) + mentioned(desc, known, name):
        if n in known and n != name and n not in seen:
            seen.add(n)
            links.append('<li><a href="%s.html"><code>%s</code></a></li>'
                         % (page_id(n), esc(n)))
    if links:
        body.append('<ul class="seealso">%s</ul>' % "".join(links[:24]))
    else:
        body.append('<p class="none">No other entity is named in this '
                    "help block.</p>")

    body.append('<p class="prov">shAnalysis v%s (%s) &mdash; page generated '
                "from the help block by "
                "<code>tools/dev/make_refpages.py</code>. %s</p>"
                % (esc(version), esc(vdate), esc(PROV)))
    return ('<!DOCTYPE html>\n<html lang="en">\n<head>\n'
            '<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, '
            'initial-scale=1">\n'
            "<title>%s &mdash; shAnalysis</title>\n"
            '<link rel="stylesheet" href="../shAnalysis.css">\n'
            "</head>\n<body>\n<div class=\"page\">\n%s\n</div>\n"
            "</body>\n</html>\n" % (esc(name), "\n".join(body)))


def render_index(ents, version, vdate):
    groups = [("Classes", "class"), ("Class methods", "method"),
              ("Package functions (+shLowLevel)", "package"),
              ("Root functions", "root")]
    body = ['<nav class="crumb"><a href="../shAnalysis.html">shAnalysis</a>'
            " &rsaquo; Reference</nav>",
            "<h1>Reference pages</h1>",
            '<p class="h1line">One page per public entity, generated from '
            "the in-file help.</p>"]
    for title, kind in groups:
        rows = [(n, e) for n, k, e in ents if k == kind]
        if not rows:
            continue
        body.append("<h2>%s</h2>" % esc(title))
        body.append("<table><tr><th>Name</th><th>Summary</th></tr>%s</table>"
                    % "".join('<tr><td><a href="%s.html"><code>%s</code></a>'
                              "</td><td>%s</td></tr>"
                              % (page_id(n), esc(n), esc(e.get("h1") or ""))
                              for n, e in rows))
    body.append("<h2>All entities, A&ndash;Z</h2>")
    body.append('<ul class="index">%s</ul>'
                % "".join('<li><a href="%s.html"><code>%s</code></a></li>'
                          % (page_id(n), esc(n))
                          for n in sorted(x[0] for x in ents)))
    body.append('<p class="prov">shAnalysis v%s (%s) &mdash; %s</p>'
                % (esc(version), esc(vdate), esc(PROV)))
    return ('<!DOCTYPE html>\n<html lang="en">\n<head>\n'
            '<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, '
            'initial-scale=1">\n'
            "<title>Reference &mdash; shAnalysis</title>\n"
            '<link rel="stylesheet" href="../shAnalysis.css">\n'
            "</head>\n<body>\n<div class=\"page\">\n%s\n</div>\n"
            "</body>\n</html>\n" % "\n".join(body))


def main(argv):
    check = "--check" in argv
    version, vdate = toolbox_version()
    api = load_api()
    ents = entities(api)
    known = {n for n, _, _ in ents}
    build_name_re(known)
    examples = {}
    jp = os.path.join(ROOT, "docs", "apiExamples.json")
    if os.path.isfile(jp):
        with open(jp, encoding="utf-8") as fh:
            J = json.load(fh)
        rows = J["entries"] if isinstance(J, dict) and "entries" in J else J
        examples = {r["name"]: r.get("example", "") for r in rows}

    if not check:
        os.makedirs(OUTDIR, exist_ok=True)
    pages = {}
    for name, kind, e in ents:
        pages[page_id(name) + ".html"] = render(
            name, kind, e, known, examples, version, vdate)
    pages["index.html"] = render_index(ents, version, vdate)

    stale = []
    for fn, text in sorted(pages.items()):
        p = os.path.join(OUTDIR, fn)
        old = None
        if os.path.isfile(p):
            with open(p, encoding="utf-8") as fh:
                old = fh.read()
        if old != text:
            stale.append(fn)
            if not check:
                with open(p, "w", encoding="utf-8") as fh:
                    fh.write(text)
    extra = []
    if os.path.isdir(OUTDIR):
        extra = [f for f in os.listdir(OUTDIR)
                 if f.endswith(".html") and f not in pages]
        for f in extra:
            if not check:
                os.remove(os.path.join(OUTDIR, f))

    if check:
        if stale or extra:
            print("make_refpages: %d page(s) stale, %d orphaned - rerun "
                  "tools/dev/make_refpages.py" % (len(stale), len(extra)))
            for f in (stale + extra)[:10]:
                print("  -", f)
            return 1
        print("make_refpages: %d pages up to date" % len(pages))
        return 0
    print("make_refpages: %d pages written to html/ref (%d changed, "
          "%d orphans removed)" % (len(pages), len(stale), len(extra)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
