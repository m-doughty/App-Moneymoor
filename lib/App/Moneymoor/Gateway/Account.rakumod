=begin pod

=head1 NAME

App::Moneymoor::Gateway::Account - SQL gateway for accounts, and the
owner of the credit-card payment-category invariant.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Gateway::Account;

my $gw = App::Moneymoor::Gateway::Account.new(:$db);

my $current = $gw.create(App::Moneymoor::Model::Account.new(
    name => 'Current Account', type => 'cash',
));

# Creating a credit account also creates its payment envelope, in the
# same SQL transaction — there is no window in which one exists
# without the other.
my $visa = $gw.create(App::Moneymoor::Model::Account.new(
    name => 'Visa', type => 'credit',
));
my $envelope = $gw.payment-category-for($visa.id);
say $envelope.name;                     # Visa

my @open = $gw.find-all;                # closed accounts excluded
my @all  = $gw.find-all(:include-closed);

$gw.close($visa.id);                    # soft retire, history intact
$gw.reopen($visa.id);

my $dup = $gw.create(App::Moneymoor::Model::Account.new(name => 'Visa'));
say $dup ~~ Failure;                    # True — names are unique
$dup.so;

=end code

=head1 DESCRIPTION

Accounts are the one entity whose creation has a side effect, and it
is a load-bearing one: B<every credit account owns exactly one
payment category>, created with it and deleted with it. The budget
derivation relies on that — a credit account with no payment envelope
has nowhere to reserve the cash its spending commits, so
C<Service::Budget> refuses to let its transactions reach the budget
at all (and says so in C<warnings>). Doing the two inserts inside one
C<run-txn> is what makes the invariant true rather than usually true.

The payment envelope is named after its account and lives in the
system C<Credit Card Payments> group, which the migrations seed. If
that group has somehow been deleted, C<create> recreates it rather
than failing: an ungrouped payment category is a display problem, a
missing one is a correctness problem.

=head2 VALIDATION AND FAILURE

Every method validates B<before> opening a transaction and returns a
C<Failure> (via C<fail>) for anything it will not do — duplicate
name, empty name, unknown type, unknown id. A C<Failure> returned
from inside a transaction would be a silent commit of a half-applied
change, so the rule is: validate first, then write.

    my $r = $gw.create($account);
    if $r ~~ Failure { note $r.exception.message; $r.so }

=head2 WHAT UPDATE WILL NOT DO

C<update> changes C<name>, C<note>, C<closed> and C<sort-order>. It
refuses to change C<type>, and that is deliberate: every type
transition has a different correct behaviour (cash → credit must mint
a payment envelope; credit → cash must retire one that may already
hold money and be referenced by splits; anything → tracking must pull
existing transactions back out of the budget). Silently picking one
of those would corrupt history. Delete the account and re-create it,
or wait for a version that offers explicit conversions.

=head2 DELETION

C<delete> is a hard delete and it takes the account's transactions
(and their splits) with it, plus the payment category and any money
assigned to it. It is refused when the payment category is referenced
by splits belonging to B<other> accounts' transactions — that would
rewrite those transactions' history — with a message naming the
problem. Prefer C<close> for anything you still want to see.

=head1 ATTRIBUTES

=item C<db> — required C<App::Moneymoor::DB>.

=head1 METHODS

=item C<find-all(Bool :$include-closed = False --> Array)>
=item C<find-by-id(Int:D $id --> Model::Account)> — type object when
      absent.
=item C<find-by-name(Str:D $name --> Model::Account)>
=item C<create(Model::Account:D $account --> Model::Account)>
=item C<update(Model::Account:D $account)>
=item C<close(Int:D $id)> / C<reopen(Int:D $id)>
=item C<delete(Int:D $id)>
=item C<payment-category-for(Int:D $account-id --> Model::Category)>

=end pod

unit class App::Moneymoor::Gateway::Account;

use App::Moneymoor::DB;
use App::Moneymoor::Model::Account;
use App::Moneymoor::Model::Category;

has App::Moneymoor::DB $.db is required;

constant PAYMENT-GROUP-NAME = 'Credit Card Payments';
my constant VALID-TYPES = <cash credit tracking>;

method find-all(Bool :$include-closed = False --> Array) {
    my $sql = $include-closed
        ?? 'SELECT * FROM accounts ORDER BY sort_order, id'
        !! 'SELECT * FROM accounts WHERE closed = 0 ORDER BY sort_order, id';
    $!db.query-all($sql).map({
        App::Moneymoor::Model::Account.new-from-row($_)
    }).Array;
}

method find-by-id(Int:D $id --> App::Moneymoor::Model::Account) {
    my $row = $!db.query-one('SELECT * FROM accounts WHERE id = ?', $id);
    return App::Moneymoor::Model::Account unless $row && $row<id>;
    App::Moneymoor::Model::Account.new-from-row($row);
}

method find-by-name(Str:D $name --> App::Moneymoor::Model::Account) {
    my $row = $!db.query-one('SELECT * FROM accounts WHERE name = ?', $name);
    return App::Moneymoor::Model::Account unless $row && $row<id>;
    App::Moneymoor::Model::Account.new-from-row($row);
}

method create(App::Moneymoor::Model::Account:D $account
              --> App::Moneymoor::Model::Account) {
    my Str $name = $account.name.trim;
    return fail 'Account name cannot be empty' if $name eq '';
    return fail "Unknown account type '{ $account.type }' "
        ~ "(expected one of { VALID-TYPES.join(', ') })"
        unless VALID-TYPES.first({ $_ eq $account.type }).defined;
    return fail "An account named '$name' already exists"
        if self.find-by-name($name).defined;

    my Int $new-id;
    $!db.run-txn: {
        $!db.execute(
            q:to/SQL/,
                INSERT INTO accounts (name, type, note, closed, sort_order)
                VALUES (?, ?, ?, ?, ?)
                SQL
            $name, $account.type, $account.note,
            ($account.closed ?? 1 !! 0), $account.sort-order,
        );
        $new-id = $!db.last-insert-id;

        # The payment envelope has to exist before anyone can record a
        # single transaction on the card, so it is created here rather
        # than lazily on first use — and inside the same transaction,
        # so a failure leaves neither row behind.
        self!create-payment-category($new-id, $name, $account.sort-order)
            if $account.type eq 'credit';
    };

    self.find-by-id($new-id);
}

method !create-payment-category(Int:D $account-id, Str:D $name,
                                Int:D $sort-order) {
    my $group = $!db.query-one(
        'SELECT id FROM category_groups WHERE name = ?', PAYMENT-GROUP-NAME);
    my Int $group-id = ($group && $group<id>) ?? $group<id>.Int !! Int;

    # Seeded by the migrations; recreated here if a user (or a future
    # bug) removed it. An ungrouped payment category is cosmetic
    # damage, a missing one is a broken budget.
    without $group-id {
        $!db.execute(
            'INSERT INTO category_groups (name, sort_order, hidden, system)
             VALUES (?, ?, 0, 1)',
            PAYMENT-GROUP-NAME, 1000,
        );
        $group-id = $!db.last-insert-id;
    }

    $!db.execute(
        q:to/SQL/,
            INSERT INTO categories
                (group_id, name, kind, payment_account_id, sort_order, hidden)
            VALUES (?, ?, 'payment', ?, ?, 0)
            SQL
        $group-id, $name, $account-id, $sort-order,
    );
}

method payment-category-for(Int:D $account-id
                            --> App::Moneymoor::Model::Category) {
    my $row = $!db.query-one(
        'SELECT * FROM categories WHERE payment_account_id = ?', $account-id);
    return App::Moneymoor::Model::Category unless $row && $row<id>;
    App::Moneymoor::Model::Category.new-from-row($row);
}

method update(App::Moneymoor::Model::Account:D $account) {
    return fail 'Cannot update an account with no id' without $account.id;
    my $existing = self.find-by-id($account.id);
    return fail "No account with id { $account.id }" without $existing;

    my Str $name = $account.name.trim;
    return fail 'Account name cannot be empty' if $name eq '';
    return fail "Account type cannot be changed (from '{ $existing.type }' "
        ~ "to '{ $account.type }') — create a new account instead"
        unless $account.type eq $existing.type;

    my $clash = self.find-by-name($name);
    return fail "An account named '$name' already exists"
        if $clash.defined && $clash.id != $account.id;

    $!db.run-txn: {
        $!db.execute(
            q:to/SQL/,
                UPDATE accounts
                SET name = ?, note = ?, closed = ?, sort_order = ?
                WHERE id = ?
                SQL
            $name, $account.note, ($account.closed ?? 1 !! 0),
            $account.sort-order, $account.id,
        );
        # The payment envelope is named after its account; renaming one
        # without the other leaves a budget screen lying about which
        # card it is showing.
        $!db.execute(
            'UPDATE categories SET name = ? WHERE payment_account_id = ?',
            $name, $account.id,
        ) if $existing.is-credit;
    };
    True;
}

method close(Int:D $id) {
    return fail "No account with id $id" without self.find-by-id($id);
    $!db.execute('UPDATE accounts SET closed = 1 WHERE id = ?', $id);
    True;
}

method reopen(Int:D $id) {
    return fail "No account with id $id" without self.find-by-id($id);
    $!db.execute('UPDATE accounts SET closed = 0 WHERE id = ?', $id);
    True;
}

method delete(Int:D $id) {
    my $account = self.find-by-id($id);
    return fail "No account with id $id" without $account;

    my $payment = self.payment-category-for($id);
    if $payment.defined {
        # Splits on *other* accounts' transactions that point at this
        # payment envelope would lose their category. Refuse rather
        # than rewrite them.
        my $foreign = $!db.query-one(
            q:to/SQL/,
                SELECT count(*) AS n
                FROM splits s
                JOIN transactions t ON t.id = s.transaction_id
                WHERE s.category_id = ? AND t.account_id != ?
                SQL
            $payment.id, $id,
        );
        my Int $n = ($foreign<n> // 0).Int;
        return fail "Cannot delete account '{ $account.name }': its payment "
            ~ "category is used by $n split(s) on other accounts — "
            ~ "recategorize them first"
            if $n > 0;
    }

    $!db.run-txn: {
        # Transactions first: their splits cascade, which is what
        # releases the RESTRICT'd references to the payment category.
        $!db.execute('DELETE FROM transactions WHERE account_id = ?', $id);
        $!db.execute('DELETE FROM categories WHERE payment_account_id = ?', $id)
            if $payment.defined;
        $!db.execute('DELETE FROM accounts WHERE id = ?', $id);
    };
    True;
}
