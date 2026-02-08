<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class AsteriskRealtimeService
{
    /**
     * Create a PJSIP extension in the realtime DB.
     * Secret is auto-generated and NEVER returned to admin.
     *
     * @param array $data Extension data from CMS
     * @param string $type extension|line|vpw|cas|3rd_party
     * @return array Result with extension info (without secret)
     */
    public function createExtension(array $data, string $type = 'extension'): array
    {
        $extensionNumber = $data['extension'] ?? $data['number'];
        $name = $data['name'] ?? $extensionNumber;
        $callServerId = $data['call_server_id'] ?? null;

        // Auto-generate secret (32 chars, never shown to admin)
        $secret = $this->generateSecret();

        // Determine transport based on type
        $transport = $this->getTransport($type);

        // Determine context based on type
        $context = $this->getContext($type);

        // WebRTC settings for WSS transport
        $isWebRTC = ($transport !== 'transport-udp');

        DB::beginTransaction();

        try {
            // 1. Create ps_endpoints
            DB::table('ps_endpoints')->insert([
                'id' => $extensionNumber,
                'transport' => $transport,
                'aors' => $extensionNumber,
                'auth' => $extensionNumber,
                'context' => $context,
                'disallow' => 'all',
                'allow' => $isWebRTC ? 'opus,ulaw,alaw' : 'ulaw,alaw,g722',
                'direct_media' => 'no',
                'force_rport' => 'yes',
                'ice_support' => $isWebRTC ? 'yes' : 'no',
                'rewrite_contact' => 'yes',
                'rtp_symmetric' => 'yes',
                'dtmf_mode' => 'rfc4733',
                'use_avpf' => $isWebRTC ? 'yes' : 'no',
                'media_encryption' => $isWebRTC ? 'dtls' : 'no',
                'media_encryption_optimistic' => $isWebRTC ? 'yes' : 'no',
                'webrtc' => $isWebRTC ? 'yes' : 'no',
                'dtls_auto_generate_cert' => $isWebRTC ? 'yes' : 'no',
                'callerid' => "\"{$name}\" <{$extensionNumber}>",
                'mailboxes' => "{$extensionNumber}@default",
                'device_state_busy_at' => ($type === 'line') ? 0 : 1,
                'smartcms_type' => $type,
                'smartcms_call_server_id' => $callServerId,
                'smartcms_created_at' => now(),
                'smartcms_updated_at' => now(),
            ]);

            // 2. Create ps_auths
            DB::table('ps_auths')->insert([
                'id' => $extensionNumber,
                'auth_type' => 'userpass',
                'password' => $secret, // Stored in DB, never shown in CMS
                'username' => $extensionNumber,
            ]);

            // 3. Create ps_aors
            $maxContacts = match ($type) {
                'line' => 5,      // Lines can have multiple devices
                'vpw' => 2,       // VPW point-to-point
                'cas' => 1,       // CAS single channel
                default => 1,     // Extensions = 1 device
            };

            DB::table('ps_aors')->insert([
                'id' => $extensionNumber,
                'max_contacts' => $maxContacts,
                'remove_existing' => 'yes',
                'qualify_frequency' => 60,
                'qualify_timeout' => 3.0,
                'minimum_expiration' => 60,
                'default_expiration' => 3600,
                'maximum_expiration' => 7200,
            ]);

            DB::commit();

            // Reload PJSIP in Asterisk via AMI
            $this->reloadPjsip();

            Log::info("Extension created: {$extensionNumber} (type: {$type})");

            return [
                'success' => true,
                'extension' => $extensionNumber,
                'name' => $name,
                'type' => $type,
                'transport' => $transport,
                'context' => $context,
                // SECRET IS INTENTIONALLY NOT RETURNED
                'message' => 'Extension created. Secret auto-generated (not visible).',
            ];

        } catch (\Exception $e) {
            DB::rollBack();
            Log::error("Failed to create extension {$extensionNumber}: " . $e->getMessage());
            throw $e;
        }
    }

    /**
     * Create a Trunk or SBC in PJSIP realtime.
     *
     * @param array $data Trunk/SBC data
     * @param string $type trunk|sbc
     */
    public function createTrunk(array $data, string $type = 'trunk'): array
    {
        $name = $data['name'];
        $sipServer = $data['sip_server'];
        $sipPort = $data['sip_server_port'] ?? 5060;
        $authUsername = $data['auth_username'] ?? null;
        $secret = $data['secret'] ?? null;
        $context = ($type === 'sbc') ? 'from-pstn' : 'from-pstn';
        $codecs = $data['codecs'] ?? 'ulaw,alaw';
        $maxchans = $data['maxchans'] ?? 2;
        $registration = $data['registration'] ?? 'none';

        $trunkId = Str::slug($name, '_');

        DB::beginTransaction();

        try {
            // 1. Create endpoint for trunk
            DB::table('ps_endpoints')->insert([
                'id' => $trunkId,
                'transport' => 'transport-udp',
                'aors' => $trunkId,
                'auth' => $authUsername ? $trunkId : null,
                'outbound_auth' => $authUsername ? $trunkId : null,
                'context' => $context,
                'disallow' => 'all',
                'allow' => $codecs,
                'direct_media' => 'no',
                'force_rport' => 'yes',
                'ice_support' => 'no',
                'rewrite_contact' => 'yes',
                'rtp_symmetric' => 'yes',
                'dtmf_mode' => $data['dtmfmode'] ?? 'auto',
                'webrtc' => 'no',
                'use_avpf' => 'no',
                'media_encryption' => 'no',
                'from_domain' => $sipServer,
                'identify_by' => 'ip',
                'callerid' => $data['outcid'] ?? null,
                'smartcms_type' => $type,
                'smartcms_call_server_id' => $data['call_server_id'] ?? null,
                'smartcms_created_at' => now(),
                'smartcms_updated_at' => now(),
            ]);

            // 2. Create auth if credentials provided
            if ($authUsername && $secret) {
                DB::table('ps_auths')->insert([
                    'id' => $trunkId,
                    'auth_type' => 'userpass',
                    'password' => $secret,
                    'username' => $authUsername,
                ]);
            }

            // 3. Create AOR
            DB::table('ps_aors')->insert([
                'id' => $trunkId,
                'contact' => "sip:{$sipServer}:{$sipPort}",
                'qualify_frequency' => $data['qualify_frequency'] ?? 60,
                'qualify_timeout' => 3.0,
                'max_contacts' => 1,
            ]);

            // 4. Create IP identification
            DB::table('ps_endpoint_id_ips')->insert([
                'id' => $trunkId . '_ip',
                'endpoint' => $trunkId,
                'match' => $sipServer,
            ]);

            // 5. Create outbound registration if needed
            if ($registration !== 'none' && $authUsername) {
                DB::table('ps_registrations')->insert([
                    'id' => $trunkId,
                    'transport' => 'transport-udp',
                    'outbound_auth' => $trunkId,
                    'server_uri' => "sip:{$sipServer}:{$sipPort}",
                    'client_uri' => "sip:{$authUsername}@{$sipServer}:{$sipPort}",
                    'contact_user' => $authUsername,
                    'retry_interval' => 60,
                    'expiration' => 3600,
                    'line' => 'yes',
                    'endpoint' => $trunkId,
                ]);
            }

            DB::commit();
            $this->reloadPjsip();

            Log::info("Trunk/SBC created: {$trunkId} (type: {$type})");

            return [
                'success' => true,
                'trunk_id' => $trunkId,
                'name' => $name,
                'type' => $type,
                'sip_server' => $sipServer,
            ];

        } catch (\Exception $e) {
            DB::rollBack();
            Log::error("Failed to create trunk {$name}: " . $e->getMessage());
            throw $e;
        }
    }

    /**
     * Delete an extension/trunk from PJSIP realtime.
     */
    public function deleteEndpoint(string $id): bool
    {
        DB::beginTransaction();

        try {
            DB::table('ps_contacts')->where('endpoint', $id)->delete();
            DB::table('ps_endpoint_id_ips')->where('endpoint', $id)->delete();
            DB::table('ps_registrations')->where('id', $id)->delete();
            DB::table('ps_auths')->where('id', $id)->delete();
            DB::table('ps_aors')->where('id', $id)->delete();
            DB::table('ps_endpoints')->where('id', $id)->delete();

            DB::commit();
            $this->reloadPjsip();

            return true;
        } catch (\Exception $e) {
            DB::rollBack();
            Log::error("Failed to delete endpoint {$id}: " . $e->getMessage());
            return false;
        }
    }

    /**
     * Get extension status from Asterisk via AMI.
     */
    public function getEndpointStatus(string $extensionId): array
    {
        try {
            $response = $this->sendAmiCommand("pjsip show endpoint {$extensionId}");
            
            // Parse contact info for registration status
            $registered = str_contains($response, 'Avail');

            return [
                'extension' => $extensionId,
                'registered' => $registered,
                'raw' => $response,
            ];
        } catch (\Exception $e) {
            return [
                'extension' => $extensionId,
                'registered' => false,
                'error' => $e->getMessage(),
            ];
        }
    }

    /**
     * Get all registered endpoints.
     */
    public function getRegisteredEndpoints(): array
    {
        try {
            $response = $this->sendAmiCommand('pjsip show contacts');
            return ['raw' => $response];
        } catch (\Exception $e) {
            return ['error' => $e->getMessage()];
        }
    }

    // ========================================
    // Private helpers
    // ========================================

    /**
     * Generate a strong random secret (never shown to admin).
     */
    private function generateSecret(): string
    {
        return bin2hex(random_bytes(16)); // 32 hex chars
    }

    /**
     * Get transport based on extension type.
     * 3rd_party = UDP, everything else = WSS
     */
    private function getTransport(string $type): string
    {
        return match ($type) {
            '3rd_party' => 'transport-udp',
            'trunk', 'sbc' => 'transport-udp',
            default => 'transport-wss', // extension, line, vpw, cas
        };
    }

    /**
     * Get dialplan context based on type.
     */
    private function getContext(string $type): string
    {
        return match ($type) {
            'line' => 'from-internal',
            'vpw' => 'vpw',
            'cas' => 'from-internal',
            '3rd_party' => 'from-internal',
            'trunk', 'sbc' => 'from-pstn',
            default => 'from-internal',
        };
    }

    /**
     * Send AMI command to Asterisk.
     */
    private function sendAmiCommand(string $command): string
    {
        $host = config('asterisk.ami.host', 'asterisk');
        $port = config('asterisk.ami.port', 5038);
        $username = config('asterisk.ami.username', 'smartcms');
        $secret = config('asterisk.ami.secret', 'smartcms_ami_secret_2026');

        $socket = @fsockopen($host, $port, $errno, $errstr, 5);

        if (!$socket) {
            throw new \RuntimeException("Cannot connect to AMI: {$errstr}");
        }

        // Read greeting
        fgets($socket);

        // Login
        $loginCmd = "Action: Login\r\nUsername: {$username}\r\nSecret: {$secret}\r\n\r\n";
        fwrite($socket, $loginCmd);
        $this->readAmiResponse($socket);

        // Send command
        $actionCmd = "Action: Command\r\nCommand: {$command}\r\n\r\n";
        fwrite($socket, $actionCmd);
        $response = $this->readAmiResponse($socket);

        // Logoff
        fwrite($socket, "Action: Logoff\r\n\r\n");
        fclose($socket);

        return $response;
    }

    /**
     * Read AMI response until double newline.
     */
    private function readAmiResponse($socket): string
    {
        $response = '';
        $emptyLines = 0;

        stream_set_timeout($socket, 5);

        while (!feof($socket)) {
            $line = fgets($socket, 4096);

            if ($line === false) break;

            $response .= $line;

            if (trim($line) === '') {
                $emptyLines++;
                if ($emptyLines >= 1) break;
            } else {
                $emptyLines = 0;
            }
        }

        return $response;
    }

    /**
     * Reload PJSIP module in Asterisk.
     */
    private function reloadPjsip(): void
    {
        try {
            $this->sendAmiCommand('pjsip reload');
        } catch (\Exception $e) {
            Log::warning("Could not reload PJSIP: " . $e->getMessage());
        }
    }
}
