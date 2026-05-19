#!/bin/bash
set -euo pipefail

# Wait for ODF to provision the ObjectBucketClaim resources (configmap + secret)
NAMESPACE="openshift-logging"
CONFIGMAP="loki-bucket-odf"
SECRET="loki-bucket-odf"
TIMEOUT=300
INTERVAL=10
elapsed=0

echo "Waiting for configmap '$CONFIGMAP' and secret '$SECRET' in '$NAMESPACE'..."
until oc get configmap "$CONFIGMAP" -n "$NAMESPACE" &>/dev/null && \
      oc get secret    "$SECRET"    -n "$NAMESPACE" &>/dev/null; do
  if [ $elapsed -ge $TIMEOUT ]; then
    echo "ERROR: Timed out waiting for OBC resources in '$NAMESPACE'" >&2
    exit 1
  fi
  echo "  Not ready yet (${elapsed}s elapsed)..."
  sleep $INTERVAL
  elapsed=$((elapsed + INTERVAL))
done
echo "  OBC resources ready."

BUCKET_HOST=$(oc get -n openshift-logging configmap loki-bucket-odf -o jsonpath='{.data.BUCKET_HOST}')
BUCKET_NAME=$(oc get -n openshift-logging configmap loki-bucket-odf -o jsonpath='{.data.BUCKET_NAME}')
BUCKET_PORT=$(oc get -n openshift-logging configmap loki-bucket-odf -o jsonpath='{.data.BUCKET_PORT}')
ACCESS_KEY_ID=$(oc get -n openshift-logging secret loki-bucket-odf -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
SECRET_ACCESS_KEY=$(oc get -n openshift-logging secret loki-bucket-odf -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
output=$(oc create secret generic logging-loki-odf -n openshift-logging \
   --from-literal=access_key_id=${ACCESS_KEY_ID} \
   --from-literal=access_key_secret=${SECRET_ACCESS_KEY} \
   --from-literal=bucketnames=${BUCKET_NAME} \
   --from-literal=endpoint=https://${BUCKET_HOST}:${BUCKET_PORT} 2>&1) || {
  if echo "$output" | grep -q "already exists"; then
    echo "  Secret 'logging-loki-odf' already exists — skipping"
  else
    echo "$output" >&2
    exit 1
  fi
}
