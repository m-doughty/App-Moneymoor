=begin pod

=head1 NAME

App::Moneymoor::Screen::Budget - the budget tab: the Ready-to-Assign
pill, the envelope table and the detail rail.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Screen::Budget;

# Built by Screen::Main's content-host seam, never directly:
my $tab = App::Moneymoor::Screen::Budget.new(main => $main);
$tab.build($content-host);       # mounts the panes
$tab.install-subscriptions;      # store → rows / rail / pill
$tab.install-keybinds;           # a m f x n g e h u i, and Enter

# What the modals in Screen::Main::Modals read back:
$tab.selected-row;               # the row hash under the cursor
$tab.selected-category-id;       # Int, or the type object on a header
$tab.selected-group-id;          # Int, or the type object on a category

=end code

=head1 DESCRIPTION

    VBox (the content host)
     ├ Border(fixed 3, 'August 2026')      the Ready-to-Assign pill
     │   └ HBox: RichText(flex)            'Ready to Assign  £412.50'
     │           Text(flex, right)         '£300.00 assigned in future periods'
     └ HBox(flex)
         ├ Border(flex, 'Envelopes · August 2026') → Table
         └ Border(fixed 30, '<category>')          → RichText rail

The Table's five columns are Category (flex), Assigned, Activity,
Available and Target; C<View::BudgetRow> renders every cell.

Everything this class paints comes out of two pure modules —
C<View::BudgetRow> for the grid and the pill, C<View::InspectorPane>
for the rail — and this file is the wiring: which widget, which
subscription, which key.

=head2 Group headers live in the same Table as the rows

C<Selkie::Widget::Table> has no notion of a section, so the group
headers are ordinary rows carrying C<< kind => 'group' >>. That buys
one grid, one cursor and one scrollbar; it costs the two things this
class has to handle by hand:

=item B<The cursor can sit on a header.> Every action checks
      C<selected-row><kind> and either does the group-flavoured thing
      (C<e> edits the group, C<d> deletes it, Enter folds it) or says
      why it can't. It never silently acts on the wrong row.
=item B<Row indices are not stable across a rebuild.> Folding a group
      or hiding an envelope changes what lives at index 7. So the
      cursor is restored B<by category id> after every C<set-rows>,
      and only then is the selection re-announced to the store.

C<set-rows> and C<select-index> both fire C<on-select>, which is how
the store learns where the cursor is — so both are wrapped in a
suppression flag during a rebuild, and one deliberate announcement is
made at the end. Without it, a rebuild would announce the row that
happens to be under the old index, the rail would repaint for a
category the user never chose, and (once the rebuild was itself
triggered by a selection-keyed subscription) it would do it every
frame.

=head2 Sorting is off

Every column is C<< sortable => False >>. Sorting reorders the view
rows without knowing that some of them are headers, which would scatter
the categories away from their groups. The grid's order is the user's
own C<sort_order>, which is what the category and group editors exist
to change.

=head2 The rail is mounted, not hidden

C<i> toggles C<budget/inspector>, and the tab is rebuilt rather than
the rail being resized to nothing: a zero-allocation child of an
C<HBox> has to be parked or it paints outside its parent, and "rebuild
the tab" is a path that already exists, already restores the cursor
and already re-registers every subscription. The rebuild is driven by a
subscription anchored on the B<content host> — the one widget in the
tab that survives its own rebuild.

=head1 METHODS

=item C<build($host)> — construct and mount. Registers the table as the
      tab's C<budget> hint-context pane and its initial focus target.
=item C<install-subscriptions()> / C<install-keybinds()> — the two
      seams C<Screen::Main::Subscriptions::install-content> and
      C<Screen::Main::Keybinds::install-content> call.
=item C<refresh-rows()> / C<refresh-inspector()> / C<refresh-rta()> —
      the subscription callbacks, public because a modal that has just
      mutated something outside the store's sight can ask for a
      repaint.
=item C<table>, C<selected-row>, C<selected-category-id>,
      C<selected-group-id>, C<inspector-mounted>.

=head1 SEE ALSO

=item L<App::Moneymoor::View::BudgetRow> — the rows, the pill, §2.
=item L<App::Moneymoor::View::InspectorPane> — the rail's lines.
=item L<App::Moneymoor::Screen::Main::Modals> — what the keys open.
=item L<App::Moneymoor::StoreHandlers> — C<budget/select-category>,
      C<budget/toggle-group> and the two change tokens.

=end pod

unit class App::Moneymoor::Screen::Budget;

use Selkie::Align;
use Selkie::BorderStyle;
use Selkie::Layout::HBox;
use Selkie::Sizing;
use Selkie::Style;
use Selkie::Widget::Border;
use Selkie::Widget::RichText;
use Selkie::Widget::RichText::Span;
use Selkie::Widget::Table;
use Selkie::Widget::Text;

use App::Moneymoor::View::BudgetRow;
use App::Moneymoor::View::EmptyState;
use App::Moneymoor::View::InspectorPane;
use App::Moneymoor::Screen::Main::Modals;

#| The C<Screen::Main> that owns the caches, the store and the palette.
#| Untyped so this class does not have to C<use> the screen that
#| C<use>s it.
has $.main is required;

has Selkie::Widget::Table $.table;
has Selkie::Widget::Border $!rta-border;
has Selkie::Widget::RichText $!rta-line;
has Selkie::Widget::Text $!rta-note;
has Selkie::Widget::Border $!inspector-border;
has Selkie::Widget::RichText $!inspector;

#| Whether this build put the rail on screen. Compared against
#| C<budget/inspector> by the mount subscription to decide whether the
#| tab needs rebuilding; see "The rail is mounted, not hidden".
has Bool $.inspector-mounted = False;

#| True while a rebuild is moving the cursor about, so the C<on-select>
#| tap knows the movement is the app's and not the user's.
has Bool $!suppress-select = False;

#| Rows of the Ready-to-Assign pill: a frame plus the one line inside
#| it.
my constant RTA-ROWS = 3;

method build($host --> Nil) {
    my $main  = $!main;
    my $theme = $main.theme;
    my $store = $main.store;

    # --- The Ready-to-Assign pill ------------------------------------
    #
    # Padding on the sides only: three rows is the frame plus exactly
    # one line, and a cell of vertical padding would leave the content
    # box with negative height.
    $!rta-border = Selkie::Widget::Border.new(
        sizing        => Sizing.fixed(RTA-ROWS),
        border-style  => BorderRounded,
        title         => '',
        padding-left  => 1,
        padding-right => 1,
    );
    my $head = Selkie::Layout::HBox.new(sizing => Sizing.flex);
    $!rta-line = Selkie::Widget::RichText.new(sizing => Sizing.flex);
    # A right-aligned Text rather than spans with computed padding: the
    # alignment is then the widget's job and survives a resize without
    # anything having to recompute a gap.
    $!rta-note = Selkie::Widget::Text.new(
        text   => '',
        sizing => Sizing.flex,
        align  => TextRight,
        style  => Selkie::Style.new(fg => $theme.fg-dim),
    );
    $head.add($!rta-line);
    $head.add($!rta-note);
    $!rta-border.set-content($head);
    $host.add($!rta-border);
    $!rta-border.set-store($store);

    # --- The grid and the rail ---------------------------------------
    my $row = Selkie::Layout::HBox.new(sizing => Sizing.flex);
    $host.add($row);

    $!table = Selkie::Widget::Table.new(
        sizing => Sizing.flex, show-scrollbar => True,
    );
    $!table.add-column(
        name => 'category', label => 'Category', sizing => Sizing.flex);
    $!table.add-column(
        name   => 'assigned',
        label  => money-header('Assigned', ASSIGNED-COLS),
        sizing => Sizing.fixed(ASSIGNED-COLS));
    $!table.add-column(
        name   => 'activity',
        label  => money-header('Activity', ACTIVITY-COLS),
        sizing => Sizing.fixed(ACTIVITY-COLS));
    $!table.add-column(
        name   => 'available',
        label  => money-header('Available', AVAILABLE-COLS),
        sizing => Sizing.fixed(AVAILABLE-COLS));
    # Rightmost, because it is the column the eye needs least often:
    # available is the number you budget against, the target is the
    # number you set once and then forget until `f`.
    $!table.add-column(
        name   => 'target',
        label  => money-header('Target', TARGET-COLS),
        sizing => Sizing.fixed(TARGET-COLS));
    $!table.set-row-style(-> %r {
        severity-style((%r<severity> // 'normal').Str, :$theme)
    });

    # mount-pane frames it, registers the `budget` hint context, makes
    # it the tab's focus target and pushes the store down.
    $main.mount-pane($row, $main.pane-border('Envelopes', Sizing.flex),
                     $!table, 'budget');

    $!inspector-mounted = ($store.get-in('budget', 'inspector') // True).Bool;
    if $!inspector-mounted {
        $!inspector = Selkie::Widget::RichText.new(sizing => Sizing.flex);
        $!inspector-border =
            $main.pane-border('Detail', Sizing.fixed(RAIL-COLS));
        $!inspector-border.set-content($!inspector);
        $row.add($!inspector-border);
        # A fixed-width HBox child does NOT get set-store cascaded to
        # it — see Screen::Main.mount-pane's note. The rail has no
        # subscriptions of its own today, but a Border that never sees
        # the store also never gets its focus highlight.
        $!inspector-border.set-store($store);
    }

    self!wire-table;
    Nil
}

# --- Wiring ---------------------------------------------------------

method !wire-table(--> Nil) {
    my $store = $!main.store;

    # A cursor move is a store write, and the rail follows the store
    # rather than the widget — so a selection restored by code and one
    # made with the arrow keys land in exactly the same place.
    #
    # `self!` rather than a captured `$self-ref!`: a private method call
    # needs the invocant's type known at compile time, and an untyped
    # lexical holding the same object does not give the compiler that.
    $!table.on-select.tap: -> UInt $ {
        self!announce-selection unless $!suppress-select;
    };

    # Enter: fold a group, or assign to an envelope. Bound through
    # on-activate rather than an `enter` keybind because Table checks
    # its keybinds *before* its own navigation, and stealing Enter here
    # would take it away from the widget for good.
    $!table.on-activate.tap: -> UInt $idx {
        my $row = $!table.row-at($idx);
        with $row {
            if $_<kind> eq 'group' {
                $store.dispatch('budget/toggle-group', group-id => $_<id>);
            } elsif $_<kind> eq 'category' {
                App::Moneymoor::Screen::Main::Modals::open-assign($!main);
            }
        }
    };
    Nil
}

#| Tell the store which category the cursor is on — the type object
#| when it is on a group header or the empty-state row, which is what
#| makes the rail able to say "nothing selected" rather than describing
#| the last envelope the user passed over.
method !announce-selection(--> Nil) {
    my $row = $!table.selected-row;
    my Int $id = ($row.defined && $row<kind> eq 'category')
        ?? $row<id>.Int !! Int;
    $!main.store.dispatch('budget/select-category', category-id => $id);
    Nil
}

#|( The tab's store wiring. Four channels:

    =item the rows, keyed on both change tokens plus the period and the
       two view switches;
    =item the rail, keyed on both change tokens and the cursor;
    =item the pill, keyed on the derivation and the period;
    =item the rail's presence, which rebuilds the tab.

    Every selector returns one flat C<Str>. That is not stylistic: the
    store compares subscription values by content digest and keys
    objects by identity, so a selector handing back the collapsed-group
    Hash would read as changed on every tick and rebuild the grid sixty
    times a second. )
method install-subscriptions(--> Nil) {
    my $self-ref = self;
    my $store    = $!main.store;

    $store.subscribe-with-callback(
        'budget-rows',
        -> $s {
            join("\x[1F]",
                ($s.get-in('budget', 'catalogue') // '').Str,
                ($s.get-in('budget', 'digest')    // '').Str,
                ($s.get-in('app',    'period')    // '').Str,
                (($s.get-in('budget', 'show-hidden') // False) ?? '1' !! '0'),
                ($s.get-in('budget', 'collapsed-groups') // %())
                    .keys.sort.join(','),
            );
        },
        -> Str $ { $self-ref.refresh-rows },
        $!table,
    );

    $store.subscribe-with-callback(
        'budget-inspector',
        -> $s {
            # The catalogue token is in here for the same reason it is
            # in the rows selector: the rail draws a target block, a
            # target moves no money, and the derivation's digest is
            # therefore byte-identical either side of saving one. Without
            # it a saved target repaints the grid and leaves the rail
            # showing the old figure until the selection moved.
            join("\x[1F]",
                ($s.get-in('budget', 'digest')    // '').Str,
                ($s.get-in('budget', 'catalogue') // '').Str,
                ($s.get-in('app',    'period')    // '').Str,
                ($s.get-in('budget', 'selected-category-id') // '').Str,
            );
        },
        -> Str $ { $self-ref.refresh-inspector },
        $!table,
    );

    $store.subscribe-with-callback(
        'budget-rta',
        -> $s {
            join("\x[1F]",
                ($s.get-in('budget', 'digest') // '').Str,
                ($s.get-in('app',    'period') // '').Str,
            );
        },
        -> Str $ { $self-ref.refresh-rta },
        $!table,
    );

    # Anchored on the content host, not on anything this tab built: the
    # callback destroys the tab, and a subscription bound to a widget
    # inside it would be tearing down its own anchor. The host outlives
    # every tab.
    my Str $built = $!inspector-mounted ?? '1' !! '0';
    my $main = $!main;
    $store.subscribe-with-callback(
        'budget-inspector-mount',
        -> $s { ($s.get-in('budget', 'inspector') // True) ?? '1' !! '0' },
        -> Str $want {
            $main.rebuild-content
                if $want ne $built && $main.current-tab eq 'budget';
        },
        $!main.content-host,
    );
    Nil
}

#|( Per-pane keys, §4.3's table. Bound on the C<Table> rather than
    app-globally, so a bare C<a> is only "assign" while the grid has
    focus and remains a letter everywhere else.

    C<[> and C<]> are not here: the period is global state (the banner
    and the reports chart read it too) and C<Screen::Main::Keybinds>
    binds them on the screen root. )
method install-keybinds(--> Nil) {
    my $main  = $!main;
    my $app   = $main.app;
    my $store = $main.store;
    my $self-ref = self;

    $!table.on-key: 'a',
        -> $ { App::Moneymoor::Screen::Main::Modals::open-assign($main) },
        :description('Assign to this envelope');

    $!table.on-key: 'm',
        -> $ { App::Moneymoor::Screen::Main::Modals::open-move-money($main) },
        :description('Move money out of this envelope');

    # Not row-dependent: `f` is about the whole period, so it works from
    # a group header and from the empty state as readily as from an
    # envelope. What it finds (or does not find) to fund is the
    # dialog's business.
    $!table.on-key: 'f',
        -> $ { App::Moneymoor::Screen::Main::Modals::open-fund-all($main) },
        :description('Fund every underfunded envelope to its target');

    $!table.on-key: 'x',
        -> $ { App::Moneymoor::Screen::Main::Modals::open-explain($main) },
        :description('Explain this balance');

    $!table.on-key: 'n',
        -> $ {
            App::Moneymoor::Screen::Main::Modals::open-category-editor($main);
        },
        :description('New envelope');

    $!table.on-key: 'g',
        -> $ {
            App::Moneymoor::Screen::Main::Modals::open-group-editor($main);
        },
        :description('New group');

    # The one key whose meaning depends on the row: a header is a
    # group, a category row is an envelope, and the empty-state row is
    # neither — which is why this dispatches on `kind` rather than on
    # "is there a selected category id".
    $!table.on-key: 'e',
        -> $ {
            my $row = $self-ref.selected-row;
            my Str $kind = $row.defined ?? $row<kind>.Str !! '';
            if $kind eq 'group' {
                App::Moneymoor::Screen::Main::Modals::open-group-editor(
                    $main, group-id => $row<id>.Int);
            } elsif $kind eq 'category' {
                App::Moneymoor::Screen::Main::Modals::open-category-editor(
                    $main, category-id => $row<id>.Int);
            } elsif $app.defined {
                $app.toast('Nothing to edit here');
            }
        },
        :description('Edit the selected envelope or group');

    # Row-dependent for the same reason `e` is, and deliberately the
    # same dispatch: whatever `e` would edit is what `d` deletes.
    # Deleting is confirmed and then refused by the engine when the row
    # has history — the refusal arrives as a toast, so this does not
    # pre-check it.
    $!table.on-key: 'd',
        -> $ {
            my $row = $self-ref.selected-row;
            my Str $kind = $row.defined ?? $row<kind>.Str !! '';
            if $kind eq 'group' {
                App::Moneymoor::Screen::Main::Modals::delete-group(
                    $main, group-id => $row<id>.Int);
            } elsif $kind eq 'category' {
                App::Moneymoor::Screen::Main::Modals::delete-category($main);
            } elsif $app.defined {
                $app.toast('Nothing to delete here');
            }
        },
        :description('Delete the selected envelope or group');

    $!table.on-key: 'h',
        -> $ { App::Moneymoor::Screen::Main::Modals::hide-category($main) },
        :description('Hide (or unhide) this envelope');

    # Both toasts read the store BEFORE dispatching, so they see the
    # value the toggle is about to replace — `dispatch` queues and the
    # handler runs on the next tick. Each branch is therefore the
    # opposite of what the pre-dispatch read says.
    $!table.on-key: 'u',
        -> $ {
            $store.dispatch('budget/toggle-hidden');
            $app.toast(
                ($store.get-in('budget', 'show-hidden') // False)
                    ?? 'Hiding hidden envelopes' !! 'Showing hidden envelopes',
            ) if $app.defined;
        },
        :description('Toggle hidden envelopes');

    $!table.on-key: 'i',
        -> $ {
            $store.dispatch('budget/toggle-inspector');
            $app.toast(
                ($store.get-in('budget', 'inspector') // True)
                    ?? 'Detail hidden' !! 'Detail shown',
            ) if $app.defined;
        },
        :description('Toggle the category detail rail');
    Nil
}

# --- Repaints -------------------------------------------------------

#|( Rebuild the grid from the cache and put the cursor back on the
    category it was on.

    The restore is by id, not by index — see "Group headers live in the
    same Table". When the selected envelope is no longer in the list
    (it was hidden, or its group was folded) the cursor stays where it
    is and the new row under it is announced instead, which is the
    least surprising thing a list can do. )
method refresh-rows(--> Nil) {
    return without $!table;
    my $main  = $!main;
    my $store = $main.store;

    my @rows = budget-rows(
        groups      => $main.groups,
        categories  => $main.categories,
        view        => $main.view,
        scheme      => $main.workspace.scheme,
        period      => $main.viewed-period,
        collapsed   => ($store.get-in('budget', 'collapsed-groups') // %()),
        show-hidden => ($store.get-in('budget', 'show-hidden') // False).Bool,
        icons       => $main.icons,
    ).Array;

    # A budget with no envelopes at all: one unselectable row carrying
    # the empty-state copy, rather than a blank rectangle under a
    # header row. `kind => 'empty'` keeps every action off it.
    unless @rows.elems {
        @rows = empty-state-for('budget', icons => $main.icons).map({
            %( kind => 'empty', id => 0, group-id => 0, hidden => False,
               severity => 'zero', category => $_,
               assigned => '', activity => '', available => '', target => '' )
        }).Array;
    }

    my $want = $store.get-in('budget', 'selected-category-id');
    $!suppress-select = True;
    $!table.set-rows(@rows);
    if $want.defined {
        my $idx = @rows.first(
            { $_<kind> eq 'category' && $_<id> == $want.Int }, :k);
        $!table.select-index($idx.UInt) with $idx;
    }
    $!suppress-select = False;
    self!announce-selection;
    Nil
}

#| Repaint the detail rail for whatever the store says is selected.
method refresh-inspector(--> Nil) {
    return without $!inspector;
    my $main  = $!main;
    my $theme = $main.theme;
    my $id    = $main.store.get-in('budget', 'selected-category-id');

    unless $id.defined {
        $!inspector-border.set-title('Detail');
        $!inspector.set-content((
            Selkie::Widget::RichText::Span.new(
                text  => 'Select an envelope',
                style => severity-style('label', :$theme),
            ),
        ));
        return;
    }

    my $category = $main.category($id.Int);
    $!inspector-border.set-title(
        $category.defined ?? $category.name !! 'Detail');
    # `target-figures` is handed the model, the scheme and the period
    # and answers with flat data — it is the only thing in the rail's
    # path that knows a target has kinds. A stale selection pointing at
    # a just-deleted envelope arrives here as a type object and comes
    # back as an empty Hash, which renders as no target block at all.
    my %target = target-figures(
        $main.view, $main.workspace.scheme, $category, $main.viewed-period);
    $!inspector.set-content(inspector-spans(
        $main.view, $main.viewed-period, $id.Int,
        theme => $theme, width => RAIL-TEXT-COLS, icons => $main.icons,
        :%target,
    ));
    Nil
}

#| Repaint the Ready-to-Assign pill: its frame title is the period, its
#| line is the figure, and the note on the right is the money already
#| committed to periods the user is not looking at.
method refresh-rta(--> Nil) {
    return without $!rta-line;
    my $main  = $!main;
    my $theme = $main.theme;
    my Str $period = $main.viewed-period;

    my %summary = rta-summary($main.view, $period, icons => $main.icons);

    # `label` answers '' rather than throwing for anything that is not
    # a start under the workspace's scheme, so the `||` is the whole
    # guard the title needs.
    $!rta-border.set-title(
        $main.workspace.scheme.label($period) || 'Budget');
    $!rta-line.set-content((
        Selkie::Widget::RichText::Span.new(
            text  => %summary<text>,
            style => severity-style(%summary<severity>, :$theme),
        ),
    ));
    $!rta-note.set-text(%summary<note>);
    Nil
}

# --- What the modals ask ---------------------------------------------

#| The row hash under the cursor, or C<Nil> on an empty grid.
method selected-row() { $!table.defined ?? $!table.selected-row !! Nil }

#| The selected envelope's id, or the C<Int> type object when the
#| cursor is on a group header (or the empty-state row).
method selected-category-id(--> Int) {
    my $row = self.selected-row;
    ($row.defined && $row<kind> eq 'category') ?? $row<id>.Int !! Int;
}

#| The selected group's id — from a header row, or from the group the
#| selected category belongs to. C<Int> type object on an empty grid.
method selected-group-id(--> Int) {
    my $row = self.selected-row;
    return Int without $row;
    return Int if $row<kind> eq 'empty';
    ($row<kind> eq 'group' ?? $row<id> !! $row<group-id>).Int;
}
