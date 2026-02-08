"""
Price extraction logic for PSP classifieds.

Extracts selling prices from post subjects and bodies,
handling cases where retail/original prices are also mentioned.
"""

import re


def _parse_price_value(price_str: str) -> float | None:
    """Extract numeric value from a price string for comparison."""
    match = re.search(r"[\d,]+(?:\.\d{2})?", price_str)
    if match:
        return float(match.group(0).replace(",", ""))
    return None


def _find_dollar_prices(text: str) -> list[str]:
    """Find all $X prices in text."""
    # Match $X but don't include trailing commas (stop at comma not followed by digit)
    return re.findall(r"\$\d+(?:,\d{3})*(?:\.\d{2})?", text)


def extract_price(subject: str | None, body: str | None) -> str | None:
    """
    Extract the selling price from subject or body.

    Strategy:
    1. Subject takes priority - if it has a price, return it
    2. Look for explicit "asking/selling" patterns in body
    3. Smart fallback: if 1-2 prices, return the lower one; if 3+, bail out

    Matches patterns like:
    - $40, $40.00, $1,000
    - asking $50, asking 50
    - selling for $50
    - 50 dollars, 40 obo
    """
    # 1. Check subject first - it's almost always the selling price
    if subject:
        subject_prices = _find_dollar_prices(subject)
        if subject_prices:
            return subject_prices[0]
        # Also check for other patterns in subject
        for pattern in [r"asking\s*\$?[\d,]+", r"[\d,]+\s*(?:dollars|obo)"]:
            match = re.search(pattern, subject, re.IGNORECASE)
            if match:
                return match.group(0)

    if not body:
        return None

    # 2. Look for explicit selling intent patterns in body
    selling_patterns = [
        r"asking\s*\$?\d+(?:,\d{3})*(?:\.\d{2})?",  # asking $50, asking 50
        r"selling\s+(?:for\s+)?\$?\d+(?:,\d{3})*(?:\.\d{2})?",  # selling for $50
        r"hoping\s+(?:for\s+)?\$?\d+(?:,\d{3})*(?:\.\d{2})?",  # hoping for $200
        r"\$\d+(?:,\d{3})*(?:\.\d{2})?\s*obo",  # $50 OBO
        r"\$\d+(?:,\d{3})*(?:\.\d{2})?\s*per\s+(?:night|evening|day|week|month|hour)",  # $349 per night
    ]

    for pattern in selling_patterns:
        match = re.search(pattern, body, re.IGNORECASE)
        if match:
            return match.group(0)

    # 3. Smart fallback based on number of prices
    body_prices = _find_dollar_prices(body)

    if len(body_prices) == 0:
        # Check for other formats (dollars, obo without $)
        match = re.search(r"[\d,]+\s*(?:dollars|obo)", body, re.IGNORECASE)
        if match:
            return match.group(0)
        return None

    if len(body_prices) == 1:
        return body_prices[0]

    if len(body_prices) == 2:
        # Return the lower price (selling price < retail price)
        price_values = [(p, _parse_price_value(p)) for p in body_prices]
        price_values = [(p, v) for p, v in price_values if v is not None]
        if price_values:
            return min(price_values, key=lambda x: x[1])[0]

    # 3+ prices: too ambiguous, bail out
    return None
