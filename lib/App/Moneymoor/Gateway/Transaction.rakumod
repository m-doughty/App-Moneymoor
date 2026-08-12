=begin pod

=head1 NAME

App::Moneymoor::Gateway::Transaction - SQL gateway for transactions,
their splits, and transfer pairs.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Gateway::Transaction;

my $gw = App::Moneymoor::Gateway::Transaction.new(:$db);

# A £42.50 shop, all groceries. Transaction and split land together.
my $t = $gw.create(
    App::Moneymoor::Model::Transaction.new(
        account-id => $visa, date => '2026-03-14',
        payee-id => $tesco, amount => -4250,
    ),
    splits => [
        App::Moneymoor::Model::Split.new(category-id => $groceries, amount => -4250),
    ],
);

# A split shop: the parts must sum to the whole.
my $s = $gw.create($txn, splits => [
    App::Moneymoor::Model::Split.new(category-id => $groceries, amount => -4500),
    App::Moneymoor::Model::Split.new(category-id => $household,  amount => -1500),
]);

# Paying the card: one call, two legs, one SQL transaction.
my ($out, $in) = $gw.create-transfer(
    from-account-id => $current, to-account-id => $visa,
    date => '2026-03-28', amount => 25000,
);
say $in.transfer-peer-id == $out.id;    # True

# Moving money to a tracking account is spending, so it is categorized
# on the on-budget leg:
$gw.create-transfer(
    from-account-id => $current, to-account-id => $isa,
    date => '2026-03-30', amount => 10000,
    splits => [App::Moneymoor::Model::Split.new(
        category-id => $investing, amount => -10000)],
);

$gw.set-cleared($t.id, 'cleared');
$gw.delete($out.id);                    # takes the peer leg with it

=end code

=head1 DESCRIPTION

This gateway owns three invariants that the budget derivation depends
on. All three are enforced before any write, and every multi-row write
happens inside one C<run-txn>, so no invariant can be observed
half-true.

=head2 1. SPLITS SUM TO THE TRANSACTION

A transaction on an on-budget account is either a transfer or fully
categorized: at least one split, and the splits' amounts sum exactly
to the transaction's amount. A transaction whose splits sum to
something else is a hole in the budget — the cash moved but the
envelopes did not — so C<create> and C<update> reject it by
C<Failure> rather than storing it.

Transactions on B<tracking> accounts must have B<no> splits: they are
off budget, and a categorized tracking transaction would move an
envelope without moving any cash.

=head2 2. TRANSFERS COME IN PAIRS

C<create-transfer> writes both legs and cross-links them in one
transaction. C<$amount> is the positive magnitude moving
C<from-account-id> → C<to-account-id>; the from leg is stored negative
and the to leg positive.

Whether the pair carries splits depends on where the money goes:

=item B<Both legs on budget> (cash ↔ cash, cash ↔ card, card ↔ card):
      no splits at all. The money has not left the budget, so no
      envelope may move. (The derivation still moves the payment
      envelope of a credit leg — see C<Service::Budget> rule 2 — but
      that is derived, not stored.)
=item B<One leg on a tracking account>: money really is entering or
      leaving the budget, so the B<on-budget> leg is categorized and
      C<:@splits> is required, summing to that leg's amount.
=item B<Both legs tracking>: no splits; invisible to the budget.

C<delete> on either leg deletes both. C<update> on either leg keeps
the peer's date and amount in step — a transfer whose legs disagree
about how much moved is not a transfer.

=head2 3. IDS ARE NEVER GUESSED

C<create> returns the stored row read back from the database, so the
caller gets the real id, the real defaults and the real timestamp
rather than a model it built by hand. C<:@splits> are accepted with
no C<transaction-id>: the gateway fills it in once the transaction has
an id.

=head2 EDITING

C<update> replaces the whole transaction and, when C<:@splits> is
passed, its entire split set (delete then insert, inside the same
transaction). Passing no C<:@splits> leaves the existing splits alone,
which is what a "just fix the memo" edit wants — but if you change the
amount without passing splits, the sums no longer agree, so that
combination is refused for a categorized transaction.

Moving a transfer leg to a different account is refused: the pair's
account types decide whether the pair may be categorized, so a move is
a delete plus a create, not an update.

=head1 ATTRIBUTES

=item C<db> — required C<App::Moneymoor::DB>.
=item C<scheme> — the C<App::Moneymoor::Util::Period> C<find-by-period>
      reads its argument against. Defaults to C<monthly/1>, the
      calendar month. Nothing else in this gateway has an opinion about
      periods: a transaction is dated, not bucketed, and which bucket
      its date falls in is the derivation's question.

=head1 METHODS

=item C<create(Model::Transaction:D $txn, :@splits --> Model::Transaction)>
=item C<create-transfer(Int:D :$from-account-id!, Int:D :$to-account-id!,
      Str:D :$date!, Int:D :$amount!, Str :$memo, Str :$cleared,
      :@splits --> Array)> — the two legs, from first.
=item C<update(Model::Transaction:D $txn, :@splits)>
=item C<delete(Int:D $id)> — with its peer leg, if any.
=item C<set-cleared(Int:D $id, Str:D $state)>
=item C<find-by-id(Int:D $id --> Model::Transaction)>
=item C<find-all(--> Array)> — ordered C<(date, id)>.
=item C<find-by-account(Int:D $account-id --> Array)>
=item C<find-by-period(Str:D $period --> Array)> — every transaction
      dated in C<[$period, $scheme.next-period($period))>. A
      C<Failure> unless C<$period> is a real period start under
      C<scheme>: a key that is not one names a window with two
      possible meanings, and picking either quietly would answer a
      question nobody asked.
=item C<find-splits(Int:D $transaction-id --> Array)>
=item C<find-all-splits(--> Array)> — every split, ordered by
      C<(transaction_id, id)>; this is what C<Service::Workspace>
      hands to the derivation.

=end pod

unit class App::Moneymoor::Gateway::Transaction;

use App::Moneymoor::DB;
use App::Moneymoor::Model::Account;
use App::Moneymoor::Model::Transaction;
use App::Moneymoor::Model::Split;
use App::Moneymoor::Service::Budget;
use App::Moneymoor::Util::Period;

has App::Moneymoor::DB $.db is required;

#| The scheme C<find-by-period> reads a period key against. Defaults to
#| the calendar month; C<Service::Workspace> owns the budget's real one
#| and constructs this gateway with it.
has App::Moneymoor::Util::Period $.scheme =
    App::Moneymoor::Util::Period.default-scheme;

my constant VALID-CLEARED = <uncleared cleared reconciled>;

# --- reads ----------------------------------------------------------

method find-by-id(Int:D $id --> App::Moneymoor::Model::Transaction) {
    my $row = $!db.query-one('SELECT * FROM transactions WHERE id = ?', $id);
    return App::Moneymoor::Model::Transaction unless $row && $row<id>;
    App::Moneymoor::Model::Transaction.new-from-row($row);
}

method find-all(--> Array) {
    $!db.query-all('SELECT * FROM transactions ORDER BY date, id').map({
        App::Moneymoor::Model::Transaction.new-from-row($_)
    }).Array;
}

method find-by-account(Int:D $account-id --> Array) {
    $!db.query-all(
        'SELECT * FROM transactions WHERE account_id = ? ORDER BY date, id',
        $account-id,
    ).map({ App::Moneymoor::Model::Transaction.new-from-row($_) }).Array;
}

#| Returns an error message, or the Str type object when C<$period> is
#| a real period start under this gateway's scheme. Shape and
#| start-ness in one message: a caller that got either wrong got the
#| key wrong.
method !period-error(Str $period --> Str) {
    my Str $bad = "Malformed period '{ $period // '(undefined)' }' "
        ~ "(expected the YYYY-MM-DD start of a budget period under "
        ~ "{ $!scheme.gist })";
    return $bad unless valid-period($period);
    my $start = try $!scheme.period-of($period);
    return $bad unless $start.defined && $start eq $period;
    Str;
}

method find-by-period(Str:D $period --> Array) {
    # A LIKE prefix would need escaping; a half-open date range uses
    # the (date, id) index and cannot be confused by a wildcard in the
    # caller's string. The end of the range is the next period's start,
    # asked of the scheme rather than computed here — under a clamping
    # or an every-N-weeks scheme it is not a fixed distance away.
    my $period-error = self!period-error($period);
    return fail $period-error with $period-error;
    $!db.query-all(
        'SELECT * FROM transactions WHERE date >= ? AND date < ?
         ORDER BY date, id',
        $period, $!scheme.next-period($period),
    ).map({ App::Moneymoor::Model::Transaction.new-from-row($_) }).Array;
}

method find-splits(Int:D $transaction-id --> Array) {
    $!db.query-all(
        'SELECT * FROM splits WHERE transaction_id = ? ORDER BY id',
        $transaction-id,
    ).map({ App::Moneymoor::Model::Split.new-from-row($_) }).Array;
}

method find-all-splits(--> Array) {
    $!db.query-all('SELECT * FROM splits ORDER BY transaction_id, id').map({
        App::Moneymoor::Model::Split.new-from-row($_)
    }).Array;
}

# --- validation -----------------------------------------------------

#| Returns an error message, or the Str type object when the split set
#| is legal for this account and amount. Kept separate from the write
#| paths because every one of them needs it and a `fail` inside a
#| transaction would commit the half-written rows.
method !split-error($account, Int:D $amount, @splits --> Str) {
    if $account.is-on-budget {
        return 'a transaction on an on-budget account must have at least '
             ~ 'one split (or be created with create-transfer)'
            unless @splits;
    } else {
        return "account '{ $account.name }' is a tracking account, so its "
             ~ 'transactions cannot be categorized'
            if @splits;
        return Str;
    }

    for @splits -> $s {
        my $row = $!db.query-one(
            'SELECT id FROM categories WHERE id = ?', $s.category-id);
        return "no category with id { $s.category-id }"
            unless $row && $row<id>;
    }

    my Int $sum = [+] @splits.map(*.amount);
    return "splits sum to $sum but the transaction is $amount"
        unless $sum == $amount;

    Str;
}

method !account-or-error(Int $id --> App::Moneymoor::Model::Account) {
    my $row = $!db.query-one('SELECT * FROM accounts WHERE id = ?', $id);
    return App::Moneymoor::Model::Account unless $row && $row<id>;
    App::Moneymoor::Model::Account.new-from-row($row);
}

method !insert-splits(Int:D $transaction-id, @splits) {
    for @splits -> $s {
        $!db.execute(
            'INSERT INTO splits (transaction_id, category_id, amount, memo)
             VALUES (?, ?, ?, ?)',
            $transaction-id, $s.category-id, $s.amount, $s.memo,
        );
    }
}

# --- writes ---------------------------------------------------------

method create(App::Moneymoor::Model::Transaction:D $txn, :@splits = ()
              --> App::Moneymoor::Model::Transaction) {
    my $account = self!account-or-error($txn.account-id);
    return fail "No account with id { $txn.account-id }" without $account;

    return fail "Malformed date '{ $txn.date }' (expected YYYY-MM-DD)"
        unless valid-date($txn.date);
    return fail "Unknown cleared state '{ $txn.cleared }'"
        unless VALID-CLEARED.first({ $_ eq $txn.cleared }).defined;
    return fail 'Use create-transfer to create a transfer pair'
        if $txn.transfer-peer-id.defined;

    with $txn.payee-id {
        my $payee = $!db.query-one('SELECT id FROM payees WHERE id = ?', $_);
        return fail "No payee with id $_" unless $payee && $payee<id>;
    }

    my $split-error = self!split-error($account, $txn.amount, @splits);
    return fail $split-error with $split-error;

    my Int $new-id;
    $!db.run-txn: {
        $!db.execute(
            q:to/SQL/,
                INSERT INTO transactions
                    (account_id, date, payee_id, memo, amount, cleared)
                VALUES (?, ?, ?, ?, ?, ?)
                SQL
            $txn.account-id, $txn.date, $txn.payee-id, $txn.memo,
            $txn.amount, $txn.cleared,
        );
        $new-id = $!db.last-insert-id;
        self!insert-splits($new-id, @splits);
    };

    self.find-by-id($new-id);
}

method create-transfer(
    Int:D :$from-account-id!,
    Int:D :$to-account-id!,
    Str:D :$date!,
    Int:D :$amount!,
    Str :$memo = '',
    Str :$cleared = 'uncleared',
    :@splits = (),
    --> Array
) {
    my $from = self!account-or-error($from-account-id);
    return fail "No account with id $from-account-id" without $from;
    my $to = self!account-or-error($to-account-id);
    return fail "No account with id $to-account-id" without $to;
    return fail 'A transfer needs two different accounts'
        if $from-account-id == $to-account-id;

    return fail "Malformed date '$date' (expected YYYY-MM-DD)"
        unless valid-date($date);
    return fail "Unknown cleared state '$cleared'"
        unless VALID-CLEARED.first({ $_ eq $cleared }).defined;
    return fail 'A transfer amount must be a positive number of pence '
        ~ '(the direction is from-account-id -> to-account-id)'
        unless $amount > 0;

    # Exactly one on-budget leg means money is entering or leaving the
    # budget, and that leg has to say which envelope it came from or
    # went to.
    my $on-budget-legs = ($from.is-on-budget, $to.is-on-budget).grep(*.so).elems;
    my $categorized-account = Nil;
    my Int $categorized-amount = 0;
    if $on-budget-legs == 1 {
        $categorized-account = $from.is-on-budget ?? $from !! $to;
        $categorized-amount  = $from.is-on-budget ?? -$amount !! $amount;
        return fail "A transfer between '{ $from.name }' and '{ $to.name }' "
            ~ "crosses the budget boundary, so its on-budget leg must be "
            ~ "categorized — pass :\@splits summing to $categorized-amount"
            unless @splits;
        my $split-error = self!split-error(
            $categorized-account, $categorized-amount, @splits);
        return fail $split-error with $split-error;
    } else {
        return fail 'A transfer between two on-budget accounts cannot be '
            ~ 'categorized: no envelope moves when money stays inside the '
            ~ 'budget'
            if @splits && $on-budget-legs == 2;
        return fail 'A transfer between two tracking accounts cannot be '
            ~ 'categorized: neither leg is on budget'
            if @splits;
    }

    my Int $from-id;
    my Int $to-id;
    $!db.run-txn: {
        $!db.execute(
            'INSERT INTO transactions (account_id, date, memo, amount, cleared)
             VALUES (?, ?, ?, ?, ?)',
            $from-account-id, $date, $memo, -$amount, $cleared,
        );
        $from-id = $!db.last-insert-id;

        $!db.execute(
            'INSERT INTO transactions
                 (account_id, date, memo, amount, cleared, transfer_peer_id)
             VALUES (?, ?, ?, ?, ?, ?)',
            $to-account-id, $date, $memo, $amount, $cleared, $from-id,
        );
        $to-id = $!db.last-insert-id;

        $!db.execute(
            'UPDATE transactions SET transfer_peer_id = ? WHERE id = ?',
            $to-id, $from-id);

        if @splits {
            my Int $categorized-id = $from.is-on-budget ?? $from-id !! $to-id;
            self!insert-splits($categorized-id, @splits);
        }
    };

    [self.find-by-id($from-id), self.find-by-id($to-id)];
}

method update(App::Moneymoor::Model::Transaction:D $txn, :@splits) {
    return fail 'Cannot update a transaction with no id' without $txn.id;
    my $existing = self.find-by-id($txn.id);
    return fail "No transaction with id { $txn.id }" without $existing;

    return fail "Malformed date '{ $txn.date }' (expected YYYY-MM-DD)"
        unless valid-date($txn.date);
    return fail "Unknown cleared state '{ $txn.cleared }'"
        unless VALID-CLEARED.first({ $_ eq $txn.cleared }).defined;

    my $account = self!account-or-error($txn.account-id);
    return fail "No account with id { $txn.account-id }" without $account;
    return fail 'A transfer leg cannot be moved to another account — '
        ~ 'delete the transfer and create it again'
        if $existing.is-transfer && $txn.account-id != $existing.account-id;

    with $txn.payee-id {
        my $payee = $!db.query-one('SELECT id FROM payees WHERE id = ?', $_);
        return fail "No payee with id $_" unless $payee && $payee<id>;
    }

    my @existing-splits = self.find-splits($txn.id);
    my Bool $replacing = @splits.defined && so @splits;
    my @effective-splits = $replacing ?? @splits.List !! @existing-splits;

    if $existing.is-transfer {
        # The peer leg's account decides whether this pair may carry
        # splits at all; !split-error only knows about this leg.
        my $peer = App::Moneymoor::Model::Transaction;
        with $existing.transfer-peer-id {
            $peer = self.find-by-id($_);
        }
        my $peer-account = App::Moneymoor::Model::Account;
        $peer-account = self!account-or-error($peer.account-id) if $peer.defined;
        # ?^ rather than ^^: the boolean xor always answers with a
        # Bool, where ^^ hands back Nil when both operands are true.
        my Bool $crosses-boundary = $peer-account.defined
            ?? ($account.is-on-budget ?^ $peer-account.is-on-budget)
            !! False;
        return fail 'A transfer between two accounts on the same side of '
            ~ 'the budget cannot be categorized'
            if @effective-splits && !$crosses-boundary;
        if $crosses-boundary {
            # The on-budget leg of a boundary-crossing transfer must be
            # categorized and must sum; the tracking leg must not be
            # categorized at all. !split-error answers both questions
            # from the account's type.
            my $split-error = self!split-error(
                $account, $txn.amount, @effective-splits);
            return fail $split-error with $split-error;
        }
    } else {
        my $split-error = self!split-error(
            $account, $txn.amount, @effective-splits);
        return fail $split-error with $split-error;
    }

    $!db.run-txn: {
        $!db.execute(
            q:to/SQL/,
                UPDATE transactions
                SET account_id = ?, date = ?, payee_id = ?, memo = ?,
                    amount = ?, cleared = ?
                WHERE id = ?
                SQL
            $txn.account-id, $txn.date, $txn.payee-id, $txn.memo,
            $txn.amount, $txn.cleared, $txn.id,
        );

        # Both legs of a transfer always agree about the date and the
        # magnitude; a pair that disagrees is two transactions wearing
        # a transfer's clothes.
        with $existing.transfer-peer-id {
            $!db.execute(
                'UPDATE transactions SET date = ?, amount = ? WHERE id = ?',
                $txn.date, -$txn.amount, $_,
            );
        }

        if $replacing {
            $!db.execute('DELETE FROM splits WHERE transaction_id = ?', $txn.id);
            self!insert-splits($txn.id, @splits);
        }
    };
    True;
}

method set-cleared(Int:D $id, Str:D $state) {
    return fail "No transaction with id $id" without self.find-by-id($id);
    return fail "Unknown cleared state '$state'"
        unless VALID-CLEARED.first({ $_ eq $state }).defined;
    $!db.execute('UPDATE transactions SET cleared = ? WHERE id = ?', $state, $id);
    True;
}

method delete(Int:D $id) {
    my $existing = self.find-by-id($id);
    return fail "No transaction with id $id" without $existing;

    $!db.run-txn: {
        # Splits cascade with their transaction. The peer goes too:
        # half a transfer is money that appeared from nowhere.
        with $existing.transfer-peer-id {
            $!db.execute('DELETE FROM transactions WHERE id = ?', $_);
        }
        $!db.execute('DELETE FROM transactions WHERE id = ?', $id);
    };
    True;
}
