// Récupère l'utilisateur courant depuis sessionStorage
function getCurrentUser() {
  const userInfo = AppUser.get();
  return userInfo ? JSON.parse(userInfo) : null;
}

// Vérifie qu'un utilisateur est connecté, sinon redirige
function requireLogin() {
  const user = getCurrentUser();
  if (!user || !user.username || !user.role) {
    showError("Session invalide. Veuillez vous reconnecter.");
    setTimeout(() => window.location.href = "/index.html", 2000);
    return null;
  }
  return user;
}

// Affiche un message d'erreur (simple exemple)
function showError(message) {
  const errorBox = document.getElementById("errorBox");
  if (errorBox) {
    errorBox.textContent = message;
    errorBox.style.display = "block";
  } else {
    alert(message);
  }
}

// Charge le contenu en fonction du rôle
function loadRoleContent(role) {
  let html = "";

  switch (role) {
    case "superadmin":
      html = "<p>Accès illimité : gestion globale, configuration système, supervision des admins.</p>";
      break;
    case "admin":
      html = "<p>Accès complet : gestion des utilisateurs, audit, caisse et stock.</p>";
      break;
    case "auditeur":
      html = "<p>Accès audit : consultation des journaux, vérification des opérations, rapports.</p>";
      break;
    case "caisse":
      html = "<p>Accès caisse : opérations financières et chèques.</p>";
      break;
    case "stock":
      html = "<p>Accès stock : gestion des lots, inventaire et alertes.</p>";
      break;
    default:
      html = "<p>Rôle non reconnu. Contactez un administrateur.</p>";
  }

  const roleContent = document.getElementById("roleContent");
  if (roleContent) {
    roleContent.innerHTML = `<h2>Section ${role}</h2>${html}`;
  }
}
(function () {
  'use strict';

  const API_BASE = (window.API_BASE || '/api');

  async function fetchJson(url, opts) {
    const res = await fetch(url, opts);
    if (!res.ok) {
      const txt = await res.text().catch(()=>null);
      throw new Error(`Erreur fetch ${url}: ${res.status} ${txt || ''}`);
    }
    return res.json();
  }

  function escapeHtml(str = '') {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  // --- LOADERS ---
  async function loadLotsInto(selectId, placeholder = '-- Sélectionner un lot --') {
    const sel = document.getElementById(selectId);
    if (!sel) return;
    try {
      const lots = await fetchJson(`${API_BASE}/lots`);
      sel.innerHTML = `<option value="">${escapeHtml(placeholder)}</option>` +
        lots.map(l => {
          const unites = JSON.stringify(l.unites_admises || []);
          const prix = (l.prix_ref !== undefined && l.prix_ref !== null) ? ` (${l.prix_ref} FCFA)` : '';
          const label = `${escapeHtml(l.description || l.nom_produit || `Lot ${l.id}`)}${prix}`;
          // stock data attributes: unites (json) and prix_ref
          const dataUnites = escapeHtml(unites).replace(/&quot;/g, '"');
          return `<option value="${l.id}" data-unites='${dataUnites}' data-prix='${escapeHtml(l.prix_ref || 0)}'>${label}</option>`;
        }).join('');
    } catch (err) {
      console.error('loadLotsInto', err);
      sel.innerHTML = `<option value="">Erreur chargement lots</option>`;
    }
  }

  async function loadProducteursInto(selectId, placeholder = '-- Sélectionner --') {
    const sel = document.getElementById(selectId);
    if (!sel) return;
    try {
      const producteurs = await fetchJson(`${API_BASE}/producteurs`);
      sel.innerHTML = `<option value="">${escapeHtml(placeholder)}</option>` +
        producteurs.map(p => {
          const label = `${escapeHtml(p.nom_producteur || p.nom || `Producteur ${p.id}`)}${p.tel_producteur ? ' - ' + escapeHtml(p.tel_producteur) : ''}`;
          return `<option value="${p.id}">${label}</option>`;
        }).join('');
    } catch (err) {
      console.error('loadProducteursInto', err);
      sel.innerHTML = `<option value="">Erreur chargement producteurs</option>`;
    }
  }

  async function loadMagasinsInto(selectId, placeholder = '-- Sélectionner --') {
    const sel = document.getElementById(selectId);
    if (!sel) return;
    try {
      const magasins = await fetchJson(`${API_BASE}/magasins`);
      sel.innerHTML = `<option value="">${escapeHtml(placeholder)}</option>` +
        magasins.map(m => `<option value="${m.id}">${escapeHtml(m.nom || `Magasin ${m.id}`)}${m.code ? ' ('+escapeHtml(m.code)+')' : ''}</option>`).join('');
    } catch (err) {
      console.error('loadMagasinsInto', err);
      sel.innerHTML = `<option value="">Erreur chargement magasins</option>`;
    }
  }

  // Remplit le select d'unités pour un lot (lit data-unites, sinon récupère /api/lots/:id)
  async function loadUnitsForLotSelect(lotSelectId, unitSelectId) {
    const lotSel = document.getElementById(lotSelectId);
    const unitSel = document.getElementById(unitSelectId);
    if (!lotSel || !unitSel) return;

    const opt = lotSel.selectedOptions && lotSel.selectedOptions[0];
    let unites = [];

    if (opt) {
      const raw = opt.getAttribute('data-unites');
      if (raw) {
        try { unites = JSON.parse(raw); } catch (e) { 
          // si format étrange, essayer split
          unites = String(raw).split(',').map(s => s.trim()).filter(Boolean);
        }
      }
      // fallback : if option has no data-unites but has value -> fetch single lot
      if ((!unites || unites.length === 0) && opt.value) {
        try {
          const lot = await fetchJson(`${API_BASE}/lots/${opt.value}`);
          unites = lot.unites_admises || [];
        } catch (e) {
          console.warn('Impossible de fetch lot pour unités', e);
        }
      }
    }

    if (!Array.isArray(unites) || unites.length === 0) {
      unitSel.innerHTML = '<option value="">-- --</option>';
      return;
    }
    unitSel.innerHTML = unites.map(u => `<option value="${escapeHtml(u)}">${escapeHtml(u)}</option>`).join('');
  }

  // --- FORM SUBMIT HELPERS (RETRAIT / TRANSFERT) ---
  // Soumet le formulaire de retrait (utilise les colonnes DB : lot_id, quantite, unite, prix_ref, type_retrait, destination_* ...)
// Remplacer uniquement la fonction handleRetraitSubmit par ce code (dans public/js/common.js)
async function handleRetraitSubmit(e) {
  e.preventDefault();
  const get = id => document.getElementById(id) && document.getElementById(id).value;
  const lotId = parseInt(get('retraitLot'));
  const quantite = parseFloat(get('retraitQuantity') || get('retraitQty') || get('retraitQty') || 0);
  const unite = get('retraitUnite') || '';
  const type_retrait = get('typeRetrait') || 'client';
  const lotOpt = document.getElementById('retraitLot')?.selectedOptions?.[0];
  const prix_ref = lotOpt ? parseFloat(lotOpt.getAttribute('data-prix') || 0) : 0;

// Récupérer le magasin_id depuis le select retraitMagasin
const magasinId = parseInt(get('retraitMagasin')) || null;

const body = {
  lot_id: lotId,
  quantite,
  unite,
  type_retrait,
  prix_ref,
  utilisateur: (window.CURRENT_USER || localStorage.getItem('username') || 'unknown'),
  magasin_id: magasinId  // ← Maintenant on utilise la valeur du select
};

// Validation : vérifier que magasin_id existe
if (!magasinId) {
  alert('Veuillez sélectionner un magasin source');
  return;
}

  if (type_retrait === 'producteur') body.destination_producteur_id = parseInt(get('destProducteur')) || null;
  if (type_retrait === 'magasin') body.destination_magasin_id = parseInt(get('destMagasinRetrait') || get('destMagasin')) || null;
  if (type_retrait === 'destruction') body.motif = get('motif') || null;

  console.log('Envoi /api/retraits body =', body);

  try {
    const response = await fetch('/api/retraits', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });

    if (!response.ok) {
      // essaie parser JSON d'erreur si possible
      let errText = await response.text().catch(()=>null);
      let errObj;
      try { errObj = errText ? JSON.parse(errText) : null; } catch(e) { errObj = null; }
      console.error('Erreur submit retrait (HTTP ' + response.status + '):', errObj || errText);
      // message utilisateur
      const userMsg = (errObj && (errObj.error || errObj.message)) || errText || `Erreur HTTP ${response.status}`;
      alert('Erreur lors de l\'enregistrement du retrait : ' + userMsg);
      return;
    }

    const result = await response.json();
    alert('Retrait enregistré ✔️');
    e.target.reset();
    if (typeof loadLotsInto === 'function') loadLotsInto('retraitLot');
    if (typeof loadRetraits === 'function') loadRetraits().catch(()=>{});
  } catch (err) {
    console.error('Erreur submit retrait (fetch failed):', err);
    alert('Erreur réseau lors de l\'enregistrement du retrait : ' + (err.message || err));
  }
}

  // Submit pour transfert (enregistre un retrait de type magasin vers magasin)
  async function handleTransferSubmit(e) {
    e.preventDefault();
    const get = id => document.getElementById(id) && document.getElementById(id).value;
    const lotId = parseInt(get('transferLot') || get('trans-lot') || 0);
    const quantite = parseFloat(get('transferQuantity') || 0);
    const destMagasinId = parseInt(get('destMagasin') || get('trans-dest') || 0);
    const lotOpt = document.getElementById('transferLot')?.selectedOptions?.[0] || document.getElementById('trans-lot')?.selectedOptions?.[0];
    const prix_ref = lotOpt ? parseFloat(lotOpt.getAttribute('data-prix') || 0) : 0;

    const body = {
      lot_id: lotId,
      quantite,
      type_retrait: 'magasin',
      destination_magasin_id: destMagasinId,
      prix_ref,
      utilisateur: (window.CURRENT_USER || 'unknown'),
      magasin_id: (window.CURRENT_MAGASIN_ID || null)
    };

    try {
      await fetchJson(`${API_BASE}/retraits`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });
      alert('Transfert enregistré ✔️');
      const form = document.getElementById('transferForm') || document.getElementById('transfertForm');
      if (form) { form.reset(); form.style.display = 'none'; }
      if (typeof loadLotsInto === 'function') loadLotsInto('transferLot');
      if (typeof loadRetraits === 'function') loadRetraits().catch(()=>{});
      if (typeof loadTransfers === 'function') loadTransfers().catch(()=>{});
    } catch (err) {
      console.error('Erreur submit transfert', err);
      alert('Erreur lors de l\'enregistrement du transfert');
    }
  }

  // --- AUTO INIT: ids trouvés dans ton repo (silencieux si n'existent pas) ---
  document.addEventListener('DOMContentLoaded', async () => {
    const lotIds = ['lotSelect', 'adm-lot-select', 'retraitLot', 'transferLot', 'trans-lot'];
    const producteurIds = ['producerSelect', 'adm-producer-select', 'destProducteur'];
    const magasinIds = ['magasinSelect', 'destMagasin', 'destMagasinRetrait', 'retraitMagasin', 'trans-dest'];

    // Parallel load
    await Promise.all([
      ...lotIds.map(id => loadLotsInto(id).catch(()=>{})),
      ...producteurIds.map(id => loadProducteursInto(id).catch(()=>{})),
      ...magasinIds.map(id => loadMagasinsInto(id).catch(()=>{}))
    ]).catch(()=>{});

    // Bind units update maps
    [
      ['lotSelect', 'unitSelect'],
      ['adm-lot-select', 'adm-unit'],
      ['retraitLot', 'retraitUnite'],
      ['transferLot', 'transferUnite'],
      ['trans-lot', 'transferUnite']
    ].forEach(([lotId, unitId]) => {
      const lot = document.getElementById(lotId);
      const unit = document.getElementById(unitId);
      if (!lot || !unit) return;
      // initial fill
      loadUnitsForLotSelect(lotId, unitId).catch(()=>{});
      // on change
      lot.addEventListener('change', () => loadUnitsForLotSelect(lotId, unitId));
    });

    // Hook forms if present
    const retraitForm = document.getElementById('retraitForm');
    if (retraitForm && !retraitForm.__nbfo_attached) {
      retraitForm.addEventListener('submit', handleRetraitSubmit);
      retraitForm.__nbfo_attached = true;
    }

    const transferForm = document.getElementById('transferForm') || document.getElementById('transfertForm');
    if (transferForm && !transferForm.__nbfo_attached) {
      transferForm.addEventListener('submit', handleTransferSubmit);
      transferForm.__nbfo_attached = true;
    }
  });

  // Export utiles (pour debug ou appel manuel)
  window.NFBO = window.NFBO || {};
  Object.assign(window.NFBO, {
    loadLotsInto,
    loadProducteursInto,
    loadMagasinsInto,
    loadUnitsForLotSelect,
    handleRetraitSubmit,
    handleTransferSubmit
  });

})(); // ← CETTE LIGNE MANQUAIT !!!

console.log('✅ common.js chargé avec succès');
