#!/usr/bin/env bash
# Cria o catálogo do projeto por fora do bundle.
#
# POR QUE: esta conta usa Default Storage, e nessa configuração a API do Unity
# Catalog RECUSA criar catálogo sem uma MANAGED LOCATION explícita:
#   Error: Metastore storage root URL does not exist.
#          Default Storage is enabled in your account. (400 INVALID_STATE)
# O comando SQL (CREATE CATALOG) funciona porque usa o caminho de storage
# padrão do metastore. Depois que o catálogo existe, `bundle deploy` cria
# schemas e volume normalmente (resources/catalogo.yml).
set -euo pipefail

PROFILE="${1:?uso: criar-catalogo.sh <profile> [catalog]}"
CATALOG="${2:-lakehouse_rotaperfume}"

databricks experimental aitools tools query \
  "CREATE CATALOG IF NOT EXISTS ${CATALOG} COMMENT 'Catálogo do projeto rota-perfume — distribuidora B2B de perfumes (ERP + CRM).'" \
  --profile "$PROFILE"
