-- Silver: pedidos. Tipa data e valor, e resolve o "valor zerado sem flag" dos
-- pedidos cancelados criando uma coluna booleana explícita e um valor_liquido.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.pedidos AS
SELECT
  pedido_id,
  cliente_id,
  vendedor_id,
  coalesce(try_to_date(data_pedido), try_to_date(data_pedido, 'dd/MM/yyyy')) AS data_pedido,
  canal,
  status,
  CAST(valor_total AS DECIMAL(18, 2)) AS valor_total,
  status = 'Cancelado' AS cancelado,
  CASE WHEN status = 'Cancelado' THEN CAST(0 AS DECIMAL(18, 2))
       ELSE CAST(valor_total AS DECIMAL(18, 2)) END AS valor_liquido,
  year(coalesce(try_to_date(data_pedido), try_to_date(data_pedido, 'dd/MM/yyyy'))) AS ano,
  month(coalesce(try_to_date(data_pedido), try_to_date(data_pedido, 'dd/MM/yyyy'))) AS mes,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.pedidos) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.pedidos;

COMMENT ON TABLE lakehouse_rotaperfume.silver.pedidos IS
  'Pedidos tipados; pedidos cancelados têm valor_liquido zerado explicitamente via a coluna cancelado.';

ALTER TABLE lakehouse_rotaperfume.silver.pedidos ALTER COLUMN data_pedido COMMENT
  'Convertido com coalesce de try_to_date(ISO) e try_to_date(dd/MM/yyyy); a origem mistura os dois formatos.';
ALTER TABLE lakehouse_rotaperfume.silver.pedidos ALTER COLUMN cancelado COMMENT
  'Derivado de status = ''Cancelado''; a origem zerava o valor do pedido cancelado sem nenhuma flag.';
ALTER TABLE lakehouse_rotaperfume.silver.pedidos ALTER COLUMN valor_liquido COMMENT
  'Zero quando cancelado, valor_total caso contrário. Pode ser negativo em pedidos com item devolvido — isso é esperado, não é sujeira.';

ALTER TABLE lakehouse_rotaperfume.silver.pedidos ADD CONSTRAINT data_pedido_not_null CHECK (data_pedido IS NOT NULL);
ALTER TABLE lakehouse_rotaperfume.silver.pedidos ADD CONSTRAINT pedido_cancelado_zerado CHECK (NOT cancelado OR valor_liquido = 0);
