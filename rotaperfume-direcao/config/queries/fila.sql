-- @param vendedor STRING = Todos
-- Os 200 contatos com tudo que precisa para ler na tela — motivo, sugestão e o
-- retorno mais recente já registrado (se houver). 'Todos' não filtra.
WITH retorno_atual AS (
  SELECT cliente_id, status, comentario, registrado_em
  FROM (
    SELECT cliente_id, status, comentario, registrado_em,
           ROW_NUMBER() OVER (PARTITION BY cliente_id ORDER BY registrado_em DESC) AS rn
    FROM lakehouse_rotaperfume.gold.retorno_ligacao
  )
  WHERE rn = 1
)
SELECT
  f.vendedor,
  f.ordem,
  f.cliente_id,
  f.razao_social,
  f.cidade,
  f.uf,
  f.score,
  f.faixa,
  f.ticket_medio,
  f.motivo,
  f.sugestao,
  r.status AS retorno_status,
  r.comentario AS retorno_comentario
FROM lakehouse_rotaperfume.gold.fila_semanal f
LEFT JOIN retorno_atual r ON r.cliente_id = f.cliente_id
WHERE (:vendedor = 'Todos' OR f.vendedor = :vendedor)
ORDER BY f.vendedor, f.ordem;
