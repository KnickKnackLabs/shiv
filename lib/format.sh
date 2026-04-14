# Formatting utilities for shiv output

# strip_ansi — Remove ANSI escape codes from text
# Handles color codes (\e[...m), cursor control, and mode sequences.
# Usage: echo "$colored_output" | strip_ansi
strip_ansi() {
  sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g'
}
