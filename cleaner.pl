# github.com/cxmplex
# Deluge Slow Torrent Remover

my %local_collection;

local *get_deluge_info = sub {
    my $info = `deluge-console "connect 10.0.0.1:52757 user pass; info"`;
    my @collection;
    while ($info =~ /(?:Name:\s)(.+)\n(?:ID:\s)([a-z0-9]+)\n(?:State:\s)(.+)\n(?:Seeds:\s)(.+)\n(?:Size:\s)(.+)\n(?:Seed time:\s)(.+)\n(?:Tracker status:\s)(.+)/ig) {
        # this could be auto-gen by removing the non capture
        my %deluge_obj = (
            'name' => $1,
            'id' => $2,
            'state' => $3,
            'seeds' => $4,
            'size' => $5,
            'seed_time' => $6,
            'tracker_status' => $7,
        );

        # ignore incomplete
        next if ($state !~ /seeding/i);

        # set seed_time
        $deluge_obj{'seed_time'} =~ /^(\d+)\s([a-z]+)\s(?:([\d]+):(\d+):(\d+))/i;
        my %date = (
            'days' => $1,
            'hours' => $3,
            'minutes' => $4,
            'seconds' => $5 ,
        );
        $deluge_obj{'seed_time'} = \%date;

        # set Speed
        $deluge_obj{'state'} =~ /(?:Up Speed:\s)([\d\.]+)\s([a-z]+)/i;
        my %speed = (
            'speed' => 0,
            'unit' => '',
        );
        $speed{'speed'} = $1;
        $speed{'unit'} = $2;
        $deluge_obj{'speed'} = \%speed;

        push @collection, \%deluge_obj;
    }
    return \@collection;
};

# normalize to a base unit of MiB
local *normalize = sub {
    my $obj = shift;
    if ($obj->{'unit'} =~ /KiB/i) {
        return $obj->{'speed'} /= 1000;
    }
    return $obj->{'speed'};
};

local *update_local_info = sub {
    my $collection = shift;
    foreach(@$collection) {
        $obj = $_;
        next unless (length $obj->{'id'} > 0);
        if (!$local_collection{$obj->{'id'}}) {
            my %speeds = (
                'speeds' => [normalize($obj->{'speed'})],
                'seed_time' => $obj->{'seed_time'}
            );
            $local_collection{$obj->{'id'}} = \%speeds;
            next;
        }
        push @{$local_collection{$obj->{'id'}}->{'speeds'}}, normalize($obj->{'speed'});
        $local_collection{$obj->{'id'}}->{'seed_time'} = $obj->{'seed_time'};
    }
};

local *get_average = sub {
    my $objs = shift;
    my $total;
    my $n = 0;
    foreach(@$objs) {
        $total += $_;
        $n++;
    }
    return ($total/$n, $n);
};

local *get_slow_torrents = sub {
    my @slow;
    foreach(keys %local_collection) {
        my ($average, $n) = get_average($local_collection{$_}->{'speeds'});
        my $time = $local_collection{$_}->{'seed_time'}->{'minutes'};
        if ($n >= 5 && $average <= 10 && $time >= 5) {
            push @slow, $_;
            delete $local_collection{$_};
        }
    }
    return \@slow;
};

while (true) {
    my $collection = get_deluge_info();
    if ($collection) {
        update_local_info($collection);
    }
    my $delete_list = get_slow_torrents();
    foreach(@$delete_list) {
        print "Deleting $_ \n";
        my $output = `deluge-console "connect 10.0.0.1:52757 user pass; rm $_ --remove_data"`;
    }
    sleep 60;
}

