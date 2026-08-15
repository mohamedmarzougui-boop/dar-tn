import re
import unicodedata

from tunisia_locations import TUNISIA_LOCATIONS

PROPERTY_TYPE_KEYWORDS = [
    ("colocation", "COLOCATION"),
    ("coloc", "COLOCATION"),
    ("studio", "STUDIO"),
    ("villa", "VILLA"),
    ("maison", "HOUSE"),
    ("house", "HOUSE"),
]

TARGET_TENANT_KEYWORDS = [
    ("filles", "GIRLS_ONLY"),
    ("girls", "GIRLS_ONLY"),
    ("garcons", "BOYS_ONLY"),
    ("boys", "BOYS_ONLY"),
    ("etudiant", "STUDENT"),
    ("student", "STUDENT"),
    ("famille", "FAMILY"),
    ("family", "FAMILY"),
]

AMENITY_KEYWORDS = {
    "has_climatisation": ["climatisation", "climatise", "clim "],
    "has_chauffage_central": ["chauffage central", "central heating"],
    "has_wifi": ["wifi", "wi-fi", "internet"],
    "has_elevator": ["ascenseur", "elevator"],
    "is_furnished": ["meuble", "furnished"],
}

# Matches "500 dt", "1 200dt", "750 DT/mois", "500tnd", "1.200 dinars" etc.
PRICE_PATTERN = re.compile(r"(\d[\d\s.,]{0,8}\d|\d)\s*(dt|tnd|dinars?)\b", re.IGNORECASE)

# S+1 .. S+4, tolerant of spacing ("S+1", "S +1", "s + 2").
PROPERTY_TYPE_SPLUS_PATTERN = re.compile(r"\bs\s*\+\s*([1-4])\b", re.IGNORECASE)

NEGATION_WORDS = ["non ", "sans ", "pas de ", "pas d'", "aucun", "aucune", "no ", "without "]


def _strip_accents(text: str) -> str:
    normalized = unicodedata.normalize("NFKD", text)
    return "".join(c for c in normalized if not unicodedata.combining(c))


def _normalize(text: str) -> str:
    return _strip_accents(text).lower()


def _extract_price(normalized_text: str) -> float | None:
    match = PRICE_PATTERN.search(normalized_text)
    if not match:
        return None
    digits = re.sub(r"[\s.,]", "", match.group(1))
    return float(digits) if digits else None


def _extract_property_type(normalized_text: str) -> str | None:
    # Check "colocation"/"coloc" before S+N: a post like "chambre dans une
    # colocation, S+3 meuble" is renting a single room, not the whole S+3
    # apartment, so COLOCATION is the accurate category even though an S+N
    # pattern also appears describing the underlying unit.
    for keyword, value in PROPERTY_TYPE_KEYWORDS:
        if keyword in normalized_text:
            return value
    splus_match = PROPERTY_TYPE_SPLUS_PATTERN.search(normalized_text)
    if splus_match:
        return f"S_PLUS_{splus_match.group(1)}"
    return None


def _extract_target_tenant(normalized_text: str) -> str | None:
    for keyword, value in TARGET_TENANT_KEYWORDS:
        if keyword in normalized_text:
            return value
    return None


def _keyword_present(normalized_text: str, keyword: str) -> bool:
    """Substring match that skips occurrences immediately preceded by a
    negation word (e.g. "non meuble", "sans clim") - a plain `in` check
    would confidently report an amenity the post explicitly says is absent."""
    start = 0
    while True:
        idx = normalized_text.find(keyword, start)
        if idx == -1:
            return False
        window = normalized_text[max(0, idx - 12):idx]
        if any(neg in window for neg in NEGATION_WORDS):
            start = idx + len(keyword)
            continue
        return True


def _extract_amenities(normalized_text: str) -> dict:
    return {
        field: any(_keyword_present(normalized_text, keyword) for keyword in keywords)
        for field, keywords in AMENITY_KEYWORDS.items()
    }


def _extract_location(normalized_text: str) -> tuple[str | None, str | None]:
    # Delegations are more specific than city/governorate names, so check
    # them first: a delegation match tells us the city with certainty,
    # whereas matching only on the city name is a weaker signal.
    for city, delegations in TUNISIA_LOCATIONS.items():
        for delegation in delegations:
            if _normalize(delegation) in normalized_text:
                return city, delegation
    for city in TUNISIA_LOCATIONS:
        if _normalize(city) in normalized_text:
            return city, None
    return None, None


def _extract_title(raw_text: str) -> str | None:
    for line in raw_text.splitlines():
        stripped = line.strip()
        if stripped:
            return stripped[:80]
    return None


def parse_listing_text(raw_text: str) -> dict:
    """Best-effort field extraction from an informally-written listing post
    (e.g. copy-pasted from a Facebook group). Returns None for anything not
    confidently matched - the caller is expected to have the user review and
    fill in the rest, never to auto-publish this without a human in the loop."""
    normalized_text = _normalize(raw_text)
    city, delegation = _extract_location(normalized_text)

    return {
        "title": _extract_title(raw_text),
        "description": raw_text.strip(),
        "price_tnd": _extract_price(normalized_text),
        "property_type": _extract_property_type(normalized_text),
        "target_tenant": _extract_target_tenant(normalized_text),
        "city": city,
        "delegation": delegation,
        **_extract_amenities(normalized_text),
    }
