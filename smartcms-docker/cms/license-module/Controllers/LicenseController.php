<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\License;
use App\Models\LicenseActivation;
use App\Models\CmsUser;
use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Str;

class LicenseController extends Controller
{
    /**
     * GET /api/license/verify
     * Public endpoint - check if server has active license
     * Called BEFORE login on /license page
     */
    public function verify(Request $request): JsonResponse
    {
        $license = License::active()->first();

        if (!$license) {
            return response()->json([
                'licensed' => false,
                'message' => 'No active license found. Please contact super admin.',
            ], 200);
        }

        return response()->json([
            'licensed' => true,
            'company_name' => $license->company_name,
            'license_type' => $license->license_type,
            'expires_at' => $license->expires_at?->toISOString(),
            'max_extensions' => $license->max_extensions,
            'max_trunks' => $license->max_trunks,
            'max_call_servers' => $license->max_call_servers,
        ]);
    }

    /**
     * POST /api/license/activate
     * Activate a license key on this server
     * Only super_admin can do this
     */
    public function activate(Request $request): JsonResponse
    {
        $request->validate([
            'license_key' => 'required|string',
        ]);

        $license = License::where('license_key', $request->license_key)->first();

        if (!$license) {
            return response()->json([
                'success' => false,
                'message' => 'Invalid license key.',
            ], 404);
        }

        if (!$license->isValid()) {
            return response()->json([
                'success' => false,
                'message' => 'License is expired or inactive.',
            ], 403);
        }

        // Check hardware binding
        $hardwareId = $this->getHardwareId();
        if ($license->hardware_id && $license->hardware_id !== $hardwareId) {
            return response()->json([
                'success' => false,
                'message' => 'License is bound to a different server.',
            ], 403);
        }

        // Bind to this server if not bound yet
        if (!$license->hardware_id) {
            $license->update(['hardware_id' => $hardwareId]);
        }

        // Log activation
        LicenseActivation::create([
            'license_id' => $license->id,
            'activated_by' => $request->user()?->id,
            'ip_address' => $request->ip(),
            'hostname' => gethostname(),
            'hardware_id' => $hardwareId,
            'status' => 'activated',
            'activated_at' => now(),
        ]);

        return response()->json([
            'success' => true,
            'message' => 'License activated successfully.',
            'license' => [
                'company_name' => $license->company_name,
                'license_type' => $license->license_type,
                'allowed_modules' => $license->allowed_modules,
                'expires_at' => $license->expires_at?->toISOString(),
            ],
        ]);
    }

    /**
     * GET /api/license/modules
     * Get allowed modules for current user's license
     * Used by Angular to show/hide menu items
     */
    public function modules(Request $request): JsonResponse
    {
        $user = $request->user();

        // Super admin always gets all modules
        if ($user->is_super_admin) {
            return response()->json([
                'modules' => $this->getAllModules(),
                'license_type' => 'super_admin',
            ]);
        }

        // Get user's license
        $license = License::find($user->license_id);

        if (!$license || !$license->isValid()) {
            return response()->json([
                'modules' => ['dashboard'], // Minimal access
                'license_type' => 'none',
                'message' => 'License not available or expired.',
            ]);
        }

        return response()->json([
            'modules' => $license->allowed_modules ?? ['dashboard'],
            'license_type' => $license->license_type,
            'limits' => [
                'max_extensions' => $license->max_extensions,
                'max_trunks' => $license->max_trunks,
                'max_call_servers' => $license->max_call_servers,
            ],
        ]);
    }

    /**
     * POST /api/license/check-module
     * Check if specific module is accessible
     */
    public function checkModule(Request $request): JsonResponse
    {
        $request->validate(['module' => 'required|string']);

        $user = $request->user();

        if ($user->is_super_admin) {
            return response()->json(['allowed' => true]);
        }

        $license = License::find($user->license_id);

        if (!$license || !$license->isValid()) {
            return response()->json([
                'allowed' => false,
                'message' => 'License not available.',
            ]);
        }

        $allowed = $license->hasModule($request->module);

        return response()->json([
            'allowed' => $allowed,
            'message' => $allowed ? 'Access granted.' : 'License not available for this module.',
        ]);
    }

    // ========================================
    // SUPER ADMIN ONLY - License CRUD
    // ========================================

    /**
     * GET /api/licenses
     * List all licenses (super admin only)
     */
    public function index(Request $request): JsonResponse
    {
        $licenses = License::with(['creator', 'activations'])
            ->orderBy('created_at', 'desc')
            ->get()
            ->map(function ($license) {
                return [
                    'id' => $license->id,
                    'masked_key' => $license->masked_key,
                    'company_name' => $license->company_name,
                    'license_type' => $license->license_type,
                    'max_extensions' => $license->max_extensions,
                    'max_trunks' => $license->max_trunks,
                    'max_call_servers' => $license->max_call_servers,
                    'allowed_modules' => $license->allowed_modules,
                    'is_active' => $license->is_active,
                    'is_valid' => $license->isValid(),
                    'expires_at' => $license->expires_at?->toISOString(),
                    'created_at' => $license->created_at?->toISOString(),
                    'created_by' => $license->creator?->name,
                    'activations_count' => $license->activations->count(),
                ];
            });

        return response()->json(['data' => $licenses]);
    }

    /**
     * POST /api/licenses
     * Create new license (super admin only)
     */
    public function store(Request $request): JsonResponse
    {
        $request->validate([
            'company_name' => 'required|string|max:255',
            'license_type' => 'required|in:super_admin,admin,operator,viewer',
            'max_extensions' => 'required|integer|min:1',
            'max_trunks' => 'required|integer|min:0',
            'max_call_servers' => 'required|integer|min:1',
            'allowed_modules' => 'required|array',
            'allowed_modules.*' => 'string',
            'expires_at' => 'nullable|date|after:now',
        ]);

        // Generate unique license key
        $prefix = match ($request->license_type) {
            'super_admin' => 'SCMS-SA',
            'admin' => 'SCMS-AD',
            'operator' => 'SCMS-OP',
            'viewer' => 'SCMS-VW',
        };
        $licenseKey = $prefix . '-' . strtoupper(Str::random(4)) . '-' . strtoupper(Str::random(4)) . '-' . date('Y');

        $license = License::create([
            'license_key' => $licenseKey,
            'company_name' => $request->company_name,
            'license_type' => $request->license_type,
            'max_extensions' => $request->max_extensions,
            'max_trunks' => $request->max_trunks,
            'max_call_servers' => $request->max_call_servers,
            'allowed_modules' => $request->allowed_modules,
            'issued_at' => now(),
            'expires_at' => $request->expires_at,
            'is_active' => true,
            'created_by' => $request->user()->id,
        ]);

        return response()->json([
            'success' => true,
            'message' => 'License created successfully.',
            'data' => [
                'id' => $license->id,
                'license_key' => $licenseKey, // Show ONCE on creation
                'company_name' => $license->company_name,
                'license_type' => $license->license_type,
            ],
        ], 201);
    }

    /**
     * PUT /api/licenses/{id}
     * Update license (super admin only)
     */
    public function update(Request $request, int $id): JsonResponse
    {
        $license = License::findOrFail($id);

        $request->validate([
            'company_name' => 'sometimes|string|max:255',
            'max_extensions' => 'sometimes|integer|min:1',
            'max_trunks' => 'sometimes|integer|min:0',
            'max_call_servers' => 'sometimes|integer|min:1',
            'allowed_modules' => 'sometimes|array',
            'is_active' => 'sometimes|boolean',
            'expires_at' => 'nullable|date',
        ]);

        $license->update($request->only([
            'company_name',
            'max_extensions',
            'max_trunks',
            'max_call_servers',
            'allowed_modules',
            'is_active',
            'expires_at',
        ]));

        return response()->json([
            'success' => true,
            'message' => 'License updated.',
        ]);
    }

    /**
     * DELETE /api/licenses/{id}
     * Revoke license (super admin only)
     */
    public function destroy(int $id): JsonResponse
    {
        $license = License::findOrFail($id);

        // Don't delete, just deactivate
        $license->update(['is_active' => false]);

        // Log revocation
        LicenseActivation::create([
            'license_id' => $license->id,
            'status' => 'revoked',
            'activated_at' => now(),
        ]);

        return response()->json([
            'success' => true,
            'message' => 'License revoked.',
        ]);
    }

    // ========================================
    // Private helpers
    // ========================================

    private function getHardwareId(): string
    {
        // Generate hardware ID from system info
        $info = php_uname('n') . '|' . php_uname('m') . '|' . php_uname('r');
        return hash('sha256', $info);
    }

    private function getAllModules(): array
    {
        return [
            'dashboard', 'extensions', 'lines', 'vpws', 'cas', '3rd_party',
            'trunks', 'sbcs', 'inbound_routes', 'outbound_routes',
            'ring_groups', 'ivr', 'conferences', 'announcements',
            'recordings', 'time_conditions', 'blacklists', 'phone_directory',
            'firewall', 'static_routes', 'call_servers', 'customers',
            'head_offices', 'branches', 'sub_branches', 'cms_users',
            'cms_groups', 'turret_users', 'turret_groups', 'turret_policies',
            'turret_templates', 'sbc_routes', 'dahdi', 'intercoms',
            'activity_logs', 'system_logs', 'cdrs', 'usage_statistics',
            'settings', 'license_management',
        ];
    }
}
