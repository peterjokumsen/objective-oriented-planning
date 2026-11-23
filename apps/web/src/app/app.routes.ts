import { Route } from '@angular/router';
import { Tree } from './pages/tree';
import { ObjectiveDetail } from './pages/objective-detail';
import { Inbox } from './pages/inbox';
import { Participants } from './pages/participants';
import { ObserverPreview } from './pages/observer-preview';

export const appRoutes: Route[] = [
  { path: '', component: Tree },
  { path: 'objective/:id', component: ObjectiveDetail },
  { path: 'inbox', component: Inbox },
  { path: 'participants', component: Participants },
  { path: 'observer-preview', component: ObserverPreview },
];