=begin pod

=head1 NAME

App::Moneymoor::View::RegisterRow - the row models behind the accounts
sidebar and the transaction register, including the running balance.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::View::RegisterRow;

# The sidebar: one string per row, plus the metadata the screen acts on.
my @side = sidebar-rows(
    accounts => $ws.accounts.find-all(:include-closed),
    view     => $view,
    icons    => icons('unicode'),
);
@side[0]<label>;      # 'All Accounts          £1,240.00'
@side[1]<kind>;       # 'header'  — BUDGET, not actionable
@side[2]<id>;         # the first account's id

net-worth(accounts => @accounts, view => $view);   # Σ working, open only

# The register: rows straight into Selkie::Widget::Table.
my @rows = register-rows(
    transactions   => $ws.transactions.find-by-account($current.id),
    payees         => %payees-by-id,
    categories     => %categories-by-id,
    accounts       => %accounts-by-id,
    splits         => %splits-by-txn-id,
    peer-accounts  => %account-id-by-txn-id,
    running-balance => True,
    icons          => $icons,
);
@rows[0]<payee>;      # '⇄ Savings'      (a transfer leg)
@rows[1]<category>;   # '(3 splits)'
@rows[1]<outflow>;    # '   £42.10 '
@rows[1]<balance>;    # '   £957.90 '

# The columns those rows fill, which depend on the view and the width:
register-columns(width => 120).map(*<name>);
# (date payee category cleared outflow inflow balance)
register-columns(width => 80).map(*<name>);
# (date payee category cleared outflow inflow)          — no room
register-columns(all-accounts => True, width => 120).map(*<name>);
# (date payee category cleared outflow inflow account)

next-cleared-state('cleared');    # 'reconciled'

=end code

=head1 DESCRIPTION

Pure functions. Models, lookup hashes and a C<BudgetView> go in, row
hashes come out — no widgets, no store, no database. The awkward parts
of a register (a running balance that only makes sense in one order, a
transfer leg that has to name the account at the I<other> end, a split
set that renders three different ways) are all here, where they can be
tested without a terminal.

=head2 Rows come back newest first

C<register-rows> returns rows in reverse chronological order — the most
recent transaction first — because a register grows at the recent end and
scrolling to the bottom of a long ledger to reach today is tedious.

This is a presentation order only. The gateway still returns C<(date, id)>
ascending and B<must> keep doing so: C<Service::Budget> derives each period
from the running balance at the instant of each purchase, and the reports
depend on the same ordering. The reversal happens once, on the finished row
list, at the very end of C<register-rows>.

Selection survives the flip: C<Screen::Accounts> re-finds the selected row by
transaction id rather than by index, so the cursor follows its row.

=head2 The running balance is a scan, and only in one view

C<balance> is the cumulative sum of every amount up to and including
the row, in the C<(date, id)> order the gateway returns — B<not> in the
order the rows are displayed. The scan runs before the reversal above, so
each row's balance is the account's balance as of that transaction; running
it over reversed input would instead count backwards from zero, which yields
a column that looks plausible and is wrong.

That is a number about B<one> account: in the All Accounts view it would be the
sum of unrelated ledgers interleaved by date, which is not a balance of
anything. So C<:running-balance> is off by default, the column is only
added in the single-account view, and the All Accounts view spends the
same columns on an C<account> column instead.

The column is also dropped below C<BALANCE-MIN-COLS> (95) — see
C<register-columns>. Losing the running balance on a narrow terminal is
better than losing the pence off every figure in the row, which is what
C<Table> truncation would do.

=head2 What a transfer leg says

A transfer is two rows in two registers, each with the peer's id in
C<transfer_peer_id> and B<no> payee. The payee cell therefore renders
C<'⇄ <the other account>'>, which needs a hop the row builder cannot do
on its own: peer transaction id → account id → account. That hop is the
C<:%peer-accounts> parameter (transaction id → account id); the screen
builds it once per repaint. A peer that is not in the map renders as a
bare C<'⇄ Transfer'> rather than a blank cell — a leg with an unknown
peer is still legibly a transfer.

=head2 The category cell has three shapes

=item B<no splits> — C<'—'>. An uncategorised transaction: every
      transaction on a tracking account, and both legs of a transfer
      that stays on one side of the budget.
=item B<one split> — the category's name, or C<'Inflow: Ready to
      Assign'> when it is the C<rta> row. The engine stores a
      single-category transaction as exactly one split, so this is the
      common case rather than a special one.
=item B<more than one> — C<'(3 splits)'>. The figures are in the split
      editor; the register's job is to say that there are some.

=head2 Reconciling changes the title, not the rows

§4.5's reconcile mode is a state of the B<pane>, not of the rows: the
register keeps showing the same transactions, C<c> keeps cycling the
same three states, and the only thing that changes is the frame. So
this module's part in it is four small functions — C<register-title>'s
C<:$statement> variant, C<reconcile-diff>, C<reconcile-style> and
C<promotable-ids> — and no change at all to C<register-rows>.

C<promotable-ids> is the rule the whole flow turns on: finishing a
reconciliation promotes the transactions the user marked B<cleared>,
and nothing else. An C<uncleared> row is one the statement did not
mention, and sweeping it up would put a "this matched a statement"
mark on a transaction no statement has ever seen.

=head2 §2, and what a Table can colour

C<Selkie::Widget::Table> resolves B<one> style per row — C<row-style>
receives the whole row hash and returns a single C<Selkie::Style> — so
the register cannot paint the Outflow cell red and leave the rest of
the row alone. §2's "outflow amounts red / inflow green" is written
down here as the C<severity> key on every row, and C<register-style>
resolves it the only way a whole-row painter sensibly can:

=begin table
Row                       | severity   | Style
--------------------------+------------+------------------
reconciled                | reconciled | fg-dim
money in                  | inflow     | fg-green
money out                 | outflow    | fg-base
zero, or no direction     | normal     | fg-base
sidebar section header    | header     | fg-bright bold on bg-surface
=end table

Outflow is the default state of a register — a month of shopping is
mostly outflow — and painting every one of those rows red would leave
nothing for the colour to mean. Inflow keeps its green because it is
the exception the eye is looking for. Reconciled outranks both: a
locked row is finished business whichever way the money went.

The resolution itself is delegated to
C<App::Moneymoor::View::BudgetRow::severity-style>, so the register and
the envelope grid cannot end up disagreeing about what the palette's
green is.

=head2 Column widths, and the two that are not §4.4's

§4.4 pins the register's columns. Two are one cell wider here, for the
same reason C<BudgetRow>'s money cells reserve a trailing gutter:
C<Table> lays columns out edge to edge and pads every cell to the full
column width, so a cell whose content exactly fills its column touches
its neighbour.

=item B<date> — §4.4 says 10, which is exactly the width of
      C<'YYYY-MM-DD'>. At 10 the date would run into the payee; at 11
      it keeps the one-cell gutter every other column has.
=item B<cleared> — §4.4 says 1, which is exactly the width of the
      state glyph. At 2 (a leading space, then the glyph) the icon
      stops touching a category name long enough to fill the flex
      column.

Every other width is §4.4's.

=head1 EXPORTS

=item C<register-rows(:@transactions!, :%payees, :%categories,
      :%accounts, :%splits, :%peer-accounts, :$running-balance,
      :$icons --> List)>
=item C<register-columns(:$all-accounts, :$width, --> List)> —
      C<< { name, label, width } >>, C<width> 0 meaning flex.
=item C<register-title(Str $name, $balance, :$statement --> Str)>
=item C<reconcile-diff(Int $statement, $balance --> Int)> /
      C<reconcile-style(Int $diff, :$theme! --> Selkie::Style)> /
      C<promotable-ids(@transactions --> List)>
=item C<sidebar-rows(:@accounts!, :$view!, :$show-closed, :$width,
      :$icons --> List)>
=item C<net-worth(:@accounts!, :$view! --> Int)>
=item C<working-balance($view, $id --> Int)>
=item C<sidebar-label(Str $left, Str $right, Int $width --> Str)>
=item C<account-icon($account, :$icons --> Str)>
=item C<cleared-icon(Str $state, :$icons --> Str)> /
      C<next-cleared-state(Str $state --> Str)>
=item C<register-style(Str $severity, :$theme! --> Selkie::Style)>
=item C<DATE-COLS> / C<CLEARED-COLS> / C<OUTFLOW-COLS> /
      C<INFLOW-COLS> / C<BALANCE-COLS> / C<ACCOUNT-COLS> /
      C<BALANCE-MIN-COLS> / C<SIDEBAR-COLS> / C<SIDEBAR-TEXT-COLS> /
      C<UNCATEGORISED-CELL> / C<RTA-LABEL> / C<CLEARED-STATES>

=head1 SEE ALSO

=item L<App::Moneymoor::Screen::Accounts> — the widget layer.
=item L<App::Moneymoor::View::BudgetRow> — C<money-cell>,
      C<money-header> and the severity palette these share.
=item L<App::Moneymoor::Gateway::Transaction> — the C<(date, id)>
      order the running balance depends on.

=end pod

unit module App::Moneymoor::View::RegisterRow;

use Selkie::Style;

use App::Moneymoor::Service::Icons;
use App::Moneymoor::Theme;
use App::Moneymoor::Util::Money;
use App::Moneymoor::View::BudgetRow;

#| Register column widths, in cells. C<date> and C<cleared> are one
#| cell wider than §4.4's table — see "Column widths" in the Pod. The
#| payee and category columns are flex and so have no constant.
our constant DATE-COLS    is export = 11;
our constant CLEARED-COLS is export = 2;
our constant OUTFLOW-COLS is export = 10;
our constant INFLOW-COLS  is export = 10;
our constant BALANCE-COLS is export = 11;

#| The All-Accounts view's extra column, which takes the balance
#| column's place. Wide enough for most account names; C<Table>
#| truncates the rest, and the sidebar is where the full name lives.
our constant ACCOUNT-COLS is export = 14;

#|( Terminal columns below which the running-balance column is
    dropped. §4.4's number: at 95 the fixed columns (date, cleared,
    outflow, inflow, balance) plus the frame leave the payee and
    category columns about 25 cells each, which is the point where a
    payee name stops being recognisable. )
our constant BALANCE-MIN-COLS is export = 95;

#| Total width of the accounts sidebar, frame and padding included.
#| Its Border spends four of these columns (two frame glyphs, two
#| padding cells) on chrome.
our constant SIDEBAR-COLS      is export = 26;
our constant SIDEBAR-TEXT-COLS is export = SIDEBAR-COLS - 4;

#| What the category cell says for a transaction with no splits.
our constant UNCATEGORISED-CELL is export = '—';

#| How the Ready-to-Assign row is named everywhere the register can see
#| it — the cell, and the transaction editor's category picker.
our constant RTA-LABEL is export = 'Inflow: Ready to Assign';

#| The cleared cycle, in the order C<c> walks it (§4.4).
our constant CLEARED-STATES is export = <uncleared cleared reconciled>;

# The sidebar's section captions. Upper case rather than title case so
# they cannot be mistaken for an account name at a glance.
my constant BUDGET-SECTION   = 'BUDGET';
my constant TRACKING-SECTION = 'TRACKING';

#| One account's working balance, tolerating a view that has not been
#| computed yet (the frames between building the screen and the first
#| recompute, where every balance is legitimately zero).
sub working-balance($view, $id --> Int) is export {
    return 0 unless $view.defined && $id.defined;
    $view.account-balance($id.Int).working.Int;
}

#|( Σ working balance over the B<open> accounts — cash, credit and
    tracking alike. That is what "net worth" means: the tracking
    accounts are exactly the ones holding the house and the pension,
    and leaving them out would print a number that is not anybody's.

    Closed accounts are out. A closed account is one the user has
    finished with; its balance is zero in the ordinary case and a
    historical curiosity in the rest. )
sub net-worth(:@accounts!, :$view! --> Int) is export {
    [+] @accounts.grep({ .defined && !.closed }).map({
        working-balance($view, .id)
    }).Slip, 0;
}

#| The glyph for an account's type.
sub account-icon($account, :$icons = icons() --> Str) is export {
    return $icons.account-cash without $account;
    return $icons.account-credit   if $account.is-credit;
    return $icons.account-tracking if $account.is-tracking;
    $icons.account-cash;
}

#| The glyph for a cleared state. An unknown state — which the engine
#| cannot produce — reads as uncleared rather than as a blank cell.
sub cleared-icon(Str $state, :$icons = icons() --> Str) is export {
    given ($state // 'uncleared') {
        when 'reconciled' { $icons.cleared-reconciled }
        when 'cleared'    { $icons.cleared-cleared    }
        default           { $icons.cleared-uncleared  }
    }
}

#| The next state in §4.4's cycle: uncleared → cleared → reconciled →
#| uncleared. An unrecognised state enters the cycle at C<cleared>.
sub next-cleared-state(Str $state --> Str) is export {
    my $idx = CLEARED-STATES.first($state // '', :k);
    $idx.defined ?? CLEARED-STATES[($idx + 1) % CLEARED-STATES.elems]
                 !! 'cleared';
}

#|( Turn a register or sidebar severity key into a style. Delegates to
    C<BudgetRow::severity-style> so the two tables cannot disagree
    about the palette; see "§2, and what a Table can colour" for why
    C<outflow> is not red. )
sub register-style(Str $severity, App::Moneymoor::Theme :$theme!
                   --> Selkie::Style) is export {
    my Str $key = do given ($severity // 'normal') {
        when 'reconciled' { 'zero'     }   # fg-dim
        when 'inflow'     { 'positive' }   # fg-green
        when 'header'     { 'header'   }
        default           { 'normal'   }
    };
    severity-style($key, :$theme);
}

#|( One sidebar line: C<$left> flush left, C<$right> flush right, in
    C<$width> cells with at least one space between them.

    The left side is truncated (with an ellipsis) rather than the
    right: an account whose name does not fit is still recognisable
    from its first dozen characters, where a balance missing its last
    two digits is a lie. )
sub sidebar-label(Str:D $left, Str:D $right, Int:D $width --> Str) is export {
    my Int $w = $width max 1;
    return $left.chars > $w ?? truncate($left, $w) !! $left
        if $right.chars == 0;

    # One cell of separation is the floor; below that the balance wins
    # the whole line, because a row showing only a name says less than
    # a row showing only a figure.
    my Int $room = $w - $right.chars - 1;
    return $right.chars > $w ?? $right.substr(0, $w)
                             !! ' ' x ($w - $right.chars) ~ $right
        if $room < 1;

    my Str $name = $left.chars > $room ?? truncate($left, $room) !! $left;
    $name ~ (' ' x ($w - $name.chars - $right.chars)) ~ $right;
}

#| Cut a string to C<$width> cells, ending in an ellipsis when
#| anything was lost. At one cell there is no room for both, so the
#| ellipsis alone is the honest answer.
sub truncate(Str:D $text, Int:D $width --> Str) {
    return $text if $text.chars <= $width;
    return '…' if $width <= 1;
    $text.substr(0, $width - 1) ~ '…';
}

#|( The sidebar, top to bottom: All Accounts, the on-budget section,
    the tracking section, and the closed bucket.

    Every row carries C<kind>, and only three kinds are actionable:

    =item C<all> — the All Accounts pseudo-row, id 0.
    =item C<account> — a real account; C<id> is its id.
    =item C<closed-toggle> — the C<CLOSED (n)> fold.

    C<header> rows are captions. The screen re-selects the previous
    account when the cursor lands on one, which is why they carry the
    previous row's id rather than nothing: a caption is a place the
    cursor passes through, not a selection.

    A section with no accounts in it gets no caption. An empty
    "TRACKING" heading on a budget with no tracking accounts is
    furniture for a feature that is not in use — the same call
    C<BudgetRow> makes about empty system groups. )
sub sidebar-rows(
    :@accounts!,
    :$view!,
    Bool :$show-closed = False,
    Int  :$width = SIDEBAR-TEXT-COLS,
    :$icons = icons(),
    --> List
) is export {
    my @live = @accounts.grep(*.defined).sort({
        ($_.sort-order // 0, $_.id // 0)
    });
    my @open   = @live.grep({ !.closed });
    my @closed = @live.grep({  .closed });

    my @rows;
    my Int $previous = 0;   # what a header row re-selects

    # No figure on this row. The net worth belongs to it arithmetically
    # — it is the sum of everything below — but "All Accounts" is
    # twelve of the twenty-two cells a sidebar line has, and any real
    # net worth would push the name into an ellipsis. It goes in the
    # pane's bottom title instead, where it has the whole width.
    @rows.push: %(
        kind => 'all', id => 0, closed => False, severity => 'normal',
        label => sidebar-label('All Accounts', '', $width),
    );

    sub section(Str:D $caption, @members --> Nil) {
        return unless @members.elems;
        @rows.push: %(
            kind => 'header', id => $previous, closed => False,
            severity => 'header', label => $caption,
        );
        for @members -> $a {
            $previous = ($a.id // 0).Int;
            @rows.push: %(
                kind => 'account', id => $previous, closed => ?$a.closed,
                severity => ($a.closed ?? 'reconciled' !! 'normal'),
                label => sidebar-label(
                    account-icon($a, :$icons) ~ ' ' ~ $a.name,
                    format-pence(working-balance($view, $a.id)), $width),
            );
        }
        Nil
    }

    section(BUDGET-SECTION,   @open.grep(*.is-on-budget));
    section(TRACKING-SECTION, @open.grep(*.is-tracking));

    if @closed.elems {
        @rows.push: %(
            kind => 'closed-toggle', id => $previous, closed => False,
            severity => 'header',
            label => ($show-closed ?? $icons.group-expanded
                                   !! $icons.group-collapsed)
                     ~ ' CLOSED (' ~ @closed.elems ~ ')',
        );
        if $show-closed {
            for @closed -> $a {
                $previous = ($a.id // 0).Int;
                @rows.push: %(
                    kind => 'account', id => $previous, closed => True,
                    severity => 'reconciled',
                    label => sidebar-label(
                        account-icon($a, :$icons) ~ ' ' ~ $a.name,
                        format-pence(working-balance($view, $a.id)), $width),
                );
            }
        }
    }

    @rows.List;
}

#|( The register's frame title: the account, its cleared balance and
    its working balance.

    All Accounts gets its bare name. The two figures are about one
    ledger — "cleared" is a statement-reconciliation concept — and
    summing them across every account would produce a pair of numbers
    that reconcile against nothing.

    C<:$statement> switches it into §4.5's reconcile-mode title:

        Reconciling · cleared £900.00 · statement £912.40 · diff +£12.40

    The working balance goes when the statement arrives, and that is
    the point of the swap. Reconciling is a comparison between two
    numbers — what the register says has cleared, and what the bank
    says — and the third figure in the title should be the one that
    closes the gap, not one about money the bank has not seen yet.

    The diff carries its sign explicitly (C<+£12.40>, not C<£12.40>)
    because the two directions mean opposite corrections: too much
    cleared, or not enough. )
sub register-title(Str $name, $balance, Int :$statement --> Str) is export {
    return ($name // 'Register') without $balance;
    with $statement {
        my Int $cleared = $balance.cleared.Int;
        return 'Reconciling · cleared ' ~ format-pence($cleared)
            ~ ' · statement ' ~ format-pence($statement)
            ~ ' · diff ' ~ format-pence($statement - $cleared, :plus);
    }
    ($name // 'Register')
        ~ ' · cleared ' ~ format-pence($balance.cleared.Int)
        ~ ' · working ' ~ format-pence($balance.working.Int);
}

#|( What is still between the register and the statement: the
    statement balance less what the account says has cleared.

    Positive means the bank has seen money the register has not
    cleared; negative means the register has cleared money the bank
    has not. Zero means done. Tolerates a view that has not been
    computed yet, where every balance is legitimately zero. )
sub reconcile-diff(Int:D $statement, $balance --> Int) is export {
    return $statement without $balance;
    $statement - $balance.cleared.Int;
}

#|( §4.5's colour for a reconcile diff: green at zero, red anywhere
    else.

    Red rather than amber: an unreconciled difference is not a warning
    about the future, it is a statement and a ledger that disagree
    right now. Delegated to C<BudgetRow::severity-style> so the frame
    cannot end up a different green from the envelope grid's. )
sub reconcile-style(Int:D $diff, App::Moneymoor::Theme :$theme!
                    --> Selkie::Style) is export {
    severity-style($diff == 0 ?? 'positive' !! 'cash-overspend', :$theme);
}

#|( The ids §4.5's finalize promotes: every transaction sitting at
    C<cleared>, and B<only> those.

    Not C<uncleared> — a transaction the statement does not mention
    has not been reconciled by finishing a reconciliation of the ones
    it does. Not C<reconciled> either, though re-setting those would be
    harmless: a promotion list that includes them makes the write count
    a function of the account's history rather than of what the user
    just did. )
sub promotable-ids(@transactions --> List) is export {
    @transactions.grep({ .defined && (.cleared // '') eq 'cleared' })
                 .map({ (.id // 0).Int }).List;
}

#|( The columns C<Screen::Accounts> installs, as
    C<< { name, label, width } >> hashes with C<width> 0 for flex.

    Two of them are conditional, and they trade places:

    =item B<balance> — single-account view only, and only at
       C<BALANCE-MIN-COLS> cells or wider. See "The running balance".
    =item B<account> — All Accounts only, where "which ledger is this
       row in" is the question the balance column would otherwise be
       answering badly.

    Returned as data rather than as C<Table> columns so the widths and
    the threshold can be asserted without a terminal. )
sub register-columns(Bool :$all-accounts = False, Int :$width = 0
                     --> List) is export {
    my @cols =
        %( name => 'date',     label => 'Date',     width => DATE-COLS ),
        %( name => 'payee',    label => 'Payee',    width => 0 ),
        %( name => 'category', label => 'Category', width => 0 ),
        # A blank caption: the column is two cells wide and every glyph
        # that could label it is one of the three it is already showing.
        %( name => 'cleared',  label => '',         width => CLEARED-COLS ),
        %( name    => 'outflow',
           label   => money-header('Outflow', OUTFLOW-COLS),
           width   => OUTFLOW-COLS ),
        %( name    => 'inflow',
           label   => money-header('Inflow', INFLOW-COLS),
           width   => INFLOW-COLS ),
    ;

    if $all-accounts {
        @cols.push: %( name => 'account', label => 'Account',
                       width => ACCOUNT-COLS );
    } elsif ($width // 0) >= BALANCE-MIN-COLS {
        @cols.push: %( name  => 'balance',
                       label => money-header('Balance', BALANCE-COLS),
                       width => BALANCE-COLS );
    }
    @cols.List;
}

#| A category cell's text for one split's category.
sub category-label($category --> Str) {
    return '(unknown category)' without $category;
    $category.is-rta ?? RTA-LABEL !! $category.name;
}

#| The payee cell: a transfer names the account at the other end, an
#| ordinary transaction names its payee, and a transaction with
#| neither leaves the cell empty rather than inventing a label.
sub payee-cell($txn, %payees, %accounts, %peer-accounts, $icons --> Str) {
    if $txn.is-transfer {
        my $peer-account-id = %peer-accounts{ $txn.transfer-peer-id } // Int;
        my $peer = $peer-account-id.defined ?? %accounts{$peer-account-id} !! Nil;
        return $icons.transfer ~ ' '
             ~ ($peer.defined ?? $peer.name !! 'Transfer');
    }
    my $payee = $txn.payee-id.defined ?? %payees{ $txn.payee-id } !! Nil;
    $payee.defined ?? $payee.name !! '';
}

#| The category cell's three shapes — see the Pod.
sub category-cell(@splits, %categories --> Str) {
    return UNCATEGORISED-CELL unless @splits.elems;
    return '(' ~ @splits.elems ~ ' splits)' if @splits.elems > 1;
    category-label(%categories{ @splits[0].category-id });
}

#|( The register's rows, in the order they were handed over — which is
    the gateway's C<(date, id)>, and which the running balance depends
    on being.

    Everything the row needs beyond the transaction itself arrives as a
    lookup hash, because the alternative is a row builder that queries,
    and a row builder that queries cannot be tested without a database.

    =item C<:%payees> / C<:%categories> / C<:%accounts> — id → model.
    =item C<:%splits> — transaction id → its splits.
    =item C<:%peer-accounts> — transaction id → the account it belongs
          to. Only transfer peers are ever looked up in it.
    =item C<:$running-balance> — off by default; see the Pod. )
sub register-rows(
    :@transactions!,
    :%payees = %(),
    :%categories = %(),
    :%accounts = %(),
    :%splits = %(),
    :%peer-accounts = %(),
    Bool :$running-balance = False,
    :$icons = icons(),
    --> List
) is export {
    my Int $running = 0;
    my @rows;

    for @transactions.grep(*.defined) -> $t {
        my Int $amount = ($t.amount // 0).Int;
        $running += $amount;

        my $account = %accounts{ $t.account-id } // Nil;
        my @txn-splits = (%splits{ $t.id } // []).List;

        @rows.push: %(
            kind     => 'txn',
            id       => ($t.id // 0).Int,
            transfer => ?$t.is-transfer,
            severity => severity-for-transaction($t),
            date     => ($t.date // ''),
            payee    => payee-cell($t, %payees, %accounts, %peer-accounts,
                                   $icons),
            category => category-cell(@txn-splits, %categories),
            cleared  => ' ' ~ cleared-icon($t.cleared, :$icons),
            outflow  => ($amount < 0
                ?? money-cell($amount.abs, OUTFLOW-COLS) !! ''),
            inflow   => ($amount > 0
                ?? money-cell($amount, INFLOW-COLS) !! ''),
            balance  => ($running-balance
                ?? money-cell($running, BALANCE-COLS) !! ''),
            account  => ($account.defined ?? $account.name !! ''),
        );
    }
    # Newest first. The scan above must stay chronological — each row's
    # balance is the account's balance *as of* that transaction, so
    # accumulating in reverse would count backwards from zero and produce a
    # column that looks plausible and is wrong. Build in (date, id) order,
    # then flip the finished rows for display.
    @rows.reverse.List;
}

#| §2's state key for one transaction. Reconciled outranks direction:
#| a locked row is finished business whichever way the money went.
sub severity-for-transaction($txn --> Str) is export {
    return 'normal' without $txn;
    return 'reconciled' if $txn.is-reconciled;
    return 'inflow'     if $txn.amount > 0;
    return 'outflow'    if $txn.amount < 0;
    'normal';
}
