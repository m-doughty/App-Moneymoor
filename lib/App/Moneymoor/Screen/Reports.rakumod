=begin pod

=head1 NAME

App::Moneymoor::Screen::Reports - the reports tab: the period's
cash-flow strip and the bar chart of what it went on.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Screen::Reports;

# Built by Screen::Main's content-host seam, never directly:
my $tab = App::Moneymoor::Screen::Reports.new(main => $main);
$tab.build($content-host);       # mounts the strip and the chart
$tab.install-subscriptions;      # digest / period / by-group → repaint
$tab.install-keybinds;           # b

$tab.chart.data.head<label>;     # '£412.50  Groceries'
$tab.by-group;                   # False — b flips it
$tab.summary.parent.sizing.value; # 3 — the strip fits on one line

=end code

=head1 DESCRIPTION

    VBox (the content host)
     ├ Border(fixed 3 or 4, 'March 2026 summary') → RichText strip
     └ Border(flex, 'Spending by category',
              bottom '+3 more…')                  → BarChart (horizontal)

Every number on screen comes out of C<View::ReportRow>; this file is
the wiring. The tab is period-scoped and shares the budget tab's C<[> /
C<]> navigation — the period lives in C<app/period>, so switching tabs
keeps the user where they were.

=head2 One pane takes focus, and it is the chart

C<mount-pane> registers a pane's hint context and makes the first one
mounted the tab's focus target. The summary strip is a caption for the
chart, not a thing to drive, so it is added to the host directly (with
its store pushed down by hand — a fixed-size child does not get
C<set-store> cascaded) and only the chart is mounted. That makes the
chart the tab's focus target, the C<reports> hint context's pane, and
the widget C<b> is bound on.

The chart is constructed C<focusable> for exactly that reason. A
C<BarChart> has nothing to do with a keystroke of its own, but a pane
that cannot take focus leaves the hint footer resolving to C<generic>
and the tab's one keybind unreachable.

=head2 The cut is a function of the pane's height

Horizontal bars do not scroll and do not compress below one row each,
so a chart with more categories than rows draws the overflow on top of
its own axis. The tab therefore asks C<View::ReportRow::top-spending>
for as many bars as it has rows for (less the one the value axis
takes), and puts C<'+3 more…'> in the pane's B<bottom title> — where
it costs no row, which is the whole problem being solved.

The height is read at every repaint rather than cached, and
C<handle-resize> re-runs the cut when a resize changes how many bars
fit. C<Screen::Main> owns the app's single C<App.on-resize> callback
and fans it out here (resize callbacks accumulate with no way to
remove them, so a per-tab registration would leak one per visit).

=head2 The strip's box is as deep as the strip

The summary pane is B<three> rows on any terminal wide enough for
§4.6's five figures — frame, one line, frame — and four only when the
strip has to wrap. A fourth row held in reserve for a wrap that never
happens is a blank line inside a box, which reads as a bug rather than
as spacing, and it is a row taken off the chart.

C<View::ReportRow::summary-rows-needed> owns the rule and
C<!fit-summary-height> applies it, from both of the places the answer
can change: the strip's own repaint (a period whose totals gained a
digit) and a resize (the same strip in a narrower box). Applying it is
C<Selkie::Widget::MultiLineInput>'s re-measure idiom — C<set-sizing>
followed by a dirty mark, because the parent layout re-reads a child's
sizing on its next render and never on its own — with
C<Widget.mark-screen-dirty> as the mark, since the row that moves here
is a row the chart below gains or loses.

The height is only touched when it actually changes;
C<$!summary-rows-painted> is to the strip what C<$!limit-painted> is
to the chart.

=head2 Why the digest is enough here

The register keys on C<ws/rev> because neither change token can see a
memo or a cleared state. Reports has the opposite problem and the
opposite answer: every figure on this tab — spending, inflow, outflow,
assigned — moves the derivation, so C<budget/digest> covers all of
them, and a payee rename that leaves the derivation identical genuinely
changes nothing here.

=head1 METHODS

=item C<build($host)> — construct and mount.
=item C<install-subscriptions()> / C<install-keybinds()> — the two
      seams C<Screen::Main::Subscriptions::install-content> and
      C<Screen::Main::Keybinds::install-content> call.
=item C<refresh()> — repaint both panes; the subscription callback.
=item C<refresh-summary()> / C<refresh-chart()> — one pane each, and
      the two subscription callbacks. C<refresh-summary> also fits the
      strip's box to the strip.
=item C<handle-resize(Int $rows, Int $cols)> — re-fit the strip's box
      and re-cut the bars.
=item C<chart>, C<summary>, C<by-group>, C<rows>, C<hidden-count>.

=head1 SEE ALSO

=item L<App::Moneymoor::View::ReportRow> — every figure and every label.
=item L<App::Moneymoor::StoreHandlers> — C<reports/toggle-by-group>.
=item L<Selkie::Widget::BarChart> — the chart, in horizontal mode.

=end pod

unit class App::Moneymoor::Screen::Reports;

use Selkie::BorderStyle;
use Selkie::Sizing;
use Selkie::Widget::BarChart;
use Selkie::Widget::Border;
use Selkie::Widget::RichText;

use App::Moneymoor::View::EmptyState;
use App::Moneymoor::View::ReportRow;

#| The C<Screen::Main> that owns the caches, the store and the palette.
#| Untyped so this class does not have to C<use> the screen that
#| C<use>s it.
has $.main is required;

has Selkie::Widget::Border $!summary-border;
has Selkie::Widget::RichText $.summary;
has Selkie::Widget::Border $!chart-border;
has Selkie::Widget::BarChart $.chart;

#| The spending rows behind the bars, before the height cut — what the
#| C<Spent> figure is summed from, and what the tests read.
has @.rows;

#| How many rows the last repaint left off the chart.
has Int $.hidden-count = 0;

#| The bar count the chart was last built for, compared on resize so a
#| height change that does not move the cut costs nothing.
has Int $!limit-painted = -1;

#|( The summary pane's height as it currently stands, compared before
    anything is resized so a repaint that does not move the wrap costs
    no reflow. Starts at the height C<build> constructs the pane with,
    because that is what the layout has been told. )
has Int $!summary-rows-painted = SUMMARY-ROWS;

method build($host --> Nil) {
    my $main  = $!main;
    my $store = $main.store;

    # --- The summary strip -------------------------------------------
    #
    # Padding on the sides only: the pane is three rows once it has
    # been measured — frame plus the one line the strip fits on — and a
    # cell of vertical padding would leave it none. It is built at
    # SUMMARY-ROWS, the height a wrapped strip needs, because nothing
    # has been laid out yet at this point and a pane that guesses short
    # cuts the strip on the frame it is mounted; `!fit-summary-height`
    # takes the spare row back as soon as there is a width to measure.
    $!summary-border = Selkie::Widget::Border.new(
        sizing        => Sizing.fixed(SUMMARY-ROWS),
        border-style  => BorderRounded,
        title         => summary-title(''),
        padding-left  => 1,
        padding-right => 1,
    );
    $!summary = Selkie::Widget::RichText.new(sizing => Sizing.flex);
    $!summary-border.set-content($!summary);
    $host.add($!summary-border);
    # A fixed-height child does not get set-store cascaded to it, and a
    # Border that never sees the store never gets its focus highlight.
    $!summary-border.set-store($store);

    # --- The chart ----------------------------------------------------
    $!chart = Selkie::Widget::BarChart.new(
        sizing        => Sizing.flex,
        orientation   => 'horizontal',
        # Focusable so the hint footer can resolve this pane's context
        # and so `b` has somewhere to live — see the Pod.
        focusable     => True,
        # The chart's own empty rendering, in the app's own words.
        empty-message => (empty-state-for('reports',
                                          icons => $main.icons).head // ''),
    );
    $!chart-border = $main.pane-border(chart-title(False), Sizing.flex);
    $!chart-border.set-bottom-title-align(TitleRight);
    $main.mount-pane($host, $!chart-border, $!chart, 'reports');
    Nil
}

#|( The tab's store wiring. Two channels — the strip and the chart —
    keyed on the derivation digest, the viewed period, and (for the
    chart) which way C<b> has the aggregation.

    Both selectors return one flat C<Str>: the store compares
    subscription values by content digest and keys objects by identity,
    so a selector handing back anything richer would read as changed on
    every tick.

    Both are anchored on the chart. It is the pane C<mount-pane> pushed
    the store into, and the two panes are built and destroyed together,
    so there is nothing to be gained by anchoring the strip's channel
    on the strip. )
method install-subscriptions(--> Nil) {
    my $self-ref = self;
    my $store    = $!main.store;

    $store.subscribe-with-callback(
        'reports-summary',
        -> $s {
            join("\x[1F]",
                ($s.get-in('budget', 'digest') // '').Str,
                ($s.get-in('app',    'period') // '').Str,
            );
        },
        -> Str $ { $self-ref.refresh-summary },
        $!chart,
    );

    $store.subscribe-with-callback(
        'reports-chart',
        -> $s {
            join("\x[1F]",
                ($s.get-in('budget', 'digest') // '').Str,
                ($s.get-in('app',    'period') // '').Str,
                (($s.get-in('reports', 'by-group') // False) ?? '1' !! '0'),
            );
        },
        -> Str $ { $self-ref.refresh-chart },
        $!chart,
    );
    Nil
}

#|( §4.6's one key. Bound on the chart rather than app-globally, so a
    bare C<b> is only "by group" while this tab has focus and remains
    a letter everywhere else.

    C<[> and C<]> are not here: the period is global state and
    C<Screen::Main::Keybinds> binds them on the screen root. )
method install-keybinds(--> Nil) {
    my $main  = $!main;
    my $app   = $main.app;
    my $store = $main.store;

    $!chart.on-key: 'b',
        -> $ {
            $store.dispatch('reports/toggle-by-group');
            # The store read happens BEFORE the handler runs — dispatch
            # queues — so this is the value the toggle is about to
            # replace, and each branch is its opposite.
            $app.toast(
                ($store.get-in('reports', 'by-group') // False)
                    ?? 'Spending by category' !! 'Spending by group',
            ) if $app.defined;
        },
        :description('Group spending by category or by group');
    Nil
}

# --- Repaints -------------------------------------------------------

#| Both panes. What a caller outside the subscription path (a modal
#| that has just mutated something) asks for.
method refresh(--> Nil) {
    self.refresh-summary;
    self.refresh-chart;
    Nil
}

#| Which way the aggregation is pointing, from the store.
method by-group(--> Bool) {
    ($!main.store.get-in('reports', 'by-group') // False).Bool;
}

#| Rebuild the spending rows from the cache, in the current
#| aggregation. The rows are kept because the strip's C<Spent> figure
#| is the sum of exactly what the chart is showing.
method !rebuild-rows(--> Nil) {
    my $main = $!main;
    @!rows = spending-rows(
        categories => $main.categories,
        groups     => $main.groups,
        view       => $main.view,
        period     => $main.viewed-period,
        by-group   => self.by-group,
    ).Array;
    Nil
}

#| Repaint the cash-flow strip and its frame title.
method refresh-summary(--> Nil) {
    return without $!summary;
    my $main = $!main;
    my $ws   = $main.workspace;
    my Str $period = $main.viewed-period;

    self!rebuild-rows;

    # find-by-period answers with a Failure on a key that is not a
    # period start, which the store's own guard makes unreachable — but
    # a Failure sunk into a `for` would throw in the middle of a
    # repaint, so it is defused into an empty period here rather than
    # trusted.
    my $found = $ws.transactions.find-by-period($period);
    my @txns = do if $found ~~ Failure { $found.so; () } else { $found.List }

    my %accounts = $main.accounts.map({ .id => $_ }).Hash;

    my %figures = report-summary(
        transactions  => @txns,
        accounts      => %accounts,
        peer-accounts => self!peer-index(@txns, $ws),
        view          => $main.view,
        period        => $period,
        spending      => @!rows,
    );

    $!summary-border.set-title(
        summary-title($main.workspace.scheme.label($period)))
        if $!summary-border.defined;
    $!summary.set-content(summary-spans(%figures, theme => $main.theme));
    # The figures that just changed are what decides whether the strip
    # still fits on one line — a period whose totals gained a digit is
    # exactly the case that pushes it over.
    self!fit-summary-height(summary-line(%figures));
    Nil
}

#| Repaint the chart: its bars, its frame title and the caption for
#| whatever did not fit.
method refresh-chart(--> Nil) {
    return without $!chart;
    self!rebuild-rows;

    my Int $limit = self!bar-limit;
    $!limit-painted = $limit;
    my %cut = top-spending(@!rows, $limit);
    $!hidden-count = %cut<hidden>.Int;
    $!chart.set-data(report-bars(%cut<rows>).Array);

    if $!chart-border.defined {
        $!chart-border.set-title(chart-title(self.by-group));
        $!chart-border.set-bottom-title(more-label($!hidden-count));
    }
    Nil
}

#|( How many bars fit. The chart's own row count less the row its
    value axis takes, and the fallback before the tab has been laid out
    (a widget with no plane reports zero rows, and cutting to zero bars
    would leave the first frame of every visit blank). )
method !bar-limit(--> Int) {
    my Int $rows = ($!chart.defined ?? $!chart.rows !! 0).Int;
    return CHART-FALLBACK-ROWS unless $rows > 0;
    max($rows - CHART-AXIS-ROWS, 1);
}

#|( How many cells wide the strip's content box is, or zero when there
    is nothing to measure it from.

    C<Border.inner-rect> is asked rather than the frame's two cells and
    the two of side padding being subtracted here: the pane's chrome is
    the Border's business, and a padding change in C<build> should not
    quietly leave this measuring a box that does not exist.

    A widget with no plane reports zero columns, and the strip is
    repainted for the first time on the frame the tab is B<mounted> —
    before any of it has been laid out. The parent answers for it: the
    content host outlives every tab switch, so it has real dimensions
    before this tab is built, and a C<VBox> child spans the box's full
    width. Only the very first layout of the whole screen has neither,
    and that one falls through to C<summary-rows-needed>'s own
    fallback. )
method !summary-inner-cols(--> Int) {
    my $border = $!summary-border;
    return 0 without $border;
    my Int $cols = $border.cols.Int;
    $cols = $border.parent.cols.Int
        if $cols == 0 && $border.parent.defined;
    return 0 unless $cols > 0;
    $border.inner-rect($border.rows, $cols)[3].Int;
}

#|( The strip as it stands on screen, read back off the C<RichText>
    rather than re-derived. A resize does not move a single figure, so
    re-running the period's derivation to find out how long the line is
    would be work for an answer already in hand. )
method !painted-strip(--> Str) {
    return '' without $!summary;
    $!summary.spans.map({ ($_.text // '').Str }).join;
}

#|( Give the summary pane the height C<$line> needs at the width it
    has, and — when that is a change — ask for the reflow that makes it
    real.

    Only on a change. C<set-sizing> costs nothing but the full-screen
    repaint behind it does, and this runs on every repaint of the strip
    and every resize; C<$!summary-rows-painted> is to the strip what
    C<$!limit-painted> is to the chart.

    The reflow is C<Selkie::Widget::MultiLineInput>'s own re-measure
    idiom: C<set-sizing> writes the new constraint, and something has
    to be marked dirty afterwards or nobody reads it — the parent
    layout re-runs its allocation from the child's sizing on its next
    render and never on its own. Where C<MultiLineInput> marks its
    parent, this marks the whole screen through
    C<Widget.mark-screen-dirty>: the row this pane gives up or takes
    back is a row the chart underneath gains or loses, so the reshape
    is the tab's rather than one container's. )
method !fit-summary-height(Str $line --> Nil) {
    return without $!summary-border;
    my Int $needed = summary-rows-needed($line, self!summary-inner-cols);
    return if $needed == $!summary-rows-painted;
    $!summary-rows-painted = $needed;
    $!summary-border.set-sizing(Sizing.fixed($needed));
    $!summary-border.mark-screen-dirty;
    Nil
}

#|( Transaction id → the account it belongs to, for the peer of every
    transfer leg in the period.

    Skipped entirely when nothing in the period is a transfer, and
    otherwise built from every transaction rather than the period's:
    both legs of a transfer share a date, so the period's own set would
    do — but C<create-transfer> is the only thing guaranteeing that,
    and a peer that cannot be resolved counts as external money. )
method !peer-index(@txns, $ws --> Hash) {
    return %() unless @txns.first(*.is-transfer).defined;
    $ws.transactions.find-all.map({ .id => .account-id }).Hash;
}

#|( The terminal changed size. Called by C<Screen::Main>'s single
    C<App.on-resize> callback.

    Two re-checks, and both of them run. A resize moves the strip's box
    and the chart's pane independently: getting narrower can push the
    strip onto a second line without changing how many bars fit, and
    getting shorter can move the cut without touching the strip. An
    early return on either question would drop the other.

    Neither costs anything when nothing moved — the height is only
    applied when it changes, and the chart is only re-cut when the
    number of bars that fit actually moved. A resize that leaves both
    alone changes nothing this tab draws that the layout has not
    already handled.

    Both panes are asked for their own geometry rather than told the
    screen's: Selkie has already re-laid-out the tree by the time
    resize callbacks run, and each pane is a fraction of the screen. )
method handle-resize(Int $rows, Int $cols --> Nil) {
    self!fit-summary-height(self!painted-strip);
    return without $!chart;
    return if self!bar-limit == $!limit-painted;
    self.refresh-chart;
    Nil
}
