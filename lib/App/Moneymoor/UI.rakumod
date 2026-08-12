=begin pod

=head1 NAME

App::Moneymoor::UI - the TUI's entry point: builds the notcurses app,
runs the login handshake, and hands over to the main shell.

=head1 SYNOPSIS

=begin code :lang<raku>

# In bin/moneymoor, AFTER `use MacOS::NativeLib <sqlcipher>`:
use App::Moneymoor::UI;

App::Moneymoor::UI.new.run;

=end code

=head1 DESCRIPTION

The whole of the app's lifecycle, in one small class:

=item load C<App::Moneymoor::Config> from C<~/.moneymoor/config.json>;
=item point C<App::Moneymoor::Util::Money> at the saved currency
      symbol and decimal mark. That module holds the display locale as
      module state precisely so that no other call site has to thread
      it, which makes this the one place it is set;
=item resolve the palette by name and hand it to C<Selkie::App> at
      construction, so the login screen is themed from the first frame
      rather than starting stock and snapping over once a budget opens;
=item show C<Screen::Login> and wait for an unlock or a create;
=item on success, open the C<DB>, build a C<Service::Workspace> over
      it, construct C<Screen::Main> and switch to it;
=item on a B<create>, ask the new budget's owner when their period
      starts, over the empty budget the shell has just come up on.

=head2 The two things that can go wrong at the boundary

C<DB.connect> answers with a C<Failure> (see below).
C<Service::Workspace.new> B<throws>, and for exactly one reason: the
file's C<budget_meta.period_scheme> holds something the engine cannot
read. Both land on the login screen's status line and neither switches
screens — the login screen is still the current one either way, so the
user is looking at the message in the place they can act on it.

Refusing to open, rather than falling back to the calendar month, is
the engine's ruling and this is only the other end of it: a budget
opened under a scheme its owner never chose buckets every derived
figure by the wrong windows and then refuses every write, which is a
much worse afternoon than a file that will not open and says why.

=head2 The period question is asked after creation, not during it

The create-a-budget form is 24 rows tall on the nose, which is the
height of the terminal it has to fit; a scheme picker does not go in
it. So C<!handle-create> hands C<:fresh> to C<!show-main>, which opens
the period picker in its first-run mode once the shell is up. The
budget behind that dialog is empty, so whatever is chosen re-buckets
nothing, and Esc means "the calendar month" — which is what an
untouched file already says.

Nothing here knows anything about budgets, envelopes or periods. The
login screen knows nothing about databases. This class is the only
place the two meet, which is what keeps the DB handshake — the one
step that can fail in a way the user has to understand — in a single
readable method.

=head2 The sqlcipher ordering rule

C<App::Moneymoor::DB> deliberately does B<not> C<use MacOS::NativeLib>:
it is a macOS-only distribution and depending on it inside the engine
would make every Linux consumer install it. The obligation therefore
falls on the entry point, which must load the shim B<before> the first
C<use App::Moneymoor::DB> — including the transitive one through this
module. C<bin/moneymoor> does it in a C<BEGIN> block, guarded on the
symlink already existing (C<use MacOS::NativeLib> shells out to
C<brew config> per library, which costs about a second per launch).

=head2 Failure, not exceptions

C<DB.connect> answers with a C<Failure> and never throws, with two
distinct messages: C<"Not an encrypted budget file (plain SQLite
file)"> and C<"Invalid passphrase (or corrupted budget file)">. Both
go to the login screen's status line B<verbatim> — the difference between
"you typed the wrong passphrase" and "you opened the wrong file"
decides what the user does next, and a generic "login failed" would
have them retyping a passphrase that was correct all along.

Every handled C<Failure> is then C<.so>'d. A Failure that is never
defused re-throws when it is next sunk, which in a TUI means a crash
several frames later with a backtrace pointing at innocent code.

=head1 EXAMPLES

=head2 Driving it against a scratch data home

C<MONEYMOOR_HOME> moves the config file, the budget list and the error
log together, so a throwaway run cannot touch a real budget:

=begin code :lang<raku>

MONEYMOOR_HOME=/tmp/mm-demo raku -I lib bin/moneymoor

=end code

=head1 SEE ALSO

=item L<App::Moneymoor::Config> — the data home and the four display
      settings.
=item L<App::Moneymoor::Util::Money> — the display locale this class
      installs.
=item L<App::Moneymoor::Screen::Login> — the dialog this drives.
=item L<App::Moneymoor::Screen::Main> — what it hands over to.

=end pod

unit class App::Moneymoor::UI;

use Selkie::App;

use App::Moneymoor::Config;
use App::Moneymoor::DB;
use App::Moneymoor::Service::Workspace;
use App::Moneymoor::Theme;
use App::Moneymoor::Themes;
use App::Moneymoor::Util::Money;
use App::Moneymoor::Screen::Login;
use App::Moneymoor::Screen::Main;

has Selkie::App $!app;
has App::Moneymoor::Config $!config;
has App::Moneymoor::Theme $!theme;
has App::Moneymoor::DB $!db;
has App::Moneymoor::Service::Workspace $!workspace;
has App::Moneymoor::Screen::Login $!login-screen;
has App::Moneymoor::Screen::Main $!main-screen;

method run() {
    $!config = App::Moneymoor::Config.new;
    $!config.load;
    # The data home is created lazily, in !handle-login / !handle-create,
    # once the user has actually named a budget.

    # Before anything can render or parse a figure. The money locale is
    # module state in Util::Money rather than an argument threaded
    # through every call site, so this one call is what makes the first
    # frame — the login screen's, already — use the saved symbol and
    # decimal mark. `load` has validated both against the same
    # whitelists, so this cannot throw on a hand-edited config.
    set-money-locale(
        symbol       => $!config.currency,
        decimal-mark => $!config.decimal-mark,
    );

    $!theme = App::Moneymoor::Themes::load($!config.theme);

    # The theme goes in at construction so Selkie's own widgets
    # (Border, TextInput, Select, scrollbars) render in the same
    # palette as Moneymoor's without extra plumbing. Stderr is
    # redirected to `~/.moneymoor/logs/error.log`: TUI cells and stderr
    # cannot share a terminal without one splatting over the other.
    #
    # `animate-*` are Selkie opt-ins, off for every consumer that
    # doesn't ask. On, they give the 120 ms scrim fade under every
    # modal and the toast's fade in and out. Both are bounded colour
    # ramps on the tween group, so they hold the render loop at the hot
    # frame budget only while they run and the idle ladder resumes the
    # moment they finish.
    $!app = Selkie::App.new(
        theme            => $!theme.to-selkie,
        error-log        => $!config.error-log-path,
        animate-backdrop => True,
        animate-toast    => True,
    );
    # Tab, Shift+Tab, Esc and Ctrl+Q are Selkie defaults.

    self!show-login;

    $!app.run;
}

method !show-login() {
    my @budgets = $!config.available-budget-names;
    $!login-screen = App::Moneymoor::Screen::Login.new(
        available-budgets => @budgets,
        force-new-db      => @budgets.elems == 0,
        theme             => $!theme,
    );
    my $root = $!login-screen.build;

    $!app.add-screen('login', $root);
    self!focus-first-login-field;

    $!login-screen.on-login.tap: -> %data {
        given %data<action> {
            when 'focus-next' {
                self!handle-focus-next(%data<target>);
            }
            when 'login' {
                self!handle-login(%data<budget-name>, %data<passphrase>);
            }
            when 'create' {
                self!handle-create(%data<budget-name>, %data<passphrase>);
            }
        }
    };
}

method !focus-first-login-field() {
    if $!login-screen.in-new-db-mode {
        $!app.focus($!login-screen.name-input);
    } else {
        $!app.focus($!login-screen.password-input);
    }
}

method !handle-focus-next(Str $target) {
    given $target {
        # 'name' is Ctrl+N rather than an Enter walk down the form: the
        # switch to the create-a-budget mode destroyed whichever field
        # had focus, so this one is a repair, not a convenience.
        when 'name'     { $!app.focus($!login-screen.name-input)     }
        when 'password' { $!app.focus($!login-screen.password-input) }
        when 'confirm'  { $!app.focus($!login-screen.confirm-input)  }
    }
}

method !handle-login(Str $budget-name, Str $passphrase) {
    $!config.budget-name = $budget-name;
    $!config.ensure-directories;

    $!db = App::Moneymoor::DB.new(db-path => $!config.budget-path);
    my $result = $!db.connect($passphrase);

    if $result ~~ Failure {
        # Verbatim: the two messages say different things and the user
        # needs to know which one they got.
        $!login-screen.set-status($result.exception.message, :error);
        $result.so;
        return;
    }

    $!config.save;
    self!show-main;
}

method !handle-create(Str $budget-name, Str $passphrase) {
    $!config.budget-name = $budget-name;

    if $!config.budget-exists {
        $!login-screen.set-status(
            "Budget '$budget-name' already exists — pick it from the list",
            :error,
        );
        return;
    }

    $!config.ensure-directories;

    $!db = App::Moneymoor::DB.new(db-path => $!config.budget-path);
    my $result = $!db.connect($passphrase);

    if $result ~~ Failure {
        # A create can only fail for reasons that aren't the
        # passphrase — the file didn't exist a moment ago, so there is
        # no key to get wrong. Surfacing the engine's message anyway
        # beats inventing a vaguer one.
        $!login-screen.set-status($result.exception.message, :error);
        $result.so;
        return;
    }

    $!config.save;
    # `:fresh` is what turns the first frame of a brand-new budget into
    # the period question. See !show-main.
    self!show-main(:fresh);
}

#|( Open the budget, build the shell, and switch to it.
    C<:fresh> means the budget was created a moment ago and has nothing
    in it, which is when the period question gets asked.

    The C<Workspace> construction is the one step here that can throw:
    a C<budget_meta.period_scheme> the engine cannot read is refused
    rather than guessed at, because a budget opened under a scheme its
    owner never chose buckets every figure by the wrong windows. There
    is nowhere better to say so than the login screen's status line —
    it is still the current screen, the user is still standing in front
    of it, and the message names the key and quotes what it found. So
    the failure is caught here and the screen switch simply does not
    happen. )
method !show-main(Bool :$fresh = False) {
    $!workspace = try App::Moneymoor::Service::Workspace.new(db => $!db);
    without $!workspace {
        $!login-screen.set-status(
            ($! andthen .message) // 'This budget file could not be opened',
            :error,
        );
        return;
    }

    $!main-screen = App::Moneymoor::Screen::Main.new(
        app       => $!app,
        db        => $!db,
        workspace => $!workspace,
        config    => $!config,
        theme     => $!theme,
    );
    $!app.add-screen('main', $!main-screen.build);
    $!app.switch-screen('main');
    # After the switch, not before: `switch-screen` restores whatever
    # focus it remembers for the screen (nothing, the first time) and
    # would override an earlier placement. The shell handles every
    # later content rebuild itself.
    $!main-screen.focus-content;

    # And after the focus, not before: the picker takes focus itself,
    # and placing the content focus afterwards would pull it back out
    # of the dialog. Asked here rather than in the create form because
    # that form is exactly 24 rows tall — the height of the terminal it
    # has to fit — and because the budget behind this dialog is empty,
    # so whatever is chosen moves no money at all.
    $!main-screen.open-period-picker(:first-run) if $fresh;
}

#|( The dist version as the compiler knows it, or "dev" when there is
    no distribution context. C<$?DISTRIBUTION> resolves both for a
    zef-installed dist and for a checkout loaded via C<-Ilib> (the
    FileSystem repo synthesises a Distribution from the adjacent
    C<META6.json>), but it only works from module scope —
    C<bin/moneymoor> asking the same question gets no answer, which is
    why the entry point calls this instead of asking itself. )
our sub dist-version(--> Str:D) {
    # `meta<version>` is an undefined Any under `-Ilib` (the
    # FileSystem repo is rooted at lib/, so there is no META6.json to
    # synthesise a version from) — and stringifying that warns and
    # yields "", which would dodge a bare `//`. Guard on definedness
    # and content, not just presence.
    my $v = try $?DISTRIBUTION.meta<version>;
    $v.defined && $v.Str.chars ?? $v.Str !! 'dev'
}
