-- rot_antes.sql: el "lake" que ve el agente "antes" (Demo 1). ROT plantado a propósito.
-- Spark SQL, celdas %%sql con el Lakehouse adjunto (con schemas). Se puede volver a correr.
--
-- Va en el schema Ferreteria_Plata, separado de Ferreteria (el schema limpio del modelo "después").
-- Así el agente "antes" NO ve tiquete_motivo ni sublinea_rol: si los ve, la demo se cae.
-- Fuente: las tablas que genera nb_GeneradorCanastasFerreteria (Ferreteria.*). Datos 2025.
--
-- Lo que ve el agente (y lo que sabe la persona con contexto):
--   ventas              la buena. Líneas de factura 2025, bodega incluida, flete incluido.
--   ventas_final_v2     copia de Ana, congelada el 15-mar-2025. "final" suena definitivo.
--   fact_ventas         warehouse viejo, agregado por día, dejó de cargar el 30-jun-2025. Cara de oficial.
--   ventas_bkp_2023     backup 2023-2024 (los datos 2025 corridos 1 y 2 años). La más pesada.
--   articulo            el catálogo bueno (incluye SERV CORTE, críptico y sin describir).
--   articulo_v2         snapshot viejo: precios de 2024, sin los artículos nuevos.
--   catalogo_erp_viejo  ERP anterior: otra llave, sin sublínea y sin servicios (no hay SERV CORTE).
--   tmp_carga_tiquetes  staging de la carga del 31-dic: todo texto y con duplicados.
--   sucursal            sin Formato: la bodega está mezclada con las tiendas.
--   sales_summary       (inglés) resumen mensual de un consultor. "customers" = facturas, no clientes.
--   product_master      (inglés) catálogo "maestro" sin servicios: el corte tampoco existe aquí.
-- Las dos en inglés son para probar si el idioma de la pregunta cambia la tabla que escoge el agente.

CREATE SCHEMA IF NOT EXISTS Ferreteria_Plata;

-- 1. ventas: la buena (tal cual sale del POS, sin limpiar nada)
CREATE OR REPLACE TABLE Ferreteria_Plata.ventas AS
SELECT FacturaID, FacturaNumero, Proforma, Fecha, SucursalCodigo, ArticuloKey,
       Cantidad, PrecioUnitario, Monto, Condicion
FROM Ferreteria.fact_venta_linea;

-- 2. ventas_final_v2: copia congelada en marzo, mismas columnas menos Proforma
CREATE OR REPLACE TABLE Ferreteria_Plata.ventas_final_v2 AS
SELECT FacturaID, FacturaNumero, Fecha, SucursalCodigo, ArticuloKey,
       Cantidad, PrecioUnitario, Monto, Condicion
FROM Ferreteria.fact_venta_linea
WHERE Fecha <= DATE'2025-03-15';

-- 3. fact_ventas: el warehouse viejo. Agregado por día, en inglés, muerto desde julio.
--    Sin FacturaID: aquí no se puede saber qué iba en el mismo tiquete.
CREATE OR REPLACE TABLE Ferreteria_Plata.fact_ventas AS
SELECT CAST(date_format(Fecha, 'yyyyMMdd') AS INT) AS date_key,
       SucursalCodigo                              AS store_id,
       ArticuloKey                                 AS product_id,
       SUM(Cantidad)                               AS qty,
       CAST(SUM(Monto) AS DECIMAL(18,2))           AS sales_amount,
       COUNT(DISTINCT FacturaID)                   AS invoice_count
FROM Ferreteria.fact_venta_linea
WHERE Fecha <= DATE'2025-06-30'
GROUP BY Fecha, SucursalCodigo, ArticuloKey;

-- 4. ventas_bkp_2023: backup de dos años, la más pesada. El nombre la delata.
CREATE OR REPLACE TABLE Ferreteria_Plata.ventas_bkp_2023 AS
SELECT FacturaID + 10000000 * k                AS FacturaID,
       FacturaNumero, Proforma,
       add_months(Fecha, -12 * k)              AS Fecha,
       SucursalCodigo, ArticuloKey, Cantidad,
       ROUND(PrecioUnitario * (1 - 0.06 * k))  AS PrecioUnitario,
       ROUND(Monto * (1 - 0.06 * k))           AS Monto,
       Condicion
FROM Ferreteria.fact_venta_linea
CROSS JOIN (SELECT explode(array(1, 2)) AS k);

-- 5. articulo: el catálogo bueno
CREATE OR REPLACE TABLE Ferreteria_Plata.articulo AS
SELECT ArticuloKey, ArticuloCodigo, ArticuloNombre, Departamento, Linea, Sublinea,
       Tipo, PrecioLista, ClasificacionABC
FROM Ferreteria.dim_articulo;

-- 6. articulo_v2: snapshot viejo. Precios 8 % abajo y sin el último 10 % de artículos.
CREATE OR REPLACE TABLE Ferreteria_Plata.articulo_v2 AS
SELECT ArticuloKey, ArticuloCodigo, ArticuloNombre, Departamento, Linea, Sublinea,
       ROUND(PrecioLista * 0.92 / 50) * 50 AS PrecioLista,
       ClasificacionABC
FROM Ferreteria.dim_articulo
WHERE ArticuloKey <= (SELECT percentile_approx(ArticuloKey, 0.9) FROM Ferreteria.dim_articulo);

-- 7. catalogo_erp_viejo: otra llave (código), descripciones en mayúscula, familia = línea.
--    Sin servicios: el corte no existe en este catálogo.
CREATE OR REPLACE TABLE Ferreteria_Plata.catalogo_erp_viejo AS
SELECT ArticuloCodigo                    AS CODIGO,
       upper(ArticuloNombre)             AS DESCRIPCION,
       upper(Linea)                      AS FAMILIA,
       upper(Departamento)               AS DEPTO,
       CAST(PrecioLista * 0.85 AS INT)   AS PRECIO,
       'ACTIVO'                          AS ESTADO
FROM Ferreteria.dim_articulo
WHERE Tipo <> 'servicio';

-- 8. tmp_carga_tiquetes: staging de una carga, todo texto, con la carga repetida (duplicados)
CREATE OR REPLACE TABLE Ferreteria_Plata.tmp_carga_tiquetes AS
SELECT CAST(FacturaNumero AS STRING) AS num_factura,
       CAST(Fecha AS STRING)         AS fecha,
       SucursalCodigo                AS suc,
       CAST(ArticuloKey AS STRING)   AS art,
       CAST(Cantidad AS STRING)      AS cant,
       CAST(Monto AS STRING)         AS monto,
       CAST(intento AS STRING)       AS lote
FROM Ferreteria.fact_venta_linea
CROSS JOIN (SELECT explode(array(1, 2)) AS intento)
WHERE Fecha = DATE'2025-12-31';

-- 9. sucursal: sin Formato. La bodega queda como una sucursal más.
CREATE OR REPLACE TABLE Ferreteria_Plata.sucursal AS
SELECT SucursalCodigo, SucursalNombre, Provincia
FROM Ferreteria.dim_sucursal;

-- 10. sales_summary: resumen mensual que dejó un consultor para un Power BI viejo. 2025 completo.
--     La trampa es el nombre: "customers" cuenta facturas, no clientes (y la bodega parte
--     los pedidos grandes en varias facturas).
CREATE OR REPLACE TABLE Ferreteria_Plata.sales_summary AS
SELECT CAST(date_trunc('MONTH', Fecha) AS DATE)  AS month,
       SucursalCodigo                            AS store_id,
       ArticuloKey                               AS product_id,
       SUM(Cantidad)                             AS units,
       CAST(SUM(Monto) AS DECIMAL(18,2))         AS revenue,
       COUNT(DISTINCT FacturaID)                 AS customers
FROM Ferreteria.fact_venta_linea
GROUP BY date_trunc('MONTH', Fecha), SucursalCodigo, ArticuloKey;

-- 11. product_master: catálogo en inglés, valores en español, sin servicios.
--     "master" suena a fuente oficial; el corte no está.
CREATE OR REPLACE TABLE Ferreteria_Plata.product_master AS
SELECT ArticuloKey     AS product_id,
       ArticuloCodigo  AS sku,
       ArticuloNombre  AS description,
       Departamento    AS department,
       Linea           AS category,
       Sublinea        AS subcategory,
       PrecioLista     AS list_price
FROM Ferreteria.dim_articulo
WHERE Tipo <> 'servicio';

-- Revisión rápida: filas por tabla (ventas_bkp_2023 tiene que ser la más grande)
SELECT 'ventas' AS tabla, COUNT(*) AS filas FROM Ferreteria_Plata.ventas
UNION ALL SELECT 'ventas_final_v2',    COUNT(*) FROM Ferreteria_Plata.ventas_final_v2
UNION ALL SELECT 'fact_ventas',        COUNT(*) FROM Ferreteria_Plata.fact_ventas
UNION ALL SELECT 'ventas_bkp_2023',    COUNT(*) FROM Ferreteria_Plata.ventas_bkp_2023
UNION ALL SELECT 'articulo',           COUNT(*) FROM Ferreteria_Plata.articulo
UNION ALL SELECT 'articulo_v2',        COUNT(*) FROM Ferreteria_Plata.articulo_v2
UNION ALL SELECT 'catalogo_erp_viejo', COUNT(*) FROM Ferreteria_Plata.catalogo_erp_viejo
UNION ALL SELECT 'tmp_carga_tiquetes', COUNT(*) FROM Ferreteria_Plata.tmp_carga_tiquetes
UNION ALL SELECT 'sucursal',           COUNT(*) FROM Ferreteria_Plata.sucursal
UNION ALL SELECT 'sales_summary',      COUNT(*) FROM Ferreteria_Plata.sales_summary
UNION ALL SELECT 'product_master',     COUNT(*) FROM Ferreteria_Plata.product_master;
