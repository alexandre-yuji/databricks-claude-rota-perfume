# Databricks notebook source
# MAGIC %md
# MAGIC # Modelo de propensão de compra
# MAGIC Baseline primeiro (três regras simples, avaliadas como se fossem o score),
# MAGIC depois o modelo — e o modelo só entra em produção se ganhar do melhor
# MAGIC baseline por uma margem real. `lift_top200` é a métrica que responde a
# MAGIC pergunta do diretor: dos 200 que a gente ligar, quantos compram.

# COMMAND ----------
dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
CATALOG = dbutils.widgets.get("catalog")
REGISTERED_MODEL = f"{CATALOG}.gold.propensao_compra"

# COMMAND ----------
import numpy as np
import pandas as pd
import mlflow
import mlflow.sklearn
from mlflow.tracking import MlflowClient
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.model_selection import train_test_split, StratifiedKFold, cross_val_predict
from sklearn.metrics import roc_auc_score
from sklearn.inspection import permutation_importance
from databricks.sdk import WorkspaceClient
from datetime import datetime, timezone

FEATURE_COLS = [
    "recencia_dias", "frequencia_pedidos", "valor_total", "ticket_medio",
    "margem_total", "margem_percentual",
    "intervalo_medio_dias", "desvio_intervalo_dias", "atraso_relativo", "pedidos_ultimos_90d",
    "oportunidades_abertas", "oportunidades_ganhas", "taxa_ganho", "visitas_90d", "conversao_visita",
    "skus_distintos", "categorias_distintas", "marcas_distintas",
    "concentracao_marca_top", "comprou_lancamento",
]
ALVO = "comprou_em_7d"

# COMMAND ----------
treino_pd = spark.table(f"{CATALOG}.gold.features_treino").toPandas()
X = treino_pd[FEATURE_COLS]
y = treino_pd[ALVO].astype(int)

X_treino, X_holdout, y_treino, y_holdout = train_test_split(
    X, y, test_size=0.25, random_state=42, stratify=y
)
taxa_base = float(y.mean())

# COMMAND ----------
# 1) BASELINE — antes de treinar qualquer coisa. Cada regra simples usada
# como se fosse o score, avaliada no MESMO holdout que vai avaliar o modelo.
baselines = {
    "recencia (ligue para quem comprou recentemente)": -X_holdout["recencia_dias"],
    "valor_total (ligue para quem compra mais)": X_holdout["valor_total"],
    "atraso_relativo (ligue para quem está atrasado)": X_holdout["atraso_relativo"].fillna(0),
}
auc_baselines = {nome: roc_auc_score(y_holdout, score) for nome, score in baselines.items()}
melhor_baseline_nome = max(auc_baselines, key=auc_baselines.get)
melhor_baseline_auc = auc_baselines[melhor_baseline_nome]

print(f"{'moeda (referência)':<55} 0.5000")
for nome, auc in auc_baselines.items():
    print(f"{nome:<55} {auc:.4f}")
print(f"\nmelhor baseline: {melhor_baseline_nome} ({melhor_baseline_auc:.4f})")

# COMMAND ----------
# 2) TREINO — HistGradientBoostingClassifier trata NaN nativamente (as
# features de ritmo são NULL de propósito para quem tem um pedido só).
# NÃO usar XGBoost: falha ao carregar de volta no serverless (sklearn 1.6.1).
modelo_avaliacao = HistGradientBoostingClassifier(random_state=42)
modelo_avaliacao.fit(X_treino, y_treino)

# COMMAND ----------
# 3) AS DUAS MÉTRICAS
auc = roc_auc_score(y_holdout, modelo_avaliacao.predict_proba(X_holdout)[:, 1])

# lift_top200 e acertos_top200: out-of-fold sobre TODOS os 2.815 clientes de
# features_treino (não só o holdout de ~700) — a fila real é 200 entre 3.000,
# e um holdout de 700 superestimaria o lift (200 seria 28% da amostra).
skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
oof_proba = cross_val_predict(
    HistGradientBoostingClassifier(random_state=42), X, y, cv=skf, method="predict_proba"
)[:, 1]

ranking = pd.DataFrame({"cliente_id": treino_pd["cliente_id"], "y": y, "score": oof_proba})
top200 = ranking.sort_values("score", ascending=False).head(200)
acertos_top200 = int(top200["y"].sum())
taxa_top200 = acertos_top200 / 200.0
lift_top200 = taxa_top200 / taxa_base

print(f"\nauc (holdout) = {auc:.4f}")
print(f"lift_top200   = {lift_top200:.2f}x")
print(f"acertos_top200 = {acertos_top200} de 200 (taxa base: {100*taxa_base:.2f}%)")

# COMMAND ----------
# 4) IMPORTÂNCIA POR PERMUTAÇÃO, no holdout — dado que o modelo nunca viu.
perm = permutation_importance(
    modelo_avaliacao, X_holdout, y_holdout, n_repeats=5, random_state=42, scoring="roc_auc"
)
importancia = (
    pd.Series(perm.importances_mean, index=FEATURE_COLS)
    .sort_values(ascending=False)
)
print("\ntop 10 features por importância de permutação:")
print(importancia.head(10).to_string())
feature_top1 = importancia.index[0]

# COMMAND ----------
# 5) MLFLOW — a pasta pai do experimento precisa existir ANTES do
# set_experiment, senão o erro é "BAD_REQUEST: For input string: None" e não
# menciona pasta nenhuma.
w = WorkspaceClient()
usuario = w.current_user.me().user_name
pasta_experimentos = f"/Users/{usuario}/rotaperfume_experimentos"
w.workspace.mkdirs(pasta_experimentos)
mlflow.set_experiment(f"{pasta_experimentos}/propensao_compra")
mlflow.set_registry_uri("databricks-uc")

# Modelo final: treinado com TODO features_treino (não só os 75% do split de
# avaliação) — o holdout e o out-of-fold já provaram a performance; o modelo
# que vai para produção usa todo o dado rotulado disponível.
modelo_final = HistGradientBoostingClassifier(random_state=42)
modelo_final.fit(X, y)

with mlflow.start_run(run_name="propensao_compra") as run:
    mlflow.log_param("algoritmo", "HistGradientBoostingClassifier")
    mlflow.log_param("random_state", 42)
    mlflow.log_param("n_features", len(FEATURE_COLS))
    mlflow.log_param("n_clientes_treino", len(X))
    mlflow.log_metric("auc", auc)
    mlflow.log_metric("lift_top200", lift_top200)
    mlflow.log_metric("acertos_top200", acertos_top200)
    mlflow.log_metric("taxa_base", taxa_base)
    for nome, valor in auc_baselines.items():
        mlflow.log_metric(f"auc_baseline_{nome.split(' ')[0]}", valor)

    assinatura = mlflow.models.infer_signature(X, modelo_final.predict_proba(X))
    info = mlflow.sklearn.log_model(
        modelo_final,
        artifact_path="modelo",
        signature=assinatura,
        registered_model_name=REGISTERED_MODEL,
    )

versao = info.registered_model_version
MlflowClient().set_registered_model_alias(REGISTERED_MODEL, "prod", versao)
print(f"\nmodelo registrado: {REGISTERED_MODEL}, versão {versao}, alias @prod")

# COMMAND ----------
# 6) TRÊS TESTES QUE INTERROMPEM A TAREFA — vazamento chega com elogio, não
# com erro, e a única defesa é desconfiar do sucesso demais.
assert auc >= melhor_baseline_auc + 0.05, (
    f"O modelo (auc={auc:.4f}) não ganhou do melhor baseline "
    f"({melhor_baseline_nome}, auc={melhor_baseline_auc:.4f}) por pelo menos 0,05 de AUC."
)
assert auc < 0.99, (
    f"auc={auc:.4f} está bom demais para ser verdade — isso é vazamento de dado, não competência."
)
assert lift_top200 >= 2.5, (
    f"lift_top200={lift_top200:.2f}x está abaixo de 2,5x — a fila não justifica o projeto."
)

# COMMAND ----------
# 7) SCORE — carrega o modelo DE VOLTA do registro (prova que o @prod
# funciona), nunca reaproveita o objeto Python em memória.
modelo_prod = mlflow.sklearn.load_model(f"models:/{REGISTERED_MODEL}@prod")

cliente_pd = spark.table(f"{CATALOG}.gold.features_cliente").toPandas()
# nunca confiar na ordem das colunas da tabela: reordena pela ordem que o
# modelo aprendeu.
X_score = cliente_pd[list(modelo_prod.feature_names_in_)]
cliente_pd["score"] = modelo_prod.predict_proba(X_score)[:, 1]

score_spark = spark.createDataFrame(cliente_pd[["cliente_id", "score"]])
score_spark.createOrReplaceTempView("_score_temp")

score_final = spark.sql(f"""
    SELECT
        CAST(cliente_id AS INT) AS cliente_id,
        score,
        CASE NTILE(4) OVER (ORDER BY score ASC)
            WHEN 1 THEN 'Fria' WHEN 2 THEN 'Morna' WHEN 3 THEN 'Quente' ELSE 'Muito quente'
        END AS faixa,
        DATE'2026-08-31' AS _referencia,
        {versao} AS versao
    FROM _score_temp
""")

score_final.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(
    f"{CATALOG}.gold.score_propensao"
)
spark.sql(f"""
    COMMENT ON TABLE {CATALOG}.gold.score_propensao IS
    'Os clientes pontuados pelo modelo de propensão de compra (@prod), com a faixa de prioridade (Fria/Morna/Quente/Muito quente) para a fila de ligação da semana.'
""")

# COMMAND ----------
# 8) AS MÉTRICAS TAMBÉM VIRAM TABELA — o Genie não lê MLflow.
metricas_pd = pd.DataFrame([{
    "versao": versao,
    "auc": float(auc),
    "lift_top200": float(lift_top200),
    "acertos_top200": acertos_top200,
    "taxa_base": taxa_base,
    "auc_baseline_recencia": float(auc_baselines["recencia (ligue para quem comprou recentemente)"]),
    "auc_baseline_valor_total": float(auc_baselines["valor_total (ligue para quem compra mais)"]),
    "auc_baseline_atraso_relativo": float(auc_baselines["atraso_relativo (ligue para quem está atrasado)"]),
    "feature_top1": feature_top1,
    "_treinado_em": datetime.now(timezone.utc),
}])
spark.createDataFrame(metricas_pd).write.mode("append").option("mergeSchema", "true").saveAsTable(
    f"{CATALOG}.gold.modelo_metricas"
)
spark.sql(f"""
    COMMENT ON TABLE {CATALOG}.gold.modelo_metricas IS
    'Uma linha por treino do modelo de propensão de compra: AUC, lift_top200, acertos_top200, taxa base, o AUC de cada baseline e a feature mais importante — a régua para comparar treinos ao longo do tempo.'
""")

# COMMAND ----------
# calibragem_holdout: faixa, clientes, compraram e taxa de compra no HOLDOUT
# (onde existe rótulo de verdade) — a prova de que o score ordena, sem
# precisar explicar curva ROC para o comercial.
holdout_pd = pd.DataFrame({
    "y": y_holdout.values,
    "score": modelo_avaliacao.predict_proba(X_holdout)[:, 1],
})
holdout_spark = spark.createDataFrame(holdout_pd)
holdout_spark.createOrReplaceTempView("_holdout_temp")

calibragem = spark.sql("""
    WITH faixado AS (
        SELECT y, score,
               CASE NTILE(4) OVER (ORDER BY score ASC)
                   WHEN 1 THEN 'Fria' WHEN 2 THEN 'Morna' WHEN 3 THEN 'Quente' ELSE 'Muito quente'
               END AS faixa
        FROM _holdout_temp
    )
    SELECT
        faixa,
        COUNT(*) AS clientes,
        SUM(y) AS compraram,
        AVG(y) AS taxa_de_compra,
        AVG(score) AS score_medio
    FROM faixado
    GROUP BY faixa
""")

calibragem.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(
    f"{CATALOG}.gold.calibragem_holdout"
)
spark.sql(f"""
    COMMENT ON TABLE {CATALOG}.gold.calibragem_holdout IS
    'Taxa de compra real por faixa de score, medida no holdout — a prova de que o score ordena: a taxa de compra sobe da faixa fria para a muito quente.'
""")

# COMMAND ----------
print("\nresumo:")
print(f"  auc = {auc:.4f} (melhor baseline: {melhor_baseline_auc:.4f})")
print(f"  lift_top200 = {lift_top200:.2f}x, acertos_top200 = {acertos_top200}/200")
print(f"  modelo: {REGISTERED_MODEL} versão {versao} @prod")
