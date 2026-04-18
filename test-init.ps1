# Test script to verify /init in the Docker image
# Run this locally to check if /init exists in the latest image

$IMAGE = "ghcr.io/comedy1024/hermes-agent-desktop:latest"

Write-Host "Testing /init in image: $IMAGE" -ForegroundColor Cyan

# Pull the latest image
Write-Host "`n[1/4] Pulling latest image..." -ForegroundColor Yellow
docker pull $IMAGE

# Check if /init exists
Write-Host "`n[2/4] Checking /init file..." -ForegroundColor Yellow
docker run --rm --entrypoint sh $IMAGE -c "ls -la /init /init.s6 2>&1 || echo 'FILES NOT FOUND'"

# Check /init content
Write-Host "`n[3/4] Checking /init content (first 10 lines)..." -ForegroundColor Yellow
docker run --rm --entrypoint sh $IMAGE -c "head -10 /init 2>&1 || echo 'CANNOT READ /init'"

# Check file type
Write-Host "`n[4/4] Checking file types..." -ForegroundColor Yellow
docker run --rm --entrypoint sh $IMAGE -c "file /init /init.s6 2>&1 || echo 'file command failed'"

Write-Host "`nTest complete!" -ForegroundColor Green
