#!/usr/bin/perl

# simulate filling a filesystem with bittorrent data.
# write random access to tons of files in pieces of $piecesize.
#
# for simplicity, files should be $filesize apiece, with
# $filesize/$piecesize pieces each.
#
# sample: 1GB files with 512K pieces (very comment torrent
#         parameters) gives you 2048 pieces per file.
#
# $rewrite chance that any given write will be to an already
# allocated block (simulate bad block received).


my $K = 1024;
my $M = 1024 * $K;
my $G = 1024 * $M;
my $T = 1024 * $G;

use Fcntl;

my $takesnapshots = 60; # take a snapshot every minute

my $datasetname = 'test/fillcow'; # where we're going to dump the data
my $path = '/' . $datasetname;
my $filesize = (1 * $G); # 1GB
my $piecesize = (512 * $K) ; # 512K
my $piecesperfile = $filesize / $piecesize;
my $concurrentset = (10 * $G) ; # 10G
my $rewrite = .001 ; # 0.1% chance of rewriting a block

my $piecedata = "D" x $piecesize; # $piecesize bytes worth of the character "D"

my $cycles = 4; # 4*10G = 40G

####

my $begin = time();

for (my $cycle=0; $cycle < $cycles; $cycle++) {
	
	# initialize our arrays - we write the piece number
	# of each piece into @unwritten, then as we actually write
	# pieces to the disk selected at random from @unwritten,
	# we pop that piece and push it into @written.
	
	my $totalnumberofpieces = $concurrentset / $piecesize;
	
	my @unwritten;
	my @written;
	
	# the important bit here is the VALUE of $unwritten[$loop].
	# at initialization, it's the same as its place in the array,
	# but as we pop things the value of remaining elements will no longer
	# match their place in the array.
	
	for (my $loop=0; $loop < $totalnumberofpieces; $loop++) {
		$unwritten[$loop] = $loop;
	}
	
	# now we're ready to start writing blocks.
	# we figure out what filename to write to by the block number
	# itself, rather than keeping track of individual files directly.
		
	my $lastsnap; # don't try to take several snapshots in the same second

	while (scalar @unwritten) {
		my $element;
		my $piecenum;
	
		if (rand() < $rewrite) {
			$element = rand @written;
			$piecenum = $written[$element];
			print "Rewriting piece $piecenum...\n";
		} else {
			$element = rand @unwritten;
			$piecenum = $unwritten[$element];
			# print "Piecenum: $piecenum  Blocks left: " . scalar @unwritten . "\n";
			push @written, $piecenum;
			splice @unwritten, $element, 1;
		}
	
		my $filenum = int ($piecenum / $piecesperfile);
		my $filepiecenum = $piecenum - ($filenum * $piecesperfile);
		my $filepos = $filepiecenum * $piecesize;
		my $filename = "$path/$cycle" . '_' . "$filenum";
	
		# sysopen FH, $filename, O_WRONLY|O_CREAT|O_SYNC;   # O_SYNC for much pain on the platters
		sysopen FH, $filename, O_WRONLY|O_CREAT; # no O_SYNC for how awesome your FS is
		sysseek (FH, $filepos, SEEK_SET);
		syswrite FH, $piecedata;
		close FH;
	
		my $elapsed = time() + 1 - $begin ;

		if ($takesnapshots && (int ($elapsed/$takesnapshots) == ($elapsed/$takesnapshots)) ) { 
			my $snapid = time();
			if ($snapid > $lastsnap) {
				print "taking per-minute snapshot $datasetname\@$snapid ...\n";
				system ("/sbin/zfs snapshot $datasetname\@$snapid"); 
				$lastsnap = $snapid;
			}
		}

		my $speed = ( ($concurrentset * $cycle + (scalar @written) * $piecesize ) / $M) / $elapsed;
		if ( int((scalar @unwritten)/100) == ((scalar @unwritten) / 100) ) {
			print "Cycle $cycle/" . ($cycles-1) . ", Written " . scalar @written . " / " . $totalnumberofpieces . " pieces (file $filename \@ filepiecenum $filepiecenum) at " . sprintf("%.1f",$speed) . " MB/sec.\n";
		}
	}
	
	print "unwritten: " . scalar @unwritten . "\n";
	print "written: " . scalar @written . "\n";
	print "total: " . $totalnumberofpieces . "\n";
	my $hours_elapsed = sprintf ("%.02d", int ( (time() - $begin) / 60 / 60));
	my $min_elapsed = sprintf ("%.02d", int ( (time() - $begin) / 60 ) - ($hours_elapsed * 60) );
	my $sec_elapsed = sprintf ("%.02d", (time() - $begin) - ($hours_elapsed * 60 * 60) - ($min_elapsed * 60) );
	print "time elapsed: $hours_elapsed:$min_elapsed:$sec_elapsed\n";

}

