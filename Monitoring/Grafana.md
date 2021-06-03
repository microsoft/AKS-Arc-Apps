**Use Grafana with AKS-HCI**

[Grafana](https://github.com/grafana/grafana) is a tool used to view, query, and visualize metrics on the Grafana dashboards. It can be configured to use Prometheus as the data source. The deployment guidance below requires that you license your own copy of Grafana.
 

**Grafana dashboards available in AKS-HCI**

Following Grafana dashboards are supported in AKS-HCI.

- API server
- Networking / Cluster
- Compute Resources / Cluster
- Compute Resources / Namespace (Pods)
- Compute Resources / Node (Pods)
- Compute Resources / Pod
- Compute Resources / Workload
- Compute Resources / Namespace (Workloads)
- Kubelet
- Networking / Namespace (Pods)
- Networking / Namespace (Workload)
- Persistent Volumes
- Networking / Pod
- StatefulSets
- Networking / Workload
- Compute Resources / Cluster (Windows)
- Compute Resources / Namespace (Windows Pods)
- Compute Resources / Pod (Windows)
- USE Method / Cluster (Windows)
- USE Method / Node (Windows)



**Deploy Grafana**

There are two approaches for deploying Granafa for AKS-HCI.

 

***Deploy Grafana in AKS-HCI cluster***

Configure Dashboards and data source
```
kubectl apply -f https://raw.githubusercontent.com/microsoft/AKS-HCI-Apps/main/Monitoring/data-source.yaml
kubectl apply -f https://raw.githubusercontent.com/microsoft/AKS-HCI-Apps/main/Monitoring/dashboards.yaml
```
Grafana can be installed using helm chart

```
helm repo add grafana https://grafana.github.io/helm-charts

helm repo update

helm install grafana grafana/grafana --set nodeSelector."kubernetes\.io/os"=linux --set sidecar.dashboards.enabled=true --set sidecar.datasources.enabled=true -n monitoring
```
Wait until Grafana pod is up and running and get the Grafana login password.
```
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}"
```
above password is base64 encoded so you need to decode it.

port-forward to the grafana pod and login into grafana using username *admin* and above decoded password.
```
e.g. kubectl port-forward grafana-79d6b8dfbf-z4zxk 3000 -n monitoring
```
 

***Deploy Grafana outside AKS-HCI cluster***

If Grafana instance is running outside the cluster then you need to connect the Prometheus endpoint to Grafana.
and then configure the Grafana dashboards stored here https://raw.githubusercontent.com/microsoft/AKS-HCI-Apps/main/Monitoring/dashboards.yaml
