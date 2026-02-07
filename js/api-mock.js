// js/api-mock.js - API Mock pour PWA Standalone (remplace les appels serveur)
(function () {
  'use strict';

  // Interception de tous les appels fetch vers /api/*
  const originalFetch = window.fetch;

  window.fetch = function (url, options = {}) {
    // Si ce n'est pas un appel API, on laisse passer
    if (typeof url !== 'string' || !url.includes('/api/')) {
      return originalFetch.apply(this, arguments);
    }

    console.log('🔄 API Mock intercepte:', url, options.method || 'GET');

    // Parse l'URL
    const urlObj = new URL(url, window.location.origin);
    const path = urlObj.pathname;
    const method = (options.method || 'GET').toUpperCase();

    // Routeur API
    return handleApiRequest(path, method, options);
  };

  // Gestionnaire principal des requêtes
  async function handleApiRequest(path, method, options) {
    try {
      let response;

      // ============ AUTH ============
      if (path.match(/^\/api\/(auth\/)?login$/)) {
        response = await handleLogin(options);
      }

      // ============ LOTS ============
      else if (path === '/api/lots' && method === 'GET') {
        const lots = await window.DBLocal.getAll('lots');
        // Parse unites_admises si c'est une string
        const formatted = lots.map(l => ({
          ...l,
          unites_admises: typeof l.unites_admises === 'string' 
            ? JSON.parse(l.unites_admises) 
            : l.unites_admises
        }));
        response = formatted;
      }
      else if (path.match(/^\/api\/lots\/(\d+)$/)) {
        const id = parseInt(path.split('/')[3]);
        const lot = await window.DBLocal.getById('lots', id);
        if (lot && typeof lot.unites_admises === 'string') {
          lot.unites_admises = JSON.parse(lot.unites_admises);
        }
        response = lot || { error: 'Lot non trouvé' };
      }
      else if (path === '/api/lots' && method === 'POST') {
        const data = JSON.parse(options.body);
        response = await window.DBLocal.add('lots', data);
      }

      // ============ PRODUCTEURS ============
      else if (path === '/api/producteurs' && method === 'GET') {
        response = await window.DBLocal.getAll('producteurs');
      }
      else if (path === '/api/producteurs' && method === 'POST') {
        const data = JSON.parse(options.body);
        response = await window.DBLocal.add('producteurs', data);
      }

      // ============ MAGASINS ============
      else if (path === '/api/magasins' && method === 'GET') {
        response = await window.DBLocal.getAll('magasins');
      }
      else if (path === '/api/magasins' && method === 'POST') {
        const data = JSON.parse(options.body);
        response = await window.DBLocal.add('magasins', data);
      }

      // ============ ADMISSIONS ============
      else if (path === '/api/admissions' && method === 'GET') {
        response = await window.DBLocal.getAll('admissions');
      }
      else if (path === '/api/admissions' && method === 'POST') {
        const data = JSON.parse(options.body);
        
        // Validation basique
        if (!data.lot_id || !data.producteur_id || !data.quantite) {
          return createJsonResponse({ error: 'Données manquantes' }, 400);
        }

        // Ajoute la date de réception
        data.date_reception = new Date().toISOString();
        
        response = await window.DBLocal.add('admissions', data);
      }
      else if (path.match(/^\/api\/admissions\/(\d+)$/) && method === 'DELETE') {
        const id = parseInt(path.split('/')[3]);
        await window.DBLocal.delete('admissions', id);
        response = { message: 'Admission supprimée', id };
      }

      // ============ RETRAITS ============
      else if (path === '/api/retraits' && method === 'GET') {
        response = await window.DBLocal.getAll('retraits');
      }
      else if (path === '/api/retraits' && method === 'POST') {
        const data = JSON.parse(options.body);
        
        // Validation
        if (!data.lot_id || !data.quantite || !data.magasin_id) {
          return createJsonResponse({ error: 'Données manquantes (lot_id, quantite, magasin_id requis)' }, 400);
        }

        // Vérifie le stock disponible
        const stockDispo = await window.BusinessLogic.getStockDisponible(data.magasin_id);
        const lotStock = stockDispo.find(s => s.lot_id === parseInt(data.lot_id));
        
        if (!lotStock) {
          return createJsonResponse({ error: 'Lot non disponible dans ce magasin' }, 400);
        }
        
        if (parseFloat(data.quantite) > lotStock.stock_actuel) {
          return createJsonResponse({ 
            error: `Stock insuffisant. Disponible: ${lotStock.stock_actuel} ${lotStock.unite}` 
          }, 400);
        }

        response = await window.DBLocal.add('retraits', data);
      }

      // ============ STOCKS ============
      else if (path.match(/^\/api\/stocks\/disponible\/(\d+)$/)) {
        const magasinId = parseInt(path.split('/')[4]);
        response = await window.BusinessLogic.getStockDisponible(magasinId);
      }

      // ============ AUDIT ============
      else if (path === '/api/audit/performance-by-store') {
        response = await window.BusinessLogic.getPerformanceByStore();
      }
      else if (path === '/api/audit/recent-logs') {
        response = await window.BusinessLogic.getRecentLogs(20);
      }

      // ============ TRANSFERTS ============
      else if (path === '/api/transferts/pending-audit') {
        // Pour la démo, retourne un tableau vide (pas de transferts en attente)
        response = [];
      }

      // ============ USERS ============
      else if (path === '/api/users' && method === 'GET') {
        response = await window.DBLocal.getAll('users');
      }
      else if (path === '/api/users' && method === 'POST') {
        const data = JSON.parse(options.body);
        response = await window.DBLocal.add('users', data);
      }

      // ============ 404 ============
      else {
        console.warn('⚠️ API Mock: Route non gérée:', path);
        return createJsonResponse({ error: 'Endpoint non implémenté en mode local' }, 404);
      }

      // Retourne la réponse
      return createJsonResponse(response, 200);

    } catch (err) {
      console.error('❌ Erreur API Mock:', err);
      return createJsonResponse({ error: err.message }, 500);
    }
  }

  // Gestion du login
  async function handleLogin(options) {
    const { username, password } = JSON.parse(options.body);
    
    try {
      const user = await window.BusinessLogic.login(username, password);
      return { user }; // Format attendu par auth.js
    } catch (err) {
      throw new Error(err.message);
    }
  }

  // Crée une réponse HTTP compatible
  function createJsonResponse(data, status = 200) {
    return Promise.resolve(new Response(
      JSON.stringify(data),
      {
        status,
        headers: { 'Content-Type': 'application/json' }
      }
    ));
  }

  console.log('✅ API Mock initialisé - Mode PWA Standalone');

})();
