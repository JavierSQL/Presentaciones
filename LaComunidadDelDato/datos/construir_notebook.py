"""
Arma nb_GeneradorCanastasFerreteria.ipynb a partir de generar_canastas.py y analizar_canastas.py.
Una sola fuente de verdad: si cambia la lógica, se edita el .py y se vuelve a correr esto.
Uso:  python construir_notebook.py
"""
import json
import re
from pathlib import Path

AQUI = Path(__file__).parent


def cuerpo(py):
    """Código del módulo sin el docstring inicial ni el bloque __main__."""
    s = (AQUI / py).read_text(encoding="utf-8")
    s = re.sub(r'^""".*?"""\s*', "", s, count=1, flags=re.S)
    s = s.split('\nif __name__ == "__main__":')[0]
    return s.strip() + "\n"


def md(texto):
    return {"cell_type": "markdown", "metadata": {}, "source": texto.strip("\n").splitlines(keepends=True)}


def code(texto, tags=None):
    meta = {"tags": tags} if tags else {}
    return {"cell_type": "code", "metadata": meta, "execution_count": None, "outputs": [],
            "source": texto.strip("\n").splitlines(keepends=True)}


celdas = [
    md("""
# Generador de canastas: ferretería La Comunidad

Genera un año de tiquetes sintéticos de una ferretería ficticia y los escribe como **Delta tables** en el Lakehouse.
Es la demo de la charla *La Comunidad del Dato* (Comunidad de Data & AI Costa Rica, 2026-11-23).

Extiende el [generador de datos sintéticos](https://github.com/JavierSQL/GeneradorDatosSinteticos) con un tipo de
dataset nuevo, `baskets`: cada tiquete nace de una **misión** (el motivo del viaje) que arrastra acompañantes con
probabilidades. El YAML es el conocimiento del mostrador escrito como datos.

## Antes de correr

1. Lakehouse adjunto **con schemas habilitados**.
2. Subir `ferreteria_canastas.yml` a `Files/config/` del Lakehouse.
3. Runtime con PyYAML (viene en los runtimes de Fabric; si falta, la celda de imports lo dice).

## Qué escribe

| Tabla | Schema | Va al modelo semántico |
|---|---|---|
| `dim_sucursal` | `Ferreteria` | Sí (en el modelo "antes", sin `Formato`) |
| `dim_articulo` | `Ferreteria` | Sí |
| `fact_venta_linea` | `Ferreteria` | Sí |
| `validacion_mision` | `Ferreteria_Validacion` | **No**: es la verdad de terreno para validar |

Todo es ficticio: empresa, sucursales, artículos y precios.
"""),
    md("## Parámetros"),
    code("""
YAML_PATH = "/lakehouse/default/Files/config/ferreteria_canastas.yml"
TIQUETES = None                      # None = lo que diga el YAML (500 mil). Para una prueba rápida: 20000
SCHEMA = None                        # None = dataset.schema del YAML
SCHEMA_VALIDACION = "Ferreteria_Validacion"
""", tags=["parameters"]),
    code("""
try:
    import yaml  # noqa: F401
except ImportError:
    raise ImportError("Falta PyYAML: correr  %pip install pyyaml  en una celda y reiniciar la sesión")
"""),
    md("## Generador\n\nMisma lógica que `generar_canastas.py`."),
    code(cuerpo("generar_canastas.py")),
    md("## Validación\n\nMisma lógica que `analizar_canastas.py`: confirma que los patrones plantados aparecen."),
    code(cuerpo("analizar_canastas.py")),
    md("## Generar"),
    code("""
cfg = cargar_config(YAML_PATH)
tablas = generar(cfg, TIQUETES)
for nombre, df in tablas.items():
    print(f"{nombre}: {len(df):,} filas")
"""),
    code("validar(tablas)"),
    md("## Escribir Delta tables"),
    code("""
spark.conf.set("spark.sql.execution.arrow.pyspark.enabled", "true")

schema = SCHEMA or cfg["dataset"]["schema"]
for sch in {schema, SCHEMA_VALIDACION}:
    spark.sql(f"CREATE SCHEMA IF NOT EXISTS {sch}")

destinos = {"dim_sucursal": schema, "dim_articulo": schema,
            "fact_venta_linea": schema, "_validacion_mision": SCHEMA_VALIDACION}

for nombre, df in tablas.items():
    df = df.copy()
    for c in df.columns:                       # columnas de texto con nulos: tipo string explícito
        if df[c].dtype == object and c != "Fecha":
            df[c] = df[c].astype("string")
    tabla = f"{destinos[nombre]}.{nombre.lstrip('_')}"
    (spark.createDataFrame(df)
          .write.mode("overwrite").option("overwriteSchema", "true")
          .format("delta").saveAsTable(tabla))
    print(f"✓ {tabla}: {spark.table(tabla).count():,} filas")
"""),
    md("""
## Siguiente: modelo semántico

- **Modelo "antes"**: las tres tablas tal cual. Sin `Formato` en la sucursal, sin descripciones, sin rol de sublínea.
  `SERV CORTE` sin describir.
- **Modelo "después"**: `Formato` visible y descrito, rol de sublínea (imán, acompañante, nicho, relleno) con
  definición y owner, la regla *"si el tiquete trae un servicio, el servicio es el motivo"*, y sinónimos
  ("corte de melamina", "cortar tablero").

Detalle en `03 Demo/demo-imanes-ferreteria.md`.
"""),
]

nb = {
    "cells": celdas,
    "metadata": {
        "kernelspec": {"name": "synapse_pyspark", "display_name": "Synapse PySpark", "language": "Python"},
        "language_info": {"name": "python"},
    },
    "nbformat": 4,
    "nbformat_minor": 5,
}

salida = AQUI / "nb_GeneradorCanastasFerreteria.ipynb"
salida.write_text(json.dumps(nb, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"OK: {salida.name} ({len(celdas)} celdas)")
