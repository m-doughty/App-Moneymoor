=begin pod

=head1 NAME

App::Moneymoor::View::InspectorPane - the detail rail's lines, and the
Explain dialog's, both derived from the one equation that defines an
envelope's balance.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::View::InspectorPane;

# The rail beside the envelope table (fixed 30 columns, 26 inside the
# frame and its padding):
my @lines = inspector-lines($view, '2026-08-01', $groceries-id,
                            width => RAIL-TEXT-COLS, icons => $icons);
@lines».<text>;
# ('Carry-in            £0.00',
#  'Assigned          £400.00',
#  'Activity          -£72.50',
#  'Moved in            £0.00',
#  'Moved out           £0.00',
#  '──────────────────────────',
#  'Available         £327.50')

# With a target, two or three more lines under it. The figures are
# gathered first, by the one sub in this module that knows what a
# Model::Category is:
my %target = target-figures($view, $scheme, $groceries, '2026-08-01');
inspector-lines($view, '2026-08-01', $groceries-id, :%target)».<text>.tail(2);
# ('Target            £400.00', 'To fund            +£72.50')

# A goal, which carries its schedule with it:
target-lines(target-figures($view, $scheme, $tax, '2026-12-01'))».<text>;
# ('Target         £50,000.00',
#  'by April 2027 · 5 of 9',
#  'To fund         +£2,777.77')

# Straight to a RichText, coloured per §2:
$rail.set-content(inspector-spans($view, $period, $id,
                                  theme => $theme, icons => $icons));

# The Explain dialog is the same equation plus the derived moves:
explain-lines($view, '2026-08-01', $visa-payment-id,
              names => %categories-by-name, width => 60)».<text>;
# (… , '', 'Derived moves (2)',
#  'card coverage  Groceries → Visa  £72.50',
#  'card refund  Visa → Dining Out  £5.00')

cause-label('card-inflow-to-rta');   # 'card inflow → RTA'

=end code

=head1 DESCRIPTION

Pure line builders. Every function takes a C<BudgetView>, a period and
a category id, and returns a list of C<< { text, severity } >> hashes;
the C<*-spans> wrappers turn those into C<Selkie::Widget::RichText>
spans using C<App::Moneymoor::View::BudgetRow::severity-style>, so the
rail, the grid and the Explain dialog cannot drift apart on colour.

=head2 Rule 1, written out

An envelope's balance is

    available = carry-in + assigned + activity + moved-in - moved-out

and the rail is that sum, one term per line, with a rule and the total
underneath. C<moved-out> is rendered B<negated> for exactly that
reason: a column of figures that does not add up to the number at the
bottom is worse than no column at all.

C<moved-in> and C<moved-out> are the derivation's own credit-card
moves, not anything the user typed — which is why the rail says how
many there are and offers C<x> to see them, rather than trying to
explain them in twenty-six columns.

=head2 The target block is not part of the equation

An envelope with a target gets two or three more lines under the
flags: what it wants, what its plan says about this period, and what
is still missing (C<To fund  +£37.50>) or that it has it. They sit
B<below> the rule and the total on purpose. C<available> is a derived
fact and the five terms above it are why it is what it is; a target is
a plan, and the derivation has never heard of one. Putting the target
inside the sum would make the column stop adding up, which is the one
thing the rail must never do.

=head2 Underfunded is not computed here

It used to be — C<max(0, target - available)>, in C<target-lines>, and
that is only right for one of the three target kinds. The kind-aware
answer is C<App::Moneymoor::Service::Target>'s C<target-ask>, and
there is exactly one of it in the app: the rail, the grid, C<f> and
the assign field's bare C<=> all ask the same function the same
question. What is still true is that the figure is never negative —
an envelope over its target is funded, not "minus £20 to fund".

=head2 …but the figures are gathered here, and rendered separately

C<target-figures> is the seam. It takes the model and the scheme,
calls C<Service::Target> four times and answers a flat C<Hash> of
numbers and strings; C<target-lines> takes that C<Hash> and knows
nothing else. Two reasons for the split, and both of them are about
keeping this module honest:

=item B<Presentation stays testable without a budget.> Every wording
      below — and there are now three kinds' worth — can be asserted
      against a hand-built C<Hash>, with no view, no facts and no
      schedule arithmetic in the way.
=item B<The C<Model::Category> stops at one function.> Every other
      builder in this module still takes a view and an id, which is
      what lets the Explain dialog reuse them. The target block cannot:
      a kind is a property of the row, not of the derivation. So the
      model goes into C<target-figures> and comes no further.

=head2 What each kind's block says

=begin table
Kind      | Line 1                     | Line 2                  | Line 3
----------+----------------------------+-------------------------+--------------------
refill    | Target           £400.00   |                         | To fund  +£72.50 — or Target met
set_aside | Target   £100.00 /period   |                         | To fund  +£40.00 — or Funded this period
by_period | Target        £50,000.00   | by April 2027 · 5 of 9  | To fund  +£2,777.77 — or On track, or Target met
=end table

C<set_aside> says C</period> rather than C<Target met> on the second
line because its question is per-period: £900 already saved does not
mean this period's £100 is done, and "met" would claim it does.
C<describe-target>'s full caption ("Set aside £100.00 each period") is
five columns too wide for the rail, so the rail says the same thing in
its own shorthand.

C<by_period>'s schedule line is B<packed to fit>: the clauses are the
goal period ("by April 2027"), the position in the plan ("3 of 9") and,
when the goal repeats, how often ("every 3 periods"). They are joined
with a middle dot while they fit in C<$width> and broken onto another
line when they do not. That is not decoration — a C<monthly/14>
budget's period label is "14 Aug – 13 Sep 2026", which with a position
clause after it is thirty-two columns in a rail that has twenty-six.

Its last line tells three states apart: C<Target met> when the
envelope is at or past the B<goal> (the plan is done, whatever period
it is), C<On track> when this period asks for nothing but the goal is
still ahead, and the amber C<To fund> otherwise.

=head2 Why the width is a parameter

The rail is 30 cells wide, less two for the frame and two for its
padding: 26. The Explain dialog is a modal and much wider. Both want
the same lines with the money flushed right against a different edge,
so the width is an argument and C<RAIL-TEXT-COLS> is just the default
the rail passes.

A label and figure that will not fit in the given width fall back to
"label space figure" rather than being truncated — a squeezed layout
that still says the number beats a tidy one that does not.

=head1 EXPORTS

=item C<inspector-lines($view, $period, $id, :$width, :%target, :$icons --> List)>
=item C<inspector-spans($view, $period, $id, :$theme!, :$width, :%target, :$icons --> List)>
=item C<equation-lines($view, $period, $id, :$width --> List)>
=item C<flag-lines($cm, :$width, :$icons --> List)>
=item C<target-figures($view, $scheme, $category, Str $period --> Hash)>
      — the block's numbers and captions, or an empty C<Hash> when
      there is no target. Tolerates an uncomputed view, a missing
      scheme and a C<Category> type object.
=item C<target-lines(%target, :$width --> List)> — empty for an empty
      C<Hash>.
=item C<moves-footer($view, $period, $id --> Str)> — C<Str> (the type
      object) when the period has no derived moves for the category.
=item C<explain-lines($view, $period, $id, :%names!, :$width, :$icons --> List)>
=item C<explain-spans(…, :$theme! --> List)>
=item C<cause-label(Str $cause --> Str)>
=item C<pad-line(Str $label, Str $value, Int $width --> Str)>
=item C<RAIL-COLS> (30) / C<RAIL-TEXT-COLS> (26)

=head1 SEE ALSO

=item L<App::Moneymoor::View::BudgetRow> — the severity table these
      colours come from.
=item L<App::Moneymoor::Service::Budget> — C<CategoryPeriod>, C<Move>
      and what a C<cause> means.
=item L<App::Moneymoor::Service::Target> — C<target-ask>,
      C<target-milestone> and C<target-cycle>: the whole of what the
      target block knows.

=end pod

unit module App::Moneymoor::View::InspectorPane;

use Selkie::Widget::RichText::Span;

use App::Moneymoor::Service::Budget;
use App::Moneymoor::Service::Icons;
use App::Moneymoor::Service::Target;
use App::Moneymoor::Theme;
use App::Moneymoor::Util::Money;
use App::Moneymoor::View::BudgetRow;

#| The rail's Border width, and the columns left inside it once the
#| frame (2) and its one cell of padding on each side (2) are paid for.
our constant RAIL-COLS      is export = 30;
our constant RAIL-TEXT-COLS is export = RAIL-COLS - 4;

#|( C<$label> at the left, C<$value> flush right, in C<$width> cells.

        pad-line('Assigned', '£400.00', 26);   # 'Assigned          £400.00'

    Too narrow to separate them at all ⇒ a single space between, and
    the caller's widget clips it. Losing the figure to make the label
    fit would be the wrong half to keep. )
sub pad-line(Str:D $label, Str:D $value, Int:D $width --> Str) is export {
    my Int $gap = $width - $label.chars - $value.chars;
    $gap > 0 ?? $label ~ (' ' x $gap) ~ $value !! $label ~ ' ' ~ $value;
}

#| One money line of the equation.
sub money-line(Str:D $label, Int:D $pence, Int:D $width, Str:D $severity
               --> Hash) {
    %( text => pad-line($label, format-pence($pence), $width), :$severity );
}

#|( The Rule-1 equation for one category-period: five terms, a rule, and
    the total. The total's severity is the row's §2 state, so the
    number at the bottom of the rail is the same colour as the row in
    the grid the user selected to get here. )
sub equation-lines($view, Str:D $period, $category-id,
                   Int :$width = RAIL-TEXT-COLS --> List) is export {
    my $cm = category-period($view, $period, $category-id);
    (
        money-line('Carry-in',  $cm.carry-in,  $width, 'label'),
        money-line('Assigned',  $cm.assigned,  $width, 'label'),
        money-line('Activity',  $cm.activity,  $width, 'label'),
        money-line('Moved in',  $cm.moved-in,  $width, 'label'),
        # Negated on purpose — see "Rule 1, written out" in the Pod.
        money-line('Moved out', -$cm.moved-out, $width, 'label'),
        %( text => '─' x $width, severity => 'rule' ),
        money-line('Available', $cm.available, $width, severity-for($cm)),
    );
}

#|( The category's flags as their own lines, in §2's severity order.
    Only the ones that are actually set appear; a clean envelope
    contributes nothing.

    The two overspend lines carry their amounts because "how much" is
    the next question either of them provokes; the two purple ones do
    not, because their amount B<is> the available figure two lines
    above.

    C<payment-negative> and C<carried-negative> are the same arithmetic
    and the same colour, and they still get different sentences: a card
    you are behind on is a fact about the card, while a carried
    envelope is the rule the user asked for, working. Saying the second
    one out loud is the whole point of giving it its own flag — a
    purple row with no explanation reads as a bug in the budget rather
    than as the setting that produced it. )
sub flag-lines($cm, Int :$width = RAIL-TEXT-COLS,
               :$icons = icons() --> List) is export {
    return () without $cm;
    my @out;
    @out.push(%(
        text     => pad-line($icons.warn ~ ' Cash overspend',
                             format-pence($cm.cash-overspend), $width),
        severity => 'cash-overspend',
    )) if $cm.cash-overspend > 0;
    @out.push(%(
        text     => pad-line($icons.warn ~ ' Credit overspend',
                             format-pence($cm.credit-overspend), $width),
        severity => 'credit-overspend',
    )) if $cm.credit-overspend > 0;
    @out.push(%(
        text     => 'Payment envelope negative',
        severity => 'payment-negative',
    )) if $cm.has-flag('payment-negative');
    # Twenty-five columns of the rail's twenty-six, and every one of
    # them working: "carries forward" is the rule, and the reason the
    # row is purple rather than red is that nothing was charged for it.
    @out.push(%(
        text     => 'Overspend carries forward',
        severity => 'carried-negative',
    )) if $cm.has-flag('carried-negative');
    @out.List;
}

#|( C<'2 moves · x to explain'>, or the C<Str> type object when the
    derivation moved nothing through this envelope this period.

    The count is of C<Move>s touching the category on B<either> side —
    the same set the Explain dialog lists, so the footer never promises
    a dialog more (or less) than it delivers. )
sub moves-footer($view, Str:D $period, $category-id --> Str) is export {
    my @moves = moves-for($view, $period, $category-id);
    return Str unless @moves.elems;
    my Int $n = @moves.elems;
    ($n == 1 ?? '1 move' !! "$n moves") ~ ' · x to explain';
}

#| The kind names as C<Model::Category> stores them. Spelled out here
#| rather than imported, for the same reason C<Service::Target> spells
#| them out for itself: a rendering module that depended on the
#| storage layer's constants would have a reason to depend on the
#| storage layer.
my constant REFILL    = 'refill';
my constant SET-ASIDE = 'set_aside';
my constant BY-PERIOD = 'by_period';

#| The goal period's label, for the schedule line: the cycle's own goal
#| when there is a live cycle, and the stored goal date read as its
#| period when there is not (a plan that has not started, or a one-shot
#| that is past). C<''> whenever that cannot be answered — a rail line
#| naming no period is better left off the rail.
sub goal-label-of($scheme, $category, %cycle --> Str) {
    return '' without $scheme;
    my Str $key = (%cycle<goal> // Str).defined
        ?? %cycle<goal>.Str
        !! do {
            my Str $date = $category.target-period;
            valid-date($date) ?? (try $scheme.period-of($date)) !! Str;
        };
    return '' without $key;
    ($scheme.label($key) // '');
}

#|( Everything the target block needs, as flat data: the amount, the
    kind, this period's milestone and ask, where the envelope actually
    is, and the words for the schedule.

    The one function in this module that takes a C<Model::Category> —
    see "…but the figures are gathered here". An empty C<Hash> is "no
    target", which C<target-lines> renders as nothing at all.

    Everything is guarded, because this is called from a repaint: a
    deleted envelope arrives as a type object, and the frames between
    building the screen and the first recompute have no view. Without
    a view the two static kinds still answer honestly (their figure is
    their amount, and an empty envelope is short by all of it); a
    C<by_period> plan cannot be placed without one, and says so with
    zeroes rather than by guessing. )
sub target-figures($view, $scheme, $category, Str:D $period --> Hash)
        is export {
    return %() without $category;
    my Int $pence = ($category.target-pence // 0).Int;
    return %() unless $pence > 0;

    my Str $kind = ($category.target-kind // REFILL).Str;
    my Bool $live = $view.defined && $scheme.defined && $category.id.defined;
    my Int $available = $live
        ?? category-period($view, $period, $category.id).available.Int !! 0;

    my %cycle = ($live && $kind eq BY-PERIOD)
        ?? target-cycle($scheme, $category, $period) !! %();

    my Int $milestone = do {
        if $kind ne BY-PERIOD      { $pence }
        elsif $live { target-milestone($view, $scheme, $category, $period) }
        else                       { 0 }
    };
    my Int $ask = do {
        if $live              { target-ask($view, $scheme, $category, $period) }
        elsif $kind eq BY-PERIOD { 0 }
        # `max($a, $b)`, never `.max` — the method on an Int does not
        # clamp, it picks the larger of two things and would happily
        # answer with the argument.
        else                  { max($pence - $available, 0) }
    };

    %(
        :$kind, :$pence, :$milestone, :$ask, :$available,
        goal-label => ($kind eq BY-PERIOD
            ?? goal-label-of($scheme, $category, %cycle) !! ''),
        index      => (%cycle<index> // 0).Int,
        of         => (%cycle<of> // 0).Int,
        repeat     => ($category.target-repeat // 0).Int,
    );
}

#|( C<$clauses> joined with C< · > into as few lines of C<$width> as
    they fit in, greedily, one clause per line at worst.

    The schedule reads as one sentence when the rail can hold it and as
    a stack when it cannot; a clause is never split and never dropped.
    Twenty-six columns is not much, and the widest period label this
    app can produce ("14 Aug – 13 Sep 2026") is twenty of them. )
sub packed-lines(@clauses, Int:D $width --> List) {
    my Str @out;
    for @clauses.grep({ ($_ // '').chars }) -> Str $clause {
        if @out.elems && (@out[*-1] ~ ' · ' ~ $clause).chars <= $width {
            @out[*-1] = @out[*-1] ~ ' · ' ~ $clause;
        } else {
            @out.push($clause);
        }
    }
    @out.List;
}

#| The amber "still to fund" line, shared by all three kinds. It
#| carries its sign (C<+£37.50>), because it is the figure the user is
#| about to type into the assign dialog — or press C<f> to have typed
#| for them — and it goes in as an adjustment. Amber rather than red:
#| an underfunded target is a plan not yet finished, not money lost.
sub to-fund-line(Int:D $ask, Int:D $width --> Hash) {
    %( text     => pad-line('To fund', format-pence($ask, :plus), $width),
       severity => 'target-unfunded' );
}

#|( The target block: what this envelope wants, what its plan asks for
    in the period on screen, and what is still missing.

    Returns nothing at all for an empty C<%target>, which is the "no
    target" answer — an envelope without one is not "£0.00 short of
    £0.00", it is simply not in this conversation, and two lines saying
    so on every rail would bury the equation above them.

    Presentation only: every number here was worked out by
    C<target-figures> (and, under that, by C<Service::Target>). See
    "What each kind's block says" for the wordings and why each kind
    gets its own. )
sub target-lines(%target, Int :$width = RAIL-TEXT-COLS --> List) is export {
    my Int $pence = (%target<pence> // 0).Int;
    return () unless $pence > 0;

    my Int $ask = (%target<ask> // 0).Int;

    given (%target<kind> // REFILL).Str {
        when SET-ASIDE {
            (
                # Not `money-line`: the figure is per-period and saying
                # so is the whole difference between this kind and
                # refill. `describe-target`'s "Set aside £100.00 each
                # period" is the same sentence, five columns too wide.
                %( text     => pad-line('Target',
                                        format-pence($pence) ~ ' /period',
                                        $width),
                   severity => 'label' ),
                $ask > 0
                    ?? to-fund-line($ask, $width)
                    # Never "Target met": this kind measures the period's
                    # assignments, and a pot with £900 in it has still not
                    # had this period's £100.
                    !! %( text => 'Funded this period', severity => 'positive' ),
            );
        }
        when BY-PERIOD {
            my Int $of = (%target<of> // 0).Int;
            my Int $repeat = (%target<repeat> // 0).Int;
            my @clauses;
            @clauses.push('by ' ~ %target<goal-label>)
                if (%target<goal-label> // '').chars;
            @clauses.push("{ (%target<index> // 0).Int } of $of") if $of > 0;
            # The same phrasing `describe-target` uses, for the same
            # reason it drops the count in the singular.
            @clauses.push($repeat == 1 ?? 'every period'
                                       !! "every $repeat periods")
                if $repeat >= 1;

            (
                money-line('Target', $pence, $width, 'label'),
                |packed-lines(@clauses, $width).map({
                    %( text => $_, severity => 'label' )
                }),
                $ask > 0
                    ?? to-fund-line($ask, $width)
                    # The goal, not the milestone: a plan that has
                    # arrived says so whatever period it is, and one
                    # that is merely up to date this period says the
                    # more modest thing.
                    !! ((%target<available> // 0).Int >= $pence
                        ?? %( text => 'Target met', severity => 'positive' )
                        !! %( text => 'On track',   severity => 'positive' )),
            );
        }
        default {
            (
                money-line('Target', $pence, $width, 'label'),
                $ask > 0
                    ?? to-fund-line($ask, $width)
                    !! %( text => 'Target met', severity => 'positive' ),
            );
        }
    }
}

#|( The whole rail: equation, then flags, then the target block, then
    the moves footer, each block separated by a blank line.

    C<:%target> is threaded in by the caller rather than read off a
    model here, for the same reason every other function in this module
    takes a view and an id: these builders know about the derivation
    and nothing else. C<Screen::Budget.refresh-inspector> has the model
    and the scheme in hand and calls C<target-figures> with them. )
sub inspector-lines($view, Str:D $period, $category-id,
                    Int :$width = RAIL-TEXT-COLS,
                    :%target = %(),
                    :$icons = icons() --> List) is export {
    my @lines = equation-lines($view, $period, $category-id, :$width).Array;

    my $cm = category-period($view, $period, $category-id);
    my @flags = flag-lines($cm, :$width, :$icons);
    if @flags.elems {
        @lines.push(%( text => '', severity => 'label' ));
        @lines.append(@flags);
    }

    my @target = target-lines(%target, :$width);
    if @target.elems {
        @lines.push(%( text => '', severity => 'label' ));
        @lines.append(@target);
    }

    my Str $footer = moves-footer($view, $period, $category-id);
    with $footer {
        @lines.push(%( text => '', severity => 'label' ));
        @lines.push(%( text => $footer, severity => 'rule' ));
    }
    @lines.List;
}

#| The rail's lines as C<RichText> spans, one line per span with a
#| trailing newline, coloured through the §2 table.
sub inspector-spans($view, Str:D $period, $category-id,
                    App::Moneymoor::Theme :$theme!,
                    Int :$width = RAIL-TEXT-COLS,
                    :%target = %(),
                    :$icons = icons() --> List) is export {
    lines-to-spans(
        inspector-lines($view, $period, $category-id, :$width,
                        :%target, :$icons),
        :$theme,
    );
}

#|( A derivation C<Move>'s C<cause> as English.

    The engine's causes are kebab-case identifiers because they are
    compared and serialised; a dialog that shows the user
    C<card-inflow-to-rta> is showing them the wire format. Unknown
    causes — there are none today, but the engine may grow one before
    this module hears about it — degrade to the identifier with its
    hyphens opened out, which reads acceptably for anything named the
    way the existing three are. )
sub cause-label(Str $cause --> Str) is export {
    given ($cause // '') {
        when 'card-coverage'      { 'card coverage'     }
        when 'card-refund'        { 'card refund'       }
        when 'card-inflow-to-rta' { 'card inflow → RTA' }
        default                   { $_.subst('-', ' ', :g) }
    }
}

#|( The Explain dialog: the equation block, then every derived move
    that touched this envelope this period, named rather than numbered.

    C<:%names> maps category id → name (C<Screen::Main>'s
    C<categories> cache, keyed by id). An id with no name behind it
    renders as C<'category 7'> rather than blank: a move whose other
    side has been deleted is exactly the case someone opens this dialog
    to understand. )
sub explain-lines($view, Str:D $period, $category-id,
                  :%names!, Int :$width = RAIL-TEXT-COLS,
                  :$icons = icons() --> List) is export {
    my @lines = equation-lines($view, $period, $category-id, :$width).Array;

    my $cm = category-period($view, $period, $category-id);
    my @flags = flag-lines($cm, :$width, :$icons);
    if @flags.elems {
        @lines.push(%( text => '', severity => 'label' ));
        @lines.append(@flags);
    }

    @lines.push(%( text => '', severity => 'label' ));

    my @moves = moves-for($view, $period, $category-id);
    unless @moves.elems {
        @lines.push(%( text => 'No derived moves this period',
                       severity => 'rule' ));
        return @lines.List;
    }

    @lines.push(%( text => "Derived moves ({@moves.elems})",
                   severity => 'rule' ));
    for @moves -> $mv {
        @lines.push(%(
            text => cause-label($mv.cause)
                    ~ '  ' ~ name-of(%names, $mv.from-category-id)
                    ~ ' ' ~ $icons.move ~ ' '
                    ~ name-of(%names, $mv.to-category-id)
                    ~ '  ' ~ format-pence($mv.amount),
            severity => 'normal',
        ));
    }
    @lines.List;
}

#| The Explain dialog's lines as C<RichText> spans.
sub explain-spans($view, Str:D $period, $category-id,
                  App::Moneymoor::Theme :$theme!, :%names!,
                  Int :$width = RAIL-TEXT-COLS,
                  :$icons = icons() --> List) is export {
    lines-to-spans(
        explain-lines($view, $period, $category-id, :%names, :$width, :$icons),
        :$theme,
    );
}

#|( One span per line, each ending in a newline so C<RichText> lays
    them out as a stack. Shared by both dialogs, which is what keeps
    "a line" meaning the same thing in each. )
sub lines-to-spans(@lines, App::Moneymoor::Theme :$theme! --> List) is export {
    @lines.map(-> %line {
        Selkie::Widget::RichText::Span.new(
            text  => (%line<text> // '') ~ "\n",
            style => severity-style(%line<severity> // 'normal', :$theme),
        )
    }).List;
}

#|( A category's name, or a legible stand-in. Deliberately not blank:
    see C<explain-lines>. )
sub name-of(%names, $id --> Str) {
    return '(none)' without $id;
    my $c = %names{$id};
    ($c.defined && $c.can('name')) ?? $c.name !! ($c // "category $id").Str;
}

#| Zero-filled category-period, tolerant of an uncomputed view — the
#| same contract C<View::BudgetRow> works to.
sub category-period($view, Str:D $period, $id) {
    return App::Moneymoor::Service::Budget::CategoryPeriod.new(
        period => $period, category-id => ($id // 0).Int,
    ) unless $view.defined && $id.defined;
    $view.category($period, $id.Int);
}

#| Moves touching a category in a period, tolerating an uncomputed view.
sub moves-for($view, Str:D $period, $id --> List) {
    return () unless $view.defined && $id.defined;
    $view.moves-for($period, category-id => $id.Int).List;
}
