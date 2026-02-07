// js/db-local.js - Base de données locale IndexedDB pour NBFO PWA
(function () {
  'use strict';

  const DB_NAME = 'NBFO_Database';
  const DB_VERSION = 3;
  let db = null;

  // Structure des tables (object stores)
  const STORES = {
    users: { keyPath: 'id', autoIncrement: true, indexes: [{ name: 'username', unique: true }] },
    lots: { keyPath: 'id', autoIncrement: true },
    producteurs: { keyPath: 'id', autoIncrement: true },
    magasins: { keyPath: 'id', autoIncrement: true },
    admissions: { keyPath: 'id', autoIncrement: true, indexes: [
      { name: 'lot_id', unique: false },
      { name: 'magasin_id', unique: false },
      { name: 'producteur_id', unique: false }
    ]},
    retraits: { keyPath: 'id', autoIncrement: true, indexes: [
      { name: 'lot_id', unique: false },
      { name: 'magasin_id', unique: false }
    ]},
    transferts: { keyPath: 'id', autoIncrement: true },
    messages: { keyPath: 'id', autoIncrement: true }
  };

  // Initialisation de la base de données
  function initDB() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION);

      request.onerror = () => reject(request.error);
      request.onsuccess = () => {
        db = request.result;
        console.log('✅ IndexedDB initialisée');
        resolve(db);
      };

      request.onupgradeneeded = (event) => {
        const db = event.target.result;
        console.log('🔧 Mise à jour de la base de données...');

        Object.entries(STORES).forEach(([storeName, config]) => {
          // Supprime l'ancien store si existe
          if (db.objectStoreNames.contains(storeName)) {
            db.deleteObjectStore(storeName);
          }

          // Crée le nouveau store
          const store = db.createObjectStore(storeName, {
            keyPath: config.keyPath,
            autoIncrement: config.autoIncrement
          });

          // Crée les index
          if (config.indexes) {
            config.indexes.forEach(idx => {
              store.createIndex(idx.name, idx.name, { unique: idx.unique });
            });
          }
        });

        console.log('✅ Schéma de base de données créé');
      };
    });
  }

  // Opérations CRUD génériques
  const DBLocal = {
    // CREATE
    async add(storeName, data) {
      const tx = db.transaction(storeName, 'readwrite');
      const store = tx.objectStore(storeName);
      
      // Ajoute timestamp automatiquement
      if (!data.created_at) data.created_at = new Date().toISOString();
      
      return new Promise((resolve, reject) => {
        const request = store.add(data);
        request.onsuccess = () => resolve({ ...data, id: request.result });
        request.onerror = () => reject(request.error);
      });
    },

    // READ ALL
    async getAll(storeName) {
      const tx = db.transaction(storeName, 'readonly');
      const store = tx.objectStore(storeName);
      
      return new Promise((resolve, reject) => {
        const request = store.getAll();
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
    },

    // READ BY ID
    async getById(storeName, id) {
      const tx = db.transaction(storeName, 'readonly');
      const store = tx.objectStore(storeName);
      
      return new Promise((resolve, reject) => {
        const request = store.get(parseInt(id));
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
    },

    // READ BY INDEX
    async getByIndex(storeName, indexName, value) {
      const tx = db.transaction(storeName, 'readonly');
      const store = tx.objectStore(storeName);
      const index = store.index(indexName);
      
      return new Promise((resolve, reject) => {
        const request = index.getAll(value);
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
    },

    // UPDATE
    async update(storeName, data) {
      const tx = db.transaction(storeName, 'readwrite');
      const store = tx.objectStore(storeName);
      
      data.updated_at = new Date().toISOString();
      
      return new Promise((resolve, reject) => {
        const request = store.put(data);
        request.onsuccess = () => resolve(data);
        request.onerror = () => reject(request.error);
      });
    },

    // DELETE
    async delete(storeName, id) {
      const tx = db.transaction(storeName, 'readwrite');
      const store = tx.objectStore(storeName);
      
      return new Promise((resolve, reject) => {
        const request = store.delete(parseInt(id));
        request.onsuccess = () => resolve(true);
        request.onerror = () => reject(request.error);
      });
    },

    // CLEAR (vider une table)
    async clear(storeName) {
      const tx = db.transaction(storeName, 'readwrite');
      const store = tx.objectStore(storeName);
      
      return new Promise((resolve, reject) => {
        const request = store.clear();
        request.onsuccess = () => resolve(true);
        request.onerror = () => reject(request.error);
      });
    },

    // QUERY personnalisée
    async query(storeName, filterFn) {
      const all = await this.getAll(storeName);
      return all.filter(filterFn);
    }
  };

  // Fonctions métier spécifiques
  const BusinessLogic = {
    // Authentification
    async login(username, password) {
      const tx = db.transaction('users', 'readonly');
      const store = tx.objectStore('users');
      const index = store.index('username');
      
      return new Promise((resolve, reject) => {
        const request = index.get(username);
        request.onsuccess = () => {
          const user = request.result;
          if (!user) {
            reject(new Error('Utilisateur introuvable'));
          } else if (user.password_hash !== password) { // En prod: utiliser bcrypt
            reject(new Error('Mot de passe incorrect'));
          } else if (user.statut !== 'actif') {
            reject(new Error('Compte inactif'));
          } else {
            resolve({
              id: user.id,
              username: user.username,
              role: user.role,
              magasin_id: user.magasin_id
            });
          }
        };
        request.onerror = () => reject(request.error);
      });
    },

    // Calcul du stock disponible pour un magasin
    async getStockDisponible(magasinId) {
      const admissions = await DBLocal.getByIndex('admissions', 'magasin_id', parseInt(magasinId));
      const retraits = await DBLocal.getByIndex('retraits', 'magasin_id', parseInt(magasinId));
      const lots = await DBLocal.getAll('lots');

      // Groupe par lot_id
      const stockMap = {};

      admissions.forEach(adm => {
        if (!stockMap[adm.lot_id]) {
          stockMap[adm.lot_id] = { entrees: 0, sorties: 0, unite: adm.unite };
        }
        stockMap[adm.lot_id].entrees += parseFloat(adm.quantite);
      });

      retraits.forEach(ret => {
        if (!stockMap[ret.lot_id]) {
          stockMap[ret.lot_id] = { entrees: 0, sorties: 0, unite: ret.unite };
        }
        stockMap[ret.lot_id].sorties += parseFloat(ret.quantite);
      });

      // Construit le résultat
      const result = [];
      Object.keys(stockMap).forEach(lotId => {
        const stock = stockMap[lotId];
        const lot = lots.find(l => l.id === parseInt(lotId));
        const stockActuel = stock.entrees - stock.sorties;

        if (stockActuel > 0 && lot) {
          result.push({
            lot_id: parseInt(lotId),
            description: lot.description,
            unite: stock.unite,
            prix_ref: lot.prix_ref,
            unites_admises: lot.unites_admises,
            stock_actuel: stockActuel
          });
        }
      });

      return result;
    },

    // Performance par magasin (pour audit)
    async getPerformanceByStore() {
      const admissions = await DBLocal.getAll('admissions');
      const magasins = await DBLocal.getAll('magasins');

      const stats = {};

      admissions.forEach(adm => {
        if (!stats[adm.magasin_id]) {
          stats[adm.magasin_id] = {
            nombre_admissions: 0,
            quantite_totale: 0,
            profit_virtuel_genere: 0,
            alertes_qualite: 0
          };
        }

        stats[adm.magasin_id].nombre_admissions++;
        stats[adm.magasin_id].quantite_totale += parseFloat(adm.quantite);

        // Calcul du profit (taxe coopérative)
        const montantBrut = adm.quantite * adm.prix_ref * (adm.coef_qualite || 1);
        const tauxTaxe = adm.mode_paiement === 'mobile_money' ? 0.07 : 0.05;
        stats[adm.magasin_id].profit_virtuel_genere += montantBrut * tauxTaxe;

        if (adm.coef_qualite && adm.coef_qualite < 0.9) {
          stats[adm.magasin_id].alertes_qualite++;
        }
      });

      return magasins.map(mag => ({
        magasin_id: mag.id,
        nom_magasin: mag.nom,
        ...stats[mag.id] || {
          nombre_admissions: 0,
          quantite_totale: 0,
          profit_virtuel_genere: 0,
          alertes_qualite: 0
        }
      }));
    },

    // Logs récents pour audit
    async getRecentLogs(limit = 10) {
      const admissions = await DBLocal.getAll('admissions');
      const retraits = await DBLocal.getAll('retraits');
      const lots = await DBLocal.getAll('lots');

      const logs = [];

      // Admissions
      admissions.forEach(adm => {
        const lot = lots.find(l => l.id === adm.lot_id);
        logs.push({
          date: adm.created_at,
          action: 'ADMISSION',
          produit: lot?.description || 'Inconnu',
          montant: adm.quantite * adm.prix_ref * (adm.coef_qualite || 1),
          utilisateur: adm.utilisateur
        });
      });

      // Retraits
      retraits.forEach(ret => {
        const lot = lots.find(l => l.id === ret.lot_id);
        logs.push({
          date: ret.created_at,
          action: ret.type_retrait === 'vente' ? 'VENTE' : 'RETRAIT',
          produit: lot?.description || 'Inconnu',
          montant: -(ret.quantite * (ret.prix_ref || 0)),
          utilisateur: ret.utilisateur
        });
      });

      // Trie par date décroissante
      return logs
        .sort((a, b) => new Date(b.date) - new Date(a.date))
        .slice(0, limit);
    }
  };

  // Données de démonstration
  async function seedDemoData() {
    const hasData = (await DBLocal.getAll('users')).length > 0;
    if (hasData) {
      console.log('⚠️ Données existantes détectées, skip seed');
      return;
    }

    console.log('🌱 Insertion des données de démonstration...');

    // Utilisateurs
    await DBLocal.add('users', { username: 'admin', password_hash: 'admin123', role: 'admin', statut: 'actif' });
    await DBLocal.add('users', { username: 'auditeur', password_hash: 'audit123', role: 'auditeur', statut: 'actif' });
    await DBLocal.add('users', { username: 'stock', password_hash: 'stock123', role: 'stock', statut: 'actif', magasin_id: 1 });

    // Magasins
    await DBLocal.add('magasins', { nom: 'Magasin Central', code: 'MC01', adresse: 'Yaoundé' });
    await DBLocal.add('magasins', { nom: 'Dépôt Douala', code: 'DD02', adresse: 'Douala' });

    // Producteurs
    await DBLocal.add('producteurs', { nom_producteur: 'Coopérative Nord', tel_producteur: '+237690000001' });
    await DBLocal.add('producteurs', { nom_producteur: 'Ferme du Sud', tel_producteur: '+237690000002' });

    // Lots
    await DBLocal.add('lots', {
      nom_produit: 'Maïs Sec',
      description: 'Maïs jaune sec calibre A',
      categorie: 'cereales',
      prix_ref: 350,
      unites_admises: JSON.stringify(['Sac 50kg', 'Tonne'])
    });
    await DBLocal.add('lots', {
      nom_produit: 'Cacao Fèves',
      description: 'Fèves de cacao séchées',
      categorie: 'cacao',
      prix_ref: 1200,
      unites_admises: JSON.stringify(['Sac 60kg', 'Tonne'])
    });

    console.log('✅ Données de démonstration insérées');
  }

  // Export global
  window.DBLocal = DBLocal;
  window.BusinessLogic = BusinessLogic;

  // Auto-initialisation
  window.addEventListener('DOMContentLoaded', async () => {
    try {
      await initDB();
      await seedDemoData();
      console.log('✅ db-local.js initialisé');
    } catch (err) {
      console.error('❌ Erreur initialisation DB:', err);
    }
  });

})();
