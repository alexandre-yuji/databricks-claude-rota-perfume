#!/usr/bin/env bash
# Sobe os CSVs de dados/erp e dados/crm (na raiz do repositório) para o Volume
# bronze.raw do catálogo do projeto. O destino usa o esquema `dbfs:`, mesmo
# sendo um Volume do Unity Catalog — é assim que `databricks fs cp` espera.
set -euo pipefail

PROFILE="${1:?uso: subir-raw.sh <profile> [catalog]}"
CATALOG="${2:-lakehouse_rotaperfume}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DADOS_DIR="$(cd "$SCRIPT_DIR/../../dados" && pwd)"

if [ ! -d "$DADOS_DIR/erp" ] || [ ! -d "$DADOS_DIR/crm" ]; then
  echo "dados/erp e dados/crm não encontrados em $DADOS_DIR" >&2
  exit 1
fi

databricks fs cp --recursive --overwrite \
  "$DADOS_DIR/erp" "dbfs:/Volumes/${CATALOG}/bronze/raw/erp" \
  --profile "$PROFILE"

databricks fs cp --recursive --overwrite \
  "$DADOS_DIR/crm" "dbfs:/Volumes/${CATALOG}/bronze/raw/crm" \
  --profile "$PROFILE"

echo "OK: CSVs enviados para /Volumes/${CATALOG}/bronze/raw/{erp,crm}"
