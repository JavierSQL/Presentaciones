# La Comunidad del Dato

*Arquitectura de datos como ventaja competitiva: ingeniería, gobierno e IA en Microsoft Fabric*

Comunidad de Data & AI Costa Rica, 23 de noviembre de 2026. Javier Loria, Primus Data.

Hoy tu competencia usa el mismo modelo que vos. Lo que no tiene son tus datos. Pero un agente no los aprovecha si están acumulados sin decidir qué significan: ingeniería sin gobierno acumula, gobierno sin ingeniería escribe documentos, e IA sin las dos contesta con total seguridad algo equivocado. Hace falta una comunidad.

La charla sigue una sola pregunta de una ferretería ficticia, *¿qué productos atraen clientes a la tienda?*, con tres Fabric Data Agents:

1. **Sobre el lake**, con tablas viejas, copias y respaldos: contesta tornillos, desde una tabla muerta.
2. **Sobre cuatro tablas gobernadas**: escoge bien las tablas y sigue contestando tornillos.
3. **Sobre un modelo semántico** donde alguien decidió qué significa «atraer»: aparece el servicio de corte, que el ERP clasifica como C.

## Qué hay en esta carpeta

| Archivo | Qué es |
|---|---|
| `LaComunidadDelDato.pdf` | El deck |
| `datos/ferreteria_canastas.yml` | La ferretería descrita en YAML: sucursales, catálogo, misiones de compra y precios. Los patrones están plantados a propósito |
| `datos/nb_GeneradorCanastasFerreteria.ipynb` | Notebook de Fabric que lee el YAML y escribe un año de tiquetes como Delta tables |
| `datos/generar_canastas.py`, `analizar_canastas.py` | La lógica del notebook, para correr y validar en local |
| `datos/construir_notebook.py` | Arma el notebook a partir de los dos `.py` |
| `datos/*.sql` | Spark SQL para el resto del modelo (ver el orden abajo) |

Los datos son **sintéticos**: los patrones se inspiran en un análisis real de retail, pero ninguna cifra es real.

## Cómo armar la demo

1. En un Lakehouse de Fabric (con schemas), subí `ferreteria_canastas.yml` a `Files/config/`.
2. Importá el notebook y corrélo. Crea `Ferreteria.dim_sucursal`, `Ferreteria.dim_articulo` y `Ferreteria.fact_venta_linea` (500 mil tiquetes; para una prueba rápida, poné `TIQUETES = 20000`).
3. Corré los scripts en celdas `%%sql`, en este orden:
   - `dim_fecha.sql`: el calendario.
   - `tabla_medidas_ventas.sql`: la tabla vacía donde viven las medidas del modelo semántico.
   - `tiquete_motivo.sql`: el motivo de cada visita, decidido una vez y guardado como dato.
   - `meta_business_rules.sql`: las reglas de negocio con dueño, vigencia y razón del cambio.
   - `sublinea_rol.sql`: el rol de cada sublínea (imán, acompañante, nicho, relleno). Necesita los dos anteriores.
   - `rot_antes.sql`: el lake «de antes», con el ROT plantado (`ventas_final_v2`, `fact_ventas`…), en un schema aparte.

El notebook extiende el [generador de datos sintéticos](https://github.com/JavierSQL/GeneradorDatosSinteticos) con un tipo de dataset nuevo, `baskets`: canastas armadas por misión de compra. Cambiá el YAML y tenés la demo de tu propia industria, con datos que hablan tu idioma.

## Para seguir

- [El lector cambió](https://www.primusdata.net/2026/10/15/el-lector-cambio/)
- Serie *Trust Erosion*, en español: empieza en [Falso consenso semántico](https://www.primusdata.net/2026/07/21/falso-consenso-semantico/)
- Serie *¿Quién lo decidió?*: [El ROT pesa](https://www.primusdata.net/2026/10/19/el-rot-pesa/) · [El agente elige](https://www.primusdata.net/2026/10/27/el-agente-elige/) · [Escrito para otro](https://www.primusdata.net/2026/11/02/escrito-para-otro/)
- [linkedin.com/in/javiersql](https://www.linkedin.com/in/javiersql/)

#ModelosComunitariosDemos
