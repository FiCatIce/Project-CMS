<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class LicenseActivation extends Model
{
    protected $table = 'license_activations';

    public $timestamps = false;

    protected $fillable = [
        'license_id',
        'activated_by',
        'ip_address',
        'hostname',
        'hardware_id',
        'status',
        'activated_at',
        'deactivated_at',
    ];

    protected $casts = [
        'activated_at' => 'datetime',
        'deactivated_at' => 'datetime',
    ];

    public function license()
    {
        return $this->belongsTo(License::class);
    }
}
