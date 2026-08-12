unit module App::Moneymoor::View::ModalChrome;

=begin pod

=head1 NAME

App::Moneymoor::View::ModalChrome - the one canonical set of
C<Selkie::Style>s every modal, dialog and settings pane paints its
chrome with.

=head1 DESCRIPTION

Modals are built fresh on every open, and each one used to hand-roll
its own bold-blue title, grey label and dim italic hint from raw hex
literals. Six copies of the same three values meant two things: the
modals were frozen on a pseudo-TokyoNight palette no matter which of
the eleven themes the user picked, and "make hints a touch dimmer"
was a six-file change that would inevitably miss one.

C<modal-styles> replaces those literals with one theme-derived bundle.
Every entry is a semantic role, not a colour: pick the role that
describes what the text I<is> and the palette decides what it looks
like.

=head2 ROLES

=item C<title> — the modal's own heading. Palette C<accent>, bold: the
      one place in a modal that gets the theme's signature hue.
=item C<label> — a field caption ("Project", "Duration"). Reads at
      full C<fg-base> weight because the user has to scan these to
      find the field they want.
=item C<dim> — supporting body copy that is present but not shouting:
      the grammar / syntax explainer walls, read-only context lines.
      C<fg-dim>.
=item C<hint> — the trailing key-hint line ("Enter save · Esc
      cancel"). C<fg-dim> plus italic — the italic keeps it behind
      C<label> in the hierarchy without dropping to C<fg-dimmer>,
      which in several palettes (Nord's canonical comment grey most
      of all) falls under 1.5:1 contrast against C<bg-base> and
      renders the hint effectively invisible. C<hint> and C<dim> text
      never sit adjacent in practice, so sharing the hue costs
      nothing.
=item C<warn> — a consequence the user should read before acting (the
      login screen's "there is no passphrase reset"). C<fg-amber>,
      italic.
=item C<error> — a failed action or invalid input. C<fg-red>.

=head1 EXAMPLES

The whole bundle at once, destructured into the names the modal's
build method already used:

=begin code :lang<raku>

use App::Moneymoor::View::ModalChrome;

method build(App::Moneymoor::Theme :$theme! --> Selkie::Widget::Modal) {
    my %styles = modal-styles(:$theme);

    $content.add: Selkie::Widget::Text.new(
        text => ' Edit task', sizing => Sizing.fixed(1),
        style => %styles<title>,
    );
    $content.add: Selkie::Widget::Text.new(
        text => ' Title', sizing => Sizing.fixed(1),
        style => %styles<label>,
    );
    $content.add: Selkie::Widget::Text.new(
        text => ' Enter save · Esc cancel', sizing => Sizing.fixed(1),
        style => %styles<hint>,
    );
}

=end code

The returned styles are plain C<Selkie::Style> objects — immutable
value types — so a modal can safely hand the same one to a dozen
C<Text> widgets, and a caller that wants a variation merges rather
than mutates:

=begin code :lang<raku>

my %styles = modal-styles(:$theme);
my $bold-label = %styles<label>.merge(Selkie::Style.new(bold => True));

=end code

=head2 THEME SWATCH

C<swatch-spans(:$theme)> is a second, unrelated export sharing this
module because it is the same kind of thing: a pure, theme-derived
piece of chrome consumed by C<Screen::Settings>' live theme-preview
row. It returns eight C<Selkie::Widget::RichText::Span>s — one C<██>
colour chip per named palette slot, in a fixed order:

=begin code :lang<raku>

use App::Moneymoor::View::ModalChrome;

my @chips = swatch-spans(theme => $theme);
# accent, fg-red, fg-amber, fg-green, fg-blue, fg-purple, fg-cyan, bg-surface

=end code

Callers interleave their own separator spans (a plain-space C<Span>
between chips, as the doc example on C<swatch-spans> above shows) —
the eight returned spans carry only the colour, so a positional test
never has to skip over spacing.

=head1 NOTES

Modals are rebuilt per-open (see C<App::Moneymoor::Screen::Main::Modals>),
so injecting the theme at construction is enough to re-theme them: a
live theme swap while a modal is open isn't reachable, because the
Settings screen that performs the swap is itself the modal-free path.
No live-patch machinery is needed here, unlike the long-lived widgets
C<App::Moneymoor::Screen::Main.rebuild-captured-styles> has to fix up.

=head1 SEE ALSO

L<App::Moneymoor::Theme> — the palette these roles resolve against.

=end pod

use Selkie::Style;
use Selkie::Widget::RichText::Span;

use App::Moneymoor::Theme;

#|( The canonical modal-chrome style bundle for C<$theme>, keyed by
    semantic role: C<title>, C<label>, C<dim>, C<hint>, C<warn>,
    C<error>.

        my %styles = modal-styles(theme => $main.theme);
        %styles<title>;   # accent, bold
        %styles<hint>;    # fg-dim, italic

    Cheap enough to call once per modal build; callers hold the Hash
    for the life of the build rather than calling per widget. )
sub modal-styles(App::Moneymoor::Theme :$theme! --> Hash) is export {
    %(
        title => Selkie::Style.new(fg => $theme.accent,    bold   => True),
        label => Selkie::Style.new(fg => $theme.fg-base),
        dim   => Selkie::Style.new(fg => $theme.fg-dim),
        hint  => Selkie::Style.new(fg => $theme.fg-dim,    italic => True),
        warn  => Selkie::Style.new(fg => $theme.fg-amber,  italic => True),
        error => Selkie::Style.new(fg => $theme.fg-red),
    );
}

#|( Eight C<██> RichText spans, one per swatch slot, in the fixed
    order C<accent, fg-red, fg-amber, fg-green, fg-blue, fg-purple,
    fg-cyan, bg-surface> — the colour chips the Settings screen's live
    theme-preview row paints under the theme C<Select>. Each span's
    style carries only C<fg> (the chip colour); for the C<bg-surface>
    slot that means painting the surface colour I<as a foreground>
    — it's a colour swatch, not a background fill, so fg is what the
    user actually sees.

    The caller is responsible for any spacing between chips —
    C<swatch-spans> returns exactly the eight colour spans, no
    separators, so a positional/order assertion in a test doesn't
    have to skip over interleaved space spans:

        my @chips = swatch-spans(theme => $theme);
        my @content = @chips.kv.map(-> $i, $span {
            $i == @chips.end ?? $span
                              !! ($span, Selkie::Widget::RichText::Span.new(text => ' '))
        }).flat;
        $swatch-row.set-content(@content); )
sub swatch-spans(App::Moneymoor::Theme :$theme! --> List) is export {
    (
        $theme.accent, $theme.fg-red,    $theme.fg-amber, $theme.fg-green,
        $theme.fg-blue, $theme.fg-purple, $theme.fg-cyan,  $theme.bg-surface,
    ).map({
        Selkie::Widget::RichText::Span.new(
            text => '██', style => Selkie::Style.new(fg => $_),
        )
    }).List;
}
