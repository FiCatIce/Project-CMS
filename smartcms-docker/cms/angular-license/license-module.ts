// ============================================================
// FILE: src/app/core/services/license.service.ts
// Angular License Service - manages module access
// ============================================================

import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { BehaviorSubject, Observable, of } from 'rxjs';
import { tap, catchError, map } from 'rxjs/operators';
import { environment } from '../../../environments/environment';

export interface LicenseInfo {
  licensed: boolean;
  company_name?: string;
  license_type?: string;
  expires_at?: string;
  max_extensions?: number;
  max_trunks?: number;
  max_call_servers?: number;
}

export interface ModuleAccess {
  modules: string[];
  license_type: string;
  limits?: {
    max_extensions: number;
    max_trunks: number;
    max_call_servers: number;
  };
}

@Injectable({ providedIn: 'root' })
export class LicenseService {
  private apiUrl = `${environment.apiUrl}/api`;
  private modulesSubject = new BehaviorSubject<string[]>([]);
  private licenseTypeSubject = new BehaviorSubject<string>('none');

  modules$ = this.modulesSubject.asObservable();
  licenseType$ = this.licenseTypeSubject.asObservable();

  constructor(private http: HttpClient) {}

  /**
   * Check if server has active license (called on /license page, before login)
   */
  verifyLicense(): Observable<LicenseInfo> {
    return this.http.get<LicenseInfo>(`${this.apiUrl}/license/verify`);
  }

  /**
   * Activate a license key
   */
  activateLicense(licenseKey: string): Observable<any> {
    return this.http.post(`${this.apiUrl}/license/activate`, { license_key: licenseKey });
  }

  /**
   * Load allowed modules for current user (called after login)
   */
  loadModules(): Observable<ModuleAccess> {
    return this.http.get<ModuleAccess>(`${this.apiUrl}/license/modules`).pipe(
      tap((response) => {
        this.modulesSubject.next(response.modules);
        this.licenseTypeSubject.next(response.license_type);
      }),
      catchError((error) => {
        console.error('Failed to load license modules:', error);
        this.modulesSubject.next(['dashboard']);
        this.licenseTypeSubject.next('none');
        return of({ modules: ['dashboard'], license_type: 'none' });
      })
    );
  }

  /**
   * Check if specific module is allowed
   */
  hasModule(module: string): boolean {
    const modules = this.modulesSubject.value;
    return modules.includes(module);
  }

  /**
   * Check if user is super admin
   */
  isSuperAdmin(): boolean {
    return this.licenseTypeSubject.value === 'super_admin';
  }

  /**
   * Get current modules
   */
  getModules(): string[] {
    return this.modulesSubject.value;
  }
}


// ============================================================
// FILE: src/app/core/guards/license.guard.ts
// Angular Route Guard - blocks access to unlicensed modules
// ============================================================

import { Injectable } from '@angular/core';
import {
  CanActivate,
  ActivatedRouteSnapshot,
  Router,
  UrlTree,
} from '@angular/router';
import { Observable, of } from 'rxjs';
import { map, take } from 'rxjs/operators';
import { LicenseService } from '../services/license.service';

@Injectable({ providedIn: 'root' })
export class LicenseGuard implements CanActivate {
  constructor(
    private licenseService: LicenseService,
    private router: Router
  ) {}

  canActivate(route: ActivatedRouteSnapshot): Observable<boolean | UrlTree> {
    const requiredModule = route.data['module'] as string;

    if (!requiredModule) {
      return of(true); // No module restriction
    }

    // Super admin bypasses
    if (this.licenseService.isSuperAdmin()) {
      return of(true);
    }

    // Check module access
    if (this.licenseService.hasModule(requiredModule)) {
      return of(true);
    }

    // Module not licensed - redirect with message
    console.warn(`License not available for module: ${requiredModule}`);
    
    // Navigate to a "license not available" page or show alert
    return of(this.router.createUrlTree(['/license-required'], {
      queryParams: { module: requiredModule }
    }));
  }
}


// ============================================================
// FILE: src/app/core/guards/license-page.guard.ts
// Guard for /license page - redirect if already licensed
// ============================================================

import { Injectable } from '@angular/core';
import { CanActivate, Router, UrlTree } from '@angular/router';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';
import { LicenseService } from '../services/license.service';

@Injectable({ providedIn: 'root' })
export class LicensePageGuard implements CanActivate {
  constructor(
    private licenseService: LicenseService,
    private router: Router
  ) {}

  canActivate(): Observable<boolean | UrlTree> {
    return this.licenseService.verifyLicense().pipe(
      map((info) => {
        if (info.licensed) {
          // Already licensed, go to login
          return this.router.createUrlTree(['/login']);
        }
        return true; // Show license page
      })
    );
  }
}


// ============================================================
// USAGE IN ROUTING MODULE:
// src/app/app-routing.module.ts
// ============================================================
/*
const routes: Routes = [
  // License page (before login)
  {
    path: 'license',
    component: LicensePageComponent,
    canActivate: [LicensePageGuard],
  },

  // Login page
  {
    path: 'login',
    component: LoginComponent,
  },

  // Protected routes with license check
  {
    path: '',
    component: LayoutComponent,
    canActivate: [AuthGuard],
    children: [
      { path: 'dashboard', component: DashboardComponent, data: { module: 'dashboard' }, canActivate: [LicenseGuard] },
      { path: 'extensions', component: ExtensionsComponent, data: { module: 'extensions' }, canActivate: [LicenseGuard] },
      { path: 'lines', component: LinesComponent, data: { module: 'lines' }, canActivate: [LicenseGuard] },
      { path: 'vpws', component: VpwsComponent, data: { module: 'vpws' }, canActivate: [LicenseGuard] },
      { path: 'cas', component: CasComponent, data: { module: 'cas' }, canActivate: [LicenseGuard] },
      { path: '3rd-party', component: ThirdPartyComponent, data: { module: '3rd_party' }, canActivate: [LicenseGuard] },
      { path: 'trunks', component: TrunksComponent, data: { module: 'trunks' }, canActivate: [LicenseGuard] },
      { path: 'sbcs', component: SbcsComponent, data: { module: 'sbcs' }, canActivate: [LicenseGuard] },
      // ... semua route lainnya dengan data: { module: 'xxx' }

      // License management (super admin only)
      { path: 'license-management', component: LicenseManagementComponent, data: { module: 'license_management' }, canActivate: [LicenseGuard] },
    ],
  },

  // License not available page
  {
    path: 'license-required',
    component: LicenseRequiredComponent,
  },
];
*/


// ============================================================
// SIDEBAR MENU FILTERING:
// In your sidebar component, filter menu items based on license
// ============================================================
/*
// sidebar.component.ts
export class SidebarComponent implements OnInit {
  menuItems: MenuItem[] = [];
  
  constructor(private licenseService: LicenseService) {}

  ngOnInit() {
    this.licenseService.modules$.subscribe(modules => {
      this.menuItems = this.allMenuItems.filter(item => 
        modules.includes(item.module)
      );
    });
  }

  allMenuItems: MenuItem[] = [
    { label: 'Dashboard', icon: 'dashboard', route: '/dashboard', module: 'dashboard' },
    { label: 'Extensions', icon: 'phone', route: '/extensions', module: 'extensions' },
    { label: 'Lines', icon: 'line', route: '/lines', module: 'lines' },
    { label: 'VPW', icon: 'vpw', route: '/vpws', module: 'vpws' },
    { label: 'CAS', icon: 'cas', route: '/cas', module: 'cas' },
    { label: '3rd Party', icon: 'device', route: '/3rd-party', module: '3rd_party' },
    { label: 'Trunks', icon: 'trunk', route: '/trunks', module: 'trunks' },
    { label: 'SBCs', icon: 'sbc', route: '/sbcs', module: 'sbcs' },
    // ... etc
  ];
}
*/
