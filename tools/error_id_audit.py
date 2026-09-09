#!/usr/bin/env python3
"""error_id_audit: every error identifier is owned and documented (v1.0.0).

A3/A15 were the finding: 17 raise sites in +shLowLevel used identifiers
belonging to another function - `kernelFactors` raised `shSynthesis:*`,
`writeFrames` raised `shLowLevel:writeAnimation:*` alongside its own
`shLowLevel:writeFrames:badSize`. A caller cannot catch by owner when the
owner is fiction, and `tvANSFilter` does exactly that catch:

    if strcmp(ME.identifier, 'shLowLevel:buildNoiseCov:notBlockDiagonal')

Three checks:

  OWNERSHIP   +shLowLevel/X.m raises only shLowLevel:X:<reason>.
              No backlog: the v4.0.0 sweep made this true everywhere, so
              a new violation is a new defect, not inherited debt.
  DOCUMENTED  every raised identifier appears in that file's
              "Error identifiers" help section. 61 files predated the
              convention and sat in UNDOCUMENTED, a list that only ever
              shrinks; A20 drained it in v4.0.2, so this rule now holds
              with no exemption at all.
  PINS        every toolbox identifier a TEST names is one some file
              actually raises. Nothing read tests/ before v5.0.1.
              REACH, stated because it is narrower than it sounds: this
              catches a pin naming an identifier that EXISTS NOWHERE
              (A21b's `shCoefficients:noC30`, missed by an enumerating
              grep whose [A-Za-z]* could not match the digits). It does
              NOT catch a pin naming a real identifier that the call
              under test cannot reach (`shSeries:fromFolder:noFiles`
              where the empty folder is caught by `read`) - that needs
              per-call guard analysis, and only MATLAB has it. One of
              A21b's two red rounds is preventable here; the other is
              not, and saying so is the point.
  GHOSTS      every identifier the help documents is actually raised.
              A12's lesson: documentation drifts in BOTH directions.

WHAT COUNTS AS A RAISE. Only the identifier argument of error(), assert()
and warning(). A first pass that matched any quoted identifier reported
five violations of which FOUR were false: `tvANSFilter` COMPARES against
another function's id (the catch above), and `fetchITSGSINEX` passes
"shLowLevel:fetchITSGSINEX" as a PREFIX to a helper that appends the
reason. Neither raises anything. Read a checker's output against the
source before believing it.

Run: python3 tools/error_id_audit.py [--list]
Nonzero exit on any finding.

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-09.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKG = os.path.join(ROOT, "+shLowLevel")
# A class raises per-METHOD identifiers, so the file-level owner rule does
# not fit it. A21 added the CLASS pass below instead of widening the loop.
CLASS_FILES = ("shCoefficients.m", "shSeries.m", "shClimatology.m")
# surface() must skip the class files whatever CLASS_FILES is set to: the
# two uses are different questions, and conflating them let a test that
# emptied the class list silently re-admit shSeries.m as a ROOT function
# owning `shAnalysis:shSeries:*`. Same trap as A17 - one name, two jobs.
_IS_CLASS = frozenset(CLASS_FILES)

# A21b: DRAINED in v5.0.0. Every class identifier is now three-part, so
# this set is empty and the rule holds with no exemption. It stays as the
# mechanism - a new file could earn a temporary entry with a dated reason
# - and, as in A20, the self-test asserts that mechanism with a TEMPORARY
# entry rather than pinning a member name, because a loop over an empty
# set cannot fail (A14).
TWO_PART_OK = set()

# The middle segment of a class identifier. Normally the raising PUBLIC
# method, so a caller can tell what they called. The exceptions are the
# shared private checks: `shCoefficients.checkPair` guards the operand
# pair for both binary operators, `shSeries.assertClean` guards the
# stacks for six methods. Those get a stable CONCEPT name rather than the
# helper's own, so renaming a private function is not a breaking change -
# which is the whole reason this list is short and hand-written.
SHARED_CHECKS = {"operands", "stack", "range"}

# error('id', ...) / warning('id', ...) -> identifier is argument 1.
# assert(cond, 'id', ...)               -> identifier is argument 2.
# Continuations are folded first, so the id may sit on the next line.
RAISE = re.compile(
    r"\b(?:error|warning)\s*\(\s*['\"]([A-Za-z][\w]*(?::[\w]+)+)['\"](\s*\+)?"
    r"|\bassert\s*\([^;]*?,\s*['\"]([A-Za-z][\w]*(?::[\w]+)+)['\"](\s*\+)?")

# An identifier BUILT at runtime. setup_shAnalysis raises
#     warning("shAnalysis:setup:no" + locs(li, 1), ...)
# for five option names, so no scan of that file can name what it raises.
# Reading the literal as if it were the identifier is worse than useless:
# it invents `shAnalysis:setup:no`, which nothing ever raises. Such a
# literal is treated as a PREFIX - the help must document at least one
# identifier under it, and says so, since the gate cannot enumerate them.

# Both house styles: the id alone on its line with the reason indented
# below, and "id  reason" on one line. Requiring the first spelling
DOC_ID = re.compile(r"^%\s+((?:shLowLevel|shAnalysis):[\w:]+)(?:\s|$)", re.M)
# Class help lines are stripped of their indent before matching, and the
# identifier root is the class name rather than a fixed prefix.
DOC_ID_ANY = re.compile(r"^%\s+((?:shCoefficients|shSeries|shClimatology):[\w:]+)(?:\s|$)", re.M)
SECTION = "%   Error identifiers"

# Files that raise identifiers but predate the "Error identifiers" help
# section. DRAINED in v4.0.2 (A20): all 61 files, 208 identifiers, were
# documented against their raise sites. The set stays as the mechanism -
# a new file may earn a temporary entry with a dated reason - but it is
# empty, so the DOCUMENTED rule now holds with no exemption. An empty
# backlog is exactly how A14's LEGACY test rotted into a no-op, so the
# self-test asserts the mechanism with a TEMPORARY entry rather than
# pinning a member name.
UNDOCUMENTED = set()


def fold(text):
    """Join MATLAB ... continuations so a raise can be read on one line."""
    return re.sub(r"\.\.\.[^\n]*\n\s*", " ", text)


def surface():
    """(path, stem, owner prefix) of every file this gate reads.

    +shLowLevel/X.m owns shLowLevel:X:*. A root function owns
    shAnalysis:<tag>:* where <tag> is its name without the toolbox
    suffix - setup_shAnalysis -> shAnalysis:setup:*, demo_shAnalysis ->
    shAnalysis:demo:*. The three class files are deliberately absent:
    their identifiers are per-METHOD, so the file-level owner rule does
    not apply to them (A21).
    """
    out = []
    for f in sorted(os.listdir(PKG)):
        if f.endswith(".m"):
            out.append((os.path.join(PKG, f), f[:-2],
                        "shLowLevel:%s:" % f[:-2]))
    for f in sorted(os.listdir(ROOT)):
        if not f.endswith(".m") or f in _IS_CLASS or f == "Contents.m":
            continue
        tag = f[:-2].replace("_shAnalysis", "")
        out.append((os.path.join(ROOT, f), f[:-2], "shAnalysis:%s:" % tag))
    return out


def code_of(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    body = "\n".join(l for l in src.splitlines()
                     if not l.lstrip().startswith("%"))
    return src, fold(body)


def raised_in(code):
    """-> (literal identifiers, prefixes of runtime-built identifiers)"""
    ids, prefixes = set(), set()
    for m in RAISE.finditer(code):
        ident = m.group(1) or m.group(3)
        built = m.group(2) or m.group(4)
        (prefixes if built else ids).add(ident)
    return ids, prefixes


def documented_in(src):
    if SECTION not in src:
        return None                      # no section at all
    return set(DOC_ID.findall(src))


# --- CLASS pass (A21) -----------------------------------------------------
# A class file needs a different instrument, not a wider loop: identifiers
# belong to METHODS, and a user catching one calls a PUBLIC method. Several
# are raised by PRIVATE helpers (shCoefficients.checkPair,
# shSeries.assertClean), so documenting them only where they are raised
# would put them where `help` cannot reach. The rule therefore follows
# REACHABILITY, one hop: a public method must document what it raises
# itself plus what the private helpers it calls raise.
#
# One hop is enough here and is checked - see CLASS_HOPS below - rather
# than assumed.
FUN = re.compile(r"^(\s*)function\s+(?:\[[^\]]*\]|[\w~., ]+?)\s*=\s*(\w+)|"
                 r"^(\s*)function\s+(\w+)\s*[(\s]|^(\s*)function\s+(\w+)\s*$")
METHODS_BLOCK = re.compile(r"^\s*methods\s*(\(([^)]*)\))?\s*(%.*)?$")


def parse_class(path):
    """-> list of {name, access, help, raises, body} in file order."""
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    blocks = [(i, (m.group(2) or "public").strip())
              for i, L in enumerate(lines)
              if not L.lstrip().startswith("%") and (m := METHODS_BLOCK.match(L))]
    funs = []
    for i, L in enumerate(lines):
        if L.lstrip().startswith("%"):
            continue
        m = FUN.match(L)
        if not m:
            continue
        acc, best = "public", -1
        for k, v in blocks:
            if k <= i and k > best:
                best, acc = k, v
        funs.append({"line": i, "name": m.group(2) or m.group(4) or m.group(6),
                     "access": acc})
    for n, f in enumerate(funs):
        stop = funs[n + 1]["line"] if n + 1 < len(funs) else len(lines)
        j = f["line"] + 1
        h = []
        while j < stop and lines[j].lstrip().startswith("%"):
            h.append(lines[j].strip())
            j += 1
        f["help"] = "\n".join(h)
        f["body"] = "\n".join(l for l in lines[j:stop]
                               if not l.lstrip().startswith("%"))
        ids, pre = raised_in(fold(f["body"]))
        f["raises"] = ids | pre
    return funs


def class_requirements(funs):
    """(public method -> identifiers it must document, private raisers)."""
    priv = {f["name"]: f["raises"] for f in funs
            if "private" in f["access"].lower() and f["raises"]}
    need = {}
    for f in funs:
        if "private" in f["access"].lower():
            continue
        got = set(f["raises"])
        for h, hid in priv.items():
            if re.search(r"\b%s\s*\(" % re.escape(h), f["body"]):
                got |= hid
        if got:
            need[f["name"]] = got
    return need, priv


TEST_DIR = os.path.join(ROOT, "tests")
# Toolbox-owned roots. A test may legitimately name MATLAB's own
# identifiers (MATLAB:*) or a third party's; those are not ours to check.
OWNED = ("shLowLevel:", "shAnalysis:", "shCoefficients:", "shSeries:",
         "shClimatology:")
_OWNED_RE = "|".join(re.escape(o) for o in OWNED)
# NOTE the digits: `shCoefficients:applyTN14:noC30` and `readTN13` carry
# them, and a letters-only class is exactly how the noC30 pin escaped.
PIN = re.compile(r"['\"]((?:%s)[\w:]+)['\"]" % _OWNED_RE)


# An owned-looking literal that is NOT itself a raised identifier is a
# PREFIX handed to a helper: +shLowLevel/private/normalizeMonthList.m
# raises `errId + ":badMonth"` and its callers pass
# "shLowLevel:fetchITSGSINEX". The first version of the PINS rule reported
# those two real identifiers as raised by nothing - a new checker lies
# before it tells the truth (A12), so it was narrowed rather than the
# tests "fixed".
LITERAL = re.compile(r"['\"]((?:%s)[\w:]+)['\"]" % _OWNED_RE)


def raisable():
    """(identifiers raised, prefixes under which more may be raised)."""
    ids, prefixes = set(), set()
    sources = [p for p, _s, _o in surface()]
    sources += [os.path.join(ROOT, f) for f in CLASS_FILES]
    priv = os.path.join(PKG, "private")
    if os.path.isdir(priv):
        sources += [os.path.join(priv, f) for f in sorted(os.listdir(priv))
                    if f.endswith(".m")]
    # tests raise a few identifiers of their own (tests/rmIfFolder.m warns
    # shAnalysis:test:cleanupFailed); those are raises, not pins.
    if os.path.isdir(TEST_DIR):
        sources += [os.path.join(TEST_DIR, f)
                    for f in sorted(os.listdir(TEST_DIR)) if f.endswith(".m")]
    lits = set()
    for path in sources:
        if not os.path.isfile(path):
            continue
        src, code = code_of(path)
        i, p = raised_in(code)
        ids |= i
        prefixes |= p
        # Prefix literals come from the TOOLBOX only. Harvesting them from
        # tests/ too let a pin validate itself: the bad `shCoefficients:noC30`
        # pin was read as its own prefix and the rule went quiet. Tests
        # contribute their RAISES (rmIfFolder warns) and nothing else.
        if not path.startswith(TEST_DIR + os.sep):
            lits |= set(LITERAL.findall(code))
    for f in CLASS_FILES:
        path = os.path.join(ROOT, f)
        if os.path.isfile(path):
            for fn in parse_class(path):
                ids |= fn["raises"]
    prefixes |= (lits - ids)
    return ids, prefixes


def check_pins():
    """PINS: a test may only name an identifier something raises."""
    probs, checked = [], 0
    if not os.path.isdir(TEST_DIR):
        return probs, checked
    ids, prefixes = raisable()
    for f in sorted(os.listdir(TEST_DIR)):
        if not f.endswith(".m"):
            continue
        src = open(os.path.join(TEST_DIR, f), encoding="utf-8",
                   errors="replace").read()
        for k, line in enumerate(src.split("\n"), 1):
            if line.lstrip().startswith("%"):
                continue
            for m in PIN.finditer(line):
                pin = m.group(1)
                checked += 1
                if pin in ids:
                    continue
                # a prefix only covers what sits BELOW it: "shSeries:read"
                # must not validate "shSeries:readFoo"
                if any(pin.startswith(pre + ":") for pre in prefixes):
                    continue
                probs.append("%s:%d pins %s, which no file raises"
                             % (f, k, pin))
    return probs, checked


def check_classes():
    probs, backlog, checked = [], [], 0
    for f in CLASS_FILES:
        cls = f[:-2]
        path = os.path.join(ROOT, f)
        if not os.path.isfile(path):
            probs.append("%s is listed as a class file but does not exist - "
                         "renamed or deleted?" % f)
            continue
        funs = parse_class(path)
        names = {x["name"] for x in funs}
        need, priv = class_requirements(funs)
        # a private helper calling another private helper would make one hop
        # too few; the rule says so out loud instead of hoping
        for h in priv:
            for other in priv:
                if other != h and re.search(
                        r"\b%s\s*\(" % re.escape(other),
                        next(x["body"] for x in funs if x["name"] == h)):
                    probs.append("%s: private %s calls private %s - the "
                                 "one-hop reachability rule is too shallow "
                                 "for this file" % (f, h, other))
        for fn in funs:
            for i in sorted(fn["raises"]):
                if not i.startswith(cls + ":"):
                    probs.append("%s.%s raises %s - the class owns %s:* only"
                                 % (cls, fn["name"], i, cls))
                elif i.count(":") == 1:
                    if i in TWO_PART_OK:
                        backlog.append(i)
                    else:
                        probs.append(
                            "%s.%s raises the two-part %s, which does not name "
                            "its method - use %s:%s:<reason> (A21b)"
                            % (cls, fn["name"], i, cls, fn["name"]))
                else:
                    mid = i.split(":")[1]
                    if mid not in names and mid not in SHARED_CHECKS:
                        probs.append(
                            "%s.%s raises %s, whose middle segment names "
                            "neither a method of this class nor a declared "
                            "shared check %s" % (cls, fn["name"], i,
                                                 sorted(SHARED_CHECKS)))
        for meth, ids in sorted(need.items()):
            fn = next(x for x in funs if x["name"] == meth)
            doc = set(DOC_ID_ANY.findall(fn["help"]))
            checked += 1
            if SECTION.strip() not in fn["help"]:
                probs.append("%s.%s can raise %d identifier(s) and its help "
                             "has no 'Error identifiers' section"
                             % (cls, meth, len(ids)))
                continue
            for i in sorted(ids - doc):
                probs.append("%s.%s can raise %s but its help does not "
                             "document it" % (cls, meth, i))
            for i in sorted(doc - ids):
                probs.append("%s.%s documents %s but neither raises it nor "
                             "calls a private helper that does"
                             % (cls, meth, i))
    return probs, sorted(set(backlog)), checked


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    probs, backlog, checked = [], [], 0
    for path, stem, own in surface():
        src, code = code_of(path)
        ids, prefixes = raised_in(code)
        if not ids and not prefixes:
            continue
        checked += 1
        for i in sorted(ids | prefixes):
            if not i.startswith(own):
                probs.append("%s.m raises %s - it owns %s* only" % (stem, i, own))
        doc = documented_in(src)
        for i in sorted(ids & prefixes):
            probs.append("%s.m raises %s both as a whole identifier and as a "
                         "prefix - one of the two is a typo" % (stem, i))
        if doc is None:
            if stem in UNDOCUMENTED:
                backlog.append(stem)
            else:
                probs.append("%s.m raises %d identifier(s) and has no "
                             "'Error identifiers' help section"
                             % (stem, len(ids)))
            continue
        if stem in UNDOCUMENTED:
            probs.append("%s.m now documents its identifiers - remove it "
                         "from UNDOCUMENTED (the backlog only shrinks)" % stem)
        for i in sorted(ids - doc):
            probs.append("%s.m raises %s but its help does not document it"
                         % (stem, i))
        for i in sorted(doc - ids):
            # a documented id under a runtime-built prefix is exactly what
            # that prefix asks for; it cannot be matched to a raise site
            if not any(i.startswith(pre) for pre in prefixes):
                probs.append("%s.m documents %s but never raises it"
                             % (stem, i))
        for pre in sorted(prefixes):
            if not any(i.startswith(pre) and i != pre for i in doc):
                probs.append("%s.m builds identifiers as \"%s\" + <name> and "
                             "documents none of them - the gate cannot "
                             "enumerate them, so the help must" % (stem, pre))

    cprobs, cbacklog, cchecked = check_classes()
    probs += cprobs
    pprobs, pchecked = check_pins()
    probs += pprobs

    if "--list" in argv:
        for s in sorted(backlog):
            print("  backlog: %s.m" % s)
        for i in cbacklog:
            print("  two-part (A21b): %s" % i)
    if probs:
        print("error_id_audit: %d finding(s)" % len(probs), file=sys.stderr)
        for p in probs:
            print("  - " + p, file=sys.stderr)
        return 1
    tail = ("no backlog left (A20 drained it in v4.0.2)" if not backlog
            else "%d in the shrinking UNDOCUMENTED backlog" % len(backlog))
    print("error_id_audit: 0 findings - %d files raise identifiers, every one "
          "owned by the file that raises it; %d document them, %s. Classes: "
          "%d public methods document every identifier they can raise, their "
          "private helpers' included, and every identifier is three-part (%s). "
          "%d test pins name an identifier something raises. Reach: "
          "+shLowLevel, the root functions, the three class files and "
          "tests/ - nothing else."
          % (checked, checked - len(backlog), tail, cchecked,
             "A21b drained its backlog in v5.0.0" if not cbacklog
             else "%d still in the A21b backlog" % len(cbacklog), pchecked))
    return 0


if __name__ == "__main__":
    sys.exit(main())
