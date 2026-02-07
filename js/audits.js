/**
 * audit.js - Module d'Audit & Performance NBFO
 * Version unifiée : Performance, Logs et Drill-down (Détail Magasin)
 */

let performanceData = [];
// --- 1. UTILITAIRES ---
function getCurrentUser() {
    if (typeof window.user !== 'undefined' && window.user) return window.user;
    return {
        username: localStorage.getItem('username') || 'anonyme',
        nom: localStorage.getItem('nom') || 'Utilisateur',
        role: localStorage.getItem('role') || 'guest'
    };
}

// --- 2. INITIALISATION ---
async function initModuleAudit() {
    const currentUser = getCurrentUser();

    // Délai de sécurité pour le DOM
    await new Promise(resolve => setTimeout(resolve, 300));

    // Chargement des données
    await refreshAuditData();

    // Vérification des validations en attente (Auditeurs seulement)
    if (['auditeur', 'admin', 'superadmin'].includes(currentUser.role)) {
        await checkPendingValidations();
    }
}
// --- 3. CHARGEMENT DES DONNÉES ---
async function refreshAuditData() {
    const currentUser = getCurrentUser();
    const container = document.getElementById('performance-chart-container');

    try {
        const [perfRes, logsRes] = await Promise.all([
            fetch('/api/audit/performance-by-store', { headers: { 'x-user-role': currentUser.role } }),
            fetch('/api/audit/recent-logs', { headers: { 'x-user-role': currentUser.role } })
        ]);

        if (perfRes.status === 403 || logsRes.status === 403) throw new Error("Accès non autorisé.");

        performanceData = await perfRes.json();
        const logsData = await logsRes.json();

        // Affichage
        renderPerformanceChart(performanceData);
        renderAuditLogs(logsData);
        updateGlobalStatsFromData(performanceData);

    } catch (err) {
        console.error('❌ Erreur audit:', err);
        if (container) {
            container.innerHTML = `<p style="color:red; padding:20px;">⚠️ Erreur de chargement: ${err.message}</p>`;
        }
    }
}

function updateGlobalStatsFromData(data) {
    if (!data) return;
    const totalProfit = data.reduce((sum, s) => sum + (parseFloat(s.profit_virtuel_genere) || 0), 0);
    const totalQty = data.reduce((sum, s) => sum + (parseFloat(s.quantite_totale) || 0), 0);
    const totalAlerts = data.reduce((sum, s) => sum + (parseInt(s.alertes_qualite) || 0), 0);

    const setVal = (id, val) => { const el = document.getElementById(id); if(el) el.textContent = val; };

    setVal('audit-total-profit', Math.round(totalProfit).toLocaleString('fr-FR'));
    setVal('audit-total-qty', Math.round(totalQty).toLocaleString('fr-FR'));
    setVal('audit-alerts', totalAlerts);
}
function renderPerformanceChart(data) {
    const container = document.getElementById('performance-chart-container');
    const currentUser = getCurrentUser();

    if (!['superadmin', 'admin', 'auditeur'].includes(currentUser.role)) {
        container.innerHTML = `<p style="color:red;">⛔ Accès refusé.</p>`;
        return;
    }

    if (!data || data.length === 0) {
        container.innerHTML = `<p style="text-align:center; color:#999;">Aucune donnée disponible.</p>`;
        return;
    }

    let html = `<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 15px;">`;

    data.forEach(store => {
        const profit = parseFloat(store.profit_virtuel_genere) || 0;
        const color = profit >= 0 ? '#1565c0' : '#d32f2f';

        // ⚠️ IMPORTANT : Appeler la NOUVELLE fonction de store-detail.js
        html += `
        <div onclick="ouvrirDetailMagasin('${store.magasin_id}', '${store.nom_magasin.replace(/'/g, "\\'")}')"
            style="
            background: white; border: 2px solid ${color}20; border-radius: 12px; padding: 20px; 
            text-align: center; cursor: pointer; transition: all 0.2s ease; box-shadow: 0 2px 5px rgba(0,0,0,0.05);"
            onmouseover="this.style.transform='translateY(-3px)'; this.style.boxShadow='0 5px 15px rgba(0,0,0,0.1)';"
            onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='0 2px 5px rgba(0,0,0,0.05)';"
            title="Cliquez pour analyser ${store.nom_magasin}">
            
            <div style="font-size: 13px; font-weight: 600; margin-bottom: 10px; color: #333; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                ${store.nom_magasin}
            </div>
            
            <div style="font-size: 20px; font-weight: bold; color: ${color}; margin-bottom: 5px;">
                ${Math.round(profit).toLocaleString('fr-FR')} <span style="font-size:10px; color:#999">FCFA</span>
            </div>
            
            <div style="font-size: 11px; color: #666; background: ${color}10; padding: 4px 10px; border-radius: 15px; display: inline-block;">
                📦 ${store.nombre_admissions} op.
            </div>

            <div style="font-size:10px; color:#1565c0; margin-top:10px; text-decoration:underline;">
                Analyser <i class="fa-solid fa-magnifying-glass"></i>
            </div>
        </div>`;
    });

    html += `</div>`;
    container.innerHTML = html;
}
// --- 5. LOGS D'AUDIT ---
function renderAuditLogs(logs) {
    const list = document.getElementById('audit-log-list');
    if (!logs || logs.length === 0) {
        list.innerHTML = `<p style="text-align:center; color:#999;">Aucune transaction récente.</p>`;
        return;
    }

    list.innerHTML = logs.map(log => {
        const isPositive = log.montant > 0;
        return `
        <div style="padding:10px 0; border-bottom:1px solid #f0f0f0; display:flex; justify-content:space-between; align-items:center;">
            <div>
                <strong style="font-size:12px; display:block;">${log.action} <span style="font-weight:normal; color:#666;">- ${log.produit || '?'}</span></strong>
                <span style="font-size:10px; color:#999;">${new Date(log.date).toLocaleString()} • ${log.utilisateur}</span>
            </div>
            <div style="font-weight:bold; font-size:12px; color:${isPositive ? 'green' : '#d32f2f'};">
                ${isPositive ? '+' : ''}${Math.round(log.montant).toLocaleString()}
            </div>
        </div>`;
    }).join('');
}

// --- 6. VALIDATIONS (AUDITEUR) ---
async function checkPendingValidations() {
    try {
        const res = await fetch('/api/transferts/pending-audit');
        if(!res.ok) return;
        const pending = await res.json();

        const container = document.getElementById('audit-validation-queue');
        const notif = document.getElementById('notif'); // Assure-toi d'avoir cet ID dans ton HTML

        if (pending.length > 0 && container) {
            container.innerHTML = pending.map(t => `
                <div style="background:#fff3e0; border-left:4px solid orange; padding:10px; margin-bottom:10px; font-size:12px;">
                    <strong>Transfert #${t.id}</strong>: ${t.produit} (${t.quantite})<br>
                    De: ${t.magasinDepart} ➔ Vers: ${t.magasinDest}<br>
                    <div style="margin-top:5px; display:flex; gap:10px;">
                        <button onclick="approveTransfer('${t.id}')" style="background:#4caf50; color:white; border:none; padding:4px 8px; cursor:pointer;">Autoriser</button>
                        <button onclick="rejectTransfer('${t.id}')" style="background:#f44336; color:white; border:none; padding:4px 8px; cursor:pointer;">Refuser</button>
                    </div>
                </div>
            `).join('');
            if(notif) {
                notif.style.display = 'inline-block';
                notif.innerText = pending.length;
            }
        } else if (container) {
            container.innerHTML = '';
            if(notif) notif.style.display = 'none';
        }
    } catch (e) { console.error("Erreur validations", e); }
}

async function approveTransfer(id) { /* ... logique API existante ... */ }
async function rejectTransfer(id) { /* ... logique API existante ... */ }
    