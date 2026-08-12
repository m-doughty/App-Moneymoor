=begin pod

=head1 NAME

App::Moneymoor::Model::Split - the categorized part of a transaction.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Model::Split;

# A £60 shop split between food and household:
my @splits = (
    App::Moneymoor::Model::Split.new(category-id => $groceries, amount => -4500),
    App::Moneymoor::Model::Split.new(category-id => $household, amount => -1500),
);
# ... created together with the transaction, in one SQL transaction:
$gw.create($txn, :@splits);

my $s = App::Moneymoor::Model::Split.new-from-row(%row);

=end code

=head1 DESCRIPTION

Splits are where transactions meet envelopes. Every categorized
transaction owns at least one, and their amounts must sum to the
transaction's amount — C<Gateway::Transaction> enforces that inside
the same SQL transaction that writes them, so a budget file can never
contain a half-categorized transaction.

Amounts follow the transaction's sign convention (outflow negative,
inflow positive), so a refund split is positive and a spending split
is negative. A split may be zero — that is a legitimate placeholder
while a UI is being edited — and the engine treats zero splits as
no-ops.

Inflows are categorized like anything else: a salary payment is a
split against the C<rta> category, which is what makes it "Ready to
Assign" rather than money that appeared in an envelope by magic.

C<memo> is per-split, so a three-way split can explain each part.

=head1 ATTRIBUTES

=item C<id> — primary key; absent on a not-yet-inserted row.
=item C<transaction-id> — FK to C<transactions.id>. Left unset when
      building splits to pass to C<Gateway::Transaction.create>: the
      gateway fills it in once the transaction has an id.
=item C<category-id> — required FK to C<categories.id>.
=item C<amount> — required signed integer pence.
=item C<memo> — free-form, default empty string.

=head1 METHODS

=item C<new-from-row(%row)> — build from a DBIish row hash.
=item C<is-inflow> / C<is-outflow> — amount sign predicates.

=end pod

unit class App::Moneymoor::Model::Split;

has Int $.id;
has Int $.transaction-id;
has Int $.category-id is required;
has Int $.amount is required;
has Str $.memo = '';

method new-from-row(%row --> App::Moneymoor::Model::Split) {
    App::Moneymoor::Model::Split.new(
        id             => %row<id>,
        transaction-id => %row<transaction_id> // Int,
        category-id    => (%row<category_id> // 0).Int,
        amount         => (%row<amount> // 0).Int,
        memo           => %row<memo> // '',
    );
}

method is-inflow(--> Bool)  { $!amount > 0 }
method is-outflow(--> Bool) { $!amount < 0 }
