# Installing Kubernetes Dashboard  in a Kubernetes Cluster created by AKS-HCI

This topic describes how to install Kubernetes Dashboard  in a Kubernetes cluster created by AKS-HCI. 



## Prerequisites:
Before performing the procedure in this topic, you must have installed and configured the following:

* A Kubernetes cluster created with AKS-HCI with at least 1 master and 1 Linux worker nodes.
* Install kubectl.exe and add it to system PATH. 

## Steps to install Kubernetes Dashboard:
* Download Setup-Dashboard.ps1 https://github.com/microsoft/AKS-HCI-Apps/blob/main/kubernetes-dashboard/Setup-Dashboard.ps1 script and save it to local machine.
* Open a new powershell Admin Window and run below command
 ```
 .\Setup-Dashboard.ps1 -installDashboard $true -kubeconfigFile <target cluster kubeconfig file path> -dashboardProxyPort 50051
 
 e.g. 
 .\Setup-Dashboard.ps1 -installDashboard $true -kubeconfigFile C:\wssd\mycluster-kubeconfig -dashboardProxyPort 50051

 Sample output: 

 PS C:\wssd> .\Setup-Dashboard.ps1 -installDashboard $true -kubeconfigFile C:\wssd\bugbash1-kubeconfig
 Installing dashboard
 Waiting for dashboard pods to be ready
 Waiting for 'Dashboard Metrics Scraper' pod to be ready...
 Pod 'Dashboard Metrics Scraper' is ready.

 Waiting for 'Kubernetes Dashboard' pod to be ready...
 Pod 'Kubernetes Dashboard' is ready.

 Starting dashboard proxy
 Please close any command window with previous dashboard proxy running!
 Dashboard is available at: http://localhost:50051/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#!/login
 Retrieving dashboard secret
 eyJhbGciOiJSUzI1NiIsImtpZCI6IjU1eU95dk9vUFgtLTBveWxCbktERDVXOHNDZ1JyRTdYWVFEcTNlTTZnelkifQ.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJkZWZhdWx0Iiwia3ViZXJuZXRlcy5p <truncated>
 PS C:\wssd>
 ```

 ## Steps to launch a kubernetes Dashboard

 Running the install command will also launch a dashboard proxy on the specified port in the local system.

 Open a browser and type: http://localhost:50051/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#!/login
 
![dashboard1](Images/dashboard1.jpg)

 Please make sure you replace the dashboard port with the port you specified in the previous install command.


## Steps to retrieve Kubernetes Dashboard Token

 Token for the Kubernetes Dashboard can be retrived from the install command or by executing the following command

 ```
 .\Setup-Dashboard.ps1 -getDashboardSecret $true -kubeconfigFile <target cluster kubeconfig file path>
 
 e.g. 
 .\Setup-Dashboard.ps1 -getDashboardSecret $true -kubeconfigFile C:\wssd\mycluster-kubeconfig

 Sample output: 

 PS C:\wssd> .\Setup-Dashboard.ps1 -getDashboardSecret $true -kubeconfigFile C:\wssd\bugbash1-kubeconfig 
 eyJhbGciOiJSUzI1NiIsImtpZCI6IjU1eU95dk9vUFgtLTBveWxCbktERDVXOHNDZ1JyRTdYWVFEcTNlTTZnelkifQ.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJkZWZhdWx0Iiwia3ViZXJuZXRlcy5 <truncated>
 ```
![dashboard2](Images/dashboard2.jpg)

## Steps to uninstall Kubernetes Dashboard:

* Run below command to uninstall Kubernetes Dashboard.
 ```
 .\Setup-Dashboard.ps1 -uninstallDashboard $true -kubeconfigFile <target cluster kubeconfig file path>
 
 e.g. 
 .\Setup-Dashboard.ps1 -uninstallDashboard $true -kubeconfigFile C:\wssd\mycluster-kubeconfig
  ```
