=begin pod

=head1 NAME

App::Moneymoor::Gateway::Assignment - SQL gateway for the money you
give categories each budget period.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Gateway::Assignment;

# The scheme decides which keys are legal; it defaults to the
# calendar month, whose starts are always 'YYYY-MM-01'.
my $gw = App::Moneymoor::Gateway::Assignment.new(:$db);

$gw.set('2026-03-01', $groceries, 40000);      # insert
$gw.set('2026-03-01', $groceries, 45000);      # update — one row/pair
say $gw.get('2026-03-01', $groceries).amount;  # 45000

# Budgeting December in March is legal and deliberate:
$gw.set('2026-12-01', $council-tax, 30000);

# Robbing Peter to pay Paul, atomically:
$gw.move-money('2026-03-01', $groceries, $dining, 5000);
say $gw.get('2026-03-01', $groceries).amount;  # 40000
say $gw.get('2026-03-01', $dining).amount;     # 5000

my @march = $gw.find-by-period('2026-03-01');
$gw.delete('2026-03-01', $dining);             # same as setting 0, but
                                               # leaves no row behind

# A pay-day scheme moves the legal keys, and nothing else:
my $pay = App::Moneymoor::Gateway::Assignment.new(
    :$db, scheme => App::Moneymoor::Util::Period.monthly(anchor-day => 14));
$pay.set('2026-03-14', $groceries, 40000);     # fine
$pay.set('2026-03-01', $groceries, 40000);     # Failure: not a start

=end code

=head1 DESCRIPTION

An assignment is a B<set>, not an increment: there is one row per
C<(period, category)>, guaranteed by a unique index, and C<set>
upserts. That is what makes "assign £400 to Groceries in March"
idempotent no matter how many times a UI fires it.

C<move-money> is the other primitive — two upserts in one C<run-txn>,
so the pair can never half-apply and invent or destroy money. It
adjusts B<relatively> (subtract from one, add to the other), because
that is what moving money means when both categories already have
assignments.

Negative amounts are legal. Pulling £50 back out of a category that
had nothing assigned this period leaves C<-5000> assigned, and the
engine reads that exactly as written: the category has £50 less, Ready
to Assign has £50 more.

Assigning to the C<rta> category is refused. Ready to Assign is the
pool assignments come I<from>; letting money be assigned I<to> it
would make rule 4 circular.

=head2 PERIODS ARE VALIDATED AS STARTS

Every method that takes a period key checks two things and fails
unless both hold: the key is a well-formed C<YYYY-MM-DD> date, B<and>
it is the start of a period under this gateway's C<scheme>
(C<$scheme.period-of($period) eq $period>).

The first check is the one the old C<YYYY-MM> validation did, and for
the same reason: a typo'd key does not merely misplace the money, it
extends the derived range, so C<'20226-03-01'> would ask the engine to
derive eighteen thousand years of budget.

The second is stronger, and matters more. A key that is well formed
but is not a start — C<'2026-03-15'> under the calendar month, or a
C<'2026-03'> row from before the period migration — creates a
B<phantom bucket>. Nothing rejects it downstream; the derivation
happily sums it alongside the real periods, so the money is neither
lost nor visible, and the budget stops adding up in a way no screen
explains. Storing such a key is worse than storing a typo, because a
typo announces itself.

=head1 ATTRIBUTES

=item C<db> — required C<App::Moneymoor::DB>.
=item C<scheme> — the C<App::Moneymoor::Util::Period> whose starts are
      legal keys. Defaults to C<monthly/1>, the calendar month, which
      is what every budget written so far uses.

=head1 METHODS

=item C<set(Str:D $period, Int:D $category-id, Int:D $amount --> Model::Assignment)>
=item C<adjust(Str:D $period, Int:D $category-id, Int:D $delta --> Model::Assignment)>
      — relative change; the primitive C<move-money> is built from.
=item C<get(Str:D $period, Int:D $category-id --> Model::Assignment)> —
      type object when nothing has been assigned.
=item C<amount-for(Str:D $period, Int:D $category-id --> Int)> — 0 when
      nothing has been assigned.
=item C<find-all(--> Array)> — ordered C<(period_start, id)>.
=item C<find-by-period(Str:D $period --> Array)>
=item C<find-by-category(Int:D $category-id --> Array)>
=item C<move-money(Str:D $period, Int:D $from-id, Int:D $to-id, Int:D $amount)>
=item C<delete(Str:D $period, Int:D $category-id)>

=end pod

unit class App::Moneymoor::Gateway::Assignment;

use App::Moneymoor::DB;
use App::Moneymoor::Model::Assignment;
use App::Moneymoor::Model::Category;
use App::Moneymoor::Service::Budget;
use App::Moneymoor::Util::Period;

has App::Moneymoor::DB $.db is required;

#| The scheme whose period starts are legal keys. Defaults to the
#| calendar month; the budget file's own scheme is threaded in from
#| C<Service::Workspace>, which reads it from C<budget_meta> and
#| rebuilds this gateway whenever it changes.
has App::Moneymoor::Util::Period $.scheme =
    App::Moneymoor::Util::Period.default-scheme;

#| Returns an error message, or the Str type object when C<$period> is
#| a real period start under this gateway's scheme. One message for
#| both failures on purpose: it names the shape and the start-ness
#| together, because a caller that got either wrong got the key wrong.
method !period-error(Str $period --> Str) {
    my Str $bad = "Malformed period '{ $period // '(undefined)' }' "
        ~ "(expected the YYYY-MM-DD start of a budget period under "
        ~ "{ $!scheme.gist })";
    return $bad unless valid-period($period);
    # period-of throws on what it cannot parse; valid-period has ruled
    # that out already, and the `try` costs nothing to be sure.
    my $start = try $!scheme.period-of($period);
    return $bad unless $start.defined && $start eq $period;
    Str;
}

#| Returns an error message, or the Str type object when the category
#| may be assigned to.
method !category-error(Int:D $id --> Str) {
    my $row = $!db.query-one('SELECT * FROM categories WHERE id = ?', $id);
    return "no category with id $id" unless $row && $row<id>;
    my $category = App::Moneymoor::Model::Category.new-from-row($row);
    return 'cannot assign to the Ready to Assign category — it is the pool '
         ~ 'assignments come from'
        if $category.is-rta;
    Str;
}

method get(Str:D $period, Int:D $category-id
           --> App::Moneymoor::Model::Assignment) {
    my $row = $!db.query-one(
        'SELECT * FROM assignments WHERE period_start = ? AND category_id = ?',
        $period, $category-id,
    );
    return App::Moneymoor::Model::Assignment unless $row && $row<id>;
    App::Moneymoor::Model::Assignment.new-from-row($row);
}

method amount-for(Str:D $period, Int:D $category-id --> Int) {
    my $existing = self.get($period, $category-id);
    $existing.defined ?? $existing.amount !! 0;
}

method find-all(--> Array) {
    $!db.query-all('SELECT * FROM assignments ORDER BY period_start, id').map({
        App::Moneymoor::Model::Assignment.new-from-row($_)
    }).Array;
}

method find-by-period(Str:D $period --> Array) {
    $!db.query-all(
        'SELECT * FROM assignments WHERE period_start = ? ORDER BY category_id',
        $period,
    ).map({ App::Moneymoor::Model::Assignment.new-from-row($_) }).Array;
}

method find-by-category(Int:D $category-id --> Array) {
    $!db.query-all(
        'SELECT * FROM assignments WHERE category_id = ? ORDER BY period_start',
        $category-id,
    ).map({ App::Moneymoor::Model::Assignment.new-from-row($_) }).Array;
}

method set(Str:D $period, Int:D $category-id, Int:D $amount
           --> App::Moneymoor::Model::Assignment) {
    my $period-error = self!period-error($period);
    return fail $period-error with $period-error;
    my $category-error = self!category-error($category-id);
    return fail $category-error with $category-error;

    self!upsert($period, $category-id, $amount);
    self.get($period, $category-id);
}

#| The upsert itself, with no validation: every caller in this class
#| has already validated, and it is also called from inside a
#| transaction where a `fail` would be a silent partial commit.
method !upsert(Str:D $period, Int:D $category-id, Int:D $amount) {
    # ON CONFLICT needs the unique index on (period_start, category_id)
    # — see idx_assignments_period_category in the migrations. Without
    # it this silently becomes an insert-only path and the budget grows
    # duplicate rows that both count.
    $!db.execute(
        q:to/SQL/,
            INSERT INTO assignments (period_start, category_id, amount)
            VALUES (?, ?, ?)
            ON CONFLICT(period_start, category_id)
            DO UPDATE SET amount = excluded.amount
            SQL
        $period, $category-id, $amount,
    );
}

method adjust(Str:D $period, Int:D $category-id, Int:D $delta
              --> App::Moneymoor::Model::Assignment) {
    my $period-error = self!period-error($period);
    return fail $period-error with $period-error;
    my $category-error = self!category-error($category-id);
    return fail $category-error with $category-error;

    self!upsert($period, $category-id,
        self.amount-for($period, $category-id) + $delta);
    self.get($period, $category-id);
}

method move-money(Str:D $period, Int:D $from-id, Int:D $to-id, Int:D $amount) {
    my $period-error = self!period-error($period);
    return fail $period-error with $period-error;
    return fail 'Cannot move money from a category to itself'
        if $from-id == $to-id;
    return fail 'Cannot move zero pence' if $amount == 0;

    my $from-error = self!category-error($from-id);
    return fail "source: $from-error" with $from-error;
    my $to-error = self!category-error($to-id);
    return fail "destination: $to-error" with $to-error;

    # Read both current amounts inside the transaction so a concurrent
    # writer cannot slip between the read and the write. v0.1 is
    # single-connection, but BEGIN IMMEDIATE costs nothing and this is
    # the one operation whose halves must agree.
    $!db.run-txn: {
        my Int $from-amount = self.amount-for($period, $from-id);
        my Int $to-amount   = self.amount-for($period, $to-id);
        self!upsert($period, $from-id, $from-amount - $amount);
        self!upsert($period, $to-id,   $to-amount   + $amount);
    };
    True;
}

method delete(Str:D $period, Int:D $category-id) {
    $!db.execute(
        'DELETE FROM assignments WHERE period_start = ? AND category_id = ?',
        $period, $category-id,
    );
    True;
}
