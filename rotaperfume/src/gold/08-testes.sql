-- 9 testes de qualidade. Cada um levanta raise_error() quando falha, para o
-- job PARAR — um teste que não quebra o job não é teste, é relatório.
-- Se algum falhar, corrija a transformação, nunca o teste.

-- 1 · receita da gold = receita da silver = R$ 102.303.828,05 (tolerância 0,01)
SELECT
  '1_receita_conformada' AS teste,
  CAST(g.receita_gold AS STRING) AS valor_calculado,
  '102303828.05 (== silver, tolerância 0.01)' AS valor_esperado,
  CASE WHEN abs(g.receita_gold - s.receita_silver) <= 0.01
        AND abs(g.receita_gold - 102303828.05) <= 0.01
       THEN 'PASSOU'
       ELSE raise_error('teste 1_receita_conformada FALHOU: gold=' || CAST(g.receita_gold AS STRING)
                         || ' silver=' || CAST(s.receita_silver AS STRING))
  END AS resultado
FROM (SELECT ROUND(SUM(receita), 2) AS receita_gold FROM lakehouse_rotaperfume.gold.fato_vendas) g,
     (SELECT ROUND(SUM(valor_liquido), 2) AS receita_silver FROM lakehouse_rotaperfume.silver.pedidos) s;

-- 2 · CNPJ único na silver.clientes (0 duplicados)
SELECT
  '2_cnpj_unico' AS teste,
  CAST(total - unicos AS STRING) AS valor_calculado,
  '0' AS valor_esperado,
  CASE WHEN total = unicos THEN 'PASSOU'
       ELSE raise_error('teste 2_cnpj_unico FALHOU: ' || CAST(total - unicos AS STRING) || ' CNPJ duplicado(s)')
  END AS resultado
FROM (SELECT COUNT(*) AS total, COUNT(DISTINCT cnpj) AS unicos FROM lakehouse_rotaperfume.silver.clientes);

-- 3 · nenhuma data_pedido nula na silver.pedidos
SELECT
  '3_data_pedido_nao_nula' AS teste,
  CAST(nulos AS STRING) AS valor_calculado,
  '0' AS valor_esperado,
  CASE WHEN nulos = 0 THEN 'PASSOU'
       ELSE raise_error('teste 3_data_pedido_nao_nula FALHOU: ' || CAST(nulos AS STRING) || ' data_pedido nula(s)')
  END AS resultado
FROM (SELECT COUNT(*) AS nulos FROM lakehouse_rotaperfume.silver.pedidos WHERE data_pedido IS NULL);

-- 4 · receita negativa só onde devolucao = true
SELECT
  '4_receita_negativa_so_devolucao' AS teste,
  CAST(violacoes AS STRING) AS valor_calculado,
  '0' AS valor_esperado,
  CASE WHEN violacoes = 0 THEN 'PASSOU'
       ELSE raise_error('teste 4_receita_negativa_so_devolucao FALHOU: ' || CAST(violacoes AS STRING)
                         || ' linha(s) com receita negativa e devolucao=false')
  END AS resultado
FROM (SELECT COUNT(*) AS violacoes FROM lakehouse_rotaperfume.gold.fato_vendas WHERE receita < 0 AND NOT devolucao);

-- 5 · volume da gold.fato_vendas entre 140.000 e 250.000 linhas
SELECT
  '5_volume_fato_vendas' AS teste,
  CAST(linhas AS STRING) AS valor_calculado,
  'entre 140000 e 250000' AS valor_esperado,
  CASE WHEN linhas BETWEEN 140000 AND 250000 THEN 'PASSOU'
       ELSE raise_error('teste 5_volume_fato_vendas FALHOU: ' || CAST(linhas AS STRING) || ' linhas, fora de [140000, 250000]')
  END AS resultado
FROM (SELECT COUNT(*) AS linhas FROM lakehouse_rotaperfume.gold.fato_vendas);

-- 6 · nenhum pedido_id na gold que não exista na silver.pedidos
SELECT
  '6_pedido_id_existe_na_silver' AS teste,
  CAST(orfaos AS STRING) AS valor_calculado,
  '0' AS valor_esperado,
  CASE WHEN orfaos = 0 THEN 'PASSOU'
       ELSE raise_error('teste 6_pedido_id_existe_na_silver FALHOU: ' || CAST(orfaos AS STRING)
                         || ' pedido_id na gold sem par em silver.pedidos')
  END AS resultado
FROM (
  SELECT COUNT(DISTINCT f.pedido_id) AS orfaos
  FROM lakehouse_rotaperfume.gold.fato_vendas f
  LEFT JOIN lakehouse_rotaperfume.silver.pedidos p ON p.pedido_id = f.pedido_id
  WHERE p.pedido_id IS NULL
);

-- 7 · nenhum cliente_id na gold que não exista na silver.clientes
SELECT
  '7_cliente_id_existe_na_silver' AS teste,
  CAST(orfaos AS STRING) AS valor_calculado,
  '0' AS valor_esperado,
  CASE WHEN orfaos = 0 THEN 'PASSOU'
       ELSE raise_error('teste 7_cliente_id_existe_na_silver FALHOU: ' || CAST(orfaos AS STRING)
                         || ' cliente_id na gold sem par em silver.clientes')
  END AS resultado
FROM (
  SELECT COUNT(DISTINCT f.cliente_id) AS orfaos
  FROM lakehouse_rotaperfume.gold.fato_vendas f
  LEFT JOIN lakehouse_rotaperfume.silver.clientes c ON c.cliente_id = f.cliente_id
  WHERE c.cliente_id IS NULL
);

-- 8 · mart_produto_performance soma o mesmo que fato_vendas
SELECT
  '8_mart_produto_conformado' AS teste,
  CAST(mart_total AS STRING) AS valor_calculado,
  CAST(fato_total AS STRING) AS valor_esperado,
  CASE WHEN abs(mart_total - fato_total) <= 0.01 THEN 'PASSOU'
       ELSE raise_error('teste 8_mart_produto_conformado FALHOU: mart=' || CAST(mart_total AS STRING)
                         || ' fato=' || CAST(fato_total AS STRING))
  END AS resultado
FROM (
  SELECT
    (SELECT ROUND(SUM(receita), 2) FROM lakehouse_rotaperfume.gold.mart_produto_performance) AS mart_total,
    (SELECT ROUND(SUM(receita), 2) FROM lakehouse_rotaperfume.gold.fato_vendas) AS fato_total
);

-- 9 · todo CNPJ com exatamente 14 dígitos
SELECT
  '9_cnpj_14_digitos' AS teste,
  CAST(invalidos AS STRING) AS valor_calculado,
  '0' AS valor_esperado,
  CASE WHEN invalidos = 0 THEN 'PASSOU'
       ELSE raise_error('teste 9_cnpj_14_digitos FALHOU: ' || CAST(invalidos AS STRING) || ' CNPJ(s) sem 14 dígitos')
  END AS resultado
FROM (SELECT COUNT(*) AS invalidos FROM lakehouse_rotaperfume.silver.clientes WHERE length(cnpj) <> 14);
