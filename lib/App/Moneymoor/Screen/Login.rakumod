=begin pod

=head1 NAME

App::Moneymoor::Screen::Login - the centred unlock / create-a-budget
dialog, and the only screen that runs before a passphrase exists.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Screen::Login;
use App::Moneymoor::Themes;

my $login = App::Moneymoor::Screen::Login.new(
    available-budgets => ('household', 'business'),
    theme             => App::Moneymoor::Themes::load('nord'),
);
my $root = $login.build;         # a plain Selkie tree, no terminal needed

$login.on-login.tap: -> %data {
    given %data<action> {
        when 'login'  { unlock(%data<budget-name>, %data<passphrase>) }
        when 'create' { create(%data<budget-name>, %data<passphrase>) }
        when 'focus-next' { $app.focus(...) }
    }
};

$login.set-status('Invalid passphrase (or corrupted budget file)', :error);

=end code

=head1 DESCRIPTION

A fixed 24 x 64 dialog, centred by flex struts, with a rounded frame
and one cell of padding. It has two modes, swapped in place inside a
single form container:

=item B<open a budget> — the budget C<Select> plus one masked
      passphrase field.
=item B<create a budget> — the same C<Select> (parked on
      C<+ Create new budget…>), a three-row warning, a name field, a
      passphrase field with a live C<PasswordStrength> meter, and a
      confirmation field.

Either the picker or C<Ctrl+N> gets you to the second mode; both go
through the picker's C<on-change> tap, which is the one place that
knows how to swap the form.

Nothing here touches the database — it cannot, since the database is
exactly what the passphrase typed into this screen unlocks. The only
state it reads is the budget-name list the caller hands it, so the
screen is safe to build and render before any credential exists.

=head2 The row budget

The dialog is centred but never scrolled, so every row it spends is
spent at build time and the create-a-budget branch spends all of them.
See the comment on C<DIALOG-ROWS> in the source for the full sum;
C<t/63-login-layout.rakutest> pins it. Adding a field, or a line of
warning copy, without growing C<DIALOG-ROWS> pushes the hint line off
the bottom edge.

=head2 Error reporting

C<App::Moneymoor::DB.connect> answers with a C<Failure> — never an
exception — carrying one of two distinct messages:

=item C<"Not an encrypted budget file (plain SQLite file)"> — the file
      exists but is plaintext SQLite, i.e. the user picked the wrong
      file.
=item C<"Invalid passphrase (or corrupted budget file)"> — the file is
      encrypted and the key did not open it.

The distinction is worth surfacing verbatim: one is "you typed the
wrong thing", the other is "you opened the wrong thing", and a single
"login failed" would leave the user retyping a passphrase that was
always correct. C<App::Moneymoor::UI> passes
C<$result.exception.message> straight into C<set-status(:error)> and
then calls C<.so> on the Failure — a handled Failure that is never
defused re-throws at sink time.

=head2 SUPPLIES

C<on-login> emits a Hash with an C<action> key:

=item C<focus-next> — C<{ target => 'name' | 'password' | 'confirm' }>.
      The screen has no C<Selkie::App> reference, so moving focus
      between its own fields is a request to whoever owns the app.
      C<name> is the C<Ctrl+N> case: the field that had focus was
      destroyed with the form the mode switch replaced.
=item C<login> — C<{ budget-name, passphrase }>.
=item C<create> — C<{ budget-name, passphrase }>.

=head2 ACCESSORS

=item C<password-input>, C<confirm-input>, C<name-input>,
      C<budget-select> — focus targets.
=item C<in-new-db-mode> — which branch the form is currently showing.
=item C<selected-budget> — the picked budget name, or the
      C<Str> type object when the create row is selected.

=head1 SEE ALSO

=item L<App::Moneymoor::UI> — owns the DB handshake this screen feeds.
=item L<App::Moneymoor::Config> — supplies C<available-budget-names>.
=item L<App::Moneymoor::View::HintBar> — the footer's C<login> context.

=end pod

unit class App::Moneymoor::Screen::Login;

use Selkie::Layout::VBox;
use Selkie::Layout::HBox;
use Selkie::Widget::Text;
use Selkie::Widget::RichText;
use Selkie::Widget::RichText::Span;
use Selkie::Widget::TextInput;
use Selkie::Widget::Select;
use Selkie::Widget::Border;
use Selkie::Align;
use Selkie::BorderStyle;
use Selkie::Widget::PasswordStrength;
use Selkie::Sizing;

use App::Moneymoor::Theme;
use App::Moneymoor::View::HintBar;
use App::Moneymoor::View::ModalChrome;

# The palette read from config before the app window exists —
# App::Moneymoor::UI.run loads it ahead of !show-login, so login is
# themed from the first frame rather than starting on a stock palette
# and snapping over once a budget opens.
has App::Moneymoor::Theme $.theme is required;

has Selkie::Layout::VBox $.root;
has Selkie::Widget::Border $!border;

has Selkie::Widget::Select $!budget-select;
has Selkie::Widget::TextInput $!name-input;
has Selkie::Widget::TextInput $!password-input;
has Selkie::Widget::TextInput $!confirm-input;
has Selkie::Widget::PasswordStrength $!strength-meter;
has Selkie::Widget::Text $!status;
has Selkie::Widget::RichText $!hint;
has Selkie::Widget::RichText $!warning;

has Selkie::Layout::VBox $!form-container;

has @.available-budgets;
has Bool $.force-new-db = False;

has Bool $!in-new-db-mode = False;
has Supplier $!login-supplier = Supplier.new;

# The modal-chrome bundle for `theme`, built once on first use. Held
# rather than rebuilt per widget because both mode switches and every
# set-status call want it, and a Style is an immutable value — the same
# object can back a dozen widgets.
has %!styles;

my constant CREATE-NEW-LABEL = '+ Create new budget…';

#| Outer size of the centred dialog box, frame and padding included.
#| The rounded Border spends two rows and two columns on its frame and
#| two more of each on its one cell of padding, leaving a 20 x 60
#| content box.
#|
#| Those 20 rows are spent I<exactly>, with nothing to spare, by the
#| create-a-budget branch — the taller of the two forms:
#|
#|     2   wordmark
#|     1   gap
#|     2   budget label + Select
#|     1   gap
#|    11   form: warning (3) + gap + seven field rows
#|     1   gap
#|     2   status line + hint line
#|
#| The gaps are C<CONTENT-GAP> rows the two VBoxes reserve between
#| their children (Selkie never puts one at an end), so adding a child
#| costs its own height I<plus> a gap. Adding a row to
#| C<!enter-new-db-mode>, or a line to the warning copy, therefore
#| pushes the hint line off the bottom unless C<DIALOG-ROWS> grows with
#| it — and it can only grow to the height of the smallest terminal we
#| are willing to run in, since the dialog is centred but never
#| scrolled. t/63-login-layout pins the whole sum.
my constant DIALOG-ROWS = 24;
my constant DIALOG-COLS = 64;

#| Width of the Border's content box, and so the width every line
#| inside the dialog wraps and centres against: the frame costs a
#| column on each edge and the padding one more.
my constant INTERIOR-COLS = DIALOG-COLS - 4;

#| Rows reserved between adjacent children of the dialog's VBoxes.
#| Structural, not decorative: this is what replaces blank C<Text>
#| widgets stacked between sections.
my constant CONTENT-GAP = 1;

#| Height of the create-a-budget warning. The copy is short enough to
#| wrap to two lines at INTERIOR-COLS, but the block claims three: the
#| row budget has no slack to redistribute (see DIALOG-ROWS), and the
#| extra row gives the one genuinely alarming sentence in the app some
#| air rather than jamming it against the name field. t/63-login-layout
#| re-wraps the real spans through C<RichText.wrap-spans> and fails if
#| a re-wording ever spills past what it has.
my constant WARNING-ROWS = 3;

#|( The wordmark, in half-block letterforms, painted centred in the
    palette's accent above the form. Two rows and 40 columns — it has
    to clear INTERIOR-COLS with room to spare at both ends, or a
    centred wordmark stops reading as one.

    The alphabet is the same one App-Mindmoor's login draws from:
    C<█> for a full-strength stroke, C<▀> / C<▄> for a half-height
    one. C<E> and C<Y> are the two letters Mindmoor's wordmark never
    needed — C<E> is a stem with a top and bottom bar, C<Y> is two
    arms meeting a centred stem at the row boundary. )
my constant WORDMARK = (
    '█▀▄▀█ █▀█ █▄ █ █▀▀ █▄█ █▀▄▀█ █▀█ █▀█ █▀▄',
    '█ ▀ █ █▄█ █ ▀█ █▄▄  █  █ ▀ █ █▄█ █▄█ █▀▄',
);

#| The one sentence pair that has to land, quoted from the UI spec.
#| sqlcipher has no recovery path and no key escrow: a forgotten
#| passphrase is a destroyed budget, and the user has to be told that
#| before they choose one, not after.
my constant WARNING-TEXT =
    'This passphrase encrypts your budget with sqlcipher. '
  ~ 'There is no reset.';

method on-login(--> Supply) { $!login-supplier.Supply }

method password-input(--> Selkie::Widget::TextInput) { $!password-input }
method confirm-input(--> Selkie::Widget::TextInput)  { $!confirm-input }
method name-input(--> Selkie::Widget::TextInput)     { $!name-input }
method budget-select(--> Selkie::Widget::Select)     { $!budget-select }
method in-new-db-mode(--> Bool)                      { $!in-new-db-mode }

#| The budget the C<Select> is parked on, or the C<Str> type object
#| when it is parked on the create-a-budget row (which is not a budget
#| and has no path).
method selected-budget(--> Str) {
    my $val = $!budget-select.defined ?? $!budget-select.selected-value !! Str;
    return Str without $val;
    $val eq CREATE-NEW-LABEL ?? Str !! $val;
}

method build(--> Selkie::Layout::VBox) {
    # The root deliberately keeps gap 0: its flex Text rows are the
    # centring struts, and a gap between a strut and the dialog would
    # come out of the dialog's own height on a terminal exactly
    # DIALOG-ROWS tall.
    $!root = Selkie::Layout::VBox.new(sizing => Sizing.flex);

    $!root.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);

    my $dialog-row = Selkie::Layout::HBox.new(sizing => Sizing.fixed(DIALOG-ROWS));
    $!root.add($dialog-row);
    $dialog-row.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);

    my $dialog-col = Selkie::Layout::VBox.new(sizing => Sizing.fixed(DIALOG-COLS));
    $dialog-row.add($dialog-col);

    $dialog-row.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);

    # No frame title: the wordmark inside the dialog says the app's
    # name far better than four small words on the top edge, and two
    # of them competing for the same glance is one too many.
    $!border = Selkie::Widget::Border.new(
        sizing       => Sizing.flex,
        border-style => BorderRounded,
        padding      => 1,
    );
    $dialog-col.add($!border);

    my $content = Selkie::Layout::VBox.new(
        sizing => Sizing.flex,
        gap    => CONTENT-GAP,
    );
    $!border.set-content($content);

    $content.add(self!wordmark);

    $!budget-select = Selkie::Widget::Select.new(sizing => Sizing.fixed(1));
    $!budget-select.set-items(self!budget-options);
    $content.add: self!group(self!label('Budget'), $!budget-select);

    $!form-container = Selkie::Layout::VBox.new(
        sizing => Sizing.flex,
        gap    => CONTENT-GAP,
    );
    $content.add($!form-container);

    # Status and hint are one group, not two children of `$content`:
    # they belong to the bottom edge together, and a gap between an
    # empty status line and the hints would read as a hole.
    $!status = Selkie::Widget::Text.new(
        text   => '',
        sizing => Sizing.fixed(1),
        style  => self!styles<dim>,
    );
    $!hint = Selkie::Widget::RichText.new(sizing => Sizing.fixed(1));
    # The dialog is a fixed size, so the hint bar's width is known here
    # and never changes — no on-resize repaint, unlike the main screen
    # whose footer spans the terminal.
    $!hint.set-content(
        hint-spans('login', INTERIOR-COLS, theme => $!theme),
    );
    $content.add: self!group($!status, $!hint);

    $!root.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);

    my $initial-new = $!force-new-db || @!available-budgets.elems == 0;
    if $initial-new {
        $!budget-select.select-index(@!available-budgets.elems.UInt);
        self!enter-new-db-mode;
    } else {
        self!enter-existing-db-mode;
    }

    $!budget-select.on-change.tap: -> UInt $ {
        my $val = $!budget-select.selected-value;
        if $val eq CREATE-NEW-LABEL {
            self!enter-new-db-mode unless $!in-new-db-mode;
        } else {
            self!enter-existing-db-mode if $!in-new-db-mode;
        }
    };

    # The one keybind this screen has, and the one the hint line
    # advertises. Bound on the root rather than app-globally (the
    # screen has no C<Selkie::App>) — a keypress starts at the focused
    # field and bubbles up, and C<TextInput> lets unmodified Ctrl
    # chords through for exactly this.
    $!root.on-key: 'ctrl+n',
        -> $ { self!request-new-db },
        :description('Create a new budget');

    $!root;
}

#|( C<Ctrl+N> from anywhere in the dialog: show the create-a-budget
    form and put the cursor in its first field.

    The mode change goes through the C<Select> rather than straight to
    C<!enter-new-db-mode>, so the keybind and the picker cannot end up
    disagreeing about what the dialog is showing — moving the picker
    fires C<on-change>, and that tap is the single owner of the switch.

    The focus request is not optional and not decoration: the field
    that had focus was inside the form container the switch just
    cleared, so without it the user is typing into a destroyed widget.
    C<Selkie::App> is the only thing that can move focus, and this
    screen deliberately holds no reference to it, so it asks. )
method !request-new-db(--> Nil) {
    $!budget-select.select-index(@!available-budgets.elems.UInt)
        unless $!in-new-db-mode;
    $!login-supplier.emit({ action => 'focus-next', target => 'name' });
    Nil
}

# The canonical modal-chrome bundle, memoised. Lazy rather than built
# in TWEAK so `set-status` is safe to call on a screen that has not
# been built yet.
method !styles(--> Hash) {
    %!styles = modal-styles(theme => $!theme) unless %!styles;
    %!styles;
}

#| A field caption. No leading space: the Border's padding already
#| insets the content box, and an extra one would push every label a
#| column right of the input it names.
method !label(Str:D $text --> Selkie::Widget::Text) {
    Selkie::Widget::Text.new(
        text   => $text,
        sizing => Sizing.fixed(1),
        style  => self!styles<label>,
    );
}

#|( One visual block of single-row widgets — a caption and its input, a
    caption and its input and a strength meter — stacked with no gap
    between them, so that the gap the parent VBox reserves falls
    between I<blocks> rather than between a label and the field it
    belongs to.

    The group's height is the number of rows it was handed, which is
    why every widget passed in must be C<Sizing.fixed(1)>. )
method !group(*@rows --> Selkie::Layout::VBox) {
    my $group = Selkie::Layout::VBox.new(
        sizing => Sizing.fixed(@rows.elems),
    );
    $group.add($_) for @rows;
    $group;
}

method !wordmark(--> Selkie::Layout::VBox) {
    my $style = self!styles<title>;
    self!group(|WORDMARK.map(-> $line {
        Selkie::Widget::Text.new(
            text   => $line,
            sizing => Sizing.fixed(1),
            align  => TextCenter,
            style  => $style,
        )
    }));
}

method !budget-options(--> List) {
    my @opts = @!available-budgets.List;
    @opts.push(CREATE-NEW-LABEL);
    @opts.List;
}

method !enter-existing-db-mode() {
    $!in-new-db-mode = False;
    $!form-container.clear;

    $!password-input = Selkie::Widget::TextInput.new(
        sizing      => Sizing.fixed(1),
        placeholder => 'Enter passphrase…',
        mask-char   => '*',
    );
    $!form-container.add:
        self!group(self!label('Passphrase'), $!password-input);

    $!password-input.on-submit.tap: -> $pass {
        self!attempt-login($pass);
    };

    $!name-input = Selkie::Widget::TextInput;
    $!confirm-input = Selkie::Widget::TextInput;
    $!strength-meter = Selkie::Widget::PasswordStrength;
    $!warning = Selkie::Widget::RichText;

    self.set-status('');
}

method !enter-new-db-mode() {
    $!in-new-db-mode = True;
    $!form-container.clear;

    $!warning = Selkie::Widget::RichText.new(
        sizing => Sizing.fixed(WARNING-ROWS),
    );
    $!warning.set-content([
        Selkie::Widget::RichText::Span.new(
            text  => WARNING-TEXT,
            style => self!styles<warn>,
        ),
    ]);
    $!form-container.add($!warning);

    $!name-input = Selkie::Widget::TextInput.new(
        sizing      => Sizing.fixed(1),
        placeholder => 'e.g. household, business',
    );
    $!password-input = Selkie::Widget::TextInput.new(
        sizing      => Sizing.fixed(1),
        placeholder => 'Enter passphrase…',
        mask-char   => '*',
    );
    $!strength-meter = Selkie::Widget::PasswordStrength.new(
        sizing => Sizing.fixed(1),
        input  => $!password-input,
    );
    $!confirm-input = Selkie::Widget::TextInput.new(
        sizing      => Sizing.fixed(1),
        placeholder => 'Re-enter passphrase…',
        mask-char   => '*',
    );

    # All three fields in one group: the row budget has no room for a
    # gap between them (see DIALOG-ROWS), and the warning above them is
    # the block they need separating from.
    $!form-container.add: self!group(
        self!label('Budget name'),        $!name-input,
        self!label('Passphrase'),         $!password-input,
        $!strength-meter,
        self!label('Confirm passphrase'), $!confirm-input,
    );

    $!name-input.on-submit.tap: -> $ {
        $!login-supplier.emit({ action => 'focus-next', target => 'password' });
    };
    $!password-input.on-submit.tap: -> $ {
        $!login-supplier.emit({ action => 'focus-next', target => 'confirm' });
    };
    $!confirm-input.on-submit.tap: -> $ {
        self!attempt-create;
    };

    self.set-status('');
}

#| Show a one-line message under the form. C<:error> paints it in the
#| palette's error colour; without it the line is ordinary dim body
#| copy, which is what the empty string every mode switch sets wants.
method set-status(Str:D $msg, Bool :$error = False) {
    $!status.set-text($msg);
    $!status.set-style($error ?? self!styles<error> !! self!styles<dim>);
}

method !attempt-login(Str $pass) {
    if $pass.chars == 0 {
        self.set-status('Passphrase cannot be empty', :error);
        return;
    }
    my $name = self.selected-budget;
    without $name {
        self.set-status('No budget selected', :error);
        return;
    }
    $!login-supplier.emit({
        action      => 'login',
        budget-name => $name,
        passphrase  => $pass,
    });
}

method !attempt-create() {
    my $name = ($!name-input.text // '').trim;
    my $pass = $!password-input.text;
    my $conf = $!confirm-input.text;

    if $name.chars == 0 {
        self.set-status('Budget name cannot be empty', :error);
        return;
    }
    unless $name ~~ /^ <[a..z A..Z 0..9 _ \- \.]>+ $/ {
        self.set-status('Budget name: letters, digits, . _ - only', :error);
        return;
    }
    if $pass.chars == 0 {
        self.set-status('Passphrase cannot be empty', :error);
        return;
    }
    if $pass ne $conf {
        self.set-status('Passphrases do not match', :error);
        return;
    }
    $!login-supplier.emit({
        action      => 'create',
        budget-name => $name,
        passphrase  => $pass,
    });
}
