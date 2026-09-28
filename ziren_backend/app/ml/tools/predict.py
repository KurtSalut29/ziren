#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Run one emergency report through the full Ziren pipeline and show every step.

    python tools/predict.py                                  interactive
    python tools/predict.py "may sunog didi ha Naval"         one report
    python tools/predict.py "may away didi" --selected CRIME  simulate the user's dropdown

Pipeline: normalise -> classify -> compare with the user's selection -> extract signals
-> severity rules -> routing -> human validation.
"""
import argparse, json, os, re, sys, csv

try:
    from sklearn.feature_extraction.text import TfidfVectorizer
    from sklearn.pipeline import FeatureUnion, Pipeline
    from sklearn.linear_model import LogisticRegression
    import joblib
except ImportError as e:
    sys.exit("Missing package: %s\nRun:  pip install scikit-learn joblib" % e.name)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MODEL = os.path.join(ROOT, "07_MODELS", "ziren_model.joblib")
FLAG_THRESHOLD = 0.60          # from results_checker.csv: 70% catch, 0% false alarms

AGENCY = {"FIRE": ["BFP"], "CRIME": ["PNP"], "ACCIDENT": ["MDRRMO"],
          "VEHICULAR_ACCIDENT": ["PNP", "MDRRMO"], "MEDICAL": ["MDRRMO"],
          "NATURAL_HAZARD": ["MDRRMO"]}

INJURY = re.compile(
    r"nasamdan|nasamad|samad|samdan|sugatan|sugat|nagdurugo|nagdugo|duguan|dugo"
    r"|hurt|bleeding|injured|wounded|fracture|broken"
    r"|nakahigda|naghigda|nakahandusay|lying on the ground"
    # fractures and limb injuries - "bali ang tiil", "nabalian", "napiang"
    r"|\bbali\b|nabali|nabalian|nabalii|pilay|napilay|napiang|piang"
    r"|(?:bali|nabali)\s+(?:ang|an|ng)\s+(?:tiil|siki|kamot|bukton|braso|ulo|paa|bitiis)"
    , re.I)
MEDICAL_NEED = re.compile(r"ambulansya|ambulance|dughan|chest|luspad|namumutla|pale|"
                          r"lisod na maginhawa|hirap na huminga|trouble breathing|"
                          r"dili na motubag|diri na nagbabaton|not responding|collapsed|"
                          r"natumba|nalumos|nalunod|drown|nakuryente|electrocut", re.I)
UNSURE = re.compile(r"basi|basin|baka|not sure|dili ko sigurado|hindi ko sigurado", re.I)
# "diri na kami makagawas" and "may tawo pa ha sulod" both mean someone cannot get out.
# Allow filler words between the negation and the verb, and treat "still inside" as trapped.
TRAPPED_NEGFORM = re.compile(
    r"(?:dili|diri|hindi|wala|waray)\s+(?:\w+\s+){0,3}?(?:maka|maka-)?(?:gawas|labas|lihok|halin)"
    r"|cannot get out|can'?t get out", re.I)
TRAPPED_AFFIRM = re.compile(
    # "na trap" / "na-trap" / "natrap": the English verb carrying the Bisaya and
    # Waray perfective prefix, which is how residents actually say it. Matching
    # only "trapped" missed "naay na trap sa sulod" — someone is inside a
    # burning house — and that is the highest-value signal a fire report has.
    r"na[\s-]?trap(?:ped)?\b"
    r"|trapped|na-?ipit|naipit|natabunan|nabaon|buried|stuck|still inside|trapped inside"
    # (?:ng|g)? is the Tagalog/Bisaya linker: "batang naiwan", "taong
    # naipit". Without it the bare noun matched and the natural
    # phrasing did not.
    r"|(?:tawo|tao|bata|katawhan|people|person|child)(?:ng|g)?\s+(?:\w+\s+){0,3}?(?:ha|sa)\s+(?:sulod|loob)"
    r"|(?:naa|may|naay)\s+(?:pa\s+)?(?:tawo|tao|bata)(?:ng|g)?\s+(?:pa\s+)?(?:ha|sa)\s+(?:sulod|loob)", re.I)
TRAPPED = re.compile(
    r"na[\s-]?trap(?:ped)?\b"
    r"|trapped|na-?ipit|naipit|natabunan|nabaon|buried|stuck"
    r"|(?:dili|diri|hindi|wala|waray)\s+(?:\w+\s+){0,3}?(?:maka|maka-)?(?:gawas|labas|lihok|halin)"
    r"|(?:tawo|tao|bata|katawhan|people|person|child)(?:ng|g)?\s+(?:\w+\s+){0,3}?"
    r"(?:ha|sa)\s+(?:sulod|loob)"
    r"|(?:naa|may|naay)\s+(?:pa\s+)?(?:tawo|tao|bata)(?:ng|g)?\s+(?:pa\s+)?(?:ha|sa)\s+(?:sulod|loob)"
    r"|still inside|trapped inside|cannot get out|can'?t get out", re.I)
FATAL = re.compile(r"patay|namatay|died|dead|wala nay ginhawa|walay kinabuhi", re.I)
SPREAD = re.compile(r"nagkakalat|kumakalat|spreading|nagsangyaw|padayon nga|grabe na", re.I)
STRUCT = re.compile(r"balay|bahay|house|building|balayan|eskwelahan|school|tindahan|store|"
                    r"balayan|kabalayan|barong-?barong|apartment|dormitor", re.I)
WEAPON = re.compile(r"\bpusil\b|baril|gun|armas|weapon|armed|kutsilyo|kutsilyu|sundang|"
                    r"itak|bolo|knife|blade|bladed|sanggot|garab|granada|grenade", re.I)
UNRESPONSIVE = re.compile(r"dili na motubag|diri na nagbabaton|wala na motubag|hindi na sumasagot|"
                          r"not responding|unresponsive|unconscious|wala nay ginhawa|"
                          r"dili maghinuktok|walay reaksyon|hindi gumagalaw", re.I)
NUM = re.compile(r"\b(\d{1,2})\b")

# Counts in Waray/Cebuano/Tagalog are usually written as words.
WORDNUM = {
    "usa": 1, "isa": 1, "uno": 1,
    "duha": 2, "duwa": 2, "dalawa": 2, "dos": 2,
    "tulo": 3, "tolo": 3, "tatlo": 3, "tres": 3,
    "upat": 4, "apat": 4, "kwatro": 4,
    "lima": 5, "singko": 5,
    "unom": 6, "anim": 6, "unum": 6,
    "pito": 7, "walo": 8, "siyam": 9, "syam": 9,
    "napulo": 10, "sampu": 10, "napulu": 10,
}

# A number means nothing without the thing it counts. "duha ka motor" is two VEHICLES;
# "duha ka tawo" is two PEOPLE; "duha an nasamdan" is two INJURED. Counting them into
# one bucket produces a severity decision based on a fiction.
ENTITY = {
    "people": r"tawo|tao|katawhan|tawhan|bata|bataa?n|lalaki|babaye|babae|persona?s?|"
              r"people|person|biktima|victims?|pasahero|passengers?|estudyante|students?|"
              r"residente|residents?|pamilya|famil(?:y|ies)|myembro",
    "vehicles": r"motor(?:siklo|cycle)?s?|sakyanan|sasakyan|salakyanan|kotse|cars?|"
                r"trucks?|trak|tricycles?|traysikel|habal-?habal|multicab|vans?|jeeps?|"
                r"jeepney|bisikleta|bikes?|pick-?ups?|bus(?:es)?|ambulansya|ambulances?",
    "injured": r"nasamdan|nasamad|samdan|sugatan|sugat|injured|hurt|wounded|nabalian|"
               r"napilay|napiang|nasakitan",
    "dead": r"patay|namatay|nangamatay|deads?|dead|fatalit(?:y|ies)|nawad-?an hin kinabuhi",
}
_NUMWORD = "|".join(n + r"(?:ng|g)?" for n in WORDNUM) + r"|\d{1,2}"
# "kabuok" / "kabook" / "ka buok" is the Bisaya and Waray classifier for counting
# people and things — "duha kabook" is "two of them". It has to be tried BEFORE
# the bare "ka" connector, or "ka" matches and leaves "book" stranded in front of
# the noun, and the count is silently dropped.
_CLASSIFIER = r"kabuok|kabook|kabuk|ka\s+buok|ka\s+buk"
# One connector is not enough once the classifier is in play: "tulo kabuok ang
# nasamdan" spends "kabuok" on the classifier and still has "ang" standing
# between the number and the noun, so a single-slot connector drops the count.
_CONN = (r"(?:(?:" + _CLASSIFIER + r"|ka|nga|an|ang|na|ng|mga)"
         r"(?:\s+(?:an|ang|nga|na|ng|mga))?)?")
# "duha ka motor" / "2 motor" / "duha nga tawo" / "tulo an nasamdan" / "2 ang patay"
COUNT_PAT = {
    k: re.compile(r"\b(" + _NUMWORD + r")\s+" + _CONN + r"\s*(?:ka\s+)?(?:mga\s+)?"
                  r"(?:" + v + r")\b", re.I)
    for k, v in ENTITY.items()
}
# the reverse order: "nasamdan nga duha", "patay nga usa"
COUNT_PAT_REV = {
    k: re.compile(r"\b(?:" + v + r")\s+(?:nga|na|ng)?\s*(" + _NUMWORD + r")\b", re.I)
    for k, v in ENTITY.items()
}

# "tulo ka tawo an nasamdan" / "dalawang tao ang sugatan" - a people-count followed by an
# injury word means that many are injured, not merely present.
PEOPLE_THEN_INJURED = re.compile(
    r"\b(" + _NUMWORD + r")\s+" + _CONN + r"\s*(?:mga\s+)?(?:" + ENTITY["people"] +
    r")\s+(?:an|ang|na|nga|ay|ang mga)?\s*(?:" + ENTITY["injured"] + r")\b", re.I)
PEOPLE_THEN_DEAD = re.compile(
    r"\b(" + _NUMWORD + r")\s+" + _CONN + r"\s*(?:mga\s+)?(?:" + ENTITY["people"] +
    r")\s+(?:an|ang|na|nga|ay|ang mga)?\s*(?:" + ENTITY["dead"] + r")\b", re.I)

# "duha kabook ang na trap" / "tulo ka tawo nga naipit": how many are trapped.
# Spoken reports drop the person noun once the classifier has been said, so this
# counts off the trapped word rather than off a noun that is not there.
TRAPPED_COUNT = re.compile(
    r"\b(" + _NUMWORD + r")\s+" + _CONN + r"\s*(?:mga\s+)?(?:(?:" + ENTITY["people"] +
    r")\s+)?(?:an|ang|na|nga|ay)?\s*"
    r"(?:na[\s-]?trap(?:ped)?|trapped|na-?ipit|naipit|natabunan|nabaon)\b", re.I)

# Negators in Waray / Cebuano / Tagalog. A signal word preceded by one of these within a
# short window is explicitly DENIED, which is different from unknown: "waray nasamdan"
# means nobody is hurt, and must not be read as an injury.
NEGATOR = r"(?:wala|walay|wala'?y|waray|dili|diri|\bdi\b|hindi|hindi\s+po|ayaw)"
NEG_WINDOW = 4          # tokens between the negator and the signal word


def _negated(text, match):
    """True when a negator sits just before this match."""
    before = text[: match.start()]
    tail = before.split()[-NEG_WINDOW:]
    return bool(re.search(NEGATOR + r"$|" + NEGATOR + r"\b", " ".join(tail), re.I))


def _find(pat, text):
    """First non-negated match, or None. Returns (match, denied) where denied=True means
    the report explicitly says this is NOT the case."""
    denied = False
    for m in pat.finditer(text):
        if _negated(text, m):
            denied = True
            continue
        return m, False
    return None, denied


HAZARD = re.compile(r"nagtagas|tumatagas|tumulo|nagtutulo|leak(?:ing)?|gasolina|gasoline|"
                    r"lpg|gas tank|kuryente nga nahulog|live wire|nagkakalat|kumakalat|"
                    r"spreading|nagsangyaw|padayon nga nag|nagdako", re.I)

BARANGAYS = ["san isidro", "san roque", "julita", "canila", "bato", "burabod", "sanggalang",
             "sangalang", "busali", "pinangumhan", "hugpa", "villa enage", "naval", "almeria",
             "caibiran", "culaba", "kawayan", "maripipi", "cabucgayan", "biliran", "pili",
             "tabunan", "tamarindo", "virginia", "bunga", "caray-caray", "caraycaray",
             "larrazabal", "ungale", "cabibihan", "anislagan", "balaquid", "baso", "bari-is",
             "sampao", "manlabang", "union", "atipolo", "calumpang", "agpangi", "talahid",
             "catmon", "libertad", "looc", "marvel", "agutay", "tucdao", "uson", "maurang",
             "santo rosario", "p.i. garcia", "padre inocentes garcia", "talustusan", "borac",
             "haguikhikan", "imelda", "matanggo", "iyusan", "jamorawon", "danao", "viga"]
BARANGAY_PAT = re.compile(r"\b(" + "|".join(re.escape(b) for b in
                          sorted(BARANGAYS, key=len, reverse=True)) + r")\b", re.I)
# These barangay names are also ordinary words: bato = stone, bunga = fruit,
# libertad = liberty, pili = to choose, danao = lake. Accept them as a location only
# with a "brgy"/"barangay"/"purok" marker, or when capitalised in the original text.
AMBIGUOUS_PLACE = {"bato", "union", "naval", "libertad", "bunga", "pili", "danao", "viga",
                   "marvel", "looc", "catmon", "imelda", "virginia", "julita", "biliran"}
PLACE_MARKER = re.compile(r"(?:brgy\.?|barangay|bgy\.?|purok|sitio)\s*$", re.I)


def strip_places(text):
    """Remove barangay names before classification. Location is recovered separately by
    extract(), so nothing is lost - but the classifier can no longer learn that a place
    name predicts a category, which would not generalise to unseen barangays."""
    return re.sub(r"\s+", " ", BARANGAY_PAT.sub(" ", text)).strip()


def _numval(tok):
    tok = tok.lower()
    if tok.isdigit():
        return int(tok)
    if tok in WORDNUM:
        return WORDNUM[tok]
    for suf in ("ng", "g"):                       # Tagalog ligature: tatlong -> tatlo
        if tok.endswith(suf) and tok[: -len(suf)] in WORDNUM:
            return WORDNUM[tok[: -len(suf)]]
    return None


def _count(text, kind):
    """Number attached to a specific entity type, in either word order."""
    if kind == "injured":
        m = PEOPLE_THEN_INJURED.search(text)
        if m:
            return _numval(m.group(1))
    if kind == "dead":
        m = PEOPLE_THEN_DEAD.search(text)
        if m:
            return _numval(m.group(1))
    for pat in (COUNT_PAT[kind], COUNT_PAT_REV[kind]):
        m = pat.search(text)
        if m:
            return _numval(m.group(1))
    return None


def load_dict():
    d = {}
    for fn in ("misspellings.csv",):
        p = os.path.join(ROOT, "06_DICTIONARY", fn)
        if os.path.exists(p):
            for r in csv.DictReader(open(p, encoding="utf-8")):
                if r.get("observed") and r.get("corrected"):
                    d[r["observed"].lower()] = r["corrected"]
    terms = []
    p = os.path.join(ROOT, "06_DICTIONARY", "emergency_terms.csv")
    if os.path.exists(p):
        terms = sorted({r["term"].lower() for r in csv.DictReader(open(p, encoding="utf-8"))
                        if r.get("term")})
    return d, terms


# Words fuzzy matching must NEVER touch. Number words and common function words are
# short, so they score high against unrelated dictionary terms - "tulo" (three) was
# being rewritten to "tulong" (help), silently destroying the casualty count.
PROTECTED = set("""
usa isa uno duha duwa dalawa dos tulo tolo tatlo tres upat apat kwatro lima singko
unom anim unum pito walo siyam syam napulo sampu napulu
may naay naa an ang ng nga ka na ug ngan sa ha didi diri dinhi dito po ba ko ako
kami kita sila siya hiya iya amon among namin natin ini adto ini-an mga ni si
ug og o at pero pero kay kai kun kon nga in on at is to the a of and it
""".split())


def _threshold_for(word):
    """Short words need a higher bar - one edit costs proportionally more, so unrelated
    short words collide easily."""
    n = len(word)
    if n <= 4:
        return 92
    if n <= 6:
        return 85
    return 78


def normalise(text, aliases, terms, threshold=None):
    """Alias table first (abbreviations), then fuzzy match (typos)."""
    changes = []
    out = []
    for w in text.split():
        bare = re.sub(r"[^\w']", "", w.lower())
        if not bare:
            out.append(w); continue
        if bare in PROTECTED:
            out.append(w); continue
        if bare in aliases:
            out.append(w.replace(bare, aliases[bare]) if bare in w.lower() else aliases[bare])
            changes.append("%s -> %s (alias)" % (bare, aliases[bare]))
            continue
        try:
            from rapidfuzz import process, fuzz
            if terms and bare not in terms:      # already a valid term - leave it alone
                m, score, _ = process.extractOne(bare, terms, scorer=fuzz.ratio)
                th = threshold if threshold is not None else _threshold_for(bare)
                if score >= th and m != bare:
                    out.append(w.lower().replace(bare, m))
                    changes.append("%s -> %s (%.0f)" % (bare, m, score))
                    continue
        except ImportError:
            pass
        out.append(w)
    return " ".join(out), changes


def train_if_needed(force=False):
    if os.path.exists(MODEL) and not force:
        return joblib.load(MODEL)
    tr = os.path.join(ROOT, "03_CLASSIFICATION", "splits", "train.csv")
    if not os.path.exists(tr):
        sys.exit("No train.csv. Run:  python tools/make_splits.py")
    rows = list(csv.DictReader(open(tr, encoding="utf-8")))
    X = [strip_places(r["report_text"]) for r in rows]
    y = [r["incident_type"] for r in rows]
    pipe = Pipeline([
        ("feats", FeatureUnion([
            ("word", TfidfVectorizer(analyzer="word", ngram_range=(1, 2), sublinear_tf=True)),
            ("char", TfidfVectorizer(analyzer="char_wb", ngram_range=(3, 5),
                                     sublinear_tf=True, min_df=2)),
        ])),
        ("clf", LogisticRegression(max_iter=2000, C=5.0, class_weight="balanced",
                                   random_state=42)),
    ]).fit(X, y)
    os.makedirs(os.path.dirname(MODEL), exist_ok=True)
    joblib.dump(pipe, MODEL)
    print("[trained on %d rows and cached to 07_MODELS/ziren_model.joblib]\n" % len(rows))
    return pipe


STALE = re.compile(r"last week|last month|kagahapon|niadtong|kaniadto|nakaraang|"
                   r"natapos na|human na|tapos na|safe na|okay na na|controlled na|"
                   r"gipalong na|napalong na|patay na ang kalayo", re.I)


def extract(text):
    """Signals recoverable from the report text alone.

    Three states, not two: True (stated), False (explicitly denied), None (unknown).
    A denial is not the same as silence - "waray nasamdan" means nobody is hurt, while
    saying nothing about injuries means we do not know.
    """
    sig = {}
    hedged = bool(UNSURE.search(text))

    def flag(pat):
        m, denied = _find(pat, text)
        if m:
            return True
        return False if denied else None

    inj_m, inj_denied = _find(INJURY, text)
    med_m, med_denied = _find(MEDICAL_NEED, text)
    inj_n = _count(text, "injured")
    dead_m, dead_denied = _find(FATAL, text)
    dead_n = _count(text, "dead")
    if dead_denied:
        dead_n = None

    casualty = bool(inj_m or med_m)
    if hedged and casualty:
        sig["injured"] = None
    elif casualty or inj_n:
        sig["injured"] = True
    elif inj_denied or med_denied:
        sig["injured"] = False
    else:
        sig["injured"] = None
    sig["injured_count"] = inj_n if sig["injured"] is not False else None
    sig["fatalities"] = (dead_n if dead_n else (1 if dead_m else None))

    # Entrapment has two forms and only the affirmative one can be negated:
    # "dili naipit" denies it, but "dili makagawas" IS the signal.
    aff = flag(TRAPPED_AFFIRM)
    negform = bool(TRAPPED_NEGFORM.search(text))
    sig["entrapment"] = True if (aff is True or negform) else (False if aff is False else None)

    sig["hazard_spreading"] = True if (SPREAD.search(text) or HAZARD.search(text)) else None
    sig["structure_involved"] = flag(STRUCT)
    sig["weapon_mentioned"] = flag(WEAPON)
    sig["unresponsive"] = flag(UNRESPONSIVE)

    people = _count(text, "people")
    vehicles = _count(text, "vehicles")
    if people is None and inj_n:
        people = inj_n
    if people is None and sig["entrapment"] is not False:
        # "duha kabook ang na trap" states a headcount without ever naming a
        # person, so the people-noun patterns above cannot see it. Skipped when
        # entrapment was explicitly denied — a denial should not import a count.
        m = TRAPPED_COUNT.search(text)
        if m:
            people = _numval(m.group(1))
    sig["people_involved"] = people
    sig["vehicles_involved"] = vehicles

    # Location: ambiguous names need a marker or a capital letter.
    sig["location"] = None
    for m in BARANGAY_PAT.finditer(text):
        raw = m.group(1)
        if raw.lower() in AMBIGUOUS_PLACE:
            marked = bool(PLACE_MARKER.search(text[: m.start()]))
            capped = raw[0].isupper()
            if not (marked or capped):
                continue
        sig["location"] = raw.title()
        break

    sig["possibly_stale"] = True if STALE.search(text) else None
    return sig, hedged


def severity(sig, category, confidence, category_from_user=True):
    """The 14-rule engine. Priority order, first match wins.

    `category_from_user` says whether `category` is the resident's own selection
    or the model's guess. It matters for SR005B/SR005E/SR005F: a resident who
    taps a category is asserting something about the scene, and that assertion
    stands however the text reads. A low-confidence MODEL guess asserts nothing,
    and must not be allowed to lift an unreadable report over the SR010 fail-safe.

    Only MEDICAL, FIRE and NATURAL_HAZARD get a category floor. All three share
    the same justification: harm compounds the longer the response is delayed
    (a person in distress, a fire that spreads, a hazard that reaches more
    homes), so treating the bare category as reason enough to escalate errs
    the direction that costs less. CRIME does not get one — "domestic dispute
    or crime" spans a noise complaint and an armed robbery, and unlike the
    other three the category alone says nothing about whether delay makes it
    worse. It keeps its narrower signal-gated rule (SR005C) and otherwise
    falls through to the same SR010/SR011 fail-safe as any other category
    with nothing else known.
    """
    R = []
    if sig["fatalities"]:                                  R.append(("SR001", "CRITICAL", "fatality reported"))
    if sig["entrapment"]:                                  R.append(("SR002", "CRITICAL", "someone is trapped"))
    if (sig["injured_count"] or 0) >= 3:                   R.append(("SR003", "CRITICAL", "3+ injured"))
    if (sig["people_involved"] or 0) >= 3 and sig["injured"]:
                                                           R.append(("SR003", "CRITICAL", "multiple casualties"))
    if sig["injured"] and sig["unresponsive"]:             R.append(("SR004", "CRITICAL", "casualty is unresponsive"))
    if category == "FIRE" and sig["structure_involved"]:   R.append(("SR005", "HIGH", "structural fire"))
    if category == "MEDICAL" and (category_from_user or confidence >= FLAG_THRESHOLD):
                                                           R.append(("SR005B", "HIGH", "medical category floor - a person is in distress"))
    if category == "CRIME" and sig["weapon_mentioned"]:    R.append(("SR005C", "HIGH", "weapon present - danger to responders"))
    if category == "NATURAL_HAZARD" and sig["structure_involved"]:
                                                           R.append(("SR005D", "HIGH", "hazard has reached homes"))
    if category == "FIRE" and (category_from_user or confidence >= FLAG_THRESHOLD):
                                                           R.append(("SR005E", "HIGH", "fire category floor - fire risk compounds without intervention"))
    if category == "NATURAL_HAZARD" and (category_from_user or confidence >= FLAG_THRESHOLD):
                                                           R.append(("SR005F", "HIGH", "natural hazard category floor - hazard risk compounds and usually reaches beyond the reporter alone"))
    if sig["injured"]:                                     R.append(("SR006", "HIGH", "injury reported"))
    if (sig["people_involved"] or 0) >= 5:                 R.append(("SR007", "HIGH", "5+ people involved"))
    if sig["hazard_spreading"]:                            R.append(("SR008", "HIGH", "hazard is spreading"))
    # location and vehicle count describe the scene, not its seriousness
    known = [k for k, v in sig.items()
             if v is not None and k not in ("location", "vehicles_involved",
                                            "possibly_stale")]
    if not known:                                          R.append(("SR010", "MODERATE", "no signals readable - fail-safe, route to a human"))
    if confidence < FLAG_THRESHOLD and not known:          R.append(("SR011", "MODERATE", "low confidence and no signal - fail-safe"))
    if not R:                                              R.append(("SR012", "LOW", "confirmed incident, low signal"))
    return R[0]


def run(text, selected, pipe, aliases, terms, quiet=False):
    norm, changes = normalise(text, aliases, terms)
    # Classify the ORIGINAL text, not the fuzzy-corrected one. The classifier is
    # trained on un-normalised text and its char n-grams already absorb spelling
    # variation; running RapidFuzz first creates train/serve skew and collapses
    # distinctions the model relies on (measured: 6 errors -> 14). `norm` is still
    # used below for rule-based signal extraction, where alias correction helps.
    proba = pipe.predict_proba([strip_places(text)])[0]
    classes = list(pipe.named_steps["clf"].classes_)
    order = proba.argsort()[::-1]
    pred, conf = classes[order[0]], float(proba[order[0]])

    sig, hedged = extract(norm)
    routing_cat = selected or pred
    rule, level, why = severity(sig, routing_cat, conf,
                                category_from_user=selected is not None)

    if selected is None:
        verification = "NO_SELECTION"
        vmsg = "User made no selection; the model's category was used."
    elif selected == pred:
        verification = "AGREE"
        vmsg = "The model agrees with the user's selection."
    elif conf >= FLAG_THRESHOLD:
        verification = "MISMATCH_FLAGGED"
        vmsg = ("The text reads as %s (%.2f) but %s was selected. Confirm before dispatch."
                % (pred, conf, selected))
    else:
        verification = "UNCERTAIN"
        vmsg = "The model is unsure (%.2f); deferring to the user's selection." % conf

    agencies = list(AGENCY.get(routing_cat, []))
    if sig["entrapment"] and "BFP" not in agencies:
        agencies.append("BFP")
    if sig["injured"] and "MDRRMO" not in agencies:
        agencies.append("MDRRMO")

    if not quiet:
        print("-" * 72)
        print("REPORT      %s" % text)
        if changes:
            print("NORMALISED  %s" % norm)
            for c in changes:
                print("            %s" % c)
        print()
        print("MODEL READS %-22s confidence %.2f" % (pred, conf))
        print("            runner-up: %s (%.2f)" % (classes[order[1]], proba[order[1]]))
        if selected:
            print("USER PICKED %s" % selected)
        print("VERIFY      %-18s %s" % (verification, vmsg))
        print()
        known = {k: v for k, v in sig.items() if v is not None}
        print("SIGNALS     %s" % (", ".join("%s=%s" % kv for kv in known.items())
                                  if known else "none readable"))
        unknown = [k for k, v in sig.items() if v is None]
        if unknown:
            print("UNKNOWN     %s" % ", ".join(unknown))
        if hedged:
            print("            (caller hedged - treated as unknown, not as 'no')")
        print()
        print("SEVERITY    %-10s  %s fired: %s" % (level, rule, why))
        print("ROUTING     %s   (based on %s)" % (" + ".join(agencies),
                                                  "user selection" if selected else "model"))
        print("STATUS      PENDING_VALIDATION - a responder must confirm before dispatch")
        print("-" * 72)

    return {
        "incident": {"user_selected": selected, "model_predicted": pred,
                     "model_confidence": round(conf, 3)},
        "verification": {"status": verification, "message": vmsg},
        "signals": {k: v for k, v in sig.items() if v is not None},
        "severity": {"level": level, "rule": rule, "reason": why},
        "routing": {"agencies": agencies,
                    "based_on": "user_selected" if selected else "model_predicted",
                    "status": "PENDING_VALIDATION"},
    }


SAMPLES = [
    ("Tabang! nagdidilaab an balay ha Brgy Naval, may tawo pa ha sulod!", "FIRE"),
    ("may nabangga nga duha ka motor didi ha kanto, may nasamdan", "VEHICULAR_ACCIDENT"),
    ("may away didi, may nagdurugo nga lalaki", "ACCIDENT"),
    ("grabe an baha ha amon, diri na kami makagawas", "NATURAL_HAZARD"),
    ("may lalaki nga nagkukuptan han iya dughan, luspad na", "MEDICAL"),
    ("tabang", None),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("text", nargs="?")
    ap.add_argument("--selected", help="category the user picked in the app")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--demo", action="store_true", help="run the built-in sample reports")
    ap.add_argument("--retrain", action="store_true")
    args = ap.parse_args()

    pipe = train_if_needed(args.retrain)
    aliases, terms = load_dict()

    if args.demo:
        for t, sel in SAMPLES:
            run(t, sel, pipe, aliases, terms)
            print()
        return

    if args.text:
        out = run(args.text, args.selected, pipe, aliases, terms, quiet=args.json)
        if args.json:
            print(json.dumps(out, indent=2, ensure_ascii=False))
        return

    print("Ziren — type a report and press Enter. Blank line or Ctrl+C to quit.")
    print("Tip: prefix with a category to simulate the dropdown, e.g.  CRIME: may away didi\n")
    while True:
        try:
            line = input("report> ").strip()
        except (EOFError, KeyboardInterrupt):
            print(); break
        if not line:
            break
        sel = None
        if ":" in line:
            head, rest = line.split(":", 1)
            if head.strip().upper() in AGENCY:
                sel, line = head.strip().upper(), rest.strip()
        run(line, sel, pipe, aliases, terms)
        print()


if __name__ == "__main__":
    main()
