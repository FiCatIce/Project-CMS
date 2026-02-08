FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV ASTERISK_VERSION=21.7.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential wget curl ca-certificates gnupg pkg-config \
    aptitude git python3 python3-dev file subversion autoconf automake libtool \
    libedit-dev libjansson-dev libxml2-dev libsqlite3-dev \
    libssl-dev libncurses5-dev uuid-dev libsrtp2-dev \
    libspandsp-dev libcurl4-openssl-dev libnewt-dev \
    libpopt-dev libical-dev libiksemel-dev libsnmp-dev \
    libunbound-dev libspeex-dev libspeexdsp-dev \
    libresample1-dev libopus-dev liburiparser-dev \
    unixodbc unixodbc-dev odbc-mariadb libmariadb-dev \
    sox net-tools iputils-ping tcpdump procps \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src
RUN wget -q https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-${ASTERISK_VERSION}.tar.gz \
    && tar xzf asterisk-${ASTERISK_VERSION}.tar.gz \
    && rm asterisk-${ASTERISK_VERSION}.tar.gz

WORKDIR /usr/src/asterisk-${ASTERISK_VERSION}

RUN apt-get update && apt-get install -y aptitude \
    && yes | contrib/scripts/install_prereq install \
    && rm -rf /var/lib/apt/lists/*

RUN ./configure \
    --with-pjproject-bundled --with-jansson-bundled \
    --with-crypto --with-ssl --with-srtp \
    --with-unixodbc --with-opus \
    --with-resample --with-speex --with-speexdsp \
    --with-libedit --libdir=/usr/lib/x86_64-linux-gnu

RUN make menuselect.makeopts \
    && menuselect/menuselect \
        --enable res_pjsip --enable res_pjsip_authenticator_digest \
        --enable res_pjsip_caller_id --enable res_pjsip_diversion \
        --enable res_pjsip_dtmf_info \
        --enable res_pjsip_endpoint_identifier_anonymous \
        --enable res_pjsip_endpoint_identifier_ip \
        --enable res_pjsip_endpoint_identifier_user \
        --enable res_pjsip_exten_state --enable res_pjsip_header_funcs \
        --enable res_pjsip_logger --enable res_pjsip_messaging \
        --enable res_pjsip_mwi --enable res_pjsip_nat \
        --enable res_pjsip_notify \
        --enable res_pjsip_outbound_authenticator_digest \
        --enable res_pjsip_outbound_registration \
        --enable res_pjsip_path --enable res_pjsip_pubsub \
        --enable res_pjsip_refer --enable res_pjsip_registrar \
        --enable res_pjsip_rfc3326 --enable res_pjsip_sdp_rtp \
        --enable res_pjsip_session \
        --enable res_pjsip_transport_websocket \
        --enable res_odbc --enable res_config_odbc \
        --enable cdr_odbc --enable func_odbc --enable cel_odbc \
        --enable res_http_websocket --enable app_mixmonitor \
        --enable res_ari --enable res_ari_channels \
        --enable res_ari_bridges --enable res_ari_endpoints \
        --enable res_ari_events --enable res_stasis \
        --enable codec_opus --enable codec_speex \
        --enable codec_resample --enable codec_g722 \
        --enable CORE-SOUNDS-EN-ULAW --enable CORE-SOUNDS-EN-ALAW \
        --enable MOH-OPSOUND-ULAW \
        menuselect.makeopts

RUN make -j$(nproc) && make install && make samples \
    && make config && make install-logrotate && ldconfig

RUN rm -rf /usr/src/asterisk*

RUN groupadd -r asterisk 2>/dev/null || true \
    && useradd -r -g asterisk -d /var/lib/asterisk -s /bin/false asterisk 2>/dev/null || true \
    && mkdir -p /var/run/asterisk \
    && chown -R asterisk:asterisk /etc/asterisk /var/lib/asterisk \
       /var/log/asterisk /var/spool/asterisk /var/run/asterisk /usr/lib/asterisk 2>/dev/null || true


RUN apt-get update && apt-get install -y --no-install-recommends \
    liburiparser1 libsrtp2-1 libspandsp2 libiksemel3 libunbound8 \
    libcap2 libcap2-bin \
    libspeex1 libspeexdsp1 libresample1 libopus0 libical3 \
    libpopt0 libnewt0.52 unixodbc odbc-mariadb libmariadb3 \
    && rm -rf /var/lib/apt/lists/*
RUN ln -sf /usr/lib/x86_64-linux-gnu/asterisk /usr/lib/asterisk
COPY configs/ /etc/asterisk/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chown -R asterisk:asterisk /etc/asterisk

EXPOSE 5060/udp 5060/tcp 5061/tcp 8088/tcp 8089/tcp 5038/tcp
EXPOSE 10000-20000/udp

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD asterisk -rx "core show channels" || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["asterisk", "-fvvvg", "-c"]
