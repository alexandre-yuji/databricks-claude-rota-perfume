-- Auditoria de metadado da gold. Metadado faltando é BUG, não pendência de
-- documentação: a partir de hoje tem um agente (Genie) lendo esse COMMENT
-- para decidir qual coluna usar.

-- 1) toda tabela/view da gold precisa de COMMENT
WITH problema AS (
  SELECT COUNT(*) AS n, array_join(collect_list(table_name), ', ') AS lista
  FROM lakehouse_rotaperfume.information_schema.tables
  WHERE table_schema = 'gold' AND (comment IS NULL OR comment = '')
)
SELECT CASE WHEN n = 0 THEN 'OK: todas as tabelas/views da gold têm COMMENT'
            ELSE raise_error('Objetos da gold sem COMMENT: ' || lista)
       END AS checagem_1
FROM problema;

-- 2) toda coluna de fato_vendas, das 6 views de negócio, de fila_semanal e de
-- retorno_ligacao precisa de COMMENT
WITH problema AS (
  SELECT COUNT(*) AS n, array_join(collect_list(table_name || '.' || column_name), ', ') AS lista
  FROM lakehouse_rotaperfume.information_schema.columns
  WHERE table_schema = 'gold'
    AND table_name IN (
      'fato_vendas', 'receita_mensal', 'ranking_marcas', 'margem_por_categoria',
      'clientes_em_risco', 'efeito_lancamento', 'ruptura_por_marca',
      'fila_semanal', 'retorno_ligacao'
    )
    AND (comment IS NULL OR comment = '')
)
SELECT CASE WHEN n = 0 THEN 'OK: todas as colunas dessas tabelas/views têm COMMENT'
            ELSE raise_error('Colunas sem COMMENT em fato_vendas/views/fila_semanal/retorno_ligacao: ' || lista)
       END AS checagem_2
FROM problema;

-- 3) relatório de cobertura de metadado por objeto — não quebra, é informativo
SELECT
  c.table_name,
  COUNT(*) AS colunas,
  COUNT(*) FILTER (WHERE c.comment IS NOT NULL AND c.comment <> '') AS comentadas,
  ROUND(100.0 * COUNT(*) FILTER (WHERE c.comment IS NOT NULL AND c.comment <> '') / COUNT(*), 1) AS cobertura_pct
FROM lakehouse_rotaperfume.information_schema.columns c
WHERE c.table_schema = 'gold'
GROUP BY c.table_name
ORDER BY cobertura_pct, c.table_name;
