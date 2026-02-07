// public/js/transfert.js
(function () {
  'use strict';
  const API_BASE = (window.API_BASE || '/api');

  async function fetchJson(url, opts) {
    const res = await fetch(url, opts);
    if (!res.ok) {
      const txt = await res.text().catch(() => null);
      throw new Error(`Erreur fetch ${url}: ${res.status} ${txt || ''}`);
    }
    return res.json();
  }

  function escapeHtml(str = '') {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  // ============================================
  // FONCTION : Charge les chauffeurs du magasin
  // ============================================
  window.loadChauffeurs = async function (magasinId) {
    const magasinSourceId = magasinId || document.getElementById('trans-magasin-source')?.value;
    const chauffeurSelect = document.getElementById('trans-driver');

    console.log('🔧 loadChauffeurs appelé avec magasinId:', magasinSourceId);

    if (!chauffeurSelect) {
      console.error('❌ Select trans-driver introuvable');
      return;
    }

    chauffeurSelect.innerHTML = '<option value="">-- Chargement... --</option>';

    if (!magasinSourceId) {
      console.log('⚠️ Pas de magasin source sélectionné');
      chauffeurSelect.innerHTML = '<option value="">-- Choisir d\'abord un magasin source --</option>';
      return;
    }

    try {
      const url = `${API_BASE}/employers?magasin_id=${encodeURIComponent(magasinSourceId)}`;
      console.log('🌐 Fetching:', url);

      const employers = await fetchJson(url);
      console.log('📦 Employers reçus:', employers);

      // Filtrer uniquement les chauffeurs actifs
      const chauffeurs = employers.filter(e => {
        console.log(`  - ${e.nom}: role=${e.role}, statut=${e.statut}`);
        return e.role === 'chauffeur' && (!e.statut || e.statut === 'actif');
      });

      console.log('🚗 Chauffeurs filtrés:', chauffeurs.length, 'trouvé(s)');

      if (chauffeurs.length === 0) {
        chauffeurSelect.innerHTML = '<option value="">-- Aucun chauffeur disponible --</option>';
        return;
      }

      chauffeurSelect.innerHTML = '<option value="">-- Sélectionner un chauffeur --</option>' +
        chauffeurs.map(c => {
          const nom = escapeHtml(c.nom || `Employé ${c.id}`);
          const matricule = c.matricule ? ` (${escapeHtml(c.matricule)})` : '';
          const contact = c.contact ? ` - ${escapeHtml(c.contact)}` : '';
          return `<option value="${c.id}">${nom}${matricule}${contact}</option>`;
        }).join('');

      console.log('✅ Select chauffeur peuplé avec', chauffeurs.length, 'chauffeur(s)');

    } catch (err) {
      console.error('❌ Erreur loadChauffeurs:', err);
      chauffeurSelect.innerHTML = '<option value="">Erreur chargement chauffeurs</option>';
    }
  };

  // ============================================
  // FONCTION : Charge les lots du magasin source
  // ============================================
  window.loadLotsForTransfer = async function () {
    const magasinSourceId = document.getElementById('trans-magasin-source')?.value;
    const lotSelect = document.getElementById('trans-lot');
    const uniteSelect = document.getElementById('trans-unite');

    if (!lotSelect) return;

    lotSelect.innerHTML = '<option value="">-- Chargement... --</option>';
    if (uniteSelect) uniteSelect.innerHTML = '<option value="">-- --</option>';

    if (!magasinSourceId) {
      lotSelect.innerHTML = '<option value="">-- Choisir d\'abord un magasin source --</option>';
      return;
    }

    try {
      const stocks = await fetchJson(`${API_BASE}/stocks/disponible/${encodeURIComponent(magasinSourceId)}`);

      if (!Array.isArray(stocks) || stocks.length === 0) {
        lotSelect.innerHTML = '<option value="">-- Aucun lot en stock --</option>';
        return;
      }

      lotSelect.innerHTML = '<option value="">-- Sélectionner un lot --</option>' +
        stocks.map(s => {
          const lid = String(s.lot_id || s.lotId || s.id);
          const prix = (s.prix_ref !== undefined && s.prix_ref !== null) ? s.prix_ref : 0;
          const unites = (s.unites_admises && Array.isArray(s.unites_admises)) ? s.unites_admises : (s.unite ? [s.unite] : []);
          const dataUnites = escapeHtml(JSON.stringify(unites)).replace(/&quot;/g, '"');
          const description = escapeHtml(s.description || `Lot ${lid}`);
          const stock = Number(s.stock_actuel != null ? s.stock_actuel : (s.stock || 0));
          const uniteLabel = s.unite || (unites[0] || '');

          return `<option value="${lid}" data-unites='${dataUnites}' data-prix='${escapeHtml(prix)}' data-stock='${stock}'>
            ${description} — ${stock} ${escapeHtml(uniteLabel)}
          </option>`;
        }).join('');

    } catch (err) {
      console.error('loadLotsForTransfer error', err);
      lotSelect.innerHTML = '<option value="">Erreur chargement stock</option>';
    }
  };

  // ============================================
  // FONCTION : Charge les unités du lot sélectionné
  // ============================================
  async function loadUnitsForTransferLot() {
    const lotSel = document.getElementById('trans-lot');
    const unitSel = document.getElementById('trans-unite');
    
    if (!lotSel || !unitSel) return;
    
    const opt = lotSel.selectedOptions[0];

    if (!opt || !opt.dataset.unites) {
      unitSel.innerHTML = '<option value="">-- --</option>';
      return;
    }

    try {
      const unites = JSON.parse(opt.dataset.unites);
      unitSel.innerHTML = unites.map(u => 
        `<option value="${escapeHtml(u)}">${escapeHtml(u)}</option>`
      ).join('');
    } catch (e) {
      // Fallback si c'est une chaîne simple
      const u = opt.dataset.unites;
      unitSel.innerHTML = `<option value="${escapeHtml(u)}">${escapeHtml(u)}</option>`;
    }
  }

  // ============================================
  // FONCTION : Soumission du formulaire
  // ============================================

async function handleTransferSubmit(e) {
    e.preventDefault();

    const get = id => document.getElementById(id)?.value;

    const magasinSourceId = parseInt(get('trans-magasin-source')) || null;
    const lotId = parseInt(get('trans-lot')) || null;
    const quantite = parseFloat(get('trans-qty')) || 0;
    const unite = get('trans-unite') || '';
    const destMagasinId = parseInt(get('trans-dest')) || null;
    const chauffeurId = get('trans-driver') || ''; // C'est maintenant un VARCHAR (ex: EMP-001)
    const note = get('trans-note') || '';

    // Validations
    if (!magasinSourceId || !lotId || !destMagasinId || !chauffeurId || quantite <= 0) {
        alert('Veuillez remplir tous les champs obligatoires (Source, Destination, Lot, Quantité et Chauffeur)');
        return;
    }

    if (magasinSourceId === destMagasinId) {
        alert('Le magasin source et destinataire doivent être différents');
        return;
    }

    // Récupération du prix pour la valeur du transfert
    const lotOpt = document.getElementById('trans-lot')?.selectedOptions?.[0];
    const prix_ref = lotOpt ? parseFloat(lotOpt.getAttribute('data-prix') || 0) : 0;

    // Construction du corps pour la table 'transferts'
    const body = {
        lot_id: lotId,
        magasin_id: magasinSourceId, // magasin_depart
        destination_magasin_id: destMagasinId, // magasin_destination
        chauffeur_id: chauffeurId, // Correspond au VARCHAR(50) de la table employers
        quantite: quantite,
        unite: unite,
        prix_ref: prix_ref,
        utilisateur: (localStorage.getItem('username') || 'anonyme'),
        motif: note
    };

    console.log('🚀 Envoi du transfert vers le backend:', body);

    try {
        const response = await fetch(`${API_BASE}/transferts`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });

        const result = await response.json();

        if (!response.ok) {
            throw new Error(result.error || 'Erreur lors de l\'enregistrement du transfert');
        }

        alert(`✔️ Transfert #${result.transfert_id} enregistré et en transit !`);
        
        // Réinitialisation
        e.target.reset();
        // Optionnel : rafraîchir le stock affiché si nécessaire
        if (typeof loadLotsForTransfer === 'function') loadLotsForTransfer();

    } catch (err) {
        console.error('❌ Erreur submit transfert:', err);
        alert('Erreur : ' + err.message);
    }
}


  // ============================================
  // INITIALISATION AU CHARGEMENT
  // ============================================
  document.addEventListener('DOMContentLoaded', async () => {
    console.log('🚀 Initialisation sécurisée du module transfert');

    // 1. Récupérer l'utilisateur (via la fonction de common.js)
    const user = requireLogin(); 
    if (!user) return;

    const sourceSelect = document.getElementById('trans-magasin-source');
    const destSelect = document.getElementById('trans-dest');

    try {
      // 2. Charger TOUS les magasins depuis l'API
      const magasins = await fetchJson(`${API_BASE}/magasins`);
      console.log('📦 Magasins chargés:', magasins);

      const optionsHtml = magasins.map(m => {
        const nom = escapeHtml(m.nom || `Magasin ${m.id}`);
        const code = m.code ? ` (${escapeHtml(m.code)})` : '';
        return `<option value="${m.id}">${nom}${code}</option>`;
      }).join('');

      if (sourceSelect) {
        sourceSelect.innerHTML = '<option value="">-- Sélectionner Source --</option>' + optionsHtml;
        console.log('✅ Select magasin source peuplé');
      }
      
      if (destSelect) {
        destSelect.innerHTML = '<option value="">-- Sélectionner Destination --</option>' + optionsHtml;
        console.log('✅ Select magasin dest peuplé');
      }

      // 3. LOGIQUE DE VERROUILLAGE (Admin Local vs SuperAdmin)
      if (user.role !== 'superadmin' && user.magasin_id) {
        console.log(`🔒 Verrouillage sur le magasin ID: ${user.magasin_id}`);

        sourceSelect.value = user.magasin_id;
        sourceSelect.disabled = true;
        sourceSelect.style.background = "#eeeeee";

        // Charger immédiatement le stock et les chauffeurs pour ce magasin
        loadLotsForTransfer();
        loadChauffeurs(user.magasin_id);
      }

    } catch (err) {
      console.error('❌ Erreur lors de l\'init des magasins:', err);
    }

    // 4. Listeners pour les changements manuels (utile pour le SuperAdmin)
    if (sourceSelect) {
      sourceSelect.addEventListener('change', (e) => {
        const id = e.target.value;
        console.log('🚛 Magasin source changé:', id);
        if (id) {
          loadLotsForTransfer();
          loadChauffeurs(id);
        } else {
          document.getElementById('trans-lot').innerHTML = '<option value="">-- Choisir d\'abord un magasin source --</option>';
          document.getElementById('trans-unite').innerHTML = '<option value="">-- --</option>';
          document.getElementById('trans-driver').innerHTML = '<option value="">-- Choisir d\'abord un magasin source --</option>';
        }
      });
      console.log('✅ Event listener magasin source attaché');
    }

    // 5. Bind changement de lot -> mise à jour unités
    const lotSel = document.getElementById('trans-lot');
    if (lotSel) {
      lotSel.addEventListener('change', loadUnitsForTransferLot);
      console.log('✅ Event listener lot attaché');
    }

    // 6. Liaison du formulaire
    const form = document.getElementById('form-expedition');
    if (form && !form.__transfer_attached) {
      form.addEventListener('submit', handleTransferSubmit);
      form.__transfer_attached = true;
      console.log('✅ Event listener formulaire attaché');
    }

    console.log('✅ Module transfert initialisé');
  });

  // ============================================
  // EXPORT
  // ============================================
  window.NFBO = window.NFBO || {};
  Object.assign(window.NFBO, {
    loadLotsForTransfer,
    loadChauffeurs,
    handleTransferSubmit
  });

})();

console.log('✅ transfert.js chargé avec succès');