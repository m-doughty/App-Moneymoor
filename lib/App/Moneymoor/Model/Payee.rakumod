=begin pod

=head1 NAME

App::Moneymoor::Model::Payee - who you paid, or who paid you.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Model::Payee;

my $p = App::Moneymoor::Model::Payee.new(name => 'Tesco');
my $loaded = App::Moneymoor::Model::Payee.new-from-row(%row);

=end code

=head1 DESCRIPTION

A payee is a name and nothing else. It carries no budgeting semantics
— the engine never looks at one — and exists so transactions can be
grouped and searched by counterparty, and so a future UI can offer
autocomplete and remembered categories.

Names are unique; C<Gateway::Payee.find-or-create> is the idiomatic
way to attach one to a transaction without racing on that uniqueness.
Deleting a payee nulls the reference on its transactions
(C<ON DELETE SET NULL>) rather than deleting them: losing a payee
name is an annoyance, losing a transaction is a corrupted budget.

Transfers do not use payees. The other leg of a transfer I<is> the
counterparty, and it is identified by C<transfer-peer-id> on the
transaction.

=head1 ATTRIBUTES

=item C<id> — primary key; absent on a not-yet-inserted row.
=item C<name> — required, unique.

=head1 METHODS

=item C<new-from-row(%row)> — build from a DBIish row hash.

=end pod

unit class App::Moneymoor::Model::Payee;

has Int $.id;
has Str $.name is required;

method new-from-row(%row --> App::Moneymoor::Model::Payee) {
    App::Moneymoor::Model::Payee.new(
        id   => %row<id>,
        name => %row<name> // '',
    );
}
