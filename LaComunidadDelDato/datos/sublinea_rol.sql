-- sublinea_rol: el rol de cada sublínea (imán, acompañante, nicho, relleno) publicado como dato.
-- Spark SQL, celda %%sql con el Lakehouse adjunto. Requiere Ferreteria.tiquete_motivo (correr antes tiquete_motivo.sql)
-- y meta.business_rules (correr antes meta_business_rules.sql).
--
-- La regla vigente de motivo de visita (MOT-002) va pegada a cada fila: ReglaMotivo, DuenoRegla, ReglaVigenteDesde,
-- RazonRegla. Prueba C (2026-11-16): el agente resuelve en una sola consulta y nunca leyó la tabla de reglas suelta.
-- Pegada al dato, la misma consulta que trae los imanes trae quién lo decidió.
--
-- Por qué columna y no medida: el Data Agent ignora la medida de texto [Rol Sublínea] y agrega columnas
-- (unidades, tiquetes). Un atributo filtrable (RolTrafico = 'Imán') es más fácil de encontrar.
-- Misma lógica que las medidas del modelo: tráfico de mostrador, imán = penetración >= 1 % y motivo >= 80 %.
CREATE OR REPLACE TABLE Ferreteria.sublinea_rol AS
WITH presencia AS (            -- una fila por tiquete de mostrador y sublínea presente
  SELECT DISTINCT f.FacturaID, a.Sublinea
  FROM Ferreteria.fact_venta_linea f
  JOIN Ferreteria.dim_articulo a ON a.ArticuloKey = f.ArticuloKey
  JOIN Ferreteria.tiquete_motivo t ON t.FacturaID = f.FacturaID     -- solo mostrador
  WHERE a.Sublinea <> 'FLETE'
),
total AS (SELECT COUNT(*) AS N FROM Ferreteria.tiquete_motivo),
m AS (
  SELECT p.Sublinea,
         COUNT(*)                                                         AS Tiquetes,
         AVG(CASE WHEN t.MotivoConcilio = p.Sublinea THEN 1.0 ELSE 0 END) AS MotivoConcilio,
         AVG(CASE WHEN t.MotivoPorMonto = p.Sublinea THEN 1.0 ELSE 0 END) AS MotivoPorMonto,
         percentile_approx(t.MontoTiquete, 0.5)                           AS CanastaMediana
  FROM presencia p
  JOIN Ferreteria.tiquete_motivo t ON t.FacturaID = p.FacturaID
  GROUP BY p.Sublinea
)
-- Todas las sublíneas del catálogo tienen fila: las que no son tráfico de mostrador (FLETE) quedan
-- como 'No aplica'. Sin fila, el rol queda en blanco y el agente las coló como imanes (2026-11-15).
, sub AS (SELECT DISTINCT Sublinea FROM Ferreteria.dim_articulo)
SELECT
  sub.Sublinea,
  CASE WHEN m.Sublinea IS NULL THEN 'No aplica'
       WHEN m.Tiquetes / total.N >= 0.01 AND m.MotivoConcilio >= 0.8 THEN 'Imán'
       WHEN m.Tiquetes / total.N >= 0.01                             THEN 'Acompañante masivo'
       WHEN m.MotivoConcilio >= 0.8                                  THEN 'Destino de nicho'
       ELSE 'Relleno' END                                            AS RolTrafico,
  CASE WHEN m.Sublinea IS NULL THEN 'No aplica'
       WHEN m.Tiquetes / total.N >= 0.01 AND m.MotivoPorMonto >= 0.8 THEN 'Imán'
       WHEN m.Tiquetes / total.N >= 0.01                             THEN 'Acompañante masivo'
       WHEN m.MotivoPorMonto >= 0.8                                  THEN 'Destino de nicho'
       ELSE 'Relleno' END                                            AS RolTraficoPorMonto,
  COALESCE(m.Tiquetes / total.N >= 0.01 AND m.MotivoConcilio >= 0.8, FALSE) AS EsIman,
  CAST(m.Tiquetes / total.N AS DOUBLE)                               AS Penetracion,
  CAST(m.MotivoConcilio AS DOUBLE)                                   AS MotivoConcilio,
  CAST(m.MotivoPorMonto AS DOUBLE)                                   AS MotivoPorMonto,
  CAST(m.CanastaMediana AS DOUBLE)                                   AS CanastaMediana,
  r.RuleID                                                           AS ReglaMotivo,
  r.BusinessOwner                                                    AS DuenoRegla,
  r.EffectiveFrom                                                    AS ReglaVigenteDesde,
  r.ChangeReason                                                     AS RazonRegla
FROM sub
CROSS JOIN total
CROSS JOIN (SELECT RuleID, BusinessOwner, EffectiveFrom, ChangeReason
            FROM meta.business_rules
            WHERE RuleName = 'Motivo de visita' AND IsActive) r
LEFT JOIN m ON m.Sublinea = sub.Sublinea;
