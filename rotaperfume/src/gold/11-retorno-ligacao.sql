-- gold.retorno_ligacao: a única tabela do projeto cujo dado NÃO vem do
-- pipeline — vem do time, pelo app. Por isso CREATE TABLE IF NOT EXISTS, e
-- não CREATE OR REPLACE: um redeploy não pode apagar o que o vendedor
-- respondeu.
CREATE TABLE IF NOT EXISTS lakehouse_rotaperfume.gold.retorno_ligacao (
  cliente_id INT,
  vendedor STRING,
  status STRING,
  comentario STRING,
  registrado_em TIMESTAMP,
  registrado_por STRING,
  _referencia DATE
);

COMMENT ON TABLE lakehouse_rotaperfume.gold.retorno_ligacao IS
  'O que aconteceu depois da ligação de cada cliente da fila — o caminho de volta do dado. Começa vazia: ninguém registrou retorno ainda é a resposta certa, não zero como erro.';

ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao ALTER COLUMN cliente_id COMMENT
  'Cliente que recebeu a ligação (mesmo cliente_id de gold.fila_semanal).';
ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao ALTER COLUMN vendedor COMMENT
  'Vendedor que fez a ligação.';
ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao ALTER COLUMN status COMMENT
  'Desfecho da ligação: vendeu, vai_pensar, sem_interesse ou nao_atendeu — validado pelo enum do servidor do app, não por CHECK constraint aqui.';
ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao ALTER COLUMN comentario COMMENT
  'Texto livre do vendedor sobre a ligação, opcional.';
ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao ALTER COLUMN registrado_em COMMENT
  'Quando o retorno foi gravado.';
ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao ALTER COLUMN registrado_por COMMENT
  'E-mail de quem estava logado no app quando registrou.';
ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao ALTER COLUMN _referencia COMMENT
  'A semana da fila (mesma _referencia de gold.score_propensao/fila_semanal) a que este retorno se refere.';
