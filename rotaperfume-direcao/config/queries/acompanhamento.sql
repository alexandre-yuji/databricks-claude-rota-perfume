-- Por vendedor: quantos estão na fila, quantos já foram trabalhados, e o
-- desfecho de cada um (vendeu / vai_pensar / sem_interesse / nao_atendeu).
WITH retorno_atual AS (
  SELECT cliente_id, status
  FROM (
    SELECT cliente_id, status,
           ROW_NUMBER() OVER (PARTITION BY cliente_id ORDER BY registrado_em DESC) AS rn
    FROM lakehouse_rotaperfume.gold.retorno_ligacao
  )
  WHERE rn = 1
)
SELECT
  f.vendedor,
  COUNT(*) AS na_fila,
  COUNT(r.cliente_id) AS trabalhados,
  COUNT(*) FILTER (WHERE r.status = 'vendeu') AS vendeu,
  COUNT(*) FILTER (WHERE r.status = 'vai_pensar') AS vai_pensar,
  COUNT(*) FILTER (WHERE r.status = 'sem_interesse') AS sem_interesse,
  COUNT(*) FILTER (WHERE r.status = 'nao_atendeu') AS nao_atendeu
FROM lakehouse_rotaperfume.gold.fila_semanal f
LEFT JOIN retorno_atual r ON r.cliente_id = f.cliente_id
GROUP BY f.vendedor
ORDER BY f.vendedor;
