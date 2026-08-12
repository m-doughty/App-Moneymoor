# The README recording. Regenerate with xxt/demo/record.sh, which
# prepares /tmp/moneymoor-demo (clean data home + a config.json opting
# into nerd icons) and runs vhs from the module root — Output and the
# launch command below both assume that working directory.
#
# Pacing notes, learned the hard way:
#   - Toasts live for ~2.2s and their teardown can eat a focus step, so
#     every save is followed by Sleep 3s before the next keypress.
#   - Modals open over a 120ms scrim fade — Sleep before typing into one.
#   - Select dropdowns: Enter opens, Up/Down moves, Enter commits.
#     RadioGroups: Down moves the cursor, Space commits it.
#   - Tab switching uses the bare digit keys: Ctrl+digit cannot be
#     transmitted by xterm.js (which is what vhs records through).
Output docs/demo.gif
Set FontFamily "Maple Mono NF"
Set FontSize 18
Set Width 1400
Set Height 840
Set Padding 10
Set TypingSpeed 100ms

Hide
Type "export MONEYMOOR_HOME=/tmp/moneymoor-demo"
Enter
Type "raku -I lib -I ../Selkie/lib -I ../Notcurses-Native/lib bin/moneymoor"
Enter
Sleep 8s
Show

# ---- Create a budget (empty data home opens straight into create mode) ----
Sleep 1s
Type "demo"
Sleep 500ms
Enter
Type@50ms "otter-radar-plinth"
Sleep 1s
Enter
Type@50ms "otter-radar-plinth"
Sleep 500ms
Enter
Sleep 2.5s

# ---- First-run period picker: Esc keeps the calendar month ----
Escape
Sleep 1s

# ---- A group and three envelopes, two with targets ----
Type "g"
Sleep 500ms
Type "Essentials"
Sleep 300ms
Enter
Sleep 3s

Type "n"
Sleep 500ms
Type "Groceries"
Tab@200ms
Sleep 300ms
Enter
Sleep 300ms
Down
Sleep 300ms
Enter
Sleep 300ms
Tab@200ms 4
Sleep 300ms
Type "400"
Sleep 300ms
Enter
Sleep 3s

Type "n"
Sleep 500ms
Type "Rent"
Tab@200ms
Sleep 300ms
Enter
Sleep 300ms
Down
Sleep 300ms
Enter
Sleep 300ms
Tab@200ms 4
Sleep 300ms
Type "950"
Sleep 300ms
Enter
Sleep 3s

Type "n"
Sleep 500ms
Type "Fun Money"
Sleep 300ms
Enter
Sleep 3s

# ---- An account on the Accounts tab ----
Type "2"
Sleep 1s
Type "n"
Sleep 500ms
Type "Current Account"
Sleep 300ms
Enter
Sleep 3s

# ---- Payday: an inflow into Ready to Assign ----
Enter
Sleep 500ms
Type "n"
Sleep 500ms
Tab@200ms 2
Sleep 300ms
Type "Employer"
Sleep 300ms
Tab@200ms
Sleep 300ms
Down
Sleep 300ms
Space
Sleep 300ms
Tab@200ms
Sleep 300ms
Type "2500"
Sleep 500ms
Enter
Sleep 3s

# ---- Allocate: fund every target at once, then assign by hand ----
Type "1"
Sleep 2s
Type "f"
Sleep 2.5s
Enter
Sleep 3s
Down
Sleep 300ms
Down
Sleep 300ms
Down
Sleep 300ms
Down
Sleep 300ms
Type "a"
Sleep 500ms
Ctrl+A
Type "150"
Sleep 500ms
Enter
Sleep 3s

# ---- Spend against an envelope ----
Type "2"
Sleep 1s
Enter
Sleep 500ms
Type "n"
Sleep 500ms
Tab@200ms 2
Sleep 300ms
Type "Tesco"
Sleep 300ms
Tab@200ms 2
Sleep 300ms
Type "72.50"
Sleep 300ms
Tab@200ms
Sleep 300ms
Enter
Sleep 500ms
Down
Sleep 300ms
Enter
Sleep 500ms
Ctrl+S
Sleep 3s

# ---- The month's report ----
Type "3"
Sleep 3s
Type "b"
Sleep 2s

# ---- End on the funded grid, activity showing ----
Type "1"
Sleep 5s

Hide
Ctrl+Q
Sleep 2s
