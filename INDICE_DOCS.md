# 📚 Índice de Documentación — Repartidor App

> **Guía de navegación de toda la documentación del proyecto**

---

## 🎯 ¿Qué documento necesito?

### Para Usuarios (Operación diaria)

```
┌─────────────────────────────────────────────────────┐
│  "Quiero arrancar el sistema AHORA"                 │
│  → INICIO_RAPIDO.md (1 página, comandos básicos)   │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  "Prefiero entender cada paso manualmente"          │
│  → GUIA_INICIO.md (paso a paso con explicaciones)  │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  "Quiero usar el script automático"                 │
│  → README_SCRIPT.md (guía completa del script)     │
└─────────────────────────────────────────────────────┘
```

### Para Desarrolladores

```
┌─────────────────────────────────────────────────────┐
│  "Necesito la documentación técnica completa"       │
│  → DOCUMENTACION.md (arquitectura, API, código)    │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  "Visión general rápida del proyecto"               │
│  → README.md (punto de entrada principal)          │
└─────────────────────────────────────────────────────┘
```

---

## 📖 Detalle de cada documento

### 1. [README.md](README.md) — Punto de Entrada
📄 **Tamaño:** ~10 KB  
⏱️ **Lectura:** 5 minutos  
🎯 **Para quién:** Todos (primera lectura)

**Contiene:**
- Descripción del proyecto
- Arquitectura visual
- Stack tecnológico
- Enlaces a otros documentos
- Comandos rápidos de verificación
- Troubleshooting básico

**Cuándo leerlo:**
- Primera vez que abres el proyecto
- Quieres una visión general
- No sabes por dónde empezar

---

### 2. [INICIO_RAPIDO.md](INICIO_RAPIDO.md) — Cheat Sheet
📄 **Tamaño:** ~4 KB  
⏱️ **Lectura:** 2 minutos  
🎯 **Para quién:** Operadores, usuarios diarios

**Contiene:**
- Comando único de inicio
- URLs de todos los servicios
- Verificación en un comando
- Troubleshooting express (tabla)
- Workflow diario

**Cuándo leerlo:**
- Todos los días antes de trabajar
- Necesitas arrancar rápido
- Ya conoces el sistema

**Ideal para:**
- Tener abierto en una pestaña
- Imprimir y pegar en la pared
- Consulta rápida

---

### 3. [GUIA_INICIO.md](GUIA_INICIO.md) — Manual Paso a Paso
📄 **Tamaño:** ~6 KB  
⏱️ **Lectura:** 10 minutos  
🎯 **Para quién:** Primera instalación, aprendizaje

**Contiene:**
- Requisitos previos detallados
- Comandos manuales explicados
- Verificación de cada servicio
- Tabla de puertos
- Troubleshooting con soluciones

**Cuándo leerlo:**
- Primera vez que instalas el sistema
- Quieres entender cada comando
- Prefieres control manual
- El script automático falla

**Incluye explicaciones de:**
- Por qué se ejecuta cada comando
- Qué hace cada servicio
- Cómo verificar que funciona
- Qué hacer si falla

---

### 4. [README_SCRIPT.md](README_SCRIPT.md) — Guía del Script
📄 **Tamaño:** ~13 KB  
⏱️ **Lectura:** 15 minutos  
🎯 **Para quién:** Usuarios del script `start.sh`

**Contiene:**
- Qué hace el script internamente
- Todos los comandos disponibles
- Salida visual explicada
- Health checks automáticos
- Características avanzadas
- Troubleshooting específico del script
- Flujo de trabajo recomendado

**Cuándo leerlo:**
- Vas a usar `./start.sh` regularmente
- Quieres personalizar el script
- El script da errores
- Necesitas entender los timeouts

**Secciones destacadas:**
- Detección inteligente de servicios
- Logs persistentes
- Ejecución en segundo plano
- Limpieza manual si falla

---

### 5. [DOCUMENTACION.md](DOCUMENTACION.md) — Biblia Técnica
📄 **Tamaño:** ~95 KB (2135 líneas)  
⏱️ **Lectura:** 1-2 horas  
🎯 **Para quién:** Desarrolladores, arquitectos, mantenimiento

**Contiene:**
- Visión general del proyecto
- Arquitectura completa con diagramas
- Stack tecnológico detallado
- Estructura de archivos explicada
- Backend: cada archivo, función y modelo
- Flutter: pantallas, widgets, servicios
- Servicios Docker (OSRM, VROOM)
- Flujo de datos completo
- API: todos los endpoints con ejemplos
- Guía de desarrollo y modificaciones
- Problemas conocidos y soluciones
- Glosario técnico
- Generación de APK paso a paso
- Changelog completo

**Cuándo leerlo:**
- Vas a modificar código
- Necesitas añadir features
- Debugging avanzado
- Onboarding de nuevo desarrollador
- Arquitectura del sistema
- Cambiar zona geográfica

**Índice interno (14 secciones):**
1. Visión General
2. Arquitectura
3. Tecnologías
4. Estructura de Archivos
5. Backend
6. Servicios Docker
7. Flutter App
8. Flujo de Datos
9. API
10. Instalación
11. Desarrollo
12. Troubleshooting
13. Glosario
14. APK y Despliegue

---

### 6. [start.sh](start.sh) — Script de Inicio
📄 **Tamaño:** ~15 KB  
💻 **Tipo:** Bash script ejecutable  
🎯 **Para quién:** Todos (herramienta principal)

**Funciones:**
- `start` — Inicia todos los servicios con verificación
- `stop` — Detiene todo de forma limpia
- `restart` — Reinicia (útil tras cambios)
- `status` — Muestra estado actual

**Características:**
- ✅ Verifica requisitos previos
- ✅ Health checks automáticos
- ✅ Timeouts configurables
- ✅ Detección de servicios corriendo
- ✅ Salida con colores y emojis
- ✅ Captura URL de ngrok
- ✅ Logs persistentes
- ✅ Limpieza segura al detener

**Uso:**
```bash
./start.sh          # Iniciar
./start.sh status   # Ver estado
./start.sh stop     # Detener
./start.sh restart  # Reiniciar
```

---

## 🗺️ Mapa de Lectura Recomendado

### 🟢 Primera Vez (Día 1)
```
1. README.md           (5 min)  → Visión general
2. INICIO_RAPIDO.md    (2 min)  → Arrancar el sistema
3. README_SCRIPT.md    (15 min) → Entender el script
```

### 🔵 Uso Diario (Día 2+)
```
→ INICIO_RAPIDO.md (consulta)
→ ./start.sh (ejecutar)
```

### 🟣 Desarrollo/Modificación
```
1. DOCUMENTACION.md (secciones 1-4) → Arquitectura
2. DOCUMENTACION.md (sección 11)     → Desarrollo
3. Modificar código
4. ./start.sh restart
```

### 🟠 Troubleshooting
```
1. INICIO_RAPIDO.md (tabla troubleshooting)
2. ./start.sh status
3. GUIA_INICIO.md (sección troubleshooting)
4. DOCUMENTACION.md (sección 12)
```

---

## 📊 Comparación Rápida

| Documento | Páginas | Tiempo | Público | Propósito |
|-----------|---------|--------|---------|-----------|
| **README.md** | 2 | 5 min | Todos | Intro + enlaces |
| **INICIO_RAPIDO.md** | 1 | 2 min | Operadores | Cheat sheet |
| **GUIA_INICIO.md** | 3 | 10 min | Nuevos usuarios | Tutorial manual |
| **README_SCRIPT.md** | 6 | 15 min | Usuarios script | Guía script |
| **DOCUMENTACION.md** | 50+ | 1-2 h | Desarrolladores | Biblia técnica |
| **start.sh** | — | — | Todos | Herramienta |

---

## 🎯 Búsqueda por Tema

### Quiero saber cómo...

| Tema | Documento | Sección |
|------|-----------|---------|
| **Arrancar el sistema** | INICIO_RAPIDO.md | Comando Único |
| **Detener servicios** | INICIO_RAPIDO.md | Detener Todo |
| **Ver logs** | README_SCRIPT.md | Logs Persistentes |
| **Verificar estado** | GUIA_INICIO.md | Verificación |
| **Entender la arquitectura** | DOCUMENTACION.md | § 2 Arquitectura |
| **Modificar backend** | DOCUMENTACION.md | § 11 Desarrollo |
| **Cambiar colores app** | DOCUMENTACION.md | § 7.3.1 app_theme |
| **Generar APK** | DOCUMENTACION.md | § 14 APK |
| **Resolver error Docker** | GUIA_INICIO.md | Troubleshooting |
| **Personalizar script** | README_SCRIPT.md | Características Avanzadas |
| **API endpoints** | DOCUMENTACION.md | § 9 API |
| **Añadir pantalla Flutter** | DOCUMENTACION.md | § 11 Desarrollo |

---

## 🔍 Búsqueda por Problema

| Problema | Solución en |
|----------|-------------|
| Puerto 8000 ocupado | INICIO_RAPIDO.md → Troubleshooting |
| Backend no responde | GUIA_INICIO.md → Verificación Completa |
| Script da timeout | README_SCRIPT.md → Troubleshooting |
| App muestra Offline | README.md → Troubleshooting |
| Docker no arranca | GUIA_INICIO.md → Troubleshooting |
| ngrok sin URL | README_SCRIPT.md → ngrok no muestra URL |
| Error geocodificación | DOCUMENTACION.md § 12 |
| APK no instala | DOCUMENTACION.md § 14.8 |

---

## 📝 Historial de Versiones de Docs

| Versión | Fecha | Cambios |
|---------|-------|---------|
| 3.0.0 | Feb 2026 | Reorganización completa, nuevo script, índice |
| 2.9.0 | Feb 2026 | Actualización paleta colores |
| 2.8.0 | Feb 2026 | ngrok zero-config |
| 2.0.0 | 2025 | Versión inicial |

---

## 🎨 Convenciones de Formato

### Emojis usados en la documentación

| Emoji | Significado |
|-------|-------------|
| ⚡ | Acción rápida / inicio rápido |
| 🚀 | Script / automatización |
| 📋 | Lista / checklist |
| 🎯 | Objetivo / propósito |
| 🔧 | Configuración / tools |
| 🐛 | Bug / troubleshooting |
| ✅ | Completado / verificado |
| ❌ | Error / fallo |
| ⚠️ | Advertencia |
| 💡 | Tip / consejo |
| 📚 | Documentación |
| 🗺️ | Mapa / arquitectura |

### Bloques de código

```bash
# Comentario explicativo
comando --flag valor
```

### Estructura de troubleshooting

```
Problema: Descripción clara del síntoma
Causa: Por qué ocurre
Solución: Comandos específicos para resolver
```

---

## 🆘 Ayuda Adicional

Si después de leer toda la documentación sigues teniendo problemas:

1. ✅ Ejecuta: `./start.sh status` → captura salida
2. ✅ Revisa logs:
   ```bash
   tail -100 backend.log
   docker logs osrm-posadas --tail 50
   tail -100 /tmp/ngrok.log
   ```
3. ✅ Verifica requisitos: `./start.sh` (sin args) → ve errores de requisitos

---

*Documentación v3.0.0 — Última actualización: Febrero 2026*
