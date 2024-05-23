
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.

<#
    .PARAMETER installDashboard
        installDashboard boolean flag
    
    .PARAMETER uninstallDashboard
        uninstallDashboard boolean flag

     .PARAMETER getDashboardSecret
        Retrieve Dashboard Secret boolean flag

    .PARAMETER kubeConfigFile
        Kubeconfig Path    

    .PARAMETER dashboardProxyPort
        Local port to use for the dashboard proxy
#>
param (
    [Parameter()]
    [bool] $installDashboard,

    [Parameter()]
    [bool] $uninstallDashboard,

    [Parameter()]
    [bool] $getDashboardSecret,

    [Parameter(Mandatory = $true)]
    [string] $kubeconfigFile,
    
    [Parameter()]
    [ValidateRange(0, 65535)]
    [Int]$dashboardProxyPort = 50051    
)

function Install-Dashboard
{
    <#
    .DESCRIPTION
        Install the Kubernetes Dashboard.

    .PARAMETER kubeConfigFile
        kubeConfigFile

    .PARAMETER proxyPort
        Local port to use for the dashboard proxy
    #>

    param (
        [Parameter(Mandatory=$true)]
        [String] $kubeConfigFile,

        [Parameter()]
        [ValidateRange(0,65535)]
        [Int]$proxyPort = $script:dashboardPort
    )    

    Write-Host $("Installing dashboard")

    if (Get-DashboardSecret -kubeconfig $kubeConfigFile)
    {
        Write-Host "A dashboard secret is already present for this cluster. Skipping installation." -color magenta
    }
    else
    {
        Execute-KubeCtl -kubeconfig $kubeConfigFile -arguments $("apply -f " + $global:dashboardYaml) | Out-Null
        Execute-KubeCtl -kubeconfig $kubeConfigFile -arguments "create serviceaccount cluster-admin-dashboard-sa" | Out-Null
        Execute-KubeCtl -kubeconfig $kubeConfigFile -arguments "create clusterrolebinding cluster-admin-dashboard-sa --clusterrole=cluster-admin --serviceaccount=default:cluster-admin-dashboard-sa" | Out-Null
    }

    Write-Host $("Waiting for dashboard pods to be ready")
    foreach($pod in $global:dashboardPods)
    {
        Wait-ForKubernetesPod -kubeconfigFile $kubeConfigFile -podFriendlyName $pod[0] -namespace $pod[1] -selector $pod[2]
    }

    Write-Host $("Starting dashboard proxy")
    Write-Host $("Please close any command window with previous dashboard proxy running!")
    & start-process -FilePath "kubectl.exe" -ArgumentList "--kubeconfig=$kubeConfigFile proxy --port $proxyPort"

    Write-Host $("Dashboard is available at: http://localhost:$proxyPort/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#!/login")

    Write-Host "Retrieving dashboard secret"
    return Get-DashboardSecret -kubeconfig $kubeConfigFile
}

function Get-DashboardSecret
{
    <#
    .DESCRIPTION
        Retrieve the kubernetes secret that allows you to access the deployed dashboard.

    .PARAMETER kubeconfig
        Path to a kubeconfig file.
    #>

    param (
        [Parameter(Mandatory=$true)]
        [String] $kubeconfig
    )

    try {
        $secret = (Execute-KubeCtl -kubeconfig $kubeconfig -arguments "get secret") | findstr $global:dashboardSecret
    } catch {
        Write-Host $_
    }
    if ($secret -eq $null)
    {
        return $null
    }

    $token = (Execute-KubeCtl -kubeconfig $kubeconfig -arguments $("describe secret " + $secret.Split(" ")[0])) | findstr "token:"
    $tokenString = ($token.Split(":")[1]).trim(" ")

    return $tokenString
}

function Uninstall-Dashboard
{
    <#
    .DESCRIPTION
        Orchestrates the process of uninstalling the dashboard addon.
    
    .PARAMETER kubeConfigFile
        kubeConfigFile
    #>

    param (
        [Parameter(Mandatory=$true)]
        [string] $kubeConfigFile
    ) 

    
    Write-Host "Uninstalling dashboard"

    Execute-KubeCtl -kubeconfig $kubeConfigFile -arguments $("delete -f " + $global:dashboardYaml) -ignoreError

    try{
        $secret = (Execute-KubeCtl -kubeconfig $kubeConfigFile -arguments "get secret") | findstr $global:dashboardSecret
    } catch {
        Write-Host $_
    }
    if ($secret)
    {
        Write-Host "Removing dashboard secret"
        Execute-KubeCtl -kubeconfig $kubeConfigFile -arguments $("delete secret " + $secret.Split(" ")[0])  -ignoreError
    }

    Write-Host "Removing dashboard service account"
    Execute-KubeCtl -kubeconfig $kubeConfigFile -arguments "delete serviceaccount/cluster-admin-dashboard-sa" -ignoreError

    Write-Host "Removing dashboard clusterrolebinding"
    Execute-KubeCtl -kubeconfig $kubeConfigFile -arguments "delete clusterrolebinding.rbac.authorization.k8s.io/cluster-admin-dashboard-sa" -ignoreError

    Write-Host "Please close any command window with dashboard proxy running!"
}

function Wait-ForKubernetesPod
{
    <#
    .DESCRIPTION
        Waits for a pod to be present and to enter a running state.

    .PARAMETER kubeconfigFile
        Path to a kubeconfig file

    .PARAMETER podFriendlyName
        Friendly name of the pod, for logging purposes

    .PARAMETER namespace
        The namespace of the pod

    .PARAMETER selector
        label query to filter on

    .PARAMETER sleepDuration
        Duration to sleep for between attempts
    #>

    param (
        [String]$kubeconfigFile,
        [String]$podFriendlyName,
        [String]$namespace,
        [String]$selector,
        [int]$sleepDuration=5
    )

    Write-Host $("Waiting for '$podFriendlyName' pod to be ready...")

    while($true) 
    {
        $result = (Execute-KubeCtl -ignoreError -kubeconfig $kubeconfigFile -arguments $("wait --for=condition=Ready --timeout=5m -n $namespace pod -l $selector"))
        if ($result -ne $null)
        {
            break
        }
        Sleep $sleepDuration
    }

    Write-Host $("Pod '$podFriendlyName' is ready.`n")
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


$global:dashboardSecret      = "cluster-admin-dashboard"
$global:dashboardYaml        = "https://raw.githubusercontent.com/kubernetes/dashboard/master/charts/kubernetes-dashboard/Chart.yaml"

$global:dashboardPods =
@(
    ("Dashboard Metrics Scraper", "kubernetes-dashboard", "k8s-app=dashboard-metrics-scraper"),
    ("Kubernetes Dashboard", "kubernetes-dashboard", "k8s-app=kubernetes-dashboard")
)

if (($installDashboard -eq $false -and $uninstallDashboard -eq $false -and $getDashboardSecret -eq $false) -or ($installDashboard -eq $true -and $uninstallDashboard -eq $true -and $getDashboardSecret -eq $true))
{
    Write-Error "Please set either installDashboard or uninstallDashboard or getDashboardSecret flag"
    exit
}

try {
    if ($installDashboard -eq $true) {        
        Install-Dashboard -kubeConfigFile $kubeconfigFile -proxyPort $dashboardProxyPort
    }
    elseif ($uninstallDashboard -eq $true) {
        Uninstall-Dashboard -kubeConfigFile $kubeconfigFile
    }
    elseif ($getDashboardSecret -eq $true) {
        Get-DashboardSecret -kubeconfig $kubeconfigFile
    }
    else {
        Write-Error "Unknown"
        exit
    }
}
catch [Exception] {
    Write-Error "Exception caught!!!" $_.Exception.Message.ToString()
        
}
