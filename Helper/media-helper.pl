use strict;
use warnings;
use DynaLoader;

# Loads Cranny's media helper library inside Apple's perl so it is allowed to
# read the system "Now Playing" state. Usage: perl media-helper.pl <library>
my $library = shift @ARGV or die "usage: media-helper.pl <library>\n";
my $handle = DynaLoader::dl_load_file($library, 0) or die DynaLoader::dl_error() . "\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "cranny_media_main") or die DynaLoader::dl_error() . "\n";
DynaLoader::dl_install_xsub("main::cranny_media_main", $symbol);
cranny_media_main();
