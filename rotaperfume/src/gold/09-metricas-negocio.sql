-- Views com nome de negócio sobre a gold. O COMMENT de cada uma é a PERGUNTA
-- que ela responde — é o que o Genie lê para escolher onde procurar.

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.receita_mensal (
  ano COMMENT 'Ano do mês',
  mes COMMENT 'Mês (1-12)',
  receita COMMENT 'Receita líquida do mês (com devolução, negativa)',
  margem COMMENT 'Margem do mês (receita menos custo do produto)',
  pedidos COMMENT 'Número de pedidos distintos no mês',
  mes_pico_setor COMMENT 'true em abril, junho e outubro — meses de pico do SETOR de perfumaria, não da empresa; dezembro e janeiro são vale esperado'
)
COMMENT 'Quanto vendemos, quanto ganhamos e quantos pedidos tivemos a cada mês — e se aquele mês era esperado ser de pico ou de vale para o setor.'
AS
WITH cal_mes AS (
  SELECT DISTINCT ano, mes, mes_pico_setor FROM lakehouse_rotaperfume.gold.dim_calendario
)
SELECT
  f.ano,
  f.mes,
  ROUND(SUM(f.receita), 2) AS receita,
  ROUND(SUM(f.margem), 2) AS margem,
  COUNT(DISTINCT f.pedido_id) AS pedidos,
  cm.mes_pico_setor
FROM lakehouse_rotaperfume.gold.fato_vendas f
JOIN cal_mes cm ON cm.ano = f.ano AND cm.mes = f.mes
GROUP BY f.ano, f.mes, cm.mes_pico_setor;

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.ranking_marcas (
  marca COMMENT 'Marca',
  receita COMMENT 'Receita líquida da marca (com devolução, negativa)',
  margem_pct COMMENT 'Margem da marca dividida pela receita da marca, em %',
  participacao_pct COMMENT 'Receita da marca dividida pela receita total da empresa, em %'
)
COMMENT 'Quais marcas mais vendem, com que margem, e qual fatia da receita total cada uma representa.'
AS
WITH por_marca AS (
  SELECT marca, SUM(receita) AS receita, SUM(margem) AS margem
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY marca
)
SELECT
  marca,
  ROUND(receita, 2) AS receita,
  ROUND(100 * margem / receita, 1) AS margem_pct,
  ROUND(100 * receita / SUM(receita) OVER (), 1) AS participacao_pct
FROM por_marca;

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.margem_por_categoria (
  categoria COMMENT 'Categoria de produto',
  receita COMMENT 'Receita líquida da categoria',
  margem COMMENT 'Margem da categoria (receita menos custo do produto)',
  margem_pct COMMENT 'Margem dividida pela receita, em %'
)
COMMENT 'Qual categoria vende mais e qual categoria dá mais margem — nem sempre é a mesma (Kit Presente vende muito e ganha pouco).'
AS
SELECT
  categoria,
  ROUND(SUM(receita), 2) AS receita,
  ROUND(SUM(margem), 2) AS margem,
  ROUND(100 * SUM(margem) / SUM(receita), 1) AS margem_pct
FROM lakehouse_rotaperfume.gold.fato_vendas
GROUP BY categoria;

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.clientes_em_risco (
  cliente_id COMMENT 'Identificador do cliente',
  razao_social COMMENT 'Razão social do cliente',
  segmento COMMENT 'Segmento de atuação do cliente',
  cidade COMMENT 'Cidade do cliente',
  data_ultimo_pedido COMMENT 'Data do último pedido do cliente',
  dias_sem_comprar COMMENT 'Dias corridos desde o último pedido',
  receita_media_mensal_antes_de_sumir COMMENT 'Receita acumulada do cliente dividida pelos meses entre o primeiro e o último pedido — quanto ele comprava por mês, em média, antes de parar'
)
COMMENT 'Quais clientes pararam de comprar (mais de 90 dias sem pedido) e quanta receita mensal a gente perdeu com cada um.'
AS
SELECT
  cliente_id,
  razao_social,
  segmento,
  cidade,
  data_ultimo_pedido,
  dias_sem_comprar,
  ROUND(receita_acumulada / GREATEST(1, months_between(data_ultimo_pedido, data_primeiro_pedido)), 2) AS receita_media_mensal_antes_de_sumir
FROM lakehouse_rotaperfume.gold.dim_cliente
WHERE dias_sem_comprar > 90;

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.efeito_lancamento (
  sku COMMENT 'SKU do produto',
  marca COMMENT 'Marca do produto',
  categoria COMMENT 'Categoria do produto',
  data_lancamento COMMENT 'Data de lançamento do produto',
  receita_120_dias_lancamento COMMENT 'Receita do SKU nos 120 dias seguintes ao lançamento',
  receita_resto_periodo COMMENT 'Receita do SKU depois dos 120 dias de lançamento, até o fim do período disponível — NULL quando o produto ainda não completou 120 dias de vida'
)
COMMENT 'Produtos novos vendem mais forte logo no lançamento, ou o efeito é parecido com o resto da vida do produto? Compara a receita dos primeiros 120 dias contra o resto.'
AS
SELECT
  p.sku,
  p.marca,
  p.categoria,
  p.data_lancamento,
  ROUND(SUM(f.receita) FILTER (WHERE f.data_pedido < date_add(p.data_lancamento, 120)), 2) AS receita_120_dias_lancamento,
  ROUND(SUM(f.receita) FILTER (WHERE f.data_pedido >= date_add(p.data_lancamento, 120)), 2) AS receita_resto_periodo
FROM lakehouse_rotaperfume.gold.dim_produto p
LEFT JOIN lakehouse_rotaperfume.gold.fato_vendas f ON f.sku = p.sku
WHERE p.data_lancamento IS NOT NULL
GROUP BY p.sku, p.marca, p.categoria, p.data_lancamento;

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.ruptura_por_marca (
  marca COMMENT 'Marca',
  snapshots COMMENT 'Número de snapshots de estoque considerados',
  snapshots_em_ruptura COMMENT 'Número de snapshots em que o saldo estava zerado (ruptura)',
  ruptura_pct COMMENT 'Percentual dos snapshots em ruptura'
)
COMMENT 'Qual marca sofre mais com estoque zerado (ruptura), para priorizar reposição.'
AS
SELECT
  pr.marca,
  COUNT(*) AS snapshots,
  COUNT(*) FILTER (WHERE e.ruptura) AS snapshots_em_ruptura,
  ROUND(100.0 * COUNT(*) FILTER (WHERE e.ruptura) / COUNT(*), 1) AS ruptura_pct
FROM lakehouse_rotaperfume.silver.estoque e
JOIN lakehouse_rotaperfume.gold.dim_produto pr ON pr.sku = e.sku
GROUP BY pr.marca;
