=begin pod

=head1 NAME

App::Moneymoor - YNAB-style envelope budgeting: a derivation engine
over an encrypted SQLite file, and a terminal UI that drives it.

=head1 SYNOPSIS

Run the app:

=begin code :lang<shell>

moneymoor                      # or: raku -I lib bin/moneymoor
moneymoor --version
MONEYMOOR_HOME=/tmp/demo moneymoor    # a throwaway data home

=end code

Or use the engine directly:

=begin code :lang<raku>

use MacOS::NativeLib <sqlcipher>;   # macOS only — see PORTABILITY
use App::Moneymoor;
use App::Moneymoor::DB;
use App::Moneymoor::Service::Workspace;
use App::Moneymoor::Model::Account;
use App::Moneymoor::Model::Category;
use App::Moneymoor::Model::Transaction;
use App::Moneymoor::Model::Split;

say App::Moneymoor.version;             # v0.3.1

my $db = App::Moneymoor::DB.new(:db-path("$*HOME/.moneymoor/budget.db"));
$db.connect('correct horse battery staple');

my $ws = App::Moneymoor::Service::Workspace.new(:$db);

my $current = $ws.accounts.create(App::Moneymoor::Model::Account.new(
    name => 'Current Account', type => 'cash'));
my $food = $ws.categories.create(App::Moneymoor::Model::Category.new(
    name => 'Groceries'));
my $rta = $ws.categories.rta-category;

# £1,800 in:
$ws.transactions.create(
    App::Moneymoor::Model::Transaction.new(
        account-id => $current.id, date => '2026-03-01', amount => 180000),
    splits => [App::Moneymoor::Model::Split.new(
        category-id => $rta.id, amount => 180000)],
);

# Give it a job. Budgets are keyed by period start; under the default
# calendar-month scheme that is the first of the month.
$ws.set-assigned('2026-03-01', $food.id, 40000);

my $view = $ws.budget(through-period => '2026-03-01');
say $view.rta('2026-03-01');                            # 140000
say $view.category('2026-03-01', $food.id).available;   # 40000

$db.disconnect;

=end code

=head1 DESCRIPTION

Moneymoor is an envelope budget: every pound you have gets a job
before you spend it. It is the "give every pound a job, budget only
money you actually hold, roll the rest forward" school of budgeting —
the same model YNAB popularised — implemented as a Raku library over
an encrypted SQLite (SQLCipher) file.

The engine came first and is still usable on its own — everything
under C<Model>, C<Gateway>, C<Service> and C<DB> is a library with no
opinion about how you look at it. On top of that sits a C<Selkie>
terminal UI, C<bin/moneymoor>, which is what most people will actually
use — see L<#THE TERMINAL UI> below.

=head2 WHAT IT IS BUILT ON

=item B<Facts in, everything else derived.> The database stores only
      what you authored: accounts, categories, transactions with their
      splits, and per-period assignments. Balances, activity, available,
      Ready to Assign and credit-card payment moves are recomputed on
      demand by a pure function. Nothing derived is stored, so nothing
      derived can drift.
=item B<The master invariant.> Envelopes partition cash:
      C<Σ available + RTA == Σ cash-account balances>. Its general
      form (with future assignments and uncovered card spending) is
      checked for every period by C<BudgetView.invariant-errors> and
      asserted after every operation by the property test suite.
=item B<Integer pence.> No floats, no C<Rat>s, anywhere. A budget that
      has to prove an equality cannot afford lossy addition.
=item B<Encrypted at rest.> One SQLCipher file, keyed on connect.

=head2 THE PIECES

=item C<App::Moneymoor::DB> — SQLCipher connection, migrations
      (additive ones replayed on every connect, transforming ones
      gated on a schema revision), transactions.
=item C<App::Moneymoor::Model::*> — attribute-only row classes.
=item C<App::Moneymoor::Gateway::*> — the SQL, and the invariants that
      have to hold before a row is written (splits sum to their
      transaction, transfers come in pairs, every credit account owns a
      payment envelope).
=item C<App::Moneymoor::Service::Budget> — the pure derivation. Its
      Pod is the specification of the budgeting semantics, with worked
      numbers for each of the four rules.
=item C<App::Moneymoor::Service::Workspace> — gateways in, derived
      budget out. Owns the budget's period scheme and is the only
      layer that reads the clock.
=item C<App::Moneymoor::Service::Target> — what an envelope's target
      asks for in the period you are looking at. Pure, and the only
      module that knows what the three target kinds mean.
=item C<App::Moneymoor::Util::Period> — what a budget period is: a
      calendar month, a month anchored on payday, or an every-N-weeks
      pay window. Pure, and the only module that knows.
=item C<App::Moneymoor::Util::Money> — pence ↔ C<"£12.34">.

=head2 WHAT IT DOES NOT DO

Scheduled transactions, CSV or bank imports, multi-currency,
incremental rollup caching, and net worth over time (which needs a
per-month, per-account balance derivation the engine does not have
yet).

B<Targets> do exist — see the Budget tab below — but note where they
live: on the category row, read by the view layer, and invisible to
C<Service::Budget>. There are three kinds of them — refill to a level,
set aside an amount each period, and reach an amount by a period, the
last with a milestone schedule and optional repeat — and all three are
derived by C<Service::Target> from figures the engine produced for its
own reasons. The engine still derives money from facts alone, and a
target is not a fact about money that has moved. The Budget tab's
envelope editor sets refill targets; the other two kinds are engine
capabilities today.

=head1 THE TERMINAL UI

C<bin/moneymoor> launches it; C<--version> and C<--help> are the only
things it will do without a terminal. Everything else — creating a
budget, assigning money, entering transactions, reconciling a
statement — happens inside, from the keyboard.

=head2 Logging in

Budgets live in the B<data home>, C<~/.moneymoor/>, one encrypted
C<*.db> file each. Set C<MONEYMOOR_HOME> to put them somewhere else;
the config file, the budget list and the error log all move together,
which is what makes a throwaway run safe.

The first screen lists the budgets it found and asks for a passphrase,
or — with none to list, or on C<Ctrl+N> — offers to create one. That
passphrase B<is> the encryption key: there is no reset, no recovery
question and no copy of it anywhere. A wrong one is reported
differently from a wrong file, because they are different mistakes.

=head2 Inside

Three tabs, C<1> / C<2> / C<3> (also C<Ctrl+1> / C<Ctrl+2> / C<Ctrl+3>
on terminals that can send it):

=item B<Budget> — the envelope grid for one month, grouped, with
      Ready-to-Assign above it and a detail rail beside it that shows
      exactly how an envelope's available figure was arrived at.
      C<a> assigns, C<m> moves money between envelopes, C<x> explains a
      derived number, C<[> and C<]> change period. Give an envelope a
      B<target> in its editor and the grid gains a Target
      column, the rail says how much is still to fund, the assign
      field takes C<=450> ("make it £450") and a bare C<=> ("make it
      the target"), and C<f> funds every underfunded envelope at once
      in a single write.
=item B<Accounts> — the ledgers on the left, the register on the
      right. C<n> adds a transaction (with splits), C<t> a transfer,
      C<c> cycles uncleared → cleared → reconciled, C<Ctrl+R> starts a
      reconciliation against a statement balance.
=item B<Reports> — the month's cash flow, and where the money went.

C<Ctrl+H> lists the keys for whatever has focus; the bottom line
always shows the important ones. C<Ctrl+G> opens diagnostics — the
derivation's warnings, invariant errors and a digest fingerprint safe
to paste into a bug report. C<Ctrl+,> opens settings: eleven palettes
and a glyph tier (plain Unicode or Nerd Font), applied live and
remembered in C<~/.moneymoor/config.json>.

=head2 The UI's pieces

=item C<App::Moneymoor::UI> — the entry point: app construction, the
      login handshake, the hand-off to the main screen.
=item C<App::Moneymoor::Screen::*> — Login, the Main shell, and one
      controller per tab.
=item C<App::Moneymoor::StoreHandlers> — the state shape, and the
      single effect every mutation in the app funnels through.
=item C<App::Moneymoor::View::*> — the row and span builders, pure and
      unit-tested; no widget code decides what a number says.
=item C<App::Moneymoor::Theme> / C<Themes> / C<Service::Icons> —
      palette and glyph tiers.

=head1 PORTABILITY

The C<sqlcipher> shared library has to be loadable by NativeCall. On
macOS, C<<use MacOS::NativeLib <sqlcipher>;>> before the first
C<use App::Moneymoor::DB> points NativeCall at the Homebrew install.
On Linux the system loader finds a distro sqlcipher by itself only
when its soname is C<libsqlcipher.so.0>; modern Debian and Ubuntu
(24.04+) package soname 1, which DBIish's built-in lookup refuses —
point C<DBIISH_SQLCIPHER_LIB> at the library
(C</usr/lib/x86_64-linux-gnu/libsqlcipher.so.1>) and it is loaded
verbatim. On Windows the DLL just has to be on C<PATH>. Nothing else
in the distribution is platform-specific, and the pure engine
(C<Service::Budget>, C<Util::Money>, every C<Model>) needs no native
library at all.

=head1 AUTHOR

Matt Doughty <matt@apogee.guru>

=head1 COPYRIGHT AND LICENSE

Copyright 2026 Matt Doughty

This library is free software; you can redistribute it and/or modify
it under the Artistic License 2.0.

=end pod

unit class App::Moneymoor;

#| The distribution version, for callers that want to record which
#| engine derived a budget they are storing alongside it. Kept in step
#| with C<META6.json> by C<t/85-distribution.rakutest>.
method version(--> Version) { v0.3.2 }
