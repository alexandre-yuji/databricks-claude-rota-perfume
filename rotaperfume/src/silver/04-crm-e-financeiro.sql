-- Silver: vendedores, carteira, oportunidades, visitas, pagamentos, estoque.
-- Nenhuma inconsistência de negócio é corrigida aqui: carteiras órfãs e saldo
-- em ruptura ficam sinalizados em colunas próprias, para o gestor decidir.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.vendedores AS
SELECT
  vendedor_id,
  nome,
  regiao,
  uf,
  try_to_date(nullif(data_admissao, '')) AS data_admissao,
  try_to_date(nullif(data_desligamento, '')) AS data_desligamento,
  CAST(meta_mensal AS DECIMAL(18, 2)) AS meta_mensal,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.vendedores) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.vendedores;

COMMENT ON TABLE lakehouse_rotaperfume.silver.vendedores IS
  'Vendedores tipados; data_desligamento NULL significa vendedor ativo.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.carteira AS
SELECT
  c.carteira_id,
  c.cliente_id,
  c.vendedor_id,
  try_to_date(nullif(c.data_inicio, '')) AS data_inicio,
  try_to_date(nullif(c.data_fim, '')) AS data_fim,
  try_to_date(nullif(c.data_fim, '')) IS NULL AND v.data_desligamento IS NULL AS vigente,
  try_to_date(nullif(c.data_fim, '')) IS NULL AND v.data_desligamento IS NOT NULL AS orfao_vendedor_desligado,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.carteira) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.carteira c
LEFT JOIN lakehouse_rotaperfume.silver.vendedores v ON v.vendedor_id = c.vendedor_id;

COMMENT ON TABLE lakehouse_rotaperfume.silver.carteira IS
  'Carteira de clientes por vendedor; vigente e orfao_vendedor_desligado expõem, sem corrigir, o caso de carteira sem data_fim ligada a vendedor já desligado.';
ALTER TABLE lakehouse_rotaperfume.silver.carteira ALTER COLUMN vigente COMMENT
  'true só quando data_fim é nula E o vendedor não está desligado.';
ALTER TABLE lakehouse_rotaperfume.silver.carteira ALTER COLUMN orfao_vendedor_desligado COMMENT
  'true quando a carteira parece vigente (data_fim nula) mas o vendedor responsável já foi desligado — inconsistência da origem, exposta e não corrigida.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.oportunidades AS
SELECT
  oportunidade_id,
  cliente_id,
  vendedor_id,
  origem,
  coalesce(try_to_date(data_abertura), try_to_date(data_abertura, 'dd/MM/yyyy')) AS data_abertura,
  etapa,
  CASE etapa
    WHEN 'Fechado ganho' THEN 'Ganho'
    WHEN 'Fechado perdido' THEN 'Perdido'
    ELSE 'Aberto'
  END AS resultado,
  CAST(probabilidade_pct AS DECIMAL(5, 2)) AS probabilidade_pct,
  CAST(valor_estimado AS DECIMAL(18, 2)) AS valor_estimado,
  coalesce(try_to_date(data_fechamento), try_to_date(data_fechamento, 'dd/MM/yyyy')) AS data_fechamento,
  CAST(ciclo_dias AS INT) AS ciclo_dias,
  motivo_perda,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.oportunidades) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.oportunidades;

COMMENT ON TABLE lakehouse_rotaperfume.silver.oportunidades IS
  'Oportunidades tipadas; resultado resume a etapa (as etapas de origem se chamam "Fechado ganho"/"Fechado perdido", não "Ganha"/"Perdida").';
ALTER TABLE lakehouse_rotaperfume.silver.oportunidades ALTER COLUMN resultado COMMENT
  'Derivado de etapa: Ganho (Fechado ganho), Perdido (Fechado perdido) ou Aberto (qualquer outra etapa).';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.visitas AS
SELECT
  visita_id,
  cliente_id,
  vendedor_id,
  coalesce(try_to_date(data_visita), try_to_date(data_visita, 'dd/MM/yyyy')) AS data_visita,
  resultado,
  CAST(duracao_min AS INT) AS duracao_min,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.visitas) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.visitas;

COMMENT ON TABLE lakehouse_rotaperfume.silver.visitas IS
  'Visitas tipadas, sem regra de negócio adicional.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.pagamentos AS
SELECT
  pagamento_id,
  pedido_id,
  forma_pagamento,
  CAST(parcelas AS INT) AS parcelas,
  CAST(valor AS DECIMAL(18, 2)) AS valor,
  CAST(taxa_pct AS DECIMAL(5, 2)) AS taxa_pct,
  CAST(valor_liquido AS DECIMAL(18, 2)) AS valor_liquido,
  try_to_date(nullif(data_vencimento, '')) AS data_vencimento,
  try_to_date(nullif(data_pagamento, '')) AS data_pagamento,
  status_pagamento,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.pagamentos) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.pagamentos;

COMMENT ON TABLE lakehouse_rotaperfume.silver.pagamentos IS
  'Pagamentos tipados; data_pagamento fica NULL quando ainda não pago.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.estoque AS
SELECT
  try_to_date(nullif(data_snapshot, '')) AS data_snapshot,
  sku,
  CAST(saldo AS INT) AS saldo,
  CAST(saldo AS INT) = 0 AS ruptura,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.estoque) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.estoque;

COMMENT ON TABLE lakehouse_rotaperfume.silver.estoque IS
  'Estoque tipado; ruptura é recalculada a partir de saldo = 0, em vez de confiar na flag de texto da origem.';
ALTER TABLE lakehouse_rotaperfume.silver.estoque ALTER COLUMN ruptura COMMENT
  'Derivado de saldo = 0, não copiado da coluna de texto da origem.';
