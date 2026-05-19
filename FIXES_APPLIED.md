# Korrel8r-Tempo Integration Fixes Applied

## Summary

This document summarizes the fixes applied to resolve the Korrel8r → Tempo integration issues.

## Issues Identified and Fixed

### 1. ✅ OTEL Collector RBAC Permissions (FIXED)

**Problem:**  
The OpenTelemetry Collector's service account (`otel-collector-sidecar`) lacked permissions to read Kubernetes metadata (pods, namespaces, replicasets). This prevented the `k8sattributes` processor from enriching traces with Kubernetes attributes.

**Symptoms:**
```
Error: pods is forbidden: User "system:serviceaccount:opentelemetry:otel-collector-sidecar" cannot list resource "pods"
Error: replicasets.apps is forbidden: User "system:serviceaccount:opentelemetry:otel-collector-sidecar" cannot list resource "replicasets"
```

**Fix Applied:**  
Created a new ClusterRole and ClusterRoleBinding granting the OTEL collector service account permissions to read pods, namespaces, deployments, and replicasets.

**File:** `04_Opentelemetry/01_collector.yaml`

**Changes:**
```yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: otel-collector-k8s-metadata
rules:
  - apiGroups: [""]
    resources:
      - pods
      - namespaces
    verbs:
      - get
      - list
      - watch
  - apiGroups: ["apps"]
    resources:
      - replicasets
      - deployments
    verbs:
      - get
      - list
      - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: otel-collector-k8s-metadata
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: otel-collector-k8s-metadata
subjects:
  - kind: ServiceAccount
    name: otel-collector-sidecar
    namespace: opentelemetry
```

**Result:**  
✅ OTEL collector logs no longer show permission errors  
✅ Traces now include `k8s.namespace.name` attribute  
✅ Tempo queries by namespace now work correctly

### 2. ✅ Korrel8r RBAC Permissions (FIXED)

**Problem:**  
Korrel8r's service account (`troubleshooting-panel-sa`) was not granted access to read traces from Tempo. The `tempostack-traces-reader` ClusterRole was only bound to `system:cluster-admins`.

**Symptoms:**
- Korrel8r could not query Tempo for traces
- Correlation queries returned empty results

**Fix Applied:**  
Added Korrel8r's service account to the `tempostack-traces-reader` ClusterRoleBinding.

**File:** `04_Opentelemetry/01_collector.yaml`

**Changes:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tempostack-traces-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tempostack-traces-reader
subjects:
  - kind: Group
    name: system:cluster-admins
    apiGroup: rbac.authorization.k8s.io
  - kind: ServiceAccount
    name: troubleshooting-panel-sa  # ADDED
    namespace: openshift-operators  # ADDED
```

**Result:**  
✅ Korrel8r pod can now query Tempo directly
✅ Manual trace queries from Korrel8r pod succeed

### 3. ✅ Test Script HTTP/HTTPS Fix (FIXED)

**Problem:**  
The test script was using `http://localhost:3200` to query Tempo, but Tempo requires HTTPS.

**Symptoms:**
```
Client sent an HTTP request to an HTTPS server.
```

**Fix Applied:**  
Updated test script to use the correct Tempo gateway endpoint with HTTPS and authentication.

**File:** `test_korrel8r.sh`

**Changes:**
- Changed from local port-forward approach to direct gateway access
- Added authentication token (`oc whoami -t`)
- Updated endpoint to: `https://tempo-platform-gateway-openshift-tracing.apps.../api/traces/v1/platform/tempo/api/search`
- Changed protocol from `http` to `https`

**Result:**  
✅ Step 2 of test script now successfully queries Tempo  
✅ Finds traces in both ns1-uwl and ns2-uwl namespaces  
✅ No more HTTP/HTTPS errors

## Current Status

### What's Working ✅

1. **OTEL Collector:**
   - ✅ Has proper RBAC permissions
   - ✅ Successfully enriches traces with `k8s.namespace.name`
   - ✅ Sending traces to Tempo via gateway

2. **Tempo:**
   - ✅ Storing traces correctly
   - ✅ Traces searchable by namespace: `{resource.k8s.namespace.name="ns1-uwl"}`
   - ✅ Traces searchable by service name
   - ✅ Gateway authentication working

3. **Korrel8r:**
   - ✅ Has RBAC permission to read traces
   - ✅ Can query Tempo directly from pod

### What's Not Working ❌

1. **Missing `k8s.pod.name` Attribute:**
   - Traces only have `k8s.namespace.name`
   - Missing `k8s.pod.name` and `k8s.pod.ip`
   - **Cause:** OTEL collector in `deployment` mode cannot associate traces with specific pods
   - **Impact:** Pod-level correlation (Pod → Trace) doesn't work

2. **Korrel8r Trace Queries Still Fail:**
   - Direct trace queries: `404 page not found`
   - Graph queries: `{}` (empty results)
   - **Despite:** Korrel8r has RBAC access and can query Tempo directly
   - **Possible causes:**
     - Korrel8r rule configuration issue
     - Korrel8r store configuration issue
     - Bug in Korrel8r trace domain implementation

## Remaining Issues

### Issue #1: Pod-Level Trace Attributes

**Problem:**  
Traces lack pod-level metadata (`k8s.pod.name`, `k8s.pod.ip`) needed for pod-to-trace correlation.

**Root Cause:**  
When the OTEL collector runs in `deployment` mode (centralized), the `k8sattributes` processor can only enrich traces with namespace-level metadata because it doesn't have direct access to the originating pod.

**Potential Solutions:**

1. **Switch to DaemonSet Mode:**
   - Change OTEL collector `mode` from `deployment` to `daemonset`
   - Each node runs its own collector instance
   - Collectors can use pod IP for accurate association
   - **Trade-off:** Higher resource usage (one collector per node)

2. **Use OpenTelemetry Operator Auto-Instrumentation:**
   - Deploy Instrumentation CRD
   - Automatically injects pod metadata via init containers
   - Applications get pod info via environment variables
   - **Trade-off:** Requires pod restarts, more complex setup

3. **Application-Level Injection:**
   - Modify application code to include pod metadata
   - Use Kubernetes Downward API to inject pod info
   - **Trade-off:** Requires application changes, not tested in this reproducer

### Issue #2: Korrel8r Cannot Query Traces

**Problem:**  
Even with proper RBAC and traces having `k8s.namespace.name`, Korrel8r queries return 404 or empty results.

**Evidence:**
- Manual query from Korrel8r pod to Tempo: ✅ Works
- Korrel8r API query for traces: ❌ Returns 404
- Korrel8r graph query (Pod → Trace): ❌ Returns {}

**Potential Causes:**

1. **Korrel8r Store Configuration:**
   - The `tempoStack` URL in korrel8r ConfigMap might be incorrect
   - Current: `https://tempo-platform-gateway.openshift-tracing.svc.cluster.local:8080/api/traces/v1/platform/tempo/api/search`

2. **Korrel8r Rule Issue:**
   - The `PodToTrace` rule expects both namespace AND pod name
   - Only namespace is available in traces
   - Rule might be failing due to missing pod name

3. **Korrel8r Bug:**
   - Possible bug in Korrel8r's trace domain implementation
   - Version 0.9.1 might have issues with Tempo integration

**Next Steps to Debug:**

1. Check Korrel8r logs when making queries
2. Test namespace-only correlation rule
3. Verify Korrel8r trace store initialization
4. Test with Korrel8r debug logging enabled

## Test Results

### Step 2: Tempo Direct Query
```
✓ SUCCESS: Found 10 traces in Tempo by service name
  Tempo is working correctly and storing traces

Traces found in ns1-uwl: 10
Traces found in ns2-uwl: 10
```

### Step 3: Korrel8r Integration
```
Test 1 - Direct trace query: 404 page not found ❌
Test 2 - Graph query (grafana): {} ❌
Test 3 - Graph query (ns1-uwl): {} ❌
```

## Files Modified

1. `04_Opentelemetry/01_collector.yaml` - Added RBAC for OTEL collector and Korrel8r
2. `test_korrel8r.sh` - Fixed HTTP/HTTPS and added Tempo gateway authentication

## Commands to Apply Fixes

```bash
# Apply RBAC fixes
oc apply -f 04_Opentelemetry/01_collector.yaml

# Restart OTEL collector to pick up new permissions
oc delete pod -n opentelemetry -l app.kubernetes.io/name=otel-collector

# Restart Korrel8r to pick up new permissions
oc delete pod -n openshift-operators -l app.kubernetes.io/name=korrel8r

# Run test script
bash test_korrel8r.sh
```

## Verification

```bash
# Verify OTEL collector has no permission errors
oc logs -n opentelemetry -l app.kubernetes.io/name=otel-collector | grep -i "forbidden"
# Should return nothing

# Verify traces have namespace attribute
TOKEN=$(oc whoami -t)
curl -sk -G "https://tempo-platform-gateway-openshift-tracing.apps.../api/traces/v1/platform/tempo/api/search" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode 'q={resource.k8s.namespace.name="ns1-uwl"}' \
  --data-urlencode 'limit=1'
# Should return traces

# Test Korrel8r can access Tempo
oc exec -n openshift-operators deploy/korrel8r -- sh -c \
  'curl -sk "https://tempo-platform-gateway.openshift-tracing.svc.cluster.local:8080/api/traces/v1/platform/tempo/api/search?limit=1" \
   -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"'
# Should return traces
```

## Additional Finding: Operator-Managed Configuration

### Discovery

The Korrel8r ConfigMap is **operator-managed** and cannot be manually modified:

- **Owner:** `UIPlugin/troubleshooting-panel` 
- **Managed by:** `cluster-observability-operator v1.4.0`
- **ConfigMap path:** `openshift-operators/korrel8r`

Any manual changes to the ConfigMap or UIPlugin CR will be reverted by the operator.

### Current Operator-Generated Configuration

```yaml
- domain: trace
  tempoStack: https://tempo-platform-gateway.openshift-tracing.svc.cluster.local:8080/api/traces/v1/platform/tempo/api/search
```

### Potential Issue

The operator is generating a tempoStack URL that includes the full `/tempo/api/search` path. This might be incorrect if Korrel8r expects a base URL and constructs its own API paths.

**Expected URL (hypothesis):**
```yaml
tempoStack: https://tempo-platform-gateway.openshift-tracing.svc.cluster.local:8080/api/traces/v1/platform
```

### Impact

Since the configuration is operator-managed, this issue can only be resolved by:

1. **Updating the cluster-observability-operator** to generate the correct URL format
2. **Fixing Korrel8r** to handle the URL format the operator provides
3. **Reporting this as a bug** to the appropriate project (operator or Korrel8r)

### Evidence

- Korrel8r pod can query Tempo directly: ✅
- Korrel8r has proper RBAC: ✅  
- Traces have required attributes: ✅
- Korrel8r API queries return 404: ❌

This suggests a configuration mismatch between what the operator generates and what Korrel8r expects.
