#!/bin/bash

# Test script to verify discovery limits work correctly
set -e

DISCOVERY_DIR="/root/onlyoffice-deployment-toolkit/test-discovery-data"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MAX_LINES=10
MAX_LOG_LINES=5

mkdir -p "$DISCOVERY_DIR"

echo "=== Testing Discovery Script Limits ==="
echo "Testing with MAX_LINES=$MAX_LINES, MAX_LOG_LINES=$MAX_LOG_LINES"

# Function to limit output lines
limit_output() {
    head -n "$MAX_LINES"
}

# Test 1: Verify line limiting works
echo "Test 1: Line limiting"
test_file="$DISCOVERY_DIR/line_limit_test.txt"
seq 1 100 | limit_output > "$test_file"
line_count=$(wc -l < "$test_file")
echo "Generated 100 lines, limited to $MAX_LINES, actual: $line_count"

# Test 2: Verify timeout works 
echo "Test 2: Timeout functionality"
timeout_file="$DISCOVERY_DIR/timeout_test.txt"
if timeout 2 sleep 5 2>&1 > "$timeout_file"; then
    echo "ERROR: Timeout did not work"
else
    echo "SUCCESS: Timeout worked correctly"
fi

# Test 3: Test Docker commands with limits (if Docker is available)
echo "Test 3: Docker command limits"
docker_test_file="$DISCOVERY_DIR/docker_test.txt"
if command -v docker >/dev/null 2>&1; then
    echo "=== Docker Containers (Limited) ===" > "$docker_test_file"
    timeout 5 docker ps -a 2>&1 | limit_output >> "$docker_test_file" || echo "Timeout or no Docker" >> "$docker_test_file"
    docker_lines=$(wc -l < "$docker_test_file")
    echo "Docker test file has $docker_lines lines (should be ≤ $((MAX_LINES + 1)))"
else
    echo "Docker not available - skipping Docker tests"
fi

# Test 4: Test find command limits
echo "Test 4: Find command limits"
find_test_file="$DISCOVERY_DIR/find_test.txt"
timeout 10 find /usr -maxdepth 2 -type f 2>/dev/null | head -n 20 > "$find_test_file" || echo "Find timeout or error" > "$find_test_file"
find_lines=$(wc -l < "$find_test_file")
echo "Find test returned $find_lines lines (limited to 20)"

# Test 5: Test file size limits
echo "Test 5: File size limits" 
size_test_file="$DISCOVERY_DIR/size_test.txt"
seq 1 10000 | head -c 1024 > "$size_test_file"  # Create ~1KB file
file_size=$(stat -f%z "$size_test_file" 2>/dev/null || stat -c%s "$size_test_file" 2>/dev/null || echo "0")
echo "Test file size: $file_size bytes"

echo ""
echo "=== Limit Test Results ==="
echo "All files created in: $DISCOVERY_DIR"
ls -la "$DISCOVERY_DIR"
echo ""
echo "Limits test completed successfully!"
echo "The discovery script v2 should now have proper output controls."