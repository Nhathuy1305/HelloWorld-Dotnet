param(
    [string]$DockerUsername = "dangnhathuywork", 
    [string]$ImageName = "helloworld",
    [string]$Tag = "latest",
    [int]$HostPort = 8080
)

# 1. CONSTRUCT VARIABLES
$FullImageName = "$DockerUsername/$ImageName"
$Combo = "$FullImageName`:$Tag" 

Write-Host "------------------------------------------------" -ForegroundColor Cyan
Write-Host "DEBUG INFO:"
Write-Host "  User:  '$DockerUsername'"
Write-Host "  Image: '$ImageName'"
Write-Host "  Tag:   '$Tag'"
Write-Host "  Full:  '$Combo'"
Write-Host "------------------------------------------------" -ForegroundColor Cyan

# 2. CHECK DOCKER
Write-Host "Checking Docker version..."
docker --version
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker is not running or not installed!"
    exit
}

# 3. PULL IMAGE
Write-Host "--- Pulling Image [$Combo] ---" -ForegroundColor Cyan
$pullCommand = "docker pull $Combo"
Write-Host "Executing: $pullCommand"
Invoke-Expression $pullCommand

# 4. RUN CONTAINER
$ContainerName = "eurofins-helloworld-container"

Write-Host "--- Stopping Old Container ---" -ForegroundColor Cyan
# 2>$null hides the error if the container doesn't exist
docker rm -f $ContainerName 2>$null 

Write-Host "--- Starting New Container ---" -ForegroundColor Cyan
# Construct the run command explicitly
$runCommand = "docker run -d -p ${HostPort}:8080 --name $ContainerName $Combo"
Write-Host "Executing: $runCommand"
Invoke-Expression $runCommand

Write-Host "------------------------------------------------" -ForegroundColor Green
Write-Host "DONE. Check http://localhost:$HostPort"