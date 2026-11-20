"""
Valida que los datos sintéticos muestren los patrones plantados.

Métricas por sublínea (tráfico de mostrador: formato Tienda, sin pedidos grandes, sin flete):
  Pen        % de tiquetes que la llevan                         (el oro común)
  Sola       de los que la llevan, % en que fue lo único
  MotivoMonto  de los que la llevan, % en que fue sola o lo de mayor monto  (definición del análisis real)
  MotivoReal   de los que la llevan, % cuya misión fue ella      (verdad de terreno; en la vida real no se ve)
  Canasta    monto mediano del tiquete cuando está
  ABC        mejor clasificación ERP de sus artículos

Uso:  python analizar_canastas.py salida/
"""
import sys
from pathlib import Path

import pandas as pd

CLAVE = ["TORNILLOS GYPSUM", "CEMENTO GRIS", "ACRILICAS", "ANTICORROSIVOS", "PISO CERAMICO",
         "ACCESORIOS PVC", "SERV CORTE", "COPIA DE LLAVES", "TABLEROS MELAMINA"]


def cargar(d):
    d = Path(d)
    return {n: pd.read_csv(d / f"{n}.csv") for n in
            ["dim_sucursal", "dim_articulo", "fact_venta_linea", "_validacion_mision"]}


def tiquetes_mostrador(t):
    f = t["fact_venta_linea"].merge(t["dim_sucursal"], on="SucursalCodigo") \
                             .merge(t["dim_articulo"][["ArticuloKey", "Sublinea", "Tipo", "ClasificacionABC"]], on="ArticuloKey")
    f = f[(f["Formato"] == "Tienda") & (f["Proforma"].isna()) & (f["Sublinea"] != "FLETE") & (f["Monto"] > 0)]
    return f


def metricas(f, val):
    ts = f.groupby(["FacturaID", "Sublinea", "Tipo"], as_index=False)["Monto"].sum()
    n_sub = ts.groupby("FacturaID")["Sublinea"].transform("count")
    tot = ts.groupby("FacturaID")["Monto"].transform("sum")
    ts["Sola"] = n_sub == 1
    rank = ts.sort_values(["FacturaID", "Monto", "Sublinea"], ascending=[True, False, True]) \
             .groupby("FacturaID").cumcount()
    ts["Dominante"] = rank.reindex(ts.index) == 0
    ts["MontoTiquete"] = tot
    # Regla del Concilio: si el tiquete trae un servicio, el servicio es el motivo
    ts["EsServicio"] = ts["Tipo"] == "servicio"
    rank2 = ts.sort_values(["FacturaID", "EsServicio", "Monto", "Sublinea"], ascending=[True, False, False, True])               .groupby("FacturaID").cumcount()
    ts["DominanteRegla"] = rank2.reindex(ts.index) == 0
    ts = ts.merge(val[["FacturaID", "Mision"]], on="FacturaID")
    ts["EsMision"] = ts["Mision"] == ts["Sublinea"]
    N = ts["FacturaID"].nunique()
    g = ts.groupby("Sublinea")
    r = pd.DataFrame({
        "Tiquetes": g.size(),
        "Pen": 100 * g.size() / N,
        "Sola": 100 * g["Sola"].mean(),
        "MotivoMonto": 100 * g["Dominante"].mean(),   # sola => dominante
        "MotivoRegla": 100 * g["DominanteRegla"].mean(),
        "MotivoReal": 100 * g["EsMision"].mean(),
        "Canasta": g["MontoTiquete"].median(),
        "MontoTotal": g["Monto"].sum(),
    })
    r["RankPen"] = r["Pen"].rank(ascending=False).astype(int)
    r["RankMonto"] = r["MontoTotal"].rank(ascending=False).astype(int)
    # perfil (cortes: penetración 1 %, motivo 50 %) con las dos definiciones
    for col, nom in [("MotivoMonto", "PerfilMonto"), ("MotivoRegla", "PerfilRegla")]:
        r[nom] = [("Imán" if m >= 50 else "Acompañante") if p >= 1 else ("Nicho" if m >= 50 else "Relleno")
                  for p, m in zip(r["Pen"], r[col])]
    return r, N, ts


def validar(t):
    """t: dict con dim_sucursal, dim_articulo, fact_venta_linea, _validacion_mision (DataFrames de pandas)."""
    f = tiquetes_mostrador(t)
    r, N, ts = metricas(f, t["_validacion_mision"])
    abc = t["dim_articulo"].groupby("Sublinea")["ClasificacionABC"].min()
    r["ABC"] = abc
    canasta_global = ts.groupby("FacturaID")["MontoTiquete"].first().median()

    pd.set_option("display.width", 200)
    pd.set_option("display.max_columns", 20)
    print(f"Tiquetes de mostrador: {N:,}   canasta mediana global: {canasta_global:,.0f}\n")
    print("== Top 12 por penetración (el oro común) ==")
    print(r.sort_values("Pen", ascending=False).head(12)[
        ["RankPen", "RankMonto", "Pen", "Sola", "MotivoMonto", "MotivoReal", "Canasta", "ABC"]].round(1))
    print("\n== Sublíneas clave ==")
    print(r.loc[[c for c in CLAVE if c in r.index],
                ["RankPen", "Pen", "MotivoMonto", "MotivoRegla", "MotivoReal", "Canasta", "ABC",
                 "PerfilMonto", "PerfilRegla"]].round(1))
    print("\n== Imanes clasificados C en el ERP ==")
    for col in ["PerfilMonto", "PerfilRegla"]:
        print(f"  con {col}: {list(r[(r[col] == 'Imán') & (r['ABC'] == 'C')].index)}")

    # arrastre: en tiquetes cuya misión fue X, % que llevó Y
    print("\n== Arrastre (tiquetes con canasta) ==")
    multi = ts[ts.groupby("FacturaID")["Sublinea"].transform("count") > 1]
    for a, bs in {"SERV CORTE": ["TABLEROS MELAMINA", "CANTOS", "BISAGRAS", "TORNILLOS MELAMINA"],
                  "ACRILICAS": ["BROCHAS", "FELPAS Y RODILLOS"],
                  "PISO CERAMICO": ["PEGA PISOS"],
                  "ANTICORROSIVOS": ["SOLVENTES"]}.items():
        fa = set(multi.loc[multi["Sublinea"] == a, "FacturaID"])
        base = set(multi["FacturaID"]) - fa
        for b in bs:
            fb = set(multi.loc[multi["Sublinea"] == b, "FacturaID"])
            pa = 100 * len(fa & fb) / max(1, len(fa))
            pb = 100 * len(base & fb) / max(1, len(base))
            print(f"  {a:15s} -> {b:20s} {pa:5.1f} %  (resto {pb:4.1f} %, lift {pa / max(pb, 0.01):5.1f})")

    # vista ingenua del agente "antes": todas las sucursales, factura = tiquete
    fa = t["fact_venta_linea"].merge(t["dim_articulo"][["ArticuloKey", "Sublinea"]], on="ArticuloKey")
    nv = fa["FacturaID"].nunique()
    pen_naive = (fa.groupby("Sublinea")["FacturaID"].nunique() / nv * 100).sort_values(ascending=False)
    venta_naive = fa.groupby("Sublinea")["Monto"].sum().sort_values(ascending=False)
    print("\n== Vista ingenua (agente 'antes'): top 5 por facturas y por venta ==")
    print(pd.DataFrame({"PorFacturas": pen_naive.head(5).index, "PorVenta": venta_naive.head(5).index}))
    bod = t["fact_venta_linea"].merge(t["dim_sucursal"], on="SucursalCodigo")
    print(f"\nBodega: {100 * (bod['Formato'] == 'Bodega').mean():.1f} % de las líneas, "
          f"{100 * bod.loc[bod['Formato'] == 'Bodega', 'Monto'].sum() / bod['Monto'].sum():.1f} % del monto; "
          f"facturas con proforma: {100 * bod.drop_duplicates('FacturaID')['Proforma'].notna().mean():.1f} %")


if __name__ == "__main__":
    validar(cargar(sys.argv[1]))
