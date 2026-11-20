-- meta_business_rules: las reglas de negocio con dueño, vigencia y razón del cambio (Bloque 3, slide 3.6 y Demo 3).
-- Spark SQL, celdas %%sql con el Lakehouse adjunto (con schemas). Se puede volver a correr.
--
-- Para qué sirve en la charla:
--   3.6     La sala se divide (¿tablero o corte?). La ferretería también se dividió, y por eso existe esta tabla.
--           MOT-001 es la regla vieja: nadie la decidió, venía del reporte ABC por monto (BusinessOwner NULL).
--           MOT-002 es la vigente, con dueño, fecha y razón. Es la respuesta a "¿Quién lo decidió?".
--   Demo 3  Prueba C: la tabla entra al modelo FerreteriaComunidad y el agente contesta
--           "¿Quién decidió que el corte es un imán y por qué?" sin tocar sus instrucciones.
--
-- La lógica de cada regla es la que ya implementan tiquete_motivo.sql y sublinea_rol.sql.
-- Columnas recortadas a propósito: nada de LoadDate ni RecordSource (metadatos de carga, no le dicen nada a la sala).
-- El agente "antes" no la ve: solo ve el schema Ferreteria_Plata.

CREATE SCHEMA IF NOT EXISTS meta;

CREATE OR REPLACE TABLE meta.business_rules (
  RuleID          STRING  NOT NULL,
  RuleName        STRING  NOT NULL,
  RuleDescription STRING,
  RuleLogic       STRING,
  BusinessOwner   STRING,          -- NULL = nadie la decidió
  EffectiveFrom   DATE    NOT NULL,
  EffectiveTo     DATE,            -- NULL = vigente
  IsActive        BOOLEAN NOT NULL,
  ChangeReason    STRING
);

INSERT INTO meta.business_rules VALUES
('MOT-001', 'Motivo de visita',
 'Por qué vino el cliente a la tienda. Versión original.',
 'El artículo de mayor monto del tiquete es el motivo de la visita.',
 NULL,
 DATE'2024-01-01', DATE'2025-12-31', FALSE,
 'Nadie la decidió: era el criterio implícito del reporte ABC por monto. Con esta regla el servicio de corte sale clase C y se propuso cerrarlo.'),

('MOT-002', 'Motivo de visita',
 'Por qué vino el cliente a la tienda. Versión vigente.',
 'Si el tiquete trae un servicio (por ejemplo, el corte de melamina), el servicio es el motivo de la visita. Si no trae servicio, el motivo es el artículo de mayor monto.',
 'Concilio de tienda: Gerencia de tienda y Jefatura de taller',
 DATE'2026-01-01', NULL, TRUE,
 'Revisión de 2025: el dependiente del taller dice que la gente viene a cortar, y el tablero lo compra porque ya está aquí. Antes de cerrar el corte por ser clase C, se cambió la regla.'),

('IMA-001', 'Imán de tráfico',
 'Qué sublínea atrae clientes a la tienda (rol "Imán" en Rol Trafico).',
 'Aparece en al menos el 1 % de los tiquetes de mostrador y es el motivo de la visita en al menos el 80 % de los tiquetes donde aparece (según la regla MOT vigente).',
 'Gerencia comercial',
 DATE'2026-01-01', NULL, TRUE,
 'Se definió junto con MOT-002 para que "qué atrae clientes" no se responda con unidades ni con ventas.'),

('TRF-001', 'Tráfico de mostrador',
 'Qué tiquetes cuentan como visita de un cliente a la tienda.',
 'Solo cuentan los tiquetes de sucursales con Formato = Tienda. La bodega de constructores queda fuera: sus pedidos grandes no son visitas. Las compras que el POS partió en varias facturas (comparten Proforma) tampoco entran en el cálculo de motivo.',
 'Gerencia de operaciones',
 DATE'2025-01-01', NULL, TRUE,
 'La bodega parte los pedidos grandes en varias facturas e inflaba el conteo de clientes.'),

('TRF-002', 'Flete',
 'El flete no es un producto que atraiga clientes.',
 'La sublínea FLETE no participa en el tráfico ni en el motivo de visita (rol "No aplica").',
 'Gerencia de operaciones',
 DATE'2025-01-01', NULL, TRUE,
 'Va en casi todos los pedidos de bodega y aparecía como "imán".');

-- Revisión: 5 filas, una sola versión activa por regla
SELECT RuleName, COUNT(*) AS versiones, SUM(CASE WHEN IsActive THEN 1 ELSE 0 END) AS activas
FROM meta.business_rules
GROUP BY RuleName;
