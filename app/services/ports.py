"""
Contratos (Protocol) para los componentes intercambiables de routing.

MatrixProvider — calcula la matriz de duraciones/distancias entre coords.
RouteSolver    — ordena las paradas resolviendo el TSP.

Usar Protocol (structural typing) significa que cualquier callable con la
firma correcta satisface el contrato sin herencia ni registro explícito.
"""

from typing import Protocol


class MatrixProvider(Protocol):
    """Proveedor de matriz de distancias/duraciones entre coordenadas."""

    def __call__(
        self,
        coords: list[tuple[float, float]],
    ) -> tuple[list[list[int]], list[list[int]]] | None:
        """
        Args:
            coords: Lista de (lat, lon). Índice 0 = depósito.

        Returns:
            (dur_matrix, dist_matrix) como listas NxN de int, o None si falla.
        """
        ...


class RouteSolver(Protocol):
    """Solver TSP: recibe matrices de dur/dist y devuelve el orden de visita."""

    def __call__(
        self,
        dur_matrix: list[list[int]],
        dist_matrix: list[list[int]],
    ) -> list[int] | None:
        """
        Args:
            dur_matrix:  Matriz NxN de duraciones (segundos).
            dist_matrix: Matriz NxN de distancias (metros).

        Returns:
            Lista de índices ordenados (índice 0 = depósito siempre primero),
            o None si el solver falla.
        """
        ...
