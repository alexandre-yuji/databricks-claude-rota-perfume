-- Gold: quatro dimensões conformadas. Lê só da silver, nunca da bronze.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_cliente AS
SELECT
  c.cliente_id,
  c.cnpj,
  c.razao_social,
  c.segmento,
  c.cidade,
  c.uf,
  c.data_cadastro,
  MIN(p.data_pedido) AS data_primeiro_pedido,
  MAX(p.data_pedido) AS data_ultimo_pedido,
  COUNT(p.pedido_id) AS total_pedidos,
  COALESCE(SUM(p.valor_liquido), 0) AS receita_acumulada,
  datediff(current_date(), MAX(p.data_pedido)) AS dias_sem_comprar
FROM lakehouse_rotaperfume.silver.clientes c
LEFT JOIN lakehouse_rotaperfume.silver.pedidos p ON p.cliente_id = c.cliente_id
GROUP BY c.cliente_id, c.cnpj, c.razao_social, c.segmento, c.cidade, c.uf, c.data_cadastro;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_cliente IS
  'Uma linha por cliente, com histórico de compra resumido. Base para o mart comercial e para o dim_cliente do dashboard.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN receita_acumulada COMMENT
  'Soma do valor_liquido de todos os pedidos do cliente. Pedido cancelado contribui zero, nunca negativo.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN dias_sem_comprar COMMENT
  'Dias corridos entre hoje e a data do último pedido. NULL quando o cliente nunca comprou.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_produto AS
SELECT
  sku,
  descricao,
  marca,
  categoria,
  nota_olfativa,
  custo_unitario,
  preco_tabela,
  data_lancamento,
  NOT ativo AS descontinuado
FROM lakehouse_rotaperfume.silver.produtos;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_produto IS
  'Uma linha por SKU, com o custo e o preço de tabela usados para calcular margem na gold.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN descontinuado COMMENT
  'true quando o produto está inativo hoje — vendas passadas desse SKU continuam válidas no fato.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_vendedor AS
SELECT
  vendedor_id,
  nome,
  regiao,
  meta_mensal,
  data_desligamento IS NULL AS ativo
FROM lakehouse_rotaperfume.silver.vendedores;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_vendedor IS
  'Uma linha por vendedor, com a meta mensal usada para calcular atingimento no mart comercial.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN ativo COMMENT
  'true quando o vendedor não tem data_desligamento — vendas passadas de um vendedor desligado continuam válidas no fato.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_calendario AS
WITH limites AS (
  SELECT
    CAST(date_trunc('month', MIN(data_pedido)) AS DATE) AS inicio,
    last_day(MAX(data_pedido)) AS fim
  FROM lakehouse_rotaperfume.silver.pedidos
)
SELECT
  dia,
  year(dia) AS ano,
  month(dia) AS mes,
  CASE month(dia)
    WHEN 1 THEN 'Janeiro' WHEN 2 THEN 'Fevereiro' WHEN 3 THEN 'Março'
    WHEN 4 THEN 'Abril' WHEN 5 THEN 'Maio' WHEN 6 THEN 'Junho'
    WHEN 7 THEN 'Julho' WHEN 8 THEN 'Agosto' WHEN 9 THEN 'Setembro'
    WHEN 10 THEN 'Outubro' WHEN 11 THEN 'Novembro' ELSE 'Dezembro'
  END AS nome_mes,
  quarter(dia) AS trimestre,
  dayofweek(dia) AS dia_semana,
  CASE dayofweek(dia)
    WHEN 1 THEN 'Domingo' WHEN 2 THEN 'Segunda-feira' WHEN 3 THEN 'Terça-feira'
    WHEN 4 THEN 'Quarta-feira' WHEN 5 THEN 'Quinta-feira' WHEN 6 THEN 'Sexta-feira'
    ELSE 'Sábado'
  END AS nome_dia_semana,
  month(dia) IN (4, 6, 10) AS mes_pico_setor
FROM limites
LATERAL VIEW explode(sequence(inicio, fim, interval 1 day)) dias AS dia;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_calendario IS
  'Uma linha por dia, cobrindo os meses com pedido (24 meses nesta base). Base para join por ano/mes com o fato e os marts.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN mes_pico_setor COMMENT
  'true em abril, junho e outubro — os meses de pico de vendas do setor de perfumaria, usados para explicar sazonalidade nos dashboards.';
