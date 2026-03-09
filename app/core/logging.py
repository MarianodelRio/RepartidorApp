"""Logging centralizado del proyecto."""

import logging


def get_logger(name: str) -> logging.Logger:
    """Devuelve un logger estándar para el módulo dado."""
    return logging.getLogger(name)
