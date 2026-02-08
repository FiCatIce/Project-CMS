<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use App\Models\License;

class CheckLicense
{
    /**
     * Check if current user's license allows access to the requested module.
     * 
     * Usage in routes:
     *   Route::get('/extensions', ...)->middleware('license:extensions');
     *   Route::get('/trunks', ...)->middleware('license:trunks');
     */
    public function handle(Request $request, Closure $next, string $module = null)
    {
        $user = $request->user();

        if (!$user) {
            return response()->json([
                'error' => 'Unauthorized',
                'message' => 'Authentication required.',
            ], 401);
        }

        // Super admin bypasses all license checks
        if ($user->is_super_admin) {
            return $next($request);
        }

        // Get user's license
        $license = License::find($user->license_id);

        // No license assigned
        if (!$license) {
            return response()->json([
                'error' => 'License not available',
                'message' => 'No license assigned to your account. Contact super admin.',
                'code' => 'NO_LICENSE',
            ], 403);
        }

        // License expired or inactive
        if (!$license->isValid()) {
            return response()->json([
                'error' => 'License not available',
                'message' => 'Your license has expired or been deactivated.',
                'code' => 'LICENSE_INVALID',
            ], 403);
        }

        // Check specific module access
        if ($module && !$license->hasModule($module)) {
            return response()->json([
                'error' => 'License not available',
                'message' => "Your license does not include access to '{$module}'. Contact super admin.",
                'code' => 'MODULE_NOT_LICENSED',
                'module' => $module,
            ], 403);
        }

        // Inject license into request for downstream use
        $request->merge(['_license' => $license]);

        return $next($request);
    }
}
