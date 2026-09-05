-- Contrato de gold.fato_vendas — escrito antes do SQL:
--   Granularidade: uma linha por ITEM de pedido (item_id é a chave do grão,
--                  junto com pedido_id).
--   Filtro: exclui pedidos cancelados. Devolução fica DENTRO, com quantidade
--           e receita NEGATIVAS e a flag devolucao — nunca é descartada.
--   Dimensões: data_pedido, ano, mes, canal, cliente_id, razao_social,
--              segmento, cidade, vendedor_id, sku, categoria, marca,
--              nota_olfativa.
--   Métricas:  quantidade, preco_praticado, receita, custo, margem, devolucao.
--   custo  = quantidade * custo_unitario do produto (segue o sinal da quantidade)
--   margem = receita - custo
--   Particionada por ano e mes.
--
-- 36 pedidos apontam para um cliente_id descartado na deduplicação da silver
-- (silver.clientes.cliente_ids_duplicados). O mapa abaixo resolve esses
-- pedidos para o cliente_id que sobreviveu, para não perder as linhas.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.fato_vendas
USING DELTA
PARTITIONED BY (ano, mes)
AS
WITH mapa_cliente AS (
  SELECT explode(cliente_ids_duplicados) AS id_antigo, cliente_id AS id_atual
  FROM lakehouse_rotaperfume.silver.clientes
  WHERE cliente_ids_duplicados IS NOT NULL
)
SELECT
  i.item_id,
  i.pedido_id,
  p.data_pedido,
  p.ano,
  p.mes,
  p.canal,
  coalesce(m.id_atual, p.cliente_id) AS cliente_id,
  c.razao_social,
  c.segmento,
  c.cidade,
  p.vendedor_id,
  i.sku,
  pr.categoria,
  pr.marca,
  pr.nota_olfativa,
  i.quantidade,
  i.preco_praticado,
  CAST(i.quantidade * i.preco_praticado AS DECIMAL(18, 2)) AS receita,
  CAST(i.quantidade * pr.custo_unitario AS DECIMAL(18, 2)) AS custo,
  CAST(i.quantidade * i.preco_praticado - i.quantidade * pr.custo_unitario AS DECIMAL(18, 2)) AS margem,
  i.devolucao
FROM lakehouse_rotaperfume.silver.itens_pedido i
JOIN lakehouse_rotaperfume.silver.pedidos p ON p.pedido_id = i.pedido_id
LEFT JOIN mapa_cliente m ON m.id_antigo = p.cliente_id
JOIN lakehouse_rotaperfume.silver.clientes c ON c.cliente_id = coalesce(m.id_atual, p.cliente_id)
JOIN lakehouse_rotaperfume.silver.produtos pr ON pr.sku = i.sku
WHERE NOT p.cancelado;

COMMENT ON TABLE lakehouse_rotaperfume.gold.fato_vendas IS
  'Uma linha por item de pedido não cancelado. Devolução fica dentro, com quantidade e receita negativas e a flag devolucao — para não somar bruto e líquido em números diferentes sem ninguém perceber.';

ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN item_id COMMENT
  'Chave do grão, junto com pedido_id: identifica um item específico dentro de um pedido.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN pedido_id COMMENT
  'Pedido ao qual o item pertence. Pedidos cancelados não aparecem aqui.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN data_pedido COMMENT
  'Data em que o pedido foi feito.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN ano COMMENT
  'Ano do pedido. Coluna de partição.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN mes COMMENT
  'Mês do pedido (1-12). Coluna de partição.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN canal COMMENT
  'Canal pelo qual o pedido foi feito (visita, WhatsApp, etc.).';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN cliente_id COMMENT
  'Cliente do pedido. Já resolvido para o cliente_id que sobreviveu à deduplicação da silver, mesmo quando o pedido original apontava para o cadastro descartado.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN razao_social COMMENT
  'Razão social do cliente no momento da consulta (não no momento da venda).';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN segmento COMMENT
  'Segmento de atuação do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN cidade COMMENT
  'Cidade do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN vendedor_id COMMENT
  'Vendedor responsável pelo pedido.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN sku COMMENT
  'Produto vendido neste item.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN categoria COMMENT
  'Categoria do produto.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN marca COMMENT
  'Marca do produto.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN nota_olfativa COMMENT
  'Nota olfativa predominante do produto.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN quantidade COMMENT
  'Quantidade vendida. Negativa quando o item é uma devolução (veja a coluna devolucao).';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN preco_praticado COMMENT
  'Preço unitário efetivamente cobrado no item, já com desconto aplicado.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN receita COMMENT
  'quantidade * preco_praticado. Negativa em itens de devolução, de propósito: quem quiser só o vendido bruto usa SUM(receita) FILTER (WHERE NOT devolucao).';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN custo COMMENT
  'quantidade * custo_unitario do produto. Segue o sinal da quantidade, como a receita.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN margem COMMENT
  'Receita menos custo do produto. Não considera desconto comercial nem frete.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN devolucao COMMENT
  'true quando este item é uma devolução (quantidade negativa na origem). A linha permanece no fato — nunca é descartada.';
