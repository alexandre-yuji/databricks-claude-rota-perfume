-- Os quatro números da semana: contatos/vendedores/receita esperada da fila,
-- desempenho do último modelo treinado, e quantos já foram trabalhados.
WITH fila_stats AS (
  SELECT
    COUNT(*) AS contatos,
    COUNT(DISTINCT vendedor) AS vendedores,
    ROUND(SUM(score * ticket_medio), 2) AS receita_esperada
  FROM lakehouse_rotaperfume.gold.fila_semanal
),
referencia AS (
  SELECT MAX(_referencia) AS referencia
  FROM lakehouse_rotaperfume.gold.score_propensao
),
ultimo_modelo AS (
  SELECT versao, lift_top200, acertos_top200, taxa_base
  FROM lakehouse_rotaperfume.gold.modelo_metricas
  QUALIFY ROW_NUMBER() OVER (ORDER BY versao DESC) = 1
),
retorno_atual AS (
  SELECT cliente_id, status
  FROM (
    SELECT cliente_id, status,
           ROW_NUMBER() OVER (PARTITION BY cliente_id ORDER BY registrado_em DESC) AS rn
    FROM lakehouse_rotaperfume.gold.retorno_ligacao
  )
  WHERE rn = 1
),
trabalhados AS (
  SELECT
    COUNT(*) AS ja_trabalhados,
    COUNT(*) FILTER (WHERE r.status = 'vendeu') AS viraram_pedido
  FROM lakehouse_rotaperfume.gold.fila_semanal f
  JOIN retorno_atual r ON r.cliente_id = f.cliente_id
)
SELECT
  fs.contatos,
  fs.vendedores,
  fs.receita_esperada,
  ref.referencia,
  um.versao,
  um.lift_top200,
  um.acertos_top200,
  um.taxa_base,
  t.ja_trabalhados,
  t.viraram_pedido
FROM fila_stats fs
CROSS JOIN referencia ref
CROSS JOIN ultimo_modelo um
CROSS JOIN trabalhados t;
