-- Fila semanal: quem ligar, por quê, e o que oferecer. A fila é GLOBAL
-- (ORDER BY score DESC LIMIT 200) e só depois numerada por vendedor — cota
-- fixa por vendedor obrigaria a gastar ligação com cliente frio.
--
-- A ORDEM IMPORTA: 1º descarta quem não é elegível (carteira vigente E
-- vendedor não desligado), 2º corta os 200 melhores, 3º numera por vendedor.
-- Se o descarte vier depois do corte, a fila sai com ~172 linhas em vez de
-- 200 (vendedores desligados levam os clientes deles junto) e o teste 1 quebra.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.fila_semanal AS
WITH elegiveis AS (
  SELECT c.cliente_id, c.vendedor_id
  FROM lakehouse_rotaperfume.silver.carteira c
  WHERE c.vigente = true AND c.orfao_vendedor_desligado = false
),
base AS (
  SELECT
    v.nome AS vendedor,
    CAST(e.cliente_id AS INT) AS cliente_id,
    d.razao_social,
    d.cidade,
    d.uf,
    s.score,
    s.faixa,
    f.ticket_medio,
    f.atraso_relativo,
    f.intervalo_medio_dias,
    f.recencia_dias,
    f.valor_total,
    f.comprou_lancamento
  FROM elegiveis e
  JOIN lakehouse_rotaperfume.silver.vendedores v ON v.vendedor_id = e.vendedor_id
  JOIN lakehouse_rotaperfume.gold.score_propensao s ON s.cliente_id = CAST(e.cliente_id AS INT)
  JOIN lakehouse_rotaperfume.gold.dim_cliente d ON d.cliente_id = e.cliente_id
  JOIN lakehouse_rotaperfume.gold.features_cliente f ON f.cliente_id = e.cliente_id
),
top200 AS (
  SELECT * FROM base ORDER BY score DESC LIMIT 200
),
limiar AS (
  SELECT percentile(valor_total, 0.9) AS limiar_valor_total FROM base
),
marca_preferida AS (
  SELECT cliente_id, marca FROM (
    SELECT CAST(cliente_id AS INT) AS cliente_id, marca,
           ROW_NUMBER() OVER (PARTITION BY cliente_id ORDER BY SUM(receita) DESC) AS rn
    FROM lakehouse_rotaperfume.gold.fato_vendas
    GROUP BY cliente_id, marca
  ) WHERE rn = 1
),
comprado_90d AS (
  SELECT DISTINCT CAST(cliente_id AS INT) AS cliente_id, sku
  FROM lakehouse_rotaperfume.gold.fato_vendas
  WHERE data_pedido >= date_sub(DATE'2026-08-31', 90)
),
candidatos AS (
  SELECT CAST(fv.cliente_id AS INT) AS cliente_id, fv.sku, SUM(fv.quantidade) AS quantidade_total
  FROM lakehouse_rotaperfume.gold.fato_vendas fv
  JOIN marca_preferida mp ON mp.cliente_id = CAST(fv.cliente_id AS INT) AND mp.marca = fv.marca
  GROUP BY fv.cliente_id, fv.sku
),
candidatos_disponiveis AS (
  SELECT c.* FROM candidatos c
  LEFT ANTI JOIN comprado_90d r ON r.cliente_id = c.cliente_id AND r.sku = c.sku
),
sugestao_sku AS (
  SELECT cliente_id, sku,
         ROW_NUMBER() OVER (PARTITION BY cliente_id ORDER BY quantidade_total DESC) AS rn
  FROM candidatos_disponiveis
),
estoque_atual AS (
  SELECT sku, saldo, ruptura FROM (
    SELECT sku, saldo, ruptura,
           ROW_NUMBER() OVER (PARTITION BY sku ORDER BY data_snapshot DESC) AS rn
    FROM lakehouse_rotaperfume.silver.estoque
  ) WHERE rn = 1
)
SELECT
  t.vendedor,
  ROW_NUMBER() OVER (PARTITION BY t.vendedor ORDER BY t.score DESC) AS ordem,
  t.cliente_id,
  t.razao_social,
  t.cidade,
  t.uf,
  t.score,
  t.faixa,
  t.ticket_medio,
  -- do sinal mais RARO para o mais comum: se o mais comum vier primeiro, ele
  -- come todos os outros motivos. Medido nesta base (não é a ordem literal do
  -- prompt): comprou_lancamento é verdadeiro para 70% da base inteira (5
  -- lançamentos recentes muito vendidos) — mais comum que valor_total no
  -- topo (percentil 90). Por isso valor_total vem antes de comprou_lancamento.
  CASE
    WHEN t.atraso_relativo > 3 THEN
      CONCAT('Compra a cada ', FORMAT_NUMBER(t.intervalo_medio_dias, 0), ' dias e está há ',
             FORMAT_NUMBER(t.recencia_dias, 0), ' sem pedido. Risco de perder para o concorrente.')
    WHEN t.atraso_relativo > 1.5 THEN
      CONCAT('Está ', FORMAT_NUMBER(t.atraso_relativo, 1), 'x mais atrasado que o ritmo dele.')
    WHEN t.valor_total >= l.limiar_valor_total THEN
      CONCAT('Cliente grande, R$ ', FORMAT_NUMBER(t.valor_total, 0), ' no ano. Manter próximo.')
    WHEN t.comprou_lancamento = 1 THEN
      'Comprou lançamento recente. Alta chance de repetir.'
    ELSE 'Dentro do ritmo. Contato de manutenção.'
  END AS motivo,
  CASE WHEN ss.sku IS NOT NULL THEN
    CONCAT('Sugestão: ', ss.sku,
           CASE WHEN ea.ruptura THEN ' (sem estoque no momento)'
                ELSE CONCAT(' — saldo: ', ea.saldo) END)
  ELSE NULL END AS sugestao
FROM top200 t
CROSS JOIN limiar l
LEFT JOIN sugestao_sku ss ON ss.cliente_id = t.cliente_id AND ss.rn = 1
LEFT JOIN estoque_atual ea ON ea.sku = ss.sku;

COMMENT ON TABLE lakehouse_rotaperfume.gold.fila_semanal IS
  'A lista de ligação da semana: os 200 clientes de maior score entre os elegíveis (carteira vigente, vendedor ativo), numerados por vendedor, com motivo e sugestão de produto.';

ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN vendedor COMMENT
  'Vendedor responsável pela carteira do cliente — quem faz a ligação.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN ordem COMMENT
  'Posição do cliente na lista do vendedor, 1 = maior prioridade (maior score).';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN cliente_id COMMENT
  'Cliente a ser contatado.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN razao_social COMMENT
  'Razão social do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN cidade COMMENT
  'Cidade do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN uf COMMENT
  'UF do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN score COMMENT
  'Probabilidade de compra em 7 dias, do modelo @prod (0 a 1).';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN faixa COMMENT
  'Faixa de prioridade do score: Fria, Morna, Quente ou Muito quente.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN ticket_medio COMMENT
  'Ticket médio histórico do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN motivo COMMENT
  'Por que este cliente está na fila, em português, com os números dele — nunca nulo.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN sugestao COMMENT
  'SKU da marca preferida do cliente que ele não compra há mais de 90 dias, com o saldo do snapshot mais recente de estoque — NULL quando não há sugestão elegível.';

-- As quatro ferramentas do agente: funções SQL no Unity Catalog. O COMMENT é
-- o que o Genie lê para decidir QUANDO chamar cada uma. Todo parâmetro
-- prefixado com p_ — parâmetro com o mesmo nome de coluna deixa o CREATE
-- ambíguo.

CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.priorizar_carteira(p_vendedor STRING, p_quantos INT)
RETURNS TABLE (ordem INT, cliente_id INT, razao_social STRING, cidade STRING, score DOUBLE, faixa STRING, motivo STRING, sugestao STRING)
COMMENT 'Traz a fatia da fila da semana (fila_semanal) de um vendedor, em ordem de prioridade. Use quando o vendedor perguntar quem ligar essa semana ou pedir sua lista de contatos.'
RETURN
  SELECT ordem, cliente_id, razao_social, cidade, score, faixa, motivo, sugestao
  FROM lakehouse_rotaperfume.gold.fila_semanal
  WHERE vendedor = p_vendedor AND ordem <= p_quantos
  ORDER BY ordem;

CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.contexto_cliente(p_cliente_id INT)
RETURNS TABLE (razao_social STRING, cidade STRING, uf STRING, segmento STRING, total_pedidos BIGINT, receita_acumulada DOUBLE, ticket_medio DOUBLE, marca_preferida STRING, data_ultimo_pedido DATE, dias_sem_comprar INT)
COMMENT 'Histórico resumido de um cliente: total de pedidos, receita acumulada, ticket médio, marca preferida e data da última compra. Use quando perguntarem sobre o histórico ou perfil de um cliente específico, por exemplo "por que esse cliente está no topo da lista".'
RETURN
  SELECT
    d.razao_social, d.cidade, d.uf, d.segmento,
    d.total_pedidos, d.receita_acumulada,
    f.ticket_medio,
    (
      SELECT marca FROM lakehouse_rotaperfume.gold.fato_vendas fv
      WHERE fv.cliente_id = CAST(p_cliente_id AS STRING)
      GROUP BY marca ORDER BY SUM(receita) DESC LIMIT 1
    ) AS marca_preferida,
    d.data_ultimo_pedido,
    d.dias_sem_comprar
  FROM lakehouse_rotaperfume.gold.dim_cliente d
  LEFT JOIN lakehouse_rotaperfume.gold.features_cliente f ON f.cliente_id = d.cliente_id
  WHERE d.cliente_id = CAST(p_cliente_id AS STRING);

CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.sugerir_produtos(p_cliente_id INT)
RETURNS TABLE (sku STRING, descricao STRING, marca STRING, categoria STRING, ultima_compra DATE, quantidade_total_historica BIGINT)
COMMENT 'O que o cliente já comprou e parou de comprar nos últimos 90 dias, ordenado do mais comprado historicamente para o menos. Use quando perguntarem o que oferecer ou sugerir para um cliente.'
RETURN
  WITH historico AS (
    SELECT f.sku, MAX(f.data_pedido) AS ultima_compra, SUM(f.quantidade) AS quantidade_total_historica
    FROM lakehouse_rotaperfume.gold.fato_vendas f
    WHERE f.cliente_id = CAST(p_cliente_id AS STRING)
    GROUP BY f.sku
  )
  SELECT h.sku, p.descricao, p.marca, p.categoria, h.ultima_compra, h.quantidade_total_historica
  FROM historico h
  JOIN lakehouse_rotaperfume.gold.dim_produto p ON p.sku = h.sku
  WHERE h.ultima_compra < date_sub(DATE'2026-08-31', 90)
  ORDER BY h.quantidade_total_historica DESC;

CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.checar_disponibilidade(p_sku STRING)
RETURNS TABLE (sku STRING, data_snapshot DATE, saldo INT, ruptura BOOLEAN)
COMMENT 'Saldo de estoque e situação de ruptura de um SKU no snapshot mais recente. Use quando perguntarem se um produto tem estoque disponível antes de sugerir para o cliente.'
RETURN
  SELECT sku, data_snapshot, saldo, ruptura
  FROM (
    SELECT sku, data_snapshot, saldo, ruptura,
           ROW_NUMBER() OVER (PARTITION BY sku ORDER BY data_snapshot DESC) AS rn
    FROM lakehouse_rotaperfume.silver.estoque
    WHERE sku = p_sku
  )
  WHERE rn = 1;

-- Três testes que quebram o job.
WITH problema AS (SELECT COUNT(*) AS n FROM lakehouse_rotaperfume.gold.fila_semanal)
SELECT CASE WHEN n = 200 THEN 'OK: fila_semanal tem 200 linhas'
            ELSE raise_error('fila_semanal tem ' || CAST(n AS STRING) || ' linhas, esperado exatamente 200')
       END AS teste_1
FROM problema;

WITH problema AS (
  SELECT COUNT(*) AS n FROM lakehouse_rotaperfume.gold.fila_semanal WHERE motivo IS NULL OR motivo = ''
)
SELECT CASE WHEN n = 0 THEN 'OK: nenhum motivo nulo ou vazio'
            ELSE raise_error(CAST(n AS STRING) || ' linha(s) de fila_semanal com motivo nulo ou vazio')
       END AS teste_2
FROM problema;

WITH problema AS (
  SELECT COUNT(*) AS n FROM lakehouse_rotaperfume.gold.fila_semanal WHERE score < 0 OR score > 1
)
SELECT CASE WHEN n = 0 THEN 'OK: nenhum score fora de [0,1]'
            ELSE raise_error(CAST(n AS STRING) || ' linha(s) de fila_semanal com score fora do intervalo [0,1]')
       END AS teste_3
FROM problema;
