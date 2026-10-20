# Requirements: timeout

## Introduction

`timeout` is the Windows command that pauses a batch file or a console for
a number of seconds and shows how many are left. This repository recreates
it in Loup for Linux, with its switches, messages and ERRORLEVELs and the
Windows conventions from the shared code in `source/win/` (master copy:
loup-cmd-type). Ending the wait early with a key press is deferred
(roadmap constraint T2), so every wait behaves like `/NOBREAK`.

## Requirements

### Requirement 1: Waiting with a countdown

**User Story:** As a batch-file author, I want to pause for a number of
seconds and see how long is left.

#### Acceptance Criteria

1. WHEN a value N from 0 to 99999 is given, THE program SHALL print a blank
   line and `Waiting for N seconds, press CTRL+C to quit ...`, then rewrite
   that line in place (a carriage return, then the new line) each time the
   number of whole seconds left (rounded up) goes down, down to 0, then
   print a newline and exit with status 0.
2. THE program SHALL right-align the number to the width of N, so that every
   redraw has the same length.
3. THE program SHALL time the wait with the monotonic clock, so that the
   countdown does not drift and the total wait is N seconds.
4. WHEN N is 0, THE program SHALL print the line for 0 and return at once.
5. WHEN N is -1, THE program SHALL print a blank line and
   `Press CTRL+C to quit ...` and wait until it is interrupted.
6. THE program SHALL not read standard input: a key press or piped input
   does not end the wait.

### Requirement 2: Arguments

**User Story:** As a cmd user, I want timeout's argument forms.

#### Acceptance Criteria

1. THE program SHALL accept the value as `/T N`, `/T:N`, `/T=N` or a bare
   `N`, with switches starting with `/` or `-` in any case, and `--` ending
   switch parsing. `-1` is a value, not a switch.
2. THE program SHALL accept `/NOBREAK`; it changes nothing, since no wait
   ends on a key press.
3. WHEN `/?` (or `-?`, `--help` alone) is given, THE program SHALL print a
   short summary of the syntax and switches and exit with status 0.
4. WHEN `--version` is the only argument, THE program SHALL print
   `timeout (loup-cmd-timeout) 0.1.0` and exit with status 0.

### Requirement 3: Errors

**User Story:** As a script author, I want clear messages and timeout's
ERRORLEVEL for bad command lines.

#### Acceptance Criteria

1. WHEN no value is given, or `/T` has none, THE program SHALL print
   `ERROR: Invalid syntax. Value expected for '/T'.` (the switch as typed).
2. WHEN an argument before `--` starts with `/` or `-` and is neither a
   switch of timeout nor a number, THE program SHALL print
   `ERROR: Invalid argument/option - 'ARG'.`
3. WHEN more than one value is given (two bare values, or `/T` and a bare
   value), THE program SHALL print `ERROR: Invalid syntax. Default option is
   not allowed more than '1' time(s).`; WHEN `/T` or `/NOBREAK` is repeated,
   `ERROR: Invalid syntax. 'SWITCH' option is not allowed more than '1'
   time(s).`
4. THE messages in 3.1 to 3.3 SHALL be followed by
   `Type "TIMEOUT /?" for usage.`
5. WHEN the value is not a whole number from -1 to 99999, THE program SHALL
   print `ERROR: Invalid value for timeout (/T) specified. Valid range is -1
   to 99999.`
6. THE program SHALL print errors on standard error, print nothing on
   standard output, and exit with status 1.
