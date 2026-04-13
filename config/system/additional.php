<?php

use Undkonsorten\TYPO3AutoLogin\Service\AutomaticAuthenticationService;

$trustAnyProxy = filter_var(
    getenv('TYPO3_TRUST_ANY_PROXY') ?: false,
    FILTER_VALIDATE_BOOLEAN
);

if (getenv('IS_DDEV_PROJECT') == 'true') {
    $GLOBALS['TYPO3_CONF_VARS'] = array_replace_recursive(
        $GLOBALS['TYPO3_CONF_VARS'],
        [
            // This GFX configuration allows processing by installed ImageMagick 6
            'GFX' => [
                'processor' => 'ImageMagick',
                'processor_path' => '/usr/bin/',
                'processor_path_lzw' => '/usr/bin/',
            ],
            // This mail configuration sends all emails to mailpit
            'MAIL' => [
                'transport' => 'smtp',
                'transport_smtp_encrypt' => false,
                'transport_smtp_server' => 'localhost:1025',
            ],
            'SYS' => [
                'trustedHostsPattern' => '.*.*',
                'devIPmask' => '*',
                'displayErrors' => 1,
            ],
        ]
    );
}

if ($trustAnyProxy) {
    $GLOBALS['TYPO3_CONF_VARS'] = array_replace_recursive(
        $GLOBALS['TYPO3_CONF_VARS'],
        [
            'SYS' => [
                'reverseProxyIP' => '*',
                'reverseProxySSL' => '*',
                'reverseProxyHeaderMultiValue' => 'first',
                'trustedHostsPattern' => '.*',
            ],
        ]
    );
}

if (\TYPO3\CMS\Core\Core\Environment::getContext()->isDevelopment()) {
    putenv(AutomaticAuthenticationService::TYPO3_AUTOLOGIN_USERNAME_ENVVAR . '=admin');
    \Undkonsorten\TYPO3AutoLogin\Utility\RegisterServiceUtility::registerAutomaticAuthenticationService();
}
