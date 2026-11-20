-- dim_fecha para el modelo de la ferretería (Spark SQL, correr en una celda %%sql del Lakehouse)
-- Tabla Delta física (Direct Lake). Rango: años completos que cubre Ferreteria.fact_venta_linea.
-- Nombres en español, semana de lunes a domingo. Se puede volver a correr si se regeneran los datos.
CREATE OR REPLACE TABLE Ferreteria.dim_fecha AS
WITH rango AS (
  SELECT make_date(year(min(Fecha)), 1, 1)   AS desde,
         make_date(year(max(Fecha)), 12, 31) AS hasta
  FROM Ferreteria.fact_venta_linea
),
dias AS (
  SELECT explode(sequence(desde, hasta, INTERVAL 1 DAY)) AS Fecha FROM rango
)
SELECT
  Fecha,
  CAST(date_format(Fecha, 'yyyyMMdd') AS INT)                         AS FechaKey,
  year(Fecha)                                                         AS Anio,
  quarter(Fecha)                                                      AS Trimestre,
  concat('T', quarter(Fecha))                                         AS TrimestreNombre,
  month(Fecha)                                                        AS MesNumero,
  element_at(array('Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio',
                   'Agosto','Setiembre','Octubre','Noviembre','Diciembre'), month(Fecha)) AS MesNombre,
  element_at(array('Ene','Feb','Mar','Abr','May','Jun','Jul',
                   'Ago','Set','Oct','Nov','Dic'), month(Fecha))      AS MesCorto,
  year(Fecha) * 100 + month(Fecha)                                    AS AnioMesNumero,
  concat(element_at(array('Ene','Feb','Mar','Abr','May','Jun','Jul',
                          'Ago','Set','Oct','Nov','Dic'), month(Fecha)), ' ', year(Fecha)) AS AnioMes,
  day(Fecha)                                                          AS DiaMes,
  dayofyear(Fecha)                                                    AS DiaAnio,
  weekofyear(Fecha)                                                   AS SemanaISO,
  date_sub(Fecha, weekday(Fecha))                                     AS InicioSemana,      -- lunes
  weekday(Fecha) + 1                                                  AS DiaSemanaNumero,   -- 1 = lunes … 7 = domingo
  element_at(array('Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'),
             weekday(Fecha) + 1)                                      AS DiaSemanaNombre,
  element_at(array('Lun','Mar','Mié','Jue','Vie','Sáb','Dom'), weekday(Fecha) + 1) AS DiaSemanaCorto,
  weekday(Fecha) >= 5                                                 AS EsFinDeSemana
FROM dias
ORDER BY Fecha;
