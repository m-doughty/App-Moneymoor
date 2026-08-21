unit module App::Moneymoor::Screen::Main::Modals;

=begin pod

=head1 NAME

App::Moneymoor::Screen::Main::Modals - every dialog in the app: the
shell's own three, the budget tab's seven, and the accounts tab's
seven.

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Moneymoor::Screen::Main::Modals;

App::Moneymoor::Screen::Main::Modals::open-settings($main);      # ctrl+o
App::Moneymoor::Screen::Main::Modals::open-diagnostics($main);   # ctrl+g

# The budget period: ctrl+p from Settings, and once at creation.
App::Moneymoor::Screen::Main::Modals::open-period-picker($main);
App::Moneymoor::Screen::Main::Modals::open-period-picker($main, :first-run);

# The budget tab's, all keyed off whatever row its table has selected:
App::Moneymoor::Screen::Main::Modals::open-assign($main);          # a
App::Moneymoor::Screen::Main::Modals::open-move-money($main);      # m
App::Moneymoor::Screen::Main::Modals::open-fund-all($main);        # f
App::Moneymoor::Screen::Main::Modals::open-explain($main);         # x
App::Moneymoor::Screen::Main::Modals::open-category-editor($main); # n
App::Moneymoor::Screen::Main::Modals::open-group-editor($main);    # g
App::Moneymoor::Screen::Main::Modals::hide-category($main);        # h

# The accounts tab's, keyed off its register cursor or its sidebar:
App::Moneymoor::Screen::Main::Modals::open-transaction-editor($main);   # n / e
App::Moneymoor::Screen::Main::Modals::open-transfer($main);             # t
App::Moneymoor::Screen::Main::Modals::cycle-cleared($main);             # c
App::Moneymoor::Screen::Main::Modals::delete-transaction($main);        # d
App::Moneymoor::Screen::Main::Modals::open-account-editor($main);       # n
App::Moneymoor::Screen::Main::Modals::toggle-account-closed($main);     # c

# Reconcile mode (§4.5): ctrl+r starts it, Enter finishes it.
App::Moneymoor::Screen::Main::Modals::open-reconcile($main);            # ^r
App::Moneymoor::Screen::Main::Modals::finish-reconcile($main);          # enter

# Give a Selkie-provided dialog Moneymoor's backdrop:
$app.show-modal(scrimmed($help-overlay.build));

# Pure, and so directly testable:
period-option-index($ws.scheme);            # 0 / 1 / 2, the picker's list
parse-period-choice(1, day => '14');        # Period(monthly/14)
parse-assign-input('+5');       # { mode => 'adjust', amount => 500 }
parse-assign-input('400');      # { mode => 'set',    amount => 40000 }
parse-assign-input('=450');     # { mode => 'fund-to', amount => 45000 }
parse-assign-input('=');        # { mode => 'fund-target' }
parse-target('400');            # 40000 — the editor's Target field
parse-target('');               # 0     — blank clears the target
parse-repeat('3');              # 3     — the editor's Repeat field
parse-repeat('');               # 0     — blank is a one-off goal
signed-amount(1250, 'Outflow'); # -1250
number-example('.');            # '1,234.56'  (the Settings label)
number-example(',');            # '1.234,56'
split-remainder(1250, (500, 250));  # 500 still to allocate
payee-suggest-tail(('Tesco', 'Tesco Express'), 'tes');   # 'co'
balance-adjustment(account-id => 1, amount => 1240,
                   date => '2026-03-31', rta-category-id => 3);
# { txn => Transaction(+£12.40, reconciled), splits => [Split(RTA, 1240)] }

=end code

=head1 DESCRIPTION

Every function takes the C<Main> screen as its first argument and
reaches into it through the public accessors (C<.app>, C<.config>,
C<.store>, C<.theme>, C<.view>, C<.viewed-period>, C<.with-modal>,
C<.apply-theme-live>). The screen keeps one-line delegates
(C<Main.open-settings>, C<Main.open-diagnostics>) so keybind call sites
don't have to know where a dialog's body lives.

Both dialogs open through C<Main.with-modal>, which owns the lifecycle
contract: the modal closes I<before> the body runs, and Esc closes.
Diagnostics is read-only and so passes a supply that never emits — the
point of a single wrapper is that the Esc binding and the close
ordering are written once, not that every dialog has a submit path.

=head2 Settings

Four C<Select>s — palette, glyph tier, currency symbol, number format
— with a live colour-swatch row under the first that re-paints as the
highlighted palette changes, so the user sees what they are choosing
before committing to it. C<Ctrl+S> writes all four keys to
C<App::Moneymoor::Config> and closes.

The two money settings are then pushed into
C<App::Moneymoor::Util::Money::set-money-locale>, and the redraw is
the one C<Main.apply-theme-live> was already doing: it rebuilds the
content area, and every figure in the tree is formatted on the way
through, so a currency or decimal-mark change needs no plumbing of its
own to reach the budget grid, the register, the sidebar or the
reports. No restart for any of the four.

Under those four is the B<period> section, which is a line of text and
a key rather than a fifth picker: the other four are display
preferences in C<config.json>, and the period is a property of the
budget I<file> whose change rewrites every assignment row. C<Ctrl+P>
closes Settings and opens the picker — see THE PERIOD PICKER — so
re-bucketing somebody's money can never be a side effect of changing a
currency symbol.

The number-format C<Select> lists B<examples> (C<1,234.56> /
C<1.234,56>), not the bare mark, because the setting moves two
characters at once — the decimal mark and, by implication, the
thousands separator — and one example says that where a C<,> in a
dropdown does not. C<number-example> derives the label from the mark,
so the two lists stay index-aligned and the submit can map the
selection back by index.

=head2 THE PERIOD PICKER

C<open-period-picker> is the one dialog that decides how the whole
budget is bucketed, and it is reached two ways: C<Ctrl+P> from
Settings, and once with C<:first-run> immediately after a budget is
created.

B<The first run asks after creation, not during it.> The
create-a-budget form is 24 rows tall, which is the whole of the
terminal it has to fit; three more fields and a picker do not go in it.
So the question is asked over the new, empty budget — where changing
the scheme moves no money whatsoever — and Esc means "the calendar
month, then", which is what the file already says. Nothing is written
for that answer: an absent C<period_scheme> B<is> the calendar month,
and recording the default as a choice would leave a file diff and a
"changed" toast for a change nobody made. Choosing it from Settings
later does write the key, because by then it is a change from
something.

B<Three options, two schemes.> "Calendar month (the 1st)" and "Day of
the month" are the same C<monthly> scheme; the first is
C<< anchor-day => 1 >>. The split is the difference between asking
somebody what their budget looks like and asking them what the engine
should store. C<parse-period-choice> normalises a typed day of 1 back
onto the calendar month for free, because they are the same scheme. The
first option names the day it pins because "Calendar month" alone reads
as "a month-long period, starting when?", and a user with a Day field
in front of them will answer that themselves.

B<Only the fields the selected option reads are on the dialog.> None
for the calendar month, Day for the day-of-the-month option, Weeks and
First payday for the weekly one. C<parse-period-choice> ignores the
fields its mode does not use, and a field that renders, takes focus and
accepts keystrokes I<is> an input — so leaving the unused ones on
screen made a correct save look like a broken one ("Calendar month",
14 typed into a visible Day box, Ctrl+S, "Budget period unchanged").
The rows live in a C<VBox> of their own between the Select and the
hint, rebuilt on each change — C<Container.clear> destroys what it
removes, so this is the Login screen's mode switch rather than the
transaction editor's swap — and what was typed is remembered across the
rebuild, so flipping options and back costs nobody a date. The dialog
keeps one height throughout: the flex error line absorbs the rows an
option does not use.

The hint under the fields spends three of those rows, at every option.
It is a C<RichText> that wraps, because all three sentences are longer
than the 44 columns this dialog has and a one-row C<Text> cut every one
of them off mid-clause — including the one saying what the weekly
option counts its periods from, which is the only place that is said.
Three rows is the longest of them measured through
C<RichText.wrap-spans>, not guessed, and t/90 re-measures it so a
re-wording that runs long fails a test instead of silently dropping its
last line.

B<Changing it on a budget with history is a confirm with numbers in
it.> C<Workspace.re-bucket-preview> is a read-only dry run, and its
counts go into the message: how many assignments move, how many periods
they are in now, how many they will be in, and — when the answer is not
zero — how many will land on top of another and be added together. That
last one is the only irreversible part of the operation (changing back
restores the totals, not the split), so it gets its own sentence. The
same scheme again is a toast naming the scheme the budget is staying on
and no dialog; a budget with no assignments at all skips the confirm,
for the same reason fund-all with nothing to fund does.

B<Applying it re-seeds C<app/period>.> After a change the store is
holding a key from the old scheme, which is very likely not a start
under the new one, and C<app/period-set>'s guard would drop it. The
apply path therefore dispatches the new scheme's C<current-period>, and
the recompute that follows carries the change to the banner, the grid,
the pill and the reports through the digest every subscription already
watches.

=head2 The budget dialogs

Seven, and they share three rules.

B<Every write goes through C<ws/mutate>.> Not one of these functions
calls a gateway directly: they build the call as a closure and dispatch
it, so the Failure check, the toast, the C<.so> and the recompute are
written once (C<App::Moneymoor::StoreHandlers>). That is also why a
refused delete shows the engine's own "hide it instead" wording rather
than something this file invented.

B<Validation happens before the submit supply emits.> C<with-modal>
closes the dialog and I<then> runs the body, which is right for a
dialog that has succeeded and wrong for one the user has fat-fingered.
So the input's own C<on-submit> is tapped first, and the supply
C<with-modal> sees only ever carries a value that has already parsed.
A malformed amount paints the error line inside the still-open dialog.

B<The row decides what is possible.> C<a>, C<m>, C<x>, C<h> and C<d>
need an envelope, so on a group header C<a>, C<m>, C<x> and C<h> toast
and return; C<e> and C<d> ask the row what it is and open the matching
editor or confirm. Nothing silently acts on a neighbouring row. C<f>
is the exception that proves it: fund-all is about the whole period,
not about the row, so it works from a header and from the empty state
just as well.

=head2 Saving: Enter and Ctrl+S

Every field in every dialog here is single-line, so B<Enter in a text
field saves the form>, through the same closure C<Ctrl+S> runs — the
same validation, the same refusals, the same error line. Ctrl+S stays,
because it works from a picker as well as from a field.

That is wired per field (C<enter-saves>), not as an C<enter> keybind on
the modal, and the reason is C<Selkie::App>'s dispatch order: a key goes
to the B<focused> widget first and walks C<parent>-wards, with the
modal's own keybinds consulted B<last>. C<TextInput> consumes Enter —
emitting C<on-submit> is what it does with it — so a modal-level bind
would never see Enter from a field at all. It also means the widgets
that already own Enter keep it: a C<Select> opens or commits its
dropdown, a C<RadioGroup> picks, a C<Checkbox> toggles, and the
transaction editor's splits C<ListView> edits the split under its
cursor. None of those save, which is the point — Enter on a picker
means "choose this", not "I am done".

The one dialog without an Enter-save is Settings: it has no text field
at all, only pickers, and Enter in a picker is how you pick.

=head3 Assign — the C<+>/C<->/C<=> rule

A leading sign means B<adjust by>, a leading C<=> means B<fund to>,
anything else means B<set to>:

Every "Typed" cell below is quoted because two of them begin with an
C<=>, and a Pod table cell is plain text — no formatting codes in it,
and a line starting with C<=> is a directive:

=begin table
Typed        | Effect
-------------+--------------------------------------------
'400'        | set-assigned £400.00
'£1,234.56'  | set-assigned £1,234.56
'+5'         | adjust by +£5.00
'-2.50'      | adjust by -£2.50
'(5.00)'     | set-assigned -£5.00
'=450'       | make AVAILABLE £450.00 this period
'='          | make available equal this envelope's target
=end table

C<(5.00)> is the escape hatch, and it is why the sign rule can be this
simple: negative assignments are legal (pulling money back out of a
category that had none this period is an ordinary correction), so there
has to be some way to type one, and C<-5> is already spoken for.
Accountant parentheses are the notation every CSV export already uses
for it, and C<parse-pence> already accepts them.

C<=450> is about B<available>, not about assigned, and that is the
whole reason it exists. Assigned is what you put in; available is what
is left after carry-in, spending and the derivation's own card moves —
and "I want £450 in this envelope" is what a person actually means. So
C<=450> is implemented as C<adjust(450 - available)>, never as a set:
setting I<assigned> to 450 on an envelope that already carried £37.50
in would leave £487.50 available, which is not what the user typed.

Three consequences fall out of that:

=item B<A negative fund-to is refused.> C<=-5> and C<=(5)> both reach
      C<parse-pence> as minus five pounds, and "fund to minus five" is
      not a thing anyone means. Taking money out is C<-5>, which the
      sign rule above already reads.
=item B<A zero delta writes nothing.> C<=450> on an envelope already
      sitting at £450 closes with a toast saying so and dispatches no
      mutation at all. The upsert would be a no-op in the database and
      anything but a no-op in the app: it bumps C<ws/rev>, re-derives
      the whole budget and repaints every subscription to announce
      that nothing changed.
=item B<A bare C<=> needs a target.> C<parse-assign-input> is pure and
      has no envelope to ask, so it answers C<fund-target> and the
      dialog resolves it. No target, and the dialog stays open with
      "No target set — edit the envelope to add one" on its error
      line, which is the same validate-before-emit contract every
      other refusal here obeys.

A bare C<=> is B<not> a fund-to, though it used to be. It is "fund
this envelope's plan for this period", and only under a C<refill>
target is that plan's gap C<target − available>: a set-aside measures
this period's assignments and a goal measures its milestone, so the
old identity is simply false for two kinds out of three. The dialog
therefore resolves C<=> through C<Service::Target.target-ask> — the
one function every target feature keys on — and emits the ask itself
as an adjustment. A zero ask takes the same no-write path a zero
delta does, for the same reason.

=head3 Fund all — C<f>

The same idea over the whole period, in one write:
C<open-fund-all> lists every standard, visible envelope whose plan
asks for something this period, with the C<+£> each would take, a
total, and what Ready to Assign will be afterwards. Enter or Ctrl+S
confirms.

Four rules, all of them stated in C<fund-all-candidates> and
C<open-fund-all>'s own Pod: standard envelopes only, a target above
zero, not hidden, and underfunded — fund-all only ever B<adds>, and
will not pull an over-target envelope back down. "Underfunded" is
C<target-ask> and nothing else, so C<f> funds a refill to its level, a
set-aside's contribution and a goal's next milestone in the same
sweep; each line says the figure it lands on, which for a goal is that
milestone and not the goal's total. Nothing to fund is a toast rather
than a dialog whose only answer is "do nothing".

Confirming dispatches B<one> C<ws/mutate> closure that loops the
adjustments, so twenty envelopes are one derivation and not twenty,
and a refusal partway through stops the run and toasts the engine's
own words.

Ready to Assign is allowed to go negative, loudly: the modal says what
RTA will be, in red and in words, when the answer is below zero — and
then lets the user do it anyway. Assigning money that has not arrived
is a real step on the way to a plan, and the app's job is to be
unmistakable about it, not to forbid it.

=head2 The accounts dialogs

Seven, and they obey the same three rules as the budget's — every write
through C<ws/mutate>, validation before the submit supply emits, the
row under the cursor decides what is possible. Four of them are worth
reading about.

=head3 The transaction editor, and the shape of a transaction

A transaction is an amount on an account, and — on an on-budget
account — a set of splits that sum to it. The form types the amount as
a positive figure plus an Outflow/Inflow choice, because that is how a
register reads it and how a bank statement prints it; C<signed-amount>
is the one place the sign is applied.

Splits are an entries list, in Mindmoor's pattern: a C<ListView> of
formatted rows over an array of entry hashes, with a nested dialog for
adding and editing one. It is B<always mounted>, and its content — not
its presence — changes:

=item empty, which is the ordinary case: the row reads "one category,
      press a to split", and the Category picker above it is live.
      Saving builds exactly one split, which is what the engine stores
      for a single-category transaction anyway.
=item non-empty: the Category picker is replaced (in content, not in
      layout) by "(split across N categories)" and ignored, and the
      remainder line under the list says how much of the amount is
      still unallocated.

The alternative — a C<Split…> toggle that grows the dialog — means
adding and removing widgets from a live C<VBox>, which costs the
editor's transient state (C<Container.clear> destroys its children) and
risks a zero-allocation child painting outside its parent. Swapping
content is the same UX with none of that.

Saving is refused while the remainder is non-zero: the remainder line
turns amber, the status line says Save is disabled, and C<Ctrl+S> does
nothing. There is no Save button to grey out — this is a keyboard
dialog — so the greying is the amber and the refusal.

Split amounts are typed as positive figures too, and take the
transaction's direction. Accountant parentheses are the escape hatch
for the odd line that runs the other way (a refund inside a purchase),
exactly as they are in the Assign dialog.

=head3 What the editor will not let you change

=item B<The account, once the transaction exists.> The engine refuses
      to move a transfer leg outright, and moving an ordinary
      transaction between accounts silently rewrites two balances —
      offering it in the same form as a memo edit invites it by
      accident. Delete and re-enter.
=item B<A tracking account's category.> The derivation excludes
      tracking splits, and C<Gateway::Transaction> refuses them, so the
      picker says so instead of pretending.
=item B<A transfer's endpoints.> Same reason; the payee and category
      fields are replaced by the transfer's own facts.

A reconciled transaction gets a confirm first. Reconciled means "this
matched a statement", and the whole point of the state is that it does
not change by accident.

=head3 The transfer dialog carries a category

§4.4 draws it as from / to / amount / date / memo, which is right for a
transfer inside the budget. A transfer that B<crosses> the budget
boundary — cash out to a tracking account, or in from one — is money
entering or leaving the envelopes, and C<create-transfer> refuses it
without a split on the on-budget leg. So the picker is there, with a
line saying when it applies, and it is ignored for the transfers where
the engine would refuse it.

=head3 Reconcile is a mode, and it finishes in one write

C<Ctrl+R> asks for the statement balance and writes
C<accounts/reconcile>; from then on the register's frame carries the
diff and Enter means "finish" instead of "edit". The dialogs here are
the two ends of that: C<open-reconcile> takes the figure, and
C<finish-reconcile> either promotes or offers the transaction that
would let it.

Two decisions worth stating:

=item B<Promotion is one C<ws/mutate> closure.> Every C<cleared>
      transaction on the account is set to C<reconciled> inside a
      single action, so the budget is derived once. Per-transaction
      dispatches would derive it once per row, each derivation
      discarding the last.
=item B<An out-of-balance finish is a confirm, not a refusal.> The
      difference is offered as a C<Balance Adjustment> transaction —
      signed from the account's point of view, filed to Ready to
      Assign on a budget account and to nothing at all on a tracking
      one — and declining leaves the mode running with every cleared
      mark intact. A statement that does not match usually means a
      receipt that has not been entered, and the app should not make
      the user choose between finishing wrongly and starting over.

=head3 Deleting an account is the one true cascade

Every other delete in the app is either refused (a category with
history) or lossless (a group). C<Gateway::Account.delete> is a hard
delete of the account, its transactions, their splits and the peer leg
of every transfer that touched it. The confirm says all of that in
words, and offers closing the account as the thing the user probably
meant.

=head2 Diagnostics

A read-only dump of what the derivation thinks about the current
budget: C<view.warnings>, C<view.invariant-errors>, the viewed period's
flags, and the C<canonical-digest>.

The first two should be B<empty> on any budget written through the
gateways — they exist to catch facts the derivation could not make
sense of. Non-empty means a bug, and the dialog says so in as many
words and in the palette's red, because a warning list nobody knows is
abnormal is a warning list nobody reports.

The digest is there for exactly that report. Note that
C<canonical-digest> is B<not> a fingerprint despite the name: it is the
full canonical serialisation of the derivation — one line per period,
per category-period, per move and per account, every figure in it. That
is the right thing for the engine (it is what makes the property tests
able to say "these two derivations are identical"), but it is the wrong
thing to paint into a dialog: hundreds of lines, and every balance the
user owns. So the dialog shows a 64-bit FNV-1a fingerprint of it plus
the line count — enough to say "my budget is in state X" in an issue,
and safe to paste in public.

=head1 EXPORTS

Private — every sub is C<our sub>, called by fully-qualified name. The
module name is the namespace boundary.

=head1 SEE ALSO

=item L<App::Moneymoor::Screen::Main> — C<with-modal> and the accessors.
=item L<App::Moneymoor::View::ModalChrome> — the shared style bundle
      and the swatch spans.
=item L<App::Moneymoor::Service::Budget> — what C<warnings> /
      C<invariant-errors> / C<canonical-digest> mean.

=end pod

use Selkie::BorderStyle;
use Selkie::Layout::VBox;
use Selkie::Sizing;
use Selkie::Style;
use Selkie::Widget::Checkbox;
use Selkie::Widget::ConfirmModal;
use Selkie::Widget::ListView;
use Selkie::Widget::Modal;
use Selkie::Widget::RadioGroup;
use Selkie::Widget::RichText;
use Selkie::Widget::RichText::Span;
use Selkie::Widget::Select;
use Selkie::Widget::Text;
use Selkie::Widget::TextInput;

use App::Moneymoor::Config;
use App::Moneymoor::Model::Account;
use App::Moneymoor::Model::Category;
use App::Moneymoor::Model::CategoryGroup;
use App::Moneymoor::Model::Split;
use App::Moneymoor::Model::Transaction;
use App::Moneymoor::Service::Budget;
use App::Moneymoor::Service::Icons;
use App::Moneymoor::Service::Target;
use App::Moneymoor::Theme;
use App::Moneymoor::Themes;
use App::Moneymoor::Util::Money;
use App::Moneymoor::Util::Period;
use App::Moneymoor::View::BudgetRow;
use App::Moneymoor::View::InspectorPane;
use App::Moneymoor::View::ModalChrome;
use App::Moneymoor::View::RegisterRow;

#|( Put Moneymoor's backdrop on a modal Selkie built for us.

    Every dialog the app builds itself opens over a scrim — the screen
    behind stays legible, tinted through the palette's C<modal-scrim>
    slot — and the Selkie-provided ones (C<ConfirmModal>,
    C<CommandPalette>, C<HelpOverlay>) would otherwise open over the
    stock opaque plane, which reads as a different app.
    C<set-backdrop> is a runtime setter, so this costs no fork of the
    widgets.

    Framing is not available the same way: C<framed> is a
    construction-time flag and none of the three exposes it, so they
    stay frameless with their in-content headings.

    Returns the modal, so it can wrap a C<build> call inline. )
our sub scrimmed(Selkie::Widget::Modal $modal --> Selkie::Widget::Modal) {
    $modal.set-backdrop(BackdropScrim);
    $modal;
}

# The glyph tiers, in the order the Select lists them. Duplicated from
# nowhere: Service::Icons resolves a tier name to a table but does not
# enumerate the names, and inventing an accessor there to serve one
# Select would put a UI concern in a pure lookup module.
my constant ICON-TIERS = <unicode nerd>;

#|( The label for a decimal mark: a worked example rather than the
    character itself.

    "." and "," in a dropdown are two one-pixel-different glyphs
    describing a rule with two halves (the mark I<and> the grouping
    that follows from it). "1,234.56" and "1.234,56" show both halves
    at once and need no legend. Derived from the mark so the two lists
    cannot drift out of index alignment. )
our sub number-example(Str:D $mark --> Str) {
    my Str $group = $mark eq '.' ?? ',' !! '.';
    '1' ~ $group ~ '234' ~ $mark ~ '56';
}

our sub open-settings($main) {
    my $cfg = $main.config;
    return without $cfg;   # nothing to edit, and nowhere to save it

    my $app    = $main.app;
    my %styles = modal-styles(theme => $main.theme);

    # Four pickers, four captions, the swatch and the three-row period
    # section is twelve content rows, and a framed modal spends four of
    # its own on borders and padding — so on the 24-row terminal this
    # has to fit, 0.75 (18 rows, 14 for content) is the first ratio that
    # holds all of it and still leaves the flex spacer something to eat.
    my $modal = Selkie::Widget::Modal.new(
        width-ratio        => 0.5,
        height-ratio       => 0.75,
        backdrop           => BackdropScrim,
        framed             => True,
        frame-style        => BorderRounded,
        frame-title        => 'Settings',
        frame-bottom-title => 'ctrl+s save · esc cancel',
    );

    my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);

    # No leading space on the captions: the frame's one cell of padding
    # is the inset, and a baked-in space would offset every label a
    # column right of the control it names.
    $content.add: Selkie::Widget::Text.new(
        text => 'Theme', sizing => Sizing.fixed(1), style => %styles<dim>,
    );

    my @names = App::Moneymoor::Themes::all-names();
    my $theme-select = Selkie::Widget::Select.new(sizing => Sizing.fixed(1));
    $theme-select.set-items(@names);
    $content.add($theme-select);

    my $swatch = Selkie::Widget::RichText.new(sizing => Sizing.fixed(1));
    $content.add($swatch);

    # Live preview. `Select` commits on Enter / Space / click, which is
    # the only "hover" signal it has, so on-change is what drives the
    # swatch. Registered before the preselect below so one guarded
    # handler covers both — and the guard matters, because
    # `select-index` fires on-change whenever it actually moves the
    # selection, and the preselect is exactly that.
    my Bool $built = False;
    $theme-select.on-change.tap: -> $idx {
        rebuild-swatch($swatch, App::Moneymoor::Themes::load(@names[$idx]))
            if $built;
    };
    my $theme-idx = @names.first($cfg.theme, :k) // 0;
    $theme-select.select-index($theme-idx.UInt);
    rebuild-swatch($swatch, App::Moneymoor::Themes::load(@names[$theme-idx]));

    $content.add: Selkie::Widget::Text.new(
        text => 'Icons', sizing => Sizing.fixed(1), style => %styles<dim>,
    );
    my $icons-select = Selkie::Widget::Select.new(sizing => Sizing.fixed(1));
    $icons-select.set-items(ICON-TIERS.List);
    $icons-select.select-index((ICON-TIERS.first($cfg.icons, :k) // 0).UInt);
    $content.add($icons-select);

    # Currency and Numbers. Both lists come from Util::Money rather
    # than from a constant here: it owns the whitelist `Config`
    # validates against and `set-money-locale` refuses outside, and a
    # picker offering a fourth option none of them knew about would be
    # a save that throws.
    my @symbols = money-symbols();
    $content.add: Selkie::Widget::Text.new(
        text => 'Currency', sizing => Sizing.fixed(1), style => %styles<dim>,
    );
    my $currency-select = Selkie::Widget::Select.new(sizing => Sizing.fixed(1));
    $currency-select.set-items(@symbols);
    $currency-select.select-index((@symbols.first($cfg.currency, :k) // 0).UInt);
    $content.add($currency-select);

    # The Select's items are the worked examples, so the value it hands
    # back has to be mapped to a mark; index is the join, which is why
    # the examples are derived from @marks rather than written out.
    my @marks    = money-decimal-marks();
    my @examples = @marks.map({ number-example($_) });
    $content.add: Selkie::Widget::Text.new(
        text => 'Numbers', sizing => Sizing.fixed(1), style => %styles<dim>,
    );
    my $numbers-select = Selkie::Widget::Select.new(sizing => Sizing.fixed(1));
    $numbers-select.set-items(@examples);
    $numbers-select.select-index(
        (@marks.first($cfg.decimal-mark, :k) // 0).UInt);
    $content.add($numbers-select);

    # Period: a line of text and a key, not a fifth picker. The other
    # four settings are display preferences in `config.json` that a save
    # writes and a rebuild re-renders; the period is a property of the
    # budget FILE, and changing it rewrites every assignment row into
    # different buckets. That belongs behind its own dialog and its own
    # confirm — a Select sitting in a row of four, saved by the same
    # Ctrl+S as a colour scheme, would re-bucket somebody's money as a
    # side effect of changing the currency symbol.
    $content.add: Selkie::Widget::Text.new(
        text => 'Period', sizing => Sizing.fixed(1), style => %styles<dim>,
    );
    my $ws = $main.workspace;
    $content.add: Selkie::Widget::Text.new(
        text   => ($ws.defined ?? $ws.scheme.describe !! ''),
        sizing => Sizing.fixed(1), style => %styles<label>,
    );
    $content.add: Selkie::Widget::Text.new(
        text => 'ctrl+p change', sizing => Sizing.fixed(1),
        style => %styles<hint>,
    );

    # A flex spacer, so the field blocks stay at the top of the dialog
    # whatever height ratio resolves to on this terminal.
    $content.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);

    $modal.set-content($content);
    $built = True;

    # Ctrl+S is the submit signal: neither Select emits anything a
    # `with-modal` body could hang off, and a dedicated Save button
    # would cost a row and a Tab stop for no gain over the key the
    # bottom title already advertises.
    my $submit = Supplier.new;
    $modal.on-key: 'ctrl+s',
        -> $ {
            # The decimal mark travels as a mark, not as the example
            # string the Select is showing: `selected` is the index
            # into the list both were built from.
            $submit.emit({
                theme    => ($theme-select.selected-value    // $cfg.theme),
                icons    => ($icons-select.selected-value    // $cfg.icons),
                currency => ($currency-select.selected-value // $cfg.currency),
                'decimal-mark' =>
                    (@marks[$numbers-select.selected] // $cfg.decimal-mark),
            });
        },
        :description('Save settings');

    # The period lives in the budget file, not in the config this
    # dialog's Ctrl+S writes, so it chains to its own dialog rather than
    # riding along on this one's save. Settings closes first — the same
    # rule the editors' Ctrl+D delete follows: the second dialog is
    # about something the first was only reporting, and two dialogs deep
    # is one too many to reason about.
    $modal.on-key: 'ctrl+p',
        -> $ {
            $app.close-modal if $app.defined;
            open-period-picker($main);
        },
        :description('Change the budget period');

    $main.with-modal($submit.Supply, $modal, $theme-select,
        body => -> %f {
            $cfg.theme        = %f<theme>;
            $cfg.icons        = %f<icons>;
            $cfg.currency     = %f<currency>;
            $cfg.decimal-mark = %f<decimal-mark>;
            $cfg.save;
            # The locale registers before the rebuild, not after: the
            # rebuild is what re-renders every figure, and it reads the
            # registers as it goes.
            set-money-locale(
                symbol       => $cfg.currency,
                decimal-mark => $cfg.decimal-mark,
            );
            # All four keys land in one pass: apply-theme-live
            # re-resolves the palette AND re-reads the glyph tier, then
            # rebuilds the content area — so every closure that
            # captured either gets the new one, and every money string
            # in the tree is formatted again through the new locale.
            $main.apply-theme-live;
            $app.toast('Settings saved') if $app.defined;
        },
    );
}

#|( Repaint the swatch row for C<$theme>: the eight C<swatch-spans>
    colour chips with a single space between them. C<swatch-spans>
    returns only the chips — spacing is the caller's job, so a
    positional assertion in a test doesn't have to skip over
    interleaved separators. )
sub rebuild-swatch(Selkie::Widget::RichText $swatch,
                   App::Moneymoor::Theme $theme --> Nil) {
    my @chips = swatch-spans(:$theme);
    my @content;
    for @chips.kv -> $i, $span {
        @content.push($span);
        @content.push(Selkie::Widget::RichText::Span.new(text => ' '))
            unless $i == @chips.end;
    }
    $swatch.set-content(@content);
    Nil
}

# --- The period picker ------------------------------------------------

#|( The three shapes a budget period can have, in the order the picker
    lists them, in the words a person paid on the 14th would use.

    Index is the join: it names the option, it decides which detail
    fields are B<on the dialog at all>, and C<parse-period-choice>
    builds the scheme from it. Two of the three are the same C<monthly>
    scheme underneath — the calendar month I<is> C<< anchor-day => 1 >>
    — and that is exactly why the list has three entries: "day of the
    month: 1" is what the engine stores, and "the calendar month" is
    what the user is choosing.

    The first option names the day it pins. "Calendar month" on its own
    reads as "a month-long period", which invites the next question —
    starting when? — and a user who has just typed 14 into a Day field
    will answer it themselves, wrongly. "(the 1st)" closes that off in
    four words, and the fields the option does not use are no longer on
    screen to suggest otherwise. )
my constant PERIOD-OPTIONS =
    'Calendar month (the 1st)', 'Day of the month', 'Every N weeks';

my constant MODE-CALENDAR = 0;
my constant MODE-DAY      = 1;
my constant MODE-WEEKS    = 2;

#|( One hint per option, saying what the choice does to the budget's
    windows, under the fields it applies to.

    Written to be read whole. They are painted through a C<RichText>
    that wraps them (see C<HINT-ROWS>), because the sentence that
    explains what "every N weeks" counts from is worth more than the
    row it costs — and a one-row C<Text> silently cut all three of them
    off mid-clause at the width this dialog actually has. )
my constant PERIOD-HINTS =
    'The 1st to the last day, the way a calendar prints it.',
    'Paid on the 14th? The period runs the 14th to the 13th, '
        ~ 'and short months clamp to their last day.',
    'Periods are counted from the payday above, backwards as well '
        ~ 'as forwards, so older transactions still bucket.';

#|( Rows the hint block claims, whichever option is selected.

    Three is what the longest of C<PERIOD-HINTS> wraps to at this
    dialog's interior width on the terminal the app is built to fit —
    44 columns: C<< width-ratio => 0.6 >> of 80, less the frame's two
    edges and its cell of padding on each side. Measured through
    C<RichText.wrap-spans>, which is the algorithm the renderer wraps
    with, rather than counted by eye; t/90 re-measures the real spans
    and fails if a re-wording runs long, because C<RichText>'s answer
    to overflow is to drop the line it cannot fit.

    Constant across the three options on purpose. The hint sits under
    the fields that come and go, so a block that grew and shrank with
    its own copy would move the error line on every Select change on
    top of the field rows already moving.

    The budget stands at the 24-row floor: 14 interior rows, of which
    the copy line, the caption, the Select and the weekly option's two
    two-row fields take seven and the hint takes three, leaving four
    for the error line — which needs two for the longest refusal. )
my constant HINT-ROWS = 3;

#|( Which option C<$scheme> is, so the picker opens on what the budget
    is already doing rather than on the top of the list.

    C<monthly/1> is the calendar month and takes the first option; every
    other monthly scheme is the day-of-the-month one; weekly is weekly.
    Pure, and exported for the same reason C<parse-assign-input> is: the
    mapping between a scheme and the option that means it is the one
    piece of the picker with semantics in it. )
our sub period-option-index($scheme --> Int) {
    return MODE-WEEKS unless $scheme.defined && $scheme.type eq 'monthly';
    $scheme.anchor-day == 1 ?? MODE-CALENDAR !! MODE-DAY;
}

#|( The picker's fields in, an C<App::Moneymoor::Util::Period> out — or
    a C<Failure> whose message is fit to paint on the dialog's error
    line.

    Pure: no widgets, no screen, no workspace. That is what lets the
    validation rules be asserted directly, and it is why the dialog can
    obey the file's validate-before-emit contract without duplicating
    them.

        parse-period-choice(0)                      # monthly/1
        parse-period-choice(1, day => '14')         # monthly/14
        parse-period-choice(1, day => '1')          # monthly/1 again
        parse-period-choice(2, weeks => '4',
                            payday => '2026-08-14') # weekly/4
        parse-period-choice(1, day => '32')         # Failure

    Day 1 is B<not> a special case here and does not need to be: the
    calendar month and "the 1st of the month" are the same scheme, so
    C<< .monthly(anchor-day => 1) >> normalises the second into the
    first for free, and C<to-hash> proves it.

    The messages name what was typed. A picker that answers "invalid
    input" to C<'32'> is telling the user something they can already
    see. )
our sub parse-period-choice(
    Int:D $mode,
    Str :$day = '',
    Str :$weeks = '',
    Str :$payday = '',
    --> App::Moneymoor::Util::Period
) {
    given $mode {
        when MODE-DAY {
            my Str $d = ($day // '').trim;
            return fail 'Enter the day of the month the period starts on'
                if $d eq '';
            return fail "The day of the month must be a whole number "
                        ~ "between 1 and 31 (got '$d')"
                unless $d ~~ / ^ \d+ $ /;
            my Int $n = $d.Int;
            return fail "There is no { $n }th day in every month — the "
                        ~ 'day of the month must be between 1 and 31'
                unless 1 <= $n <= 31;
            App::Moneymoor::Util::Period.monthly(anchor-day => $n);
        }
        when MODE-WEEKS {
            my Str $w = ($weeks // '').trim;
            return fail 'Enter how many weeks long a period is'
                if $w eq '';
            return fail "The number of weeks must be a whole number "
                        ~ "(got '$w')"
                unless $w ~~ / ^ \d+ $ /;
            my Int $n = $w.Int;
            return fail 'A period is at least one week long' unless $n >= 1;

            my Str $anchor = ($payday // '').trim;
            return fail 'Enter the first payday, as YYYY-MM-DD'
                if $anchor eq '';
            return fail "Malformed date '$anchor' (expected YYYY-MM-DD)"
                unless valid-date($anchor);
            App::Moneymoor::Util::Period.weekly(weeks => $n, anchor => $anchor);
        }
        default {
            # Anything that is not one of the two detailed options is
            # the calendar month, which is also what an out-of-range
            # index would have to mean: the Select cannot produce one,
            # and inventing a fifth failure mode for it would be a
            # message no user can ever read.
            App::Moneymoor::Util::Period.default-scheme;
        }
    }
}

#|( The period picker — the one dialog that decides how the whole budget
    is bucketed. Opened from Settings with C<ctrl+p>, and once with
    C<:first-run> just after a budget is created.

    B<Why the first run is a dialog after creation, not a field in the
    login form.> The create-a-budget form is 24 rows tall on the nose,
    which is exactly the height of the terminal it has to fit; there is
    no room in it for three more fields and a picker. So the question is
    asked the moment the shell comes up, over an empty budget where
    changing the scheme moves no money at all, and Esc means "the
    calendar month, then" — which is what the file already says.

    B<Three options, two schemes, one Select.> "Calendar month (the
    1st)" and "Day of the month" are both C<monthly>; the first is
    C<< anchor-day => 1 >>. Splitting them is the difference between
    asking somebody what their budget looks like and asking them what
    the engine should store.

    B<Only the fields the option reads are on the dialog.> The calendar
    month has none, the day-of-the-month option has Day, the weekly one
    has Weeks and First payday — and nothing else is rendered.
    C<parse-period-choice> has always ignored the fields its mode does
    not use, and that is exactly the problem this shape fixes: a field
    that paints, takes focus and accepts a keystroke I<is> an input, so
    one that is quietly discarded on save reads as a bug in the save.
    (It was reported as one: "Calendar month", type 14 into the visible
    Day box, Ctrl+S, "Budget period unchanged" — three times.)

    The rows live in their own C<VBox> between the Select and the hint,
    and it is the only thing the mode switch touches: the copy line,
    the caption, the Select, the hint and the error line are built once
    and never move in the tree. The rows themselves are rebuilt on each
    switch rather than parked, because C<Container.clear> destroys what
    it removes — the Login screen's mode switch, for the Login screen's
    reasons. What the user typed survives that in C<$day-text> and
    friends, saved back off the live inputs on the way out of a mode
    and handed to the fresh row on the way back in, so flipping between
    the options and back does not cost them the date they just entered.

    The modal keeps one height across all three. The freed rows go to
    the error line, which is the flex child, so choosing an option
    never resizes the dialog under the user's hands.

    B<Validation happens before the supply emits>, like every other
    dialog here: a day of 32, a week count of 0 or a payday that is not
    a date paints the error line inside the still-open dialog. )
our sub open-period-picker($main, Bool :$first-run = False) {
    my $ws     = $main.workspace;
    my $scheme = $ws.defined
        ?? $ws.scheme !! App::Moneymoor::Util::Period.default-scheme;
    my %styles = modal-styles(theme => $main.theme);

    # Ten content rows at the widest the dialog ever gets — the copy
    # line, the caption and its Select, the weekly option's two two-row
    # fields and the three-row hint — and a framed modal spends four of
    # its own, so 0.75 of a 24-row terminal (18, less those four) is 14
    # interior rows: the ten above, and four left for the error line,
    # which needs two for the longest refusal.
    #
    # The other two options render fewer rows, and the height does not
    # follow them down: the error line is flex and absorbs what they
    # free. A modal that resized itself every time the Select moved
    # would jump under the cursor that is still inside it.
    my $modal = Selkie::Widget::Modal.new(
        width-ratio        => 0.6,
        height-ratio       => 0.75,
        backdrop           => BackdropScrim,
        framed             => True,
        frame-style        => BorderRounded,
        frame-title        => 'Budget period',
        # Esc on the first run is not a cancel — there is nothing to
        # cancel yet — it is a choice, and the bottom title says which.
        frame-bottom-title => $first-run
            ?? 'ctrl+s save · esc keep calendar month'
            !! 'ctrl+s save · esc cancel',
    );

    my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);
    $content.add: Selkie::Widget::Text.new(
        text   => $first-run
            ?? 'When does your budget period start?'
            !! 'Currently: ' ~ $scheme.describe,
        sizing => Sizing.fixed(1),
        style  => $first-run ?? %styles<label> !! %styles<dim>,
    );

    $content.add: Selkie::Widget::Text.new(
        text => 'Period', sizing => Sizing.fixed(1), style => %styles<label>,
    );
    my $mode-select = Selkie::Widget::Select.new(sizing => Sizing.fixed(1));
    $mode-select.set-items(PERIOD-OPTIONS.List);
    $content.add($mode-select);

    # The swappable middle, and the only part of this tree the mode
    # switch touches. It opens empty because the calendar month is
    # option zero and asks for nothing; `refresh-fields` fills it and
    # re-declares its height on every change.
    my $fields = Selkie::Layout::VBox.new(sizing => Sizing.fixed(0));
    $content.add($fields);

    # A RichText rather than a Text because these sentences do not fit
    # on one row of a 44-column dialog and are worth reading in full —
    # see HINT-ROWS for the measurement and the row budget.
    my $hint = Selkie::Widget::RichText.new(sizing => Sizing.fixed(HINT-ROWS));
    $content.add($hint);

    my $error = Selkie::Widget::Text.new(
        text => '', sizing => Sizing.flex, style => %styles<error>,
    );
    $content.add($error);
    $modal.set-content($content);

    # What each field opens on when its option puts it on the dialog,
    # and where what was typed in it goes while another option is
    # selected and the row is not in the tree. The day and the weeks
    # start on whatever the budget is already doing; the payday starts
    # on today, because a scheme that is not weekly has no anchor to
    # offer and a blank date field is one more thing to type on a
    # dialog that is already asking a question.
    my Str $day-text = ($scheme.type eq 'monthly' && $scheme.anchor-day > 1)
        ?? $scheme.anchor-day.Str !! '';
    my Str $weeks-text  = $scheme.type eq 'weekly' ?? $scheme.weeks.Str !! '';
    my Str $payday-text = $scheme.type eq 'weekly'
        ?? $scheme.anchor.Str !! Date.today.Str;

    # The inputs currently mounted, or type objects for the ones the
    # selected option does not ask for. Undefined is the honest value
    # here — the widget genuinely is not on the dialog — and every
    # reader guards for it (`field-text`, and `enter-saves`, which
    # skips undefined inputs by contract).
    my Selkie::Widget::TextInput $day-input;
    my Selkie::Widget::TextInput $weeks-input;
    my Selkie::Widget::TextInput $payday-input;

    # Which option's fields are on screen right now. The save-back below
    # therefore happens exactly once per change, and the first call —
    # with nothing shown yet — saves nothing.
    my Int $shown = -1;

    #| What a mounted field holds, or the empty string when the option
    #| on screen has no such field. `.text` on a type object would
    #| throw, and `.?text` would answer Nil rather than a Str.
    my sub field-text($input --> Str) {
        $input.defined ?? ($input.text // '') !! '';
    }

    my $submit = Supplier.new;
    my sub save-now(--> Nil) {
        my $period = parse-period-choice(
            $mode-select.selected.Int,
            day    => field-text($day-input),
            weeks  => field-text($weeks-input),
            payday => field-text($payday-input),
        );
        if $period ~~ Failure {
            # Defused before it is painted: an undefused Failure
            # re-throws when it is next sunk, frames later and nowhere
            # near this dialog.
            my Str $msg = $period.exception.message;
            $period.so;
            $error.set-text($msg);
        } else {
            $submit.emit($period);
        }
        Nil
    }

    #|( Put the rows the selected option actually reads into C<$fields>,
        and nothing else.

        The three steps are all load-bearing. B<Save back> what is on
        screen first, because the rows are about to be destroyed and
        C<$day-text> and friends are the only memory of what the user
        typed. B<Clear and rebuild> rather than hide: C<Container.clear>
        destroys its children, so a row that comes back is a new row —
        which is why the remembered text is what the fresh row opens on.
        B<Re-declare the height> from the rows that were added, so the
        hint sits under the last field rather than under a hole, and
        the freed rows go to the flex error line instead of to the
        modal's height.

        Enter-saves is re-wired here because the inputs it was wired to
        no longer exist; the same C<&save-now> closure backs Ctrl+S, so
        the two keys cannot drift apart.

        B<Focus is never inside a row this destroys.> The only caller
        is the Select's C<on-change>, and the Select holds focus in
        every route to it — the dropdown is a focus trap that closes
        when focus leaves, and C<Selkie::App>'s click-to-focus promotes
        the Select on the press before the commit — plus the one
        explicit call below, which runs before the modal is shown and
        focused at all. )
    my sub refresh-fields(Int:D $mode --> Nil) {
        if $shown == MODE-DAY {
            $day-text = field-text($day-input).trim;
        } elsif $shown == MODE-WEEKS {
            $weeks-text  = field-text($weeks-input).trim;
            $payday-text = field-text($payday-input).trim;
        }
        $shown = $mode;

        $fields.clear;
        $day-input    = Selkie::Widget::TextInput;
        $weeks-input  = Selkie::Widget::TextInput;
        $payday-input = Selkie::Widget::TextInput;

        if $mode == MODE-DAY {
            my ($row, $input) = labelled-input(
                'Day', $day-text, %styles<label>,
                placeholder => '1–31 · e.g. 14',
            );
            $day-input = $input;
            $fields.add($row);
        } elsif $mode == MODE-WEEKS {
            my ($weeks-row, $weeks-in) = labelled-input(
                'Weeks', $weeks-text, %styles<label>, placeholder => 'e.g. 4',
            );
            $weeks-input = $weeks-in;
            $fields.add($weeks-row);

            my ($payday-row, $payday-in) = labelled-input(
                'First payday', $payday-text, %styles<label>,
                placeholder => 'YYYY-MM-DD',
            );
            $payday-input = $payday-in;
            $fields.add($payday-row);
        }

        # Asked of the rows rather than hard-coded, so a change to how
        # tall a labelled field is stays a change in one place.
        $fields.update-sizing(
            Sizing.fixed($fields.children.map(*.sizing.value).sum.Int));
        enter-saves(&save-now, $day-input, $weeks-input, $payday-input);

        $hint.set-content([
            Selkie::Widget::RichText::Span.new(
                text  => PERIOD-HINTS[$mode] // PERIOD-HINTS[MODE-CALENDAR],
                style => %styles<hint>,
            ),
        ]);
        # Everything below `$fields` has just moved, and the rows that
        # went away took their planes with them. A mode switch is a
        # keypress-rare event, so the whole-tree repaint is the cheap
        # and certain answer rather than the extravagant one.
        $content.mark-screen-dirty;
        Nil
    }

    # Registered before the preselect, so one handler covers both — and
    # then called explicitly, because `select-index` only emits when it
    # actually moves the selection and the calendar-month preselect is
    # index 0, which it is on already.
    $mode-select.on-change.tap: -> $idx { refresh-fields($idx.Int) };
    my Int $initial = period-option-index($scheme);
    $mode-select.select-index($initial.UInt);
    refresh-fields($initial);

    $modal.on-key: 'ctrl+s', -> $ { save-now() },
        :description('Save the budget period');

    $main.with-modal($submit.Supply, $modal, $mode-select,
        body => -> $period {
            if $first-run {
                apply-first-period($main, $period);
            } else {
                change-period($main, $period);
            }
        },
    );
}

#|( Adopt C<$period> as the budget's scheme and put the app back on a
    period that exists under it.

    Three things happen in order, and the order is the point:

    =item C<change-scheme> re-buckets and persists, in one transaction.
       It B<dies> rather than failing if its own totals assertion trips
       — which rolls the transaction back — so the call is wrapped and
       the message goes to a toast. The engine's wording already ends
       with "refused, and nothing was written", which is the half the
       user needs.
    =item C<app/period> is re-seeded with the new scheme's current
       period. It is holding a key from the old scheme, which is very
       likely not a period start under the new one, and
       C<app/period-set>'s guard is start-ness against
       C<workspace.scheme> — already the new one by now — so anything
       else would be dropped on the floor and leave the app looking at
       a bucket the engine no longer has.
    =item the toast names the scheme in words, because "changed" on its
       own leaves the user to go and look.

    The re-seed's recompute is also what carries the change to the
    screen: it bumps the digest, which every subscription in the app
    watches, and the banner, the Ready-to-Assign pill, the grid and the
    reports all read C<workspace.scheme> live. Nothing here has to poke
    them. )
sub adopt-period($main, $period, Str:D $verb --> Bool) {
    my $ws = $main.workspace;
    my $done = try { $ws.change-scheme($period); True };
    unless $done {
        toast($main, ($! andthen .message)
                     // 'The budget period could not be changed');
        return False;
    }
    $main.store.dispatch('app/period-set', period => $ws.current-period);
    toast($main, $verb ~ ' — ' ~ $period.describe);
    True;
}

#|( The first-run answer, applied to a budget with nothing in it yet.

    The calendar month is a no-op on purpose: it is what an untouched
    file already means, and writing C<period_scheme> to say so would
    turn the default into a recorded choice — a file diff, a scheme the
    next version has to keep honouring, and a "changed" toast for a
    change nobody made. Choosing it later from Settings does write the
    key, because by then it is a change I<from> something. )
sub apply-first-period($main, $period --> Nil) {
    adopt-period($main, $period, 'Budget period set')
        unless $period.to-hash eqv
               App::Moneymoor::Util::Period.default-scheme.to-hash;
    Nil
}

#|( The Settings answer, on a budget that may well have history.

    Three outcomes, and the middle one is why C<re-bucket-preview>
    exists:

    =item B<the same scheme> — a toast and nothing else. The engine
       would happily re-bucket a budget onto the scheme it is already
       on (it is a legal no-op that still rewrites every row), and a
       confirm asking to move 400 assignments nowhere is a dialog whose
       only honest answer is "why". The toast names the scheme the
       budget is staying on, for the same reason the applied one names
       the scheme it moved to: "unchanged" on its own leaves a user who
       expected a change with nothing to check their expectation
       against.
    =item B<no assignments to move> — apply it directly. A confirm
       listing zero rows is the fund-all "nothing to do" dialog again.
    =item B<anything else> — the confirm, with the actual numbers in
       it.

    The preview is a read-only dry run, but it reads stored period keys
    and throws on one it cannot parse, so it is wrapped like the change
    itself: a corrupt key becomes a toast, not an exception inside a
    modal body. )
sub change-period($main, $period --> Nil) {
    my $ws = $main.workspace;
    if $period.to-hash eqv $ws.scheme.to-hash {
        toast($main, 'Budget period unchanged — ' ~ $period.describe);
        return;
    }

    my $preview = try { $ws.re-bucket-preview($period) };
    without $preview {
        toast($main, ($! andthen .message)
                     // 'The budget period could not be changed');
        return;
    }

    my %p = $preview;
    if %p<rows>.Int == 0 {
        adopt-period($main, $period, 'Budget period set');
        return;
    }
    confirm-period-change($main, $period, %p);
    Nil
}

#|( The re-bucket confirm: what will move, where it will land, and the
    one guarantee that makes saying yes safe.

    The numbers come from the preview rather than from a sentence about
    re-bucketing in general, because "422 assignments across 13 periods
    into 14 periods" is a fact the user can weigh and "your assignments
    will be moved" is not.

    Merges get their own sentence when there are any. Two periods that
    fold into one cannot be told apart afterwards — changing back
    restores the totals, not the split — and that is the only part of
    this operation that is not reversible, so it is said out loud
    rather than left in the Changes file.

    Focus starts on Cancel, like every other confirm in the app. )
sub confirm-period-change($main, $period, %preview --> Nil) {
    my Int $rows   = %preview<rows>.Int;
    my Int $before = %preview<periods-before>.Int;
    my Int $after  = %preview<periods-after>.Int;
    my Int $merged = %preview<merged>.Int;

    my sub plural(Int:D $n, Str:D $word --> Str) {
        $n ~ ' ' ~ $word ~ ($n == 1 ?? '' !! 's');
    }

    my Str $message = 'Re-bucket ' ~ plural($rows, 'assignment')
        ~ ' across ' ~ plural($before, 'period')
        ~ ' into ' ~ plural($after, 'period')
        ~ ' under ' ~ $period.describe
        ~ '? Envelope totals are preserved.';
    $message ~= ' ' ~ plural($merged, 'assignment')
        ~ ($merged == 1 ?? ' lands' !! ' land')
        ~ ' on top of another and ' ~ ($merged == 1 ?? 'is' !! 'are')
        ~ ' added together, which changing back will not undo.'
        if $merged > 0;

    my $confirm = Selkie::Widget::ConfirmModal.new;
    my $modal = scrimmed($confirm.build(
        title     => 'Change budget period',
        :$message,
        yes-label => 'Re-bucket',
        no-label  => 'Cancel',
    ));
    $main.with-modal($confirm.on-result, $modal, $confirm.no-button,
        body => -> Bool $yes {
            adopt-period($main, $period, 'Budget period changed') if $yes;
        },
    );
    Nil
}

our sub open-diagnostics($main) {
    my $modal = Selkie::Widget::Modal.new(
        width-ratio        => 0.7,
        height-ratio       => 0.7,
        backdrop           => BackdropScrim,
        framed             => True,
        frame-style        => BorderRounded,
        frame-title        => 'Diagnostics',
        frame-bottom-title => 'esc close',
    );

    my $body = Selkie::Widget::RichText.new(sizing => Sizing.flex);
    $body.set-content(diagnostic-spans($main));
    $modal.set-content($body);

    # Read-only: the supply never emits, so `with-modal`'s body is
    # unreachable by design and Esc — bound by the wrapper — is the
    # only way out. Routing through the wrapper anyway is what keeps
    # the Esc contract in one place.
    $main.with-modal(Supplier.new.Supply, $modal, $modal,
        body => -> $ { },
    );
}

#|( The diagnostics body, as C<RichText> spans with hard line breaks.

    Reads exactly three things off C<$main> — C<.theme>, C<.view> and
    C<.viewed-period> — and touches nothing else, which is what lets a
    test build the spans against a hand-made C<BudgetView> and assert
    on them without a terminal. That matters more here than for most
    view code: the whole point of the dialog is what it says when
    something has gone wrong, and a bug report is the only time anyone
    reads it.

    A view that has not been computed yet — the window between
    constructing the screen and the first recompute — answers with a
    single honest line rather than a stack of C<Nil>s. )
our sub diagnostic-spans($main --> List) {
    my $theme = $main.theme;
    my $dim    = Selkie::Style.new(fg => $theme.fg-dim);
    my $dimmer = Selkie::Style.new(fg => $theme.fg-dimmer);
    my $label  = Selkie::Style.new(fg => $theme.fg-base);
    my $bad    = Selkie::Style.new(fg => $theme.fg-red);

    my $view = $main.view;
    return (Selkie::Widget::RichText::Span.new(
        text  => 'No budget computed yet.',
        style => $dim,
    ),) without $view;

    my Str $period = $main.viewed-period;
    my @spans;

    sub line(Str $text, $style) {
        @spans.push(Selkie::Widget::RichText::Span.new(:$text, :$style));
    }

    # Raw keys, deliberately: this is the dialog somebody pastes into a
    # bug report, and the label a scheme composes is exactly what is
    # not wanted when the question is which bucket a figure landed in.
    line("Period  $period\n", $label);

    my $bp = $view.period($period);
    my @flags = $bp.defined ?? $bp.flags.List !! ();
    line("Flags   " ~ (@flags ?? @flags.join(', ') !! '(none)') ~ "\n", $dim);
    line("Periods " ~ ($view.periods.elems
        ?? "{$view.periods.elems} ({$view.periods[0]} … {$view.periods[*-1]})"
        !! '(none)') ~ "\n\n", $dim);

    # `warnings` and `invariant-errors` are the two lists that should
    # always be empty. Saying so explicitly — rather than printing
    # nothing — is what makes a non-empty one legible as abnormal.
    section(&line, 'Warnings', $view.warnings.List, $dim, $bad);
    section(&line, 'Invariant errors', $view.invariant-errors.List, $dim, $bad);

    my Str $digest = $view.canonical-digest;
    line("Digest  " ~ digest-fingerprint($digest)
         ~ " ({$digest.lines.elems} lines)\n", $dimmer);

    @spans.List;
}

#|( A 64-bit FNV-1a fingerprint of C<$digest>, as 16 lowercase hex
    digits.

    Why hash at all: see the DESCRIPTION — C<canonical-digest> is the
    whole derivation, not a summary, and neither the dialog nor a
    public bug report can carry it.

    Why FNV-1a and not a real digest: this identifies a state, it does
    not protect one. FNV-1a is a dozen lines, has no dependency, and is
    byte-for-byte reproducible on every platform and every Raku
    version, which is what makes "same fingerprint" mean "same budget"
    between a user's machine and a maintainer's. A cryptographic hash
    would buy nothing here and would pull in a dependency the engine
    doesn't otherwise need.

    Operates on the UTF-8 encoding, not on codepoints, so a payee name
    with an accent in it fingerprints the same everywhere. )
our sub digest-fingerprint(Str:D $digest --> Str) {
    my constant OFFSET = 0xcbf29ce484222325;
    my constant PRIME  = 0x100000001b3;
    my constant MASK   = 0xFFFFFFFFFFFFFFFF;
    my Int $h = OFFSET;
    for $digest.encode('utf-8').list -> $byte {
        $h = (($h +^ $byte) * PRIME) +& MASK;
    }
    sprintf('%016x', $h);
}

#| One diagnostics block: a heading, then either "none" or every entry
#| on its own line in the palette's red with the "this is a bug" note
#| attached to the heading.
sub section(&line, Str:D $title, @entries, $dim, $bad --> Nil) {
    if @entries.elems == 0 {
        line("$title: none\n\n", $dim);
    } else {
        line("$title ({@entries.elems}) — this indicates a bug\n", $bad);
        line("  $_\n", $bad) for @entries;
        line("\n", $dim);
    }
    Nil
}

# ======================================================================
# The budget tab's dialogs
# ======================================================================

# --- Shared plumbing --------------------------------------------------

#| Columns the Explain dialog's equation is flushed right against. Not
#| derived from the modal's width: the dialog is a ratio of the
#| terminal and has no columns until it is laid out, and an equation
#| that re-aligns itself on every resize reads as a glitch. Wide enough
#| for the longest label and a seven-figure sum, narrow enough to stay
#| left-of-centre in a 0.7 modal on an 80-column terminal.
my constant EXPLAIN-COLS = 40;

#| Send a gateway call through the one write path. Every mutation in
#| this file goes through here; see "The budget dialogs".
sub mutate($main, &action --> Nil) {
    $main.store.dispatch('ws/mutate-requested', :&action);
    Nil
}

sub toast($main, Str:D $message --> Nil) {
    my $app = $main.app;
    $app.toast($message) if $app.defined;
    Nil
}

#|( The envelope the budget table's cursor is on, or the C<Category>
    type object plus a toast explaining why not.

    C<$why> names the action so the message is worth reading: "Select
    an envelope to assign to" tells the user what to do next, where
    "no selection" only tells them what went wrong. )
sub selected-envelope($main, Str:D $why --> App::Moneymoor::Model::Category) {
    my $tab = $main.budget-tab;
    return App::Moneymoor::Model::Category without $tab;
    my Int $id = $tab.selected-category-id;
    unless $id.defined {
        toast($main, "Select an envelope to $why");
        return App::Moneymoor::Model::Category;
    }
    my $category = $main.category($id);
    return App::Moneymoor::Model::Category without $category;
    $category;
}

#| A category's current period figures, tolerating a view that has not
#| been computed yet.
sub period-row($main, Int:D $id) {
    my $view = $main.view;
    $view.defined ?? $view.category($main.viewed-period, $id) !! Nil;
}

#| A labelled single-line text field: caption above, input below. Two
#| rows. No leading space on the caption — the frame's own padding is
#| the inset, and a baked-in space would offset the label a column
#| right of the field it names.
sub labelled-input($label, $initial, $label-style,
                   Str :$placeholder = '' --> List) {
    my $row = Selkie::Layout::VBox.new(sizing => Sizing.fixed(2));
    $row.add: Selkie::Widget::Text.new(
        text => $label, sizing => Sizing.fixed(1), style => $label-style,
    );
    my $input = Selkie::Widget::TextInput.new(
        sizing => Sizing.fixed(1), :$placeholder,
    );
    $input.set-text($initial) if ($initial // '').chars > 0;
    $row.add($input);
    ($row, $input);
}

#| A read-only field: caption above, value below in dim text. What a
#| system row's name and group get instead of inputs — the engine
#| refuses to change either, so offering the field would be a lie the
#| user only discovers on save.
sub static-field(Str:D $label, Str:D $value, %styles --> Selkie::Layout::VBox) {
    my $row = Selkie::Layout::VBox.new(sizing => Sizing.fixed(2));
    $row.add: Selkie::Widget::Text.new(
        text => $label, sizing => Sizing.fixed(1), style => %styles<label>,
    );
    $row.add: Selkie::Widget::Text.new(
        text => $value, sizing => Sizing.fixed(1), style => %styles<dim>,
    );
    $row;
}

#|( Enter in a text field saves the form, through the same closure
    C<ctrl+s> runs — gating, validation messages and all.

    Every field in these dialogs is single-line, so Enter has nothing
    else to mean in one. It is wired per field rather than as an
    C<enter> keybind on the modal because that is the only thing that
    works: C<Selkie::App>'s dispatcher offers a key to the B<focused>
    widget first and walks C<parent>-wards from there, consulting the
    modal's own keybinds last, and C<TextInput> consumes Enter (it is
    what emits C<on-submit>). A modal-level bind would therefore never
    see Enter from a field — while a C<Select>, C<RadioGroup>,
    C<Checkbox> or the splits C<ListView> consumes it for its own
    purposes, which is exactly what should keep happening: Enter opens
    a dropdown, toggles a box, edits a split. Only text fields save.

    Undefined inputs are skipped, so a caller can pass a field that a
    system row replaced with static text without guarding at the call
    site.

    Note for the payee field: its ghost suggestion is accepted with
    C<Right>, never with Enter, so Enter saves exactly what is in the
    buffer and cannot silently swallow half a completion. )
sub enter-saves(&save, *@inputs --> Nil) {
    for @inputs -> $input {
        next without $input;
        $input.on-submit.tap: -> Str $ { save() };
    }
    Nil
}

#| A sort-order string the gateways will accept, or the Int type object.
sub parse-sort-order(Str $text --> Int) {
    my Str $s = ($text // '').trim;
    return 0 if $s eq '';
    $s ~~ / ^ '-'? \d+ $ / ?? $s.Int !! Int;
}

#|( The category editor's Target field: pence, or a C<Failure> whose
    message is fit to paint on the dialog's error line.

    Blank is C<0>, which is the "no target" value — clearing the field
    is how a target is removed, so an empty box must not be an error.
    A negative is refused here rather than left to the gateway, so the
    dialog stays open on the typo; the gateway refuses it too, because
    it is not the only caller. )
our sub parse-target(Str $text --> Int) {
    my Str $s = ($text // '').trim;
    return 0 if $s eq '';

    my $pence = parse-pence($s);
    if $pence ~~ Failure {
        my Str $msg = $pence.exception.message;
        $pence.so;
        return fail $msg;
    }
    return fail 'A target cannot be negative — leave it blank for none'
        if $pence < 0;
    $pence;
}

#|( The three target kinds as the category editor's C<Select> offers
    them, and the storage names they map onto position for position.

    Two lists rather than a list of pairs because a C<Select> takes
    labels and answers with an index, and the index is the only thing
    that crosses between them. The order is the order of increasing
    commitment — a level, a habit, a plan — and C<refill> is first
    because it is the default every target-less envelope preselects and
    every legacy file already means. )
our constant TARGET-KIND-LABELS is export =
    'Refill each period', 'Set aside each period', 'Goal by period';
our constant TARGET-KIND-VALUES is export =
    'refill', 'set_aside', 'by_period';

#| The index of the one kind that reads more than an amount, named so
#| the two places that test for it cannot drift from the lists above.
our constant KIND-BY-PERIOD is export =
    TARGET-KIND-VALUES.first('by_period', :k);

#|( The category editor's Repeat field: periods between goals, or the
    C<Int> type object for something that is not a count.

    Blank is C<0>, which is "once" — a one-off goal is the ordinary
    case and should not need the user to type anything. A negative is
    refused here rather than left to the gateway (which refuses it too),
    so the dialog stays open on the typo. )
our sub parse-repeat(Str $text --> Int) {
    my Str $s = ($text // '').trim;
    return 0 if $s eq '';
    $s ~~ / ^ \d+ $ / ?? $s.Int !! Int;
}

#|( Whether the category editor's form asks for a different target from
    the one the row already holds.

    All four fields the front door writes, compared the way they are
    stored: C<target_period> is a date string kept exactly as typed, so
    a goal that has not moved compares equal and does not re-stamp.
    C<target_start> is deliberately B<not> in here — nothing in the app
    may set it, and whether it changes is
    C<Service::Workspace.set-target>'s decision to make. )
sub target-differs($existing, %f --> Bool) {
    return True without $existing;
    ($existing.target-pence // 0)  != %f<target-pence>
        || ($existing.target-kind // 'refill') ne %f<target-kind>
        || ($existing.target-period // '') ne (%f<target-period> // '')
        || ($existing.target-repeat // 0) != %f<target-repeat>;
}

# --- Assign -----------------------------------------------------------

#|( Read an amount field the way §4.3 specifies: a leading C<+> or C<->
    is a relative adjustment, a leading C<=> funds B<to> a figure, and
    anything else is an absolute set. Returns
    C<< { mode => 'set'|'adjust'|'fund-to', amount => Int } >> or
    C<< { mode => 'fund-target' } >>, or a C<Failure> carrying a
    message fit to show the user.

        parse-assign-input('400')      # { set,     40000 }
        parse-assign-input('+5')       # { adjust,    500 }
        parse-assign-input('-2.50')    # { adjust,  -250 }
        parse-assign-input('(5)')      # { set,     -500 }  see the Pod
        parse-assign-input('=450')     # { fund-to, 45000 }
        parse-assign-input('=')        # { fund-target }
        parse-assign-input('twelve')   # Failure

    C<fund-target> carries no amount because this function has no
    context to resolve one from: it is handed a string and nothing
    else, which is what makes the whole sign rule testable without a
    screen. The dialog reads the envelope's target and turns it into a
    C<fund-to>, or refuses when there is none.

    Pure, and exported for exactly that reason: the sign rule is the
    one piece of the assign dialog with real semantics in it. )
our sub parse-assign-input(Str $text --> Hash) {
    my Str $s = ($text // '').trim;
    return fail 'Enter an amount' if $s eq '';

    # `=` first: it is the only prefix whose payload may be empty, and
    # the only one that does not fold into the +/- sign rule below.
    if $s.starts-with('=') {
        my Str $rest = $s.substr(1).trim;
        return %( mode => 'fund-target' ) if $rest eq '';

        my $to = parse-pence($rest);
        if $to ~~ Failure {
            my Str $msg = $to.exception.message;
            $to.so;
            return fail $msg;
        }
        # '=-5' and '=(5)' both land here. "Fund to minus five pounds"
        # is not a thing anyone means; taking money out is '-5', which
        # the sign rule below already reads.
        return fail "Cannot fund to a negative amount — use '-"
                    ~ format-pence($to.abs, :!symbol) ~ "' to take money out"
            if $to < 0;
        return %( mode => 'fund-to', amount => $to );
    }

    my Str $mode = 'set';
    my Int $sign = 1;
    if $s.starts-with('+') {
        $mode = 'adjust';
        $s = $s.substr(1).trim;
    } elsif $s.starts-with('-') {
        $mode = 'adjust';
        $sign = -1;
        $s = $s.substr(1).trim;
    }
    return fail 'Enter an amount after the sign' if $s eq '';

    my $pence = parse-pence($s);
    if $pence ~~ Failure {
        # Defuse before re-failing with our own wording: an undefused
        # Failure re-throws when it is next sunk, which in a TUI means
        # a crash some frames later pointing at innocent code.
        my Str $msg = $pence.exception.message;
        $pence.so;
        return fail $msg;
    }
    # A '-' in front of an accountant negative is a contradiction, and
    # parse-pence has already refused it for the 'set' shape; refuse it
    # here too rather than quietly making '-(5)' mean +£5.
    return fail "Malformed money value '$text'" if $mode eq 'adjust' && $pence < 0;

    %( :$mode, amount => $sign * $pence );
}

#|( The assign dialog: one amount field, prefilled with what this
    envelope already has this period.

    The field understands four shapes, and only two of them need
    anything the parser cannot see. C<=n> is about the envelope's
    B<available>, not its assigned, so it is an adjustment by the
    difference. A bare C<=> is about the envelope's B<plan>, which is
    not the same thing at all: only under C<refill> is the gap
    C<target − available>, and under a set-aside or a goal that
    identity is simply false. So the submit tap resolves C<=> through
    C<Service::Target.target-ask> — the one function every target
    feature in the app keys on — and emits the ask itself as the
    adjustment.

    Both resolutions happen before the supply emits, which keeps the
    "no target" refusal inside the still-open dialog where the user can
    act on it. )
our sub open-assign($main) {
    my $category = selected-envelope($main, 'assign to');
    return without $category;

    my Str $period = $main.viewed-period;
    my Int $id  = $category.id;
    my $row     = period-row($main, $id);
    my Int $current = $row.defined ?? $row.assigned !! 0;
    # An envelope the period has never heard of has no row at all, and
    # zero is exactly what its available is.
    my Int $available = $row.defined ?? $row.available.Int !! 0;
    my Int $target = ($category.target-pence // 0).Int;
    # What a bare `=` is worth here, and what it would land the envelope
    # on: both read live off the view, both zero when there is no target
    # or no derivation yet.
    my $view = $main.view;
    my $scheme = $main.workspace.scheme;
    my Int $ask = $view.defined
        ?? target-ask($view, $scheme, $category, $period) !! 0;
    my Int $milestone = $view.defined
        ?? target-milestone($view, $scheme, $category, $period) !! 0;
    my %styles  = modal-styles(theme => $main.theme);

    my $modal = Selkie::Widget::Modal.new(
        width-ratio        => 0.5,
        height-ratio       => 0.35,
        backdrop           => BackdropScrim,
        framed             => True,
        frame-style        => BorderRounded,
        frame-title        => 'Assign · ' ~ $category.name
                              ~ ' · ' ~ $main.workspace.scheme.label($period),
        frame-bottom-title => 'enter save · esc cancel · +n/-n · =n/=',
    );

    my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);
    # No currency symbol in the field: it is there to be overtyped, and
    # a symbol the user has to type back is friction. parse-pence
    # accepts one anyway if they do.
    my ($field, $input) = labelled-input(
        'Amount', format-pence($current, :!symbol), %styles<label>,
        placeholder => 'e.g. 400 · +25 · =450 · = (target)',
    );
    $content.add($field);

    my $error = Selkie::Widget::Text.new(
        text => '', sizing => Sizing.flex, style => %styles<error>,
    );
    $content.add($error);
    $modal.set-content($content);

    # Validate before the supply emits — with-modal closes on emit, and
    # a dialog that vanishes on a typo has thrown the typo away too.
    my $submit = Supplier.new;
    my sub refuse(Str:D $msg --> Nil) {
        $error.set-text($msg);
        toast($main, $msg);
        Nil
    }
    $input.on-submit.tap: -> Str $text {
        my $parsed = parse-assign-input($text);
        if $parsed ~~ Failure {
            my Str $msg = $parsed.exception.message;
            $parsed.so;
            refuse($msg);
        } elsif $parsed<mode> eq 'fund-target' && $target <= 0 {
            # Two different "no target"s: one the user can fix, and one
            # the engine will never let them. "Edit the envelope to add
            # one" pointed at a dialog with no Target field in it would
            # be advice that cannot be taken.
            refuse($category.is-system
                ?? 'This envelope belongs to the engine and has no target — '
                   ~ 'type a figure instead'
                !! 'No target set — edit the envelope to add one');
        } elsif $parsed<mode> eq 'fund-target' {
            # The ask, as an adjustment — not a fund-to. `fund-to`
            # computes its own delta as `amount − available`, which is
            # the right sum for a refill and the wrong one for the two
            # kinds whose gap is measured against something else.
            $submit.emit(%( mode => 'fund-target', amount => $ask,
                            milestone => $milestone ));
        } else {
            $submit.emit($parsed);
        }
    };

    my $ws = $main.workspace;
    $main.with-modal($submit.Supply, $modal, $input,
        body => -> %parsed {
            my Int $amount = %parsed<amount>;
            given %parsed<mode> {
                when 'adjust' {
                    mutate($main, -> { $ws.assignments.adjust($period, $id, $amount) });
                    toast($main, 'Adjusted ' ~ $category.name ~ ' by '
                                 ~ format-pence($amount, :plus));
                }
                when 'fund-target' {
                    # Already emitted as the adjustment, so there is no
                    # difference to compute: this period's plan costs
                    # exactly this. Zero takes the same no-write path a
                    # zero-delta fund-to does, and for the same reason —
                    # an upsert of nothing still bumps ws/rev and
                    # re-derives the whole budget.
                    if $amount == 0 {
                        toast($main, $category.name
                                     ~ ' is already funded to its target '
                                     ~ 'this period');
                    } else {
                        mutate($main, -> { $ws.assignments.adjust($period, $id, $amount) });
                        toast($main, 'Funded ' ~ $category.name ~ ' '
                                     ~ format-pence($amount, :plus)
                                     ~ ' (target '
                                     ~ format-pence(%parsed<milestone> // 0)
                                     ~ ')');
                    }
                }
                when 'fund-to' {
                    # Funding TO a figure is an adjustment by the
                    # difference, not a set: `assigned` and `available`
                    # differ by carry-in, activity and the derivation's
                    # own moves, so setting assigned to the target
                    # would land the available somewhere else entirely.
                    my Int $delta = $amount - $available;
                    if $delta == 0 {
                        # A zero-delta upsert is still a write: it would
                        # bump ws/rev, re-derive the whole budget and
                        # repaint every subscription to say nothing had
                        # changed.
                        toast($main, $category.name ~ ' is already at '
                                     ~ format-pence($amount));
                    } else {
                        mutate($main, -> { $ws.assignments.adjust($period, $id, $delta) });
                        toast($main, 'Funded ' ~ $category.name ~ ' to '
                                     ~ format-pence($amount) ~ ' ('
                                     ~ format-pence($delta, :plus) ~ ')');
                    }
                }
                default {
                    mutate($main, -> { $ws.set-assigned($period, $id, $amount) });
                    toast($main, 'Assigned ' ~ format-pence($amount)
                                 ~ ' to ' ~ $category.name);
                }
            }
        },
    );
}

# --- Fund all ---------------------------------------------------------

#|( Every envelope C<f> would fund this period, in grid order.

    Four filters, each of them a ruling rather than a convenience:
    standard envelopes only (a payment envelope's figure is the card's
    balance, and Ready to Assign is not an envelope); a target above
    zero (zero is "no target", not "target nothing"); not hidden (a
    retired envelope is not part of this period's plan, and funding one
    behind the C<u> filter would move money the user cannot see); and
    underfunded, because fund-all only ever B<adds>.

    "Underfunded" is C<Service::Target.target-ask> and nothing else, so
    C<f> funds each envelope's B<plan for this period> whatever kind of
    plan it is: a refill to its level, a set-aside's contribution, a
    goal's next milestone. That is the whole of what adding target kinds
    did to this function.

    Each entry is C<< { id, name, target, available, delta } >> with
    C<delta> the positive amount to add and C<target> the milestone it
    lands on — the period's figure, not a C<by_period> goal's total. )
our sub fund-all-candidates($main --> List) {
    my Str $period = $main.viewed-period;
    my $view = $main.view;
    # No view is no answer: `target-ask` is a question about a derived
    # budget, and the frames before the first recompute have none. `f`
    # in one of them finds nothing to fund, which is the truth as far
    # as this process knows it.
    return () without $view;
    my $scheme = $main.workspace.scheme;

    my @envelopes = $main.categories
        .grep({ .defined && .is-standard && !.hidden && .has-target })
        .sort({ ($_.sort-order // 0, $_.id // 0) });

    my @out;
    for @envelopes -> $c {
        my $row = period-row($main, $c.id);
        my Int $available = $row.defined ?? $row.available.Int !! 0;
        # The kind-aware gap, and the only place `f` decides anything
        # about targets: refill measures available, set-aside measures
        # this period's assignments, and a goal measures its milestone.
        my Int $delta = target-ask($view, $scheme, $c, $period);
        next unless $delta > 0;
        # What this period wants, not the end goal: a line reading
        # "(to £50,000.00)" beside "+£555.55" describes a different
        # sum from the one about to be written.
        @out.push(%(
            id => ($c.id // 0).Int, name => $c.name,
            target => target-milestone($view, $scheme, $c, $period),
            :$available, :$delta,
        ));
    }
    @out.List;
}

#|( C<f> on the envelope grid: fund every underfunded envelope to its
    target, for the period on screen, in one write.

    Three decisions worth stating.

    B<Nothing to do is a toast, not a dialog.> A confirm listing
    nothing, over a budget that is already on plan, is a dialog whose
    only possible answer is "yes, do nothing".

    B<Overspending Ready to Assign is allowed, loudly.> The modal says
    what RTA will be afterwards and, when that is negative, says so in
    the palette's red and in words — and then lets the user confirm
    anyway. Assigning money you have not got is a real thing to do on
    the way to a plan (you are about to be paid, or you are about to
    move money back out of something else), and the app's job is to be
    unmistakably clear about it, not to forbid it. The Ready-to-Assign
    pill goes red for exactly as long as it stays true.

    B<One closure, one recompute.> The confirm dispatches a single
    C<ws/mutate> whose action loops over every candidate. Twenty
    dispatches would be twenty full derivations of the budget, each
    discarding the last, and — worse — twenty chances to stop halfway
    with the period half funded. )
our sub open-fund-all($main) {
    my Str $period = $main.viewed-period;
    my @candidates = fund-all-candidates($main);

    unless @candidates.elems {
        toast($main, 'All targets funded — nothing to do this period');
        return;
    }

    my Int $total = @candidates.map({ $_<delta> }).sum.Int;
    my $view = $main.view;
    my Int $rta = $view.defined ?? $view.rta($period).Int !! 0;
    my Int $after = $rta - $total;

    my %styles = modal-styles(theme => $main.theme);
    my $modal = Selkie::Widget::Modal.new(
        width-ratio        => 0.6,
        height-ratio       => 0.6,
        backdrop           => BackdropScrim,
        framed             => True,
        frame-style        => BorderRounded,
        frame-title        => 'Fund targets · '
                              ~ $main.workspace.scheme.label($period),
        frame-bottom-title => 'enter/^s fund · esc cancel',
    );

    my $body = Selkie::Widget::RichText.new(sizing => Sizing.flex);
    $body.set-content(fund-all-spans(
        @candidates, :$total, :$rta, :$after, theme => $main.theme,
        icons => $main.icons,
    ));
    $modal.set-content($body);

    # Nothing here is typed, so there is no validation to do before the
    # supply emits and no error line to paint: both keys emit straight
    # away. Ctrl+S as well as Enter, because every other dialog in the
    # app takes it and a keyboard app should not make the user
    # remember which.
    my $submit = Supplier.new;
    $modal.on-key: 'enter', -> $ { $submit.emit(True) },
        :description('Fund every listed envelope');
    $modal.on-key: 'ctrl+s', -> $ { $submit.emit(True) },
        :description('Fund every listed envelope');

    my $ws = $main.workspace;
    $main.with-modal($submit.Supply, $modal, $modal,
        body => -> $ {
            mutate($main, -> {
                my $result;
                for @candidates -> %c {
                    $result = $ws.assignments.adjust($period, %c<id>, %c<delta>);
                    # The first refusal stops the run and is what the
                    # effect toasts, exactly as a single-envelope
                    # assign would. Carrying on past one would leave
                    # the period half funded with a success toast over
                    # it.
                    last if $result ~~ Failure;
                }
                $result;
            });
            toast($main, 'Funded ' ~ @candidates.elems
                         ~ (@candidates.elems == 1 ?? ' envelope' !! ' envelopes')
                         ~ ' · ' ~ format-pence($total));
        },
    );
}

#|( The fund-all confirm's body: one line per envelope, a total, and
    what Ready to Assign will be when it is done.

    Pure, and separate from C<open-fund-all>, so the copy that has to
    be right — most of all the overspend warning — can be asserted
    without a terminal. )
our sub fund-all-spans(
    @candidates,
    Int:D :$total!,
    Int:D :$rta!,
    Int:D :$after!,
    App::Moneymoor::Theme :$theme!,
    :$icons = icons(),
    --> List
) {
    my %styles = modal-styles(:$theme);
    my $green = Selkie::Style.new(fg => $theme.fg-green);
    my @spans;
    my sub line(Str:D $text, $style --> Nil) {
        @spans.push(Selkie::Widget::RichText::Span.new(:$text, :$style));
        Nil
    }

    line("Fund { @candidates.elems } envelope"
         ~ (@candidates.elems == 1 ?? '' !! 's') ~ " to target:\n\n",
         %styles<label>);

    # Names are not padded to a column: an envelope name can be as long
    # as the user likes, and a computed gutter that works for
    # "Groceries" reads as a bug beside "Christmas and Birthdays".
    for @candidates -> %c {
        line('  ' ~ %c<name> ~ '  ' ~ format-pence(%c<delta>, :plus)
             ~ "  (to " ~ format-pence(%c<target>) ~ ")\n", %styles<dim>);
    }

    line("\nTotal  " ~ format-pence($total) ~ "\n", %styles<label>);
    line('Ready to Assign  ' ~ format-pence($rta) ~ '  '
         ~ $icons.move ~ '  ' ~ format-pence($after) ~ "\n",
         $after < 0 ?? %styles<error> !! $green);

    if $after < 0 {
        line("\n" ~ $icons.warn ~ ' This overspends Ready to Assign by '
             ~ format-pence($after.abs)
             ~ ' — you can still do it, but that money is not there yet.'
             ~ "\n", %styles<error>);
    }
    @spans.List;
}

# --- Move money -------------------------------------------------------

#| Move money between envelopes: a static "from", a picker for the
#| "to", and an amount.
our sub open-move-money($main) {
    my $from = selected-envelope($main, 'move money from');
    return without $from;

    my Str $period = $main.viewed-period;
    my Int $from-id = $from.id;
    my %styles = modal-styles(theme => $main.theme);

    my @options = envelope-options(
        categories => $main.categories,
        groups     => $main.groups,
        exclude-id => $from-id,
        include-hidden => ($main.store.get-in('budget', 'show-hidden') // False).Bool,
    );
    unless @options.elems {
        toast($main, 'There is nowhere to move it to — create another envelope first');
        return;
    }

    my $row = period-row($main, $from-id);
    my Int $available = $row.defined ?? $row.available !! 0;

    my $modal = Selkie::Widget::Modal.new(
        width-ratio        => 0.6,
        height-ratio       => 0.5,
        backdrop           => BackdropScrim,
        framed             => True,
        frame-style        => BorderRounded,
        frame-title        => 'Move money · '
                              ~ $main.workspace.scheme.label($period),
        frame-bottom-title => 'tab move · enter save · esc cancel',
    );

    my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);
    $content.add(static-field('From',
        $from.name ~ '  (' ~ format-pence($available) ~ ' available)', %styles));

    $content.add: Selkie::Widget::Text.new(
        text => 'To', sizing => Sizing.fixed(1), style => %styles<label>,
    );
    my $target = Selkie::Widget::Select.new(sizing => Sizing.fixed(1));
    $target.set-items(@options.map(*.key).List);
    $content.add($target);

    my ($amount-field, $amount-input) = labelled-input(
        'Amount', '', %styles<label>, placeholder => 'e.g. 25.00',
    );
    $content.add($amount-field);

    my $error = Selkie::Widget::Text.new(
        text => '', sizing => Sizing.flex, style => %styles<error>,
    );
    $content.add($error);
    $modal.set-content($content);

    my @ids = @options.map(*.value).List;
    my $submit = Supplier.new;
    my sub try-submit(Str $text) {
        my $pence = parse-pence(($text // '').trim);
        if $pence ~~ Failure {
            my Str $msg = $pence.exception.message;
            $pence.so;
            $error.set-text($msg);
        } elsif $pence <= 0 {
            # The engine refuses zero and would read a negative as a
            # move in the other direction, which is not what a form
            # with a "from" and a "to" on it means.
            $error.set-text('Enter a positive amount');
        } else {
            $submit.emit(%( to => @ids[$target.selected], amount => $pence ));
        }
    }
    $amount-input.on-submit.tap: -> Str $text { try-submit($text) };
    # Enter inside the Select opens its dropdown, so the dialog needs a
    # submit key that works from any field.
    $modal.on-key: 'ctrl+s', -> $ { try-submit($amount-input.text) },
        :description('Move the money');

    my $ws = $main.workspace;
    $main.with-modal($submit.Supply, $modal, $target,
        body => -> %f {
            my Int $to = %f<to>;
            my Int $amount = %f<amount>;
            mutate($main, -> { $ws.move-money($period, $from-id, $to, $amount) });
            my $dest = $main.category($to);
            toast($main, 'Moved ' ~ format-pence($amount) ~ ' to '
                         ~ ($dest.defined ?? $dest.name !! 'the other envelope'));
        },
    );
}

# --- Explain ----------------------------------------------------------

#| Read-only: the Rule-1 equation for the selected envelope, then every
#| move the derivation made through it this period, in words.
our sub open-explain($main) {
    my $category = selected-envelope($main, 'explain');
    return without $category;

    my Str $period = $main.viewed-period;
    my $modal = Selkie::Widget::Modal.new(
        width-ratio        => 0.7,
        height-ratio       => 0.6,
        backdrop           => BackdropScrim,
        framed             => True,
        frame-style        => BorderRounded,
        frame-title        => 'Explain · ' ~ $category.name
                              ~ ' · ' ~ $main.workspace.scheme.label($period),
        frame-bottom-title => 'esc close',
    );

    my $body = Selkie::Widget::RichText.new(sizing => Sizing.flex);
    $body.set-content(explain-spans(
        $main.view, $period, $category.id,
        theme => $main.theme,
        names => $main.categories.map({ .id => $_ }).Hash,
        width => EXPLAIN-COLS,
        icons => $main.icons,
    ));
    $modal.set-content($body);

    # Read-only, so the supply never emits and Esc — bound by
    # with-modal — is the only way out.
    $main.with-modal(Supplier.new.Supply, $modal, $modal, body => -> $ { });
}

# --- Category editor --------------------------------------------------

#|( New envelope (no C<:category-id>) or edit an existing one.

    A system row — a card's payment envelope, or Ready to Assign — gets
    its name and group as static text, and neither the carry toggle nor
    any target UI at all: C<Gateway::Category.update> permits only the
    sort order and the hidden flag on those, so an editable field would
    be a promise the engine breaks.

    =head3 Carry overspending

    One C<Checkbox>, and the only control on this dialog that changes
    what the B<engine> does with the row. Unchecked (the default, and
    what every existing envelope reads as) puts it on rule 3's forcing
    rule: overspend it in cash and it resets to zero at the period
    boundary with Ready to Assign charged for the hole. Checked carries
    the negative forward instead, exactly as a payment envelope's does,
    and charges nothing — which is what you want for the envelope you
    deliberately run negative, like a reimbursable expense.

    It sits above the target block rather than inside it because it is
    not a target: it is a property of the envelope, like its name and
    its group, and the three target rows below it come and go with the
    Kind picker. It is offered only on a standard envelope, for the same
    reason the target fields are — see
    L<App::Moneymoor::Service::Budget>'s rule 3 for what it means, and
    L<App::Moneymoor::Model::Category> for why the default is off.

    =head3 The Kind picker, and the rows that follow it

    A target has three kinds and they do not want the same information:
    a refill and a set-aside are an amount, a goal is an amount plus a
    period plus how often it comes round. So C<Kind> is a C<Select> and
    the two extra fields are mounted B<only> under C<Goal by period>,
    through the same swap-container pattern the budget-period picker
    uses (see C<open-period-picker>): a dedicated fixed C<VBox>,
    remembered text in lexicals outside the widgets, type-object slots
    for the inputs that are not on the dialog, and a C<refresh> that
    saves back, clears, rebuilds, re-declares its height, re-wires
    Enter and marks the screen dirty. A field that takes a keystroke
    and then has it discarded on save is the bug that pattern exists to
    prevent.

    The C<Target> amount is B<not> in the swap container: every kind
    reads it, so it is an ordinary field that never moves. Blank still
    clears the target — and clearing it forces the kind back to
    C<refill> on save, because "no target" has exactly one shape and
    the gateway refuses a set-aside or a goal of nothing.

    =head3 Saving without clearing what it did not touch

    C<Gateway::Category.update> writes the B<whole> row, target tuple
    included, and this dialog builds a fresh C<Model::Category> out of
    its own fields — which is exactly the shape that silently wipes a
    target on a rename. Two halves, therefore:

    =item the C<update> carries B<the row's existing target tuple>,
       every one of the five columns, unchanged. Renaming an envelope
       writes its target back exactly as it found it, and the editor
       cannot clear a plan it was not asked to change. The carry flag
       is not in that group: this dialog B<renders> it, so it carries
       what the checkbox says rather than what the row said.
    =item the target itself goes through C<Service::Workspace.set-target>
       and only when it actually changed. That is the front door that
       stamps C<target_start>, so a goal re-ramps from today when its
       amount or its goal period moves and keeps its stamp when only
       the repeat does. Nothing else in the app may write that column,
       and this dialog does not.

    A new envelope is created with no target at all and then given one
    through the same front door, so the stamp is right on the first
    save rather than on the second. )
our sub open-category-editor($main, Int :$category-id) {
    my $existing = $category-id.defined ?? $main.category($category-id) !! Nil;
    if $category-id.defined && !$existing.defined {
        toast($main, 'That envelope no longer exists');
        return;
    }
    my Bool $is-system = $existing.defined && $existing.is-system;

    my $app     = $main.app;
    my %styles  = modal-styles(theme => $main.theme);
    my @groups  = $main.groups.sort({ ($_.sort-order // 0, $_.id // 0) });
    my @group-ids = (Int, |@groups.map({ $_.id }));
    my @group-labels = ('(none)', |@groups.map({ $_.name }));

    my $modal = Selkie::Widget::Modal.new(
        width-ratio        => 0.6,
        # Measured against the terminal this app is built to fit. On 24
        # rows a 0.9 modal has seventeen interior rows, and the form's
        # widest shape claims fifteen of them outright: Name 2, the
        # Group caption and its Select 2, Sort order 2, Carry
        # overspending 1, the Kind caption and its Select 2, Target 2,
        # and — under `Goal by period` only — Goal period 2 and Repeat
        # 2. The two that are left go to the flex error line, which
        # needs both for a wrapped refusal.
        #
        # It was 0.6 while the form ended at Target, which is ten rows,
        # and 0.85 while that was fourteen. A form whose last field is
        # under the frame is a form nobody fills in, and the goal fields
        # are exactly the ones a user is least likely to guess at.
        height-ratio       => 0.9,
        backdrop           => BackdropScrim,
        framed             => True,
        frame-style        => BorderRounded,
        frame-title        => $existing.defined
                                ?? 'Edit envelope · ' ~ $existing.name
                                !! 'New envelope',
        frame-bottom-title => ($existing.defined && !$is-system)
            ?? 'enter/^s save · ^d delete · esc cancel'
            !! 'enter/^s save · esc cancel',
    );

    my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);

    my $name-input;
    my $group-select;
    if $is-system {
        $content.add(static-field('Name', $existing.name, %styles));
        my $g = $existing.group-id.defined ?? $main.group($existing.group-id) !! Nil;
        $content.add(static-field('Group',
            ($g.defined ?? $g.name !! '(none)'), %styles));
        $content.add: Selkie::Widget::Text.new(
            text   => 'This envelope belongs to the engine — only its order '
                      ~ 'can be changed.',
            sizing => Sizing.fixed(1), style => %styles<hint>,
        );
    } else {
        my ($name-field, $ni) = labelled-input(
            'Name', ($existing.defined ?? $existing.name !! ''),
            %styles<label>, placeholder => 'Required',
        );
        $name-input = $ni;
        $content.add($name-field);

        $content.add: Selkie::Widget::Text.new(
            text => 'Group', sizing => Sizing.fixed(1), style => %styles<label>,
        );
        $group-select = Selkie::Widget::Select.new(sizing => Sizing.fixed(1));
        $group-select.set-items(@group-labels.List);
        my $current-group = $existing.defined ?? $existing.group-id !! Int;
        my $gidx = @group-ids.first(
            { ($_ // -1) == ($current-group // -1) }, :k) // 0;
        $group-select.select-index($gidx.UInt);
        $content.add($group-select);
    }

    my ($order-field, $order-input) = labelled-input(
        'Sort order', ($existing.defined ?? $existing.sort-order.Str !! '0'),
        %styles<label>, placeholder => 'lower sorts first',
    );
    $content.add($order-field);

    # The one control here that changes what the derivation does — see
    # "Carry overspending". A Checkbox rather than a Select because it
    # is one bit, and it carries its own label, so it costs a single row
    # of a dialog that has none to spare. Undefined on a system row,
    # where the flag is refused by the gateway; `save-now` reads it
    # through a guard for exactly that case.
    my $carry-check;
    unless $is-system {
        $carry-check = Selkie::Widget::Checkbox.new(
            label  => 'Carry overspending',
            sizing => Sizing.fixed(1),
        );
        $carry-check.set-checked(
            ?($existing.defined && $existing.carry-overspend));
        $content.add($carry-check);
    }

    # Targets are a standard-envelope idea, and the gateway refuses one
    # on a system row — so none of the target UI is offered there, for
    # the same reason the name is static text.
    my $kind-select;
    my $target-input;
    # The goal fields' container: mounted always, empty except under
    # `Goal by period`. Zero-height rather than absent, so nothing below
    # it moves when the kind changes.
    my $goal-fields = Selkie::Layout::VBox.new(sizing => Sizing.fixed(0));
    unless $is-system {
        $content.add: Selkie::Widget::Text.new(
            text => 'Kind', sizing => Sizing.fixed(1), style => %styles<label>,
        );
        $kind-select = Selkie::Widget::Select.new(sizing => Sizing.fixed(1));
        $kind-select.set-items(TARGET-KIND-LABELS.List);
        # A target-less envelope preselects Refill: that is what the
        # column defaults to and what a row that never had a target
        # means. `has-target` first, because `is-refill` and friends
        # read the kind alone.
        $kind-select.select-index(
            ($existing.defined && $existing.has-target
                ?? (TARGET-KIND-VALUES.first(
                        { $_ eq ($existing.target-kind // 'refill') }, :k) // 0)
                !! 0).UInt);
        $content.add($kind-select);

        # Symbol-less prefill, like the assign dialog's: it is there to
        # be overtyped. Blank rather than '0' when there is no target,
        # because a field reading 0 looks like a target of nothing.
        my Str $initial = ($existing.defined && $existing.has-target)
            ?? format-pence($existing.target-pence, :!symbol) !! '';
        my ($target-field, $ti) = labelled-input(
            'Target', $initial, %styles<label>,
            placeholder => 'blank for none · e.g. 400',
        );
        $target-input = $ti;
        $content.add($target-field);
        $content.add($goal-fields);
    }

    my $error = Selkie::Widget::Text.new(
        text => '', sizing => Sizing.flex, style => %styles<error>,
    );
    $content.add($error);
    $modal.set-content($content);

    # What the goal fields open on, and where what was typed in them
    # goes while another kind is selected and the rows are not in the
    # tree. The goal date is prefilled from the row's own — the date the
    # user chose, not the period it resolves to, because that is what
    # they would recognise coming back.
    my Str $goal-text = ($existing.defined && $existing.is-by-period
        && ($existing.target-period // '') ne '')
            ?? $existing.target-period !! '';
    my Str $repeat-text = ($existing.defined && $existing.is-by-period
        && ($existing.target-repeat // 0) > 0)
            ?? $existing.target-repeat.Str !! '';

    # Undefined is the honest value for an input that is genuinely not
    # on the dialog. `field-text` guards it, and `enter-saves` skips it
    # by contract.
    my Selkie::Widget::TextInput $goal-input;
    my Selkie::Widget::TextInput $repeat-input;
    my Bool $goal-shown = False;

    my sub field-text($input --> Str) {
        $input.defined ?? ($input.text // '') !! '';
    }

    my $submit = Supplier.new;
    my sub save-now(--> Nil) {
        my Str $name = $is-system
            ?? $existing.name !! ($name-input.text // '').trim;
        my Int $order = parse-sort-order($order-input.text);

        # Defused here rather than inside the branch that reports it: a
        # Failure left sitting in a lexical because the name was empty
        # too would re-throw the next time anything sank it, frames
        # later and nowhere near this dialog.
        my $parsed-target = $is-system
            ?? ($existing.target-pence // 0).Int
            !! parse-target($target-input.text);
        my Str $target-error = '';
        my Int $target = 0;
        if $parsed-target ~~ Failure {
            $target-error = $parsed-target.exception.message;
            $parsed-target.so;
        } else {
            $target = $parsed-target.Int;
        }

        # Blank clears the target, and "no target" has exactly one
        # shape: a refill of nothing, with no goal and no repeat. The
        # gateway refuses any other reading of zero, so this resolves it
        # here rather than letting the form's unused fields travel.
        my Str $kind = ($is-system || $target == 0)
            ?? 'refill'
            !! TARGET-KIND-VALUES[$kind-select.selected];
        my Str $goal = $kind eq 'by_period'
            ?? field-text($goal-input).trim !! '';
        my $repeat = $kind eq 'by_period'
            ?? parse-repeat(field-text($repeat-input)) !! 0;

        if $name eq '' {
            $error.set-text('An envelope needs a name');
        } elsif !$order.defined {
            $error.set-text('Sort order must be a whole number');
        } elsif $target-error ne '' {
            $error.set-text($target-error);
        } elsif $kind eq 'by_period' && !valid-date($goal) {
            $error.set-text('A goal needs a date like 2026-11-07 — any day '
                            ~ 'in the period the bill is paid in');
        } elsif !$repeat.defined {
            $error.set-text('Repeat must be a whole number of periods — '
                            ~ 'leave it blank for a one-off goal');
        } else {
            $submit.emit(%(
                :$name, sort-order => $order, target-pence => $target,
                target-kind => $kind, target-repeat => $repeat.Int,
                target-period => ($goal eq '' ?? Str !! $goal),
                # A system row has no checkbox, and its stored flag is
                # False by construction (the gateway has never let one
                # be set) — so reading the row back is both the honest
                # value and the one `update` will accept unchanged.
                carry-overspend => ($carry-check.defined
                    ?? $carry-check.checked
                    !! ?($existing.defined && $existing.carry-overspend)),
                group-id => ($is-system
                    ?? $existing.group-id
                    !! @group-ids[$group-select.selected]),
            ));
        }
        Nil
    }

    #|( Mount the rows the selected kind reads, and nothing else — the
        budget-period picker's C<refresh-fields>, on this dialog's two
        fields. Every step there is load-bearing here for the same
        reasons: save back before destroying, rebuild rather than hide
        (C<Container.clear> destroys its children, so a row that comes
        back is a new row opening on the remembered text), re-declare
        the height, and re-wire Enter to inputs that did not exist a
        moment ago.

        Focus is never inside a row this destroys: the only caller is
        the C<Select>'s C<on-change>, which holds focus in every route
        to it, plus the explicit call below that runs before the modal
        is shown at all. )
    my sub refresh-goal-fields(Bool:D $wanted --> Nil) {
        if $goal-shown {
            $goal-text   = field-text($goal-input).trim;
            $repeat-text = field-text($repeat-input).trim;
        }
        $goal-shown = $wanted;

        $goal-fields.clear;
        $goal-input   = Selkie::Widget::TextInput;
        $repeat-input = Selkie::Widget::TextInput;

        if $wanted {
            my ($goal-row, $gi) = labelled-input(
                'Goal period', $goal-text, %styles<label>,
                # The guidance the ruling asks for, in the one place it
                # costs no rows: a goal targets the period its bill is
                # PAID in, and the date is read as "the period
                # containing it".
                placeholder => 'YYYY-MM-DD · when the bill is paid',
            );
            $goal-input = $gi;
            $goal-fields.add($goal-row);

            my ($repeat-row, $ri) = labelled-input(
                'Repeat', $repeat-text, %styles<label>,
                placeholder => 'blank for once · e.g. 3 periods',
            );
            $repeat-input = $ri;
            $goal-fields.add($repeat-row);
        }

        # Asked of the rows rather than hard-coded, so a change to how
        # tall a labelled field is stays a change in one place.
        $goal-fields.update-sizing(Sizing.fixed(
            $goal-fields.children.map(*.sizing.value).sum.Int));
        enter-saves(&save-now, $goal-input, $repeat-input);
        # Everything below the container has just moved, and the rows
        # that went away took their planes with them. A kind change is a
        # keypress-rare event, so the whole-tree repaint is the cheap and
        # certain answer.
        $content.mark-screen-dirty;
        Nil
    }

    if $kind-select.defined {
        # Registered before the explicit call, so one handler covers
        # both — and called explicitly, because `select-index` only
        # emits when it actually moves the selection and Refill (which
        # every target-less envelope preselects) is index 0.
        $kind-select.on-change.tap: -> $idx {
            refresh-goal-fields($idx.Int == KIND-BY-PERIOD);
        };
        refresh-goal-fields($kind-select.selected.Int == KIND-BY-PERIOD);
    }

    $modal.on-key: 'ctrl+s', -> $ { save-now() }, :description('Save');
    enter-saves(&save-now, $name-input, $order-input, $target-input);

    if $existing.defined && !$is-system {
        $modal.on-key: 'ctrl+d',
            -> $ {
                # Close first rather than stacking: the confirm is
                # about the thing the editor is editing, and two
                # dialogs deep is one too many to reason about.
                $app.close-modal if $app.defined;
                confirm-delete-category($main, $existing);
            },
            :description('Delete this envelope');
    }

    my $ws = $main.workspace;
    $main.with-modal($submit.Supply, $modal,
                     ($is-system ?? $order-input !! $name-input),
        body => -> %f {
            if $existing.defined {
                # The target tuple is carried through EXACTLY as the row
                # holds it — all five columns — because `update` writes
                # the whole row and a fresh model built from this form
                # would otherwise clear whatever it did not carry. See
                # "Saving without clearing what it did not touch".
                my $updated = App::Moneymoor::Model::Category.new(
                    id                 => $existing.id,
                    group-id           => %f<group-id>,
                    name               => %f<name>,
                    kind               => $existing.kind,
                    payment-account-id => $existing.payment-account-id,
                    sort-order         => %f<sort-order>,
                    hidden             => $existing.hidden,
                    carry-overspend    => %f<carry-overspend>,
                    target-pence       => $existing.target-pence,
                    target-kind        => $existing.target-kind,
                    target-period      => $existing.target-period,
                    target-start       => $existing.target-start,
                    target-repeat      => $existing.target-repeat,
                );
                # …and the target goes through the front door, and only
                # when it moved. Skipping the no-change case is not just
                # an optimisation: `set-target` is the one thing that
                # stamps a plan start, and a re-stamp on every rename
                # would restart the ramp of a goal nobody edited.
                my Bool $target-changed = target-differs($existing, %f);
                mutate($main, -> {
                    my $saved = $ws.categories.update($updated);
                    ($saved ~~ Failure || !$target-changed)
                        ?? $saved
                        !! $ws.set-target($existing.id,
                               kind   => %f<target-kind>,
                               pence  => %f<target-pence>,
                               period => %f<target-period>,
                               repeat => %f<target-repeat>);
                });
                toast($main, 'Saved ' ~ %f<name>);
            } else {
                # Created without a target and then given one, rather
                # than created with one: `create` cannot stamp a plan
                # start (only `Service::Workspace.set-target` may), so a
                # goal written straight into the insert would have no
                # schedule until its next save.
                my $fresh = App::Moneymoor::Model::Category.new(
                    group-id        => %f<group-id>,
                    name            => %f<name>,
                    sort-order      => %f<sort-order>,
                    carry-overspend => %f<carry-overspend>,
                );
                mutate($main, -> {
                    my $created = $ws.categories.create($fresh);
                    if $created ~~ Failure || %f<target-pence> <= 0 {
                        $created;
                    } else {
                        $ws.set-target($created.id,
                            kind   => %f<target-kind>,
                            pence  => %f<target-pence>,
                            period => %f<target-period>,
                            repeat => %f<target-repeat>);
                    }
                });
                toast($main, 'Created ' ~ %f<name>);
            }
        },
    );
}

#|( C<d> on the envelope table: confirm, then delete the envelope the
    cursor is on. The editor's C<ctrl+d> lands on the same confirm, so
    there is one delete path however you reach it.

    Only category rows: a group header is C<delete-group>'s business
    and the empty-state row is nobody's. C<Screen::Budget> dispatches on
    the row kind before it gets here, and C<selected-envelope> is the
    backstop for a stale selection. )
our sub delete-category($main) {
    my $category = selected-envelope($main, 'delete');
    return without $category;
    if $category.is-system {
        # The engine would refuse anyway; saying so without opening a
        # confirm the user cannot act on is the kinder version.
        toast($main, "\"{ $category.name }\" belongs to the engine and "
                     ~ 'cannot be deleted');
        return;
    }
    confirm-delete-category($main, $category);
}

#|( C<d> on a group header: confirm, then delete the group. Its
    envelopes survive as ungrouped rows — see C<confirm-delete-group>.

    Two rows here are not groups: the Ungrouped bucket is a display
    fiction with no row behind it, and the system "Credit Card Payments"
    group belongs to the engine. Both get a toast rather than a confirm
    that could only end in a refusal. )
our sub delete-group($main, Int :$group-id) {
    my $group = $group-id.defined ?? $main.group($group-id) !! Nil;
    unless $group.defined {
        toast($main, 'That is not a real group — it is where ungrouped '
                     ~ 'envelopes are shown');
        return;
    }
    if $group.is-system {
        toast($main, "\"{ $group.name }\" belongs to the engine and cannot "
                     ~ 'be deleted');
        return;
    }
    confirm-delete-group($main, $group);
}

#|( Confirm, then delete. The engine refuses any category with
    transactions categorized to it, or with money assigned in any period
    — past or future — and says so with a message pointing at C<hide>.
    That message reaches the user through C<ws/mutate>'s toast, which is
    why this does not try to pre-check. Pre-checking would mean a second
    copy of the rule, and the second copy is the one that goes stale.

    The copy says "period" rather than "month" because the gateway
    guard it is mirroring does: the engine's refusal names the
    "period(s) of non-zero assignments" it found, and a dialog that
    calls them months would be describing a different rule from the
    toast that follows it.

    Periods the user has zeroed out are B<not> history and do not block
    the delete; the copy says "money", not "history", because that is
    the rule the engine actually enforces. )
sub confirm-delete-category($main, $category --> Nil) {
    my $confirm = Selkie::Widget::ConfirmModal.new;
    my $modal = scrimmed($confirm.build(
        title     => 'Delete envelope?',
        message   => "Delete \"{ $category.name }\"? Transactions "
                     ~ 'categorized to it, or money assigned to it in any '
                     ~ 'period, block this — hide it instead, which keeps '
                     ~ 'the money and the past where they are.',
        yes-label => 'Delete',
        no-label  => 'Cancel',
    ));
    my $ws = $main.workspace;
    $main.with-modal($confirm.on-result, $modal, $confirm.no-button,
        body => -> Bool $yes {
            if $yes {
                mutate($main, -> { $ws.categories.delete($category.id) });
            }
        },
    );
    Nil
}

# --- Group editor -----------------------------------------------------

#| New group (no C<:group-id>) or edit an existing one. System groups —
#| "Credit Card Payments" is the only one — can be reordered but not
#| renamed or deleted, so they get the same static-field treatment
#| system categories do.
our sub open-group-editor($main, Int :$group-id) {
    my $existing = $group-id.defined ?? $main.group($group-id) !! Nil;
    if $group-id.defined && !$existing.defined {
        # The ungrouped bucket is a display fiction with no row behind
        # it, and its header is the one a user is most likely to press
        # `e` on by accident.
        toast($main, 'That is not a real group — it is where ungrouped '
                     ~ 'envelopes are shown');
        return;
    }
    my Bool $is-system = $existing.defined && $existing.is-system;

    my $app    = $main.app;
    my %styles = modal-styles(theme => $main.theme);

    my $modal = Selkie::Widget::Modal.new(
        width-ratio        => 0.55,
        height-ratio       => 0.4,
        backdrop           => BackdropScrim,
        framed             => True,
        frame-style        => BorderRounded,
        frame-title        => $existing.defined
                                ?? 'Edit group · ' ~ $existing.name
                                !! 'New group',
        frame-bottom-title => ($existing.defined && !$is-system)
            ?? 'enter/^s save · ^d delete · esc cancel'
            !! 'enter/^s save · esc cancel',
    );

    my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);
    my $name-input;
    if $is-system {
        $content.add(static-field('Name', $existing.name, %styles));
        $content.add: Selkie::Widget::Text.new(
            text   => 'This group belongs to the engine — only its order '
                      ~ 'can be changed.',
            sizing => Sizing.fixed(1), style => %styles<hint>,
        );
    } else {
        my ($name-field, $ni) = labelled-input(
            'Name', ($existing.defined ?? $existing.name !! ''),
            %styles<label>, placeholder => 'Required',
        );
        $name-input = $ni;
        $content.add($name-field);
    }

    my ($order-field, $order-input) = labelled-input(
        'Sort order', ($existing.defined ?? $existing.sort-order.Str !! '0'),
        %styles<label>, placeholder => 'lower sorts first',
    );
    $content.add($order-field);

    my $error = Selkie::Widget::Text.new(
        text => '', sizing => Sizing.flex, style => %styles<error>,
    );
    $content.add($error);
    $modal.set-content($content);

    my $submit = Supplier.new;
    my sub save-now(--> Nil) {
        my Str $name = $is-system
            ?? $existing.name !! ($name-input.text // '').trim;
        my Int $order = parse-sort-order($order-input.text);
        if $name eq '' {
            $error.set-text('A group needs a name');
        } elsif !$order.defined {
            $error.set-text('Sort order must be a whole number');
        } else {
            $submit.emit(%( :$name, sort-order => $order ));
        }
        Nil
    }
    $modal.on-key: 'ctrl+s', -> $ { save-now() }, :description('Save');
    enter-saves(&save-now, $name-input, $order-input);

    if $existing.defined && !$is-system {
        $modal.on-key: 'ctrl+d',
            -> $ {
                $app.close-modal if $app.defined;
                confirm-delete-group($main, $existing);
            },
            :description('Delete this group');
    }

    my $ws = $main.workspace;
    $main.with-modal($submit.Supply, $modal,
                     ($is-system ?? $order-input !! $name-input),
        body => -> %f {
            if $existing.defined {
                my $updated = App::Moneymoor::Model::CategoryGroup.new(
                    id         => $existing.id,
                    name       => %f<name>,
                    sort-order => %f<sort-order>,
                    hidden     => $existing.hidden,
                );
                mutate($main, -> { $ws.categories.update-group($updated) });
                toast($main, 'Saved ' ~ %f<name>);
            } else {
                my $fresh = App::Moneymoor::Model::CategoryGroup.new(
                    name => %f<name>, sort-order => %f<sort-order>,
                );
                mutate($main, -> { $ws.categories.create-group($fresh) });
                toast($main, 'Created ' ~ %f<name>);
            }
        },
    );
}

#| Deleting a group is the one destructive action here that cannot lose
#| anything: the foreign key is ON DELETE SET NULL, so the categories
#| survive as ungrouped rows. The copy says so, because "delete" on a
#| container reads as "and everything in it".
sub confirm-delete-group($main, $group --> Nil) {
    my $confirm = Selkie::Widget::ConfirmModal.new;
    my $modal = scrimmed($confirm.build(
        title     => 'Delete group?',
        message   => "Delete \"{ $group.name }\"? Its envelopes are kept — "
                     ~ 'they move to the Ungrouped section, with their money '
                     ~ 'and history intact.',
        yes-label => 'Delete',
        no-label  => 'Cancel',
    ));
    my $ws = $main.workspace;
    $main.with-modal($confirm.on-result, $modal, $confirm.no-button,
        body => -> Bool $yes {
            if $yes {
                mutate($main, -> { $ws.categories.delete-group($group.id) });
            }
        },
    );
    Nil
}

# --- Hide / unhide ----------------------------------------------------

#|( C<h> on the envelope table. Hiding an envelope that still holds
    money is allowed — the engine keeps its balance in the derivation
    either way, because pretending otherwise would break the master
    invariant — but it is worth saying out loud, so a non-zero
    Available gets a confirm whose message is informational rather than
    a warning.

    On an already-hidden row (visible only while C<u> is on), C<h> is
    the inverse and unhides without ceremony: nothing is at stake. )
our sub hide-category($main) {
    my $category = selected-envelope($main, 'hide');
    return without $category;

    my $ws = $main.workspace;
    my Int $id = $category.id;

    if $category.hidden {
        mutate($main, -> { $ws.categories.unhide($id) });
        toast($main, 'Showing ' ~ $category.name ~ ' again');
        return;
    }

    my $row = period-row($main, $id);
    my Int $available = $row.defined ?? $row.available !! 0;
    if $available == 0 {
        mutate($main, -> { $ws.categories.hide($id) });
        toast($main, 'Hid ' ~ $category.name ~ ' · u shows hidden envelopes');
        return;
    }

    my $confirm = Selkie::Widget::ConfirmModal.new;
    my $modal = scrimmed($confirm.build(
        title     => 'Hide envelope?',
        message   => "\"{ $category.name }\" has { format-pence($available) } "
                     ~ 'available. Hiding it only takes it off the list — the '
                     ~ 'money stays on the books until you move it somewhere '
                     ~ 'else.',
        yes-label => 'Hide',
        no-label  => 'Cancel',
    ));
    $main.with-modal($confirm.on-result, $modal, $confirm.no-button,
        body => -> Bool $yes {
            if $yes {
                mutate($main, -> { $ws.categories.hide($id) });
                toast($main, 'Hid ' ~ $category.name
                             ~ ' · u shows hidden envelopes');
            }
        },
    );
}

# ======================================================================
# The accounts tab's dialogs
# ======================================================================

# --- Pure helpers ------------------------------------------------------

#| The two directions, exactly as the RadioGroup lists them and as the
#| register's two money columns are headed.
our constant OUTFLOW-LABEL is export = 'Outflow';
our constant INFLOW-LABEL  is export = 'Inflow';

#| Rows the splits list is given. Four is enough to see a household
#| shop split three ways without pushing the status line off a 32-row
#| terminal; the list scrolls past that.
my constant SPLIT-ROWS = 4;

#|( Apply the direction to a magnitude. The form always types money as
    a positive figure — the way a statement prints it — and this is the
    single place that becomes a signed amount in the account's point of
    view.

        signed-amount(1250, 'Outflow');   # -1250
        signed-amount(1250, 'Inflow');    #  1250

    Anything that is not the inflow label reads as outflow, because a
    missing direction on a spending form is far more likely to be a
    purchase than a windfall. )
our sub signed-amount(Int:D $magnitude, Str $direction --> Int) {
    ($direction // '') eq INFLOW-LABEL ?? $magnitude !! -$magnitude;
}

#|( How much of C<$magnitude> the split entries have not accounted for.
    Zero is the only state the editor will save from.

        split-remainder(1250, (500, 250));   # 500
        split-remainder(1250, (1000, 250));  # 0
        split-remainder(1250, (2000,));      # -750, over-allocated

    Entries are magnitudes in the same direction as the transaction, so
    this is plain subtraction — the sign is applied once, on save. )
our sub split-remainder(Int:D $magnitude, @amounts --> Int) {
    $magnitude - ([+] @amounts.map({ ($_ // 0).Int }).Slip, 0);
}

#|( The ghost tail C<TextInput>'s C<suggest-provider> paints after the
    payee field: the rest of the first name that starts with what has
    been typed, case-insensitively.

        payee-suggest-tail(('Tesco', 'Tesco Express'), 'tes');   # 'co'
        payee-suggest-tail(('Tesco',), 'TESCO');                 # ''

    First in the list, not shortest or best: C<Gateway::Payee.find-all>
    answers in name order, so "Tesco" is offered before "Tesco Express"
    and the suggestion is stable between keystrokes. An exact match
    suggests nothing — there is no tail to accept. )
our sub payee-suggest-tail(@names, Str $buffer --> Str) {
    my Str $typed = ($buffer // '');
    return '' unless $typed.chars;
    my Str $lc = $typed.lc;
    my $hit = @names.first({
        .defined && .chars > $typed.chars && .lc.starts-with($lc)
    });
    $hit.defined ?? $hit.substr($typed.chars) !! '';
}

#|( What the transaction editor may offer for one account / transaction
    pair. Pure, because every one of these rules is an engine rule
    restated, and a restated rule that nobody can test goes stale.

    =item C<categorised> — the form shows a live category picker and
       saves splits. False on a tracking account (the engine refuses
       splits there) and on a transfer leg that does not cross the
       budget boundary (the engine refuses those too — no envelope
       moves when money stays inside the budget).
    =item C<tracking> / C<transfer> — which of the two reasons applies,
       so the picker can say which.
    =item C<endpoints-locked> — the account is static text. True for
       every edit: the engine refuses to move a transfer leg outright,
       and moving an ordinary transaction between accounts rewrites two
       balances, which is not something to offer in the same form as a
       memo edit.
    =item C<warn-first> — a reconciled transaction; confirm before
       opening.

    C<:$has-splits> is how a boundary-crossing transfer is recognised:
    the engine only permits splits on a transfer whose legs are on
    opposite sides of the budget, so a leg that has them is one. )
our sub editor-capabilities($account, $txn, Bool :$has-splits = False --> Hash) {
    my Bool $tracking = $account.defined && $account.is-tracking;
    my Bool $transfer = $txn.defined && $txn.is-transfer;
    %(
        :$tracking,
        :$transfer,
        categorised      => ($transfer ?? $has-splits !! !$tracking),
        endpoints-locked => $txn.defined,
        warn-first       => ($txn.defined && $txn.is-reconciled).Bool,
    );
}

#|( An amount field's value as a positive number of pence, or a
    C<Failure> carrying a message fit to show the user.

    Negatives are refused rather than accepted and negated: the
    direction is the RadioGroup's job, and a form where C<-5> in an
    Outflow field means an inflow is a form that lies about what it is
    going to do. )
our sub parse-magnitude(Str $text --> Int) {
    my Str $s = ($text // '').trim;
    return fail 'Enter an amount' if $s eq '';
    my $pence = parse-pence($s);
    if $pence ~~ Failure {
        my Str $msg = $pence.exception.message;
        $pence.so;
        return fail $msg;
    }
    return fail 'Enter a positive amount — use the Outflow / Inflow '
        ~ 'choice for the direction'
        if $pence <= 0;
    $pence;
}

# --- Shared plumbing ---------------------------------------------------

#| The accounts tab's controller, or a toast saying why not. Every
#| dialog below reaches the register and the sidebar through it.
sub accounts-tab($main) {
    my $tab = $main.accounts-tab;
    toast($main, 'Open the Accounts tab first') without $tab;
    $tab;
}

#|( Every category the register may file a transaction under: Ready to
    Assign first, then the envelopes in the budget grid's own order.

    Ready to Assign leads because it is the one the inflow rows want
    and because that is where a YNAB user's hand goes. It is an
    envelope the budget grid never shows and the move-money picker
    refuses — but a payday deposit has to land somewhere, and this is
    the only screen that can put it there. )
sub register-category-options($main --> List) {
    my $rta = $main.categories.first({ .defined && .is-rta });
    my @options = envelope-options(
        categories => $main.categories,
        groups     => $main.groups,
        include-hidden => True,
    );
    # (RTA-LABEL) parenthesised: a bareword before `=>` is autoquoted,
    # so without them the pair's key is the literal string "RTA-LABEL"
    # rather than the constant's value — which is exactly what the
    # category picker then printed.
    $rta.defined ?? (((RTA-LABEL) => $rta.id.Int), |@options).List
                 !! @options.List;
}

#| Every account a picker may offer, closed ones left out — a closed
#| account is one the user has finished with, and offering it as the
#| home for a new transaction is offering to reopen it by accident.
sub account-options($main --> List) {
    $main.accounts.grep({ .defined && !.closed })
        .sort({ ($_.sort-order // 0, $_.id // 0) })
        .map({ $_.name => $_.id.Int }).List;
}

#| A labelled C<Select>, two rows like C<labelled-input>: caption
#| above, control below.
sub labelled-select($label, @labels, $label-style, Int :$selected = 0 --> List) {
    my $row = Selkie::Layout::VBox.new(sizing => Sizing.fixed(2));
    $row.add: Selkie::Widget::Text.new(
        text => $label, sizing => Sizing.fixed(1), style => $label-style,
    );
    my $select = Selkie::Widget::Select.new(sizing => Sizing.fixed(1));
    $select.set-items(@labels.List);
    $select.select-index($selected.UInt) if @labels.elems;
    $row.add($select);
    ($row, $select);
}

# --- The transaction editor --------------------------------------------

#|( New transaction (no C<:transaction-id>) or edit an existing one.

    C<:$confirmed> is how the reconciled warning re-enters: the confirm
    dialog's yes-branch calls this again with it set, so there is one
    editor rather than an editor and a nearly-identical copy behind a
    guard. )
our sub open-transaction-editor($main, Int :$transaction-id,
                                Bool :$confirmed = False) {
    my $tab = accounts-tab($main);
    return without $tab;
    my $ws  = $main.workspace;
    my $app = $main.app;

    my $existing = $transaction-id.defined
        ?? $ws.transactions.find-by-id($transaction-id) !! Nil;
    if $transaction-id.defined && !$existing.defined {
        toast($main, 'That transaction no longer exists');
        return;
    }

    my @existing-splits = $existing.defined
        ?? $ws.transactions.find-splits($existing.id).List !! ();

    # Which account this transaction is on. An edit is stuck with the
    # one it has; a new one starts on whichever ledger the register is
    # showing, and All Accounts starts on the first in the picker.
    my @accounts = account-options($main);
    unless @accounts.elems || $existing.defined {
        toast($main, 'Create an account first — n on the sidebar');
        return;
    }
    my Int $account-id = $existing.defined
        ?? $existing.account-id.Int
        !! do {
            my Int $selected = $tab.register-account-id;
            $selected > 0 ?? $selected !! @accounts.head.value;
        };
    my $account = $main.account($account-id);

    my %caps = editor-capabilities($account, $existing,
                                   has-splits => ?@existing-splits.elems);

    # Reconciled means "this matched a statement". Ask first, then come
    # back through the same door.
    if %caps<warn-first> && !$confirmed {
        confirm-edit-reconciled($main, $existing);
        return;
    }

    my %styles = modal-styles(theme => $main.theme);
    my $icons  = $main.icons;

    #| Row budget — 22 fixed rows plus the flex status line:
    #| account (2), date (2), payee or transfer info (2), direction
    #| caption + its two options (3), amount (2), category (2),
    #| memo (2), the cleared checkbox (1), the splits caption (1) and
    #| its four rows (4), the remainder line (1). The frame charges 4
    #| more (two edges, a cell of padding each side), so the whole
    #| dialog wants 27 rows and 0.95 puts that inside a 29-row
    #| terminal.
    my $modal = Selkie::Widget::Modal.new(
        width-ratio        => 0.85,
        height-ratio       => 0.95,
        backdrop           => BackdropScrim,
        framed             => True,
        frame-style        => BorderRounded,
        frame-title        => ($existing.defined
            ?? 'Edit transaction' !! 'New transaction'),
        frame-bottom-title => ($existing.defined
            ?? 'tab move · enter/^s save · ^d delete · esc cancel'
            !! 'tab move · enter/^s save · esc cancel'),
    );

    my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);

    # --- Account ------------------------------------------------------
    my $account-select;
    if %caps<endpoints-locked> {
        $content.add(static-field('Account',
            ($account.defined ?? $account.name !! '(unknown account)'),
            %styles));
    } else {
        my $idx = @accounts.first({ .value == $account-id }, :k) // 0;
        my ($account-row, $as) = labelled-select(
            'Account', @accounts.map(*.key), %styles<label>,
            selected => $idx.Int);
        $account-select = $as;
        $content.add($account-row);
    }

    # --- Date ---------------------------------------------------------
    my ($date-row, $date-input) = labelled-input(
        'Date', ($existing.defined ?? $existing.date !! Date.today.Str),
        %styles<label>, placeholder => 'YYYY-MM-DD',
    );
    $content.add($date-row);

    # --- Payee, or what a transfer has instead ------------------------
    my $payee-input;
    if %caps<transfer> {
        my $peer = $existing.transfer-peer-id.defined
            ?? $ws.transactions.find-by-id($existing.transfer-peer-id) !! Nil;
        my $peer-account = $peer.defined ?? $main.account($peer.account-id) !! Nil;
        $content.add(static-field('Transfer',
            $icons.transfer ~ ' '
            ~ ($peer-account.defined ?? $peer-account.name !! 'the other account'),
            %styles));
    } else {
        my $current-payee = ($existing.defined && $existing.payee-id.defined)
            ?? $main.payee($existing.payee-id) !! Nil;
        my ($payee-row, $pi) = labelled-input(
            'Payee', ($current-payee.defined ?? $current-payee.name !! ''),
            %styles<label>, placeholder => 'e.g. Tesco  (blank = none)',
        );
        $payee-input = $pi;
        # Ghost completion over the payees that already exist. Pulled
        # at paint time, so it can never be stale against the buffer.
        my @names = $main.payees.sort({ $_.name }).map(*.name).List;
        $payee-input.suggest-provider = -> Str $buf, UInt $ {
            payee-suggest-tail(@names, $buf);
        };
        $content.add($payee-row);
    }

    # --- Direction and amount -----------------------------------------
    #
    # Stacked rather than side by side: an HBox whose children are two
    # rows tall and one row tall would leave the shorter one's
    # allocation to argue about, and a vertical form keeps Tab order
    # and reading order the same.
    $content.add: Selkie::Widget::Text.new(
        text => 'Direction', sizing => Sizing.fixed(1), style => %styles<label>,
    );
    my $direction = Selkie::Widget::RadioGroup.new(
        sizing => Sizing.fixed(2), show-scrollbar => False,
    );
    $direction.set-items((OUTFLOW-LABEL, INFLOW-LABEL));
    $direction.select-index(
        (($existing.defined && $existing.amount > 0) ?? 1 !! 0).UInt);
    $content.add($direction);

    my ($amount-row, $amount-input) = labelled-input(
        'Amount',
        ($existing.defined ?? format-pence($existing.amount.abs, :!symbol) !! ''),
        %styles<label>, placeholder => 'e.g. 42.10',
    );
    $content.add($amount-row);

    # --- Category ------------------------------------------------------
    my @categories = register-category-options($main);
    my Int $current-category = @existing-splits.elems == 1
        ?? @existing-splits[0].category-id.Int !! Int;
    my $cidx = $current-category.defined
        ?? (@categories.first({ .value == $current-category }, :k) // 0) !! 0;
    my ($category-row, $category-select) = labelled-select(
        'Category',
        (%caps<categorised> && @categories.elems
            ?? @categories.map(*.key)
            !! (uncategorised-note(%caps),)),
        %styles<label>, selected => $cidx.Int,
    );
    $content.add($category-row);

    # --- Memo, cleared --------------------------------------------------
    my ($memo-row, $memo-input) = labelled-input(
        'Memo', ($existing.defined ?? $existing.memo !! ''),
        %styles<label>, placeholder => 'Optional',
    );
    $content.add($memo-row);

    my $cleared-cb = Selkie::Widget::Checkbox.new(
        label  => 'Cleared',
        sizing => Sizing.fixed(1),
    );
    $cleared-cb.set-checked($existing.defined && $existing.is-cleared);
    $content.add($cleared-cb);

    # --- Splits ----------------------------------------------------------
    $content.add: Selkie::Widget::Text.new(
        text   => 'Splits    a add · e edit · d remove',
        sizing => Sizing.fixed(1), style => %styles<label>,
    );
    my $splits-list = Selkie::Widget::ListView.new(
        sizing => Sizing.fixed(SPLIT-ROWS),
    );
    $content.add($splits-list);
    my $remainder-line = Selkie::Widget::Text.new(
        text => '', sizing => Sizing.fixed(1), style => %styles<hint>,
    );
    $content.add($remainder-line);

    my $error = Selkie::Widget::Text.new(
        text => '', sizing => Sizing.flex, style => %styles<error>,
    );
    $content.add($error);
    $modal.set-content($content);

    # An existing multi-split transaction opens in split mode; a
    # single-split one opens with its category in the picker, which is
    # the shape it was entered in.
    my @entries = @existing-splits.elems > 1
        ?? @existing-splits.map({
               %( category-id => $_.category-id.Int,
                  amount      => ($_.amount.abs).Int,
                  memo        => ($_.memo // '') )
           }).Array
        !! [];

    # --- The live bits ----------------------------------------------------

    my sub current-magnitude(--> Int) {
        my $parsed = parse-magnitude($amount-input.text);
        if $parsed ~~ Failure { $parsed.so; 0 } else { $parsed }
    }

    # Which envelope the picker was on before the splits took it over,
    # so removing every split gives the user back the category they had
    # chosen rather than the one the dialog opened on.
    my Int $picked = $cidx.Int;
    my Bool $split-mode = False;

    my sub refresh-splits(--> Nil) {
        if @entries.elems {
            $splits-list.set-items(@entries.map({
                split-entry-label($main, $_)
            }).List);
            my Int $rem = split-remainder(current-magnitude(),
                                          @entries.map(*<amount>));
            $remainder-line.set-text($rem == 0
                ?? 'All ' ~ format-pence(current-magnitude()) ~ ' allocated'
                !! format-pence($rem) ~ ' unallocated — Save is disabled '
                   ~ 'until this is ' ~ format-pence(0));
            $remainder-line.set-style(
                $rem == 0 ?? %styles<hint> !! %styles<warn>);
            # The picker cannot mean anything while the splits do.
            $picked = $category-select.selected.Int unless $split-mode;
            $split-mode = True;
            $category-select.set-items(
                ('(split across ' ~ @entries.elems ~ ' categories)',));
        } else {
            # The placeholder has to be honest about whether `a` does
            # anything: on a tracking account or a same-side transfer
            # the split keys are not even bound.
            $splits-list.set-items((%caps<categorised>
                ?? '  (one category · press a to split it up)'
                !! '  ' ~ uncategorised-note(%caps),));
            $remainder-line.set-text('');
            $remainder-line.set-style(%styles<hint>);
            $category-select.set-items(
                (%caps<categorised> && @categories.elems
                    ?? @categories.map(*.key)
                    !! (uncategorised-note(%caps),)).List);
            $category-select.select-index($picked.UInt)
                if %caps<categorised> && @categories.elems;
            $split-mode = False;
        }
        Nil
    }
    refresh-splits();

    # The remainder is against the amount, so it has to follow it.
    $amount-input.on-change.tap: -> $ { refresh-splits() };

    # $picked has to follow the user's own choice, not stay frozen at
    # the index the dialog opened on: every Amount keystroke re-enters
    # refresh-splits, whose no-splits branch restores $picked — with a
    # stale $picked that restore silently threw away a category chosen
    # before the amount was (re)typed.
    $category-select.on-change.tap: -> $idx {
        $picked = $idx.Int unless $split-mode;
    };

    #|( Changing the account can change what the form is allowed to be:
        picking a tracking account takes the category picker and the
        splits away, and picking a budget account gives them back.

        C<%caps> is re-derived rather than re-read, and re-derived into
        the B<same> Hash — every closure below (including the one that
        saves) reads it at press time, so they all see the new answer
        without being rebuilt. Any splits already entered go with it: a
        tracking transaction cannot carry them, and keeping them
        invisibly would mean a Save that the engine refuses for a
        reason the screen is no longer showing. )
    with $account-select {
        $account-select.on-change.tap: -> $idx {
            my Int $now = (@accounts[$idx] andthen .value) // $account-id;
            %caps = editor-capabilities($main.account($now), $existing,
                                        has-splits => ?@existing-splits.elems);
            @entries = () unless %caps<categorised>;
            refresh-splits();
        };
    }

    # Bound unconditionally, and each one asks C<%caps> at press time
    # rather than at build time — the account picker above can turn the
    # splits on and off while the dialog is open.
    $splits-list.on-key: 'a',
        -> $ {
            if %caps<categorised> {
                open-split-entry($main, @categories, Nil, -> %entry {
                    @entries.push(%entry);
                    refresh-splits();
                });
            } else {
                toast($main, uncategorised-note(%caps));
            }
        },
        :description('Add a split');

    $splits-list.on-key: 'e',
        -> $ {
            my Int $idx = $splits-list.cursor.Int;
            if %caps<categorised> && 0 <= $idx < @entries.elems {
                open-split-entry($main, @categories, @entries[$idx],
                    -> %entry {
                        @entries[$idx] = %entry;
                        refresh-splits();
                    });
            }
        },
        :description('Edit this split');

    $splits-list.on-key: 'd',
        -> $ {
            my Int $idx = $splits-list.cursor.Int;
            if %caps<categorised> && 0 <= $idx < @entries.elems {
                @entries.splice($idx, 1);
                refresh-splits();
            }
        },
        :description('Remove this split');

    # --- Save --------------------------------------------------------------

    my $submit = Supplier.new;
    my sub save-now(--> Nil) {
        my Str $date = ($date-input.text // '').trim;
        my $magnitude = parse-magnitude($amount-input.text);
        my Int $chosen = %caps<endpoints-locked>
            ?? $account-id
            !! (@accounts[$account-select.selected] andthen .value) // $account-id;

        if !valid-date($date) {
            $error.set-text("Malformed date '$date' (expected YYYY-MM-DD)");
        } elsif $magnitude ~~ Failure {
            my Str $msg = $magnitude.exception.message;
            $magnitude.so;
            $error.set-text($msg);
        } elsif @entries.elems
                && split-remainder($magnitude, @entries.map(*<amount>)) != 0 {
            $error.set-text('The splits do not add up to '
                ~ format-pence($magnitude) ~ ' yet');
        } else {
            $error.set-text('');
            $submit.emit(%(
                account-id => $chosen,
                date       => $date,
                magnitude  => $magnitude.Int,
                direction  => ($direction.selected-label // OUTFLOW-LABEL),
                payee      => ($payee-input.defined
                    ?? ($payee-input.text // '').trim !! ''),
                category   => (%caps<categorised> && @categories.elems
                    ?? (@categories[$category-select.selected]
                            andthen .value) !! Int),
                memo       => ($memo-input.text // '').trim,
                cleared    => $cleared-cb.checked,
                entries    => @entries.clone,
            ));
        }
        Nil
    }
    $modal.on-key: 'ctrl+s', -> $ { save-now() }, :description('Save');
    # Enter in any of the text fields. Not on the splits list, the
    # direction radio or the cleared checkbox: Enter is already how you
    # edit a split, pick a direction and tick the box.
    enter-saves(&save-now, $date-input, $payee-input, $amount-input,
                $memo-input);

    if $existing.defined {
        $modal.on-key: 'ctrl+d',
            -> $ {
                $app.close-modal if $app.defined;
                confirm-delete-transaction($main, $existing);
            },
            :description('Delete this transaction');
    }

    $main.with-modal($submit.Supply, $modal,
                     ($account-select // $date-input),
        body => -> %f { save-transaction($main, $existing, %caps, %f) },
    );
}

#| What the category picker says when there is nothing to pick.
sub uncategorised-note(%caps --> Str) {
    return '(tracking account — never categorised)' if %caps<tracking>;
    return '(transfer inside the budget — no envelope moves)'
        if %caps<transfer>;
    '(no envelopes yet — create one on the Budget tab)';
}

#| One split entry as a list row: category, amount, and the memo if it
#| has one.
sub split-entry-label($main, %entry --> Str) {
    my $category = $main.category(%entry<category-id>);
    my Str $name = $category.defined
        ?? ($category.is-rta ?? RTA-LABEL !! $category.name)
        !! '(unknown category)';
    my Str $line = '  ' ~ name-cell($name, 24) ~ ' '
        ~ sprintf('%10s', format-pence((%entry<amount> // 0).Int));
    (%entry<memo> // '').chars ?? $line ~ '  ' ~ %entry<memo> !! $line;
}

#| A fixed-width name cell for the splits list, padded or elided.
sub name-cell(Str:D $name, Int:D $width --> Str) {
    return $name ~ (' ' x ($width - $name.chars)) if $name.chars < $width;
    return $name if $name.chars == $width;
    $name.substr(0, $width - 1) ~ '…';
}

#|( Add or edit one split. A nested modal — Selkie stacks them, so the
    editor underneath keeps every field the user has already filled in,
    which is the whole reason the splits are an entries list rather
    than a second screen.

    C<&on-save> receives C<< { category-id, amount, memo } >>, with the
    amount as a magnitude in the transaction's own direction (see the
    Pod). )
our sub open-split-entry($main, @categories, $entry, &on-save) {
    unless @categories.elems {
        toast($main, 'There are no envelopes to split across yet');
        return;
    }
    my %styles = modal-styles(theme => $main.theme);
    my $modal = Selkie::Widget::Modal.new(
        width-ratio        => 0.6,
        height-ratio       => 0.45,
        backdrop           => BackdropScrim,
        framed             => True,
        frame-style        => BorderRounded,
        frame-title        => ($entry.defined ?? 'Edit split' !! 'Add split'),
        frame-bottom-title => 'tab move · enter/^s save · esc cancel',
    );

    my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);
    my Int $current = $entry.defined ?? ($entry<category-id> // 0).Int !! Int;
    my $idx = $current.defined
        ?? (@categories.first({ .value == $current }, :k) // 0) !! 0;
    my ($category-row, $category-select) = labelled-select(
        'Category', @categories.map(*.key), %styles<label>,
        selected => $idx.Int);
    $content.add($category-row);

    my ($amount-row, $amount-input) = labelled-input(
        'Amount',
        ($entry.defined ?? format-pence(($entry<amount> // 0).Int, :!symbol) !! ''),
        %styles<label>, placeholder => 'e.g. 12.40  ·  (2.50) runs the other way',
    );
    $content.add($amount-row);

    my ($memo-row, $memo-input) = labelled-input(
        'Memo', ($entry.defined ?? ($entry<memo> // '') !! ''),
        %styles<label>, placeholder => 'Optional',
    );
    $content.add($memo-row);

    my $error = Selkie::Widget::Text.new(
        text => '', sizing => Sizing.flex, style => %styles<error>,
    );
    $content.add($error);
    $modal.set-content($content);

    my $submit = Supplier.new;
    my sub save-now(--> Nil) {
        # parse-pence rather than parse-magnitude: a split line may
        # legitimately run against the transaction's direction (a
        # refund inside a purchase), and accountant parentheses are
        # how that is typed here as everywhere else.
        my $pence = parse-pence(($amount-input.text // '').trim);
        if $pence ~~ Failure {
            my Str $msg = $pence.exception.message;
            $pence.so;
            $error.set-text($msg);
        } elsif $pence == 0 {
            $error.set-text('A split of nothing is not a split');
        } else {
            $submit.emit(%(
                category-id => (@categories[$category-select.selected]
                                    andthen .value) // 0,
                amount      => $pence.Int,
                memo        => ($memo-input.text // '').trim,
            ));
        }
        Nil
    }
    $modal.on-key: 'ctrl+s', -> $ { save-now() },
        :description('Save this split');
    enter-saves(&save-now, $amount-input, $memo-input);

    $main.with-modal($submit.Supply, $modal, $category-select,
        body => -> %entry { on-save(%entry) },
    );
}

#|( Turn the editor's fields into a gateway call, through the one write
    path.

    The payee is resolved B<inside> the mutation closure rather than
    before it: C<find-or-create> is itself a write, and a payee created
    for a transaction that then fails validation is a row nobody asked
    for. Its C<Failure> is returned as the closure's value, so
    C<ws/mutate> toasts it and skips the recompute exactly as it would
    for the transaction's own. )
sub save-transaction($main, $existing, %caps, %f --> Nil) {
    my $ws = $main.workspace;
    my Int $amount = signed-amount(%f<magnitude>, %f<direction>);
    my Str $cleared = do {
        # An edit never demotes a reconciled row by accident: the
        # checkbox is checked for both cleared and reconciled, so
        # leaving it alone has to mean "leave it alone".
        if %f<cleared> {
            ($existing.defined && $existing.is-reconciled)
                ?? 'reconciled' !! 'cleared';
        } else {
            'uncleared';
        }
    };

    my @splits;
    if %caps<categorised> {
        @splits = %f<entries>.elems
            ?? %f<entries>.map({
                   App::Moneymoor::Model::Split.new(
                       category-id => ($_<category-id>).Int,
                       amount      => signed-amount(($_<amount>).Int,
                                                    %f<direction>),
                       memo        => ($_<memo> // ''),
                   )
               }).Array
            !! (%f<category>.defined
                ?? [App::Moneymoor::Model::Split.new(
                        category-id => %f<category>.Int, amount => $amount)]
                !! []);
    }

    if %caps<categorised> && !@splits.elems {
        toast($main, 'Pick a category — a transaction on a budget account '
                     ~ 'has to say where the money went');
        return;
    }

    my Str $payee-name = (%f<payee> // '').trim;

    mutate($main, -> {
        my $payee = $payee-name.chars
            ?? $ws.payees.find-or-create($payee-name) !! Nil;
        if $payee ~~ Failure {
            $payee;
        } else {
            my Int $payee-id = $payee.defined ?? $payee.id.Int !! Int;
            if $existing.defined {
                my $updated = App::Moneymoor::Model::Transaction.new(
                    id               => $existing.id,
                    account-id       => $existing.account-id,
                    date             => %f<date>,
                    payee-id         => $payee-id,
                    memo             => %f<memo>,
                    amount           => $amount,
                    cleared          => $cleared,
                    transfer-peer-id => $existing.transfer-peer-id,
                );
                # Omitting :@splits keeps the existing ones, which is
                # what an uncategorised transaction wants; passing an
                # empty list would do the same thing less clearly.
                @splits.elems
                    ?? $ws.transactions.update($updated, :@splits)
                    !! $ws.transactions.update($updated);
            } else {
                my $fresh = App::Moneymoor::Model::Transaction.new(
                    account-id => %f<account-id>,
                    date       => %f<date>,
                    payee-id   => $payee-id,
                    memo       => %f<memo>,
                    amount     => $amount,
                    cleared    => $cleared,
                );
                $ws.transactions.create($fresh, :@splits);
            }
        }
    });
    toast($main, ($existing.defined ?? 'Saved ' !! 'Added ')
                 ~ format-pence($amount.abs)
                 ~ ($payee-name.chars ?? ' · ' ~ $payee-name !! ''));
    Nil
}

#| The confirm in front of editing a reconciled transaction. Yes
#| re-enters the editor with the warning already answered.
sub confirm-edit-reconciled($main, $txn --> Nil) {
    my $confirm = Selkie::Widget::ConfirmModal.new;
    my $modal = scrimmed($confirm.build(
        title     => 'Edit a reconciled transaction?',
        message   => 'This transaction is reconciled — it matched a '
                     ~ 'statement. Changing it means the account no longer '
                     ~ 'agrees with the statement it was reconciled '
                     ~ 'against.',
        yes-label => 'Edit anyway',
        no-label  => 'Leave it',
    ));
    my Int $id = $txn.id.Int;
    $main.with-modal($confirm.on-result, $modal, $confirm.no-button,
        body => -> Bool $yes {
            open-transaction-editor($main, transaction-id => $id,
                                    confirmed => True) if $yes;
        },
    );
    Nil
}

# --- Cleared, delete ----------------------------------------------------

#|( C<c> on the register: uncleared → cleared → reconciled → uncleared.

    One key for three states rather than a picker, because the state
    the user wants is almost always the next one along: a row is
    cleared when it shows up on the bank's site, reconciled when the
    statement agrees, and back to uncleared when it was neither. )
our sub cycle-cleared($main) {
    my $tab = accounts-tab($main);
    return without $tab;
    my $txn = $tab.selected-transaction;
    unless $txn.defined {
        toast($main, 'Select a transaction first');
        return;
    }

    my Str $next = next-cleared-state($txn.cleared);
    my $ws = $main.workspace;
    my Int $id = $txn.id.Int;
    mutate($main, -> { $ws.transactions.set-cleared($id, $next) });
    toast($main, 'Marked ' ~ $next);
}

#| C<d> on the register.
our sub delete-transaction($main) {
    my $tab = accounts-tab($main);
    return without $tab;
    my $txn = $tab.selected-transaction;
    unless $txn.defined {
        toast($main, 'Select a transaction first');
        return;
    }
    confirm-delete-transaction($main, $txn);
}

#|( Confirm, then delete. A transfer's peer leg goes with it — half a
    transfer is money that appeared from nowhere — and the copy says
    so, because the row the user is looking at is only one of the two
    that is about to disappear. )
sub confirm-delete-transaction($main, $txn --> Nil) {
    my $ws = $main.workspace;
    my Int $id = $txn.id.Int;
    my Str $what = format-pence($txn.amount.abs) ~ ' on ' ~ $txn.date;

    my $confirm = Selkie::Widget::ConfirmModal.new;
    my $modal = scrimmed($confirm.build(
        title     => 'Delete transaction?',
        message   => "Delete $what? " ~ ($txn.is-transfer
            ?? 'This is one leg of a transfer — the matching entry in the '
               ~ 'other account goes with it, because half a transfer is '
               ~ 'money that appeared from nowhere.'
            !! 'Its splits go with it. This cannot be undone.'),
        yes-label => 'Delete',
        no-label  => 'Cancel',
    ));
    $main.with-modal($confirm.on-result, $modal, $confirm.no-button,
        body => -> Bool $yes {
            if $yes {
                mutate($main, -> { $ws.transactions.delete($id) });
                toast($main, 'Deleted ' ~ $what);
            }
        },
    );
    Nil
}

# --- Reconcile (§4.5) ----------------------------------------------------

#| The payee every balance adjustment is filed under. Found or created,
#| so a budget reconciled twelve times has one payee and twelve
#| transactions rather than twelve payees.
our constant ADJUSTMENT-PAYEE is export = 'Balance Adjustment';

#|( C<Ctrl+R> on the register: ask for the statement balance and enter
    reconcile mode.

    Single-account only. A diff against All Accounts would be the
    difference between one statement and the sum of every ledger the
    user owns, which is not a number about anything — and there is no
    "the cleared balance" to compare it with either. )
our sub open-reconcile($main) {
    my $tab = accounts-tab($main);
    return without $tab;

    my Int $account-id = $tab.register-account-id;
    unless $account-id.defined && $account-id > 0 {
        toast($main, 'Pick one account in the sidebar — a statement is '
                     ~ 'about one ledger');
        return;
    }
    my $account = $main.account($account-id);
    return without $account;

    my $view = $main.view;
    my Int $cleared = $view.defined
        ?? $view.account-balance($account-id).cleared.Int !! 0;
    my %styles = modal-styles(theme => $main.theme);

    my $modal = Selkie::Widget::Modal.new(
        width-ratio        => 0.5,
        height-ratio       => 0.35,
        backdrop           => BackdropScrim,
        framed             => True,
        frame-style        => BorderRounded,
        frame-title        => 'Reconcile · ' ~ $account.name,
        frame-bottom-title => 'enter start · esc cancel',
    );

    my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);
    # What the register thinks has cleared, stated rather than left for
    # the user to read off the frame behind the scrim — it is the
    # number the statement is being compared against.
    $content.add(static-field('Cleared balance',
                              format-pence($cleared), %styles));

    # Prefilled with the cleared balance: the common case is that they
    # already agree, and a prefilled field that only needs Enter is the
    # difference between reconciling monthly and not bothering.
    my ($field, $input) = labelled-input(
        'Statement balance', format-pence($cleared, :!symbol),
        %styles<label>, placeholder => 'the closing balance on the statement',
    );
    $content.add($field);

    my $error = Selkie::Widget::Text.new(
        text => '', sizing => Sizing.flex, style => %styles<error>,
    );
    $content.add($error);
    $modal.set-content($content);

    # Validate before the supply emits — with-modal closes on emit, and
    # a dialog that vanishes on a typo has thrown the typo away too.
    my $submit = Supplier.new;
    $input.on-submit.tap: -> Str $text {
        my $parsed = parse-pence(($text // '').trim);
        if $parsed ~~ Failure {
            my Str $msg = $parsed.exception.message;
            $parsed.so;
            $error.set-text($msg);
            toast($main, $msg);
        } else {
            $submit.emit($parsed.Int);
        }
    };

    my $store = $main.store;
    $main.with-modal($submit.Supply, $modal, $input,
        body => -> Int $statement {
            $store.dispatch('accounts/reconcile-start',
                            :$account-id, :$statement);
            toast($main, 'Reconciling ' ~ $account.name
                         ~ ' · c marks cleared · enter finishes');
        },
    );
}

#|( Enter on the register while reconcile mode is active.

    Balanced, and every cleared transaction on the account is promoted
    to reconciled in one write. Out by anything at all, and the user is
    offered the transaction that would close the gap — because the
    alternative to offering it is a mode the user cannot leave through
    the front door when their bank has charged them a fee they never
    entered.

    C<:$today> is the adjustment's date, injected rather than read from
    the clock inside so a test can pin it. )
our sub finish-reconcile($main, Date :$today = Date.today) {
    my $tab = accounts-tab($main);
    return without $tab;

    my $mode = $main.store.get-in('accounts', 'reconcile');
    return without $mode;

    my Int $account-id = ($mode<account-id> // 0).Int;
    my Int $statement  = ($mode<statement>  // 0).Int;
    my $account = $main.account($account-id);
    return without $account;

    my $view = $main.view;
    my $balance = $view.defined ?? $view.account-balance($account-id) !! Nil;
    my Int $diff = reconcile-diff($statement, $balance);

    if $diff == 0 {
        promote-reconciled($main, $account-id);
    } else {
        confirm-adjustment($main, $account, $diff, $today);
    }
}

#|( The out-of-balance branch: offer a transaction for the difference,
    and only then finish.

    Declining leaves the mode exactly as it was — the user has a
    receipt to find, not a decision to unmake — which is why this is a
    confirm rather than a two-way choice. )
sub confirm-adjustment($main, $account, Int:D $diff, Date:D $today --> Nil) {
    my Str $what = format-pence($diff, :plus);
    my $confirm = Selkie::Widget::ConfirmModal.new;
    my $modal = scrimmed($confirm.build(
        title     => 'Out by ' ~ format-pence($diff.abs) ~ '?',
        message   => "The statement and the cleared balance differ by "
                     ~ "$what. Adding a $what '" ~ ADJUSTMENT-PAYEE
                     ~ "' transaction dated { $today.Str } will square them, "
                     ~ ($account.is-on-budget
                        ?? 'with the difference going to Ready to Assign. '
                        !! 'and it needs no envelope, because this is a '
                           ~ 'tracking account. ')
                     ~ 'Or find the missing transaction first and come '
                     ~ 'back — nothing you have marked cleared is lost.',
        yes-label => 'Adjust',
        no-label  => 'Keep looking',
    ));
    my Int $account-id = $account.id.Int;
    $main.with-modal($confirm.on-result, $modal, $confirm.no-button,
        body => -> Bool $yes {
            promote-reconciled($main, $account-id,
                               adjustment => $diff, date => $today.Str)
                if $yes;
        },
    );
    Nil
}

#|( The one write reconciling makes: the optional balance adjustment,
    then every C<cleared> transaction on the account promoted to
    C<reconciled>.

    All of it inside B<one> C<ws/mutate> closure, which is what makes
    it one recompute and one repaint. Sixty transactions promoted
    through sixty dispatches would be sixty derivations of the whole
    budget, each one throwing away the last.

    The first failure stops the run and is what the effect sees, so the
    toast is the engine's own words rather than "something went
    wrong" — and the recompute is skipped, exactly as it is for every
    other refused write. )
sub promote-reconciled($main, Int:D $account-id,
                       Int :$adjustment, Str :$date --> Nil) {
    my $ws = $main.workspace;
    my $account = $main.account($account-id);
    my $rta = $main.categories.first({ .defined && .is-rta });
    my Int $rta-id = $rta.defined ?? $rta.id.Int !! Int;
    my Bool $on-budget = $account.defined && $account.is-on-budget;

    mutate($main, -> {
        my $result = True;

        with $adjustment {
            my $payee = $ws.payees.find-or-create(ADJUSTMENT-PAYEE);
            if $payee ~~ Failure {
                $result = $payee;
            } else {
                my %adj = balance-adjustment(
                    :$account-id, amount => $adjustment, date => $date,
                    payee-id => ($payee.defined ?? $payee.id.Int !! Int),
                    rta-category-id => $rta-id, :$on-budget,
                );
                my @splits = %adj<splits>.List;
                $result = $ws.transactions.create(%adj<txn>, :@splits);
            }
        }

        unless $result ~~ Failure {
            # Re-read rather than trusting the rows on screen: the
            # register may be showing a cursor-restored repaint from
            # before the last `c`, and the promotion has to cover the
            # account, not the view of it.
            for promotable-ids($ws.transactions.find-by-account($account-id))
                    -> Int $id {
                my $one = $ws.transactions.set-cleared($id, 'reconciled');
                if $one ~~ Failure {
                    $result = $one;
                    last;
                }
            }
        }

        $result;
    });

    $main.store.dispatch('accounts/reconcile-exit');
    toast($main, 'Reconciled ✓');
    Nil
}

#|( The transaction that squares a statement with a register, as data:
    C<< { txn, splits } >>.

    Pure, and exported for that reason — three things about the shape
    are worth pinning:

    =item B<The sign is the diff's.> A statement showing more than the
       register has cleared means money arrived that was never
       entered, so the adjustment is an inflow. The diff is already
       signed from the account's point of view; nothing negates it.
    =item B<On-budget accounts get one split, to Ready to Assign.>
       Money appearing in a budget account is money to be assigned —
       the same place a payday deposit lands. An outward adjustment is
       a negative split against the same envelope, which takes it back
       out of Ready to Assign.
    =item B<Tracking accounts get no splits at all.> The engine
       refuses to categorise a tracking transaction, and the
       derivation excludes them from the budget by design.

    It is created already C<reconciled>: it exists to match a
    statement, and it matched one the moment it was written. )
our sub balance-adjustment(
    Int:D :$account-id!,
    Int:D :$amount!,
    Str:D :$date!,
    Int :$payee-id,
    Int :$rta-category-id,
    Bool :$on-budget = True,
    Str :$memo = '',
    --> Hash
) {
    my $txn = App::Moneymoor::Model::Transaction.new(
        :$account-id, :$date, :$payee-id, :$memo, :$amount,
        cleared => 'reconciled',
    );
    my @splits = ($on-budget && $rta-category-id.defined)
        ?? (App::Moneymoor::Model::Split.new(
                category-id => $rta-category-id, :$amount),)
        !! ();
    %( :$txn, splits => @splits.List );
}

# --- Transfer ------------------------------------------------------------

#|( C<t> on the register: move money between two accounts.

    The amount is always positive and the direction is the pair of
    pickers — C<create-transfer> takes a magnitude and reads the
    direction off which account is which, and a form with a "from" and
    a "to" on it that also accepted a negative would have two ways to
    say the same thing.

    The category picker only bites when the transfer crosses the budget
    boundary; see the DESCRIPTION. )
our sub open-transfer($main) {
    my $tab = accounts-tab($main);
    return without $tab;

    my @accounts = account-options($main);
    unless @accounts.elems >= 2 {
        toast($main, 'A transfer needs two accounts — n on the sidebar');
        return;
    }

    my %styles = modal-styles(theme => $main.theme);
    my @categories = register-category-options($main);

    # The register's own account is the obvious "from"; the "to"
    # defaults to the next one along so the form opens on a legal pair.
    my Int $selected = $tab.register-account-id;
    my Int $from-idx = $selected > 0
        ?? (@accounts.first({ .value == $selected }, :k) // 0).Int !! 0;
    my Int $to-idx = ($from-idx + 1) % @accounts.elems;

    my $modal = Selkie::Widget::Modal.new(
        width-ratio        => 0.65,
        height-ratio       => 0.7,
        backdrop           => BackdropScrim,
        framed             => True,
        frame-style        => BorderRounded,
        frame-title        => 'Transfer',
        frame-bottom-title => 'tab move · enter/^s save · esc cancel',
    );

    my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);
    my ($from-row, $from-select) = labelled-select(
        'From', @accounts.map(*.key), %styles<label>, selected => $from-idx);
    $content.add($from-row);
    my ($to-row, $to-select) = labelled-select(
        'To', @accounts.map(*.key), %styles<label>, selected => $to-idx);
    $content.add($to-row);

    my ($amount-row, $amount-input) = labelled-input(
        'Amount', '', %styles<label>, placeholder => 'e.g. 250.00');
    $content.add($amount-row);

    my ($date-row, $date-input) = labelled-input(
        'Date', Date.today.Str, %styles<label>, placeholder => 'YYYY-MM-DD');
    $content.add($date-row);

    my ($memo-row, $memo-input) = labelled-input(
        'Memo', '', %styles<label>, placeholder => 'Optional');
    $content.add($memo-row);

    my ($category-row, $category-select) = labelled-select(
        'Category', (@categories.elems
            ?? @categories.map(*.key) !! ('(no envelopes yet)',)),
        %styles<label>);
    $content.add($category-row);
    $content.add: Selkie::Widget::Text.new(
        text   => 'The category only applies when one side is a tracking '
                  ~ 'account — money leaving or entering the budget.',
        sizing => Sizing.fixed(2), style => %styles<hint>,
    );

    my $error = Selkie::Widget::Text.new(
        text => '', sizing => Sizing.flex, style => %styles<error>,
    );
    $content.add($error);
    $modal.set-content($content);

    my $submit = Supplier.new;
    my sub save-now(--> Nil) {
        my Int $from = (@accounts[$from-select.selected] andthen .value) // 0;
        my Int $to   = (@accounts[$to-select.selected]   andthen .value) // 0;
        my Str $date = ($date-input.text // '').trim;
        my $amount = parse-magnitude($amount-input.text);

        if $from == $to {
            $error.set-text('A transfer needs two different accounts');
        } elsif !valid-date($date) {
            $error.set-text("Malformed date '$date' (expected YYYY-MM-DD)");
        } elsif $amount ~~ Failure {
            my Str $msg = $amount.exception.message;
            $amount.so;
            $error.set-text($msg);
        } else {
            $error.set-text('');
            $submit.emit(%(
                from => $from, to => $to, date => $date,
                amount => $amount.Int,
                memo => ($memo-input.text // '').trim,
                category => (@categories.elems
                    ?? (@categories[$category-select.selected]
                            andthen .value) !! Int),
            ));
        }
        Nil
    }
    $modal.on-key: 'ctrl+s', -> $ { save-now() },
        :description('Make the transfer');
    enter-saves(&save-now, $amount-input, $date-input, $memo-input);

    my $ws = $main.workspace;
    $main.with-modal($submit.Supply, $modal, $from-select,
        body => -> %f {
            my $from = $main.account(%f<from>);
            my $to   = $main.account(%f<to>);
            # Exactly one on-budget leg means the money is entering or
            # leaving the envelopes, and that leg has to say from or to
            # which one. Two of a kind means no envelope moves at all,
            # and the engine refuses a split on it.
            my Int $on-budget = ($from, $to).grep({
                .defined && .is-on-budget }).elems;
            my @splits;
            if $on-budget == 1 && %f<category>.defined {
                @splits = [App::Moneymoor::Model::Split.new(
                    category-id => %f<category>.Int,
                    amount      => ($from.defined && $from.is-on-budget
                        ?? -%f<amount> !! %f<amount>),
                )];
            }
            mutate($main, -> {
                $ws.transactions.create-transfer(
                    from-account-id => %f<from>,
                    to-account-id   => %f<to>,
                    date            => %f<date>,
                    amount          => %f<amount>,
                    memo            => %f<memo>,
                    :@splits,
                );
            });
            toast($main, 'Transferred ' ~ format-pence(%f<amount>)
                         ~ ' to ' ~ ($to.defined ?? $to.name !! 'the other account'));
        },
    );
}

# --- The account editor ---------------------------------------------------

#|( New account (no C<:account-id>) or edit an existing one.

    The type is a picker on a new account and static text on an
    existing one, because C<Gateway::Account.update> refuses to change
    it — a cash account that became a credit card would need a payment
    envelope invented for it retroactively and every past period's
    coverage re-derived. )
our sub open-account-editor($main, Int :$account-id) {
    my $existing = ($account-id.defined && $account-id > 0)
        ?? $main.account($account-id) !! Nil;
    if $account-id.defined && $account-id > 0 && !$existing.defined {
        toast($main, 'That account no longer exists');
        return;
    }

    my $app    = $main.app;
    my $ws     = $main.workspace;
    my %styles = modal-styles(theme => $main.theme);
    my @types  = <cash credit tracking>;

    my $modal = Selkie::Widget::Modal.new(
        width-ratio        => 0.6,
        height-ratio       => 0.6,
        backdrop           => BackdropScrim,
        framed             => True,
        frame-style        => BorderRounded,
        frame-title        => ($existing.defined
            ?? 'Edit account · ' ~ $existing.name !! 'New account'),
        frame-bottom-title => ($existing.defined
            ?? 'enter/^s save · ^d delete · esc cancel'
            !! 'enter/^s save · esc cancel'),
    );

    my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);
    my ($name-row, $name-input) = labelled-input(
        'Name', ($existing.defined ?? $existing.name !! ''),
        %styles<label>, placeholder => 'Required');
    $content.add($name-row);

    my $type-select;
    if $existing.defined {
        $content.add(static-field('Type', $existing.type, %styles));
        $content.add: Selkie::Widget::Text.new(
            text   => 'An account\'s type cannot change — create a new '
                      ~ 'account instead.',
            sizing => Sizing.fixed(1), style => %styles<hint>,
        );
    } else {
        my ($type-row, $ts) = labelled-select(
            'Type', @types, %styles<label>);
        $type-select = $ts;
        $content.add($type-row);
        $content.add: Selkie::Widget::Text.new(
            text   => 'cash and credit are on budget · tracking is not · '
                      ~ 'a credit card gets its own payment envelope',
            sizing => Sizing.fixed(1), style => %styles<hint>,
        );
    }

    my ($note-row, $note-input) = labelled-input(
        'Note', ($existing.defined ?? $existing.note !! ''),
        %styles<label>, placeholder => 'Optional');
    $content.add($note-row);

    my ($order-row, $order-input) = labelled-input(
        'Sort order', ($existing.defined ?? $existing.sort-order.Str !! '0'),
        %styles<label>, placeholder => 'lower sorts first');
    $content.add($order-row);

    my $error = Selkie::Widget::Text.new(
        text => '', sizing => Sizing.flex, style => %styles<error>,
    );
    $content.add($error);
    $modal.set-content($content);

    my $submit = Supplier.new;
    my sub save-now(--> Nil) {
        my Str $name = ($name-input.text // '').trim;
        my Int $order = parse-sort-order($order-input.text);
        if $name eq '' {
            $error.set-text('An account needs a name');
        } elsif !$order.defined {
            $error.set-text('Sort order must be a whole number');
        } else {
            $submit.emit(%(
                :$name,
                type => ($existing.defined
                    ?? $existing.type
                    !! ($type-select.selected-value // 'cash')),
                note => ($note-input.text // '').trim,
                sort-order => $order,
            ));
        }
        Nil
    }
    $modal.on-key: 'ctrl+s', -> $ { save-now() }, :description('Save');
    enter-saves(&save-now, $name-input, $note-input, $order-input);

    if $existing.defined {
        $modal.on-key: 'ctrl+d',
            -> $ {
                $app.close-modal if $app.defined;
                confirm-delete-account($main, $existing);
            },
            :description('Delete this account');
    }

    $main.with-modal($submit.Supply, $modal, $name-input,
        body => -> %f {
            if $existing.defined {
                my $updated = App::Moneymoor::Model::Account.new(
                    id         => $existing.id,
                    name       => %f<name>,
                    type       => $existing.type,
                    note       => %f<note>,
                    closed     => $existing.closed,
                    sort-order => %f<sort-order>,
                );
                mutate($main, -> { $ws.accounts.update($updated) });
                toast($main, 'Saved ' ~ %f<name>);
            } else {
                my $fresh = App::Moneymoor::Model::Account.new(
                    name       => %f<name>,
                    type       => %f<type>,
                    note       => %f<note>,
                    sort-order => %f<sort-order>,
                );
                mutate($main, -> { $ws.accounts.create($fresh) });
                toast($main, 'Created ' ~ %f<name>
                             ~ (%f<type> eq 'credit'
                                ?? ' · its payment envelope is on the Budget tab'
                                !! ''));
            }
        },
    );
}

#|( C<c> on the sidebar: close an open account, reopen a closed one.

    Closing is the reversible half of deleting, and the one the user
    almost always wants: the history stays, the balances stay in the
    derivation, and the account leaves the sidebar for the C<CLOSED>
    fold. )
our sub toggle-account-closed($main) {
    my $tab = accounts-tab($main);
    return without $tab;
    my Int $id = $tab.selected-account-id;
    unless $id.defined && $id > 0 {
        toast($main, 'Select an account first');
        return;
    }
    my $account = $main.account($id);
    return without $account;

    my $ws = $main.workspace;
    if $account.closed {
        mutate($main, -> { $ws.accounts.reopen($id) });
        toast($main, 'Reopened ' ~ $account.name);
        return;
    }

    my Int $working = working-balance($main.view, $id);
    my $confirm = Selkie::Widget::ConfirmModal.new;
    my $modal = scrimmed($confirm.build(
        title     => 'Close account?',
        message   => "Close \"{ $account.name }\"? "
                     ~ ($working == 0
                        ?? 'Its history stays where it is, and it moves to '
                           ~ 'the CLOSED section of the sidebar.'
                        !! 'It still has ' ~ format-pence($working)
                           ~ ' in it — the money stays on the books either '
                           ~ 'way, but a closed account with a balance is '
                           ~ 'usually a transfer that has not been entered '
                           ~ 'yet.'),
        yes-label => 'Close',
        no-label  => 'Cancel',
    ));
    $main.with-modal($confirm.on-result, $modal, $confirm.no-button,
        body => -> Bool $yes {
            if $yes {
                mutate($main, -> { $ws.accounts.close($id) });
                toast($main, 'Closed ' ~ $account.name);
            }
        },
    );
}

#|( The one delete in the app that really does take everything with it.
    C<Gateway::Account.delete> removes the account, every transaction
    on it, their splits, and the peer leg of every transfer that
    touched it. The copy spells that out and points at closing, which
    is what the user almost certainly meant. )
sub confirm-delete-account($main, $account --> Nil) {
    my $ws = $main.workspace;
    my Int $id = $account.id.Int;
    my $confirm = Selkie::Widget::ConfirmModal.new;
    my $modal = scrimmed($confirm.build(
        title     => 'Delete account?',
        message   => "Delete \"{ $account.name }\"? This deletes ALL its "
                     ~ 'transactions and the matching leg of every transfer '
                     ~ 'it was part of, in every other account. It cannot be '
                     ~ 'undone. To keep the history and just get it off the '
                     ~ 'list, cancel and press c to close it instead.',
        yes-label => 'Delete everything',
        no-label  => 'Cancel',
    ));
    $main.with-modal($confirm.on-result, $modal, $confirm.no-button,
        body => -> Bool $yes {
            if $yes {
                mutate($main, -> { $ws.accounts.delete($id) });
                toast($main, 'Deleted ' ~ $account.name);
            }
        },
    );
    Nil
}
