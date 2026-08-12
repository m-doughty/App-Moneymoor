=begin pod

=head1 NAME

App::Moneymoor::View::ReportRow - the reports tab's numbers: what was
spent on what, and the period's cash flow.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::View::ReportRow;

# What the period was spent on, biggest first.
my @rows = spending-rows(
    categories => $main.categories,
    groups     => $main.groups,
    view       => $main.view,
    period     => '2026-03-01',
);
@rows[0];        # { kind => 'category', id => 4, name => 'Groceries',
                 #   pence => 41250 }

# The same, aggregated up to the groups.
my @by-group = spending-rows(:@categories, :@groups, :$view,
                             period => '2026-03-01', :by-group);

# Only as many bars as the chart has rows for, and a caption for the
# ones that did not fit.
my %cut = top-spending(@rows, 5);
%cut<rows>.elems;                  # 5
more-label(%cut<hidden>);          # '+3 more…'

# Bars, ready for Selkie::Widget::BarChart in horizontal mode.
report-bars(%cut<rows>).head;      # { label => '£412.50  Groceries',
                                   #   value => 412.5 }

# The strip above the chart.
my %sum = report-summary(
    transactions  => $ws.transactions.find-by-period('2026-03-01'),
    accounts      => %accounts-by-id,
    peer-accounts => %account-id-by-txn-id,
    view          => $main.view,
    period        => '2026-03-01',
    spending      => @rows,
);
%sum<text>;
# 'Inflow £2,000.00 · Outflow £412.50 · Net £1,587.50   Assigned …'

# How deep a box that strip needs, given the content width it is
# going into: frame plus one line, or frame plus two if it wraps.
summary-rows-needed(summary-line(%sum), 96);   # 3
summary-rows-needed(summary-line(%sum), 40);   # 4

=end code

=head1 DESCRIPTION

Pure functions: models, lookup hashes and a C<BudgetView> in, row
hashes and formatted strings out. No widgets, no store, no database —
C<App::Moneymoor::Screen::Reports> is the wiring, and every definition
worth arguing about lives here where it can be argued about in a test.

=head2 Spending is not "negative activity"

An envelope's C<activity> in a period is the sum of the splits filed
against it. Spending is C<-activity> B<when activity is negative>, and
nothing at all otherwise: a period where the only movement on
"Groceries" was a £20 refund did not spend minus twenty pounds on
groceries, and a chart with a bar pointing the wrong way says something
the reader has to stop and decode.

Three kinds of row never appear:

=item B<the C<rta> pseudo-category> — it is not an envelope; money
      passing through it is money arriving, which is the summary
      strip's inflow figure and not a category anybody spent.
=item B<payment envelopes> — a credit-card payment envelope's activity
      is the card's own spending seen a second time, from the other
      side. Counting it would double every card purchase in the chart.
=item B<zero rows> — an envelope with no spending is not a bar of
      length zero, it is an absence, and the derivation is full of them
      (every envelope exists in every period).

C<:by-group> sums the same per-category figures into their groups; a
category with no group lands in the C<UNGROUPED-NAME> bucket, which is
the same bucket the envelope grid puts it in. Aggregating the
B<spending> rather than the activity matters: a group holding one
envelope that spent £40 and another that was refunded £10 spent £40,
not £30. The refund is a fact about that envelope's balance, not about
the group's outgoings.

=head2 Transfers are not cash flow, except when they are

The summary strip's inflow and outflow come from the period's
transactions on B<on-budget> accounts, and the interesting case is the
transfer. Moving £500 from the current account to savings is two legs,
C<-500> and C<+500>, and both accounts are on-budget: counting them
would add £500 to both inflow and outflow while nothing entered or left
the budget. So a transfer leg whose peer is B<also> on-budget is
dropped from both sums.

A transfer to (or from) a B<tracking> account is the opposite case: the
money really did leave the budget, and that leg counts like any other
outflow. So does an ordinary transaction, transfer or not.

A leg whose peer cannot be resolved — the peer index is built from the
same transaction set, so this does not happen in the app — counts. The
alternative is silently dropping real money from the report because a
lookup missed.

=head2 The bars carry their own figures

C<Selkie::Widget::BarChart> renders a label and a bar; it has no
per-bar value annotation, and its value axis is a scale along the top,
not a figure per row. A spending report whose figures are only readable
off a scale is a spending report nobody can quote, so C<report-bars>
puts the money B<in the label>, right-aligned into a column as wide as
the widest figure in the set:

     £412.50  Groceries
      £88.00  Transport
       £4.20  Coffee

Money first because C<BarChart> clips a label that does not fit its
label column from the right — the same call C<View::RegisterRow>'s
C<sidebar-label> makes, for the same reason. A name cut short is still
recognisable; a figure cut short is a different figure.

Values are handed over in B<pounds>, not pence: the axis labels are
generated from the values, and a scale reading "0 20000 40000" is not a
scale about money anybody has.

=head2 The cut, and the caption

Bars do not scroll and they do not compress below one row each, so a
chart with more categories than rows draws some of them on top of the
axis. C<top-spending> takes the biggest C<$limit> and reports how many
it left behind; C<more-label> turns that count into the C<'+3 more…'>
caption the pane puts in its bottom title. Biggest-first is what makes
the cut defensible: the rows that fall off are the ones that matter
least.

=head2 The strip is one line, until it is two

C<Selkie::Widget::RichText> word-wraps, so the summary strip needs a
second content row on a terminal too narrow for its five figures — and
a second content row that nothing wraps into is a blank line inside a
box, which reads as a rendering fault rather than as breathing room.

C<summary-rows-needed> is the whole decision, as a function of the
strip and the width of the box it is going into:

=begin code :lang<raku>

my Str $line = summary-line(%sum);          # 74 characters
summary-rows-needed($line, 96);             # 3 — frame plus one line
summary-rows-needed($line, 60);             # 4 — frame plus two
summary-rows-needed($line, 0);              # 4 — nothing measured yet

=end code

C<SUMMARY-ROWS> (4) is the ceiling as well as the fallback: the pane
never grows a third content row, because the chart underneath is what
the tab is for. A strip that would wrap twice is cut instead, and
C<Screen::Reports> is the caller that owns applying the answer.

=head1 EXPORTS

=item C<spending-rows(:@categories!, :@groups, :$view!, :$period!,
      :$by-group --> List)> — C<< { kind, id, name, pence } >>,
      descending.
=item C<spending-total(@rows --> Int)>
=item C<top-spending(@rows, Int $limit --> Hash)> —
      C<< { rows, hidden } >>.
=item C<more-label(Int $hidden --> Str)>
=item C<report-bars(@rows --> List)> — C<< { label, value } >> for
      C<Selkie::Widget::BarChart>.
=item C<cash-flow(:@transactions!, :%accounts!, :%peer-accounts
      --> Hash)> — C<< { inflow, outflow, net } >> in pence.
=item C<assigned-total($view, Str $period --> Int)>
=item C<report-summary(...)> — every figure plus C<segments> and
      C<text>.
=item C<summary-segments(%figures --> List)> /
      C<summary-line(%figures --> Str)> /
      C<summary-spans(%figures, :$theme! --> List)>
=item C<summary-rows-needed(Str $line, Int $inner-width --> Int)> —
      C<SUMMARY-ROWS-MIN> or C<SUMMARY-ROWS>.
=item C<chart-title(Bool $by-group --> Str)> /
      C<summary-title(Str $period-label --> Str)>
=item C<CHART-AXIS-ROWS> / C<CHART-FALLBACK-ROWS> / C<SUMMARY-ROWS> /
      C<SUMMARY-ROWS-MIN>

=head1 SEE ALSO

=item L<App::Moneymoor::Screen::Reports> — the widget layer.
=item L<App::Moneymoor::View::BudgetRow> — C<UNGROUPED-NAME> and the
      §2 severity palette these share.
=item L<App::Moneymoor::Service::Budget> — C<BudgetPeriod.assigned-total>
      and the C<activity> figure spending is derived from.

=end pod

unit module App::Moneymoor::View::ReportRow;

use Selkie::Style;
use Selkie::Widget::RichText::Span;

use App::Moneymoor::Theme;
use App::Moneymoor::Util::Money;
use App::Moneymoor::View::BudgetRow;

#|( Rows the chart loses to its own axis. C<BarChart> in horizontal
    mode spends the top row on the value scale, so a pane C<n> rows
    tall fits C<n - 1> bars. )
our constant CHART-AXIS-ROWS is export = 1;

#|( How many bars to assume before the chart has been laid out. A
    widget with no plane reports zero rows, and cutting to zero bars
    would paint an empty chart on the first frame of every visit to the
    tab. Twelve is a full-screen terminal's worth; the first real
    layout corrects it. )
our constant CHART-FALLBACK-ROWS is export = 12;

#|( Tallest the summary pane ever gets, frame included: two rows of
    chrome and two of content, which is what a strip that has wrapped
    once needs.

    Also the height the pane is built with and the answer
    C<summary-rows-needed> gives when it has no width to measure
    against — an unlaid-out pane guessing short would cut the strip on
    the first frame of every visit, and guessing tall only costs a
    blank line until the first measurement lands. )
our constant SUMMARY-ROWS is export = 4;

#| Height of the summary pane when the strip fits on one line: two
#| rows of chrome and one of content. The ordinary case on any
#| terminal wide enough for §4.6's five figures.
our constant SUMMARY-ROWS-MIN is export = 3;

# Gap between the money column and the name in a bar label, and
# between the two halves of the summary strip. Two spaces rather than
# one: a single space next to a right-aligned figure reads as part of
# the number.
my constant LABEL-GAP   = '  ';
my constant SUMMARY-GAP = '   ';

#|( One envelope's spending in a period: C<-activity> when the activity
    is negative, and zero otherwise. See "Spending is not negative
    activity".

    Tolerates a view that has not been computed yet — the frames
    between building the tab and the first recompute, where every
    figure is legitimately zero. )
sub category-spend($view, Str:D $period, $id --> Int) is export {
    return 0 unless $view.defined && $id.defined;
    my $cm = $view.category($period, $id.Int);
    return 0 without $cm;
    my Int $activity = ($cm.activity // 0).Int;
    $activity < 0 ?? -$activity !! 0;
}

#| A group's display name, from the id → group map the screen holds.
#| A category filed under no group (or under one that has been
#| deleted) lands in the same C<Ungrouped> bucket the envelope grid
#| gives it.
sub group-name(%groups, $id --> Str) {
    return UNGROUPED-NAME without $id;
    my $g = %groups{$id};
    ($g.defined && $g.can('name')) ?? $g.name !! UNGROUPED-NAME;
}

#|( What C<$period> was spent on, biggest first.

    Standard envelopes only — see the Pod for why C<rta> and payment
    envelopes are not spending — with the zero rows dropped, because
    an envelope that saw no money is an absence rather than a bar of
    length zero.

    C<:by-group> sums the per-category figures into their groups.
    Ties break on the name, so two envelopes that spent the same
    amount come out in a stable order rather than whichever one the
    lookup hash happened to yield first. )
sub spending-rows(
    :@categories!,
    :@groups = (),
    :$view!,
    Str:D :$period!,
    Bool :$by-group = False,
    --> List
) is export {
    my @envelopes = @categories.grep({ .defined && .is-standard });

    my @rows;
    if $by-group {
        my %groups-by-id = @groups.grep(*.defined).map({ .id => $_ }).Hash;
        my %total;
        my %name;
        for @envelopes -> $c {
            my Int $spend = category-spend($view, $period, $c.id);
            next unless $spend > 0;
            my Int $gid = ($c.group-id // UNGROUPED-ID).Int;
            %total{$gid.Str} += $spend;
            %name{$gid.Str} //= group-name(%groups-by-id, $c.group-id);
        }
        @rows = %total.keys.map(-> Str $key {
            %( kind  => 'group',
               id    => $key.Int,
               name  => %name{$key},
               pence => %total{$key}.Int )
        }).Array;
    } else {
        for @envelopes -> $c {
            my Int $spend = category-spend($view, $period, $c.id);
            next unless $spend > 0;
            @rows.push: %( kind  => 'category',
                           id    => ($c.id // 0).Int,
                           name  => ($c.name // '').Str,
                           pence => $spend );
        }
    }

    @rows.sort({ (-$_<pence>, $_<name>) }).List;
}

#| Everything the chart is showing, added up — the summary strip's
#| C<Spent> figure. Taken from the rows rather than re-derived, so the
#| number under the chart is the sum of the chart.
sub spending-total(@rows --> Int) is export {
    ([+] @rows.map({ ($_<pence> // 0).Int })) // 0;
}

#|( The biggest C<$limit> rows, and how many were left behind.

    A limit of zero or less keeps nothing and reports every row as
    hidden: a pane too short for one bar still has a bottom title to
    say what it is not showing. )
sub top-spending(@rows, Int:D $limit --> Hash) is export {
    my Int $keep = $limit > 0 ?? $limit !! 0;
    return %( rows => @rows.List, hidden => 0 ) if @rows.elems <= $keep;
    %( rows   => @rows[^$keep].List,
       hidden => (@rows.elems - $keep).Int );
}

#| C<'+3 more…'>, or the empty string when nothing was cut. The pane
#| puts it in its bottom title, where it costs no row.
sub more-label(Int $hidden --> Str) is export {
    my Int $n = ($hidden // 0).Int;
    $n > 0 ?? '+' ~ $n ~ ' more…' !! '';
}

#|( Spending rows as C<Selkie::Widget::BarChart> entries: a label with
    the figure in it and a value in pounds. See "The bars carry their
    own figures". )
sub report-bars(@rows --> List) is export {
    my @money = @rows.map({ format-pence(($_<pence> // 0).Int) });
    # `max` over an empty list is -Inf, not Nil, so `// 0` would not
    # catch it — and a chart with no bars is the ordinary empty period.
    my Int $width = @money.elems ?? @money.map(*.chars).max.Int !! 0;
    @rows.kv.map(-> $i, %row {
        %( label => bar-label((%row<name> // '').Str, @money[$i], $width),
           value => (%row<pence> // 0).Int / 100 )
    }).List;
}

#| One bar's label: the figure right-aligned into C<$width> cells, a
#| gap, then the name.
sub bar-label(Str:D $name, Str:D $money, Int:D $width --> Str) is export {
    (' ' x (($width - $money.chars) max 0)) ~ $money ~ LABEL-GAP ~ $name;
}

#|( The period's cash flow across the B<on-budget> accounts, in pence:
    C<inflow> (positive amounts), C<outflow> (negative amounts, kept
    signed) and C<net>, their sum.

    Internal transfers are excluded from both — see "Transfers are not
    cash flow, except when they are". C<:%peer-accounts> maps a
    transaction id to the account it belongs to, exactly as
    C<View::RegisterRow::register-rows> takes it; only the peers of
    transfer legs are ever looked up in it. )
sub cash-flow(:@transactions!, :%accounts!, :%peer-accounts = %()
              --> Hash) is export {
    my Int $inflow = 0;
    my Int $outflow = 0;

    for @transactions.grep(*.defined) -> $t {
        my $account = %accounts{ $t.account-id };
        next unless $account.defined && $account.is-on-budget;

        if $t.is-transfer {
            my $peer-account-id = %peer-accounts{ $t.transfer-peer-id };
            my $peer = $peer-account-id.defined
                ?? %accounts{$peer-account-id} !! Nil;
            next if $peer.defined && $peer.is-on-budget;
        }

        my Int $amount = ($t.amount // 0).Int;
        if    $amount > 0 { $inflow  += $amount }
        elsif $amount < 0 { $outflow += $amount }
    }

    %( :$inflow, :$outflow, net => $inflow + $outflow );
}

#|( C<BudgetPeriod.assigned-total> for a period, or zero.

    The guard is load-bearing rather than defensive: C<BudgetView.period>
    answers with a type object for a period outside the derived range,
    and an attribute accessor on a type object throws. Navigating back
    before the first fact is an ordinary thing to do. )
sub assigned-total($view, Str:D $period --> Int) is export {
    return 0 without $view;
    my $bp = $view.period($period);
    return 0 without $bp;
    ($bp.assigned-total // 0).Int;
}

#|( Every figure the summary strip shows, plus the strip itself.

    Returns C<< { inflow, outflow, net, assigned, spent, segments,
    text } >>. The parts are separately exported (C<cash-flow>,
    C<assigned-total>, C<spending-total>) so a test can pin one
    definition at a time; this is the one call the screen makes. )
sub report-summary(
    :@transactions = (),
    :%accounts = %(),
    :%peer-accounts = %(),
    :$view,
    Str:D :$period!,
    :@spending = (),
    --> Hash
) is export {
    my %flow = cash-flow(:@transactions, :%accounts, :%peer-accounts);
    my %figures = %(
        inflow   => %flow<inflow>,
        outflow  => %flow<outflow>,
        net      => %flow<net>,
        assigned => assigned-total($view, $period),
        spent    => spending-total(@spending),
    );
    %figures<segments> = summary-segments(%figures);
    %figures<text>     = %figures<segments>.map({ $_<text> }).join;
    %figures;
}

#|( The summary strip as C<< { text, severity } >> segments, separators
    included, so the screen can colour the figures without knowing how
    the line is put together.

    Outflow is printed as a magnitude: the word says which way it went,
    and a minus sign in front of it would read as "outflow was
    negative". Net keeps its sign, because that one really can go
    either way, and takes the §2 colour that says which. )
sub summary-segments(%figures --> List) is export {
    my Int $inflow   = (%figures<inflow>   // 0).Int;
    my Int $outflow  = (%figures<outflow>  // 0).Int;
    my Int $net      = (%figures<net>      // 0).Int;
    my Int $assigned = (%figures<assigned> // 0).Int;
    my Int $spent    = (%figures<spent>    // 0).Int;

    my Str $net-severity = do {
        if    $net > 0 { 'positive'       }
        elsif $net < 0 { 'cash-overspend' }
        else           { 'zero'           }
    };

    (
        %( text => 'Inflow ' ~ format-pence($inflow),
           severity => ($inflow > 0 ?? 'positive' !! 'zero') ),
        %( text => ' · ', severity => 'rule' ),
        %( text => 'Outflow ' ~ format-pence($outflow.abs),
           severity => ($outflow < 0 ?? 'normal' !! 'zero') ),
        %( text => ' · ', severity => 'rule' ),
        %( text => 'Net ' ~ format-pence($net), severity => $net-severity ),
        %( text => SUMMARY-GAP, severity => 'rule' ),
        %( text => 'Assigned ' ~ format-pence($assigned),
           severity => ($assigned == 0 ?? 'zero' !! 'normal') ),
        %( text => ' · ', severity => 'rule' ),
        %( text => 'Spent ' ~ format-pence($spent),
           severity => ($spent == 0 ?? 'zero' !! 'normal') ),
    );
}

#| The strip as one string — what a test asserts on, and what the
#| screen would fall back to if it had no palette.
sub summary-line(%figures --> Str) is export {
    (%figures<segments> // summary-segments(%figures))
        .map({ $_<text> }).join;
}

#|( How tall the summary pane has to be to hold C<$line> in a content
    box C<$inner-width> cells wide: C<SUMMARY-ROWS-MIN> when the strip
    fits on one line, C<SUMMARY-ROWS> when it has to wrap. See "The
    strip is one line, until it is two".

    The comparison is C<.chars> against the width because that is
    exactly what C<RichText>'s word-wrap counts, and because every
    glyph the strip is made of — digits, C<£>, C<·> — is one cell
    wide. A strip one character over its box wraps, and the answer is
    the same four rows whether it spills by one character or forty:
    the pane never grows past the frame plus two lines, so a terminal
    too narrow for two lines of strip shows a cut strip rather than a
    chart squeezed out of existence.

    A width of zero or less is not a narrow pane, it is a pane nobody
    has measured yet — a widget with no plane reports zero columns —
    and answers with the C<SUMMARY-ROWS> maximum. )
sub summary-rows-needed(Str $line, Int $inner-width --> Int) is export {
    my Int $width = ($inner-width // 0).Int;
    return SUMMARY-ROWS unless $width > 0;
    ($line // '').chars <= $width ?? SUMMARY-ROWS-MIN !! SUMMARY-ROWS;
}

#| The strip as C<RichText> spans, coloured through §2's table. No
#| trailing newline: the box holds one line, or two when the strip has
#| wrapped, and a newline would push a wrapped strip out of view.
sub summary-spans(%figures, App::Moneymoor::Theme :$theme! --> List) is export {
    (%figures<segments> // summary-segments(%figures)).map(-> %seg {
        Selkie::Widget::RichText::Span.new(
            text  => (%seg<text> // '').Str,
            style => severity-style((%seg<severity> // 'normal').Str, :$theme),
        )
    }).List;
}

#| The chart pane's frame title, which says which aggregation C<b> has
#| the tab in.
sub chart-title(Bool $by-group --> Str) is export {
    $by-group ?? 'Spending by group' !! 'Spending by category';
}

#| The summary pane's frame title. C<$period-label> is
#| C<App::Moneymoor::Util::Period.label>'s output; an unknown period
#| degrades to the bare word rather than a stray separator.
sub summary-title(Str $period-label --> Str) is export {
    ($period-label // '').chars ?? $period-label ~ ' summary' !! 'Summary';
}
