-- tiquete_motivo: el motivo de cada visita de mostrador, decidido una vez y publicado como dato.
-- Spark SQL, celda %%sql con el Lakehouse adjunto. Se vuelve a correr si se regeneran los datos.
--
-- Por qué tabla y no medida: calcular "lo de mayor monto en cada tiquete" en DAX sobre ~460 mil
-- tiquetes revienta el límite de memoria por consulta de la capacidad (1 GB). Además cuenta la
-- historia del Acto 3: la decisión del Concilio no queda en un documento, queda en el dato.
--
-- Una fila por tiquete de mostrador (formato Tienda, sin proforma, sin la línea de flete):
--   MotivoPorMonto   sublínea de mayor monto (o la única). Definición del análisis original.
--   MotivoConcilio   regla del Concilio: si el tiquete trae un servicio, el servicio es el motivo;
--                    si no, la de mayor monto. Empates: orden alfabético de la sublínea.
CREATE OR REPLACE TABLE Ferreteria.tiquete_motivo AS
WITH lineas AS (
  SELECT f.FacturaID, a.Sublinea, a.Tipo, SUM(f.Monto) AS Monto
  FROM Ferreteria.fact_venta_linea f
  JOIN Ferreteria.dim_sucursal s ON s.SucursalCodigo = f.SucursalCodigo
  JOIN Ferreteria.dim_articulo a ON a.ArticuloKey = f.ArticuloKey
  WHERE s.Formato = 'Tienda'
    AND f.Proforma IS NULL
    AND a.Sublinea <> 'FLETE'
  GROUP BY f.FacturaID, a.Sublinea, a.Tipo
),
orden AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY FacturaID ORDER BY Monto DESC, Sublinea) AS rk_monto,
    ROW_NUMBER() OVER (PARTITION BY FacturaID
                       ORDER BY CASE WHEN Tipo = 'servicio' THEN 0 ELSE 1 END, Monto DESC, Sublinea) AS rk_concilio
  FROM lineas
)
SELECT
  FacturaID,
  COUNT(*)                                          AS SublineasEnTiquete,
  CAST(SUM(Monto) AS DOUBLE)                        AS MontoTiquete,
  MAX(CASE WHEN rk_monto = 1    THEN Sublinea END)  AS MotivoPorMonto,
  MAX(CASE WHEN rk_concilio = 1 THEN Sublinea END)  AS MotivoConcilio,
  MAX(CASE WHEN Tipo = 'servicio' THEN 1 ELSE 0 END) = 1 AS TraeServicio
FROM orden
GROUP BY FacturaID;
