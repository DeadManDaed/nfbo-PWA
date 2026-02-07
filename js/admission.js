/**
 * admission.js - Système d'admission avec Audit Qualité par notation
 * Synchronisé sur les catégories globales de window.COOP_CRITERIA
 */

let activeLotData = null;

// 1. INITIALISATION DU MODULE
function initModuleAdmission() {
    chargerLots();
    chargerProducteurs();
    chargerMagasins();
    
    const lotSelect = document.getElementById('adm-lot-select');
    const form = document.getElementById('admissionForm');

    // ÉCOUTEUR D'ÉVÉNEMENT : Déclenche l'audit au changement de sélection
    if (lotSelect) {
        lotSelect.addEventListener('change', onAdmissionLotChange);
    }

    if (form) {
        form.onsubmit = soumettreAdmission;
    }
}

// 2. CHANGEMENT DE LOT : APPEL DES INFOS ET DÉCLENCHEMENT GRILLE
async function onAdmissionLotChange() {
    const lotId = document.getElementById('adm-lot-select').value;
    
    if (!lotId) {
        document.getElementById('lot-info-preview').style.display = 'none';
        document.getElementById('zone-evaluation-qualite').innerHTML = '';
        return;
    }

    try {
        const res = await fetch(`/api/lots/${lotId}`);
        activeLotData = await res.json();

        // Affichage des infos (Prix, Catégorie, etc.)
        document.getElementById('lot-prix-display').innerText = activeLotData.prix_ref;
        document.getElementById('lot-categorie-display').innerText = activeLotData.categorie;
        document.getElementById('lot-info-preview').style.display = 'block';

        // Gestion des unités
        const unitSelect = document.getElementById('adm-unit');
        let unites = Array.isArray(activeLotData.unites_admises) ? activeLotData.unites_admises : JSON.parse(activeLotData.unites_admises || "[]");
        unitSelect.innerHTML = unites.map(u => `<option value="${u}">${u}</option>`).join('');

        // CORRECTION DÉFINITIVE : On appelle la fonction avec le bon nom et la catégorie
        genererGrilleParCategorie(activeLotData.categorie);
        calculateInternalFinance();

    } catch (err) { 
        console.error("Erreur lors du changement de lot:", err); 
    }
}

// 3. CHARGEMENT DES RÉFÉRENTIELS
async function chargerLots() {
    const sel = document.getElementById('adm-lot-select');
    try {
        const res = await fetch('/api/lots');
        const data = await res.json();
        sel.innerHTML = '<option value="">-- Sélectionner un lot --</option>' +
            data.map(l => `<option value="${l.id}">${l.description} (${l.prix_ref} FCFA)</option>`).join('');
    } catch (e) { console.error("Erreur lots", e); }
}

async function chargerProducteurs() {
    const sel = document.getElementById('adm-producer-select');
    try {
        const res = await fetch('/api/producteurs');
        const data = await res.json();
        sel.innerHTML = '<option value="">-- Sélectionner --</option>' +
            data.map(p => `<option value="${p.id}">${p.nom_producteur || p.nom}</option>`).join('');
    } catch (e) { console.error("Erreur producteurs", e); }
}

async function chargerMagasins() {
    const sel = document.getElementById('adm-magasin-select');
    try {
        const res = await fetch('/api/magasins');
        const data = await res.json();
        sel.innerHTML = '<option value="">-- Sélectionner --</option>' +
            data.map(m => `<option value="${m.id}">${m.nom}</option>`).join('');
    } catch (e) { console.error("Erreur magasins", e); }
}

// 4. GÉNÉRATION DE LA GRILLE (Cible la catégorie dans admin.js)
function genererGrilleParCategorie(categorie) {
    const container = document.getElementById('zone-evaluation-qualite');
    
    // Récupération depuis window.COOP_CRITERIA (défini dans admin.js)
    const criteres = window.COOP_CRITERIA ? window.COOP_CRITERIA[categorie] : null;

    if (!criteres || criteres.length === 0) {
        container.innerHTML = `<p style="color:orange; text-align:center; padding:10px; border:1px dashed orange;">
            ⚠️ Aucun protocole d'examen trouvé pour la catégorie : "${categorie}"
        </p>`;
        return;
    }

    let html = `<div style="display:grid; gap:10px;">`;
    criteres.forEach((critereLabel, i) => {
        html += `
            <div style="background:#f8f9fa; padding:10px; border-radius:6px; border:1px solid #eee;">
                <div style="display:flex; justify-content:space-between; margin-bottom:5px;">
                    <span style="font-size:12px; font-weight:600;">${critereLabel}</span>
                    <span id="note-val-${i}" style="font-weight:bold; color:var(--primary);">10</span>
                </div>
                <input type="range" class="note-slider" data-index="${i}" min="1" max="10" value="10" 
                       style="width:100%; cursor:pointer;" 
                       oninput="document.getElementById('note-val-${i}').innerText=this.value; calculerGradeAutomatique();">
            </div>
        `;
    });
    
    html += `
        <div id="grade-badge" style="margin-top:15px; padding:12px; background:#c8e6c9; border-radius:6px; text-align:center; font-weight:bold; border:1px solid #ddd;">
            GRADE CALCULÉ : <span id="lbl-grade">A</span> (Coef: <span id="lbl-coef">1.0</span>)
        </div>
    </div>`;

    container.innerHTML = html;
    calculerGradeAutomatique();
}

// 5. CALCUL DU GRADE & COEF
function calculerGradeAutomatique() {
    const sliders = document.querySelectorAll('.note-slider');
    if (sliders.length === 0) return;

    const notes = Array.from(sliders).map(s => parseFloat(s.value));
    const moyenne = notes.reduce((a, b) => a + b, 0) / notes.length;

    let grade = "D", coef = 0.7;
    if (moyenne >= 9) { grade = "A"; coef = 1.0; }
    else if (moyenne >= 7.5) { grade = "B"; coef = 0.9; }
    else if (moyenne >= 6) { grade = "C"; coef = 0.8; }

    document.getElementById('lbl-grade').innerText = grade;
    document.getElementById('lbl-coef').innerText = coef.toFixed(1);
    document.getElementById('adm-quality').value = coef;

    const badge = document.getElementById('grade-badge');
    const colors = { "A": "#c8e6c9", "B": "#fff9c4", "C": "#ffe0b2", "D": "#ffcdd2" };
    badge.style.background = colors[grade] || "#eee";

    calculateInternalFinance();
}

// 6. CALCULS FINANCIERS
function calculateInternalFinance() {
    if (!activeLotData) return;

    const qty = parseFloat(document.getElementById('adm-qty').value) || 0;
    const prixRef = parseFloat(activeLotData.prix_ref) || 0;
    const coefQualite = parseFloat(document.getElementById('adm-quality').value) || 1;
    const modePaiement = document.getElementById('adm-payment-mode').value;
    const expiryDate = document.getElementById('adm-expiry').value;

    const baseMontant = qty * prixRef * coefQualite;
    let taxeTaux = (modePaiement === 'mobile_money') ? 0.07 : 0.05;

    if (expiryDate) {
        const joursRestants = Math.ceil((new Date(expiryDate) - new Date()) / (1000*60*60*24));
        if (joursRestants > 0 && joursRestants < 30) {
            taxeTaux += (30 - joursRestants) * 0.005; 
        }
    }

    const montantTaxe = baseMontant * taxeTaux;
    const netProducteur = baseMontant - montantTaxe;

    document.getElementById('val-due').innerText = Math.round(netProducteur).toLocaleString() + ' FCFA';
    document.getElementById('val-profit').innerText = Math.round(montantTaxe).toLocaleString() + ' FCFA';
}

// 7. SOUMISSION
async function soumettreAdmission(e) {
    e.preventDefault();
    const notesDetail = Array.from(document.querySelectorAll('.note-slider')).map(s => s.value).join('|');

    const payload = {
        lot_id: document.getElementById('adm-lot-select').value,
        producteur_id: document.getElementById('adm-producer-select').value,
        magasin_id: document.getElementById('adm-magasin-select').value,
        quantite: document.getElementById('adm-qty').value,
        unite: document.getElementById('adm-unit').value,
        coef_qualite: document.getElementById('adm-quality').value,
        grade_qualite: document.getElementById('lbl-grade').innerText,
        prix_ref: document.getElementById('lot-prix-display').innerText,
        date_expiration: document.getElementById('adm-expiry').value || null,
        mode_paiement: document.getElementById('adm-payment-mode').value,
        utilisateur: localStorage.getItem('username'),
        notes_audit: notesDetail
    };

    try {
        const res = await fetch('/api/admissions', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });

        if (res.ok) {
            alert("✅ Admission validée !");
            location.reload();
        } else {
            const err = await res.json();
            alert("❌ Erreur: " + err.error);
        }
    } catch (err) { alert("❌ Erreur connexion serveur"); }
}
