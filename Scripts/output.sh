# Sourced by the check scripts: where a script writes its output.
#
# continuumkit_output NAME GIVEN sets `output` to GIVEN, the folder the caller asked for (an
# argument or a CONTINUUMKIT_*_OUTPUT variable), which is kept. With none given, it makes
# `continuumkit-NAME.XXXXXX` under CONTINUUMKIT_OUTPUT_ROOT (TMPDIR by default) and removes it
# when the script exits (continuumkit_cleanup, called from the script's EXIT trap), unless
# CONTINUUMKIT_KEEP_OUTPUT=1.

continuumkit_discard=

continuumkit_output() {
    local name=$1 given=${2:-}
    if test -n "$given"; then
        output=$given
        return
    fi
    local parent=${CONTINUUMKIT_OUTPUT_ROOT:-${TMPDIR:-/tmp}}
    mkdir -p "$parent"
    output=$(mktemp -d "${parent%/}/continuumkit-$name.XXXXXX")
    if test "${CONTINUUMKIT_KEEP_OUTPUT:-0}" = 1; then
        echo "Keeping the output in $output" >&2
    else
        continuumkit_discard=$output
    fi
}

continuumkit_cleanup() {
    if test -n "$continuumkit_discard"; then
        rm -rf "$continuumkit_discard"
    fi
}
