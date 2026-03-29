#!/usr/bin/env bash
set -euo pipefail

RESOURCE_GROUP="${1:?Usage: $0 <resource-group>}"

echo "==> Looking up resources in $RESOURCE_GROUP..."

ACR_NAME=$(az acr list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)
if [ -z "$ACR_NAME" ]; then
  echo "Error: No Azure Container Registry found in $RESOURCE_GROUP" >&2
  exit 1
fi

ENV_NAME=$(az containerapp env list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)
if [ -z "$ENV_NAME" ]; then
  echo "Error: No Container Apps environment found in $RESOURCE_GROUP" >&2
  exit 1
fi

API_FQDN=$(az containerapp show --name claims-processing-api --resource-group "$RESOURCE_GROUP" \
  --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null || true)
if [ -z "$API_FQDN" ]; then
  echo "Error: claims-processing-api not found in $RESOURCE_GROUP" >&2
  exit 1
fi

echo "    ACR:         $ACR_NAME"
echo "    Environment: $ENV_NAME"
echo "    API FQDN:    $API_FQDN"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Building image in ACR..."
az acr build \
  --registry "$ACR_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --image claims-ui:latest \
  "$SCRIPT_DIR" \
  --no-logs

echo "==> Deploying to Container Apps..."
az containerapp create \
  --name claims-processing-ui \
  --resource-group "$RESOURCE_GROUP" \
  --environment "$ENV_NAME" \
  --image "${ACR_NAME}.azurecr.io/claims-ui:latest" \
  --registry-server "${ACR_NAME}.azurecr.io" \
  --target-port 8501 \
  --ingress external \
  --env-vars "API_URL=https://${API_FQDN}" \
  --query "properties.configuration.ingress.fqdn" \
  -o tsv

UI_FQDN=$(az containerapp show --name claims-processing-ui --resource-group "$RESOURCE_GROUP" \
  --query "properties.configuration.ingress.fqdn" -o tsv)

echo ""
echo "==> Streamlit UI deployed successfully!"
echo "    https://${UI_FQDN}"
