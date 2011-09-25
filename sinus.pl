
#   Sinusfont: a simple SDL_ttf based sinus scroller
#   Copyright (C) 2004 Angelo "Encelo" Theodorou
 
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
 
#   NOTE: 
 
#   This program is part of "Mars, Land of No Mercy" SDL examples, 
#   you can find others examples on http://mars.sourceforge.net

#   This is a literal translation to Perl of the above as found at
#   http://encelo.netsons.org/_download/sinus_font.tar.gz.
#   Translation by Scott Walters (aka scrottie, scott@slowass.net).
#   Get that for the .ttfs and the original .c or else cp your own
#   .ttf in here and change this to use that.

=for comment

Todo:

o. buttons for next slide, effects, exit...
o. code listing markup/mode in the slide source that does fixed with font
o. integrate with xclip so that when code gets shown, it also gets loaded into the copy buffer
o. multiple lines
o. instructions in the slide for selecting font
o. instructions in the slide for selecting render effects/settings

=cut

use strict;
use warnings;

use SDL;
use SDL::Video;
use SDL::Surface;
use SDL::TTF;
use SDL::Rect;
use SDL::Color;
use SDL::GFX::Rotozoom;
use SDL::Event;  # for the event object itself
use SDL::Events; # functions for event queue handling

use Coro;
use Coro::Event;

use Math::Trig;

use PadWalker;

use constant DIM_W => 800;
use constant DIM_H => 600;
use constant CENTER_X => DIM_W/2;
use constant CENTER_Y => DIM_H/2;
use constant M_PI => 3.14159265358979323846;

$SIG{USR1} = sub { use Carp; Carp::confess "USR1"; };

my $screen;	
my $black;

# renderer vars

my $text_color_ob;
my $font_ob;
my $dir = 1;
my $angle = 0;
my $xpos; my $first_x;
my $ypos;
my $wave_stop_at_center_cur;
my $wave_amplitude_cur;

# commands from IO to renderer 

my $next_slide;
my $skip;

# commands from IO to renderer or from slide file to renderer

my $effect = 'wave';
my $text_color = "242 91 9";
my $background_color = "255 255 255";
my $wave_stop_at_center = 1;
my $wave_amplitude = 2;
my $font;
my $font_size = 35;

#

my $slides_fn = shift @ARGV or die "pass slides filename as arg";
open my $fh, '<', $slides_fn or die $!;

$font = "Distres2.ttf"; # XXX overwrite and re-open TTF as necessary based on instructions in the slide file

# Initializing video subsystem 
if ( SDL::init(SDL::SDL_INIT_VIDEO) < 0 ) {
    printf("SDL_Init error: %s\n", SDL::get_error());
    exit(-1);
}

# Opening a window to draw inside 
if ( ! ( $screen = SDL::Video::set_video_mode( DIM_W, DIM_H, 32, SDL_HWSURFACE | SDL_DOUBLEBUF ) ) ) {
    printf("SDL_SetVideoMode error: %s\n", SDL::get_error());
    exit(-1);
}

# Initializing SDL_ttf 
if ( SDL::TTF::init() < 0 ) {
    printf("TTF_Init error: %s\n", SDL::get_error());
    exit(-1);
}

#
# animate
#

async {

  next_slide:

    my $string = '';

    my $pad = PadWalker::peek_my(0);

    while( my $line = readline $fh ) {
       last if $line =~ m/^===.*===$/;
       if( $line =~ m/^=(\w+) (['"]?)(.*)\2/ ) {
           warn "setting $1 = $3";
            exists $pad->{'$' . $1} or die "variable ``$1'' not in pad";
            ${$pad->{'$' . $1}} = $3;
       } else {
           chomp $line;
           $string .= $line;
       }
    }

    warn "string: $string";

    $next_slide = 0;

    # Opening the font 
    if( ! ( $font_ob = SDL::TTF::open_font($font, $font_size) ) ) {
        die "TTF_OpenFont error: " . SDL::get_error();
    }

    # Mapping background and text color 
    $black = SDL::Video::map_RGB($screen->format, split m/ +/, $background_color );

    $text_color_ob = SDL::Color->new(split m/ +/, $text_color);

    # Getting text surface dimension, it will be useful later 
    (my $text_width, my $text_height) = @{ SDL::TTF::size_text($font_ob, $string) };

    # Vertical text scrolling 
    # Dynamic allocation of structures based on number of letters 
    my @letter_rect = map { SDL::Rect->new( 0, 0, 0, 0 ) } 1 .. length $string;

    # Creating surfaces for every letter 
    my @letter_surf;
    for ( my $i = 0; $i < length($string); $i++) {
        my $letter = substr $string, $i, 1;
        $letter_surf[$i] = SDL::TTF::render_text_blended($font_ob, $letter, $text_color_ob);
        $letter_rect[$i]->w( $letter_surf[$i]->w );
        $letter_rect[$i]->h( $letter_surf[$i]->h );
    }

    goto "effect_$effect" if $effect;
    goto effect_wave;

    #
    #
    #

  effect_credits: 

    $ypos = $screen->h;
    $xpos = CENTER_X - $text_width / 2;
    while ( $ypos > CENTER_Y) {
        for ( my $i = 0; $i < length($string); $i++) {
            $letter_rect[$i]->x( $xpos );
            $letter_rect[$i]->y( $ypos );
            $xpos += $letter_rect[$i]->w;
            # SDL::Video::blit_surface( $src_surface, $src_rect, $dest_surface, $dest_rect );
            # SDL::Video::blit_surface( $letter_surf[$i], undef, $screen, $letter_rect[$i]); # no, undef does *not* just copy the whole thing
            SDL::Video::blit_surface( $letter_surf[$i], SDL::Rect->new(0, 0, $letter_surf[$i]->w, $letter_surf[$i]->h), $screen, $letter_rect[$i]);
        }
        $xpos = CENTER_X - ($text_width / 2);
        $ypos -= 2;
    
        SDL::Video::flip($screen) < 0 and die;
        SDL::delay(20);

        cede;

        goto next_slide if $next_slide;
        $skip and do { $skip = 0; last; };
    
        for ( my $i = 0; $i < length($string); $i++) {
            SDL::Video::fill_rect($screen, $letter_rect[$i], $black);
        }
    
    }
    
    #
    #
    #

  effect_wave:

    # Sinus scroller 
    $ypos = CENTER_Y;
    $wave_stop_at_center_cur = $wave_stop_at_center;
    $wave_amplitude_cur = $wave_amplitude;
    # $first_x = DIM_W;
    $first_x = - $text_width; # DIM_W;
    while ( 1 ) {
    	$xpos = $first_x;
        for (my $i = 0; $i < length($string); $i++) {
            $letter_rect[$i]->x( $xpos );
    	    $xpos += $letter_rect[$i]->w;
    	    $ypos = CENTER_Y + sin(M_PI / 180 * ($angle + $i * 15)) * $text_height * $wave_amplitude_cur;

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
            SDL::Video::blit_surface( 
                $tmp_surface, 
                SDL::Rect->new(0, 0, $tmp_surface->w, $tmp_surface->h), 
                $screen, 
                SDL::Rect->new($letter_rect[$i]->x, $letter_rect[$i]->y, $tmp_surface->w, $tmp_surface->h) # $letter_rect[$i],
            ); 
    
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
    
        #for (my $i = 0; $i < length($string); $i++) {
        #    SDL::Video::fill_rect($screen, $letter_rect[$i], $black);
        #}

        SDL::Video::flip($screen) < 0 and die;
        SDL::Video::fill_rect($screen, SDL::Rect->new(0, 0, DIM_W, DIM_H), $black);
        SDL::delay(20);

        cede;
    
        goto next_slide if $next_slide;
        $skip and do { $skip = 0; last; };

    }
};

#
# keyboard/mouse input
#

while(1) {   

    # SDL::Events::pump_events();

    my $event = SDL::Event->new();

    if(SDL::Events::poll_event($event)) {  
       if( $event->type == SDL_MOUSEBUTTONDOWN ) {
           # now you can handle the details
           #$event->button_which;
           #$event->button_button;
           #$event->button_x;
           #$event->button_y;
       } elsif( $event->type == SDL_KEYUP ) {
           if( $event->key_sym == SDLK_SPACE ) {
               # next slide
               $next_slide = 1;
           } elsif( $event->key_sym == SDLK_q ) {
               # spin faster
           } elsif( $event->key_sym == SDLK_a ) {
               # spin slower
           } elsif( $event->key_sym == SDLK_w ) {
               # skip
               $skip = 1;
           } 
           
       } elsif( $event->type == SDL_QUIT ) { 
           last;
       }
    }

    cede;

}

# Freeing the surfaces 
#for (my $i = 0; $i < length($string); $i++) {
#    delete $letter_surf[$i];
#}

# Freeing dynamic allocated structures 
#@letter_surf = ();
#@letter_rect = ();

# Closing font and libraries 
#$font = undef;
#SDL::TTF::quit();
#SD::quit();

exit;


__END__

# if ( ! ( $screen = SDL::Video::set_video_mode( DIM_W, DIM_H, 32, SDL_SWSURFACE ) ) )  # XXX
        # SDL::Video::blit_surface( $letter_surf[$i], undef, $screen, $letter_rect[$i]); # XXX no

        # SDL::Video::blit_surface( $letter_surf[$i], SDL::Rect->new(0, 0, $letter_surf[$i]->w, $letter_surf[$i]->h), $screen, $letter_rect[$i]); # good


