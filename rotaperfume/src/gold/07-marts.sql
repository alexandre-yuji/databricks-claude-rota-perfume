-- Gold: três marts, um por diretoria, todos sobre o MESMO fato_vendas.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor AS
SELECT
  f.vendedor_id,
  v.nome AS vendedor_nome,
  f.ano,
  f.mes,
  ROUND(SUM(f.receita), 2) AS receita,
  ROUND(SUM(f.margem), 2) AS margem,
  v.meta_mensal AS meta,
  ROUND(100 * SUM(f.receita) / v.meta_mensal, 1) AS atingimento_pct,
  COUNT(DISTINCT f.cliente_id) AS clientes_atendidos,
  ROUND(SUM(f.receita) / COUNT(DISTINCT f.pedido_id), 2) AS ticket_medio
FROM lakehouse_rotaperfume.gold.fato_vendas f
JOIN lakehouse_rotaperfume.gold.dim_vendedor v ON v.vendedor_id = f.vendedor_id
GROUP BY f.vendedor_id, v.nome, f.ano, f.mes, v.meta_mensal;

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor IS
  'Mart da diretoria comercial: desempenho de cada vendedor por mês, sobre o mesmo fato_vendas dos outros marts.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN atingimento_pct COMMENT
  'Receita do mês dividida pela meta mensal do vendedor, em percentual.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN ticket_medio COMMENT
  'Receita do mês dividida pelo número de pedidos distintos do vendedor no mês.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_produto_performance AS
WITH por_mes AS (
  SELECT sku, ano, mes,
         SUM(receita) AS receita,
         SUM(margem) AS margem,
         SUM(quantidade) AS quantidade
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY sku, ano, mes
),
total_sku AS (
  SELECT sku, SUM(receita) AS receita_total
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY sku
),
ranqueado AS (
  SELECT
    sku,
    SUM(receita_total) OVER (ORDER BY receita_total DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS receita_acumulada,
    SUM(receita_total) OVER () AS receita_geral
  FROM total_sku
),
classificado AS (
  SELECT
    sku,
    CASE
      WHEN receita_acumulada / receita_geral <= 0.8 THEN 'A'
      WHEN receita_acumulada / receita_geral <= 0.95 THEN 'B'
      ELSE 'C'
    END AS curva_abc
  FROM ranqueado
)
SELECT
  m.sku,
  m.ano,
  m.mes,
  ROUND(m.receita, 2) AS receita,
  ROUND(m.margem, 2) AS margem,
  ROUND(100 * m.margem / m.receita, 1) AS margem_pct,
  m.quantidade,
  cl.curva_abc
FROM por_mes m
JOIN classificado cl ON cl.sku = m.sku;

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_produto_performance IS
  'Mart da diretoria de produto: desempenho de cada SKU por mês, sobre o mesmo fato_vendas dos outros marts.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN curva_abc COMMENT
  'Classificação ABC pela receita acumulada do SKU no período inteiro (A até 80%, B até 95%, C o restante) — é do produto, não do mês, e se repete em todas as linhas mensais do SKU.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento AS
SELECT
  year(data_vencimento) AS ano,
  month(data_vencimento) AS mes,
  ROUND(SUM(valor), 2) AS valor_a_receber,
  ROUND(SUM(valor) FILTER (WHERE data_pagamento IS NOT NULL), 2) AS recebido,
  ROUND(AVG(datediff(data_pagamento, data_vencimento)) FILTER (WHERE data_pagamento IS NOT NULL), 1) AS atraso_medio_dias,
  ROUND(SUM(valor - valor_liquido), 2) AS custo_de_taxa
FROM lakehouse_rotaperfume.silver.pagamentos
GROUP BY year(data_vencimento), month(data_vencimento);

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento IS
  'Mart da diretoria financeira: contas a receber por mês de vencimento, não por mês de pedido.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN recebido COMMENT
  'Soma do valor de pagamentos com data_pagamento preenchida (Pago ou Pago com atraso). Pendente/Inadimplente não entra aqui.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN atraso_medio_dias COMMENT
  'Média de dias entre vencimento e pagamento, só de quem já pagou. Negativo significa pago antes do vencimento.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN custo_de_taxa COMMENT
  'Soma de (valor - valor_liquido): quanto foi perdido em taxa de forma de pagamento neste mês de vencimento.';
