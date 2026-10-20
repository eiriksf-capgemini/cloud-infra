<#
  Stops or starts an AKS cluster via the ARM REST API using the Automation
  account's managed identity. Uses Invoke-AzRestMethod (Az.Accounts, present in
  every Automation runtime) so no extra modules have to be imported.
#>
param(
    [Parameter(Mandatory = $true)] [string] $ClusterId,
    [Parameter(Mandatory = $true)] [ValidateSet("stop", "start")] [string] $Action
)

$ErrorActionPreference = "Stop"
$apiVersion = "2024-09-01"

Disable-AzContextAutosave -Scope Process | Out-Null
Connect-AzAccount -Identity | Out-Null

$get = Invoke-AzRestMethod -Method GET -Path "$ClusterId`?api-version=$apiVersion"
if ($get.StatusCode -ne 200) { throw "GET cluster failed: $($get.StatusCode) $($get.Content)" }
$state = ($get.Content | ConvertFrom-Json).properties.powerState.code
Write-Output "Cluster power state: $state"

if ($Action -eq "stop" -and $state -eq "Stopped") { Write-Output "Already stopped; nothing to do."; return }
if ($Action -eq "start" -and $state -eq "Running") { Write-Output "Already running; nothing to do."; return }

$resp = Invoke-AzRestMethod -Method POST -Path "$ClusterId/$Action`?api-version=$apiVersion"
if ($resp.StatusCode -notin 200, 202) { throw "$Action failed: $($resp.StatusCode) $($resp.Content)" }
Write-Output "$Action accepted (HTTP $($resp.StatusCode))."
