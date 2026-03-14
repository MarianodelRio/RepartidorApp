"""
Posadas Route Planner — Backend FastAPI v2.3.0
==============================================
Arquitectura:
  core/config.py    → Configuración centralizada
  core/logging.py   → Logger compartido
  models/           → Modelos Pydantic (request/response)
  services/         → Lógica de negocio (geocoding, routing, catalog, map_editor)
  routers/          → Endpoints de la API
  utils/            → Helpers compartidos (normalización)

Servicios requeridos:
  OSRM → localhost:5000  (motor de rutas, Docker)
  LKH3 → binario local  (solver TSP)
"""

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.core.config import BASE_DIR
from app.routers import optimize, validation, system, map_editor
from osm_app.router import router as osm_router

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)

app = FastAPI(
    title="Posadas Route Planner",
    description="API de optimización de rutas de reparto para Posadas (Córdoba)",
    version="2.3.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

STATIC_DIR = BASE_DIR / "static"
STATIC_DIR.mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

app.include_router(system.router)
app.include_router(optimize.router,    prefix="/api")
app.include_router(validation.router,  prefix="/api")
app.include_router(map_editor.router,  prefix="/api")
app.include_router(osm_router)
