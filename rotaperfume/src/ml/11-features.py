# Databricks notebook source
# MAGIC %md
# MAGIC # Features de cliente
# MAGIC Uma linha por cliente com tudo que se sabia dele ATÉ a data de referência.
# MAGIC A mesma `montar_features()` gera o dado de treino (com rótulo) e o de
# MAGIC score (sem rótulo) — impossível os dois divergirem (training/serving skew).
# MAGIC
# MAGIC Não lê `gold.dim_cliente`: `dias_sem_comprar`, `receita_acumulada` e
# MAGIC `total_pedidos` agregam a base inteira sem corte de data — usar
# MAGIC qualquer uma delas aqui seria vazamento.

# COMMAND ----------
dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
CATALOG = dbutils.widgets.get("catalog")

# COMMAND ----------
from pyspark.sql import functions as F
from pyspark.sql import Window

NUMERIC_COLS = [
    "recencia_dias", "frequencia_pedidos", "valor_total", "ticket_medio",
    "margem_total", "margem_percentual",
    "intervalo_medio_dias", "desvio_intervalo_dias", "atraso_relativo", "pedidos_ultimos_90d",
    "oportunidades_abertas", "oportunidades_ganhas", "taxa_ganho", "visitas_90d", "conversao_visita",
    "skus_distintos", "categorias_distintas", "marcas_distintas",
    "concentracao_marca_top", "comprou_lancamento",
]

ZERO_FILL_COLS = [
    "pedidos_ultimos_90d",
    "oportunidades_abertas", "oportunidades_ganhas", "taxa_ganho",
    "visitas_90d", "conversao_visita",
    "comprou_lancamento",
]


def montar_features(referencia: str):
    """Uma linha por cliente com o que se sabia dele até `referencia` (exclusive)."""
    ref = F.lit(referencia).cast("date")

    pedidos = spark.table(f"{CATALOG}.gold.fato_vendas").filter(F.col("data_pedido") < ref)
    oportunidades = spark.table(f"{CATALOG}.silver.oportunidades").filter(F.col("data_abertura") < ref)
    visitas = spark.table(f"{CATALOG}.silver.visitas").filter(F.col("data_visita") < ref)
    produtos = spark.table(f"{CATALOG}.gold.dim_produto").select("sku", "data_lancamento")

    # --- RFM ---
    rfm = (
        pedidos.groupBy("cliente_id")
        .agg(
            F.datediff(ref, F.max("data_pedido")).alias("recencia_dias"),
            F.countDistinct("pedido_id").alias("frequencia_pedidos"),
            F.sum("receita").alias("valor_total"),
            F.sum("margem").alias("margem_total"),
        )
        .withColumn("ticket_medio", F.col("valor_total") / F.col("frequencia_pedidos"))
        .withColumn("margem_percentual", F.col("margem_total") / F.expr("nullif(valor_total, 0)"))
    )

    # --- Ritmo: gaps entre pedidos consecutivos (datas distintas, via lag()) ---
    datas = pedidos.select("cliente_id", "data_pedido").distinct()
    janela_datas = Window.partitionBy("cliente_id").orderBy("data_pedido")
    gaps = (
        datas.withColumn("data_anterior", F.lag("data_pedido").over(janela_datas))
        .withColumn("gap_dias", F.datediff("data_pedido", "data_anterior"))
        .filter(F.col("gap_dias").isNotNull())
    )
    ritmo = gaps.groupBy("cliente_id").agg(
        F.avg("gap_dias").alias("intervalo_medio_dias"),
        F.stddev("gap_dias").alias("desvio_intervalo_dias"),
    )

    pedidos_90d = (
        pedidos.filter(F.col("data_pedido") >= F.date_sub(ref, 90))
        .groupBy("cliente_id")
        .agg(F.countDistinct("pedido_id").alias("pedidos_ultimos_90d"))
    )

    # --- Mix ---
    mix = pedidos.groupBy("cliente_id").agg(
        F.countDistinct("sku").alias("skus_distintos"),
        F.countDistinct("categoria").alias("categorias_distintas"),
        F.countDistinct("marca").alias("marcas_distintas"),
    )

    receita_por_marca = pedidos.groupBy("cliente_id", "marca").agg(F.sum("receita").alias("receita_marca"))
    janela_marca = Window.partitionBy("cliente_id").orderBy(F.desc("receita_marca"))
    top_marca = (
        receita_por_marca.withColumn("rn", F.row_number().over(janela_marca))
        .filter(F.col("rn") == 1)
        .select("cliente_id", F.col("receita_marca").alias("receita_marca_top"))
    )

    lancamentos_recentes = produtos.filter(
        F.col("data_lancamento").isNotNull()
        & (F.col("data_lancamento") >= F.date_sub(ref, 120))
        & (F.col("data_lancamento") < ref)
    )
    compras_lancamento = (
        pedidos.join(lancamentos_recentes, on="sku", how="inner")
        .select("cliente_id")
        .distinct()
        .withColumn("comprou_lancamento", F.lit(1))
    )

    # --- CRM ---
    # silver.oportunidades não tem colunas booleanas ganha/perdida: usa resultado
    # (Ganho / Aberto / Perdido). silver.visitas não tem gerou_pedido: usa
    # resultado = 'Pedido realizado'.
    crm_op = (
        oportunidades.groupBy("cliente_id")
        .agg(
            F.sum(F.when(F.col("resultado") == "Aberto", 1).otherwise(0)).alias("oportunidades_abertas"),
            F.sum(F.when(F.col("resultado") == "Ganho", 1).otherwise(0)).alias("oportunidades_ganhas"),
            F.count(F.lit(1)).alias("total_oportunidades"),
        )
        .withColumn("taxa_ganho", F.col("oportunidades_ganhas") / F.expr("nullif(total_oportunidades, 0)"))
    )

    visitas_90d = (
        visitas.filter(F.col("data_visita") >= F.date_sub(ref, 90))
        .groupBy("cliente_id")
        .agg(F.count(F.lit(1)).alias("visitas_90d"))
    )

    conversao = (
        visitas.groupBy("cliente_id")
        .agg(
            F.sum(F.when(F.col("resultado") == "Pedido realizado", 1).otherwise(0)).alias("visitas_com_pedido"),
            F.count(F.lit(1)).alias("total_visitas"),
        )
        .withColumn("conversao_visita", F.col("visitas_com_pedido") / F.expr("nullif(total_visitas, 0)"))
    )

    base = (
        rfm
        .join(ritmo, "cliente_id", "left")
        .join(pedidos_90d, "cliente_id", "left")
        .join(crm_op, "cliente_id", "left")
        .join(visitas_90d, "cliente_id", "left")
        .join(conversao, "cliente_id", "left")
        .join(mix, "cliente_id", "left")
        .join(top_marca, "cliente_id", "left")
        .join(compras_lancamento, "cliente_id", "left")
    )

    # atraso_relativo: F.least() ignora nulo e devolveria o teto (10) para quem
    # tem intervalo_medio_dias nulo (um pedido só) — por isso o cálculo do
    # teto fica DENTRO do when(), nunca exposto a um argumento nulo.
    base = base.withColumn(
        "atraso_relativo",
        F.when(
            F.col("intervalo_medio_dias").isNotNull() & (F.col("intervalo_medio_dias") > 0),
            F.least(F.col("recencia_dias") / F.col("intervalo_medio_dias"), F.lit(10.0)),
        ),
    )
    base = base.withColumn(
        "concentracao_marca_top",
        F.col("receita_marca_top") / F.expr("nullif(valor_total, 0)"),
    )

    base = base.fillna(0, subset=ZERO_FILL_COLS)

    for c in NUMERIC_COLS:
        base = base.withColumn(c, F.col(c).cast("double"))

    return (
        base
        .withColumn("_referencia", ref)
        .select("cliente_id", "_referencia", *NUMERIC_COLS)
    )


# COMMAND ----------
# features_treino: referência 2026-08-01, com o alvo comprou_em_7d
features_treino_base = montar_features("2026-08-01")

alvo = (
    spark.table(f"{CATALOG}.gold.fato_vendas")
    .filter((F.col("data_pedido") >= F.lit("2026-08-01")) & (F.col("data_pedido") <= F.lit("2026-08-07")))
    .select("cliente_id")
    .distinct()
    .withColumn("comprou_em_7d", F.lit(1.0))
)

features_treino = (
    features_treino_base.join(alvo, "cliente_id", "left")
    .fillna(0.0, subset=["comprou_em_7d"])
)

features_treino.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(
    f"{CATALOG}.gold.features_treino"
)
spark.sql(f"""
    COMMENT ON TABLE {CATALOG}.gold.features_treino IS
    'Uma linha por cliente com features calculadas com dado anterior a 2026-08-01, mais o rótulo comprou_em_7d (fez pedido entre 2026-08-01 e 2026-08-07). Usada para treinar o modelo de propensão de compra.'
""")

# COMMAND ----------
# features_cliente: referência 2026-08-31, sem alvo — é o que será pontuado
features_cliente = montar_features("2026-08-31")

features_cliente.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(
    f"{CATALOG}.gold.features_cliente"
)
spark.sql(f"""
    COMMENT ON TABLE {CATALOG}.gold.features_cliente IS
    'Uma linha por cliente com features calculadas com dado anterior a 2026-08-31, sem rótulo — é a fila que o modelo pontua para dizer quem tem mais chance de comprar esta semana.'
""")

# COMMAND ----------
print("features_treino:", features_treino.count(), "clientes")
print("features_cliente:", features_cliente.count(), "clientes")
