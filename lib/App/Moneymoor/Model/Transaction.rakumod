=begin pod

=head1 NAME

App::Moneymoor::Model::Transaction - money entering or leaving one
account on one day.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Model::Transaction;

# £42.50 of groceries on the Visa (outflow: negative):
my $spend = App::Moneymoor::Model::Transaction.new(
    account-id => $visa-id,
    date       => '2026-03-14',
    payee-id   => $tesco-id,
    amount     => -4250,
);

# £1,800 of salary into the current account (inflow: positive):
my $pay = App::Moneymoor::Model::Transaction.new(
    account-id => $current-id,
    date       => '2026-03-25',
    amount     => 180000,
);

my $t = App::Moneymoor::Model::Transaction.new-from-row(%row);
say $t.is-transfer;      # True when it has a peer leg
say $t.is-outflow;       # amount < 0

=end code

=head1 DESCRIPTION

C<amount> is integer pence, signed B<from the account's point of
view>: an inflow is positive, an outflow is negative. That single
convention is what makes an account balance a plain sum, and it holds
for every account type — spending £42.50 on a credit card is
C<-4250>, which drives the card's balance further negative (i.e.
deeper into debt).

A transaction is either B<categorized> or a B<transfer>:

=item Categorized: it owns one or more C<splits> whose amounts sum to
      C<amount>. A single-category transaction is just a transaction
      with one split — there is no separate "simple" shape to special
      case.
=item Transfer: C<transfer-peer-id> points at the other leg, which is
      a separate transaction on the other account with the negated
      amount and the same date. Transfers between two B<on-budget>
      accounts carry no splits at all: the money has not left the
      budget, so no envelope should move. (The one derived exception is
      a transfer involving a credit account, which moves that card's
      payment envelope — see C<App::Moneymoor::Service::Budget>.)
      A transfer to or from a B<tracking> account is different: money
      really is leaving or entering the budget, so the on-budget leg
      I<is> categorized and carries splits.

C<cleared> is the reconciliation state: C<uncleared> (you entered it),
C<cleared> (you saw it on the statement), C<reconciled> (locked as
part of a finished reconciliation). v0.1 stores it and reports
cleared / uncleared balances; the reconciliation workflow arrives with
the UI.

C<date> is C<YYYY-MM-DD> — no timezone, no time of day. A transaction
happens on a day, and a day is a calendar fact, not an instant.

It is B<not> bucketed here. Which budget period a date falls in
depends on the budget's period scheme (a calendar month, a month
anchored on payday, a four-weekly pay window), and this model does not
know the scheme and should not: a bucket derived from a date by a
scheme-ignorant model is right only for the default scheme and
silently wrong for every other one. C<Service::Budget> asks
C<App::Moneymoor::Util::Period> the question, once, with the scheme in
hand.

=head1 ATTRIBUTES

=item C<id> — primary key; absent on a not-yet-inserted row.
=item C<account-id> — required FK to C<accounts.id>.
=item C<date> — required C<YYYY-MM-DD>.
=item C<payee-id> — FK to C<payees.id>; null for transfers.
=item C<memo> — free-form, default empty string.
=item C<amount> — required signed integer pence.
=item C<cleared> — C<uncleared> / C<cleared> / C<reconciled>.
=item C<transfer-peer-id> — FK to the other leg's C<transactions.id>.
=item C<created-at> — gateway-managed timestamp.

=head1 METHODS

=item C<new-from-row(%row)> — build from a DBIish row hash.
=item C<is-inflow> / C<is-outflow> — amount sign predicates (a zero
      amount is neither).
=item C<is-transfer> — has a peer leg.
=item C<is-cleared> — cleared B<or> reconciled (the "has the bank
      seen it" question).
=item C<is-reconciled> — strictly reconciled.

=end pod

unit class App::Moneymoor::Model::Transaction;

has Int $.id;
has Int $.account-id is required;
has Str $.date is required;
has Int $.payee-id;
has Str $.memo = '';
has Int $.amount is required;
has Str $.cleared = 'uncleared';
has Int $.transfer-peer-id;
has Str $.created-at;

method new-from-row(%row --> App::Moneymoor::Model::Transaction) {
    App::Moneymoor::Model::Transaction.new(
        id               => %row<id>,
        account-id       => (%row<account_id> // 0).Int,
        date             => %row<date> // '',
        payee-id         => %row<payee_id> // Int,
        memo             => %row<memo> // '',
        amount           => (%row<amount> // 0).Int,
        cleared          => %row<cleared> // 'uncleared',
        transfer-peer-id => %row<transfer_peer_id> // Int,
        created-at       => %row<created_at> // Str,
    );
}

method is-inflow(--> Bool)     { $!amount > 0 }
method is-outflow(--> Bool)    { $!amount < 0 }
method is-transfer(--> Bool)   { $!transfer-peer-id.defined }
method is-cleared(--> Bool)    { $!cleared eq 'cleared' || $!cleared eq 'reconciled' }
method is-reconciled(--> Bool) { $!cleared eq 'reconciled' }
