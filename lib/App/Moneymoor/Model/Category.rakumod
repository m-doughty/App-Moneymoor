=begin pod

=head1 NAME

App::Moneymoor::Model::Category - an envelope (or one of the two
system rows that look like one).

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Model::Category;

my $groceries = App::Moneymoor::Model::Category.new(
    name     => 'Groceries',
    group-id => $bills-group-id,
);

my $c = App::Moneymoor::Model::Category.new-from-row(%row);

if $c.is-payment {
    say "payment envelope for account { $c.payment-account-id }";
}

# Envelopes are the categories you can assign to:
my @envelopes = @categories.grep(*.is-envelope);

=end code

=head1 DESCRIPTION

C<kind> is the whole story:

=item C<standard> — an ordinary envelope. Assign to it, spend from
      it, roll it over.
=item C<payment> — the payment envelope of one credit account
      (C<payment-account-id>). It holds the cash you have set aside to
      pay that card. Created automatically with the account and
      deleted with it; the engine moves money into it whenever you
      spend on the card from a funded category. You can also assign to
      it directly (that is how you fund pre-existing debt), and it is
      the one envelope whose negative balance carries into next month
      instead of being written off — see
      C<App::Moneymoor::Service::Budget>.
=item C<rta> — the single system row that inflows are categorized to
      ("Ready to Assign"). It is not an envelope: it has no carry, no
      assignments (C<Gateway::Assignment> rejects them), and it never
      appears in a budget month's category rows. Its balance is
      computed by rule 4 of the budget semantics.

C<hidden> retires an envelope from pickers while keeping its history
and its money. Deleting a category with history is refused by the
gateway (and by an C<ON DELETE RESTRICT> foreign key on C<splits>) —
a deleted category would rewrite the past.

=head1 ATTRIBUTES

=item C<id> — primary key; absent on a not-yet-inserted row.
=item C<group-id> — FK to C<category_groups.id>; may be null (the
      C<rta> row is ungrouped).
=item C<name> — required.
=item C<kind> — C<standard> / C<payment> / C<rta>; default
      C<standard>.
=item C<payment-account-id> — set only on C<payment> rows; the credit
      account this envelope pays.
=item C<sort-order> — display order; default 0.
=item C<hidden> — Bool; default False.
=item C<carry-overspend> — Bool; default False. Which of rule 3's two
      cash-overspending rules this envelope is on — see CARRYING A
      NEGATIVE.
=item C<target-pence> — the target amount, in pence; default 0.
=item C<target-kind> — C<refill> / C<set_aside> / C<by_period>;
      default C<refill>.
=item C<target-period> — C<by_period> only: the goal, as a
      C<'YYYY-MM-DD'> date read as the period containing it. C<Str>
      type object otherwise.
=item C<target-start> — C<by_period> only: the stamped plan start,
      same shape. C<Str> type object otherwise.
=item C<target-repeat> — C<by_period> only: C<0> for a one-shot goal,
      C<R E<gt>= 1> for a goal that repeats every C<R> periods.

=head1 CARRYING A NEGATIVE

Rule 3 of L<App::Moneymoor::Service::Budget> has always known two ways
to end a period in the red, and until now which one you got was decided
by C<kind>: a payment envelope carried its negative into the next
period, and every other envelope reset to zero and had the shortfall
charged against every subsequent period's Ready to Assign. That second
rule is the right default — it is the one that stops you spending your
way out of a hole by ignoring it — but it is wrong for the envelope you
deliberately run negative: a reimbursable expense, a shared bill you
front and get back, a pot that is meant to be square by the time the
money lands rather than by the end of the month.

C<carry-overspend> is that choice, per envelope:

=item B<False> (the default) — cash overspending resets the envelope to
      zero at the boundary and Ready to Assign carries the charge.
=item B<True> — the negative available carries forward intact, exactly
      as a payment envelope's does, and B<nothing> is charged to Ready
      to Assign. The hole stays visible in the envelope it was dug in
      until money is assigned to fill it.

Three properties fall out of that, and each is deliberate:

=item B<False is what every legacy row already meant.> The column is
      C<NOT NULL DEFAULT 0>, so a budget file written before it existed
      reads as the forcing rule it was derived under, with no backfill
      — the same argument the target columns' migration makes.
=item B<Cash only.> Credit overspending is written off at the boundary
      whatever this flag says: that debt is on the card, and carrying
      it in the envelope B<as well> would count it twice against the
      master invariant.
=item B<It is a fact, not a preference.> C<compute> re-derives every
      period from the facts on each call, so turning the flag on
      re-derives the past under the new rule — including Ready to
      Assign figures for periods that have already been and gone. That
      is the honest reading of "this envelope was always allowed to run
      negative", and the only one a pure derivation can give.

C<carries-negative> is the predicate the engine actually asks, because
the two ways of carrying are one rule from rule 3's point of view: a
payment envelope carries by kind, a standard envelope by flag.

=head1 THE TARGET

A target is what an envelope wants, and C<target-kind> says in what
sense it wants it. C<target-pence> is the amount in all three cases;
what it is measured B<against> is the difference:

=item C<refill> — "available should be C<target-pence> each budget
      period". The v0.1 behaviour, the default, and what every budget
      file written before the kinds existed reads as, with no
      migration: carry-in counts, so an envelope you did not empty
      asks for less.
=item C<set_aside> — "put C<target-pence> in each budget period,
      whatever the balance". Measured against what was B<assigned>
      this period, deliberately: a Christmas fund that is meant to
      grow must not fall silent because last month's money is still
      sitting in it.
=item C<by_period> — "reach C<target-pence> available by the period
      containing C<target-period>", ramped in equal steps from the
      period containing C<target-start>, repeating every
      C<target-repeat> periods when that is above zero.

The semantics — the milestone schedule, the base the ramp starts
from, the goal period's outflow credit — belong to
L<App::Moneymoor::Service::Target>, which derives them from a
C<BudgetView> and a period scheme. This class only carries the tuple.
Three rulings live in it:

=item B<Zero pence is no target>, not a target of nothing. The column
      is C<NOT NULL DEFAULT 0>, so no read site has to distinguish a
      NULL from a zero, and C<has-target> is the one place the
      sentinel is interpreted. Because it means "no target", it is
      only legal alongside the default kind: C<Gateway::Category>
      refuses a C<set_aside> or C<by_period> target of nothing.
=item B<It is a view-layer fact.> C<Service::Budget> has never heard
      of any of it and never will: "underfunded" is derived where it
      is drawn, from figures the engine already produced.
      A target cannot move a penny by itself — only the assign
      dialog's C<=> and the grid's C<f> can, and both do it through
      an ordinary assignment.
=item B<Standard envelopes only.> A payment envelope's figure is the
      card's balance and Ready to Assign is not an envelope at all,
      so C<Gateway::Category> refuses a target on either — the same
      refusal it gives every other field change on a system row.

=head1 METHODS

=item C<new-from-row(%row)> — build from a DBIish row hash.
=item C<is-standard> / C<is-payment> / C<is-rta> — kind predicates.
=item C<has-target> — True when C<target-pence> is above zero.
=item C<is-refill> / C<is-set-aside> / C<is-by-period> — target-kind
      predicates. They read the kind alone: an envelope with no target
      is still C<is-refill>, because C<refill> is the shape a
      target-less row has. Ask C<has-target> first.
=item C<is-system> — True for C<payment> and C<rta> rows (the ones
      the engine owns and the user may not delete).
=item C<is-envelope> — True for C<standard> and C<payment>: the
      categories that carry a balance and may be assigned to.
=item C<carries-negative> — True when a negative available carries into
      the next period instead of resetting to zero: by kind for a
      payment envelope, by C<carry-overspend> for a standard one. The
      one question rule 3 asks — see CARRYING A NEGATIVE.

=end pod

unit class App::Moneymoor::Model::Category;

has Int  $.id;
has Int  $.group-id;
has Str  $.name is required;
has Str  $.kind = 'standard';
has Int  $.payment-account-id;
has Int  $.sort-order = 0;
has Bool $.hidden = False;

#| Which of rule 3's two cash-overspending rules this envelope is on —
#| see CARRYING A NEGATIVE. False is both the default and what a row
#| written before the column existed means, which is what makes the
#| migration free: the forcing rule is the one the whole file was
#| derived under.
has Bool $.carry-overspend = False;

has Int  $.target-pence = 0;

#| Which sense the target is meant in — see THE TARGET. 'refill' is
#| both the default and what a row written before the kinds existed
#| means, which is what makes the migration free.
has Str  $.target-kind = 'refill';

#| by_period only, and undefined on every other kind: the goal date and
#| the stamped plan-start date, each read as B<the period containing
#| it> rather than as a period key. Storing dates is deliberate — a
#| budget that changes its period scheme re-derives its plan under the
#| new windows instead of holding a key that no longer names a period.
has Str  $.target-period;
has Str  $.target-start;

#| by_period only: 0 is a one-shot goal, R >= 1 puts goal periods at
#| E, E+R, E+2R, … Counted in B<periods>, not months — quarterly VAT
#| is "every 3" under monthly/1 and something else under weekly/4, and
#| that mismatch is the schemes', not this column's.
has Int  $.target-repeat = 0;

method new-from-row(%row --> App::Moneymoor::Model::Category) {
    App::Moneymoor::Model::Category.new(
        id                 => %row<id>,
        group-id           => %row<group_id> // Int,
        name               => %row<name> // '',
        kind               => %row<kind> // 'standard',
        payment-account-id => %row<payment_account_id> // Int,
        sort-order         => (%row<sort_order> // 0).Int,
        hidden             => ?(%row<hidden> // 0),
        # The `//` defaults cover two cases at once: a legacy row read
        # before the additive migrations have run, and a caller
        # building a row hash by hand. For the target tuple they are
        # also the "no target of this kind" values, so a file from
        # before the kinds existed reads as the refill target it was;
        # for carry_overspend the default is the forcing rule, which is
        # the rule every such file was already derived under.
        carry-overspend    => ?(%row<carry_overspend> // 0),
        target-pence       => (%row<target_pence> // 0).Int,
        target-kind        => (%row<target_kind> // 'refill').Str,
        target-period      => (%row<target_period>.defined
                                   ?? %row<target_period>.Str !! Str),
        target-start       => (%row<target_start>.defined
                                   ?? %row<target_start>.Str !! Str),
        target-repeat      => (%row<target_repeat> // 0).Int,
    );
}

method is-standard(--> Bool) { $!kind eq 'standard' }
method is-payment(--> Bool)  { $!kind eq 'payment'  }
method is-rta(--> Bool)      { $!kind eq 'rta'      }
method is-system(--> Bool)   { $!kind ne 'standard' }
method is-envelope(--> Bool) { $!kind ne 'rta'      }

#| Does a negative available carry into the next period, or reset to
#| zero with Ready to Assign charged for it? The one question rule 3
#| asks, and the reason it is a method rather than two tests at the call
#| site: a payment envelope carries by kind and a standard envelope by
#| flag, but the engine is doing the same thing in both cases. See
#| CARRYING A NEGATIVE.
method carries-negative(--> Bool) { $!kind eq 'payment' || ?$!carry-overspend }

#| True when this envelope wants a figure at all. Zero is the "no
#| target" value, so this is the one place the sentinel is read and
#| every caller asks the question by name.
method has-target(--> Bool)  { ($!target-pence // 0) > 0 }

# The kind predicates read the kind and nothing else: a row with no
# target still has a kind ('refill', the default), so these say what
# shape the target would be, not whether there is one. Callers pair
# them with `has-target`, exactly as the budget grid does.
method is-refill(--> Bool)     { ($!target-kind // 'refill') eq 'refill'     }
method is-set-aside(--> Bool)  { ($!target-kind // 'refill') eq 'set_aside'  }
method is-by-period(--> Bool)  { ($!target-kind // 'refill') eq 'by_period'  }
