# Databricks notebook source
# MAGIC %md
# MAGIC # Conferência de chegada — raw
# MAGIC Confere que os 10 arquivos de origem (ERP + CRM) chegaram ao Volume `bronze.raw`
# MAGIC antes de qualquer processamento seguir adiante. Arquivo que falta ou vem vazio
# MAGIC interrompe o job aqui — em vez de virar, silenciosamente, um número menor lá na frente.

# COMMAND ----------
dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")

# COMMAND ----------
import os
from datetime import datetime, timezone

ARQUIVOS_ESPERADOS = {
    "erp": ["produtos", "pedidos", "itens_pedido", "pagamentos", "estoque"],
    "crm": ["clientes", "vendedores", "carteira", "oportunidades", "visitas"],
}

RAW_ROOT = f"/Volumes/{catalog}/bronze/raw"


def contar_linhas_de_dado(caminho: str) -> int:
    with open(caminho, "rb") as f:
        total = sum(1 for _ in f)
    return max(total - 1, 0)  # desconta o cabeçalho


registros = []
faltantes = []
vazios = []

for sistema, nomes in ARQUIVOS_ESPERADOS.items():
    for nome in nomes:
        caminho = f"{RAW_ROOT}/{sistema}/{nome}.csv"
        if not os.path.exists(caminho):
            faltantes.append(caminho)
            continue
        tamanho = os.path.getsize(caminho)
        linhas = contar_linhas_de_dado(caminho)
        if tamanho == 0 or linhas == 0:
            vazios.append(caminho)
        registros.append(
            {
                "sistema": sistema,
                "arquivo": f"{nome}.csv",
                "bytes": tamanho,
                "linhas": linhas,
                "conferido_em": datetime.now(timezone.utc),
            }
        )

if faltantes or vazios:
    partes = []
    if faltantes:
        partes.append("faltando: " + ", ".join(faltantes))
    if vazios:
        partes.append("vazios: " + ", ".join(vazios))
    raise Exception("Conferência de chegada falhou — " + " | ".join(partes))

# COMMAND ----------
df = spark.createDataFrame(registros)
df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(
    f"{catalog}.bronze._raw_arquivos"
)
spark.sql(
    f"""
    COMMENT ON TABLE {catalog}.bronze._raw_arquivos IS
    'Controle de chegada da camada raw: tamanho e linhas de cada arquivo, conferidos a cada execução do pipeline.'
    """
)

# COMMAND ----------
print(f"{'sistema':<6} {'arquivo':<20} {'bytes':>10} {'linhas':>10}")
for r in sorted(registros, key=lambda r: r["linhas"], reverse=True):
    print(f"{r['sistema']:<6} {r['arquivo']:<20} {r['bytes']:>10} {r['linhas']:>10}")
print(f"\n{len(registros)} arquivos conferidos, {sum(r['linhas'] for r in registros)} linhas de dado.")
