# Design: timeout

## Overview

`main()` passes `runtime.args()` to `cli.app.run`, which parses them with
the shared switch parser (`win.switches`), handles `/?` and `--version`, and
calls `commands.timeout.run_timeout(seconds)`. `run_timeout` prints the
countdown, sleeping until the shown number should next change.

## Modules

| Module | Contents |
|---|---|
| `source/main.loup` | entry point: `run(runtime.args())` |
| `source/appinfo.loup` | name, version, summary, exit statuses 0 and 1 |
| `source/cli/args.loup` | `Options`, `timeout_switches()`, `parse_args`, `parse_seconds`, the usage errors |
| `source/cli/usage.loup` | `usage()` (the `/?` summary), `version_line()` |
| `source/cli/app.loup` | `run()`: parse, help/version, run, exceptions to status 1 |
| `source/commands/timeout.loup` | `countdown_line`, `seconds_left`, `ns_until_change`, `countdown_text`, `run_timeout` |
| `source/win/` | the shared Windows code: switches, wildcards, paths, messages |

### Arguments

`timeout_switches()` declares `/T` (`required_value`: `/T 10`, `/T:10`,
`/T=10`) and `/NOBREAK` (`flag`). An undeclared `/x` or `-x` comes back
from the shared parser as an operand; `parse_args` turns it into
`Invalid argument/option` unless it is a number (`-1`) or follows `--`.
Then it counts the values (`/T`'s and the operands), checks for repeated
switches, and parses the value with `parse_int_value` (decimal, optional
sign) and the range -1 to 99999. `Options` is built only in `args.loup`
(`make_options`); `app.loup` passes `opts.seconds` (an `int`) on.

### The countdown

`run_timeout(seconds)`:

1. `-1`: print a blank line and `Press CTRL+C to quit ...`, then sleep an
   hour at a time, for ever.
2. Otherwise read the monotonic clock (`system.time.monotonicNs`) once at
   the start. The total wait is a `core.time.Duration`; each pass computes
   the time left (`total - Duration.ofNanos(now - start)`), and
   `seconds_left` rounds it up to whole seconds. When that is below the
   number on screen, print `\r` and the new line.
3. Sleep (`system.time.sleepNs`) for `ns_until_change`: until the number
   should drop again. A late wake-up (a suspended process) just skips to
   the right number.
4. After showing 0, print a newline and return 0.

`countdown_line(n, width)` right-aligns the number to the width of the
starting value (`digits`, `pad_left`), so every redraw covers the previous
one. `countdown_text(n)` is the full output of an undisturbed wait (used by
the tests and the README).

Each piece is printed with `print` as soon as it is ready: native `print`
writes at once (no buffering), so the countdown is live on a terminal and
a killed run keeps what it printed.

Loup 1.26.0 constraints: `core.time.sleep` does not build natively (an
`async` function), so the program uses `system.time.sleepNs`;
`core.time.Instant.now()` reads the wall clock, so the monotonic clock comes
from `system.time`. Standard input can only be read whole (T2), so a key
press cannot end the wait.

## Differences from the original

- A key press does not end the wait (T2): every wait behaves like
  `/NOBREAK`, which is accepted and changes nothing. The line therefore
  always says `press CTRL+C to quit`, and `-1` waits until CTRL+C.
- The line is rewritten with a carriage return.
- CTRL+C is Linux's SIGINT: the program ends at once, leaving the countdown
  line without a final newline, and the shell reports status 130.
- Redirected standard input is not an error: the program never reads it.
- `/?` prints this project's own short summary, not Microsoft's help text.
- `--help` and `--version` (alone) are series conventions.

## Error handling

Every usage error and invalid value is detected by `parse_args` before
anything is printed on standard output; `run` prints the message on
standard error and returns 1. An unexpected exception is printed as
`ERROR: message` with status 1.

## Testing

- `tests/args_test.loup`: every value form, `/NOBREAK`, help and version,
  `looks_like_option`, `parse_seconds`, every usage error.
- `tests/timeout_test.loup`: `digits`, `pad_left`, `countdown_line`,
  `seconds_left` rounding, `ns_until_change`, `countdown_text`, a 0-second
  wait.
- `tests/app_test.loup`: exit statuses through `run()`, including a
  one-second wait.
- `tests/win_*_test.loup`: the shared Windows code.
- `tests/e2e.sh`: the native binary: exact output bytes (blank line, `\r`
  redraws, final newline) and durations of 0-, 1- and 2-second waits;
  padding and partial output of interrupted waits (ended by GNU `timeout`);
  `-1`; ignored standard input; every error message and status.
