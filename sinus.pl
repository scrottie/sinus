
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

use strict;
use warnings;

use SDL;
use SDL::Video;
use SDL::Surface;
use SDL::TTF;
use SDL::Rect;
use SDL::Color;

use constant DIM_W => 800;
use constant DIM_H => 600;
use constant CENTER_X => DIM_W/2;
use constant CENTER_Y => DIM_H/2;
use constant M_PI => 3.14159265358979323846;  # some math.h don't define Pi 

my $screen;	
my $black;

my $font;
my $height; my $width;
my $text_color;
my $string;
my $default_str = "Mars: Land of No Mercy";
my $size;
my $letter;
my @letter_surf;
my @letter_rect;
my $font_file;
	
my $dir = 1;
my $angle = 0;
my $xpos; my $first_x;
my $ypos;
	
# Parsing shell parameters 
if (@ARGV == 0) {
    $font_file = "Distres2.ttf";
    $size = 35;
    $string = $default_str;
}
elsif (@ARGV == 3) {
    $font_file = $ARGV[0];
    if ( ! 0 + $ARGV[1] ) {
         printf("The second argument must be an int\n");
         exit(-1);
    }
    $string = $ARGV[2];
}
else {
    printf("The correct syntax is: %s font dimension string\n", $0);
    exit(-1);
}

# Dynamic allocation of structures based on numeber of letters 
@letter_rect = map { SDL::Rect->new( 0, 0, 0, 0 ) } 1 .. length $string;

# Initializing video subsystem 
if ( SDL::init(SDL::SDL_INIT_VIDEO) < 0 ) {
    printf("SDL_Init error: %s\n", SDL::get_error());
    exit(-1);
}

# Calling SDL_Quit at exit -- happens automatically so redundant
# END { SDL::quit() }

# Opening a window to draw inside 
# if ( ! ( $screen = SDL::Video::set_video_mode( DIM_W, DIM_H, 32, SDL_SWSURFACE ) ) )  # XXX
if ( ! ( $screen = SDL::Video::set_video_mode( DIM_W, DIM_H, 32, SDL_HWSURFACE | SDL_DOUBLEBUF ) ) ) {
    printf("SDL_SetVideoMode error: %s\n", SDL::get_error());
    exit(-1);
}

# Initializing SDL_ttf 
if ( SDL::TTF::init() < 0 ) {
    printf("TTF_Init error: %s\n", SDL::get_error());
    exit(-1);
}

# Opening the font 
if( ! ( $font = SDL::TTF::open_font($font_file, $size) ) ) {
    printf("TTF_OpenFont error: %s\n", SDL::get_error());
    exit(-1);
}

# Mapping background and text color 
$black = SDL::Video::map_RGB($screen->format, 0x00, 0x00, 0x00);

$text_color = SDL::Color->new(0xf2, 0x5b, 0x09);

# Getting text surface dimension, it will be useful later 
($width, $height) = @{ SDL::TTF::size_text($font, $string) };

# Creating surfaces for every letter 
for ( my $i = 0; $i < length($string); $i++) {
    $letter = substr $string, $i, 1;
    $letter_surf[$i] = SDL::TTF::render_text_blended($font, $letter, $text_color);
    $letter_rect[$i]->w( $letter_surf[$i]->w );
    $letter_rect[$i]->h( $letter_surf[$i]->h );
}

# Vertical text scrolling 
$ypos = $screen->h;
$xpos = CENTER_X - $width / 2;
while ( $ypos > CENTER_Y) {
    for ( my $i = 0; $i < length($string); $i++) {
        $letter_rect[$i]->x( $xpos );
        $letter_rect[$i]->y( $ypos );
        $xpos += $letter_rect[$i]->w;
        # SDL::Video::blit_surface( $src_surface, $src_rect, $dest_surface, $dest_rect );
        # SDL::Video::blit_surface( $letter_surf[$i], undef, $screen, $letter_rect[$i]); # no, undef does *not* just copy the whole thing
        SDL::Video::blit_surface( $letter_surf[$i], SDL::Rect->new(0, 0, $letter_surf[$i]->w, $letter_surf[$i]->h), $screen, $letter_rect[$i]);
    }
    $xpos = CENTER_X - ($width / 2);
    $ypos -= 2;

    SDL::Video::flip($screen) < 0 and die;
    SDL::delay(20);

    for ( my $i = 0; $i < length($string); $i++) {
        SDL::Video::fill_rect($screen, $letter_rect[$i], $black);
    }

}

# Sinus scroller 
$first_x = $xpos;
while ( $angle <= 360 * 8 ) {
    for (my $i = 0; $i < length($string); $i++) {
        if ($i == 0) {
	        $xpos = $first_x;
        }
        $letter_rect[$i]->x( $xpos );
	    $xpos += $letter_rect[$i]->w;
	    $ypos = CENTER_Y + sin(M_PI / 180 * ($angle + $i * 15)) * $height;
	    $letter_rect[$i]->y( $ypos );
        # SDL::Video::blit_surface( $letter_surf[$i], undef, $screen, $letter_rect[$i]); # XXX no
        SDL::Video::blit_surface( $letter_surf[$i], SDL::Rect->new(0, 0, $letter_surf[$i]->w, $letter_surf[$i]->h), $screen, $letter_rect[$i]);
    }
    $angle += 7;

    SDL::Video::flip($screen) < 0 and die;
    SDL::delay(20);

    # Bouncing from one screen edge to the other 
    if ($xpos > $screen->w) {
      $dir = -1;
    }
    if ($first_x < 0) {
      $dir = 1;
    }
    $first_x += $dir * 3;

    for (my $i = 0; $i < length($string); $i++) {
        SDL::Video::fill_rect($screen, $letter_rect[$i], $black);
    }
}

# Freeing the surfaces 
for (my $i = 0; $i < length($string); $i++) {
    delete $letter_surf[$i];
}

# Freeing dynamic allocated structures 
@letter_surf = ();
@letter_rect = ();

# Closing font and libraries 
$font = undef;
SDL::TTF::quit();
SD::quit();

exit;

