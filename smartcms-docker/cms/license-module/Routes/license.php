<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\LicenseController;

/*
|--------------------------------------------------------------------------
| License Routes
|--------------------------------------------------------------------------
|
| These routes should be added to your routes/api.php
|
*/

// ============================================================
// PUBLIC ROUTES (no auth required)
// Called on /license page before login
// ============================================================
Route::prefix('license')->group(function () {
    // Check if server has valid license
    Route::get('/verify', [LicenseController::class, 'verify']);
    
    // Activate a license key
    Route::post('/activate', [LicenseController::class, 'activate']);
});

// ============================================================
// AUTHENTICATED ROUTES
// ============================================================
Route::middleware('auth:sanctum')->group(function () {
    
    // Get allowed modules for current user
    Route::get('/license/modules', [LicenseController::class, 'modules']);
    
    // Check specific module access
    Route::post('/license/check-module', [LicenseController::class, 'checkModule']);

    // ============================================================
    // SUPER ADMIN ONLY - License management
    // ============================================================
    Route::middleware('super_admin')->group(function () {
        Route::apiResource('licenses', LicenseController::class);
    });

    // ============================================================
    // LICENSE-PROTECTED MODULE ROUTES
    // Example of how to protect existing routes:
    // ============================================================
    
    // Extensions (license: extensions)
    // Route::middleware('license:extensions')->group(function () {
    //     Route::apiResource('extensions', ExtensionController::class);
    // });

    // Trunks (license: trunks)
    // Route::middleware('license:trunks')->group(function () {
    //     Route::apiResource('trunks', TrunkController::class);
    // });

    // Lines (license: lines)
    // Route::middleware('license:lines')->group(function () {
    //     Route::apiResource('lines', LineController::class);
    // });

    // ... add middleware('license:module_name') to each route group
});

/*
|--------------------------------------------------------------------------
| REGISTER MIDDLEWARE
|--------------------------------------------------------------------------
|
| Add to app/Http/Kernel.php in $middlewareAliases:
|
|   'license' => \App\Http\Middleware\CheckLicense::class,
|   'super_admin' => \App\Http\Middleware\SuperAdmin::class,
|
*/
