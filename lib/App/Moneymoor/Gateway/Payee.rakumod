=begin pod

=head1 NAME

App::Moneymoor::Gateway::Payee - SQL gateway for payees.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Gateway::Payee;

my $gw = App::Moneymoor::Gateway::Payee.new(:$db);

my $tesco = $gw.find-or-create('Tesco');    # insert or fetch
my $again = $gw.find-or-create('  Tesco  ');
say $again.id == $tesco.id;                 # True — names are trimmed

my @all = $gw.find-all;                     # ordered by name
$gw.rename($tesco.id, 'Tesco Express');
$gw.delete($tesco.id);                      # transactions keep their
                                            # amounts, lose the name

=end code

=head1 DESCRIPTION

Payees are names. They carry no budgeting semantics and the engine
never reads them; they exist so a transaction list can be grouped and
searched by counterparty.

C<find-or-create> is the method to reach for when attaching a payee to
a transaction: names are unique, and doing "look it up, insert if
missing" in the caller invites two code paths that disagree about
trimming. Names are trimmed before comparison and storage, so
C<'Tesco'> and C<' Tesco '> are the same payee.

Deleting a payee nulls the reference on its transactions
(C<ON DELETE SET NULL>). Losing a name is an annoyance; losing a
transaction would be a corrupted budget.

=head1 ATTRIBUTES

=item C<db> — required C<App::Moneymoor::DB>.

=head1 METHODS

=item C<find-all(--> Array)> — ordered by name.
=item C<find-by-id(Int:D --> Model::Payee)> — type object when absent.
=item C<find-by-name(Str:D --> Model::Payee)>
=item C<create(Str:D $name --> Model::Payee)> — C<Failure> on a
      duplicate or empty name.
=item C<find-or-create(Str:D $name --> Model::Payee)>
=item C<rename(Int:D $id, Str:D $name)>
=item C<delete(Int:D $id)>
=item C<usage-count(Int:D $id --> Int)> — how many transactions point
      at it.

=end pod

unit class App::Moneymoor::Gateway::Payee;

use App::Moneymoor::DB;
use App::Moneymoor::Model::Payee;

has App::Moneymoor::DB $.db is required;

method find-all(--> Array) {
    $!db.query-all('SELECT * FROM payees ORDER BY name').map({
        App::Moneymoor::Model::Payee.new-from-row($_)
    }).Array;
}

method find-by-id(Int:D $id --> App::Moneymoor::Model::Payee) {
    my $row = $!db.query-one('SELECT * FROM payees WHERE id = ?', $id);
    return App::Moneymoor::Model::Payee unless $row && $row<id>;
    App::Moneymoor::Model::Payee.new-from-row($row);
}

method find-by-name(Str:D $name --> App::Moneymoor::Model::Payee) {
    my $row = $!db.query-one(
        'SELECT * FROM payees WHERE name = ?', $name.trim);
    return App::Moneymoor::Model::Payee unless $row && $row<id>;
    App::Moneymoor::Model::Payee.new-from-row($row);
}

method create(Str:D $name --> App::Moneymoor::Model::Payee) {
    my Str $trimmed = $name.trim;
    return fail 'Payee name cannot be empty' if $trimmed eq '';
    return fail "A payee named '$trimmed' already exists"
        if self.find-by-name($trimmed).defined;

    $!db.execute('INSERT INTO payees (name) VALUES (?)', $trimmed);
    self.find-by-id($!db.last-insert-id);
}

method find-or-create(Str:D $name --> App::Moneymoor::Model::Payee) {
    my Str $trimmed = $name.trim;
    return fail 'Payee name cannot be empty' if $trimmed eq '';
    my $existing = self.find-by-name($trimmed);
    return $existing if $existing.defined;
    self.create($trimmed);
}

method rename(Int:D $id, Str:D $name) {
    return fail "No payee with id $id" without self.find-by-id($id);
    my Str $trimmed = $name.trim;
    return fail 'Payee name cannot be empty' if $trimmed eq '';

    my $clash = self.find-by-name($trimmed);
    return fail "A payee named '$trimmed' already exists"
        if $clash.defined && $clash.id != $id;

    $!db.execute('UPDATE payees SET name = ? WHERE id = ?', $trimmed, $id);
    True;
}

method usage-count(Int:D $id --> Int) {
    my $row = $!db.query-one(
        'SELECT count(*) AS n FROM transactions WHERE payee_id = ?', $id);
    ($row<n> // 0).Int;
}

method delete(Int:D $id) {
    return fail "No payee with id $id" without self.find-by-id($id);
    $!db.execute('DELETE FROM payees WHERE id = ?', $id);
    True;
}
