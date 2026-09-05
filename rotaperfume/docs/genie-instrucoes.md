# Instruções do Genie space — Rota Perfume · Comercial

Texto para colar na configuração do Genie space (também versionado em
`resources/comercial.geniespace.json`, dentro de `instructions.text_instructions`).

## Contexto

A Rota Perfume é uma distribuidora B2B de perfumaria árabe: compra de
fabricantes/importadores e revende para o varejo (perfumarias, farmácias,
lojas de departamento, quiosques, salões de beleza, revendedoras autônomas).
Os dados cobrem 24 meses de vendas, de setembro/2024 a agosto/2026.

Use SÓ as tabelas e views do schema `gold`. Nunca leia `bronze` ou `silver`
diretamente — a bronze não tem nenhuma limpeza aplicada e vai te dar números
errados.

## Glossário

- **Ruptura**: quando o saldo de estoque de um SKU chega a zero num snapshot.
  `gold.ruptura_por_marca` traz o percentual de snapshots em ruptura por marca.
- **Carteira**: a relação entre um vendedor e os clientes que ele atende.
- **Oportunidade**: um negócio em prospecção no funil comercial, que termina
  em "Fechado ganho", "Fechado perdido" ou continua aberto.
- **Devolução**: item de pedido com quantidade negativa — o cliente devolveu
  o produto. Entra na `fato_vendas` com quantidade e receita **negativas**,
  nunca é descartada.
- **SKU**: código único de um produto (referência de estoque).
- **Segmento**: o tipo de negócio do cliente (ex.: Perfumaria, Farmácia,
  Loja de departamento, Quiosque, Salão de beleza, Revendedora autônoma).
- **Atingimento de meta**: receita do vendedor no mês dividida pela meta
  mensal dele, em %. Vem de `gold.mart_vendas_por_vendedor`.
- **Curva ABC**: classificação de produto pela receita acumulada no período
  inteiro (A até 80% da receita acumulada, B até 95%, C o restante). É do
  produto, não do mês — a mesma classificação se repete em todas as linhas
  mensais do SKU em `gold.mart_produto_performance`.

## Regra de sazonalidade (a mais importante)

O pico de vendas da distribuidora acontece no mês **ANTERIOR** à data
comemorativa, porque o varejo compra o estoque antes da data, não durante.

- **Abril** (antes do Dia das Mães em maio), **junho** (antes do Dia dos
  Namorados em junho/julho no varejo) e **outubro** (antes da Black Friday)
  são meses de **pico**.
- **Dezembro e janeiro são VALE — e isso é esperado e saudável, não é queda.**
  O varejo já está abastecido pelos picos anteriores e reduz compra.

Nunca chame dezembro ou janeiro de "mês ruim" ou de "queda de vendas" sem
checar `gold.receita_mensal.mes_pico_setor` primeiro. Se `mes_pico_setor`
for `false` e a receita for menor que a média, isso é o comportamento
NORMAL do setor, não um problema do negócio.

## Como calcular cada métrica

- **Receita**: `SUM(receita)` em `gold.fato_vendas` (ou nas views que já
  agregam). Já vem líquida — inclui devolução como valor negativo.
- **Receita bruta vendida** (sem efeito de devolução): `SUM(receita) FILTER
  (WHERE NOT devolucao)`.
- **Margem**: `SUM(margem)` — é receita menos custo do produto. Não
  considera desconto comercial nem frete.
- **Margem %**: `100 * SUM(margem) / SUM(receita)`.
- **Ticket médio**: `SUM(receita) / COUNT(DISTINCT pedido_id)`.
- **Atingimento de meta**: receita do vendedor no mês dividido pela
  `meta_mensal` dele (de `gold.dim_vendedor` / `gold.mart_vendas_por_vendedor`).
- **Churn / cliente em risco**: cliente sem nenhum pedido há mais de 90 dias
  (`gold.clientes_em_risco.dias_sem_comprar > 90`).

## Aviso sobre devolução

A devolução **entra com valor negativo** dentro de `receita`, `custo` e
`margem` em `gold.fato_vendas` — de propósito, para que a soma da receita
líquida nunca precise de um ajuste manual em outro lugar. Se a pergunta for
sobre o **bruto vendido** (sem o efeito da devolução), filtre
`devolucao = false` (ou use `SUM(receita) FILTER (WHERE NOT devolucao)`).
