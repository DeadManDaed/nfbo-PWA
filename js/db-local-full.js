// js/db-local-full.js - Base de données IndexedDB complète pour NBFO PWA
// Réplique exacte de la structure PostgreSQL
(function () {
  'use strict';

  const DB_NAME = 'NBFO_Database';
  const DB_VERSION = 5; // Incrémenté pour nouvelles tables

  let db = null;

  // Structure complète des tables (mappées depuis PostgreSQL)
  const STORES = {
    // Tables principales
    users: { 
      keyPath: 'id', 
      autoIncrement: true, 
      indexes: [
        { name: 'username', unique: true },
        { name: 'role', unique: false },
        { name: 'magasin_id', unique: false }
      ] 
    },
    
    admissions: { 
      keyPath: 'id', 
      autoIncrement: true,
      indexes: [
        { name: 'lot_id', unique: false },
        { name: 'producteur_id', unique: false },
        { name: 'magasin_id', unique: false },
        { name: 'date_reception', unique: false },
        { name: 'region_id', unique: false },
        { name: 'departement_id', unique: false },
        { name: 'user_id', unique: false }
      ]
    },
    
    lots: { 
      keyPath: 'id', 
      autoIncrement: true,
      indexes: [
        { name: 'categorie', unique: false }
      ]
    },
    
    producteurs: { 
      keyPath: 'id', 
      autoIncrement: true,
      indexes: [
        { name: 'nom_producteur', unique: false },
        { name: 'region_id', unique: false }
      ]
    },
    
    magasins: { 
      keyPath: 'id', 
      autoIncrement: true,
      indexes: [
        { name: 'code', unique: true },
        { name: 'region_id', unique: false }
      ]
    },
    
    retraits: { 
      keyPath: 'id', 
      autoIncrement: true,
      indexes: [
        { name: 'lot_id', unique: false },
        { name: 'magasin_id', unique: false },
        { name: 'type_retrait', unique: false }
      ]
    },
    
    // Tables géographiques
    regions: {
      keyPath: 'id',
      autoIncrement: true
    },
    
    departements: {
      keyPath: 'id',
      autoIncrement: true,
      indexes: [
        { name: 'region_id', unique: false }
      ]
    },
    
    arrondissements: {
      keyPath: 'id',
      autoIncrement: true,
      indexes: [
        { name: 'departement_id', unique: false }
      ]
    },
    
    departement_codes: {
      keyPath: 'departement_id',
      autoIncrement: false
    },
    
    // Tables finances
    caisse: {
      keyPath: 'id',
      autoIncrement: true
    },
    
    caisse_lignes: {
      keyPath: 'id',
      autoIncrement: true,
      indexes: [
        { name: 'caisse_id', unique: false },
        { name: 'lot_id', unique: false },
        { name: 'producteur_id', unique: false }
      ]
    },
    
    cheques: {
      keyPath: 'id',
      autoIncrement: true,
      indexes: [
        { name: 'numero_cheque', unique: true }
      ]
    },
    
    paiements: {
      keyPath: 'id',
      autoIncrement: true,
      indexes: [
        { name: 'producteur_id', unique: false },
        { name: 'mode_paiement', unique: false }
      ]
    },
    
    internal_bank_logs: {
      keyPath: 'id',
      autoIncrement: true,
      indexes: [
        { name: 'lot_id', unique: false },
        { name: 'admission_id', unique: false }
      ]
    },
    
    // Tables RH
    employers: {
      keyPath: 'id',
      autoIncrement: false, // ID est VARCHAR
      indexes: [
        { name: 'magasin_id', unique: false },
        { name: 'matricule', unique: true }
      ]
    },
    
    // Tables transferts
    transferts: { 
      keyPath: 'id', 
      autoIncrement: true,
      indexes: [
        { name: 'lot_id', unique: false },
        { name: 'magasin_depart', unique: false },
        { name: 'magasin_dest', unique: false },
        { name: 'statut', unique: false }
      ]
    },
    
    // Tables audit
    audit: {
      keyPath: 'id',
      autoIncrement: true,
      indexes: [
        { name: 'utilisateur', unique: false },
        { name: 'date', unique: false }
      ]
    },
    
    logs_deploiement: {
      keyPath: 'id',
      autoIncrement: true,
      indexes: [
        { name: 'date_erreur', unique: false },
        { name: 'resolu', unique: false }
      ]
    },
    
    // Messages
    messages: { 
      keyPath: 'id', 
      autoIncrement: true,
      indexes: [
        { name: 'expediteur', unique: false },
        { name: 'destinataire', unique: false },
        { name: 'lu', unique: false }
      ]
    }
  };

  // Initialisation de la base de données
  function initDB() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION);

      request.onerror = () => reject(request.error);
      request.onsuccess = () => {
        db = request.result;
        console.log('✅ IndexedDB NBFO initialisée (version complète)');
        resolve(db);
      };

      request.onupgradeneeded = (event) => {
        const db = event.target.result;
        console.log('🔧 Mise à jour schéma de base de données...');

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
              try {
                store.createIndex(idx.name, idx.name, { unique: idx.unique });
              } catch (e) {
                console.warn(`Index ${idx.name} déjà existant`);
              }
            });
          }
        });

        console.log('✅ Schéma complet de base de données créé');
      };
    });
  }

  // Opérations CRUD génériques
  const DBLocal = {
    // CREATE
    async add(storeName, data) {
      if (!db) await initDB();
      const tx = db.transaction(storeName, 'readwrite');
      const store = tx.objectStore(storeName);
      
      if (!data.created_at) data.created_at = new Date().toISOString();
      
      return new Promise((resolve, reject) => {
        const request = store.add(data);
        request.onsuccess = () => resolve({ ...data, id: request.result });
        request.onerror = () => reject(request.error);
      });
    },

    // BULK INSERT (pour migration)
    async addBulk(storeName, dataArray) {
      if (!db) await initDB();
      const tx = db.transaction(storeName, 'readwrite');
      const store = tx.objectStore(storeName);
      
      const promises = dataArray.map(data => {
        return new Promise((resolve, reject) => {
          const request = store.add(data);
          request.onsuccess = () => resolve(request.result);
          request.onerror = () => reject(request.error);
        });
      });
      
      return Promise.all(promises);
    },

    // READ ALL
    async getAll(storeName) {
      if (!db) await initDB();
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
      if (!db) await initDB();
      const tx = db.transaction(storeName, 'readonly');
      const store = tx.objectStore(storeName);
      
      return new Promise((resolve, reject) => {
        const request = store.get(typeof id === 'string' ? id : parseInt(id));
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
    },

    // READ BY INDEX
    async getByIndex(storeName, indexName, value) {
      if (!db) await initDB();
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
      if (!db) await initDB();
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
      if (!db) await initDB();
      const tx = db.transaction(storeName, 'readwrite');
      const store = tx.objectStore(storeName);
      
      return new Promise((resolve, reject) => {
        const request = store.delete(typeof id === 'string' ? id : parseInt(id));
        request.onsuccess = () => resolve(true);
        request.onerror = () => reject(request.error);
      });
    },

    // CLEAR
    async clear(storeName) {
      if (!db) await initDB();
      const tx = db.transaction(storeName, 'readwrite');
      const store = tx.objectStore(storeName);
      
      return new Promise((resolve, reject) => {
        const request = store.clear();
        request.onsuccess = () => resolve(true);
        request.onerror = () => reject(request.error);
      });
    },

    // QUERY
    async query(storeName, filterFn) {
      const all = await this.getAll(storeName);
      return all.filter(filterFn);
    },

    // COUNT
    async count(storeName) {
      if (!db) await initDB();
      const tx = db.transaction(storeName, 'readonly');
      const store = tx.objectStore(storeName);
      
      return new Promise((resolve, reject) => {
        const request = store.count();
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
    }
  };

  // Fonctions métier (gardées de l'ancienne version)
  const BusinessLogic = {
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
          } else if (user.password_hash !== password) {
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

    async getStockDisponible(magasinId) {
      const admissions = await DBLocal.getByIndex('admissions', 'magasin_id', parseInt(magasinId));
      const retraits = await DBLocal.getByIndex('retraits', 'magasin_id', parseInt(magasinId));
      const lots = await DBLocal.getAll('lots');

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

        if (adm.benefice_estime) {
          stats[adm.magasin_id].profit_virtuel_genere += parseFloat(adm.benefice_estime);
        }

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

    async getRecentLogs(limit = 10) {
      const admissions = await DBLocal.getAll('admissions');
      const retraits = await DBLocal.getAll('retraits');
      const lots = await DBLocal.getAll('lots');

      const logs = [];

      admissions.forEach(adm => {
        const lot = lots.find(l => l.id === adm.lot_id);
        logs.push({
          date: adm.date_reception || adm.created_at,
          action: 'ADMISSION',
          produit: lot?.description || 'Inconnu',
          montant: adm.valeur_totale || (adm.quantite * adm.prix_ref),
          utilisateur: adm.utilisateur
        });
      });

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

      return logs
        .sort((a, b) => new Date(b.date) - new Date(a.date))
        .slice(0, limit);
    }
  };

  // Pas de seed automatique (sera fait via import SQL)

  // Export global
  window.DBLocal = DBLocal;
  window.BusinessLogic = BusinessLogic;

  // Auto-initialisation
  window.addEventListener('DOMContentLoaded', async () => {
    try {
      await initDB();
      console.log('✅ db-local-full.js initialisé (migration-ready)');
    } catch (err) {
      console.error('❌ Erreur initialisation DB:', err);
    }
  });

})();
