package App::Droplets;

use 5.010;
use File::Spec;
use File::Basename;
use Expect;
use Config::Tiny;
use UUID::Tiny qw(:std);
use WebService::DigitalOcean;
use Data::Dump::Color;

our $VERSION = '0.07.2';

#
# methods
#
sub new {
    my ($class, %args) = @_;

    my $self = bless {}, $class;
    $self->{opts} = $args{opts};

    return $self;
}

sub run {
    my $self = shift;
    my $opt  = $self->{opts};

    $opt = $self->configure($opt);
    my $token = $self->get_token($opt);
 
    my $do_obj = WebService::DigitalOcean->new({ token => $token });

    ## make sure the token is valid before performing any method calls
    my $auth = $self->_confirm_authentication($do_obj);
    unless (defined $auth && $auth eq 'success') {
	say "\nERROR: Could not authenticate API token: $token\nCheck that the token is valid. Exiting.\n";
	exit(1);
    }
    
    if ($opt->{available}) {
	$self->report_available($do_obj, $opt->{available});
    }
    
    if ($opt->{running}) {
	$self->get_droplets($do_obj);
	exit(0);
    }

    my $server_addr = $self->create_droplet($do_obj, $config, $opt) if $opt->{create};

    if ($opt->{login} || $opt->{logon}) {
	my ($cmd, $serverid);
	if (@{$opt->{serverid}}) { 
	    if (@{$opt->{serverid}} == 1) {
		$serverid = shift @{$opt->{serverid}};
	    }
	    elsif (@{$opt->{serverid}} > 1) { 
		say "\nERROR: Only one server ID may be given with the '--login' option to avoid unexpected results. ".
		    "Check the '--serverid' arguments. Exiting.\n";
		exit(1);
	    }
	}

	my $user = $opt->{username} // 'root';
	my $ip = defined $serverid ? $self->get_address_for_droplet($do_obj, $serverid) : $server_addr;
	$cmd = sprintf "ssh $user@%s", $ip;
	my $ssh = Expect->new;
	$ssh->raw_pty(1);
	$ssh->slave->clone_winsize_from(\*STDIN);
	$ssh->spawn($cmd);
	$ssh->interact();
	$ssh->close();
    }

    if ($opt->{destroy}) {
	my @ids = @{$opt->{serverid}};
	$self->destroy_droplet($do_obj, \@ids);
    }

    if ($opt->{destroyall}) {
	$self->destroy_all($do_obj);
    }
}

sub configure {
    my $self = shift;
    my ($opt) = @_;

    my $conf_file = File::Spec->catfile($ENV{HOME}, '.droplets');
    if (-e $conf_file) {
	my $config = Config::Tiny->read( $conf_file, 'utf8' );
	return $opt if defined $config->{droplets}->{api_token};
    }
    elsif (defined $opt->{configfile}) {
	my $config = Config::Tiny->read( $opt->{configfile}, 'utf8' );
	return $opt if defined $config->{droplets}->{api_token};
    }
    else {
	print STDERR "\nApp::Droplets is not configured. Please provide your API token: ";
	my $token = <STDIN>;
	chomp $token;
	open my $out, '>', $conf_file;
	say $out "[droplets]";
	say $out "api_token = $token";
	close $out;

	$opt->{configfile} = $conf_file;
	return $opt;
    }
}

sub get_token {
    my $self = shift;
    my ($opt) = @_;

    $opt->{configfile} //= File::Spec->catfile($ENV{HOME}, '.droplets');
    my $config = Config::Tiny->read( $opt->{configfile}, 'utf8' );

    unless (defined $config->{droplets}->{api_token}) {
	say "\nERROR: The configuration is not formatted correctly. Exiting.\n";
	exit(1);
    }
    
    return $config->{droplets}->{api_token};
}

sub destroy_all {
    my $self = shift;
    my ($do_obj) = @_;

    my $droplets = $do_obj->droplet_list();

    my @ids;
    if ($droplets->{meta}{total} > 0) {
	for my $drop (@{$droplets->{content}}) {
	    if (defined $drop) {
		for my $ip (@{$drop->{networks}{v4}}) {
		    push @ids, $drop->{id};
		}
	    }
	}
    }

     $self->destroy_droplet($do_obj, \@ids);
}

sub destroy_droplet {
    my $self = shift;
    my ($do_obj, $ids) = @_;

    unless (@$ids) {
	say "\nERROR: Need at least 1 server ID to call destroy method. Exiting.\n";
	exit(1);
    }
    
    say "====> Before destroy...";
    $self->get_droplets($do_obj);
    for my $id (@$ids) {
	if (defined $id) {
	    $do_obj->droplet_delete($id);
	}
    }
    sleep 10;
    say "====> After destroy...";
    $self->get_droplets($do_obj);
}

sub create_droplet {
    my $self = shift;
    my ($do_obj, $config, $opt) = @_;

    my $ssh_id = $self->get_keys($config);
    $opt->{region}  //= 'sfo1';        # San Francisco
    $opt->{size}    //= '512mb';       # 512MB
    $opt->{name}    //= create_uuid_as_string(UUID_V1);
    $opt->{imageid} //= 17384153;      # CentOS 7.2 x64
    
    my $t0 = time;
    my $droplet = $do_obj->droplet_create({
	name     => $opt->{name},
	size     => $opt->{size},
	image    => $opt->{imageid},
	region   => $opt->{region},
	ssh_keys => [ $ssh_id ],
    });
    my $t1 = time;

    sleep 5;
    my $success = $self->_check_droplet_params($droplet);
    if ($success) {
	my $server = $do_obj->droplet_get($droplet->{content}{id});
	my $ip = $self->get_address_for_droplet($do_obj, $server->{content}{id});
        
	say "---------------------------------------------------";
	say "Created Droplet:         ", $server->{content}{id}; 
	say "Droplet name:            ", $server->{content}{name}; 
	say "Distribution:            ", $server->{content}{image}{distribution}.q{ }.$server->{content}{image}{name};
	say "Region:                  ", $server->{content}{region}{name};
	say "Disk:                    ", $server->{content}{size}{disk};
	say "Memory:                  ", $server->{content}{size_slug};
	say "CPUs:                    ", $server->{content}{vcpus};
	say "Server IP:               ", $ip;
	say "Creation time (seconds): ", $t1-$t0;
	say "---------------------------------------------------";

	return $server->{content}{networks}{v4}[0]{ip_address};
    }
}

sub report_available {
    my $self = shift;
    my ($obj, $available) = @_;

    my %disp = (
	'sizes'   => sub { $self->get_sizes($obj)   },
	'images'  => sub { $self->get_images($obj)  },
	'regions' => sub { $self->get_regions($obj) },
    );

    if (defined $available && exists $disp{$available}) {
	$disp{$available}->();
    }
    else {
	say STDERR "\nERROR: '$available' is not recognized. ".
	    "Argument must be one of: sizes, images, or regions. Exiting.\n";
	exit(1);
    }
    
    exit(0);
}
	
	
sub get_sizes {
    my $self = shift;
    my ($do_obj) = @_;
    
    my $sizes = $do_obj->size_list();
    
    say join "\t", "Name", "Disk_space", "Memory", "CPUs", "Cost_per_month", "Cost_per_hour", "Regions";
    for my $s (@{$sizes->{content}}) {
	say join "\t", $s->{slug}, $s->{disk}, $s->{memory}, $s->{vcpus}, 
	    $s->{price_monthly}, $s->{price_hourly}, join ',', @{$s->{regions}};
    }

    exit(0);
}

sub get_regions {
    my $self = shift;
    my ($do_obj) = @_;

    my $region_id;
    my $regions = $do_obj->region_list();
    
    say join "\t", "Name", "Slug", "Sizes";
    for my $r (@{$regions->{content}}) {
	say join "\t", $r->{name}, $r->{slug}, join ',', @{$r->{sizes}};
    }

    exit(0);
}

sub get_images {
    my $self = shift;
    my ($do_obj) = @_;
    
    my $image_id;
    my $images = $do_obj->image_list();

    say join "\t", "Distribution", "ID", "Name";
    for my $img (@{$images->{content}}) {
	say join "\t", $img->{distribution}, $img->{id}, $img->{name};
    }

    exit(0);
}

sub get_keys {
    my $self = shift;
    my ($config) = @_;

    ## this creates a new key fingerprint
    my $key = File::Spec->catfile($ENV{HOME}, '.ssh', 'id_rsa.pub');
    my $cmd = "ssh-keygen -lf $key";
    my $out = qx($cmd);
    chomp $out;
    my ($bits, $fingerprint, $identity) = split /\s+/, $out;

    return $fingerprint;
}

sub get_address_for_droplet {
    my $self = shift;
    my ($do_obj, $id) = @_;

    my $sid = ref($id) ? shift(@$id) : $id;

    my $server = $do_obj->droplet_get($sid);
    my $ip = $server->{content}{networks}{v4}[0]{ip_address};
    
    return $ip;
}

sub get_droplets {
    my $self = shift;
    my ($do_obj) = @_;

    my $droplets = $do_obj->droplet_list();

    my @ips;
    if ($droplets->{meta}{total} > 0) {
	say "Running Droplets: ";
	for my $drop (@{$droplets->{content}}) {
	    if (defined $drop) {
		for my $ip (@{$drop->{networks}{v4}}) {
		    printf "Droplet %s has id %s, IP address %s, Gateway %s, and Netmask %s\n", 
	            $drop->{name}, $drop->{id}, $ip->{ip_address}, $ip->{gateway}, $ip->{netmask};
		}
	    }
	}
    }
    else {
	say "No running droplets.";
    }
}

sub _confirm_authentication {
    my $self = shift;
    my ($do_obj) = @_;

    my $content = $do_obj->region_list->{content};

    if (ref($content) eq 'HASH') {
	if (defined $content->{id} && $content->{id} eq 'unauthorized') { # && 
	    #defined $content->{message} && $content->{message} eq 'Unable to authenticate you.') {
	    return undef;
	}
    }
    else {
	return 'success';
    }
}

sub _check_droplet_params {
    my $self = shift;
    my ($do_obj) = @_;

    if ($do_obj->{content}{id} eq 'unprocessable_entity') {
	say STDERR "\nERROR: There appears to be an error with the input parameters.\n";
	say STDERR "Here is the message: ",$do_obj->{content}{message};
	exit(1);
    }
    else {
	return 1;
    }
}

1;

__END__

=head1 NAME 
                                                                       
App::Droplets - Create, destroy, inspect, and log on to your droplets from the command line

=head1 SYNOPSIS    

  ## get the available image sizes
  droplets --available sizes

  # get the available distributions
  droplets --available images
    Distribution  ID          Name
    CoreOS        12789350    723.3.0 (beta)
    CentOS        6372321     5.10 x64
    CentOS        6372425     5.10 x32
    Debian        6372581     6.0 x64
    Debian        6372662     6.0 x32
    Fedora        9640922     21 x64
    FreeBSD       10144573    10.1
    Ubuntu        10321756    12.04.5 x64
    Ubuntu        10321777    12.04.5 x32
    Debian        10322059    7.0 x64
    Debian        10322378    7.0 x32
    CentOS        10322623    7 x64
    Fedora        12065782    22 x64
    Ubuntu        12658446    15.04 x64
    Ubuntu        12660649    15.04 x32
    Debian        12778278    8.1 x64
    Debian        12778337    8.1 x32
    CoreOS        13068283    723.3.0 (stable)
    Ubuntu        13089493    14.04 x64
    Ubuntu        13089823    14.04 x32

  ## Create a droplet (in this case, Fedora 22)
  droplets --imageid 12065782 --create

  ## Check all running droplets
  droplets --running

  ## destroy one specific droplet
  droplets --destroy --serverid 6588509

  ## destroy numerous droplets in one go                                                                                                droplets --destroy --serverid 6588509 6588510 6588511

  ## Create a droplet, with defaults, and log on to it
  droplets --create --login

  ## Destroy all running droplets
  droplets --destroyall

=head1 DESCRIPTION
     
 This is a command-line tool for DigitalOcean's REST API called droplets. After setting up an API key on the DigitalOcean website, you can check on all your existing droplets, query the available droplet sizes and prices by region, create new droplets, or log on to droplets (either existing droplets or ones you just created) without leaving the command line. 
=head1 LICENSE
 
The MIT License should included with the project. If not, it can be found at: http://opensource.org/licenses/mit-license.php

Copyright (C) 2015-2016 S. Evan Staton

=cut
