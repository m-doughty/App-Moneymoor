=begin pod

=head1 NAME

App::Moneymoor::Service::Budget - the pure envelope-budgeting
derivation, and the specification of what every number means.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Service::Budget;

my $view = compute(
    :@accounts, :@categories, :@transactions, :@splits, :@assignments,
    through-period => '2026-04-01',
);

say $view.periods;                      # ('2026-03-01', '2026-04-01')
say $view.rta('2026-03-01');            # Ready to Assign, in pence

my $groceries = $view.category('2026-03-01', $groceries-id);
say $groceries.assigned;                # 40000
say $groceries.activity;                # -37250
say $groceries.available;               # 2750
say $groceries.flags;                   # ()

# Why does the Visa payment envelope hold £372.50?
.say for $view.moves-for('2026-03-01', category-id => $visa-payment-id);
# 2026-03-01 card-coverage 12 -> 4 £120.00
# 2026-03-01 card-coverage 13 -> 4 £252.50

# The engine checks itself:
say $view.invariant-errors;             # ()

=end code

=head1 DESCRIPTION

C<compute> is a pure function. It takes lists of facts — accounts,
categories, transactions, splits, assignments — and returns a
C<BudgetView>. It touches no database, no clock and no filesystem,
which is what lets the property suite hammer it with hundreds of
randomly generated budgets in a couple of seconds.

Nothing derived is ever stored. Balances, activity, available,
Ready to Assign and credit-card payment moves are all recomputed from
the facts on every call. A stored derived value is a cache, and a
cache that disagrees with the transactions that produced it is worse
than no budget at all.

All money is C<Int> pence.

=head2 THE PERIOD IS THE KEYING DIMENSION

Everything below is derived B<per period>, and a period is named by
its own start date as a C<'YYYY-MM-DD'> string: C<'2026-03-01'>,
C<'2026-08-14'>. C<App::Moneymoor::Util::Period> owns what a period is
— a calendar month, a month anchored on payday, or an every-N-weeks
pay window — and C<compute> takes one as C<:$scheme>.

The algebra that follows does not care. Rollover, coverage, the carry
chain and Ready to Assign depend on exactly two properties of the
keying dimension:

=item B<Facts bucket into exactly one period each>, which is
      C<$scheme.period-of($date)>.
=item B<Periods are totally ordered, and the order is the order of the
      keys as text.> Zero-padded ISO dates sort as strings exactly as
      they sort as dates, so the derivation compares, sorts and hashes
      period keys without parsing them and without consulting the
      scheme.

Nothing here reads a period's I<length>. That is what makes a
four-weekly budget and a calendar-month budget the same code: the
degenerate case of the general one. Under the default C<monthly/1>
scheme every period start is C<'YYYY-MM-01'>, which is the calendar
month the engine has always derived — the pre-period C<'YYYY-MM'> keys
migrate by appending C<'-01'> and no number changes.

C<:$scheme> defaults to C<Period.default-scheme> (C<monthly/1>), and
in this release every caller takes that default; C<Service::Workspace>
is where a budget's real scheme will be threaded in from.

=head2 THE MASTER INVARIANT

Envelopes partition B<cash>. Every pound in a cash account is either
sitting in an envelope or sitting in Ready to Assign, and no pound is
in two places:

    Σ available + RTA == Σ cash-account balances

That is the headline form, and it holds exactly whenever the budget
has no future-dated assignments and no uncovered credit-card
spending. The general form, which C<BudgetView.invariant-errors>
checks for I<every> period, adds the two terms those features
introduce:

    Σ available(p) + RTA(p) + assigned-in-periods-after(p)
                            + credit-overspend(p)
        == cash-balance(p)

=item C<assigned-in-periods-after(p)> — money you have already promised
      to a future period. Rule 4 removes it from Ready to Assign in
      every period, so it has to be added back to see the cash again.
=item C<credit-overspend(p)> — card spending in period C<p> that no
      category could fund. It is debt, not cash, and rule 3 writes it
      off at the period boundary, so it only ever appears in its own
      period.

Credit card accounts are B<not> on the right-hand side. Their balance
is debt; the cash you have set aside to pay it lives in the card's
payment envelope, which I<is> on the left-hand side.

=head1 THE FOUR RULES

Periods are derived in order, oldest first, each one starting from the
previous period's carry. Within a period the order is: rule 1 (what
each envelope has), rule 2 (card coverage), rule 3 (what carries),
rule 4 (Ready to Assign).

=head2 RULE 1 — PER-CATEGORY AVAILABLE

    available = carry-in + assigned + activity + moved-in - moved-out

C<activity> is the sum of every split against the category, dated in
this period, on an B<on-budget> account — cash and credit alike. It is
the "Activity" column of a budget screen. Splits on tracking accounts
are ignored: tracking accounts are off budget.

C<moved-in> / C<moved-out> are the derived credit-card moves of rule
2, and are zero for every ordinary category.

B<Worked example.> Groceries carries £27.50 in from the period before.
In this one you assign £400 and spend £372.50 (£300 on the debit card,
£72.50 on the Visa):

    carry-in    27.50
    assigned   400.00
    activity  -372.50
    ---------------------
    available   55.00

=head2 RULE 2 — CREDIT-CARD COVERAGE

Spending on a credit card does not move cash, but it does commit
cash: the money has to stay put until the statement is paid. So when
you spend on a card from a funded category, the engine moves that
money from the category into the card's B<payment envelope>. This is
derived on every recompute and never stored.

For each category, in each period:

    S       = total card spending charged to the category this period
    base    = carry-in + assigned + activity + S - moved-out
              (i.e. everything the category has, before its card
               spending is taken out)
    covered = min(S, max(0, base))

C<covered> is then distributed across that period's card-spending
splits in C<(date, transaction id, split id)> order — greedily, each
split taking as much of the remaining coverage as it can — so every
move points at a specific transaction and a specific card. Each
produces a C<Move> from the category to that card's payment envelope.

Taking the coverage from the period's totals rather than from the
running balance at the instant of each purchase is deliberate: it is
what makes the derivation independent of the order facts arrive in,
and it is the only definition under which the master invariant
survives rule 3 (a mid-period refund that fills an overspent category
must retroactively fund the card spending it just paid for). The
I<distribution> is still walked in date order, so the Move log reads
chronologically.

B<Worked example — full coverage.> Groceries has £400 assigned, £0
carried in, and one £72.50 Visa shop:

    S       =  72.50        base    = 0 + 400 + (-72.50) + 72.50 = 400
    covered = min(72.50, 400) = 72.50

Groceries available £327.50; the Visa payment envelope gains £72.50.
Cash never moved, and £400 is still £400.

B<Worked example — partial coverage.> Same category with only £50
assigned:

    S       =  72.50        base    = 50
    covered = min(72.50, 50) = 50

Groceries available is 50 - 72.50 = B<-£22.50> (overspent, in red);
the Visa payment envelope gains £50. The remaining £22.50 is
B<credit overspending>: real debt on the card that no envelope is
funding. See rule 3.

Three more card cases, all derived, all logged as moves:

=item B<Refund on a card> (a positive split): the category gets the
      money back as activity, and the payment envelope gives up the
      cash it had reserved — a C<card-refund> move from the payment
      envelope to the category. It is not capped: refunding more than
      you have reserved pushes the payment envelope negative, which
      is flagged (C<payment-negative>) rather than rejected, because
      it is a true statement about your budget.
=item B<Paying the card> (a transfer from a cash account to the
      card): the payment envelope's activity, straight up. Cash goes
      down, the envelope goes down, the debt goes down. Symmetrically,
      a cash advance (card to cash account) raises both.
=item B<An inflow to Ready to Assign recorded on a card> (a positive
      split against the C<rta> category): the money lands on the card
      rather than in the bank, so it reduces debt instead of raising
      cash. Ready to Assign rises and the payment envelope falls by
      the same amount — a C<card-inflow-to-rta> move releasing the
      cash that was reserved for the debt it just cancelled. This is
      the only treatment consistent with the master invariant: adding
      it to the payment envelope instead would create envelope money
      that no cash account backs.

=head2 RULE 3 — ROLLOVER

At the period boundary each envelope's available becomes the next
period's carry-in, with negative balances split into two very
different kinds of overspending. What that split is depends on one
property of the envelope — whether it B<carries a negative>, which
C<Model::Category.carries-negative> answers:

    credit-overspend = S - covered          (uncovered card spending)
    cash-overspend   = carries ?? 0 !! max(0, -base)
    carry-out        = available + credit-overspend + cash-overspend

=item B<Credit overspending> is written off at the boundary, whatever
      kind of envelope it happened in. The debt stays on the card —
      that is what makes it debt — and no envelope and no future Ready
      to Assign is charged for it. The category is flagged
      C<credit-overspend> for the period it happened in.
=item B<Cash overspending> is money you spent that you did not have,
      and it is the half this rule has two answers for.

B<The forcing rule> is the default and covers every envelope unless it
has been told otherwise: the category resets to zero and the next
period's Ready to Assign is reduced by exactly that amount, in every
subsequent period (rule 4 subtracts the running total). You cannot
spend your way out of a hole by ignoring it. The row is flagged
C<cash-overspend>.

B<Carrying> is the other: the negative available becomes the next
period's carry-in intact, and B<nothing> is charged to Ready to Assign.
There is no cash overspending on such an envelope by definition — the
hole was not written off, so it does not need paying for a second time
— which is why C<cash-overspend> is zero and the row is flagged
C<carried-negative> instead. Two kinds of envelope carry:

=item B<Payment envelopes>, always and by kind. A negative payment
      envelope means "you owe more on this card than you have set
      aside", which is precisely the thing you want to keep seeing
      until you fix it. Its flag is C<payment-negative> rather than
      C<carried-negative>, because the two states read differently to a
      user even though the arithmetic is identical: one is a card you
      are behind on, the other is a choice you made about an envelope.
=item B<Standard envelopes with C<carry-overspend> set>, which is that
      choice — for the envelope you deliberately run negative, like a
      reimbursable expense. It is a per-envelope flag with no default
      but False, so a budget file that has never heard of it behaves
      exactly as it did. See L<App::Moneymoor::Model::Category>.

C<compute> is a pure derivation over the facts, so the flag is
B<retroactive> by construction: turning it on re-derives every period
under the carrying rule, past Ready to Assign figures included. That is
the honest reading of "this envelope was always allowed to run
negative", and there is no other one available to a function that
stores nothing.

B<Worked example.> The partial-coverage Groceries above ends the
period at -£22.50, all of it uncovered card spending:

    credit-overspend = 72.50 - 50 = 22.50
    cash-overspend   = max(0, -50) = 0
    carry-out        = -22.50 + 22.50 + 0 = 0

The next period's Groceries starts at zero and Ready to Assign is
untouched. Had the same £72.50 been spent on the debit card, C<S>
would be 0, C<base> would be -22.50, and the whole £22.50 would be
cash overspending — the next period's Ready to Assign £22.50 lighter.

B<Worked example — the same hole, carried.> Give that Groceries row
C<carry-overspend> and spend the £72.50 on the debit card instead:

    credit-overspend = 0
    cash-overspend   = 0                    (it carries)
    carry-out        = -22.50 + 0 + 0 = -22.50

Next period's Groceries starts £22.50 down and Ready to Assign is
untouched in every period. Assigning £22.50 into it fills the hole and
ends the chain; ignoring it leaves the row in the red until you do.

=head2 RULE 4 — READY TO ASSIGN

    RTA(p) = Σ inflow-to-RTA through p
           - Σ assigned in ALL periods, including future ones
           - Σ cash-overspend through the period before p

The middle term is the interesting one. Assignments to future periods
are deducted B<immediately>, from every period's Ready to Assign, not
just from the period they land in. Funding December's council tax in
August works exactly as you would hope: December's envelope has the
money, and August stops offering it to you.

Ready to Assign can go negative. That is not an error — it is the
statement "you have assigned money you do not have", and it is
flagged C<rta-negative> on the period.

B<Worked example.> £1,800 salary arrives in the August period. You
assign £600 there and £300 to December's council tax:

    RTA(2026-08-01) = 1800 - (600 + 300) - 0 = 900
    RTA(2026-12-01) = 1800 - (600 + 300) - 0 = 900   (same money,
                                                      still only spent
                                                      once)

If August's Dining Out then overspends by £40 in cash:

    RTA(2026-09-01) = 1800 - 900 - 40 = 860

=head1 WARNINGS, NOT EXCEPTIONS

C<compute> is total: no fact combination makes it throw. Facts that
cannot be interpreted are skipped and recorded in
C<BudgetView.warnings> — an unknown account or category, a malformed
date, an assignment whose key is not a period start under the scheme,
a transaction whose splits do not sum to its amount, an uncategorized
transaction on an on-budget account, a credit account with no payment
envelope, splits attached to an on-budget transfer.

The gateways make all of these impossible to store; the warnings exist
because C<compute> is also called on hand-built facts (tests, imports,
a future undo buffer) and silently producing a wrong number is the one
outcome a budget cannot tolerate. The assignment case is the sharpest:
a key that is well-formed but is not a start under this scheme — a
row written under a different scheme, or an unmigrated C<'YYYY-MM'> —
would otherwise open a phantom bucket that the totals happily sum
alongside the real ones.

=head1 SUBROUTINES

=item C<compute(:@accounts, :@categories, :@transactions, :@splits,
      :@assignments, Str :$through-period,
      Period :$scheme --> BudgetView)> — the derivation. The five fact
      lists hold C<App::Moneymoor::Model::*> objects (C<Account>,
      C<Category>, C<Transaction>, C<Split>, C<Assignment>); any may be
      empty. C<:$scheme> is an C<App::Moneymoor::Util::Period> and
      defaults to C<monthly/1>, the calendar month.
      C<:$through-period> extends the derived range in either
      direction, so a caller can ask for "the period we are in" even
      when the newest fact is older (or newer); it must itself be a
      period start under C<:$scheme>, and is ignored with a warning
      when it is not. Note that C<compute> never reads the clock —
      deciding which period is "now" is C<Service::Workspace>'s job.
=item C<valid-date(Str $d --> Bool)> — shape B<and> calendar validity
      (C<'2026-02-30'> is False).
=item C<valid-period(Str $p --> Bool)> — the same check under the name
      that says why the engine wants it: a period key is a date,
      because a period is named by its start. Format only —
      B<start-ness needs a scheme>, and callers that hold one ask it
      with C<$scheme.period-of($p) eq $p>.
=item C<period-range(Period:D $scheme, Str $from, Str $to --> Array)>
      — the inclusive run of starts the derivation walks, capped at
      C<MAX-PERIODS> (1200). Empty when C<$to lt $from>; a C<Failure>
      when either endpoint is not a start under C<$scheme>.
      C<Util::Period.periods-through> is the uncapped form — the cap is
      an engine-level typo guard, not a fact about schemes.

=head1 CLASSES

All are plain value objects with no behaviour beyond accessors and
the lookups documented here.

=item C<Move> — C<period>, C<from-category-id>, C<to-category-id>,
      C<amount> (always positive), C<cause>
      (C<card-coverage> / C<card-refund> / C<card-inflow-to-rta>),
      C<account-id>, C<transaction-id>.
=item C<CategoryPeriod> — C<period>, C<category-id>, C<carry-in>,
      C<assigned>, C<activity>, C<moved-in>, C<moved-out>,
      C<available>, C<credit-overspend>, C<cash-overspend>,
      C<carry-out>, C<flags>.
=item C<BudgetPeriod> — C<period>, C<rta>, C<cash-balance>,
      C<assigned-total>, C<assigned-future>, C<credit-overspend-total>,
      C<cash-overspend-total>, C<category-periods>, C<moves>, C<flags>,
      C<category($id)> and C<has-category($id)>. C<category-periods>
      holds only the categories that had something to say that period;
      C<category($id)> answers for any category, with a zero-filled row
      when there is no stored one.
=item C<AccountBalance> — C<account-id>, C<cleared>, C<uncleared>,
      C<working> (cleared + uncleared).
=item C<BudgetView> — C<periods>, C<period($p)>, C<category($p, $id)>,
      C<rta($p)>, C<moves>, C<moves-for($p, :$category-id)>,
      C<account-balances>, C<account-balance($id)>, C<warnings>,
      C<invariant-errors>, C<canonical-digest>.

=head1 SEE ALSO

=item L<App::Moneymoor::Util::Period> — what a period is, and the only
      module that knows.
=item L<App::Moneymoor::Service::Workspace> — loads the facts, owns
      the scheme, and is the only layer that reads the clock.

=end pod

unit module App::Moneymoor::Service::Budget;

use App::Moneymoor::Util::Money;
use App::Moneymoor::Util::Period;

#| One derived, balanced transfer between two categories. Every move
#| is a double entry by construction: `amount` leaves
#| `from-category-id` and arrives at `to-category-id`, so any set of
#| moves sums to zero across the budget.
#|
#| One side of a card move is always a payment envelope, and that is
#| the side the derivation applies explicitly (as `moved-in` /
#| `moved-out` on the envelope's CategoryPeriod). The other side — the
#| spending category, or Ready to Assign — is already embodied in the
#| activity or the inflow that caused the move, which is why applying
#| `moved-out` to it as well would double-count it.
our class Move {
    has Str $.period is required;
    has Int $.from-category-id is required;
    has Int $.to-category-id is required;
    has Int $.amount is required;
    has Str $.cause is required;
    has Int $.account-id;
    has Int $.transaction-id;

    method Str(--> Str) {
        "$!period $!cause { $!from-category-id } -> { $!to-category-id } "
            ~ format-pence($!amount)
    }
    method gist(--> Str) { self.Str }
}

#| One category's row in one period.
our class CategoryPeriod {
    has Str $.period is required;
    has Int $.category-id is required;
    has Int $.carry-in = 0;
    has Int $.assigned = 0;
    has Int $.activity = 0;
    has Int $.moved-in = 0;
    has Int $.moved-out = 0;
    has Int $.available = 0;
    has Int $.credit-overspend = 0;
    has Int $.cash-overspend = 0;
    has Int $.carry-out = 0;
    has Str @.flags;

    method is-overspent(--> Bool) { $!available < 0 }
    method has-flag(Str:D $f --> Bool) { @!flags.first({ $_ eq $f }).defined }
}

#| An account's derived balances over the whole fact set.
our class AccountBalance {
    has Int $.account-id is required;
    has Int $.cleared = 0;
    has Int $.uncleared = 0;
    method working(--> Int) { $!cleared + $!uncleared }
}

#| One period of the budget.
our class BudgetPeriod {
    has Str $.period is required;
    has Int $.rta = 0;
    has Int $.cash-balance = 0;
    has Int $.assigned-total = 0;
    has Int $.assigned-future = 0;
    has Int $.credit-overspend-total = 0;
    has Int $.cash-overspend-total = 0;
    has CategoryPeriod @.category-periods;
    has Move @.moves;
    has Str @.flags;

    has %!by-category;

    submethod TWEAK() {
        %!by-category{ .category-id } = $_ for @!category-periods;
    }

    #| The category's row for this period. A category with no money, no
    #| history and no carry has no stored row — a budget with forty
    #| categories and five years of periods would otherwise be mostly
    #| zeroes — so this answers with a zero-filled row rather than a
    #| type object. "This category has nothing this period" is a true
    #| statement, and it is the one every caller wants; use
    #| C<has-category> when the distinction matters.
    method category(Int:D $id --> CategoryPeriod) {
        %!by-category{$id}
            // CategoryPeriod.new(period => $!period, category-id => $id)
    }

    #| True when the period has a stored row for this category, i.e. the
    #| category had something to say that period.
    method has-category(Int:D $id --> Bool) {
        %!by-category{$id}.defined
    }

    #| `.sum` rather than a `[+] …, 0` reduction: the reduction form
    #| numifies the Seq when a second term is present, quietly
    #| returning the row count instead of the total.
    method available-total(--> Int) {
        @!category-periods.map(*.available).sum
    }

    method has-flag(Str:D $f --> Bool) { @!flags.first({ $_ eq $f }).defined }
}

#| The whole derivation: every period, every category row, every move,
#| plus account balances and any facts that had to be skipped.
our class BudgetView {
    has Str @.periods;
    has BudgetPeriod @.budget-periods;
    has Move @.moves;
    has Str @.warnings;
    has %.account-balances;

    has %!by-period;

    submethod TWEAK() {
        %!by-period{ .period } = $_ for @!budget-periods;
    }

    method period(Str:D $p --> BudgetPeriod) { %!by-period{$p} // BudgetPeriod }

    method category(Str:D $p, Int:D $id --> CategoryPeriod) {
        my $bp = self.period($p);
        $bp.defined
            ?? $bp.category($id)
            !! CategoryPeriod.new(period => $p, category-id => $id)
    }

    method rta(Str:D $p --> Int) {
        my $bp = self.period($p);
        $bp.defined ?? $bp.rta !! 0
    }

    method account-balance(Int:D $id --> AccountBalance) {
        %!account-balances{$id} // AccountBalance.new(account-id => $id)
    }

    #| Every move in a period, optionally narrowed to the ones touching
    #| one category (either side). This is the "explain this number"
    #| entry point: a payment envelope's balance is its assignments
    #| plus its activity plus exactly these.
    method moves-for(Str:D $p, Int :$category-id --> Array) {
        my @in-period = @!moves.grep({ .period eq $p });
        return @in-period.Array without $category-id;
        @in-period.grep({
            .from-category-id == $category-id || .to-category-id == $category-id
        }).Array;
    }

    #| The master invariant, checked per period in its general form.
    #| Returns an empty Array when the derivation is sound; each entry
    #| names the period and the discrepancy in pence.
    method invariant-errors(--> Array) {
        my Str @errors;
        for @!budget-periods -> $bp {
            my Int $lhs = $bp.available-total + $bp.rta
                        + $bp.assigned-future + $bp.credit-overspend-total;
            next if $lhs == $bp.cash-balance;
            @errors.push(
                "{ $bp.period }: available+rta+future-assigned+credit-overspend "
                ~ "= { $lhs } but cash balance = { $bp.cash-balance } "
                ~ "(off by { $lhs - $bp.cash-balance })"
            );
        }
        @errors.Array;
    }

    #| A stable textual rendering of the whole view. Two computations
    #| over the same facts must produce byte-identical digests
    #| whatever order the facts arrived in — that property is what the
    #| determinism test asserts, and what makes a diff of two digests
    #| a usable debugging tool.
    method canonical-digest(--> Str) {
        my Str @lines;
        for @!budget-periods -> $bp {
            @lines.push(join('|', 'M', $bp.period, $bp.rta, $bp.cash-balance,
                $bp.assigned-total, $bp.assigned-future,
                $bp.credit-overspend-total, $bp.cash-overspend-total,
                $bp.flags.sort.join(',')));
            for $bp.category-periods -> $cp {
                @lines.push(join('|', 'C', $cp.period, $cp.category-id,
                    $cp.carry-in, $cp.assigned, $cp.activity, $cp.moved-in,
                    $cp.moved-out, $cp.available, $cp.credit-overspend,
                    $cp.cash-overspend, $cp.carry-out,
                    $cp.flags.sort.join(',')));
            }
            for $bp.moves -> $mv {
                @lines.push(join('|', 'V', $mv.period, $mv.cause,
                    $mv.from-category-id, $mv.to-category-id, $mv.amount,
                    $mv.account-id // -1, $mv.transaction-id // -1));
            }
        }
        for %!account-balances.keys.sort({ .Int }) -> $id {
            my $ab = %!account-balances{$id};
            @lines.push(join('|', 'A', $id, $ab.cleared, $ab.uncleared));
        }
        @lines.push(join('|', 'W', $_)) for @!warnings.sort;
        @lines.join("\n");
    }
}

# --- date / period helpers ------------------------------------------

my constant DAYS-IN-MONTH = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

#| Hard ceiling on the number of derived periods: a century of monthly
#| ones, or some twenty-three years of weekly/1 ones. Reached only via
#| a fact with a typo'd date — nobody has a budget that long.
#| C<period-range> stops there and C<compute> records a warning when it
#| truncates.
constant MAX-PERIODS = 1200;

our sub valid-date(Str $d --> Bool) is export {
    return False without $d;
    return False unless $d ~~ / ^ (\d ** 4) '-' (\d ** 2) '-' (\d ** 2) $ /;
    my Int $y = +$0;
    my Int $m = +$1;
    my Int $day = +$2;
    return False unless 1 <= $m <= 12;
    return False unless $day >= 1;
    my Int $limit = DAYS-IN-MONTH[$m - 1];
    # Gregorian leap year: every 4th, except centuries, except every
    # 400th. A budget that accepts 2100-02-29 will happily sort it into
    # a month that has no such day.
    $limit = 29 if $m == 2 && ($y %% 4 && (!($y %% 100) || $y %% 400));
    $day <= $limit;
}

#|( Is C<$p> shaped like a period key at all?

    Format only. A period is named by its own start date, so the shape
    of a key is exactly the shape of a date — which is why this
    delegates rather than duplicating the calendar arithmetic.

    Whether a well-formed key is a real B<start> is a different and
    stronger question, and it cannot be answered without a scheme:
    C<'2026-03-15'> is a start under a fortnightly scheme anchored on
    it and not under C<monthly/1>. Callers that hold a scheme ask it,
    with C<$scheme.period-of($p) eq $p>; the gateways and this module's
    own derivation all do. )
our sub valid-period(Str $p --> Bool) is export { valid-date($p) }

#| Well-formed B<and> a real start under C<$scheme>. Module-private:
#| every caller outside holds a scheme of its own and asks it directly.
my sub is-period-start(App::Moneymoor::Util::Period:D $scheme, Str $p --> Bool) {
    return False unless valid-period($p);
    # period-of throws on input it cannot parse; valid-period has
    # already excluded that, and the `try` costs nothing to be sure.
    my $start = try $scheme.period-of($p);
    $start.defined && $start eq $p;
}

#|( The capped, inclusive run of period starts the derivation iterates.

    C<Util::Period.periods-through> is the uncapped version, and is
    deliberately so: it answers a question about a scheme, and a scheme
    has no opinion about how long a budget may be. The cap belongs
    here, because the thing it defends against is an engine problem —
    a fact dated C<'20226-03-01'> would otherwise ask for eighteen
    thousand years of buckets, and materialising them hangs the caller
    instead of telling it what went wrong. C<compute> warns when the
    range it got back was capped.

    Both endpoints must be starts under C<$scheme>. A range whose ends
    are not on the sequence has no unambiguous meaning, and rounding
    them quietly would hand the derivation a first bucket that is not
    the one it asked for. A backwards range is empty rather than a
    C<Failure>: C<$to lt $from> is a legitimate "nothing to derive". )
our sub period-range(App::Moneymoor::Util::Period:D $scheme,
                     Str $from, Str $to --> Array) is export {
    return fail "Malformed period '{ $from // '(undefined)' }' (expected the "
            ~ "YYYY-MM-DD start of a budget period under { $scheme.gist })"
        unless is-period-start($scheme, $from);
    return fail "Malformed period '{ $to // '(undefined)' }' (expected the "
            ~ "YYYY-MM-DD start of a budget period under { $scheme.gist })"
        unless is-period-start($scheme, $to);

    my Str @periods;
    my Str $cursor = $from;
    # Fixed-width ISO keys: `le` on the text is `<=` on the dates.
    while $cursor le $to {
        @periods.push($cursor);
        last if @periods.elems >= MAX-PERIODS;
        $cursor = $scheme.next-period($cursor);
    }
    @periods.Array;
}
# --- the derivation -------------------------------------------------

our sub compute(
    :@accounts     = (),
    :@categories   = (),
    :@transactions = (),
    :@splits       = (),
    :@assignments  = (),
    Str :$through-period,
    App::Moneymoor::Util::Period :$scheme =
        App::Moneymoor::Util::Period.default-scheme,
    --> BudgetView
) is export {
    my Str @warnings;

    # ---- index the facts -------------------------------------------
    my %account-by-id;
    for @accounts -> $a {
        unless $a.id.defined {
            @warnings.push("account '{ $a.name }' has no id — skipped");
            next;
        }
        %account-by-id{ $a.id } = $a;
    }

    my %category-by-id;
    my Int $rta-id;
    my %payment-cat-of-account;
    for @categories.sort({ .id // 0 }) -> $c {
        unless $c.id.defined {
            @warnings.push("category '{ $c.name }' has no id — skipped");
            next;
        }
        %category-by-id{ $c.id } = $c;
        if $c.is-rta {
            if $rta-id.defined {
                @warnings.push(
                    "multiple 'rta' categories ({ $rta-id } and { $c.id }); "
                    ~ "using { $rta-id }");
            } else {
                $rta-id = $c.id;
            }
        }
        if $c.is-payment {
            if $c.payment-account-id.defined {
                %payment-cat-of-account{ $c.payment-account-id } = $c.id;
            } else {
                @warnings.push(
                    "payment category { $c.id } has no payment_account_id");
            }
        }
    }
    # Only worth saying when there are categories at all: an empty
    # fact set is legitimately empty, not misconfigured.
    @warnings.push(
        "no 'rta' category in the fact set — inflows cannot be recorded")
        if %category-by-id && !$rta-id.defined;

    my %txn-by-id;
    for @transactions -> $t {
        unless $t.id.defined {
            @warnings.push("transaction with no id — skipped");
            next;
        }
        %txn-by-id{ $t.id } = $t;
    }

    my %splits-by-txn;
    for @splits -> $s {
        unless $s.transaction-id.defined {
            @warnings.push("split { $s.id // '(no id)' } has no transaction — skipped");
            next;
        }
        %splits-by-txn{ $s.transaction-id }.push($s);
    }
    for %splits-by-txn.keys -> $k {
        %splits-by-txn{$k} = %splits-by-txn{$k}.sort({ .id // 0 }).Array;
    }

    # ---- per-period accumulators -----------------------------------
    # Nested plain hashes keyed period -> bucket -> category-id. Reads
    # go through the `// 0` idiom, which does not autovivify.
    my %assigned;         # period => cat => Int
    my %activity;         # period => cat => Int   (YNAB "Activity")
    my %card-spend;       # period => cat => Int   (S, positive)
    my %moved-out;        # period => cat => Int   (payment releases)
    my %card-outflows;    # period => cat => Array of %(...)
    my %rta-inflow;       # period => Int
    my %cash-delta;       # period => Int
    my %moves-by-period;  # period => Array of Move
    my %account-cleared;  # account-id => Int
    my %account-uncleared;

    my sub emit-move(Str:D $period, Int:D $from, Int:D $to, Int:D $amount,
                     Str:D $cause, Int :$account-id, Int :$transaction-id) {
        return if $amount == 0;
        # Moves always read forwards; a negative amount is the same
        # move with its endpoints swapped.
        my ($f, $t, $a) = $amount > 0 ?? ($from, $to, $amount)
                                      !! ($to, $from, -$amount);
        %moves-by-period{$period}.push(Move.new(
            period => $period, from-category-id => $f, to-category-id => $t,
            amount => $a, cause => $cause,
            account-id => $account-id, transaction-id => $transaction-id,
        ));
    }

    # ---- walk the transactions -------------------------------------
    my %warned-no-payment-cat;

    for @transactions.sort({ (.date, .id // 0) }) -> $t {
        next unless $t.id.defined;

        my $account = %account-by-id{ $t.account-id };
        without $account {
            @warnings.push(
                "transaction { $t.id } references unknown account "
                ~ "{ $t.account-id } — skipped");
            next;
        }

        unless valid-date($t.date) {
            @warnings.push(
                "transaction { $t.id } has malformed date '{ $t.date }' — skipped");
            next;
        }
        # The bucket. `valid-date` above has already ruled out
        # everything `period-of` throws on, so the `try` is a belt on
        # top of a brace: a fact that reaches it anyway is skipped with
        # a warning rather than taking the whole derivation down.
        my Str $p = try $scheme.period-of($t.date);
        without $p {
            @warnings.push(
                "transaction { $t.id } date '{ $t.date }' cannot be bucketed "
                ~ "under { $scheme.gist } — skipped");
            next;
        }

        # Account balances count every account type, including
        # tracking: they are a statement about the account, not about
        # the budget.
        if $t.is-cleared {
            %account-cleared{ $t.account-id } =
                (%account-cleared{ $t.account-id } // 0) + $t.amount;
        } else {
            %account-uncleared{ $t.account-id } =
                (%account-uncleared{ $t.account-id } // 0) + $t.amount;
        }

        unless $account.is-on-budget {
            # Off budget: the transaction counts towards the account's
            # balance (done above) and stops there. Splits on such a
            # transaction would move an envelope without moving any
            # cash, so they are ignored — loudly.
            @warnings.push(
                "transaction { $t.id } on tracking account { $t.account-id } "
                ~ "has splits — they are ignored because the account is off "
                ~ "budget")
                if (%splits-by-txn{ $t.id } // []).elems;
            next;
        }

        # A credit account with no payment envelope cannot participate
        # in the budget without breaking the invariant (its spending
        # would have nowhere to reserve cash). Treat it as off-budget
        # and say so, once.
        my Int $payment-cat;
        if $account.is-credit {
            $payment-cat = %payment-cat-of-account{ $t.account-id };
            without $payment-cat {
                unless %warned-no-payment-cat{ $t.account-id } {
                    %warned-no-payment-cat{ $t.account-id } = True;
                    @warnings.push(
                        "credit account { $t.account-id } has no payment "
                        ~ "category — its transactions are ignored");
                }
                next;
            }
        }

        %cash-delta{$p} = (%cash-delta{$p} // 0) + $t.amount
            if $account.is-cash;

        my @txn-splits = (%splits-by-txn{ $t.id } // []).List;

        # ---- transfers between two on-budget accounts --------------
        my $peer = $t.transfer-peer-id.defined
            ?? %txn-by-id{ $t.transfer-peer-id } !! Nil;
        my $peer-account = $peer.defined
            ?? %account-by-id{ $peer.account-id } !! Nil;
        if $t.transfer-peer-id.defined && !$peer.defined {
            @warnings.push(
                "transaction { $t.id } points at missing transfer peer "
                ~ "{ $t.transfer-peer-id }");
        }

        if $peer.defined && $peer-account.defined && $peer-account.is-on-budget {
            if @txn-splits {
                @warnings.push(
                    "transfer { $t.id } between on-budget accounts has splits "
                    ~ "— they are ignored");
            }
            # Money moving between two on-budget accounts is invisible
            # to envelopes, with one derived exception: the leg on a
            # credit account moves that card's payment envelope, because
            # paying a card spends the cash you reserved for it (and a
            # cash advance does the reverse).
            if $account.is-credit {
                %activity{$p}{$payment-cat} =
                    (%activity{$p}{$payment-cat} // 0) - $t.amount;
            }
            next;
        }

        # ---- categorized transactions ------------------------------
        unless @txn-splits {
            @warnings.push(
                "transaction { $t.id } on on-budget account { $t.account-id } "
                ~ "has no splits — it does not reach the budget")
                unless $t.amount == 0;
            next;
        }

        my Int $split-sum = [+] @txn-splits.map(*.amount);
        @warnings.push(
            "transaction { $t.id } splits sum to { $split-sum } but the "
            ~ "transaction is { $t.amount }")
            unless $split-sum == $t.amount;

        for @txn-splits -> $s {
            my $category = %category-by-id{ $s.category-id };
            without $category {
                @warnings.push(
                    "split { $s.id // '(no id)' } references unknown category "
                    ~ "{ $s.category-id } — skipped");
                next;
            }
            next if $s.amount == 0;

            my Int $cat-id = $s.category-id;

            if $account.is-cash {
                if $category.is-rta {
                    %rta-inflow{$p} = (%rta-inflow{$p} // 0) + $s.amount;
                } else {
                    %activity{$p}{$cat-id} =
                        (%activity{$p}{$cat-id} // 0) + $s.amount;
                }
                next;
            }

            # ---- on a credit card ----------------------------------
            if $category.is-rta {
                # Income landing on the card: Ready to Assign rises,
                # and the payment envelope releases the cash it had
                # reserved for the debt this inflow just cancelled.
                %rta-inflow{$p} = (%rta-inflow{$p} // 0) + $s.amount;
                %moved-out{$p}{$payment-cat} =
                    (%moved-out{$p}{$payment-cat} // 0) + $s.amount;
                emit-move($p, $payment-cat, $rta-id, $s.amount,
                    'card-inflow-to-rta',
                    account-id => $t.account-id, transaction-id => $t.id);
                next;
            }

            %activity{$p}{$cat-id} = (%activity{$p}{$cat-id} // 0) + $s.amount;

            if $s.amount > 0 {
                # Refund on the card: the category gets its money back
                # and the payment envelope gives up the cash it was
                # holding for that purchase. Uncapped by design.
                %moved-out{$p}{$payment-cat} =
                    (%moved-out{$p}{$payment-cat} // 0) + $s.amount;
                emit-move($p, $payment-cat, $cat-id, $s.amount, 'card-refund',
                    account-id => $t.account-id, transaction-id => $t.id);
            } else {
                my Int $magnitude = -$s.amount;
                %card-spend{$p}{$cat-id} =
                    (%card-spend{$p}{$cat-id} // 0) + $magnitude;
                %card-outflows{$p}{$cat-id}.push(%(
                    amount         => $magnitude,
                    payment-cat    => $payment-cat,
                    account-id     => $t.account-id,
                    transaction-id => $t.id,
                    split-id       => ($s.id // 0),
                ));
            }
        }
    }

    # ---- assignments -----------------------------------------------
    my Int $assigned-all-periods = 0;
    my %assigned-total-by-period;
    for @assignments.sort({ (.period, .id // 0) }) -> $a {
        # Not merely well-formed: a real start under this scheme. A key
        # that is not one buckets alongside the real ones and invents a
        # phantom bucket the totals then include.
        unless is-period-start($scheme, $a.period) {
            @warnings.push(
                "assignment { $a.id // '(no id)' } has period "
                ~ "'{ $a.period }', which is not a period start under "
                ~ "{ $scheme.gist } — skipped");
            next;
        }
        my $category = %category-by-id{ $a.category-id };
        without $category {
            @warnings.push(
                "assignment { $a.id // '(no id)' } references unknown category "
                ~ "{ $a.category-id } — skipped");
            next;
        }
        if $category.is-rta {
            @warnings.push(
                "assignment { $a.id // '(no id)' } targets the Ready to Assign "
                ~ "category — skipped");
            next;
        }
        %assigned{ $a.period }{ $a.category-id } =
            (%assigned{ $a.period }{ $a.category-id } // 0) + $a.amount;
        %assigned-total-by-period{ $a.period } =
            (%assigned-total-by-period{ $a.period } // 0) + $a.amount;
        $assigned-all-periods += $a.amount;
    }

    # ---- the period range ------------------------------------------
    my Str @fact-periods = (
        |%cash-delta.keys, |%activity.keys, |%card-spend.keys,
        |%rta-inflow.keys, |%moved-out.keys, |%moves-by-period.keys,
        |%assigned.keys,
    ).unique.sort;

    my Str @periods;
    if @fact-periods || $through-period.defined {
        my Str $first = @fact-periods ?? @fact-periods[0]  !! $through-period;
        my Str $last  = @fact-periods ?? @fact-periods[*-1] !! $through-period;
        with $through-period {
            if is-period-start($scheme, $through-period) {
                # Period keys are fixed-width ISO dates, so lexical
                # order is chronological order and `lt` / `gt` need
                # neither a parse nor a scheme.
                $first = $through-period if $through-period lt $first;
                $last  = $through-period if $through-period gt $last;
            } else {
                @warnings.push(
                    "through-period '{ $through-period }' is not a period "
                    ~ "start under { $scheme.gist } — ignored");
                $first = @fact-periods ?? @fact-periods[0]   !! Str;
                $last  = @fact-periods ?? @fact-periods[*-1] !! Str;
            }
        }
        @periods = $first.defined
            ?? period-range($scheme, $first, $last).List !! ();
        @warnings.push(
            "derivation truncated at { MAX-PERIODS } periods starting { $first }")
            if @periods.elems >= MAX-PERIODS;
    }

    # Money promised to periods after each period, for rule 4's
    # "assignments in all periods" behaviour to remain explainable.
    my %assigned-future;
    my Int $suffix = 0;
    for @periods.reverse -> $p {
        %assigned-future{$p} = $suffix;
        $suffix += %assigned-total-by-period{$p} // 0;
    }

    # Envelopes, in display order. The rta row is not an envelope: it
    # has no carry and never gets a category row.
    my @envelopes = @categories
        .grep({ .id.defined && .is-envelope })
        .sort({ (.sort-order, .id) });

    # ---- walk the periods ------------------------------------------
    my %carry;
    my Int $cum-rta-inflow    = 0;
    my Int $cum-cash-overspend = 0;
    my Int $cash-running      = 0;
    my BudgetPeriod @budget-periods;

    for @periods -> $p {
        $cash-running   += %cash-delta{$p}  // 0;
        $cum-rta-inflow += %rta-inflow{$p} // 0;

        # Pass A — coverage. Every category's funding is known before
        # any coverage is distributed, so the payment envelopes can be
        # completed in pass B without depending on category order.
        my %base;
        my %moved-in;
        for @envelopes -> $c {
            my Int $id = $c.id;
            my Int $carry-in = %carry{$id} // 0;
            my Int $assigned = %assigned{$p}{$id} // 0;
            my Int $activity = %activity{$p}{$id} // 0;
            my Int $spend    = %card-spend{$p}{$id} // 0;
            my Int $out      = %moved-out{$p}{$id} // 0;

            # `activity` already contains -$spend, so adding it back
            # gives what the category had before its card spending.
            my Int $base = $carry-in + $assigned + $activity + $spend - $out;
            %base{$id} = $base;

            next unless $spend > 0;
            my Int $covered = min($spend, max(0, $base));
            my Int $remaining = $covered;
            for (%card-outflows{$p}{$id} // []).List -> %outflow {
                last if $remaining <= 0;
                my Int $take = min(%outflow<amount>, $remaining);
                $remaining -= $take;
                my Int $pay = %outflow<payment-cat>;
                %moved-in{$pay} = (%moved-in{$pay} // 0) + $take;
                emit-move($p, $id, $pay, $take, 'card-coverage',
                    account-id     => %outflow<account-id>,
                    transaction-id => %outflow<transaction-id>);
            }
        }

        # Pass B — availability, overspending, carry.
        my CategoryPeriod @rows;
        my Int $credit-overspend-total = 0;
        my Int $cash-overspend-total   = 0;

        for @envelopes -> $c {
            my Int $id = $c.id;
            my Int $carry-in = %carry{$id} // 0;
            my Int $assigned = %assigned{$p}{$id} // 0;
            my Int $activity = %activity{$p}{$id} // 0;
            my Int $spend    = %card-spend{$p}{$id} // 0;
            my Int $out      = %moved-out{$p}{$id} // 0;
            my Int $in       = %moved-in{$id} // 0;
            my Int $base     = %base{$id};

            # The one question rule 3 asks of an envelope: does a
            # negative available survive the boundary, or is it written
            # off and charged to Ready to Assign? A payment envelope
            # answers yes by kind, a standard one by its
            # `carry-overspend` flag, and the two ternaries below are
            # the whole of the difference.
            my Bool $carries = $c.carries-negative;

            my Int $available = $carry-in + $assigned + $activity + $in - $out;
            my Int $covered   = min($spend, max(0, $base));
            my Int $credit-overspend = $spend - $covered;
            # An envelope that carries has no cash overspending to
            # classify: the hole is not being written off, so nothing
            # has to pay for it. Charging Ready to Assign here as well
            # as carrying the negative forward would take the same money
            # out of the budget twice.
            my Int $cash-overspend   = $carries ?? 0 !! max(0, -$base);

            # Carrying envelopes keep their negatives: "you owe more
            # than you have set aside" on a card, or "this envelope is
            # allowed to run negative" on one the user has said so
            # about. Everything else resets to zero once its
            # overspending has been classified.
            my Int $carry-out = $carries
                ?? $available + $credit-overspend
                !! $available + $credit-overspend + $cash-overspend;

            my Str @flags;
            @flags.push('overspent')        if $available < 0;
            @flags.push('credit-overspend') if $credit-overspend > 0;
            @flags.push('cash-overspend')   if $cash-overspend > 0;
            # Two flags for one arithmetic state, on purpose: the view
            # layer words and colours "a card you are behind on"
            # separately from "an envelope you chose to let run
            # negative", and neither can be inferred from the numbers
            # alone once the derivation has finished.
            @flags.push('payment-negative') if $c.is-payment && $available < 0;
            @flags.push('carried-negative')
                if !$c.is-payment && $carries && $available < 0;

            # Skip rows that say nothing at all: a category with no
            # money, no history and no carry does not belong in a
            # period it was not part of. A row with any non-zero number
            # — including a zero balance reached by spending exactly
            # what was assigned — stays.
            my Bool $empty = $carry-in == 0 && $assigned == 0 && $activity == 0
                && $in == 0 && $out == 0 && $available == 0;

            %carry{$id} = $carry-out;
            $credit-overspend-total += $credit-overspend;
            $cash-overspend-total   += $cash-overspend;

            next if $empty;

            @rows.push(CategoryPeriod.new(
                period => $p, category-id => $id,
                :$carry-in, :$assigned, :$activity,
                moved-in => $in, moved-out => $out,
                :$available, :$credit-overspend, :$cash-overspend,
                :$carry-out, :@flags,
            ));
        }

        # Rule 4. Cash overspending is charged to the periods *after*
        # the one it happened in, so this period's total is added to the
        # running figure only once its own RTA has been computed.
        my Int $rta = $cum-rta-inflow - $assigned-all-periods - $cum-cash-overspend;
        $cum-cash-overspend += $cash-overspend-total;

        my Str @period-flags;
        @period-flags.push('rta-negative')     if $rta < 0;
        @period-flags.push('credit-overspend') if $credit-overspend-total > 0;
        @period-flags.push('cash-overspend')   if $cash-overspend-total > 0;

        @budget-periods.push(BudgetPeriod.new(
            period => $p,
            :$rta,
            cash-balance           => $cash-running,
            assigned-total         => (%assigned-total-by-period{$p} // 0),
            assigned-future        => (%assigned-future{$p} // 0),
            :$credit-overspend-total,
            :$cash-overspend-total,
            category-periods        => @rows,
            moves                  => (%moves-by-period{$p} // []).Array,
            flags                  => @period-flags,
        ));
    }

    my %balances;
    for (|%account-cleared.keys, |%account-uncleared.keys).unique -> $id {
        %balances{$id} = AccountBalance.new(
            account-id => $id.Int,
            cleared    => (%account-cleared{$id} // 0),
            uncleared  => (%account-uncleared{$id} // 0),
        );
    }

    BudgetView.new(
        periods          => @periods,
        budget-periods    => @budget-periods,
        moves            => @budget-periods.map({ |.moves }).Array,
        warnings         => @warnings,
        account-balances => %balances,
    );
}
