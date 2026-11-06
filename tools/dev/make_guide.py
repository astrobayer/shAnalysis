"""make_guide.py - build docs/shAnalysis_workflow_guide.pdf (Edition 6).

The toolbox version and date on every page are read from Contents.m line 2
at build time, so a release bump needs no edit here.

Rebuilt after the original builder was lost; content reconstructed from the
shipped Edition-2 PDF, updated for v2.4.2, with all display equations
rendered as matplotlib mathtext (Computer Modern) images instead of the
former flattened inline text. Figures live in tools/dev/guide_assets/ IN
THE REPO - they were lost once when the container path they used to be
read from vanished, and were recovered from the shipped PDF.

Snippets are declared via code(\"\"\"...\"\"\") so check_api.py / mlint_lite can
lint every guide code block (gate 2).

Developed by Matthias Weigelt with the help of Claude (Fable 5), 2026-08-07.
"""
import hashlib
import os
import re

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

from reportlab.lib import colors  # noqa: E402
from reportlab.lib.pagesizes import A4  # noqa: E402
from reportlab.lib.styles import ParagraphStyle  # noqa: E402
from reportlab.lib.units import cm  # noqa: E402
from reportlab.platypus import (BaseDocTemplate, Frame, Image,  # noqa: E402
                                PageBreak, PageTemplate, Paragraph, Spacer,
                                Table, TableStyle, XPreformatted)

matplotlib.rcParams["mathtext.fontset"] = "cm"

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.environ.get("SHX_ROOT",
                       os.path.dirname(os.path.dirname(_HERE)))
OUT = os.environ.get("SHX_GUIDE_OUT",
                     os.path.join(_ROOT, "docs",
                                  "shAnalysis_workflow_guide.pdf"))
# figures live IN THE REPO (they were lost once when a container path
# vanished; recovered from the shipped PDF and committed since v3.1.2)
ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                      "guide_assets")
EQDIR = "/tmp/guide_eq"
os.makedirs(EQDIR, exist_ok=True)

import re as _re
_cm = open(os.path.join(_ROOT, "Contents.m")).read()
_mv = _re.search(r"% Version (\S+) \([^)]*\) (\S+)", _cm)
VERSION = "v" + _mv.group(1)
STAMP = ("shAnalysis %s - Workflow & Theory Guide - Developed by "
         "Matthias Weigelt with the help of Claude, %s"
         % (VERSION, _mv.group(2)))

PAGE_W, PAGE_H = A4
MARGIN = 1.9 * cm
TEXT_W = PAGE_W - 2 * MARGIN

# ----------------------------------------------------------------- styles
S = {}
S["body"] = ParagraphStyle("body", fontName="Helvetica", fontSize=9.3,
                           leading=12.3, spaceAfter=4)
S["bullet"] = ParagraphStyle("bullet", parent=S["body"], leftIndent=14,
                             bulletIndent=4, spaceAfter=2)
S["h1"] = ParagraphStyle("h1", fontName="Helvetica-Bold", fontSize=15,
                         leading=18, spaceBefore=10, spaceAfter=6, keepWithNext=1,
                         textColor=colors.HexColor("#1a3a5c"))
S["h2"] = ParagraphStyle("h2", fontName="Helvetica-Bold", fontSize=11.5,
                         leading=14, spaceBefore=9, spaceAfter=3, keepWithNext=1,
                         textColor=colors.HexColor("#1a3a5c"))
S["h3"] = ParagraphStyle("h3", fontName="Helvetica-Bold", fontSize=9.8,
                         leading=12, spaceBefore=7, spaceAfter=2, keepWithNext=1)
S["title"] = ParagraphStyle("title", fontName="Helvetica-Bold", fontSize=21,
                            leading=26, spaceAfter=4,
                            textColor=colors.HexColor("#1a3a5c"))
S["subtitle"] = ParagraphStyle("subtitle", fontName="Helvetica", fontSize=11,
                               leading=14, spaceAfter=14,
                               textColor=colors.HexColor("#444444"))
S["code"] = ParagraphStyle("code", fontName="Courier", fontSize=7.8,
                           leading=9.6)
S["caption"] = ParagraphStyle("caption", parent=S["body"], fontSize=8.6,
                              leading=11, textColor=colors.HexColor("#333333"),
                              spaceBefore=2, spaceAfter=10)
S["cell"] = ParagraphStyle("cell", parent=S["body"], fontSize=8.6,
                           leading=10.8, spaceAfter=0)
S["cellb"] = ParagraphStyle("cellb", parent=S["cell"],
                            fontName="Helvetica-Bold")

TBL = TableStyle([
    ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#b7c4d1")),
    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e8eef4")),
    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ("TOPPADDING", (0, 0), (-1, -1), 3),
    ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
])
TBL_PLAIN = TableStyle([
    ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ("TOPPADDING", (0, 0), (-1, -1), 2),
    ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
])
CODEBOX = TableStyle([
    ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#f4f6f8")),
    ("BOX", (0, 0), (-1, -1), 0.4, colors.HexColor("#c9d3dc")),
    ("LEFTPADDING", (0, 0), (-1, -1), 7),
    ("RIGHTPADDING", (0, 0), (-1, -1), 7),
    ("TOPPADDING", (0, 0), (-1, -1), 5),
    ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
])


# ------------------------------------------------------------- equations
def eq(tex, fontsize=11.5, pad=0.35):
    """Render display math via matplotlib mathtext -> centered Image."""
    key = hashlib.md5((tex + str(fontsize)).encode()).hexdigest()[:12]
    png = os.path.join(EQDIR, key + ".png")
    if not os.path.exists(png):
        fig = plt.figure(figsize=(0.01, 0.01))
        fig.text(0, 0, "$%s$" % tex, fontsize=fontsize)
        fig.savefig(png, dpi=300, bbox_inches="tight",
                    pad_inches=0.02, transparent=True)
        plt.close(fig)
    from PIL import Image as PILImage
    w, h = PILImage.open(png).size
    scale = 72.0 / 300.0
    wpt, hpt = w * scale, h * scale
    if wpt > TEXT_W - 20:
        f = (TEXT_W - 20) / wpt
        wpt, hpt = wpt * f, hpt * f
    img = Image(png, width=wpt, height=hpt)
    img.hAlign = "CENTER"
    return [Spacer(1, pad * 10), img, Spacer(1, pad * 10)]


def ieq(tex, fontsize=8.8):
    """Small equation image for table cells (left-aligned)."""
    key = hashlib.md5(("i" + tex + str(fontsize)).encode()).hexdigest()[:12]
    png = os.path.join(EQDIR, key + ".png")
    if not os.path.exists(png):
        fig = plt.figure(figsize=(0.01, 0.01))
        fig.text(0, 0, "$%s$" % tex, fontsize=fontsize)
        fig.savefig(png, dpi=300, bbox_inches="tight",
                    pad_inches=0.02, transparent=True)
        plt.close(fig)
    from PIL import Image as PILImage
    w, h = PILImage.open(png).size
    scale = 72.0 / 300.0
    img = Image(png, width=w * scale, height=h * scale)
    img.hAlign = "LEFT"
    return img


SNIPPETS = []


def code(src):
    """Register + typeset a MATLAB snippet (linted by check_api/mlint)."""
    SNIPPETS.append(src)
    pre = XPreformatted(src.strip("\n"), S["code"])
    t = Table([[pre]], colWidths=[TEXT_W])
    t.setStyle(CODEBOX)
    return [Spacer(1, 3), t, Spacer(1, 5)]


def para(txt, style="body"):
    return Paragraph(txt, S[style])


def bullets(items):
    return [Paragraph("&bull; " + it, S["bullet"]) for it in items]


def fig(png, caption, width=None):
    from PIL import Image as PILImage
    p = os.path.join(ASSETS, png)
    w, h = PILImage.open(p).size
    wpt = width or min(TEXT_W, w * 72.0 / 271.0)
    img = Image(p, width=wpt, height=wpt * h / w)
    img.hAlign = "CENTER"
    return [Spacer(1, 6), img, Paragraph(caption, S["caption"])]


def tbl(header, rows, widths, style=None):
    data = [[Paragraph(c, S["cellb"]) for c in header]]
    for r in rows:
        data.append([c if not isinstance(c, str)
                     else Paragraph(c, S["cell"]) for c in r])
    t = Table(data, colWidths=widths, repeatRows=1)
    t.setStyle(style or TBL)
    return [Spacer(1, 3), t, Spacer(1, 6)]


# ------------------------------------------------------------ page frame
def on_page(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 7)
    canvas.setFillColor(colors.HexColor("#666666"))
    canvas.drawString(MARGIN, 1.05 * cm, STAMP)
    canvas.drawRightString(PAGE_W - MARGIN, 1.05 * cm, "p. %d" % doc.page)
    canvas.restoreState()


doc = BaseDocTemplate(OUT, pagesize=A4,
                      leftMargin=MARGIN, rightMargin=MARGIN,
                      topMargin=1.6 * cm, bottomMargin=1.7 * cm,
                      title="shAnalysis Workflow & Theory Guide",
                      author="Matthias Weigelt with Claude (Fable 5)")
frame = Frame(MARGIN, 1.7 * cm, TEXT_W, PAGE_H - 3.3 * cm, id="main")
doc.addPageTemplates([PageTemplate(id="page", frames=[frame],
                                   onPage=on_page)])

story = []

# ================================================================= title
story += [Spacer(1, 30),
          para("shAnalysis Workflow &amp; Theory Guide", "title"),
          para("GRACE / GRACE-FO spherical-harmonic processing in base "
               "MATLAB &mdash; theory, best practices, and step-by-step "
               "recipes", "subtitle")]
story += tbl(["", ""], [
    ["Toolbox version", "shAnalysis " + VERSION],
    ["Edition", "6 (adds: evaluation on the ellipsoid, GIA uncertainty, "
                "data-driven leakage correction, model grids, Earth-rotation "
                "excitation, bridging the mission gap, and the numerical "
                "lanes as class methods)"],
    ["Scope", "ICGEM I/O, spectral diagnostics, synthesis &amp; analysis, "
              "destriping, Gaussian / DDK / tvANS filtering, VCE, basin "
              "averages &amp; deconvolution, climatology &amp; AR(1) "
              "significance, GIA, degree-1/C20 chain, Slepian localization, "
              "SINEX covariances, mascon comparison, load deformation, "
              "gradient tensor, multi-center combination, sea-level "
              "fingerprints, Love-number I/O incl. frame conversion, "
              "ICGEM series download, pole-tide conventions, pointwise "
              "synthesis at satellite altitude, the ellipsoidal surface, "
              "leakage correction, Kalman/VAR smoothing, Earth-rotation "
              "excitation, gap bridging, CF grids"],
    ["Dependencies", "base MATLAB only (no toolboxes); Java optionally for "
                     "gz streaming"],
    ["Validation", "every numerical method independently validated in "
                   "Python (numpy/scipy) before MATLAB implementation; "
                   "runAllTests (five suites) is the acceptance gate on "
                   "every pull request"],
    ["License", "MIT (see LICENSE; the DDK3 Wbd test fixture MIT from its "
                "upstream repository; ITSG/GFZ fixtures remain their "
                "providers' property)"],
    ["Provenance", "Developed by Matthias Weigelt with the help of "
                   "Claude (Fable 5), 2026-08-07"],
], [3.4 * cm, TEXT_W - 3.4 * cm],
    TableStyle([("GRID", (0, 0), (-1, -1), 0.4,
                 colors.HexColor("#b7c4d1")),
                ("BACKGROUND", (0, 0), (0, -1),
                 colors.HexColor("#e8eef4")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("TOPPADDING", (0, 0), (-1, -1), 3),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3)]))
story += [Spacer(1, 8),
          para("<b>How to read this guide.</b> Part I develops the theory "
               "exactly as implemented (equation forms match the code, "
               "including storage conventions and numerically validated "
               "tolerances). Part II condenses the best practices the "
               "implementation enforces or enables. Part IV is the "
               "complete API reference &mdash; every public function and "
               "method with typed, dimensioned inputs/outputs, defaults "
               "and a real-data example, generated from the source "
               "arguments blocks at build time. Part III gives "
               "copy-paste step-by-step recipes for the standard products. "
               "The HTML reference (<font face='Courier'>doc shAnalysis"
               "</font>) documents every function signature; this guide "
               "explains why and in which order."),
          PageBreak()]

# ========================================================== Installation
story += [para("Installation and data", "h1")]
story += [para("The toolbox itself needs nothing beyond base MATLAB. One "
               "call puts it on the path and, optionally, fetches the "
               "correction files the standard chain uses:")]
story += code("""
cd shAnalysis
setup_shAnalysis(Permanent = true, Download = "core")
% levels: "none" (path only) | "core" (TN-13/TN-14) | "filters" (+DDK)
%         | "starter" (+ a few ITSG months) | "all" (+ the complete ITSG
%         monthly archive, resumable);  DryRun = true shows the plan
shLowLevel.makeTutorials(Cases = "core");   % Live Scripts to open and run
""")
story += [para("Downloads land under a persistent data folder "
               "(<font face='Courier'>shLowLevel.dataFolder</font>), set "
               "once with <font face='Courier'>DataFolder=</font>. The "
               "fetchers throttle themselves and verify every file by "
               "parsing it before it replaces anything, so an interrupted "
               "download is resumable and never leaves a corrupt file in "
               "place.")]

story += [para("Opt-in test data", "h2")]
story += [para("Seven tests need data far too large to ship as fixtures, "
               "so each reads its location from an environment variable "
               "or a MATLAB preference and filters itself out when there "
               "is none. This is not tidiness: the fixture suite cannot "
               "see the class of failure that only appears on real data "
               "of real length &mdash; three such bugs were found the "
               "first time the toolbox was run against a full 24-year "
               "series, and the mascon reader's dimension order was only "
               "settled by a real product file.")]
story += tbl(["Test", "What it needs", "Where it looks"], [
    ["testPublishedTrendOnARealSeries (testScience)",
     "a folder of monthly GSM .gfc files, more than 24 epochs",
     "SHX_SERIES_FOLDER, the environment only"],
    ["testMasconReaderOnARealFile (testRobustness)",
     "a real mascon product: CSR (no login), GSFC, or JPL PO.DAAC",
     "SHX_MASCON_FILE"],
    ["testReadGridOnTheGravISGrid (testRobustness)",
     "the GravIS Level-3 TWS grid in the GravIS folder",
     "SHX_GRAVIS_FOLDER or preference GravisFolder"],
    ["testGravisChainsRealData (testContract)",
     "the GravIS folder, a monthly series and the DDK binaries",
     "SHX_GRAVIS_FOLDER, SHX_SERIES_FOLDER and SHX_DDK_FOLDER, or the "
     "preferences GravisFolder, SeriesFolder and DDKFolder"],
    ["testExcitationAgainstESMGFZ (testScience)",
     "the ESMGFZ angular momentum functions (ESMGFZ/HAM, ESMGFZ/SLAM) "
     "and a monthly series",
     "SHX_EARTHROTATION_FOLDER or preference EarthRotationFolder, plus "
     "the series"],
    ["testBridgeGapsAgainstGRACE (testScience)",
     "an HLSST series such as HLSST_SLR_COMB2023s, and a monthly series",
     "SHX_BRIDGE_FOLDER or preference BridgeFolder, plus the series"],
    ["testUserSuppliedSINEXFiles (testRobustness)",
     "SINEX files of your own (*.snx, *.snx.gz, up to ~30 MB)",
     "the test-data folder: SHX_TESTDATA_FOLDER or preference "
     "TestDataFolder"],
], [5.8 * cm, 4.9 * cm, TEXT_W - 10.7 * cm])
story += code("""
% five locations through setup: setenv for this session AND setpref
setup_shAnalysis(SeriesFolder = "D:/grace/itsg", ...
                 MasconFile = "D:/grace/GRCTellus_JPL.nc", ...
                 GravisFolder = "D:/grace/gravis", DDKFolder = "D:/grace/DDK");
% the other two as preferences
setpref("shAnalysis", "EarthRotationFolder", "D:/grace/earthRotation");
setpref("shAnalysis", "BridgeFolder", "D:/grace/hlsst");
""")
story += [para("<font face='Courier'>SHX_SERIES_FOLDER</font> is the one "
               "location read from the environment only, and only by the "
               "trend regression: a routine acceptance run must never "
               "reach for a network or archive drive, so that test runs "
               "only in a session that asked for it (setup exports the "
               "variable for the session; a setenv line in startup.m "
               "keeps it). None of the seven is required: without their "
               "data the suite runs complete and each reports as "
               "filtered rather than passing silently."),
          para("One more opt-in test needs no data, only time and memory "
               "(v5.27.2): testRegionalClosedLoopAtFullSize (testRobustness) "
               "runs the regional Kalman filter's closed loop at full size - "
               "one full SH normal matrix per month, carried into an RBF "
               "basis of the Elbe - and logs memory and wall time per degree "
               "to tests/closedloop_log.csv. It runs when "
               "<font face='Courier'>SHX_CLOSEDLOOP_NMAX</font> (e.g. "
               "\"60,96\") or the ClosedLoopNmax preference is set; on CI, "
               "run the workflow by hand with the input closed_loop_nmax. "
               "tools/dev/closed_loop_budget.py prints the prediction."),
          PageBreak()]

# ========================================================= Part I theory
story += [para("Part I &mdash; Theory as implemented", "h1")]

story += [para("0. What GRACE measures, for readers starting from zero", "h2"),
          para("Mass attracts. Every redistribution of water on and in the "
               "Earth &mdash; a monsoon soaking a river basin, an ice sheet "
               "shedding meltwater, groundwater pumped from an aquifer "
               "&mdash; changes the gravity field by a minute amount. The "
               "GRACE mission (2002&ndash;2017) and its successor GRACE-FO "
               "(2018&ndash;) measure exactly this: two satellites chase "
               "each other about 220 km apart on a near-polar orbit, and a "
               "microwave (GRACE) or laser (GRACE-FO) link measures their "
               "separation to micrometers or better. Flying toward extra "
               "mass, the leading satellite accelerates first and the gap "
               "stretches; the gap history maps the gravity field, month "
               "after month. The magic number to remember: converted to "
               "water, GRACE resolves changes of roughly a centimeter of "
               "water spread over a few hundred kilometers &mdash; enough "
               "to weigh continents breathing."),
          para("The monthly product is not a map but a set of a few "
               "thousand numbers: <b>Stokes coefficients</b>, the "
               "spherical-harmonic spectrum of the field (Section 1 "
               "explains the mathematics; for now: degree l is inverse "
               "wavelength, about 20000/l km, so degree 60 means ~330 km "
               "features). Everything in this toolbox starts from such "
               "coefficient files. The product vocabulary, once and for "
               "all:"),
          *bullets([
    "GSM &mdash; the monthly gravity solution, with atmosphere and ocean "
    "dynamics already subtracted by background models. GSM over land = "
    "water storage; GSM over the ocean = nearly nothing, ON PURPOSE.",
    "GAA/GAB/GAC/GAD &mdash; monthly means of exactly those subtracted "
    "background models (atmosphere / ocean / both / ocean bottom "
    "pressure). To study ocean mass you must ADD the right one back "
    "(Section 23); shLowLevel.fetchGAX provisions them.",
    "Monthly SINEX &mdash; the full normal-equation matrix of a solution "
    "(ITSG only), i.e. its complete error description; the key to the "
    "VDK filter (Sections 21&ndash;22). One month is ~460 MB.",
    "Daily Kalman solutions &mdash; low-resolution (n40) daily fields "
    "from ITSG, the basis of near-real-time flood tracking (Section 26).",
    "Mascons &mdash; an alternative representation on mass tiles with "
    "built-in regularization; readMascon reads CSR and JPL products."]),
          para("Two truths shape all processing. First, the raw monthly "
               "fields are STRIPED: the along-track sampling makes "
               "north&ndash;south errors much smaller than east&ndash;west "
               "ones, and unfiltered maps drown in meridional stripes "
               "&mdash; hence the whole filtering industry of Sections "
               "7&ndash;9 and 21. Second, low degrees are special: the "
               "satellites cannot see degree 1 (geocenter) at all and "
               "measure C20 poorly, so both are completed from external "
               "series (Section 16). Skipping either correction silently "
               "biases every trend you compute afterwards."),
]

story += [para("1. Spherical harmonics, normalization, storage", "h2"),
          para("The disturbing potential is expanded in fully "
               "(4&pi;-)normalized real spherical harmonics:")]
story += eq(r"V(r,\vartheta,\lambda)=\frac{GM}{R}\sum_{n=0}^{N}"
            r"\left(\frac{R}{r}\right)^{n+1}\sum_{m=0}^{n}"
            r"\left[\bar{C}_{nm}\cos m\lambda+\bar{S}_{nm}\sin m\lambda"
            r"\right]\bar{P}_{nm}(\cos\vartheta)")
story += [para("with the normalization &int;|Y<sub>nm</sub>|&sup2; "
               "d&Omega; = 4&pi;, the ICGEM convention. Throughout the "
               "toolbox coefficients live in lower-triangular matrices "
               "with 1-based indexing <font face='Courier'>C(n+1, m+1)"
               "</font>; vectorized orderings are always mediated by "
               "<font face='Courier'>shLowLevel.shIndex</font> (fields n, m, cs, "
               "P; Nmin defaults to 2 for GRACE work, 0 for "
               "analysis). GM and R ride with the data (read from the gfc "
               "header); the defaults (3.986004415e14, 6378136.3) are "
               "overridable, never baked-in physics. Load Love numbers "
               "k<sub>n</sub> for water-storage kernels must be supplied "
               "explicitly &mdash; the toolbox refuses to guess them.")]

story += [para("2. Legendre functions: scaled Holmes&ndash;Featherstone "
               "recursion", "h2"),
          para("Fully normalized associated Legendre functions are "
               "computed by the standard order-diagonal seed plus degree "
               "recursion. The naive diagonal seed underflows near the "
               "poles at high degree; <font face='Courier'>"
               "shLowLevel.legendreALF</font> therefore implements the globally "
               "scaled Holmes&ndash;Featherstone variant (scale "
               "10<super>-280</super>, rescaling on the fly), verified "
               "stable to degree 2190: the sum rule and parity")]
story += eq(r"\sum_{m=0}^{n}\bar{P}_{nm}^{\,2}(\cos\vartheta)=2n+1"
            r"\ \ (\sim 10^{-11}\ \mathrm{at}\ n=2190),\qquad"
            r"\bar{P}_{nm}(-\varphi)=(-1)^{n+m}\,\bar{P}_{nm}(\varphi)")
story += [para("hold across all latitudes; the parity relation halves the "
               "recursion cost on hemispherically symmetric grids (the "
               "parity trick).")]

story += [para("3. Synthesis", "h2"),
          para("Spatial synthesis evaluates, per latitude, the order sums")]
story += eq(r"A_m(\varphi)=\sum_{n=m}^{N}f_n\,\bar{C}_{nm}\,"
            r"\bar{P}_{nm}(\varphi),\qquad B_m(\varphi)\ \mathrm{"
            r"analogously\ with}\ \bar{S}_{nm},")
story += [para("then the longitude sum")]
story += eq(r"g(\varphi,\lambda)=\sum_{m=0}^{N}\left[A_m(\varphi)"
            r"\cos m\lambda+B_m(\varphi)\sin m\lambda\right].")
story += [para("For uniform full-circle longitude grids this last sum is "
               "an inverse FFT after folding aliased orders into "
               "mod(m, n<sub>lon</sub>) bins &mdash; exact, validated "
               "against the direct product to 3e-13 (<font face='Courier'>"
               "Method=\"auto\"|\"fft\"|\"direct\"</font>)."),
          para("<b>Memory model (v2.2).</b> The Legendre stack "
               "(n<sub>max</sub>+1)&sup2; &times; n<sub>lat</sub> &times; "
               "8 bytes is the memory driver: 7 GB at n<sub>max</sub> 2190 "
               "over 181 latitudes. Above the 'MaxMemGB' budget (default "
               "4), synthesis streams latitude bands: compute the Legendre "
               "block, fold into A<sub>m</sub>/B<sub>m</sub>, discard. "
               "Chunked equals monolithic exactly (Python-validated, max "
               "deviation 0.0); the class-level Legendre cache is bypassed "
               "automatically when the stack would not fit.")]

story += [para("<b>Scattered points (v5.1.0).</b> <font face='Courier'>"
               "shLowLevel.synthesisPoints</font> evaluates at arbitrary "
               "(latitude, longitude, radius), with the upward "
               "continuation a spherical grid cannot express. "
               "Method = \"clenshaw\" sums each order by Clenshaw's "
               "recursion on lumped coefficients and never forms the "
               "Legendre array; \"direct\" batches the Legendre functions "
               "and is bitwise the earlier path. In MATLAB clenshaw won at "
               "every point count measured (1 to 2000 points, nmax 60 to "
               "360), so \"auto\" picks it everywhere (v5.3.0): 2000 points "
               "at nmax 60 take 0.022 s on the CI machine against 2.28 s "
               "for the per-point code it replaced.")]

story += [para("4. Quantity kernels", "h2"),
          para("A single degree factor f<sub>n</sub> maps Stokes "
               "coefficients to the target quantity (<font face='Courier'>"
               "shLowLevel.kernelFactors</font>):")]
story += tbl(["quantity", "f<sub>n</sub>", "unit"], [
    ["geoid", ieq(r"R"), "m"],
    ["potential", ieq(r"GM/R"), "m&sup2;/s&sup2;"],
    ["gravity disturbance", ieq(r"\frac{GM}{R^2}\,(n+1)"), "m/s&sup2;"],
    ["gravity anomaly", ieq(r"\frac{GM}{R^2}\,(n-1)"), "m/s&sup2;"],
    ["EWH (water)",
     ieq(r"R\;\frac{\rho_{\mathrm{ave}}}{3\rho_w}\;\frac{2n+1}{1+k_n}"),
     "m"],
    ["surface density *",
     ieq(r"R\;\frac{\rho_{\mathrm{ave}}}{3}\;\frac{2n+1}{1+k'_n}"),
     "kg/m&sup2;"],
    ["bottom pressure *",
     ieq(r"g_0R\,\frac{\rho_{\mathrm{ave}}}{3}\,\frac{2n+1}{1+k'_n},"
         r"\quad g_0=\frac{GM}{R^2}"), "Pa"],
    ["vertical deformation *", ieq(r"R\;\frac{h'_n}{1+k'_n}"), "m"],
    ["gravity gradient T<sub>rr</sub> *",
     ieq(r"\frac{GM}{R^3}\,(n+1)(n+2)"), "1/s&sup2;"],
], [4.6 * cm, TEXT_W - 4.6 * cm - 2.3 * cm, 2.3 * cm])
story += [para("(* new in v2.3.) The 'Height' option continues "
               "potential-type kernels upward by (R/r)<super>p</super> "
               "(p = n+1 potential, n+2 anomaly/disturbance, n+3 "
               "T<sub>rr</sub>; validated against -d/dr and "
               "d&sup2;/dr&sup2; of the continued potential) &mdash; "
               "evaluate directly at satellite altitude. Surface "
               "quantities reject Height by contract."),
          para("The EWH kernel divides by (1+k<sub>n</sub>): the observed "
               "potential contains the solid-Earth loading response, which "
               "must be removed to recover surface mass. k<sub>n</sub> is "
               "always user-supplied (e.g. Wahr et al. 1998 or your "
               "loading-theory set of choice).")]

story += [para("5. Elastic load deformation (v2.3)", "h2"),
          para("A surface load deforms the elastic Earth; the displacement "
               "at the surface, expressed through the load-induced "
               "(residual) Stokes coefficients, is (Wahr et al. 1998):")]
story += eq(r"u_{\mathrm{up}}=R\sum_{n,m}\frac{h'_n}{1+k'_n}\,"
            r"\Delta\bar{C}_{nm}\,\bar{Y}_{nm},\qquad"
            r"u_{\mathrm{north}}=R\sum_{n,m}\frac{l'_n}{1+k'_n}\,"
            r"\Delta\bar{C}_{nm}\,\frac{\partial\bar{Y}_{nm}}"
            r"{\partial\varphi},\qquad"
            r"u_{\mathrm{east}}=R\sum_{n,m}\frac{l'_n}{1+k'_n}\,"
            r"\Delta\bar{C}_{nm}\,\frac{1}{\cos\varphi}\,"
            r"\frac{\partial\bar{Y}_{nm}}{\partial\lambda}", 10.5)
story += [para("The vertical is a pure degree factor ('deformation_up'); "
               "the horizontals need the exact spherical-harmonic "
               "gradient. <font face='Courier'>shLowLevel.legendreALFDeriv</font> "
               "provides d<font face='Courier'>Pbar</font>/d&phi; through "
               "a frozen identity &mdash; the (n,m) coefficient pattern "
               "(with &radic;2 corrections at m=0 and m=1 from the "
               "normalization of Pbar<sub>n0</sub>/Pbar<sub>n1</sub>) was "
               "calibrated by least squares against numerical "
               "differentiation and then frozen; residuals sit at the "
               "finite-difference floor (~1e-9). <font face='Courier'>"
               "shLowLevel.shSynthesisDeformation</font> / <font face='Courier'>"
               "g.deformation</font> evaluate all three components on "
               "grids or GNSS station lists (Mode=\"points\", "
               "LatType=\"geodetic\"); north/east validated point-wise "
               "against brute-force gradients to ~5e-10. Degree 0 is "
               "excluded; degree 1 is opt-in and only meaningful with "
               "consistent geocenter (CF/CE frame) handling; all three "
               "Love-number sets must come from ONE loading model. East "
               "is NaN at the poles (undefined direction).")]

story += [para("6. Analysis (the inverse problem)", "h2"),
          para("<font face='Courier'>shLowLevel.shAnalysisGrid</font> / "
               "<font face='Courier'>shCoefficients.analysis</font> "
               "estimate coefficients from data. Two regimes:")]
story += bullets([
    "<b>Ring grids</b> (uniform full-circle longitudes, arbitrary "
    "latitude rings): an FFT along longitude decouples the normal "
    "equations per order; each order solves a small least-squares over "
    "latitude rings. Exact recovery of band-limited input to ~8.7e-15 "
    "when the sampling theorem is met (n<sub>lat</sub> &ge; "
    "n<sub>max</sub>+1, n<sub>lon</sub> &ge; 2n<sub>max</sub>+1).",
    "<b>Scattered points</b>: chunked accumulation of full normal "
    "equations. Under-determined or ill-conditioned samplings (polar "
    "gaps, regional patches) need Kaula regularization: a diagonal prior"])
story += eq(r"\sigma^2_{\mathrm{prior}}(n)=\left(\frac{K}{n^{2}}"
            r"\right)^{2}")
story += [para("stabilizes the inversion at the cost of damping "
               "unconstrained coefficients toward zero. For regional data "
               "the mathematically cleaner route is Slepian localization "
               "(Section 12) &mdash; estimate only the ~N concentrated "
               "linear combinations the data can actually see.")]

story += [para("7. Destriping and Gaussian smoothing", "h2"),
          para("GRACE monthly solutions carry correlated north&ndash;south "
               "stripes: within one order and parity, coefficients of "
               "successive degrees correlate. The classic "
               "Swenson&ndash;Wahr destriper (<font face='Courier'>"
               "shLowLevel.shDestripe</font>) fits and removes a low-order "
               "polynomial across same-parity degree series per order "
               "(defaults: orders &ge; 8, polynomial order 2, window 5, "
               "all configurable). Gaussian smoothing "
               "(<font face='Courier'>shLowLevel.shGaussianFilter</font>) "
               "multiplies degree-wise by Jekeli weights from the "
               "recursion")]
story += eq(r"b=\frac{\ln 2}{1-\cos(r/R)},\qquad W_0=1,\qquad"
            r"W_1=\frac{1+e^{-2b}}{1-e^{-2b}}-\frac{1}{b},\qquad"
            r"W_{n+1}=-\frac{2n+1}{b}\,W_n+W_{n-1}")
story += [para("with the half-response radius r as the single tuning "
               "knob. Both are provided primarily as the baseline against "
               "which tvANS and DDK are judged.")]

story += [para("8. DDK anisotropic decorrelation (v2.2)", "h2"),
          para("The DDK filters (Kusche 2007; Kusche et al. 2009: "
               "DDK1&ndash;DDK8, ordered strong&rarr;weak) replace the "
               "scalar Gaussian weight by a full matrix per (order, C/S) "
               "block, derived from a GRACE error covariance and a signal "
               "prior &mdash; anisotropic, order-dependent smoothing that "
               "suppresses stripes with less signal attenuation than an "
               "equivalent Gaussian. <font face='Courier'>shLowLevel.readDDK"
               "</font> parses the released binary Wbd files natively "
               "(Rietbroek/Kusche BIN format; endian autodetect; verified "
               "to 4.4e-16 against the repository-documented DDK3 "
               "reference values; DDK1..8 = a_1d14p_4, 1d13, 1d12, 5d11, "
               "1d11, 5d10, 1d10, 5d9; Nmax= truncates an Lmax-120 filter "
               "to n96 series), plus .mat containers and an ASCII "
               "exchange layout; <font face='Courier'>applyDDK</font> "
               "applies block-wise c &rarr; M&middot;c, passing uncovered "
               "degrees through unchanged. Formal errors are invalidated "
               "by the filter (coefficients become correlated); propagate "
               "uncertainties with <font face='Courier'>shLowLevel.mcPropagate"
               "</font>."),
          para("<b>Note.</b> The real DDK3 file (Wbd_2-120.a_1d12p_4, "
               "MIT-licensed, from github.com/strawpants/GRACE-filter) "
               "is one of the test fixtures (shLowLevel.testDataDir finds it); the unit tests pin the parser "
               "to the repository-documented pack values. Degrees below "
               "the filter's Lmin (2) pass through unfiltered, as in the "
               "reference implementation.")]

story += [para("9. The tvANS filter (time-variable anisotropic "
               "noise/signal Wiener filter)", "h2"),
          para("The toolbox's flagship decorrelation filter. Model per "
               "month t: x = signal + noise with signal covariance S "
               "(estimated from the data themselves) and noise covariance "
               "s<sub>t</sub>N (a shape N, e.g. from a SINEX covariance "
               "or the built-in order/parity model, scaled monthly by VCE "
               "factors s<sub>t</sub>). The Wiener estimate of the "
               "residual field is")]
story += eq(r"\hat{x}_t=W_t\,x_t,\qquad W_t=S\,(S+s_tN)^{-1}")
story += [para("Implementation: one generalized symmetric "
               "eigendecomposition gives, for every month simultaneously,")]
story += eq(r"SU=NU\Lambda\ \ \Rightarrow\ \ W_t=V\,\mathrm{diag}\!"
            r"\left(\frac{\lambda_i}{\lambda_i+s_t}\right)U^{\mathsf{T}},"
            r"\qquad V=U^{-\mathsf{T}}")
story += [para("&mdash; O(P&sup2;) per month instead of a fresh P&sup3; "
               "solve. The deterministic model (bias/trend/annual/"
               "semi-annual) is removed first and restored after "
               "filtering; VCE factors are estimated from high-degree "
               "residuals via a robust median &chi;&sup2; estimator "
               "(<font face='Courier'>shLowLevel.vceRescale</font>). With a "
               "block-diagonal N (order/parity blocks), the whole "
               "machinery runs per block (Blocks=\"auto\"), tractable to "
               "Lmax &asymp; 120. External noise models join the block "
               "path when they are block-diagonal in the (order, C/S, "
               "parity) partition (verified, not assumed &mdash; v2.2.2); "
               "dense covariances fall back to the full path (auto) or "
               "error loudly (on)."),
          para("<b>Per-order-band VCE (v2.2).</b> One s<sub>t</sub> per "
               "month is coarse: striping strength varies with order. "
               "VCEBands=[0 16 33 61] estimates independent monthly "
               "factors per order band (block path only &mdash; band-wise "
               "scaling breaks the single global eigendecomposition, "
               "which the code asserts). The per-block factors are "
               "honored consistently in the filter application, the "
               "posterior sigmas, and the basin deconvolution covariance "
               "(identity of the banded block filter with the directly "
               "constructed W validated to 5.6e-16)."),
          para("<b>Posterior uncertainty.</b> The filtered-residual "
               "variance")]
story += eq(r"\mathrm{diag}\left((I-W_t)\,S\right)=(V\circ V)\;"
            r"\frac{s_t\lambda}{\lambda+s_t}")
story += [para("(validated 3.5e-16) is exposed as per-coefficient/month "
               "sigma stacks (<font face='Courier'>tsF.sigmaCs/Ss"
               "</font>). With hard constraints (v2.5) the EXACT diagonal "
               "of (W&minus;I)S(W&minus;I)' + s&middot;WNW' is used "
               "(O(P&sup2;q) in the eig basis, validated 2e-15 against "
               "the brute-force covariance; the constrained-direction "
               "identity Ac'&middot;Cov&middot;Ac = s&middot;Ac'NAc holds "
               "exactly). Honest correction: the earlier formula "
               "UNDERESTIMATED along constrained directions (ratios down "
               "to ~0.72) &mdash; the pre-v2.5 'upper bound' note had the "
               "direction wrong.")]

story += [para("10. Basin averages and deconvolution", "h2"),
          para("A basin kernel b (Section 11) gives the filtered basin "
               "series a<sub>t</sub> = b<super>T</super>x&#770;"
               "<sub>t</sub> / (b<super>T</super>b). Because filtering "
               "attenuates and leaks, <font face='Courier'>"
               "shLowLevel.basinDeconvolve</font> solves the small linear system "
               "that undoes the filter's action on a set of basin kernels "
               "B:")]
story += eq(r"c_t=A^{-1}B^{\mathsf{T}}\hat{x}_t,\quad "
            r"A=B^{\mathsf{T}}W_tB\ \ (K\times K);\qquad"
            r"\mathrm{cov}(c_t)=A^{-1}\left[G_v^{\mathsf{T}}\,"
            r"\mathrm{diag}(s_{\mathrm{vec}}\,g^2)\,G_v\right]"
            r"A^{-\mathsf{T}}")
story += [para("where g are the spectral gains and s<sub>vec</sub> the "
               "(possibly band-wise) monthly noise factors &mdash; the "
               "v2.2 form is exactly the v2.1 formula when bands are off. "
               "Ill-conditioned kernel sets accept a relative ridge "
               "(&lambda; = Ridge&middot;||A||), with the covariance "
               "consistently using the regularized inverse. Since v2.5 "
               "the basin sigma also carries the OLS parameter "
               "uncertainty of the restored deterministic part "
               "(design leverage h<sub>t</sub> &times; per-coefficient "
               "residual variance, carried on the operator; Monte-Carlo: "
               "emp/pred 1.18 without the term, 1.00 with it, 1.26 "
               "&rarr; 1.08 at seasonal leverage peaks), and with "
               "constraints the deconvolution noise covariance uses the "
               "exact constrained operator. The deterministic-part "
               "errors remain correlated across epochs through the "
               "shared fit (pointwise sigma; documented).")]

story += [para("11. Basin kernels: buffering and tapering (v2.2)", "h2"),
          para("<font face='Courier'>shLowLevel.basinKernel</font> builds "
               "b = Y<super>T</super>(w&middot;mask) by exact "
               "Gauss&ndash;Legendre quadrature from a polygon, mask, or "
               "f(lat,lon) handle. Two leakage controls:")]
story += bullets([
    "<b>BufferKm</b>: grow/shrink the region by exact great-circle "
    "distance before quadrature (trade leakage-in against leakage-out; "
    "computed in latitude chunks, practical to Lmax ~ 96).",
    "<b>TaperKm</b>: multiply the kernel spectrally by Jekeli Gaussian "
    "weights &mdash; soft edges suppress the ringing of the truncated "
    "indicator. Rule of thumb: taper radius &asymp; the coefficient "
    "filter's half-response radius."])
story += [para("The quadrature area fraction is returned; b(1) equals it "
               "exactly (Y<sub>00</sub> = 1), which the tests pin down.")]

story += [para("12. Slepian localization (v2.2)", "h2"),
          para("For a region R, the concentration problem maximizes the "
               "energy ratio over band-limited g = Yx:")]
story += eq(r"\lambda=\frac{\int_{R}g^{2}\,d\Omega}"
            r"{\int_{\Omega}g^{2}\,d\Omega}\ \rightarrow\ \max,"
            r"\qquad K=Y^{\mathsf{T}}\mathrm{diag}(w\cdot\mathrm{mask})"
            r"\,Y,\qquad N_{\mathrm{Shannon}}=\sum_i\lambda_i="
            r"\frac{A_R}{4\pi}\,P")
story += [para("Eigenvectors (Slepian tapers) are orthonormal; "
               "eigenvalues are concentrations in [0,1]; the Shannon "
               "number (exact by the addition theorem &mdash; the trace "
               "identity the tests verify) counts the tapers the region "
               "supports. Regional analysis then estimates ~N Slepian "
               "coefficients a = G<super>T</super>x instead of P Stokes "
               "coefficients &mdash; well-posed by construction, no Kaula "
               "prior needed. Validated on the 30&deg; polar cap: "
               "&lambda; bounds to 4e-16, orthonormality 3e-15.")]

story += [para("<font face='Courier'>shLowLevel.slepianProject</font> "
               "projects a coefficient stack onto the tapers and rebuilds "
               "the part of the field they carry; <font face='Courier'>"
               "g.slepianProject</font> and <font face='Courier'>"
               "ts.slepianProject</font> (v5.13.0) do the same for one "
               "field or every epoch of a series.")]

story += [para("13. Climatology, alias periods, AR(1) significance "
               "(v2.2)", "h2"),
          para("<font face='Courier'>ts.climatology()</font> fits bias, "
               "trend, annual and semi-annual terms (plus optional extra "
               "periods) per coefficient. GRACE tidal aliasing puts S2 at "
               "161 d, K2 at 3.66 yr, K1 at 7.48 yr: "
               "Periods=[161/365.25, 3.66, 7.48] keeps these out of trend "
               "and semi-annual estimates. Per-coefficient 1-sigma "
               "significance comes from the OLS covariance (weighted and "
               "robust variants available) and rides on every component "
               "accessor, enabling significance-masked maps."),
          para("<b>AR(1) correction.</b> GRACE residuals are temporally "
               "correlated; white-noise sigmas are optimistic. "
               "ARCorrect=true estimates the lag-1 residual "
               "autocorrelation r<sub>1</sub> per coefficient and "
               "inflates sigmas by")]
story += eq(r"\sigma_{\mathrm{AR(1)}}=\sigma\;\sqrt{\frac{1+r_1}{1-r_1}}")
story += [para("&mdash; the standard first-order effective-sample-size "
               "correction, since v2.5 applied to the Kendall bias-"
               "corrected r<sub>1</sub>' = r<sub>1</sub> + "
               "(1+3r<sub>1</sub>)/T. Monte-Carlo validation: uncorrected "
               "sigmas underestimate the empirical trend scatter by "
               "2.00&times; (&phi; = 0.6, T = 120); with the raw-"
               "r<sub>1</sub> inflation the ratio is 1.065, with the "
               "bias-corrected r<sub>1</sub> 1.028 (1.152 &rarr; 1.079 "
               "at T = 60). Still first-order and slightly conservative "
               "&mdash; the residual few percent stems from the "
               "regression absorbing low-frequency noise.")]

story += [para("14. GIA correction (v2.2)", "h2"),
          para("Secular Stokes trends mix present-day mass change with "
               "glacial isostatic adjustment. <font face='Courier'>"
               "ts.removeGIA(gia)</font> subtracts rate&middot;"
               "(t - T<sub>0</sub>) per epoch; <font face='Courier'>"
               "clim.removeGIA(gia)</font> corrects a fitted trend "
               "directly &mdash; both routes agree identically (tested to "
               "1e-13). GIA models (ICE-6G_D, Caron et al., A/W13, ...) "
               "are user-supplied gfc rate files, never embedded. The "
               "model's own uncertainty, often the dominant regional "
               "trend error (Laurentia, Fennoscandia, Antarctica), "
               "propagates too since v5.2.0: <font face='Courier'>"
               "ts.removeGIA(gia, Sigma = s)</font> adds the rate sigma "
               "times |t &minus; T<sub>0</sub>| in quadrature to every "
               "epoch's sigmas &mdash; correct MARGINAL sigmas &mdash; "
               "and returns the rate sigma itself in <font face='Courier'>"
               "info.rateSigmaC/S</font>. That second output is the one "
               "a trend needs: one rate error applies to every epoch, so "
               "the GIA term is perfectly correlated in time, and a trend "
               "fitted from per-epoch sigmas that assume independence "
               "understates it by about &radic;T (measured 3.49&times; "
               "against &radic;T = 3.46). Without a sigma field, "
               "differencing several models remains the spread "
               "estimate.")]

story += [para("15. Geocentric vs. geodetic latitude (v2.2)", "h2"),
          para("All SH mathematics here runs in geocentric latitude; "
               "maps, GIS products and mascon grids are geodetic:")]
story += eq(r"\tan\varphi'=(1-f)^{2}\,\tan\varphi")
story += [para("with the WGS84 flattening as overridable default. The "
               "difference peaks at 0.192&deg; (~21 km) near 45&deg; "
               "&mdash; large enough to visibly bias basin averages and "
               "point comparisons. Synthesis, analysis and "
               "shAnalysisGrid accept LatType=\"geodetic\" and convert "
               "internally.")]

story += [para("16. The degree-1 / C20 completion chain", "h2"),
          para("GRACE does not observe geocenter motion (degree 1), and "
               "its C20 is weak: the standard product chain is GSM + "
               "TN-14 (C20/C30 from SLR) + TN-13 (degree-1). "
               "<font face='Courier'>shLowLevel.readTN14</font> and "
               "<font face='Courier'>shLowLevel.readTN13</font> parse the "
               "official technical notes (TN-13 verified against the real "
               "GFZ RL06 file: 256 paired months 2002-04 to 2026-04, "
               "including the 2017.4&ndash;2018.4 gap); "
               "<font face='Courier'>ts.addDegree1</font> and the "
               "C20/C30 replacement close the chain with epoch matching "
               "and provenance notes in the history.")]

story += [para("A TN-13 table is one source of degree 1; the data "
               "themselves are the other. <font face='Courier'>"
               "shLowLevel.estimateDegree1</font> (v3.6.0) implements "
               "Swenson, Chambers &amp; Wahr (2008): the degree-1 terms "
               "are whatever, added to the field, make its ocean part "
               "agree with an ocean model &mdash; a small least-squares "
               "problem per epoch over the ocean domain. Its output has "
               "the TN-13 layout, so <font face='Courier'>ts.addDegree1"
               "</font> takes either, and <font face='Courier'>"
               "ts.estimateDegree1</font> (v5.13.0) is the method form. "
               "Omitting the ocean model attributes real ocean signal to "
               "the geocentre, and a warning says so.")]

story += [para("17. Normal field and (GM, R) conventions (v2.4)", "h2"),
          para("Geoid maps need the DISTURBING field: subtract the "
               "ellipsoidal normal potential. <font face='Courier'>"
               "shLowLevel.normalFieldCS</font> computes the even zonals from "
               "the WGS84/GRS80 defining constants (GM, a, f, &omega;) "
               "via the Heiskanen&ndash;Moritz closed form "
               "(q<sub>0</sub> series &rarr; J<sub>2</sub> &rarr; "
               "J<sub>2n</sub>) &mdash; no coefficient tables; validated "
               "against NIMA TR8350.2 to all published digits. Crucially, "
               "WGS84 GM (3.986004418e14) and a (6378137.0) DIFFER from "
               "the ICGEM conventions (3.986004415e14, 6378136.3): "
               "<font face='Courier'>g.subtractNormalField</font> "
               "rescales the ellipsoid field to the model's (GM, R) "
               "first via")]
story += eq(r"\bar{C}'_{nm}=\bar{C}_{nm}\;\frac{GM_1}{GM_2}"
            r"\left(\frac{R_1}{R_2}\right)^{n}")
story += [para("(<font face='Courier'>shLowLevel.rescaleGMR</font> / "
               "<font face='Courier'>g.toReference</font>; the physical "
               "field is invariant &mdash; verified by synthesizing the "
               "potential at a common radius from both representations). "
               "Skipping the rescaling costs millimetres. The arithmetic "
               "operators refuse GM/R-mismatched operands "
               "(shCoefficients:operands:constantsMismatch) instead of silently "
               "mixing conventions. Permanent tide: the ellipsoid is "
               "tide-free by construction; the model's C20 tide system "
               "(ICGEM header) is NOT converted silently &mdash; "
               "zero-tide vs tide-free differ by ~4.2e-9 in "
               "Cbar<sub>20</sub>.")]

story += [para("18. Multi-center combination (v2.4)", "h2"),
          para("Several centers observe the same monthly field with "
               "different noise. One variance factor per (center, month) "
               "&mdash; the COST-G granularity &mdash; estimated by "
               "Foerstner iteration with PARTIAL redundancies:")]
story += eq(r"\hat{x}=\left(\sum_c w_cN_c^{-1}\right)^{-1}"
            r"\sum_c w_cN_c^{-1}x_c,\qquad "
            r"s_c^{2}=\frac{v_c^{\mathsf{T}}N_c^{-1}v_c}{r_c},\qquad "
            r"r_c=P-\mathrm{tr}\!\left(H\,w_cN_c^{-1}\right)")
story += [para("Without r<sub>c</sub> the factors bias low "
               "(v<sub>c</sub> is correlated with x&#770;). Noise shapes "
               "N<sub>c</sub> come from each center's own climatology "
               "residuals as (order, C/S, parity) blocks; the whole "
               "iteration runs block-wise. Robust=true replaces the "
               "global ratio by the median of per-block unbiased "
               "estimates q<sub>b</sub>/r<sub>b</sub>. The empirical "
               "shapes are trace-normalized, so the factors carry each "
               "center's absolute noise power and are directly comparable "
               "(weights invariant; v2.4.1). Two limits are structural: "
               "common-mode errors (shared K-band data, AOD1B, tides) are "
               "invisible to inter-center VCE &mdash; posterior sigmas "
               "are a LOWER bound &mdash; and inter-center correlations "
               "violate independence; info.interCenterCorr quantifies the "
               "optimism. Combine GSM before TN-14/TN-13, then apply the "
               "replacements once.")]

story += [para("19. Elastic sea-level fingerprints (v2.4)", "h2"),
          para("A melting ice mass does not raise the ocean uniformly: "
               "the ocean surface follows the perturbed geoid minus the "
               "deformed crust, under global mass conservation (Farrell "
               "&amp; Clark 1976, elastic limit):")]
story += eq(r"S=\mathcal{O}\,(N-U+\kappa),\qquad "
            r"\int_{\mathrm{ocean}}\rho_w\,S\;dA="
            r"-\int_{\mathrm{land}}\sigma\;dA")
story += [para("<font face='Courier'>shLowLevel.seaLevelFingerprint</font> "
               "iterates this on the toolbox's exact Gauss&ndash;Legendre "
               "quadrature pair. Validation: mass conserved to machine "
               "precision, ~11 iterations, and the classic pattern "
               "&mdash; sea level FALLS near the melting mass (lost "
               "self-attraction plus rebound; validation run: near field "
               "-0.3 mm vs far field +0.8 mm about a +0.6 mm eustatic "
               "mean per unit load). Elastic only, no rotational "
               "feedback, fixed coastlines.")]

story += [para("20. Gravity gradient tensor (v2.4)", "h2"),
          para("<font face='Courier'>shLowLevel.shSynthesisGradientTensor"
               "</font> synthesizes all six NEU components at altitude; "
               "second Legendre derivatives come from the frozen "
               "first-derivative stencil applied twice (exact identity). "
               "Every call self-checks the Laplace invariant "
               "trace(G) = 0, validated at 7e-16 of max|G|; "
               "G<sub>uu</sub> is bit-consistent with the "
               "'gravity_gradient_rr' kernel route. 1 Eotvos = 1e-9 "
               "s<super>-2</super>."),
          PageBreak()]

story += [para("21. Time-variable decorrelation: the VDK/VADER filter "
               "(v3.13)", "h2"),
          para("Sections 8&ndash;9 introduced the Wiener family: damp each "
               "coefficient by how much you trust it. The DDK filter fixes "
               "ONE synthetic error model for the whole mission; tvANS "
               "estimates one empirical structure from the series itself. "
               "Both assume the error STRUCTURE never changes &mdash; but "
               "it does: orbit height decays, ground tracks enter and "
               "leave short repeat cycles, instruments age. The VDK filter "
               "(Horvath et al. 2018; VADER in the paper) uses the actual "
               "monthly normal-equation matrix N from the ITSG SINEX:"),
          *eq(r"x_\alpha = (N + \alpha M)^{-1} N\, x"),
          para("with M the inverse signal variance (a Kaula rule "
               "a&thinsp;l<sup>b</sup> per calendar month, estimated by "
               "signalVarianceKaula with an exact log-chi-square bias "
               "correction) and &alpha; the strength knob. With "
               "S&nbsp;=&nbsp;M<sup>-1</sup> this is ALGEBRAICALLY the "
               "tvANS form S(S+&alpha;N<sup>-1</sup>)<sup>-1</sup> &mdash; "
               "same family, different inputs, and the difference is worth "
               "15% median error and an order of magnitude in bad months "
               "(paper Table 2). The price: the one-eigendecomposition "
               "trick of tvANS requires a stationary structure, so VDK "
               "pays one Cholesky factorization per month instead "
               "(seconds at n96). vdkApply never forms the filter matrix; "
               "tools/dev/run_vdk_series.m drives the archive-scale batch."),
          *fig("t04_wiener.png",
               "Figure T4 &mdash; the Wiener principle behind DDK, tvANS "
               "and VDK (computed illustration). (a) Signal follows a "
               "falling Kaula law while GRACE errors rise with degree; "
               "(b) the resulting gain damps degrees where noise wins. "
               "VDK recomputes the gain every month from the measured N."),
          *code("""idx = shLowLevel.shIndex(96, Nmin= 2);
f = shLowLevel.fetchITSGSINEX("2018-06", Nmax = 96);   % ~460 MB, deliberate
snx = shLowLevel.readSINEX(f(1), Index = idx);     % N + x in idx order
[ab, ~] = shLowLevel.signalVarianceKaula(ts.Cs, ts.Ss, ts.epochs);
xf = shLowLevel.vdkApply(snx.x, snx.M, idx.n, ab(6, :), Alpha = 1);""")]

story += [para("22. Normal equations and SINEX, demystified", "h2"),
          para("A monthly solution is a least-squares estimate: the "
               "satellites provide millions of range observations, the "
               "unknowns are the ~9400 Stokes coefficients (n96, degrees "
               "2&ndash;96), and the NORMAL-EQUATION MATRIX "
               "N&nbsp;=&nbsp;A<sup>T</sup>PA condenses the whole "
               "adjustment: its inverse is the error covariance, its "
               "structure encodes which coefficient combinations that "
               "month's orbit could or could not see. SINEX is simply the "
               "exchange format that ships x, N and metadata in labelled "
               "blocks; the ITSG monthly files carry "
               "SOLUTION/NORMAL_EQUATION_MATRIX as a packed triangle "
               "&mdash; hence 460 MB. readSINEX streams the blocks and "
               "reorders everything onto a shIndex layout, verified "
               "against exactly this product. COST-G distributes no "
               "per-month SINEX (their combination happens internally), "
               "so ITSG is the only public source."),]

story += [para("23. Ocean mass: restoring GAX, barystatic sea level and "
               "OBP (v3.10&ndash;3.11)", "h2"),
          para("Because GSM has ocean dynamics removed by construction, "
               "the honest recipe for ocean-mass questions is: restore "
               "what was subtracted, then average. oceanChain adds the "
               "monthly GAD field (ocean bottom pressure) back, subtracts "
               "GAA over the ocean to avoid double-counting atmosphere, "
               "filters, masks (|lat| &le; 66&deg; away from the crude "
               "coasts) and area-averages to the barystatic curve "
               "&mdash; the ocean-mass part of sea-level rise, "
               "+1.41&thinsp;&plusmn;&thinsp;0.03 mm/yr in the shipped "
               "acceptance on COST-G (published range ~1.6&ndash;2.2; "
               "Section 24 explains the gap's main suspect). obpChain "
               "keeps the FIELDS instead (GravIS OBP recipe: GAD before "
               "the filter, reference period 2002/04&ndash;2020/03, land "
               "NaN). The pixel residuals still contain real ocean "
               "circulation; SeparateCirculation splits them by EOF with "
               "a Marchenko&ndash;Pastur significance limit &mdash; modes "
               "are only removed where they rise above what pure noise "
               "eigenvalues could produce."),
          *code("""[out, rep] = shLowLevel.oceanChain(ser, kn = kn, OceanMask = oc, ...
    GADFolder = gadF, GAAFolder = gaaF, SeparateCirculation = true);
[out.trend, out.nModes, out.sigMon]""")]

story += [para("24. Coastal leakage: buffers and support separation "
               "(v3.15)", "h2"),
          para("A band-limited field has no sharp edges: truncate any "
               "coastline at degree 60&ndash;96 and it rings; filter it "
               "and land signal smears hundreds of kilometers into the "
               "ocean. Greenland alone biases the North Atlantic mean "
               "visibly. Two controls, both quantified before they were "
               "built. CoastBufferKm erodes the ocean mask by a "
               "great-circle distance (shLowLevel.erodeMask): for "
               "gauss445, 300 km removes 54% of a coastal point-source "
               "leak, 500 km 82%, at under 1% ocean-area loss. "
               "RemoveLandLeakage attacks the cause: separate the field "
               "into land-supported and ocean-supported band-limited "
               "components by two-sided alternating projections "
               "(Papoulis&ndash;Gerchberg style) and subtract the land "
               "part BEFORE filtering. The pre-validation taught a hard "
               "lesson worth stating in bold: a naive ONE-step "
               "subtraction makes the leak WORSE, because the "
               "reconstruction of the outside field rings INTO the mask. "
               "The two-sided iteration (LandLeakIter = 5) cuts an "
               "adjacent-source leak of 47% of the ocean mean by 94%."),
          *fig("t05_leak_pocs.png",
               "Figure T5 &mdash; the 1D reference experiment behind the "
               "v3.15 leakage controls (computed, identical mathematics "
               "to the sphere). (a) A band-limited land source adjacent "
               "to the ocean mask leaks under filtering; (b) two-sided "
               "support separation converges within a few sweeps to a "
               "small fraction of the raw leak &mdash; the CI test "
               "freezes the <0.5 criterion, the converged value is ~0.06."),]

story += [para("25. Hydrological extremes: standardized indices (v3.14)",
               "h2"),
          para("A TWS anomaly of &minus;12 cm means nothing by itself: is "
               "that a dry month for THIS place and season, or business "
               "as usual? Standardized indices answer by comparing "
               "against the local seasonal climatology. The GRACE-DSI "
               "(Zhao et al. 2017) is the z-score per calendar month, "
               "binned into the 11 USDM-style classes D4 (exceptional "
               "drought, z &le; &minus;2) through W4; it agrees with "
               "USDM, PDSI, SPEI, NDVI and in-situ groundwater in the "
               "validation literature &mdash; while seeing the FULL "
               "storage column including groundwater, which no "
               "precipitation-based index does. Two policies are "
               "measured, not assumed: DETREND FIRST (a 0.5 cm/yr GIA or "
               "depletion trend weakens a planted exceptional-drought "
               "month from &minus;2.41 to &minus;1.44 &mdash; out of its "
               "class &mdash; and turns 45% of the late decade spuriously "
               "wet), and a robust sigma option (one corrupt month "
               "inflates the classical sigma sixfold; the 1.4826&middot;"
               "MAD not at all). For floods, the causal Reager storage "
               "deficit S<sub>def</sub>(t) = max of the past minus the "
               "last state measures how much water the basin can still "
               "take; with a precipitation grid it becomes the full "
               "Flood Potential Index behind multi-month lead times "
               "(Reager et al. 2014)."),
          *fig("t07_dsi.png",
               "Figure T7 &mdash; the DSI construction on the "
               "pre-validation experiment (computed). The planted "
               "&minus;2.5&sigma; event keeps its D4 class only when the "
               "trend is removed first; the class edges are the USDM "
               "convention."),
          *fig("t08_sdef.png",
               "Figure T8 &mdash; the causal storage deficit (computed "
               "illustration): zero at a running maximum, growing as the "
               "basin dries; small deficit means flood-prone."),
          *code("""B = ts.toGrid(-89.5:89.5, 0.5:359.5, Quantity = "ewh", kn = kn);
[Z, ih] = shLowLevel.hydroExtremeIndex(B.Z, ts.epochs);
ih.categoryNames(ih.category(iLat, iLon, end) + 6)""")]

story += [para("26. Daily solutions and near-real-time monitoring "
               "(v3.14 stage 2)", "h2"),
          para("Monthly fields cannot see a two-week flood wave. The ITSG "
               "daily Kalman solutions (n40, one gfc per day, fetchITSG "
               "Product = &quot;daily&quot;) can &mdash; Gouweleeuw et al. "
               "(2018) tracked major Ganges&ndash;Brahmaputra floods this "
               "way. hydroExtremeIndex switches automatically to a "
               "day-of-year climatology on daily input: means per exact "
               "DOY, sigma from the RESIDUALS in a circular 31-day window "
               "that wraps December into January, with the sqrt(n/(n-1)) "
               "correction for the estimated mean. The construction is "
               "measured, not assumed: window sigma on RAW values leaks "
               "the seasonal cycle (1.99 instead of 1.5), the two-stage "
               "form does not; a planted +3&sigma; January-2nd flood "
               "scores z = 2.9 straight across the year boundary."),]

story += [para("27. Temporal smoothing: Kalman filtering with VAR "
               "process models (v3.21&ndash;3.26)", "h2"),
          para("Every method so far treats months independently. But mass "
               "redistribution has memory: the field of one epoch predicts "
               "the next. Kurtenbach (2012) and Kvas (2019) built the ITSG "
               "daily solutions on exactly this idea &mdash; a "
               "vector-autoregressive (VAR) process model inside a Kalman "
               "filter &mdash; and the module implements their chain end "
               "to end: estimateVAR, kalmanFilter, rtsSmoother, "
               "buildCondFun, neqCombine, with kalmanChain as the single "
               "point of access."),
          para("The process and observation model", "h3"),
          para("The reduced (climatology-removed) coefficient vector "
               "x<sub>t</sub> follows a VAR(p); observations are either "
               "solutions with covariance (l = x + v) or normal "
               "equations (N x = b) consumed in information form. For "
               "p = 1 the Yule&ndash;Walker solution is Kurtenbach's "
               "closed form:")]
story += eq(r"B=\Sigma(1)\,\Sigma(0)^{-1},\qquad "
            r"Q=\Sigma(0)-B\,\Sigma(0)\,B^{\mathsf{T}}")
story += [para("Higher orders embed into the companion form; the filter "
               "starts stationary (x&#8320;&#8315; = 0, "
               "P&#8320;&#8315; = &Sigma;(0)), which makes the forward "
               "filter plus RTS smoother an EXACT solver of the joint "
               "block-tridiagonal least-squares adjustment over all "
               "epochs (Kvas Sec. 2.3) &mdash; pinned in the test suite "
               "to 1e-15 (Python) and 1e-9 (MATLAB) against the "
               "explicitly built batch system. Gap months become "
               "prediction-only and relax toward the prior at the rate "
               "the estimated dynamics dictate."),
          para("Choosing the process model: measured, not assumed", "h3"),
          para("The first live VAR table (ITSG monthly n40, T = 257, "
               "36-month holdout, one-step coefficient RMS, computed "
               "through the shipped estimator) settled the defaults:")]
story += fig("kalman_var_table.png",
             "Figure: one-step holdout RMS per process model on the live "
             "monthly series. The dense VAR(1) at weak shrink is WORSE "
             "than no dynamics at all (overfit at T &asymp; 0.13 P); the "
             "structured estimators beat climatology-only by 21&ndash;23%; "
             "p &ge; 2 explodes. Order = 1 confirmed.")
story += [para("Consequence in the API: estimateVAR "
               "Structure = &quot;full&quot; | &quot;diagonal&quot; | "
               "&quot;orderblock&quot;. For MONTHLY series use "
               "&quot;orderblock&quot; (one block per order m and C/S "
               "&mdash; kalmanChain builds the partition itself) or "
               "&quot;diagonal&quot;; the dense default targets the "
               "DAILY regime, where Kurtenbach's production choice is "
               "dense plus spatial conditioning (buildCondFun: the Kvas "
               "EWH-domain land/ocean masks with the "
               "exp(&minus;&psi;/&psi;&#8320;) taper, PSD by the Schur "
               "product theorem &mdash; it turns a singular empirical "
               "&Sigma;(0) into a usable one, measured rcond "
               "0 &rarr; 5.7e-2)."),
          para("What the filter does to real data", "h3")]
story += fig("kalman_live_run.png",
             "Figure: the live run on the monthly residual series "
             "(orderblock VAR(1), formal sigmas as R). Left: the smoother "
             "leaves the signal-dominated low degrees at 95% and halves "
             "the noise-dominated n = 40 band. Right: Kurtenbach's "
             "contribution diagnostic diag(K) &mdash; the share of each "
             "estimate coming from the DATA; the process model carries a "
             "third of the estimate at high degrees.")
story += [para("Honest scope note: an 11&deg;-cap basin average of the "
               "same run changes by 2% RMS only (measured ratio 0.979) "
               "&mdash; basin averaging is itself a low-pass, so on "
               "monthly data the module's value sits at coefficient "
               "level, in the propagated sigmas, and in the machinery "
               "below. The DAILY regime it targets is different: there "
               "the process model is the difference between unusable "
               "and usable fields (Kurtenbach), and a live acceptance "
               "against the published ITSG daily series is on the "
               "roadmap, waiting on public daily normal equations."),
          para("Robustness machinery, each decided on measurement", "h3"),
          *bullets([
    "Innovation QC (Kvas Sec. 3.3, v3.21): per-epoch chi-square test "
    "T = d'S&#8315;&sup1;d (solution form, dof = P) or "
    "u'(N P&#8315; N + N)&#8314; u (NEQ form, dof = rank(N)); identical "
    "when N = R&#8315;&sup1;. QC = &quot;reject&quot; turns a failing "
    "epoch into prediction-only &mdash; essential in a RECURSIVE "
    "estimator, where one accepted blunder propagates into every later "
    "state (test: rejecting one 50-sigma epoch cuts downstream error "
    "by &gt; 20%). Thresholds from the base-MATLAB Wilson&ndash;"
    "Hilferty quantile, accuracy measured against scipy.",
    "Joseph-stabilized update (v3.22): decided on a 50-digit-reference "
    "A/B, not textbook habit &mdash; with R small against a "
    "wide-spectrum prior (the strong-daily-data regime) the standard "
    "(I&minus;K)P update loses six orders of covariance accuracy "
    "(1.3e-6 vs 1.9e-13). Exact-arithmetic identical otherwise.",
    "Multi-center (v3.23): a string array of SINEX folders is grouped "
    "by epoch and combined by neqCombine (per-epoch VCE or fixed "
    "weights) BEFORE the update; rep.sigma2 reports the factors.",
    "Bounded memory and latency (v3.19/v3.24): StoreCov = "
    "&quot;matfile&quot; keeps year-long full-covariance runs flat in "
    "RAM (bit-identical to in-memory); rtsSmoother Lag = L bounds the "
    "latency for near-real-time production (Lag = 0 is the filter, "
    "Lag &ge; T&minus;1 the full smoother to rounding). With "
    "QC = &quot;reject&quot; this is the complete bounded-latency "
    "chain; the daily output feeds hydroExtremeIndex directly "
    "(chapter 26)."]),
          para("The one-call form", "h3")]
story += code("""idx = shLowLevel.shIndex(40);
ts   = shSeries.fromFolder(folder, Truncate = 40);
[tsK, rep] = shLowLevel.kalmanChain(ts, ModelSeries = ts, ...
    Structure = "orderblock", Shrink = 1e-2, QC = "reject");
plot(rep.epochs, rep.qcStat); yline(shLowLevel.chi2Quantile(0.999, idx.P));""")
story += [para("For SINEX normal equations replace the first argument by "
               "the folder (or a string array of folders, one per "
               "center); kalmanChain reads, epoch-groups, VCE-combines "
               "and filters in information form, and returns the "
               "smoothed shSeries with propagated sigmas plus the full "
               "report (model, contribution, QC record). For a series in "
               "solution mode, <font face='Courier'>ts.kalman(ModelSeries "
               "= tsm)</font> (v5.6.0) is the method form of the same "
               "call.")]

# ------------------------------------------------ v5 chapters (v5.13.1)
story += [para("28. Evaluating on the ellipsoid (v5.5.0)", "h2"),
          para("Every synthesis in Sections 3&ndash;5 evaluates on the "
               "sphere r = R. The Earth's surface is much closer to the "
               "WGS84 ellipsoid, whose geocentric radius at geocentric "
               "latitude &phi; is")]
story += eq(r"r(\varphi)=a\,\sqrt{\frac{1-e^{2}}{1-e^{2}\cos^{2}\varphi}},"
            r"\qquad e^{2}=f\,(2-f)")
story += [para("(<font face='Courier'>shLowLevel.ellipsoidRadius</font>, "
               "the one place the toolbox computes it). "
               "<font face='Courier'>Surface = \"ellipsoid\"</font> in "
               "shSynthesis and shSynthesisGradient, and in the class "
               "methods synthesis, gradient, toGrid and map, moves every "
               "point to r(&phi;) + Height and applies the radial law "
               "(R/r)<super>p</super> of Section 4 there. The difference "
               "is largest at the poles, where the ellipsoid lies 21.4 km "
               "inside the sphere: (R/b)<super>n+2</super> is 1.23 at "
               "n = 60, 1.39 at n = 96 and 1.84 at n = 180. Only "
               "quantities with a radial law accept the option &mdash; "
               "potential, gravity anomaly and disturbance, "
               "T<sub>rr</sub>. The geoid is refused on purpose: on the "
               "ellipsoid it also needs the latitude-dependent normal "
               "gravity &gamma;(&phi;), and moving the radius alone would "
               "be half a correction. The semi-major axis is WGS84's "
               "a = 6378137 m, not the coefficients' R: R belongs to the "
               "series, a to the surface. The sphere path is bitwise "
               "unchanged, and f = 0 with a = R reproduces it bitwise. "
               "Station lists go through synthesisPoints, which takes a "
               "radius per point; latitudes must be geocentric &mdash; a "
               "geodetic 45&deg; taken as geocentric misplaces the radius "
               "by 71.8 m.")]
story += code("""
dg  = g.synthesis(-90:0.5:90, 0:0.5:359.5, ...
          Quantity = "gravity_disturbance", Surface = "ellipsoid");
r   = shLowLevel.ellipsoidRadius(latSta) + hSta;   % a radius per station
dgS = g.synthesisPoints(latSta, lonSta, r, Quantity = "disturbance");
""")

story += [para("29. Leakage correction without a model (v5.4.0, v5.9.0)",
               "h2"),
          para("Guide G12 corrects leakage by forward modelling, which "
               "needs a mask, or by scaling factors, which need a "
               "hydrological model. The method of deviation (Vishwakarma "
               "et al. 2017) needs neither. Split the true field g into "
               "its part inside the catchment (catchment function R) and "
               "the rest. For any filter that leaves a constant alone "
               "&mdash; the Gaussian does &mdash; the filtered catchment "
               "average splits with no approximation:")]
story += eq(r"\bar{g}_c=f_c+\Delta F_c+l_c\quad\Rightarrow\quad"
            r"\hat{f}_c=\bar{g}_c-\Delta\hat{F}_c-\hat{l}_c")
story += [para("&mdash; the wanted mean f<sub>c</sub>, the deviation "
               "integral &Delta;F<sub>c</sub> (what the filter does to the "
               "catchment's own signal because it is not a uniform layer, "
               "weighted by the FILTERED catchment function) and the "
               "leakage l<sub>c</sub> smeared in from outside. Both "
               "corrections need the unfiltered g; the method estimates "
               "them from the once- and twice-filtered fields and "
               "extrapolates one filtering step back. The leakage "
               "extrapolation corrects a PHASE as well as an amplitude "
               "(Hilbert regression, Phillips et al. 2012) &mdash; "
               "out-of-phase leakage is exactly what a scale factor cannot "
               "repair &mdash; while the deviation integral deliberately "
               "gets none: the thesis measured those phase differences and "
               "found no consistent relation. Both steps are regressions "
               "over time, so the function refuses fewer than 12 epochs "
               "and refuses NaN, and the method is designed for catchments "
               "of about 65000 km&sup2; and up."),
          para("<b>The method of scale</b> (Method = \"scale\", v5.9.0) "
               "removes the same leakage estimate and scales the rest:")]
story += eq(r"\hat{f}_c=s\,(\bar{g}_c-\hat{l}_c),\qquad "
            r"s=\frac{\int R\,d\Omega}{\int R\,\bar{R}\,d\Omega}")
story += [para("s depends on the catchment and the filter alone, and "
               "INFO.scale reports it whichever method ran. It is exact "
               "only for a uniform layer inside the catchment, and it "
               "grows as the catchment shrinks, amplifying errors. The "
               "closed loops favour it (75% of the filtering damage "
               "removed against 55% on the testCorrectness fixture), but "
               "both fixtures put a uniform layer inside the catchment "
               "&mdash; the one case it is exact for &mdash; so that ranks "
               "nothing, and the method of deviation stays the default.")]
story += code("""
% ewh: nLat x nLon x T fields that already saw a 300 km Gaussian
[fHat, info] = shLowLevel.leakageDataDriven(ewh, lat, lon, ...
    Mask = basin, Filter = "gauss300");
[info.phaseDeg, info.leakageRatio, info.scale]
fS = shLowLevel.leakageDataDriven(ewh, lat, lon, Mask = basin, ...
    Filter = "gauss300", Method = "scale");        % the method of scale
fT = ts.leakageDataDriven(lat, lon, Filter = "gauss300", kn = kn, ...
    Mask = basin);                                 % from a series (v5.6.0)
""")

story += [para("30. Model grids into coefficients (v5.8.0)", "h2"),
          para("Hydrological models and the GravIS Level-3 products come "
               "as CF netCDF grids. <font face='Courier'>"
               "shLowLevel.readGrid</font>, the inverse of writeGrid, "
               "reads one: dimensions are found by name and returned as "
               "(lat, lon, time), longitudes come back in 0..360 "
               "ascending, fill values as NaN, and the time axis is "
               "decoded by the toolbox's one CF time decoder, the one "
               "readMascon uses. It changes no numbers: it neither regrids "
               "nor fills, and it does not assume the latitude type "
               "&mdash; INFO.latType reports what writeGrid recorded, and "
               "an empty string for a grid from elsewhere, whose "
               "latitudes are geographic, that is geodetic. A land-only "
               "grid comes back with NaN over the ocean, and "
               "<font face='Courier'>shCoefficients.analysis</font> "
               "refuses NaN until Fill = value says what the gaps mean "
               "(0 for no mass there): a NaN would otherwise reach every "
               "coefficient. Since v5.12.1 <font face='Courier'>"
               "shLowLevel.shAnalysisGrid</font> refuses NaN as well.")]
story += code("""
[tws, lat, lon, info] = shLowLevel.readGrid(gravisFile, Var = "tws");
info.units, info.latType                  % check both before going on
gT = shCoefficients.analysis(tws(:, :, 1), lat, lon, 96, ...
    Quantity = "ewh", kn = kn, Fill = 0, LatType = "geodetic");
""")

story += [para("31. Earth-rotation excitation (v5.10.0, v5.11.0)", "h2"),
          para("Mass that moves on and in the Earth changes its inertia "
               "tensor and so its rotation, and the degree-2 Stokes "
               "coefficients are that tensor's time-variable part: C21 and "
               "S21 excite polar motion, C20 the length of day. Chen "
               "&amp; Wilson (2003, eq. 1, after Eubanks 1993), solved "
               "for the excitation:")]
story += eq(r"\chi_1=-\frac{1.098\,R^{2}M}{(1+k'_2)\,\sqrt{3/5}\,(C-A)}"
            r"\,\Delta C_{21},\qquad \chi_2\ \mathrm{likewise\ with}\ "
            r"\Delta S_{21}")
story += eq(r"\chi_3=-\frac{0.753\,R^{2}M\,2\sqrt{5}}{(1+k'_2)\,3C}\,"
            r"\Delta C_{20},\qquad \Delta\mathrm{LOD}=\frac{2\pi}{\Omega}"
            r"\,\chi_3")
story += [para("&Delta;LOD is the ESMGFZ convention (Dobslaw &amp; Dill "
               "2019, eq. 2.8, read as a time). <font face='Courier'>"
               "ts.excitation(kn = kn, TN14 = tn)</font> returns "
               "&chi;<sub>1</sub> and &chi;<sub>2</sub> in mas and, with a "
               "TN-14 table, &chi;<sub>3</sub> and &Delta;LOD in ms from "
               "the SLR C20 &mdash; GRACE's own C20 is the coefficient it "
               "determines worst. The Earth's constants default to the "
               "IERS Conventions (2010), Table 1.1: M = GM/G, C &minus; A = "
               "J<sub>2</sub>Ma<sub>E</sub>&sup2;, C = (C &minus; A)/H, "
               "R = a<sub>E</sub>, which agree with the ESMGFZ values of C "
               "and A to 0.03%; Earth = struct(...) takes your own. Three "
               "things the excitation is not. A GSM series has the "
               "atmosphere and the ocean removed, so it is the excitation "
               "of the rest &mdash; restore GAC first for the whole mass "
               "term. The motion term (winds, currents) is never in a "
               "gravity field. And &chi;<sub>2</sub> points to 90&deg;E "
               "in the coefficients' frame, while the IERS pole y "
               "coordinate points to 90&deg;W. C21/S21 also depend on the "
               "mean-pole convention of the pole-tide removal: convert "
               "with poleTideConvert before comparing series processed "
               "differently."),
          para("The factors 1.098 and 0.753 are options (PolarFactor, "
               "AxialFactor). ESMGFZ's prefactors give 1.101 for the "
               "polar terms, 0.3% apart, but 0.844 for the axial one, 12% "
               "more &mdash; close to the whole Earth's axial moment over "
               "the mantle's, which some authors put into the axial "
               "term. The opt-in testExcitationAgainstESMGFZ compares "
               "GRACE's excitation with the ESMGFZ hydrological and "
               "sea-level angular momentum functions.")]
story += code("""
tn = shLowLevel.readTN14(tn14File);
[tbl, info] = ts.excitation(kn = kn, TN14 = tn);   % t, chi1, chi2, chi3, dLOD
plot(tbl.t, tbl.dLOD); ylabel("dLOD [ms]")
info.earth                                         % the constants used
""")

story += [para("32. Bridging the mission gap (v5.12.0)", "h2"),
          para("Between the last GRACE month and the first GRACE-FO month "
               "lie eleven months without a K-band solution (2017-07 to "
               "2018-05), and GRACE lost scattered months to battery "
               "management before that. High-low satellite-to-satellite "
               "tracking of low orbiters such as Swarm, combined with SLR, "
               "covers them at lower resolution (Weigelt et al. 2024). "
               "<font face='Courier'>shLowLevel.bridgeGaps</font> and "
               "<font face='Courier'>ts.bridgeGaps</font> fill every month "
               "the reference series lacks within its span from such a "
               "series, calibrated on the months both have. Both are "
               "truncated to the lower nmax and smoothed with a Gaussian "
               "of RadiusKm (750 by default) &mdash; the whole output, so "
               "its resolution does not jump. Per coefficient, the means "
               "over the overlap give an offset, which also absorbs a "
               "difference in tide system or reference field; per degree, "
               "a scale regresses the reference's anomalies on the "
               "bridge's:")]
story += eq(r"\tilde{c}_{nm}(t)=R_{0,nm}+s_n\left(B_{nm}(t)-B_{0,nm}\right),"
            r"\qquad s_n=\frac{\sum\Delta B\,\Delta R}{\sum\Delta B^{2}}")
story += [para("The sigma of a filled month is the RMS over the overlap of "
               "the calibration residual &mdash; the fill's error as the "
               "reference itself sees it &mdash; because the formal sigmas "
               "of the HLSST series are too small at low degrees, by a "
               "factor 3 to 6 for the Kalman-filtered variant. Measured "
               "on COST-G RL02.1 against the Kalman-filtered "
               "QuantumFrontiers HLSST_SLR_COMB2023s at 750 km (208 "
               "overlap months), the fill's error over degrees 3&ndash;60 "
               "is 41% of the GRACE signal with the scale and 45% without; "
               "the unfiltered HLSST variant gives 62% and 92%. A filled "
               "month is named bridge: followed by its name in the bridge "
               "series, and INFO.bridged marks it, so the flag travels "
               "with the epochs through select, truncate and every other "
               "method. Apply TN-14 to the reference first: TN-14 has no "
               "C20 between the missions, and a filled month keeps the "
               "bridge series' own C20, which an HLSST + SLR combination "
               "determines from SLR as well.")]
story += code("""
tsG = shSeries.read("GSM-2_*.gfc").applyTN14(tnFile);   % TN-14 first
tsH = shSeries.read(fullfile(hlFolder, "*.gfc"));        % HLSST + SLR
[ts, info] = tsG.bridgeGaps(tsH, RadiusKm = 750);
ts.names(info.bridged)                                   % "bridge:..." months
[info.overlap, nnz(info.bridged)]
""")
story += [para("Since v5.25.0 the same HLSST series can enter the Kalman "
               "chain instead, as a second observation group "
               "(<font face='Courier'>SecondSeries</font> on "
               "<font face='Courier'>shLowLevel.kalmanChain</font> and "
               "<font face='Courier'>ts.kalman</font>). It is calibrated on "
               "the overlap like the fill - an offset per coefficient, a "
               "scale and a noise per degree, the scale corrected for the "
               "reference's own noise - but then observes every month it "
               "has, weighted by that noise, and the process model carries "
               "the GRACE information into the gap from both sides. In the "
               "closed loop of validate_kalman_bridge.py the gap error at "
               "750 km is 0.34 of the signal against 0.46 for the "
               "calibrated fill; on real data it has not been measured "
               "yet. A Kalman run holds two full covariances per epoch, so "
               "run it on a window around the gap.")]
story += code("""
[tsK, rep] = tsG.kalman(ModelSeries = tsm, SecondSeries = tsH);
tsK.epochs(rep.observedBy == "second")                   % gap months
rep.second.scale                                         % s_n per degree
""")
story += [para("The climatology from the normal equations (v5.26.0)", "h3"),
          para("<font face='Courier'>shLowLevel.neqClimatology</font> estimates "
               "the six terms of a climatology from every month's normal "
               "equation rather than from filtered solutions. A month's "
               "deviation from the climatology, with covariance Sigma_d "
               "(DeviationCov), is reduced from its normal equation, which "
               "leaves the contribution W = (I + N Sigma_d)^-1 N and never "
               "inverts N. With Sigma_d = 0 the result is the generalized "
               "least-squares fit of the solutions with their full "
               "covariances. The gain comes from the month-to-month change "
               "of the noise pattern. With stripes whose direction changes "
               "every month the trend error is 0.44 of an equal-weight "
               "fit's in the synthetic closed loop of "
               "validate_neq_climatology.py; with a covariance of the same "
               "shape every month it is nil. On real data the gain has not "
               "been measured. The solve holds three (6P x 6P) matrices, "
               "about 4 GB each at nmax 60, so truncate with Nmax.")]
story += code("""
[clim, info] = shLowLevel.neqClimatology(itsgFolder, Nmax = 40, ...
    DeviationCov = sigd .^ 2);
tr = clim.trend;                                         % with tr.sigmaC
""")
story += [para("Low degrees estimated jointly (v5.28.0)", "h3"),
          para("<font face='Courier'>shLowLevel.neqAddCoefficients</font> "
               "adds C20/C30 from TN-14 and degree 1 from TN-13 to a "
               "monthly normal equation as pseudo-observations (value and "
               "1-sigma), instead of substituting them into the solution. "
               "It extends the index down to degree 1 when needed. C20 and "
               "C30 are then estimated jointly: the normal equation's "
               "correlations carry the SLR information into the other "
               "coefficients. The gain is set by those correlations: 0.99 "
               "of substitution's error for the other zonals at a C20 "
               "correlation of 0.12, 0.75 at 0.77, in the synthetic design "
               "of validate_neq_low_degree.py. On real normal equations it "
               "has not been measured. Degree 1 is exactly substitution: a "
               "GRACE normal equation holds no degree-1 information, so "
               "TN-13 cannot count GRACE twice, and it adds nothing beyond "
               "substitution either. The values must match the normal "
               "equation's tide system, GM and R.")]
story += code("""
obs = struct('n', [2; 3], 'm', [0; 0], 'cs', [0; 0], ...
    'value', [tn.C20(k); tn.C30(k)], 'sigma', [tn.sigmaC20(k); tn.sigmaC30(k)]);
[neq, idx2] = shLowLevel.neqAddCoefficients(snx, idx, obs);
x = neq.N \\ neq.b;                                         % in idx2 order
""")

story += [para("33. Regional bases for a selectable basin (v5.14.0)", "h2"),
          para("The first step towards a regional Kalman filter after "
               "Kurtenbach (2012) whose state is a set of LOCAL basis "
               "functions. Every basis is a linear map to spherical-harmonic "
               "coefficients, x = T a with T of size P x K, so an SH "
               "solution or normal equation enters it as T'NT and T'b, a "
               "grid or point functional as A T, and a model series through "
               "a projector; on the SH basis itself (T = I) the regional "
               "filter is the global one, which is its oracle. "
               "<font face='Courier'>shLowLevel.readBasin</font> finds a "
               "GravIS basin by name or a unique part of it and returns a "
               "wrap-safe region: basins across lon 0 (Loire, Niger, Volta) "
               "and rings around a pole are inside where they should be. "
               "Since v5.21.0 the GravIS chains take their basin masks from "
               "it too, which closes Antarctic basin 302 through the pole "
               "(1.2 percent of the Antarctic area the old rule left out). "
               "<font face='Courier'>shLowLevel.regionalBasis</font> builds "
               "radial basis functions after Eicker (2008) and Woehnke et "
               "al. (2025), Slepian tapers, or the SH basis, for the region "
               "grown by BufferKm (600 km, Woehnke's computation area). A "
               "radial basis function centred on node x_k is the Legendre "
               "series")]
story += eq(r"\Psi_k(x)=\sum_{n}\varphi_n\,(2n+1)\,P_n(\cos\psi_k),"
            r"\qquad T_{nm,k}=\varphi_n\,\bar{Y}_{nm}(x_k),"
            r"\qquad \varphi_n=\frac{\sigma_n}{\sqrt{2n+1}}")
story += [para("with the shape coefficients from the signal's degree "
               "amplitudes (Woehnke's eq. 7), Kaula's 1/n<super>2</super> "
               "(the default) or one. Nodes are an icosahedral grid of "
               "10(j+1)<super>2</super> + 2 points or a Reuter grid, the "
               "default level the smallest whose global grid is as large as "
               "the SH basis (j = 30 at nmax 96); a node belongs to the "
               "basis when its nearest quadrature point lies in the "
               "buffered region. The projector is the least-squares fit "
               "over that region,")]
story += eq(r"P=\left(T^{\mathsf{T}}KT\right)^{+}T^{\mathsf{T}}K,"
            r"\qquad K=Y^{\mathsf{T}}\mathrm{diag}(w\,m)\,Y,")
story += [para("which for Slepian tapers is exactly G' (2.2e-15 in the "
               "oracle), so <font face='Courier'>regionalProject</font> "
               "generalises <font face='Courier'>slepianProject</font>. Only "
               "the grid points inside the buffered region are formed. "
               "Measured in tools/dev/validate_regional_basis.py: the radial "
               "basis function against scipy's Legendre series to 1.2e-14, "
               "the projector's normal equations to 2e-11, and the Elbe "
               "polygon's area, 140 031 km<super>2</super>, against the mask "
               "quadrature (3.6% below it at nmax 60). The process model, "
               "the observation adapters and the filter on this state "
               "come next.")]
story += code("""
idx = shLowLevel.shIndex(60);
B = shLowLevel.regionalBasis(idx, "Elbe");          % RBF, Kaula kernel
S = shLowLevel.regionalBasis(idx, "Elbe", Type = "slepian", Threshold = 0.5);
[a, rec] = ts.regionalProject(ts.regionalBasis("Elbe"));   % K x T state
[B.K, B.nGlobal, S.K]
""")
story += [para("Mascons (v5.27.0)", "h3"),
          para("<font face='Courier'>Type = \"mascon\"</font> puts "
               "spherical caps of radius CapRadiusKm on the same nodes, each "
               "a uniform layer of 1 m equivalent water height, so that the "
               "coefficients are the caps' EWH in metres - the quantity "
               "mascon products report (Watkins et al. 2015). The cap "
               "indicator expands as")]
story += eq(r"\chi(\psi)=\sum_n c_n P_n(\cos\psi),\quad "
            r"c_0=\frac{1-t_0}{2},\quad c_n=\frac{P_{n-1}(t_0)-P_{n+1}(t_0)}{2},"
            r"\quad T_{nm,k}=\frac{c_n}{(2n+1)\,f_n}\,\bar{Y}_{nm}(x_k),")
story += [para("with t<sub>0</sub> = cos psi<sub>0</sub> and f<sub>n</sub> "
               "the EWH kernel of <font face='Courier'>kernelFactors</font>, "
               "so a mascon is a radial basis function with the cap kernel "
               "and shares its node selection and projector; the load Love "
               "numbers kn are required. The default radius is equal-area, "
               "cos psi<sub>0</sub> = 1 - 2/N for the N nodes of the global "
               "grid: 201.7 km at nmax 60. A band-limited cap is not a cap - "
               "its centre value is 1 - (P<sub>L</sub>(t<sub>0</sub>) + "
               "P<sub>L+1</sub>(t<sub>0</sub>))/2, 0.73 for that default "
               "cap - and caps neither tile nor are orthogonal: a smooth 1 m "
               "layer projects to interior caps of median 1.02 m with a "
               "spread of 0.53 to 1.20 (nmax 30). Measured in "
               "tools/dev/validate_regional_mascon.py: c<sub>n</sub> against "
               "40-digit values to 4e-17, a column of T against scipy's "
               "Legendre series to 9.4e-14, the projector at a resolvable "
               "level to 1.1e-14.")]
story += code("""
LN = shLowLevel.readLoveNumbers(loveFile);  kn = LN.kn(1:61);
M = ts.regionalBasis("Elbe", Type = "mascon", kn = kn);   % equal-area caps
ewh = ts.regionalProject(M);                              % K x T cap EWH [m]
M.capRadiusKm
""")

story += [para("34. The process model in a regional basis (v5.15.0)", "h2"),
          para("The second step towards the regional Kalman filter: "
               "Kurtenbach's (2012) stochastic process model, estimated in "
               "the coefficients of the basis of chapter 33. "
               "<font face='Courier'>shLowLevel.regionalProcessModel</font> "
               "and <font face='Courier'>ts.regionalProcessModel</font> "
               "remove the climatology of a geophysical model series (mean, "
               "trend, annual, semi-annual), project every epoch onto the "
               "basis, a = P x, and estimate the VAR model from the basis "
               "coefficients. The climatology is a fit along time with one "
               "design for every coefficient and the projection a map along "
               "the coefficients, so the two commute (6e-16 in the oracle). "
               "For order 1 the estimate is Kurtenbach's")]
story += eq(r"B=\Sigma(1)\,\Sigma(0)^{-1},\qquad "
            r"Q=\Sigma(0)-B\,\Sigma(1)^{\mathsf{T}},")
story += [para("and on the SH basis it is, bit for bit, the model "
               "<font face='Courier'>kalmanChain</font> builds. His two "
               "adjustments are options. QScale multiplies Q alone (his eq. "
               "4.8): with alpha = 10 the largest error RMS of his closed "
               "loop fell from 4.83 to 3.41 cm EWH and the mean from 1.12 to "
               "1.01 cm, because an underestimated process variance "
               "suppresses signal while an overestimated one costs little. "
               "GroundNoise adds an isotropic, temporally uncorrelated "
               "variance to Sigma(0), his 2 cm EWH for the real data; it is "
               "read as the white EWH field band-limited to the index, "
               "sigma<super>2</super>/(P f<sub>n</sub><super>2</super>) per "
               "Stokes coefficient, whose pointwise variance is exactly "
               "sigma<super>2</super> by the addition theorem. It changes B "
               "as well as Q, and in his simulation it made results worse, "
               "so both default to off. info.representation reports the "
               "share of the model's regional signal energy the basis "
               "carries. Measured in tools/dev/validate_regional_process.py: "
               "a VAR(1) simulated in an RBF basis is recovered through the "
               "whole pipeline within the sampling error over 60 seeds.")]
story += code("""
B = tsModel.regionalBasis("Elbe", Type = "slepian", Threshold = 0.5);
[model, info] = tsModel.regionalProcessModel(B, QScale = 10);
[info.representation, model.specRadius, info.minEigQ]
""")

story += [para("35. Observations as normal equations in the basis (v5.16.0)", "h2"),
          para("The third step: every level of gravity information becomes a "
               "normal equation in the basis coefficients, so that one regional "
               "state can be updated by all of them. "
               "<font face='Courier'>shLowLevel.regionalNEQ</font> reduces each "
               "kind to a design A in the basis and the covariance C of its data, "
               "and forms")]
story += eq(r"N=A^{\mathsf{T}}C^{-1}A,\qquad b=A^{\mathsf{T}}C^{-1}y,"
            r"\qquad l^{\mathsf{T}}Pl=y^{\mathsf{T}}C^{-1}y")
story += [para("through the Cholesky factor of C (Woehnke et al. 2025, eq. A6). "
               "An SH solution with its covariance has A = T; an SH normal "
               "equation - a SINEX NEQ, or a GNSS loading equation built by "
               "another toolbox - enters as T'NT and T'b; point functionals "
               "in any quantity of kernelFactors have the design row "
               "f<sub>n</sub> (R/r)<super>p<sub>n</sub></super> Y<sub>nm</sub>, "
               "and with a direction the row is the gradient along it - the "
               "gravity vector for the potential - from the north, east and "
               "up derivatives. A combination matrix forms differences, the "
               "shape of a line-of-sight gravity difference. The result is a "
               "neqCombine contribution with l'Pl and the observation count, "
               "so several kinds of one epoch combine with variance "
               "components before they update the filter. Measured in "
               "tools/dev/validate_regional_observations.py: the point design "
               "against the Legendre series of an RBF to 4e-15, the "
               "directional design against its analytic ECEF gradient to "
               "4e-10 (the oracle's own finite-difference floor), and the "
               "Cholesky route against the explicit one to 5e-16.")]
story += code("""
r1 = g.regionalNEQ(B);                                   % a GRACE month
r2 = shLowLevel.regionalNEQ(B, "points", Values = dg, LatDeg = lat, ...
    LonDeg = lon, Height = 450e3, Quantity = "gravity_disturbance", Cov = 1e-16);
[a, out] = shLowLevel.neqCombine([r1, r2]);              % VCE of the two
""")

story += [para("36. The regional Kalman filter (v5.17.0)", "h2"),
          para("The fourth step chains the three before it into one call. "
               "<font face='Courier'>shLowLevel.regionalKalman</font> and "
               "<font face='Courier'>ts.regionalKalman</font> estimate the "
               "process model in the basis from a model series (chapter 34), "
               "turn every observation epoch into a normal equation in the "
               "basis (chapter 35) and run the existing kalmanFilter in its "
               "normal-equation mode and the RTS smoother on the basis "
               "coefficients. With the stationary start of kalmanFilter the "
               "two passes are the joint least-squares adjustment over all "
               "epochs (Kvas 2019, Sec. 2.3); in an RBF basis the oracle "
               "solves that block-tridiagonal system densely and agrees to "
               "2.6e-15, gaps included. The observations are a series with "
               "formal sigmas, whose climatology is removed first and "
               "restored in the basis afterwards, T(a + P c), or a struct "
               "array of basis normal equations with an epoch each. The "
               "smoothed coefficients leave the chain through linear "
               "functionals F a whose sigmas come from the full smoothed "
               "covariance,")]
story += eq(r"\sigma_F=\sqrt{\mathrm{diag}\left(F\,P_s\,F^{\mathsf{T}}\right)},")
story += [para("with F = T for the output series, the EWH design at the "
               "region's quadrature points for out.grid, and their "
               "area-weighted mean over the unbuffered region for out.basin "
               "- the basin mean EWH and its sigma, which the per-coefficient "
               "sigmas of the output series could not give back afterwards. "
               "The EWH outputs need the load Love numbers. On the SH basis "
               "the chain is kalmanChain: the same process model bit for bit "
               "and, through the information form instead of the gain form, "
               "the same estimates to 5.6e-15 and the same sigmas to 8.9e-16. "
               "In a closed loop with a known VAR(1) the basin-mean error is "
               "1.07 predicted sigmas (RMS over 60 seeds), the predicted "
               "sigma honest to within the error of the estimated model. "
               "Measured in tools/dev/validate_regional_kalman.py.")]
story += code("""
B = tsGrace.regionalBasis("Elbe", Type = "slepian", Threshold = 0.5);
[tsK, out] = tsGrace.regionalKalman(B, ModelSeries = tsESM, kn = kn, QScale = 10);
errorbar(out.epochs, out.basin.mean, out.basin.sigma)   % basin mean EWH [m]
""")

story += [para("37. Regional consistency: remove-compute-restore (v5.18.0)", "h2"),
          para("A regional basis sees the signal outside its region only "
               "through the observations, and what it cannot represent leaks "
               "into the coefficients it has. The option Background of "
               "regionalKalman removes a global background series b from the "
               "observations before they become normal equations in the "
               "basis, and restores it in every output:")]
story += eq(r"x(t)=b(t)+T\left(a(t)+P\,c(t)\right).")
story += [para("The grid and basin outputs carry b's EWH too. The background "
               "is taken as error-free, so no sigma changes. With the process "
               "model fixed the chain is linear in its data, so a background "
               "c z holding a fraction c of an outside signal z gives")]
story += eq(r"x(\mathrm{obs};\,c z)=c z+x(\mathrm{obs}_{in})+(1-c)\left(x(\mathrm{obs}_{in}+z)-x(\mathrm{obs}_{in})\right),")
story += [para("which is the test: exact to 5.6e-15. A basis built on an index "
               "with Nmin above 2 leaves the low degrees to the background "
               "entirely - remove-compute-restore of the low degrees. In "
               "record mode the records must already be reduced; the "
               "background is only restored. Neither Woehnke et al. (2025) "
               "nor Steffen et al. (2026) apply it; Steffen et al. name it as "
               "the treatment of long wavelengths, so it is checked here on "
               "its own terms. In a closed loop (nmax 30, a cap north of "
               "60 N, a 30 cm seasonal neighbour and a degree-2..4 random "
               "walk, five seeds) the outside signal raises the grid RMS over "
               "the region by 28%; with an 80% background the error is within "
               "3.6% of what the same data give without any outside signal. "
               "A background must be a good field: the observations' own "
               "unfiltered low degrees did worse than none (1.57 against "
               "1.20 cm). The process model may come from the full model "
               "series (worst ratio 1.011). Woehnke's observation area, EWH on "
               "the region grown by 300 km, helps without a background (1.04 "
               "against 1.20 cm) and costs in every seed with one, so it is "
               "not a chain option. Measured in "
               "tools/dev/validate_regional_rcr.py.")]
story += code("""
[tsK, out] = tsGrace.regionalKalman(B, ModelSeries = tsESM, kn = kn, ...
    Background = tsHydrologyModel);              % removed, filtered, restored
""")
story += [para("The observation climatology the chains remove and restore "
               "is, by default, fitted to the noisy observations, so the "
               "noise of the fit returns unfiltered in every epoch. In the "
               "closed loop above it dominates: 14.5 cm grid RMS. Since "
               "v5.22.0 FitClimatology = \"filtered\" fits it instead to a "
               "first pass run without a climatology, removes that and "
               "filters the residual - twice the cost, 0.89 to 1.96 cm over "
               "three climatology strengths, and never more than 2% above "
               "leaving the climatology in the filter. The same option exists "
               "on kalmanChain; the default is unchanged. Measured in "
               "tools/dev/validate_climatology_restore.py.")]
story += code("""
[tsK, out] = tsGrace.regionalKalman(B, ModelSeries = tsESM, kn = kn, ...
    FitClimatology = "filtered");                % fit it to a first pass
""")

story += [para("38. Line-of-sight gravity differences (v5.19.0)", "h2"),
          para("Kind lgd of regionalNEQ takes the line-of-sight gravity "
               "differences of a satellite pair in lgdToolbox's definition, "
               "the difference of the gravitational acceleration at the two "
               "satellites projected on the line of sight e = (rB - rA)/|rB - rA|:")]
story += eq(r"\mathrm{LGD}=e\cdot\left(g_B-g_A\right),\qquad g=\nabla V.")
story += [para("The design is the potential's gradient design along e at B "
               "minus that at A, from the two orbits in the Earth-fixed frame "
               "of the coefficients; lgdToolbox works in an inertial frame, and "
               "the caller rotates both orbits. The along-track processing "
               "stays in lgdToolbox. Its band filter is passed as Operator and "
               "applied once to the block [y, A], data first, because "
               "lgd.spectralOperator fits its edge predictor on the first "
               "column and applies the fitted map to every column: filtered "
               "data against unfiltered partials would bias the inversion. So "
               "the values are the unfiltered LGD, Valid is the mask of the "
               "data's own filtered call, and Cov belongs to the filtered data; "
               "rows left non-finite or outside Valid are dropped with their "
               "part of Cov. Checked against lgdToolbox's own forward models in "
               "tools/dev/validate_regional_lgd.py: degrees 0 and 2 with C00 = 1 "
               "and C20 = -J2/sqrt(5) reproduce lgdReferenceJ2 to 1.7e-15 of "
               "|g| at the satellites, degree 0 its 50-digit Kepler pair to "
               "5.3e-16 of |g|, and degrees 2..30 agree with Cartesian "
               "differences of the potential to the difference floor, 1.8e-8.")]
story += code("""
op = @(X) lgd.spectralOperator(t, X, Band = band);      % the data's operator
rec = shLowLevel.regionalNEQ(B, "lgd", Values = lgdUnfiltered, ...
    PositionA = rA, PositionB = rB, Operator = op, Valid = valid, Cov = C);
""")

story += [para("39. Process-noise scales from the data (v5.20.0)", "h2"),
          para("Kurtenbach (2012, Sec. 4.3.5) scales the process noise by a "
               "hand-tuned factor and notes that for real data such a factor "
               "cannot be fixed beforehand. QBlocks labels blocks of the basis "
               "coefficients and QScale gives one factor per block,")]
story += eq(r"Q(\alpha)=D\,Q\,D,\qquad D=\mathrm{diag}\left(\sqrt{\alpha_k}\right),")
story += [para("so the correlations of the estimated Q are kept; one block is "
               "Kurtenbach's alpha. EstimateQScale finds the factors as the "
               "maximum of the innovation likelihood. kalmanFilter returns its "
               "terms per epoch (Likelihood); in normal-equation form, with the "
               "predicted state m and covariance P,")]
story += eq(r"-2\log L_t=\log\left|I+PN\right|+m^{\mathsf{T}}Nm-2m^{\mathsf{T}}b-u^{\mathsf{T}}\left(P^{-1}+N\right)^{-1}u+c_t,\quad u=b-Nm,")
story += [para("where c_t = log|R| + l'R^-1 l is free of the model and is left "
               "out. Checked in tools/dev/validate_regional_adaptive.py: the sum "
               "equals the dense joint Gaussian likelihood to 3.9e-15, gaps "
               "included; for one block its maximum is the EM fixed point of "
               "Shumway and Stoffer (1982) to 1.3e-8; with true factors (4, "
               "0.5) on two blocks the estimates average (3.95, 0.49) over 30 "
               "seeds and lower the state error against alpha = 1 in all of "
               "them. VAR(2) passes through the chain (with a VAR(2) truth "
               "Order 2 has the lower -2 log L in 10 of 10 seeds), and "
               "buildCondFun(..., Basis = B) turns Kvas' space-domain "
               "conditioner into one of basis covariances, Proj f(T S T') Proj'.")]
story += code("""
[tsK, out] = tsGrace.regionalKalman(B, ModelSeries = tsESM, EstimateQScale = true);
cf = shLowLevel.buildCondFun(B.idx, kn = kn, Psi0Km = 1100, Basis = B);
[tsK, out] = tsGrace.regionalKalman(B, ModelSeries = tsESM, CondFun = cf, Order = 2);
""")
story += [para("A Matern prior in place of Q (v5.29.0)", "h3"),
          para("A model series of a few years cannot estimate a full process "
               "noise in K unknowns. shLowLevel.maternCovariance builds one "
               "from two fields instead: the stochastic PDE of Lindgren, Rue "
               "and Lindstroem (2011) with alpha = 2,")]
story += eq(r"\left(\kappa(x)^2-\Delta\right)\left(\tau(x)\,u(x)\right)=W(x),\qquad \kappa=\sqrt{8}/\rho,")
story += [para("rho the local practical range and tau set so that the pointwise "
               "standard deviation is the local Sigma. Scalars give the "
               "stationary Matern field, function handles a non-stationary "
               "one. It is discretised by Galerkin in the SH up to the band "
               "limit, with the multiplications as quadrature Gram matrices. "
               "regionalKalman takes the result as ProcessCov (Q = Proj C "
               "Proj', the dynamics still from the model series) or StartCov, "
               "and QScale, QBlocks and EstimateQScale scale it: the block "
               "scales are the coarse form of a Sigma that varies in space. "
               "Checked in tools/dev/validate_matern_prior.py: the stationary "
               "series equals the closed form through the Legendre function of "
               "complex degree to 1.1e-14; constant fields give the Matern "
               "degree variances to 3.0e-14; with two hemispheres of different "
               "range and Sigma the local std and correlation distance match "
               "the stationary field's with the local parameters within 0.5%. "
               "As the process noise of a VAR(1) closed loop the true prior "
               "gives honest smoothed sigmas (z-rms 0.98-1.02 over 20 seeds) "
               "where a diagonal Q from a 60-epoch model series gives 1.14, "
               "at 0.94 of its error. HB-STAR's own parameterisation of the "
               "fields was not available; this is the published SPDE.")]
story += code("""
rho = @(lat, lon) 300 + 500 * (abs(lat) > 60);                  % km
C = tsESM.maternCovariance(PracticalRangeKm = rho, Sigma = 0.02, kn = kn);
[tsK, out] = tsGrace.regionalKalman(B, ModelSeries = tsESM, ProcessCov = C, ...
    EstimateQScale = true);
""")

story += [para("Land mass with its sea-level fingerprint (v5.30.0)", "h3"),
          para("GRACE sees a land mass change together with the ocean's "
               "answer to it: the sea-level fingerprint. regionalBasis(..., "
               "Ocean = oceanMask, kn = kn, hn = hn) builds that answer into "
               "every column of T. The land part of each basis function and "
               "its elastic sea-level response (the equations of "
               "seaLevelFingerprint) are solved for all columns at once, and "
               "the projector is rebuilt. The coefficients are then land "
               "mass, and each column's total mass is zero by construction. "
               "B.fingerprint.coreLandEWH * a is the region's mean land EWH, "
               "which regionalKalman returns as out.landMean with its sigma. "
               "In the closed loop of tools/dev/validate_sea_level_basis.py "
               "(Lmax 30, a box whose edge is the coast), the ocean response a "
               "coastal-masked basis ignores shifts its land mass by +5.7 to "
               "+6.6%. With the fingerprint the estimate is within 0.6% of what "
               "the same basis gives for a truth without ocean response. "
               "Without the masking an RBF basis recovers 0.64 to 0.83 of the "
               "land loss. kn must be in the CE frame at degree 1.")]
story += code("""
B = ts.regionalBasis("Greenland", Ocean = oceanMask, kn = kn, hn = hn);
[tsK, out] = ts.regionalKalman(B, ModelSeries = tsm, kn = kn);
plot(out.epochs, out.landMean.mean)
""")

story += [para("40. References", "h2"),
          *bullets([
    "Chambers, D.P., Willis, J.K. (2010): A global evaluation of ocean "
    "bottom pressure from GRACE, OMCT, and steric-corrected altimetry. "
    "J. Atmos. Oceanic Technol. 27, 1395&ndash;1402.",
    "Chen, J.L., Wilson, C.R. (2003): Low degree gravitational changes "
    "from earth rotation and geophysical models. Geophys. Res. Lett. "
    "30(24), 2257. (Equation (1) of chapter 31.)",
    "Cheng, M., Tapley, B.D., Ries, J.C. (2013): Deceleration in the "
    "Earth's oblateness. J. Geophys. Res. Solid Earth 118, 740&ndash;747.",
    "Dobslaw, H., Dill, R. (2019): Product Description Document: "
    "Effective Angular Momentum Functions from Earth System Modelling at "
    "GFZ, rev. 1.1. (The length of day of chapter 31.)",
    "Eicker, A. (2008): Gravity field refinement by radial basis "
    "functions from in-situ satellite data. PhD thesis, University of "
    "Bonn. (Chapter 33.)",
    "Farrell, W.E., Clark, J.A. (1976): On postglacial sea level. "
    "Geophys. J. R. astr. Soc. 46, 647&ndash;667. (The sea-level "
    "fingerprint of chapter 39.)",
    "Gerchberg, R.W. (1974): Super-resolution through error energy "
    "reduction. Optica Acta 21, 709&ndash;720. (With Papoulis 1975, the "
    "support-projection principle behind Section 24.)",
    "Ghobadi-Far, K., Han, S.-C., Weller, S., et al. (2018): A transfer "
    "function between line-of-sight gravity difference and GRACE "
    "intersatellite ranging data. J. Geophys. Res. Solid Earth 123. "
    "(Chapter 38.)",
    "Gouweleeuw, B.T. et al. (2018): Daily GRACE gravity field solutions "
    "track major flood events in the Ganges&ndash;Brahmaputra Delta. "
    "Hydrol. Earth Syst. Sci. 22, 2867&ndash;2880.",
    "Horvath, A., Murboeck, M., Pail, R., Horwath, M. (2018): "
    "Decorrelation of GRACE time variable gravity field solutions using "
    "full covariance information. Geosciences 8, 323.",
    "Jekeli, C. (1981): Alternative methods to smooth the Earth's "
    "gravity field. Rep. 327, Dept. of Geodetic Science, Ohio State "
    "University.",
    "Kusche, J. (2007): Approximate decorrelation and non-isotropic "
    "smoothing of time-variable GRACE-type gravity field models. "
    "J. Geodesy 81, 733&ndash;749.",
    "Kurtenbach, E. (2012): Entwicklung eines Kalman-Filters zur "
    "Bestimmung kurzzeitiger Variationen des Erdschwerefeldes aus "
    "Daten der Satellitenmission GRACE. DGK Reihe C, Nr. 683, Bonn. "
    "(The VAR(1) closed form and the contribution diagnostic of "
    "chapter 27.)",
    "Lindgren, F., Rue, H., Lindstroem, J. (2011): An explicit link "
    "between Gaussian fields and Gaussian Markov random fields: the "
    "stochastic partial differential equation approach. J. R. Stat. Soc. "
    "B 73, 423&ndash;498. (The Matern prior of chapter 39.)",
    "Kvas, A. (2019): Estimation of high-frequency mass variations "
    "from GRACE inter-satellite ranging. PhD thesis, TU Graz. (The "
    "batch-equivalence, innovation QC and EWH conditioning of "
    "chapter 27.)",
    "Kvas, A. et al. (2019): ITSG-Grace2018: overview and evaluation of "
    "a new GRACE-only gravity field time series. J. Geophys. Res. Solid "
    "Earth 124, 9332&ndash;9344.",
    "Mayer-Guerr, T. et al.: ITSG GRACE/GRACE-FO monthly, daily and "
    "SINEX products. TU Graz, ftp.tugraz.at/pub/ITSG/GRACE.",
    "Papoulis, A. (1975): A new algorithm in spectral analysis and "
    "band-limited extrapolation. IEEE Trans. Circuits Syst. 22, "
    "735&ndash;742.",
    "Petit, G., Luzum, B. (eds.) (2010): IERS Conventions (2010). IERS "
    "Technical Note 36. (The Earth's constants of chapter 31.)",
    "Phillips, T., Nerem, R.S., Fox-Kemper, B., Famiglietti, J.S., "
    "Rajagopalan, B. (2012): The influence of ENSO on global terrestrial "
    "water storage using GRACE. Geophys. Res. Lett. 39, L16705. (The "
    "Hilbert phase estimator of chapter 29.)",
    "Reager, J.T., Famiglietti, J.S. (2009): Global terrestrial water "
    "storage capacity and flood potential using GRACE. Geophys. Res. "
    "Lett. 36, L23402.",
    "Reager, J.T., Thomas, B.F., Famiglietti, J.S. (2014): River basin "
    "flood potential inferred using GRACE gravity observations at "
    "several months lead time. Nature Geosci. 7, 588&ndash;592.",
    "Sasgen, I. et al. (2012): Timing and origin of recent regional "
    "ice-mass loss in Greenland. Earth Planet. Sci. Lett. 333&ndash;334, "
    "293&ndash;303.",
    "Sinha, D., Syed, T.H., Famiglietti, J.S., Reager, J.T., Thomas, "
    "R.C. (2017): Characterizing drought in India using GRACE "
    "observations of terrestrial water storage deficit. "
    "J. Hydrometeorol. 18, 381&ndash;396.",
    "Shumway, R.H., Stoffer, D.S. (1982): An approach to time series "
    "smoothing and forecasting using the EM algorithm. J. Time Ser. Anal. "
    "3, 253&ndash;264. (Chapter 39.)",
    "Steffen, R., Woehnke, V., Weigelt, M., Eicker, A. (2026): Improved "
    "regional mass change estimation using Slepian functions in a "
    "Kalman filter framework. IAG Symposia, doi:10.1007/1345_2026_348. "
    "(Chapter 33.)",
    "Swenson, S., Wahr, J. (2002): Methods for inferring regional "
    "surface-mass anomalies from GRACE. J. Geophys. Res. 107, 2193.",
    "Swenson, S., Wahr, J. (2006): Post-processing removal of correlated "
    "errors in GRACE data. Geophys. Res. Lett. 33, L08402.",
    "Swenson, S., Chambers, D., Wahr, J. (2008): Estimating geocenter "
    "variations from a combination of GRACE and ocean model output. "
    "J. Geophys. Res. 113, B08410.",
    "Vishwakarma, B.D. (2017): Understanding and repairing the signal "
    "damage due to filtering of mass change estimates from the GRACE "
    "satellite mission. PhD thesis, University of Stuttgart. (Chapter "
    "29.)",
    "Vishwakarma, B.D., Horwath, M., Devaraju, B., Groh, A., Sneeuw, N. "
    "(2017): A data-driven approach for repairing the hydrological "
    "catchment signal damage due to filtering of GRACE products. Water "
    "Resour. Res. 53, 9824&ndash;9844.",
    "Wahr, J., Molenaar, M., Bryan, F. (1998): Time variability of the "
    "Earth's gravity field. J. Geophys. Res. 103, 30205&ndash;30229. "
    "(The EWH kernel of Section 4.)",
    "Weigelt, M. et al. (2024): Bridging the gap between GRACE and GRACE "
    "Follow-On by combining high-low satellite-to-satellite tracking data "
    "and satellite laser ranging. J. Geodesy 98, 84. (Chapter 32.)",
    "Woehnke, V., Eicker, A., Weigelt, M., et al. (2025): Kalman filter "
    "framework for a regional mass change model from GRACE satellite "
    "gravity. GEM - Int. J. Geomath. 16, 2. (Chapter 33.)",
    "Zhao, M., Geruo, A., Velicogna, I., Kimball, J.S. (2017): A global "
    "gridded dataset of GRACE drought severity index. "
    "J. Hydrometeorol. 18, 2117&ndash;2129."]),
          para("Data providers to cite alongside the methods: ITSG (TU "
               "Graz), COST-G, GFZ/GravIS, CSR and JPL (mascons), ICGEM "
               "as the archive. The shipped acceptance numbers "
               "(&minus;224.6 Gt/yr Greenland vs the published "
               "&minus;231.1; +1.41 mm/yr barystatic) are reproduced "
               "against these products with the exact recipes of this "
               "guide.")]

story += [PageBreak()]

# ================================================== Part II best practices
story += [para("Part II &mdash; Best practices", "h1"),
          para("Processing chain order", "h2"),
          para("The order below is not arbitrary; each step assumes the "
               "previous ones:")]
story += bullets([
    "<b>1.</b> Read GSM monthlies (shSeries.read, gz transparent, ICGEM "
    "1.0/2.0 incl. gfct).",
    "<b>2.</b> Replace C20 (and C30 in the accelerometer-degraded years) "
    "from TN-14; add degree-1 from TN-13 (addDegree1). Do this BEFORE "
    "filtering &mdash; filters see the stripes, not the low-degree "
    "completions.",
    "<b>3.</b> Bridge the GRACE&harr;GRACE-FO gap explicitly: dropNaN / "
    "select, or fill it from an HLSST series with bridgeGaps (after "
    "TN-14, chapter 32); never fit a climatology across NaNs.",
    "<b>4.</b> Filter: tvANS (or DDK for benchmarking; Gaussian as "
    "baseline).",
    "<b>5.</b> Remove GIA (trend work only).",
    "<b>6.</b> Fit climatology with tidal alias periods and "
    "ARCorrect=true; or form basin series with deconvolution.",
    "<b>7.</b> Synthesize maps / averages; propagate sigmas (analytic "
    "where derived, mcPropagate everywhere else)."])

story += [para("Choosing a filter", "h2")]
story += tbl(["situation", "recommendation"], [
    ["global EWH maps, standard use",
     "tvANS (Blocks=\"auto\"); Gaussian 300 km only as sanity baseline"],
    ["cross-paper comparability",
     "add DDK3-DDK6 variants via readDDK (binary Wbd, Nmax=96) + applyDDK"],
    ["strong order-dependent striping",
     "tvANS with VCEBands=[0 16 33 61] (v2.2)"],
    ["small basins (&lt; ~200,000 km&sup2;)",
     "expect leakage; taper kernels, consider basinDeconvolve with "
     "several neighboring kernels"],
    ["regional studies",
     "Slepian basis instead of filtering a global field (Part III, G4)"],
    ["a single catchment and no model you trust",
     "filter as usual, then leakageDataDriven (chapter 29)"],
], [6.3 * cm, TEXT_W - 6.3 * cm])

story += [para("Uncertainty accounting &mdash; what is honest and what "
               "is approximate", "h2")]
story += bullets([
    "Formal per-coefficient sigmas (readers) &rarr; exact as published.",
    "tvANS posterior sigmas &rarr; exact for the unconstrained AND (v2.5) "
    "the constrained filter.",
    "Basin sigmas &rarr; noise part consistent with (banded) VCE and the "
    "exact (constrained) operator; deterministic-fit parameter "
    "uncertainty included since v2.5 (pointwise; epoch-correlated "
    "through the shared fit).",
    "Climatology sigmas &rarr; OLS/weighted/robust; AR(1) correction "
    "first-order with Kendall-corrected r<sub>1</sub> (v2.5; residual "
    "~3% optimism from regression absorption).",
    "GIA &rarr; the model's rate sigma propagates with removeGIA(Sigma=) "
    "(v5.2.0); for a trend add info.rateSigmaC/S, which is fully "
    "correlated in time; without a sigma field use the model spread.",
    "Multi-center combination &rarr; posterior sigmas are a LOWER bound "
    "(common mode invisible; see info.interCenterCorr).",
    "DDK-filtered fields &rarr; no analytic sigmas; use mcPropagate.",
    "Anything else &rarr; mcPropagate: independent-sigma or full SINEX "
    "covariance sampling validates every analytic formula empirically "
    "(the toolbox's own tests do exactly this)."])

story += [para("Validation habits the toolbox is built around", "h2")]
story += bullets([
    "Every numerical method was validated in Python (numpy/scipy) before "
    "the MATLAB implementation; the validation numbers are quoted in the "
    "help texts. Keep the habit for your own extensions.",
    "Ring-grid analysis&harr;synthesis roundtrips are exact to ~1e-14: "
    "use them as a self-test on your grids (Part III, G1 step 5).",
    "Real provider files beat synthetic fixtures: the test suite "
    "auto-discovers any *.snx(.gz) you drop into the test-data folder "
    "(shLowLevel.testDataDir) and sanity-checks it (files above ~30 MB "
    "are skipped with a message), and seven opt-in tests run on real "
    "data you point them at (see Opt-in test data).",
    "runAllTests is the gate: run it after every toolbox update; "
    "perf_log.csv accumulates machine-local timing history."])

story += [para("Common silent errors this toolbox guards against", "h2")]
story += tbl(["error", "guard"], [
    ["geodetic latitudes fed to SH math (~21 km bias)",
     "LatType=\"geodetic\" + conversion helpers (v2.2)"],
    ["hardcoded Love numbers", "kn is a required explicit input for EWH"],
    ["climatology across the 2017-2018 gap NaNs",
     "assertClean errors loudly; dropNaN/select"],
    ["trend maps without GIA", "removeGIA one-liner (v2.2)"],
    ["optimistic trend sigmas", "ARCorrect=true (v2.2)"],
    ["tidal alias leakage into trends", "Periods=[161/365.25, 3.66, 7.48]"],
    ["zero-variance rows collapsing the noise floor",
     "positive-diagonal floor + shLowLevel:buildNoiseCov:allZeroVariance"],
    ["8-column ICGEM 1.0 acos/asin ambiguity",
     "EIGEN-style period read; documented in README"],
    ["sine sectorals S<sub>nn</sub> blanked in difference triangles",
     "fixed v2.4.2; rendered-CData regression test"],
    ["NaN in a grid reaching every coefficient of an analysis",
     "analysis refuses NaN until Fill= says what the gaps mean (v5.8.0); "
     "shAnalysisGrid refuses it too (v5.12.1)"],
    ["a malformed filter spec (\"gaussX\", a negative radius)",
     "one parser, shLowLevel.filterSpec, refuses it before any data is "
     "read (v5.7.0)"],
], [7.6 * cm, TEXT_W - 7.6 * cm])
story += [PageBreak()]

# ===================================================== Part III guides
story += [para("Part III &mdash; Step-by-step guides", "h1")]

story += [para("G1. Monthly EWH anomaly maps from ITSG files", "h2")]
story += code("""
% 1. read the monthly GSM series (gz ok, ICGEM 1.0/2.0)
ts = shSeries.read("data/ITSG-Grace2018_n96_*.gfc");

% 2. low-degree completion BEFORE filtering
tn14 = shLowLevel.readTN14("TN-14_C30_C20_SLR_GSFC.txt");
ts   = ts.applyTN14(tn14);                  % C20 (+C30 where flagged)
tn13 = shLowLevel.readTN13("TN-13_GEOC_GFZ_RL06.txt");
ts   = ts.addDegree1(tn13);

% 3. bridge the mission gap explicitly
ts = ts.dropNaN();

% 4. anomalies w.r.t. a mean field, then filter
ts  = ts - ts.mean();                       % anomalies
tsF = ts.filter("tvANS", Blocks="auto");    % or .gaussian(300)

% 5. EWH synthesis (Love numbers user-supplied!)
kn  = readmatrix("loadLoveNumbers.txt");    % your set, degrees 0..nmax
lat = -89.5:1:89.5; lon = 0.5:1:359.5;
ewh = tsF.at(24).synthesis(lat, lon, Quantity="ewh", kn=kn);  % [m]

% self-test: analysis roundtrip on a ring grid should be ~1e-14
gChk = shCoefficients.analysis(ewh, lat, lon, tsF.nmax, ...
          Quantity='ewh', kn=kn);
""")
story += [para("Interpretation: values are equivalent water height "
               "anomalies relative to the removed mean, in meters. The "
               "FFT synthesis path engages automatically on this uniform "
               "grid; check <font face='Courier'>tsF.at(24).history"
               "</font> for the full provenance chain.")]

story += [para("G2. Basin time series with uncertainties", "h2")]
story += code("""
idx = shLowLevel.shIndex(ts.nmax, Nmin=2);
% kernel from a polygon [lat lon], buffered + tapered (v2.2)
amazon = readmatrix("amazon_polygon.txt");
[b, info] = shLowLevel.basinKernel(idx, amazon, BufferKm=150, TaperKm=350);

% filtered series + filter operator
[tsF, op] = ts.filter("tvANS", Blocks="auto", VCEBands=[0 16 33 61]);

% deconvolved basin average with 1-sigma (banded-VCE-consistent, v2.2)
[avg, out] = shLowLevel.basinDeconvolve(b, op);
shLowLevel.plotBasinSeries(op.tYears, avg(1,:)', out.sigma(1,:)', Units="cm");
""")
story += [para("The deconvolution undoes the filter's attenuation of the "
               "kernel; the sigma comes from the posterior covariance "
               "with per-band noise factors. For several basins pass a "
               "kernel matrix B &mdash; the joint solve also "
               "redistributes mutual leakage. (Edition-2 erratum fixed: "
               "the signature is <font face='Courier'>basinDeconvolve(B, "
               "op)</font>, epochs live in <font face='Courier'>"
               "op.tYears</font>, averages in the first output.)")]

story += [para("G3. Significance-masked trend maps (GIA- and "
               "AR(1)-honest)", "h2")]
story += code("""
gia = shCoefficients.read("ICE-6G_D_rates.gfc");       % rate [1/yr]
tsG = tsF.removeGIA(gia);
clim = tsG.climatology(Periods=[161/365.25, 3.66, 7.48], ...
                       ARCorrect=true);
tr   = clim.trend();                        % shCoefficients WITH sigmas
kn   = readmatrix("loadLoveNumbers.txt");
rate = tr.synthesis(lat, lon, Quantity="ewh", kn=kn);         % [m/yr]
mc   = shLowLevel.mcPropagate(@(g) g.synthesis(lat, lon, ...
          Quantity="ewh", kn=kn), tr, N=300, Seed=1);
sigma = mc.sigma;
mask = abs(rate) > 2 * sigma;               % 2-sigma significance
rate(~mask) = NaN; imagesc(lon, lat, rate);
""")
story += [para("Compare against a second GIA model (Caron) and show the "
               "difference as the model-spread contribution to the error "
               "budget &mdash; usually dominant over formal errors in "
               "formerly glaciated regions.")]

story += [para("G4. Regional analysis with Slepian functions", "h2")]
story += code("""
idx = shLowLevel.shIndex(60, Nmin=0);
region = @(la,lo) double(la>-90 & la<-60);      % Antarctica-ish belt
[G, lam, infoS] = shLowLevel.slepianBasis(idx, region);
fprintf("Shannon %.1f -> keeping %d tapers\\n", infoS.shannon, numel(lam));

x  = shLowLevel.vecFromCS(g.C, g.S, idx);              % one month, idx order
a  = G' * x;                                    % Slepian coefficients
xR = G * a;                                     % regional part of x
[Cr, Sr] = shLowLevel.csFromVec(xR, idx);
gR = shCoefficients(Cr, Sr, GM=g.GM, R=g.R);
""")
story += [para("Estimating a (dimension &asymp; Shannon number) instead "
               "of all P Stokes coefficients is well-posed on regional "
               "data by construction; concentrations &lambda; near 1 "
               "tell you which tapers the region genuinely constrains.")]

story += [para("G5. Working with released covariances (SINEX)", "h2")]
story += code("""
idx = shLowLevel.shIndex(96, Nmin=2);
% full read (monthly solutions to ~30 MB): covariance in idx order
snx = shLowLevel.readSINEX("ITSG-..._n96_2008-04.snx.gz", ...
                    Output="covariance", Index=idx);
N   = snx.M;                                % noise shape for tvANS
[tsF, op] = ts.filter("tvANS", NoiseCov=N, Blocks="off");

% multi-100-MB NEQ SINEX: stream just the estimates in seconds (v2.2)
est = shLowLevel.readSINEX("ITSG-..._operational_n96_2020-01.snx.gz", ...
                    Only="estimate");

% propagate the full covariance through ANY functional (v2.2)
out = shLowLevel.mcPropagate(@(gs) b' * shLowLevel.vecFromCS(gs.C,gs.S,idx), ...
                      g0, Cov=snx.M, Idx=idx, N=2000);
""")

story += [para("G6. Comparing against mascons", "h2")]
story += code("""
mas = shLowLevel.readMascon("GRCTellus.JPL...MSCNv03CRI.nc");
% mascon lats are GEODETIC -> one switch avoids the 21-km bias (v2.2)
kn = readmatrix("loadLoveNumbers.txt");
k  = find(abs(mas.epoch - 2010.29) < 0.05, 1);     % match an epoch
ewhSH = tsF.at(k).synthesis(mas.lat', mas.lon', ...
          Quantity="ewh", kn=kn, LatType="geodetic");  % [m]
d = 100*ewhSH - mas.ewh(:,:,k);                    % mascon units: cm
fprintf("RMS diff %.2f cm\\n", sqrt(mean(d(:).^2, 'omitnan')));
""")
story += [para("Expect coastal and small-basin differences: mascons "
               "carry their own regularization. Compare basin-integrated "
               "series rather than pointwise fields for a fair "
               "statement; use the same GIA convention on both sides "
               "(JPL mascons ship GIA-corrected &mdash; remove GIA from "
               "the SH side too).")]

story += [para("G7. GNSS loading comparison (v2.3)", "h2")]
story += code("""
% residual monthly series (mean removed), filtered
ts  = ts - ts.mean();                       % anomalies
tsF = ts.filter("tvANS", Blocks="auto");

% load Love numbers k', h', l' - ONE consistent model, user-supplied;
% v2.5 reader: layouts, sparse pchip interpolation, CF-frame conversion
LN = shLowLevel.readLoveNumbers("loadLoveNumbers_PREM.txt", ...
    Columns="n k h l", Nmax=tsF.nmax, Interp="pchip", ...
    InFrame="CE", OutFrame="CF");               % match TN-13 (CF)
kn = LN.kn; hn = LN.hn; ln = LN.ln;

% GNSS stations (geodetic coordinates!)
sta = readmatrix("stations.txt");               % [lat lon]
T = tsF.nEpochs;
up = zeros(size(sta,1), T); no = up; ea = up;
for k = 1:T
    [up(:,k), no(:,k), ea(:,k)] = tsF.at(k).deformation( ...
        sta(:,1)', sta(:,2)', kn=kn, hn=hn, ln=ln, ...
        Mode="points", LatType="geodetic");
end
% compare up(i,:) against the GNSS vertical of station i (same epochs);
% typical GRACE-elastic amplitudes: mm to ~1 cm vertical, ~1/3 horizontal
""")
story += [para("Degree 1 is excluded by default; include it only when "
               "both the GRACE side (TN-13 in the CF frame) and the Love "
               "numbers use the same frame convention. The elastic "
               "prediction excludes GIA and poroelastic effects &mdash; "
               "detrend both series or remove GIA explicitly before "
               "comparing trends.")]

story += [para("G7b. Data management (v2.4.1, temporal catalogue "
               "v2.4.2)", "h2")]
story += code("""
shLowLevel.dataFolder("D:/geodata/shAnalysis");      % once; persists (getpref)
shLowLevel.fetchDDK(1:8);                     % all released DDK filters
W5 = shLowLevel.readDDK("DDK5");              % by name, from the data folder
T = shLowLevel.listICGEM();                   % 180+ static models as a table
f = shLowLevel.fetchICGEM("EGM2008");         % -> dataFolder/static/EGM2008.gfc
g = shCoefficients.read(f);
shLowLevel.fetchITSG(2010:2016);              % -> dataFolder/series/itsg/monthly
shLowLevel.fetchITSG("2008-04", Product="daily"); % Kalman daily n40 (v2.4.1)

% FULL temporal catalogue: all ~70+ series, all centers
Tt = shLowLevel.listICGEM(Type="temporal");
% fetch a WHOLE monthly series (v3.1.1) - one row of that catalogue
fs = shLowLevel.fetchICGEM(17, Type="temporal");
ts = shSeries.fromFolder(fileparts(fs(1)));   % straight into a series
""")
story += [para("The ICGEM static catalogue is parsed from icgem.gfz.de "
               "(fixture-tested offline). The temporal catalogue lists "
               "every series of every center &mdash; groups 01_GRACE, "
               "02_COST-G, 03_other, 04_SLR &mdash; with columns group, "
               "center, series, path, url and zip. Since v3.1.1 a "
               "temporal row is not just browsable but fetchable: "
               "<font face='Courier'>fetchICGEM(idx, Type=\"temporal\")</font> "
               "downloads the whole series into "
               "<font face='Courier'>&lt;dataFolder&gt;/series/"
               "&lt;group&gt;_&lt;center&gt;_&lt;series&gt;/</font>, which "
               "<font face='Courier'>shSeries.fromFolder</font> and "
               "<font face='Courier'>shLowLevel.standardChain</font> consume "
               "directly. For ITSG monthlies "
               "<font face='Courier'>shLowLevel.fetchITSG</font> remains the "
               "convenient route.")]

story += [para("Mode: one request, not three hundred", "h3")]
story += [para("The default <font face='Courier'>Mode=\"auto\"</font> takes "
               "the server's whole-series ZIP in a SINGLE request and "
               "unpacks it. This is not an optimization but a courtesy "
               "requirement: icgem.gfz.de rate-limits, and fetching a "
               "283-file series one file at a time earns HTTP 429 and a "
               "tarpit (field-observed as &quot;too many connections&quot;). "
               "If the archive is unavailable the fetcher falls back to "
               "per-file mode automatically &mdash; resumable, throttled "
               "with <font face='Courier'>Pause=</font> and "
               "<font face='Courier'>Retries=</font> exponential backoff, "
               "each file verified by parse before it replaces anything. "
               "<font face='Courier'>Mode=\"archive\"|\"files\"</font> force "
               "either path; <font face='Courier'>info.mode</font> reports "
               "which one actually ran, so a script can tell a fresh "
               "download from a no-op. <font face='Courier'>Files=</font> "
               "filters the series, and "
               "<font face='Courier'>FileList=</font> injects a catalogue "
               "table for offline mirrors and subsets.")]
story += code("""
% forced per-file, filtered to a window, gentle on the server
fs = shLowLevel.fetchICGEM(17, Type = "temporal", Mode = "files", ...
        Files = "*2008*.gfc", Pause = 3, Retries = 3);
[ts, rep] = shLowLevel.standardChain(fileparts(fs(1)), Filter = "DDK3");
""")

story += [para("G8. Multi-center combination (v2.4)", "h2")]
story += code("""
shLowLevel.fetchITSG(2010:2016);              % download once (websave)
tsI = shSeries.fromFolder("ITSG/");    % GSM level, same nmax
tsC = shSeries.fromFolder("CSR/");
tsG = shSeries.fromFolder("GFZ/");
[tsComb, info] = shLowLevel.combineCenters({tsI, tsC, tsG}, Robust=true);

figure; plot(info.epochs, info.weights');     % weight time series
legend(info.centers); ylabel("relative weight");
figure; imagesc(info.interCenterCorr);        % honesty diagnostic
% THEN degree-1 / C20-C30 replacements, once:
tsComb = tsComb.applyTN14("TN-14.txt");
tsComb = tsComb.addDegree1("TN-13.txt");
""")
story += [para("Watch the weight series for regime changes "
               "(single-accelerometer era, GRACE-FO transition) and "
               "treat posterior sigmas as lower bounds &mdash; the "
               "common mode is invisible.")]

story += [para("G9. Sea-level fingerprint (v2.4)", "h2")]
story += code("""
idx = shLowLevel.shIndex(96, Nmin=0);
LN = readmatrix("loadLoveNumbers.txt"); kn = LN(:,2); hn = LN(:,3);
greenland = @(la,lo) -280 * inGreenland(la, lo);   % kg/m^2/yr, say
oceanF = @(la,lo) oceanMaskFun(la, lo);            % 1 over ocean
[S, grid, info] = shLowLevel.seaLevelFingerprint(greenland, oceanF, idx, ...
    kn=kn, hn=hn);
imagesc(grid.lonDeg, grid.latDeg, info.S2D / info.eustatic);   % S / eustatic
axis xy; colorbar; title("Greenland fingerprint")
""")
story += [para("Plot S normalized by the eustatic mean: near-field "
               "values drop below zero, far-field plateaus around "
               "1.1&ndash;1.3 &mdash; if not, check the ocean mask and "
               "that idx uses Nmin= 0.")]

story += [para("G10. The standard chain in one call", "h2")]
story += code("""
% the whole post-processing chain, in the ONE correct order
gia = shCoefficients.read("ICE-6G_D_trend.gfc");   % a TREND field [1/yr]
[ts, rep] = shLowLevel.standardChain("D:/grace/monthly", ...
    TN14File = "TN-14_C30_C20_SLR_GSFC.txt", ...   % TN14 itself is a FLAG
    Degree1 = "CSR", ...                           % provider, not a path
    GIA = gia, Filter = "DDK3");
disp(rep.steps')          % what was applied, in order, with provenance
""")
story += [para("Order is not a matter of taste here. The SLR C20/C30 "
               "replacement and the degree-1 restoration must happen on "
               "the UNFILTERED coefficients &mdash; a filter mixes degrees, "
               "so replacing a coefficient afterwards inserts an "
               "unfiltered value into a filtered field and the low "
               "degrees no longer mean anything consistent. GIA is a "
               "trend in the same (corrected) coefficients, so it comes "
               "next; filtering is last. "
               "<font face='Courier'>standardChain</font> encodes exactly "
               "that order and returns REP, a provenance record naming "
               "every step, the files it used and the toolbox version "
               "that ran &mdash; the thing you paste into a paper's data "
               "section. Every stage is optional: leave "
               "<font face='Courier'>GIA=</font> out and the report says "
               "so, rather than silently skipping a step you assumed had "
               "happened.")]
story += [para("Two contracts worth reading before the first call: "
               "<font face='Courier'>TN14</font> is a logical FLAG and the "
               "path goes in <font face='Courier'>TN14File</font>, while "
               "<font face='Courier'>Degree1</font> names the TN-13 "
               "provider (\"GFZ\" | \"CSR\" | \"JPL\" | \"none\") with the "
               "path in <font face='Courier'>Degree1File</font>; and "
               "<font face='Courier'>GIA</font> takes an "
               "<font face='Courier'>shCoefficients</font> TREND field in "
               "[1/yr], not a filename &mdash; it is applied as "
               "(t &minus; GIAEpoch) &times; GIA. Left at their defaults "
               "the files come from the persistent data folder that "
               "<font face='Courier'>setup_shAnalysis</font> populates.")]

story += [para("G11. Designing your own anisotropic filter", "h2")]
story += code("""
% a DDK-class filter built from YOUR error covariance
g  = shCoefficients.read("ITSG-Grace2018_n60_2008-04.gfc");
W  = shLowLevel.designFilter(g.sigmaC, g.sigmaS, Kaula = 1e-5);
[Cf, Sf] = shLowLevel.applyDDK(g.C, g.S, W);   % same block format as readDDK
""")
story += [para("The released DDK filters are built from a specific "
               "center's normal equations. If you have your own sigmas "
               "or a released covariance, "
               "<font face='Courier'>designFilter</font> builds the same "
               "kind of operator, W = (N + a S<sup>-1</sup>)<sup>-1</sup> N, "
               "in the block format "
               "<font face='Courier'>readDDK</font> produces &mdash; so it "
               "drops into <font face='Courier'>applyDDK</font>, "
               "<font face='Courier'>g.applyDDK</font> and "
               "<font face='Courier'>standardChain(Filter=W)</font> "
               "unchanged. Note that <font face='Courier'>Noise=</font> "
               "expects a COVARIANCE, not sigmas: passing standard "
               "deviations where a variance is expected is the classic "
               "way to get a filter that looks plausible and smooths by "
               "the square root of what you intended.")]

story += [para("G12. Correcting leakage", "h2")]
story += code("""
% forward modelling: only the FILTER has to be known
ewh = g.synthesis(-89:89, 0:359, Quantity= "ewh", kn = kn);
[m, info] = shLowLevel.leakageCorrect(ewh, -89:89, 0:359, ...
    Filter = "gauss300", Mask = basinMask, Gain = 2);

% or scaling factors, if you trust a model's spatial PATTERN
k = shLowLevel.gridScaling(modelEWH, -89:89, 0:359, Filter = "gauss300");
corrected = k .* ewh;                 % NaN where the model is blind
""")
story += [para("A filter removes real signal and spreads the rest across "
               "basin boundaries; a 6&deg; disc under a 500 km Gaussian "
               "keeps about half its peak. The two corrections differ in "
               "what you have to BELIEVE, which is how to choose between "
               "them. Forward modelling "
               "(<font face='Courier'>leakageCorrect</font>) needs only "
               "the filter and, usefully, a mask saying where mass can "
               "exist &mdash; it then has to explain the observation with "
               "mass inside that region, so leakage outside is removed "
               "rather than redistributed. Scaling factors "
               "(<font face='Courier'>gridScaling</font>) need a model "
               "series, and inherit the correctness of its spatial "
               "pattern: the factors are invariant to the model&rsquo;s "
               "amplitude but not to its shape.")]
story += [para("Two behaviours worth knowing before you read the output. "
               "Convergence is judged on the change of the SOLUTION, not "
               "on the residual: with a mask the problem is inconsistent, "
               "so the residual settles at a floor while the solution is "
               "converged. And <font face='Courier'>gridScaling</font> "
               "returns NaN where the model carries no signal instead of "
               "a ratio of two numerical zeros &mdash; a model that does "
               "not reach your basin shows up as missing coverage rather "
               "than as noise multiplying your data. A third correction, "
               "the data-driven method of deviation (chapter 29), needs "
               "neither a mask nor a model &mdash; only the filter, the "
               "catchment and at least 12 epochs.")]

story += [para("G13. What real provider files look like", "h2")]
story += [para("Format specifications describe what files ought to "
               "contain. The reader is written against what they "
               "actually contain, and three separate field failures are "
               "worth knowing about, because they are silent &mdash; you "
               "get numbers, just not the right ones.")]
story += bullets([
    "<b>FORTRAN D-exponents.</b> Providers switch from "
    "<font face='Courier'>1.23E-10</font> to "
    "<font face='Courier'>1.23D-10</font> partway through large files "
    "(EIGEN-6C4 does it above degree ~370). MATLAB's "
    "<font face='Courier'>str2double</font> returns NaN for those, so a "
    "line-by-line parser quietly corrupts the high degrees of exactly "
    "the models where the high degrees are the point. The reader "
    "normalizes D/d to E/e before conversion.",
    "<b>ICGEM 2.0 column order.</b> The real-world layout of an "
    "<font face='Courier'>acos</font>/<font face='Courier'>asin</font> "
    "line is <font face='Courier'>... sigC sigS t0 t1 period</font> "
    "&mdash; period LAST, verified against CNES/GRGS files. A "
    "period-first assumption mis-parses every such file and produces a "
    "time-variable model whose seasonal terms are wrong without ever "
    "raising an error.",
    "<b>Ragged record groups.</b> EIGEN-5S and 5C carry a single "
    "<font face='Courier'>gfc</font> line with a trailing epoch among "
    "thousands of uniform ones. Bulk "
    "<font face='Courier'>sscanf(txt, '%f', [nc Inf])</font> does not "
    "complain about that &mdash; it silently re-flows the whole group by "
    "one column and asks for a coefficient matrix indexed by a date. "
    "The reader checks rows-out == lines-in per group, subgroups by "
    "numeric width when ragged, and keeps an n/m sanity net.",
])
story += [para("The practical rule: when a new provider or a new release "
               "enters your pipeline, read one file and check "
               "<font face='Courier'>g.C(3,1)</font> and the highest "
               "degrees against the provider's own published values "
               "before you trust a thousand of them. Bulk parsing is "
               "fast &mdash; EIGEN-6C4 at 177.7 MB and degree 2190 in "
               "about 5 s, a 73.6 MB GRGS mean field with 674k variable "
               "terms in about 7 s &mdash; but fast and correct are "
               "different properties.")]
story += [para("G14. The lanes behind the classes (v5.6.0&ndash;v5.13.0)",
               "h2")]
story += [para("Since v5.6.0 the numerical lanes that used to need C, S, "
               "GM and R unpacked by hand are methods of the classes. Each "
               "is a thin delegate: it fills in the object's coefficients, "
               "GM and R and forwards only the options you give, so every "
               "default lives in one place, and a test pins each method "
               "bitwise to the function it calls, with options and "
               "without. The two leakage methods REQUIRE Filter, although "
               "the functions default it: a series cannot know which "
               "filter its data saw, and the wrong one gives a plausible "
               "wrong answer. ts.write warns when a file name would not "
               "bring its epoch back, because a .gfc file carries no "
               "epoch of its own.")]
story += code("""
[tsK, rep]       = ts.kalman(ModelSeries = tsm, Order = 1);    % kalmanChain
[modes, pcs, ve] = ts.eof(NModes = 4);                         % eofAnalysis
[m, infoL]   = ts.leakageCorrect(lat, lon, Filter = "gauss300", kn = kn, ...
                   Mask = mask, NoiseLevel = sigTrend);
[dq, infoG]  = ts.gradient(lat, lon, Quantity = "ewh", kn = kn);
ts.write(outFolder);                                           % one .gfc per epoch
tsP          = ts.poleTideConvert(From = "IERS2010", To = "IERS2018");
[d1, infoD]  = ts.estimateDegree1(isOcean, kn = kn, OceanModel = obp);
[tsC, infoC] = ts.combineCenters({tsB, tsD});
[a, rec]     = ts.slepianProject(G, idx);
avg = g.basinAverage(B);
sig = g.errorMap(lat, lon);
val = g.synthesisPoints(latP, lonP, rP);
[T, infoT]   = g.gradientTensor(lat, lon, Height = 255e3);
""")
story += [PageBreak()]

# ======================================================== demo gallery
story += [para("Validation against GravIS", "h1")]
story += [para("This chapter is a worked, reproducible comparison of the "
               "toolbox against a PUBLISHED product: the GravIS "
               "Greenland ice-mass basin averages "
               "(https://gravis.gfz.de/gis). It is written out in full "
               "because the numbers only mean something together with "
               "the choices behind them &mdash; and because two of those "
               "choices cost a factor that would otherwise have been "
               "mistaken for a bug in the toolbox.")]

story += [para("V1. The reference", "h2")]
story += [para("GravIS publishes seven Greenland drainage basins as "
               "ASCII time series in Gt. Summing them and fitting bias, "
               "trend, annual and semi-annual gives the reference "
               "trend. It must be recomputed over the SPAN YOU ACTUALLY "
               "USE: over the full record COST-G RL02 gives "
               "&minus;220.8 Gt/yr, but over the shorter span for which "
               "the auxiliary correction tables were available it is "
               "&minus;231.1 Gt/yr (that span: 2002-04..2023-02, n = 217 "
               "monthly solutions - QUOTE THE DATES with the number; an "
               "independent audit measured ~10 Gt/yr of reference drift "
               "over two years of end date). Comparing against the wrong span is "
               "a 5% error before any processing starts.")]

story += [para("V2. Matching the GravIS processing", "h2")]
story += [para("GravIS Level-3 basin averages come from Level-2B "
               "coefficients, which are Level-2 plus four corrections "
               "(https://gravis.gfz.de/corrections). Applying anything "
               "less makes the comparison meaningless. All four are "
               "read with <font face='Courier'>shLowLevel.readSHM</font> "
               "or as plain tables:")]
story += code("""
% (1) their low-degree replacement: C20, C30, C21, S21
% (2) their geocenter (Swenson approximation, NOT TN-13)
% (3) their mean field, 2002/04-2020/03
% (4) GIA: ICE-6G_D (VM5a), a GRDOTA rate model in 1/yr
Mn  = shLowLevel.readSHM("GRAVIS-2B_..._MEAN_2002095-2020091_NFIL.gz", Nmax = 90);
Gi  = shLowLevel.readSHM("GRAVIS-2B_..._GIA_ICE-6G_D_VM5a.gz", Nmax = 90);

ts = shSeries.fromFolder(costgFolder);
ts = ts.select(ts.epochs <= maxTableEpoch + 0.05);   % tables trail the data
% ... insert their C20/C30/C21/S21 and C10/C11/S11 per epoch ...
for k = 1:ts.nEpochs                    % mean field and GIA, per epoch
    Cs(:,:,k) = Cs(:,:,k) - Mn.C - (ts.epochs(k) - 2011) * Gi.C;
    Ss(:,:,k) = Ss(:,:,k) - Mn.S - (ts.epochs(k) - 2011) * Gi.S;
end
ts = ts.removeAlias();                  % (5) the S2 161-day alias
""")

story += [para("V3. The basin average", "h2")]
story += code("""
idx = shLowLevel.shIndex(ts.nmax, Nmin= 0);
[b, info] = shLowLevel.basinKernel(idx, gisPolygon);   % NaN-separated rings
area = info.areaFraction * 4*pi*6371^2;                % NOT b(1)
kf   = shLowLevel.kernelFactors("ewh", ts.nmax, GM, R, kn = kn);
avg  = (b .* kf(idx.n+1))' * X / (b'*b);               % EWH [m] per epoch
mass = avg(:) * area * 1e6 * 1000 / 1e12;              % -> Gt
""")

story += [para("V4. Results, and what each step is worth", "h2")]
story += tbl(["Method", "Gt/yr", "vs published"], [
    ["naive kernel average", "&minus;196.4", "&minus;15%"],
    ["naive grid integral", "&minus;170.3", "&minus;26%"],
    ["forward modelling, <b>Greenland-only</b> mask", "&minus;259.8", "+12%"],
    ["forward modelling, <b>union</b> mask", "&minus;240.2", "+4%"],
    ["union mask + S2 alias removed", "&minus;240.0", "+4%"],
    ["<b>GravIS COST-G RL02, matching span</b>", "<b>&minus;231.1</b>", "&mdash;"],
], [7.2*cm, 3.2*cm, 3.2*cm])

story += [para("V4b. Describe the filter the FORWARD MODEL sees", "h2")]
story += [para("The table above hides the single largest error I made. "
               "GravIS basin averages start from UNFILTERED Level-2B "
               "coefficients, so I passed "
               "<font face='Courier'>Filter=\"none\"</font> to "
               "<font face='Courier'>leakageCorrect</font>. But Dahle et "
               "al. (2025), Sect. 2.2.1, list the basin-average steps: "
               "spectral masking, then <b>low-pass filtering with a "
               "Wiener optimal filter, approximately a Gaussian of 4&deg; "
               "latitude spatial half-width</b>, then the conversion to "
               "surface mass, then the least-squares adjustment. The "
               "forward model is filtered IDENTICALLY to the "
               "observations &mdash; that is the whole point of the "
               "method &mdash; so the filter to declare is the Wiener "
               "one, not \"none\".")]
story += code("""
r = 4 * 111.195;                         % 4 deg latitude ~ 445 km
wG = shLowLevel.shGaussianWeights(nmax, r);
obs = shCoefficients(Ct .* wG(:), St .* wG(:)).synthesis( ...
        lat, lon, Quantity= "ewh", kn = kn, Nmin= 0);
m = shLowLevel.leakageCorrect(obs, lat, lon, Filter = "gauss445", ...
        Mask = unionMask, Gain = 2, MaxIter = 300);
""")
story += tbl(["Declared filter", "Gt/yr", "vs published"], [
    ["<font face='Courier'>\"none\"</font> (wrong)", "&minus;234.9", "+1.6%"],
    ["<font face='Courier'>\"gauss445\"</font> (Wiener equivalent)",
     "<b>&minus;227.4</b>", "<b>&minus;1.6%</b>"],
    ["<b>GravIS COST-G RL02, matching span</b>", "<b>&minus;231.1</b>",
     "&mdash;"],
], [7.2*cm, 3.2*cm, 3.2*cm])
story += [para("Declaring the filter correctly turns a 1.6% overshoot "
               "into a 1.6% undershoot, and the iteration also drifts "
               "less with continued iteration (2.0 Gt/yr from 300 to 900 "
               "steps, against 2.5 unfiltered) because the filter "
               "regularises the inverse problem. At that point the "
               "agreement is as close as this reproduction can "
               "meaningfully be read: the remaining difference is "
               "smaller than the spread between GravIS product versions "
               "and smaller than the effect of the stopping point.")]
story += [para("The paper also specifies the mask GravIS uses, which is "
               "NOT the bare drainage-basin outline: the spectral mask "
               "is 1 until 200 km outside the grounding line and tapers "
               "smoothly to 0 by 600 km. That is "
               "<font face='Courier'>basinKernel(..., BufferKm = 200, "
               "TaperKm = 400)</font>, not a hard boundary.")]

story += [para("V4c. The regularised number, and the noise it needs", "h2")]
story += [para("Every figure above was produced by stopping the "
               "iteration at a fixed count, which is not a criterion. "
               "Rerun with the discrepancy principle, two further things "
               "have to be right &mdash; and getting either wrong is "
               "worse than the leakage it was meant to fix.")]
story += bullets([
    "<b>The residual must be measured where the model is "
    "responsible.</b> With a Greenland mask the model describes one "
    "region while the data contains Antarctica, Alaska and global "
    "hydrology, so the GLOBAL residual never falls to the noise level: "
    "0.0085 globally against 0.0008 near the mask, with a noise level "
    "of 0.0024. The principle silently never fires and the run stops "
    "at MaxIter. <font face='Courier'>ResidualRegion</font> (default: "
    "the mask) fixes this.",
    "<b>The noise level must match the quantity being inverted.</b> "
    "The open-ocean RMS of a TREND field is 0.0024 m/yr &mdash; but "
    "most of that is real barystatic sea-level rise, not error. Using "
    "it stops the iteration after 4 steps and gives &minus;201.0 Gt/yr, "
    "13% low. The trend&rsquo;s actual noise is the monthly noise "
    "propagated through the fit, sigma_monthly / sqrt(Sxx) = 0.0115 / "
    "sqrt(8353) = 0.000125 m/yr &mdash; nineteen times smaller.",
])
story += code("""
% the concrete definitions this chapter previously left implicit
% (audit 2026-08: the recipe was not runnable as printed):
lat = (-89.5:89.5)';  lon = (0.5:359.5)';       % 1-degree grid
[LO, LA] = meshgrid(lon, lat);  lonW = mod(LO+180, 360) - 180;
box = @(a,b,c,d) LA>=a & LA<=b & lonW>=c & lonW<=d;
unionMask = gisMask ...                          % basin polygon pixels
    | box(60, 84, -128, -60) ...                 % Canadian Arctic
    | box(63, 67,  -25, -13) ...                 % Iceland
    | box(76, 81,   10,  34);                    % Svalbard
% Greenland mass rate from the corrected trend grid m [m/yr EWH]:
A  = (6371e3)^2 .* cosd(LA) * deg2rad(1)^2;      % cell areas [m^2]
Gt = sum(m(gisMask) .* A(gisMask), 'omitnan') * 1000 / 1e12;
""")
story += code("""
% monthly noise from the residuals about the deterministic fit ...
sigMon = shLowLevel.oceanRMS(residGrid, lat, lon, openOcean);
% ... propagated to the TREND: sigma_trend = sigma_monthly / sqrt(Sxx)
sigTrend = sigMon / sqrt(sum((epochs - mean(epochs)).^2));
[m, info] = shLowLevel.leakageCorrect(trendGrid, lat, lon, ...
    Filter = "gauss445", Mask = unionMask, NoiseLevel = sigTrend);
info.stoppedBy      % "discrepancy", after 82 iterations
""")
story += tbl(["Stopping rule", "Gt/yr", "vs published"], [
    ["fixed 300 iterations (no criterion)", "&minus;227.4", "&minus;1.6%"],
    ["discrepancy, trend-field oceanRMS (wrong noise)", "&minus;201.0",
     "&minus;13%"],
    ["<b>discrepancy, propagated trend noise</b>", "<b>&minus;224.6</b>",
     "<b>&minus;2.8%</b>"],
    ["<b>GravIS COST-G RL02, matching span</b>", "<b>&minus;231.1</b>",
     "&mdash;"],
], [7.2*cm, 3.2*cm, 3.2*cm])
story += [para("The regularised answer is 2.8% from the published one, "
               "slightly further than the 1.6% obtained by stopping at "
               "an arbitrary iteration count. That is the honest "
               "outcome: the closer number was a coincidence of where "
               "the iteration happened to be, and a result that depends "
               "on an arbitrary choice is not a result. This one "
               "follows from a stated criterion and a noise estimate "
               "that can be recomputed.")]

story += [para("V5. The lessons", "h2")]
story += [para("<b>The mask must cover every region that can hold mass, "
               "not only the one you are measuring.</b> A Greenland-only "
               "mask tells the inversion that mass exists nowhere else, "
               "so Canadian Arctic, Iceland and Svalbard signal is "
               "forced into Greenland: +12% instead of +4%. In the union "
               "solution the neighbours absorb &minus;112 Gt/yr &mdash; "
               "mass the first mask had nowhere to put. The union mask "
               "also converges faster. This is a usage rule, not a bug: "
               "<font face='Courier'>Mask=</font> always accepted a "
               "union.")]
story += [para("<b>The filter you declare must be the filter the "
               "FORWARD MODEL sees, not the filter the input file "
               "carries.</b> The inputs here are genuinely unfiltered, "
               "and declaring that was still wrong, because the method "
               "filters both sides. This cost more than the mask, the "
               "polygon resolution and the alias put together.")]
story += [para("<b>The S2 alias removal is worth 0.2 Gt/yr on a "
               "twenty-year trend &mdash; that is, nothing.</b> A "
               "161-day harmonic is very nearly orthogonal to a linear "
               "trend over two decades, so removing it barely moves the "
               "trend even though it is a real and necessary correction "
               "for the MONTHLY series. Reported here because it was "
               "expected to explain part of the residual and did not: a "
               "hypothesis removed is worth as much as one confirmed.")]

story += [para("V6. What the remaining 4% is, honestly", "h2")]
story += bullets([
    "GravIS inverts SEVEN drainage basins jointly (Sasgen et al. 2012); "
    "this recipe constrains one region against coarse neighbour boxes.",
    "The basin outline used here is decimated to 97.4% of the published "
    "area, and the neighbour outlines are rectangles.",
    "The iteration has not converged: step 3.2e-4 against Tol 1e-4 after "
    "900 iterations, and the estimate was still drifting "
    "(&minus;240.2 at 300, &minus;242.5 at 900). Call it &plusmn;5 Gt/yr.",
    "Nothing here was tuned to close the gap. A 4% agreement with an "
    "independently produced product, reached by matching its documented "
    "processing step for step, is the result; making it smaller by "
    "adjusting a mask until the number matched would not be.",
])

story += [para("V7. Antarctica: where the one-map inversion meets its limit", "h2")]
story += [para("The same chain, run unchanged on the same corrected, "
               "GIA-reduced series with the 25 GravIS AIS basin polygons as "
               "the mask (span 2002-04..2023-02, n = 217), gives "
               "&minus;125.7 Gt/yr against the official AWI basin-average "
               "product's &minus;146.9 &mdash; a 14% attenuation, an order "
               "of magnitude worse than Greenland's 2.8%. Three controls "
               "say the chain itself is healthy: the GIA field alone "
               "carries +52.2 Gt/yr of apparent mass over the AIS and the "
               "uncorrected chain lands at &minus;34.5 (the correction "
               "does exactly its advertised work); the wrong-noise "
               "control collapses to &minus;108 in 8 iterations with the "
               "same signature as Greenland; and an 8-fold sweep of the "
               "noise level moves the answer by 2 Gt/yr &mdash; the "
               "stopping rule is NOT the problem.")]
story += [para("The basin-by-basin comparison locates the gap: the "
               "inversion damps the EXTREMES of both signs (Amundsen and "
               "Getz come out 7&ndash;11 Gt/yr too weakly negative, the "
               "Dronning-Maud-sector accumulation basins 12&ndash;16 too "
               "weakly positive; 5.9 Gt/yr RMS per basin). The decisive "
               "cross-check is the SECOND official product: integrating "
               "the TU Dresden tailored-sensitivity-kernel GRID product "
               "(Groh &amp; Horwath 2021) over the same basin polygons "
               "gives &minus;112.8 Gt/yr with an 8.2 Gt/yr per-basin RMS "
               "and a 0.905 correlation to this chain's difference "
               "pattern. Every map-based estimator damps the same "
               "basins the same way; the Sasgen forward-modelling "
               "inversion (25 basins jointly, Sasgen et al. 2013) is a "
               "different method class, and the 14% is the distance "
               "between the classes, not a defect of the chain. A "
               "one-map inversion of a continent with a 113-pixel "
               "peninsula also reproduces every stopping pathology this "
               "guide warns about: the Peninsula alone never reaches the "
               "noise floor (maxIter), and the three sub-sheet "
               "inversions sum to &minus;172, not &minus;126 &mdash; "
               "V2's mask lesson, live.")]

story += [para("V8. Terrestrial water storage: 0.03 cm/yr against GravIS", "h2")]
story += [para("The hydrology test inverts the roles: small signals, "
               "seasonal amplitudes, and a reference (the GravIS TWS "
               "portal series, COST-G) whose averaging convention was "
               "first pinned by reproducing the official gridded "
               "product's basin means to two decimals from the same "
               "polygons. The chain &mdash; corrections, minus the NFIL "
               "mean, DDK3 as the declared stand-in for GravIS' VDK3/VDK5 "
               "blend, cos-weighted 1&deg; basin means over eleven major "
               "river basins, full 252-month span &mdash; reproduces the "
               "seasonal amplitudes at a median ratio of 1.001 "
               "(0.98..1.04). The trends came out at 0.225 cm/yr RMS "
               "with a pattern any geodesist will recognise: Mississippi "
               "&minus;0.49 against +0.07, Ob/Yenisei/Lena all too "
               "positive &mdash; the Laurentide and Fennoscandian GIA "
               "signature. Subtracting the same ICE-6G_D rate model the "
               "ice products use drops the trend RMS to "
               "<b>0.032 cm/yr</b> (Mississippi +0.09 vs +0.07, Ganges "
               "&minus;1.24 vs &minus;1.22, Amazonas +0.01 vs +0.01). "
               "Two findings travel beyond this toolbox: the GravIS TWS "
               "Technical Note (2025-08-14) does not mention a GIA "
               "correction, but the product plainly carries one &mdash; "
               "a 7-fold RMS reduction is not a coincidence; and the "
               "residual Ganges difference is consistent with GravIS' "
               "empirical removal of the 2004 Sumatra earthquake steps, "
               "which this chain deliberately does not model. Declare "
               "the filter, declare the GIA, and a 90-degree spherical "
               "harmonic series reproduces an independently produced "
               "hydrology product to three hundredths of a centimetre "
               "per year.")]
story += [para("V9. The chains: the validation as an API", "h2")]
story += fig("standardchain_flow.png",
    "The generic core: shLowLevel.standardChain applies the classic "
    "TN-14/TN-13 corrections in the only correct order, with the same "
    "drop-and-record policy for uncovered epochs. gravisL2B (below) is "
    "its GravIS-flavoured sibling: same shape, GravIS aux tables and "
    "NFIL mean instead of the TN files.", width=200)
story += fig("chains_flow.png",
    "The chain family at v3.11.0. gravisL2B is the single "
    "shared correction core; the ice chains share one engine "
    "(gravisRegionChain), the TWS chain filters and averages in "
    "per-basin boxes, and the ocean lane forks after the GAD "
    "restoration: oceanChain removes the atmospheric ocean mean for "
    "the barystatic series (with an optional EOF split of residual "
    "circulation from noise), obpChain keeps the air column and "
    "delivers GravIS-style bottom-pressure fields. "
    "Defaults ARE the tested configuration; the shipped data/gravis "
    "folder makes the calls below run as written.")
story += [para("Every number in V1&ndash;V8 is reproducible in one "
               "call. The shipped <font face='Courier'>data/gravis"
               "</font> copies (frozen 2026-08-12) cover the aux "
               "tables, the NFIL mean, the ICE-6G_D GIA rate and the "
               "GravIS basin polygons (<font face='Courier'>shLowLevel."
               "gravisDataFolder</font> returns the path); only the "
               "monthly series folder "
               "and the Love numbers are yours to supply. Greenland, "
               "with the guide-V4c ocean mask:")]
story += code("""kn = readmatrix("loadLoveNumbers_Gegout97.txt", FileType = "text", ...
    NumHeaderLines = 2);
oc = @(la, lo) abs(la) <= 55 & ~(la < -60 | ...      % crude continents
    (la > -35 & la < 37 & mod(lo+180,360)-180 > -17 & mod(lo+180,360)-180 < 52));
[gt, rep] = shLowLevel.greenlandChain("E:/series/COSTG", ...
    kn = kn, OceanMask = oc);                        % -> -225.6 Gt/yr
disp(rep.steps')""")
story += [para("Antarctica adds the 25-basin table, and "
               "<font face='Courier'>TrendGrid=</font> re-feeds a "
               "previous report so a sensitivity sweep costs seconds, "
               "not synthesis:")]
story += code("""[gt, rep] = shLowLevel.antarcticaChain("E:/series/COSTG", ...
    kn = kn, OceanMask = oc);                        % -> -125.7 Gt/yr
disp(rep.basins)                                     % 301..325 [Gt/yr]
gt2 = shLowLevel.antarcticaChain("E:/series/COSTG", kn = kn, ...
    TrendGrid = rep, NoiseLevel = 2 * rep.sigTrend); % noise sweep, ~20 s""")
story += [para("TWS runs full-span with GIA ON by default (the V8 "
               "finding); switching it off reproduces the 7&times; "
               "worse trend RMS:")]
story += code("""[out, rep] = shLowLevel.twsChain("E:/series/COSTG", kn = kn, ...
    Basins = ["Amazonas", "Ganges", "Mississippi River"], ...
    DDKFolder = "E:/DDK");                           % amp 20.5/14.3/6.1 cm
plot(out.epochs, out.series); legend(out.name)
noGia = shLowLevel.twsChain("E:/series/COSTG", kn = kn, ...
    Basins = "Mississippi River", DDKFolder = "E:/DDK", GIAFile = "");""")
story += [para("The two ice chains share one engine (<font "
               "face='Courier'>gravisRegionChain</font>); every input "
               "above is exchangeable, every deviation from the "
               "defaults is a declared sensitivity study, and REP "
               "records each step with the toolbox version. Data "
               "fetches behind these chains and all fetchers retry "
               "politely on 429/5xx: <font face='Courier'>httpFetch"
               "</font> honours the server's Retry-After header and "
               "<font face='Courier'>httpRetryDelay</font> supplies "
               "the capped, jittered backoff otherwise &mdash; the "
               "policy the GravIS portal's 503 bursts demanded during "
               "the V7/V8 data collection. Spelling convention "
               "throughout: every option is an arguments-block "
               "Name=value option in the house casing "
               "(<font face='Courier'>OceanMask=</font>, "
               "<font face='Courier'>Quantity=</font>) &mdash; no "
               "inputParser option is left since v4.0.0 &mdash; MATLAB "
               "matches the names case-insensitively, and quantity strings "
               "are lowercase. <font face='Courier'>Quantity = "
               "\"none\"</font> is the dimensionless passthrough for "
               "synthesizing raw coefficient fields.")]
story += [para("V10. Ocean and Slepian: closing the chain family", "h2")]
story += [para("The ocean is the missing member: <font face='Courier'>"
               "oceanChain</font> runs the same gravisL2B core, applies "
               "the ICE-6G_D ocean-floor GIA rate (a measured "
               "+0.89&nbsp;mm/yr lever on the barystatic trend) and "
               "gauss445, and returns the area-weighted ocean-mean "
               "series. Acceptance run on COST-G RL02.1 (252 months, "
               "|lat|&le;66&deg;, crude-continent mask): "
               "<b>+1.49&nbsp;&plusmn;&nbsp;0.02&nbsp;mm/yr "
               "(+312&nbsp;Gt/yr)</b>, annual amplitude 8.0&nbsp;mm. "
               "The ocean MEAN is filter-invariant to 0.01&nbsp;mm/yr "
               "while unfiltered pixel residuals are stripe-dominated "
               "(1.62&nbsp;m measured) &mdash; sigMon&nbsp;=&nbsp;"
               "0.0121&nbsp;m after the trend+seasonal separation is "
               "the honest noise proxy the V6 finding demanded. "
               "GAD/GAA restoration is a declared limitation "
               "(<font face='Courier'>GADFolder=</font> adds GAD where "
               "available; AOD1B carries no secular trend by "
               "construction).")]
story += code("""[out, rep] = shLowLevel.oceanChain("E:/series/COSTG", kn = kn, ...
    OceanMask = oc);                       % -> +1.49 mm/yr, +312 Gt/yr
plot(out.epochs, out.oceanMean)            % barystatic curve [cm]
noGia = shLowLevel.oceanChain("E:/series/COSTG", kn = kn, ...
    OceanMask = oc, GIAFile = "");         % the +0.89 mm/yr lever""")
story += [para("Slepian analysis gets its application half: project "
               "any coefficient series onto the ~Shannon leading "
               "tapers of a region and analyze those few well-posed "
               "modes instead of all P coefficients. The localization "
               "kernel is cross-validated against an independent "
               "Python ring quadrature (30&deg; cap, "
               "&lambda;&#8321;&nbsp;=&nbsp;0.999981), and ICGEM "
               "<font face='Courier'>dot</font> secular lines now read "
               "as <font face='Courier'>trnd</font> synonyms.")]
story += [para("Full ocean restoration (Chambers &amp; Willis 2010) "
               "is one fetch away: <font face='Courier'>fetchGAX</font> "
               "downloads the AOD1B monthly means as ICGEM-converted "
               ".gfc from the GFZ series pages (163 GRACE-era + 88 "
               "GRACE-FO files per product, verified live; the AOD1B "
               "products are centre-independent, so they serve COST-G "
               "too). <font face='Courier'>GADFolder=</font> adds the "
               "model ocean signal back on the coefficient level, "
               "<font face='Courier'>GAAFolder=</font> subtracts the "
               "per-epoch ocean mean of the atmospheric product - the "
               "land-ocean air-mass term GRACE sees but that is not "
               "water. Epoch coverage is reported, never silent: REP "
               "carries nGadRestored and nGaaApplied. Accepted on the "
               "full COST-G RL02.1 series (252 months, 251 covered): "
               "the annual amplitude rises from 8.0 to 9.1 mm - the "
               "published manometric range - while the trend moves "
               "only 0.08 mm/yr (+1.41 &plusmn; 0.03), confirming that "
               "AOD1B is trend-free by construction; the residual RMS "
               "grows from 1.21 to 1.49 cm because GAD puts REAL "
               "sub-annual ocean variability back into the field.")]
story += [para("<b>Bottom pressure versus barystatic - one step apart.</b> "
               "The GravIS Level-3 OBP product is GSM plus GAD with the "
               "standard corrections: bottom pressure is the weight of "
               "the FULL column (water plus air), so nothing is "
               "subtracted and the ocean mean contains the mean "
               "atmospheric mass. <font face='Courier'>obpChain</font> "
               "reproduces that recipe as gridded EWH anomalies against "
               "the GravIS reference window 2002/04-2020/03, with GAD "
               "added BEFORE the filter (the GravIS order - the filter "
               "note in both chain helps) and land set to NaN. "
               "<font face='Courier'>oceanChain</font> continues one "
               "step further and removes the ocean mean of GAA "
               "(Chambers &amp; Willis 2010) to isolate water mass.")]
story += code("""[obp, rep] = shLowLevel.obpChain(ser, kn = kn, OceanMask = oc, ...
    GADFolder = "E:/DATAPOOL/GravityField/GAX/GAD");
size(obp.grid)                 % nLat x nLon x T, land NaN
rep.nRefEpochs                 % epochs inside the GravIS window""")
story += [para("<b>Residual circulation, separated instead of ignored.</b> "
               "After the trend + seasonal fit the ocean pixels still "
               "carry coherent interannual dynamics - real circulation, "
               "not error. <font face='Courier'>eofSeparate</font> "
               "splits the residual stack with an area-weighted EOF and "
               "the North et al. (1982) rule, keeping modes while their "
               "eigenvalue is separated by more than its sampling "
               "uncertainty. The physical limit is stated, not hidden: "
               "modes at or below the Marchenko-Pastur noise bulk "
               "(about sigma^2 (1+sqrt(Q/T))^2) are not separable by "
               "ANY eigenvalue criterion - the Python pre-validation "
               "demonstrated exactly that failure before the synthetic "
               "amplitudes were dimensioned above the bulk. Passing "
               "SeparateCirculation to oceanChain applies the split and "
               "turns sigMon into the de-circulated noise RMS.")]
story += code("""[out, rep] = shLowLevel.oceanChain(ser, kn = kn, OceanMask = oc, ...
    GADFolder = gadF, GAAFolder = gaaF, SeparateCirculation = true);
[out.nModes, out.circulationRMS, out.sigMon]   % modes, circ, noise""")
story += [para("<b>The fetch family, one function per source and "
               "product.</b> fetchITSG and fetchICGEM download solution "
               "series; fetchGAX the AOD1B GAA/GAB/GAC/GAD monthly "
               "means from the ICGEM/GFZ pages; fetchITSGSINEX the ITSG "
               "monthly normal-equation SINEX from TU Graz - the ONLY "
               "public per-month SINEX source, and heavy: one n96 "
               "month is about 460 MB gzipped (verified live), so "
               "months are a required argument and there is no "
               "convenience \"all\"; fetchITSGBackground the ITSG "
               "monthly background models (dealiasing, tides, and in "
               "the GRACE era also atmosphere/ocean splits, c20, "
               "degree-1, GIA, hydrology). The ITSG background means "
               "are NOT the AOD1B GAX split - dealiasing is the "
               "closest GAC counterpart and no GAD substitute. All "
               "fetchers share one robust download loop: "
               "skip-if-present, MaxFiles/BudgetSec/MaxFailures caps, "
               "polite pauses, a single capped 429 retry, and a "
               "websave transport fallback.")]
story += code("""f = shLowLevel.fetchITSGBackground(["2018-06", "2018-07"]);
s = shLowLevel.fetchITSGSINEX("2018-06", Nmax = 96);   % ~460 MB, deliberate
snx = shLowLevel.readSINEX(s(1), Only = "estimate");""")
story += [para("<b>VDK decorrelation - the reason the SINEX fetcher "
               "exists.</b> With the monthly normal-equation matrices "
               "the VDK/VADER filter of Horvath et al. (2018) becomes "
               "buildable: x<sub>f</sub> = (N + &alpha;M)<sup>-1</sup>N x "
               "with the FORMAL monthly N (structure changes with "
               "orbit, repeat cycles and instrument state) and a "
               "cyclostationary Kaula signal model sigma_M(l) = a l^b "
               "estimated per calendar month from a pre-filtered "
               "series (signalVarianceKaula, with the exact "
               "log-chi-square bias correction - without it a biases "
               "6% low). Algebraically this is the SAME family as the "
               "tvANS Wiener filter (S = M<sup>-1</sup>, "
               "Python-verified to 1e-15); the difference is the "
               "input, and it is worth 15% median cumulative geoid "
               "error - an order of magnitude in short-repeat-cycle "
               "months (paper Table 2). tvANS remains the tool for "
               "series without released covariances. The full series "
               "is a deliberate batch (~460 MB SINEX per month): "
               "tools/dev/run_vdk_series.m is the resumable driver - "
               "downloads skip present files, months skip existing "
               "output, the signal model is cached, and the paper's "
               "closed-form identity runs as a built-in self-test.")]
story += code("""idx = shLowLevel.shIndex(96, Nmin= 2);
snx = shLowLevel.readSINEX(f, Index = idx);        % N + x, idx order
[ab, ~] = shLowLevel.signalVarianceKaula(ts.Cs, ts.Ss, ts.epochs);
xf = shLowLevel.vdkApply(snx.x, snx.M, idx.n, ab(mo, :), Alpha = 1);""")
story += [para("<b>Flood and drought indices per cell or basin.</b> "
               "hydroExtremeIndex turns any TWS stack - ts.toGrid grids "
               "or basinAverage series - into published extreme "
               "indices: the GRACE-DSI of Zhao et al. (2017), the "
               "standardized anomaly per calendar month with the "
               "11-class USDM-style categories (validated in the "
               "literature against USDM, PDSI, SPEI, NDVI and in-situ "
               "groundwater); the WSDI deficit standardization; and "
               "the Reager &amp; Famiglietti (2009) storage deficit - "
               "the CAUSAL flood predisposition (how much the store "
               "can still take), which with a precipitation grid "
               "becomes the full Flood Potential Index, the quantity "
               "behind multi-month flood lead times (Reager et al. "
               "2014, Nature Geoscience). One policy is quantified "
               "rather than assumed: detrending. The pre-validation "
               "planted an exceptional-drought month under a 0.5 "
               "cm/yr trend - undetrended it weakens from -2.41 to "
               "-1.44, OUT of its class, while 45% of the late "
               "decade turns spuriously wet; Detrend = linear is "
               "therefore the DSI/WSDI default, while StorageDeficit "
               "keeps the physical Reager convention (none). A robust "
               "sigma option (1.4826 MAD) survives single corrupt "
               "months that inflate the classical sigma sixfold. "
               "STAGE 2 is live too: on the ITSG daily Kalman "
               "solutions (fetchITSG Product = daily, 365 files/yr, "
               "n40) the index switches to a day-of-year climatology "
               "- per-DOY means, sigma from the RESIDUALS in a "
               "circular 31-day window that wraps December into "
               "January, with the sqrt(n/(n-1)) estimated-mean "
               "correction. The construction matters and was "
               "measured: window sigma on RAW values leaks the "
               "seasonal cycle (1.99 instead of 1.5), the two-stage "
               "form does not (1.52). Daily solutions track "
               "short-lived floods that monthly fields miss "
               "(Gouweleeuw et al. 2018, Ganges-Brahmaputra) - a "
               "planted +3-sigma January-2nd flood scores z = 2.9 "
               "across the year wrap.")]
story += code("""[tws, rep] = shLowLevel.twsChain(ser, kn = kn);
[Z, inf1] = shLowLevel.hydroExtremeIndex(tws.grid, tws.epochs);
inf1.categoryNames(inf1.category(iLat, iLon, end) + 6)   % cell class
[Sd, ~] = shLowLevel.hydroExtremeIndex(basinSeries, ep, ...
    Mode = "StorageDeficit");                 % flood predisposition""")
story += [para("<b>Offline by design.</b> No chain ever fetches: "
               "greenland/antarctica/tws/ocean/obp and every filter "
               "consume LOCAL paths only. The GravIS correction "
               "tables (C20/C30/C21/S21, degree 1, NFIL mean, GIA "
               "rate, ice basins) ship frozen inside the toolbox "
               "(data/gravis), so a fresh clone plus one local GSM "
               "series folder runs the ice and TWS chains completely "
               "offline; the ocean chains additionally need the "
               "GAD/GAA folders on disk - however they got there "
               "(fetchGAX, a browser, a copied drive: the chains "
               "cannot tell and do not care). The fetch* functions "
               "are one-time provisioners with skip-if-present "
               "semantics - re-running them against a populated "
               "folder is a no-op, and the VDK batch runs fully "
               "offline once its SINEX archive exists. Path "
               "resolution is three layers, explicit first: a "
               "passed argument always wins; below it the "
               "setup_shAnalysis preferences (SeriesFolder, "
               "MasconFile, GravisFolder, DDKFolder - "
               "setpref-persistent) and dataFolder() as the root for "
               "fetch targets; at the bottom the shipped freezes. The "
               "on-disk layout since v3.16 is uniform: temporal "
               "products under series/ (series/itsg/monthly|daily|"
               "sinex|background, series/&lt;group&gt;_&lt;center&gt;_&lt;series&gt; "
               "for an ICGEM series, "
               "series/GAX/&lt;product&gt;), static models under "
               "static/, auxiliaries under DDK/ and TN/; the fetchers "
               "warn once when they find data in a pre-v3.16 location "
               "instead of silently re-downloading. "
               "The single deliberate exception is gravisL2B with an "
               "explicit GravisFolder= requesting fresh tables - and "
               "even there the shipped freeze is the default, "
               "precisely so reproducibility never hangs on a "
               "server (the ISDC 503 episode was the confirmation).")]
story += [para("<b>Coastal leakage, controlled twice.</b> The crude "
               "ocean mask plus gauss445 lets land signal - Greenland "
               "above all - smear across the coast into the ocean "
               "mean. Two independent controls, both quantified "
               "before implementation: <font face='Courier'>"
               "CoastBufferKm</font> (the public helper <font "
               "face='Courier'>shLowLevel.erodeMask</font>) erodes "
               "the mask by a great-circle distance from every coast (the Python "
               "point-source experiment for gauss445: 300 km removes "
               "54% of the leak, 500 km 82%, at under 1% "
               "ocean-area loss - 300 km is the Chambers-style "
               "standard), and <font face='Courier'>"
               "RemoveLandLeakage</font> separates the outside-mask "
               "sources by two-sided alternating support projections "
               "(Papoulis-Gerchberg style, LandLeakIter sweeps) and "
               "subtracts the converged land component before the "
               "filter. The pre-validation taught the hard lesson "
               "here: a naive ONE-step subtraction makes the leak "
               "WORSE, because the reconstruction of the outside "
               "field rings INTO the mask; the two-sided iteration "
               "cuts an adjacent-source leak of 47% of the ocean "
               "mean by 94% (1D reference, frozen in CI on the "
               "band-limited spherical experiment). "
               "Since v3.16.1 the 300 km buffer IS the default - the "
               "machine re-baseline moved the barystatic trend "
               "+1.407 to +1.557 mm/yr (500 km: +1.647), into the "
               "published ~1.6-2.2 band; CoastBufferKm = 0 "
               "reproduces the pre-v3.16.1 numbers. Changing a "
               "validated number happened here the only allowed "
               "way: measured first, then decided, then frozen.")]
story += code("""[out, rep] = shLowLevel.oceanChain(ser, kn = kn, OceanMask = oc, ...
    GADFolder = gadF, GAAFolder = gaaF, ...
    CoastBufferKm = 300, RemoveLandLeakage = true);""")
story += code("""f = shLowLevel.fetchGAX("E:/DATAPOOL/GravityField/GAX");
[out, rep] = shLowLevel.oceanChain(ser, kn = kn, OceanMask = oc, ...
    GADFolder = "E:/DATAPOOL/GravityField/GAX/GAD", ...
    GAAFolder = "E:/DATAPOOL/GravityField/GAX/GAA");
[rep.nGadRestored, rep.nGaaApplied]        % coverage, reported""")
story += code("""idx = shLowLevel.shIndex(30, Nmin= 0);
[G, lam, info] = shLowLevel.slepianBasis(idx, @(la, lo) double(la > 60));
K = round(info.shannon);                   % ~N useful modes
a = shLowLevel.slepianProject(ts.Cs, ts.Ss, G(:, 1:K), idx);
plot(ts.epochs, a')                        % regional modes vs time""")
story += [PageBreak()]

story += [para("Demo gallery", "h1"),
          para("<font face='Courier'>demo_shAnalysis</font> is a case "
               "registry: <font face='Courier'>demo_shAnalysis(\"list\")"
               "</font> prints the table below, <font face='Courier'>"
               "demo_shAnalysis(\"all\")</font> runs everything, "
               "<font face='Courier'>demo_shAnalysis([\"D04\",\"D15\"])"
               "</font> runs a selection, and Visible=false keeps figures "
               "hidden for smoke tests. Real files in the test-data folder "
               "(shLowLevel.testDataDir: ITSG months, the DDK3 Wbd) are "
               "used when present; every case "
               "falls back to synthetic data. Love numbers in the demos "
               "are SYNTHETIC &mdash; real work requires a real loading "
               "model.")]
story += tbl(["ID", "Case", "Exercises"], [
    ["D01", "Read &amp; spectral diagnostics",
     "shReadGFC, shDegreeRMS, triangle, spectrum"],
    ["D02", "Synthesis quantities &amp; maps",
     "shSynthesis, kernelFactors, toGrid, Height"],
    ["D03", "Normal field &rarr; geoid",
     "normalFieldCS, subtractNormalField, toReference"],
    ["D04", "Filter comparison",
     "gaussian, fan, destripe, DDK, triangle diff"],
    ["D05", "Climatology &amp; basin series",
     "climatology, basinKernel, plotBasinSeries"],
    ["D06", "tvANS pipeline", "buildNoiseCov, tvANSFilter, basinDeconvolve"],
    ["D07", "Analysis (inverse)", "shAnalysisGrid, Kaula"],
    ["D08", "Basin tools", "basinKernel taper, deconvolve vs scaling"],
    ["D09", "Uncertainty", "errorMap, mcPropagate, plotCovariance"],
    ["D10", "Load deformation", "shSynthesisDeformation, Mode=points"],
    ["D11", "Gradient tensor", "shSynthesisGradientTensor"],
    ["D12", "EOF analysis", "eofAnalysis"],
    ["D13", "Trend breakpoints", "trendBreaks, F-test"],
    ["D14", "Multi-center combination", "combineCenters, VCE weights"],
    ["D15", "Sea-level fingerprint", "seaLevelFingerprint, evalMask"],
    ["D16", "Export", "writeGrid netCDF, writeAnimation MP4"],
], [1.1 * cm, 5.6 * cm, TEXT_W - 6.7 * cm])
story += [para("<b>Note.</b> Provenance of the figures below: rendered "
               "with the toolbox's Python validation port &mdash; the "
               "same algorithms that gate every MATLAB implementation, "
               "numerically equivalent by construction. D01/D02 use the "
               "REAL ITSG files among the test fixtures (and D04 the "
               "real DDK3 Wbd binary); the remaining figures use "
               "synthetic data with known ground truth, because recovery "
               "demonstrations (VCE factors, EOF modes, F-test "
               "calibration) require a truth to recover. "
               "<font face='Courier'>shLowLevel.fetchITSG(years)</font> extends "
               "the real-data demos to full monthly series. The MATLAB "
               "demo cases produce the interactive originals.")]

story += fig("d01.png",
             "<b>D01 &mdash; REAL DATA:</b> the shipped ITSG-Grace2018 "
             "2008-04 month (rendered by the rebuilt Python port, v2.5). "
             "Coefficient triangle (apex up; C00/C20 removed for "
             "display) and the degree-amplitude spectrum with the REAL "
             "formal errors from the gfc file. At this n60 truncation "
             "the formal errors stay ~3 orders below the signal - the "
             "signal/error crossover (the resolution limit) lies beyond "
             "the truncation degree; Kaula decay as the yardstick.")
story += fig("f-002.png",
             "<b>D02 &mdash; REAL DATA.</b> Left: the disturbing geoid of "
             "2008-04 after subtracting the WGS84 normal field computed "
             "from defining constants and rescaled to the ITSG (GM, R) "
             "&mdash; the classic &plusmn;100 m map (Indian Ocean low, "
             "New Guinea high). Right: the real 2008-2025 mass change "
             "(GRACE-FO minus GRACE, Gaussian 350 km, EWH): Greenland "
             "and West Antarctic mass loss stand out; residual "
             "meridional stripes at low latitudes are the real GRACE "
             "error structure. Honest caveats: synthetic Love numbers, "
             "no GIA correction, degree 1 absent &mdash; patterns are "
             "real, amplitudes approximate.")
story += fig("d04_gains.png",
             "<b>D04 &mdash; Filter gain over the (degree, order) "
             "triangle.</b> Gaussian: isotropic in degree. Fan (Han): "
             "the order Gaussian additionally damps high orders &mdash; "
             "the striping direction. DDK3 (diagonal of the real Wbd "
             "blocks): anisotropic and order-dependent &mdash; "
             "near-zonal signal survives to n~35 while high orders are "
             "suppressed hard; exactly the structure a GRACE error "
             "covariance demands.")
story += fig("d04_diff.png",
             "<b>D04b &mdash; REAL DATA, v2.4.2 fix:</b> the signed "
             "difference triangle (Gaussian 350 &minus; raw) on the real "
             "GRACE-FO &minus; GRACE field at n40 &mdash; the removed "
             "signal concentrates at the low orders where the real "
             "stripes and secular signal live. The sine wing now spans "
             "the full n &ge; m &ge; 1 support including the sectorals "
             "S<sub>nn</sub>: before v2.4.2 the difference mode blanked "
             "the sectoral edge and every diff triangle rendered the "
             "left wing one column narrower than the right (regression-"
             "tested on the rendered CData since).", width=330)
story += fig("f-006.png",
             "<b>D05/D06 &mdash; The standard basin figure</b> from "
             "plotBasinSeries: 1-sigma band, grey mission-gap patch, "
             "AR(1)-corrected trend annotation. With tvANS + "
             "basinDeconvolve the band comes from propagated posterior "
             "covariances instead of an empirical scatter.")
story += fig("f-008.png",
             "<b>D15 &mdash; Sea-level fingerprint</b> of a polar-cap "
             "melt, normalized by the eustatic mean: the near field "
             "FALLS (blue; lost self-attraction plus crustal rebound), "
             "the far field exceeds eustatic by ~20-30%. Mass conserved "
             "to machine precision &mdash; the printed residual is the "
             "built-in check.")
story += fig("f-010.png",
             "<b>D14 &mdash; Multi-center VCE:</b> per-(center, month) "
             "weights track the time-varying noise levels; the "
             "inter-center residual correlation matrix is the honesty "
             "diagnostic &mdash; VCE assumes independence, GRACE centers "
             "share data and background models.")
story += fig("f-012.png",
             "<b>D10 &mdash; Elastic load deformation:</b> up, north, "
             "east from the same residual field. Horizontals are ~1/3 "
             "of the vertical (validation run: 0.38) and require the "
             "exact SH gradient (legendreALFDeriv); east is undefined "
             "at the poles.")
story += fig("f-014.png",
             "<b>D11 &mdash; All six gradient tensor components</b> at "
             "250 km in Eotvos. The Laplace invariant G<sub>nn</sub> + "
             "G<sub>ee</sub> + G<sub>uu</sub> = 0 holds at roundoff "
             "(4e-15 of max|G| here) &mdash; a full-chain check of first "
             "and second Legendre derivatives, trig derivatives and "
             "frame terms at once.")
story += fig("f-016.png",
             "<b>D13 &mdash; Trend breakpoint:</b> continuous "
             "piecewise-linear hinge model vs the no-break fit; the "
             "F-test (p via betainc, base MATLAB) quantifies the break. "
             "Null rejection is calibrated at the nominal level (5.1% "
             "at 5%).")
story += [PageBreak()]

# ============================================================= appendix

# ===================================================== Part IV API reference
import sys as _sys
if _HERE not in _sys.path:
    _sys.path.insert(0, _HERE)
from api_data import API as _API


def _esc(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;")
             .replace(">", "&gt;"))


_INSTVAR = {"shCoefficients": "g", "shSeries": "ts", "shClimatology": "clim"}


def api_entry(e, qual):
    out = [para("<b>%s</b>" % _esc(qual), "h3")]
    # call-form signature
    if e["kind"] == "method" and not e.get("static"):
        callee = _INSTVAR[e["cls"]] + "." + e["name"]
        ins = [a for a in e["inputs"] if a not in ("obj",)]
    elif e["kind"] == "method":
        callee = e["cls"] + "." + e["name"]
        ins = e["inputs"]
    else:
        callee = qual
        ins = e["inputs"]
    nvargs = [a for a in e.get("args", []) if a["nv"]]
    ins = [a for a in ins if a != "opts"] +           (["Name=Value"] if nvargs else [])
    outs = e["outputs"]
    sig = (("[" + ", ".join(outs) + "] = ") if len(outs) > 1 else
           (outs[0] + " = " if outs else "")) + callee +           "(" + ", ".join(ins) + ")"
    out.append(para("<font face='Courier' size='8.2'>%s</font>" % _esc(sig)))
    d = (e.get("h1", "") + " " + e.get("desc", "")).strip()
    if len(d) > 520:
        d = d[:517] + "..."
    if d:
        out.append(para(_esc(d)))
    # inputs table from the arguments block (ground truth)
    rows = []
    for a in e.get("args", []):
        typ = a["cls"] or "&mdash;"
        if a.get("allowed"):
            typ += " &isin; " + _esc(a["allowed"])
        de = (a.get("desc") or "").strip()
        if len(de) > 160:
            de = de[:157] + "..."
        rows.append([a["name"], a["size"] or "&mdash;", typ,
                     _esc(a["default"]) if a["default"] else "required",
                     _esc(de) or "&mdash;"])
    if not rows:
        rows = [[i, "&mdash;", "&mdash;", "required", "&mdash;"]
                for i in ins if i != "Name=Value"]
    if rows:
        out += tbl(["input", "size", "type", "default", "description"],
                   rows,
                   [0.14 * TEXT_W, 0.09 * TEXT_W, 0.2 * TEXT_W,
                    0.15 * TEXT_W, 0.42 * TEXT_W])
    # outputs
    orow = e.get("outdocs") or [[o, ""] for o in outs]
    if orow:
        out += tbl(["output", "description"],
                   [[_esc(a), _esc(b)] for a, b in orow],
                   [0.18 * TEXT_W, 0.82 * TEXT_W])
    if e.get("example"):
        out.append(para("<i>Example</i>"))
        out += code(e["example"])
    return out


story += [PageBreak(), para("Part IV &mdash; API reference", "h1"),
          para("Generated from the source: the <b>arguments blocks are the "
               "ground truth</b> for input names, dimensions, classes and "
               "defaults (default 'required' = mandatory positional input); "
               "name-value options are passed as Name=Value. Conventions "
               "throughout: coefficient triangles are addressed C(n+1, m+1); "
               "vectors follow shLowLevel.shIndex ordering (Nmin= 2 unless "
               "stated); latitudes are geocentric degrees; filter radii in "
               "km, other lengths in m; epochs in decimal years. An entry "
               "whose help carries an example closes with it; every "
               "example is lint- and API-gated at build time.")]

for _cls in _API["classes"]:
    story += [para(_cls["name"] + " class", "h2"),
              para(_esc((_cls["h1"] + " " + _cls["desc"]).strip()[:600]))]
    if _cls["props"]:
        _rows = []
        for _p in _cls["props"]:
            _nm, _sz, _ty, _df, _cm = (_p + [""] * 5)[:5]
            _rows.append([_esc(_nm), _esc(_sz) or "&mdash;",
                          _esc(_ty) or "&mdash;",
                          _esc(_df) if _df else "&mdash;", _esc(_cm)])
        story += tbl(["property", "size", "type", "default", "notes"],
                     _rows, [0.18 * TEXT_W, 0.12 * TEXT_W, 0.2 * TEXT_W,
                             0.3 * TEXT_W, 0.2 * TEXT_W])
    for _m in _cls["methods"]:
        story += api_entry(_m, _cls["name"] + "." + _m["name"] +
                           (" (static)" if _m.get("static") else ""))

_CATS = [
 ("Readers, writers &amp; data management",
  ["shReadGFC", "shEvalGFCT", "readTN13", "readTN14", "readSINEX",
   "readDDK", "readMascon", "readSHM", "readGrid", "readLoveNumbers",
   "listICGEM", "listITSG", "fetchITSG", "fetchICGEM", "fetchDDK", "fetchTN",
   "fetchGAX", "fetchITSGSINEX", "fetchITSGBackground", "fetchLoveNumbers",
   "dataFolder", "gravisDataFolder", "testDataDir", "ddkNames",
   "parseGraceFilename", "icgemDate2Year", "writeGFC", "writeGrid",
   "writeAnimation", "writeFrames", "gridHandover", "requireGeoMap"]),
 ("Legendre, spectral tools &amp; indexing",
  ["legendreALF", "legendreALFDeriv", "legendreCached", "ylm", "shIndex",
   "vecFromCS", "csFromVec", "shDegreeRMS", "shOrderRMS",
   "shSpectralCrossover", "gaussLegendre"]),
 ("Synthesis &amp; analysis",
  ["shSynthesis", "synthesisMatrix", "synthesisPoints", "shSynthesisGradient",
   "shSynthesisDeformation", "shSynthesisGradientTensor", "shAnalysisGrid",
   "kernelFactors", "ellipsoidRadius", "normalFieldCS", "rescaleGMR",
   "geodetic2geocentric", "geocentric2geodetic", "evalMask"]),
 ("Filtering &amp; operators",
  ["filterSpec", "shGaussianWeights", "shGaussianFilter", "shFanFilter",
   "shDestripe", "applyDDK", "designFilter", "vdkApply",
   "signalVarianceKaula", "tvANSFilter", "buildNoiseCov", "buildSignalCov",
   "vceRescale", "opApply", "resolutionMap"]),
 ("Leakage correction",
  ["leakageCorrect", "leakageDataDriven", "gridScaling", "basinScaling",
   "sensitivityKernel", "oceanRMS", "erodeMask"]),
 ("Basins, regions &amp; uncertainty",
  ["basinKernel", "basinDeconvolve", "slepianBasis", "slepianProject",
   "fitDeterministicModel", "mcPropagate", "errorMap", "eofAnalysis",
   "eofSeparate", "seaLevelFingerprint", "hydroExtremeIndex", "pctile"]),
 ("Low degrees, rotation &amp; the mission gap",
  ["estimateDegree1", "poleTideConvert", "rotationExcitation",
   "bridgeGaps", "combineCenters"]),
 ("Temporal smoothing (Kalman/VAR)",
  ["kalmanChain", "estimateVAR", "kalmanFilter", "rtsSmoother",
   "buildCondFun", "neqCombine", "chi2Quantile"]),
 ("Validated chains",
  ["standardChain", "gravisL2B", "gravisRegionChain", "greenlandChain",
   "antarcticaChain", "twsChain", "oceanChain", "obpChain"]),
 ("Comparison &amp; validation metrics (v2.6.0)",
  ["compareSolutions", "compareSeries", "diffSpectrum", "spatialStats",
   "nashSutcliffe", "effectiveCorr", "threeCorneredHat",
   "taylorDiagram"]),
 ("Plotting",
  ["plotSHSpectrum", "plotSHCoeffTriangle", "plotBasinSeries",
   "plotCovariance"]),
]
_bynm = {e["name"]: e for e in _API["shLowLevel"]}
_used = set()
story += [para("Package +shLowLevel", "h2")]
for _t, _names in _CATS:
    story += [para(_t, "h3"), Spacer(1, 2)]
    for _n in _names:
        if _n in _bynm:
            story += api_entry(_bynm[_n], "shLowLevel." + _n)
            _used.add(_n)
_rest = [n for n in sorted(_bynm) if n not in _used]
if _rest:
    story += [para("Utilities", "h3")]
    for _n in _rest:
        story += api_entry(_bynm[_n], "shLowLevel." + _n)

story += [para("Toolbox root", "h2")]
for _e in _API["root"]:
    story += api_entry(_e, _e["name"])


story += [para("Appendix", "h1"),
          para("A. Error-identifier conventions", "h2"),
          para("Every identifier has three parts, owner:function:reason: "
               "<font face='Courier'>shLowLevel:&lt;function&gt;:"
               "&lt;reason&gt;</font> for package functions; "
               "<font face='Courier'>&lt;class&gt;:&lt;method&gt;:"
               "&lt;reason&gt;</font> for class methods, where the middle "
               "segment is the public method that raises it (the "
               "constructor included) or one of three shared checks "
               "named by concept (operands, stack, range); and "
               "<font face='Courier'>shAnalysis:&lt;function&gt;:"
               "&lt;reason&gt;</font> for the root functions. Each is "
               "documented in the help of the function or method that "
               "raises it, which tools/error_id_audit.py enforces. Every "
               "guard has a unit test; every message names the offending "
               "quantity. "
               "Instrumentation asserts (nonFiniteVCE, nonFiniteEig, "
               "nonFiniteOperator, allZeroVariance) remain in the code "
               "as a permanent safety net after the v2.1 debugging "
               "campaign."),
          para("B. Known limitations (documented, tested where "
               "applicable)", "h2")]
story += bullets([
    "TN-13 verified against the real GFZ, CSR and JPL RL06.3 files "
    "(v2.5; 256 paired months each, cross-provider C10 correlation "
    "0.995); SINEX against ITSG monthly files and synthetic fixtures "
    "&mdash; COST-G/other SINEX dialects may need parser tweaks (drop "
    "SINEX files into the test-data folder, shLowLevel.testDataDir; "
    "the discovery test picks them up).",
    "DDK: all eight released Wbd binaries parsed and gain-ordering "
    "validated (v2.5); a discovery test re-checks whatever subset is "
    "present locally. Other BIN dialects untested.",
    "readMascon is tested against a synthetic JPL-style fixture and has "
    "read a real CSR mascon product (v5.8.0); the opt-in "
    "SHX_MASCON_FILE test checks any real file you point it at "
    "&mdash; verify against yours (units, GIA convention, CRI flag).",
    "GIA uncertainty propagates only when a sigma field is given "
    "(removeGIA Sigma=, v5.2.0); AR(1) correction is first-order "
    "(Kendall-corrected r<sub>1</sub> since v2.5, ~3% residual optimism).",
    "Multi-center combination: common-mode errors invisible &rarr; "
    "posterior sigmas a lower bound.",
    "Basin sigma: deterministic-part errors correlated across epochs "
    "(pointwise 1-sigma reported).",
    "Streaming gz SINEX needs the JVM (fallback: gunzip to temp).",
    "ICGEM catalogue parsers are fixture-tested against real page "
    "captures (2026-08-07); a future site redesign would need refreshed "
    "fixtures (shLowLevel:listICGEM:parseFailed errors loudly).",
    "Earth-rotation excitation: the factors 1.098 and 0.753 are Chen "
    "&amp; Wilson's; ESMGFZ's prefactors give a 12% larger axial term "
    "(AxialFactor= takes that convention).",
    "Gap bridging: a filled month carries the resolution and the error "
    "of the bridge series (41% of the GRACE signal over degrees "
    "3&ndash;60 for the Kalman-filtered HLSST_SLR_COMB2023s at 750 km), "
    "and the whole bridged series is smoothed to match."])
story += [para("C. License &amp; provenance", "h2"),
          para("The toolbox is released under the MIT license (LICENSE "
               "in the package root; copyright Matthias Weigelt). The "
               "DDK3 Wbd test fixture carries its own MIT license from "
               "its upstream repository; the ITSG/GFZ files among the test "
               "fixtures (the testdata branch) remain the property of their providers "
               "and are included as test fixtures only."),
          para("All code, tests, documentation and this guide: developed "
               "by Matthias Weigelt with the help of Claude (Fable 5), "
               "2026-08-07 (v1 through v2.4.2 in working sessions the "
               "same week). Every numerical method was independently "
               "validated in Python before MATLAB implementation; MATLAB "
               "execution itself happens on the user's side with "
               "runAllTests as the acceptance gate (118/118 green at "
               "v2.1; 134 at v2.2.2; 167 at v2.4.1; 168 at v2.4.2; 179 "
               "at v2.5 &mdash; v2.5 adds the exact constrained "
               "posterior, the basin deterministic-sigma term, the "
               "Kendall AR(1) correction, shLowLevel.readLoveNumbers, "
               "setup_shAnalysis/shLowLevel.fetchTN with verified staged "
               "downloads, real CSR/JPL TN-13 + GSFC TN-14 fixtures "
               "and the DDK-pack validation).")]

# ---------------------------------------------------------------- build
doc.build(story)
print("built %s (%d snippets registered)" % (OUT, len(SNIPPETS)))
