=begin pod

=head1 NAME

App::Moneymoor::View::BudgetRow - the row model behind the envelope
table, and the one place §2's "state → colour" table is written down.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::View::BudgetRow;

my @rows = budget-rows(
    groups      => $ws.categories.find-groups(:include-hidden),
    categories  => $ws.categories.find-all(:include-hidden),
    view        => $view,
    scheme      => $ws.scheme,
    period      => '2026-08-01',
    collapsed   => %( '3' => True ),      # group 3 is folded shut
    show-hidden => False,
    icons       => icons('unicode'),
);

# Straight into Selkie::Widget::Table — the keys are the column names:
$table.set-rows(@rows);
$table.set-row-style(-> %row {
    severity-style(%row<severity>, theme => $theme)
});

@rows[0]<category>;    # '▾ Monthly Bills'
@rows[1]<category>;    # '  Rent'
@rows[1]<available>;   # '    £750.00 '   (right-aligned, one-cell gutter)
@rows[1]<target>;      # '    £750.00 '   — or blank, with no target
@rows[1]<severity>;    # 'positive'

# The header pill above the table is built from the same view:
rta-summary($view, '2026-08-01', icons => $icons);
# { text => 'Ready to Assign  £412.50', severity => 'rta-positive',
#   note => '£300.00 assigned in future periods', rta => 41250, … }

# And the pickers that have to list envelopes in the same order:
envelope-options(:@categories, :@groups, exclude-id => $rent-id);
# ('Monthly Bills · Council Tax' => 7, 'Credit Card Payments · Visa' => 9, …)

=end code

=head1 DESCRIPTION

Pure functions. No widgets, no store, no database — a C<BudgetView>,
some models and a period go in, row hashes come out. That is what makes
the grid's awkward parts (grouping, collapse, zero-fill, the two kinds
of overspending) testable without a terminal.

=head2 What a row is

Every hash carries the five C<Selkie::Widget::Table> column cells —
C<category>, C<assigned>, C<activity>, C<available>, C<target> —
already rendered as strings, plus the metadata the screen needs to act
on the row:

=item C<kind> — C<'group'> or C<'category'>.
=item C<id> — the group id or the category id. Group rows use
      C<UNGROUPED-ID> (0) for the bucket of categories with no group;
      no real row can have that id, because SQLite's C<INTEGER PRIMARY
      KEY> starts at 1.
=item C<group-id> — the owning group of a category row (again
      C<UNGROUPED-ID> when it has none).
=item C<hidden> — True for a retired envelope being shown because
      C<show-hidden> is on.
=item C<severity> — the §2 state key; C<severity-style> turns it into
      a C<Selkie::Style>.

The money cells are rendered here rather than by a C<Table> column
C<&render> callback for one reason: a callback receives only the raw
cell value, and a group header row has no C<assigned> value at all. The
row builder knows what kind of row it is; the column does not.

=head2 Right-alignment, and the gutter

C<Selkie::Widget::Table> lays columns out edge to edge with no gap and
pads every cell to the column width, so a number right-aligned into the
B<full> width would touch its neighbour. Each money cell is therefore
right-aligned into C<width - 1> and given a single trailing space,
which is the gutter. C<money-header> pads the column labels the same
way, so the header sits over its own digits instead of over the column
to its left.

A figure too wide for the column is re-rendered without thousands
separators before giving up — C<Table> truncates from the right, which
on money would silently drop the pence.

=head2 The Target column

Rightmost, and B<blank> for an envelope with no target. Zero is the
"no target" sentinel (see L<App::Moneymoor::Model::Category>), and a
column full of C<£0.00> would say that every envelope wants nothing —
a different and much louder claim than "these have not been given
targets". A group header shows the sum of its children's figures, on
the same rule as its available total: exactly the rows underneath it,
blank when they add to nothing.

What the figure B<is> depends on the target's kind, and the column
asks C<App::Moneymoor::Service::Target> rather than reading
C<target-pence>: C<refill> and C<set_aside> show their own amount,
because that is their per-period figure, while C<by_period> shows the
B<current milestone> — where this period's plan says the envelope
should be, not the £50,000 it is heading for. That is the settled
ruling and it is what makes the column addable: a group holding one
goal envelope would otherwise show a header total dwarfed by a number
nobody is being asked for this period. The rail carries the end goal
and the schedule; the grid carries what the plan wants by now.

Because a milestone moves with the period and with the money, the
column needs the period scheme and the derived view — which is why
C<budget-rows> takes C<:$scheme> as well as C<:$view>. C<target-figure>
is the one place that decision is made, and the header sum is a sum of
exactly it.

There is no colour rule here, and specifically none for underfunded.
C<Table> styles a B<row>, not a cell (C<set-row-style> takes the whole
row hash), so painting an underfunded target amber would paint the
envelope's name, its assigned and its available amber too — saying
"this row is in trouble" about a row that is merely not finished. The
detail rail says it instead, where a line can carry its own severity.

=head2 A group's own C<hidden> flag is ignored

C<category_groups> carries a C<hidden> column and this builder does not
read it. That is deliberate rather than an omission: nothing in the UI
can set it (the group editor offers a name and a sort order), and
honouring it would take every envelope in that group off the screen
along with its balance — money vanishing from a budget screen because
of a flag nobody can see or clear. Hiding is a per-envelope decision,
where the user can always get the row back with C<u>.

=head2 Zero-fill: never iterate C<category-periods>

C<BudgetPeriod.category-periods> omits rows that are entirely zero,
which is right for the derivation (a forty-category budget over five
years would otherwise be mostly noughts) and wrong for a grid, where a
category the user created this morning still has to appear. Every cell
here comes from C<view.category($period, $id)>, which is documented to
answer with a zero-filled row for a category it has never heard of.

=head2 §2, in one table

=begin table
State                              | severity           | Style
-----------------------------------+--------------------+---------------------
group header row                   | header             | fg-bright bold on bg-surface
cash overspend (flag)              | cash-overspend     | fg-red
credit overspend (flag)            | credit-overspend   | fg-amber
payment envelope negative (flag)   | payment-negative   | fg-purple
carried cash negative (flag)       | carried-negative   | fg-purple
hidden envelope                    | hidden             | fg-dim
available > 0                      | positive           | fg-green
available == 0                     | zero               | fg-dim
Ready to Assign > 0                | rta-positive       | fg-green bold
Ready to Assign < 0                | rta-negative       | fg-red bold
Ready to Assign == 0               | rta-zero           | fg-dim
anything else                      | normal             | fg-base
=end table

Three ways to be in the red, three colours, and none of it is a taste
call — each says what the period boundary is about to do with the hole:

=item B<Red> (C<cash-overspend>) — it resets to zero and drags every
      future period's Ready to Assign down with it. Money you spent
      that you did not have.
=item B<Amber> (C<credit-overspend>) — written off against the card's
      payment envelope and left where it happened. Debt on a card, not
      a hole in the budget.
=item B<Purple> (C<payment-negative>, C<carried-negative>) — it carries
      forward intact and nothing is charged to Ready to Assign. Two
      severities rather than one because the states read differently —
      a card you are behind on, versus an envelope you told the engine
      it may run negative — even though the arithmetic and the hue are
      identical. Wording is the rail's job; having the key to word it
      with is this table's.

Precedence follows that table top-down: a hidden envelope that is also
cash-overspent renders red, because the money problem outranks the
filing status. Two pairs in it cannot co-occur at all — the derivation
never charges cash overspending to an envelope that carries its
negative, so C<cash-overspend> meets neither C<payment-negative> nor
C<carried-negative> — and no row is ever both of the purple two, since
one is a payment envelope's flag and the other is only set on rows that
are not. So the only ordering that really bites is credit-overspend
before the purple pair, which is the order §2 lists them in.

=head1 EXPORTS

=item C<budget-rows(:@groups!, :@categories!, :$view!, :$scheme!,
      :$period!, :%collapsed, :$show-hidden, :$icons --> List)>
=item C<rta-summary($view, Str $period, :$icons --> Hash)>
=item C<envelope-options(:@categories!, :@groups!, :$exclude-id,
      :$include-hidden --> List)> — C<< label => id >> pairs for the
      move-money and category-editor pickers.
=item C<severity-for($cm, Bool :$hidden --> Str)>
=item C<severity-style(Str $severity, :$theme! --> Selkie::Style)>
=item C<money-cell(Int $pence, Int $width --> Str)> /
      C<money-header(Str $label, Int $width --> Str)>
=item C<target-cell(Int $pence, Int $width = TARGET-COLS --> Str)> /
      C<blank-cell(Int $width --> Str)>
=item C<target-figure($view, $scheme, $category, Str $period --> Int)>
      — the pence the Target column shows for one envelope: its amount,
      or its current milestone. 0 for no target.
=item C<group-label(Str $name, Bool :$collapsed, :$icons --> Str)>
=item C<ASSIGNED-COLS> / C<ACTIVITY-COLS> / C<AVAILABLE-COLS> /
      C<TARGET-COLS> / C<UNGROUPED-ID> / C<UNGROUPED-NAME>

=head1 SEE ALSO

=item L<App::Moneymoor::Screen::Budget> — the widget layer that
      consumes all of this.
=item L<App::Moneymoor::View::InspectorPane> — the detail rail, which
      shares C<severity-for> and C<severity-style>.
=item L<App::Moneymoor::Service::Budget> — C<BudgetView>,
      C<CategoryPeriod> and what the flags mean.
=item L<App::Moneymoor::Service::Target> — what a target asks for, and
      what its milestone is.

=end pod

unit module App::Moneymoor::View::BudgetRow;

use Selkie::Style;

use App::Moneymoor::Service::Budget;
use App::Moneymoor::Service::Icons;
use App::Moneymoor::Service::Target;
use App::Moneymoor::Theme;
use App::Moneymoor::Util::Money;
use App::Moneymoor::Util::Period;

#| Column widths, in cells. The category column is flex and so has no
#| constant; these three are what C<Screen::Budget> passes to
#| C<Table.add-column> and what the cell renderers align into, so they
#| are exported rather than duplicated.
our constant ASSIGNED-COLS  is export = 11;
our constant ACTIVITY-COLS  is export = 11;
our constant AVAILABLE-COLS is export = 12;
our constant TARGET-COLS    is export = 11;

#|( The synthetic group id for the "no group" bucket. Zero is safe as a
    sentinel because SQLite's C<INTEGER PRIMARY KEY> hands out ids from
    1, so it can never collide with a real group — and using a real id
    means the bucket collapses, sorts and styles through exactly the
    same code as every other group instead of being a special case. )
our constant UNGROUPED-ID   is export = 0;
our constant UNGROUPED-NAME is export = 'Ungrouped';

# Two spaces in front of a category name, so the eye can find the
# group headers by their left edge alone when scrolling fast.
my constant NAME-INDENT = '  ';

# What a hidden envelope's name carries so the row is legible as
# retired even in a screenshot, where the dim grey may not survive.
my constant HIDDEN-SUFFIX = ' (hidden)';

#|( Right-align C<$pence> into C<$width> cells, keeping the last cell
    empty as a gutter between this column and the next.

        money-cell(41250, 12);    # '    £412.50 '
        money-cell(-750, 11);     #  '    -£7.50 '

    A figure that will not fit is retried without thousands separators
    — C<Table> truncates cells from the right, and losing the pence off
    a balance is worse than losing the commas. )
sub money-cell(Int:D $pence, Int:D $width --> Str) is export {
    my Int $inner = ($width - 1) max 1;
    my Str $text = format-pence($pence);
    $text = format-pence($pence, :!separators) if $text.chars > $inner;
    sprintf('%' ~ $inner ~ 's ', $text);
}

#|( An empty cell of C<$width>, for the column a row has nothing to say
    in — the Target column of an envelope with no target, and of a
    group whose children have none between them.

    Spaces rather than C<''>: C<Table> pads a short cell on the
    B<left>, which is right for the money that is usually in this
    column and would make an empty string indistinguishable from one.
    Explicit blanks keep the row's cells the same shape whatever is in
    them. )
sub blank-cell(Int:D $width --> Str) is export { ' ' x ($width max 1) }

#|( A target cell: the figure, or blank when there is no target.

    Zero is the "no target" sentinel (see
    L<App::Moneymoor::Model::Category>), and C<£0.00> in a column of
    targets reads as "this envelope wants nothing", which is a
    different claim from "this envelope has not been given a target". )
sub target-cell(Int:D $pence, Int:D $width = TARGET-COLS --> Str) is export {
    $pence > 0 ?? money-cell($pence, $width) !! blank-cell($width);
}

#|( The pence the Target column shows for one envelope — see "The
    Target column".

    C<refill> and C<set_aside> answer with their own amount and need
    nothing else, which is why they are answered B<before> the view is
    consulted: their figure is a property of the row, and a grid drawn
    in the frames before the first recompute should still show it.
    C<by_period> is a milestone and genuinely cannot be placed without
    a view and a scheme, so it answers 0 — a blank cell for one frame
    rather than a number that is not the plan's. )
sub target-figure($view, $scheme, $category, Str:D $period --> Int)
        is export {
    return 0 without $category;
    my Int $pence = ($category.target-pence // 0).Int;
    return 0 unless $pence > 0;
    return $pence unless $category.is-by-period;
    return 0 unless $view.defined && $scheme.defined && $category.id.defined;
    target-milestone($view, $scheme, $category, $period);
}

#| A column label padded the same way C<money-cell> pads its digits, so
#| the header sits over its own column rather than over the one to its
#| left (C<Table> renders header labels left-aligned).
sub money-header(Str:D $label, Int:D $width --> Str) is export {
    my Int $inner = ($width - 1) max 1;
    sprintf('%' ~ $inner ~ 's ', $label);
}

#| A group header's name cell: the collapse chevron for its state, a
#| space, and the group's name.
sub group-label(Str:D $name, Bool :$collapsed = False,
                :$icons = icons() --> Str) is export {
    ($collapsed ?? $icons.group-collapsed !! $icons.group-expanded)
        ~ ' ' ~ $name;
}

#|( The §2 state key for one category-period. See the DESCRIPTION for
    the precedence and why it is that way round.

    C<$cm> is a C<Service::Budget::CategoryPeriod> — including the
    zero-filled one C<BudgetView.category> hands back for a category
    that has nothing this period, which lands on C<zero>. )
sub severity-for($cm, Bool :$hidden = False --> Str) is export {
    return $hidden ?? 'hidden' !! 'normal' without $cm;
    return 'cash-overspend'   if $cm.has-flag('cash-overspend');
    return 'credit-overspend' if $cm.has-flag('credit-overspend');
    return 'payment-negative' if $cm.has-flag('payment-negative');
    return 'carried-negative' if $cm.has-flag('carried-negative');
    return 'hidden'           if $hidden;
    # A negative balance with none of the three flags set is not
    # something the derivation produces, but a defensive `zero` here
    # would paint a real overdraft in "nothing to see" grey.
    return 'cash-overspend'   if $cm.available < 0;
    $cm.available > 0 ?? 'positive' !! 'zero';
}

#|( Turn a severity key into the C<Selkie::Style> §2 calls for. The one
    place the colour decisions live: the table's C<row-style>, the
    inspector rail and the RTA pill all resolve through here, so a
    palette change can never leave two of them disagreeing.

    Three keys never reach a grid row and exist for the rail alone:
    C<rule> (the horizontal line under the equation), C<label> (a
    caption) and C<target-unfunded> (the "To fund" line). The last is
    amber, sharing C<credit-overspend>'s hue on purpose: both mean
    "attend to this", neither means "you have lost money", and red is
    reserved for the one that does. )
sub severity-style(Str $severity, App::Moneymoor::Theme :$theme!
                   --> Selkie::Style) is export {
    given ($severity // 'normal') {
        when 'header' {
            Selkie::Style.new(fg => $theme.fg-bright, bg => $theme.bg-surface,
                              bold => True);
        }
        when 'cash-overspend'   { Selkie::Style.new(fg => $theme.fg-red)    }
        when 'credit-overspend' { Selkie::Style.new(fg => $theme.fg-amber)  }
        # One hue, two keys: both mean "this carries forward and drags
        # nothing behind it", and they are told apart in words rather
        # than in colour — see §2, in one table.
        when 'payment-negative' | 'carried-negative' {
            Selkie::Style.new(fg => $theme.fg-purple);
        }
        when 'positive'         { Selkie::Style.new(fg => $theme.fg-green)  }
        when 'hidden' | 'zero'  { Selkie::Style.new(fg => $theme.fg-dim)    }
        when 'rta-positive' {
            Selkie::Style.new(fg => $theme.fg-green, bold => True);
        }
        when 'rta-negative' {
            Selkie::Style.new(fg => $theme.fg-red, bold => True);
        }
        when 'rta-zero'  { Selkie::Style.new(fg => $theme.fg-dim)    }
        when 'rule'      { Selkie::Style.new(fg => $theme.fg-dimmer) }
        when 'label'     { Selkie::Style.new(fg => $theme.fg-dim)    }
        when 'target-unfunded' { Selkie::Style.new(fg => $theme.fg-amber) }
        default          { Selkie::Style.new(fg => $theme.fg-base)   }
    }
}

#| Groups in display order, C<(sort_order, id)> — the same order the
#| gateway's C<ORDER BY> uses, restated because the rows are assembled
#| from two queries and a synthetic bucket.
sub ordered-groups(@groups --> List) {
    @groups.sort({ ($_.sort-order // 0, $_.id // 0) }).List;
}

sub ordered-categories(@categories --> List) {
    @categories.sort({ ($_.sort-order // 0, $_.id // 0) }).List;
}

#|( The category rows of the grid, in display order, grouped and
    collapsed as the store says.

    C<:@categories> should be the full C<find-all(:include-hidden)>
    list: hiding is a display decision this function makes (via
    C<:$show-hidden>), not one the caller should have pre-applied, or a
    C<u> keypress would need a different query rather than a rebuild.

    The Ready-to-Assign row is dropped unconditionally — it is not an
    envelope, it has no balance of its own, and its number is the pill
    above the table.

    A collapsed group keeps its header row (with its total) and loses
    its categories. An empty group keeps its header too — it is the
    only way to see that it exists, and the only row C<e> can edit it
    from — B<unless> it is a system group, which is only shown once
    something is filed under it (see the comment on C<@buckets>). )
sub budget-rows(
    :@groups!,
    :@categories!,
    :$view!,
    App::Moneymoor::Util::Period :$scheme!,
    Str:D :$period!,
    :%collapsed = %(),
    Bool :$show-hidden = False,
    :$icons = icons(),
    --> List
) is export {
    my @envelopes = @categories.grep({ .defined && !.is-rta });
    @envelopes = @envelopes.grep({ !.hidden }) unless $show-hidden;

    my %by-group;
    for @envelopes -> $c {
        %by-group{ ($c.group-id // UNGROUPED-ID).Str }.push($c);
    }

    # An empty group keeps its header: it is the only way to see that
    # it exists, and the only row `e` can edit it from. An empty
    # B<system> group does not — "Credit Card Payments" is seeded by
    # the migrations whether or not the user owns a credit card, and a
    # permanent empty section on a cash-only budget is furniture for a
    # feature that is not in use.
    my @buckets = ordered-groups(@groups).grep({
        !$_.is-system || (%by-group{ ($_.id // UNGROUPED-ID).Str } // []).elems
    }).map({
        %( id => ($_.id // UNGROUPED-ID), name => $_.name )
    }).Array;
    # The ungrouped bucket sits last, and only exists when something is
    # in it — an empty "Ungrouped" header would be a permanent line of
    # furniture on a tidy budget.
    @buckets.push(%( id => UNGROUPED-ID, name => UNGROUPED-NAME ))
        if (%by-group{UNGROUPED-ID.Str} // []).elems;

    my @rows;
    for @buckets -> %bucket {
        my Int $gid = %bucket<id>.Int;
        my @members = ordered-categories(%by-group{$gid.Str} // []);
        my Bool $is-collapsed = ?%collapsed{$gid.Str};

        # The header's total covers exactly the rows underneath it —
        # the post-`show-hidden` set — so the column adds up on screen.
        # Collapsing does not change it: a folded group still owns its
        # money.
        my Int $total = @members.map({
            category-period($view, $period, $_.id).available
        }).sum.Int;
        # Same rule as the available total: exactly the rows underneath
        # this header. A group nobody has given a target gets a blank
        # cell rather than £0.00 — see `target-cell`. It sums the
        # members' FIGURES and not their amounts, so a group holding a
        # £50,000 goal shows what that goal wants by now rather than a
        # header total nobody is being asked for.
        my Int $target-total = @members.map({
            target-figure($view, $scheme, $_, $period)
        }).sum.Int;

        @rows.push: %(
            kind      => 'group',
            id        => $gid,
            group-id  => $gid,
            hidden    => False,
            severity  => 'header',
            category  => group-label(%bucket<name>,
                                     collapsed => $is-collapsed, :$icons),
            assigned  => '',
            activity  => '',
            available => money-cell($total, AVAILABLE-COLS),
            target    => target-cell($target-total),
        );

        next if $is-collapsed;

        for @members -> $c {
            my $cm = category-period($view, $period, $c.id);
            my Bool $hidden = ?$c.hidden;
            @rows.push: %(
                kind      => 'category',
                id        => ($c.id // 0).Int,
                group-id  => $gid,
                :$hidden,
                severity  => severity-for($cm, :$hidden),
                category  => NAME-INDENT ~ $c.name
                             ~ ($hidden ?? HIDDEN-SUFFIX !! ''),
                assigned  => money-cell($cm.assigned,  ASSIGNED-COLS),
                activity  => money-cell($cm.activity,  ACTIVITY-COLS),
                available => money-cell($cm.available, AVAILABLE-COLS),
                target    => target-cell(
                    target-figure($view, $scheme, $c, $period)),
            );
        }
    }
    @rows.List;
}

#|( One category's period, zero-filled, and tolerant of a view that has
    not been computed yet — the handful of frames between building the
    screen and the first recompute, where every row is legitimately
    empty. )
sub category-period($view, Str:D $period, $id) {
    return App::Moneymoor::Service::Budget::CategoryPeriod.new(
        period => $period, category-id => ($id // 0).Int,
    ) unless $view.defined && $id.defined;
    $view.category($period, $id.Int);
}

#|( The Ready-to-Assign pill above the table, as text plus a severity
    key, plus the future-assignment note that hangs off its right-hand
    end.

    Zero is not "£0.00" here. A budget whose every penny has a job is
    the goal state, and saying so in words — "All money assigned ✓" —
    is the difference between a screen that reports and a screen that
    congratulates. )
sub rta-summary($view, Str:D $period, :$icons = icons() --> Hash) is export {
    my Int $rta = $view.defined ?? $view.rta($period).Int !! 0;
    my $bp = $view.defined ?? $view.period($period) !! Nil;
    my Int $future = $bp.defined ?? $bp.assigned-future.Int !! 0;

    my ($text, $severity) = do given $rta {
        when * > 0 {
            ('Ready to Assign  ' ~ format-pence($rta), 'rta-positive');
        }
        when * < 0 {
            ($icons.warn ~ ' Ready to Assign  ' ~ format-pence($rta),
             'rta-negative');
        }
        default { ('All money assigned ✓', 'rta-zero') }
    };

    %(
        :$text, :$severity, :$rta, :$future,
        note => ($future == 0
            ?? ''
            !! format-pence($future) ~ ' assigned in future periods'),
    );
}

#|( Every envelope a picker may offer, as C<< label => id >> pairs in
    the grid's own order.

    Payment envelopes are B<in>: funding next period's card payment out
    of this period's Groceries is an ordinary thing to do, and the
    engine has no objection. Ready to Assign is B<out>: it is the pool
    assignments come from, and C<Gateway::Assignment> refuses it on
    both sides of a move.

    Labels are C<'<Group> · <Category>'> so two envelopes called
    "Insurance" in different groups are tellable apart; the ungrouped
    ones carry their bare name, because "Ungrouped · Petrol" reads as a
    group that does not exist. )
sub envelope-options(
    :@categories!,
    :@groups!,
    Int :$exclude-id,
    Bool :$include-hidden = False,
    --> List
) is export {
    my %group-name = ordered-groups(@groups)
        .map({ ($_.id // UNGROUPED-ID).Str => $_.name }).Hash;

    my @envelopes = @categories.grep({ .defined && .is-envelope });
    @envelopes = @envelopes.grep({ !.hidden }) unless $include-hidden;
    @envelopes = @envelopes.grep({ ($_.id // -1) != $exclude-id })
        if $exclude-id.defined;

    my %by-group;
    for @envelopes -> $c {
        %by-group{ ($c.group-id // UNGROUPED-ID).Str }.push($c);
    }

    my @order = ordered-groups(@groups).map({ ($_.id // UNGROUPED-ID).Int });
    @order.push(UNGROUPED-ID) if (%by-group{UNGROUPED-ID.Str} // []).elems;

    my @out;
    for @order -> $gid {
        my Str $prefix = $gid == UNGROUPED-ID
            ?? '' !! (%group-name{$gid.Str} // '') ~ ' · ';
        for ordered-categories(%by-group{$gid.Str} // []) -> $c {
            @out.push($prefix ~ $c.name => ($c.id // 0).Int);
        }
    }
    @out.List;
}
