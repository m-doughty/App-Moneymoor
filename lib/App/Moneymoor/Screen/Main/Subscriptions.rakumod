unit module App::Moneymoor::Screen::Main::Subscriptions;

=begin pod

=head1 NAME

App::Moneymoor::Screen::Main::Subscriptions - the store-subscription
wiring for the Main shell, extracted so the screen class stays a shell
rather than a wiring loom.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Screen::Main::Subscriptions;

App::Moneymoor::Screen::Main::Subscriptions::install-banner($main);
App::Moneymoor::Screen::Main::Subscriptions::install-footer($main);
App::Moneymoor::Screen::Main::Subscriptions::install-content($main);

# Pure, and so directly testable:
hint-for-focus($main, $some-widget);          # 'register'

=end code

=head1 DESCRIPTION

Three install subs, each owning one subscription channel, plus the pure
function they resolve the footer's value with.

=item C<install-banner> — the banner line and the terminal title.
      Registered once; the banner outlives every tab change.
=item C<install-footer> — the hint footer's context, driven by focus
      and by the active tab. Registered once.
=item C<install-content> — whatever the current tab's panes need.
      Re-run by C<!refresh-content-layout> after the panes are rebuilt,
      because the widgets the subscriptions are anchored to are new
      objects each time.
=item C<refresh-footer> — re-resolve the footer's context right now,
      for the moment after a tab swap when the widget the context was
      describing has just been destroyed.

=head2 The selector rule

Every selector here returns a plain scalar — a C<Str>, an C<Int>.
C<Selkie::Store> compares subscription values by content digest and
keys objects by identity, so a selector that built a C<Style>, a
C<Span> or a model object would read as changed on every tick and
re-push its widget every frame. Widgets and styles are built in the
B<callback>; the selector's job is to answer "has anything I care
about moved?" in a form that digests stably.

The banner is the clearest case: the selector composes the whole
string, and the callback does nothing but hand it to two setters.

=head2 Why the clock is not here

C<App::Moneymoor::Widget::BannerBar> carries a right-aligned C<HH:MM>
that never touches the store. It is widget-local state nothing else
reads, and a store dispatch on a fixed period is exactly the
metronomic pattern the idle render ladder exists to avoid. The frame
callback caches the formatted minute and marks the banner dirty only
when the string moves, so 59 seconds out of 60 cost a string compare.

=head1 EXPORTS

=item C<hint-for-focus($main, $focused --> Str)> — a focused widget →
      a C<App::Moneymoor::View::HintBar> context key.

The three C<install-*> subs and C<refresh-footer> are C<our sub>s
called by fully-qualified name from C<Screen::Main>; the module name is
the namespace boundary.

=head1 SEE ALSO

=item L<App::Moneymoor::Screen::Main> — the accessors these read.
=item L<App::Moneymoor::Util::Period> — C<label>, which turns the
      C<app/period> key into the caption the banner shows.
=item L<App::Moneymoor::View::HintBar> — the context table.

=end pod

#|( The banner line: app name, active tab, viewed period, joined with
    the same C<·> the hint bar uses.

    The label comes from the workspace's own scheme rather than from a
    scheme built here, so a budget that is keyed fortnightly says so in
    the banner without this subscription knowing anything about it.
    C<Util::Period.label> answers with the empty string — never an
    exception — for a key that is not a start under that scheme, which
    is what makes it safe inside a selector: an exception here takes
    out the whole subscription walk, and the handful of frames between
    construction and C<app/init> genuinely have no period yet.

    The selector composes the finished string — see "The selector
    rule". The terminal title tracks it too, so the user sees the tab
    and period in their tmux status line or window-manager tooltip
    without switching focus in. )
our sub install-banner($main) {
    my $top-bar = $main.top-bar;
    my $app     = $main.app;
    $main.store.subscribe-with-callback(
        'main-banner',
        -> $s {
            my Str $tab    = ($s.get-in('app', 'tab')    // 'budget').Str;
            my Str $period = ($s.get-in('app', 'period') // '').Str;
            my Str $label  = $main.workspace.scheme.label($period);
            my $line = ' App::Moneymoor · ' ~ $main.tab-label($tab);
            $label.chars ?? $line ~ ' · ' ~ $label !! $line;
        },
        -> Str $t {
            $top-bar.set-text($t);
            $app.set-title($t.trim) if $app.defined;
        },
        $top-bar,
    );
}

#|( The hint footer follows focus, and falls back to the active tab
    when focus is somewhere the footer has no opinion about (the tab
    strip, a modal, nothing at all).

    Two push-based path subscriptions rather than one computed one:
    focus changes and tab changes are both writes, neither needs a
    per-tick recompute, and C<subscribe-path-callback> only fires when
    the path it names is actually written.

    The callback hands C<set-hint-context> a plain context key and the
    screen owns the rendering — nothing about the styling crosses the
    store, which is what keeps this subscription's change digest
    stable. )
our sub install-footer($main) {
    my $store  = $main.store;
    my $footer = $main.hint-footer;

    my &update = -> $ { refresh-footer($main) };

    $store.subscribe-path-callback(
        'moneymoor-hint-footer-focus',
        <ui focused-widget>,
        &update,
        $footer,
    );
    $store.subscribe-path-callback(
        'moneymoor-hint-footer-tab',
        <app tab>,
        &update,
        $footer,
    );
    # The third thing that changes which keys apply without focus
    # moving: §4.5's reconcile mode, which overrides the register's
    # hints with its own for as long as it is running.
    $store.subscribe-path-callback(
        'moneymoor-hint-footer-reconcile',
        <accounts reconcile>,
        &update,
        $footer,
    );
}

#|( Re-resolve the footer's context against whatever has focus right
    now. Called by the three subscriptions above, and directly by
    C<!refresh-content-layout> — a tab swap destroys the pane the
    context was describing, and none of the three paths is guaranteed
    to be written afterwards.

    The mode is read here rather than inside C<hint-for-focus> so that
    resolver stays a function of its two arguments: it is the one part
    of the footer machinery a test can drive without a store. )
our sub refresh-footer($main) {
    my $store = $main.store;
    my $focused = $store.get-in('ui', 'focused-widget');
    my Bool $reconciling = ($store.get-in('accounts', 'reconcile')).defined;
    $main.set-hint-context(hint-for-focus($main, $focused, :$reconciling));
}

#|( Resolve a focused widget to a C<App::Moneymoor::View::HintBar>
    context key.

    Identity comparison against the current tab's pane map rather than
    against captured references: the panes are rebuilt on every tab
    change, so anything captured at install time goes stale, but
    C<$main.pane-contexts> always describes the panes that are mounted
    right now.

    Anything else — the tab strip, the banner, a modal's field, no
    focus at all — is C<generic>, the app-wide keys.

    C<:$reconciling> is §4.5's mode, and it overrides B<only> the
    register: the sidebar keeps its own keys while the mode runs (it
    is still the thing that ends the mode by switching ledger), and no
    other pane is even on screen. Passed in rather than read from the
    store so this stays a function of its arguments. )
sub hint-for-focus($main, $focused, Bool :$reconciling = False --> Str) is export {
    return 'generic' without $focused;
    my Str $context = 'generic';
    for $main.pane-contexts -> $pair {
        if $pair.key === $focused {
            $context = $pair.value;
            last;
        }
    }
    ($reconciling && $context eq 'register') ?? 'reconcile' !! $context;
}

#|( Per-tab subscriptions, anchored on widgets the content rebuild
    replaces. Called from C<!refresh-content-layout> after the new
    panes exist; re-using the same subscription ids replaces any stale
    entry.

    Two things happen here. The shell's own channel — the budget
    grid's frame title, which carries the viewed period — and a
    hand-off to the tab controller for everything that is about the
    tab's own content. The budget tab's four channels (rows, rail,
    pill, rail-presence) live on C<App::Moneymoor::Screen::Budget>, the
    accounts tab's two (sidebar, register) on
    C<App::Moneymoor::Screen::Accounts> and the reports tab's two
    (strip, chart) on C<App::Moneymoor::Screen::Reports>, next to the
    widgets they push into.

    Only the budget grid is in the pane-title loop below. The accounts
    tab's two titles say something the period would crowd out — the
    account's two balances, and the net worth — and the reports tab's
    say which aggregation is on and which period is summarised. Both
    tabs write their own, from the same repaint that fills their
    contents, which is also what keeps a title and the figures under it
    from disagreeing. )
our sub install-content($main) {
    my $store = $main.store;

    my $budget = $main.budget-tab;
    $budget.install-subscriptions if $budget.defined;

    my $accounts = $main.accounts-tab;
    $accounts.install-subscriptions if $accounts.defined;

    my $reports = $main.reports-tab;
    $reports.install-subscriptions if $reports.defined;

    for $main.pane-contexts -> $pair {
        my $pane = $pair.key;
        my $context = $pair.value;
        # The border is the pane's parent; the budget grid puts the
        # viewed period in its title so the user can tell which period
        # a table's numbers belong to without looking up at the banner.
        next unless $context eq 'budget';
        my $border = $pane.parent;
        next without $border;
        my Str $base = 'Envelopes';
        $store.subscribe-with-callback(
            "pane-title-$context",
            -> $s {
                # Same '' -on-anything-that-is-not-a-start contract as
                # the banner's: a selector must not throw, and the
                # scheme is read live off the workspace rather than
                # captured here.
                $main.workspace.scheme.label(
                    ($s.get-in('app', 'period') // '').Str);
            },
            -> Str $label {
                $border.set-title(
                    $label.chars ?? "$base · $label" !! $base);
            },
            $pane,
        );
    }
}
