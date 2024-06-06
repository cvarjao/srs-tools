#!/usr/bin/env bash
# oc get projects --all-namespaces -l environment=test -o name

# list of resources
# oc api-resources --namespaced

# -l environment=test

mkdir -p exports
oc get projects --all-namespaces  -o name | while read -r fullName ; do
    shortName=${fullName#*/}
    echo "Exporting $shortName"
    oc -n $shortName get --ignore-not-found=true 'deployments,replicasets,replicationcontrollers,statefulsets,deploymentconfigs,daemonsets,cronjobs,jobs,imagestreams,imagestreamimages,services,persistentvolumeclaims,poddisruptionbudgets,routes,ingresses,networkpolicies' -o json > "./exports/$shortName.json"
    oc create --dry-run=client --filename "./exports/$shortName.json" -o yaml > "./exports/$shortName.yaml"

    oc -n $shortName get --ignore-not-found=true secret -o json | jq 'del(.items[] | .data) | del(.items[] | .metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]) | del(.items[] | .metadata.annotations["openshift.io/token-secret.value"])' > "./exports/$shortName-secrets.json"
    oc create --dry-run=client --filename "./exports/$shortName-secrets.json" -o yaml > "./exports/$shortName-secrets.yaml"
done