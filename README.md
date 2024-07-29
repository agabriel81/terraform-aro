# Terraforming a public Azure Red Hat OpenShift (ARO) cluster, install OpenShift ServiceMesh using OpenShift GitOps with custom CA for ServiceMesh workload by Cert-Manager Operator

Prerequisites and versions:

```
- Terraform (CLI): v1.9.2
- az (CLI): 2.62.0
- oc (CLI): version depend on the cluster version
- custom rootCA certificate and key
```
```
- ARO: 4.13
- OpenShift GitOps: 1.13
- OpenShift Kiali: 1.73
- OpenShift TempoStack: 2.4
- OpenShift ServiceMesh: 2.5
- OpenShift Cert-Manager: 1.12
```

Clone the repository and change to repo directory:
```
$ git clone https://github.com/agabriel81/terraform-aro.git
$ cd terraform-aro/terraform-code
```

Start the Terraform process by passing few variables:
```
export TF_VAR_pull_secret='{"auths":{"arosvc.azurecr.io....'
export TF_VAR_azure_app_name=agabriel-app-aro-neu
export TF_VAR_cluster_domain=agabriel-neu
export TF_VAR_cluster_version=4.13.40
export TF_VAR_location=northeurope
export TF_VAR_resourcegroup_name=aro-neu-agabriel
export TF_VAR_cluster_name=aro-neu-cluster1
export TF_VAR_tm_route=agabriel-aro-tm.trafficmanager.net
```

Deploy all Azure and OpenShift resources using Terraform:

```
terraform init
terraform validate
terraform plan 
terraform apply 
```

After completing the installation, all the Azure requirements will be created, including the StorageAccount and the Container which will be used for the TempoStack configuration.
Let's retrieve ARO credentials, ARO console and ARO API URL:

```
az aro list-credentials --name ${TF_VAR_cluster_name} --resource-group ${TF_VAR_resourcegroup_name}
az aro show --name ${TF_VAR_cluster_name} --resource-group ${TF_VAR_resourcegroup_name} --query "consoleProfile.url" -o tsv
az aro show -g ${TF_VAR_resourcegroup_name} -n ${TF_VAR_cluster_name} --query apiserverProfile.url -o tsv 
oc login $(az aro show -g ${TF_VAR_resourcegroup_name} -n ${TF_VAR_cluster_name} --query apiserverProfile.url -o tsv) -u kubeadmin
```

Access the ARO console and **install the OpenShift GitOps** using the official documentation [1] (version 1.12 at the time of writing).

Create a GitOps application for installating the Cert-Manager, Kiali, Tempo and ServiceMesh Operators, with ServiceMeshControlPlane and ServiceMeshMemberRoll CRDs pointing the `mesh_gitops_cluster` directory of this repository. 

This process requires `cluster-admin` permissions to the `openshift-gitops-argocd-application-controller` ServiceAccount:

```
oc adm policy add-cluster-role-to-user cluster-admin -z openshift-gitops-argocd-application-controller -n openshift-gitops
```
```
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mesh-cluster
  namespace: openshift-gitops
spec:
  destination:
    name: ''
    namespace: ''
    server: 'https://kubernetes.default.svc'
  source:
    path: mesh_gitops_cluster
    repoURL: 'https://github.com/agabriel81/terraform-aro.git'
    targetRevision: mtls_tempo_logs_fw
  sources: []
  project: default
  syncPolicy:
    retry:
      limit: 5
      backoff:
        duration: 15s
        maxDuration: 3m0s
        factor: 2
EOF
```

The GitOps Application resources are configured with "sync-waves" to respect creation order but you can ajust the `retry` option on GitOps for achieving more consistency.

Access the OpenShift GitOps ArgoCD instance and manually sync the `mesh-cluster` Application.

The ServiceMesh Control Plane is configured with MTLS enabled and it will expect a custom CA which needs to be configured via a secret:

```
oc create secret generic cacerts -n istio-system --from-file=<path>/ca-cert.pem \
    --from-file=<path>/ca-key.pem --from-file=<path>/root-cert.pem \
    --from-file=<path>/cert-chain.pem
```

Below a snippet of the MTLS and custom CA configuration in the SMCP (ServiceMeshControlPlane) CRD:

```
  spec:
    security:
      dataPlane:
        mtls: true
    certificateAuthority:
      type: Istiod
      istiod:
        type: PrivateKey
        privateKey:
          rootCADir: /etc/cacerts
```

You may need to restart the ServiceMesh Control Plane component:

```
oc -n istio-system delete pods -l 'app in (istiod,istio-ingressgateway, istio-egressgateway)'
```

Let's configured the TempoStack S3 reference secret.
It's possible to recover the `account_name`, `container` and `account_key` from the Azure console or CLI.

```
oc apply -f - << EOF
apiVersion: v1
kind: Secret
metadata:
  name: azure-storage-secret
  namespace: tracing-system
stringData:
  name: <name>
  container: <Azure container blob name>
  account_name: <Azure storage account name>
  account_key: <key content>
type: Opaque
EOF
```

Then, we can use the same custom CA to create the CA Issuer for the `Cert-Manager` Operator, it will sign the end TLS certificate for OpenShift ServiceMesh IngressGateway.

Create a secret containing your custom CA and then the Cert-Manager resources. Fill the resources based on your environment:

```
oc -n cert-manager create secret generic ca-key-pair --from-file=tls.key=<CA key> --from-file=tls.crt=<CA certificate>
oc create -f ../cert-manager_manifests/clusterissuer.yaml
cp -p ../cert-manager_manifests/certificate.yaml /tmp/certificate.yaml
vi /tmp/certificate.yaml
oc create -f /tmp/certificate.yaml
```

The OpenShift ServiceMesh Istio Gateway is already configured for mounting a custom certificate and it's needed to restart the Istio Gateway pod to mount the newly created custom certificate, signed by your custom CA and saved into the secret `istio-ingressgateway-custom-certs`

Let's integrate Kiali with Tempostack with the following configuration:

```
apiVersion: kiali.io/v1alpha1
kind: Kiali
# ...
spec:
  external_services:
    tracing:
      query_timeout: 30
      enabled: true
      in_cluster_url: 'http://tempo-sample-query-frontend.tracing-system.svc.cluster.local:16685'
      url: '[Tempo query frontend Route url]'
      use_grpc: true
```

Let's continue by deploying some workload into the ServiceMesh using the infamous `bookinfo` application.

We will use Kustomize with an inline patch to configure the Azure Traffic Manager DNS name.


```
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mesh-workload
  namespace: openshift-gitops
spec:
  destination:
    namespace: 'bookinfo'
    server: 'https://kubernetes.default.svc'
  source:
    path: mesh_gitops_workload/base
    repoURL: 'https://github.com/agabriel81/terraform-aro.git'
    targetRevision: mtls_tempo_logs_fw
    kustomize:
      patches:
      - target:
          kind: Route
          name: trafficmanager-route
        patch: |-
          - op: replace
            path: /spec/host
            value: $TF_VAR_tm_route
      - target:
          kind: Gateway
          name: bookinfo-gateway
        patch: |-
          - op: replace
            path: /spec/servers/0/hosts/0
            value: $TF_VAR_tm_route
      - target:
          kind: VirtualService
          name: bookinfo
        patch: |-
          - op: replace
            path: /spec/hosts/0
            value: $TF_VAR_tm_route
  project: default
  sources: []
  syncPolicy:
    retry:
      limit: 5
      backoff:
        duration: 15s
        maxDuration: 3m0s
        factor: 2
EOF
```

Access the OpenShift GitOps ArgoCD instance and sync the `mesh-workload` Application.

The repository will configure a passthrough OpenShift Route for exposing our $TF_VAR_tm_route/productpage endpoint, served by an Azure Traffic Manager component.

The application should expose a certificate signed by our custom CA with a 2h duration.

The certificate will be automatically renewed by the OpenShift Cert-Manager Operator.

And, finally, let's configure our environment to ship logs (both Infrastructure and Application logs) to an Azure Log Analitics Workplace.

1. Set some environment variables:

~~~
export AZR_RESOURCE_LOCATION=northeurope
export AZR_RESOURCE_GROUP=aro-neu-agabriel
# this value must be unique
export AZR_LOG_APP_NAME=$AZR_RESOURCE_GROUP-$AZR_RESOURCE_LOCATION
~~~

2. Create an Azure Log Analytics Workspace:

~~~
az monitor log-analytics workspace create \
 -g $AZR_RESOURCE_GROUP -n $AZR_LOG_APP_NAME \
 -l $AZR_RESOURCE_LOCATION
~~~

3. Create a secret for your Azure Log Analytics Workspace:

~~~
WORKSPACE_ID=$(az monitor log-analytics workspace show \
 -g $AZR_RESOURCE_GROUP -n $AZR_LOG_APP_NAME \
 --query customerId -o tsv)
SHARED_KEY=$(az monitor log-analytics workspace get-shared-keys \
 -g $AZR_RESOURCE_GROUP -n $AZR_LOG_APP_NAME \
 --query primarySharedKey -o tsv)
~~~

4. Create a Secret to hold the shared key:

~~~
oc -n openshift-logging create secret generic azure-monitor-shared-key --from-literal=shared_key=${SHARED_KEY}
~~~

5. Create a ClusterLogging resource, we would need just the Collector components:

~~~
cat <<EOF | oc apply -f -
apiVersion: logging.openshift.io/v1
kind: ClusterLogging
metadata:
  name: instance
  namespace: openshift-logging
spec:
  collection:
    type: vector
    vector: {}
EOF
~~~

6. Create a ClusterLogForwarder resource. This will contain the configuration to forward to Azure Log Analytics Workspace:

~~~
cat <<EOF | oc apply -f -
apiVersion: logging.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: instance
  namespace: openshift-logging
spec:
  outputs:
  - name: azure-monitor-app
    type: azureMonitor
    azureMonitor:
      customerId: $WORKSPACE_ID
      logType: aro_application_logs
    secret:
      name: azure-monitor-shared-key
  - name: azure-monitor-infra
    type: azureMonitor
    azureMonitor:
      customerId: $WORKSPACE_ID
      logType: aro_infrastructure_logs
    secret:
      name: azure-monitor-shared-key
  pipelines:
  - name: app-pipeline
    inputRefs:
    - application
    outputRefs:
    - azure-monitor-app
  - name: infra-pipeline
    inputRefs:
    - infrastructure
    outputRefs:
    - azure-monitor-infra
EOF
~~~

7. Query our new Azure Log Analytics Workspace:

~~~
az monitor log-analytics query -w $WORKSPACE_ID  \
   --analytics-query "aro_infrastructure_logs_CL | take 10" --output tsv
~~~

8. Query our new Azure Log Analytics Workspace with something more complex with the aim to set up an Alarm:

~~~
aro_application_logs_CL
   | where Message contains "DURATION" and TimeGenerated >= ago(15m)
   | parse Message with "DURATION --> " duration
   | project Message, duration, kubernetes_pod_name_s
   | where tolong(duration) > 10 and kubernetes_pod_name_s contains "productpage"
   | count 
~~~

REFERENCE

[1] https://docs.openshift.com/gitops/1.13/understanding_openshift_gitops/about-redhat-openshift-gitops.html

https://registry.terraform.io/providers/hashicorp/azurerm/3.102.0/docs/resources/redhat_openshift_cluster

https://registry.terraform.io/providers/hashicorp/azurerm/3.102.0/docs/resources/traffic_manager_azure_endpoint

https://registry.terraform.io/providers/hashicorp/azurerm/3.102.0/docs/resources/traffic_manager_external_endpoint

https://cloud.redhat.com/experts/aro/clf-to-azure/

https://docs.openshift.com/container-platform/4.13/service_mesh/v2x/ossm-observability.html#ossm-configuring-distr-tracing-tempo_observability

https://docs.openshift.com/container-platform/4.13/observability/distr_tracing/distr_tracing_tempo/distr-tracing-tempo-installing.html

