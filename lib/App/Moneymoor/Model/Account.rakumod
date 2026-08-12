=begin pod

=head1 NAME

App::Moneymoor::Model::Account - a place money actually sits.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Model::Account;

my $current = App::Moneymoor::Model::Account.new(
    name => 'Current Account',
    type => 'cash',
);

my $visa = App::Moneymoor::Model::Account.new(
    name => 'Visa',
    type => 'credit',
    note => 'statement on the 14th',
);

# From a DBIish row hash (SQL column names, underscore form):
my $a = App::Moneymoor::Model::Account.new-from-row(%row);

say $a.is-on-budget;   # True for cash and credit, False for tracking
say $a.is-credit;      # True only for credit

=end code

=head1 DESCRIPTION

Three account types, and the difference between them is exactly which
part of the budget they touch:

=item C<cash> — current accounts, savings, physical cash. B<On
      budget>: their combined balance is the money the envelopes
      partition, and it is the right-hand side of the master
      invariant.
=item C<credit> — credit cards. B<On budget>: spending from one is
      real spending and hits your envelopes, but the balance is debt,
      not cash. Every credit account owns a C<payment> category that
      tracks the cash you have set aside to pay it.
=item C<tracking> — mortgages, pensions, an investment account you
      want to see but not budget from. B<Off budget>: their
      transactions never touch an envelope. Moving money to one is
      spending (categorized on the on-budget leg of the transfer);
      moving money from one is income.

C<closed> hides an account from pickers without deleting its history —
the same soft-retire idea as hiding a category. A closed account's
transactions still count towards balances and the budget, because
they really happened.

C<amount> signs live on transactions, not here: an account has no
stored balance at all. Balances are derived (see
C<App::Moneymoor::Service::Budget>), because a stored balance is a
cache that will eventually disagree with the transactions that
produced it.

=head1 ATTRIBUTES

=item C<id> — primary key; absent on a not-yet-inserted row.
=item C<name> — required, unique across accounts.
=item C<type> — C<cash> / C<credit> / C<tracking>; default C<cash>.
=item C<note> — free-form, default empty string.
=item C<closed> — Bool; default False.
=item C<sort-order> — display order; default 0.
=item C<created-at> — gateway-managed timestamp.

=head1 METHODS

=item C<new-from-row(%row)> — build from a DBIish row hash.
=item C<is-cash> / C<is-credit> / C<is-tracking> — type predicates.
=item C<is-on-budget> — True for C<cash> and C<credit>.

=end pod

unit class App::Moneymoor::Model::Account;

has Int  $.id;
has Str  $.name is required;
has Str  $.type = 'cash';
has Str  $.note = '';
has Bool $.closed = False;
has Int  $.sort-order = 0;
has Str  $.created-at;

method new-from-row(%row --> App::Moneymoor::Model::Account) {
    App::Moneymoor::Model::Account.new(
        id         => %row<id>,
        name       => %row<name> // '',
        type       => %row<type> // 'cash',
        note       => %row<note> // '',
        closed     => ?(%row<closed> // 0),
        sort-order => (%row<sort_order> // 0).Int,
        created-at => %row<created_at> // Str,
    );
}

method is-cash(--> Bool)      { $!type eq 'cash'     }
method is-credit(--> Bool)    { $!type eq 'credit'   }
method is-tracking(--> Bool)  { $!type eq 'tracking' }
method is-on-budget(--> Bool) { $!type eq 'cash' || $!type eq 'credit' }
