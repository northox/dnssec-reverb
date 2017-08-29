# dnssec-reverb
Shell script based DNSSEC key management tool - easy to audit

## Features
TODO

## Requirements
- ldns from NLnet labs
- standard unix tools such as sed

## Installation
1. Copy dnssec-reverb into some directory.

    `$ sudo cp dnssec-reverb /var/nsd/zones/master`

2. Create dnssec-reverb.conf into the same directory of dnssec-reverb.

    if you want to change the default values.
    `touch /var/nsd/zones/master/dnssec-reverb.conf`

3. Prepare traditional zone files. File name should be equal to zone name.

    `/var/nsd/zones/master/example.com`

4. Generate first key and sign zone.

    `./dnssec-reverb keygen example.com`
    `./dnssec-reverb sign example.com`

5. Edit named.conf/nsd.conf to load signed zone file

    ```
    zone "example.com" {
        type master;
        file "/var/nsd/zones/master/example.com.signed";
    }
    ```

## Configuration

dnssec-reverb.conf:

- MASTERDIR: Zone file directory | Default: MASTERDIR="/etc/namedb/master"
- KSK_PARAM: Default dnssec-keygen's options for KSK | Default: KSK_PARAM_DEFAULT="-a ECDSAP256SHA256 -k"
- KSK_PARAM_$zone: dnssec-keygen's options for zone's KSK | Default: KSK_PARAM
- ZSK_PARAM: Default dnssec-keygen's options for ZSK | Default: ZSK_PARAM_DEFAULT="-a ECDSAP256SHA256"
- ZSK_PARAM_$zone: dnssec-keygen's options for zone's ZSK | Default: ZSK_PARAM
- SIGN_PARAM: Default dnssec-signzone options | Default: SIGN_PARAM_DEFAULT="-n"
- SIGN_PARAM_$zone: dnssec-signzone options for zone | Default: SIGN_PARAM
- DS_PARAM:  Default dsfromkey options for zone | Default: SIGN_PARAM_DEFAULT="-2"
- DS_PARAM_$zone: dsfromkey options for zone | Default: SIGN_PARAM

- keygen: dnssec-keygen path | Default: keygen="/usr/local/bin/ldns-keygen"
- signzone: dnssec-signzone path | Default: signzone="/usr/local/bin/ldns-signzone"
- dsfromkey: dnssec-dsfromkey path | Default: dsfromkey="/usr/local/bin/ldns-key2ds-n"

- CONFIGDIR: directory where dnssec-reverb store it's state/data | Default: CONFIGDIR="$MASTERDIR/dnsec-reverb-db"
- **TODO** RELOADALL_COMMAND: reload all command | Default: none

Caution: All zone name must be lowercase. $zone is zone name whose '.' and '-' characters are replaced by '_'.

## Usage

usage: dnssec-reverb keygen <zone>
       dnssec-reverb rmkeys <zone>

       dnssec-reverb [-s] ksk-add <zone>
       dnssec-reverb [-s] ksk-roll <zone>

       dnssec-reverb [-s] zsk-add <zone>
       dnssec-reverb [-s] zsk-roll <zone>
       dnssec-reverb [-s] zsk-rmold <zone>

       dnssec-reverb sign <zone>
       dnssec-reverb status <zone>

### Initial setup - assuming your zone has no DNSSEC keys published
1. Generate KSK and ZSK 

    `dnssec-reverb keygen example.org`

2. Retrieve your fresh KSK and setup the DS at your registrar

    `dnssec-reverb status example.org`
    Use the information displayed and use it with your DNSSEC compliant domain registrar. 

3. Sign zone using keys generated in step #1 

    `dnssec-reverb sign example.org`

## Rollover of the KSK
TODO

## Rollover of the ZSK

### Manual
1. Add next ZSK for future ZSK rollover (publish the upcomming ZSK and sign with active key) 

    `dnssec-reverb --sign zsk-add example.org`

2. ZSK rollover (set the published but latent ZSK created at step #3 as the active ZSK) 

    `dnssec-reverb -s zsk-roll example.org`

3. ZSK remove old (remove the old ZSK from your records)

    `dnssec-reverb zsk-roll example.org`
    `dnssec-reverb sign example.org`

### Automated
Set something similar in your crontab. This will roll the ZSK at a 4 months interval by adding the new ZSK one month ahead before publishing it and removing the old one one month later.
```
0       6       1       feb,jun,oct *   dnssec-reverb -s zsk-add example.org
0       6       1       mar,jul,nov *   dnssec-reverb -s zsk-roll example.org
0       6       1       apr,aug,dec *   dnssec-reverb -s zsk-rmold example.org
```

## License
Simplified BSD

## Source
https://github.com/northox/dnssec-reverb

## Acknowledgements
This code is based on @kfujiwara [work's](https://github.com/kfujiwara/dnsseczonetool).

# Author(s)
Danny Fullerton - Mantor Organization
