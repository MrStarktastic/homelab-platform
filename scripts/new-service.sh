#!/usr/bin/env bash
set -euo pipefail

# Service scaffolding generator for homelab-platform
# Usage: ./scripts/new-service.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Homelab Service Generator${NC}"
echo "================================"
echo ""

# Prompt for service details
read -p "Service name (e.g., radarr): " SERVICE_NAME
if [[ -z "$SERVICE_NAME" ]]; then
  echo -e "${RED}Error: Service name is required${NC}"
  exit 1
fi

# Namespace selection
echo ""
echo "Available namespaces:"
echo "  1) media"
echo "  2) operations"
echo "  3) databases"
echo "  4) other (specify)"
read -p "Select namespace [1-4]: " NS_CHOICE

case $NS_CHOICE in
  1) NAMESPACE="media"; CATEGORY="media" ;;
  2) NAMESPACE="operations"; CATEGORY="operations" ;;
  3) NAMESPACE="databases"; CATEGORY="databases" ;;
  4) read -p "Enter namespace: " NAMESPACE; CATEGORY="$NAMESPACE" ;;
  *) echo -e "${RED}Invalid choice${NC}"; exit 1 ;;
esac

read -p "Container image (e.g., lscr.io/linuxserver/radarr:latest): " IMAGE
read -p "Container port (e.g., 7878): " PORT

# Ingress configuration
echo ""
echo -e "${YELLOW}Ingress Configuration${NC}"
read -p "Enable ingress? [Y/n]: " INGRESS_ENABLED
INGRESS_ENABLED=${INGRESS_ENABLED:-Y}

if [[ "$INGRESS_ENABLED" =~ ^[Yy] ]]; then
  read -p "Internal service (behind VPN)? [Y/n]: " INTERNAL
  INTERNAL=${INTERNAL:-Y}
  
  read -p "Require Authentik SSO? [Y/n]: " AUTH
  AUTH=${AUTH:-Y}
  
  read -p "Enable rate limiting? [Y/n]: " RATELIMIT
  RATELIMIT=${RATELIMIT:-Y}
  
  read -p "Custom subdomain (default: $SERVICE_NAME): " SUBDOMAIN
  SUBDOMAIN=${SUBDOMAIN:-$SERVICE_NAME}
  
  INGRESS_BLOCK="
ingress:
  enabled: true
  host: $SUBDOMAIN
  internal: $( [[ "$INTERNAL" =~ ^[Yy] ]] && echo "true" || echo "false" )
  port: $PORT
  auth: $( [[ "$AUTH" =~ ^[Yy] ]] && echo "true" || echo "false" )
  rateLimit: $( [[ "$RATELIMIT" =~ ^[Yy] ]] && echo "true" || echo "false" )"
else
  INGRESS_BLOCK=""
fi

# Persistence configuration
echo ""
echo -e "${YELLOW}Persistence Configuration${NC}"
read -p "Need persistent storage? [Y/n]: " PERSISTENCE
PERSISTENCE=${PERSISTENCE:-Y}

if [[ "$PERSISTENCE" =~ ^[Yy] ]]; then
  read -p "Storage size (default: 5Gi): " STORAGE_SIZE
  STORAGE_SIZE=${STORAGE_SIZE:-5Gi}
  
  PERSISTENCE_BLOCK="
persistence:
  config:
    existingClaim: $SERVICE_NAME-config

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $SERVICE_NAME-config
  namespace: $NAMESPACE
spec:
  accessModes: [\"ReadWriteOnce\"]
  storageClassName: longhorn
  resources:
    requests:
      storage: $STORAGE_SIZE"
else
  PERSISTENCE_BLOCK=""
fi

# Create directory structure
SERVICE_DIR="$REPO_ROOT/apps/services/$CATEGORY/$SERVICE_NAME"
mkdir -p "$SERVICE_DIR/manifests"

# Generate app.yaml
cat > "$SERVICE_DIR/app.yaml" << EOF
name: $SERVICE_NAME
namespace: $NAMESPACE
syncWave: "5"$INGRESS_BLOCK
EOF

# Generate values.yaml
cat > "$SERVICE_DIR/values.yaml" << EOF
controllers:
  main:
    containers:
      main:
        image:
          repository: ${IMAGE%:*}
          tag: ${IMAGE#*:}
        probes:
          liveness:
            enabled: true
          readiness:
            enabled: true

service:
  main:
    controller: main
    ports:
      http:
        port: $PORT
$PERSISTENCE_BLOCK
EOF

# Create empty manifests placeholder if no persistence
if [[ ! "$PERSISTENCE" =~ ^[Yy] ]]; then
  touch "$SERVICE_DIR/manifests/.gitkeep"
else
  # Extract PVC to manifests
  if [[ -n "$PERSISTENCE_BLOCK" ]]; then
    cat > "$SERVICE_DIR/manifests/pvc.yaml" << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $SERVICE_NAME-config
  namespace: $NAMESPACE
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: longhorn
  resources:
    requests:
      storage: $STORAGE_SIZE
EOF
    # Remove PVC from values.yaml (keep only persistence reference)
    cat > "$SERVICE_DIR/values.yaml" << EOF
controllers:
  main:
    containers:
      main:
        image:
          repository: ${IMAGE%:*}
          tag: ${IMAGE#*:}
        probes:
          liveness:
            enabled: true
          readiness:
            enabled: true

service:
  main:
    controller: main
    ports:
      http:
        port: $PORT

persistence:
  config:
    existingClaim: $SERVICE_NAME-config
EOF
  fi
fi

echo ""
echo -e "${GREEN}✅ Service scaffolded successfully!${NC}"
echo ""
echo "Created files:"
echo "  - $SERVICE_DIR/app.yaml"
echo "  - $SERVICE_DIR/values.yaml"
echo "  - $SERVICE_DIR/manifests/"
echo ""

if [[ "$INGRESS_ENABLED" =~ ^[Yy] ]]; then
  if [[ "$INTERNAL" =~ ^[Yy] ]]; then
    echo -e "URL: ${BLUE}https://$SUBDOMAIN.internal.starktastic.net${NC}"
  else
    echo -e "URL: ${BLUE}https://$SUBDOMAIN.starktastic.net${NC}"
  fi
fi

echo ""
echo "Next steps:"
echo "  1. Review generated files"
echo "  2. Adjust values.yaml as needed (env vars, additional mounts, etc.)"
echo "  3. Commit and push to trigger ArgoCD sync"
