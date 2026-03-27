# ERRATA — "Host is required" fix for coexist nodes

`zfs:` storage uses `zfs_truenas_*` keys but `TrueNAS::Client` only reads `truenas_*`.
Fix: add `_scfg_for_client` to `LunCmd/TrueNAS.pm` to merge the keys.

## Hand fix (any node)

```bash
# 1. Backup
cp -a /usr/share/perl5/PVE/Storage/LunCmd/TrueNAS.pm \
      /usr/share/perl5/PVE/Storage/LunCmd/TrueNAS.pm.bak.$(date +%Y%m%d%H%M%S)

# 2. Edit
nano /usr/share/perl5/PVE/Storage/LunCmd/TrueNAS.pm
```

**A) Add** this sub directly above `sub truenas_client_connect`:

```perl
sub _scfg_for_client {
    my ($scfg) = @_;
    return {
        %$scfg,
        truenas_apiv4_host => $scfg->{zfs_truenas_apiv4_host} // $scfg->{truenas_apiv4_host} // $scfg->{portal},
        truenas_apikey     => $scfg->{zfs_truenas_apikey}      // $scfg->{truenas_apikey},
        truenas_use_ssl    => $scfg->{zfs_truenas_use_ssl}     // $scfg->{truenas_use_ssl},
        truenas_user       => $scfg->{zfs_truenas_user}        // $scfg->{truenas_user},
        truenas_password   => $scfg->{zfs_truenas_password}    // $scfg->{truenas_password},
    };
}
```

**B) Replace** `sub truenas_client_connect` with:

```perl
sub truenas_client_connect {
    my ($scfg) = @_;
    my $cfg = _scfg_for_client($scfg);

    my $apihost = defined($cfg->{truenas_apiv4_host}) ? $cfg->{truenas_apiv4_host} : $cfg->{portal};

    if ( !defined $truenas_server_list->{$apihost} ) {
        $truenas_server_list->{$apihost} = TrueNAS::Client->new($cfg);
    }
    my $client = $truenas_server_list->{$apihost};
    my $result = $client->request('system.version');
    if ( $client->{has_error} ) {
        truenas_api_log_error();
        die "Unable to connect to the TrueNAS API service at '" . $client->{uri} . "'\n";
        return undef;
    }
    $truenas_client = $truenas_server_list->{$apihost};
    return $result;
}
```

**C) Replace** `sub truenas_client_init` with:

```perl
sub truenas_client_init {
    my ( $scfg, $timeout ) = @_;
    my $cfg = _scfg_for_client($scfg);
    my $result = {};
    my $apihost = defined($cfg->{truenas_apiv4_host}) ? $cfg->{truenas_apiv4_host} : $cfg->{portal};

    if ( !defined $truenas_server_list->{$apihost} ) {
        _log("Client initilizing", 'debug');
        $result = truenas_client_connect($scfg);
        _log( "Version: " . $result );
    }
    else {
        $truenas_client = $truenas_server_list->{$apihost};
        $truenas_client->set_target( $scfg->{target} );
        _log("Client initialized", 'debug');
    }

    $truenas_iscsi_global = $truenas_iscsi_global_list->{$apihost} =
      ( !defined( $truenas_iscsi_global_list->{$apihost} ) )
      ? $truenas_client->iscsi_global_config($cfg)
      : $truenas_iscsi_global_list->{$apihost};
    return;
}
```

```bash
# 3. Verify + restart
perl -c /usr/share/perl5/PVE/Storage/LunCmd/TrueNAS.pm
systemctl restart pvedaemon pvestatd pveproxy
```

## `storage.cfg` key names

| Storage type | Keys to use |
|---|---|
| `zfs:` + `iscsiprovider truenas` | `zfs_truenas_apiv4_host`, `zfs_truenas_apikey`, `zfs_truenas_use_ssl` |
| `truenas:` | `truenas_apiv4_host`, `truenas_apikey`, `truenas_use_ssl` |

## Restore

```bash
cp -a /usr/share/perl5/PVE/Storage/LunCmd/TrueNAS.pm.bak.TIMESTAMP \
      /usr/share/perl5/PVE/Storage/LunCmd/TrueNAS.pm
systemctl restart pvedaemon pvestatd pveproxy
```
