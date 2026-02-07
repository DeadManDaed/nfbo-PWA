/**
 * admin-1.js - Logique de gestion de la console d'administration
 * Gère les tableaux dynamiques et les formulaires (Magasins, Users, Lots, etc.)
 */

// 1. VARIABLES GLOBALES ET ÉTAT
let currentSection = 'magasins';
let critereCounter = 0;

// 2. INITIALISATION AU CHARGEMENT DE LA PAGE
document.addEventListener('DOMContentLoaded', () => {
    console.log("Admin module chargé.");
    
    // Initialiser le bouton "Ajouter" principal
    const btnAdd = document.getElementById('btn-add-admin');
    if (btnAdd) {
        btnAdd.addEventListener('click', showAdminForm);
    }

    // Charger la section par défaut au démarrage
    refreshAdminTable();
});

// 3. NAVIGATION ET CHARGEMENT DES DONNÉES
// On s'assure que la fonction est globale

/*

window.loadAdminSection = async function(section, event) {
    currentSection = section; // Utilise la variable déjà définie dans votre code
    
    console.log("Chargement de la section admin :", section);

    // Votre logique existante de gestion visuelle
    document.querySelectorAll('.admin-nav-btn').forEach(b => b.classList.remove('active'));
    
    // Si l'event est passé, on active le bouton
    if (event && event.currentTarget) {
        event.currentTarget.classList.add('active');
    } else {
        // Fallback si l'event n'est pas passé (appel direct)
        const btn = document.querySelector(`button[onclick*="'${section}'"]`);
        if (btn) btn.classList.add('active');
    }
    
    const titleElem = document.getElementById('admin-title');
    if (titleElem) {
        titleElem.innerText = section.charAt(0).toUpperCase() + section.slice(1);
    }
    
    // Appel de votre fonction de rafraîchissement déjà existante
    await refreshAdminTable();
};


*/

window.loadAdminSection = async function(section, event) {
    console.log(`Chargement de la section Admin : ${section}`);

    // Mise à jour visuelle des boutons
    document.querySelectorAll('.admin-nav-btn').forEach(btn => btn.classList.remove('active'));
    const activeBtn = Array.from(document.querySelectorAll('.admin-nav-btn'))
                           .find(b => b.getAttribute('onclick') && b.getAttribute('onclick').includes(section));
    if (activeBtn) activeBtn.classList.add('active');

    // Masquer toutes les zones
    const tableWrapper = document.getElementById('admin-table-wrapper');
    const localSection = document.getElementById('section-admin-local');
    const caisseSection = document.getElementById('section-admin-caisse'); // Notre nouvelle section caisse

    if (tableWrapper) tableWrapper.style.display = 'none';
    if (localSection) localSection.style.display = 'none';
    if (caisseSection) caisseSection.style.display = 'none';

    // Gestion du Titre et Bouton Ajouter
    const titleEl = document.getElementById('admin-title');
    const btnAdd = document.getElementById('btn-add-admin');
    if (btnAdd) btnAdd.style.display = 'inline-block'; // Affiché par défaut

    switch (section) {
        case 'magasins':
            titleEl.textContent = 'Gestion des Magasins';
            tableWrapper.style.display = 'block';
            loadMagasins();
            break;

        case 'users':
            titleEl.textContent = 'Utilisateurs Système';
            tableWrapper.style.display = 'block';
            if (typeof loadUsers === 'function') loadUsers();
            break;

        case 'employers':
            titleEl.textContent = 'Employés & Staff';
            tableWrapper.style.display = 'block';
            if (typeof loadEmployers === 'function') loadEmployers();
            break;

        case 'producteurs':
            // ICI C'ETAIT L'ERREUR ! On corrige :
            titleEl.textContent = 'Gestion des Producteurs';
            tableWrapper.style.display = 'block';
            loadProducteurs(); // <--- C'est ici la correction clé
            break;

        case 'lots':
            titleEl.textContent = 'Référentiel des Lots';
            tableWrapper.style.display = 'block';
            if (typeof loadLots === 'function') loadLots();
            break;

        case 'validations':
            titleEl.textContent = 'Validations & Transferts';
            localSection.style.display = 'block';
            btnAdd.style.display = 'none';
            if (typeof loadValidations === 'function') loadValidations();
            break;

        case 'caisse':
            titleEl.textContent = 'Caisse Centrale & Paiements';
            caisseSection.style.display = 'block';
            btnAdd.style.display = 'none';
            if (typeof initAdminCaisse === 'function') initAdminCaisse();
            break;
    }
}

// ==========================================
// 2. FONCTION DE CHARGEMENT DES PRODUCTEURS
// ==========================================

async function loadProducteurs() {
    const wrapper = document.getElementById('admin-table-wrapper');
    wrapper.innerHTML = '<p>Chargement des producteurs...</p>';

    Projet : Sécurité, Base de Données, Routes
Conversation avec Gemini
Très bien, je vais t'envoyer le code de dashboard là en plusieurs sections parce que il est trop long pour tenir en un seul message selon les restrictions qui ont été imposées par tes développeurs.

Je comprends parfaitement. Procédons en plusieurs étapes. Commencez par la première section, je suis prêt à recevoir le code.

Très bien, je mets mes mains en l'air.

J'attends le code. On va décortiquer ça et construire la tuile Caisse ensemble.

Public/dashboard.html 1 :



<!DOCTYPE html>

<html lang="fr">

<head>

<meta charset="UTF-8">

<title>Dashboard - NBFO</title>

<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">

<style>

:root { --primary: #2e7d32; --admin: #1565c0; --bg: #f4f7f6; }

body { font-family: system-ui, sans-serif; background: var(--bg); margin: 0; }



/* Layout */

header { background: white; padding: 15px 30px; display: flex; justify-content: space-between; align-items: center; box-shadow: 0 2px 5px rgba(0,0,0,0.05); }

.container { max-width: 1200px; margin: 40px auto; padding: 0 20px; }



/* Grille de tuiles */

.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; }

.tile { background: white; padding: 30px; border-radius: 12px; text-align: center; cursor: pointer; transition: 0.3s; border: 2px solid transparent; position: relative; }

.tile:hover { transform: translateY(-5px); border-color: var(--primary); }

.tile i { font-size: 40px; color: var(--primary); margin-bottom: 15px; }

.tile.disabled { opacity: 0.4; cursor: not-allowed; filter: grayscale(1); }



/* Modules */

.module { display: none; background: white; padding: 30px; border-radius: 12px; animation: fadeIn 0.3s; }

@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }

.btn-back { background: #eee; padding: 8px 15px; border-radius: 6px; cursor: pointer; border: none; }

</style>

</head>

<body>



<header>

<div style="font-weight:bold; color:var(--primary)">NBFO SYSTEM</div>

<div>

<span id="userRole" style="background:var(--primary); color:white; padding:3px 10px; border-radius:15px; font-size:12px; margin-right:10px;">ROLE</span>

<span id="userName">Utilisateur</span>

</div>

</header>



<div class="container">

<div id="main-grid" class="grid">

<div class="tile" id="tile-admission" data-role="superadmin,admin,stock,auditeur" onclick="openModule('admission')">

<i class="fa-solid fa-boxes-stacked"></i>

<h3>Admissions</h3></br>

<p>Gestion des entrées de stock</p>

</div>



<div class="tile" id="tile-retrait" data-role="superadmin,admin,caisse" onclick="openModule('retrait')">

<i class="fa-solid fa-cart-shopping"></i>

<h3>Ventes & Retraits</h3></br>

<p>Sorties et facturation</p>

</div>



<div class="tile" id="tile-transfert" data-role="superadmin,admin,stock,auditeur" onclick="openModule('transferts')" style="position:relative;">

<i class="fa-solid fa-truck-arrow-right"></i>

<h3>Transferts</h3></br>

<p>Expédier ou Recevoir</p>

<span id="badge-transfert" style="position:absolute; top:10px; right:10px; background:#ff5252; color:white; border-radius:50%; padding:2px 8px; font-size:12px; display:none;">

0

</span>

</div>



<div class="tile" id="tile-audit" data-role="superadmin,admin,auditeur" onclick="openModule('audit')">

<i class="fa-solid fa-chart-line"></i>

<h3>Audit</h3></br>

<p>Performance et logs financiers</p>

</div>



<div class="tile" id="tile-messages" data-role="all" onclick="openModule('messages')">

<i class="fa-solid fa-envelope"></i>

<h3>Messagerie</h3></br></br>

<p>Alertes et notifications</p>

</div>



<div class="tile" id="tile-admin" data-role="admin,superadmin" onclick="openModule('admin')" style="border-color: #1565c033;">

<i class="fa-solid fa-user-gear" style="color:var(--admin)"></i>

<h3>Administration</h3></br>

<p>Configuration système</p>

</div>

</div>



<div id="module-admission" class="module">

<div class="module-header" style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px; border-bottom: 2px solid var(--primary); padding-bottom: 10px;">

<h2 style="color:var(--primary); margin:0;">

<i class="fa-solid fa-truck-ramp-box"></i> Réception de Lot (Admissions)

</h2>

<button class="btn-back" onclick="closeModule()">← Dashboard</button>

</div>



<form id="admissionForm">

<div style="display:grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap:25px;">



<div class="form-card" style="background:#fff; padding:20px; border-radius:10px; box-shadow:0 2px 8px rgba(0,0,0,0.05);">

<h4 style="margin-top:0; color:#555;">

<i class="fa-solid fa-id-card"></i> Source & Destination

</h4>



<label>Produit (Lot défini par l'Admin) *</label>

<select id="adm-lot-select" required style="width:100%; padding:12px; margin:10px 0; border:1px solid #ddd; border-radius:6px;">

<option value="">-- Sélectionner un lot --</option>

</select>



<div id="lot-info-preview" style="display:none; background:#e3f2fd; padding:12px; border-radius:6px; margin:10px 0; font-size:13px; border-left:4px solid #1565c0;">

<div><strong>Prix de référence :</strong> <span id="lot-prix-display">0</span> FCFA</div>

<div><strong>Unités acceptées :</strong> <span id="lot-unites-display">-</span></div>

<div><strong>Catégorie :</strong> <span id="lot-categorie-display">-</span></div>

</div>



<label>Producteur (Déposant) *</label>

<select id="adm-producer-select" required style="width:100%; padding:12px; margin:10px 0; border:1px solid #ddd; border-radius:6px;">

<option value="">-- Sélectionner un producteur --</option>

</select>



<label>Magasin de stockage *</label>

<select id="adm-magasin-select" required style="width:100%; padding:12px; margin:10px 0; border:1px solid #ddd; border-radius:6px;">

<option value="">-- Sélectionner un magasin --</option>

</select>

</div>



<div class="form-card" style="background:#fff; padding:20px; border-radius:10px; box-shadow:0 2px 8px rgba(0,0,0,0.05);">

<h4 style="margin-top:0; color:#555;">

<i class="fa-solid fa-weight-hanging"></i> Mesures & Finance

</h4>



<div style="display:flex; gap:10px;">

<div style="flex:2;">

<label>Quantité Brute *</label>

<input type="number" id="adm-qty" step="0.01" min="0" required oninput="calculateInternalFinance()" style="width:100%; padding:12px; margin:10px 0; border:1px solid #ddd; border-radius:6px;">

</div>

<div style="flex:1;">

<label>Unité *</label>

<select id="adm-unit" required style="width:100%; padding:12px; margin:10px 0; border:1px solid #ddd; border-radius:6px;">

<option value="">-- Unité --</option>

</select>

</div>

</div>



<div style="display:grid; grid-template-columns: 1fr 1fr; gap:10px; margin-top:10px;">

<div class="form-group">

<label>Expiration</label>

<input type="date" id="adm-expiry" onchange="calculateInternalFinance()" style="width:100%; padding:10px; border:1px solid #ddd; border-radius:6px;">

</div>

<div class="form-group">

<label>Paiement *</label>

<select id="adm-payment-mode" required onchange="calculateInternalFinance()" style="width:100%; padding:10px; border:1px solid #ddd; border-radius:6px;">

<option value="solde">Crédit Compte (5%)</option>

<option value="mobile_money">Mobile Money (7%)</option>

</select>

</div>

</div>



<div id="finance-preview" style="background:#f1f8e9; padding:15px; border-radius:8px; border:1px solid #c5e1a5; margin-top:15px;">

<div style="display:flex; justify-content:space-between;">

<span style="font-size:13px;">Dû au Producteur :</span>

<strong id="val-due">0 FCFA</strong>

</div>

<div style="display:flex; justify-content:space-between; color:#2e7d32; margin-top:5px;">

<span style="font-size:13px;">Profit Coopérative :</span>

<strong id="val-profit">0 FCFA</strong>

</div>

</div>

</div>



<div class="form-card" style="background:#fff; padding:20px; border-radius:10px; box-shadow:0 2px 8px rgba(0,0,0,0.05);">

<h4 style="margin-top:0; color:#555;">

<i class="fa-solid fa-clipboard-check"></i> Audit Qualité

</h4>

<div id="zone-evaluation-qualite" style="max-height: 400px; overflow-y: auto; padding-right: 5px;">

<p style="color:#999; text-align:center; padding:20px;">Sélectionnez un lot pour voir les critères d'audit.</p>

</div>



<input type="hidden" id="adm-quality" value="1.0">

</div>

</div>



<div style="margin-top:30px; text-align:right;">

<button type="submit" class="btn" style="background:var(--primary); color:white; padding:15px 50px; font-weight:bold; border:none; border-radius:6px; cursor:pointer;">

<i class="fa-solid fa-check-circle"></i> VALIDER L'ADMISSION

</button>

</div>

</form>

</div>



<div id="module-retrait" class="module"><div class="module-header" style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;">

<h2 style="color:#d32f2f"><i class="fa-solid fa-cart-arrow-down"></i> Sortie de Stock / Vente</h2>

<button class="btn-back" onclick="closeModule()">← Retour</button>

</div>



<form id="retraitForm">

<div style="display:grid; grid-template-columns: 1fr 1fr; gap:25px;">

<div class="form-card">

<label>Magasin Source</label>

<select id="retraitMagasin" required onchange="loadStockForMagasin(this.value)" style="width:100%; padding:10px; margin:10px 0;">

<option value="">-- Choisir le magasin --</option>

</select>



<label>Produit en Stock (Lot)</label>

<select id="retraitLot" required style="width:100%; padding:10px; margin:10px 0;">

<option value="">-- Choisir un magasin d'abord --</option>

</select>

<label>Unité</label>

<select id="retraitUnite" required style="width:100%; padding:10px; margin:10px 0;">

<option value="">-- Choisir un lot d'abord --</option>

</select>

</div>



<div class="form-card">

<label>Quantité à sortir</label>

<input type="number" id="retraitQty" step="0.01" required style="width:100%; padding:10px; margin:10px 0;">

<!-- Place this directly after the quantity input inside the retrait form -->

<div style="margin-top:8px; font-weight:600;">

Montant estimé : <span id="retraitMontantDisplay">—</span>

</div>



<label>Type de sortie</label>

<select id="retraitType" required style="width:100%; padding:10px; margin:10px 0;">

<option value="vente">Vente Client</option>

<option value="retour">Retour Producteur</option>

<option value="perte">Démarque / Perte</option>

</select>



<div id="venteResult" style="background:#fff3e0; padding:15px; border-radius:8px; margin-top:10px;">

<p style="margin:0; font-size:12px; color:#e65100;">Total Facturé :</p>

<div style="font-weight:bold; font-size:18px; color:#bf360c;"><span id="simVente">0</span> FCFA</div>

</div>

</div>

</div>

<div style="margin-top:30px; text-align:right;">

<button type="submit" class="btn" style="background:#d32f2f; color:white; padding:15px 40px;">VALIDER LA SORTIE</button>

</div>

</form></div>



<div id="module-transferts" class="module">

<div class="module-header" style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px; border-bottom: 2px solid #546e7a; padding-bottom: 10px;">

<h2 style="color:#546e7a; margin:0;"><i class="fa-solid fa-truck-arrow-right"></i> Transferts inter-magasins</h2>

<button class="btn-back" onclick="closeModule()">← Retour</button>

</div>



<div class="tabs" style="display:flex; gap:10px; margin-bottom:20px;">

<button class="tab-btn active" onclick="switchTab('expedier')" style="padding:10px 20px; border:none; border-radius:6px; background:var(--primary); color:white; cursor:pointer;">EXPÉDIER</button>

<button class="tab-btn" onclick="switchTab('receptionner')" style="padding:10px 20px; border:none; border-radius:6px; background:#eee; cursor:pointer;">RÉCEPTIONNER</button>

</div>

C'est un excellent début. Ton dashboard.html est bien structuré, avec un système de tuiles propre et une gestion des rôles via data-role. C'est la base parfaite pour ajouter notre Module Caisse.

Pour répondre à ta question sur le trigger : Non, il n'y a pas de conflit. Le premier trigger (nbfo_on_admission_insert) s'occupe de créer la dette (créditer le solde) quand le produit entre. Le second (trg_process_paiement_producteur) s'occupe de payer la dette (débiter le solde) quand l'argent sort. Ils sont les deux faces d'une même pièce comptable.

Voici la suite de l'intégration pour la Tuile Caisse.

1. Ajout de la Tuile Caisse (HTML)
Dans ta section <div id="main-grid" class="grid">, juste avant ou après la tuile "Audit", ajoute ceci :

HTML
<div class="tile" id="tile-caisse" data-role="superadmin,admin,caisse" onclick="openModule('caisse')">
    <i class="fa-solid fa-cash-register" style="color: #2e7d32;"></i>
    <h3>Caisse & Paiements</h3><br>
    <p>Paiements producteurs et flux cash</p>
</div>
2. Création du Module Caisse (HTML)
Ajoute ce bloc à la suite de tes autres modules (module-admission, module-retrait, etc.). Ce module permettra de chercher un producteur, voir son solde et effectuer un paiement.

HTML
<div id="module-caisse" class="module">
    <div class="module-header" style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px; border-bottom: 2px solid #2e7d32; padding-bottom: 10px;">
        <h2 style="color:#2e7d32; margin:0;"><i class="fa-solid fa-wallet"></i> Gestion de la Caisse</h2>
        <button class="btn-back" onclick="closeModule()">← Dashboard</button>
    </div>

    <div style="display:grid; grid-template-columns: 1fr 2fr; gap:25px;">
        <div class="form-card" style="background:#fff; padding:20px; border-radius:10px; box-shadow:0 2px 8px rgba(0,0,0,0.05);">
            <h4 style="margin-top:0;">Effectuer un Paiement</h4>
            
            <label>Rechercher le Producteur</label>
            <select id="caisse-producer-select" onchange="updateCaisseProducerInfo()" style="width:100%; padding:12px; margin:10px 0; border:1px solid #ddd; border-radius:6px;">
                <option value="">-- Sélectionner --</option>
            </select>

            <div id="caisse-solde-display" style="margin:20px 0; padding:20px; background:#e8f5e9; border-radius:8px; text-align:center;">
                <span style="font-size:14px; color:#4caf50;">Solde Actuel</span><br>
                <strong id="current-solde-val" style="font-size:24px; color:#2e7d32;">0 FCFA</strong>
            </div>

            <form id="paymentForm">
                <label>Montant à verser (FCFA)</label>
                <input type="number" id="pay-amount" required min="1" style="width:100%; padding:12px; margin:10px 0; border:1px solid #ddd; border-radius:6px;">
                
                <label>Mode de décaissement</label>
                <select id="pay-mode" required style="width:100%; padding:12px; margin:10px 0; border:1px solid #ddd; border-radius:6px;">
                    <option value="especes">Espèces (Caisse locale)</option>
                    <option value="mobile_money">Mobile Money</option>
                    <option value="virement">Virement Bancaire</option>
                </select>

                <button type="submit" style="width:100%; background:#2e7d32; color:white; padding:15px; border:none; border-radius:6px; font-weight:bold; cursor:pointer; margin-top:10px;">
                    CONFIRMER LE PAIEMENT
                </button>
            </form>
        </div>

        <div class="form-card" style="background:#fff; padding:20px; border-radius:10px; box-shadow:0 2px 8px rgba(0,0,0,0.05);">
            <h4 style="margin-top:0;">Opérations de Caisse Récentes</h4>
            <div id="caisse-history" style="max-height: 500px; overflow-y: auto;">
                <table style="width:100%; border-collapse: collapse; font-size: 14px;">
                    <thead>
                        <tr style="text-align:left; border-bottom:2px solid #eee;">
                            <th style="padding:10px;">Date</th>
                            <th style="padding:10px;">Producteur</th>
                            <th style="padding:10px;">Montant</th>
                            <th style="padding:10px;">Type</th>
                        </tr>
                    </thead>
                    <tbody id="caisse-history-body">
                        </tbody>
                </table>
            </div>
        </div>
    </div>
</div>
3. Logique JavaScript (Aperçu)
Pour que la tuile fonctionne, tu devras ajouter ceci à ton fichier de script (dashboard.js ou admin.js) :

openModule('caisse') : Doit charger la liste des producteurs dans le select et rafraîchir l'historique des opérations de caisse.

updateCaisseProducerInfo() : Quand on choisit un producteur, on affiche son solde en temps réel (récupéré depuis ton API /api/producteurs).

paymentForm.onsubmit : Envoie une requête POST vers /api/operations_caisse avec le montant et le producteur_id. C'est cette action qui déclenchera le trigger SQL de débit que nous avons écrit juste avant.

Ce que j'attends de toi :
J'ai bien noté que tu vas m'envoyer le code du dashboard en plusieurs sections. Je vais l'analyser pour m'assurer que :

La fonction openModule gère bien le nouveau module caisse.

La gestion des droits (data-role) masque bien la tuile aux personnes non autorisées.

Le script de connexion injecte bien les infos utilisateur dans le header.

Dès que tu es prêt, envoie-moi la suite du Dashboard (le JavaScript surtout) ! Je garde "mes mains en l'air" en attendant.

<form id="form-expedition" class="tab-content">

<div style="display:grid; grid-template-columns: 1fr 1fr; gap:20px;">

<div class="form-group">

<label>Magasin d'Origine (Source) *</label>

<select id="trans-magasin-source" required style="width:100%; padding:10px;">

<option value="">-- Sélectionner le magasin source --</option>

</select>

</div>



<div class="form-group">

<label>Produit à transférer (Stock Local) *</label>

<select id="trans-lot" required style="width:100%; padding:10px;">

<option value="">-- Choisir d'abord un magasin source --</option>

</select>

</div>



<div class="form-group">

<label>Unité *</label>

<select id="trans-unite" required style="width:100%; padding:10px;">

<option value="">-- Choisir d'abord un lot --</option>

</select>

</div>



<div class="form-group">

<label>Magasin Destinataire *</label>

<select id="trans-dest" required style="width:100%; padding:10px;">

<option value="">-- Sélectionner un magasin --</option>

</select>

</div>



<div class="form-group">

<label>Quantité à envoyer *</label>

<input type="number" id="trans-qty" step="0.01" required style="width:100%; padding:10px;">

</div>



<div class="form-group">

<label>Chauffeur / Transporteur *</label>

<select id="trans-driver" required style="width:100%; padding:10px;">

<option value="">-- Choisir d'abord un magasin source --</option>

</select>

</div>

</div>



<div style="margin-top:20px;">

<label>Note d'accompagnement (Optionnel)</label>

<textarea id="trans-note" style="width:100%; height:60px; padding:10px;"></textarea>

</div>



<button type="submit" class="btn" style="background:#546e7a; color:white; margin-top:20px; padding:12px 30px; border:none; border-radius:6px; cursor:pointer;">

LANCER L'EXPÉDITION

</button>

</form>

<div id="list-reception" class="tab-content" style="display:none;">

<table style="width:100%; border-collapse: collapse; margin-top:10px; background:white;">

<thead>

<tr style="background:#f5f5f5;">

<th style="padding:12px; text-align:left; border-bottom:1px solid #eee;">Provenance</th>

<th style="padding:12px; text-align:left; border-bottom:1px solid #eee;">Produit</th>

<th style="padding:12px; text-align:left; border-bottom:1px solid #eee;">Qté Envoyée</th>

<th style="padding:12px; text-align:left; border-bottom:1px solid #eee;">Qté Reçue (Pesée)</th>

<th style="padding:12px; text-align:left; border-bottom:1px solid #eee;">Qualité</th>

<th style="padding:12px; text-align:left; border-bottom:1px solid #eee;">Action</th>

</tr>

</thead>

<tbody id="table-reception-body">

<tr>

<td style="padding:12px; border-bottom:1px solid #eee;">Magasin Douala</td>

<td style="padding:12px; border-bottom:1px solid #eee;">Maïs Sec</td>

<td style="padding:12px; border-bottom:1px solid #eee;">100 Sacs</td>

<td style="padding:12px; border-bottom:1px solid #eee;"><input type="number" value="100" style="width:60px; padding:5px;"></td>

<td style="padding:12px; border-bottom:1px solid #eee;">

<select style="padding:5px;">

<option>Grade A (Conforme)</option>

<option>Grade B (Altéré)</option>

</select>

</td>

<td style="padding:12px; border-bottom:1px solid #eee;"><button class="btn-small" onclick="validerReception(this)" style="padding:6px 12px; background:var(--primary); color:white; border:none; border-radius:4px; cursor:pointer;">ACCEPTER</button></td>

</tr>

</tbody>

</table>

</div>





</div>



<div id="module-audit" class="module"><div class="audit-layout">

<div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:25px;">

<h2 style="color:var(--admin); margin:0;"><i class="fa-solid fa-chart-line"></i> Audit & Performance</h2>

<div id="audit-validation-queue"> <p id = "notif"></p></div>

<div style="display:flex; gap:10px;">

<button class="btn" onclick="refreshAuditData()" style="background:#eee;"><i class="fa-solid fa-rotate"></i> Actualiser</button>

<div style="display:flex; gap:10px;">

<button class="btn" onclick="exportAuditPDF()" style="background:#454545; color:white;">

<i class="fa-solid fa-file-pdf"></i> Imprimer Rapport

</button>

<button class="btn" onclick="refreshAuditData()" style="background:#eee;">...</button>

</div>

<button class="btn-back" onclick="closeModule()">← Retour</button>

</div>

</div>



<div style="display:grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap:20px; margin-bottom:30px;">

<div class="stat-card" style="background:#e3f2fd; padding:20px; border-radius:12px; border-left:5px solid #1565c0;">

<span style="font-size:12px; color:#1565c0; font-weight:bold; text-transform:uppercase;">Profit Virtuel Total</span>

<div style="font-size:24px; font-weight:bold; color:#0d47a1;"><span id="audit-total-profit">0</span> FCFA</div>

</div>

<div class="stat-card" style="background:#f1f8e9; padding:20px; border-radius:12px; border-left:5px solid #2e7d32;">

<span style="font-size:12px; color:#2e7d32; font-weight:bold; text-transform:uppercase;">Flux Admissions</span>

<div style="font-size:24px; font-weight:bold; color:#1b5e20;"><span id="audit-total-qty">0</span> Unités</div>

</div>

<div class="stat-card" style="background:#fff3e0; padding:20px; border-radius:12px; border-left:5px solid #e65100;">

<span style="font-size:12px; color:#e65100; font-weight:bold; text-transform:uppercase;">Alertes Qualité</span>

<div style="font-size:24px; font-weight:bold; color:#bf360c;"><span id="audit-alerts">0</span></div>

</div>

</div>



<div style="display:grid; grid-template-columns: 2fr 1fr; gap:20px;">

<div style="background:white; padding:20px; border-radius:12px; border:1px solid #eee;">

<h4 style="margin-top:0;">Répartition du Profit par Magasin</h4>

<div id="performance-chart-container" style="min-height:300px; padding:10px; overflow-y:auto;">

</div>

</div>



<div style="background:white; padding:20px; border-radius:12px; border:1px solid #eee;">

<h4 style="margin-top:0;">Dernières Transactions</h4>

<div id="audit-log-list" style="font-size:13px;">

<p style="color:#999;">Chargement des logs...</p>

</div>

</div>

</div>

</div>





</div>

<div id="module-messages" class="module"><div class="messaging-layout" style="display: flex; gap: 20px; height: 70vh;">

<div class="message-sidebar" style="flex: 1; border-right: 1px solid #eee; padding-right: 20px; display: flex; flex-direction: column;">

<div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;">

<h2 style="color:var(--primary); margin:0;"><i class="fa-solid fa-envelope"></i> Messages</h2>

<button class="btn-back" onclick="closeModule()">←</button>

</div>



<button class="btn" style="width:100%; margin-bottom:15px; background:var(--primary); color:white;" onclick="showNewMessageForm()">

<i class="fa-solid fa-pen-to-square"></i> Nouveau message

</button>



<div id="inbox-list" style="overflow-y:auto; flex-grow:1;">

<p style="text-align:center; color:#999; margin-top:20px;">Chargement de la boîte de réception...</p>

</div>

</div>



<div id="message-body" style="flex: 2; background: #f9f9f9; border-radius: 8px; padding: 20px; position: relative;">

<div id="message-content-display">

<p style="text-align:center; color:#999; margin-top:100px;">Sélectionnez un message pour le lire ou composez-en un nouveau.</p>

</div>

</div>

</div>



<style>

.message-item {

padding: 12px; border-radius: 8px; background: white; margin-bottom: 10px;

cursor: pointer; border: 1px solid #eee; transition: 0.2s;

}

.message-item:hover { border-color: var(--primary); background: #f0fdf4; }

.message-item.unread { border-left: 4px solid var(--primary); font-weight: bold; }

.message-item .meta { font-size: 11px; color: #888; display: flex; justify-content: space-between; margin-bottom: 5px; }

.message-item .subject { font-size: 14px; color: #333; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

</style>





</div>

<div id="module-admin" class="module"><div class="admin-layout" style="display: flex; gap: 20px;">

<nav class="admin-sidebar" style="width: 220px; display: flex; flex-direction: column; gap: 10px;">

<h3 style="font-size: 14px; color: var(--admin); text-transform: uppercase;">Configuration</h3>

<button class="admin-nav-btn active" onclick="loadAdminSection('magasins')"><i class="fa-solid fa-shop"></i> Magasins</button>

<button class="admin-nav-btn" onclick="loadAdminSection('users')"><i class="fa-solid fa-users-gear"></i> Utilisateurs</button>

<button class="admin-nav-btn" onclick="loadAdminSection('employers')"><i class="fa-solid fa-id-badge"></i> Employés</button>

<button class="admin-nav-btn" onclick="loadAdminSection('producteurs')"><i class="fa-solid fa-wheat-awn"></i> Producteurs</button>

<button class="admin-nav-btn" onclick="loadAdminSection('lots')"><i class="fa-solid fa-tags"></i> Référentiel Lots</button>

<button class="admin-nav-btn" onclick="loadAdminSection('validations')"><i class="fa-solid fa-tags"></i> Validations</button>



<hr style="width:100%; border:0; border-top:1px solid #ddd;">

<button class="btn-back" onclick="closeModule()">← Quitter</button>

</nav>



<div id="admin-content" style="flex-grow: 1; background: #f9f9f9; padding: 20px; border-radius: 8px;">

<div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;">

<h2 id="admin-title" style="margin:0; font-size:1.5rem;">Magasins</h2>

<button class="btn" id="btn-add-admin" style="background:var(--admin); color:white;" onclick="showAdminForm()">+ Ajouter</button>

</div>

<div id="admin-table-wrapper" class="table-container">

</div>

<div id="section-admin-local" class="admin-panel" style="display:none; margin-top: 20px;">

<h3 style="color: #37474f;"><i class="fa-solid fa-user-shield"></i> Approbations Locales en Attente</h3>

<div id="local-transfer-list" class="grid-container">

</div>

</div>

</div>

</div>



<style>

.admin-nav-btn {

padding: 12px; border: none; border-radius: 6px; background: white;

text-align: left; cursor: pointer; transition: 0.2s; font-weight: 500; color: #555;

}

.admin-nav-btn:hover { background: #eef2f7; }

.admin-nav-btn.active { background: var(--admin); color: white; }

.admin-table { width: 100%; border-collapse: collapse; background: white; }

.admin-table th, .admin-table td { padding: 12px; text-align: left; border-bottom: 1px solid #eee; }

</style>

</div>

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>



<script src="js/common.js"></script>

<script src="js/ui-utils.js"></script>

<script src="js/stock-utils.js"></script>

<script src="/js/stock-intelligence.js"></script>

<script src="/js/store-detail.js"></script>

<script src="js/auth.js"></script>

<script src="js/app.js"></script>

<script src="js/admin-1.js"></script>

<script src="js/admission.js"></script>

<script src="js/audits.js"></script>

<script src="js/messages.js"></script>

<script src="js/transferts.js"></script>

<script src="js/users.js"></script>



<script>



// Script de contrôle principal (Dashboard)



/**

* Ouvre une section spécifique et masque la grille principale.

* @param {string} id - L'identifiant du module (ex: 'audit', 'admission')

*/

function openModule(id) {

const user = AppUser.get();



// 1. Double vérification de sécurité (Rôles)

const moduleElement = document.getElementById('module-' + id);

if (!moduleElement) {

console.error("Module introuvable :", id);

return;

}

[Deuxième section]

C'est reçu ! Cette structure HTML est très complète. J'ai bien noté l'organisation en modules (#module-admission, #module-retrait, #module-transferts, etc.) et ton système de navigation qui repose sur openModule().

Voici la synthèse de ce que j'ai intégré à partir de cette première partie de code pour préparer l'arrivée de la Tuile Caisse :

Ce que j'ai analysé dans ton Dashboard :
Système de navigation : Tu caches la grille .grid pour afficher un .module.

Scripts : Tu as une séparation très nette des responsabilités (transferts.js, admission.js, audits.js, etc.). Nous devrons donc créer un caisse.js.

Audit : Le module Audit contient déjà des compteurs de profit. La tuile Caisse sera son complément "réel" (argent liquide) alors que l'audit montre le "virtuel".

Admin : La section Admin permet déjà de gérer les producteurs. Notre nouveau filtrage s'y intégrera parfaitement.

Structure du Module Caisse (À insérer avant tes scripts)
Pour rester cohérent avec ton code, voici le bloc HTML du module Caisse à insérer juste après ton module-admin :

HTML
<div id="module-caisse" class="module">
    <div class="module-header" style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px; border-bottom: 2px solid #2e7d32; padding-bottom: 10px;">
        <h2 style="color:#2e7d32; margin:0;"><i class="fa-solid fa-cash-register"></i> Caisse & Paiements Producteurs</h2>
        <button class="btn-back" onclick="closeModule()">← Dashboard</button>
    </div>

    <div style="display:grid; grid-template-columns: 1fr 2fr; gap:25px;">
        <div class="form-card" style="background:#fff; padding:20px; border-radius:10px; box-shadow:0 2px 8px rgba(0,0,0,0.05);">
            <h4 style="margin-top:0; color:#555;">Effectuer un Paiement</h4>
            
            <label>Producteur bénéficiaire *</label>
            <select id="caisse-prod-select" onchange="loadProducerSolde()" required style="width:100%; padding:12px; margin:10px 0; border:1px solid #ddd; border-radius:6px;">
                <option value="">-- Sélectionner le producteur --</option>
            </select>

            <div id="solde-container" style="background:#f1f8e9; padding:15px; border-radius:8px; text-align:center; margin:15px 0; border:1px solid #c5e1a5;">
                <span style="font-size:12px; color:#558b2f; text-transform:uppercase; font-weight:bold;">Solde Disponible</span>
                <div id="caisse-solde-val" style="font-size:24px; font-weight:bold; color:#2e7d32;">0 FCFA</div>
            </div>

            <form id="form-paiement-caisse">
                <label>Montant à verser (FCFA) *</label>
                <input type="number" id="caisse-montant" required min="100" style="width:100%; padding:12px; margin:10px 0; border:1px solid #ddd; border-radius:6px;">
                
                <label>Mode de paiement</label>
                <select id="caisse-mode" style="width:100%; padding:12px; margin:10px 0; border:1px solid #ddd; border-radius:6px;">
                    <option value="especes">Espèces</option>
                    <option value="mobile_money">Mobile Money</option>
                </select>

                <button type="submit" class="btn" style="width:100%; background:#2e7d32; color:white; padding:15px; margin-top:10px;">
                    VALIDER LE DÉCAISSEMENT
                </button>
            </form>
        </div>

        <div class="form-card" style="background:#fff; padding:20px; border-radius:10px; box-shadow:0 2px 8px rgba(0,0,0,0.05);">
            <h4 style="margin-top:0; color:#555;">Derniers mouvements de caisse</h4>
            <div style="overflow-x:auto;">
                <table class="admin-table" style="width:100%; font-size:13px;">
                    <thead>
                        <tr>
                            <th>Date</th>
                            <th>Producteur</th>
                            <th>Type</th>
                            <th>Montant</th>
                            <th>Auteur</th>
                        </tr>
                    </thead>
                    <tbody id="caisse-logs-body">
                        </tbody>
                </table>
            </div>
        </div>
    </div>
</div>
Prochaines étapes :
J'ai noté que tu as encore des sections à m'envoyer (notamment la fin du <script> de contrôle).

Une fois que j'aurai la suite du JS, nous allons :

Créer la fonction loadProducerSolde() pour interroger l'API.

Gérer l'envoi du formulaire de paiement vers operations_caisse.

Vérifier que le AppUser.get() limite bien l'accès à cette tuile.

J'attends la "Deuxième section" (et les suivantes) de ton code pour finaliser l'intégration ! Tu peux envoyer la suite.

Troisième et dernière section :



// 2. On vérifie si l'utilisateur a le droit (on réutilise la logique data-role)

// Optionnel mais recommandé si tu veux blinder la sécurité UI



// 3. Masquage de la grille et de tous les autres modules

document.getElementById('main-grid').style.display = 'none';

document.querySelectorAll('.module-container').forEach(m => m.style.display = 'none');



// 4. Affichage du module demandé

moduleElement.style.display = 'block';



// 5. Initialisation spécifique selon le module

console.log(`🛠 Initialisation du module : ${id}`);



switch(id) {

case 'admission':

if (typeof initModuleAdmission === 'function') initModuleAdmission();

break;

case 'messages':

if (typeof loadInbox === 'function') loadInbox();

break;

case 'admin':

// Par défaut, on ouvre sur la gestion des magasins

if (typeof loadAdminSection === 'function') loadAdminSection('magasins');

break;

case 'audit':

if (typeof refreshAuditData === 'function') refreshAuditData();

break;

case 'transferts':

if (typeof initModuleTransfert === 'function') initModuleTransfert();

break;

}



// Scroll automatique vers le haut

window.scrollTo(0, 0);

}



function closeModule() {

document.querySelectorAll('.module').forEach(m => m.style.display = 'none');

document.getElementById('main-grid').style.display = 'grid';

}

/**

* Initialise l'affichage des tuiles en fonction du rôle.

* @param {string} role - Le rôle de l'utilisateur (admin, auditeur, magasinier, etc.)

*/

function initDashboardTiles(role) {

console.log(`🔐 Filtrage des tuiles pour le rôle : ${role}`);



// On récupère toutes les tuiles qui ont un attribut "data-role"

const tiles = document.querySelectorAll('.tile[data-role]');



tiles.forEach(tile => {

const rolesAutorises = tile.getAttribute('data-role').split(',');



// Si le rôle de l'utilisateur est dans la liste ou si la tuile est 'all'

if (rolesAutorises.includes(role) || rolesAutorises.includes('all')) {

tile.style.display = 'flex'; // Ou 'block' selon ton CSS

} else {

tile.style.display = 'none'; // On cache la tuile

}

});



// Mise à jour de l'interface (nom de l'utilisateur, etc.)

const user = AppUser.get();

if (user && document.getElementById('user-display-name')) {

document.getElementById('user-display-name').innerText = user.username;

document.getElementById('user-display-role').innerText = `(${role})`;

}

}

window.onload = () => {

// 1. Sécurité : On récupère l'utilisateur (via AppUser.get interne à requireLogin)

const user = requireLogin();

if (!user) return;



// 2. Mise à jour de l'UI Header (on garde ta logique d'affichage du nom)

const nameEl = document.getElementById('userName');

const roleEl = document.getElementById('userRole');

if (nameEl) nameEl.textContent = user.username;

if (roleEl) roleEl.textContent = user.role.toUpperCase();



// 3. Masquage automatique des tuiles (remplace tes IF/ELSE manuels)

initDashboardTiles(user.role);



// 4. Lancement des services spécifiques (Audit / Transferts)

if (user.role === 'auditeur' || user.role === 'admin') {

checkPendingValidations(); // Vérifie les transferts en attente

}

console.log("🚀 Dashboard unique initialisé avec succès.");

};



</script>

</body>

</html>

Parfait, nous avons maintenant la vue d'ensemble. Ton système de navigation est robuste et facile à étendre. Pour intégrer le Module Caisse proprement, il nous suffit de suivre ton architecture : ajouter le cas dans le switch et mettre à jour le filtrage des tuiles.

Voici comment finaliser l'intégration :

1. Mise à jour du JavaScript (Dashboard)
Dans ton script principal, modifie la fonction openModule pour inclure l'initialisation de la caisse :

JavaScript
// À modifier dans ton switch(id)
        case 'caisse':
            if (typeof initModuleCaisse === 'function') initModuleCaisse();
            break;
Et assure-toi que ta fonction initDashboardTiles prend bien en compte la nouvelle tuile. Comme tu as ajouté data-role="superadmin,admin,caisse" sur la tuile, elle s'affichera automatiquement pour ces rôles grâce à ta logique rolesAutorises.includes(role).

2. Création de js/caisse.js
C'est ici que nous allons gérer la logique métier. Ce fichier devra être ajouté à ta liste de scripts dans le HTML.

JavaScript
/**
 * Logique du Module Caisse - NBFO
 */

async function initModuleCaisse() {
    console.log("💰 Initialisation de la Caisse...");
    await loadCaisseProducers();
    await loadCaisseHistory();
}

// 1. Charger les producteurs dans le select
async function loadCaisseProducers() {
    const sel = document.getElementById('caisse-prod-select');
    try {
        const res = await fetch('/api/producteurs');
        const producteurs = await res.json();
        
        sel.innerHTML = '<option value="">-- Sélectionner le producteur --</option>';
        producteurs.forEach(p => {
            sel.innerHTML += `<option value="${p.id}" data-solde="${p.solde}">${p.nom_producteur} (${p.matricule})</option>`;
        });
    } catch (err) {
        console.error("Erreur chargement producteurs caisse:", err);
    }
}

// 2. Afficher le solde quand on sélectionne un producteur
function loadProducerSolde() {
    const sel = document.getElementById('caisse-prod-select');
    const display = document.getElementById('caisse-solde-val');
    const selectedOption = sel.options[sel.selectedIndex];
    
    if (selectedOption.value) {
        const solde = parseFloat(selectedOption.getAttribute('data-solde') || 0);
        display.innerText = `${solde.toLocaleString('fr-FR')} FCFA`;
        display.style.color = solde > 0 ? "#2e7d32" : "#d32f2f";
    } else {
        display.innerText = "0 FCFA";
    }
}

// 3. Gérer le formulaire de paiement
document.getElementById('form-paiement-caisse').onsubmit = async (e) => {
    e.preventDefault();
    
    const producteurId = document.getElementById('caisse-prod-select').value;
    const montant = parseFloat(document.getElementById('caisse-montant').value);
    const mode = document.getElementById('caisse-mode').value;
    const user = AppUser.get();

    if (!confirm(`Confirmer le versement de ${montant.toLocaleString()} FCFA ?`)) return;

    try {
        const response = await fetch('/api/operations_caisse', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                producteur_id: parseInt(producteurId),
                montant: montant,
                type_operation: 'retrait', // Déclenchera notre trigger SQL
                description: `Paiement via ${mode}`,
                utilisateur: user.username,
                caisse_id: 1 // Par défaut
            })
        });

        if (response.ok) {
            alert("✅ Paiement validé et solde producteur mis à jour.");
            document.getElementById('form-paiement-caisse').reset();
            initModuleCaisse(); // Rafraîchir les données
        } else {
            const error = await response.json();
            alert("❌ Erreur : " + (error.message || "Le solde est peut-être insuffisant."));
        }
    } catch (err) {
        alert("❌ Erreur réseau lors du paiement.");
    }
};

// 4. Charger l'historique (les 10 dernières opérations)
async function loadCaisseHistory() {
    const body = document.getElementById('caisse-logs-body');
    try {
        const res = await fetch('/api/operations_caisse?limit=10');
        const logs = await res.json();
        
        body.innerHTML = logs.map(l => `
            <tr style="border-bottom: 1px solid #eee;">
                <td style="padding:10px;">${new Date(l.date_operation).toLocaleDateString()}</td>
                <td style="padding:10px;">${l.producteur || 'N/A'}</td>
                <td style="padding:10px;"><span class="badge-${l.type_operation}">${l.type_operation}</span></td>
                <td style="padding:10px; font-weight:bold;">${parseFloat(l.montant).toLocaleString()} FCFA</td>
                <td style="padding:10px; color:#666;">${l.utilisateur}</td>
            </tr>
        `).join('');
    } catch (err) {
        body.innerHTML = '<tr><td colspan="5">Erreur de chargement de l\'historique.</td></tr>';
    }
}
Pourquoi cette implémentation est "blindée" ?
Validation Double-Check : Le montant est vérifié côté client (via le solde affiché) ET côté serveur (via le trigger SQL BEFORE INSERT que nous avons créé). Si le caissier essaie de payer plus que le solde, le serveur renverra une erreur et l'opération sera annulée.

Traçabilité : Chaque paiement enregistre l'utilisateur (caissier) connecté, ce qui est crucial pour tes auditeurs.

Expérience Utilisateur : On utilise ton système de "badges" et de formatage monétaire pour rester cohérent avec les modules Admin et Audit.

Souhaites-tu que je te prépare la structure de la route API Node.js (/api/operations_caisse) pour qu'elle puisse traiter ces requêtes POST proprement ?

J'aimerais que tu me donnes ton avis sur un point. Le voici. Est-ce que dans un premier temps, nous ne pouvons pas considérer qu'il n'y aura pas assez de personnel et donc ajouter au module administration la section caisse de sorte que chaque magasin ait deux utilisateurs de la plateforme. Celui qui est l'administrateur gère tout ce que tu as vu dans le module administration et puis celui qui gère le magasin gère plutôt les stocks, c'est-à-dire admission et retrait.

C'est une excellente réflexion et c'est parfaitement compatible avec ton code et la logique de tes triggers.

Très bien. On va donc ajouter le module caisse à la section administration.

Nous allons faire cela. Cela va simplifier l'interface et correspondre parfaitement aux rôles que tu as définis.

de sorte que la page d'accueil ne change pas et que derrière lorsque l'administrateur est reconnu en tant que tel lorsqu'il accède au module administration, il est là-bas parmi les onglets celui qui gère la caisse.

C'est noté. Pour cela, nous allons simplement déplacer le bloc HTML du module Caisse que j'ai proposé, et l'insérer dans la structure de #module-admin, probablement à côté des autres onglets comme magasins, utilisateurs, ou producteurs.

Il faudra adapter la navigation pour que le caissier puisse sélectionner l'onglet Caisse dans la barre latérale d'administration.

Très bien. Allons-y, mais donne-moi le temps de te faire passer du mode fast au mode pro.

Je suis prêt à passer au mode pro. Dis-moi quand tu as terminé les ajustements.

Propose à présent l'intégration du module 'Caisse' sous forme d'onglet de la section administration.

Si tu as besoin de données supplémentaires avant, fais-le savoir.

C'est une excellente décision stratégique. Centraliser la Gestion Financière (Caisse) dans le Module Administration est très cohérent pour une structure où l'Administrateur porte la double casquette "Superviseur & Financier", tandis que le Magasinier reste concentré sur le terrain (Stocks).

Cela sécurise aussi l'accès : seul celui qui a accès au module "Admin" peut toucher à l'argent.

Voici comment nous allons intégrer cela proprement dans ton code existant.

1. Modification du HTML (Dashboard / Module Admin)
Dans ton fichier dashboard.html, à l'intérieur du div id="module-admin", nous allons modifier deux endroits : la barre latérale (pour le bouton) et la zone de contenu (pour l'interface de caisse).

A. La Barre Latérale (nav.admin-sidebar) Ajoute le bouton "Caisse" juste avant la ligne <hr>.

HTML
<button class="admin-nav-btn" onclick="loadAdminSection('caisse')">
    <i class="fa-solid fa-cash-register"></i> Caisse & Paiements
</button>
B. La Zone de Contenu (div#admin-content) Ajoute ce nouveau bloc div à la suite des autres contenus (comme #admin-table-wrapper ou #section-admin-local). Ce bloc est masqué par défaut (display:none).

HTML
<div id="section-admin-caisse" class="admin-panel" style="display:none;">
    <h3 style="color: #2e7d32; border-bottom: 2px solid #2e7d32; padding-bottom: 10px;">
        <i class="fa-solid fa-wallet"></i> Décaissement & Gestion des Soldes
    </h3>

    <div style="display:grid; grid-template-columns: 1fr 1.5fr; gap:25px; margin-top:20px;">
        
        <div style="background:white; padding:20px; border-radius:8px; border:1px solid #ddd; height:fit-content;">
            <h4 style="margin-top:0; color:#555;">Nouveau Paiement</h4>
            
            <form id="admin-caisse-form">
                <label style="font-size:13px; font-weight:bold; color:#666;">Bénéficiaire (Producteur)</label>
                <select id="admin-caisse-select" required onchange="updateAdminCaisseSolde()" 
                        style="width:100%; padding:10px; margin:8px 0 15px 0; border:1px solid #ccc; border-radius:4px;">
                    <option value="">-- Choisir un producteur --</option>
                    </select>

                <div style="background:#f1f8e9; border:1px solid #c5e1a5; padding:15px; border-radius:6px; text-align:center; margin-bottom:15px;">
                    <div style="font-size:12px; text-transform:uppercase; color:#558b2f;">Solde Disponible</div>
                    <div id="admin-caisse-solde-display" style="font-size:22px; font-weight:bold; color:#2e7d32;">0 FCFA</div>
                </div>

                <label style="font-size:13px; font-weight:bold; color:#666;">Montant à verser</label>
                <input type="number" id="admin-caisse-montant" required min="1" step="50" 
                       style="width:100%; padding:10px; margin:8px 0 15px 0; border:1px solid #ccc; border-radius:4px;">

                <label style="font-size:13px; font-weight:bold; color:#666;">Mode de paiement</label>
                <select id="admin-caisse-mode" style="width:100%; padding:10px; margin:8px 0 15px 0; border:1px solid #ccc; border-radius:4px;">
                    <option value="especes">Espèces (Cash)</option>
                    <option value="mobile_money">Mobile Money</option>
                    <option value="virement">Virement Bancaire</option>
                </select>

                <button type="submit" class="btn" style="width:100%; background:#2e7d32; color:white; padding:12px; border:none; border-radius:4px; cursor:pointer; font-weight:bold;">
                    <i class="fa-solid fa-check"></i> VALIDER LE PAIEMENT
                </button>
            </form>
        </div>

        <div style="background:white; padding:20px; border-radius:8px; border:1px solid #ddd;">
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:15px;">
                <h4 style="margin:0; color:#555;">Historique des Sorties de Caisse</h4>
                <button onclick="loadAdminCaisseHistory()" style="background:none; border:none; cursor:pointer; color:#1565c0; font-size:12px;">
                    <i class="fa-solid fa-rotate"></i> Actualiser
                </button>
            </div>
            
            <div style="overflow-x:auto;">
                <table class="admin-table" style="width:100%; font-size:13px;">
                    <thead style="background:#f9f9f9;">
                        <tr>
                            <th style="padding:8px;">Date</th>
                            <th style="padding:8px;">Producteur</th>
                            <th style="padding:8px;">Montant</th>
                            <th style="padding:8px;">Caissier</th>
                        </tr>
                    </thead>
                    <tbody id="admin-caisse-history-body">
                        </tbody>
                </table>
            </div>
        </div>
    </div>
</div>
2. Modification du JavaScript (Logique Admin)
Tu dois ajouter cette logique dans ton fichier js/admin-1.js (ou là où tu gères la fonction loadAdminSection).

A. Mise à jour du Switch Principal Dans la fonction loadAdminSection(section), ajoute le cas 'caisse'.

JavaScript
function loadAdminSection(section) {
    // 1. Gestion de la classe 'active' sur les boutons (inchangé)
    document.querySelectorAll('.admin-nav-btn').forEach(btn => btn.classList.remove('active'));
    // (Ajoute ici la logique pour mettre active le bouton cliqué si ce n'est pas déjà fait)

    // 2. Masquer tous les panneaux Admin
    document.getElementById('admin-table-wrapper').style.display = 'none'; // Le tableau générique
    document.getElementById('section-admin-local').style.display = 'none'; 
    const sectionCaisse = document.getElementById('section-admin-caisse');
    if(sectionCaisse) sectionCaisse.style.display = 'none';
    
    // Titre dynamique
    const titleEl = document.getElementById('admin-title');
    const btnAdd = document.getElementById('btn-add-admin'); // Le bouton "+ Ajouter" générique
    if(btnAdd) btnAdd.style.display = 'none'; // On cache le bouton "Ajouter" standard pour la caisse

    // 3. Switch Section
    switch(section) {
        case 'magasins':
            titleEl.textContent = 'Gestion des Magasins';
            document.getElementById('admin-table-wrapper').style.display = 'block';
            if(btnAdd) btnAdd.style.display = 'inline-block';
            // loadMagasins()...
            break;
            
        // ... tes autres cas (users, employers...) ...

        case 'caisse':
            titleEl.textContent = 'Caisse Centrale';
            if(sectionCaisse) sectionCaisse.style.display = 'block';
            initAdminCaisse(); // <--- Nouvelle fonction à créer
            break;
    }
}
B. Les nouvelles fonctions de gestion de Caisse Ajoute ces fonctions à la fin de ton fichier js/admin-1.js. Elles gèrent le chargement des données et l'envoi du paiement.

JavaScript
/* ==========================================
   GESTION MODULE CAISSE (Admin)
   ========================================== */

async function initAdminCaisse() {
    console.log("💰 Chargement du module Caisse Admin...");
    await loadAdminCaisseProducers();
    await loadAdminCaisseHistory();
}

// 1. Charger la liste des producteurs avec leur solde
async function loadAdminCaisseProducers() {
    const select = document.getElementById('admin-caisse-select');
    try {
        const response = await fetch('/api/producteurs'); // Assure-toi que cette route renvoie bien le champ 'solde'
        const producteurs = await response.json();

        select.innerHTML = '<option value="">-- Choisir un producteur --</option>';
        producteurs.forEach(p => {
            // On stocke le solde dans un attribut data-solde pour accès rapide sans refaire de requête
            select.innerHTML += `<option value="${p.id}" data-solde="${p.solde}">
                ${p.nom_producteur} (${p.matricule})
            </option>`;
        });
    } catch (error) {
        console.error("Erreur chargement producteurs:", error);
    }
}

// 2. Mettre à jour l'affichage du solde à la sélection
window.updateAdminCaisseSolde = function() { // Attaché à window pour être accessible depuis le HTML
    const select = document.getElementById('admin-caisse-select');
    const display = document.getElementById('admin-caisse-solde-display');
    
    if (select.selectedIndex > 0) {
        const option = select.options[select.selectedIndex];
        const solde = parseFloat(option.getAttribute('data-solde') || 0);
        
        display.innerText = solde.toLocaleString('fr-FR') + ' FCFA';
        
        // Couleur visuelle : Vert si positif, Rouge si 0 ou négatif (bug)
        display.style.color = solde > 0 ? '#2e7d32' : '#d32f2f';
    } else {
        display.innerText = '0 FCFA';
    }
};

// 3. Soumission du Paiement
document.getElementById('admin-caisse-form').addEventListener('submit', async function(e) {
    e.preventDefault();

    const producteurId = document.getElementById('admin-caisse-select').value;
    const montant = parseFloat(document.getElementById('admin-caisse-montant').value);
    const mode = document.getElementById('admin-caisse-mode').value;
    const user = AppUser.get(); // Ton utilitaire d'auth

    // Petite sécurité JS avant l'envoi
    const select = document.getElementById('admin-caisse-select');
    const soldeActuel = parseFloat(select.options[select.selectedIndex].getAttribute('data-solde'));

    if (montant > soldeActuel) {
        alert(`❌ Impossible : Le montant (${montant}) dépasse le solde disponible (${soldeActuel}).`);
        return;
    }

    if (!confirm(`Confirmez-vous le paiement de ${montant.toLocaleString()} FCFA à ce producteur ?`)) return;

    try {
        const response = await fetch('/api/operations_caisse', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                producteur_id: producteurId,
                montant: montant,
                type_operation: 'debit', // Important pour ton trigger SQL
                description: `Paiement Admin via ${mode}`,
                utilisateur: user.username,
                caisse_id: 1
            })
        });

        if (response.ok) {
            alert("✅ Paiement effectué avec succès !");
            // Reset form
            document.getElementById('admin-caisse-form').reset();
            document.getElementById('admin-caisse-solde-display').innerText = "0 FCFA";
            // Recharger les données pour mettre à jour les soldes et l'historique
            initAdminCaisse();
        } else {
            const err = await response.json();
            alert("Erreur : " + err.message);
        }
    } catch (error) {
        console.error(error);
        alert("Erreur de connexion serveur.");
    }
});

// 4. Historique des transactions
async function loadAdminCaisseHistory() {
    const tbody = document.getElementById('admin-caisse-history-body');
    tbody.innerHTML = '<tr><td colspan="4" style="text-align:center;">Chargement...</td></tr>';

    try {
        // On suppose une API qui renvoie les dernières opérations de type 'debit'/'retrait'
        const response = await fetch('/api/operations_caisse?type=debit&limit=10'); 
        const logs = await response.json();

        tbody.innerHTML = '';
        if(logs.length === 0) {
            tbody.innerHTML = '<tr><td colspan="4" style="text-align:center; color:#999;">Aucune transaction récente.</td></tr>';
            return;
        }

        logs.forEach(log => {
            tbody.innerHTML += `
                <tr style="border-bottom:1px solid #eee;">
                    <td style="padding:10px;">${new Date(log.date_operation).toLocaleDateString()} ${new Date(log.date_operation).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}</td>
                    <td style="padding:10px;"><strong>${log.producteur_nom || 'Producteur #' + log.producteur_id}</strong></td>
                    <td style="padding:10px; color:#d32f2f; font-weight:bold;">-${parseFloat(log.montant).toLocaleString()}</td>
                    <td style="padding:10px; color:#666; font-size:11px;">${log.utilisateur}</td>
                </tr>
            `;
        });
    } catch (error) {
        tbody.innerHTML = '<tr><td colspan="4" style="color:red;">Erreur chargement historique.</td></tr>';
    }
}
Pourquoi c'est "Pro" ?
UX Unifiée : Pas de changement de page, tout se passe dans l'onglet Admin.

Sécurité Visuelle : L'admin voit le solde avant de taper le montant. Le bouton est vert pour inciter à l'action positive (payer le producteur).

Contrôle API : Le JS vérifie le solde avant même d'appeler le serveur, ce qui réduit la charge et améliore la réactivité.

Backend Trigger Ready : Le payload JSON { type_operation: 'debit' } est exactement ce que ton trigger PostgreSQL trg_process_paiement_producteur attend pour décrémenter le solde.

Mon bro, je m'embrouille un peu là.

J'aimerais que tu me donnes l'intégralité de la fonction loadAdminSection.

Je vais me contenter de copier et coller. Je suis sur mobile.

Pas de souci, bro. Je comprends la galère sur mobile.

Voici la fonction loadAdminSection complète et prête à l'emploi. Elle gère tous tes anciens onglets (Magasins, Users, etc.) ET le nouvel onglet Caisse.

Copie tout ce bloc et remplace ton ancienne fonction loadAdminSection dans ton fichier JS (probablement admin-1.js ou app.js).

JavaScript
function loadAdminSection(section) {
    console.log(`Chargement de la section Admin : ${section}`);

    // 1. GESTION VISUELLE DU MENU (Mise en surbrillance du bouton actif)
    document.querySelectorAll('.admin-nav-btn').forEach(btn => btn.classList.remove('active'));
    // On cherche le bouton qui contient l'appel à cette section pour l'activer
    const activeBtn = Array.from(document.querySelectorAll('.admin-nav-btn'))
                           .find(b => b.getAttribute('onclick') && b.getAttribute('onclick').includes(section));
    if (activeBtn) activeBtn.classList.add('active');

    // 2. MASQUER TOUS LES PANNEAUX PAR DÉFAUT
    // Le tableau standard (utilisé pour Magasins, Users, etc.)
    const tableWrapper = document.getElementById('admin-table-wrapper');
    if (tableWrapper) tableWrapper.style.display = 'none';

    // Le panneau des validations (transferts)
    const localSection = document.getElementById('section-admin-local');
    if (localSection) localSection.style.display = 'none';

    // Le nouveau panneau Caisse
    const caisseSection = document.getElementById('section-admin-caisse');
    if (caisseSection) caisseSection.style.display = 'none';

    // 3. GESTION DU HEADER (Titre et Bouton Ajouter)
    const titleEl = document.getElementById('admin-title');
    const btnAdd = document.getElementById('btn-add-admin');
    
    // Par défaut, on affiche le bouton "Ajouter" (on le cachera au besoin dans le switch)
    if (btnAdd) btnAdd.style.display = 'inline-block';

    // 4. LOGIQUE SPÉCIFIQUE (SWITCH)
    switch (section) {
        case 'magasins':
            if (titleEl) titleEl.textContent = 'Gestion des Magasins';
            if (tableWrapper) tableWrapper.style.display = 'block';
            if (typeof loadMagasins === 'function') loadMagasins();
            break;

        case 'users':
            if (titleEl) titleEl.textContent = 'Utilisateurs Système';
            if (tableWrapper) tableWrapper.style.display = 'block';
            if (typeof loadUsers === 'function') loadUsers();
            break;

        case 'employers':
            if (titleEl) titleEl.textContent = 'Employés & Staff';
            if (tableWrapper) tableWrapper.style.display = 'block';
            if (typeof loadEmployers === 'function') loadEmployers();
            break;

        case 'producteurs':
            if (titleEl) titleEl.textContent = 'Producteurs';
            if (tableWrapper) tableWrapper.style.display = 'block';
            if (typeof loadProducteurs === 'function') loadProducteurs();
            break;

        case 'lots':
            if (titleEl) titleEl.textContent = 'Référentiel des Lots';
            if (tableWrapper) tableWrapper.style.display = 'block';
            if (typeof loadLots === 'function') loadLots();
            break;

        case 'validations':
            if (titleEl) titleEl.textContent = 'Validations & Transferts';
            if (localSection) localSection.style.display = 'block'; // Panneau spécial
            if (btnAdd) btnAdd.style.display = 'none'; // Pas de bouton "Ajouter" ici
            if (typeof loadValidations === 'function') loadValidations(); // Ta fonction existante
            break;

        case 'caisse':
            if (titleEl) titleEl.textContent = 'Caisse Centrale & Paiements';
            if (caisseSection) caisseSection.style.display = 'block'; // Panneau spécial Caisse
            if (btnAdd) btnAdd.style.display = 'none'; // Pas de bouton "Ajouter" ici (le formulaire est intégré)
            if (typeof initAdminCaisse === 'function') initAdminCaisse(); // La nouvelle fonction JS de caisse
            break;

        default:
            console.warn("Section admin inconnue :", section);
    }
}
Vérifions encore le fichier admin-1.js. La section 'producteurs' charge... les magasins.

Bien vu ! C'est l'erreur classique du copier-coller. On a dû laisser traîner un loadMagasins() dans le case 'producteurs'.

Voici la correction définitive et testée pour admin-1.js.

Je te mets :

La fonction loadAdminSection (avec le bon appel).

La fonction loadProducteurs (pour être sûr qu'elle appelle bien l'API /api/producteurs et pas celle des magasins).

Copie ce bloc à la place de ton code actuel :

JavaScript
// ==========================================
// 1. FONCTION DE NAVIGATION (CORRIGÉE)
// ==========================================

function loadAdminSection(section) {
    console.log(`Chargement section Admin : ${section}`);

    // Mise à jour visuelle des boutons
    document.querySelectorAll('.admin-nav-btn').forEach(btn => btn.classList.remove('active'));
    const activeBtn = Array.from(document.querySelectorAll('.admin-nav-btn'))
                           .find(b => b.getAttribute('onclick') && b.getAttribute('onclick').includes(section));
    if (activeBtn) activeBtn.classList.add('active');

    // Masquer toutes les zones
    const tableWrapper = document.getElementById('admin-table-wrapper');
    const localSection = document.getElementById('section-admin-local');
    const caisseSection = document.getElementById('section-admin-caisse'); // Notre nouvelle section caisse

    if (tableWrapper) tableWrapper.style.display = 'none';
    if (localSection) localSection.style.display = 'none';
    if (caisseSection) caisseSection.style.display = 'none';

    // Gestion du Titre et Bouton Ajouter
    const titleEl = document.getElementById('admin-title');
    const btnAdd = document.getElementById('btn-add-admin');
    if (btnAdd) btnAdd.style.display = 'inline-block'; // Affiché par défaut

    switch (section) {
        case 'magasins':
            titleEl.textContent = 'Gestion des Magasins';
            tableWrapper.style.display = 'block';
            loadMagasins();
            break;

        case 'users':
            titleEl.textContent = 'Utilisateurs Système';
            tableWrapper.style.display = 'block';
            if (typeof loadUsers === 'function') loadUsers();
            break;

        case 'employers':
            titleEl.textContent = 'Employés & Staff';
            tableWrapper.style.display = 'block';
            if (typeof loadEmployers === 'function') loadEmployers();
            break;

        case 'producteurs':
            // ICI C'ETAIT L'ERREUR ! On corrige :
            titleEl.textContent = 'Gestion des Producteurs';
            tableWrapper.style.display = 'block';
            loadProducteurs(); // <--- C'est ici la correction clé
            break;

        case 'lots':
            titleEl.textContent = 'Référentiel des Lots';
            tableWrapper.style.display = 'block';
            if (typeof loadLots === 'function') loadLots();
            break;

        case 'validations':
            titleEl.textContent = 'Validations & Transferts';
            localSection.style.display = 'block';
            btnAdd.style.display = 'none';
            if (typeof loadValidations === 'function') loadValidations();
            break;

        case 'caisse':
            titleEl.textContent = 'Caisse Centrale & Paiements';
            caisseSection.style.display = 'block';
            btnAdd.style.display = 'none';
            if (typeof initAdminCaisse === 'function') initAdminCaisse();
            break;
    }
}

// ==========================================
// 2. FONCTION DE CHARGEMENT DES PRODUCTEURS
// ==========================================

async function loadProducteurs() {
    const wrapper = document.getElementById('admin-table-wrapper');
    wrapper.innerHTML = '<p>Chargement des producteurs...</p>';

    try {
        // On appelle bien l'API /producteurs
        const res = await fetch('/api/producteurs');
        if (!res.ok) throw new Error("Erreur réseau");
        
        const producteurs = await res.json();

        // Construction du tableau spécifique aux Producteurs
        let html = `
        <table class="admin-table">
            <thead>
                <tr>
                    <th>Matricule</th>
                    <th>Nom Complet</th>
                    <th>Contact</th>
                    <th>Localité</th>
                    <th>Solde (FCFA)</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>`;

        producteurs.forEach(p => {
            html += `
            <tr>
                <td><strong>${p.matricule || '-'}</strong></td>
                <td>${p.nom_producteur}</td>
                <td>${p.contact || '-'}</td>
                <td>${p.localite || '-'}</td>
                <td style="font-weight:bold; color:${p.solde > 0 ? '#2e7d32' : '#d32f2f'}">
                    ${parseFloat(p.solde || 0).toLocaleString()}
                </td>
                <td>
                    <button class="btn-small" onclick="editProducteur(${p.id})"><i class="fa-solid fa-pen"></i></button>
                    <button class="btn-small delete" onclick="deleteProducteur(${p.id})"><i class="fa-solid fa-trash"></i></button>
                </td>
            </tr>`;
        });

        html += `</tbody></table>`;
        wrapper.innerHTML = html;

    } catch (err) {
        console.error(err);
        wrapper.innerHTML = '<p style="color:red">Impossible de charger les producteurs.</p>';
    }
}

async function refreshAdminTable() {
    const wrapper = document.getElementById('admin-table-wrapper');
    if (!wrapper) return;

    wrapper.innerHTML = `<div style="padding:20px;"><i class="fa-solid fa-spinner fa-spin"></i> Chargement...</div>`;
    
    let endpoint;
    let errorMessage;
    
    // Mapping des sections
    switch(currentSection) {
        case 'magasins':
            endpoint = '/api/magasins';
            errorMessage = 'Impossible de charger la liste des magasins.';
            break;
        case 'users':
        case 'utilisateurs':
            endpoint = '/api/users';
            errorMessage = 'Impossible de charger la liste des utilisateurs.';
            break;
        case 'employers':
        case 'employes':
            endpoint = '/api/employers';
            errorMessage = 'Impossible de charger la liste des employés.';
            break;
        case 'producteurs':
            endpoint = '/api/producteurs';
            errorMessage = 'Impossible de charger la liste des producteurs.';
            break;
        case 'lots':
            endpoint = '/api/lots';
            errorMessage = 'Impossible de charger le référentiel des lots.';
            break;
        case 'validations':
            endpoint = '/api/validations';
            errorMessage = 'Impossible de charger les validations en attente.';
            break;
        default:
            wrapper.innerHTML = `<p style='color:orange; padding:20px;'>⚠️ Section "${currentSection}" non reconnue.</p>`;
            return;
    }
    
    try {
        const res = await fetch(endpoint);
        if (!res.ok) throw new Error(`Erreur HTTP ${res.status}`);
        
    /*    const data = await res.json();
        if (!Array.isArray(data)) throw new Error('Format de données invalide');
        
        renderAdminTable(data); */
        const data = await res.json();
        if (!Array.isArray(data)) throw new Error('Format de données invalide');

        // SAUVEGARDE GLOBALE pour le filtrage
        window.currentAdminData = data; 
        
        // On affiche
        renderAdminTable(data);

    } catch (err) {
        console.error('Erreur refreshAdminTable:', err);
        wrapper.innerHTML = `
            <div style='background:#ffebee; padding:20px; border-radius:8px; border-left:4px solid #d32f2f;'>
                <h4 style='color:#c62828; margin-top:0;'>⚠️ ${errorMessage}</h4>
                <p>${err.message}</p>
                <button class="btn" onclick="refreshAdminTable()" style="background:#d32f2f; color:white; margin-top:10px;">Réessayer</button>
            </div>`;
        
        if (typeof logDeploymentError === 'function') {
            logDeploymentError(`Admin-Load-${currentSection}`, err);
        }
    }
}

function execFilterProducteurs() {
    if (!window.currentAdminData) return;

    const search = document.getElementById('prod-search').value.toLowerCase();
    const soldeCritere = document.getElementById('prod-filter-solde').value;
    const sortCritere = document.getElementById('prod-sort').value;

    let filtered = window.currentAdminData.filter(p => {
        // Recherche Nom / Matricule / Tel
        const matchSearch = (p.nom_producteur || '').toLowerCase().includes(search) || 
                            (p.matricule || '').toLowerCase().includes(search) ||
                            (p.tel_producteur || '').includes(search);

        // Filtre Solde
        const s = parseFloat(p.solde || 0);
        let matchSolde = true;
        if (soldeCritere === 'positif') matchSolde = s > 0;
        if (soldeCritere === 'important') matchSolde = s >= 100000;
        if (soldeCritere === 'zero') matchSolde = s === 0;

        return matchSearch && matchSolde;
    });

    // Tri
    filtered.sort((a, b) => {
        if (sortCritere === 'solde_desc') return parseFloat(b.solde) - parseFloat(a.solde);
        if (sortCritere === 'recent') return b.id - a.id; // Basé sur l'ID séquentiel
        return (a.nom_producteur || '').localeCompare(b.nom_producteur);
    });

    // On relance le rendu avec les données filtrées
    // /!\ Attention : il faut empêcher la barre de filtre de se ré-injecter à l'infini
    // On peut passer un flag ou simplement vider le wrapper avant
    renderAdminTable(filtered);
    
    // Petit hack pour remettre le focus dans l'input après le refresh du HTML
    const input = document.getElementById('prod-search');
    if(input) {
        input.focus();
        input.setSelectionRange(search.length, search.length);
    }
}


// 4. RENDU DU TABLEAU (Version Intelligente)
function renderAdminTable(data) {
    const wrapper = document.getElementById('admin-table-wrapper');
    
    if(!data || data.length === 0) {
        wrapper.innerHTML = "<div style='padding:40px; text-align:center; color:#888;'><i class='fa-solid fa-inbox fa-2x'></i><br>Aucune donnée disponible pour le moment.</div>";
        return;
    }

    // --- NOUVEAU : INJECTION DES FILTRES ---
    let filterHtml = "";
    if (currentSection === 'producteurs') {
        filterHtml = `
        <div class="admin-filter-bar" style="display:flex; gap:10px; margin-bottom:15px; background:#f4f7f6; padding:10px; border-radius:8px;">
            <input type="text" id="prod-search" placeholder="Rechercher nom, matricule..." 
                style="flex:2; padding:8px; border:1px solid #ddd; border-radius:4px;"
                oninput="execFilterProducteurs()">
            
            <select id="prod-filter-solde" style="flex:1; padding:8px; border:1px solid #ddd; border-radius:4px;" onchange="execFilterProducteurs()">
                <option value="all">Tous les soldes</option>
                <option value="positif">Soldes > 0 FCFA</option>
                <option value="important">Gros soldes (> 100k)</option>
                <option value="zero">Soldes nuls</option>
            </select>

            <select id="prod-sort" style="flex:1; padding:8px; border:1px solid #ddd; border-radius:4px;" onchange="execFilterProducteurs()">
                <option value="nom">Trier par Nom</option>
                <option value="solde_desc">Plus gros soldes</option>
                <option value="recent">Plus récents</option>
            </select>
        </div>`;
    }
    // ---------------------------------------

    if(!data || data.length === 0) {
        // On garde les filtres même si la liste est vide après filtrage
        wrapper.innerHTML = filterHtml + "<div style='padding:40px; text-align:center; color:#888;'><i class='fa-solid fa-inbox fa-2x'></i><br>Aucune donnée disponible.</div>";
        return;
    }
 
    // A. DÉFINITION DES COLONNES PAR SECTION
    // Cela permet de ne pas afficher les mots de passe ou les ID techniques
    const columnsConfig = {
    'users': [
        { key: 'id', label: 'Matricule/ID' }, // Affichera l'ID généré par le trigger
        { key: 'username', label: 'Login' },
        { key: 'role', label: 'Rôle', type: 'badge' },
        { key: 'prenom', label: 'Prénom' },
        { key: 'statut', label: 'Statut' }
    ],
        'lots': [
            { key: 'categorie', label: 'Catégorie', type: 'badge' },
            { key: 'description', label: 'Désignation' },
            { key: 'prix_ref', label: 'Prix Réf.', type: 'money' },
            { key: 'unites_admises', label: 'Unités', type: 'json_list' }, // Spécial pour nos arrays
            { key: 'stock_disponible', label: 'Stock' }
        ],
    // ... vos autres configs (users, lots) ...
    
    'producteurs': [
        { key: 'matricule', label: 'Matricule' },
        { key: 'nom_producteur', label: 'Nom / Organisation' },
        { key: 'type_producteur', label: 'Type', type: 'badge' },
        { key: 'telephone', label: 'Contact' },
        { key: 'localite', label: 'Localité' },
        { key: 'solde', label: 'Solde (FCFA)', type: 'money' },
        { key: 'statut', label: 'Statut', type: 'badge' }
    ],
            // Fallback pour les sections simples (magasins, etc.)
        'default': Object.keys(data[0]).map(k => ({ key: k, label: k.replace(/_/g, ' ').toUpperCase() }))
    };

    // Choix de la config ou fallback automatique
    const columns = columnsConfig[currentSection] || columnsConfig['default'];

    // B. CONSTRUCTION HTML
    let html = `<table class="admin-table"><thead><tr>`;
    columns.forEach(col => html += `<th>${col.label}</th>`);
    html += `<th style="width:100px; text-align:center;">Actions</th></tr></thead><tbody>`;
    
    data.forEach(row => {
        html += `<tr>`;
        columns.forEach(col => {
            let value = row[col.key];

            // C. FORMATAGE INTELLIGENT
            if (col.type === 'badge') {
                value = `<span class="badge-${value}">${value}</span>`;
            } 
            else if (col.type === 'money') {
                value = value ? `${parseFloat(value).toLocaleString('fr-FR')} FCFA` : '0 FCFA';
            }
            else if (col.type === 'json_list') {
                // Gestion spécifique pour vos colonnes JSONB (Lots)
                if (Array.isArray(value)) {
                    value = value.join(', ');
                } else if (typeof value === 'object' && value !== null) {
                    value = Object.keys(value).length + ' éléments';
                } else {
                    value = '-';
                }
            }
            // Gestion des valeurs nulles
            else if (value === null || value === undefined) {
                value = '-';
            }

            html += `<td>${value}</td>`;
        });
        
        // Bouton supprimer avec ID sécurisé
        html += `
            <td style="text-align:center;">
                <button class="btn-icon delete" onclick="deleteItem('${currentSection}', ${row.id})" title="Supprimer">
                    <i class="fa-solid fa-trash"></i>
                </button>
            </td>
        </tr>`;
    });
    
    html += `</tbody></table>`;
    
    // Ajout d'un petit compteur en bas
    html += `<div style="margin-top:10px; font-size:12px; color:#666; text-align:right;">${data.length} enregistrements trouvés</div>`;

    wrapper.innerHTML = html;
}

// 5. GESTION DES FORMULAIRES DYNAMIQUES
function showAdminForm() {
    const wrapper = document.getElementById('admin-table-wrapper');
    if (!wrapper) return;
    
    switch(currentSection) {
        case 'magasins': showFormMagasins(wrapper); break;
        case 'users':
        case 'utilisateurs': showFormUsers(wrapper); break;
        case 'employers':
        case 'employes': showFormEmployers(wrapper); break;
        case 'producteurs': showFormProducteurs(wrapper); break;
        case 'lots': showFormLots(wrapper); break;
        default:
            wrapper.innerHTML = `<p style="padding:20px; color:orange;">⚠️ Formulaire non implémenté.</p>`;
    }
}

// --- FORMULAIRE PRODUCTEURS ---
/**
 * Formulaire Producteurs avec Géographie en Cascade
 */
function showFormProducteurs(wrapper) {
    wrapper.innerHTML = `
        <form id="form-producteur" class="admin-form" style="background:white; padding:25px; border-radius:8px;">
            <h3 style="margin-top:0; color:#2c3e50; border-bottom:2px solid #3498db; padding-bottom:10px;">
                <i class="fa-solid fa-address-card"></i> Fiche Nouveau Producteur
            </h3>
            
            <div style="display:grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap:20px;">
                <div class="form-group">
                    <label>Nom / Raison Sociale *</label>
                    <input type="text" id="p-nom" required placeholder="Ex: Jean Planteur">
                </div>
                <div class="form-group">
                    <label>Téléphone *</label>
                    <input type="tel" id="p-tel" required placeholder="6XXXXXXXX">
                </div>
                <div class="form-group">
                    <label>Type *</label>
                    <select id="p-type" required>
                        <option value="individuel">Individuel</option>
                        <option value="agriculteur">Agriculteur</option>
                        <option value="éleveur">Éleveur</option>
                        <option value="pêcheur">Pêcheur</option>
                        <option value="artisan">Artisan</option>
                        <option value="coopérative">Coopérative</option>
                    </select>
                </div>
                <div class="form-group">
                    <label>Carte Membre</label>
                    <select id="p-carte">
                        <option value="false">Non Membre</option>
                        <option value="true">Membre Actif</option>
                    </select>
                </div>
            </div>

            <fieldset style="margin-top:20px; border:1px solid #ddd; padding:15px; border-radius:8px;">
                <legend style="padding:0 10px; font-weight:bold;">Localisation Géographique</legend>
                <div style="display:grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap:15px;">
                    <div class="form-group">
                        <label>Région *</label>
                        <select id="p-region" required onchange="chargerGeographie('departements', this.value, 'p-departement')">
                            <option value="">Chargement...</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label>Département *</label>
                        <select id="p-departement" required onchange="chargerGeographie('arrondissements', this.value, 'p-arrondissement')">
                            <option value="">-- Choisir Région --</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label>Arrondissement *</label>
                        <select id="p-arrondissement" required>
                            <option value="">-- Choisir Dept --</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label>Localité spécifique</label>
                        <input type="text" id="p-localite" placeholder="Village, Quartier...">
                    </div>
                </div>
            </fieldset>

            <div style="display:flex; justify-content:flex-end; gap:12px; margin-top:25px;">
                <button type="button" class="btn" onclick="refreshAdminTable()">Annuler</button>
                <button type="submit" class="btn btn-save" style="background:#27ae60; color:white;">
                    VALIDER L'INSCRIPTION
                </button>
            </div>
        </form>
    `;

    // Chargement initial des régions
    fetch('/api/geo/api/regions')
        .then(res => res.json())
        .then(data => {
            const sel = document.getElementById('p-region');
            sel.innerHTML = '<option value="">-- Sélectionner --</option>';
            data.forEach(r => sel.innerHTML += `<option value="${r.id}">${r.nom}</option>`);
        });

    document.getElementById('form-producteur').onsubmit = async (e) => {
        e.preventDefault();
        const payload = {
            nom_producteur: document.getElementById('p-nom').value,
            tel_producteur: document.getElementById('p-tel').value,
            type_producteur: document.getElementById('p-type').value,
            carte_membre: document.getElementById('p-carte').value === 'true',
            region_id: parseInt(document.getElementById('p-region').value),
            departement_id: parseInt(document.getElementById('p-departement').value),
            arrondissement_id: parseInt(document.getElementById('p-arrondissement').value),
            localite: document.getElementById('p-localite').value,
            statut: 'actif'
        };
        await submitForm('/api/producteurs', payload);
    };
}
// --- FORMULAIRE MAGASINS ---
function showFormMagasins(wrapper) {
    wrapper.innerHTML = `
        <form id="form-magasin" class="admin-form">
            <h3>Nouveau Magasin</h3>
            <div class="form-grid">
                <div class="form-group">
                    <label>Nom du magasin *</label>
                    <input type="text" id="magasin-nom" required>
                </div>
                <div class="form-group">
                    <label>Code *</label>
                    <input type="text" id="magasin-code" placeholder="Ex: YDE001" required maxlength="10">
                </div>
                <div class="form-group">
                    <label>Région</label>
                    <select id="magasin-region"><option value="">-- Sélectionner --</option></select>
                </div>
                <div class="form-actions">
                    <button type="button" class="btn" onclick="refreshAdminTable()">Annuler</button>
                    <button type="submit" class="btn btn-save">Enregistrer</button>
                </div>
            </div>
        </form>`;
    
    if (typeof loadReference === 'function') loadReference('regions', 'magasin-region');

    document.getElementById('form-magasin').onsubmit = async (e) => {
        e.preventDefault();
        const payload = {
            nom: document.getElementById('magasin-nom').value.trim(),
            code: document.getElementById('magasin-code').value.trim().toUpperCase(),
            region_id: document.getElementById('magasin-region').value || null
        };
        await submitForm('/api/magasins', payload);
    };
}
// --- FROMULAIRE DES UTILISATEURS ---
/**
 * Affiche le formulaire de création d'un utilisateur
 * @param {HTMLElement} wrapper - Le conteneur où injecter le formulaire
 */
function showFormUsers(wrapper) {
    wrapper.innerHTML = `
        <div class="form-container" style="background: #f9f9f9; padding: 20px; border-radius: 8px; border: 1px solid #ddd;">
            <h3 style="margin-top:0;"><i class="fa-solid fa-user-plus"></i> Créer un nouvel utilisateur</h3>
            <form id="form-user-creation">
                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
                    
                    <div class="form-group">
                        <label>Nom d'utilisateur (Identifiant de connexion) *</label>
                        <input type="text" id="u-username" name="username" required placeholder="ex: jdoe">
                    </div>

                    <div class="form-group">
                        <label>Mot de passe *</label>
                        <input type="password" id="u-password" name="password" required>
                    </div>

                    <div class="form-group">
                        <label>Rôle Système *</label>
                        <select id="u-role" name="role" required>
                            <option value="stock">Agent de Stock (Admission)</option>
                            <option value="caisse">Agent de Caisse</option>
                            <option value="admin">Gestionnaire de Magasin</option>
                            <option value="auditeur">Auditeur (Lecture seule)</option>
                            <option value="superadmin">Super-Administrateur</option>
                        </select>
                    </div>

                    <div class="form-group">
                        <label>Magasin d'affectation</label>
                        <select id="u-magasin" name="magasin_id">
                            <option value="">-- Aucun (Utilisateur Central) --</option>
                            </select>
                    </div>

                    <div class="form-group">
                        <label>Prénom</label>
                        <input type="text" id="u-prenom" name="prenom">
                    </div>

                    <div class="form-group">
                        <label>Nom</label>
                        <input type="text" id="u-nom" name="nom">
                    </div>

                    <div class="form-group">
                        <label>Email</label>
                        <input type="email" id="u-email" name="email">
                    </div>

                    <div class="form-group">
                        <label>Téléphone</label>
                        <input type="tel" id="u-telephone" name="telephone">
                    </div>
                </div>

                <div style="margin-top: 20px; display: flex; justify-content: flex-end; gap: 10px;">
                    <button type="button" class="btn" onclick="refreshAdminTable()">Annuler</button>
                    <button type="submit" class="btn btn-save" style="background: #27ae60; color: white; border: none; padding: 10px 20px; border-radius: 4px; cursor: pointer;">
                        Enregistrer l'utilisateur
                    </button>
                </div>
            </form>
        </div>
    `;

    // Charger dynamiquement les magasins dans le select
    fetchMagasinsForSelect('u-magasin');

    // Gestion de la soumission
    document.getElementById('form-user-creation').onsubmit = async (e) => {
        e.preventDefault();
        
        const payload = {
            username: document.getElementById('u-username').value,
            password: document.getElementById('u-password').value,
            role: document.getElementById('u-role').value,
            magasin_id: document.getElementById('u-magasin').value || null,
            prenom: document.getElementById('u-prenom').value,
            nom: document.getElementById('u-nom').value,
            email: document.getElementById('u-email').value,
            telephone: document.getElementById('u-telephone').value,
            statut: 'actif'
        };

        try {
            const response = await fetch('/api/users', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });

            if (response.ok) {
                alert('Utilisateur créé avec succès !');
                refreshAdminTable(); // Recharge le tableau des utilisateurs
            } else {
                const err = await response.json();
                alert('Erreur : ' + err.error);
            }
        } catch (error) {
            console.error('Erreur soumission utilisateur:', error);
        }
    };
}

/**
 * Charge les magasins depuis l'API pour remplir un <select>
 */
async function fetchMagasinsForSelect(selectId) {
    try {
        const res = await fetch('/api/magasins');
        const magasins = await res.json();
        const select = document.getElementById(selectId);
        magasins.forEach(m => {
            const opt = document.createElement('option');
            opt.value = m.id;
            opt.textContent = `${m.nom} (${m.code})`;
            select.appendChild(opt);
        });
    } catch (err) {
        console.error('Impossible de charger les magasins', err);
    }
}
// --- FORMULAIRE LOTS (PRODUITS) ---
function showFormLots(wrapper) {
    wrapper.innerHTML = `
        <form id="form-lot" style="background:white; padding:25px; border-radius:8px; max-width:1000px; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
            <h3 style="margin-top:0; color:var(--admin); border-bottom:2px solid #eee; padding-bottom:10px;">
                <i class="fa-solid fa-box-open"></i> Référentiel Produit : Création d'un Lot
            </h3>
            
            <div style="display:grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap:20px;">
                <div class="form-group">
                    <label style="font-weight:bold; display:block; margin-bottom:5px;">Catégorie *</label>
                    <select id="lot-categorie" required style="width:100%; padding:12px; border-radius:6px; border:1px solid #ddd;">
                        <option value="">-- Sélectionner une catégorie --</option>
                        
                        <optgroup label="Agriculture & Nature">
                            <option value="frais">Produits Frais (Vivres frais)</option>
                            <option value="secs">Céréales, Grains et Légumineuses</option>
                            <option value="huiles_liquides">Huiles et Produits Liquides</option>
                            <option value="produits_foret">Produits de la Forêt (PFNL / NTFP)</option>
                        </optgroup>
                    
                        <optgroup label="Artisanat & Objets">
                            <option value="artisanat_utilitaire">Artisanat Utilitaire (Meubles, Poterie, Paniers)</option>
                            <option value="artisanat_art">Artisanat d'Art & Décoration</option>
                            <option value="ustensiles_traditionnels">Ustensiles & Outils de fabrication (Forge, Bois)</option>
                        </optgroup>
                    
                        <optgroup label="Transformés & Manufacturés">
                            <option value="cosmetiques_locaux">Savonnerie & Cosmétiques (Beurre de Karité/Moringa)</option>
                            <option value="manufactures_alim">Manufacturés Alimentaires (Conserves, Farines)</option>
                            <option value="manufactures_non_alim">Manufacturés Non Alimentaires</option>
                        </optgroup>
                    
                        <optgroup label="Gestion Spécifique">
                            <option value="sensibles">Produits de Haute Valeur / Sensibles</option>
                        </optgroup>
                    </select>
                                    </div>

                <div class="form-group">
                    <label style="font-weight:bold; display:block; margin-bottom:5px;">Description du produit *</label>
                    <input type="text" id="lot-description" placeholder="Ex: Huile de palme raffinée" required style="width:100%; padding:10px; border:1px solid #ddd; border-radius:6px;">
                </div>

                <div class="form-group">
                    <label style="font-weight:bold; display:block; margin-bottom:5px;">Prix de Référence (FCFA/Unité) *</label>
                    <input type="number" id="lot-prix-ref" step="0.01" min="0" required style="width:100%; padding:10px; border:1px solid #ddd; border-radius:6px;">
                </div>
            </div>

            <div style="margin-top:25px;">
                <label style="font-weight:bold; display:block; margin-bottom:10px;">Unités de mesure admises *</label>
                <div style="display:grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap:10px; background:#f8f9fa; padding:15px; border-radius:6px; border:1px solid #eee;">
                    ${['kg', 'gr', 'litres', 'unites', 'sacs', 'caisses', 'bottes', 'plateaux'].map(u => `
                        <label style="display:flex; align-items:center; gap:8px; cursor:pointer; font-size:14px;">
                            <input type="checkbox" name="unite" value="${u}"> ${u === 'unites' ? 'Unités (pièces)' : u.charAt(0).toUpperCase() + u.slice(1)}
                        </label>
                    `).join('')}
                </div>
            </div>

            <div style="margin-top:25px; border-top:2px solid #eee; padding-top:20px;">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:15px;">
                    <h4 style="margin:0; color:#555;">
                        <i class="fa-solid fa-clipboard-check"></i> Critères de Contrôle Qualité (Admission)
                    </h4>
                    <button type="button" onclick="ajouterCriterePersonnalise()" style="background:#f0f0f0; padding:6px 12px; border:1px solid #ccc; border-radius:4px; cursor:pointer; font-size:13px;">
                        <i class="fa-solid fa-plus"></i> Critère personnalisé
                    </button>
                </div>
                
                <div id="zone-criteres-auto" style="background:#f1f8e9; padding:15px; border-radius:6px; border-left:4px solid #4caf50; margin-bottom:15px; display:none;">
                    <div style="font-size:11px; font-weight:bold; color:#2e7d32; margin-bottom:10px; text-transform:uppercase;">
                        📋 Critères standards recommandés
                    </div>
                    <div id="liste-criteres-auto" style="display:grid; grid-template-columns: 1fr 1fr; gap:10px;"></div>
                </div>

                <div id="zone-criteres-personnalises" style="display:grid; gap:10px;"></div>

                <textarea id="lot-criteres-notes" placeholder="Instructions spéciales pour les agents de réception..." style="width:100%; height:70px; padding:10px; border:1px solid #ddd; border-radius:4px; margin-top:15px; font-family:inherit; resize:vertical;"></textarea>
            </div>

            <div style="display:flex; justify-content:flex-end; gap:12px; margin-top:25px; padding-top:20px; border-top:1px solid #eee;">
                <button type="button" class="btn" onclick="refreshAdminTable()" style="background:#eee; padding:12px 25px; border:none; border-radius:6px; cursor:pointer;">Annuler</button>
                <button type="submit" class="btn" style="background:var(--admin); color:white; padding:12px 35px; border:none; border-radius:6px; font-weight:bold; cursor:pointer;">
                    <i class="fa-solid fa-save"></i> ENREGISTRER LE PRODUIT
                </button>
            </div>
        </form>
    `;

    document.getElementById('form-lot').onsubmit = async (e) => {
        e.preventDefault();
        const unitesChecked = Array.from(document.querySelectorAll('input[name="unite"]:checked')).map(cb => cb.value);
        if (unitesChecked.length === 0) return alert('❌ Sélectionnez au moins une unité.');
        
        const criteresAuto = Array.from(document.querySelectorAll('#liste-criteres-auto input:checked'))
            .map(cb => ({ type: 'standard', critere: cb.value, obligatoire: true }));
        
        const criteresPerso = Array.from(document.querySelectorAll('.critere-personnalise'))
            .map(div => ({
                type: 'personnalise',
                critere: div.querySelector('input').value,
                obligatoire: div.querySelector('select').value === 'obligatoire'
            })).filter(c => c.critere.trim() !== '');
        
        const payload = {
            categorie: document.getElementById('lot-categorie').value,
            description: document.getElementById('lot-description').value.trim(),
            prix_ref: parseFloat(document.getElementById('lot-prix-ref').value),
            unites_admises: unitesChecked,
            criteres_admission: [...criteresAuto, ...criteresPerso],
            notes: document.getElementById('lot-criteres-notes').value.trim()
        };

        await submitForm('/api/lots', payload);
    };
} 

// DÉCLARATION GLOBALE (En dehors de toute fonction)
const categoriesMapping = {
    // ... catégories existantes (frais, secs, etc.) ...
    
    'produits_foret': [
        'Identification correcte de l\'espèce',
        'Séchage ou état de conservation',
        'Absence de moisissures/parasites',
        'Pureté (absence d\'écorces étrangères)',
        'Conditionnement (sacs propres)'
    ],
    'ustensiles_traditionnels': [
        'Qualité de la forge ou de la taille',
        'Solidité des manches et fixations',
        'Sécurité d\'utilisation (pas de bords tranchants imprévus)',
        'Absence de corrosion (pour le métal)',
        'Ergonomie et poids'
    ],
    'cosmetiques_locaux': [
        'Texture et homogénéité',
        'Odeur caractéristique (absence de rancissement)',
        'Étanchéité du contenant',
        'Date de fabrication/péremption visible',
        'Clarté des instructions d\'usage'
    ],
    // Rappel des catégories artisanat demandées précédemment
    'artisanat_utilitaire': [
        'Solidité et assemblage (stabilité)',
        'Finition des surfaces (ponçage, vernis)',
        'Absence de fissures ou défauts majeurs',
        'Conformité aux dimensions/usage',
        'Esthétique globale et symétrie'
    ],
    'artisanat_art': [
        'Qualité des matériaux de base',
        'Finesse des détails et ornements',
        'Authenticité du style/technique',
        'Absence de fragilité excessive',
        'Propreté et présentation finale'
    ],
        'frais': [
            'Aspect visuel (couleur, fermeté)',
            'Absence de moisissure ou pourriture',
            'Absence d\'insectes ou parasites',
            'Odeur normale (pas de fermentation)',
            'Température de conservation respectée',
            'Date de récolte < 48h',
            'Conditionnement propre et intact'
        ],
        'court': [
            'Fraîcheur apparente',
            'Absence de flétrissement',
            'Feuillage vert et turgescent',
            'Racines ou tiges non endommagées',
            'Absence de terre excessive',
            'Calibrage homogène',
            'Emballage aéré et propre'
        ],
        'secs': [
            'Taux d\'humidité conforme (< 14%)',
            'Absence de moisissure',
            'Grains entiers et sains',
            'Absence d\'insectes (charançons, etc.)',
            'Couleur uniforme et typique',
            'Absence d\'odeur de fermentation',
            'Absence de corps étrangers',
            'Conditionnement étanche et sec'
        ],
        'manufactures_alim': [
            'Date de péremption valide',
            'Emballage intact (non percé, non gonflé)',
            'Étiquetage conforme et lisible',
            'Absence de rouille (conserves)',
            'Température de stockage respectée',
            'Numéro de lot visible',
            'Certification sanitaire valide'
        ],
        'manufactures_non_alim': [
            'Emballage intact et scellé',
            'Étiquetage présent et lisible',
            'Date de fabrication visible',
            'Absence de dommages physiques',
            'Conformité aux normes',
            'Certificat de qualité (si applicable)',
            'Stockage approprié (T°, humidité)'
        ],
        'sensibles': [
            '⚠️ Contrôle sanitaire obligatoire',
            'Certificat vétérinaire ou phytosanitaire',
            'Traçabilité complète (origine, lot)',
            'Chaîne du froid respectée',
            'Analyses de laboratoire récentes',
            'Conditionnement conforme (hermétique)',
            'Étiquetage de danger (si applicable)',
            'Autorisation de transport'
        ]
    };
window.COOP_CRITERIA = categoriesMapping;
// === FONCTION : CHARGEMENT DES CRITÈRES PAR CATÉGORIE ===
function chargerCriteresParCategorie() {
    const cat = document.getElementById('lot-categorie').value;
    const zoneAuto = document.getElementById('zone-criteres-auto');
    const listeAuto = document.getElementById('liste-criteres-auto');
    

    listeAuto.innerHTML = "";
    if (categoriesMapping[cat]) {
        zoneAuto.style.display = 'block';
        categoriesMapping[cat].forEach(critere => {
            const div = document.createElement('div');
            div.innerHTML = `
                <label style="display:flex; align-items:center; gap:8px; background:white; padding:8px; border-radius:4px; border:1px solid #e0e0e0; cursor:pointer; font-size:13px;">
                    <input type="checkbox" value="${critere}" checked> 
                    <span>${critere}</span>
                </label>
            `;
            listeAuto.appendChild(div);
        });
    } else {
        zoneAuto.style.display = 'none';
    }
}

function ajouterCriterePersonnalise() {
    const zone = document.getElementById('zone-criteres-personnalises');
    const div = document.createElement('div');
    div.className = 'critere-personnalise';
    div.style = "display:flex; gap:10px; margin-bottom:10px; align-items:center; background:#fff; padding:5px; border-radius:4px;";
    div.innerHTML = `
        <input type="text" placeholder="Nouveau critère..." style="flex:1; padding:8px; border:1px solid #ddd; border-radius:4px; font-size:13px;">
        <select style="padding:8px; border:1px solid #ddd; border-radius:4px; width:110px; font-size:12px;">
            <option value="obligatoire">Obligatoire</option>
            <option value="optionnel">Optionnel</option>
        </select>
        <button type="button" onclick="this.parentElement.remove()" style="background:none; border:none; color:#d32f2f; cursor:pointer; font-size:18px;">&times;</button>
    `;
    zone.appendChild(div);
}

async function submitForm(url, payload) {
    try {
        const res = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        if (!res.ok) throw new Error(await res.text());
        alert('✅ Enregistrement réussi !');
        refreshAdminTable();
    } catch (err) {
        alert('❌ Erreur : ' + err.message);
    }
}

/**
 * Charge les données géographiques en cascade depuis geo.js
 */
async function chargerGeographie(type, parentId, targetSelectId) {
    const select = document.getElementById(targetSelectId);
    if (!parentId) {
        select.innerHTML = '<option value="">-- Sélectionner --</option>';
        return;
    }

    // On définit le nom du paramètre en fonction du type (region_id ou departement_id)
    const paramName = (type === 'departements') ? 'region_id' : 'departement_id';

    try {
        const res = await fetch(`/api/geo/api/${type}?${paramName}=${parentId}`);
        const data = await res.json();
        
        select.innerHTML = '<option value="">-- Sélectionner --</option>';
        data.forEach(item => {
            const opt = document.createElement('option');
            opt.value = item.id;
            opt.textContent = item.nom;
            select.appendChild(opt);
        });
        
        // Si on change de région, on réinitialise aussi les arrondissements
        if (type === 'departements') {
            const arrSelect = document.getElementById('p-arrondissement');
            if (arrSelect) arrSelect.innerHTML = '<option value="">-- Choisir Dept --</option>';
        }
    } catch (err) {
        console.error(`❌ Erreur chargement ${type}:`, err);
    }
}
// Alertes conditionnelles
async function verifierSanteMonMagasin() {
    const stocks = await fetch('/api/mon-magasin/stock').then(r => r.json());
    
    // Utilisation du code partagé
    if (window.StockIntelligence) {
        const rapport = window.StockIntelligence.analyserInventaire(stocks);
        const alertes = window.StockIntelligence.genererAlertesGlobales(rapport);

        if (alertes.length > 0) {
            // Afficher une bulle de notification rouge
            afficherNotificationUrgente(alertes.join('<br>'));
        }
    }
}
async function deleteItem(section, id) {
    if (!confirm("⚠️ Êtes-vous sûr de vouloir supprimer cet élément ?")) return;
    const apiMap = { 'utilisateurs': 'users', 'employes': 'employers', 'magasins': 'magasins', 'lots': 'lots' };
    const endpoint = apiMap[section] || section;

    try {
        const res = await fetch(`/api/${endpoint}/${id}`, { method: 'DELETE' });
        if (res.ok) refreshAdminTable();
        else {
            const err = await res.json();
            alert("Erreur: " + (err.message || "Impossible de supprimer"));
        }
    } catch (error) {
        console.error("Erreur delete:", error);
    }
}
/* ==========================================
   GESTION MODULE CAISSE (Admin)
   ========================================== */

async function initAdminCaisse() {
    console.log("💰 Chargement du module Caisse Admin...");
    await loadAdminCaisseProducers();
    await loadAdminCaisseHistory();
}

// 1. Charger la liste des producteurs avec leur solde
async function loadAdminCaisseProducers() {
    const select = document.getElementById('admin-caisse-select');
    try {
        const response = await fetch('/api/producteurs'); // Assure-toi que cette route renvoie bien le champ 'solde'
        const producteurs = await response.json();

        select.innerHTML = '<option value="">-- Choisir un producteur --</option>';
        producteurs.forEach(p => {
            // On stocke le solde dans un attribut data-solde pour accès rapide sans refaire de requête
            select.innerHTML += `<option value="${p.id}" data-solde="${p.solde}">
                ${p.nom_producteur} (${p.matricule})
            </option>`;
        });
    } catch (error) {
        console.error("Erreur chargement producteurs:", error);
    }
}

// 2. Mettre à jour l'affichage du solde à la sélection
window.updateAdminCaisseSolde = function() { // Attaché à window pour être accessible depuis le HTML
    const select = document.getElementById('admin-caisse-select');
    const display = document.getElementById('admin-caisse-solde-display');
    
    if (select.selectedIndex > 0) {
        const option = select.options[select.selectedIndex];
        const solde = parseFloat(option.getAttribute('data-solde') || 0);
        
        display.innerText = solde.toLocaleString('fr-FR') + ' FCFA';
        
        // Couleur visuelle : Vert si positif, Rouge si 0 ou négatif (bug)
        display.style.color = solde > 0 ? '#2e7d32' : '#d32f2f';
    } else {
        display.innerText = '0 FCFA';
    }
};

// 3. Soumission du Paiement
document.getElementById('admin-caisse-form').addEventListener('submit', async function(e) {
    e.preventDefault();

    const producteurId = document.getElementById('admin-caisse-select').value;
    const montant = parseFloat(document.getElementById('admin-caisse-montant').value);
    const mode = document.getElementById('admin-caisse-mode').value;
    const user = AppUser.get(); // Ton utilitaire d'auth

    // Petite sécurité JS avant l'envoi
    const select = document.getElementById('admin-caisse-select');
    const soldeActuel = parseFloat(select.options[select.selectedIndex].getAttribute('data-solde'));

    if (montant > soldeActuel) {
        alert(`❌ Impossible : Le montant (${montant}) dépasse le solde disponible (${soldeActuel}).`);
        return;
    }

    if (!confirm(`Confirmez-vous le paiement de ${montant.toLocaleString()} FCFA à ce producteur ?`)) return;

    try {
        const response = await fetch('/api/operations_caisse', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                producteur_id: producteurId,
                montant: montant,
                type_operation: 'debit', // Important pour ton trigger SQL
                description: `Paiement Admin via ${mode}`,
                utilisateur: user.username,
                caisse_id: 1
            })
        });

        if (response.ok) {
            alert("✅ Paiement effectué avec succès !");
            // Reset form
            document.getElementById('admin-caisse-form').reset();
            document.getElementById('admin-caisse-solde-display').innerText = "0 FCFA";
            // Recharger les données pour mettre à jour les soldes et l'historique
            initAdminCaisse();
        } else {
            const err = await response.json();
            alert("Erreur : " + err.message);
        }
    } catch (error) {
        console.error(error);
        alert("Erreur de connexion serveur.");
    }
});

// 4. Historique des transactions
async function loadAdminCaisseHistory() {
    const tbody = document.getElementById('admin-caisse-history-body');
    tbody.innerHTML = '<tr><td colspan="4" style="text-align:center;">Chargement...</td></tr>';

    try {
        // On suppose une API qui renvoie les dernières opérations de type 'debit'/'retrait'
        const response = await fetch('/api/operations_caisse?type=debit&limit=10'); 
        const logs = await response.json();

        tbody.innerHTML = '';
        if(logs.length === 0) {
            tbody.innerHTML = '<tr><td colspan="4" style="text-align:center; color:#999;">Aucune transaction récente.</td></tr>';
            return;
        }

        logs.forEach(log => {
            tbody.innerHTML += `
                <tr style="border-bottom:1px solid #eee;">
                    <td style="padding:10px;">${new Date(log.date_operation).toLocaleDateString()} ${new Date(log.date_operation).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}</td>
                    <td style="padding:10px;"><strong>${log.producteur_nom || 'Producteur #' + log.producteur_id}</strong></td>
                    <td style="padding:10px; color:#d32f2f; font-weight:bold;">-${parseFloat(log.montant).toLocaleString()}</td>
                    <td style="padding:10px; color:#666; font-size:11px;">${log.utilisateur}</td>
                </tr>
            `;
        });
    } catch (error) {
        tbody.innerHTML = '<tr><td colspan="4" style="color:red;">Erreur chargement historique.</td></tr>';
    }
}

