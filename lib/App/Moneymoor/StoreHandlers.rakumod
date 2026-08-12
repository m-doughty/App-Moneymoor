=begin pod

=head1 NAME

App::Moneymoor::StoreHandlers - the store's state shape, the navigation
events, and the one effect every mutation in the app funnels through.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::StoreHandlers;

my $handlers = App::Moneymoor::StoreHandlers.new(
    workspace => $workspace,
    toast     => -> Str $msg { $app.toast($msg) },
    on-view   => -> $view    { $main.set-view($view) },
);
$handlers.register($store);

$store.dispatch('app/init', theme => 'nord', icons => 'unicode');
$store.tick;

# Every write in the app looks like this — a closure the effect runs.
$store.dispatch('ws/mutate-requested', action => -> {
    $workspace.set-assigned('2026-08-01', $groceries-id, 40000);
});
$store.tick;

=end code

=head1 DESCRIPTION

=head2 The state shape

    app/       tab      'budget' | 'accounts' | 'reports'
               period   'YYYY-MM-DD' — the budget period the user is
                        looking at, named by its start date
               theme    palette name (mirrors Config)
               icons    glyph tier (mirrors Config)

    ws/        rev      monotonic recompute counter — the coarse change
                        token (see below)

    budget/    digest            BudgetView.canonical-digest — THE change token
               catalogue         the envelope catalogue's shape — the OTHER
                                 change token (see below)
               overspent-count   categories with available < 0 in the viewed period
               selected-category-id
               collapsed-groups  { group-id => True }
               show-hidden       Bool
               inspector         Bool

    accounts/  selected-account-id   0 = All Accounts
               closed-expanded       Bool — the sidebar's CLOSED (n) fold
               reconcile             Nil | { account-id, statement }

    reports/   by-group              Bool — b's aggregation toggle

Note what is B<not> here: the C<BudgetView> itself, and the id → model
lookup hashes built from it. Those live on C<App::Moneymoor::Screen::Main>
and reach the store only as C<budget/digest>. The digest is documented
byte-stable and order-independent, which makes it the one thing derived
from the view that is safe to hand a subscription selector — a selector
returning the view object itself would be compared by identity and read
as "changed" on every single tick.

C<on-view> is the seam: the recompute hands the fresh view to whoever
owns the cache, then writes the digest. Subscriptions watch the digest
and pull from the cache in their callbacks.

=head2 The digest is not enough on its own

C<canonical-digest> is a digest of the B<derivation>: periods, balances,
moves, account totals. It contains no category names, no group
memberships and no sort orders, and it omits a category that has no
money and no history entirely. So creating an envelope, renaming one,
moving it to another group or reordering the groups all leave the
digest byte-identical — and a table subscribed only to the digest would
not repaint.

C<budget/catalogue> is the second token, covering exactly what the
digest does not: every group and category's id, name, group, kind, sort
order, hidden flag, carry-overspend flag and target tuple, in id order. The two together are what the
envelope grid watches. It costs two extra C<SELECT>s per recompute,
which is the same trade C<Screen::Main.set-view> already makes for the
lookup caches.

=head2 …and neither of them can see a memo

Both tokens are about the B<budget>. Neither carries a payee's name, a
transaction's memo or its cleared state, and the register shows all
three: renaming a payee, retyping a memo or pressing C<c> on a row
leaves the digest and the catalogue byte-identical, and a register
keyed on those two would repaint nothing.

C<ws/rev> is the third token and the coarsest: an integer bumped by
every C<recompute>, which is to say by every successful mutation and by
the initial load. The register and the sidebar key on it. It is
deliberately blunt — it says "something was written", not what — which
is the right resolution for a pane that rebuilds its rows wholesale
anyway, and the wrong one for the envelope grid, which is why the grid
keeps the two finer tokens.

Monotonic rather than a content hash: a counter cannot collide, and an
undo that restores a previous state still has to repaint.

=head2 Reconcile mode is one path, and it clears itself

C<accounts/reconcile> is either C<Nil> or a two-key map naming the
account being reconciled and the statement balance typed into the
dialog. Three things about it are load-bearing.

B<It is written with C<db-replace>, never C<db>.> The C<db> effect
deep-merges, so merging C<Nil> — or a map for a different account —
into a populated one either does nothing or leaves half the old map
behind. Leaving reconcile mode has to be an exact replacement.

B<It is a mode, so it has to end.> Switching to another ledger, or to
another tab, exits it (C<accounts/select-account> and
C<app/tab-selected> clear it themselves). A statement balance is about
one account, and a "Reconciling" title left on a register the user has
walked away from is a lie the next keystroke acts on. Cleared marks
already made are kept either way: they are facts about transactions,
not about the mode.

B<It never survives a reload.> Nothing here is persisted — the
statement balance is a number the user is holding in their hand, not
part of the budget.

=head2 The one mutation effect

Every gateway call in C<App::Moneymoor> answers with a C<Failure> on
invalid input rather than throwing, and every one of them needs the
same four things afterwards: check for failure, toast the message,
defuse the Failure, recompute. Writing that at thirty call sites is
thirty chances to forget the C<.so> and get a re-thrown Failure at some
unrelated sink later.

So there is exactly one effect, C<ws/mutate>, and it takes the gateway
call as a closure:

=begin code :lang<raku>

# From a keybind or a modal's submit handler:
$store.dispatch('ws/mutate-requested', action => -> {
    $workspace.move-money($period, $from, $to, $pence);
});

# Or, from a handler that has other state to write in the same delta:
$store.register-handler('budget/assign-requested', -> $st, %ev {
    (
        (db => { budget => { selected-category-id => %ev<category-id> } }),
        ('ws/mutate' => { action => -> {
            $workspace.set-assigned(%ev<period>, %ev<category-id>, %ev<amount>);
        } }),
    );
});

=end code

On C<Failure> the message is toasted, the Failure is defused, and the
recompute is B<skipped> — a write that did not happen must not bump the
digest, or every subscription in the app repaints to say nothing
changed. On success the budget is recomputed through
C<max(current-period, viewed-period)> so future periods materialise,
the lookup caches are rebuilt, and the digest plus the overspent badge
count land in the store.

Effects run I<after> the dispatching handler's own C<db> delta has been
applied, so a handler can write the period and let the effect recompute
against it in one dispatch.

=head2 Recompute is also callable directly

C<recompute($store)> is public because two paths need it outside the
mutation flow: the initial load (there is nothing to mutate yet) and
period navigation (the through-period moved, but no fact did). Both go
through the same code, so a bug in the badge arithmetic cannot show up
on one path and not the other.

=head1 EVENTS

=item C<app/init> — seeds the whole state tree and recomputes. Payload:
      C<theme>, C<icons> (both optional; they mirror Config).
=item C<app/tab-selected> — C<{ name }>. Writes C<app/tab>.
=item C<app/period-prev> / C<app/period-next> — step C<app/period>
      along the workspace's scheme and recompute.
=item C<app/period-set> — C<{ period }>. Jump straight to a period;
      ignores anything that is not a real period start under the
      workspace's scheme rather than corrupting the store.
=item C<budget/toggle-inspector> / C<budget/toggle-hidden> — flip the
      two budget-tab view switches. No recompute: neither changes a
      fact, only which rows get drawn.
=item C<budget/select-category> — C<{ category-id }>. The grid's
      cursor. An undefined id is legal and means "the cursor is on a
      group header", which is not a category.
=item C<budget/toggle-group> — C<{ group-id }>. Fold or unfold one
      group in C<budget/collapsed-groups>. Also no recompute.
=item C<accounts/select-account> — C<{ account-id }>. The sidebar's
      cursor, and so which ledger the register shows. C<0> — the
      default — is All Accounts, not "none": a missing or undefined id
      is written through as 0 rather than left to every read site to
      guard.
=item C<accounts/toggle-closed> — fold or unfold the sidebar's
      C<CLOSED (n)> bucket. No recompute: closed accounts are always
      in the derivation, this only decides whether they are drawn.
=item C<accounts/reconcile-start> — C<{ account-id, statement }>.
      Enter reconcile mode against a statement balance in pence. An
      account id of 0 (All Accounts) or an unparseable statement is
      refused rather than written: reconciling every ledger at once is
      not a thing.
=item C<accounts/reconcile-exit> — leave reconcile mode, keeping every
      cleared mark made in it.
=item C<reports/toggle-by-group> — flip the reports tab between
      per-envelope and per-group aggregation. No recompute: it changes
      how the same derivation is added up, not any fact.
=item C<ws/mutate-requested> — C<{ action }>. The generic doorway to
      the C<ws/mutate> effect for call sites with nothing else to
      write; handlers with their own delta should return the effect
      directly instead.

=head1 EFFECTS

=item C<ws/mutate> — C<{ action }>, the closure described above.
=item C<ws/recompute> — no payload. Recompute without mutating; what
      C<app/init> and the period-nav handlers return.

=head1 SEE ALSO

=item L<App::Moneymoor::Screen::Main> — owns the cache C<on-view> fills.
=item L<App::Moneymoor::Service::Workspace> — the gateways being called,
      and the owner of the C<scheme> every step here navigates along.
=item L<App::Moneymoor::Util::Period> — C<next-period> / C<prev-period>
      / C<period-of>, the navigation the handlers below delegate to.
=item L<App::Moneymoor::Service::Budget> — C<valid-period>, and the
      C<BudgetView> being cached.

=end pod

unit class App::Moneymoor::StoreHandlers;

use Selkie::Store;

use App::Moneymoor::Service::Workspace;
use App::Moneymoor::Service::Budget;

has App::Moneymoor::Service::Workspace $.workspace is required;

#| Where a failed mutation's message goes. Defaults to a no-op so the
#| handlers are constructible in a unit test with no C<Selkie::App>.
has &.toast = -> Str $ { };

#| Where a fresh C<BudgetView> goes. C<Screen::Main> passes a closure
#| that replaces its cached view and rebuilds its lookup hashes.
has &.on-view = -> $ { };

method register(Selkie::Store:D $store --> Nil) {
    my $self-ref = self;

    # --- Bootstrap -------------------------------------------------------
    #
    # One handler seeds every path §5 of the UI spec names, so there is
    # exactly one place to read the state shape off. Selectors that
    # `// default` a missing path still work, but a store where every
    # path exists from tick one means a subscription's first firing
    # carries real values rather than a fallback that immediately
    # changes.
    $store.register-handler('app/init', -> $st, %ev {
        (
            (db => {
                app => {
                    tab    => 'budget',
                    period => $self-ref.workspace.current-period,
                    theme  => (%ev<theme> // 'gruvbox'),
                    icons  => (%ev<icons> // 'unicode'),
                },
                # Seeded at 0 so the first recompute's bump to 1 is a
                # change every register subscription sees, rather than
                # a first reading they have nothing to compare against.
                ws => {
                    rev => 0,
                },
                budget => {
                    digest               => '',
                    catalogue            => '',
                    overspent-count      => 0,
                    selected-category-id => Int,
                    collapsed-groups     => %(),
                    show-hidden          => False,
                    inspector            => True,
                },
                accounts => {
                    # 0, not a type object: "All Accounts" is a real
                    # selection the sidebar can sit on, and a nullable
                    # id would make every read site guard for it.
                    selected-account-id => 0,
                    closed-expanded     => False,
                    # Nil is "not reconciling", which is the state the
                    # app starts in and returns to; see "Reconcile
                    # mode is one path".
                    reconcile           => Nil,
                },
                reports => {
                    by-group => False,
                },
            }),
            ('ws/recompute' => %()),
        );
    });

    # --- Navigation ------------------------------------------------------

    $store.register-handler('app/tab-selected', -> $st, %ev {
        my Str $name = (%ev<name> // 'budget').Str;
        # An unknown tab name would leave the shell with no content
        # builder and a blank pane; clamp to the default instead.
        $name = 'budget' unless $name eq any(<budget accounts reports>);
        my @fx = (db => { app => { tab => $name } },);
        # Reconcile mode belongs to a register that is about to be
        # destroyed. Leaving it set would bring the mode back — with
        # the old statement balance — the next time the user opened
        # the accounts tab, whichever ledger they landed on.
        @fx.push(clear-reconcile())
            if $name ne 'accounts'
            && ($st.get-in('accounts', 'reconcile')).defined;
        @fx.List;
    });

    $store.register-handler('app/period-prev', -> $st, %ev {
        step-period($st, $self-ref.workspace, 'prev');
    });

    $store.register-handler('app/period-next', -> $st, %ev {
        step-period($st, $self-ref.workspace, 'next');
    });

    $store.register-handler('app/period-set', -> $st, %ev {
        # `.Str` before the check, not after: `period-start` takes a
        # `Str` and a caller passing an Int (or nothing) would fail the
        # binding rather than the validation.
        my Str $period = (%ev<period> // '').Str;
        # A key that is not a real start under the workspace's scheme
        # would propagate into `budget(:through-period)` and come back
        # as a Failure from deep inside the derivation — and an
        # unmigrated 'YYYY-MM' month would not even parse. Refuse it
        # here, where the caller's mistake is still local.
        period-start($self-ref.workspace.scheme, $period)
            ?? ((db => { app => { period => $period } }),
                ('ws/recompute' => %()))
            !! ();
    });

    # --- Budget-tab view toggles -----------------------------------------
    #
    # Neither touches a fact, so neither recomputes: they change which
    # rows the budget table draws and whether the inspector rail is
    # mounted, both of which are read at row-build time. Handlers
    # rather than direct `assoc-in` calls from the keybind so the
    # toggle is one auditable write with one name.

    $store.register-handler('budget/toggle-inspector', -> $st, %ev {
        my Bool $now = ($st.get-in('budget', 'inspector') // True).Bool;
        (db => { budget => { inspector => !$now } },);
    });

    $store.register-handler('budget/toggle-hidden', -> $st, %ev {
        my Bool $now = ($st.get-in('budget', 'show-hidden') // False).Bool;
        (db => { budget => { show-hidden => !$now } },);
    });

    # The grid's cursor. An undefined id is the group-header case and
    # is written through as a type object rather than dropped: the
    # inspector rail has to be able to say "nothing selected", and a
    # stale id left in the store would have it describing a row the
    # cursor has left.
    $store.register-handler('budget/select-category', -> $st, %ev {
        my $raw = %ev<category-id>;
        my Int $id = $raw.defined ?? $raw.Int !! Int;
        (db => { budget => { selected-category-id => $id } },);
    });

    #|( Fold / unfold one group.
    #
    #   Two things here are load-bearing. The Hash is a *copy* — a
    #   selector handed back the very Hash it had just mutated in place
    #   would compare equal to itself and the fold would never repaint.
    #   And the effect is `db-replace`, not `db`: `db` deep-merges, so
    #   merging a Hash with one fewer key into the stored one is a
    #   no-op and a group could be folded but never unfolded.
    #
    #   Unfolding removes the key rather than setting it False, so
    #   "collapsed" is exactly "present in this map" and the row
    #   builder's `?%collapsed{$id}` needs no second reading. )
    $store.register-handler('budget/toggle-group', -> $st, %ev {
        my $gid = %ev<group-id>;
        if $gid.defined {
            my %next = ($st.get-in('budget', 'collapsed-groups') // %()).Hash;
            my Str $key = $gid.Str;
            if %next{$key} { %next{$key}:delete } else { %next{$key} = True }
            (('db-replace' => {
                path  => <budget collapsed-groups>,
                value => %next,
            }),);
        } else {
            ();
        }
    });

    # --- Accounts-tab state ----------------------------------------------
    #
    # Neither touches a fact, so neither recomputes. The register's
    # rows are rebuilt from the id, and closed accounts are in the
    # derivation whether or not the sidebar is drawing them.

    #|( Which ledger the register is showing. An undefined or
    #   unparseable id lands on 0 — All Accounts — rather than
    #   clearing the register: the sidebar always has a cursor
    #   somewhere, and "no account selected" is not one of its
    #   states. )
    $store.register-handler('accounts/select-account', -> $st, %ev {
        my $raw = %ev<account-id>;
        my Int $id = $raw.defined ?? $raw.Int !! 0;
        my @fx = (db => { accounts => { selected-account-id => $id } },);
        # A statement balance is about one ledger. Arrowing onto
        # another one ends the reconciliation rather than carrying the
        # figure across, which would show a diff against an account
        # the statement says nothing about.
        my $mode = $st.get-in('accounts', 'reconcile');
        @fx.push(clear-reconcile())
            if $mode.defined && ($mode<account-id> // 0).Int != $id;
        @fx.List;
    });

    $store.register-handler('accounts/toggle-closed', -> $st, %ev {
        my Bool $now = ($st.get-in('accounts', 'closed-expanded') // False).Bool;
        (db => { accounts => { closed-expanded => !$now } },);
    });

    #|( Enter reconcile mode. Both fields are validated here rather
    #   than trusted from the dialog: a mode keyed on All Accounts
    #   would put a diff in the register title that is the difference
    #   between a statement and the sum of every ledger, which is not
    #   a number about anything. )
    $store.register-handler('accounts/reconcile-start', -> $st, %ev {
        my $raw = %ev<account-id>;
        my Int $id = $raw.defined ?? $raw.Int !! 0;
        my $statement = %ev<statement>;
        ($id > 0 && $statement.defined)
            ?? (('db-replace' => {
                    path  => <accounts reconcile>,
                    value => %( account-id => $id,
                                statement  => $statement.Int ),
                }),)
            !! ();
    });

    # db-replace, not db: `db` deep-merges, and merging Nil into a
    # populated map leaves the map exactly as it was — the mode could
    # be entered but never left.
    $store.register-handler('accounts/reconcile-exit', -> $st, %ev {
        (clear-reconcile(),);
    });

    # --- Reports-tab state ------------------------------------------------

    $store.register-handler('reports/toggle-by-group', -> $st, %ev {
        my Bool $now = ($st.get-in('reports', 'by-group') // False).Bool;
        (db => { reports => { by-group => !$now } },);
    });

    # --- The mutation doorway --------------------------------------------
    #
    # For call sites that have nothing to write alongside the gateway
    # call. Handlers that DO (an assign that also moves the cursor, say)
    # should return the `ws/mutate` effect themselves so both land in
    # one dispatch rather than two.
    $store.register-handler('ws/mutate-requested', -> $st, %ev {
        %ev<action> ~~ Callable
            ?? (('ws/mutate' => { action => %ev<action> }),)
            !! ();
    });

    # --- Effects ---------------------------------------------------------

    $store.register-fx('ws/recompute', -> $st, %params {
        $self-ref.recompute($st);
    });

    #| The single write path. See the DESCRIPTION: check, toast,
    #| defuse, skip. The `.so` is not optional — an undefused Failure
    #| re-throws when it is next sunk, which in a TUI means a crash
    #| some frames later with a backtrace pointing at innocent code.
    $store.register-fx('ws/mutate', -> $st, %params {
        my $action = %params<action>;
        if $action ~~ Callable {
            my $result = $action();
            if $result ~~ Failure {
                $self-ref.toast.($result.exception.message);
                $result.so;
            } else {
                $self-ref.recompute($st);
            }
        }
    });

    Nil
}

#|( The period the derivation has to reach: the later of the period
    containing today and the period the user is looking at.

    Forward navigation is what makes this necessary — a budget with no
    facts past March still has to show April's envelopes when the user
    presses C<]>, and C<compute> only materialises periods inside the
    range it is given. Backwards navigation needs nothing special: past
    periods are already in the range. )
method through-period(Selkie::Store:D $store --> Str) {
    my Str $current = $!workspace.current-period;
    my Str $viewed = ($store.get-in('app', 'period') // '').Str;
    return $current unless period-start($!workspace.scheme, $viewed);
    # `max` on two 'YYYY-MM-DD' strings is a plain string comparison —
    # the format is fixed-width and zero-padded, so lexical order IS
    # chronological order.
    $viewed gt $current ?? $viewed !! $current;
}

#|( Re-derive the budget, hand the view to C<on-view>, and publish the
    scalars the store carries: the digest every budget subscription
    keys off, the catalogue token beside it, the overspent count the
    tab badge shows, and C<ws/rev>.

    Public because the initial load and period navigation both need a
    recompute with no mutation in front of it. )
method recompute(Selkie::Store:D $store --> Nil) {
    my Str $through = self.through-period($store);
    my $view = $!workspace.budget(through-period => $through);

    &!on-view($view);

    my Str $viewed = ($store.get-in('app', 'period') // $through).Str;
    # The blunt token, bumped first so a subscription keyed on it fires
    # in the same tick as the two fine-grained ones. Read-then-write
    # rather than an increment handler: `recompute` is called from
    # inside an effect, where a dispatch would land a tick late.
    $store.assoc-in('ws', 'rev',
        value => (($store.get-in('ws', 'rev') // 0).Int + 1));
    $store.assoc-in('budget', 'digest', value => $view.canonical-digest);
    $store.assoc-in('budget', 'catalogue', value => catalogue-token(
        $!workspace.categories.find-all(:include-hidden),
        $!workspace.categories.find-groups(:include-hidden),
    ));
    $store.assoc-in('budget', 'overspent-count',
        value => overspent-count($view, $viewed));
    Nil
}

#|( The effect that leaves reconcile mode, as one named thing rather
    than as three call sites that each have to remember it is
    C<db-replace> and not C<db>.

    Returned as a C<Pair> so a handler can C<push> it onto its own
    effect list. )
our sub clear-reconcile(--> Pair) is export {
    'db-replace' => { path => <accounts reconcile>, value => Nil };
}

#|( C<accounts/reconcile> as a flat string, for a subscription
    selector.

    The state itself is a small Hash, and C<Selkie::Store> compares
    subscription values by content digest while keying objects by
    identity — a selector handing the Hash back would read as changed
    on every tick and rebuild the register with it. Not reconciling is
    the empty string. )
our sub reconcile-token($reconcile --> Str) is export {
    return '' without $reconcile;
    ($reconcile<account-id> // 0).Str ~ "\x[1F]"
        ~ ($reconcile<statement> // 0).Str;
}

#|( A stable string describing the B<shape> of the envelope catalogue:
    which groups and categories exist, what they are called, where they
    sit, whether they are hidden, whether they carry their overspending,
    and the whole of what they are targeting — amount, kind, goal
    period, stamped plan start and repeat.

    This is the change token for everything C<canonical-digest> cannot
    see — see "The digest is not enough on its own". Ordered by id so
    two calls over the same catalogue are byte-identical whatever order
    the rows came back in, and built from the same fields the row
    builder reads, so a change that would alter a rendered row always
    alters the token and a change that would not, does not. )
our sub catalogue-token(@categories, @groups --> Str) is export {
    my Str @lines;
    for @groups.sort({ .id // 0 }) -> $g {
        @lines.push(join('|', 'G', $g.id // 0, $g.sort-order // 0,
            ($g.hidden ?? 1 !! 0), $g.name // ''));
    }
    for @categories.sort({ .id // 0 }) -> $c {
        # The whole target tuple is in here for the same reason the name
        # is: the derivation cannot see any of it (it is view-layer
        # data), but the grid draws a Target column and the rail a
        # target block, so saving a new target has to move a token or
        # the screen keeps the old figure until something else repaints
        # it.
        #
        # All five columns, not just the amount. A kind change at the
        # same pence changes what both of them render; a goal date or a
        # repeat changes the schedule; and target_start — which only
        # Service::Workspace.set-target ever writes — changes where the
        # ramp starts from, so a re-stamp moves every milestone after
        # it. Each is defaulted to a fixed string so a NULL column
        # tokenises identically every time it is read.
        # carry_overspend is in here for a subtler version of the same
        # reason. The derivation CAN see it — it is the flag rule 3
        # keys on — so flipping it on an envelope that has ever been
        # overspent moves the digest by itself. On one that has not, it
        # changes nothing the engine produces and only the editor's
        # checkbox would come back stale, which is exactly the class of
        # change this token exists to catch.
        @lines.push(join('|', 'C', $c.id // 0, $c.group-id // -1,
            $c.sort-order // 0, $c.kind // '', ($c.hidden ?? 1 !! 0),
            ($c.carry-overspend ?? 1 !! 0),
            $c.target-pence // 0, $c.target-kind // '',
            $c.target-period // '', $c.target-start // '',
            $c.target-repeat // 0, $c.name // ''));
    }
    @lines.join("\n");
}

#|( How many envelopes are in the red in C<$period>: the budget tab's
    badge.

    Walks C<BudgetPeriod.category-periods> rather than every category,
    which is both cheaper and more correct — the derivation omits rows
    that are all-zero, and an all-zero row is by definition not
    overspent. The C<rta> pseudo-category never gets a row at all (it
    is not an envelope), so a negative Ready-to-Assign does not leak
    into the envelope badge; that is the period-level C<rta-negative>
    flag's job.

    A period outside the derived range answers with a type object, so
    the guard is load-bearing rather than defensive: navigating back
    before the first fact is an ordinary thing to do. )
our sub overspent-count($view, Str:D $period --> Int) is export {
    my $bp = $view.period($period);
    return 0 without $bp;
    $bp.category-periods.grep(*.is-overspent).elems.Int;
}

#|( Is C<$p> a real period start under C<$scheme>?

    Two questions in one, because the store has to answer both before
    it writes a key: well-formedness (C<valid-period>, which is a
    format check and nothing more) and B<start-ness>, which only the
    scheme can settle — C<'2026-03-15'> is a start under a fortnightly
    scheme anchored on it and not under C<monthly/1>, and an
    unmigrated C<'2026-03'> is neither.

    C<period-of> throws on input it cannot parse; C<valid-period> has
    already excluded that, and the C<try> costs nothing to be sure. )
sub period-start($scheme, Str $p --> Bool) {
    return False unless valid-period($p);
    my $start = try $scheme.period-of($p);
    ($start.defined && $start eq $p).Bool;
}

#|( Shared body of C<app/period-prev> and C<app/period-next>: step the
    viewed period one place along the workspace's scheme and recompute.

    The scheme is read off the workspace on every call rather than
    captured: it is the workspace that owns which scheme a budget is
    keyed by, and a captured copy would go stale the moment that
    changes.

    C<next-period> / C<prev-period> B<throw> on a key that is not a
    start under the scheme, which can only happen if something wrote
    junk into C<app/period> — in that case the step is dropped and the
    period reset to the current one rather than letting the exception
    out of a handler, where it would take down the dispatch. )
sub step-period($st, $workspace, Str:D $direction --> List) {
    my $scheme = $workspace.scheme;
    my Str $current = ($st.get-in('app', 'period') // '').Str;
    unless period-start($scheme, $current) {
        return ((db => { app => { period => $workspace.current-period } }),
                ('ws/recompute' => %()));
    }
    my $next = try $direction eq 'prev'
        ?? $scheme.prev-period($current)
        !! $scheme.next-period($current);
    return () without $next;
    (
        (db => { app => { period => $next } }),
        ('ws/recompute' => %()),
    );
}
