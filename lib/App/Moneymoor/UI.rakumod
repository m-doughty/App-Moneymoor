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
=item on submit, claim the handshake and show a non-dismissable progress
      modal, so repeated Enter presses cannot queue a second login;
=item open and migrate the C<DB> on a worker, while a child Rakudo warms
      C<Service::Workspace> and C<Screen::Main> compilation;
=item on success, hand DB ownership to the UI thread, build the workspace
      and main screen there, and switch to it;
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
use Selkie::Trace;

use App::Moneymoor::Config;
use App::Moneymoor::DB;
use App::Moneymoor::Theme;
use App::Moneymoor::Themes;
use App::Moneymoor::Util::Money;
use App::Moneymoor::Screen::Login;
use App::Moneymoor::Handlers::Boot;
use App::Moneymoor::Widget::BootProgressModal;

has Selkie::App $!app;
has App::Moneymoor::Config $!config;
has App::Moneymoor::Theme $!theme;
has App::Moneymoor::DB $!db;
has $!workspace;
has App::Moneymoor::Screen::Login $!login-screen;
has $!main-screen;
has App::Moneymoor::Handlers::Boot $!boot;
has App::Moneymoor::Widget::BootProgressModal $!boot-modal;
has Promise $!module-warmup;
has Bool $!show-main-pending = False;
has Bool $!show-main-fresh = False;
has Bool $!main-first-frame-pending = False;
has &!boot-launch;
has Bool $!boot-launch-armed = False;

constant WARMUP-PROGRAM =
    'use App::Moneymoor::Service::Workspace; use App::Moneymoor::Screen::Main;';
constant WARMUP-TIMEOUT-SECONDS = 300;

our sub warmup-command(--> List) {
    my @inc = $*REPO.repo-chain
        .grep({ $_ ~~ CompUnit::Repository::FileSystem })
        .map({ '-I' ~ .prefix.absolute });
    ($*EXECUTABLE.absolute, |@inc, '-e', WARMUP-PROGRAM).List;
}

our sub warm-modules(--> Bool) {
    my Bool $ok = False;
    try {
        my $proc = Proc::Async.new(:w, |warmup-command());
        $proc.stdout.tap(-> $ { });
        $proc.stderr.tap(-> $ { });
        my $done = $proc.start;
        $proc.close-stdin;
        await Promise.anyof($done, Promise.in(WARMUP-TIMEOUT-SECONDS));
        unless $done.status == Kept {
            try $proc.kill(SIGKILL);
            try await Promise.anyof($done, Promise.in(5));
        }
        if $done.status == Kept {
            my $result = try $done.result;
            $ok = $result.defined && $result.exitcode == 0;
        }
    }
    $ok;
}

method run() {
    $!config = App::Moneymoor::Config.new;
    $!config.load;
    Selkie::Trace.init(
        mode       => (%*ENV<MONEYMOOR_TIMINGS> // 'off'),
        trace-path => $!config.timing-trace-path,
        slow-path  => $!config.timing-slow-path,
        thresholds => %(default => 8e0, boot => 1e0, db => 8e0),
    );
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

    $!boot = App::Moneymoor::Handlers::Boot.new(
        show-main => -> Bool :$fresh = False {
            $!show-main-fresh = $fresh;
            $!show-main-pending = True;
        },
        on-failed => -> Str $message { self!boot-failed($message) },
    );
    $!boot.register($!app.store);
    $!app.on-frame(-> { self!boot-frame-tick }, name => 'moneymoor-boot');
    $!module-warmup = start {
        my $span = Selkie::Trace.enabled
            ?? Selkie::Trace.start('boot.module-warmup', cat => 'boot') !! Nil;
        my Bool $ok = warm-modules();
        $span.finish(:$ok) with $span;
        $ok;
    };

    $!app.run;
    Selkie::Trace.shutdown;
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
    return unless $!boot.claim;
    $!config.budget-name = $budget-name;
    $!config.ensure-directories;

    self!start-boot($passphrase, title => 'Opening budget');
}

method !handle-create(Str $budget-name, Str $passphrase) {
    return unless $!boot.claim;
    $!config.budget-name = $budget-name;

    if $!config.budget-exists {
        $!boot.release;
        $!login-screen.set-status(
            "Budget '$budget-name' already exists — pick it from the list",
            :error,
        );
        return;
    }

    $!config.ensure-directories;

    self!start-boot($passphrase, title => 'Creating budget', :fresh);
}

method !start-boot(Str:D $passphrase, Str:D :$title!, Bool :$fresh = False --> Nil) {
    $!login-screen.set-status('');
    $!boot-modal = App::Moneymoor::Widget::BootProgressModal.new(
        store => $!app.store, :$title);
    $!app.show-modal($!boot-modal.build);
    $!app.focus($!boot-modal.focus-widget);
    $!app.store.dispatch('boot/started', detail => $!config.budget-name);

    $!db = App::Moneymoor::DB.new(db-path => $!config.budget-path);
    my $db = $!db;
    my $store = $!app.store;
    my $warmup = $!module-warmup;
    # Do not start expensive native/compile work from the submit callback.
    # The on-frame callback below deliberately waits through this frame, so
    # the newly-mounted progress modal reaches notcurses_render first.
    &!boot-launch = -> {
      start {
        CATCH { default { $store.dispatch('boot/failed', message => .message) } }
        my $span = Selkie::Trace.enabled
            ?? Selkie::Trace.start('boot.database', cat => 'boot') !! Nil;
        my $phase-span;
        my $result = $db.connect($passphrase, on-progress => -> %phase {
            $phase-span.finish with $phase-span;
            $phase-span = Selkie::Trace.enabled
                ?? Selkie::Trace.start("boot.{%phase<phase>}", cat => 'boot')
                !! Nil;
            $store.dispatch('boot/phase', |%phase);
        });
        $phase-span.finish with $phase-span;
        if $result ~~ Failure {
            my Str $message = $result.exception.message;
            $result.so;
            $span.finish(ok => False) with $span;
            $store.dispatch('boot/failed', :$message);
        } else {
            $span.finish(ok => True) with $span;
            unless $warmup.status == Kept {
                $store.dispatch('boot/phase', phase => 'compile',
                    detail => 'first run after an update');
            }
            await $warmup;
            $store.dispatch('boot/ready', :$fresh);
        }
      }
    };
    $!boot-launch-armed = False;
    Nil;
}

method !boot-frame-tick(--> Nil) {
    if &!boot-launch.defined {
        if $!boot-launch-armed {
            my &launch = &!boot-launch;
            &!boot-launch = Callable;
            $!boot-launch-armed = False;
            launch();
        } else {
            # This is the submission frame. Leave the continuation parked so
            # render-frame can present the modal before boot competes for CPU,
            # precomp locks, or a native-call boundary.
            $!boot-launch-armed = True;
        }
    }
    if $!main-first-frame-pending {
        $!main-first-frame-pending = False;
        Selkie::Trace.instant('boot.main-first-frame', cat => 'boot')
            if Selkie::Trace.enabled;
    }
    .tick with $!boot-modal;
    if $!show-main-pending {
        $!show-main-pending = False;
        self!show-main(fresh => $!show-main-fresh);
    }
    Nil;
}

method !close-boot-modal(--> Nil) {
    with $!boot-modal {
        $!boot-modal = Nil;
        $!app.close-modal;
    }
    Nil;
}

method !boot-failed(Str:D $message --> Nil) {
    &!boot-launch = Callable;
    $!boot-launch-armed = False;
    self!close-boot-modal;
    with $!db {
        try {
            .adopt-ui-thread if .is-connected;
            .disconnect if .is-connected;
        }
    }
    $!db = App::Moneymoor::DB;
    $!login-screen.set-status($message, :error);
    $!login-screen.reset-credentials unless $!login-screen.in-new-db-mode;
    self!focus-first-login-field;
    Nil;
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
    my \Workspace = (require ::('App::Moneymoor::Service::Workspace'));
    my \Main = (require ::('App::Moneymoor::Screen::Main'));
    $!db.adopt-ui-thread;
    my $workspace-span = Selkie::Trace.enabled
        ?? Selkie::Trace.start('boot.workspace', cat => 'boot') !! Nil;
    $!workspace = try Workspace.new(db => $!db);
    $workspace-span.finish(ok => $!workspace.defined) with $workspace-span;
    without $!workspace {
        self!boot-failed(($! andthen .message)
            // 'This budget file could not be opened');
        return;
    }

    my $build-span = Selkie::Trace.enabled
        ?? Selkie::Trace.start('boot.main-build', cat => 'boot') !! Nil;
    $!main-screen = Main.new(
        app       => $!app,
        db        => $!db,
        workspace => $!workspace,
        config    => $!config,
        theme     => $!theme,
    );
    my $root = $!main-screen.build;
    $build-span.finish(ok => True) with $build-span;
    my $mount-span = Selkie::Trace.enabled
        ?? Selkie::Trace.start('boot.screen-mount', cat => 'boot') !! Nil;
    $!app.add-screen('main', $root);
    $!app.switch-screen('main');
    $mount-span.finish with $mount-span;
    $!main-first-frame-pending = True;
    # After the switch, not before: `switch-screen` restores whatever
    # focus it remembers for the screen (nothing, the first time) and
    # would override an earlier placement. The shell handles every
    # later content rebuild itself.
    $!main-screen.focus-content;
    $!config.save;
    self!close-boot-modal;

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
