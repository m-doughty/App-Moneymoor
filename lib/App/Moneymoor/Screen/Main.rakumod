=begin pod

=head1 NAME

App::Moneymoor::Screen::Main - the application shell: banner, tab strip,
content host, hint footer, and the caches every tab reads from.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Screen::Main;

my $main = App::Moneymoor::Screen::Main.new(
    app       => $app,
    db        => $db,
    workspace => $workspace,
    config    => $config,
    theme     => $theme,
);
$app.add-screen('main', $main.build);
$app.switch-screen('main');
$main.focus-content;    # the budget table, on the tab that is mounted

# Everything downstream reads the cache, never the gateways:
$main.view.rta($main.viewed-period);     # the cached BudgetView
$main.category($id).name;                # id → model, rebuilt per recompute

=end code

=head1 DESCRIPTION

    VBox(flex)
     ├ BannerBar(fixed 1)      ' App::Moneymoor · Budget · August 2026'  + clock
     ├ TabBar(fixed 1)         Budget / Accounts / Reports
     ├ VBox(flex)              content host — one child, swapped per tab
     └ RichText(fixed 1)       hint footer

A plain class, not a widget: it owns the tree rather than being part of
one. Its job is the four things a tab builder should not have to think
about — the palette, the glyph tier, the cached C<BudgetView> plus the
id → model lookup hashes, and the store — and it exposes all of them
through public accessors, which are the module boundary for the
C<Keybinds> / C<Modals> / C<Subscriptions> siblings.

=head2 The cache, and why it is not in the store

C<Selkie::Store> digests subscription values to decide whether anything
changed, and it keys objects by identity. A selector handing back a
C<BudgetView> — or a Hash of C<Model::Category> objects — would read as
"changed" on every tick and repaint the whole screen sixty times a
second. So the view and the four lookup hashes live here, and the store
carries C<budget/digest>: a byte-stable, order-independent string the
derivation computes for exactly this purpose. Subscriptions watch the
digest; their callbacks pull from these accessors.

C<set-view> is the sink the C<ws/mutate> effect calls (wired in
C<!register-handlers>), so the cache and the digest can never disagree
— they are written by the same recompute.

=head2 Tab switching

The tab strip, C<1> / C<2> / C<3> and C<Ctrl+1> / C<Ctrl+2> /
C<Ctrl+3> all dispatch
C<app/tab-selected>. A store subscription on C<app/tab> then drives
C<!refresh-content-layout>, which clears the content host — destroying
the departing subtree and, with it, its subscriptions — builds the new
tab's panes, pushes the store down to them, and re-installs that tab's
subscriptions and keybinds.

Doing it through the store rather than straight from the tab callback
is what makes the two entry points converge: a keybind switch and a
click both end as one write to C<app/tab>, and the strip re-syncs from
the same subscription.

The last step of a re-mount is C<focus-content>: the widget that had
focus was destroyed with the departing subtree, and Selkie does not
move focus on its own, so without it the new tab would be on screen
with the keyboard still pointing at nothing and the footer showing the
generic hints. The one mount that does B<not> focus is the first, from
inside C<build> — the screen has not been switched to yet, and
C<Selkie::App.switch-screen> restores its own remembered focus after
the fact, so placing the initial focus is C<UI>'s job.

=head2 The tab builders

C<!build-budget-pane> hands off to C<App::Moneymoor::Screen::Budget>,
which owns the envelope table, the Ready-to-Assign pill and the detail
rail, and which the shell keeps a reference to in C<budget-tab> so the
budget keybinds and modals can find the table after a rebuild.
C<!build-accounts-pane> does the same for
C<App::Moneymoor::Screen::Accounts> and C<accounts-tab>: the sidebar,
the register and the nine dialogs that change what either says.
C<!build-reports-pane> for C<App::Moneymoor::Screen::Reports> and
C<reports-tab>: the period's cash-flow strip and the chart of what it
went on.

All three go through the same seams — the builder contract,
C<mount-pane>, the per-tab subscription and keybind installs, the
per-pane hint-context map, the store cascade — which is what let each
tab land inside them without the shell changing shape.

=head2 One resize callback, for the whole app

C<Selkie::App>'s resize callbacks accumulate and there is no way to
remove one, so a tab that registered its own would leak a closure —
holding a destroyed widget tree — on every visit. The shell therefore
owns the single callback and fans it out: the hint footer refits, and
the accounts tab is told the new width so it can decide whether the
register's running-balance column still fits.

=head2 ACCESSORS

=item C<app>, C<db>, C<workspace>, C<config>, C<theme>, C<store> —
      the injected collaborators.
=item C<icons> — the active C<App::Moneymoor::Icons> tier, resolved
      lazily from C<config.icons> and refreshed by C<apply-theme-live>.
=item C<root>, C<top-bar>, C<tabs>, C<content-host>, C<hint-footer> —
      the shell's own widgets.
=item C<view> — the cached C<BudgetView>. A type object until the
      first recompute lands.
=item C<payee($id)> / C<category($id)> / C<group($id)> /
      C<account($id)> — id → model, from the caches C<set-view>
      rebuilds. A type object for an unknown id.
=item C<viewed-period> — C<app/period>, or the period containing today
      if the store has not been seeded yet.
=item C<current-tab>, C<tab-label($name)>, C<tab-names>.
=item C<pane-contexts> — the current tab's C<< widget => hint context >>
      pairs, which is how the footer resolves focus to a context.
=item C<initial-focus-widget> — the current tab's primary focus target.
=item C<focus-content()> — put focus there. Called after every content
      rebuild; C<UI> calls it once more after C<switch-screen>.
=item C<budget-tab> / C<accounts-tab> / C<reports-tab> — the tab
      controller while its tab is mounted; a type object otherwise.
=item C<pane-border($title, $sizing)> / C<mount-pane($parent, $border,
      $pane, $context)> — the pane-mounting API the tab builders work
      through.
=item C<rebuild-content()> — re-mount the current tab's panes (a live
      theme swap; the inspector toggle).

=head1 SEE ALSO

=item L<App::Moneymoor::StoreHandlers> — the state shape and the one
      mutation effect.
=item L<App::Moneymoor::Screen::Main::Subscriptions> — banner, footer
      and per-tab store wiring.
=item L<App::Moneymoor::Screen::Main::Keybinds> — the global binds.
=item L<App::Moneymoor::Screen::Main::Modals> — settings, diagnostics
      and the budget-period picker.

=end pod

use Selkie::Trace;

unit class App::Moneymoor::Screen::Main;

use Selkie::App;
use Selkie::Store;
use Selkie::Widget;
use Selkie::Layout::VBox;
use Selkie::Widget::Border;
use Selkie::Widget::RichText;
use Selkie::Widget::TabBar;
use Selkie::BorderStyle;
use Selkie::Sizing;

use App::Moneymoor::Config;
use App::Moneymoor::DB;
use App::Moneymoor::Theme;
use App::Moneymoor::Themes;
use App::Moneymoor::Service::Budget;
use App::Moneymoor::Service::Icons;
use App::Moneymoor::Service::Workspace;
use App::Moneymoor::StoreHandlers;
use App::Moneymoor::View::HintBar;
use App::Moneymoor::Widget::BannerBar;
use App::Moneymoor::Screen::Accounts;
use App::Moneymoor::Screen::Budget;
use App::Moneymoor::Screen::Reports;
use App::Moneymoor::Screen::Main::Keybinds;
use App::Moneymoor::Screen::Main::Modals;
use App::Moneymoor::Screen::Main::Subscriptions;

has Selkie::App $.app is required;
has App::Moneymoor::DB $.db is required;
has App::Moneymoor::Service::Workspace $.workspace is required;
has App::Moneymoor::Config $.config;
has App::Moneymoor::Theme $.theme is required;

# Glyph tier for every row this screen paints. Resolved from
# `config.icons` the same way `$!theme` is resolved from `config.theme`
# (UI.rakumod does the theme lookup because Login needs it before Main
# exists; nothing needs icons that early, so the lookup lives here).
# Lazily built so a Main constructed without a Config still gets the
# default tier instead of a null accessor.
has App::Moneymoor::Icons $!icons;

has Selkie::Layout::VBox $.root;
has App::Moneymoor::Widget::BannerBar $!top-bar;
has Selkie::Widget::TabBar $!tabs;
has Selkie::Layout::VBox $!content-host;
has Selkie::Widget::RichText $!hint-footer;

has App::Moneymoor::StoreHandlers $!handlers;

# --- The cache (see the Pod) ---------------------------------------------
has $!view;
has %!payees-by-id;
has %!categories-by-id;
has %!groups-by-id;
has %!accounts-by-id;

# --- Content-host state --------------------------------------------------
# Which tab's panes are mounted. A type object until the first build,
# which is what lets `apply-theme-live` force a rebuild by clearing it.
has Str $!tab-mode;
# The current tab's `widget => hint context` map, in the order the
# panes were built. Rebuilt with the panes, because the widgets it
# names are destroyed with them.
has @!pane-contexts;
# Where focus should land when this tab is mounted.
has $!content-focus;
# Whether the content host has ever held a tab's panes. The difference
# between the first mount and every one after it is who owns focus:
# the first happens inside `build`, before the screen has been added to
# the app, and `switch-screen` restores its own remembered focus
# afterwards — so `UI` places the initial focus and the shell only
# takes over from the second mount onward. See `!focus-content`.
has Bool $!content-mounted = False;
# The budget tab's controller, while that tab is the one mounted — the
# object the budget keybinds, subscriptions and modals talk to. A type
# object on the other two tabs, because the widgets it owns do not
# exist then.
has App::Moneymoor::Screen::Budget $!budget-tab;
# The same, for the accounts tab: the sidebar's ListView and the
# register's Table live on it, and the modals reach both through here.
has App::Moneymoor::Screen::Accounts $!accounts-tab;
# And for the reports tab, whose chart has to be told when the pane's
# height changes how many bars fit in it.
has App::Moneymoor::Screen::Reports $!reports-tab;

# --- Hint footer ---------------------------------------------------------
# Which hint set the footer is showing — a HintBar context key, never a
# rendered string or a Style: the focus subscription that decides it
# runs inside the store, whose change digest keys objects by identity,
# and a selector handing back freshly-built Styles would read as
# "changed" every tick and re-push the footer every frame.
has Str $!hint-context = 'generic';
# What the currently-painted spans were built from. Repaints are
# skipped when neither has moved: the focus subscription fires on every
# app-wide focus change, and rebuilding an identical span list would
# mark the footer dirty for nothing.
has Str $!hint-context-painted;
has Int $!hint-width-painted = -1;

# Columns the hint footer is fitted to before the screen has been laid
# out (a widget with no plane reports zero). The real width lands from
# the App.on-resize callback and from the focus subscription long
# before the user can read the bar; this only decides what the very
# first (invisible) build paints.
my constant HINT-FALLBACK-COLS = 80;

#| The tab strip, in display order. The C<name> is the store value and
#| the slice key everywhere downstream; the C<label> is what the strip
#| and the banner show. Only C<budget> carries a badge — the overspent
#| count — because it is the only tab with a number that means
#| "something needs your attention" rather than "here is how much data
#| there is".
my constant TABS =
    { name => 'budget',   label => 'Budget',   badged => True  },
    { name => 'accounts', label => 'Accounts', badged => False },
    { name => 'reports',  label => 'Reports',  badged => False },
;

method store() { $!app.store }

#| Look the icon tier up from config, falling back to the default tier
#| when there is no Config (unit contexts) or the key is unset.
#| C<App::Moneymoor::Service::Icons::icons> already maps an unknown
#| tier name onto unicode, so a hand-edited config can't break
#| rendering.
method !load-icons(--> App::Moneymoor::Icons) {
    icons($!config.defined ?? ($!config.icons // 'unicode') !! 'unicode');
}

method build(--> Selkie::Layout::VBox) {
    $!root = Selkie::Layout::VBox.new(sizing => Sizing.flex);

    $!top-bar = App::Moneymoor::Widget::BannerBar.new(
        palette => $!theme,
        text    => ' App::Moneymoor',
        sizing  => Sizing.fixed(1),
    );
    $!root.add($!top-bar);

    $!tabs = Selkie::Widget::TabBar.new(
        sizing          => Sizing.fixed(1),
        active-style    => TabPill,
        focus-indicator => FocusColor,
    );
    $!tabs.add-tab(name => $_<name>, label => $_<label>) for TABS;
    $!root.add($!tabs);

    # Stable wrapper — the ONLY thing between the tabs and the hint bar,
    # so a tab swap doesn't reshuffle the root's children list.
    $!content-host = Selkie::Layout::VBox.new(sizing => Sizing.flex);
    $!root.add($!content-host);

    # Content swaps with focus — see Subscriptions::install-footer. The
    # initial paint is the generic context at the fallback width; the
    # focus subscription flips both as soon as focus lands.
    $!hint-footer = Selkie::Widget::RichText.new(sizing => Sizing.fixed(1));
    $!root.add($!hint-footer);
    self!repaint-hints;
    self!register-resize;

    # Handlers + shell-level subscriptions + global keybinds wire once;
    # per-tab subscriptions and keybinds are (re-)registered inside
    # !refresh-content-layout on every tab change.
    self!register-handlers;
    App::Moneymoor::Screen::Main::Subscriptions::install-banner(self);
    App::Moneymoor::Screen::Main::Subscriptions::install-footer(self);
    self!wire-tabs;
    App::Moneymoor::Screen::Main::Keybinds::install-global(self);
    install-banner-clock($!app, $!top-bar) if $!app.defined && $!top-bar.defined;
    self!wire-tab-mode-watcher;

    # Initial layout. Deliberately before app/init: the tab
    # subscriptions installed by refresh-content-layout have to exist
    # before the first digest lands, or the first recompute paints
    # nothing and the panes stay blank until the user touches
    # something.
    self!refresh-content-layout('budget');

    my $bootstrap-span = Selkie::Trace.enabled
        ?? Selkie::Trace.start('boot.store-bootstrap', cat => 'boot') !! Nil;
    self.store.dispatch('app/init',
        theme => ($!config.defined ?? $!config.theme !! 'gruvbox'),
        icons => ($!config.defined ?? $!config.icons !! 'unicode'),
    );
    self.store.tick;
    $bootstrap-span.finish with $bootstrap-span;

    $!root;
}

# --- The cache -----------------------------------------------------------

#|( The C<on-view> sink C<StoreHandlers> calls on every recompute:
    replace the cached view and rebuild the four id → model hashes the
    row builders join against.

    Rebuilding all four on every recompute (rather than invalidating
    selectively) is deliberate. A budget is a few hundred rows at the
    outside, four C<SELECT>s cost less than a frame, and the
    alternative — per-entity invalidation — is a second consistency
    problem living next to the one the digest already solves. )
method set-view($view --> Nil) {
    $!view = $view;

    %!payees-by-id     = $!workspace.payees.find-all.map({ .id => $_ }).Hash;
    %!categories-by-id = $!workspace.categories.find-all(:include-hidden)
                            .map({ .id => $_ }).Hash;
    %!groups-by-id     = $!workspace.categories.find-groups(:include-hidden)
                            .map({ .id => $_ }).Hash;
    %!accounts-by-id   = $!workspace.accounts.find-all(:include-closed)
                            .map({ .id => $_ }).Hash;
    Nil
}

method view() { $!view }

method payee(Int $id)    { $id.defined ?? %!payees-by-id{$id}     !! Nil }
method category(Int $id) { $id.defined ?? %!categories-by-id{$id} !! Nil }
method group(Int $id)    { $id.defined ?? %!groups-by-id{$id}     !! Nil }
method account(Int $id)  { $id.defined ?? %!accounts-by-id{$id}   !! Nil }

method payees(--> List)     { %!payees-by-id.values.List     }
method categories(--> List) { %!categories-by-id.values.List }
method groups(--> List)     { %!groups-by-id.values.List     }
method accounts(--> List)   { %!accounts-by-id.values.List   }

#| The budget period the user is looking at. Falls back to the one
#| containing today rather than a type object: every caller would
#| otherwise repeat the same guard, and "no period yet" only happens in
#| the handful of frames between construction and C<app/init>.
method viewed-period(--> Str) {
    (self.store.get-in('app', 'period') // $!workspace.current-period).Str;
}

method current-tab(--> Str) {
    (self.store.get-in('app', 'tab') // 'budget').Str;
}

method tab-names(--> List) { TABS.map(*<name>).List }

method tab-label(Str $name --> Str) {
    (TABS.first({ $_<name> eq ($name // '') }) andthen *<label>) // '';
}

method badged-tab-names(--> List) { TABS.grep(*<badged>).map(*<name>).List }

method icons(--> App::Moneymoor::Icons) { $!icons //= self!load-icons }

method top-bar()      { $!top-bar      }
method tabs()         { $!tabs         }
method content-host() { $!content-host }
method hint-footer()  { $!hint-footer  }
method handlers()     { $!handlers     }
method pane-contexts(--> List) { @!pane-contexts.List }
method initial-focus-widget() { $!content-focus }

#| The budget tab's controller while that tab is mounted, and a type
#| object otherwise. The budget keybinds, subscriptions and modals all
#| reach the table through this rather than through captured
#| references, because the widgets are rebuilt on every tab change.
method budget-tab(--> App::Moneymoor::Screen::Budget) { $!budget-tab }

#| The accounts tab's controller while that tab is mounted, and a type
#| object otherwise — the same contract C<budget-tab> has, and what
#| every accounts dialog in C<Screen::Main::Modals> resolves through.
method accounts-tab(--> App::Moneymoor::Screen::Accounts) { $!accounts-tab }

#| And the reports tab's, which the resize fan-out and the per-tab
#| subscription and keybind seams resolve through.
method reports-tab(--> App::Moneymoor::Screen::Reports) { $!reports-tab }

# --- Store ----------------------------------------------------------------

method !register-handlers() {
    my $self-ref = self;
    my $app = $!app;
    $!handlers = App::Moneymoor::StoreHandlers.new(
        workspace => $!workspace,
        toast     => -> Str $msg { $app.toast($msg) if $app.defined },
        on-view   => -> $view { $self-ref.set-view($view) },
    );
    $!handlers.register(self.store);
}

method !wire-tabs() {
    my $store = self.store;
    my $tabs  = $!tabs;

    $!tabs.on-tab-selected.tap: -> Str $name {
        $store.dispatch('app/tab-selected', :$name);
    };

    # Sync the strip when a keybind (not a click) changed the tab. The
    # silent setter is what stops the sync from re-emitting
    # on-tab-selected and dispatching the event a second time.
    $store.subscribe-with-callback(
        'tab-sync',
        -> $s { ($s.get-in('app', 'tab') // 'budget').Str },
        -> Str $name { $tabs.set-active-name-silent($name) },
        $tabs,
    );

    # The budget tab's badge: how many envelopes are overspent in the
    # viewed period. Positive counts only — "Budget 0" is the one number
    # nobody needs, and a badge that never disappears trains the eye to
    # stop reading badges.
    $store.subscribe-with-callback(
        'tab-badges',
        -> $s { ($s.get-in('budget', 'overspent-count') // 0).Int },
        -> Int $n { $tabs.set-badge('budget', $n > 0 ?? $n !! Nil) },
        $tabs,
    );
}

method !wire-tab-mode-watcher() {
    my $self-ref = self;
    self.store.subscribe-with-callback(
        'tab-mode',
        -> $s { ($s.get-in('app', 'tab') // 'budget').Str },
        -> Str $tab { $self-ref!refresh-content-layout($tab) },
        $!content-host,
    );
}

# --- Content host ---------------------------------------------------------

#|( Re-mount the content area for C<$tab>. Widgets inside
    C<$!content-host> are destroyed — and their subscriptions cleaned
    up with them by C<Container>'s unsubscribe walk — then the new
    tab's panes are built, handed the store, and its subscriptions and
    keybinds re-installed against the fresh widgets.

    No-op when the tab hasn't actually changed, which is what lets the
    store subscription call it unconditionally.

    Re-focusing at the end is not optional, and it belongs here rather
    than at the call sites: the panes that had focus have just been
    destroyed, Selkie has no reason to move focus on its own, and an
    app whose focus is on a destroyed widget takes keystrokes nowhere
    and shows the generic hints. Both entry points — a tab switch and
    C<rebuild-content> — get it for the same reason. )
method !refresh-content-layout(Str $tab) {
    my Str $want = $tab // 'budget';
    $want = 'budget' unless $want eq any(self.tab-names);
    return if $!tab-mode.defined && $!tab-mode eq $want;
    # Read before the mount below flips it: whether this is a *re*-mount
    # is what decides whether the shell places focus itself.
    my Bool $relayout = $!content-mounted;
    $!tab-mode = $want;

    $!content-host.clear;
    @!pane-contexts = ();
    $!content-focus = Nil;
    $!budget-tab    = App::Moneymoor::Screen::Budget;
    $!accounts-tab  = App::Moneymoor::Screen::Accounts;
    $!reports-tab   = App::Moneymoor::Screen::Reports;

    given $want {
        when 'accounts' { self!build-accounts-pane }
        when 'reports'  { self!build-reports-pane  }
        default         { self!build-budget-pane   }
    }

    App::Moneymoor::Screen::Main::Subscriptions::install-content(self);
    App::Moneymoor::Screen::Main::Keybinds::install-content(self);

    $!content-mounted = True;
    self.focus-content if $relayout;

    # The departing tab's panes are gone, so the footer's cached
    # context can be describing a widget that no longer exists. Ask the
    # footer to re-resolve against whatever has focus now. Cheap when
    # the focus move above already did it through the store.
    App::Moneymoor::Screen::Main::Subscriptions::refresh-footer(self);
}

#|( Put focus on the tab's primary pane — the first one C<mount-pane>
    saw, which every tab builder mounts first for exactly this reason.

    Called by C<!refresh-content-layout> after a re-mount, so a tab
    switch, a live theme swap and the inspector toggle all land focus
    the same way. Focusing goes through the app rather than
    C<Widget.set-focused> so the C<ui/focus> dispatch happens too: that
    write is what the hint footer's subscription resolves the key
    context from.

    A no-op with no app (the headless unit contexts) or before any pane
    has been mounted, and public so the entry point — and a test that
    cannot construct a C<Selkie::App> — can drive the same decision. )
method focus-content(--> Nil) {
    $!app.focus($!content-focus)
        if $!app.defined && $!content-focus.defined;
    Nil
}

#|( Force a rebuild of the content area for the tab that is already
    mounted. Clearing C<$!tab-mode> is what makes
    C<!refresh-content-layout> stop treating the call as a no-op.

    Two callers, and they want it for the same reason: a live palette
    swap needs every subscription closure re-registered against the new
    colours, and the budget tab's inspector toggle needs the pane tree
    itself rebuilt (a zero-width child of an C<HBox> is not a hidden
    child, it is a child that paints outside its parent).

    Re-focusing afterwards is not optional — the old panes have been
    destroyed and whatever had focus went with them — but it is not
    done here: C<!refresh-content-layout> owns it, so the ordinary tab
    switch (which does not come through this method) gets it too. )
method rebuild-content(--> Nil) {
    my Str $tab = self.current-tab;
    $!tab-mode = Str;
    self!refresh-content-layout($tab);
    Nil
}

#|( Pane chrome shared by every tab: rounded frame, one cell of
    padding, title left-aligned (a pane label reads as a tab stop, not
    a dialog heading — only the single-dialog screens centre theirs).

    Public because the per-tab builders live in their own modules
    (C<Screen::Budget> and, from phase 3, its siblings) and every pane
    in the app is supposed to look the same. )
method pane-border(Str:D $title, Sizing $sizing --> Selkie::Widget::Border) {
    Selkie::Widget::Border.new(
        :$sizing,
        :$title,
        border-style => BorderRounded,
        padding      => 1,
    );
}

#|( Mount one pane: frame it, register its hint context, remember it as
    a focus target if it is the first, and push the store down.

    That last step is not optional plumbing. C<Split.set-first> /
    C<set-second> and a fixed-width C<HBox.add> do B<not> cascade
    C<set-store> to their children, so a pane mounted through either
    would silently never see a subscription. Doing it here, for every
    pane, means no call site has to remember which layout it used.

    Public for the same reason C<pane-border> is: this is the API a
    tab builder in its own module works through, and the hint-context
    registration has to happen for every focusable pane in the app. )
method mount-pane($parent, Selkie::Widget::Border $border,
                  $pane, Str:D $context --> Nil) {
    $border.set-content($pane);
    $parent.add($border);
    $border.set-store(self.store);
    @!pane-contexts.push($pane => $context);
    $!content-focus //= $pane;
    Nil
}

#| The budget tab owns enough state — a table whose cursor has to
#| survive a rebuild, a rail, a header pill and four subscriptions — to
#| be a class rather than a method. The shell's part is to hand it the
#| content host and keep the reference the keybinds resolve through.
method !build-budget-pane() {
    $!budget-tab = App::Moneymoor::Screen::Budget.new(main => self);
    $!budget-tab.build($!content-host);
}

#| Accounts is the one tab with two focus targets, and so the one that
#| proves the footer really resolves context per pane rather than per
#| tab: the sidebar answers to the C<sidebar> hints and the register to
#| C<register>.
method !build-accounts-pane() {
    $!accounts-tab = App::Moneymoor::Screen::Accounts.new(main => self);
    $!accounts-tab.build($!content-host);
}

#| Reports is the one tab with a pane that is not focusable furniture
#| and one that is: the cash-flow strip is a caption, the chart is the
#| thing the user drives, and only the chart is mounted through
#| C<mount-pane>.
method !build-reports-pane() {
    $!reports-tab = App::Moneymoor::Screen::Reports.new(main => self);
    $!reports-tab.build($!content-host);
}

# --- Hint footer ----------------------------------------------------------

#| Switch the footer to a different C<App::Moneymoor::View::HintBar>
#| context. Public because the focus subscription in
#| C<Screen::Main::Subscriptions> is what decides which one applies; it
#| hands over a context key and this owns the rendering.
method set-hint-context(Str:D $context) {
    $!hint-context = $context;
    self!repaint-hints;
}

method hint-context(--> Str) { $!hint-context }

#|( Rebuild the footer's spans for the current context at the footer's
    current width. Cheap to call spuriously — a repaint that would
    produce the same spans is skipped, which is what lets the focus
    subscription (fired by every focus change anywhere in the app) call
    it unconditionally.

    C<:force> is for the one case the cache can't see: a live palette
    swap, where the context and width are unchanged but every span's
    colour moved. )
method !repaint-hints(Bool :$force = False) {
    return without $!hint-footer;
    my Int $cols = self!hint-cols;
    return if !$force
           && $!hint-context-painted.defined
           && $!hint-context-painted eq $!hint-context
           && $!hint-width-painted == $cols;
    $!hint-context-painted = $!hint-context;
    $!hint-width-painted   = $cols;
    $!hint-footer.set-content(hint-spans(
        $!hint-context, $cols, theme => $!theme, icons => self.icons,
    ));
}

#| Columns the hint spans have to fit into: the footer's own allocation
#| once the screen has been laid out, and the fallback before that (a
#| widget without a plane reports zero, and fitting to zero would paint
#| nothing at all).
method !hint-cols(--> Int) {
    my Int $cols = ($!hint-footer.defined ?? $!hint-footer.cols !! 0).Int;
    $cols > 0 ?? $cols !! HINT-FALLBACK-COLS;
}

#|( The app's one resize callback, fanned out to everything that has to
    re-measure.

    One rather than one per consumer because C<Selkie::App> keeps
    resize callbacks in a list it never removes from: a per-tab
    registration would leak a closure — holding a widget tree that has
    since been destroyed — on every tab switch.

    =item The hint bar drops whole groups to fit, so a wider terminal
       has to get its groups back and a narrower one has to shed them.
    =item The register's running-balance column only exists above a
       width threshold, and crossing it rebuilds the column set.
    =item The reports chart draws one bar per row and cannot scroll,
       so a taller pane shows categories a shorter one had to cut.

    Selkie fires resize callbacks after the tree has been re-laid-out
    and the post-resize frame is on screen, so every widget's C<cols>
    is already the new one by the time this runs. )
method !register-resize() {
    return without $!app;
    my $self-ref = self;
    $!app.on-resize: -> UInt $rows, UInt $cols {
        $self-ref!repaint-hints;
        # The banner's content is width-derived — visible-text truncates to
        # the column budget — so a resize changes what it should show even
        # though nothing about its state changed. Selkie's own post-resize
        # cascade already marks the tree dirty, but these callbacks fire
        # after that frame has been composited, so this is the repaint that
        # survives a banner which skipped the cascade's render (see
        # BannerBar.render's zero-dimension path).
        my $bar = $self-ref.top-bar;
        $bar.mark-dirty with $bar;
        my $accounts = $self-ref.accounts-tab;
        $accounts.handle-resize($cols.Int) if $accounts.defined;
        my $reports = $self-ref.reports-tab;
        $reports.handle-resize($rows.Int, $cols.Int) if $reports.defined;
    };
}

# --- Live theme swap ------------------------------------------------------

#|( Reload the active theme from config and apply it end-to-end without
    an app restart. Called from the Settings modal's close handler when
    the outcome is C<saved>.

    Five steps, and each one exists because Selkie's own cascade cannot
    reach the thing it fixes:

    =item 1. Re-resolve C<$!theme> by name — several places in this
       class hold it, and every subscription closure captured it.
    =item 2. C<$!app.set-theme> — cascades through every registered
       screen's widget tree and repaints the plane bases.
    =item 3. Re-derive what the shell baked in at build time. The
       banner resolved its gradient stops itself; the footer's colours
       live in its spans. Neither is a C<Selkie::Style> the cascade can
       see.
    =item 4. Re-read the glyph tier — Settings writes both keys and
       closes through this one path.
    =item 5. C<rebuild-content> — re-registers every per-tab
       subscription closure against the new palette, and puts focus
       back on the pane that just got destroyed and rebuilt. )
method apply-theme-live() {
    return without $!config;
    my $new = App::Moneymoor::Themes::load($!config.theme);
    $!theme = $new;
    $!app.set-theme($new.to-selkie) if $!app.defined;
    $!icons = self!load-icons;

    $!top-bar.set-theme-colours($!theme) if $!top-bar.defined;
    self!repaint-hints(:force);

    self.rebuild-content;

    $!root.mark-screen-dirty if $!root.defined;
    self.store.tick;
}

# --- Modals ---------------------------------------------------------------

#|( Standard modal-lifecycle wrapper. Closes the modal before the
    caller's body fires (so dispatch / toast happen against a clean
    screen), and binds Esc to a plain close-modal. Caller supplies the
    widget's submit-supply directly — C<&body> receives whatever the
    supply emits.

    For modals where Esc should do something more than close, pass
    C<:&on-cancel>.

    Read-only dialogs (diagnostics) go through here too, with a supply
    that never emits: the point of routing every modal through one
    wrapper is that the Esc contract and the close ordering are written
    once. )
method with-modal(
    Supply:D $submit-supply,
    $modal,
    $focus-target,
    :&body!,
    :&on-cancel,
) {
    my $app = $!app;
    $submit-supply.tap: -> $emitted {
        $app.close-modal;
        body($emitted);
    };
    $modal.on-key: 'esc', -> $ {
        with &on-cancel { on-cancel() } else { $app.close-modal }
    };
    $app.show-modal($modal);
    $app.focus($focus-target);
}

method open-settings() {
    App::Moneymoor::Screen::Main::Modals::open-settings(self);
}

method open-diagnostics() {
    App::Moneymoor::Screen::Main::Modals::open-diagnostics(self);
}

#|( The budget-period picker. C<:first-run> is the entry point C<UI>
    uses once, immediately after a budget is created, and it changes
    two things: Esc reads as "keep the calendar month" rather than as a
    cancel, and the answer is applied to an empty budget rather than
    run through the re-bucket confirm.

    A delegate for the same reason C<open-settings> is one: the call
    sites — a keybind, and the entry point's hand-off — should not have
    to know which module a dialog's body lives in. )
method open-period-picker(Bool :$first-run = False) {
    App::Moneymoor::Screen::Main::Modals::open-period-picker(
        self, :$first-run);
}
