"""
validate_csv.py — Script 1: validar y geocodificar CSV de entrada.

Uso:
    python validate_csv.py data_input/prueba1_nuevo.csv [salida.csv]

Entrada:  CSV con columnas  cliente, direccion, ciudad [, nota] [, alias]
Salida:   CSV intermedio    direccion, alias, num_paquetes, paquetes_json, lat, lon, confidence
          (listo para optimize_csv.py)

Las paradas que no se puedan geocodificar se imprimen en stderr.
"""

import csv
import json
import sys
import textwrap
from pathlib import Path

import requests

# ── Configuración central ──────────────────────────────────────────────────────
BASE_URL = "http://localhost:8000"
VALIDATION_ENDPOINT = f"{BASE_URL}/api/validation/start"

INTERMEDIATE_FIELDS = ["direccion", "alias", "num_paquetes", "paquetes_json", "lat", "lon", "confidence"]


# ── Helpers ────────────────────────────────────────────────────────────────────

def _read_input_csv(path: str) -> list[dict]:
    """Lee el CSV de entrada y normaliza los nombres de columna."""
    rows = []
    with open(path, newline="", encoding="utf-8-sig") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            # Normalizar nombres de columna: strip + lowercase
            norm = {k.strip().lower(): (v or "").strip() for k, v in row.items()}
            rows.append({
                "cliente":   norm.get("cliente", ""),
                "direccion": norm.get("direccion", ""),
                "ciudad":    norm.get("ciudad", ""),
                "nota":      norm.get("nota", ""),
                "alias":     norm.get("alias", ""),
            })
    return rows


def _call_validation(rows: list[dict]) -> dict:
    """Llama a POST /api/validation/start y devuelve la respuesta JSON."""
    payload = {"rows": rows}
    resp = requests.post(VALIDATION_ENDPOINT, json=payload, timeout=120)
    resp.raise_for_status()
    return resp.json()


def _write_intermediate_csv(path: str, geocoded: list[dict]) -> None:
    """Escribe el CSV intermedio a partir de las paradas geocodificadas."""
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=INTERMEDIATE_FIELDS)
        writer.writeheader()
        for stop in geocoded:
            packages = stop.get("packages", [])
            writer.writerow({
                "direccion":    stop["address"],
                "alias":        stop.get("alias", ""),
                "num_paquetes": stop["package_count"],
                "paquetes_json": json.dumps(packages, ensure_ascii=False),
                "lat":          stop["lat"],
                "lon":          stop["lon"],
                "confidence":   stop.get("confidence", ""),
            })


# ── Main ───────────────────────────────────────────────────────────────────────

def main() -> None:
    if len(sys.argv) < 2:
        print(textwrap.dedent("""
            Uso: python validate_csv.py <input.csv> [output.csv]

            Ejemplo:
                python validate_csv.py data_input/prueba1_nuevo.csv validated.csv
        """).strip(), file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    if len(sys.argv) >= 3:
        output_path = sys.argv[2]
    else:
        stem = Path(input_path).stem
        output_path = f"{stem}_validated.csv"

    # 1. Leer CSV de entrada
    print(f"Leyendo {input_path} …")
    rows = _read_input_csv(input_path)
    if not rows:
        print("ERROR: CSV vacío o sin filas válidas.", file=sys.stderr)
        sys.exit(1)
    print(f"  {len(rows)} filas leídas.")

    # 2. Llamar al backend
    print(f"Llamando a {VALIDATION_ENDPOINT} …")
    try:
        result = _call_validation(rows)
    except requests.exceptions.ConnectionError:
        print(f"ERROR: No se pudo conectar al backend en {BASE_URL}. ¿Está arrancado?", file=sys.stderr)
        sys.exit(1)
    except requests.exceptions.HTTPError as e:
        print(f"ERROR HTTP: {e}", file=sys.stderr)
        sys.exit(1)

    geocoded = result.get("geocoded", [])
    failed   = result.get("failed", [])
    total    = result.get("total_packages", len(rows))
    unique   = result.get("unique_addresses", len(geocoded) + len(failed))

    print(f"  {total} paquetes totales, {unique} direcciones únicas.")
    print(f"  Geocodificadas: {len(geocoded)}  |  Fallidas: {len(failed)}")

    # 3. Mostrar paradas fallidas en stderr
    if failed:
        print("\n⚠  Paradas sin geocodificar (quedan fuera del CSV intermedio):", file=sys.stderr)
        for stop in failed:
            clients = ", ".join(stop.get("client_names", [])) or "—"
            print(f"   • {stop['address']}  (clientes: {clients})", file=sys.stderr)

    if not geocoded:
        print("ERROR: Ninguna parada se pudo geocodificar.", file=sys.stderr)
        sys.exit(1)

    # 4. Escribir CSV intermedio
    _write_intermediate_csv(output_path, geocoded)
    print(f"\nCSV intermedio escrito en: {output_path}  ({len(geocoded)} paradas)")


if __name__ == "__main__":
    main()
