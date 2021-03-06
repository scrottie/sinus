
#   Sinusfont: a simple SDL_ttf based sinus scroller
#   Copyright (C) 2004 Angelo "Encelo" Theodorou

#   sinus.pl: a stupid SDL_ttf based presentation software
#   Copyright (c) 2011 Scott "scrottie" Walters
 
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
 
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
  
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 
#   ORIGINAL Sinusfont NOTE: 
 
#   This program is part of "Mars, Land of No Mercy" SDL examples, 
#   you can find others examples on http://mars.sourceforge.net

#   NOTE:

#   This was adapted from a literal translation to Perl of the above 
#   as found at:
#   http://encelo.netsons.org/_download/sinus_font.tar.gz.
#   Translation by Scott Walters (aka scrottie, scott@slowass.net).
#   Get that for the .ttfs and the original .c or else cp your own
#   .ttf in here and change this to use that.

#   Usage:  $0 presentation_file.txt

#   The __DATA__ block contains a sample presentation.
#   The syntax of the file is:

#   =name value              <-- set a variable to a value
#   text text                <-- text 
#   =======================  <-- end slide; start next slide

#   See source code for all variables that can be diddled, or
#   see the example presentation for some of the more useful ones

=for comment

Todo:

o. =music directive
o. auto font size (80% of max width or height)
o.   ($seconds, $microseconds) = gettimeofday;
o. text_background image that is scaled to fit around the text and sit behind it and in front of the background; eg, alpha-effects for glass
o. build in the diagram generating tool I built earlier
o. replaced fixed delay, adapt the animation to the frame rate
o. slide file should let you map keys to increase/decrease variables by way of an order-of-magnitude system
o. integrate with xclip so that when code gets shown, it also gets loaded into the copy buffer
o. more buttons for tweaking variables
o. window manager chores, maybe?  bring windows of certain IDs forward, for example
o. effects:  spiral text inwards; start with text in place but spinning
o. display web pages via khtmltopng
o. actually, that's pretty cool that SDL recognizes my touch screen as a controller.  I may have to take advantage of that in my presentation software here, like Tim's iPad presentation software does


Done:

o. plugins
o. buttons for next slide, exit...
o. code listing markup/mode in the slide source that does fixed with font
o. multiple lines
o. instructions in the slide for selecting font
o. instructions in the slide for selecting render effects/settings

Note:

o. ls *.ttf | sed -e 's!.*!=font &\n&\n=====================================\n!' > fonts.txt 

=cut

use strict;
use warnings;

use Config;
use Carp;
use Data::Dumper;
use FindBin;

#BEGIN {
#    my $perl = $Config{perlpath};
#    push @INC, sub { 
#        my $self = shift;
#        my $module = shift;
#        return if grep $module eq $_, 'attrs.pm', 'Tie/StdScalar.pm', 'HTML/TreeBuilder/XPath/Node.pm';
#        $module =~ s{/}{::}g;  $module =~ s{\.pm$}{};
#        warn "installing $module";
#        my @module = ($module); 
#        @module = qw(Event Coro::Event Coro) if $module[0] eq 'Coro';  # all three, in order
#        my $cpanm = `which cpanm`;
#        chomp $cpanm;
#        if( ! $cpanm ) {
#            system 'wget', 'http://cpanmin.us', '-O', 'cpanm'; 
#            $cpanm = 'cpanm';
#        }
#        system $perl, $cpanm, @module;
#        return 1;
#    };
#}

use SDL;
use SDL::Image;
use SDL::Video;
use SDL::Surface;
use SDL::TTF;
use SDL::Rect;
use SDL::Color;
use SDL::Joystick;
use SDL::GFX::Rotozoom;
use SDL::Event;  # for the event object itself
use SDL::Events; # functions for event queue handling

use Coro;
use Coro::Event;

use Math::Trig;

use PadWalker;

use Web::Scraper;
use LWP::Simple;
use LWP::UserAgent;
use LWP;
use Time::HiRes;

sub opt ($) { scalar grep $_ eq $_[0], @ARGV }
sub arg ($) { my $opt = shift; my $i=1; while($i<=$#ARGV) { return $ARGV[$i] if $ARGV[$i-1] eq $opt; $i++; } }

use constant M_PI => 3.14159265358979323846;

$SIG{USR1} = sub { use Carp; Carp::confess "USR1"; };
$SIG{PIPE} = 'IGNORE';

#

my $slide_number = 1; # arg('--slide') || 1; ... need to do read all of the slides and populate @slide_offsets before we can do this, and then we'd still have to tell() to where we need to be
my @slide_offsets;

# renderer vars

my $screen;	
my $background_color_ob;
my $fh;
my $text_color_ob;
my $font_ob;
my $dir = 1;
my $angle = 0;
my $xpos; my $first_x;
my $ypos; my $first_y;
my $wave_stop_at_center_cur;
my $wave_amplitude_cur;
my $background_image_ob;
my $background_image_ob_x_offset;
my $background_image_ob_y_offset;
my %unicorns;  # unicorn surfaces
my @unicorns;  # unicorns on the screen
my $frame_number;

# commands from IO to renderer 

my $next_slide;

# commands from IO to renderer or from slide file to renderer

my $effect = 'wave';
my $text_color = "242 91 9";
my $background_color = "255 255 255";
my $wave_stop_at_center = 1;
my $wave_amplitude = 2;
my $font;
my $font_size = 35;
my $image;
my $background_image;
my $clear_background;
tie my $x_func, 'EvalScalar';
tie my $y_func, 'EvalScalar';
tie my $rot_func, 'EvalScalar';
tie my $scale_func, 'EvalScalar';
my $system;
my $google;
my $ms_per_frame = 20; # XXX temp; really we want to judge how much time elapsed and then move forward the right amount in the animation
my $bounce_rate = 10;
my $autoplay = 0;
my $autoplay_timer;

#

if( @ARGV ) {
    my $slides_fn = shift @ARGV or die "pass slides filename as arg";
    open $fh, '<', $slides_fn or die $!;
} else {
    $fh = \*DATA;
}

$font = "Distres2.ttf";

# Opening a window to draw inside 
my $fullscreen = 1;
sub open_screen {
    # SDL::quit() if $screen; # makes it crash that much quicker
    if( $fullscreen ) {
        $screen = SDL::Video::set_video_mode( 0, 0, 32, SDL_HWSURFACE | SDL_DOUBLEBUF | SDL_FULLSCREEN ) or Carp::confess SDL::get_error;
    } else {
        $screen = SDL::Video::set_video_mode( 800, 600, 24, SDL_HWSURFACE | SDL_DOUBLEBUF ) or Carp::confess SDL::get_error;
    }
    # Initializing video subsystem 
    if ( SDL::init(SDL::SDL_INIT_VIDEO | SDL_INIT_JOYSTICK) < 0 ) {
        printf("SDL_Init error: %s\n", SDL::get_error());
        exit(-1);
    }
}
open_screen();

# Joystick
my $joystick;
if( my $num_joysticks = SDL::Joystick::num_joysticks() ) {
    my $js_index = $num_joysticks-1;
    # my $js_index = 0;
    $joystick = SDL::Joystick->new($js_index) or die "XXXXXX";
    if($joystick) {
            printf("Opened Joystick $js_index\n");
            printf("Name: %s\n",              SDL::Joystick::name($js_index));
            printf("Number of Axes: %d\n",    SDL::Joystick::num_axes($joystick));
            printf("Number of Buttons: %d\n", SDL::Joystick::num_buttons($joystick));
            printf("Number of Balls: %d\n",   SDL::Joystick::num_balls($joystick));
        sleep 3;
    }
}
# SDL::Joystick::event_state(SDL_ENABLE); # http://www.libsdl.org/docs/html/sdljoystickeventstate.html
SDL::Events::joystick_event_state(SDL_ENABLE); # t/core_events.t

sub DIM_W () { $screen->w }
sub DIM_H () { $screen->h }
sub CENTER_X () { DIM_W / 2 }
sub CENTER_Y () { DIM_H / 2 }

# Initializing SDL_ttf 
if ( SDL::TTF::init() < 0 ) {
    printf("TTF_Init error: %s\n", SDL::get_error());
    exit(-1);
}

# Initialize Unicorns

if( -d 'corn' ) {
    opendir my $corns, 'corn' or die;
    while( my $fn = readdir $corns ) {
        # (my $base, my $num) = $fn =~ m{(.*)\.(\d)\.ppm$};
        (my $base, my $num) = $fn =~ m{(.*)\.(\d)\.png$};
        next unless $base and $num;
        # warn "base $base num $num fn $fn";
        my $unicorn_surface = SDL::Image::load( "corn/$fn" ) or die "couldn't load $fn: " . SDL::get_error();
# die ${  $unicorn_surface->format };

for my $surface ( $screen, $unicorn_surface ) { 

warn "bits per pixel " .           $surface->format->BitsPerPixel;

warn "bytes per pixel " .           $surface->format->BytesPerPixel;

warn "rloss " .           $surface->format->Rloss; #red   loss
warn "bloss " .          $surface->format->Bloss; #blue  loss
warn "gloss " .           $surface->format->Gloss; #green loss    
warn "aloss " .           $surface->format->Aloss; #alpha loss

warn "rshift " .           $surface->format->Rshift; #red   shift
warn "bshift " .           $surface->format->Bshift; #blue  shift
warn "gshift " .           $surface->format->Gshift; #green shift  
warn "ashift " .           $surface->format->Ashift; #alpha shift


warn "rmask " .           $surface->format->Rmask; #red   mask
warn  "bmask " .          $surface->format->Bmask; #blue  mask
warn "gmask " .           $surface->format->Gmask; #green mask    
warn "amask " .           $surface->format->Amask; #alpha mask

}



        push @{ $unicorns{$base} }, $unicorn_surface;
    }
}

# die Data::Dumper::Dumper \%unicorns;

# rainbow_2.gif.1.ppm
# rainbow_2.gif.2.ppm

#
# animate
#

async {

  next_slide:

    my $text = '';
    $autoplay = $autoplay ? $autoplay : 0; # pointless code just to get $autoplay into the pad

    @unicorns = ();

    $image = undef;
    $dir = 1;

    my $pad = PadWalker::peek_my(0);

    $slide_offsets[ $slide_number++ ] = tell $fh;

    while( my $line = readline $fh ) {
       if( $line =~ m/^===.*===$/ ) {
           print $line;
           last;
       }
       if( $line =~ m/^#/ ) {
           print $line;
           next;
       }
       if( $line =~ m/^=(\w+) (['"]?)(.*)\2/ ) {
           # warn "setting $1 = $3";
           exists $pad->{'$' . $1} or die "variable ``$1'' not in pad: " . join ', ', keys %$pad;
           ${$pad->{'$' . $1}} = $3;
       } else {
           $text .= $line;
       }
    }

    # Opening the font 
    my $font_path = $font;
    -f $font_path or $font_path = "$FindBin::Bin/$font";
    -f $font_path or $font_path = "$FindBin::RealBin/$font";
    -f $font_path or die "$font_path not found";
    if( ! ( $font_ob = SDL::TTF::open_font($font_path, $font_size) ) ) {
        die "TTF_OpenFont error: " . SDL::get_error();
    }

    # Mapping background and text color 
    $background_color_ob = SDL::Video::map_RGB($screen->format, split m/ +/, $background_color );

    $text_color_ob = SDL::Color->new(split m/ +/, $text_color);

    if( $google ) {

        $google =~ s{([^a-zA-Z0-9_-])}{'%'.sprintf('%2x', ord $1)}ge;

        my $ua = LWP::UserAgent->new;
        $ua->agent("git://gist.github.com/1240179.git");

        my $image_results_scraper = scraper {
            process "td>a", 'href[]' => '@href';
            result 'href';
        };
        
        # my $req = HTTP::Request->new(GET => 'http://images.google.com/search?tbm=isch&hl=en&source=hp&q=kitten&btnG=Search+Images&gbv=1');
        my $page = 10 * int rand 5;
        my $req = HTTP::Request->new(GET => 'http://images.google.com/search?q='.$google.'&hl=en&gbv=1&tbm=isch&start='.$page.'&sa=N');
        my $res = $ua->request($req);
        if ($res->is_success) {
            # print $res->decoded_content;
        } else {
            die $res->status_line, "\n";
        }
        
        my $hrefs = $image_results_scraper->scrape($res->decoded_content);
        
        $hrefs = [ grep m{^/imgres\?}, @$hrefs ];
        
        my $href = $hrefs->[ int rand @$hrefs ];
        
        my $params; my $nam;
        $href =~ s{^/imgres\?}{};
        map { $nam='word';s{^([a-z]+)=}{$nam=$1;''}e; tr/+/ /; s/%(..)/pack('c',hex($1))/ge; $params->{$nam}=$_; } split/[&;]/, $href;
        
        my $imgurl = $params->{imgurl};
        
        my $fn = $imgurl; $fn =~ s{.*/}{};
        
        open my $fh, '>', $fn or die "$!: $fn";
        $fh->print(get($imgurl));
        close $fh;
        
        undef $google;
        $image = $fn;

    }

    if( $system ) {
        if( $fullscreen ) { $screen = SDL::Video::set_video_mode( 1024, 768, 32, SDL_HWSURFACE | SDL_DOUBLEBUF ) or Carp::confess SDL::get_error; }
        system $system;
        $system = undef;
        sleep 1;
        my $event = SDL::Event->new();  # digest any wayward events
        SDL::Events::poll_event($event) for 1..10;
        if( $fullscreen ) { $screen = SDL::Video::set_video_mode( 0, 0, 32, SDL_HWSURFACE | SDL_DOUBLEBUF | SDL_FULLSCREEN ) or Carp::confess SDL::get_error; };
    }

    $text .= "\nX" if $image;  # image will replace the X  XXXX

    # Getting text surface dimension, it will be useful later 
    my $text_width = 0;
    my $text_height = 0;
    my $line_height = 0;  # height of an individual line of text
    for my $line ( split m/\n/, $text ) {
        $text =~ s{\t}{    }g;
        (my $tmp_text_width, my $tmp_text_height) = @{ SDL::TTF::size_text($font_ob, $line) };
        $text_width = $tmp_text_width if $tmp_text_width > $text_width;
        $line_height = $tmp_text_height if $tmp_text_height > $line_height;
        $text_height += $tmp_text_height;  # probably just $line_height * scalar @text
    }

    # Dynamic allocation of structures based on number of letters 
    my @letter_rect = map { SDL::Rect->new( 0, 0, 0, 0 ) } 1 .. length $text;

    # Creating surfaces for every letter 
    my @letter_surf;
    for ( my $i = 0; $i < length($text); $i++) {
        my $letter = substr $text, $i, 1;
        next if $letter eq "\n";
        $letter_surf[$i] = SDL::TTF::render_text_blended($font_ob, $letter, $text_color_ob) or next;

        $letter_rect[$i]->w( $letter_surf[$i]->w );
        $letter_rect[$i]->h( $letter_surf[$i]->h );
    }

    my $image_index;
    if( $image ) {
        my $surface = SDL::Image::load( $image ) or die "couldn't load $image: " . SDL::get_error();
        # treat it like another letter, though this is pretty clunky
        # do this after we've computed the line height and width and so forth so we don't throw that off, but then fix up the results
        $text_height += $surface->h;
        $text_width = $surface->w if $surface->w > $text_width; # XXX maybe we should scale the image down to something reasonable if needed
        $image_index = length($text) - 1;
        $letter_surf[$image_index] = $surface;
        $letter_rect[$image_index]->w( $surface->w );
        $letter_rect[$image_index]->h( $surface->h );
    }

    if( $background_image or $clear_background ) {
        SDL::Video::fill_rect($screen, SDL::Rect->new(0, 0, DIM_W, DIM_H), $background_color_ob);  # in case the scaled image doesn't completely cover the background
        $clear_background = $background_image = $background_image_ob = undef if $clear_background;
    }

    if( $background_image ) {
        $background_image_ob = SDL::Image::load( $background_image ) or die "couldn't load $background_image: " . SDL::get_error();
        if( $background_image_ob->w != DIM_W or $background_image_ob->h != DIM_H ) {
            # scale the image up or down as necessary to fit; correct aspect ratio isn't achieved
            my $zoom1 = DIM_W / $background_image_ob->w;
            my $zoom2 = DIM_H / $background_image_ob->h;
            (my $zoom) = sort { $a <=> $b } $zoom1, $zoom2;  # smaller size of the two
            my $tmp_surface = SDL::GFX::Rotozoom::surface( 
                $background_image_ob, 0, $zoom, SDL::GFX::Rotozoom::SMOOTHING_OFF,
            );
            $background_image_ob = $tmp_surface;
            $background_image_ob_x_offset = int( ( $screen->w - $background_image_ob->w ) / 2 );
            $background_image_ob_y_offset = int( ( $screen->h - $background_image_ob->h ) / 2 );
        }
    } else {
        $background_image_ob = undef;
    }

    #
    #
    #

    my $render_letter = sub {
        my $surface = shift;
        my $x = shift;
        my $y = shift;
        $surface or warn and return;
        SDL::Video::blit_surface( 
            $surface, 
            SDL::Rect->new(0, 0, $surface->w, $surface->h), 
            $screen, 
            SDL::Rect->new($x, $y, $surface->w, $surface->h)
        ); 
    };

    my $clear_screen = sub {
        if( $background_image_ob ) {
            $render_letter->($background_image_ob, $background_image_ob_x_offset, $background_image_ob_y_offset);
        } else {
            SDL::Video::fill_rect($screen, SDL::Rect->new(0, 0, DIM_W, DIM_H), $background_color_ob);
        }
    };

    my $delay = do {
        my $last_ts = Time::HiRes::gettimeofday();
        sub {
            my $new_ts = Time::HiRes::gettimeofday();
            my $delta_ts = $new_ts - $last_ts;
            if( $delta_ts < $ms_per_frame / 100 ) {
               # small delta; slow things down a bit
               SDL::delay(20 - $delta_ts * 100 );
               # warn "adding delay: @{[ 20 - $delta_ts * 100]} ms";
            } else {
               # warn "no delay; running behind schedule: @{[ 20 - $delta_ts * 100]} ms";
            }
            $last_ts = $new_ts;
            $frame_number++; # XXX
        };
    };

    my $cornify = sub {
        for my $unicorn_record ( @unicorns ) {
            # $unicorn_record = [ x, y, name ]
            my $unicorn_frame_number = $frame_number % @{ $unicorns{ $unicorn_record->[2] } };
            my $unicorn_surface = $unicorns{ $unicorn_record->[2] }[ $unicorn_frame_number ] or die;
            # warn "unicorn_frame_number $unicorn_frame_number x $unicorn_record->[0], y $unicorn_record->[1] ";
            $render_letter->( $unicorn_surface, $unicorn_record->[0], $unicorn_record->[1] );
        }
    };

    #
    #
    #

    $next_slide = 0;
    $autoplay_timer = undef;

    goto "effect_$effect" if $effect;
    goto effect_wave;

    #
    #
    #

  effect_bounce:

    $first_x = - $text_width;
    $first_y = CENTER_Y - $text_height / 2;

    while( 1 ) {
        $xpos = $first_x;
        $ypos = $first_y;
        for ( my $i = 0; $i < length($text); $i++ ) {
            if( substr($text, $i, 1) eq "\n" ) { 
                $xpos = $first_x;
                $ypos += $line_height;
                next;
            }
            $letter_rect[$i]->x( $xpos );
            $letter_rect[$i]->y( $ypos );
            $xpos += $letter_rect[$i]->w;
            $render_letter->($letter_surf[$i], $letter_rect[$i]->x, $letter_rect[$i]->y);
        }

        if ( $dir == 1 ) {
            $first_x += $bounce_rate;
            $dir = -1 if $first_x > 0;  # really only useful for things larger than the screen
        } elsif( $dir == -1 ) {
            $first_x -= $bounce_rate;
            $dir = 1 if $first_x + $text_width < $screen->w;
        }

        $cornify->();
        SDL::Video::flip($screen) < 0 and die;
        $clear_screen->();
        $delay->();

        cede;

        goto next_slide if $next_slide;
    
    }

  effect_instant:

    $clear_screen->();
    do {

        my $first_x = CENTER_X - $text_width / 2;
        my $first_y = CENTER_Y - $text_height / 2;

        my $x = $first_x;
        my $y = $first_y;

        for ( my $i = 0; $i < length($text); $i++ ) {

            if( substr($text, $i, 1) eq "\n" ) { 
                $x = $first_x;
                $y += $line_height;
                next;
            }

            $letter_rect[$i]->x( $x );
            $letter_rect[$i]->y( $y );

            $render_letter->($letter_surf[$i], $letter_rect[$i]->x, $letter_rect[$i]->y);

            $x += $letter_rect[$i]->w;

        }
    };
    SDL::Video::flip($screen) < 0 and die;
    while(1) {
        $cornify->();
        SDL::Video::flip($screen) < 0 and die;
        $delay->();
        cede;
        goto next_slide if $next_slide;
    }

  effect_custom:

    for my $frame ( 0..60 ) {
        my $row = 0;
        my $col = 0;

        my $prev_letter_width = 0;

        for ( my $i = 0; $i < length($text); $i++ ) {

            if( substr($text, $i, 1) eq "\n" ) { 
                $col = 0;
                $row++;
                next;
            }

            my $x     = $x_func->( $frame, $col, $row, $prev_letter_width );
            my $y     = $y_func->( $frame, $col, $row, $line_height );
            my $rot   = $rot_func ? $rot_func->( $frame, $col, $row ) : 0;
            my $scale = $scale_func ? $scale_func->( $frame, $col, $row ) : 1;

            $letter_rect[$i]->x( $x );
            $letter_rect[$i]->y( $y );

            $prev_letter_width = $letter_rect[$i]->w;

            my $tmp_surface = SDL::GFX::Rotozoom::surface( 
                $letter_surf[$i], $rot, $scale, SDL::GFX::Rotozoom::SMOOTHING_OFF,
            );

            $render_letter->($tmp_surface, $letter_rect[$i]->x, $letter_rect[$i]->y);

            $col++;

        }

        $cornify->();
        SDL::Video::flip($screen) < 0 and die;
        $clear_screen->();
        $delay->();

        cede;

        goto next_slide if $next_slide;
    }
    while(1) {
        $cornify->();
        SDL::delay(20);
        cede;
        goto next_slide if $next_slide;
    }


    #
    #
    #

  effect_lard: 0;
  effect_flab: 0;

    $first_x = - $text_width;
    $first_y = CENTER_Y - $text_height / 2;

    while ( 1 ) {
        $xpos = $first_x;
        $ypos = $first_y;
        for ( my $i = 0; $i < length($text); $i++ ) {
            if( substr($text, $i, 1) eq "\n" ) { 
                $xpos = $first_x;
                $ypos += $line_height;
                next;
            }
            $letter_rect[$i]->x( $xpos );
            $letter_rect[$i]->y( $ypos );
            $xpos += $letter_rect[$i]->w;
            # SDL::Video::blit_surface( $src_surface, $src_rect, $dest_surface, $dest_rect );
            # SDL::Video::blit_surface( $letter_surf[$i], undef, $screen, $letter_rect[$i]); # no, undef does *not* just copy the whole thing
            # SDL::Video::blit_surface( $letter_surf[$i], SDL::Rect->new(0, 0, $letter_surf[$i]->w, $letter_surf[$i]->h), $screen, $letter_rect[$i]);
            # my $letter_zoom = 1+sqrt( ( CENTER_X - ( $text_width / 2 ) + 10 ) - $xpos );
            my $letter_zoom;
            if( $effect eq 'lard' ) {
                $letter_zoom = 6;
                $letter_zoom = 5 if $xpos > 10;
                $letter_zoom = 4 if $xpos > 50;
                $letter_zoom = 3 if $xpos > 100;
                $letter_zoom = 2 if $xpos > 200;
                $letter_zoom = 1 if $xpos > 300;
            } elsif( $effect eq 'flab' ) {
                $letter_zoom = sqrt( ( CENTER_X - ( $text_width / 2 ) + 1 ) - $first_x );
            }
            my $tmp_surface = SDL::GFX::Rotozoom::surface( 
                $letter_surf[$i], 0, $letter_zoom, SDL::GFX::Rotozoom::SMOOTHING_OFF,
            );
            $render_letter->($tmp_surface, $letter_rect[$i]->x, $letter_rect[$i]->y);
        }

        if ( $first_x < CENTER_X - $text_width / 2 ) {
            $first_x += 5;
        }

        $cornify->();
        SDL::Video::flip($screen) < 0 and die;
        $clear_screen->();
        $delay->();

        cede;

        goto next_slide if $next_slide;
    
    }

    #
    #
    #

  effect_credits: 

    $first_x = CENTER_X - $text_width / 2;
    $first_y = $screen->h;
    while ( 1 ) {
        $xpos = $first_x;
        $ypos = $first_y;
        for ( my $i = 0; $i < length($text); $i++ ) {
            if( substr($text, $i, 1) eq "\n" ) { 
                $xpos = $first_x;
                $ypos += $line_height;
                next;
            }
            $letter_rect[$i]->x( $xpos );
            $letter_rect[$i]->y( $ypos );
            $xpos += $letter_rect[$i]->w;
            # SDL::Video::blit_surface( $src_surface, $src_rect, $dest_surface, $dest_rect );
            # SDL::Video::blit_surface( $letter_surf[$i], undef, $screen, $letter_rect[$i]); # no, undef does *not* just copy the whole thing
# if( $image_index and $i == $image_index ) { warn "image: x: " . $letter_rect[$i]->x . ' y: '. $letter_rect[$i]->y . ' ' . $letter_rect[$i]->h .' ' . $letter_rect[$i]->w . ' ' . $letter_surf[$i]->w . ' ' . $letter_surf[$i]->h . ' ' . substr($text, $i, 1) } # XXXX
            SDL::Video::blit_surface( $letter_surf[$i], SDL::Rect->new(0, 0, $letter_surf[$i]->w, $letter_surf[$i]->h), $screen, $letter_rect[$i]);
        }

        if ( $first_y > CENTER_Y - $text_height / 2 ) {
            $first_y -= 2;
        }

        $cornify->();
        SDL::Video::flip($screen) < 0 and die;
        $clear_screen->();
        $delay->();

        cede;

        goto next_slide if $next_slide;
    
    }

    #
    #
    #

  effect_wave:

    # Sinus scroller 
    $ypos = CENTER_Y;
    $wave_stop_at_center_cur = $wave_stop_at_center;
    $wave_amplitude_cur = $wave_amplitude;
    $first_x = - $text_width; # off left of screen
    $xpos = $first_x;

    while ( 1 ) {

        $first_y = CENTER_Y - $text_height / 2;
        $xpos = $first_x;

        for (my $i = 0; $i < length($text); $i++) {

            if( substr($text, $i, 1) eq "\n" ) { 
                $xpos = $first_x;
                $first_y += $line_height;
                next;
            }

            $letter_rect[$i]->x( $xpos );
    	    $xpos += $letter_rect[$i]->w;
    	    # $ypos = CENTER_Y + sin(M_PI / 180 * ($angle + $i * 15)) * $text_height * $wave_amplitude_cur; # works
            # $ypos = $first_y + sin(M_PI / 180 * ($angle + $i * 15)) * $text_height * $wave_amplitude_cur;
            $ypos = $first_y + sin(M_PI / 180 * ($angle + $i * 15)) * $line_height * $wave_amplitude_cur;

    	    $letter_rect[$i]->y( $ypos );
 
            my $letter_zoom = 1; # XXX control for this

            # my $letter_angle = $angle; # XXX control for this... spin on/off?
            # my $letter_angle = $angle + $i * 15; # interesting tumbling letters effect -- XXX control for this?
            # my $letter_angle = - 45 * atan(cos(M_PI / 180 * ($angle + $i * 15))); 
            my $letter_angle = - 45 * atan(cos(M_PI / 180 * ($angle + $i * 15))) * $wave_amplitude_cur;

            #  my $new_surface = SDL::GFX::Rotozoom::surface( $surface, $angle, $zoom, $smooth ); 

            my $tmp_surface = SDL::GFX::Rotozoom::surface( 
                $letter_surf[$i], $letter_angle, $letter_zoom, SDL::GFX::Rotozoom::SMOOTHING_OFF,
            );
            $render_letter->($tmp_surface, $letter_rect[$i]->x, $letter_rect[$i]->y);
    
        }
        $angle += 7;

 
        # Bouncing from one screen edge to the other 
        if ($xpos > $screen->w) {
          $dir = -1;
        }
        if ($first_x < 0) {
            $dir = 1;
        }

        if( $wave_stop_at_center_cur and $dir > 0 and $first_x > ( CENTER_X - $text_width / 2 ) * 0.65 ) {
            $dir = 0.5; # slow down
        }

        if( $wave_stop_at_center_cur and $dir > 0 and $first_x > ( CENTER_X - $text_width / 2 ) ) {
            $dir = 0;  # stop moving
        }

        if( $dir == 0 and $wave_amplitude_cur > 0 ) {
            $wave_amplitude_cur -= 0.1020;  # when we stop moving, stop oscillate
        }

        $first_x += $dir * 3;
    
        $cornify->();
        SDL::Video::flip($screen) < 0 and die;
        $clear_screen->();
        $delay->();

        cede;
    
        goto next_slide if $next_slide;

    }
};

#
# keyboard/mouse input
#

while(1) {

    # SDL::Events::pump_events();

    my $prev_slide = sub {
        $slide_number -= 2;
        $slide_number = 0 if $slide_number < 0;
        seek $fh, $slide_offsets[ $slide_number ], 0;
        $next_slide = 1;
    };

    my $event = SDL::Event->new();

    if(SDL::Events::poll_event($event)) {
       if( $event->type == SDL_MOUSEBUTTONDOWN ) {
           #$event->button_which;
           #$event->button_button;
           #$event->button_x;
           #$event->button_y;
       } elsif( $event->type == SDL_KEYUP ) {
           if( $event->key_sym == SDLK_SPACE ) {
               # next slide
               $next_slide = 1;
           } elsif( $event->key_sym == SDLK_b ) {
               $prev_slide->();
           } elsif( $event->key_sym == SDLK_p ) {
               $system = 'xpaint -size 800x600 -canvas';
               $next_slide = 1;
           } elsif( $event->key_sym == SDLK_q ) {
               warn "quitting on q key";
               SDL::quit();
               exit; # quit
           } elsif( $event->key_sym == SDLK_u ) {
               # unicorn!
               my @unicorn_names = keys %unicorns;
               my $unicorn_name = $unicorn_names[ int rand @unicorn_names ];
               my $unicorn_surface = $unicorns{ $unicorn_name }[0] or die "no surface for unicorn ``$unicorn_name''";
               push @unicorns, [ int rand( DIM_W - $unicorn_surface->w ), int rand( DIM_H - $unicorn_surface->h ), $unicorn_name ];
           } elsif( $event->key_sym == SDLK_f ) {
               # toggle fullscreen
               $fullscreen = ! $fullscreen;
               open_screen();
               $slide_number++; $prev_slide->();  # force redraw of the current slide
           } elsif( $event->key_sym == SDLK_a ) {
               # spin slower
           } elsif( $event->key_sym == SDLK_w ) {
               # spin faster... dunno...
           } 
           
       } elsif( $event->type == SDL_JOYAXISMOTION ) {
           #warn "- Joystick axis motion event structure: which axis: " . $event->jaxis_axis . " value: " . $event->jaxis_value;
           if( $event->jaxis_axis == 3 and $event->jaxis_value > 10000 ) {
               # right on the d-pad
               $next_slide = 1;
           } elsif( $event->jaxis_axis == 3 and $event->jaxis_value < -10000 ) {
               # left on the d-pad
               $prev_slide->();
           }
       } elsif( $event->type == SDL_JOYBALLMOTION ) {
           #warn "- Joystick trackball motion event structure";
       } elsif( $event->type == SDL_JOYHATMOTION ) {
           #warn " - Joystick hat position change event structure";
       } elsif( $event->type == SDL_JOYBUTTONDOWN ) {
           #warn" Joystick button event structure: button down: button ". $event->jbutton_button;
       } elsif( $event->type == SDL_JOYBUTTONUP ) {
           #warn " - Joystick button event structure: button up: button ". $event->jbutton_button;
       } elsif( $event->type == SDL_QUIT ) { 
           last;
       }
    }

    if( $autoplay and ! $autoplay_timer ) {
        $autoplay_timer = int(time()) + $autoplay;
    } elsif( $autoplay and int(time()) >= $autoplay_timer ) {
        $next_slide = 1;
        $autoplay_timer = 0;
    }

    cede;

}

#
#
#

package EvalScalar;

use Tie::Scalar;
use base 'Tie::StdScalar';

sub FETCH { ${ $_[0] } }
sub STORE { ${$_[0]} = eval 'sub { my($i, $x, $y, $d) = @_; ' . $_[1] . ' };' }

1;


__END__
test slide
with two lines
no, wait, three!
=====================
=effect custom
=x_func $i * 10 + $x * 25 
=y_func $i * 10 + $y * 30
test custom slide
=====================
=effect instant
There.
==========================
=effect credits
=image cat.jpg
image!
=====================
=effect wave
=image cat.jpg
image!
wtf...
======================
=effect wave
=font Andes.ttf
another slide
======================
=effect wave
=font Andes.ttf
=background_image border1.jpg
another slide
this time with a border
======================
=effect lard
another slide
======================
=effect flab
another slide
======================
=effect credits
another slide
======================
=background_image 0
=background_color 255 0 0
=text_color 255 255 255
red
======================
=effect wave
=background_color 192 192 192
=font Andale Mono.ttf
=text_color 0 0 0
=font_size 10
    $ypos = $first_y + sin(M_PI / 180 * ($angle + $i * 15)) * $line_height * $wave_amplitude_cur;
    $letter_rect[$i]->y( $ypos );
    my $letter_angle = - 45 * atan(cos(M_PI / 180 * ($angle + $i * 15))) * $wave_amplitude_cur;
==============================
=google kitten
a kitten
probably

