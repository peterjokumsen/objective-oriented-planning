import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

@Injectable({ providedIn: 'root' })
export class HealthService {
  private http = inject(HttpClient);
  check(): Observable<{ status: string }> {
    return this.http.get<{ status: string }>('/api/health');
  }
}
EOF
echo done