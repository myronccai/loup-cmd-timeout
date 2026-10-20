#!/usr/bin/env bash
# End-to-end tests: run the built binary and compare its standard output
# (byte for byte), and where given its standard error, and exit status with
# the expected ones. Waits are kept short (at most 2 seconds), and the
# endless `-1` wait and an interrupted countdown are ended by GNU timeout.
#
# usage: tests/e2e.sh BINARY

set -u
BIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0
elapsed_ms=0

now_ms() { echo $(( $(date +%s%N) / 1000000 )); }

# check_file NAME STATUS EXPECTED_FILE [ARGS...]
# Runs BINARY ARGS... with standard input from the file named by $IN
# (default: /dev/null), under `timeout $KILL_AFTER` when that is set (status
# 124 when it fires), and compares standard output with EXPECTED_FILE.
# If $WANT_ERR is set, standard error must equal it too. The run's
# duration is left in $elapsed_ms.
check_file() {
    local name=$1 want_status=$2 want_file=$3
    shift 3
    local start
    start=$(now_ms)
    if [ -n "${KILL_AFTER+set}" ]; then
        timeout "$KILL_AFTER" "$BIN" "$@" < "${IN:-/dev/null}" > "$TMP/out" 2> "$TMP/err"
    else
        "$BIN" "$@" < "${IN:-/dev/null}" > "$TMP/out" 2> "$TMP/err"
    fi
    local status=$?
    elapsed_ms=$(( $(now_ms) - start ))
    local err_ok=1
    if [ -n "${WANT_ERR+set}" ]; then
        printf '%s' "$WANT_ERR" > "$TMP/want_err"
        cmp -s "$TMP/want_err" "$TMP/err" || err_ok=0
    fi
    if [ "$status" -eq "$want_status" ] && cmp -s "$want_file" "$TMP/out" && [ "$err_ok" -eq 1 ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $name (exit $status, expected $want_status)"
        diff <(od -c "$want_file") <(od -c "$TMP/out") | sed 's/^/    /' | head -20
        if [ "$err_ok" -eq 0 ]; then
            diff <(od -c "$TMP/want_err") <(od -c "$TMP/err") | sed 's/^/    stderr /' | head -20
        fi
        sed 's/^/    stderr: /' "$TMP/err" | head -5
    fi
}

# check NAME STATUS EXPECTED_STDOUT [ARGS...]
# As check_file, with the expected output given as a string.
check() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    check_file "$name" "$want_status" "$TMP/want" "$@"
}

# check_both NAME STATUS EXPECTED_STDOUT EXPECTED_STDERR [ARGS...]
check_both() {
    local name=$1 want_status=$2 want_out=$3
    local WANT_ERR=$4
    shift 4
    check "$name" "$want_status" "$want_out" "$@"
}

# took NAME MIN_MS MAX_MS: the last run lasted between MIN_MS and MAX_MS.
took() {
    if [ "$elapsed_ms" -ge "$2" ] && [ "$elapsed_ms" -le "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $1 took ${elapsed_ms} ms, expected $2 to $3 ms"
    fi
}

# line N [WIDTH]: the countdown line for N seconds, the number padded to
# WIDTH columns (default 1).
line() { printf 'Waiting for %*d seconds, press CTRL+C to quit ...' "${2:-1}" "$1"; }

nl=$'\n'
cr=$'\r'
syntax='Type "TIMEOUT /?" for usage.'
range='ERROR: Invalid value for timeout (/T) specified. Valid range is -1 to 99999.'

# Help and version.
help_first='Pause for a number of seconds, showing how many are left.'
"$BIN" '/?' < /dev/null > "$TMP/help" 2>&1
if [ "$(head -1 "$TMP/help")" = "$help_first" ] && [ "$(wc -l < "$TMP/help")" -eq 10 ]; then
    pass=$((pass + 1))
else
    fail=$((fail + 1)); echo "FAIL: /? help"
fi
cp "$TMP/help" "$TMP/help_want"
check_file "-? with a value"      0 "$TMP/help_want" 5 -?
check_file "--help"               0 "$TMP/help_want" --help
check      "--version"            0 $'timeout (loup-cmd-timeout) 0.1.0\n' --version

# Waits: a blank line, the countdown rewritten with \r, a final newline.
check_both "0 seconds"            0 "$nl$(line 0)$nl" '' 0
took       "0 seconds"            0 500
check_both "/T 0 /NOBREAK"        0 "$nl$(line 0)$nl" '' /T 0 /NOBREAK
check_both "/t:2 -nobreak"        0 "$nl$(line 2)$cr$(line 1)$cr$(line 0)$nl" '' /t:2 -nobreak
took       "/t:2 -nobreak"        1900 3000
check_both "-T=1"                 0 "$nl$(line 1)$cr$(line 0)$nl" '' -T=1
took       "-T=1"                 900 2000
check_both "/T 1 after --"        0 "$nl$(line 1)$cr$(line 0)$nl" '' -- 1
check_both "+1"                   0 "$nl$(line 1)$cr$(line 0)$nl" '' +1

# A key press (here: input waiting on stdin) does not end the wait.
printf 'x\n' > "$TMP/keys"
IN="$TMP/keys" check_both "input is ignored" 0 "$nl$(line 1)$cr$(line 0)$nl" '' 1
took       "input is ignored"     900 2000

# Two-digit counts are padded so that each redraw covers the last one;
# GNU timeout ends this one after 1.5 seconds.
KILL_AFTER=1.5 check "interrupted at 9"  124 "$nl$(line 10 2)$cr$(line 9 2)" 10
KILL_AFTER=1.5 check "interrupted 99999" 124 "$nl$(line 99999 5)$cr$(line 99998 5)" /T 99999

# -1 waits until interrupted.
KILL_AFTER=1 check_both "-1"              124 "${nl}Press CTRL+C to quit ..." '' -1
KILL_AFTER=1 check_both "/T -1 /NOBREAK"  124 "${nl}Press CTRL+C to quit ..." '' /T -1 /NOBREAK

# Usage errors and invalid values (ERRORLEVEL 1, nothing on stdout).
check_both "no value"             1 '' "ERROR: Invalid syntax. Value expected for '/T'.$nl$syntax$nl"
check_both "/T without a value"   1 '' "ERROR: Invalid syntax. Value expected for '/t'.$nl$syntax$nl" /t
check_both "/T then a switch"     1 '' "ERROR: Invalid syntax. Value expected for '/T'.$nl$syntax$nl" /T /NOBREAK
check_both "unknown option"       1 '' "ERROR: Invalid argument/option - '/x'.$nl$syntax$nl" 5 /x
check_both "unknown dash option"  1 '' "ERROR: Invalid argument/option - '-wait'.$nl$syntax$nl" -wait 5
check_both "two values"           1 '' "ERROR: Invalid syntax. Default option is not allowed more than '1' time(s).$nl$syntax$nl" 5 6
check_both "/T and a value"       1 '' "ERROR: Invalid syntax. Default option is not allowed more than '1' time(s).$nl$syntax$nl" /T 5 6
check_both "/T twice"             1 '' "ERROR: Invalid syntax. '-t' option is not allowed more than '1' time(s).$nl$syntax$nl" /T 5 -t 6
check_both "/NOBREAK twice"       1 '' "ERROR: Invalid syntax. '/nobreak' option is not allowed more than '1' time(s).$nl$syntax$nl" /NOBREAK 5 /nobreak
check_both "not a number"         1 '' "$range$nl" abc
check_both "not whole"            1 '' "$range$nl" 1.5
check_both "below -1"             1 '' "$range$nl" -2
check_both "above 99999"          1 '' "$range$nl" /T 100000
check_both "option after --"      1 '' "$range$nl" -- /x

echo "e2e: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
