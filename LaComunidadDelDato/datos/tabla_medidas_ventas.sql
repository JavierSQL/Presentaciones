-- Tabla de medidas para el modelo semántico (Spark SQL, celda %%sql con el Lakehouse adjunto)
-- Una fila, una columna. En el modelo: ocultar Dummy y poner ahí las medidas.
-- Probado en Fabric (2026-11-15): el Lakehouse acepta el nombre con guion bajo.
CREATE OR REPLACE TABLE Ferreteria.`_Ventas` AS
SELECT CAST(1 AS INT) AS Dummy;
