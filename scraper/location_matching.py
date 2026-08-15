"""Matches free-typed city/delegation text against Tunisia's canonical
governorate/delegation dataset, accent- and case-insensitively. Shared by
pipeline.py (CSV import) and tayara_scraper.py (live scraper) - both need
the exact same normalization, so it lives here once rather than duplicated
in each script."""

import unicodedata

from tunisia_locations import TUNISIA_LOCATIONS


def normalize(text):
    stripped = unicodedata.normalize("NFKD", text)
    return "".join(c for c in stripped if not unicodedata.combining(c)).strip().lower()


_CITY_LOOKUP = {normalize(city): city for city in TUNISIA_LOCATIONS}
_DELEGATION_LOOKUP = {
    city: {normalize(delegation): delegation for delegation in delegations}
    for city, delegations in TUNISIA_LOCATIONS.items()
}


def resolve_location(city_input, delegation_input):
    """Returns (canonical_city, canonical_delegation, errors). The canonical
    (properly accented) names are what should get stored, so data stays
    consistent with what the app's own dropdowns produce."""
    errors = []
    city = _CITY_LOOKUP.get(normalize(city_input))
    if not city:
        errors.append(f"city '{city_input}' is not a recognized Tunisian governorate")
        return None, None, errors

    delegation = None
    if delegation_input:
        delegation = _DELEGATION_LOOKUP[city].get(normalize(delegation_input))
        if not delegation:
            errors.append(f"delegation '{delegation_input}' is not a delegation of '{city}'")

    return city, delegation, errors
