#!/bin/bash

LIVE="$1"
MERGED="$2"

# ---------------------------------------------------------
# Directory Handler
# ---------------------------------------------------------

if [ -d "$LIVE" ]; then
  EXIT_CODE=0

  for manifest in "$LIVE"/*; do
    filename=$(basename "$manifest")

    if [ -f "$MERGED/$filename" ]; then
      # Recurse
      OUTPUT=$("$0" "$LIVE/$filename" "$MERGED/$filename")
      local_exit_code=$?

      if [ $local_exit_code -ne 0 ]; then
        KIND=$(yq '.kind // "Unknown"' "$MERGED/$filename")
        NAME=$(yq '.metadata.name // "Unknown"' "$MERGED/$filename")

        echo "---------------------------------------------------------"
        echo "Resource: $KIND / $NAME"
        echo "---------------------------------------------------------"
        echo "$OUTPUT"
        echo ""
        EXIT_CODE=1
      fi
    fi
  done

  exit $EXIT_CODE
fi

# ---------------------------------------------------------
# File Handler
# ---------------------------------------------------------

CLEAN_LIVE=$(mktemp)
CLEAN_MERGED=$(mktemp)

yq 'del(.spec.sources[]?.targetRevision)' "$LIVE" >"$CLEAN_LIVE"
yq 'del(.spec.sources[]?.targetRevision)' "$MERGED" >"$CLEAN_MERGED"

dyff between \
  --omit-header \
  --set-exit-code \
  --ignore-order-changes \
  --exclude "/metadata/generation" \
  --exclude "/metadata/resourceVersion" \
  --exclude "/metadata/managedFields" \
  --exclude "/metadata/uid" \
  --exclude "/metadata/creationTimestamp" \
  --exclude "/metadata/annotations/kubectl.kubernetes.io/last-applied-configuration" \
  --exclude "/metadata/annotations/argocd.argoproj.io/tracking-id" \
  --exclude "/status" \
  --exclude "/spec/source/targetRevision" \
  "$CLEAN_LIVE" "$CLEAN_MERGED"

EXIT_CODE=$?

rm -f "$CLEAN_LIVE" "$CLEAN_MERGED"

exit $EXIT_CODE
