=begin pod

=head1 NAME

App::Moneymoor::Service::Target - what an envelope's target asks for
in the period you are looking at.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Service::Target;

my $scheme = $ws.scheme;
my $view   = $ws.budget(through-period => '2026-12-01');
my $tax    = $ws.categories.find-by-name('Tax');

# The one number everything keys on: this period's gap. £50,000 by
# April, stamped in August, and December is the fifth of the nine
# periods — so the empty pot is five ninths of the way behind.
say target-ask($view, $scheme, $tax, '2026-12-01');      # 2777777

# The figure the grid shows in its Target column: for a by-period
# target that is the current milestone, not the end goal.
say target-milestone($view, $scheme, $tax, '2026-12-01'); # 2777777

# Where in the plan this period sits, for the rail's copy.
my %c = target-cycle($scheme, $tax, '2026-12-01');
say "period { %c<index> } of { %c<of> }";                # period 5 of 9

# The caption, for the rail and the editor.
say describe-target($tax, $scheme);
# £50,000.00 by April 2027

=end code

=head1 DESCRIPTION

A target says what an envelope wants. This module says what it wants
B<now> — in one budget period, given everything the derivation already
worked out about that period.

It is pure. No database, no clock, no widgets, no state: four
subroutines over a C<BudgetView>, a period scheme and a
C<Model::Category>. The engine has never heard of targets and never
will (see L<App::Moneymoor::Model::Category>), so everything here is
derived on the way to the screen, from figures C<Service::Budget>
produced for its own reasons.

=head2 THE ONE FUNCTION THAT MATTERS

C<target-ask> is "how much would fully funding this envelope's plan
for this period cost". Every target feature in the app is that number
wearing a different hat: the assign dialog's bare C<=> assigns it, the
grid's C<f> assigns it to every envelope at once, the rail prints it,
and the grid colours a row by whether it is zero. Adding a target kind
therefore means teaching B<this> function a new case and nothing else
— which is exactly what the three kinds below are.

=head2 THE THREE KINDS, AND WHAT EACH MEASURES AGAINST

Same amount, three different questions, and the difference is which
of the derivation's figures the amount is compared to.

=begin code :lang<raku>
# refill: "available should be £400 each period"
#   ask = max(0, 40000 - available)
#
# set_aside: "put £100 in each period"
#   ask = max(0, 10000 - assigned)
#
# by_period: "reach £50,000 available by April"
#   ask = max(0, milestone-for-this-period - available - goal-outflow)
=end code

=head3 C<refill> measures B<available>

The v0.1 behaviour and the default. Carry-in counts, because that is
the point: a spending envelope you did not empty last period needs
topping up, not refilling. This is the right shape for groceries and
the wrong shape for a Christmas fund, which is why the other two
exist.

=head3 C<set_aside> measures B<assigned>

"Put £100 in each period, whatever is already in there." Deliberately
B<assigned>-based, and the consequences are all intended:

=item B<Carry-in never silences it.> £900 saved so far does not mean
      this period's £100 is done. That is the whole failure C<refill>
      has with an accumulating fund.
=item B<A refund is not saving.> Money coming back into the envelope
      is activity, not an assignment, so the ask stands.
=item B<Pulling money back re-opens it.> C<assigned> is a signed sum
      for the period, so moving £60 of this period's £100 out to cover
      something else takes the assignment to £40 and the ask back to
      £60. Undoing a contribution undoes it.

An assignment can be negative outright (a period where you took more
out than you put in), which makes the ask B<larger> than the target.
That is correct: the plan for the period is still £100 in, and you
are now further from it than you started.

=head3 C<by_period> measures a B<milestone>

"Reach £50,000 available by April." The plan is a straight line from
the period the target was stamped in to the period containing the goal
date, and each period's ask is the distance from where the envelope is
to where the line says it should be. The rest of this page is that
sentence in detail.

=head2 THE MILESTONE SCHEDULE

Four things define a C<by_period> plan:

=item B<N> — C<target-pence>, the goal amount.
=item B<S> — the period containing C<target-start>, the stamped plan
      start. C<Service::Workspace.set-target> stamps it; see there for
      when it re-stamps.
=item B<E> — the period containing C<target-period>, the goal period.
      Both are stored as B<dates> and read as the periods containing
      them, so a budget that changes its period scheme re-derives the
      plan under the new windows instead of holding keys that no
      longer name periods.
=item B<R> — C<target-repeat>. C<0> is a one-shot goal; C<R E<gt>= 1>
      puts goal periods at E, E+R, E+2R, … C<R> counts B<periods>, so
      quarterly VAT is "every 3" under C<monthly/1> and something else
      under C<weekly/4>.

The viewed period C<v> falls in a B<cycle>: a run of C<k> periods
ending on a goal period. Cycle 0 runs S…E inclusive (so C<k> is the
number of periods in it, and C<i> is C<v>'s 1-based place in it);
every later cycle runs the C<R> periods from just after one goal
period through the next. Then, with C<base> the envelope's B<carry-in
at the cycle's first period>:

=begin code :lang<raku>
milestone(i) = base + floor((N - base) * i / k)      # milestone(k) = N
ask          = max(0, milestone(i) - available - goal-outflow)
=end code

Integer pence throughout, and C<milestone(k)> is forced to exactly
C<N> rather than trusted to the division: nine steps to £50,000 gives
£5,555.55 a period, and nine of those is £49,999.95. The plan has to
end on the number the user typed.

=head3 Worked example: £50,000 by April

Self-employment tax, stamped in the August period, goal 5 April,
calendar months. S is C<2026-08-01>, E is C<2027-04-01>, so C<k> is 9
and, from an empty envelope, C<base> is 0:

=begin code :lang<raku>
i   milestone     ask with available = milestone (i.e. on plan)
1     555555      555555      # £5,555.55 — 50000/9, floored
2    1111111      555556
3    1666666      555555
…
8    4444444      555555
9    5000000      555556      # forced to exactly N
=end code

The pennies wobble by one and the total is exact, which is the right
way round.

B<Getting ahead reduces later asks.> Assign £10,000 in the first
period and C<available> is 1,000,000 against a milestone of 555,555:
the ask is 0, and the second period's ask is
C<1111111 - 1000000 = 111111> rather than 555,556. The schedule is a
line to a destination, not a subscription.

B<Raiding it makes the gap reappear at once.> In the fifth period the
milestone is 2,777,777. Take £5,000 out to cover a boiler and
C<available> falls to 2,300,000 — the ask is 477,777 B<in that same
period>, not spread over the four that are left. This is the settled
ruling and it is deliberate: a big raid late in a plan produces one
big ask, because the schedule is the schedule. It fires whether the
envelope was raided by a move or by a spend.

B<A pre-funded pot ramps only the gap.> Start the same plan with
£20,000 already carried in and C<base> is 2,000,000: milestones are
C<2000000 + 333333·i>, so the first ask is 333,333 and not 555,555.
Nothing asks the user to re-save money they have already saved.

B<The base is derived, never snapshotted.> It is read out of the view
at the cycle's first period every time the question is asked, so
correcting a transaction dated before the plan started re-derives the
whole schedule on the next repaint — the same recompute-from-facts
rule the engine follows everywhere. And when C<base> is B<above> C<N>
(a pot that was already over its goal when the plan began), the
milestone is clamped to C<N> and the plan asks for nothing, rather
than proposing a negative contribution.

=head3 Repeating goals, and the goal period's outflow

VAT, quarterly, £3,000, first due in the November period, under
calendar months: C<R> is 3 and E is C<2026-11-01>. Stamped in
September, cycle 0 is Sep–Nov with C<k = 3>, so the milestones are
100,000 / 200,000 / 300,000. Cycle 1 is Dec–Feb, cycle 2 is Mar–May,
and there is no terminal state: every period after E belongs to some
cycle.

Paying the bill in November is where the last ruling comes in. The
payment is £3,000 of outflow, so C<available> drops to zero — and
without help, a £3,000 pot that has just done its job would read as a
£3,000 raid for the rest of the month, with C<f> offering to refill it
immediately. So B<in the goal period, the envelope's outflow counts
toward the milestone>:

=begin code :lang<raku>
goal-outflow = max(0, -activity)      # in the goal period only
ask = max(0, 300000 - 0 - 300000)     # = 0 for the rest of November
=end code

In every other period spending still reads as a raid: the same £3,000
spent in October leaves an ask of 200,000, because October is not when
the bill is due and the pot is now empty.

Two consequences worth knowing:

=item B<It is net activity.> A refund landing in the goal period
      reduces the measured outflow, because C<activity> is a signed
      sum. That is the deliberate reading of "outflow": what left the
      envelope this period, net — a £3,000 payment refunded in the
      same period did not leave.
=item B<Pick the period the bill is B<paid> in as the goal period.>
      VAT due on 7 November is a November goal. A payment that lags
      into the next cycle is the one shape this cannot model.

The next cycle's C<base> is whatever is left after the bill, read as
the carry-in of the cycle's first period — so an underpaid quarter
starts the next ramp from below zero and catches up, and an overpaid
one starts it ahead.

=head3 The edges

=item B<Before S> — no ask, no milestone, no cycle. A plan that has
      not started asks for nothing.
=item B<One-shot, past E> — the milestone is C<N> for ever after, so
      the target degrades into "refill to N". The money is meant to
      stay there until it is spent, and if it is spent the envelope
      asks for it back.
=item B<Repeating, past E> — there is no terminal state; C<v> is in
      cycle C<ceil(steps-past-E / R)>.
=item B<E before S> — a goal that was already in the past when the
      plan was stamped. There is no ramp to compute, so the milestone
      is C<N> from S onwards, exactly as a one-shot past its goal.
      Re-stamping (which changing the amount or the goal period does)
      is how a user gets a real schedule back.
=item B<A missing or malformed date> — a C<by_period> row with no
      goal or no stamp cannot be a plan. C<Gateway::Category> refuses
      to write one, so this is the hand-edited-file case, and the
      answer is 0 rather than an exception.

=head2 IT NEVER THROWS

Every sub here answers with a number, a C<Hash> or a string, whatever
it is handed. That is the same ruling as C<Util::Period.label>'s and
for the same reason: these are called from inside C<Selkie::Store>
selectors and from render paths, where an exception takes out the
whole subscription walk rather than one figure. A malformed date, a
category with no id, a viewed period outside the view, a kind the
C<CHECK> constraint should have made impossible — each has a defined
answer above, and none of them is a throw.

The one thing it does B<not> do is guess. "No target", "the plan has
not started" and "there is nothing to derive" all answer 0, because 0
is true of all of them: nothing to fund.

=head1 SUBROUTINES

=item C<target-ask(BudgetView:D $view, Period:D $scheme,
      Category:D $category, Str:D $period --> Int)> — the kind-aware
      underfunded amount for the viewed period, in pence. Never
      negative.
=item C<target-milestone(BudgetView:D $view, Period:D $scheme,
      Category:D $category, Str:D $period --> Int)> — the at-a-glance
      figure for the viewed period: the current milestone for
      C<by_period>, and the target amount itself for the other two
      kinds. 0 when there is no target, or before a plan starts. The
      B<caller> decides how to present it; this answers what the
      number is.
=item C<target-cycle(Period:D $scheme, Category:D $category,
      Str:D $period --> Hash)> — where the viewed period sits in a
      C<by_period> plan: C<start> and C<goal> (period keys), C<index>
      (1-based) and C<of>. An empty C<Hash> for every other kind, for
      a period before the plan starts, and for the two terminal shapes
      (a one-shot past its goal, a goal that was already past when the
      plan was stamped) — none of which is a cycle. Takes no view:
      cycles are scheme arithmetic.
=item C<describe-target(Category:D $category, Period:D $scheme
      --> Str)> — the caption for the rail and the editor, or C<''>
      when there is no target. Money through
      C<Util::Money.format-pence>, so it follows the display locale.

=head1 SEE ALSO

=item L<App::Moneymoor::Model::Category> — the tuple this module
      interprets.
=item L<App::Moneymoor::Gateway::Category> — what may be stored in it.
=item L<App::Moneymoor::Service::Workspace> — C<set-target>, the front
      door that stamps the plan start.
=item L<App::Moneymoor::Service::Budget> — where C<carry-in>,
      C<assigned>, C<activity> and C<available> come from.

=end pod

unit module App::Moneymoor::Service::Target;

use App::Moneymoor::Model::Category;
use App::Moneymoor::Service::Budget;
use App::Moneymoor::Util::Money;
use App::Moneymoor::Util::Period;

#| The storage names of the three kinds, spelled exactly as the
#| C<CHECK> constraint on C<categories.target_kind> does.
#| C<Gateway::Category> writes the same three down for itself: the
#| gateway must not depend on the derivation, and the derivation must
#| not depend on the database.
my constant REFILL    = 'refill';
my constant SET-ASIDE = 'set_aside';
my constant BY-PERIOD = 'by_period';

#| The separator between a by-period caption and its repeat clause.
my constant CAPTION-DOT = ' · ';

# --- internals ------------------------------------------------------

#| C<$n> steps along the sequence from C<$from>. C<Util::Period> has no
#| "advance by N", and adding one would be the wrong place for it: the
#| clamping monthly schemes make stepping the only correct way to move,
#| and this is the only caller that ever needs more than one step.
my sub advance(App::Moneymoor::Util::Period:D $scheme, Str:D $from,
               Int:D $n --> Str) {
    my Str $cursor = $from;
    $cursor = $scheme.next-period($cursor) for ^$n;
    $cursor;
}

#|( Where the viewed period sits in the plan, or an empty C<Hash> when
    it sits in no cycle at all.

    Pure scheme arithmetic — no view, no money. Three shapes come back:

    =item C<%()> — not a by-period target, a malformed tuple, or a
          period before the plan started. Nothing to derive.
    =item C<< %( terminal => True ) >> — the milestone is C<N> and
          there is no ramp: a one-shot goal that is behind us, or a
          goal that was already behind us when the plan was stamped.
    =item the full cycle — C<start>, C<goal>, C<index>, C<of>.

    C<$period> is read as the period containing it, so a caller that
    hands over a date rather than a period key gets the right cycle
    rather than an exception. )
my sub resolve-cycle(App::Moneymoor::Util::Period:D $scheme,
                     App::Moneymoor::Model::Category:D $category,
                     Str $period --> Hash) {
    return %() unless $category.is-by-period;

    my Str $goal-date  = $category.target-period;
    my Str $start-date = $category.target-start;
    # A by-period row without both dates is not a plan. The gateway
    # refuses to write one; a hand-edited file is what this guards.
    return %() unless valid-date($goal-date) && valid-date($start-date)
                   && valid-date($period);

    my Str $v = $scheme.period-of($period);
    my Str $s = $scheme.period-of($start-date);
    my Str $e = $scheme.period-of($goal-date);

    # Fixed-width ISO keys: `lt` on the text is `<` on the dates.
    return %( terminal => True ) if $e lt $s;
    return %() if $v lt $s;

    my Int $repeat = ($category.target-repeat // 0).Int;

    # Cycle 0 is S..E inclusive, so `of` counts S itself: a plan whose
    # goal period is the period it was stamped in is one period long
    # and asks for the whole thing at once.
    if $v le $e {
        return %(
            start => $s,
            goal  => $e,
            index => $scheme.periods-through($s, $v).elems,
            of    => $scheme.periods-through($s, $e).elems,
        );
    }

    return %( terminal => True ) if $repeat < 1;

    # Past the goal, repeating. Count the steps from E and divide: with
    # goal periods at E+R, E+2R, …, the period `$steps` past E is in
    # cycle ceil($steps/R), at 1-based index $steps - ($cycle-1)*R.
    my Int $steps = $scheme.periods-through($e, $v).elems - 1;
    my Int $cycle = ($steps + $repeat - 1) div $repeat;
    %(
        start => advance($scheme, $e, ($cycle - 1) * $repeat + 1),
        goal  => advance($scheme, $e, $cycle * $repeat),
        index => $steps - ($cycle - 1) * $repeat,
        of    => $repeat,
    );
}

#|( The ramp, in integer pence.

    C<floor> comes free: Raku's C<div> on C<Int>s rounds towards -Inf,
    which is what the schedule wants on both signs — a rising plan
    rounds each milestone down (so the ask never runs ahead of the
    line) and a falling one rounds away from asking.

    Two clamps. The last milestone is C<$goal> by fiat rather than by
    division, because C<9 × floor(N/9)> is not C<N> and a plan has to
    end on the number the user typed. And every milestone is capped at
    C<$goal>, which only bites when C<$base> is already above it: a pot
    that starts over its goal is asked for nothing rather than for a
    negative contribution. )
my sub milestone-of(Int:D $goal, Int:D $base, Int:D $index,
                    Int:D $of --> Int) {
    return $goal if $of <= 0 || $index >= $of;
    min($base + (($goal - $base) * $index) div $of, $goal);
}

#| The row the derivation produced for this category in this period —
#| zero-filled when the view has no such period, which is what makes
#| "before the first fact" genuinely zero rather than a special case.
my sub row-of($view, App::Moneymoor::Model::Category:D $category,
              Str:D $period) {
    $view.category($period, $category.id);
}

#| C<target-ask>'s by-period case: resolve the cycle, derive the base
#| from the view, and measure the milestone against what is there.
my sub by-period-ask($view, App::Moneymoor::Util::Period:D $scheme,
                     App::Moneymoor::Model::Category:D $category,
                     Str:D $period, Int:D $goal --> Int) {
    my %cycle = resolve-cycle($scheme, $category, $period);
    return 0 unless %cycle;

    my $row = row-of($view, $category, $period);
    return max(0, $goal - $row.available) if %cycle<terminal>;

    my Int $base = row-of($view, $category, %cycle<start>).carry-in;
    my Int $milestone =
        milestone-of($goal, $base, %cycle<index>, %cycle<of>);

    # The goal period's outflow counts toward the milestone, so paying
    # the bill does not read as a raid for the rest of that period.
    # Net activity, deliberately: a refund in the same period means
    # that much did not leave. Every other period reads a spend as a
    # raid, which is what makes catch-up fire on one.
    my Int $credit = $scheme.period-of($period) eq %cycle<goal>
        ?? max(0, -$row.activity) !! 0;

    max(0, $milestone - $row.available - $credit);
}

# --- the public questions -------------------------------------------

#|( This period's gap: what fully funding this envelope's plan for the
    viewed period would cost, in pence, never negative.

    The function the whole target feature keys on — see THE ONE
    FUNCTION THAT MATTERS. Zero pence is "no target" and answers 0, as
    does a category with no id (nothing to look up) and a plan that has
    not started. )
our sub target-ask(
    App::Moneymoor::Service::Budget::BudgetView:D $view,
    App::Moneymoor::Util::Period:D $scheme,
    App::Moneymoor::Model::Category:D $category,
    Str:D $period,
    --> Int
) is export {
    my Int $goal = ($category.target-pence // 0).Int;
    return 0 unless $goal > 0;
    return 0 without $category.id;

    # The kind is read with `//` and falls back to refill for anything
    # unrecognised: the CHECK constraint and the gateway both make that
    # unreachable, and refill is what a row that lost its kind meant.
    given ($category.target-kind // REFILL) {
        when SET-ASIDE {
            max(0, $goal - row-of($view, $category, $period).assigned);
        }
        when BY-PERIOD {
            by-period-ask($view, $scheme, $category, $period, $goal);
        }
        default {
            max(0, $goal - row-of($view, $category, $period).available);
        }
    }
}

#|( The at-a-glance figure for the viewed period — what a grid column
    headed "Target" holds.

    C<refill> and C<set_aside> answer with their own amount, because
    that B<is> their per-period figure. C<by_period> answers with the
    current milestone, which is the number that moves. 0 when there is
    no target, and 0 before a plan starts: there is no milestone yet.

    How to present it is the caller's business — this answers what the
    number is. )
our sub target-milestone(
    App::Moneymoor::Service::Budget::BudgetView:D $view,
    App::Moneymoor::Util::Period:D $scheme,
    App::Moneymoor::Model::Category:D $category,
    Str:D $period,
    --> Int
) is export {
    my Int $goal = ($category.target-pence // 0).Int;
    return 0 unless $goal > 0;
    return $goal unless $category.is-by-period;
    return 0 without $category.id;

    my %cycle = resolve-cycle($scheme, $category, $period);
    return 0 unless %cycle;
    return $goal if %cycle<terminal>;

    milestone-of($goal, row-of($view, $category, %cycle<start>).carry-in,
                 %cycle<index>, %cycle<of>);
}

#|( Where the viewed period sits in a repeating or one-shot plan:
    C<start> and C<goal> as period keys, C<index> 1-based, and C<of>.
    "Period 3 of 12", for the rail.

    An empty C<Hash> whenever that phrase would be a lie — any kind but
    C<by_period>, a period before the plan starts, a malformed tuple,
    and the two terminal shapes described under THE EDGES. Takes no
    view because a cycle is arithmetic on the scheme alone; only the
    milestone needs money. )
our sub target-cycle(
    App::Moneymoor::Util::Period:D $scheme,
    App::Moneymoor::Model::Category:D $category,
    Str:D $period,
    --> Hash
) is export {
    my %cycle = resolve-cycle($scheme, $category, $period);
    return %() unless %cycle && !%cycle<terminal>;
    %cycle;
}

#|( The target in one line, for the rail's caption and the editor's
    summary. C<''> when there is no target — there is nothing to say,
    and a caller pasting it into a pane gets an empty line rather than
    the word "none".

    The by-period caption names the goal B<period>, through
    C<$scheme.label>, not the stored date: the plan is about a period,
    and the date is only how the period is identified across a scheme
    change. A repeat is a clause on the end rather than a second
    sentence, and it drops the count in the singular for the same
    reason C<Period.describe> does — "every 1 periods" reads as a bug
    in everything else too. )
our sub describe-target(
    App::Moneymoor::Model::Category:D $category,
    App::Moneymoor::Util::Period:D $scheme,
    --> Str
) is export {
    my Int $goal = ($category.target-pence // 0).Int;
    return '' unless $goal > 0;
    my Str $money = format-pence($goal);

    given ($category.target-kind // REFILL) {
        when SET-ASIDE { "Set aside $money each period" }
        when BY-PERIOD {
            my Str $date = $category.target-period;
            return '' unless valid-date($date);
            my Str $label = $scheme.label($scheme.period-of($date));
            return '' if $label eq '';

            my Int $repeat = ($category.target-repeat // 0).Int;
            my Str $every = do given $repeat {
                when 0  { '' }
                when 1  { CAPTION-DOT ~ 'every period' }
                default { CAPTION-DOT ~ "every $repeat periods" }
            };
            "$money by $label$every";
        }
        default { "Refill to $money each period" }
    }
}
