=begin pod

=head1 NAME

App::Moneymoor::Gateway::Category - SQL gateway for category groups
and categories.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Gateway::Category;

my $gw = App::Moneymoor::Gateway::Category.new(:$db);

my $bills = $gw.create-group(App::Moneymoor::Model::CategoryGroup.new(
    name => 'Monthly Bills', sort-order => 10,
));

my $rent = $gw.create(App::Moneymoor::Model::Category.new(
    name => 'Rent', group-id => $bills.id, sort-order => 1,
));

my @envelopes = $gw.find-all;                 # hidden ones excluded
my @everything = $gw.find-all(:include-hidden);
my @in-group  = $gw.find-by-group($bills.id);

$gw.hide($rent.id);                           # retire, keep history
$gw.unhide($rent.id);

my $rta = $gw.rta-category;                   # the system inflow row
my $nope = $gw.delete($rta.id);
say $nope ~~ Failure;                         # True — system row
$nope.so;

=end code

=head1 DESCRIPTION

Two tables, one gateway, because they are never useful apart: a
category picker needs its groups and a group is meaningless without
its categories.

=head2 SYSTEM ROWS ARE NOT YOURS

Three things in this table belong to the engine:

=item the C<rta> category ("Ready to Assign"), seeded by the
      migrations;
=item one C<payment> category per credit account, created and deleted
      by C<Gateway::Account>;
=item the C<Credit Card Payments> group, which is where those
      payment categories live.

C<create> refuses to mint C<payment> or C<rta> rows — those come from
the account gateway and the migrations, and a second C<rta> row would
make Ready to Assign ambiguous. C<delete> and C<delete-group> refuse
system rows outright. C<update> lets you reorder or hide a system
category, because that is a display choice, but not rename it, move
it between groups, change what it is, give it a target, or put it on
the other overspending rule.

=head2 CARRYING OVERSPENDING

C<carry-overspend> is one Bool with an engine rule behind it: False
(the default, and what every budget file written before the column
means) resets an overspent envelope to zero at the period boundary and
charges the shortfall to Ready to Assign; True carries the negative
forward instead. L<App::Moneymoor::Model::Category> is where the
semantics are written down and L<App::Moneymoor::Service::Budget> is
where they happen; the gateway stores the flag and enforces exactly one
rule about it — B<never on a system row>, with the same refusal a
rename or a target gets, because a payment envelope already carries by
kind and Ready to Assign has no available to carry.

=head2 HIDE, DO NOT DELETE

C<delete> refuses any category that has splits against it — the
C<ON DELETE RESTRICT> foreign key on C<splits> enforces the same rule
one layer down — or B<non-zero> assignments in any budget period, and
says so with a message pointing at C<hide>. Deleting a category with
history does not tidy your budget, it rewrites what you spent last
March.

Zero-amount assignment rows are not history. C<Gateway::Assignment.set>
upserts a row for every period you touch, so an envelope you funded
once and then emptied still has rows for those periods; refusing on
the rows rather than the money made every envelope that had ever been
budgeted to undeletable, however carefully the user zeroed it out
first. Those
leftover zero rows are deleted along with the category, in one
transaction.

C<hide> keeps the row, its money and its history, and only removes it
from pickers. A hidden category that still holds money keeps appearing
in budget periods (it has a balance; pretending otherwise would break
the master invariant), which is exactly what you want when you hid it
by mistake.

C<delete-group> is allowed on a non-system group and leaves its
categories in place, ungrouped (C<ON DELETE SET NULL>): losing a
grouping is recoverable, losing categories is not.

=head2 TARGETS

A target is what an envelope wants B<in one budget period> — which is
a calendar month only on a budget that is on the calendar-month scheme,
and is the payday window on every other one. The gateway stores the
tuple and nothing else; what it B<means> is
L<App::Moneymoor::Service::Target>'s subject, and the derivation and
the budget tab compare it against whatever the viewed period holds.

The tuple is five columns — C<target-pence>, C<target-kind>,
C<target-period>, C<target-start>, C<target-repeat> (see
L<App::Moneymoor::Model::Category>) — and C<create>, C<update> and
C<set-target> all put it through the same validation, because the UI
is not the only caller:

=item B<A known kind.> C<refill>, C<set_aside> or C<by_period>, the
      three the C<CHECK> constraint allows. Anything else is refused
      here, with a message, rather than by SQLite with a constraint
      error.
=item B<Never negative.> Zero clears a target; a negative one is a
      typo, and storing it would have the budget tab offering to fund
      an envelope B<down>. Refused on every path, with the same
      wording.
=item B<Zero pence only for C<refill>.> Zero B<is> the "no target"
      value, and "no target" has exactly one shape: the default one.
      A C<set_aside> of nothing each period, or a goal of nothing by
      April, is a half-filled form rather than an intention, so it is
      refused instead of being stored as an envelope the grid would
      then have to render.
=item B<C<by_period> is complete or it is refused.> It needs a
      well-formed C<'YYYY-MM-DD'> goal date and a well-formed stamped
      start date; C<target-repeat> may be any non-negative number.
      The gateway checks the B<shape> of those dates and stops there:
      which period contains one is a question only a scheme can
      answer, and this layer deliberately holds none.
=item B<Every other kind carries none of it.> A C<refill> or
      C<set_aside> row must present a NULL goal, a NULL start and a
      repeat of 0. Explicit callers are B<refused> rather than
      normalised — a caller that sent a goal period with a refill
      target has two ideas about what it is storing, and quietly
      keeping one of them is how a stale goal date outlives the plan
      it belonged to. The front door that normalises is
      C<Service::Workspace.set-target>, which is also where the fields
      are filled in from.
=item B<Never on a system row.> A target on a payment or C<rta> row
      is refused exactly as a rename or a regroup is — the same
      C<"only its sort order and hidden flag can be changed">
      message, because it is the same rule and not a second one. It
      covers all five columns, and C<set-target> refuses a system row
      outright, whatever it was asked for.

=head3 C<set-target> is a targeted write; C<update> is a whole row

C<update> writes every column it is given, the target tuple and
C<carry_overspend> included. That is the ordinary whole-row contract
the rest of this gateway has — but it means a caller that builds a
fresh C<Model::Category> out of a form and leaves those fields at their
defaults B<clears> whatever target the row had and puts it back on the
default overspending rule. Editors must carry the existing values
through.

C<set-target> exists so that the common case does not have to: it
writes the five target columns of one row by id and touches nothing
else, which is what C<Service::Workspace.set-target> — the front door
that stamps C<target-start> — delegates to.

=head3 No clock, no scheme

Neither lives here, on purpose. C<target-start> is B<supplied> by the
caller rather than defaulted to "now", so the gateway has no notion of
today; and dates are validated for shape only, so it has no notion of
what a period is either. Both questions have exactly one answer per
budget file, and C<Service::Workspace> is where that answer is held —
a second copy of it in the gateway is a second copy that can disagree.

Reads need no special handling: every finder is C<SELECT *> through
C<new-from-row>, which defaults every missing column to the "no target
of this kind" value, so a budget file written before the columns
existed answers "a refill target of nothing" — which is exactly what
it always meant — rather than blowing up.

=head1 ATTRIBUTES

=item C<db> — required C<App::Moneymoor::DB>.

=head1 METHODS

Groups:

=item C<create-group(Model::CategoryGroup:D --> Model::CategoryGroup)>
=item C<find-groups(Bool :$include-hidden = False --> Array)>
=item C<find-group-by-id(Int:D --> Model::CategoryGroup)>
=item C<find-group-by-name(Str:D --> Model::CategoryGroup)>
=item C<update-group(Model::CategoryGroup:D)>
=item C<delete-group(Int:D)>

Categories:

=item C<create(Model::Category:D --> Model::Category)>
=item C<find-all(Bool :$include-hidden = False --> Array)>
=item C<find-by-id(Int:D --> Model::Category)>
=item C<find-by-name(Str:D --> Model::Category)>
=item C<find-by-group(Int:D --> Array)>
=item C<update(Model::Category:D)>
=item C<set-target(Int:D $category-id, Str:D :$kind!, Int:D :$pence!,
      :$period, :$start, Int :$repeat = 0)> — write just the target
      tuple of one row. C<Service::Workspace.set-target> is the caller
      that stamps C<:start>.
=item C<hide(Int:D)> / C<unhide(Int:D)>
=item C<delete(Int:D)>
=item C<rta-category(--> Model::Category)>
=item C<payment-category-for(Int:D $account-id --> Model::Category)>

=end pod

unit class App::Moneymoor::Gateway::Category;

use App::Moneymoor::DB;
use App::Moneymoor::Model::Category;
use App::Moneymoor::Model::CategoryGroup;
# `valid-date` only: the shape of a date is a fact about dates, and
# Service::Budget is where this distribution already keeps it. Nothing
# else of the derivation is used here, and nothing scheme-aware could
# be — see "No clock, no scheme".
use App::Moneymoor::Service::Budget;

#| The three target kinds, exactly as the C<CHECK> constraint on
#| C<categories.target_kind> spells them. Storage names, snake_case,
#| shared with C<Service::Target> by being written down once here and
#| once there rather than by one of them importing the other: the
#| gateway must not depend on the derivation, and the derivation must
#| not depend on the database.
my constant TARGET-KINDS = ('refill', 'set_aside', 'by_period');
my constant BY-PERIOD    = 'by_period';

has App::Moneymoor::DB $.db is required;

# --- groups ---------------------------------------------------------

method create-group(App::Moneymoor::Model::CategoryGroup:D $group
                    --> App::Moneymoor::Model::CategoryGroup) {
    my Str $name = $group.name.trim;
    return fail 'Category group name cannot be empty' if $name eq '';
    return fail "A category group named '$name' already exists"
        if self.find-group-by-name($name).defined;

    $!db.execute(
        'INSERT INTO category_groups (name, sort_order, hidden, system)
         VALUES (?, ?, ?, 0)',
        $name, $group.sort-order, ($group.hidden ?? 1 !! 0),
    );
    self.find-group-by-id($!db.last-insert-id);
}

method find-groups(Bool :$include-hidden = False --> Array) {
    my $sql = $include-hidden
        ?? 'SELECT * FROM category_groups ORDER BY sort_order, id'
        !! 'SELECT * FROM category_groups WHERE hidden = 0 ORDER BY sort_order, id';
    $!db.query-all($sql).map({
        App::Moneymoor::Model::CategoryGroup.new-from-row($_)
    }).Array;
}

method find-group-by-id(Int:D $id --> App::Moneymoor::Model::CategoryGroup) {
    my $row = $!db.query-one('SELECT * FROM category_groups WHERE id = ?', $id);
    return App::Moneymoor::Model::CategoryGroup unless $row && $row<id>;
    App::Moneymoor::Model::CategoryGroup.new-from-row($row);
}

method find-group-by-name(Str:D $name --> App::Moneymoor::Model::CategoryGroup) {
    my $row = $!db.query-one(
        'SELECT * FROM category_groups WHERE name = ?', $name);
    return App::Moneymoor::Model::CategoryGroup unless $row && $row<id>;
    App::Moneymoor::Model::CategoryGroup.new-from-row($row);
}

method update-group(App::Moneymoor::Model::CategoryGroup:D $group) {
    return fail 'Cannot update a category group with no id' without $group.id;
    my $existing = self.find-group-by-id($group.id);
    return fail "No category group with id { $group.id }" without $existing;

    my Str $name = $group.name.trim;
    return fail 'Category group name cannot be empty' if $name eq '';
    return fail "The '{ $existing.name }' group is owned by the engine and "
        ~ "cannot be renamed"
        if $existing.is-system && $name ne $existing.name;

    my $clash = self.find-group-by-name($name);
    return fail "A category group named '$name' already exists"
        if $clash.defined && $clash.id != $group.id;

    $!db.execute(
        'UPDATE category_groups SET name = ?, sort_order = ?, hidden = ?
         WHERE id = ?',
        $name, $group.sort-order, ($group.hidden ?? 1 !! 0), $group.id,
    );
    True;
}

method delete-group(Int:D $id) {
    my $group = self.find-group-by-id($id);
    return fail "No category group with id $id" without $group;
    return fail "The '{ $group.name }' group is owned by the engine and "
        ~ "cannot be deleted"
        if $group.is-system;

    # categories.group_id is ON DELETE SET NULL, so the categories
    # survive as ungrouped rows rather than vanishing with the group.
    $!db.execute('DELETE FROM category_groups WHERE id = ?', $id);
    True;
}

# --- categories -----------------------------------------------------

method create(App::Moneymoor::Model::Category:D $category
              --> App::Moneymoor::Model::Category) {
    my Str $name = $category.name.trim;
    return fail 'Category name cannot be empty' if $name eq '';
    return fail "Cannot create a '{ $category.kind }' category: payment "
        ~ "categories come from Gateway::Account and the Ready to Assign "
        ~ "row from the migrations"
        unless $category.kind eq 'standard';
    return fail "A category named '$name' already exists"
        if self.find-by-name($name).defined;

    my ($kind, $target, $period, $start, $repeat) =
        target-tuple-of($category);
    my $target-error = target-tuple-error($name, $kind, $target, $period,
                                          $start, $repeat);
    return fail $target-error with $target-error;

    with $category.group-id {
        return fail "No category group with id $_"
            without self.find-group-by-id($_);
    }

    $!db.execute(
        q:to/SQL/,
            INSERT INTO categories
                (group_id, name, kind, sort_order, hidden, carry_overspend,
                 target_pence, target_kind, target_period, target_start,
                 target_repeat)
            VALUES (?, ?, 'standard', ?, ?, ?, ?, ?, ?, ?, ?)
            SQL
        $category.group-id, $name, $category.sort-order,
        ($category.hidden ?? 1 !! 0), ($category.carry-overspend ?? 1 !! 0),
        $target,
        $kind, null-unless-by-period($kind, $period),
        null-unless-by-period($kind, $start),
        ($kind eq BY-PERIOD ?? $repeat !! 0),
    );
    self.find-by-id($!db.last-insert-id);
}

#|( The two date columns as they are B<stored>: NULL for every kind
    that does not use them.

    The validator has already refused a non-C<by_period> tuple that
    carried one, so this only ever converts the empty string a form
    might have handed in — but it is applied on every path, so that
    "these columns are NULL unless the kind is by_period" is true of
    the table by construction and not by trusting the layer above. )
sub null-unless-by-period(Str:D $kind, Str $value --> Str) {
    return Str unless $kind eq BY-PERIOD;
    ($value.defined && $value ne '') ?? $value !! Str;
}

method find-all(Bool :$include-hidden = False --> Array) {
    my $sql = $include-hidden
        ?? 'SELECT * FROM categories ORDER BY sort_order, id'
        !! 'SELECT * FROM categories WHERE hidden = 0 ORDER BY sort_order, id';
    $!db.query-all($sql).map({
        App::Moneymoor::Model::Category.new-from-row($_)
    }).Array;
}

method find-by-id(Int:D $id --> App::Moneymoor::Model::Category) {
    my $row = $!db.query-one('SELECT * FROM categories WHERE id = ?', $id);
    return App::Moneymoor::Model::Category unless $row && $row<id>;
    App::Moneymoor::Model::Category.new-from-row($row);
}

method find-by-name(Str:D $name --> App::Moneymoor::Model::Category) {
    my $row = $!db.query-one('SELECT * FROM categories WHERE name = ?', $name);
    return App::Moneymoor::Model::Category unless $row && $row<id>;
    App::Moneymoor::Model::Category.new-from-row($row);
}

method find-by-group(Int:D $group-id --> Array) {
    $!db.query-all(
        'SELECT * FROM categories WHERE group_id = ? ORDER BY sort_order, id',
        $group-id,
    ).map({ App::Moneymoor::Model::Category.new-from-row($_) }).Array;
}

method rta-category(--> App::Moneymoor::Model::Category) {
    my $row = $!db.query-one(
        "SELECT * FROM categories WHERE kind = 'rta' ORDER BY id LIMIT 1");
    return App::Moneymoor::Model::Category unless $row && $row<id>;
    App::Moneymoor::Model::Category.new-from-row($row);
}

method payment-category-for(Int:D $account-id
                            --> App::Moneymoor::Model::Category) {
    my $row = $!db.query-one(
        'SELECT * FROM categories WHERE payment_account_id = ?', $account-id);
    return App::Moneymoor::Model::Category unless $row && $row<id>;
    App::Moneymoor::Model::Category.new-from-row($row);
}

method update(App::Moneymoor::Model::Category:D $category) {
    return fail 'Cannot update a category with no id' without $category.id;
    my $existing = self.find-by-id($category.id);
    return fail "No category with id { $category.id }" without $existing;

    my Str $name = $category.name.trim;
    return fail 'Category name cannot be empty' if $name eq '';
    return fail "Cannot change the kind of category { $category.id } "
        ~ "(from '{ $existing.kind }' to '{ $category.kind }')"
        unless $category.kind eq $existing.kind;

    my ($kind, $target, $period, $start, $repeat) =
        target-tuple-of($category);
    my $target-error = target-tuple-error($name, $kind, $target, $period,
                                          $start, $repeat);
    return fail $target-error with $target-error;

    # A payment envelope's name and group are owned by its account
    # (Gateway::Account keeps the name in step with the card), and the
    # rta row is referred to by kind, not by name. Reordering and
    # hiding are display choices, so those stay open. A target is not:
    # a payment envelope's figure is the card's balance and Ready to
    # Assign is not an envelope, so neither has a target of any kind to
    # want — all five columns are checked, not just the amount, so that
    # a caller cannot give a system row a goal date it will then have to
    # render.
    #
    # carry_overspend is refused on the same rule and for the same kind
    # of reason: a payment envelope already carries its negative BY
    # KIND, and Ready to Assign has no available to carry, so the flag
    # is dead weight on both — and dead weight that would read, in an
    # editor, as a choice the engine was honouring.
    if $existing.is-system {
        return fail "'{ $existing.name }' is a system category: only its "
            ~ "sort order and hidden flag can be changed"
            if $name ne $existing.name
            || ($category.group-id // -1) != ($existing.group-id // -1)
            || ?$category.carry-overspend != ?$existing.carry-overspend
            || $target != ($existing.target-pence // 0)
            || $kind ne ($existing.target-kind // TARGET-KINDS[0])
            || ($period // '') ne ($existing.target-period // '')
            || ($start  // '') ne ($existing.target-start  // '')
            || $repeat != ($existing.target-repeat // 0);
    } else {
        my $clash = self.find-by-name($name);
        return fail "A category named '$name' already exists"
            if $clash.defined && $clash.id != $category.id;
        with $category.group-id {
            return fail "No category group with id $_"
                without self.find-group-by-id($_);
        }
    }

    $!db.execute(
        'UPDATE categories SET group_id = ?, name = ?, sort_order = ?,
         hidden = ?, carry_overspend = ?, target_pence = ?, target_kind = ?,
         target_period = ?, target_start = ?, target_repeat = ?
         WHERE id = ?',
        $category.group-id, $name, $category.sort-order,
        ($category.hidden ?? 1 !! 0), ($category.carry-overspend ?? 1 !! 0),
        $target,
        $kind, null-unless-by-period($kind, $period),
        null-unless-by-period($kind, $start),
        ($kind eq BY-PERIOD ?? $repeat !! 0), $category.id,
    );
    True;
}

#|( Write one row's target tuple and nothing else.

    The narrow write C<Service::Workspace.set-target> delegates to, and
    the reason the front door does not have to read the row back and
    hand C<update> a whole C<Model::Category> just to change an amount:
    a read-modify-write of every column is a race with anything else
    editing the envelope, and it makes "the user changed their target"
    indistinguishable from "the user renamed the envelope" in the SQL.

    C<:$start> is B<supplied>, never defaulted to today: the stamping
    rule ("re-stamp when the plan changes, not when the repeat does")
    needs the previous row to decide, which is a decision for the layer
    that has one. See C<Service::Workspace.set-target>.

    Refuses a system row outright — not by comparing fields, as
    C<update> has to, because a call to this method is an attempt to
    give a system row a target however innocuous its arguments. Returns
    C<True>, or a C<Failure> carrying the reason. )
method set-target(Int:D $category-id, Str:D :$kind!, Int:D :$pence!,
                  :$period, :$start, Int :$repeat = 0) {
    my $existing = self.find-by-id($category-id);
    return fail "No category with id $category-id" without $existing;
    return fail "'{ $existing.name }' is a system category: only its "
        ~ "sort order and hidden flag can be changed"
        if $existing.is-system;

    # A Date is accepted where a date string belongs: callers that hold
    # one (the period picker, a scheme's own arithmetic) would only
    # stringify it themselves, and `.Str` on a Date is the exact
    # 'YYYY-MM-DD' form these columns hold.
    my Str $period-str = as-date-string($period);
    my Str $start-str  = as-date-string($start);

    my $error = target-tuple-error($existing.name, $kind, $pence,
                                   $period-str, $start-str, $repeat);
    return fail $error with $error;

    $!db.execute(
        'UPDATE categories SET target_pence = ?, target_kind = ?,
         target_period = ?, target_start = ?, target_repeat = ?
         WHERE id = ?',
        $pence, $kind, null-unless-by-period($kind, $period-str),
        null-unless-by-period($kind, $start-str),
        ($kind eq BY-PERIOD ?? $repeat !! 0), $category-id,
    );
    True;
}

#|( A C<Date>, a date string or nothing, as a date string or nothing.

    C<Date.Str> is the exact C<'YYYY-MM-DD'> form these columns hold,
    so both accepted shapes converge here; anything else stringifies
    and is then refused on its shape by C<target-tuple-error>, which is
    the message the caller wants anyway. )
sub as-date-string($value --> Str) {
    $value.defined ?? $value.Str !! Str;
}

#|( The one wording for a negative target, shared by every write path
    so the refusal reads the same whichever way the user got there.

    Zero is not negative: it is how a target is cleared, and the
    editor's blank field means exactly that. )
sub target-error(Str:D $name, Int:D $target --> Str) {
    "A target cannot be negative (got $target pence for "
        ~ "'$name') — leave it blank to clear the target";
}

#| How a date that should be one is quoted back. Str type objects and
#| the empty string are both "missing", and both have to print as
#| something.
sub shown(Str $value --> Str) {
    ($value.defined && $value ne '') ?? "'$value'" !! '(none)';
}

#|( The whole target contract in one place: every rule from the TARGETS
    section, checked in the order a user would hit them.

    Returns the C<Str> type object when the tuple is storable, or the
    message to refuse it with. A predicate that returns a reason rather
    than a C<Bool> because there are seven distinct ways to get this
    wrong and "invalid target" tells a caller nothing about which.

    Shape only, deliberately: whether C<$period> is a period B<start>,
    or in the past, or after C<$start>, are all questions about a
    scheme, and this layer holds none — see "No clock, no scheme". )
sub target-tuple-error(Str:D $name, Str $kind, Int:D $pence,
                       Str $period, Str $start, Int:D $repeat --> Str) {
    return "Unknown target kind '{ $kind // '(undefined)' }' for '$name' "
            ~ "(expected one of { TARGET-KINDS.join(', ') })"
        unless $kind.defined && TARGET-KINDS.first({ $_ eq $kind }).defined;

    return target-error($name, $pence) if $pence < 0;

    # Zero means "no target", and no target has exactly one shape: the
    # default one. A set_aside of nothing per period is a half-filled
    # form, not an intention.
    return "A '$kind' target needs an amount above zero (got 0 for "
            ~ "'$name') — an empty target is the default 'refill' shape, "
            ~ "which is how a target is cleared"
        if $pence == 0 && $kind ne TARGET-KINDS[0];

    if $kind eq BY-PERIOD {
        return "A '$kind' target for '$name' needs a goal date "
                ~ "(YYYY-MM-DD, got { shown($period) })"
            unless valid-date($period);
        # The start is stamped by Service::Workspace.set-target, which
        # is why this reads as an internal error rather than a form
        # one: a caller that reached here without one skipped the front
        # door.
        return "A '$kind' target for '$name' needs a stamped plan start "
                ~ "(YYYY-MM-DD, got { shown($start) }) — "
                ~ 'Service::Workspace.set-target is what stamps it'
            unless valid-date($start);
        return "A target's repeat cannot be negative (got $repeat for "
                ~ "'$name') — 0 is a one-shot goal"
            if $repeat < 0;
    } else {
        # Refuse rather than normalise: a caller that sent a goal date
        # with a refill target has two ideas about what it is storing,
        # and keeping the quiet one is how a stale date outlives the
        # plan it belonged to. Service::Workspace.set-target is the
        # front door that normalises.
        my Str @extra;
        @extra.push("a goal date ({ shown($period) })")
            if $period.defined && $period ne '';
        @extra.push("a plan start ({ shown($start) })")
            if $start.defined && $start ne '';
        @extra.push("a repeat of $repeat") if $repeat != 0;
        return "A '$kind' target for '$name' carries no goal date, plan "
                ~ "start or repeat — those belong to a "
                ~ "'{ BY-PERIOD }' target, and this one was given "
                ~ @extra.join(' and ')
            if @extra;
    }

    Str;
}

#| The target tuple as one C<Model::Category> presents it, with the
#| C<//> defaults every read site applies, so the validator and the
#| C<UPDATE> below never disagree about what a model with an
#| unset field meant.
sub target-tuple-of(App::Moneymoor::Model::Category:D $c --> List) {
    (($c.target-kind // TARGET-KINDS[0]), ($c.target-pence // 0).Int,
     $c.target-period, $c.target-start, ($c.target-repeat // 0).Int);
}

method hide(Int:D $id) {
    return fail "No category with id $id" without self.find-by-id($id);
    $!db.execute('UPDATE categories SET hidden = 1 WHERE id = ?', $id);
    True;
}

method unhide(Int:D $id) {
    return fail "No category with id $id" without self.find-by-id($id);
    $!db.execute('UPDATE categories SET hidden = 0 WHERE id = ?', $id);
    True;
}

#|( Delete a non-system category that has no history.

    "History" means B<money>, not rows. Splits are absolute: one
    categorized transaction and the answer is no, because deleting the
    category would rewrite what you spent. Assignments only count when
    they are non-zero — C<Gateway::Assignment.set> upserts a row for
    every period you touch, including one you typed a 0 into, so a
    row-counting refusal made every envelope that was ever budgeted to
    permanently undeletable even after the user had emptied it. Zeroed
    periods are not history, they are the absence of it.

    Those leftover zero rows are swept in the same transaction as the
    category, so the delete cannot half-happen. C<ON DELETE CASCADE> on
    C<assignments.category_id> would take them anyway; the explicit
    C<DELETE> is what makes the sweep true without the foreign-key
    pragma, and what makes it visible here.

    Refuses system categories outright, and refuses non-zero periods
    with a count of them, pointing at C<hide>. Returns C<True>, or a
    C<Failure> carrying the reason. )
method delete(Int:D $id) {
    my $category = self.find-by-id($id);
    return fail "No category with id $id" without $category;
    return fail "'{ $category.name }' is a system category and cannot be "
        ~ "deleted"
        if $category.is-system;

    my $splits = $!db.query-one(
        'SELECT count(*) AS n FROM splits WHERE category_id = ?', $id);
    my Int $split-count = ($splits<n> // 0).Int;
    return fail "Cannot delete '{ $category.name }': $split-count "
        ~ "transaction(s) are categorized to it — hide it instead"
        if $split-count > 0;

    my $assigned = $!db.query-one(
        'SELECT count(*) AS n FROM assignments
         WHERE category_id = ? AND amount != 0', $id);
    my Int $assignment-count = ($assigned<n> // 0).Int;
    return fail "Cannot delete '{ $category.name }': it has "
        ~ "$assignment-count period(s) of non-zero assignments — "
        ~ "hide it instead"
        if $assignment-count > 0;

    # Validation is done: everything below is the write, and a `fail`
    # inside run-txn would return a Failure while the transaction
    # committed regardless.
    $!db.run-txn: {
        $!db.execute('DELETE FROM assignments WHERE category_id = ?', $id);
        $!db.execute('DELETE FROM categories WHERE id = ?', $id);
    };
    True;
}
