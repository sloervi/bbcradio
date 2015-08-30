#!/usr/bin/perl
# bbc.pl
# sloervi McMurphy 28.08.2015
# Download BBC Radio Shows

use strict;
use warnings;
use Getopt::Long;
use utf8;
use Data::Dumper;
use Log::Log4perl qw(:easy);

my $such_sendung = "Litir";
my $help=0;
my $quiet=0;
my $outdir="/data";
my $senke="$outdir/log";
my $htmlformat=1;       # Ausgabe der Playlist in HTML oder Plaintext?
my $nocleanup = 0;
my $playlist = 0;
my $justplaylist = 0;

# Optionen auswerten
GetOptions(
        "sendung=s" => \$such_sendung,
        "senke=s" => \$senke,
        "outdir=s" => \$outdir,
        "nocleanup" => \$nocleanup,
        "justplaylist=s" => \$justplaylist,
        "playlist=s" => \$playlist,
        "help" => \$help,
        "quiet" => \$quiet,
);

if($help)
{
	print "BBC Radio Sendungen holen\n";
	print "Optionen:\n\t- sendung <Sendung> # Welche Sendung soll aufgenommen werden\n";
	print "\t\tDefault: Pipeline\n";
	print "\t\tWeitere Beispiele: Crunluath, Take the Floor, A' Mire ri Mòir\n";
	print "\t- nocleanup # Dateien nicht löschen\n";
	print "\t- justplaylist <Sendungs- ID># Nur die Playlist erstellen. Dateien liegen lokal vor.\n";
	print "\t- senke <Verzeichnis> # Verzeichnis der Dateien\n";
	print "\t- help # Diese Hilfe\n";
	print "\t- quiet # Sendung nicht aufnehmen, aber den Rest durchführen\n";
	exit;
}

my $logfile = "$senke/bbclog.txt";

Log::Log4perl->easy_init({ 
  file  => ">>$logfile", 
  level => $DEBUG,
});

DEBUG "SENDUNG: $such_sendung";
foreach my $arg (@ARGV)
{
	DEBUG "ARG: $arg\n";
}

sub     title2alias
{
        my ($title) = @_;
        $title =~ s/\'/\\\'/g;
        $title = lc($title);
        $title =~ s/\s/-/g;
        $title =~ s/\'//g;
        $title =~ s/\\//g;
        $title =~ s/://g;
        $title =~ s/,//g;
        $title =~ s/\.//g;
        $title =~ s/;//g;
        $title =~ s/\*//g;
        $title =~ s/ä/ae/g;
        $title =~ s/Ä/Ae/g;
        $title =~ s/ö/oe/g;
        $title =~ s/Ö/oe/g;
        $title =~ s/ü/ue/g;
        $title =~ s/Ü/ue/g;
        $title =~ s/ß/ss/g;
        $title =~ s/ò/o/g;
        $title =~ s/\(//g;
        $title =~ s/\)//g;
        $title =~ s/\[//g;
        $title =~ s/\]//g;
        $title =~ s/\{//g;
        $title =~ s/\}//g;
        # Als letztes: Anzahl Bindestriche reduzieren
        $title =~ s/--/-/g;

        return $title;
}

# Playlist erstellen
sub	playlist
{
	my ($fd, $playlisthtml, $sendungsid) = @_;

	my $letztezeile = 0;
	if(open(PLAYORI, "< $playlisthtml"))
	{
		my $found = 0;
		my $zeile;
		while(<PLAYORI>)
		{
			# Den Windows Zeilenvorschub entfernen
			$zeile = $_;
			$zeile =~ s/^M//g;
			# Anschliessend die Ausgabe wieder unterdrücken
			# Dieses sollte das Ende der Playlist in der HTML- Seite kennzeichnen
			if ($zeile && ($zeile =~ '</li></ul>'))
			{
				$found = 0;
			}
			# Die letzte Zeile der playlist mitnehmen
			if(!$found)
			{
				if($zeile =~ 'Title:')
				{
					$found ++;
					$letztezeile ++;
				}
			}
			# Playlist gefunden: Bearbeiten und ausgeben
			if($found)
			{
				if(!$htmlformat)
				{       # Plaintext
					$zeile =~ s/<br \/>/\n/g;
					$zeile =~ s/Title/\nStart: 00:00\nTitle/g;
					$zeile =~ s/TITLE/\nStart: 00:00\nTITLE/g;
					$zeile =~ s/TUNE/\nStart: 00:00\nTUNE/g;
				}
				else
				{       # HTML
					$zeile =~ s/<br \/>/<br \/>\n/g;        # Besser lesbar
					$zeile =~ s/Title/\n<I>Start: 00:00<\/I><BR \/>\nTitle/g;
					$zeile =~ s/TITLE/\n<I>Start: 00:00<\/I><BR \/>\nTITLE/g;
					$zeile =~ s/TUNE/\n<I>Start: 00:00<\/I><BR \/>\nTUNE/g;
				}
				if($letztezeile)
				{
					$found = 0;
					$zeile =~ s/<\/div><\/li><\/ul>//g;
				}
				print $fd "$zeile\n";
			}
			# Start der Playlist
			if($zeile)
			{
				if(
					($zeile =~ 'dc:title.*Playlist')
					|| ($zeile =~ 'dc:title.*PIPELINE')
					|| ($zeile =~ 'dc:title.*Music Detail')
				)
				{
					# Aktuelle Zeile auch ausgeben
					print $fd "$zeile\n";
					$found ++;
				}
				# Neuerdings sind die Einträge zeilenweise organisiert:
				elsif(
					($zeile =~ '^<p>Artist')
					|| ($zeile =~ '^<p>CD:')
					|| ($zeile =~ '^<p>Label:')
					|| ($zeile =~ '^<p>BBC recording')
					)
				{
					print $fd "$zeile\n";
				}
			}
		}

	}
	close(PLAYORI);

}

sub	bearbeite
{
	my ($id, $sendungsinfofile, $sendungsalias) = @_;

	#####################
	# Infos der Sendung einlesen
	####################
	my $sendung_desc = "<Beschreibung>";
	my $sendung_descshort = "";
	my $sendung_channel = "<Channel>";
	my $sendung_name = "<Title>";
	my $sendung_firstbcast = "<YYYY-MM-DD>";
	my $sendung_web = "";
	DEBUG("Infos der Sendung aus $sendungsinfofile einlesen");
	if(open(CFG, "< $sendungsinfofile"))
	{
		my      %config;
		while(<CFG>)
		{
			chomp;          # kein Newline
			s/#.*//;        # Keine Kommentare
			s/^\s+//;       # keine fuehrenden Whitepsaces
			s/\s+$//;       # keine anhaengenden Whitepsaces
			next unless length;     # Noch was da?
			my ($var, $value) = split(/\s*:\s*/, $_, 2);
			# my ($var, $value) = split(/\s*:\s*/, $_);
			$config{$var} = $value;
		}
		close (CFG);
		if($config{name}){$sendung_name = $config{name};DEBUG($config{name})};
		if($config{channel}){$sendung_channel = $config{channel};DEBUG($config{channel})};
		if($config{descshort}){$sendung_descshort = $config{descshort};DEBUG($config{descshort})};
		if($config{desc}){$sendung_desc = $config{desc};DEBUG($config{desc})};
		if($config{web}){$sendung_web = $config{web};DEBUG($config{web})};
		if($config{firstbcast})
		{
			my $dummy;
			($dummy, $sendung_firstbcast) = split /: /, $config{firstbcast};
			($sendung_firstbcast, $dummy) = split /T/, $sendung_firstbcast;
			DEBUG($config{desc});
		}
	}
	else
	{
	   ERROR "Kann $sendungsinfofile nicht lesen";
	}


	if($playlist)
	{
		####################
		# Playlist laden und als Textdatei speichern
		####################
		my $rc = 0;
		$rc = system("/usr/bin/wget -q -O $senke/$sendungsalias$id.html $sendung_web") unless $justplaylist; 
		DEBUG "Playlist laden: $sendung_web nach $senke/$sendungsalias$id.html $rc";
		# open(PLAYLIST, "> $outdir/log/$sendungsalias$id" . "_" . "$sendung_firstbcast.txt") or die "Kann Playlist nicht zum Schreiben oeffnen!";
		# ID herausgenommen
		open(PLAYLIST, "> $outdir/log/$sendungsalias" . "_" . "$sendung_firstbcast.txt") or die "Kann Playlist nicht zum Schreiben oeffnen!";

		####################
		# Titel der Sendung ausgeben
		####################
		print PLAYLIST "<H1>$sendung_name $sendung_firstbcast $sendung_descshort</H1>\n";
		print PLAYLIST "<I>$sendung_channel (ID: $id)</I><BR />\n";
		print PLAYLIST "\n$sendung_desc<BR />\n";
		print PLAYLIST "\n<hr id=\"system-readmore\" />\n";	# Hier für Joomla "Weiterlesen" nehmen


		####################
		# Playlist auslesen (Für Pipeline)
		####################
		my $fd = *PLAYLIST;
		playlist($fd, "$senke/$sendungsalias$id.html", $id);
	}

	####################
	# Aufräumen
	####################
	if(!$nocleanup)
	{
		unlink("$senke/$sendungsalias.txt");
		unlink("$senke/$sendungsalias$id.txt");
		unlink("$senke/$sendungsalias$id.html");
		unlink("$senke/$sendungsinfofile");
	}
	close(PLAYLIST);
}

if($justplaylist)
{
	bearbeite($justplaylist, "$senke/sendung$justplaylist.txt", "sendung");
}
else
{
	my $data = join '', <>;         # Eingabe ueber Datei oder stdin

	# Datei durchgehen
	for my $zeile (split /\n/, $data)
	{
		# if($zeile && !($zeile =~ '^INFO'))
		if($zeile && !($zeile =~ '^INFO') && !($zeile =~ '^Added:'))
		{
			my ($sendung, $sender, $kategorie) = split /, /, $zeile;
			# if($sender && $sendung && $sender =~ $such_sender && $sendung =~ $such_sendung)
			if($sender && $sendung =~ $such_sendung)
			{
				my $id;
				DEBUG "SENDUNG VOR SPLIT1: $sendung \n" unless $quiet;
				($id, $sendung) = split /:\s/, $sendung;
				my $datum;
				DEBUG "SENDUNG VOR SPLIT2: $sendung \n" unless $quiet;
				($sendung, $datum) = split /\s-\s/, $sendung;
				DEBUG "ID: $id DATUM: $datum SENDUNG: $sendung Ich nehme auf.\n" unless $quiet;
				#############################
				# Sendung "aufnehmen"
				#############################
				my $rc = system("/usr/local/bin/get_iplayer/get_iplayer --quiet --force --isodate --subdir --output $outdir --tag-fulltitle --command 'id3tag -g 80' --get $id") unless $quiet;
				DEBUG "Abschluss Aufnahme $id: $rc" unless $quiet;
				#############################
				# Detail- Infos in eine Sendungs- Datei schreiben
				#############################
				my $sendungsalias = title2alias($sendung);
				my $sendungsinfofile = "$senke/$sendungsalias$id.txt"; 
				DEBUG("Detail Infosschreiben nach $sendungsinfofile");
				$rc = system("/usr/local/bin/get_iplayer/get_iplayer --force --isodate --subdir --output $outdir --info $id > $sendungsinfofile");
				DEBUG "Abschluss Sendungsdatei $sendungsinfofile: $rc";

				bearbeite($id, $sendungsinfofile, $sendungsalias);
				# Jörn Droenner 01.01.2014
				# $sendung =~ s/\'//g;
				# # print "cd $outdir; git annex add $outdir\n";
				# $rc = system("cd $outdir; git annex add $outdir");
				# DEBUG "Abschluss git annex add $outdir  $rc";
				# # print "cd $outdir; git commit -a -m 'Aufnahme $sendung $datum $id'\n";
				# $rc = system("cd $outdir; git commit -a -m 'Aufnahme $sendung $datum $id'");
				# DEBUG "Abschluss git commit $sendung $datum $id:  $rc";
			}
		}
		else
		{
			DEBUG $zeile;
		}
	}
}
DEBUG "Fertig";
