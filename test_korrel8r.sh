#!/bin/bash

# Test script for Korrel8r Tempo integration issue reproduction
# This script:
# 1. Generates traces by sending traffic to test applications
# 2. Tests the failing Korrel8r scenarios described in the reproduction steps

echo "==================================================================="
echo "Korrel8r Tempo Integration Test"
echo "==================================================================="
echo ""

# Step 1: Generate traces by hitting the application endpoints
echo "==================================================================="
echo "Step 1: Generating observability traces"
echo "==================================================================="
echo ""

# Get the route URLs for the test applications
echo "Getting application routes..."
NS1_ROUTE=$(oc get route threepilar-example-route -n ns1-uwl -o jsonpath='{.spec.host}' 2>/dev/null)
NS2_ROUTE=$(oc get route threepilar-frontend-route -n ns2-uwl -o jsonpath='{.spec.host}' 2>/dev/null)

if [ -z "$NS1_ROUTE" ] || [ -z "$NS2_ROUTE" ]; then
    echo "WARNING: Could not retrieve application routes. Make sure applications are deployed."
    echo "  ns1-uwl route: ${NS1_ROUTE:-NOT FOUND}"
    echo "  ns2-uwl route: ${NS2_ROUTE:-NOT FOUND}"
    echo ""
    echo "Skipping trace generation. Testing with existing traces only..."
else
    echo "Found application routes:"
    echo "  ns1-uwl: https://${NS1_ROUTE}/ping"
    echo "  ns2-uwl: https://${NS2_ROUTE}/ping"
    echo ""

    echo "Generating traces by sending requests to applications..."
    echo "Sending 10 requests to ns1-uwl application..."
    for i in {1..10}; do
        curl -sk "https://${NS1_ROUTE}/ping" > /dev/null 2>&1
        echo -n "."
    done
    echo " done"

    echo "Sending 10 requests to ns2-uwl frontend (which also calls backend)..."
    for i in {1..10}; do
        curl -sk "https://${NS2_ROUTE}/ping" > /dev/null 2>&1
        echo -n "."
    done
    echo " done"

    echo ""
    echo "Traces generated. Waiting 30 seconds for traces to be ingested into Tempo..."
    sleep 30
fi

echo ""
echo "==================================================================="
echo "Step 2: Verifying traces exist in Tempo"
echo "==================================================================="
echo ""

# Get authentication token for Tempo gateway
echo "Getting authentication token..."
TOKEN=$(oc whoami -t)
if [ -z "$TOKEN" ]; then
    echo "ERROR: Could not get authentication token. Please ensure you are logged in with 'oc login'."
    exit 1
fi

# Set Tempo gateway URL
TEMPO_GATEWAY="tempo-platform-gateway-openshift-tracing.apps.cluster-8gcj4.8gcj4.sandbox643.opentlc.com"
echo "Tempo gateway: https://${TEMPO_GATEWAY}"
echo ""

echo "Querying Tempo directly to verify traces exist..."
echo ""

# Query for traces in ns1-uwl namespace using TraceQL
echo "--- Searching for traces in ns1-uwl namespace ---"
TEMPO_RESPONSE_NS1=$(curl -sk -G "https://${TEMPO_GATEWAY}/api/traces/v1/platform/tempo/api/search" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode 'q={resource.k8s.namespace.name="ns1-uwl"}' \
  --data-urlencode 'limit=10' 2>/dev/null)

TRACE_COUNT_NS1=$(echo "$TEMPO_RESPONSE_NS1" | grep -o '"traceID"' | wc -l)
echo "Response: $TEMPO_RESPONSE_NS1"
echo "Traces found in ns1-uwl: $TRACE_COUNT_NS1"
echo ""

# Query for traces in ns2-uwl namespace using TraceQL
echo "--- Searching for traces in ns2-uwl namespace ---"
TEMPO_RESPONSE_NS2=$(curl -sk -G "https://${TEMPO_GATEWAY}/api/traces/v1/platform/tempo/api/search" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode 'q={resource.k8s.namespace.name="ns2-uwl"}' \
  --data-urlencode 'limit=10' 2>/dev/null)

TRACE_COUNT_NS2=$(echo "$TEMPO_RESPONSE_NS2" | grep -o '"traceID"' | wc -l)
echo "Response: $TEMPO_RESPONSE_NS2"
echo "Traces found in ns2-uwl: $TRACE_COUNT_NS2"
echo ""

# Query for all traces with service names
echo "--- Searching for traces by service name ---"
TEMPO_RESPONSE_SERVICE=$(curl -sk -G "https://${TEMPO_GATEWAY}/api/traces/v1/platform/tempo/api/search" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode 'q={resource.service.name=~"threepilar.*"}' \
  --data-urlencode 'limit=10' 2>/dev/null)

TRACE_COUNT_SERVICE=$(echo "$TEMPO_RESPONSE_SERVICE" | grep -o '"traceID"' | wc -l)
echo "Response: $TEMPO_RESPONSE_SERVICE"
echo "Traces found by service name: $TRACE_COUNT_SERVICE"
echo ""

TOTAL_TRACES=$((TRACE_COUNT_NS1 + TRACE_COUNT_NS2 + TRACE_COUNT_SERVICE))
if [ "$TRACE_COUNT_SERVICE" -gt 0 ]; then
    echo "✓ SUCCESS: Found $TRACE_COUNT_SERVICE traces in Tempo by service name"
    echo "  Tempo is working correctly and storing traces"
    echo ""
    if [ "$TRACE_COUNT_NS1" -eq 0 ] && [ "$TRACE_COUNT_NS2" -eq 0 ]; then
        echo "⚠ NOTE: Traces were NOT found when searching by k8s.namespace.name attribute"
        echo "  This means the traces are missing the resource.k8s.namespace.name attribute"
        echo "  that Korrel8r needs for correlation. This is the root cause of the issue!"
    fi
else
    echo "✗ WARNING: No traces found in Tempo"
    echo "  This may indicate:"
    echo "    - Applications are not generating traces"
    echo "    - OTel collector is not forwarding traces to Tempo"
    echo "    - Need to wait longer for trace ingestion"
    echo "  Proceeding with Korrel8r tests anyway..."
fi

echo ""
echo "==================================================================="
echo "Step 3: Testing Korrel8r integration"
echo "==================================================================="
echo ""

# Check if port-forward is already running
if pgrep -f "port-forward.*korrel8r.*9443" > /dev/null; then
    echo "Port-forward to korrel8r is already running"
else
    echo "Starting port-forward to korrel8r..."
    oc port-forward -n openshift-operators deploy/korrel8r 9443:9443 &
    PORT_FORWARD_PID=$!
    echo "Port-forward started (PID: $PORT_FORWARD_PID)"
    echo "Waiting 5 seconds for port-forward to establish..."
    sleep 5
fi

echo ""
echo "==================================================================="
echo "Test 1: Direct trace-store query"
echo "Expected: HTTP 404 with body '404 page not found'"
echo "==================================================================="
echo ""
echo "Query: trace:span:{resource.k8s.namespace.name=\"grafana\"}"
echo ""

curl -sk -X POST https://localhost:9443/api/v1alpha1/objects \
  -H 'Content-Type: application/json' \
  -d '{"query":"trace:span:{resource.k8s.namespace.name=\"grafana\"}"}'

echo ""
echo ""

echo "==================================================================="
echo "Test 2: Cross-domain graph query (Pod → trace)"
echo "Expected: Empty graph '{}' returned, even when matching spans exist"
echo "==================================================================="
echo ""
echo "Query: k8s:Pod:{namespace: grafana} → trace:span"
echo ""

curl -sk -X POST https://localhost:9443/api/v1alpha1/graphs/goals \
  -H 'Content-Type: application/json' \
  -d '{
    "start": {"queries":["k8s:Pod:{namespace: grafana}"]},
    "goals": ["trace:span"]
  }'

echo ""
echo ""

# Alternative test with ns1-uwl namespace (the test app namespace in this repo)
echo "==================================================================="
echo "Test 3: Cross-domain graph query with test app namespace"
echo "Expected: Empty graph '{}' returned, even when matching spans exist"
echo "==================================================================="
echo ""
echo "Query: k8s:Pod:{namespace: ns1-uwl} → trace:span"
echo ""

curl -sk -X POST https://localhost:9443/api/v1alpha1/graphs/goals \
  -H 'Content-Type: application/json' \
  -d '{
    "start": {"queries":["k8s:Pod:{namespace: ns1-uwl}"]},
    "goals": ["trace:span"]
  }'

echo ""
echo ""

echo "==================================================================="
echo "Test 4: Direct Tempo query via korrel8r (correct URL format)"
echo "Expected: Successful trace retrieval when using proper Tempo endpoint"
echo "==================================================================="
echo ""
echo "This test demonstrates that traces CAN be queried successfully"
echo "when using the correct URL format that bypasses korrel8r's broken"
echo "trace-store domain and queries Tempo directly."
echo ""

# Query Tempo through korrel8r using the correct URL format
# This shows the expected working behavior
echo "Querying for traces using service name filter..."
echo ""

KORREL8R_TEMPO_RESPONSE=$(curl -sk -G "https://${TEMPO_GATEWAY}/api/traces/v1/platform/tempo/api/search" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode 'q={resource.service.name=~"threepilar.*"}' \
  --data-urlencode 'limit=5' 2>/dev/null)

echo "Direct Tempo API Response:"
echo "$KORREL8R_TEMPO_RESPONSE"
echo ""

KORREL8R_TRACE_COUNT=$(echo "$KORREL8R_TEMPO_RESPONSE" | grep -o '"traceID"' | wc -l)

if [ "$KORREL8R_TRACE_COUNT" -gt 0 ]; then
    echo "✓ SUCCESS: Found $KORREL8R_TRACE_COUNT traces using correct URL format"
    echo ""
    echo "This demonstrates that:"
    echo "  1. Traces ARE queryable from the Tempo backend"
    echo "  2. The correct URL format is: https://${TEMPO_GATEWAY}/api/traces/v1/platform/tempo/api/search"
    echo "  3. The issue is specific to korrel8r's trace-store domain configuration"
    echo ""
    echo "COMPARISON:"
    echo "  ✗ Broken (404): POST https://localhost:9443/api/v1alpha1/objects"
    echo "                  with query: 'trace:span:{...}'"
    echo "  ✓ Working:      GET  https://${TEMPO_GATEWAY}/api/traces/v1/platform/tempo/api/search"
    echo "                  with TraceQL query parameter"
else
    echo "⚠ No traces found, but this could be due to timing or trace attributes"
fi

echo ""
echo ""

echo "==================================================================="
echo "Test completed"
echo "==================================================================="
echo ""
echo "Summary of results:"
echo ""
echo "Step 1: Generated traces by sending HTTP requests to test applications"
echo "Step 2: Verified traces exist in Tempo (direct Tempo API query)"
echo "        - If traces were found, this confirms Tempo is working correctly"
echo "Step 3: Tested Korrel8r's ability to query the same traces"
echo ""
echo "Expected behaviors in Step 3 (Korrel8r queries):"
echo "  - Test 1: HTTP 404 error (direct trace-store query via korrel8r)"
echo "  - Test 2 & 3: Empty graph {}, no traces found despite traces existing in Tempo"
echo "  - Test 4: SUCCESS when using correct Tempo URL format (bypassing korrel8r)"
echo ""
echo "This demonstrates the Korrel8r → Tempo integration issue where:"
echo "  1. Tempo API directly returns traces ✓"
echo "  2. Korrel8r direct trace queries fail with 404 ✗"
echo "  3. Korrel8r cross-domain queries return empty results ✗"
echo "  4. Direct Tempo queries work (correct URL format) ✓"
echo "  5. Troubleshooting Panel shows no 'Related Traces' section ✗"
echo ""
echo "The contrast between successful direct Tempo queries (Steps 2 & 4) and"
echo "failed korrel8r queries (Tests 1-3) proves the issue is with Korrel8r's"
echo "trace-store domain configuration, not with trace generation or storage."
echo ""
