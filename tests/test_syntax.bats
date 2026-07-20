setup() {
    ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "syntax: all .sh files pass bash -n" {
    local errors=0
    local files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "$ROOT" -name '*.sh' -print0)

    for f in "${files[@]}"; do
        if ! bash -n "$f" 2>/dev/null; then
            echo "SYNTAX ERROR: $f"
            bash -n "$f" 2>&1 || true
            errors=$((errors + 1))
        fi
    done

    echo "$errors file(s) with syntax errors out of ${#files[@]}"
    [ "$errors" -eq 0 ]
}
