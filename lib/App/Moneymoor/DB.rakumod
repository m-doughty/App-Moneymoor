=begin pod

=head1 NAME

App::Moneymoor::DB - SQLCipher connection wrapper, idempotent schema
migration, and the transaction seam every gateway writes through.

=head1 SYNOPSIS

=begin code :lang<raku>

use MacOS::NativeLib <sqlcipher>;   # macOS only; see PORTABILITY
use App::Moneymoor::DB;

my $db = App::Moneymoor::DB.new(:db-path("$*HOME/.moneymoor/budget.db"));
my $result = $db.connect('correct horse battery staple');

if $result ~~ Failure {
    say "could not open: { $result.exception.message }";
    $result.so;                     # mark handled
    exit 1;
}

my @rows = $db.query-all(
    'SELECT id, name FROM accounts WHERE closed = 0 ORDER BY sort_order, id');
my $row  = $db.query-one('SELECT * FROM accounts WHERE id = ?', $id);

$db.execute('UPDATE accounts SET name = ? WHERE id = ?', 'Current', $id);

# Multi-statement atomicity — either both writes land or neither does.
$db.run-txn: {
    $db.execute('UPDATE assignments SET amount = ? WHERE id = ?', $a, $x);
    $db.execute('UPDATE assignments SET amount = ? WHERE id = ?', $b, $y);
};

$db.disconnect;

=end code

=head1 DESCRIPTION

A single-connection wrapper over DBIish's SQLCipher driver.
C<connect($passphrase)> opens the file (creating it when absent),
keys the encryption layer, applies connection pragmas, and runs
migrations. A bad passphrase returns a C<Failure> via C<fail> rather
than throwing, so a login screen can report it without a C<CATCH>.

v0.1 is a headless library used from one thread, so this layer is
deliberately thin: one handle, no WAL, no writer actor. The method
surface (C<execute> / C<query-one> / C<query-all> / C<run-txn>) is
the same shape as C<App::Cantina::DB>'s actor-backed DB, so a future
TUI can drop the actor in underneath without touching a single
gateway.

=head2 DBIISH TRAPS THIS LAYER ABSORBS

Three DBDish behaviours bite every caller that talks to the driver
directly. They are handled once, here:

=item B<Unfinalized SELECTs hold a read transaction.> A statement
      handle whose rows have not been consumed keeps an implicit read
      transaction open on the connection, which makes a later DDL
      statement or C<BEGIN IMMEDIATE> fail. C<query-one> / C<query-all>
      always drain with C<.allrows(:array-of-hash)> into a real
      C<Array>, and the C<pragma> helper drains with
      C<.allrows.eager>.
=item B<Several pragmas return a row.> C<busy_timeout>,
      C<journal_mode>, C<foreign_keys> and friends answer with a
      value. Executed and left unfetched they trip DBIish's deferred
      "rows() may not be accurate" warning at handle finalization —
      hence C<pragma>, which drains and hands back whatever came out.
=item B<Leaked statement handles hold schema locks.> DDL issued
      through a handle that is never disposed can block a later
      C<ALTER> / C<DROP> with C<SQLITE_LOCKED>. Writes go through
      DBDish's C<.do>, which disposes the statement handle in a
      C<LEAVE> block.

=head2 WRONG KEY VS PLAINTEXT FILE

On an existing file, C<connect> proves the key by reading
C<sqlite_master>. When that read fails the file is either encrypted
with a different passphrase or not encrypted at all. The two are
distinguishable — a SQLCipher database begins with random-looking
bytes, a plain SQLite file begins with the ASCII header
C<SQLite format 3> — so the caller gets a specific message for the
"you pointed me at an unencrypted DB" case, and a hedged one
("invalid passphrase (or corrupted profile)") otherwise, because
genuine corruption is I<not> distinguishable from a wrong key.

=head2 SCHEMA

All money columns are C<INTEGER> pence. All dates are C<TEXT> in
C<YYYY-MM-DD>, and so are all budget-period keys — a period is named by
its own start date, so C<assignments.period_start> holds C<'2026-03-01'>
under the calendar-month scheme and C<'2026-08-14'> under a scheme
anchored on payday. See C<App::Moneymoor::Util::Period>.

=item C<budget_meta> — a two-column C<key>/C<value> table for facts
      about the file itself rather than about the money in it:
      C<schema_rev> (which transforming migrations have run) and
      C<period_scheme>, the budget's own period scheme as JSON, written
      by C<Service::Workspace.change-scheme> and read back by it at
      construction. A key that is absent is not an error — for
      C<schema_rev> it means revision 0, and for the scheme it means the
      calendar month.
=item C<accounts> — C<type> is C<cash> / C<credit> / C<tracking>.
      C<cash> and C<credit> are I<on budget>; C<tracking> accounts
      hold assets or debts you want visible without them funding
      envelopes.
=item C<category_groups> — display grouping. C<system = 1> marks
      groups the engine owns (the credit-card payment group); the
      gateway refuses to delete them.
=item C<categories> — C<kind> is C<standard> / C<payment> / C<rta>.
      Exactly one C<rta> row is seeded by migrations (Ready to
      Assign, the inflow target). One C<payment> row exists per
      credit account, linked by the C<UNIQUE> C<payment_account_id>
      and created atomically with the account by
      C<Gateway::Account.create>. C<target_pence> is the envelope's
      target amount, C<0> meaning "no target" — never NULL, so no
      read site has to guard for one. It is added by C<ensure-column>
      rather than by the C<CREATE>, because budget files predating it
      exist; see SCHEMA EVOLUTION.

      Four more C<ensure-column>s say what B<kind> of target it is.
      C<target_kind> is C<refill> (the default and the whole of v0.1:
      "available should be this much each period"), C<set_aside> ("put
      this much in each period") or C<by_period> ("reach this much by
      period E"), under a C<CHECK> on those three. C<target_period>
      and C<target_start> are nullable date strings used only by
      C<by_period> — the goal and the stamped plan start, each read as
      B<the period containing it>, so a scheme change re-derives the
      plan rather than invalidating it. C<target_repeat> is C<0> for a
      one-shot goal and C<R E<gt>= 1> for one that repeats every C<R>
      periods. What the tuple B<means> is
      L<App::Moneymoor::Service::Target>'s subject; what may be stored
      in it is C<Gateway::Category>'s.

      C<carry_overspend> is an C<ensure-column> of the same shape and
      nothing to do with targets: C<0> (the default, and what every
      legacy row means) puts the envelope on rule 3's forcing rule —
      cash overspending resets it to zero and charges Ready to Assign —
      and C<1> carries the negative forward instead, as a payment
      envelope's always has. See L<App::Moneymoor::Service::Budget>.
=item C<payees> — names only; deleting one nulls the reference on its
      transactions.
=item C<transactions> — C<amount> is signed from the account's point
      of view (inflow positive, outflow negative).
      C<transfer_peer_id> points at the other leg of a transfer.
=item C<splits> — the categorized parts of a transaction; their sum
      must equal the transaction's amount (enforced in
      C<Gateway::Transaction>, inside one SQL transaction).
      Transfers between two on-budget accounts carry B<no> splits.
=item C<assignments> — one row per C<(period_start, category_id)>, the
      money you gave a category in that budget period. Enforced by a
      C<UNIQUE> index, so the gateway can upsert.

Deterministic ordering is C<(date ASC, id ASC)> for transactions and
C<(period_start ASC, id ASC)> for assignments — the budget derivation
depends on it, so the indices exist to make it cheap. Period keys are
fixed-width ISO dates, so SQLite's text ordering on C<period_start> is
chronological ordering, exactly as the engine's own C<lt> / C<gt>
comparisons are.

=head2 SCHEMA EVOLUTION

C<run-migrations> is replayed in full on every connect, so every
migration has to be safe to run against a file that has already had
it. Three patterns cover every case, and the first two are preferred
precisely because they need no bookkeeping:

=item B<Additive tables / indices> — every C<CREATE> is wrapped in
      C<IF NOT EXISTS>, so replaying is a no-op and new objects simply
      appear.
=item B<Additive columns> — C<ensure-column> checks
      C<PRAGMA table_info> and issues C<ALTER TABLE ... ADD COLUMN>
      only when the column is missing. SQLite has no
      C<ADD COLUMN IF NOT EXISTS>, and this is the only idempotent
      substitute. A C<CHECK> constraint and a C<REFERENCES> clause
      (with a NULL default) may ride along on the added column;
      C<PRIMARY KEY>, C<UNIQUE> and non-constant C<NOT NULL> defaults
      may not. An index over a newly added column must be created
      I<after> the C<ensure-column> call, or it fails on a legacy
      file where the column does not exist yet.
      C<categories.target_pence> is the worked example: a
      C<NOT NULL DEFAULT 0> column whose default is also the right
      value for every pre-existing row, which is what makes the
      migration a single line with no backfill behind it. The four
      C<target_kind> / C<target_period> / C<target_start> /
      C<target_repeat> columns that followed it are the same shape
      again, C<CHECK> constraint and nullable dates included: a legacy
      row reads as C<'refill'> with no dates and no repeat, which is
      exactly what it always meant. C<carry_overspend> is the sixth,
      and the clearest statement of why the pattern works: its default
      of C<0> is not merely a sensible value for a legacy row, it is
      the rule every period in that file was already derived under.
=item B<One-shot transforming migrations>, gated on C<schema_rev> in
      C<budget_meta>. For anything that B<rewrites data the user
      already has>.

=head3 Why a transform cannot be replay-idempotent

The other two patterns are idempotent because they are I<statements
about the desired shape>: "there should be a table like this", "there
should be a column like this". Running them twice asks for the same
shape twice.

A transform is not a statement about a shape, it is a function applied
to rows — and applying it twice applies it twice.
C<period_start || '-01'> takes C<'2026-03'> to C<'2026-03-01'> and then
takes that to C<'2026-03-01-01'>. There is no C<IF NOT ALREADY DONE>
to wrap it in, because "already done" is not visible in the schema:
after the rename the column looks exactly the same whether the rewrite
ran or not. So the fact that it ran has to be B<recorded>, and
C<budget_meta.schema_rev> is that record. C<SCHEMA-REV> is the
revision this code writes; a file stamped with it, or with anything
higher, skips the transform entirely.

Guards on the data are a useful second line — the C<WHERE length(...)
= 7> above means a double-run would be a no-op rather than a
corruption — but they are not the mechanism, because not every
transform has a predicate that distinguishes done from not-done.

=head3 The worked example: months to period starts

Revision 1 re-keys C<assignments> from calendar months (C<'2026-03'>)
to budget-period starts (C<'2026-03-01'>). Its four steps, in one
C<run-txn>:

=item drop the two indices naming the old column — SQLite carries an
      index across a C<RENAME COLUMN>, so leaving them would leave the
      index set described by history rather than by the C<CREATE>s;
=item C<ALTER TABLE assignments RENAME COLUMN month TO period_start>;
=item C<UPDATE ... SET period_start = period_start || '-01'
      WHERE length(period_start) = 7> — under C<monthly/1>, the scheme
      every pre-period file was implicitly using, the period containing
      a month starts on its first day, so the entire re-key is a
      suffix;
=item stamp C<schema_rev> = 1.

Two things make it safe. SQLite's DDL is transactional, so the rename,
the rewrite and the stamp commit or roll back together and a crash
mid-migration reopens the file as either the old shape or the new one,
never as a mixture. And the legacy shape is detected by asking
C<PRAGMA table_info> for a C<month> column rather than by trusting the
stamp — the real dogfood file has never had a C<budget_meta> table at
all, so its C<schema_rev> reads as absent on the very connect that
creates the table, and a fresh file reads exactly the same. The column
is the fact; the stamp only says whether the transform has been
applied.

The new indices are created after the gate, for the same reason an
index over an C<ensure-column> column is: an index on C<period_start>
cannot be created while a legacy file still calls it C<month>.

=head3 What still has no pattern

Widening a C<CHECK> constraint (say, a fourth account type) is B<not>
additive — SQLite stores C<CHECK> as part of the table text — and
needs the rename/recreate/copy/drop dance with a dedicated fresh
connection. v0.1 ships no such migration; when one is needed, port
C<App::Mindmoor::DB>'s C<!ensure-status-check-values>.

=head2 SEED DATA

Migrations seed two system rows, both guarded by
C<INSERT ... SELECT ... WHERE NOT EXISTS> so re-running is a no-op:

=item the C<rta> category ("Ready to Assign") — the inflow target.
      It is not an envelope: it has no carry, and assigning to it is
      rejected by C<Gateway::Assignment>.
=item the C<Credit Card Payments> group (C<system = 1>) — the home
      for the payment category of every credit account.

=head1 ATTRIBUTES

=item C<db-path> — required at construction. The file is created on
      first connect.

=head1 METHODS

=item C<connect($passphrase)> — open, key, pragma, migrate. Returns
      C<self>, or a C<Failure> when the key does not open the file.
=item C<disconnect> — dispose the handle. Safe to call twice.
=item C<is-connected(--> Bool)>
=item C<handle> — the raw DBIish connection, for the rare caller that
      needs C<last_insert_rowid()> semantics this class does not wrap.
=item C<execute($sql, *@bind)> — write path (C<.do> under the hood).
=item C<query-one($sql, *@bind --> Hash)> — first row, or an empty
      C<Hash> when nothing matched.
=item C<query-all($sql, *@bind --> Array)> — every row as a C<Hash>.
=item C<last-insert-id(--> Int)> — the rowid of the most recent
      insert on this connection.
=item C<ensure-column($table, $column, $decl)> — additive column
      migration; no-op when the column already exists.
=item C<get-meta(Str:D $key --> Str)> — one C<budget_meta> value, or
      the C<Str> type object when the key has never been written.
      Absence is an answer, not an error, and is deliberately
      distinguishable from a stored empty string.
=item C<set-meta(Str:D $key, Str:D $value)> — upsert one
      C<budget_meta> value.
=item C<in-transaction(--> Bool)> — True inside a C<run-txn> closure.
=item C<run-txn(&work)> — run C<&work> inside
      C<BEGIN IMMEDIATE> … C<COMMIT>, rolling back and rethrowing on
      exception. Re-entrant: a C<run-txn> nested inside another joins
      the outer transaction instead of nesting (SQLite has no nested
      transactions without savepoints).

=head1 PORTABILITY

The C<sqlcipher> shared library has to be findable by NativeCall.
On macOS that means C<use MacOS::NativeLib E<lt>sqlcipherE<gt>;>
before C<use DBIish> (Homebrew installs it outside the default search
path); on Linux and Windows the system loader finds the installed
library on its own. This module deliberately does not C<use
MacOS::NativeLib> itself — it is a macOS-only distribution and
depending on it here would make every Linux consumer install it.

=end pod

unit class App::Moneymoor::DB;

use DBIish;

#| The schema revision this code writes and knows how to read. Bumped
#| only for a B<transforming> migration — additive tables, indices and
#| columns need no stamp, because replaying them is a no-op. See
#| SCHEMA EVOLUTION.
constant SCHEMA-REV = 1;

#| Where that number lives in C<budget_meta>.
constant SCHEMA-REV-KEY = 'schema_rev';

has Str  $.db-path is required;
has      $!dbh;
has Bool $!connected = False;
has Bool $!in-txn    = False;

# Several pragmas answer with a row; leaving it unfetched trips
# DBIish's deferred "rows() may not be accurate" warning at handle
# finalization, and an undrained statement holds a read transaction
# that blocks the DDL immediately after it. Drain eagerly and hand
# back whatever came out.
my sub pragma($dbh, Str:D $sql) {
    $dbh.execute($sql).allrows.eager;
}

method connect(Str:D $passphrase) {
    my Bool $is-new = !$!db-path.IO.e;

    $!dbh = DBIish.connect('SQLCipher', database => $!db-path);
    $!dbh.key($passphrase);

    # Prove the key by reading the schema table. Drain the result
    # fully: an unfinalized SELECT holds an implicit read transaction
    # on the connection, which the migration DDL below would then
    # trip over.
    unless $is-new {
        my $ok = try {
            $!dbh.execute('SELECT count(*) FROM sqlite_master').allrows.eager;
            True;
        };
        unless $ok {
            $!dbh.dispose;
            $!dbh = Nil;
            return fail self!looks-like-plaintext-sqlite
                ?? "Not an encrypted budget file (plain SQLite file)"
                !! "Invalid passphrase (or corrupted budget file)";
        }
    }

    # 5s busy timeout: v0.1 is single-connection, but a second process
    # (a backup script, a second app window) opening the same file
    # should wait rather than fail instantly.
    pragma($!dbh, 'PRAGMA busy_timeout=5000');
    # Foreign keys are OFF by default in SQLite and are a per-connection
    # setting, not a file setting — it has to be re-issued on every
    # connect or the schema's referential integrity is decorative.
    pragma($!dbh, 'PRAGMA foreign_keys=ON');

    $!connected = True;
    # Migrations are CREATE ... IF NOT EXISTS plus additive column
    # checks, so running them on every connect is idempotent and
    # picks up anything a newer version added.
    self!run-migrations;
    self;
}

#| A SQLCipher file starts with encrypted (random-looking) bytes; an
#| unencrypted SQLite file starts with the ASCII header
#| "SQLite format 3\0". Only the second case is positively
#| identifiable, which is why the caller's other branch hedges.
method !looks-like-plaintext-sqlite(--> Bool) {
    return False unless $!db-path.IO.e;
    my $blob = try $!db-path.IO.open(:bin).read(16);
    return False without $blob;
    return False unless $blob.elems >= 15;
    $blob.subbuf(0, 15).decode('latin-1') eq 'SQLite format 3';
}

method handle() { $!dbh }
method is-connected(--> Bool) { $!connected }

method disconnect() {
    if $!dbh {
        $!dbh.dispose;
        $!dbh       = Nil;
        $!connected = False;
        $!in-txn    = False;
    }
}

method execute(Str:D $sql, *@bind) {
    # DBDish's `do` disposes the prepared statement in a LEAVE block.
    # Necessary for DDL and inserts alike: a leaked statement handle
    # holds a sqlite3 schema-level lock that blocks later ALTER / DROP
    # with SQLITE_LOCKED, and a manual dispose outside DBDish's own
    # statement tracking does not reliably release it.
    $!dbh.do($sql, |@bind);

    # `do` asks the statement for its row count, and DBDish::SQLCipher
    # warns whenever that count cannot be trusted — which includes
    # every statement that raised an error, i.e. every write a caller
    # is about to see throw anyway. We never read `do`'s return value,
    # so the warning is pure noise on the way to an exception the
    # caller already handles. Only that one message is swallowed;
    # anything else resumes as a normal warning.
    CONTROL {
        when CX::Warn {
            .resume if .message.starts-with('SQLCipher rows()');
        }
    }
}

method query-one(Str:D $sql, *@bind --> Hash) {
    my $sth  = $!dbh.execute($sql, |@bind);
    my @rows = $sth.allrows(:array-of-hash);
    @rows.elems > 0 ?? @rows[0].Hash !! Hash.new;
}

method query-all(Str:D $sql, *@bind --> Array) {
    my $sth  = $!dbh.execute($sql, |@bind);
    my @rows = $sth.allrows(:array-of-hash);
    @rows.Array;
}

#| The rowid of the most recent INSERT on this connection. Only
#| meaningful immediately after the insert (and, since this class owns
#| exactly one connection, never confused by another writer).
method last-insert-id(--> Int) {
    my $row = self.query-one('SELECT last_insert_rowid() AS id');
    ($row<id> // 0).Int;
}

#| Run &work inside BEGIN IMMEDIATE … COMMIT. Any exception rolls the
#| transaction back and is rethrown, so a gateway can validate mid-way
#| and abort by dying. Nested calls join the outer transaction —
#| SQLite has no nested BEGIN, and a gateway method that opens its own
#| transaction must still compose inside a caller's.
method run-txn(&work) {
    return work() if $!in-txn;

    self.execute('BEGIN IMMEDIATE');
    $!in-txn = True;

    my $result;
    {
        $result = work();
        CATCH {
            default {
                $!in-txn = False;
                # Roll back on a best-effort basis: if the rollback
                # itself fails (connection gone), the original error is
                # still the one worth reporting.
                try self.execute('ROLLBACK');
                .rethrow;
            }
        }
    }

    $!in-txn = False;
    self.execute('COMMIT');
    $result;
}

#| One value out of C<budget_meta>, or the C<Str> type object when the
#| key has never been written. Absence is a meaningful answer here —
#| "this budget file has no opinion", which for the period scheme means
#| the calendar month and for C<schema_rev> means revision 0 — so it is
#| distinguishable from an empty string, which a caller may legitimately
#| have stored.
method get-meta(Str:D $key --> Str) {
    my $row = self.query-one(
        'SELECT value FROM budget_meta WHERE key = ?', $key);
    return Str unless $row && $row<value>.defined;
    $row<value>.Str;
}

#| Write one value into C<budget_meta>, replacing whatever was there.
#| An upsert rather than a delete-then-insert: the key is the primary
#| key, so a conflict clause is exact, and a caller that writes the
#| same key twice must not depend on which write it was.
method set-meta(Str:D $key, Str:D $value) {
    self.execute(
        q:to/SQL/,
            INSERT INTO budget_meta (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            SQL
        $key, $value,
    );
    True;
}

#| True while a run-txn closure is executing. Gateways check this to
#| assert their "validate before you open a transaction" contract:
#| a `fail` inside a transaction would return a Failure while the
#| transaction quietly commits.
method in-transaction(--> Bool) { $!in-txn }

method !run-migrations() {
    # First, unconditionally: everything below may need to ask what
    # revision this file is at, and a file older than budget_meta has
    # no way to answer until the table exists.
    self.execute(q:to/SQL/);
        CREATE TABLE IF NOT EXISTS budget_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
        SQL

    self.execute(q:to/SQL/);
        CREATE TABLE IF NOT EXISTS accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            type TEXT NOT NULL DEFAULT 'cash'
                CHECK(type IN ('cash','credit','tracking')),
            note TEXT NOT NULL DEFAULT '',
            closed INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
        SQL

    self.execute(q:to/SQL/);
        CREATE TABLE IF NOT EXISTS category_groups (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            sort_order INTEGER NOT NULL DEFAULT 0,
            hidden INTEGER NOT NULL DEFAULT 0,
            system INTEGER NOT NULL DEFAULT 0
        )
        SQL

    # payment_account_id is UNIQUE so a credit account can never end up
    # with two payment envelopes; ON DELETE CASCADE so deleting the
    # account takes its envelope with it.
    self.execute(q:to/SQL/);
        CREATE TABLE IF NOT EXISTS categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            group_id INTEGER REFERENCES category_groups(id) ON DELETE SET NULL,
            name TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'standard'
                CHECK(kind IN ('standard','payment','rta')),
            payment_account_id INTEGER UNIQUE
                REFERENCES accounts(id) ON DELETE CASCADE,
            sort_order INTEGER NOT NULL DEFAULT 0,
            hidden INTEGER NOT NULL DEFAULT 0
        )
        SQL
    # The first additive migration: budget files written by v0.2.0 and
    # earlier have no target column. Zero is "no target", so the
    # constant default is also the correct value for every row in a
    # legacy file — nothing has to be backfilled.
    self.ensure-column('categories', 'target_pence',
                       'INTEGER NOT NULL DEFAULT 0');
    # The target kinds, added the same way and for the same reason. A
    # legacy row's defaults ('refill', no dates, no repeat) describe
    # exactly what it already meant — "available should be this much
    # each period" was the only kind there was — so this migration too
    # is four lines with no backfill behind it.
    #
    # The two dates are nullable because only 'by_period' has them, and
    # they are TEXT rather than anything richer because SQLite has no
    # date type and the rest of the app already keys periods on
    # 'YYYY-MM-DD' strings. They are read as "the period containing
    # this date", so a scheme change re-derives the plan instead of
    # invalidating it — see App::Moneymoor::Service::Target.
    self.ensure-column('categories', 'target_kind',
                       "TEXT NOT NULL DEFAULT 'refill'
                        CHECK(target_kind IN ('refill','set_aside','by_period'))");
    self.ensure-column('categories', 'target_period', 'TEXT');
    self.ensure-column('categories', 'target_start',  'TEXT');
    self.ensure-column('categories', 'target_repeat',
                       'INTEGER NOT NULL DEFAULT 0');
    # Which of rule 3's two cash-overspending rules an envelope is on
    # (App::Moneymoor::Model::Category, "CARRYING A NEGATIVE"). Additive
    # for the same reason the target columns are: 0 is "reset to zero
    # and charge Ready to Assign", which is the rule every period of
    # every legacy file was derived under, so the constant default is
    # also the correct value for every row already in the table.
    self.ensure-column('categories', 'carry_overspend',
                       'INTEGER NOT NULL DEFAULT 0');
    self.execute('CREATE INDEX IF NOT EXISTS idx_categories_group ON categories(group_id)');
    self.execute('CREATE INDEX IF NOT EXISTS idx_categories_kind  ON categories(kind)');

    self.execute(q:to/SQL/);
        CREATE TABLE IF NOT EXISTS payees (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
        )
        SQL

    self.execute(q:to/SQL/);
        CREATE TABLE IF NOT EXISTS transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
            date TEXT NOT NULL,
            payee_id INTEGER REFERENCES payees(id) ON DELETE SET NULL,
            memo TEXT NOT NULL DEFAULT '',
            amount INTEGER NOT NULL,
            cleared TEXT NOT NULL DEFAULT 'uncleared'
                CHECK(cleared IN ('uncleared','cleared','reconciled')),
            transfer_peer_id INTEGER REFERENCES transactions(id) ON DELETE SET NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
        SQL
    self.execute('CREATE INDEX IF NOT EXISTS idx_transactions_account ON transactions(account_id)');
    self.execute('CREATE INDEX IF NOT EXISTS idx_transactions_date    ON transactions(date, id)');
    self.execute('CREATE INDEX IF NOT EXISTS idx_transactions_peer    ON transactions(transfer_peer_id)');

    # ON DELETE RESTRICT on category_id: a category with history must
    # be hidden, not deleted — dropping it would silently rewrite the
    # past. Gateway::Category enforces the same rule with a friendlier
    # message; this is the backstop for hand-written SQL.
    self.execute(q:to/SQL/);
        CREATE TABLE IF NOT EXISTS splits (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            transaction_id INTEGER NOT NULL
                REFERENCES transactions(id) ON DELETE CASCADE,
            category_id INTEGER NOT NULL
                REFERENCES categories(id) ON DELETE RESTRICT,
            amount INTEGER NOT NULL,
            memo TEXT NOT NULL DEFAULT ''
        )
        SQL
    self.execute('CREATE INDEX IF NOT EXISTS idx_splits_transaction ON splits(transaction_id)');
    self.execute('CREATE INDEX IF NOT EXISTS idx_splits_category    ON splits(category_id)');

    self.execute(q:to/SQL/);
        CREATE TABLE IF NOT EXISTS assignments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            period_start TEXT NOT NULL,
            category_id INTEGER NOT NULL
                REFERENCES categories(id) ON DELETE CASCADE,
            amount INTEGER NOT NULL DEFAULT 0
        )
        SQL

    self!migrate-months-to-periods;

    # UNIQUE is what makes "set the assignment for this period" an
    # upsert rather than a read-modify-write race. Created *after* the
    # transform above: on a legacy file the column these name does not
    # exist until the rename has happened.
    self.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_assignments_period_category
                  ON assignments(period_start, category_id)');
    self.execute('CREATE INDEX IF NOT EXISTS idx_assignments_period
                  ON assignments(period_start)');

    self!seed-system-rows;
}

#|( Revision 1: assignments keyed by budget period rather than by
    calendar month.

    The distribution's first transforming migration, and the reason
    C<schema_rev> exists at all — see SCHEMA EVOLUTION. Rewriting
    C<'2026-03'> to C<'2026-03-01'> is not an operation that may be
    replayed, so it runs once, guarded by the stamp, and the rename,
    the rewrite and the stamp share one transaction: a file that
    crashes mid-migration reopens as either the old shape or the new
    one, never as a mixture of both. )
method !migrate-months-to-periods() {
    my Str $stamped = self.get-meta(SCHEMA-REV-KEY);
    my Int $rev = ($stamped.defined && $stamped ~~ / ^ \d+ $ /)
        ?? $stamped.Int !! 0;
    return if $rev >= SCHEMA-REV;

    self.run-txn: {
        # A file predating this revision has the column under its old
        # name; a fresh one, just created above, already has the new
        # one. Ask, rather than inferring it from the stamp: a budget
        # file that has never had a budget_meta table is exactly the
        # dogfood case, and it is indistinguishable from a fresh file
        # by the stamp alone.
        my @columns = self.query-all('PRAGMA table_info(assignments)')
            .map({ .<name> });
        if @columns.first({ $_ eq 'month' }).defined {
            # The old indices name the old column, and SQLite carries
            # an index across a RENAME COLUMN. Dropping them first
            # keeps the index set describable by the CREATEs above
            # rather than by history.
            self.execute('DROP INDEX IF EXISTS idx_assignments_month_category');
            self.execute('DROP INDEX IF EXISTS idx_assignments_month');
            self.execute('ALTER TABLE assignments RENAME COLUMN month TO period_start');
            # Under monthly/1 — the scheme every file written before
            # periods existed was using — the period containing a month
            # starts on its first day, so the whole transform is a
            # suffix. The length guard is a belt on top of the
            # transaction's braces: a row already in the new shape (a
            # half-run this transaction should have made impossible) is
            # left alone rather than becoming '2026-03-01-01'.
            self.execute(q:to/SQL/);
                UPDATE assignments SET period_start = period_start || '-01'
                WHERE length(period_start) = 7
                SQL
        }
        self.set-meta(SCHEMA-REV-KEY, SCHEMA-REV.Str);
    };
}

method !seed-system-rows() {
    # Both seeds are INSERT ... WHERE NOT EXISTS rather than INSERT OR
    # IGNORE: the rta row has no unique key of its own (its identity is
    # "the row whose kind is rta"), so a conflict clause would not
    # catch a duplicate.
    self.execute(q:to/SQL/);
        INSERT INTO category_groups (name, sort_order, hidden, system)
        SELECT 'Credit Card Payments', 1000, 0, 1
        WHERE NOT EXISTS (
            SELECT 1 FROM category_groups WHERE name = 'Credit Card Payments'
        )
        SQL

    self.execute(q:to/SQL/);
        INSERT INTO categories (group_id, name, kind, sort_order, hidden)
        SELECT NULL, 'Ready to Assign', 'rta', -1, 0
        WHERE NOT EXISTS (SELECT 1 FROM categories WHERE kind = 'rta')
        SQL
}

#| Additive-only ALTER TABLE helper for forward-compatible schema
#| bumps: adds the column when it is missing, no-ops when it is not.
#| The five C<categories.target_*> columns are its callers inside the
#| migrations — the shape every later additive column should copy: a
#| constant C<NOT NULL DEFAULT> (or a nullable column with no default
#| at all), added after the table's C<CREATE> and before any index
#| that mentions it.
method ensure-column(Str:D $table, Str:D $column, Str:D $decl) {
    # PRAGMA table_info returns rows; drain them before the ALTER, or
    # the open read transaction blocks the schema change.
    my @rows  = self.query-all("PRAGMA table_info($table)");
    my @names = @rows.map({ .<name> });
    return if @names.first({ $_ eq $column }).defined;
    self.execute("ALTER TABLE $table ADD COLUMN $column $decl");
}
