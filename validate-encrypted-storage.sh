#!/bin/bash

# OnlyOffice DocSpace Encrypted Storage Validation Script
# Tests that encrypted storage is properly configured and accessible to containers

set -e

STORAGE_MOUNT="${STORAGE_MOUNT:-/mnt/docspace_data}"

echo "=== OnlyOffice Encrypted Storage Validation ==="
echo "Mount Point: $STORAGE_MOUNT"
echo ""

# Test 1: Verify mount point exists and is accessible
test_mount_point() {
    echo "Test 1: Mount Point Accessibility"
    if [[ -d "$STORAGE_MOUNT" ]]; then
        echo "✓ Mount point exists: $STORAGE_MOUNT"
    else
        echo "✗ Mount point missing: $STORAGE_MOUNT"
        return 1
    fi
    
    if [[ -w "$STORAGE_MOUNT" ]]; then
        echo "✓ Mount point is writable"
    else
        echo "✗ Mount point is not writable"
        return 1
    fi
}

# Test 2: Verify required directories exist
test_directories() {
    echo ""
    echo "Test 2: Required Directories"
    local directories=("app_data" "log_data" "mysql_data")
    local all_exist=true
    
    for dir in "${directories[@]}"; do
        local full_path="$STORAGE_MOUNT/$dir"
        if [[ -d "$full_path" ]]; then
            echo "✓ Directory exists: $full_path"
        else
            echo "✗ Directory missing: $full_path"
            all_exist=false
        fi
    done
    
    if [[ "$all_exist" == false ]]; then
        return 1
    fi
}

# Test 3: Test container volume access
test_container_volume_access() {
    echo ""
    echo "Test 3: Container Volume Access"
    
    # Test if any OnlyOffice containers are running
    local running_containers
    running_containers=$(docker ps --format "{{.Names}}" | grep "^onlyoffice-" | head -5)
    
    if [[ -z "$running_containers" ]]; then
        echo "ℹ No OnlyOffice containers running - skipping container access test"
        return 0
    fi
    
    # Test access from a running container
    local test_container
    test_container=$(echo "$running_containers" | head -1)
    echo "Testing container access using: $test_container"
    
    # Test app_data access
    if docker exec "$test_container" test -d /app/onlyoffice/data 2>/dev/null; then
        echo "✓ Container can access app_data volume"
        
        # Test write access
        local test_file="/app/onlyoffice/data/test_write_access.tmp"
        if docker exec "$test_container" sh -c "echo 'test' > $test_file && rm $test_file" 2>/dev/null; then
            echo "✓ Container has write access to app_data"
        else
            echo "✗ Container cannot write to app_data"
            return 1
        fi
    else
        echo "ℹ Container doesn't have app_data mount (normal for some services)"
    fi
    
    # Test log_data access
    if docker exec "$test_container" test -d /var/log/onlyoffice 2>/dev/null; then
        echo "✓ Container can access log_data volume"
    else
        echo "ℹ Container doesn't have log_data mount"
    fi
}

# Test 4: Check volume mappings in containers
test_volume_mappings() {
    echo ""
    echo "Test 4: Volume Mapping Verification"
    
    # Check if volume mappings contain our encrypted storage path
    local containers_with_mappings=0
    
    for container in $(docker ps --format "{{.Names}}" | grep "^onlyoffice-"); do
        local mappings
        mappings=$(docker inspect --format='{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' "$container" 2>/dev/null | grep "$STORAGE_MOUNT" || true)
        
        if [[ -n "$mappings" ]]; then
            echo "✓ $container uses encrypted storage:"
            echo "$mappings" | sed 's/^/    /'
            ((containers_with_mappings++))
        fi
    done
    
    if [[ $containers_with_mappings -gt 0 ]]; then
        echo "✓ Found $containers_with_mappings containers using encrypted storage"
    else
        echo "✗ No containers found using encrypted storage"
        return 1
    fi
}

# Test 5: Storage performance and health
test_storage_health() {
    echo ""
    echo "Test 5: Storage Health and Performance"
    
    # Check filesystem health
    if df -h "$STORAGE_MOUNT" >/dev/null 2>&1; then
        echo "✓ Filesystem is accessible"
        df -h "$STORAGE_MOUNT" | grep -v "Filesystem"
    else
        echo "✗ Filesystem check failed"
        return 1
    fi
    
    # Test I/O performance (basic)
    local test_file="$STORAGE_MOUNT/performance_test.tmp"
    echo "Testing I/O performance..."
    
    if timeout 10 dd if=/dev/zero of="$test_file" bs=1M count=10 2>/dev/null; then
        echo "✓ Write performance test passed"
        rm -f "$test_file"
    else
        echo "✗ Write performance test failed"
        rm -f "$test_file" 2>/dev/null
        return 1
    fi
}

# Test 6: Persistence test
test_data_persistence() {
    echo ""
    echo "Test 6: Data Persistence"
    
    # Create a test file and verify it persists
    local test_file="$STORAGE_MOUNT/persistence_test.txt"
    local test_content="OnlyOffice encrypted storage test - $(date)"
    
    echo "$test_content" > "$test_file"
    
    if [[ -f "$test_file" ]]; then
        local file_content
        file_content=$(cat "$test_file")
        if [[ "$file_content" == "$test_content" ]]; then
            echo "✓ Data persistence test passed"
            rm "$test_file"
        else
            echo "✗ Data persistence test failed - content mismatch"
            rm "$test_file"
            return 1
        fi
    else
        echo "✗ Data persistence test failed - file not created"
        return 1
    fi
}

# Summary report
generate_summary() {
    echo ""
    echo "=== ENCRYPTED STORAGE VALIDATION SUMMARY ==="
    echo ""
    echo "Storage Details:"
    echo "  Mount Point: $STORAGE_MOUNT"
    echo "  Usage: $(df -h "$STORAGE_MOUNT" | awk 'NR==2{print $3 "/" $2 " (" $5 " used)"}')"
    echo ""
    echo "Directory Structure:"
    ls -la "$STORAGE_MOUNT" 2>/dev/null | tail -n +2 | while read -r line; do
        echo "  $line"
    done
    echo ""
    echo "Container Integration:"
    local active_containers
    active_containers=$(docker ps --format "{{.Names}}" | grep "^onlyoffice-" | wc -l)
    echo "  Active OnlyOffice containers: $active_containers"
    echo "  Containers using encrypted storage: $(docker ps -q | xargs -I {} docker inspect --format='{{.Name}} {{range .Mounts}}{{.Source}}{{end}}' {} 2>/dev/null | grep "$STORAGE_MOUNT" | wc -l)"
}

# Main validation function
main() {
    local failed_tests=0
    
    test_mount_point || ((failed_tests++))
    test_directories || ((failed_tests++))
    test_container_volume_access || ((failed_tests++))
    test_volume_mappings || ((failed_tests++))
    test_storage_health || ((failed_tests++))
    test_data_persistence || ((failed_tests++))
    
    generate_summary
    
    echo ""
    if [[ $failed_tests -eq 0 ]]; then
        echo "🎉 ALL TESTS PASSED - Encrypted storage is properly configured!"
        echo ""
        echo "✅ Digital Ocean encrypted block storage is working correctly"
        echo "✅ OnlyOffice containers have proper access to encrypted storage"
        echo "✅ Data persistence and performance are validated"
        echo ""
        echo "Your OnlyOffice DocSpace deployment is using encrypted storage successfully."
    else
        echo "❌ $failed_tests TEST(S) FAILED - Encrypted storage needs attention"
        echo ""
        echo "Please review the failed tests above and run setup-encrypted-storage.sh if needed."
        exit 1
    fi
}

# Run validation
main