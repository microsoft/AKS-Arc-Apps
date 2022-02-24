We recommend [Akri](https://docs.akri.sh/) to enable leaf device access on the cluster.

## Prerequisites:
Before performing the procedure in this topic, you must have installed and configured the following:

* A Kubernetes cluster created with AKS-HCI with at least 1 master and 1 Linux worker nodes.
* Install Helm V3 and add it to system PATH. 
  Helm is the package manager for Kubernetes that runs on a local machine with `kubectl` access to the Kubernetes cluster. Please review the steps on your own recommended way of [Installing Helm](https://helm.sh/docs/using_helm/#installing-helm).
  Download and install the [Helm CLI](https://github.com/helm/helm/releases/tag/v3.3.0) on the local machine that will be interfacing with the Kubernetes cluster. 

* Install kubectl.exe and add it to system PATH.

# Easy steps to set up leaf device access:
* Open a new powershell Admin window and run below command
  ```
  .\Setup-Akri.ps1 -installAkri $true -kubeconfigFile <target cluster kubeconfig file path> -namespace <namespace where akri will be installed>

  e.g. 
  .\Setup-Akri.ps1 -installAkri $true -kubeconfigFile .\mycluster-kubeconfig -namespace akri
  ```
This will start Akri in your cluster.  To configure Akri, you can create and apply Akri Configuration files using helm.exe and kubectl.exe as you normally would.

You can use helm to create Configuration yaml files (for example, an ONVIF Configuration):

```
helm repo add akri-helm-charts https://project-akri.github.io/akri/
helm template akri akri-helm-charts/akri \
    --set controller.enabled=false \
    --set agent.enabled=false \
    --set rbac.enabled=false \
    --set onvif.configuration.enabled=true \
    --set onvif.configuration.brokerPod.image.repository="ghcr.io/project-akri/akri/onvif-video-broker" > onvif-configuration.yaml
```

And you can use kubectl to apply these Configuration yaml files:

```
kubectl --kubeconfig <target cluster kubeconfig file path> apply -f onvif-configuration.yaml
```

See the [Akri documentation](https://docs.akri.sh/) for more details.

## Steps to uninstall Akri:

* Run below command to uninstall Akri.
  ```
  .\Setup-Akri.ps1 -uninstallAkri $true -kubeconfigFile <target cluster kubeconfig file path> -namespace <namespace where Akri will be installed>

  e.g. 
  .\Setup-Akri.ps1 -uninstallAkri $true -kubeconfigFile .\mycluster-kubeconfig -namespace akri
  ```



