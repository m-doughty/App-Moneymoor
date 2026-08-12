=begin pod

=head1 NAME

App::Moneymoor::Service::Workspace - the seam between the database and
the pure budget derivation.

=head1 SYNOPSIS

=begin code :lang<raku>

use MacOS::NativeLib <sqlcipher>;
use App::Moneymoor::DB;
use App::Moneymoor::Service::Workspace;

my $db = App::Moneymoor::DB.new(:db-path($path));
$db.connect($passphrase);

# The budget's period scheme comes out of the file it was opened
# from — there is no :scheme argument, and passing one is an error.
my $ws = App::Moneymoor::Service::Workspace.new(:$db);
say $ws.scheme.gist;                    # Period(monthly/1) on a file
                                        # that has never chosen one

# Gateways, already wired to the same connection:
my $current = $ws.accounts.create(
    App::Moneymoor::Model::Account.new(name => 'Current', type => 'cash'));
my $food = $ws.categories.create(
    App::Moneymoor::Model::Category.new(name => 'Groceries'));

# Mutations that are really budgeting operations. The keys are period
# starts; under the default calendar-month scheme that is the first of
# the month.
$ws.set-assigned('2026-03-01', $food.id, 40000);
$ws.move-money('2026-03-01', $food.id, $dining.id, 5000);

# Targets are a budgeting operation too, and this is their front door:
# it stamps the plan start and normalises the fields the kind does not
# use.
$ws.set-target($food.id, kind => 'refill', pence => 40000);
$ws.set-target($tax.id, kind => 'by_period', pence => 5_000_000,
               period => '2027-04-05');           # £50,000 by April
$ws.set-target($vat.id, kind => 'by_period', pence => 300000,
               period => '2026-11-01', repeat => 3);   # quarterly

# The whole derived budget, recomputed from facts:
my $view = $ws.budget(through-period => '2026-04-01');
say $view.rta('2026-03-01');
say $view.category('2026-03-01', $food.id).available;

# Or just the numbers you asked about:
say $ws.ready-to-assign('2026-03-01');
say $ws.available('2026-03-01', $food.id);
.say for $ws.explain('2026-03-01', $visa-payment-id);

# Which period are we in right now?
say $ws.current-period;                 # e.g. 2026-08-01

# Moving the whole budget onto payday windows. Ask first — this is
# what a confirm dialog is made of:
my $payday = App::Moneymoor::Util::Period.monthly(anchor-day => 14);
my %plan = $ws.re-bucket-preview($payday);
say "{ %plan<rows> } assignments in { %plan<periods-before> } periods "
  ~ "become { %plan<rows-after> } in { %plan<periods-after> } "
  ~ "({ %plan<merged> } merged)";

# ...then do it. One transaction, totals preserved or nothing happens.
my %done = $ws.change-scheme($payday);
say $ws.scheme.label($ws.current-period);   # 14 Aug – 13 Sep 2026

=end code

=head1 DESCRIPTION

C<Service::Budget.compute> is deliberately ignorant of storage: it
takes facts and returns a view. C<Workspace> is the thin piece that
loads the facts through the gateways, calls it, and offers the
mutations that are budgeting operations rather than CRUD
(C<set-assigned>, C<move-money> and C<set-target>).

It owns one gateway of each kind, all sharing the C<DB> handle it was
constructed with, and exposes them as C<accounts>, C<categories>,
C<payees>, C<transactions> and C<assignments>. Anything that is plain
CRUD goes through those directly — wrapping every gateway method in a
pass-through would only add a second place for the signatures to
drift.

=head2 RECOMPUTATION IS THE WHOLE STRATEGY

C<budget> reads every account, category, transaction, split and
assignment and derives the entire budget from scratch. There is no
incremental update path and no cached rollup in v0.1, on purpose: an
incremental rollup is a second implementation of the semantics that
has to agree with the first one forever, and the first thing it does
when it disagrees is quietly lose money.

For the size of budget a person actually has (a few thousand
transactions over a few years) a full recompute is milliseconds.
Callers that need it more often than that should hold the returned
C<BudgetView> rather than call C<budget> in a loop.

=head2 THE CLOCK LIVES HERE

C<compute> never looks at the clock — that is what makes it testable.
Someone still has to decide that "the budget runs through the period
we are in", and this is the only layer that may: C<budget> defaults
C<:$through-period> to C<current-period()>, which reads the local date
and asks the scheme which period contains it. Pass C<:through-period>
explicitly to pin it (every test in this distribution does).

=head2 SETTING A TARGET IS A BUDGETING OPERATION

C<set-target> is to targets what C<set-assigned> is to assignments:
the one call the app makes, sitting in front of a gateway that
deliberately knows less than it does. It is here rather than on
C<Gateway::Category> for one reason — it needs the clock, and
C<current-period> is the only clock read in the distribution.

=head3 The stamp

A C<by_period> target ramps from a B<plan start>, and the plan start
is stamped, not inferred: "£50,000 by April" means something
different begun in August than begun in February, and the difference
is the whole schedule. C<set-target> stamps C<current-period> when

=item the target B<becomes> C<by_period> — a new goal, or a kind
      change onto one; or
=item an existing C<by_period> target's B<amount or goal period>
      changes — the plan is a different plan, so it re-ramps from
      today rather than pretending it was always this one; or
=item the row somehow holds no start at all (a hand-edited file),
      because a plan without a start has no schedule to derive.

and B<keeps> the existing stamp otherwise. The one change that
deliberately does not re-stamp is C<repeat>: turning a one-shot goal
into a quarterly one, or changing "every 3" to "every 4", leaves the
cycle that is already under way exactly where it was.

Nothing else in the app may write C<target_start>. Re-stamping is
what makes the ramp re-derive from where the envelope is B<now>, and
a caller that could set it freely could put an envelope permanently
behind.

=head3 The normalising

C<Gateway::Category> refuses a C<refill> target that carries a goal
date, because an explicit caller with two ideas about what it is
storing should hear about it. This front door is the caller that
B<resolves> them instead: a non-C<by_period> kind arrives here with
whatever the form had in its unused fields and leaves with a NULL
goal, a NULL start and a repeat of 0.

The goal date itself is stored B<exactly as given> — it is not
rounded to a period start. A date is read as "the period containing
it", so a budget that changes its period scheme re-derives its plan
under the new windows; a key normalised to the old scheme's start
would name a period that no longer exists.

=head2 THE SCHEME LIVES HERE TOO

A budget period is a calendar month, a month anchored on payday, or an
every-N-weeks pay window, and B<which> is a property of the budget
file, not of the engine. This layer is where that choice is held: the
C<scheme> attribute is handed to the two gateways that validate period
keys (C<assignments> and C<transactions>) and to every C<compute> call,
so a single object decides what a legal key is at the boundary and what
a bucket is inside the derivation. Two different answers to that
question in one process is precisely the failure that produces a budget
summed two ways.

=head3 It is loaded from the file, not passed in

The scheme belongs to the budget file — two budgets on one machine
legitimately differ — so it lives in C<budget_meta> under the key
C<period_scheme>, holding exactly what C<Period.to-hash> produces, as
JSON:

=begin code :lang<json>
{"anchor_day":14,"type":"monthly"}
{"anchor":"2026-08-14","type":"weekly","weeks":4}
=end code

C<TWEAK> reads it before it builds a single gateway, so the two that
validate period keys are born holding the file's scheme rather than the
default. B<Absent is not an error>: a file that has never chosen means
C<monthly/1>, the calendar month, which is what every budget written
before periods existed was already doing.

A key that is present and B<unreadable> — malformed JSON, or a hash
C<Period.from-hash> refuses — B<throws>, naming the key and the value
it found. Opening the file anyway would mean bucketing a budget under a
scheme its owner never chose: every derived figure would be summed by
the wrong windows, and the gateways' start-ness validation would then
reject every write the user attempted. A budget that will not open is
a problem with an obvious cause; one that opens under the wrong scheme
is not.

Because the file is the authority, there is no C<:scheme> constructor
argument. Passing one throws rather than being quietly ignored — a
caller that believed it had set the scheme and had not is the same
failure by a different route.

=head3 C<change-scheme> is the only mutator

C<scheme> is public-read and never assigned from outside this class.
The one path that changes it is C<change-scheme>, which does not merely
record the new choice: it B<re-buckets the assignments to match>. Each
assignment row moves to whichever period of the new scheme contains its
old period's B<start date>, and rows that land together sum. That is
the whole rule, and three properties follow from it:

=item B<Total assigned per category is preserved.> Nothing is created,
      dropped or moved between categories, only re-labelled — so Ready
      to Assign and the master invariant come out exactly as they went
      in, which is why this operation needs no reconciliation step
      afterwards. C<change-scheme> asserts it at runtime, re-reading
      the per-category totals after the rewrite and refusing (rolling
      back, leaving C<period_scheme> untouched) if a single one has
      drifted.
=item B<It is atomic.> The read, the rewrite and the C<budget_meta>
      write share one transaction, so a crash mid-change reopens the
      file under the old scheme with the old buckets, never as a
      mixture.
=item B<It is deterministic and repeatable.> Rows are re-inserted in
      C<(period start, category)> order, so the same budget re-bucketed
      the same way twice produces the same table.

It is B<lossy in the buckets, by design>: two periods that merge cannot
be told apart afterwards, so changing back does not restore the
original split. The totals are what is guaranteed, and the totals are
what the budget's arithmetic is made of.

An empty budget re-buckets nothing and just writes the key — which is
how a newly created budget adopts a non-default scheme. Calling it with
the scheme already in force is a legal no-op that still writes the key:
an explicit record beats an absent one, and the caller decides whether
offering it makes sense.

=head1 ATTRIBUTES

=item C<db> — required C<App::Moneymoor::DB>.
=item C<scheme> — the C<App::Moneymoor::Util::Period> this workspace
      buckets and validates by, read from the file at construction.
      Not a constructor argument; C<change-scheme> is the only mutator.
=item C<accounts> / C<categories> / C<payees> / C<transactions> /
      C<assignments> — the gateways, built at construction, the last
      two carrying C<scheme>.

=head1 METHODS

=item C<budget(Str :$through-period --> BudgetView)> — load facts,
      derive, return.
=item C<set-assigned(Str:D $period, Int:D $category-id, Int:D $amount)>
=item C<move-money(Str:D $period, Int:D $from-id, Int:D $to-id, Int:D $amount)>
=item C<set-target(Int:D $category-id, Str:D :$kind!, Int:D :$pence!,
      :$period, Int :$repeat = 0)> — set an envelope's whole target,
      stamping the plan start and normalising the fields the kind does
      not use. C<:$period> is the C<by_period> goal, a C<'YYYY-MM-DD'>
      string or a C<Date>. Returns the gateway's C<True>, or its
      C<Failure>.
=item C<ready-to-assign(Str:D $period --> Int)>
=item C<available(Str:D $period, Int:D $category-id --> Int)>
=item C<explain(Str:D $period, Int:D $category-id --> Array)> — the
      derived moves that touch a category in a period.
=item C<current-period(--> Str)> — the start of the period containing
      today, local time.
=item C<re-bucket-preview(Period:D $new --> Hash)> — what
      C<change-scheme($new)> would do, without doing any of it. No
      writes, no state change.
=item C<change-scheme(Period:D $new --> Hash)> — re-bucket, persist,
      and adopt C<$new>. Returns the same summary.
=item C<re-bucket-cell(Period:D $new, Str:D $old-period, Int:D $category-id --> List)>
      — the mapping rule in one expression.

=head2 The summary both re-bucket methods return

C<re-bucket-preview> and C<change-scheme> return the same five counts,
which is exactly the material a confirm dialog needs:

=item C<rows> — assignment rows before.
=item C<periods-before> — distinct period keys before.
=item C<rows-after> — assignment rows after.
=item C<periods-after> — distinct period keys after.
=item C<merged> — C<rows - rows-after>, the number of rows that landed
      on top of another and were summed into it. Zero means the change
      is a pure re-labelling.

C<change-scheme>'s copy is computed from what it actually did, not from
a prediction, so a caller may compare the two.

=end pod

unit class App::Moneymoor::Service::Workspace;

use JSON::Fast;

use App::Moneymoor::DB;
use App::Moneymoor::Gateway::Account;
use App::Moneymoor::Gateway::Category;
use App::Moneymoor::Gateway::Payee;
use App::Moneymoor::Gateway::Transaction;
use App::Moneymoor::Gateway::Assignment;
use App::Moneymoor::Service::Budget;
use App::Moneymoor::Util::Period;

#| The C<budget_meta> key the budget file's period scheme is stored
#| under, holding C<Period.to-hash> as JSON. Absent means the calendar
#| month — see THE SCHEME LIVES HERE TOO.
constant PERIOD-SCHEME-KEY = 'period_scheme';

has App::Moneymoor::DB $.db is required;

#| The budget's period scheme, and the one place it is held. Every
#| seam that needs one — the two gateways that validate period keys,
#| and every `compute` call below — is handed this object, so the
#| boundary and the derivation can never disagree about what a period
#| is. Read from the file at construction (absent means the calendar
#| month) and changed only by `change-scheme`: this is a public-read
#| attribute with no public writer and no constructor argument, because
#| the budget file is the authority on its own scheme.
has App::Moneymoor::Util::Period $.scheme =
    App::Moneymoor::Util::Period.default-scheme;

has App::Moneymoor::Gateway::Account     $.accounts;
has App::Moneymoor::Gateway::Category    $.categories;
has App::Moneymoor::Gateway::Payee       $.payees;
has App::Moneymoor::Gateway::Transaction $.transactions;
has App::Moneymoor::Gateway::Assignment  $.assignments;

submethod TWEAK(*%args) {
    # Quietly ignoring a scheme somebody passed is the same failure as
    # quietly loading the wrong one: a caller that believes it chose the
    # bucketing and did not.
    die "Service::Workspace takes no 'scheme': a budget's period scheme "
            ~ "is a property of its file, read from budget_meta's "
            ~ "'{ PERIOD-SCHEME-KEY }' key at construction and changed "
            ~ "only by .change-scheme"
        if %args<scheme>:exists;

    # Before the gateways, not after: they are handed this object, and
    # a gateway built on the default would validate a payday budget's
    # keys as if it were a calendar-month one.
    $!scheme = self!load-scheme;

    $!accounts   = App::Moneymoor::Gateway::Account.new(db => $!db);
    $!categories = App::Moneymoor::Gateway::Category.new(db => $!db);
    $!payees     = App::Moneymoor::Gateway::Payee.new(db => $!db);
    self!wire-scheme-gateways;
}

#| The two gateways that validate period keys, rebuilt around whatever
#| scheme this workspace now holds. They carry nothing but a C<db> and a
#| scheme, so replacing them B<is> the update — there is no state in
#| them to migrate, and no second copy of the scheme to forget.
method !wire-scheme-gateways() {
    $!transactions = App::Moneymoor::Gateway::Transaction.new(
        db => $!db, scheme => $!scheme);
    $!assignments  = App::Moneymoor::Gateway::Assignment.new(
        db => $!db, scheme => $!scheme);
}

#| One message shape for every unreadable stored scheme, naming the key
#| and quoting what was actually in it: the value is a short JSON string
#| the user has never seen, so showing it is the difference between "your
#| budget file is broken" and a bug report somebody can act on.
my sub bad-scheme(Str:D $found, Str:D $why) {
    die "Budget file's stored period scheme is unreadable: budget_meta "
        ~ "'{ PERIOD-SCHEME-KEY }' holds '$found' — $why";
}

#|( The file's scheme, or the calendar month when it has never chosen
    one.

    Throws on a value that is present but unusable. See THE SCHEME LIVES
    HERE TOO for why this is louder than every other read in the class:
    a budget opened under a scheme its owner did not choose buckets
    every derived figure by the wrong windows, and then refuses every
    write the user makes, because the gateways validate keys against
    the same wrong scheme. )
method !load-scheme(--> App::Moneymoor::Util::Period) {
    my Str $json = $!db.get-meta(PERIOD-SCHEME-KEY);
    return App::Moneymoor::Util::Period.default-scheme without $json;

    # The CATCH comes first in each block on purpose: a phaser as the
    # last statement is what the block evaluates to, so `do { work();
    # CATCH {...} }` hands back the phaser's Nil rather than the work's
    # value.
    my $data = do {
        # JSON::Fast's message is a position plus an excerpt; the first
        # line is the part that says what is wrong with it.
        CATCH { default { bad-scheme($json, "it is not valid JSON "
                                            ~ "({ .message.lines.head })") } }
        from-json($json);
    };

    do {
        CATCH { default { bad-scheme($json, .message) } }
        App::Moneymoor::Util::Period.from-hash($data);
    };
}

#| The start of the budget period containing today, local time. The
#| only clock read in the distribution outside a caller's own code.
method current-period(--> Str) { $!scheme.period-of(Date.today) }

method budget(Str :$through-period --> App::Moneymoor::Service::Budget::BudgetView) {
    my Str $through = $through-period // self.current-period;

    # Hidden categories and closed accounts are included deliberately:
    # they still hold money and still have history, and leaving them
    # out would break the master invariant rather than tidy the view.
    compute(
        accounts      => $!accounts.find-all(:include-closed),
        categories    => $!categories.find-all(:include-hidden),
        transactions  => $!transactions.find-all,
        splits        => $!transactions.find-all-splits,
        assignments    => $!assignments.find-all,
        through-period => $through,
        scheme         => $!scheme,
    );
}

method set-assigned(Str:D $period, Int:D $category-id, Int:D $amount) {
    $!assignments.set($period, $category-id, $amount);
}

method move-money(Str:D $period, Int:D $from-id, Int:D $to-id, Int:D $amount) {
    $!assignments.move-money($period, $from-id, $to-id, $amount);
}

#|( Set an envelope's target — the front door for all three kinds, and
    the only place C<target_start> is ever written. See SETTING A
    TARGET IS A BUDGETING OPERATION for the two rulings it implements.

    C<$kind> is a storage name: C<'refill'>, C<'set_aside'> or
    C<'by_period'>. C<:$period> is the C<by_period> goal — any date,
    string or C<Date>, stored as given and read as the period
    containing it — and is ignored (and cleared) for the other two
    kinds, along with C<:$repeat>.

    Everything past the stamp is the gateway's: the kind whitelist, the
    amount, the completeness of a C<by_period> tuple and the system-row
    refusal all come back from there as a C<Failure> this method
    returns unchanged. A row that does not exist is the gateway's
    message too, which is why the read below is allowed to come back
    with nothing. )
method set-target(Int:D $category-id, Str:D :$kind!, Int:D :$pence!,
                  :$period, Int :$repeat = 0) {
    # Not by_period: the fields the kind does not use are normalised
    # away here, rather than refused as the gateway would. A form has
    # every field on it whichever radio button is selected.
    return $!categories.set-target($category-id, :$kind, :$pence,
                                   period => Str, start => Str, repeat => 0)
        unless $kind eq 'by_period';

    my $existing = $!categories.find-by-id($category-id);
    my Str $goal = $period.defined ?? $period.Str !! Str;

    # The stamping rule, read off the row that is there. `.defined`
    # guards every access: `find-by-id` answers with a type object when
    # there is no such row, and the gateway is what says so.
    my Bool $keep = $existing.defined
        && $existing.is-by-period
        && ($existing.target-start // '') ne ''
        && ($existing.target-pence // 0) == $pence
        && ($existing.target-period // '') eq ($goal // '');

    my Str $start = $keep ?? $existing.target-start !! self.current-period;

    $!categories.set-target($category-id, :$kind, :$pence,
                            period => $goal, :$start, :$repeat);
}

method ready-to-assign(Str:D $period --> Int) {
    self.budget(through-period => $period).rta($period);
}

method available(Str:D $period, Int:D $category-id --> Int) {
    my $row = self.budget(through-period => $period)
        .category($period, $category-id);
    $row.defined ?? $row.available !! 0;
}

method explain(Str:D $period, Int:D $category-id --> Array) {
    self.budget(through-period => $period).moves-for($period, :$category-id);
}

# --- changing the scheme --------------------------------------------

#|( Where one assignment row lands under C<$new>: the
    C<(period start, category id)> cell it merges into.

    The settled ruling in one expression — B<containment of the old
    period's start date>. The old key I<is> that date, so the mapping
    needs nothing but the new scheme, and a row's category never moves,
    which is what makes the totals guarantee true by construction
    rather than by luck.

    Public and overridable so a test can subclass it into a wrong
    mapping and prove the runtime guard bites; nothing in the app calls
    it directly. )
method re-bucket-cell(App::Moneymoor::Util::Period:D $new,
                      Str:D $old-period, Int:D $category-id --> List) {
    ($new.period-of($old-period), $category-id);
}

#|( The whole re-bucket, computed and not applied: the cells the
    assignments table would hold under C<$new>, the per-category totals
    it holds B<now> (the runtime guard's "before"), and the summary both
    public methods return.

    Throws if a stored key is not a well-formed date — which the
    gateways and the C<schema_rev> 1 migration between them make
    impossible, and which is not something to guess a bucket for. )
method !plan-re-bucket(App::Moneymoor::Util::Period:D $new --> Hash) {
    my @rows = $!db.query-all(
        'SELECT period_start, category_id, amount FROM assignments
         ORDER BY period_start, category_id, id');

    my %before;             # category id → assigned, before
    my %amount;             # "start\tcategory" → assigned, after
    my %periods-before;

    for @rows -> $row {
        my Str $old      = $row<period_start>.Str;
        my Int $category = $row<category_id>.Int;
        my Int $amount   = $row<amount>.Int;

        %periods-before{ $old }  = True;
        %before{ $category }     = (%before{ $category } // 0) + $amount;

        my ($start, $cell-category) =
            self.re-bucket-cell($new, $old, $category);
        my Str $cell = "$start\t$cell-category";
        %amount{ $cell } = (%amount{ $cell } // 0) + $amount;
    }

    # (start, category) order, numerically on the category: the insert
    # order is the row ids, and a replay of the same change on the same
    # budget should produce the same table down to them.
    my @cells = %amount.kv.map(-> $cell, $amount {
        my ($start, $category) = $cell.split("\t");
        ($start, $category.Int, $amount);
    }).sort({ (.[0], .[1]) }).Array;

    %(
        cells   => @cells,
        before  => %before,
        summary => %(
            rows             => @rows.elems,
            'periods-before' => %periods-before.elems,
            'rows-after'     => @cells.elems,
            'periods-after'  => @cells.map({ .[0] }).unique.elems,
            merged           => @rows.elems - @cells.elems,
        ),
    );
}

#|( What C<change-scheme($new)> would do, without doing any of it: a
    read-only dry run for the confirm that asks the user first.

    Returns the five counts documented under THE SCHEME LIVES HERE TOO
    — C<rows>, C<periods-before>, C<rows-after>, C<periods-after>,
    C<merged>. Writes nothing and changes nothing about this
    workspace. )
method re-bucket-preview(App::Moneymoor::Util::Period:D $new --> Hash) {
    self!plan-re-bucket($new)<summary>;
}

#|( Re-bucket every assignment onto C<$new>, persist C<$new> as the
    file's scheme, and adopt it here. Returns the same summary
    C<re-bucket-preview> does, computed from what actually happened.

    Everything that touches the file happens in one transaction: the
    read, the rewrite, the runtime assertion and the C<budget_meta>
    write. The rewrite is a delete-and-reinsert rather than an
    in-place re-key because the unique index on
    C<(period_start, category_id)> is a constraint on I<each statement>,
    not on the transaction: updating keys one row at a time would
    collide with a row the next update is about to move out of the way,
    and merging rows has to delete one of them anyway. No foreign key
    points at C<assignments>, so the fresh ids cost nothing.

    The assertion is the ruling's: per-category totals are re-read after
    the rewrite and compared against what they were, and a single penny
    of drift dies — which rolls the transaction back, so a mapping bug
    becomes a refused operation with the old buckets and the old scheme
    intact rather than corrupted money. )
method change-scheme(App::Moneymoor::Util::Period:D $new --> Hash) {
    my %summary = $!db.run-txn: {
        my %plan = self!plan-re-bucket($new);

        $!db.execute('DELETE FROM assignments');
        for %plan<cells>.list -> $cell {
            $!db.execute(
                'INSERT INTO assignments (period_start, category_id, amount)
                 VALUES (?, ?, ?)',
                $cell[0], $cell[1], $cell[2]);
        }

        self!assert-totals-unchanged($new, %plan<before>);

        # Sorted keys and no pretty-printing: the same scheme always
        # serialises to the same bytes, so a file diff shows a scheme
        # change only when the scheme changed.
        $!db.set-meta(PERIOD-SCHEME-KEY,
                      to-json($new.to-hash, :!pretty, :sorted-keys));

        %plan<summary>;
    };

    # Only after the commit: until then the file still says otherwise,
    # and a workspace whose scheme leads its file would validate keys
    # the file cannot hold.
    $!scheme = $new;
    self!wire-scheme-gateways;

    %summary;
}

#| The runtime half of the totals guarantee. Cheap — one grouped SELECT
#| — and it converts any future mapping bug into a refused operation
#| instead of a budget whose envelopes no longer add up to what was put
#| in them.
method !assert-totals-unchanged(App::Moneymoor::Util::Period:D $new,
                                %before) {
    my %after;
    for $!db.query-all('SELECT category_id, sum(amount) AS total
                        FROM assignments GROUP BY category_id') -> $row {
        %after{ $row<category_id>.Int } = ($row<total> // 0).Int;
    }

    my Str @drift;
    for (%before.keys, %after.keys).flat.unique.sort -> $category {
        my Int $was = (%before{ $category } // 0).Int;
        my Int $now = (%after{ $category } // 0).Int;
        @drift.push("category $category: $was → $now") unless $was == $now;
    }
    return unless @drift;

    die "Re-bucketing onto { $new.gist } would have changed what is "
        ~ "assigned ({ @drift.join('; ') }) — refused, and nothing was "
        ~ "written";
}
