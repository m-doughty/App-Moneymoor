=begin pod

=head1 NAME

App::Moneymoor::Model::Assignment - money given to a category in a
budget period.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Model::Assignment;

my $a = App::Moneymoor::Model::Assignment.new(
    period      => '2026-03-01',
    category-id => $groceries,
    amount      => 40000,        # £400.00
);

my $loaded = App::Moneymoor::Model::Assignment.new-from-row(%row);

=end code

=head1 DESCRIPTION

An assignment is the only budgeting fact the user authors directly:
"in March, Groceries gets £400". It is a B<set>, not an increment —
there is exactly one row per C<(period, category)>, enforced by a
unique index, and C<Gateway::Assignment.set> upserts it. Moving money
between two categories is two upserts inside one SQL transaction
(C<move-money>), which is why the pair can never half-apply.

This model is deliberately scheme-ignorant: it carries the period key
it was given and has no opinion about whether that key is a start
under anybody's scheme. C<Gateway::Assignment> holds the scheme and
refuses to store a key that is not one; C<Service::Budget> holds it
again and skips such a row with a warning if one arrives from
somewhere else.

Amounts may be negative: pulling £50 back out of a category that was
never funded that period leaves C<-5000> assigned, and the engine
treats that exactly as it reads — the category has £50 less, Ready to
Assign has £50 more.

Assignments in B<future> periods are legal and deliberate. They are
deducted from Ready to Assign immediately, in every period, not just
in the period they land in: budgeting December's council tax in August
means August's Ready to Assign no longer offers you that money. See
rule 4 in C<App::Moneymoor::Service::Budget>.

Assigning to the C<rta> category is rejected by the gateway. "Ready to
Assign" is the pool assignments come I<from>; letting it be assigned
to would make the arithmetic circular.

=head1 ATTRIBUTES

=item C<id> — primary key; absent on a not-yet-inserted row.
=item C<period> — required C<YYYY-MM-DD>: the start date of the
      budget period the money belongs to. Under the default
      C<monthly/1> scheme that is always the first of a month, and the
      pre-period C<YYYY-MM> keys migrate by appending C<-01>; see
      C<App::Moneymoor::Util::Period>.
=item C<category-id> — required FK to C<categories.id>.
=item C<amount> — signed integer pence; default 0.

=head1 METHODS

=item C<new-from-row(%row)> — build from a DBIish row hash.

=end pod

unit class App::Moneymoor::Model::Assignment;

has Int $.id;
has Str $.period is required;
has Int $.category-id is required;
has Int $.amount = 0;

method new-from-row(%row --> App::Moneymoor::Model::Assignment) {
    App::Moneymoor::Model::Assignment.new(
        id          => %row<id>,
        period      => %row<period_start> // '',
        category-id => (%row<category_id> // 0).Int,
        amount      => (%row<amount> // 0).Int,
    );
}
