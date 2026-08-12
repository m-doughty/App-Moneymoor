=begin pod

=head1 NAME

App::Moneymoor::Model::CategoryGroup - a display grouping of
categories.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Model::CategoryGroup;

my $g = App::Moneymoor::Model::CategoryGroup.new(
    name       => 'Monthly Bills',
    sort-order => 10,
);

my $loaded = App::Moneymoor::Model::CategoryGroup.new-from-row(%row);
say "system group" if $loaded.is-system;   # engine-owned, undeletable

=end code

=head1 DESCRIPTION

Groups carry no budgeting semantics whatsoever — the engine never
sums a group, never rolls one over, and never moves money into one.
They exist so a budget with sixty categories is readable, and so a UI
has something to collapse.

One group is created by the migrations and marked C<system>:
B<Credit Card Payments>, the home for the payment category of every
credit account. C<Gateway::Category> refuses to delete or rename a
system group, because the payment categories the engine creates have
to land somewhere predictable.

C<hidden> retires a group from pickers without deleting it. Hiding a
group does not hide its categories — that is a per-category flag, and
conflating them would silently drop categories out of a budget that
still has money in them.

=head1 ATTRIBUTES

=item C<id> — primary key; absent on a not-yet-inserted row.
=item C<name> — required, unique.
=item C<sort-order> — display order; default 0.
=item C<hidden> — Bool; default False.
=item C<system> — Bool; True for engine-owned groups.

=head1 METHODS

=item C<new-from-row(%row)> — build from a DBIish row hash.
=item C<is-system> — True when the engine owns this group.

=end pod

unit class App::Moneymoor::Model::CategoryGroup;

has Int  $.id;
has Str  $.name is required;
has Int  $.sort-order = 0;
has Bool $.hidden = False;
has Bool $.system = False;

method new-from-row(%row --> App::Moneymoor::Model::CategoryGroup) {
    App::Moneymoor::Model::CategoryGroup.new(
        id         => %row<id>,
        name       => %row<name> // '',
        sort-order => (%row<sort_order> // 0).Int,
        hidden     => ?(%row<hidden> // 0),
        system     => ?(%row<system> // 0),
    );
}

method is-system(--> Bool) { $!system }
