// Copyright (c) Microsoft Corporation.// Licensed under the MIT license.
<#
    .PARAMETER installMonitoring
        installMonitoring boolean flag
    
    .PARAMETER uninstallMonitoring
        uninstallMonitoring boolean flag

    .PARAMETER kubeConfigFile
        clusterName Path

    .PARAMETER grafanaAdminPasswd
        grafanaAdminPasswd

    .PARAMETER namespace
        namespace

    .PARAMETER forwardingLocalPort
        Local port to use for kubectl port forwarding

    .PARAMETER forwardingRemotePort
        Remote port to use for kubectl port forwarding
#>
param (
    [Parameter()]
    [bool] $installMonitoring,

    [Parameter()]
    [bool] $uninstallMonitoring,

    [Parameter(Mandatory = $true)]
    [string] $kubeconfigFile,
        
    [Parameter()]
    [string] $grafanaAdminPasswd,

    [Parameter(Mandatory = $true)]
    [string] $namespace,

    [Parameter()]
    [ValidateRange(0, 65535)]
    [Int]$forwardingLocalPort = 3000,

    [Parameter()]
    [ValidateRange(0, 65535)]
    [Int]$forwardingRemotePort = 80
)

function Install-Monitoring {
    <#
    .DESCRIPTION
        Helper function to install the monitoring addon on the target cluster.

    .PARAMETER kubeConfigFile
        cluster kubeConfigFile

    .PARAMETER grafanaAdminPasswd
        grafanaAdminPasswd

    .PARAMETER namespace
        namespace
        
    .PARAMETER forwardingLocalPort
        Local port to use for kubectl port forwarding

    .PARAMETER forwardingRemotePort
        Remote port to use for kubectl port forwarding
    #>

    param (
        [Parameter(Mandatory = $true)]
        [String] $kubeConfigFile,
        
        [Parameter()]
        [string] $grafanaAdminPasswd,

        [Parameter(Mandatory = $true)]
        [String] $namespace,

        [Parameter()]
        [ValidateRange(0, 65535)]
        [Int]$forwardingLocalPort,

        [Parameter()]
        [ValidateRange(0, 65535)]
        [Int]$forwardingRemotePort
    )

    Write-Host "Installing Monitoring"
    Write-Host "Creating namespace $namespace"
    $namespacecheck = kubectl.exe --kubeconfig=$kubeConfigFile get namespace | findstr $namespace
    if ($null -eq $namespacecheck) {
        Write-Host "namespace does not exist, Creating"
        kubectl.exe --kubeconfig=$kubeConfigFile create namespace $namespace
    }
    
    Write-Host "Retrieving ETCD credenatils"
    $podname = $(kubectl get pods -o=jsonpath='{.items[0].metadata.name}' -l component=kube-apiserver -n kube-system)
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

    $etcdcert = @"
apiVersion: v1
kind: Secret
metadata:
  name: etcd-certs
  namespace: $namespace
data:
  ca.crt: $caContentEncoded
  client.crt: $clientCertContentEncoded
  client.key: $clientKeyContentEncoded
"@
    $etcdcertyaml = [IO.Path]::GetTempFileName() | Rename-Item -NewName { $_ -replace 'tmp$', 'yaml' } -PassThru
    Set-Content -Path $etcdcertyaml -Value $etcdcert
    Write-Host "Creating etcd secret"
    kubectl create -f $etcdcertyaml
    rm $etcdcertyaml

    $custom = @"
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
  
  adminPassword: $grafanaAdminPasswd 
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
"@
    
    $customyaml = [IO.Path]::GetTempFileName() | Rename-Item -NewName { $_ -replace 'tmp$', 'yaml' } -PassThru
    Set-Content -Path $customyaml -Value $custom
   
    helm.exe --kubeconfig $kubeConfigFile repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm.exe --kubeconfig $kubeConfigFile repo add stable https://kubernetes-charts.storage.googleapis.com/
    helm.exe --kubeconfig $kubeConfigFile repo update 
   
    Write-Host "Installing monitoring charts"
    helm.exe --kubeconfig $kubeconfigFile install $global:monitoringRelName prometheus-community/kube-prometheus-stack --namespace $namespace -f $customyaml
    
    rm $customyaml

    ## Wait for Grafana pod to be ready
    Write-Host "Waiting for Pod 'Grafana' to be ready."
    while($true) 
    {
        $result = (Execute-KubeCtl -ignoreError -kubeconfig $kubeconfigFile -arguments $("wait --for=condition=Ready --timeout=5m -n $namespace pod -l app.kubernetes.io/name=grafana"))
        if ($result -ne $null)
        {
            break
        }
        Sleep $sleepDuration
    }
    Write-Host "Pod 'Grafana' is ready."

    Write-Host "Starting port forwarder for Grafana"
    & start-process -FilePath "kubectl.exe" -ArgumentList $("--kubeconfig=$kubeconfigFile port-forward svc/prometheus-grafana "+$forwardingLocalPort+":"+$forwardingRemotePort+" -n=$namespace")
    Write-Host "Grafana is available at: http://localhost:$forwardingLocalPort/" -ForegroundColor Green
}

function Execute-KubeCtl
{
    <#
    .DESCRIPTION
        Executes a kubectl command.

    .PARAMETER kubeconfig
        The kubeconfig file to use. Defaults to the management kubeconfig.

    .PARAMETER arguments
        Arguments to pass to the command.

    .PARAMETER ignoreError
        Optionally, ignore errors from the command (don't throw).

    .PARAMETER showOutput
        Optionally, show live output from the executing command.
    #>

    param (
        [string] $kubeconfig,
        [string] $arguments,
        [switch] $ignoreError,
        [switch] $showOutput
    )

    return Execute-Command -command kubectl.exe -arguments $("--kubeconfig=$kubeconfig $arguments") -showOutput:$showOutput.IsPresent -ignoreError:$ignoreError.IsPresent
}

function Execute-Command
{
    <#
    .DESCRIPTION
        Executes a command and optionally ignores errors.

    .PARAMETER command
        Comamnd to execute.

    .PARAMETER arguments
        Arguments to pass to the command.

    .PARAMETER ignoreError
        Optionally, ignore errors from the command (don't throw).

    .PARAMETER showOutput
        Optionally, show live output from the executing command.
    #>

    param (
        [String]$command,
        [String]$arguments,
        [Switch]$ignoreError,
        [Switch]$showOutput
    )

    if ($showOutput.IsPresent)
    {
        $result = (& $command $arguments.Split(" ") | Out-Default)
    }
    else
    {
        $result = (& $command $arguments.Split(" ") 2>&1)
    }

    $out = $result | ?{$_.gettype().Name -ine "ErrorRecord"}  # On a non-zero exit code, this may contain the error
    $outString = ($out | Out-String).ToLowerInvariant()

    if ($LASTEXITCODE)
    {
        if ($ignoreError.IsPresent)
        {
            return
        }
        $err = $result | ?{$_.gettype().Name -eq "ErrorRecord"}
        throw "$command $arguments failed to execute [$err]"
    }
    return $out
}

function Uninstall-Monitoring {
    <#
    .DESCRIPTION
        Helper function to Uninstall the monitoring addon on the target cluster.

    .PARAMETER kubeConfigFile
        cluster kubeConfigFile

    .PARAMETER namespace
        namespace
    #>

    param (
        [Parameter(Mandatory = $true)]
        [String] $kubeConfigFile,
        
        [Parameter(Mandatory = $true)]
        [String] $namespace
    )

    Write-Host "Uninstalling monitoring release"
    Write-Host "& helm.exe --kubeconfig $kubeConfigFile uninstall $global:monitoringRelName -n=$namespace"
    #helm.exe --kubeconfig $kubeConfigFile uninstall $global:monitoringRelName -n$namespace
    start-process -FilePath "helm.exe" -ArgumentList $("--kubeconfig $kubeConfigFile uninstall $global:monitoringRelName -n$namespace")
    Write-Host "Monitoring release ""$global:monitoringRelName"" uninstalled"

    Write-Host "Deleting cert Secrets"
    start-process -FilePath "kubectl.exe" -ArgumentList $("--kubeconfig=$kubeConfigFile delete secret etcd-certs -n=$namespace")
    #& kubectl.exe --kubeconfig=$kubeConfigFile delete secret etcd-certs -n=$namespace

    Write-Host "Uninstalling monitoring CRDS"
    & kubectl.exe --kubeconfig=$kubeConfigFile delete crds alertmanagers.monitoring.coreos.com podmonitors.monitoring.coreos.com prometheuses.monitoring.coreos.com prometheusrules.monitoring.coreos.com servicemonitors.monitoring.coreos.com thanosrulers.monitoring.coreos.com
}


$global:monitoringRelName = "prometheus"
if (($installMonitoring -eq $false -and $uninstallMonitoring -eq $false) -or ($installMonitoring -eq $true -and $uninstallMonitoring -eq $true))
{
    Write-Error "Please set either installMonitoring or uninstallMonitoring flag"
    exit
}

try {
    if ($installMonitoring -eq $true) {
        if ([string]::IsNullOrEmpty($grafanaAdminPasswd)) {
            Write-Error "Please pass Grafana admin password"
            exit
        }
        Install-Monitoring -kubeconfigFile $kubeconfigFile -grafanaAdminPasswd $grafanaAdminPasswd -namespace $namespace -forwardingLocalPort $forwardingLocalPort -forwardingRemotePort $forwardingRemotePort
    }
    elseif ($uninstallMonitoring -eq $true) {
        Uninstall-Monitoring -kubeConfigFile $kubeconfigFile -namespace $namespace
    }
    else {
        Write-Error "Unknown"
        exit
    }
}
catch [Exception] {
    Write-Error "Exception caught!!!" $_.Exception.Message.ToString()
        
}
