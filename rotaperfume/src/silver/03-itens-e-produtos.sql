-- Silver: produtos e itens_pedido. Quantidade negativa em itens_pedido é
-- devolução (não erro): fica sinalizada e preservada, nunca descartada.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.produtos AS
SELECT
  sku,
  descricao,
  categoria,
  marca,
  nota_olfativa,
  CAST(preco_tabela AS DECIMAL(18, 2)) AS preco_tabela,
  CAST(custo_unitario AS DECIMAL(18, 2)) AS custo_unitario,
  unidade,
  ativo = 'S' AS ativo,
  try_to_date(nullif(data_lancamento, '')) AS data_lancamento,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.produtos) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.produtos;

COMMENT ON TABLE lakehouse_rotaperfume.silver.produtos IS
  'Produtos tipados: preços em DECIMAL, ativo em boolean, data_lancamento convertida (vazia vira NULL, não erro).';
ALTER TABLE lakehouse_rotaperfume.silver.produtos ALTER COLUMN ativo COMMENT
  'Convertido de texto S/N para boolean.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.itens_pedido AS
SELECT
  i.item_id,
  i.pedido_id,
  i.sku,
  CAST(i.quantidade AS INT) AS quantidade,
  abs(CAST(i.quantidade AS INT)) AS quantidade_abs,
  CAST(i.quantidade AS INT) < 0 AS devolucao,
  CAST(i.preco_praticado AS DECIMAL(18, 2)) AS preco_praticado,
  CAST(i.desconto_pct AS DECIMAL(5, 2)) AS desconto_pct,
  CAST(i.valor_bruto AS DECIMAL(18, 2)) AS valor_bruto,
  coalesce(NOT p.ativo, false) AS sku_descontinuado,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.itens_pedido) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.itens_pedido i
LEFT JOIN lakehouse_rotaperfume.silver.produtos p ON p.sku = i.sku;

COMMENT ON TABLE lakehouse_rotaperfume.silver.itens_pedido IS
  'Itens de pedido tipados; quantidade negativa é devolução (sinalizada, nunca descartada) e sku_descontinuado marca itens de produto hoje inativo.';
ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido ALTER COLUMN devolucao COMMENT
  'Quantidade negativa na origem é devolução, não erro: sinalizada aqui em vez de descartada ou corrigida.';
ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido ALTER COLUMN sku_descontinuado COMMENT
  'true quando o produto do item está inativo hoje em silver.produtos — não implica que estava inativo no momento da venda.';

ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido ADD CONSTRAINT quantidade_abs_positiva CHECK (quantidade_abs > 0);
