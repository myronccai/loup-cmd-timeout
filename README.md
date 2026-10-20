# loup-cmd-timeout

The Windows `timeout` command recreated in [Loup](https://code-craft.ai/references/loup):
wait for a number of seconds with a live countdown that is rewritten in
place, with timeout's switches, messages and ERRORLEVELs, on Linux.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is `host.dual` Loup built as a native binary. It shows `core.time`
durations, the monotonic clock and sleeping from `system.time`, and
in-place terminal output. It uses the shared Windows code in
[`source/win/`](source/win/) (switch parser, wildcard matcher, path helpers,
messages), copied from [loup-cmd-type](https://github.com/myronccai/loup-cmd-type).

## Requirements

- Loup 1.26.0 or later:

  ```sh
  curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
  ```

- `make`, and `clang` 17 or later for the native build.

## Usage

```sh
make build                    # native binary: build/timeout
make ci                       # check, unit tests, build, end-to-end tests
make run ARGS="/T 3"          # run from source with loup run
```

The countdown line is redrawn every second (a carriage return, then the new
line), so a terminal shows one line counting down. When it has finished:

```text
$ build/timeout 5

Waiting for 0 seconds, press CTRL+C to quit ...
$ echo "ERRORLEVEL $?"
ERRORLEVEL 0
```

Redirected, the redraws are visible (`^M` is the carriage return):

```text
$ build/timeout /T 2 /NOBREAK > out.txt; cat -A out.txt
$
Waiting for 2 seconds, press CTRL+C to quit ...^MWaiting for 1 seconds, press CTRL+C to quit ...^MWaiting for 0 seconds, press CTRL+C to quit ...$
```

The number keeps the width of the starting value, so each redraw covers
the previous one:

```text
$ build/timeout 12 | tr '\r' '\n' | head -3

Waiting for 12 seconds, press CTRL+C to quit ...
Waiting for 11 seconds, press CTRL+C to quit ...
```

Errors:

```text
$ build/timeout 100000; echo "ERRORLEVEL $?"
ERROR: Invalid value for timeout (/T) specified. Valid range is -1 to 99999.
ERRORLEVEL 1
$ build/timeout /T 5 6; echo "ERRORLEVEL $?"
ERROR: Invalid syntax. Default option is not allowed more than '1' time(s).
Type "TIMEOUT /?" for usage.
ERRORLEVEL 1
$ build/timeout /x
ERROR: Invalid argument/option - '/x'.
Type "TIMEOUT /?" for usage.
$ build/timeout
ERROR: Invalid syntax. Value expected for '/T'.
Type "TIMEOUT /?" for usage.
$ build/timeout --version
timeout (loup-cmd-timeout) 0.1.0
```

```text
TIMEOUT [/T] seconds [/NOBREAK]
```

| Argument or switch | Effect |
|---|---|
| `seconds` | how long to wait, -1 to 99999; also `/T seconds`, `/T:seconds` or `/T=seconds` |
| `-1` | wait until CTRL+C (`Press CTRL+C to quit ...`) |
| `/NOBREAK` | accepted; changes nothing (no wait ends on a key press, see below) |
| `/?` | a summary of the syntax and switches |

Switches start with `/` or `-`, in any case; `--` ends switch parsing. A
negative number such as `-1` is a value, not a switch.

The countdown follows the monotonic clock: the program sleeps until the
number should next change, so it does not drift (a 2-second wait takes 2.0
seconds) and is not affected by changes to the wall clock.

Exit status (ERRORLEVEL): `0` when the wait ends, `1` for a usage error or
an invalid value (the message goes to standard error, nothing to standard
output).

## Differences from the original

- A key press does not end the wait: Loup 1.26.0 can only read standard
  input as a whole (roadmap constraint T2). Every wait behaves like
  `/NOBREAK`, which is accepted and has no effect, so the line always says
  `press CTRL+C to quit ...` and `-1` waits until CTRL+C.
- The countdown line is rewritten with a carriage return.
- CTRL+C is Linux's SIGINT: the program stops at once, the countdown line is
  left without a final newline, and the shell reports status 130.
- Redirected standard input is not an error: the program never reads it.
- Error messages follow the style of Windows' command-line tools
  (`ERROR: ...` and `Type "TIMEOUT /?" for usage.`); the exact wording of
  some cases may differ from timeout.exe's.
- `/?` prints this project's own short summary of the syntax and switches,
  not Microsoft's help text.
- `--help` and `--version` as the only argument are series conventions.

## Layout

```text
source/main.loup                # entry point
source/appinfo.loup             # name, version, exit statuses 0/1
source/cli/args.loup            # /T, /NOBREAK, the value and usage errors via win.switches
source/cli/usage.loup           # /? and --version text
source/cli/app.loup             # run(): parse, run, exit status
source/commands/timeout.loup    # countdown line, rounding, the timed wait
source/win/                     # shared Windows code: switches, wildcards, paths, messages
tests/*_test.loup               # unit tests (make test)
tests/e2e.sh                    # end-to-end tests of build/timeout (make e2e)
specs/timeout/                  # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every build and test command and the conventions
for changing the code.
