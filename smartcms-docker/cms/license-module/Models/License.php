<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class License extends Model
{
    protected $table = 'licenses';

    protected $fillable = [
        'license_key',
        'company_name',
        'license_type',
        'max_extensions',
        'max_trunks',
        'max_call_servers',
        'allowed_modules',
        'hardware_id',
        'issued_at',
        'expires_at',
        'is_active',
        'created_by',
    ];

    protected $casts = [
        'allowed_modules' => 'array',
        'is_active' => 'boolean',
        'issued_at' => 'datetime',
        'expires_at' => 'datetime',
        'max_extensions' => 'integer',
        'max_trunks' => 'integer',
        'max_call_servers' => 'integer',
    ];

    protected $hidden = [
        'license_key', // Never expose full key in API responses
    ];

    /**
     * Check if license is valid (active + not expired)
     */
    public function isValid(): bool
    {
        if (!$this->is_active) {
            return false;
        }

        if ($this->expires_at && $this->expires_at->isPast()) {
            return false;
        }

        return true;
    }

    /**
     * Check if a specific module is allowed
     */
    public function hasModule(string $module): bool
    {
        if ($this->license_type === 'super_admin') {
            return true;
        }

        $modules = $this->allowed_modules ?? [];
        return in_array($module, $modules);
    }

    /**
     * Check if extension limit reached
     */
    public function canCreateExtension(int $currentCount): bool
    {
        return $currentCount < $this->max_extensions;
    }

    /**
     * Check if trunk limit reached
     */
    public function canCreateTrunk(int $currentCount): bool
    {
        return $currentCount < $this->max_trunks;
    }

    /**
     * Check if call server limit reached
     */
    public function canCreateCallServer(int $currentCount): bool
    {
        return $currentCount < $this->max_call_servers;
    }

    /**
     * Get masked license key for display
     */
    public function getMaskedKeyAttribute(): string
    {
        $key = $this->license_key;
        if (strlen($key) <= 8) {
            return str_repeat('*', strlen($key));
        }
        return substr($key, 0, 4) . str_repeat('*', strlen($key) - 8) . substr($key, -4);
    }

    /**
     * Relationships
     */
    public function activations()
    {
        return $this->hasMany(LicenseActivation::class);
    }

    public function creator()
    {
        return $this->belongsTo(CmsUser::class, 'created_by');
    }

    public function users()
    {
        return $this->hasMany(CmsUser::class);
    }

    /**
     * Scopes
     */
    public function scopeActive($query)
    {
        return $query->where('is_active', true)
            ->where(function ($q) {
                $q->whereNull('expires_at')
                    ->orWhere('expires_at', '>', now());
            });
    }

    public function scopeSuperAdmin($query)
    {
        return $query->where('license_type', 'super_admin');
    }
}
