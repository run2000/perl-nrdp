#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use LWP::Simple;
use LWP::UserAgent;
use File::Basename;
use Sys::Hostname;

Getopt::Long::Configure ("bundling");

# Process command line switch input.
sub proc_input {
	my($strHostname, $strService, $strState, $strOutput, $bCheckType) = @_;
	
	my $xmlBuilder = "<?xml version='1.0'?>\n<checkresults>\n";
	if (!$strService) {
		$xmlBuilder .= generate_host_check($strHostname, $strState, $strOutput, $bCheckType);
	} else {
		$xmlBuilder .= generate_service_check($strHostname, $strService, $strState, $strOutput, $bCheckType);
	}
	$xmlBuilder .= "</checkresults>";
	return $xmlBuilder;
}

# Process either XML or other formatted file.
sub proc_file {
	my($strFile,$chrDelim) = @_;
	if (-e $strFile) {
		my ($fDir, $fName, $fExt) = fileparse($strFile, qr/\.[^.]*/);
		my $xmlBuilder;
		my $intLineCount = 1;
		open(FILE, $strFile);
		while (<FILE>) {
			if ($fExt =~ m/\.xml/i) {
				$xmlBuilder .= $_;
			} else {
				if (!$xmlBuilder) {
					$xmlBuilder = "<?xml version='1.0'?>\n<checkresults>\n";
				}
				my $line = $_;
				$line =~ s/^\s+|\s+$//g;
				my @aryLine = split($chrDelim, $line);
				if (scalar(@aryLine) == 4) {
					my($strHostname, $strState, $strOutput, $bCheckType) = @aryLine;
					$xmlBuilder .= generate_host_check($strHostname, $strState, $strOutput, $bCheckType);
				} elsif (scalar(@aryLine) == 5) {
					my($strHostname, $strService, $strState, $strOutput, $bCheckType) = @aryLine;
					$xmlBuilder .= generate_service_check($strHostname, $strService, $strState, $strOutput, $bCheckType);
				} else {
					print "Line $intLineCount is incorrectly formatted, can't parse fields\n";
					$intLineCount++;
					next; 
				}
			}
		}
		close(FILE);
		if (!($fExt =~ m/\.xml/i)) {
			$xmlBuilder .= "</checkresults>";
		}
        return $xmlBuilder;	
	} else {
		print "Unable to find the specified file.\n";
		exit;
	}
}

# Process input from STDIN.
sub proc_terminal {
	my $chrDelim = $_[0];
	print "Enter check details: \n";
	my $stdRead = <>;
	$stdRead =~ s/^\s+|\s+$//g;
	my @aryInput = split($chrDelim, $stdRead);
	my $xmlBuilder = "<?xml version='1.0'?>\n<checkresults>\n";
	if (scalar(@aryInput) == 4) {
        	my($strHostname, $strState, $strOutput, $bCheckType) = @aryInput;
            $xmlBuilder .= generate_host_check($strHostname, $strState, $strOutput, $bCheckType);
        } elsif (scalar(@aryInput) == 5) {
            my($strHostname, $strService, $strState, $strOutput, $bCheckType) = @aryInput;
            $xmlBuilder .= generate_service_check($strHostname, $strService, $strState, $strOutput, $bCheckType);
        } else {
            print "Input is incorrectly formatted, can't parse fields\n";
			help();
        }
	$xmlBuilder .= "</checkresults>";
    return $xmlBuilder;
}

# Build a single service-check XML element.
sub generate_service_check {
	my($strHostname, $strService, $strState, $strOutput, $bCheckType) = @_;
	my $intState = validate_state($strState);
	(my $xmlBuilder = <<CHECKXML) =~ s/^\s+//gm;
		<checkresult type='service' checktype='$bCheckType'>
			<hostname>$strHostname</hostname>
			<servicename>$strService</servicename>
			<state>$intState</state>
			<output>$strOutput</output>
		</checkresult>
CHECKXML
	return $xmlBuilder;
}

# Build a single host-check XML element.
sub generate_host_check {
	my($strHostname,  $strState, $strOutput, $bCheckType) = @_;
	my $intState = validate_state($strState);
	(my $xmlBuilder = <<CHECKXML) =~ s/^\s+//gm;
		<checkresult type='service' checktype='$bCheckType'>
			<hostname>$strHostname</hostname>
			<state>$intState</state>
			<output>$strOutput</output>
		</checkresult>
CHECKXML
	return $xmlBuilder;
}

sub validate_state {
	my $strState = $_[0];
	my %hshValidStates = (
                'OK' => 0,
                'WARNING' => 1,
                'CRITICAL' => 2,
                'UNKNOWN' => 3);

	$strState = uc($strState);
	if (! exists $hshValidStates{$strState}) {
			print "Invalid state specified.\n";
			help();
	}

	return $hshValidStates{$strState};
}

sub post_data {
	my($strURL, $strToken, $xmlPost) = @_;
	my $httpAgent = LWP::UserAgent->new;
	
	my $httpResponse = $httpAgent->post( $strURL,
	[
		'token' => $strToken,
		'cmd' => 'submitcheck',
		'XMLDATA' => $xmlPost
	],);
	
	if (!$httpResponse->is_success) {
		print "ERROR - NRDP Returned: " . $httpResponse->status_line . " " . $httpResponse->content;
	}
	print "$xmlPost\n\n" . $httpResponse->is_success . "\n" . $httpResponse->status_line . "\n" . $httpResponse->content . "\n";
	exit;
}

sub help {
	my $strVersion = "v1.2 b250313";
	my $strNRDPVersion = "1.2";
	print "\nPerl NRDP sender version: $strVersion for NRDP version: $strNRDPVersion\n";
	print "By John Murphy <john.murphy\@roshamboot.org>, GNU GPL License\n";
	print "\nUsage: ./perl_nrdp.pl -u <Nagios NRDP URL> -t <Token> [-H <Hostname> -S <State> -o <Information|Perfdata> [-s <service name> -c <0/1>] | -f <File path> [-d <Field delimiter>] | -i [-d <Field delimiter> ]]\n\n";
	print <<HELP;
-u, --url
	The URL used to access the remote NRDP agent. i.e. http://nagiosip/nrdp/
-t, --token
	The authentication token used to access the remote NRDP agent.
-H, --hostname
	The name of the host associated with the passive host/service check result. 
	This script will attempt to learn the hostname if not supplied.
-s, --service
	For service checks, the name of the service associated with the passive check result.
-S, --state
	The state of the host or service. Valid values are: OK, CRITICAL, WARNING, UNKNOWN
-o, --output
	Text output to be sent as the passive check result.
-d, --delim
	Used to set the text field delimiter when using non-XML file input or command-line input. 
	Defaults to tab (\\t).
-c, --checktype
	Used to specify active or passive, 0 = active, 1 = passive. Defaults to passive.
-f, --file
	Use this switch to specify the full path to a file to read. There are two usable formats:
	1. A field-delimited text file, where the delimiter is specified by -d
	2. An XML file in NRDP input format. An example can be found by browsing to the NRDP API URL. 
-i, --input
	This switch specifies that you wish to input the check via standard input on the command line.
-h, --help
	Display this help text.
	
HELP
	exit;
}

##############################################
##
## BEGIN MAIN
##
##############################################

# Initialize and read user input
my ($strURL, $strToken, $strHostname, $strService, $strState, $strOutput, $chrDelim, $bCheckType, $strFile, $oHelp, $stdReadTerm);
$oHelp = undef;
$stdReadTerm = undef;
$chrDelim = undef;

GetOptions("u=s" => \$strURL, 		"url=s" => \$strURL,
           "t=s" => \$strToken, 	"token=s" => \$strToken,
           "H=s" => \$strHostname, 	"hostname=s" => \$strHostname,
           "s=s" => \$strService, 	"service=s" => \$strService,
           "S=s" => \$strState, 	"state=s" => \$strState,
           "o=s" => \$strOutput, 	"output=s" => \$strOutput,
           "d=s" => \$chrDelim, 	"delim=s" => \$chrDelim,
           "c=i" => \$bCheckType, 	"checktype=i" => \$bCheckType,
           "f=s" => \$strFile, 		"file=s" => \$strFile,
		   "i" => \$stdReadTerm,	"input" => \$stdReadTerm,
	       "h" => \$oHelp, 			"help" => \$oHelp) or help();

if (defined $oHelp) {
	help();
}

if (!$strURL || !$strToken) {
    print "You must set a URL and Token.\n";
    help();
}

# Can't accept newline chars as a delimiter and escape punctuation chars so regex doesn't interpret them literally.
if (!$chrDelim) {
    $chrDelim = "\t";
} elsif ($chrDelim =~ m/\r|\n/) {
	print "Can't use new line character as a field separator.\n";
	help();
} elsif ($chrDelim =~ m/^[[:punct:]]{1}$/) {
	$chrDelim = "\\" . $chrDelim;
}

if (!$bCheckType) {
    $bCheckType = 1;
}

if (!$strHostname) {
	$strHostname = hostname() or die "Unable to determine hostname, please enter manually";
}

# Depending on user options build the XML doc to post.
my $xmlPost;
if ($strFile) {
    $xmlPost = proc_file($strFile, $chrDelim);
} elsif (defined $stdReadTerm) {
	$xmlPost = proc_terminal($chrDelim);
} elsif ($strHostname && $strState && $strOutput) {
    $xmlPost = proc_input($strHostname, $strService, $strState, $strOutput, $bCheckType);
} else {
    print "Incorrect options set.\n";
    help();
}

# Post data via NRDP API to Nagios.
if ($xmlPost) {
    post_data($strURL, $strToken, $xmlPost);
} else {
    print "Something has gone horribly wrong! XML build failed, bailing out...";
}
exit;
