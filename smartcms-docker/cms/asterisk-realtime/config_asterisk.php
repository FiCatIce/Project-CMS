<?php

return [
    /*
    |--------------------------------------------------------------------------
    | Asterisk AMI Configuration
    |--------------------------------------------------------------------------
    */
    'ami' => [
        'host' => env('AMI_HOST', '127.0.0.1'),
        'port' => (int) env('AMI_PORT', 5038),
        'username' => env('AMI_USERNAME', 'smartcms'),
        'secret' => env('AMI_SECRET', 'smartcms_ami_secret_2026'),
        'timeout' => (int) env('AMI_TIMEOUT', 5),
    ],

    /*
    |--------------------------------------------------------------------------
    | Asterisk ARI Configuration
    |--------------------------------------------------------------------------
    */
    'ari' => [
        'host' => env('ARI_HOST', '127.0.0.1'),
        'port' => (int) env('ARI_PORT', 8088),
        'username' => env('ARI_USERNAME', 'smartcms'),
        'password' => env('ARI_PASSWORD', 'smartcms_ari_secret_2026'),
        'scheme' => env('ARI_SCHEME', 'http'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Extension Types & Transport Mapping
    |--------------------------------------------------------------------------
    */
    'transports' => [
        'extension' => 'transport-wss',
        'line' => 'transport-wss',
        'vpw' => 'transport-wss',
        'cas' => 'transport-wss',
        '3rd_party' => 'transport-udp',
        'trunk' => 'transport-udp',
        'sbc' => 'transport-udp',
    ],

    /*
    |--------------------------------------------------------------------------
    | Extension Type Contexts
    |--------------------------------------------------------------------------
    */
    'contexts' => [
        'extension' => 'from-internal',
        'line' => 'from-internal',
        'vpw' => 'vpw',
        'cas' => 'from-internal',
        '3rd_party' => 'from-internal',
        'trunk' => 'from-pstn',
        'sbc' => 'from-pstn',
    ],
];
