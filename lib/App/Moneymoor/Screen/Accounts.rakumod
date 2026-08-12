=begin pod

=head1 NAME

App::Moneymoor::Screen::Accounts - the accounts tab: the sidebar of
ledgers and the register of the one that is selected.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Screen::Accounts;

# Built by Screen::Main's content-host seam, never directly:
my $tab = App::Moneymoor::Screen::Accounts.new(main => $main);
$tab.build($content-host);       # mounts the sidebar and the register
$tab.install-subscriptions;      # store → sidebar / register / titles
$tab.install-keybinds;           # n e d c t on the register, n e c on the list

# What the modals in Screen::Main::Modals read back:
$tab.selected-transaction;       # the Model::Transaction under the cursor
$tab.selected-account-id;        # the sidebar's account, 0 = All Accounts
$tab.sidebar-row;                # the sidebar row hash under the cursor

=end code

=head1 DESCRIPTION

    HBox (the content host's child)
     ├ Border(fixed 26, 'Accounts', bottom 'net £12,400.00') → ListView
     └ Border(flex, 'Current · cleared £900 · working £850') → Table

The two panes are one screen with one selection between them: the
sidebar decides which ledger the register shows, and it does it through
the store (C<accounts/selected-account-id>) rather than by calling the
register directly, so a selection made with the arrow keys and one
restored after a rebuild travel the same path.

Everything painted here comes out of C<View::RegisterRow>; this file is
the wiring.

=head2 The sidebar's captions are not selections

C<BUDGET> and C<TRACKING> are rows in the same C<ListView> as the
accounts — the widget has no notion of a section — and the cursor can
land on one. §4.4 says a caption re-selects the previous account; this
does slightly better and steps B<in the direction of travel>, because
bouncing straight back would make a caption a wall the user could never
arrow past.

The C<CLOSED (n)> fold and C<All Accounts> B<are> selectable: one is a
toggle, the other is a real (if synthetic) ledger.

=head2 The cursor is restored by id, twice

Neither list has stable indices. The sidebar's rows move when an
account is created, closed or reordered; the register's move when a
transaction changes date. So the sidebar's cursor is restored by
account id and the register's by transaction id after every rebuild —
and because C<ListView.set-items> and C<Table.set-rows> both fire
C<on-select>, both restores happen behind a suppression flag with one
deliberate announcement at the end. Without it a rebuild would announce
whatever row happened to be under the old index, the register would
repaint for an account the user never chose, and — the rebuild being
triggered by a selection-keyed subscription — it would do it again
every tick.

=head2 Three change tokens, and why this tab uses the blunt one

The budget grid watches C<budget/digest> and C<budget/catalogue>.
Neither can see a payee's name, a memo or a cleared state, so a memo
edit or a C<c> keypress would leave both byte-identical and repaint
nothing. The register and the sidebar key on C<ws/rev> instead — the
counter every recompute bumps — which says "something was written"
without saying what. That is the right resolution for a pane that
rebuilds its rows wholesale anyway.

=head2 Reconcile mode lives in the frame

§4.5's mode changes three things and none of them is a row.
C<accounts/reconcile> holds the account and the statement balance;
while it names the ledger on screen the frame's title becomes
C<'Reconciling · cleared £A · statement £S · diff £D'>, the frame
itself takes the diff's colour (red until it is zero, green when it
lands — a C<Border> title has no style of its own, so the whole frame
is the signal), and the hint footer switches to the C<reconcile>
context.

The two keys the mode takes over are taken over in the two different
ways the widget allows:

=item B<Enter> is not bound. C<Table> checks its keybinds before its
      own navigation, so an C<enter> bind would take the key away from
      the widget permanently — including in the frames before the mode
      exists. The mode test lives inside the C<on-activate> tap
      instead, which is where Enter already arrives.
=item B<Esc> is bound, and is a no-op outside the mode. A keybind
      consumes the key outright, which is the point: Esc must not fall
      through while a reconciliation is running. It cannot get in a
      modal's way, because an open modal holds focus and the register
      never sees the key.

Switching ledger or tab ends the mode — the store handlers do it, so
there is one rule and not one per entry point — and the cleared marks
made in it stay. They are facts about transactions; only the mode is
cancelled.

=head2 The balance column comes and goes

The running-balance column only exists in the single-account view, and
only when the terminal is at least C<BALANCE-MIN-COLS> wide. Crossing
that threshold rebuilds the C<Table>'s columns — C<Table> has no
per-column visibility, so the column set is the only lever.

The width is read at every repaint rather than cached at build time:
the tab is built while the terminal size is already known, but a
terminal that is resized while another tab is mounted would otherwise
build the wrong columns. C<Screen::Main> owns the one C<App.on-resize>
callback in the app (resize callbacks accumulate with no way to remove
them, so a per-tab registration would leak one on every tab switch) and
calls C<handle-resize> here.

=head1 METHODS

=item C<build($host)> — construct and mount. Registers the sidebar
      under the C<sidebar> hint context and the register under
      C<register>; the sidebar is the tab's initial focus, and Enter
      on it moves focus to the register.
=item C<install-subscriptions()> / C<install-keybinds()> — the two
      seams C<Screen::Main::Subscriptions::install-content> and
      C<Screen::Main::Keybinds::install-content> call.
=item C<refresh-sidebar()> / C<refresh-register()> — the subscription
      callbacks, public because a modal that has just mutated
      something can ask for a repaint.
=item C<handle-resize(Int $cols)> — the balance-column threshold.
=item C<table>, C<sidebar>, C<sidebar-row>, C<selected-account-id>,
      C<selected-transaction>, C<selected-transaction-id>.
=item C<reconcile-state> / C<reconciling> — §4.5's mode, for the
      ledger currently on screen.

=head1 SEE ALSO

=item L<App::Moneymoor::View::RegisterRow> — the rows, the columns, §2.
=item L<App::Moneymoor::Screen::Main::Modals> — what the keys open.
=item L<App::Moneymoor::StoreHandlers> — C<accounts/select-account>,
      C<accounts/toggle-closed> and C<ws/rev>.

=end pod

unit class App::Moneymoor::Screen::Accounts;

use Selkie::BorderStyle;
use Selkie::Layout::HBox;
use Selkie::Sizing;
use Selkie::Style;
use Selkie::Widget::Border;
use Selkie::Widget::ListView;
use Selkie::Widget::Table;

use App::Moneymoor::Model::Transaction;
use App::Moneymoor::StoreHandlers;
use App::Moneymoor::Util::Money;
use App::Moneymoor::View::EmptyState;
use App::Moneymoor::View::RegisterRow;
use App::Moneymoor::Screen::Main::Modals;

#| The C<Screen::Main> that owns the caches, the store and the palette.
#| Untyped so this class does not have to C<use> the screen that
#| C<use>s it.
has $.main is required;

has Selkie::Widget::ListView $.sidebar;
has Selkie::Widget::Border $!sidebar-border;
has Selkie::Widget::Table $.table;
has Selkie::Widget::Border $!register-border;

#| The sidebar's rows, parallel to the C<ListView>'s strings. The
#| widget only knows about labels; every decision this class makes
#| about a row (is it a caption, which account is it) reads from here.
has @!sidebar-rows;

#| The last row the cursor legitimately landed on, which is where a
#| caption bounces back to when the user arrives from below.
has Int $!last-landed = 0;

#| True while a rebuild is moving a cursor about, so the C<on-select>
#| taps know the movement is the app's and not the user's.
has Bool $!suppress-select = False;

#| Whether the columns currently installed include the running
#| balance, and whether they were built for the All-Accounts view.
#| Compared on every repaint to decide whether the column set has to
#| be rebuilt at all.
has Bool $!columns-have-balance = False;
has Bool $!columns-are-all = False;
has Bool $!columns-built = False;

#|( The style the register's frame is currently overridden with, or a
    type object when it is wearing the ordinary pane chrome.

    Kept because C<Selkie::Widget::Border> takes an override and never
    hands it back, and "is the frame red or green right now" is the
    whole visible signal of §4.5 — a mode whose only feedback could not
    be asserted would be a mode nobody could keep working. )
has Selkie::Style $.frame-style;

#| Terminal width as last reported. Seeded from the screen root, which
#| has its real allocation by the time this tab is built (the app is
#| laid out before the first tab switch), and updated by
#| C<handle-resize>.
has Int $!term-cols = 0;

method build($host --> Nil) {
    my $main  = $!main;
    my $store = $main.store;

    my $row = Selkie::Layout::HBox.new(sizing => Sizing.flex);
    $host.add($row);

    $!sidebar = Selkie::Widget::ListView.new(sizing => Sizing.flex);
    $!sidebar-border = $main.pane-border('Accounts',
                                         Sizing.fixed(SIDEBAR-COLS));
    $!sidebar-border.set-bottom-title-align(TitleRight);
    # mount-pane frames it, registers the hint context, makes the first
    # pane the tab's focus target and pushes the store down — a
    # fixed-width HBox child does not get set-store cascaded to it.
    $main.mount-pane($row, $!sidebar-border, $!sidebar, 'sidebar');

    $!table = Selkie::Widget::Table.new(
        sizing => Sizing.flex, show-scrollbar => True,
    );
    $!register-border = $main.pane-border('Register', Sizing.flex);
    $main.mount-pane($row, $!register-border, $!table, 'register');

    $!term-cols = self!root-cols;
    self!install-columns;
    $!table.set-row-style(-> %r {
        register-style((%r<severity> // 'normal').Str, theme => $main.theme)
    });

    self!wire-sidebar;
    self!wire-table;
    Nil
}

# --- Wiring ---------------------------------------------------------

method !wire-sidebar(--> Nil) {
    my $store = $!main.store;

    # ListView emits the selected *string*; the index is what maps back
    # to the row model, and `cursor` is where the widget actually is.
    $!sidebar.on-select.tap: -> $ {
        self!announce-sidebar unless $!suppress-select;
    };

    # Enter: fold the closed bucket, or hand focus to the register.
    # Through on-activate rather than an `enter` keybind because
    # ListView checks its keybinds before its own navigation, and
    # stealing Enter here would take it away from the widget for good.
    $!sidebar.on-activate.tap: -> $ {
        my %row = self.sidebar-row;
        if (%row<kind> // '') eq 'closed-toggle' {
            $store.dispatch('accounts/toggle-closed');
        } else {
            my $app = $!main.app;
            $app.focus($!table) if $app.defined && $!table.defined;
        }
    };
    Nil
}

method !wire-table(--> Nil) {
    my $main = $!main;
    my $self-ref = self;

    # Enter on a transaction opens its editor — same reasoning as the
    # sidebar's activate, and the same reasoning as the budget grid's:
    # Table consults its keybinds before its own navigation.
    #
    # Reconcile mode takes Enter over, which is exactly why the mode
    # test lives HERE rather than in a mode-guarded `enter` keybind: a
    # keybind would consume Enter for good, including the frames
    # before the mode exists and after it ends.
    $!table.on-activate.tap: -> UInt $idx {
        if $self-ref.reconciling {
            App::Moneymoor::Screen::Main::Modals::finish-reconcile($main);
        } else {
            my $row = $!table.row-at($idx);
            if $row.defined && ($row<kind> // '') eq 'txn' {
                App::Moneymoor::Screen::Main::Modals::open-transaction-editor(
                    $main, transaction-id => $row<id>.Int);
            }
        }
    };
    Nil
}

#|( Tell the store which ledger the sidebar is on, bouncing off a
    caption first.

    The bounce steps in the direction the cursor was travelling, so a
    caption is something the user passes over rather than a wall. It
    cannot loop: every caption is followed by at least one account (a
    section with no members gets no caption at all), and the search is
    bounded by the row count regardless. )
method !announce-sidebar(--> Nil) {
    return unless @!sidebar-rows.elems;
    my Int $idx = $!sidebar.cursor.Int;
    $idx = @!sidebar-rows.end if $idx > @!sidebar-rows.end;

    if (@!sidebar-rows[$idx]<kind> // '') eq 'header' {
        my Int $step = $idx >= $!last-landed ?? 1 !! -1;
        my Int $want = self!skip-captions($idx, $step);
        # Nothing that way (the caption is the last row, which the row
        # builder never produces, but a defensive reverse costs one
        # line and turns an impossible state into a survivable one).
        $want = self!skip-captions($idx, -$step) if $want < 0;
        if $want >= 0 {
            $!suppress-select = True;
            $!sidebar.select-index($want.UInt);
            $!suppress-select = False;
            $idx = $want;
        }
    }

    $!last-landed = $idx;
    my %row = @!sidebar-rows[$idx] // %();
    my Str $kind = (%row<kind> // '').Str;
    # A caption we could not step off, the empty state, and the closed
    # fold are all rows that exist without naming a ledger.
    return unless $kind eq 'all' | 'account';
    $!main.store.dispatch('accounts/select-account',
                          account-id => (%row<id> // 0).Int);
    Nil
}

#| The first non-caption row from C<$from> walking by C<$step>, or -1.
method !skip-captions(Int $from, Int $step --> Int) {
    my Int $idx = $from + $step;
    while 0 <= $idx <= @!sidebar-rows.end {
        return $idx unless (@!sidebar-rows[$idx]<kind> // '') eq 'header';
        $idx += $step;
    }
    -1;
}

#|( The tab's store wiring. Two channels, both keyed on C<ws/rev>:

    =item the sidebar, which also watches the closed-bucket fold;
    =item the register, which also watches the selected account.

    Every selector returns one flat C<Str> — the store compares
    subscription values by content digest and keys objects by identity,
    so a selector handing back anything richer would read as changed on
    every tick. )
method install-subscriptions(--> Nil) {
    my $self-ref = self;
    my $store    = $!main.store;

    $store.subscribe-with-callback(
        'accounts-sidebar',
        -> $s {
            join("\x[1F]",
                ($s.get-in('ws', 'rev') // 0).Str,
                ($s.get-in('accounts', 'selected-account-id') // 0).Str,
                (($s.get-in('accounts', 'closed-expanded') // False)
                    ?? '1' !! '0'),
            );
        },
        -> Str $ { $self-ref.refresh-sidebar },
        $!sidebar,
    );

    $store.subscribe-with-callback(
        'accounts-register',
        -> $s {
            join("\x[1F]",
                ($s.get-in('ws', 'rev') // 0).Str,
                ($s.get-in('accounts', 'selected-account-id') // 0).Str,
                # Entering and leaving reconcile mode changes the frame,
                # not the rows — but the frame is written by the same
                # repaint, so the mode is part of this channel's key.
                # `reconcile-token` flattens the state's small Hash into
                # a string, because a selector returning the Hash itself
                # would be compared by identity and read as changed on
                # every tick.
                reconcile-token($s.get-in('accounts', 'reconcile')),
            );
        },
        -> Str $ { $self-ref.refresh-register },
        $!table,
    );
    Nil
}

#|( Per-pane keys, §4.4's two tables. Bound on the widget rather than
    app-globally, so a bare C<n> is only "new" while one of these panes
    has focus and remains a letter everywhere else — including in a
    modal's memo field, which is the case that makes a single-character
    global bind unusable in an app with forms. )
method install-keybinds(--> Nil) {
    my $main  = $!main;
    my $store = $main.store;
    my $self-ref = self;

    # --- The register ------------------------------------------------
    $!table.on-key: 'n',
        -> $ {
            App::Moneymoor::Screen::Main::Modals::open-transaction-editor($main);
        },
        :description('New transaction');

    # `e` is not `n` with a row under it: an undefined id would open a
    # blank New-transaction dialog, which is not what pressing Edit on
    # the empty-state row asks for.
    $!table.on-key: 'e',
        -> $ {
            my Int $id = $self-ref.selected-transaction-id;
            if $id.defined {
                App::Moneymoor::Screen::Main::Modals::open-transaction-editor(
                    $main, transaction-id => $id);
            } else {
                my $app = $main.app;
                $app.toast('Select a transaction to edit') if $app.defined;
            }
        },
        :description('Edit this transaction');

    $!table.on-key: 'd',
        -> $ {
            App::Moneymoor::Screen::Main::Modals::delete-transaction($main);
        },
        :description('Delete this transaction');

    $!table.on-key: 'c',
        -> $ { App::Moneymoor::Screen::Main::Modals::cycle-cleared($main) },
        :description('Cycle uncleared / cleared / reconciled');

    $!table.on-key: 't',
        -> $ { App::Moneymoor::Screen::Main::Modals::open-transfer($main) },
        :description('Transfer between accounts');

    $!table.on-key: 'ctrl+r',
        -> $ { App::Moneymoor::Screen::Main::Modals::open-reconcile($main) },
        :description('Reconcile against a statement');

    #|( Esc leaves reconcile mode, keeping every cleared mark made in
    #   it — the marks are facts about transactions, and only the mode
    #   is being cancelled.
    #
    #   Bound on the table rather than handled globally because a
    #   keybind consumes the key outright: Selkie's app-level Esc
    #   closes a modal, and a modal has focus of its own when it is
    #   open, so this can never be in its way. Outside the mode it is
    #   deliberately a no-op — there is nothing on the register for Esc
    #   to mean. )
    $!table.on-key: 'esc',
        -> $ {
            if $self-ref.reconciling {
                $store.dispatch('accounts/reconcile-exit');
                my $app = $main.app;
                $app.toast('Left reconcile — cleared marks kept')
                    if $app.defined;
            }
        },
        :description('Leave reconcile mode');

    # --- The sidebar --------------------------------------------------
    $!sidebar.on-key: 'n',
        -> $ {
            App::Moneymoor::Screen::Main::Modals::open-account-editor($main);
        },
        :description('New account');

    # 0 is All Accounts and the type object is a caption or the empty
    # state; neither is a thing to edit, and passing either through
    # would open the New-account dialog instead.
    $!sidebar.on-key: 'e',
        -> $ {
            my Int $id = $self-ref.selected-account-id;
            if $id.defined && $id > 0 {
                App::Moneymoor::Screen::Main::Modals::open-account-editor(
                    $main, account-id => $id);
            } else {
                my $app = $main.app;
                $app.toast('Select an account to edit') if $app.defined;
            }
        },
        :description('Edit this account');

    $!sidebar.on-key: 'c',
        -> $ {
            App::Moneymoor::Screen::Main::Modals::toggle-account-closed($main);
        },
        :description('Close or reopen this account');
    Nil
}

# --- Repaints -------------------------------------------------------

#| Rebuild the sidebar and put the cursor back on the account it was
#| on. Restored by id, not by index — creating, closing or reordering
#| an account moves every row below it.
method refresh-sidebar(--> Nil) {
    return without $!sidebar;
    my $main  = $!main;
    my $store = $main.store;

    my @accounts = $main.accounts;
    @!sidebar-rows = @accounts.elems
        ?? sidebar-rows(
               accounts    => @accounts,
               view        => $main.view,
               show-closed => ($store.get-in('accounts', 'closed-expanded')
                               // False).Bool,
               icons       => $main.icons,
           ).Array
        # A budget with no accounts at all: the EmptyState copy as
        # unactionable rows, rather than a lone "All Accounts £0.00"
        # over a blank rectangle.
        !! empty-state-for('sidebar', icons => $main.icons).map({
               %( kind => 'empty', id => 0, closed => False,
                  severity => 'normal', label => $_ )
           }).Array;

    my Int $want = ($store.get-in('accounts', 'selected-account-id') // 0).Int;
    $!suppress-select = True;
    $!sidebar.set-items(@!sidebar-rows.map(*<label>).List);
    my $idx = @!sidebar-rows.first(
        { $_<kind> eq 'account' | 'all' && $_<id> == $want }, :k);
    $!sidebar.select-index($idx.UInt) with $idx;
    $!last-landed = ($idx // 0).Int;
    $!suppress-select = False;
    # One deliberate announcement: the selected account may have been
    # deleted, in which case the store still names it and the cursor is
    # somewhere else entirely.
    self!announce-sidebar;

    $!sidebar-border.set-bottom-title(
        'net ' ~ format-pence(net-worth(:@accounts, view => $main.view)))
        if $!sidebar-border.defined;
    Nil
}

#|( Rebuild the register: its columns (if the view or the width moved),
    its rows, its cursor and its frame title.

    Four queries at the outside — the transactions, every split, the
    peer index and nothing else — because the row builder is pure and
    joins against hashes. At this scale that is cheaper than a frame,
    and it is the same trade C<Screen::Main.set-view> makes for the
    lookup caches. )
method refresh-register(--> Nil) {
    return without $!table;
    my $main  = $!main;
    my $store = $main.store;
    my $ws    = $main.workspace;

    my Int $account-id =
        ($store.get-in('accounts', 'selected-account-id') // 0).Int;
    my Bool $all = $account-id == 0;
    my $account = $all ?? Nil !! $main.account($account-id);

    # A selected account that no longer exists (it was just deleted)
    # falls back to All Accounts rather than showing an empty register
    # under a stale title.
    if !$all && !$account.defined {
        $all = True;
        $account-id = 0;
    }

    self!install-columns(all-accounts => $all);

    my @txns = $all ?? $ws.transactions.find-all
                    !! $ws.transactions.find-by-account($account-id);

    my %splits;
    for $ws.transactions.find-all-splits -> $s {
        %splits{ $s.transaction-id }.push($s);
    }

    my @rows = register-rows(
        transactions    => @txns,
        payees          => $main.payees.map({ .id => $_ }).Hash,
        categories      => $main.categories.map({ .id => $_ }).Hash,
        accounts        => $main.accounts.map({ .id => $_ }).Hash,
        splits          => %splits,
        peer-accounts   => self!peer-index(@txns, $all, $ws),
        running-balance => !$all,
        icons           => $main.icons,
    ).Array;

    unless @rows.elems {
        @rows = empty-state-for('register', icons => $main.icons).map({
            %( kind => 'empty', id => 0, transfer => False,
               severity => 'normal', date => '', payee => $_,
               category => '', cleared => '', outflow => '', inflow => '',
               balance => '', account => '' )
        }).Array;
    }

    my $prior = $!table.selected-row;
    my Int $want = ($prior.defined && ($prior<kind> // '') eq 'txn')
        ?? $prior<id>.Int !! Int;

    $!suppress-select = True;
    $!table.set-rows(@rows);
    if $want.defined {
        my $idx = @rows.first(
            { $_<kind> eq 'txn' && $_<id> == $want }, :k);
        $!table.select-index($idx.UInt) with $idx;
    }
    $!suppress-select = False;

    self!repaint-title($all, $account-id, $account);
    Nil
}

#|( The register's frame: its title, and — while reconciling — its
    colour.

    §4.5 asks for the diff red until it is zero and green when it
    lands. A C<Table> row style cannot reach the frame and a C<Border>
    title has no style of its own, so the signal is the whole frame
    through C<set-style-override>: while the mode is on, the register
    is outlined in the diff's colour, and the override is cleared the
    moment it ends. Nothing else in the app overrides a pane's frame,
    so the colour cannot be mistaken for ordinary chrome. )
method !repaint-title(Bool $all, Int $account-id, $account --> Nil) {
    return without $!register-border;
    my $main = $!main;

    if $all {
        $!register-border.set-title('All Accounts');
        self!clear-frame-style;
        return;
    }

    my $balance = $main.view.defined
        ?? $main.view.account-balance($account-id) !! Nil;
    my %mode = self.reconcile-state;

    unless %mode.elems {
        $!register-border.set-title(register-title($account.name, $balance));
        self!clear-frame-style;
        return;
    }

    my Int $statement = (%mode<statement> // 0).Int;
    $!register-border.set-title(
        register-title($account.name, $balance, :$statement));
    $!frame-style = reconcile-style(reconcile-diff($statement, $balance),
                                    theme => $main.theme);
    $!register-border.set-style-override($!frame-style);
    Nil
}

#| Put the frame back on the palette's ordinary pane chrome.
method !clear-frame-style(--> Nil) {
    $!frame-style = Selkie::Style;
    $!register-border.clear-style-override if $!register-border.defined;
    Nil
}

#|( Transaction id → the account it belongs to, for the peer of every
    transfer leg on screen.

    In the All-Accounts view the visible set already contains both
    legs, so the index is free. In a single-account view the peers are
    by definition somewhere else, and the only way to name them is a
    second query — which is skipped entirely when nothing on screen is
    a transfer. )
method !peer-index(@txns, Bool $all, $ws --> Hash) {
    return @txns.map({ .id => .account-id }).Hash if $all;
    return %() unless @txns.first(*.is-transfer).defined;
    $ws.transactions.find-all.map({ .id => .account-id }).Hash;
}

#| Terminal columns, from the screen root — a widget with no plane
#| reports zero, and the fallback keeps the narrow column set rather
#| than guessing at a wide one.
method !root-cols(--> Int) {
    my $root = $!main.root;
    return 0 without $root;
    $root.cols.Int;
}

#|( Install the column set for the current view and width, if it is not
    the one already installed.

    C<Table> has no per-column visibility, so a column that comes and
    goes means rebuilding the whole set — which loses nothing, because
    the rows are re-pushed on the same repaint. )
method !install-columns(Bool :$all-accounts = False --> Nil) {
    my Bool $wide = $!term-cols >= BALANCE-MIN-COLS;
    my Bool $balance = !$all-accounts && $wide;
    return if $!columns-built
           && $!columns-are-all == $all-accounts
           && $!columns-have-balance == $balance;

    $!table.clear-columns;
    for register-columns(:$all-accounts, width => $!term-cols) -> %col {
        $!table.add-column(
            name   => %col<name>,
            label  => %col<label>,
            sizing => (%col<width> == 0
                ?? Sizing.flex !! Sizing.fixed(%col<width>)),
        );
    }
    $!columns-built = True;
    $!columns-are-all = $all-accounts;
    $!columns-have-balance = $balance;
    Nil
}

#|( The terminal changed size. Called by C<Screen::Main>'s single
    C<App.on-resize> callback — resize callbacks accumulate with no way
    to remove them, so the tab must not register its own or a tab
    switch would leak one per visit.

    A repaint only when the threshold was actually crossed: a resize
    that leaves the column set alone changes nothing this tab draws
    that the layout has not already handled. )
method handle-resize(Int $cols --> Nil) {
    my Bool $was = $!term-cols >= BALANCE-MIN-COLS;
    $!term-cols = ($cols // 0).Int;
    return if ($!term-cols >= BALANCE-MIN-COLS) == $was;
    self.refresh-register;
    Nil
}

# --- What the modals ask ---------------------------------------------

#| The sidebar row hash under the cursor, or an empty hash.
method sidebar-row(--> Hash) {
    return %() without $!sidebar;
    my Int $idx = $!sidebar.cursor.Int;
    (@!sidebar-rows[$idx] // %()).Hash;
}

#|( The account the sidebar is on: its id, C<0> for All Accounts, and
    the C<Int> type object on a caption or the empty state.

    Not read from the store: C<c> and C<e> act on the row under the
    cursor, and the store's copy is deliberately never a caption. )
method selected-account-id(--> Int) {
    my %row = self.sidebar-row;
    my Str $kind = (%row<kind> // '').Str;
    return 0   if $kind eq 'all';
    return Int unless $kind eq 'account';
    (%row<id> // 0).Int;
}

#| Which ledger the register is showing — the store's copy, which is
#| never a caption and never undefined. C<0> is All Accounts.
method register-account-id(--> Int) {
    ($!main.store.get-in('accounts', 'selected-account-id') // 0).Int;
}

#|( Reconcile mode's state — C<< { account-id, statement } >> — or an
    empty Hash.

    Empty when the mode is off B<and> when it names a different ledger
    from the one on screen. The store handlers already end the mode on
    an account switch, so the second case is a frame or two at the
    outside; the guard is here because "which account is this diff
    about" is a question the register must never get wrong. )
method reconcile-state(--> Hash) {
    my $mode = $!main.store.get-in('accounts', 'reconcile');
    return %() without $mode;
    my Int $id = ($mode<account-id> // 0).Int;
    return %() unless $id > 0 && $id == self.register-account-id;
    $mode.Hash;
}

#| Whether the register is in reconcile mode for the ledger it is
#| showing. The guard on Esc and on Enter.
method reconciling(--> Bool) { ?self.reconcile-state.elems }

#| The id of the transaction under the register's cursor, or the
#| C<Int> type object on the empty-state row.
method selected-transaction-id(--> Int) {
    return Int without $!table;
    my $row = $!table.selected-row;
    ($row.defined && ($row<kind> // '') eq 'txn') ?? $row<id>.Int !! Int;
}

#| The transaction under the register's cursor, re-read from the
#| gateway so a modal never edits a copy that a repaint has moved on
#| from. A type object when the cursor is not on one.
method selected-transaction(--> App::Moneymoor::Model::Transaction) {
    my Int $id = self.selected-transaction-id;
    return App::Moneymoor::Model::Transaction without $id;
    $!main.workspace.transactions.find-by-id($id);
}
