"""Normalización de texto para deduplicación de direcciones."""

import unicodedata


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
