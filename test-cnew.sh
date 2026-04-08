#!/bin/bash

# Self-test script for the cnew exercise

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

RUN_PATH=$(pwd)
CNEW_BIN="./cnew"
INSTALL_PATH="/usr/local/bin/cnew"
TEST_PROJECT="student-cnew-project"
TEST_GIT_PROJECT="student-cnew-git-project"

PASSED=0
FAILED=0
SKIPPED=0

print_result() {
    if [[ $1 -eq 0 ]]; then
        printf "%b\n" "${GREEN}PASS${NC}: $2"
        ((PASSED++))
    else
        printf "%b\n" "${RED}FAIL${NC}: $2"
        ((FAILED++))
    fi
}

print_skip() {
    echo "SKIP: $1"
    ((SKIPPED++))
}

can_use_sudo() {
    command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1
}

cleanup() {
    rm -rf "$TEST_PROJECT" "$TEST_GIT_PROJECT"
    if [[ -f "$INSTALL_PATH" ]]; then
        if can_use_sudo; then
            sudo rm -f "$INSTALL_PATH" 2>/dev/null
        elif [[ -w "$INSTALL_PATH" || -w "$(dirname "$INSTALL_PATH")" ]]; then
            rm -f "$INSTALL_PATH" 2>/dev/null
        fi
    fi
}

require_file() {
    if [[ ! -f "$1" ]]; then
        echo "Error: required file '$1' not found."
        exit 1
    fi
}

echo "Starting cnew self-test..."
echo "Note: install/uninstall tests require sudo privileges."
echo "Output files (*.txt) will be generated for debugging failed tests."
echo "--------------------------------"

require_file "main.c"
require_file "Makefile"

rm -f ./*_output.txt ./*_stdout.txt ./*_stderr.txt ./*_status.txt
cleanup

echo "Test 1: Build cnew"
make clean > build_clean_output.txt 2>&1
make > build_output.txt 2>&1
if [[ $? -eq 0 && -x "$CNEW_BIN" ]]; then
    print_result 0 "Build successful"
else
    print_result 1 "Build failed (check build_output.txt)"
fi

echo "Test 2: Display help"
"$CNEW_BIN" --help > help_output.txt 2>&1
if [[ $? -eq 0 ]] && grep -q "Usage: cnew" help_output.txt && grep -q -- "--name <project-name>" help_output.txt; then
    print_result 0 "Help output looks correct"
else
    print_result 1 "Help output is missing expected content (check help_output.txt)"
fi

echo "Test 3: Reject invalid project name"
"$CNEW_BIN" --name "my project" > invalid_name_output.txt 2>&1
if [[ $? -ne 0 ]] && grep -q "invalid" invalid_name_output.txt; then
    print_result 0 "Invalid project name rejected"
else
    print_result 1 "Invalid project name was not handled correctly (check invalid_name_output.txt)"
fi

echo "Test 4: Reject existing directory"
mkdir -p "$TEST_PROJECT"
"$CNEW_BIN" --name "$TEST_PROJECT" > existing_dir_output.txt 2>&1
if [[ $? -ne 0 ]] && grep -q "already exists" existing_dir_output.txt; then
    print_result 0 "Existing directory detected"
else
    print_result 1 "Existing directory case failed (check existing_dir_output.txt)"
fi
rm -rf "$TEST_PROJECT"

echo "Test 5: Create a basic project"
"$CNEW_BIN" --name "$TEST_PROJECT" > create_project_output.txt 2>&1
if [[ $? -eq 0 && -d "$TEST_PROJECT" && -d "$TEST_PROJECT/src" && -d "$TEST_PROJECT/include" \
    && -f "$TEST_PROJECT/src/main.c" && -f "$TEST_PROJECT/Makefile" && -f "$TEST_PROJECT/README.md" ]]; then
    print_result 0 "Project structure created successfully"
else
    print_result 1 "Project structure creation failed (check create_project_output.txt)"
fi

echo "Test 6: README contains the project name"
if [[ -f "$TEST_PROJECT/README.md" ]] && grep -q "^# $TEST_PROJECT" "$TEST_PROJECT/README.md"; then
    print_result 0 "README content looks correct"
else
    print_result 1 "README content is incorrect"
fi

echo "Test 7: Generated project builds and runs"
(
    cd "$TEST_PROJECT" || exit 1
    make clean > "$RUN_PATH/generated_clean_output.txt" 2>&1
    make all > "$RUN_PATH/generated_build_output.txt" 2>&1
) 
BUILD_STATUS=$?
if [[ $BUILD_STATUS -eq 0 && -x "$TEST_PROJECT/program" ]]; then
    (
        cd "$TEST_PROJECT" || exit 1
        ./program > "$RUN_PATH/generated_run_output.txt" 2>&1
    )
    RUN_STATUS=$?
    if [[ $RUN_STATUS -eq 0 ]]; then
        print_result 0 "Generated project can build and run"
    else
        print_result 1 "Generated program failed to run (check generated_run_output.txt)"
    fi
else
    print_result 1 "Generated project failed to build (check generated_build_output.txt)"
fi

echo "Test 8: make clean removes the generated binary"
(
    cd "$TEST_PROJECT" || exit 1
    make clean > "$RUN_PATH/generated_clean_verify_output.txt" 2>&1
)
if [[ $? -eq 0 && ! -f "$TEST_PROJECT/program" ]]; then
    print_result 0 "make clean works correctly"
else
    print_result 1 "make clean did not remove the binary"
fi

echo "Test 9: Create a Git-enabled project"
if ! command -v git >/dev/null 2>&1; then
    print_skip "Git is not installed; cannot verify --with-git"
else
    "$CNEW_BIN" --name "$TEST_GIT_PROJECT" --with-git > create_git_project_output.txt 2>&1
    if [[ $? -eq 0 && -d "$TEST_GIT_PROJECT/.git" && -f "$TEST_GIT_PROJECT/.gitignore" ]]; then
        if grep -q "\\*\\.o" "$TEST_GIT_PROJECT/.gitignore" && grep -q "program" "$TEST_GIT_PROJECT/.gitignore"; then
            print_result 0 "Git-enabled project created successfully"
        else
            print_result 1 ".gitignore is missing expected entries"
        fi
    else
        print_result 1 "Git-enabled project creation failed (check create_git_project_output.txt)"
    fi
fi

echo "Test 10: Install cnew"
if can_use_sudo; then
    make install > install_output.txt 2>&1
    if [[ $? -eq 0 && -x "$INSTALL_PATH" ]]; then
        "$INSTALL_PATH" --help > installed_help_output.txt 2>&1
        if [[ $? -eq 0 ]]; then
            print_result 0 "Installation successful"
        else
            print_result 1 "Installed binary did not run correctly (check installed_help_output.txt)"
        fi
    else
        print_result 1 "Installation failed (check install_output.txt)"
    fi
else
    print_skip "sudo is unavailable in non-interactive mode; skipping install test"
fi

echo "Test 11: Uninstall cnew"
if [[ -f "$INSTALL_PATH" ]] && can_use_sudo; then
    make uninstall > uninstall_output.txt 2>&1
    if [[ $? -eq 0 && ! -f "$INSTALL_PATH" ]]; then
        print_result 0 "Uninstallation successful"
    else
        print_result 1 "Uninstallation failed (check uninstall_output.txt)"
    fi
else
    print_skip "Install test was not run; skipping uninstall test"
fi

cleanup

echo "--------------------------------"
echo "Test Summary:"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "Skipped: $SKIPPED"
if [[ $FAILED -eq 0 ]]; then
    printf "%b\n" "${GREEN}All tests passed!${NC}"
else
    printf "%b\n" "${RED}Some tests failed. Review the output files (*.txt) for details.${NC}"
    exit 1
fi
