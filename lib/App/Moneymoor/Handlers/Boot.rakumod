=begin pod

=head1 NAME

App::Moneymoor::Handlers::Boot - store-side coordinator for responsive login

=head1 DESCRIPTION

Owns the single in-flight login slot and converts worker progress/completion
events into C<ui.boot> state plus loop-thread callbacks. Workers may only call
C<Selkie::Store.dispatch>; all widget and screen work remains on the loop.

=end pod

unit class App::Moneymoor::Handlers::Boot;

use Selkie::Store;

has &.show-main is required;
has &.on-failed is required;
has Bool $!in-flight = False;
has Bool $!completed = False;

method in-flight(--> Bool) { $!in-flight }
method completed(--> Bool) { $!completed }

method claim(--> Bool) {
    return False if $!in-flight || $!completed;
    $!in-flight = True;
    True;
}

method release(--> Nil) { $!in-flight = False }

method register(Selkie::Store:D $store --> Nil) {
    $store.register-handler('boot/started', -> $st, %ev {
        (db-replace => { path => <ui boot>, value => %(
            active => True, phase => 'start',
            detail => (%ev<detail> // '').Str,
        ) },);
    });
    $store.register-handler('boot/phase', -> $st, %ev {
        (db-replace => { path => <ui boot>, value => self.phase-state(%ev) },);
    });
    $store.register-handler('boot/ready', -> $st, %ev {
        (db-replace => { path => <ui boot>, value => %(
            active => True, phase => 'build', detail => 'main screen',
        ) }, 'boot-show-main' => %(fresh => ?%ev<fresh>));
    });
    $store.register-handler('boot/failed', -> $st, %ev {
        my Str $message = self.failure-message(%ev);
        (db-replace => { path => <ui boot>, value => %(
            active => False, phase => 'failed', detail => $message,
        ) }, 'boot-failed-ui' => %(:$message));
    });
    $store.register-fx('boot-show-main', -> $st, %params {
        unless $!completed {
            $!completed = True;
            &!show-main(:fresh(?%params<fresh>));
        }
    });
    $store.register-fx('boot-failed-ui', -> $st, %params {
        unless $!completed {
            $!in-flight = False;
            &!on-failed(self.failure-message(%params));
        }
    });
}

method phase-state(%ev --> Hash) {
    %(
        active => True,
        phase  => (%ev<phase> // '').Str,
        detail => (%ev<detail> // '').Str,
    );
}

method failure-message(%payload --> Str) {
    my Str $message = (%payload<message> // '').Str.trim;
    $message.chars ?? $message !! 'Could not open the budget';
}
