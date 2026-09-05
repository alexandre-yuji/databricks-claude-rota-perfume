-- Vendedor -> quantos contatos ele tem na fila desta semana. Alimenta o Select
-- de filtro da tela "A semana".
SELECT vendedor, COUNT(*) AS contatos
FROM lakehouse_rotaperfume.gold.fila_semanal
GROUP BY vendedor
ORDER BY vendedor;
