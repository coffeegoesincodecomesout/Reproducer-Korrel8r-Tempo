#!/bin/bash
oc create sa collector -n openshift-logging
oc adm policy add-cluster-role-to-user collect-application-logs system:serviceaccount:openshift-logging:collector
oc adm policy add-cluster-role-to-user collect-infrastructure-logs system:serviceaccount:openshift-logging:collector
oc adm policy add-cluster-role-to-user cluster-logging-write-application-logs system:serviceaccount:openshift-logging:collector 
oc adm policy add-cluster-role-to-user cluster-logging-write-infrastructure-logs system:serviceaccount:openshift-logging:collector

#optional roles for audit logs
#oc adm policy add-cluster-role-to-user cluster-logging-write-audit-logs system:serviceaccount:openshift-logging:collector
#oc adm policy add-cluster-role-to-user collect-audit-logs system:serviceaccount:openshift-logging:collector
