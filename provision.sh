#!/bin/sh

ASTERISK="asterisk-13.24.1"

set -e

export DEBIAN_FRONTEND=noninteractive

if [ ! -e /var/tmp/apt-update-done ]; then
	echo "*** Updating packages"
	echo 'DPkg::options { "--force-confdef"; };' >>/etc/apt/apt.conf.d/70debconf
	apt update
	apt install -y netselect-apt
	netselect-apt -so /etc/apt/sources.list
	apt update
	apt upgrade -y
	touch /var/tmp/apt-update-done
fi

if [ ! -e "/var/tmp/${ASTERISK}.tar.gz" ]; then
	echo "*** Downloading Asterisk 13 source"
	wget --no-verbose \
		-O /var/tmp/${ASTERISK}.tar.gz \
	https://downloads.asterisk.org/pub/telephony/asterisk/${ASTERISK}.tar.gz ||
	wget --no-verbose \
		-O /var/tmp/${ASTERISK}.tar.gz \
	https://downloads.asterisk.org/pub/telephony/asterisk/old-releases/${ASTERISK}.tar.gz
fi

mkdir -p /root/src/asterisk
cd /root/src/asterisk

if [ ! -e "${ASTERISK}" ]; then
	echo "*** Unpacking Asterisk source"
	tar xzf "/var/tmp/${ASTERISK}.tar.gz"
fi

cd "${ASTERISK}"

if [ ! -e config.status ]; then
    echo "*** Installing prerequisite packages"
    # extracted from contrib/scripts/install_prereq
    # libmysqlclient-dev has been renamed libmysqlclient-dev
    # libosptk-dev is gone
    apt install -y \
            build-essential pkg-config \
            libedit-dev libjansson-dev libsqlite3-dev uuid-dev libxml2-dev \
            libspeex-dev libspeexdsp-dev libogg-dev libvorbis-dev libasound2-dev portaudio19-dev libcurl4-openssl-dev xmlstarlet bison flex \
            libpq-dev unixodbc-dev libneon27-dev libgmime-2.6-dev liblua5.2-dev liburiparser-dev libxslt1-dev libssl-dev \
            libvpb-dev default-libmysqlclient-dev libbluetooth-dev libradcli-dev freetds-dev libjack-jackd2-dev bash \
            libsnmp-dev libiksemel-dev libcorosync-common-dev libcpg-dev libcfg-dev libnewt-dev libpopt-dev libical-dev libspandsp-dev \
            libresample1-dev libc-client2007e-dev binutils-dev libsrtp0-dev libsrtp2-dev libgsm1-dev doxygen graphviz zlib1g-dev libldap2-dev \
            wget subversion \
            bzip2 patch python-dev \
            libpjproject-dev
    echo "*** Running configure"
    ./configure
    make menuselect.makeopts
    menuselect/menuselect --disable BUILD_NATIVE menuselect.makeopts
fi

if [ ! -e /root/src/asterisk/asterisk-Softmodem ]; then
    echo "*** Adding softmodem"
    (
            cd ..
            git clone https://github.com/proquar/asterisk-Softmodem.git
            cp asterisk-Softmodem/app_softmodem.c "${ASTERISK}/apps/"
    )
fi

echo "*** Building Asterisk"
make

echo "*** Installing Asterisk"
make install

echo "*** Install Sample Config"
#make samples

echo "*** Configuring System for Asterisk"
adduser --system --quiet --group asterisk
for i in /var/lib /var/log /var/run /var/spool; do
	mkdir -p ${i}/asterisk
	chown -R asterisk:asterisk ${i}/asterisk
done

cat >/etc/systemd/system/asterisk.service <<'EOF'
[Unit]
Description=Asterisk PBX And Telephony Daemon
After=network.target

[Service]
User=asterisk
Group=asterisk
Environment=HOME=/var/lib/asterisk
WorkingDirectory=/var/lib/asterisk
ExecStart=/usr/sbin/asterisk -f -C /etc/asterisk/asterisk.conf
ExecStop=/usr/sbin/asterisk -rx 'core stop now'
ExecReload=/usr/sbin/asterisk -rx 'core reload'

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable asterisk

echo "*** Creating Configuration"
cat >/etc/asterisk/modules.conf <<'EOF'
[modules]
autoload=no
load=app_exec
load=app_playback
load=app_softmodem
load=chan_pjsip
load=chan_rtp
load=codec_a_mu
load=codec_adpcm
load=codec_alaw
load=codec_gsm
load=codec_resample
load=codec_ulaw
load=format_gsm
load=format_pcm
load=format_wav_gsm
load=func_dialplan
load=func_sorcery
load=pbx_config
load=res_pjproject
load=res_pjsip
load=res_pjsip_authenticator_digest
load=res_pjsip_dtmf_info
load=res_pjsip_endpoint_identifier_anonymous
load=res_pjsip_endpoint_identifier_ip
load=res_pjsip_endpoint_identifier_user
load=res_pjsip_logger
load=res_pjsip_registrar
load=res_pjsip_sdp_rtp
load=res_pjsip_session
load=res_rtp_asterisk
load=res_sorcery_astdb
load=res_sorcery_config
load=res_sorcery_memory
load=res_sorcery_memory_cache
load=res_sorcery_realtime
EOF

cat >/etc/asterisk/extensions.conf <<'EOF'
[from-internal]
exten = 100,1,Answer()
same = n,Wait(1)
same = n,Playback(hello-world)
same = n,Hangup()

exten = 01910,1,Answer()
same = n,Softmodem(btx.hanse.de,20000,v(V23)ld(8)s(1))
same = n,Hangup()
EOF

cat >/etc/asterisk/pjsip.conf <<'EOF'
[transport-udp]
type=transport
protocol=udp
bind=0.0.0.0

[general]
allow = !all,alaw,ulaw

[6001]
type=endpoint
context=from-internal
disallow=all
allow=ulaw
auth=6001
aors=6001

[6001]
type=auth
auth_type=userpass
password=unsecurepassword
username=6001

[6001]
type=aor
max_contacts=1
EOF

echo "*** starting Asterisk"
systemctl start asterisk

echo "*** Done"
