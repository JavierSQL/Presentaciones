"""
Generador de canastas por misión (tipo de dataset "baskets").

Lee ferreteria_canastas.yml y devuelve cuatro DataFrames de pandas:
  dim_sucursal, dim_articulo, fact_venta_linea, _validacion_mision

Núcleo del futuro notebook de Fabric: ahí solo cambia la escritura (Delta en vez de CSV).
Uso local:  python generar_canastas.py ferreteria_canastas.yml salida/ [tiquetes]
"""
import sys
from datetime import date, timedelta
from pathlib import Path

import numpy as np
import pandas as pd
import yaml


def cargar_config(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def construir_catalogo(cfg, rng):
    subs, arts = [], []
    art_key = 1
    for d in cfg["catalogo"]:
        for l in d["lineas"]:
            for s in l["sublineas"]:
                sub = {
                    "Departamento": d["departamento"],
                    "Linea": l["linea"],
                    "Sublinea": s["sublinea"],
                    "Tipo": s.get("tipo", "producto"),
                    "PrecioMin": s["precio"][0],
                    "PrecioMax": s["precio"][1],
                    "CantMin": s["cantidad"][0],
                    "CantMax": s["cantidad"][1],
                    "PesoMision": s.get("peso_mision", 0.0),
                    "PesoRelleno": s.get("peso_relleno", 0.0),
                    "Sola": s.get("sola", 0.4),
                }
                subs.append(sub)
                nombres = s.get("articulos", 5)
                if isinstance(nombres, int):
                    nombres = [f"{s['sublinea'].title()} {i:02d}" for i in range(1, nombres + 1)]
                # popularidad tipo Zipf dentro de la sublínea: el primer artículo es el más vendido
                pop = 1.0 / np.arange(1, len(nombres) + 1)
                pop = pop / pop.sum()
                for i, n in enumerate(nombres):
                    precio = rng.uniform(sub["PrecioMin"], sub["PrecioMax"])
                    precio = max(50, round(precio / 50) * 50)
                    arts.append({
                        "ArticuloKey": art_key,
                        "ArticuloCodigo": f"{d['departamento'][:3]}-{art_key:05d}",
                        "ArticuloNombre": n,
                        "Departamento": sub["Departamento"],
                        "Linea": sub["Linea"],
                        "Sublinea": sub["Sublinea"],
                        "Tipo": sub["Tipo"],
                        "PrecioLista": float(precio),
                        "_pop": pop[i],
                    })
                    art_key += 1
    return pd.DataFrame(subs), pd.DataFrame(arts)


def generar(cfg, tiquetes=None):
    ds = cfg["dataset"]
    rng = np.random.default_rng(ds.get("seed", 42))
    n_tiq = tiquetes or ds["tiquetes"]
    lpf = ds.get("lineas_por_factura", 20)

    subs, arts = construir_catalogo(cfg, rng)
    sub_idx = {s: i for i, s in enumerate(subs["Sublinea"])}

    # artículos por sublínea, con su popularidad
    arts_por_sub = {s: g for s, g in arts.groupby("Sublinea")}
    art_keys = {s: g["ArticuloKey"].to_numpy() for s, g in arts_por_sub.items()}
    art_pop = {s: (g["_pop"] / g["_pop"].sum()).to_numpy() for s, g in arts_por_sub.items()}
    art_precio = dict(zip(arts["ArticuloKey"], arts["PrecioLista"]))

    # sucursales
    suc = pd.DataFrame(cfg["sucursales"])
    suc_p = (suc["peso"] / suc["peso"].sum()).to_numpy()

    # fechas
    d0 = date.fromisoformat(ds["desde"])
    d1 = date.fromisoformat(ds["hasta"])
    dias = [d0 + timedelta(days=i) for i in range((d1 - d0).days + 1)]
    pdia = np.array([ds["peso_dia_semana"][d.weekday()] for d in dias], dtype=float)
    pdia /= pdia.sum()

    # misiones y relleno
    pm = subs["PesoMision"].to_numpy(dtype=float)
    pm = pm / pm.sum()
    pr = subs["PesoRelleno"].to_numpy(dtype=float)
    pr = pr / pr.sum()
    misiones = {m["motivo"]: m for m in cfg.get("misiones", [])}
    media_rel = cfg.get("relleno", {}).get("media_lineas", 1.0)
    flete = cfg.get("flete")

    pg = cfg.get("pedidos_grandes", {})
    pg_mask = subs["Departamento"].isin(pg.get("departamentos", [])).to_numpy()
    pg_w = (subs["PesoMision"] + subs["PesoRelleno"]).to_numpy(dtype=float) * pg_mask
    pg_w = pg_w / pg_w.sum()
    pg_mult = pg.get("cantidad_multiplicador", 1)

    lineas, valid = [], []
    factura_id = 0
    proforma_id = 0

    def linea_de(sub, mult=1):
        i = sub_idx[sub]
        ak = rng.choice(art_keys[sub], p=art_pop[sub])
        cant = int(rng.integers(subs.at[i, "CantMin"], subs.at[i, "CantMax"] + 1)) * mult
        return ak, cant

    suc_idx_all = rng.choice(len(suc), size=n_tiq, p=suc_p)
    dia_idx_all = rng.choice(len(dias), size=n_tiq, p=pdia)

    for t in range(n_tiq):
        s = suc.iloc[suc_idx_all[t]]
        fecha = dias[dia_idx_all[t]]
        cred_p = s.get("credito_prob", ds.get("credito_prob", 0.0))
        if pd.isna(cred_p):
            cred_p = ds.get("credito_prob", 0.0)
        condicion = "Credito" if rng.random() < cred_p else "Contado"
        es_grande = rng.random() < pg.get("prob_por_formato", {}).get(s["formato"], 0.0)

        items = []  # (sublinea, articulo, cantidad)
        if es_grande:
            n = int(rng.integers(pg["lineas"][0], pg["lineas"][1] + 1))
            n = min(n, int(pg_mask.sum()))
            elegidas = rng.choice(len(subs), size=n, replace=False, p=pg_w)
            for i in elegidas:
                sub = subs.at[i, "Sublinea"]
                ak, cant = linea_de(sub, pg_mult)
                items.append((sub, ak, cant))
            mision, variante = "PEDIDO GRANDE", None
        else:
            mi = rng.choice(len(subs), p=pm)
            mision = subs.at[mi, "Sublinea"]
            variante = None
            presentes = {mision}
            ak, cant = linea_de(mision)
            items.append((mision, ak, cant))
            if rng.random() >= subs.at[mi, "Sola"]:
                m = misiones.get(mision, {})
                extra = []
                if "variantes" in m:
                    vs = m["variantes"]
                    v = vs[rng.choice(len(vs), p=np.array([x["prob"] for x in vs]) / sum(x["prob"] for x in vs))]
                    variante = v["nombre"]
                    extra += v.get("agrega", [])
                extra += m.get("acompanantes", [])
                for a in extra:
                    if a["sublinea"] not in presentes and rng.random() < a["prob"]:
                        presentes.add(a["sublinea"])
                        ak, cant = linea_de(a["sublinea"])
                        items.append((a["sublinea"], ak, cant))
                k = rng.poisson(media_rel)
                if k:
                    cand = rng.choice(len(subs), size=k, replace=False, p=pr)
                    for i in cand:
                        sub = subs.at[i, "Sublinea"]
                        if sub not in presentes:
                            presentes.add(sub)
                            ak, cant = linea_de(sub)
                            items.append((sub, ak, cant))

        monto_tiq = sum(art_precio[ak] * c for _, ak, c in items)
        if flete and monto_tiq >= flete["monto_minimo"] and rng.random() < flete["prob"]:
            ak, cant = linea_de(flete["sublinea"])
            items.append((flete["sublinea"], ak, cant))

        # el POS parte la compra cada `lpf` líneas; las facturas comparten proforma
        partes = [items[i:i + lpf] for i in range(0, len(items), lpf)]
        proforma = None
        if len(partes) > 1:
            proforma_id += 1
            proforma = f"PF-{proforma_id:06d}"
        for parte in partes:
            factura_id += 1
            num = f"{s['codigo']}-{factura_id:07d}"
            for sub, ak, cant in parte:
                precio = art_precio[ak]
                lineas.append((factura_id, num, proforma, fecha, s["codigo"], ak, cant, precio, cant * precio, condicion))
            valid.append((factura_id, t + 1, mision, variante, es_grande))

    fact = pd.DataFrame(lineas, columns=["FacturaID", "FacturaNumero", "Proforma", "Fecha", "SucursalCodigo",
                                         "ArticuloKey", "Cantidad", "PrecioUnitario", "Monto", "Condicion"])
    val = pd.DataFrame(valid, columns=["FacturaID", "TiqueteOrigen", "Mision", "Variante", "EsPedidoGrande"])

    # ABC del ERP: Pareto por monto anual de artículo; servicios siempre C
    abc_cfg = cfg.get("abc", {})
    m = fact.groupby("ArticuloKey")["Monto"].sum().reindex(arts["ArticuloKey"], fill_value=0)
    orden = m.sort_values(ascending=False)
    acum = orden.cumsum() / orden.sum()
    abc = pd.Series(np.where(acum <= abc_cfg.get("corte_a", 0.8), "A",
                             np.where(acum <= abc_cfg.get("corte_b", 0.95), "B", "C")), index=orden.index)
    arts["ClasificacionABC"] = arts["ArticuloKey"].map(abc)
    arts.loc[arts["Tipo"] == "servicio", "ClasificacionABC"] = abc_cfg.get("servicios", "C")

    dim_suc = suc.rename(columns={"codigo": "SucursalCodigo", "nombre": "SucursalNombre",
                                  "provincia": "Provincia", "formato": "Formato"})[
        ["SucursalCodigo", "SucursalNombre", "Provincia", "Formato"]]
    dim_art = arts.drop(columns=["_pop"])
    return {"dim_sucursal": dim_suc, "dim_articulo": dim_art,
            "fact_venta_linea": fact, "_validacion_mision": val}


if __name__ == "__main__":
    cfg = cargar_config(sys.argv[1])
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    n = int(sys.argv[3]) if len(sys.argv) > 3 else None
    tablas = generar(cfg, n)
    for nombre, df in tablas.items():
        df.to_csv(out / f"{nombre}.csv", index=False, encoding="utf-8")
        print(f"{nombre}: {len(df):,} filas")
