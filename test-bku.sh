#!/bin/bash

# test_bku.sh: Self-test script for BKU implementation with system-wide install

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test directory
TEST_DIR="bku_test_dir"
BKU_SCRIPT="./bku.sh"
SETUP_SCRIPT="./setup.sh"
INSTALL_PATH="/usr/local/bin/bku"
RUN_PATH=$(pwd)

# Counter for test results
PASSED=0
FAILED=0

COMMIT_ID_REGEX='[0-9]{2}:[0-9]{2}-[0-9]{2}/[0-9]{2}/[0-9]{4}'

# Function to print test result
print_result() {
    if [[ $1 -eq 0 ]]; then
        echo -e "${GREEN}PASS${NC}: $2"
        ((PASSED++))
    else
        echo -e "${RED}FAIL${NC}: $2"
        ((FAILED++))
    fi
}

# Function to clean up test environment
cleanup() {
    rm -rf "$TEST_DIR"
    if [[ -f "$INSTALL_PATH" ]]; then
        sudo rm -f "$INSTALL_PATH" 2>/dev/null
    fi
    # Remove cron jobs
    crontab -l 2>/dev/null | grep -v "$BKU_SCRIPT" | crontab - 2>/dev/null || true
}

# Check if scripts exist
if [[ ! -f "$BKU_SCRIPT" || ! -f "$SETUP_SCRIPT" ]]; then
    echo "Error: $BKU_SCRIPT and/or $SETUP_SCRIPT not found in current directory."
    exit 1
fi

# Check if sudo is available
if ! command -v sudo >/dev/null 2>&1; then
    echo "Error: This test requires sudo privileges for installation to $INSTALL_PATH."
    exit 1
fi

# Start testing
echo "Starting BKU self-test..."
echo "Note: This test requires sudo privileges for installation/uninstallation."
echo "Output files (*.txt) will be generated for debugging failed tests."
echo "--------------------------------"

# Clean up any previous test environment
rm -rf *.txt
cleanup

# Test 1: Installation
echo "Test 1: Installation"
sudo bash "$SETUP_SCRIPT" --install > install_output.txt 2>&1
if [[ $? -eq 0 && -f "$INSTALL_PATH" && -x "$INSTALL_PATH" \
    && $(grep -c "^Checking dependencies\.\.\.$" install_output.txt) -eq 1 \
    && $(grep -c "^All dependencies installed\.$" install_output.txt) -eq 1 \
    && $(grep -c "^BKU installed to /usr/local/bin/bku\.$" install_output.txt) -eq 1 ]]; then
    print_result 0 "Installation successful"
else
    print_result 1 "Installation failed (check install_output.txt)"
fi

# Create test directory and source files
mkdir "$TEST_DIR"
cd "$TEST_DIR"
mkdir src

# Create src/main.c
cat << 'EOF' > src/main.c
#include <stdio.h>

int main() {
    printf("Hello, World!\n");
    return 0;
}
EOF

# Create src/utils.c
cat << 'EOF' > src/utils.c
#include <stdio.h>

void print_utility() {
    printf("Utility function\n");
}
EOF

# Test 2: Initialize Backup Repository
echo "Test 2: Initialize Backup Repository"
bku init > $RUN_PATH/init_output.txt 2>&1
if [[ $? -eq 0 && -d ".bku" && $(grep -c "^Backup initialized\.$" $RUN_PATH/init_output.txt) -eq 1 ]]; then
    print_result 0 "Backup initialized successfully"
else
    print_result 1 "Backup initialization failed (check init_output.txt)"
fi

# Test 3: Add Files (Single File)
echo "Test 3: Add Single File"
bku add src/main.c > $RUN_PATH/add_single_output.txt 2>&1
bku status src/main.c > /dev/null 2>&1  # Test if file is tracked
if [[ $? -eq 0 && $(grep -c "^Added src/main.c to backup tracking\.$" $RUN_PATH/add_single_output.txt) -eq 1 ]]; then
    print_result 0 "Added single file successfully"
else
    print_result 1 "Failed to add single file (check add_single_output.txt)"
fi

# Test 4: Add Files (All Files), remaining files are src/utils.c
echo "Test 4: Add All Files"
bku add > $RUN_PATH/add_all_output.txt 2>&1
bku status > $RUN_PATH/temp_status.txt 2>&1
if [[ $? -eq 0 \
    && $(grep -c "^Added src/utils.c to backup tracking\.$" $RUN_PATH/add_all_output.txt) -eq 1 \
    && $(grep -c "^src/main.c:" $RUN_PATH/temp_status.txt) -gt 0 \
    && $(grep -c "^src/utils.c:" $RUN_PATH/temp_status.txt) -gt 0 ]]; then
    print_result 0 "Added all files successfully"
else
    print_result 1 "Failed to add all files (check add_all_output.txt)"
fi

# Test 5: Status (Single File)
echo "Test 5: Status Single File"
echo -e "#include <stdio.h>\n\nint main() {\n    printf(\"Modified Hello!\n\");\n    return 0;\n}" > src/main.c
bku status src/main.c > $RUN_PATH/status_single_output.txt 2>&1
if [[ $? -eq 0 \
    && $(grep -c "^src/main.c:$" $RUN_PATH/status_single_output.txt) -eq 1 \
    && $(grep -c "^@@ " $RUN_PATH/status_single_output.txt) -gt 0 ]]; then
    print_result 0 "Status for single file shows changes"
else
    print_result 1 "Status for single file failed (check status_single_output.txt)"
fi

# Test 6: Status (All Files)
echo "Test 6: Status All Files"
bku status > $RUN_PATH/status_all_output.txt 2>&1
if [[ $? -eq 0 \
    && $(grep -c "^src/main.c:$" "$RUN_PATH/status_all_output.txt") -eq 1 \
    && $(grep -c "^src/utils.c: No changes$" $RUN_PATH/status_all_output.txt) -eq 1 \
    && $(grep -c "^@@ " "$RUN_PATH/status_all_output.txt") -gt 0 ]]; then
    print_result 0 "Status for all files shows correct output"
else
    print_result 1 "Status for all files failed (check status_all_output.txt)"
fi

# Test 7: Commit (Single File)
echo "Test 7: Commit Single File"
bku commit "Added modification" src/main.c > $RUN_PATH/commit_single_output.txt 2>&1
bku history > $RUN_PATH/temp_history.txt 2>&1
if [[ $? -eq 0 \
    && $(grep -E -c "^Committed src/main.c with ID ${COMMIT_ID_REGEX}\.$" $RUN_PATH/commit_single_output.txt) -eq 1 \
    && $(grep -c "Added modification" $RUN_PATH/temp_history.txt) -gt 0 ]]; then
    print_result 0 "Committed single file successfully"
else
    print_result 1 "Commit single file failed (check commit_single_output.txt)"
fi

# Test 8: Commit (All Files)
echo "Test 8: Commit All Files"
echo -e "#include <stdio.h>\n\nvoid print_utility() {\n    printf(\"Updated utility\n\");\n}" > src/utils.c
bku commit "Updated utils" > $RUN_PATH/commit_all_output.txt 2>&1
if [[ $? -eq 0 \
    && $(grep -E -c "^Committed src/utils.c with ID ${COMMIT_ID_REGEX}\.$" $RUN_PATH/commit_all_output.txt) -eq 1 ]]; then
    print_result 0 "Committed all files successfully"
else
    print_result 1 "Commit all files failed (check commit_all_output.txt)"
fi

# Test 9: History
echo "Test 9: History"
bku history > $RUN_PATH/history_output.txt 2>&1
LAST_HISTORY_LINE=$(tail -n 1 $RUN_PATH/history_output.txt 2>/dev/null)
if [[ $? -eq 0 \
    && $(grep -E -c "^${COMMIT_ID_REGEX}: .*\\.$" $RUN_PATH/history_output.txt) -ge 2 \
    && $(grep -c "Added modification" $RUN_PATH/history_output.txt) -gt 0 \
    && "$LAST_HISTORY_LINE" =~ ^${COMMIT_ID_REGEX}:\ BKU\ Init\.$ ]]; then
    print_result 0 "History displayed correctly"
else
    print_result 1 "History failed (check history_output.txt)"
fi

# Test 10: Restore (Single File)
echo "Test 10: Restore Single File"
echo -e "#include <stdio.h>\n\nint main() {\n    printf(\"New content\n\");\n    return 0;\n}" > src/main.c
bku commit "New change" src/main.c > $RUN_PATH/commit_new_output.txt 2>&1
bku restore src/main.c > $RUN_PATH/restore_single_output.txt 2>&1
if [[ $? -eq 0 \
    && $(grep -c "printf(\"Modified Hello" src/main.c) -eq 1 \
    && $(grep -c "^Restored src/main.c to its previous version\.$" $RUN_PATH/restore_single_output.txt) -eq 1 ]]; then
    print_result 0 "Restored single file successfully"
else
    print_result 1 "Restore single file failed (check restore_single_output.txt)"
fi

# Test 11: Restore (All Files)
echo "Test 11: Restore All Files"
echo -e "#include <stdio.h>\n\nint main() {\n    printf(\"Latest main\n\");\n    return 0;\n}" > src/main.c
echo -e "#include <stdio.h>\n\nvoid print_utility() {\n    printf(\"Latest utils\n\");\n}" > src/utils.c
bku commit "Latest change" > $RUN_PATH/commit_latest_output.txt 2>&1
bku restore > $RUN_PATH/restore_all_output.txt 2>&1
if [[ $? -eq 0 \
    && $(grep -c "printf(\"Modified Hello" src/main.c) -eq 1 \
    && $(grep -c "printf(\"Updated utility" src/utils.c) -eq 1 \
    && $(grep -c "^Restored src/main.c to its previous version\.$" $RUN_PATH/restore_all_output.txt) -eq 1 \
    && $(grep -c "^Restored src/utils.c to its previous version\.$" $RUN_PATH/restore_all_output.txt) -eq 1 ]]; then
    print_result 0 "Restored all files successfully"
else
    print_result 1 "Restore all files failed (check restore_all_output.txt)"
fi

# Test 12: Schedule (Daily)
echo "Test 12: Schedule Daily"
bku schedule --daily > $RUN_PATH/schedule_output.txt 2>&1
if [[ $? -eq 0 \
    && $(grep -c "^Scheduled daily backups at daily\.$" $RUN_PATH/schedule_output.txt) -eq 1 \
    && $(crontab -l 2>/dev/null | grep -c "Scheduled backup") -ge 1 ]]; then
    print_result 0 "Scheduled daily backup successfully"
else
    print_result 1 "Schedule daily failed (check schedule_output.txt)"
fi

# Test 13: Schedule (Off)
echo "Test 13: Schedule Off"
bku schedule --off > $RUN_PATH/schedule_off_output.txt 2>&1
if [[ $? -eq 0 \
    && $(grep -c "^Backup scheduling disabled\.$" $RUN_PATH/schedule_off_output.txt) -eq 1 \
    && $(crontab -l 2>/dev/null | grep -c "bku.sh") -eq 0 ]]; then
    print_result 0 "Disabled scheduling successfully"
else
    print_result 1 "Schedule off failed (check schedule_off_output.txt)"
fi

# Test 14: Stop Backup
echo "Test 14: Stop Backup"
bku stop > $RUN_PATH/stop_output.txt 2>&1
if [[ $? -eq 0 && ! -d ".bku" && $(grep -c "^Backup system removed\.$" $RUN_PATH/stop_output.txt) -eq 1 ]]; then
    print_result 0 "Backup system removed successfully"
else
    print_result 1 "Stop backup failed (check stop_output.txt)"
fi

# Test 15: Uninstall
echo "Test 15: Uninstall"
cd ..
sudo bash "$SETUP_SCRIPT" --uninstall > uninstall_output.txt 2>&1
if [[ $? -eq 0 && ! -f "$INSTALL_PATH" \
    && $(grep -c "^Checking BKU installation\.\.\.$" uninstall_output.txt) -eq 1 \
    && $(grep -c "^Removing BKU from /usr/local/bin/bku\.\.\.$" uninstall_output.txt) -eq 1 \
    && $(grep -c "^Removing scheduled backups\.\.\.$" uninstall_output.txt) -eq 1 \
    && $(grep -c "^BKU successfully uninstalled\.$" uninstall_output.txt) -eq 1 ]]; then
    print_result 0 "Uninstallation successful"
else
    print_result 1 "Uninstallation failed (check uninstall_output.txt)"
fi

# Clean up
cleanup
echo "Output files (*.txt) preserved for debugging. Remove manually with 'rm *_output.txt' if desired."

# Summary
echo "--------------------------------"
echo "Test Summary:"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
else
    echo -e "${RED}Some tests failed. Review the output files (*.txt) for details.${NC}"
fi
