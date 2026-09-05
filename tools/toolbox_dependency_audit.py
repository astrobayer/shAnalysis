#!/usr/bin/env python3
"""toolbox_dependency_audit: base MATLAB only, nothing else (v1.0.0).

Until 2026-09-05 this was enforced by construction rather than by a
gate: CI ran on a GitHub-hosted runner where setup-matlab installed
base MATLAB and nothing more, so any accidental dependency on an add-on
failed the moment it was introduced. CI now runs on a self-hosted
machine that carries base MATLAB *and* Parallel Computing Toolbox, so
that guard is gone - a parfor could be added tomorrow and CI would
stay green while every user without PCT broke.

This gate restores the guarantee without needing a second machine or a
second licence: it reads the source instead of the environment, so it
runs anywhere, on any platform, with no MATLAB at all.

Scope, stated rather than discovered:

* Comments are stripped, so help text may NAME a toolbox function while
  describing what the toolbox deliberately does not use. That is how
  pctile and chi2Quantile document themselves.
* Single-quoted strings are stripped too, because error messages are
  English prose and English contains words like "solve". Transpose is
  distinguished from a string opener by what precedes the quote, which
  is the standard heuristic and good enough here: the worst case is a
  retained string, i.e. a reported finding a human then dismisses.
* Detection is by name. A local function or variable shadowing a
  toolbox name would be reported; that is the intended trade, because
  such a shadow is confusing regardless.

Adding a legitimate exception means adding it to ALLOW with a reason,
which makes the decision reviewable in the diff rather than invisible.

Developed by Matthias Weigelt with the help of Claude (Sonnet 5),
2026-09-05.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Names that only resolve when an add-on product is installed. Grouped
# by product so a finding says WHICH licence a user would need.
#
# Kept to unambiguous, distinctive names. Generic ones (mean, std, fit,
# filter) are base MATLAB or too common to test by name, and generic
# short ones (pca, cov) would fire on local helpers.
PRODUCTS = {
    "Parallel Computing Toolbox": (
        r"\b(parfor|parpool|spmd|gcp|parfeval|parforOptions|"
        r"gpuArray|gpuDevice|codistributed|"
        r"createJob|createTask|ticBytes|tocBytes)\b"),
    "Statistics and Machine Learning Toolbox": (
        r"\b(fitlm|fitglm|fitrlinear|fitcsvm|fitctree|robustfit|"
        r"nlinfit|regress|anova\d*|ttest2?|kstest|normfit|"
        r"chi2inv|chi2cdf|tinv|tcdf|norminv|normcdf|finv|fcdf|"
        r"prctile|quantile|nanmean|nanstd|nansum|zscore|"
        r"pdist2?|linkage|kmeans|mahal|boxplot|histfit)\b"),
    "Signal Processing Toolbox": (
        r"\b(butter|cheby[12]|ellip|besself|freqz|filtfilt|firls|fir1|"
        r"periodogram|pwelch|spectrogram|findpeaks|resample|decimate|"
        r"hamming|hanning|blackman|kaiser|tukeywin)\b"),
    "Curve Fitting Toolbox": (
        r"\b(fittype|fitoptions|cfit|sfit|smoothingspline|csaps)\b"),
    "Optimization Toolbox": (
        r"\b(fmincon|fminunc|linprog|quadprog|lsqlin|lsqnonlin|"
        r"lsqcurvefit|intlinprog|fgoalattain)\b"),
    "Mapping Toolbox": (
        r"\b(geoshow|worldmap|axesm|shaperead|geotiffread|projfwd|"
        r"projinv|referenceEllipsoid|geodetic2ecef)\b"),
    "Image Processing Toolbox": (
        r"\b(imfilter|imresize|imerode|imdilate|bwlabel|regionprops|"
        r"imgaussfilt|imopen|imclose|graythresh|bwmorph)\b"),
    # 'sym', 'solve' and 'simplify' are deliberately absent: all three
    # are plausible local names. shCoefficients has a local parameter
    # literally called sym, and 'solve' appears in an error message.
    "Symbolic Math Toolbox": r"\b(syms|vpa|sym2poly|symfun)\b",
    "Financial Toolbox": r"\b(businessdate|isbusday|holidays|lbusdate)\b",
}

# Documented exceptions: "relative/path.m" -> reason. Empty on purpose.
# An entry here is a decision, and it shows up in review as a diff.
ALLOW = {}

SKIP_DIRS = {".git", "tools", "tests", "html", "docs", "test_data"}


def strip_strings(line):
    """Blank out single-quoted literals, leaving transpose alone.

    A quote opens a string unless the previous non-space character
    could end a value - an identifier char, a closing bracket, a dot or
    another quote - in which case it is the transpose operator. Both
    the delimiters AND the contents are replaced, because the contents
    are what carries the English prose.

    Inputs
      line  (str)  one line of MATLAB source, comments already gone

    Outputs
      (str)  same length, literal contents replaced by spaces
    """
    out = list(line)
    i, n, in_str = 0, len(line), False
    while i < n:
        c = line[i]
        if in_str:
            if c == "'":
                if i + 1 < n and line[i + 1] == "'":   # escaped quote
                    out[i] = out[i + 1] = " "
                    i += 2
                    continue
                out[i] = " "
                in_str = False
                i += 1
                continue
            out[i] = " "                                # string content
            i += 1
            continue
        if c == "'":
            prev = line[:i].rstrip()
            if prev and (prev[-1].isalnum() or prev[-1] in "_)]}.'"):
                i += 1                                  # transpose
                continue
            out[i] = " "
            in_str = True
        i += 1
    return "".join(out)


def strip_comments(text):
    """Remove MATLAB comments and string literals.

    Help text may NAME a toolbox function while describing what the
    toolbox deliberately does not use, and error messages are English
    prose, so both must go before matching.

    Inputs
      text  (str)  MATLAB source

    Outputs
      (str)  source with comments and single-quoted literals removed,
             line count preserved so reported numbers stay usable
    """
    out = []
    in_block = False
    for line in text.splitlines():
        stripped = line.strip()
        if in_block:
            out.append("")
            if stripped == "%}":
                in_block = False
            continue
        if stripped == "%{":
            in_block = True
            out.append("")
            continue
        i = line.find("%")
        # not inside a string literal - crude, but this gate only needs
        # to know whether a token survives outside a comment
        if i >= 0 and line[:i].count("'") % 2 == 0 \
                and line[:i].count('"') % 2 == 0:
            line = line[:i]
        line = re.sub(r'"[^"]*"', lambda m: " " * len(m.group(0)), line)
        out.append(strip_strings(line))
    return "\n".join(out)


def scan_source(rel, code):
    """Report add-on dependencies in one file's comment-stripped source.

    Inputs
      rel   (str)  repo-relative path, for the message
      code  (str)  source with comments already removed

    Outputs
      (list of str)  findings, one per match
    """
    if rel in ALLOW:
        return []
    findings = []
    for product, pattern in PRODUCTS.items():
        for m in re.finditer(pattern, code):
            line = code[:m.start()].count("\n") + 1
            findings.append(
                f"{rel}:{line}: '{m.group(0)}' needs {product} - "
                f"the toolbox must run on base MATLAB alone")
    return findings


def walk(root):
    """Yield (relative path, comment-stripped source) for toolbox files."""
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in sorted(filenames):
            if not fn.endswith(".m"):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            with open(full, encoding="utf-8", errors="replace") as fh:
                yield rel, strip_comments(fh.read())


def main():
    findings = []
    for rel, code in walk(ROOT):
        findings.extend(scan_source(rel, code))

    if findings:
        for f in findings:
            print(f)
        print(f"toolbox_dependency_audit: {len(findings)} finding(s)")
        return 1
    print("toolbox_dependency_audit: 0 findings - base MATLAB only")
    return 0


if __name__ == "__main__":
    sys.exit(main())
