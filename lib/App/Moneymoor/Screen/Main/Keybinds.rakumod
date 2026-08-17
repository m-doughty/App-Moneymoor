unit module App::Moneymoor::Screen::Main::Keybinds;

=begin pod

=head1 NAME

App::Moneymoor::Screen::Main::Keybinds - keybind installation for the
Main shell, extracted so the screen class stays readable.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Screen::Main::Keybinds;

App::Moneymoor::Screen::Main::Keybinds::install-global($main);
App::Moneymoor::Screen::Main::Keybinds::install-content($main);

=end code

=head1 DESCRIPTION

Two install subs:

=item C<install-global> — binds on the screen root, so they fire from
      anywhere on the Main screen regardless of which pane has focus:
      C<1> / C<2> / C<3> and C<Ctrl+1> / C<Ctrl+2> / C<Ctrl+3> (tab
      switch), C<[> / C<]> (period navigation), C<Ctrl+G>
      (diagnostics), C<Ctrl+O> (settings), C<Ctrl+H> (the keybind
      overlay). Registered once, at build time.
=item C<install-content> — binds on the current tab's panes, so they
      only fire when that pane has focus. Re-run by
      C<!refresh-content-layout> after a tab change, because the
      widgets they bind to are new objects each time.

Selkie's own defaults — Tab, Shift+Tab, Esc, Ctrl+Q — are untouched.

=head2 Why the period keys are root-level and unmodified

C<[> and C<]> are bare characters, which Selkie refuses for
I<app-global> binds (C<Selkie::App.on-key> demands a modifier so a
global can't eat text input). These are B<widget> binds on the screen
root: a keypress starts at the focused widget and bubbles up, so they
fire only if nothing on the way up consumed them. A C<TextInput> inside
a modal consumes its own characters, and modals route separately
anyway, so a user typing C<[> into a memo field never navigates the
budget.

The period is global state — the banner, the envelope table and the
reports chart all read C<app/period> — so the binds are global too
rather than duplicated onto two tabs' panes.

=head2 The FQN trap

C<our sub> inside a C<unit module> is only reachable as
C<Pkg::Name::sub-name(...)> from a caller that itself has
C<use Pkg::Name>. Without the C<use> below, this module would compile
cleanly and the keybind closures would explode the first time a user
pressed the key — "Could not find symbol '&open-settings'" — because
the lookup happens at runtime, inside the closure. That is why
C<Modals> is C<use>d here even though nothing in this file mentions
the module at compile time.

=head1 SEE ALSO

=item L<App::Moneymoor::Screen::Main::Modals> — what the modal binds open.
=item L<App::Moneymoor::View::HintBar> — the footer that advertises these.

=end pod

use Selkie::Widget::HelpOverlay;

use App::Moneymoor::Screen::Main::Modals;

our sub install-global($main) {
    my $store    = $main.store;
    my $app      = $main.app;
    my $self-ref = $main;
    my $root     = $main.root;

    # 1..3 and Ctrl+1..3, in strip order. Three tabs and three digits:
    # there is no wrap-to-zero case to handle, and a fourth tab would
    # need a deliberate decision about which digit it takes rather than
    # silently landing on 4.
    #
    # Both spellings, because Ctrl+<digit> has no legacy escape
    # encoding — it reaches the app only on terminals speaking the
    # kitty keyboard protocol. Terminal.app, an xterm.js front-end
    # (ttyd, VHS) or plain xterm physically cannot transmit it, and on
    # some of them Ctrl+3 decays to a bare Esc. The bare digit works on
    # every terminal and is safe here for the same reason as `[` / `]`
    # below: a widget bind on the screen root fires only when nothing
    # on the way up consumed the key, so a digit typed into an amount
    # or memo field never switches tabs.
    for $main.tab-names.kv -> $idx, $name {
        for ($idx + 1).Str, 'ctrl+' ~ ($idx + 1) -> $key {
            $root.on-key: $key,
                -> $ { $store.dispatch('app/tab-selected', :$name) },
                :description("Switch to {$main.tab-label($name)}");
        }
    }

    # "Period", not "month": a budget can be on a payday window that
    # lines up with no month at all, and a help overlay promising the
    # previous month on a four-weekly budget would be describing an app
    # the user is not running. Under the calendar-month scheme the
    # banner still says "August 2026", which is where the user reads
    # which one they are on — the key's description only has to say
    # which way it steps.
    $root.on-key: '[',
        -> $ { $store.dispatch('app/period-prev') },
        :description('Previous period');

    $root.on-key: ']',
        -> $ { $store.dispatch('app/period-next') },
        :description('Next period');

    $root.on-key: 'ctrl+g',
        -> $ { App::Moneymoor::Screen::Main::Modals::open-diagnostics($self-ref) },
        :description('Diagnostics');

    # Ctrl+O, not Ctrl+,: terminals without a disambiguating keyboard
    # protocol (Windows Terminal, Apple Terminal, xterm) encode
    # ctrl+punctuation by masking with 0x1F, and ',' & 0x1F is 0x0C —
    # byte-identical to ctrl+l. The combo either misfires or is
    # unreachable there; ctrl+letter combos are distinct C0 bytes
    # everywhere.
    $root.on-key: 'ctrl+o',
        -> $ { App::Moneymoor::Screen::Main::Modals::open-settings($self-ref) },
        :description('Settings');

    # Ctrl+H rather than '?': a payee name, a memo or a category name
    # may legitimately contain a question mark, and a single-character
    # global would eat it. The overlay walks the focus chain, so the
    # listing reflects the pane the user is actually in.
    #
    # `scrimmed` gives it the same backdrop every other Moneymoor modal
    # opens over; HelpOverlay builds its own Modal internally and would
    # otherwise be the one dialog in the app covering the screen with
    # an opaque plane.
    $root.on-key: 'ctrl+h',
        -> $ {
            my $help = Selkie::Widget::HelpOverlay.new(
                :$app, focused-widget => $app.focused,
            );
            $app.show-modal(
                App::Moneymoor::Screen::Main::Modals::scrimmed($help.build),
            );
        },
        :description('Show keyboard shortcuts');
}

#|( Per-pane binds for the tab that is currently mounted, delegated to
    whichever tab controller owns the panes.

    Bound on the pane widget itself rather than on the screen root, so
    C<a> means "assign" only while the envelope table has focus and
    stays an ordinary letter everywhere else — including in a modal's
    text field, which is the case that makes a single-character global
    bind unusable in an app with forms.

    Each tab's own map lives on its controller, next to the widgets the
    keys act on; this is the seam that installs whichever one is
    mounted. §4.3's C<a m x n g e h u i> plus Enter belong to
    C<Screen::Budget>; §4.4's C<n e d c t> on the register (plus
    §4.5's C<Ctrl+R> and its mode-guarded Esc) and C<n e c> on the
    sidebar belong to C<Screen::Accounts>; §4.6's C<b> to
    C<Screen::Reports>. )
our sub install-content($main) {
    my $budget = $main.budget-tab;
    $budget.install-keybinds if $budget.defined;

    my $accounts = $main.accounts-tab;
    $accounts.install-keybinds if $accounts.defined;

    my $reports = $main.reports-tab;
    $reports.install-keybinds if $reports.defined;
}
