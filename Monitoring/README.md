# Installing Prometheus in a Kubernetes Cluster created by AKS-HCI
This topic describes how to install [Prometheus](https://prometheus.io/) in a Kubernetes cluster created by AKS-HCI using Helm. Prometheus is
an open-source monitoring system with a dimensional data model, flexible query language, efficient time series database and modern alerting approach. See https://prometheus.io/ for reference.

There are multiple installation techniques for various scenarios. The goal of this guide is to focus on monitoring a single Kubernetes cluster. The optimal approach is using the Helm package manager to deploy Prometheus utilizing the Operator Framework. Reference: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack

## Prerequisites:
Before performing the procedure in this topic, you must have installed and configured the following:

* A Kubernetes cluster created with AKS-HCI with at least 1 master and 1 Linux worker nodes.
* Install Helm V3 and add it to system PATH. 
  Helm is the package manager for Kubernetes that runs on a local machine with `kubectl` access to the Kubernetes cluster. The installation process for Prometheus and the Certificate Manager leverage Helm charts available on the public Helm repo. Please review the steps on your own recommended way of [Installing Helm](https://helm.sh/docs/using_helm/#installing-helm).
  Download and install the [Helm CLI](https://github.com/helm/helm/releases/tag/v3.3.0) on the local machine that will be interfacing with the Kubernetes cluster. 

* Install kubectl.exe and add it to system PATH.
  

# Easy steps to setup monitoring to use local port-forward to access Grafana:
***Note: Below script configure 100Gi storage for prometheus instance and 20Gi for grafana.***
* Download [Setup-Monitoring.ps1](Setup-Monitoring.ps1) script and save it to local machine.
* Open a new powershell Admin Windows and run below command
  ```
  .\Setup-Monitoring.ps1 -installMonitoring $true -kubeconfigFile <target cluster kubeconfig file path> -namespace <namespace where monitoring-stack will be installed> -grafanaAdminPasswd <admin password to access Grafana> -forwardingLocalPort <localhost port to access Grafana>

  e.g. 
  .\Setup-Monitoring.ps1 -installMonitoring $true -kubeconfigFile C:\wssd\mycluster-kubeconfig -namespace monitoring -grafanaAdminPasswd AKS -forwardingLocalPort 3000
  ```

Enter the Grafana dashboard with Username/Password: admin/AKS
![grafana-02](images/grafana-02.jpg)


View the list of available dashboards.
![grafana-04](images/grafana-04.jpg)

Click on a dashboard to see the Grafana view with statistics being collected by Prometheus.
![grafana-05](images/grafana-05.jpg)

***Note: Please run below powershell command to restart Grafana port-forward If it is terminated for any reason.***

```
start-process -FilePath "kubectl.exe" -ArgumentList "--kubeconfig=<target cluster kubeconfig file path> port-forward svc/prometheus-grafana <forwardingLocalPort>:80 -n=<namespace>"
e.g.
start-process -FilePath "kubectl.exe" -ArgumentList "--kubeconfig=C:\wssd\mycluster-kubeconfig port-forward svc/prometheus-grafana 3000:80 -n=monitoring"
```
## Steps to uninstall monitoring:

* Run below command to uninstall monitoring stack.
  ```
  .\Setup-Monitoring.ps1 -uninstallMonitoring $true -kubeconfigFile <target cluster kubeconfig file path> -namespace <namespace where monitoring-stack will be installed>

  e.g. 
  .\Setup-Monitoring.ps1 -uninstallMonitoring $true -kubeconfigFile C:\wssd\mycluster-kubeconfig -namespace monitoring
  ```

### Windows Monitoring ###

Follow below steps to configure the Windows monitoring.
* Create windows-exporter container image from DockerFile present here [DockerFile](windows/DockerFile) and push it to your repository.
* Download [windows-exporter-daemonset.yaml](windows/windows-exporter-daemonset.yaml) and update the image name with the one you created above and apply it.
```
kubectl.exe --kubeconfig=<target cluster kubeconfig> apply -f windows-exporter-daemonset.yaml
```
* Create a file values.yaml as below
```
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: wmi-exporter
        kubernetes_sd_configs:
        - role: node
        scheme: http

        relabel_configs:
        - action: labelmap
          regex: __meta_kubernetes_node_label_(.+) 
          # Use wmi exporter 9182 port
        - source_labels: [__address__]
          regex: '(.*):10250'
          replacement: '${1}:9182'
          target_label: __address__   
```
and update the prometheus helm release.
```
helm --kubeconfig <target cluster kubeconfig> upgrade --reuse-values -f .\values.yaml prometheus prometheus-community/kube-prometheus-stack -n=monitoring
```
* Apply the file [windows-rules-dashboards.yaml](windows/windows-rules-dashboards.yaml) to the cluster
```
kubectl.exe --kubeconfig=<target cluster kubeconfig> apply -f windows-rules-dashboards.yaml
```
* Reload the Grafana URL and you should be able to see the Windows monitoring dasboards.

***Note: Windows Monitoring steps above assume that you have installed the prometheus in monitoring namespace. If this is not the case then please update the correct namespace in windows-rules-dashboards.yaml and windows-exporter-daemonset.yaml before applying them..***

### Certs and Keys Monitoring

For clusters with etcd secret encryption enabled, follow the below steps to configure monitoring.
* Download the necessary [values.yaml](certs-and-keys/values.yaml), and update the prometheus helm release
```
helm --kubeconfig <target cluster kubeconfig> upgrade --reuse-values -f .\values.yaml prometheus prometheus-community/kube-prometheus-stack -n=<prometheus namespace>
```
* Import [certs-and-keys-dashboard.json](certs-and-keys/certs-and-keys-dashboard.json) into Grafana  
  * Instructions on importing dashboards can be found in [Grafana documentation](https://grafana.com/docs/grafana/latest/dashboards/export-import/)

# Detailed steps to setup monitoring to use ingress controller to access Grafana:
## Certificate Manager

The cert-manager is a native Kubernetes certificate management controller.  The cert-manager can help with issuing certificates and will ensure certificates are valid and up to date; it will also attempt to renew certificates at a configured time before expiry. The documentation is available [here](https://docs.cert-manager.io/en/latest/). We will be following the [Helm based installation](https://docs.cert-manager.io/en/latest/getting-started/install/kubernetes.html#installing-with-helm). At the time of this writing, v0.16.1 is the latest stable.


  1. Create the namespace for cert-manager

  ```
kubectl create namespace cert-manager
  ```

  2. Add the Jetstack Helm repository

  ```
helm repo add jetstack https://charts.jetstack.io
  ```

  3. Update your local Helm chart repository cache

  ```
helm repo update
  ```

  4. Deploy the cert-manager Helm chart

  ```
# Helm v3+
helm install cert-manager jetstack/cert-manager --namespace cert-manager --version v0.16.1 --set installCRDs=true --set nodeSelector."kubernetes\.io/os"=linux --set cainjector.nodeSelector."kubernetes\.io/os"=linux --set webhook.nodeSelector."kubernetes\.io/os"=linux
  ```

  5. Promethus components will be deployed in the monitoring namespace. Pre-create a monitoring namespace:

  ```
kubectl create namespace monitoring
  ```

  6. Generate cert and upload as secret into your AKS-HCI cluster (scoped to a namespace).
     Install openssl for windows from here https://slproweb.com/products/Win32OpenSSL.html.  

    1. Generate a signing key pair

            openssl genrsa -out ca.key 2048

    2. Create a self signed Certificate

            $COMMON_NAME="example.com"
            openssl req -x509 -new -nodes -key ca.key -subj "/CN=${COMMON_NAME}" -days 3650 -reqexts v3_req -extensions v3_ca -out ca.crt

    3. Store cert in a Kubernetes Secret resource.

            kubectl create secret tls ca-key-pair --cert=ca.crt --key=ca.key --namespace=monitoring

  **Note**: Issuer can be namespace scoped (`kind: Issuer`) or cluster scoped (`kind: ClusterIssuer`). We will use namespace scoped issuer in this example.

  **Note: The sample above is provided as an example only.  You should follow your enterprise processes for Certificate management or adapt to use a CA like [Let's Encrypt](https://docs.cert-manager.io/en/latest/tasks/issuers/setup-acme/index.html).**   

  4. To create a certificate issuer, copy / paste the YAML sample below in a file named `issuer.yaml`.

```yaml
apiVersion: cert-manager.io/v1alpha2
kind: Issuer
metadata:
  name: ca-issuer
  namespace: monitoring
spec:
  ca:
    secretName: ca-key-pair
```

  5. Apply the configuration with:

  ```
kubectl create -f issuer.yaml
  ```

  7. In order to obtain a Certificate, create a Certificate resource in the same namespace as the Issuer.  In this example, the Issuer is a namespaced resource.  To obtain a signed Certificate, copy / paste the following into a file named `desired-cert.yaml`.

```yaml
apiVersion: cert-manager.io/v1alpha2
kind: Certificate
metadata:
  name: example-com
  namespace: monitoring
spec:
  secretName: example-com-tls
  issuerRef:
    name: ca-issuer
    # We can reference ClusterIssuers by changing the kind here.
    # The default value is Issuer (i.e. a locally namespaced Issuer)
    kind: Issuer
  commonName: example.com
  organization:
  - Microsoft
  dnsNames:
  - example.com
```

  * Apply the configuration with:

         kubectl create -f desired-cert.yaml

**Note**: The sample above is provided as an example only.  You should follow your enterprise processes for Certificate management. 

**Note**: `secretName` in the certificate request will be referenced by the ingress controller.

### Certificate Manager Validation

Verify your installation was successful:

```
kubectl get pod -n cert-manager
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-578fc6ff6-ss2r4               1/1     Running   0          39s
cert-manager-cainjector-5975fd64c5-gbtn7   1/1     Running   0          39s
cert-manager-webhook-5c7f95fd44-r7lcr      1/1     Running   0          39s
```

Confirm self-signed and signed certificates are loaded in key store:

```
kubectl get secret -n monitoring | findstr "kubernetes.io/tls"
ca-key-pair                                        kubernetes.io/tls                     2         1d
example-com-tls                                    kubernetes.io/tls                     3         1d
root@cli-vm:~/app#
```

Retrieve the signed TLS key pair:

```
kubectl get secret example-com-tls -n monitoring -o yaml
```

## Prometheus
##### ETCD Metrics scrapping
By default Prometheus does not scrap the etcd metrics because etcd metrics are exposed on the secure endpoint and Prometheus is not configured with etcd client certificate to access the etcd secure endpoint.
Etcd client certificate and etcd CA can be retrived from the api-server pod. Please use below steps to create the kubernetes secret that contains the etcd CA/cert/key to scrap the etcd endpoint.

a) Get the Api-server pod name.

```
  $podname=$(kubectl get pods -o=jsonpath='{.items[0].metadata.name}' -l component=kube-apiserver -n kube-system)
```
b) Below steps will get the ETCD CA/client cert/client key and will generate the base64 encoding to store in secret.
```
kubectl exec $podname -n=kube-system -- cat /etc/kubernetes/pki/etcd/ca.crt > ca.crt
kubectl exec $podname -nkube-system -- cat /etc/kubernetes/pki/apiserver-etcd-client.crt > client.crt
kubectl exec $podname -nkube-system -- cat /etc/kubernetes/pki/apiserver-etcd-client.key > client.key

$caContent = get-content .\ca.crt -Encoding UTF8 -Raw
$caContentBytes = [System.Text.Encoding]::UTF8.GetBytes($caContent)
$caContentEncoded = [System.Convert]::ToBase64String($caContentBytes)

$clientCertContent = get-content .\client.crt -Encoding UTF8 -Raw
$clientCertContentBytes = [System.Text.Encoding]::UTF8.GetBytes($clientCertContent)
$clientCertContentEncoded = [System.Convert]::ToBase64String($clientCertContentBytes)

$clientKeyContent = get-content .\client.key -Encoding UTF8 -Raw
$clientKeyContentBytes = [System.Text.Encoding]::UTF8.GetBytes($clientKeyContent)
$clientKeyContentEncoded = [System.Convert]::ToBase64String($clientKeyContentBytes)

rm .\ca.crt, .\client.crt, .\client.key
```
c) Copy the following into a file and named `etcd-cert.yaml` and update the ca.crt, client.crt and client.key as directed.
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: etcd-certs
  namespace: monitoring
data:
  ca.crt: < CONTENT OF $caContentEncoded >
  client.crt: < CONTENT OF $clientCertContentEncoded >
  client.key: < CONTENT OF $clientKeyContentEncoded >
```
d) Apply the 'etcd-cert.yaml'
```
kubectl create -f etcd-cert.yaml
```

### Pre-Configuration

To leverage persistent volumes for metrics and expose the Grafana service to external users using an ingress controller, with SSL termination for added security, the Prometheus deployment needs to be customized. cert-manager will issue and maintain the certificate required by the ingress controller. Core Prometheus services will not be externally accessible unless explicit port forwarding is enabled. Copy the following into a file and named `custom.yaml`:

```yaml
alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 20Gi

prometheus:
  prometheusSpec:
    nodeSelector:
      kubernetes.io/os: linux
    secrets: 
    - etcd-certs
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 100Gi

grafana:
  nodeSelector:
    kubernetes.io/os: linux

  adminPassword: "AKS"   ## change it accordingly.
  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: nginx
      certmanager.k8s.io/issuer: ca-issuer
      kubernetes.io/tls-acme: "true"
    hosts:
      - grafana.test.example.com
    tls:
      - secretName: example-com-tls
        hosts:
          - grafana.test.example.com
  persistence:
    enabled: true
    accessModes: ["ReadWriteOnce"]
    size: 20Gi

prometheusOperator:
  nodeSelector:
    kubernetes.io/os: linux

  admissionWebhooks:
    patch:
      nodeSelector:
        kubernetes.io/os: linux

alertmanager:
  alertmanagerSpec:
    nodeSelector:
      kubernetes.io/os: linux

kube-state-metrics:
  nodeSelector:
    kubernetes.io/os: linux

prometheus-node-exporter:
  nodeSelector:
    kubernetes.io/os: linux
      
kubeScheduler:
  service:
    port: 10259
    targetPort: 10259

  serviceMonitor:
    ## Enable scraping kube-controller-manager over https.
    ## Requires proper certs (not self-signed) and delegated authentication/authorization checks
    ##
    https: true

    # Skip TLS certificate validation when scraping
    insecureSkipVerify: true

    # Name of the server to use when validating TLS certificate
    serverName: null  

kubeControllerManager:
  service:
    port: 10257
    targetPort: 10257

  serviceMonitor:
    ## Enable scraping kube-controller-manager over https.
    ## Requires proper certs (not self-signed) and delegated authentication/authorization checks
    ##
    https: true

    # Skip TLS certificate validation when scraping
    insecureSkipVerify: true

    # Name of the server to use when validating TLS certificate
    serverName: null

kubeEtcd:
  serviceMonitor:
    scheme: https
    insecureSkipVerify: true
    caFile: /etc/prometheus/secrets/etcd-certs/ca.crt
    certFile: /etc/prometheus/secrets/etcd-certs/client.crt
    keyFile: /etc/prometheus/secrets/etcd-certs/client.key
```

**Note**: `secretName` must match the name specified in the certificate signing request. See `desired-cert.yaml` from prior steps.

### Deploy NGINX Ingress

Install a nginx ingress controller using helm. This is going to be ingress access to the Grafana dashboard. This controller is of `Type: LoadBalancer` so it will pull an IP address from AKS-HCI load balancer.

```
helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update
helm install nginx-ingress nginx-stable/nginx-ingress --set controller.nodeSelector."kubernetes\.io/os"=linux
```

### Deploy Promethus

Deploy Promethus components in the monitoring namespace.

```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add stable https://kubernetes-charts.storage.googleapis.com/
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring -f custom.yaml
```

  * A successful installation will look like:

  ```
  NAME:   prometheus
  LAST DEPLOYED: Thu Jul 11 09:49:51 2019
  NAMESPACE: monitoring
  STATUS: DEPLOYED

  RESOURCES:
  ==> v1/Alertmanager
  NAME                                     AGE
  prometheus-prometheus-oper-alertmanager  1s

  ==> v1/ClusterRole
  NAME                                       AGE
  prometheus-grafana-clusterrole             2s
  prometheus-prometheus-oper-alertmanager    2s
  prometheus-prometheus-oper-operator        2s
  prometheus-prometheus-oper-operator-psp    2s
  prometheus-prometheus-oper-prometheus      2s
  prometheus-prometheus-oper-prometheus-psp  2s
  psp-prometheus-kube-state-metrics          2s

  ==> v1/ClusterRoleBinding
  NAME                                       AGE
  prometheus-grafana-clusterrolebinding      2s
  prometheus-prometheus-oper-alertmanager    2s
  prometheus-prometheus-oper-operator        2s
  prometheus-prometheus-oper-operator-psp    2s
  prometheus-prometheus-oper-prometheus      2s
  prometheus-prometheus-oper-prometheus-psp  2s
  psp-prometheus-kube-state-metrics          2s

  ==> v1/ConfigMap
  NAME                                                          DATA  AGE
  prometheus-grafana                                            1     2s
  prometheus-grafana-config-dashboards                          1     2s
  prometheus-grafana-test                                       1     2s
  prometheus-prometheus-oper-etcd                               1     2s
  prometheus-prometheus-oper-grafana-datasource                 1     2s
  prometheus-prometheus-oper-k8s-cluster-rsrc-use               1     2s
  prometheus-prometheus-oper-k8s-coredns                        1     2s
  prometheus-prometheus-oper-k8s-node-rsrc-use                  1     2s
  prometheus-prometheus-oper-k8s-resources-cluster              1     2s
  prometheus-prometheus-oper-k8s-resources-namespace            1     2s
  prometheus-prometheus-oper-k8s-resources-pod                  1     2s
  prometheus-prometheus-oper-k8s-resources-workload             1     2s
  prometheus-prometheus-oper-k8s-resources-workloads-namespace  1     2s
  prometheus-prometheus-oper-nodes                              1     2s
  prometheus-prometheus-oper-persistentvolumesusage             1     2s
  prometheus-prometheus-oper-pods                               1     2s
  prometheus-prometheus-oper-statefulset                        1     2s

  ==> v1/Deployment
  NAME                                 READY  UP-TO-DATE  AVAILABLE  AGE
  prometheus-kube-state-metrics        0/1    1           0          1s
  prometheus-prometheus-oper-operator  0/1    1           0          1s

  ==> v1/PersistentVolumeClaim
  NAME                STATUS  VOLUME                                    CAPACITY  ACCESS MODES  STORAGECLASS  AGE
  prometheus-grafana  Bound   pvc-f6eca714-a3fb-11e9-86b1-005056801da1  20Gi      RWO           default       2s

  ==> v1/Pod(related)
  NAME                                                  READY  STATUS             RESTARTS  AGE
  prometheus-grafana-75f646d87b-8597r                   0/2    Init:0/2           0         1s
  prometheus-kube-state-metrics-7fbb4697c-2hwjl         0/1    ContainerCreating  0         1s
  prometheus-prometheus-node-exporter-7dnt2             0/1    ContainerCreating  0         1s
  prometheus-prometheus-node-exporter-c2r5t             0/1    ContainerCreating  0         2s
  prometheus-prometheus-node-exporter-sl6w6             0/1    ContainerCreating  0         1s
  prometheus-prometheus-oper-operator-6d875fb8b5-2tcf9  0/1    ContainerCreating  0         1s

  ==> v1/Prometheus
  NAME                                   AGE
  prometheus-prometheus-oper-prometheus  1s

  ==> v1/PrometheusRule
  NAME                                                             AGE
  prometheus-prometheus-oper-alertmanager.rules                    1s
  prometheus-prometheus-oper-etcd                                  1s
  prometheus-prometheus-oper-general.rules                         1s
  prometheus-prometheus-oper-k8s.rules                             1s
  prometheus-prometheus-oper-kube-apiserver.rules                  1s
  prometheus-prometheus-oper-kube-prometheus-node-alerting.rules   1s
  prometheus-prometheus-oper-kube-prometheus-node-recording.rules  1s
  prometheus-prometheus-oper-kube-scheduler.rules                  1s
  prometheus-prometheus-oper-kubernetes-absent                     1s
  prometheus-prometheus-oper-kubernetes-apps                       1s
  prometheus-prometheus-oper-kubernetes-resources                  1s
  prometheus-prometheus-oper-kubernetes-storage                    1s
  prometheus-prometheus-oper-kubernetes-system                     1s
  prometheus-prometheus-oper-node-network                          1s
  prometheus-prometheus-oper-node-time                             1s
  prometheus-prometheus-oper-node.rules                            1s
  prometheus-prometheus-oper-prometheus-operator                   1s
  prometheus-prometheus-oper-prometheus.rules                      1s

  ==> v1/Role
  NAME                     AGE
  prometheus-grafana-test  2s

  ==> v1/RoleBinding
  NAME                     AGE
  prometheus-grafana-test  2s

  ==> v1/Secret
  NAME                                                  TYPE    DATA  AGE
  alertmanager-prometheus-prometheus-oper-alertmanager  Opaque  1     2s
  prometheus-grafana                                    Opaque  3     2s

  ==> v1/Service
  NAME                                                TYPE       CLUSTER-IP      EXTERNAL-IP  PORT(S)    AGE
  prometheus-grafana                                  ClusterIP  10.100.200.98   <none>       80/TCP     2s
  prometheus-kube-state-metrics                       ClusterIP  10.100.200.248  <none>       8080/TCP   2s
  prometheus-prometheus-node-exporter                 ClusterIP  10.100.200.39   <none>       9100/TCP   2s
  prometheus-prometheus-oper-alertmanager             ClusterIP  10.100.200.157  <none>       9093/TCP   2s
  prometheus-prometheus-oper-coredns                  ClusterIP  None            <none>       9153/TCP   2s
  prometheus-prometheus-oper-kube-controller-manager  ClusterIP  None            <none>       10252/TCP  2s
  prometheus-prometheus-oper-kube-etcd                ClusterIP  None            <none>       2379/TCP   2s
  prometheus-prometheus-oper-kube-scheduler           ClusterIP  None            <none>       10251/TCP  2s
  prometheus-prometheus-oper-operator                 ClusterIP  10.100.200.150  <none>       8080/TCP   2s
  prometheus-prometheus-oper-prometheus               ClusterIP  10.100.200.213  <none>       9090/TCP   2s

  ==> v1/ServiceAccount
  NAME                                     SECRETS  AGE
  prometheus-grafana                       1        2s
  prometheus-grafana-test                  1        2s
  prometheus-kube-state-metrics            1        2s
  prometheus-prometheus-node-exporter      1        2s
  prometheus-prometheus-oper-alertmanager  1        2s
  prometheus-prometheus-oper-operator      1        2s
  prometheus-prometheus-oper-prometheus    1        2s

  ==> v1/ServiceMonitor
  NAME                                                AGE
  prometheus-prometheus-oper-alertmanager             1s
  prometheus-prometheus-oper-apiserver                1s
  prometheus-prometheus-oper-coredns                  1s
  prometheus-prometheus-oper-grafana                  1s
  prometheus-prometheus-oper-kube-controller-manager  1s
  prometheus-prometheus-oper-kube-etcd                1s
  prometheus-prometheus-oper-kube-scheduler           1s
  prometheus-prometheus-oper-kube-state-metrics       1s
  prometheus-prometheus-oper-kubelet                  1s
  prometheus-prometheus-oper-node-exporter            1s
  prometheus-prometheus-oper-operator                 1s
  prometheus-prometheus-oper-prometheus               1s

  ==> v1beta1/ClusterRole
  NAME                                     AGE
  prometheus-kube-state-metrics            2s
  psp-prometheus-prometheus-node-exporter  2s

  ==> v1beta1/ClusterRoleBinding
  NAME                                     AGE
  prometheus-kube-state-metrics            2s
  psp-prometheus-prometheus-node-exporter  2s

  ==> v1beta1/DaemonSet
  NAME                                 DESIRED  CURRENT  READY  UP-TO-DATE  AVAILABLE  NODE SELECTOR  AGE
  prometheus-prometheus-node-exporter  3        3        0      3           0          <none>         2s

  ==> v1beta1/Ingress
  NAME                HOSTS                     ADDRESS  PORTS  AGE
  prometheus-grafana  grafana.test.example.com  80, 443  1s

  ==> v1beta1/PodSecurityPolicy
  NAME                                     PRIV   CAPS      SELINUX           RUNASUSER  FSGROUP    SUPGROUP  READONLYROOTFS  VOLUMES
  prometheus-grafana                       false  RunAsAny  RunAsAny          RunAsAny   RunAsAny   false     configMap,emptyDir,projected,secret,downwardAPI,persistentVolumeClaim
  prometheus-grafana-test                  false  RunAsAny  RunAsAny          RunAsAny   RunAsAny   false     configMap,downwardAPI,emptyDir,projected,secret
  prometheus-kube-state-metrics            false  RunAsAny  MustRunAsNonRoot  MustRunAs  MustRunAs  false     secret
  prometheus-prometheus-node-exporter      false  RunAsAny  RunAsAny          MustRunAs  MustRunAs  false     configMap,emptyDir,projected,secret,downwardAPI,persistentVolumeClaim,hostPath
  prometheus-prometheus-oper-alertmanager  false  RunAsAny  RunAsAny          MustRunAs  MustRunAs  false     configMap,emptyDir,projected,secret,downwardAPI,persistentVolumeClaim
  prometheus-prometheus-oper-operator      false  RunAsAny  RunAsAny          MustRunAs  MustRunAs  false     configMap,emptyDir,projected,secret,downwardAPI,persistentVolumeClaim
  prometheus-prometheus-oper-prometheus    false  RunAsAny  RunAsAny          MustRunAs  MustRunAs  false     configMap,emptyDir,projected,secret,downwardAPI,persistentVolumeClaim

  ==> v1beta1/Role
  NAME                AGE
  prometheus-grafana  2s

  ==> v1beta1/RoleBinding
  NAME                AGE
  prometheus-grafana  2s

  ==> v1beta2/Deployment
  NAME                READY  UP-TO-DATE  AVAILABLE  AGE
  prometheus-grafana  0/1    1           0          2s

  NOTES:
  The Prometheus Operator has been installed. Check its status by running:
    kubectl --namespace monitoring get pods -l "release=prometheus"

  Visit https://github.com/coreos/prometheus-operator for instructions on how
  to create & configure Alertmanager and Prometheus instances using the Operator.
  ```

#### Trouble Shooting

If there is an error during deployment, it could be from a bug in Helm. It is possible for the 5 CRDs that are created by this chart to fail. Not allowing time to get fully deployed before Helm attempts to create resources that require them. A simple way to remediate this is to delete the current deployment and the associated CRDs.

```
helm delete prometheus
kubectl delete crd prometheuses.monitoring.coreos.com
kubectl delete crd prometheusrules.monitoring.coreos.com
kubectl delete crd servicemonitors.monitoring.coreos.com
kubectl delete crd podmonitors.monitoring.coreos.com
kubectl delete crd alertmanagers.monitoring.coreos.com
kubectl delete crd thanosrulers.monitoring.coreos.com
```

  * Try again using the helm installation:

  ```
helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring -f custom.yaml
  ```

  * If installation fails again, delete the installation and the CRDs once more. Try manually creating the CRDs. Wait for CRDs to be created, which should only take a few seconds

  ```
kubectl create -f https://raw.githubusercontent.com/prometheus-community/helm-charts/main/charts/kube-prometheus-stack/crds/crd-alertmanager.yaml
kubectl create -f https://raw.githubusercontent.com/prometheus-community/helm-charts/main/charts/kube-prometheus-stack/crds/crd-podmonitor.yaml
kubectl create -f https://raw.githubusercontent.com/prometheus-community/helm-charts/main/charts/kube-prometheus-stack/crds/crd-prometheus.yaml
kubectl create -f https://raw.githubusercontent.com/prometheus-community/helm-charts/main/charts/kube-prometheus-stack/crds/crd-prometheusrules.yaml
kubectl create -f https://raw.githubusercontent.com/prometheus-community/helm-charts/main/charts/kube-prometheus-stack/crds/crd-servicemonitor.yaml
kubectl create -f https://raw.githubusercontent.com/prometheus-community/helm-charts/main/charts/kube-prometheus-stack/crds/crd-thanosrulers.yaml
  ```

  * Install the Prometheus Operator using helm chart and reference the `custom.yaml` but disable the CRD provisioning.

  ```
helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring -f custom.yaml --set prometheusOperator.createCustomResource=false
  ```  


## Prometheus Validation

To verify that your Prometheus deployment was successful, check that the following PODS are running:

```
kubectl get pods -n monitoring
NAME                                                     READY   STATUS    RESTARTS   AGE
alertmanager-prometheus-prometheus-oper-alertmanager-0   2/2     Running   0          3m25s
prometheus-grafana-75f646d87b-8597r                      2/2     Running   0          3m35s
prometheus-kube-state-metrics-7fbb4697c-2hwjl            1/1     Running   0          3m35s
prometheus-prometheus-node-exporter-7dnt2                1/1     Running   0          3m35s
prometheus-prometheus-node-exporter-c2r5t                1/1     Running   0          3m36s
prometheus-prometheus-node-exporter-sl6w6                1/1     Running   0          3m35s
prometheus-prometheus-oper-operator-6d875fb8b5-2tcf9     1/1     Running   0          3m35s
prometheus-prometheus-prometheus-oper-prometheus-0       3/3     Running   1          3m15s
```
**Note**:  The number of node exporter PODS will vary depending on the number of linux worker nodes in the cluster.

```
kubectl get svc -n monitoring
NAME                                      TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
alertmanager-operated                     ClusterIP   None              <none>        9093/TCP,6783/TCP   3m50s
prometheus-grafana                        ClusterIP   10.100.200.200    <none>        80/TCP              4m1s
prometheus-kube-state-metrics             ClusterIP   10.100.200.232    <none>        8080/TCP            4m1s
prometheus-operated                       ClusterIP   None              <none>        9090/TCP            3m40s
prometheus-prometheus-node-exporter       ClusterIP   10.100.200.230    <none>        9100/TCP            4m1s
prometheus-prometheus-oper-alertmanager   ClusterIP   10.100.200.136    <none>        9093/TCP            4m1s
prometheus-prometheus-oper-operator       ClusterIP   10.100.200.179    <none>        8080/TCP            4m1s
prometheus-prometheus-oper-prometheus     ClusterIP   10.100.200.29     <none>        9090/TCP            4m1s
```
**Note**:  Prometheus services do not have External IPs Mapped.

  * Outside of Grafana, Prometheus services are not accessible outside of the cluster.  To reach Prometheus externally (from a desktop for example), use port forwarding:

  ```
kubectl port-forward prometheus-prometheus-prometheus-oper-prometheus-0 -n monitoring 9090:9090
  ```

 Once port-forwarding is enabled, access the Prometheus UI using http://127.0.0.1:9090

## Access The Grafana Dashboard

For the Grafana dashboard access, the ingress controller is set up to route based on the incoming URL. To reach the correct Grafana endpoint, we must use the Fully Qualified Domain Name (FQDN) and file path to the ingress controller. In our example, FQDN (grafana.test.example.com) must be resolvable to an IP.
External IP can found by simply looking at the services and seeing what Load Balancer IP has been allocated from load balancer.

```
kubectl get svc
NAME                          TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)                      AGE
kubernetes                    ClusterIP      10.96.0.1        <none>          443/TCP                      26h
nginx-ingress-nginx-ingress   LoadBalancer   10.109.163.110   10.185.223.96   80:32111/TCP,443:30757/TCP   92m 
```

In a production environment, register the external IP to FQDN mapping in a DNS server. Alternatively, for a pre-production development environment, create a temporary lookup entry in `/etc/hosts` file. Edit the `etc/hosts` file of the local machine putting the IP and DNS name for the Grafana dashboard to appear in a browser. Depending on the environment and access, use the correct Load Balancer IP. Such as:

```
10.185.223.96  grafana.test.example.com
```

To access Grafana, enter `https://grafana.test.example.com/` in a web browser

Accept the series of `NET::ERR_CERT_AUTHORITY_INVALID` warnings because this example uses a fake CA.
![grafana-01](images/grafana-001.jpg)

Enter the Grafana dashboard with Username/Password: admin/AKS
![grafana-02](images/grafana-002.jpg)

This particular deployment is already collecting statistics from the configured Kubernetes cluster and has preinstalled dashboards. Navigate to Dashboards -> Manage
![grafana-03](images/grafana-003.jpg)

View the list of available dashboards.
![grafana-04](images/grafana-004.jpg)

Click on a dashboard to see the Grafana view with statistics being collected by Prometheus.
![grafana-05](images/grafana-005.jpg)


### KubeProxy metrics scrapping
The metrics bind address of kube-proxy is not enabled by default. You should expose metrics by changing metricsBindAddress field value to 0.0.0.0:10249 if you want to collect them.

Please take a look here https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack#kubeproxy
