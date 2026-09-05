# Databricks notebook source
# MAGIC %md
# MAGIC # Ingestão bronze
# MAGIC Lê os 10 CSVs do Volume `bronze.raw` e grava cada um como uma tabela Delta em
# MAGIC `bronze`, sem nenhuma limpeza nem conversão de tipo — tudo entra como STRING de
# MAGIC propósito. A leitura abaixo é equivalente ao `read_files(..., inferColumnTypes
# MAGIC => false)` mostrado na demonstração: mesmo resultado (tudo texto), sem passar
# MAGIC pelo `read_files`/Auto Loader, que gera sozinho uma coluna `_rescued_data`.
# MAGIC Converter tipo é trabalho da silver, feito sabendo o que se faz.

# COMMAND ----------
dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")

# COMMAND ----------
from datetime import datetime, timezone

import pyspark.sql.functions as F

ARQUIVOS_ESPERADOS = {
    "erp": ["produtos", "pedidos", "itens_pedido", "pagamentos", "estoque"],
    "crm": ["clientes", "vendedores", "carteira", "oportunidades", "visitas"],
}

RAW_ROOT = f"/Volumes/{catalog}/bronze/raw"
INGERIDO_EM = datetime.now(timezone.utc)  # um timestamp só, compartilhado por todas as tabelas deste run


def ingerir(sistema: str, tabela: str) -> dict:
    caminho = f"{RAW_ROOT}/{sistema}/{tabela}.csv"
    destino = f"{catalog}.bronze.{tabela}"

    df = (
        spark.read.format("csv")
        .option("header", "true")
        .option("inferSchema", "false")  # tudo STRING, de propósito
        .option("multiLine", "false")  # CSVs são CRLF, um registro por linha
        .load(caminho)
        .withColumn("_ingerido_em", F.lit(INGERIDO_EM).cast("timestamp"))
        .withColumn("_arquivo_origem", F.lit(caminho))
    )

    df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(destino)
    spark.sql(
        f"COMMENT ON TABLE {destino} IS "
        f"'Ingestão bruta do sistema {sistema} — 1:1 com {tabela}.csv, sem limpeza nem conversão de tipo.'"
    )

    linhas = spark.table(destino).count()
    return {"sistema": sistema, "tabela": tabela, "arquivo": f"{tabela}.csv", "linhas": linhas}


resultados = [
    ingerir(sistema, tabela)
    for sistema, tabelas in ARQUIVOS_ESPERADOS.items()
    for tabela in tabelas
]

# COMMAND ----------
raw_counts = {
    row["arquivo"]: row["linhas"]
    for row in spark.table(f"{catalog}.bronze._raw_arquivos").collect()
}

divergencias = []
for r in resultados:
    esperado = raw_counts.get(r["arquivo"])
    r["esperado"] = esperado
    r["bate"] = esperado is not None and r["linhas"] == esperado
    if not r["bate"]:
        divergencias.append(r)

print(f"{'sistema':<6} {'tabela':<14} {'na_bronze':>10} {'no_arquivo':>10} {'bate':>6}")
for r in sorted(resultados, key=lambda r: r["linhas"], reverse=True):
    print(f"{r['sistema']:<6} {r['tabela']:<14} {r['linhas']:>10} {str(r['esperado']):>10} {str(r['bate']):>6}")
print(f"\n{len(resultados)} tabelas na bronze, {sum(r['linhas'] for r in resultados)} linhas no total.")

if divergencias:
    detalhe = ", ".join(f"{r['tabela']} (bronze={r['linhas']} vs raw={r['esperado']})" for r in divergencias)
    raise Exception(f"Contagem divergente entre bronze e _raw_arquivos: {detalhe}")
