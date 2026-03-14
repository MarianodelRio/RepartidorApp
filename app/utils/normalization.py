"""Normalización de texto para direcciones."""

import re
import unicodedata


def normalize_text(text: str) -> str:
    """Normalización general: minúsculas, sin acentos, espacios simples.

    Preserva comas y puntos — no los elimina. Usada para fuzzy matching,
    cache keys y comparación de nombres de calle.
    """
    nfkd = unicodedata.normalize("NFKD", text.lower())
    no_acc = "".join(c for c in nfkd if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", no_acc).strip()


def normalize_for_dedup(addr: str) -> str:
    """Normaliza una dirección para detectar duplicados exactos.

    Elimina acentos, convierte a minúsculas y colapsa puntuación/espacios
    para que variantes de la misma dirección coincidan:
      'Calle Gaitán, 24' == 'CALLE GAITAN 24'
    """
    s = addr.strip().lower()
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    s = s.replace(",", " ").replace(".", " ")
    return " ".join(s.split())
