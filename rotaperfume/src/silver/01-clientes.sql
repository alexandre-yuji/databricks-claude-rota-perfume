-- Silver: clientes. Normaliza CNPJ, razão social e data de cadastro; deduplica
-- CNPJs repetidos mantendo o cadastro mais antigo e rastreando o id descartado.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.clientes AS
WITH normalizado AS (
  SELECT
    cliente_id,
    lpad(regexp_replace(trim(cnpj), '[^0-9]', ''), 14, '0') AS cnpj,
    initcap(trim(regexp_replace(razao_social, ' +', ' '))) AS razao_social,
    segmento,
    cidade,
    uf,
    bairro,
    coalesce(try_to_date(data_cadastro), try_to_date(data_cadastro, 'dd/MM/yyyy')) AS data_cadastro,
    ativo = 'S' AS ativo
  FROM lakehouse_rotaperfume.bronze.clientes
),
com_grupo AS (
  SELECT
    *,
    row_number() OVER (PARTITION BY cnpj ORDER BY data_cadastro ASC, cliente_id ASC) AS ordem,
    collect_list(cliente_id) OVER (PARTITION BY cnpj) AS ids_do_grupo
  FROM normalizado
)
SELECT
  cliente_id,
  cnpj,
  razao_social,
  segmento,
  cidade,
  uf,
  bairro,
  data_cadastro,
  ativo,
  CASE WHEN size(ids_do_grupo) > 1
       THEN filter(ids_do_grupo, id -> id != cliente_id)
       ELSE NULL END AS cliente_ids_duplicados,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.clientes) AS _linhas_origem
FROM com_grupo
WHERE ordem = 1;

COMMENT ON TABLE lakehouse_rotaperfume.silver.clientes IS
  'Clientes limpos e deduplicados por CNPJ, mantendo o cadastro mais antigo de cada CNPJ.';

ALTER TABLE lakehouse_rotaperfume.silver.clientes ALTER COLUMN cnpj COMMENT
  'Normalizado para 14 dígitos: trim, remoção de tudo que não é dígito, lpad com zero à esquerda. Nunca convertido para número (perderia zeros à esquerda).';
ALTER TABLE lakehouse_rotaperfume.silver.clientes ALTER COLUMN razao_social COMMENT
  'Padronizado com initcap e espaços duplos colapsados; a origem tinha caixa e espaçamento inconsistentes.';
ALTER TABLE lakehouse_rotaperfume.silver.clientes ALTER COLUMN data_cadastro COMMENT
  'Convertido com coalesce de try_to_date(ISO) e try_to_date(dd/MM/yyyy); a origem mistura os dois formatos.';
ALTER TABLE lakehouse_rotaperfume.silver.clientes ALTER COLUMN ativo COMMENT
  'Convertido de texto S/N para boolean.';
ALTER TABLE lakehouse_rotaperfume.silver.clientes ALTER COLUMN cliente_ids_duplicados COMMENT
  '40 CNPJs tinham dois cadastros (cliente_id diferente); este campo guarda o(s) id(s) descartado(s) na deduplicação, porque pedidos antigos ainda apontam para eles.';

ALTER TABLE lakehouse_rotaperfume.silver.clientes ADD CONSTRAINT cnpj_14 CHECK (length(cnpj) = 14);
ALTER TABLE lakehouse_rotaperfume.silver.clientes ADD CONSTRAINT data_cadastro_not_null CHECK (data_cadastro IS NOT NULL);
