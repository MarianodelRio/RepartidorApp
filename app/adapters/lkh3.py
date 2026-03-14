"""
Adaptador LKH3 — resuelve el TSP abierto via subprocess.
"""

import os
import shutil

from app.core.logging import get_logger

logger = get_logger(__name__)


def _find_lkh() -> str | None:
    """Devuelve la ruta al binario LKH3, o None si no está disponible."""
    p = shutil.which("LKH")
    if p:
        return p
    home_bin = os.path.expanduser("~/bin/LKH")
    if os.path.isfile(home_bin) and os.access(home_bin, os.X_OK):
        return home_bin
    return None


_LKH_BIN: str | None = _find_lkh()


def _solve_with_lkh(
    dur_matrix: list[list[int]],
    dist_matrix: list[list[int]],
) -> list[int] | None:
    """Resuelve TSP abierto con LKH3 vía subprocess.

    Devuelve lista de índices ordenados (incluyendo depósito en posición 0),
    o None si LKH no está disponible o falla.

    Usa el truco ATSP+nodo_fantasma para modelar el viaje abierto:
      cost(i → fantasma) = 0  →  cualquier nodo puede ser el último
      cost(fantasma → 0)  = 0  →  retorno gratuito al depósito
    """
    if _LKH_BIN is None:
        return None

    import subprocess
    import tempfile

    n = len(dur_matrix)
    BIG = 999_999
    n_ext = n + 1  # nodo fantasma = índice n

    mat = [[BIG] * n_ext for _ in range(n_ext)]
    for i in range(n):
        for j in range(n):
            mat[i][j] = dur_matrix[i][j]
    for i in range(n):
        mat[i][n] = 0     # cualquier nodo → fantasma = gratis
    mat[n][0] = 0         # fantasma → depósito = gratis

    try:
        tmpdir = tempfile.mkdtemp(prefix="lkh_")
        prob_file = os.path.join(tmpdir, "route.atsp")
        par_file  = os.path.join(tmpdir, "route.par")
        tour_file = os.path.join(tmpdir, "route.tour")

        with open(prob_file, "w") as f:
            f.write(f"NAME: route\nTYPE: ATSP\nDIMENSION: {n_ext}\n")
            f.write("EDGE_WEIGHT_TYPE: EXPLICIT\nEDGE_WEIGHT_FORMAT: FULL_MATRIX\n")
            f.write("EDGE_WEIGHT_SECTION\n")
            for row in mat:
                f.write(" ".join(map(str, row)) + "\n")
            f.write("EOF\n")

        with open(par_file, "w") as f:
            f.write(f"PROBLEM_FILE = {prob_file}\n")
            f.write(f"TOUR_FILE = {tour_file}\n")
            f.write("RUNS = 10\nSEED = 1\n")

        proc = subprocess.run(
            [_LKH_BIN, par_file],
            capture_output=True, text=True, timeout=60,
        )

        if proc.returncode != 0 or not os.path.exists(tour_file):
            logger.error("LKH3 falló (rc=%d)", proc.returncode)
            return None

        with open(tour_file) as f:
            tour_lines = f.read().strip().split("\n")

        tour: list[int] = []
        in_tour = False
        for line in tour_lines:
            s = line.strip()
            if s == "TOUR_SECTION":
                in_tour = True
                continue
            if in_tour:
                v = int(s)
                if v == -1:
                    break
                tour.append(v - 1)   # LKH usa índices 1-based → 0-based

        if 0 not in tour:
            logger.error("LKH3: depósito no encontrado en el tour")
            return None

        start = tour.index(0)
        ordered: list[int] = []
        for i in range(n_ext):
            node = tour[(start + i) % n_ext]
            if node == n:   # nodo fantasma → fin del recorrido
                break
            ordered.append(node)

        if len(ordered) != n:
            logger.error("LKH3 devolvió %d nodos, esperados %d", len(ordered), n)
            return None

        return ordered

    except Exception as e:
        logger.error("LKH3 excepción: %s", e)
        return None
