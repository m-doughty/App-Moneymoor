=begin pod

=head1 NAME

App::Moneymoor::Config - the data home, the budget file list, and the
four global display settings.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Config;

my $cfg = App::Moneymoor::Config.new;
$cfg.load;                          # reads ~/.moneymoor/config.json

say $cfg.available-budget-names;    # ('household', 'business')

$cfg.budget-name = 'household';
say $cfg.budget-path;               # /Users/you/.moneymoor/household.db

$cfg.theme        = 'nord';
$cfg.icons        = 'nerd';
$cfg.currency     = '€';
$cfg.decimal-mark = ',';
$cfg.save;                          # back to ~/.moneymoor/config.json

=end code

=head1 DESCRIPTION

Moneymoor keeps everything under one directory:

    ~/.moneymoor/
      config.json          # this file: last-used budget, theme,
                           #            icons, currency, decimal mark
      household.db         # a sqlcipher budget
      business.db          # another one
      logs/error.log       # Selkie's stderr redirect while the TUI runs

Budgets are B<flat files> in the data home, not per-profile
subdirectories: a budget is a single sqlcipher database with no
sidecar state, so a directory per budget would be a directory
containing exactly one file. The login screen lists
C<~/.moneymoor/*.db> and the basename I<is> the budget name.

Everything is derived from C<moneymoor-home>, which honours the
C<MONEYMOOR_HOME> environment variable. That override exists for the
test suite — a test that wrote to the real C<~/.moneymoor> could
clobber a user's budget list — but it is equally useful for keeping a
throwaway budget out of the normal picker.

=head2 What is I<not> here

Nothing about a budget's contents. Category order, hidden flags,
collapsed groups and the viewed period all live in the encrypted
database or in the Selkie store, because they are per-budget facts
and this file is deliberately plaintext (it has to be readable before
a passphrase exists — the login screen is themed from the first
frame).

=head1 ATTRIBUTES

=item C<budget-name> — the last budget opened, pre-selected by the
      login screen next launch. Defaults to C<'budget'>.
=item C<theme> — palette name, resolved through
      C<App::Moneymoor::Themes::load>. Defaults to C<'gruvbox'>.
=item C<icons> — glyph tier, C<'unicode'> (default) or C<'nerd'>.
      Resolved through C<App::Moneymoor::Service::Icons::icons>, which
      maps an unknown tier back onto unicode, so a hand-edited config
      cannot break rendering.
=item C<currency> — the symbol money is rendered with: C<'£'>
      (default), C<'$'> or C<'€'>. Display only —
      L<App::Moneymoor::Util::Money> converts nothing and the engine
      has never heard of a currency.
=item C<decimal-mark> — C<'.'> (default) or C<','>, stored under the
      JSON key C<decimal_mark>. Thousands are grouped with the other
      one, so this single setting moves both characters, in both
      directions: C<'1,234.56'> or C<'1.234,56'> on the way out, and
      the matching shape accepted on the way in.

C<currency> and C<decimal-mark> are the two settings this class
I<validates>, because they are the two that are handed to a routine
that refuses an unknown value (C<set-money-locale> throws). A value
outside the whitelist — a hand-edited C<"currency": "CAD"> — falls
back to the default silently, the same treatment C<Service::Icons>
gives an unknown glyph tier: the plaintext config is user-editable by
design, and the failure mode for a typo in it must be "the app opens
in £" rather than "the app does not open".

=head1 METHODS

=item C<moneymoor-home> — C<~/.moneymoor>, or C<$MONEYMOOR_HOME>.
=item C<budget-path> — derived C<~/.moneymoor/{budget-name}.db>.
=item C<budget-path-for($name)> — the same derivation for any name,
      for the login screen's "open the one the user just picked".
=item C<budget-exists> — is there a file at C<budget-path>?
=item C<available-budget-names> — every C<*.db> basename in the data
      home, most-recently-modified first, so the picker opens on the
      budget the user was last in.
=item C<valid-budget-name($name)> — the create-a-budget name rule:
      letters, digits, C<.>, C<_>, C<->. Rejects anything that could
      escape the data home.
=item C<error-log-path> — C<~/.moneymoor/logs/error.log>, handed to
      C<Selkie::App> so warnings don't splatter over the TUI.
=item C<ensure-directories> — create the data home if missing.
=item C<load($path?)> / C<save> / C<config-path> — JSON round-trip.

=head1 EXAMPLES

=head2 Pointing a test at a scratch home

=begin code :lang<raku>

my $scratch = $*TMPDIR.add("moneymoor-test-{$*PID}").Str;
%*ENV<MONEYMOOR_HOME> = $scratch;

my $cfg = App::Moneymoor::Config.new.load;
$cfg.icons = 'nerd';
$cfg.save;

App::Moneymoor::Config.new.load.icons;      # 'nerd'

=end code

=head2 Opening whatever the user picked in the login Select

=begin code :lang<raku>

my $path = $cfg.budget-path-for($login.selected-budget);
my $db   = App::Moneymoor::DB.new(db-path => $path);
my $res  = $db.connect($passphrase);
if $res ~~ Failure {
    $login.set-status($res.exception.message, :error);
    $res.so;                       # a handled Failure must be defused
}

=end code

=head1 SEE ALSO

=item L<App::Moneymoor::Screen::Login> — the consumer of
      C<available-budget-names> and C<budget-path-for>.
=item L<App::Moneymoor::Themes> — resolves C<theme>.
=item L<App::Moneymoor::Service::Icons> — resolves C<icons>.
=item L<App::Moneymoor::Util::Money> — owns the whitelists
      C<currency> and C<decimal-mark> are checked against, and is
      pointed at them by C<App::Moneymoor::UI> at startup.

=end pod

unit class App::Moneymoor::Config;

use JSON::Fast;

use App::Moneymoor::Util::Money;

has Str $.budget-name  is rw = 'budget';
has Str $.theme        is rw = 'gruvbox';
has Str $.icons        is rw = 'unicode';
has Str $.currency     is rw = '£';
has Str $.decimal-mark is rw = '.';

has Str $!config-path;

#| Every budget name has to survive being concatenated onto the data
#| home, so the rule is a whitelist rather than a blacklist: no
#| separators, no C<..>, nothing a shell or a path parser would treat
#| as structure.
my constant BUDGET-NAME-RX = / ^ <[a..z A..Z 0..9 _ \- \.]>+ $ /;

method moneymoor-home(--> Str) {
    %*ENV<MONEYMOOR_HOME> // $*HOME.add('.moneymoor').Str;
}

method budget-path-for(Str:D $name --> Str) {
    "{self.moneymoor-home}/$name.db";
}

method budget-path(--> Str) { self.budget-path-for($!budget-name) }

method budget-exists(--> Bool) { self.budget-path.IO.e }

#| Where Selkie should redirect stderr while the TUI is running. Under
#| the data home rather than beside a budget because the log is
#| process-wide — a warning can fire before any budget is unlocked
#| (the login screen is a full Selkie tree). Selkie auto-creates the
#| parent directory on first write.
method error-log-path(--> Str) { "{self.moneymoor-home}/logs/error.log" }
method timing-trace-path(--> Str) { "{self.moneymoor-home}/logs/timing-trace.json" }
method timing-slow-path(--> Str) { "{self.moneymoor-home}/logs/timing-slow.jsonl" }

#| The create-a-budget name rule, exposed as a method so the login
#| screen validates against the same predicate the path derivation
#| relies on rather than a second copy of the regex.
method valid-budget-name(Str $name --> Bool) {
    return False without $name;
    so $name ~~ BUDGET-NAME-RX;
}

#|( Every C<*.db> in the data home, most-recently-modified first.
    Sorting by mtime (not alphabetically) is what makes the login
    Select open on the budget the user was last inside — the
    overwhelmingly common case is "same budget as yesterday". )
method available-budget-names(--> List) {
    my $home = self.moneymoor-home.IO;
    return () unless $home.d;
    my @candidates;
    for $home.dir -> $entry {
        next unless $entry.f;
        my $base = $entry.basename;
        next unless $base.ends-with('.db');
        my $name = $base.substr(0, $base.chars - 3);
        # A file the picker could list but the app could never reopen
        # (a name the path derivation would mangle) is worse than a
        # file the picker quietly ignores.
        next unless self.valid-budget-name($name);
        @candidates.push: { :$name, mtime => $entry.modified };
    }
    @candidates.sort(-*<mtime>).map(*<name>).List;
}

method !defaults() {
    $!budget-name  //= 'budget';
    $!theme        //= 'gruvbox';
    $!icons        //= 'unicode';
    $!currency     //= money-symbols()[0];
    $!decimal-mark //= money-decimal-marks()[0];
}

#|( Is C<$value> one of C<@allowed>? A hand-edited config is the only
    way an unknown value gets in, and the caller's answer to one is
    always "leave the default", so this returns a plain Bool rather
    than complaining. Guards a Str-typed read: JSON will happily hand
    back a number or a hash for a key we expect a string in. )
my sub allowed(Mu $value, @allowed --> Bool) {
    return False unless $value ~~ Str:D;
    so @allowed.grep($value);
}

method load(Str $path? --> App::Moneymoor::Config) {
    $!config-path = $path // "{self.moneymoor-home}/config.json";

    if $!config-path.IO.e {
        my %data = from-json(slurp $!config-path);
        $!budget-name = %data<budget_name> if %data<budget_name>.defined;
        $!theme       = %data<theme>       if %data<theme>.defined;
        $!icons       = %data<icons>       if %data<icons>.defined;
        # Validated, unlike the three above: these two are handed
        # straight to `set-money-locale`, which throws on a value it
        # does not know, and a config typo must not stop the app
        # opening.
        $!currency    = %data<currency>
            if allowed(%data<currency>, money-symbols());
        $!decimal-mark = %data<decimal_mark>
            if allowed(%data<decimal_mark>, money-decimal-marks());
    }

    self!defaults;
    self;
}

method save() {
    # `load` is what sets `$!config-path`; a Config that was never
    # loaded still has to be saveable (the create-a-budget flow builds
    # one from defaults), so fall back to the derived location.
    $!config-path //= "{self.moneymoor-home}/config.json";

    my $dir = $!config-path.IO.parent;
    $dir.mkdir unless $dir.d;

    my %data =
        budget_name  => $!budget-name,
        theme        => $!theme,
        icons        => $!icons,
        currency     => $!currency,
        decimal_mark => $!decimal-mark,
    ;

    spurt $!config-path, to-json(%data, :sorted-keys, :pretty);
}

method config-path(--> Str) { $!config-path }

method ensure-directories() {
    self.moneymoor-home.IO.mkdir unless self.moneymoor-home.IO.d;
}
