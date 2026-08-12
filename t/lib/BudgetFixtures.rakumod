=begin pod

=head1 NAME

BudgetFixtures - fact builder for the pure budget tests.

=head1 SYNOPSIS

=begin code :lang<raku>

use lib $?FILE.IO.parent.add('lib').Str;
use BudgetFixtures;

my $f = standard-facts();          # 3 accounts, 4 categories
$f.inflow(account => CURRENT, date => '2026-03-01', amount => 180000);
$f.assign('2026-03-01', GROCERIES, 40000);
$f.spend(account => VISA, date => '2026-03-14', amount => 7250,
         category => GROCERIES);

my $view = $f.compute(through-period => '2026-03-01');

=end code

=head1 DESCRIPTION

The budget tests are pure — no database, no clock — so they need
somewhere to build well-formed facts with stable ids. This is that
place: every mutator returns the ids it created, dates are always
explicit ISO strings, and the id counters are per-C<Facts> so two
fixtures in one test file cannot collide.

Period keys are C<'YYYY-MM-DD'> period starts, which under the
calendar-month scheme most of these tests use means the first of the
month: C<assign('2026-03-01', ...)>, C<compute(through-period =>
'2026-03-01')>. C<compute> and C<compute-shuffled> take a
C<:$scheme> for the property suite, which runs the same generated facts
under several — the facts themselves are scheme-free, because a
transaction is a date and an amount whatever the budget's windows are.

C<add-category> takes C<:carry-overspend> and C<set-carry-overspend>
flips it on a category that already exists, because rule 3's two
cash-overspending rules are a property of the envelope rather than of
the facts: the same transactions under the flag on and off are two
different budgets, and that is exactly what the rollover tests need to
put side by side.

The builder deliberately does I<not> validate the way the gateways do.
Some tests need malformed facts (a split that does not sum, a dangling
transfer peer, an assignment keyed on something that is not a period
start) to prove C<compute> reports them as warnings instead of
producing a wrong number.

=end pod

unit module BudgetFixtures;

use App::Moneymoor::Model::Account;
use App::Moneymoor::Model::Category;
use App::Moneymoor::Model::Transaction;
use App::Moneymoor::Model::Split;
use App::Moneymoor::Model::Assignment;
use App::Moneymoor::Service::Budget;
use App::Moneymoor::Util::Period;

# Ids of the standard fixture, so tests can read as prose.
constant CURRENT   is export = 1;   # cash account
constant VISA      is export = 2;   # credit account
constant ISA       is export = 3;   # tracking account
constant SAVINGS   is export = 4;   # second cash account

constant RTA       is export = 1;   # system Ready to Assign category
constant GROCERIES is export = 2;
constant DINING    is export = 3;
constant VISA-PAY  is export = 4;   # payment envelope of VISA

our class Facts is export {
    has @.accounts;
    has @.categories;
    has @.transactions;
    has @.splits;
    has @.assignments;

    has Int $!next-txn = 0;
    has Int $!next-split = 0;
    has Int $!next-assignment = 0;

    method add-account(Int:D $id, Str:D $name, Str:D $type) {
        @!accounts.push(App::Moneymoor::Model::Account.new(
            :$id, :$name, :$type));
        $id;
    }

    method add-category(Int:D $id, Str:D $name, Str :$kind = 'standard',
                        Int :$payment-account-id, Int :$sort-order = 0,
                        Bool :$carry-overspend = False) {
        @!categories.push(App::Moneymoor::Model::Category.new(
            :$id, :$name, :$kind, :$payment-account-id, :$sort-order,
            :$carry-overspend));
        $id;
    }

    #|( Put an existing category on the other cash-overspending rule,
        keeping everything else about it — the same facts, one flag
        flipped.

        The engine is a pure derivation, so this is how a test asks the
        retroactivity question: compute, flip, compute again, and the
        two views are the same budget under rule 3's two answers. )
    method set-carry-overspend(Int:D $id, Bool:D $carries --> Bool) {
        my $c = @!categories.first({ .id.defined && .id == $id });
        return False without $c;
        @!categories = @!categories.map(-> $each {
            $each.id.defined && $each.id == $id
                ?? App::Moneymoor::Model::Category.new(
                       id => $each.id, name => $each.name,
                       kind => $each.kind, group-id => $each.group-id,
                       payment-account-id => $each.payment-account-id,
                       sort-order => $each.sort-order,
                       hidden => $each.hidden,
                       carry-overspend => $carries)
                !! $each
        }).Array;
        True;
    }

    #| A transaction with explicit parts:
    #| C<parts =E<gt> [(GROCERIES) =E<gt> -4500, (DINING) =E<gt> -1500]>,
    #| signed exactly as they will be stored. The parentheses round the
    #| category constant are load-bearing — a bareword to the left of
    #| C<=E<gt>> is auto-quoted, so C<GROCERIES =E<gt> -4500> would
    #| build a Pair keyed on the string.
    method txn(Int :$account!, Str :$date!, Int :$amount!, :@parts = (),
               Str :$cleared = 'cleared', Int :$peer) {
        my Int $id = ++$!next-txn;
        @!transactions.push(App::Moneymoor::Model::Transaction.new(
            :$id, account-id => $account, :$date, :$amount, :$cleared,
            transfer-peer-id => $peer,
        ));
        self!add-splits($id, @parts);
        $id;
    }

    method !add-splits(Int:D $transaction-id, @parts) {
        for @parts -> $part {
            die "BudgetFixtures: part key '{ $part.key }' is not a category "
                ~ "id — write (CATEGORY) => amount, not CATEGORY => amount "
                ~ '(a bareword left of => is auto-quoted)'
                unless $part.key ~~ Int;
            @!splits.push(App::Moneymoor::Model::Split.new(
                id => ++$!next-split, transaction-id => $transaction-id,
                category-id => $part.key, amount => $part.value.Int,
            ));
        }
    }

    #| Money out: `amount` is the positive magnitude.
    method spend(Int :$account!, Str :$date!, Int :$amount!, Int :$category!) {
        self.txn(:$account, :$date, amount => -$amount,
                 parts => [$category => -$amount]);
    }

    #| Money in, to Ready to Assign: `amount` is the positive magnitude.
    method inflow(Int :$account!, Str :$date!, Int :$amount!,
                  Int :$category = RTA) {
        self.txn(:$account, :$date, amount => $amount,
                 parts => [$category => $amount]);
    }

    #| Money back into a category (a refund): positive magnitude.
    method refund(Int :$account!, Str :$date!, Int :$amount!, Int :$category!) {
        self.txn(:$account, :$date, amount => $amount,
                 parts => [$category => $amount]);
    }

    #| A paired transfer. `amount` is the positive magnitude moving
    #| from → to; `parts` categorize the on-budget leg when the
    #| transfer crosses the budget boundary.
    method transfer(Int :$from!, Int :$to!, Str :$date!, Int :$amount!,
                    :@parts = (), Bool :$categorize-from = True) {
        my Int $from-id = ++$!next-txn;
        my Int $to-id   = ++$!next-txn;
        @!transactions.push(App::Moneymoor::Model::Transaction.new(
            id => $from-id, account-id => $from, :$date, amount => -$amount,
            cleared => 'cleared', transfer-peer-id => $to-id,
        ));
        @!transactions.push(App::Moneymoor::Model::Transaction.new(
            id => $to-id, account-id => $to, :$date, amount => $amount,
            cleared => 'cleared', transfer-peer-id => $from-id,
        ));
        my Int $carrier = $categorize-from ?? $from-id !! $to-id;
        self!add-splits($carrier, @parts);
        ($from-id, $to-id);
    }

    method assign(Str:D $period, Int:D $category, Int:D $amount) {
        # One row per (period, category), exactly as the unique index
        # in the schema guarantees: assigning twice replaces.
        @!assignments = @!assignments.grep(-> $a {
            !($a.period eq $period && $a.category-id == $category)
        }).Array;
        @!assignments.push(App::Moneymoor::Model::Assignment.new(
            id => ++$!next-assignment, :$period, category-id => $category,
            :$amount,
        ));
        $amount;
    }

    #| Delete a transaction and, if it is a transfer leg, its peer —
    #| the same all-or-nothing rule Gateway::Transaction enforces.
    method delete-txn(Int:D $id --> Bool) {
        my $txn = @!transactions.first({ .id == $id });
        return False without $txn;

        my Int @doomed = $id;
        @doomed.push($txn.transfer-peer-id) if $txn.transfer-peer-id.defined;

        @!transactions = @!transactions.grep(-> $t {
            !@doomed.first({ $_ == $t.id }).defined }).Array;
        @!splits = @!splits.grep(-> $s {
            !@doomed.first({ $_ == $s.transaction-id }).defined }).Array;
        True;
    }

    #| Edit a plain (non-transfer) single-split transaction, keeping its
    #| split in step with its amount — the same all-or-nothing contract
    #| Gateway::Transaction enforces. Returns False when the target is
    #| not editable this way, so a random-operation generator can just
    #| try and move on.
    method edit-txn(Int:D $id, Int :$amount, Str :$date --> Bool) {
        my $txn = @!transactions.first({ .id == $id });
        return False without $txn;
        return False if $txn.transfer-peer-id.defined;

        my @its-splits = @!splits.grep({ .transaction-id == $id });
        return False unless @its-splits.elems == 1;

        my Int $new-amount = $amount // $txn.amount;
        my Str $new-date   = $date   // $txn.date;

        @!transactions = @!transactions.map(-> $t {
            $t.id == $id
                ?? App::Moneymoor::Model::Transaction.new(
                       id => $t.id, account-id => $t.account-id,
                       date => $new-date, amount => $new-amount,
                       cleared => $t.cleared, memo => $t.memo)
                !! $t
        }).Array;
        @!splits = @!splits.map(-> $s {
            $s.transaction-id == $id
                ?? App::Moneymoor::Model::Split.new(
                       id => $s.id, transaction-id => $s.transaction-id,
                       category-id => $s.category-id, amount => $new-amount)
                !! $s
        }).Array;
        True;
    }

    #| C<:$scheme> defaults to the calendar month, which is what every
    #| test that does not name one is written against; the property
    #| suite passes each of several schemes in turn, and the facts are
    #| identical either way — only the bucketing differs.
    method compute(Str :$through-period,
                   App::Moneymoor::Util::Period :$scheme =
                       App::Moneymoor::Util::Period.default-scheme) {
        App::Moneymoor::Service::Budget::compute(
            accounts => @!accounts, categories => @!categories,
            transactions => @!transactions, splits => @!splits,
            assignments => @!assignments, :$through-period, :$scheme,
        );
    }

    #| The same facts in a different order — same budget, or the
    #| determinism property is broken.
    method compute-shuffled(Str :$through-period,
                            App::Moneymoor::Util::Period :$scheme =
                                App::Moneymoor::Util::Period.default-scheme) {
        App::Moneymoor::Service::Budget::compute(
            accounts => @!accounts.reverse, categories => @!categories.reverse,
            transactions => @!transactions.reverse, splits => @!splits.reverse,
            assignments => @!assignments.reverse, :$through-period, :$scheme,
        );
    }
}

#| One cash account, one credit card with its payment envelope, one
#| tracking account, two spending categories, and the system rta row.
our sub standard-facts(--> Facts) is export {
    my $f = Facts.new;
    $f.add-account(CURRENT, 'Current Account', 'cash');
    $f.add-account(VISA,    'Visa',            'credit');
    $f.add-account(ISA,     'Stocks ISA',      'tracking');
    $f.add-account(SAVINGS, 'Savings',         'cash');
    $f.add-category(RTA,       'Ready to Assign', kind => 'rta', sort-order => -1);
    $f.add-category(GROCERIES, 'Groceries', sort-order => 1);
    $f.add-category(DINING,    'Dining Out', sort-order => 2);
    $f.add-category(VISA-PAY,  'Visa', kind => 'payment',
                    payment-account-id => VISA, sort-order => 1000);
    $f;
}
