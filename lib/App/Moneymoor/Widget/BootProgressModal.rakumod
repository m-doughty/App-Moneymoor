=begin pod

=head1 NAME

App::Moneymoor::Widget::BootProgressModal - non-dismissable boot progress UI

=head1 DESCRIPTION

Keeps focus away from the login fields while an encrypted budget opens. The
modal consumes ordinary input; Selkie's global C<Ctrl+Q> remains available.

=end pod

unit class App::Moneymoor::Widget::BootProgressModal;

use Selkie::BorderStyle;
use Selkie::Sizing;
use Selkie::Store;
use Selkie::Layout::VBox;
use Selkie::Widget::Modal;
use Selkie::Widget::ProgressBar;
use Selkie::Widget::Text;

has Selkie::Store $.store is required;
has Str $.title = 'Opening budget';
has Selkie::Widget::Modal $.modal;
has Selkie::Widget::Text $!status;
has Selkie::Widget::Text $!detail;
has Selkie::Widget::ProgressBar $!bar;

method focus-widget() { $!status }
method status-text(--> Str) { $!status.defined ?? $!status.text !! '' }
method detail-text(--> Str) { $!detail.defined ?? $!detail.text !! '' }
method bar() { $!bar }

method build(--> Selkie::Widget::Modal) {
    $!modal = Selkie::Widget::Modal.new(
        width-ratio => 0.6, height-ratio => 0.3,
        backdrop => BackdropScrim, :!dismissable, :framed,
        frame-style => BorderRounded, frame-title => $!title,
    );
    my $body = Selkie::Layout::VBox.new(sizing => Sizing.flex);
    $!status = Selkie::Widget::Text.new(
        text => 'Opening budget…', focusable => True,
        sizing => Sizing.fixed(1));
    $!bar = Selkie::Widget::ProgressBar.new(
        indeterminate => True, show-percentage => False,
        sizing => Sizing.fixed(1));
    $!detail = Selkie::Widget::Text.new(text => '', sizing => Sizing.fixed(1));
    $body.add($_) for $!status, $!bar, $!detail;
    $body.add(Selkie::Widget::Text.new(text => '', sizing => Sizing.flex));
    $!modal.set-content($body);
    $!store.subscribe-with-callback(
        'boot-progress',
        -> $s { ($s.get-in('ui', 'boot') // %()).Hash },
        -> %boot { self.apply(%boot) },
        $!modal,
    );
    self.apply(($!store.get-in('ui', 'boot') // %()).Hash);
    $!modal;
}

method tick(--> Nil) { .tick with $!bar }

method apply(%boot --> Nil) {
    $!status.set-text(self.headline(%boot)) if $!status.defined;
    $!detail.set-text((%boot<detail> // '').Str) if $!detail.defined;
    Nil;
}

method headline(%boot --> Str) {
    given (%boot<phase> // '').Str {
        when 'unlock'  { 'Unlocking encrypted budget…' }
        when 'verify'  { 'Verifying passphrase…' }
        when 'migrate' { 'Checking database schema…' }
        when 'compile' { 'Compiling interface (first run after an update)…' }
        when 'build'   { 'Building interface…' }
        when 'failed'  { 'Could not open the budget' }
        default        { 'Opening budget…' }
    }
}
