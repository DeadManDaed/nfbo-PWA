// service-worker.js - NBFO PWA Offline Support
const CACHE_VERSION = 'nbfo-v1.0.0';
const ASSETS_CACHE = `${CACHE_VERSION}-assets`;
const DATA_CACHE = `${CACHE_VERSION}-data`;

// Fichiers à mettre en cache au premier chargement
const STATIC_ASSETS = [
  '/',
  '/index.html',
  '/dashboard.html',
  '/manifest.json',
  '/js/auth.js',
  '/js/common.js',
  '/js/app.js',
  '/js/admission.js',
  '/js/audits.js',
  '/js/stock-utils.js',
  '/js/ui-utils.js',
  '/js/db-local.js',
  '/js/api-mock.js',
  '/icons/icon-192x192.png',
  '/icons/icon-512x512.png',
  'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css',
  'https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js'
];

// Installation du Service Worker
self.addEventListener('install', (event) => {
  console.log('[SW] Installation en cours...');
  event.waitUntil(
    caches.open(ASSETS_CACHE).then((cache) => {
      console.log('[SW] Mise en cache des assets statiques');
      return cache.addAll(STATIC_ASSETS.map(url => new Request(url, { cache: 'reload' })));
    })
  );
  self.skipWaiting(); // Active immédiatement
});

// Activation et nettoyage des anciens caches
self.addEventListener('activate', (event) => {
  console.log('[SW] Activation du Service Worker');
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName !== ASSETS_CACHE && cacheName !== DATA_CACHE) {
            console.log('[SW] Suppression ancien cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
  return self.clients.claim();
});

// Stratégie de cache pour les requêtes
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Stratégie 1: Cache First pour les assets statiques
  if (STATIC_ASSETS.includes(url.pathname) || url.pathname.match(/\.(css|js|png|jpg|jpeg|svg|woff2?)$/)) {
    event.respondWith(
      caches.match(request).then((cachedResponse) => {
        return cachedResponse || fetch(request).then((response) => {
          return caches.open(ASSETS_CACHE).then((cache) => {
            cache.put(request, response.clone());
            return response;
          });
        });
      })
    );
    return;
  }

  // Stratégie 2: Network First pour les requêtes API
  if (url.pathname.startsWith('/api/')) {
    event.respondWith(
      fetch(request)
        .then((response) => {
          // Clone pour mettre en cache
          const responseClone = response.clone();
          caches.open(DATA_CACHE).then((cache) => {
            cache.put(request, responseClone);
          });
          return response;
        })
        .catch(() => {
          // Si offline, on retourne depuis le cache
          return caches.match(request).then((cachedResponse) => {
            if (cachedResponse) {
              console.log('[SW] Requête API servie depuis le cache (mode offline)');
              return cachedResponse;
            }
            // Si pas de cache, on retourne une réponse d'erreur propre
            return new Response(
              JSON.stringify({ error: 'Mode hors ligne - Données non disponibles' }),
              { 
                status: 503, 
                headers: { 'Content-Type': 'application/json' }
              }
            );
          });
        })
    );
    return;
  }

  // Stratégie 3: Network Only pour le reste
  event.respondWith(fetch(request));
});

// Gestion des messages depuis l'application
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
  
  if (event.data && event.data.type === 'CLEAR_CACHE') {
    event.waitUntil(
      caches.keys().then((cacheNames) => {
        return Promise.all(cacheNames.map(name => caches.delete(name)));
      }).then(() => {
        console.log('[SW] Cache vidé avec succès');
        event.ports[0].postMessage({ success: true });
      })
    );
  }
});

// Synchronisation en arrière-plan (optionnel)
self.addEventListener('sync', (event) => {
  if (event.tag === 'sync-data') {
    event.waitUntil(syncDataToServer());
  }
});

async function syncDataToServer() {
  // TODO: Implémenter la logique de synchronisation
  console.log('[SW] Synchronisation des données...');
}

console.log('[SW] Service Worker NBFO initialisé');
