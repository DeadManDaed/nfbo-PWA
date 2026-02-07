/**
 * audit.js - Module d'Audit & Performance NBFO
 * Version corrigée avec API complète
 */

// Variable globale pour stocker les données de performance
let performanceData = [];

// Récupération des informations utilisateur
function getCurrentUser() {
    // Essayer de récupérer depuis la variable globale (si définie dans app.js)
    if (typeof window.user !== 'undefined' && window.user) {
    return window.user;
    }
    
    // Sinon, récupérer depuis localStorage
    return {
        username: localStorage.getItem('username') || 'anonyme',
        nom: localStorage.getItem('nom') || localStorage.getItem('username') || 'Utilisateur',
        role: localStorage.getItem('role') || 'guest'
    };
}

/**
 * Initialisation du module audit
 */
async function initModuleAudit() {
    const currentUser = getCurrentUser();
    
    // On attend un court instant que le HTML soit injecté
    await new Promise(resolve => setTimeout(resolve, 300));
    
    // On lance tout en parallèle pour gagner du temps
    // Note: on ne charge plus loadGlobalStats() ici car refreshAuditData s'en chargera via le calcul local
    await refreshAuditData();
    
    if (currentUser.role === 'auditeur' || currentUser.role === 'admin' || currentUser.role === 'superadmin') {
        await checkPendingValidations();
    }
}

/**
 * Charge et affiche toutes les données d'audit
 */
async function refreshAuditData() {
    const currentUser = getCurrentUser();
    
    try {
        const [perfRes, logsRes] = await Promise.all([
            fetch('/api/audit/performance-by-store', {
                headers: { 'x-user-role': currentUser.role }
            }),
            fetch('/api/audit/recent-logs', {
                headers: { 'x-user-role': currentUser.role }
            })
        ]);

        if (perfRes.status === 403 || logsRes.status === 403) {
            throw new Error("Accès non autorisé.");
        }
   
        performanceData = await perfRes.json();
        const logsData = await logsRes.json();

        // 1. On affiche les graphiques
        renderPerformanceChart(performanceData);
        
        // 2. On affiche les logs
        renderAuditLogs(logsData);
        
        // 3. FORCE DE FRAPPE : On met à jour les Stats Globales directement depuis les données reçues
        // Cela résout définitivement le problème des "0"
        updateGlobalStatsFromData(performanceData);

    } catch (err) {
        console.error('❌ Erreur audit:', err);
        document.getElementById('performance-chart-container').innerHTML = 
            `<p style="color:red; padding:20px;">⚠️ ${err.message}</p>`;
    }
}
/**
 * Calcule et affiche les totaux directement depuis les données magasins
 * Plus fiable qu'un appel API séparé
 */
function updateGlobalStatsFromData(data) {
    if (!data) return;

    // Calcul des sommes
    const totalProfit = data.reduce((sum, store) => sum + (parseFloat(store.profit_virtuel_genere) || 0), 0);
    const totalQty = data.reduce((sum, store) => sum + (parseFloat(store.quantite_totale) || 0), 0);
    const totalAlerts = data.reduce((sum, store) => sum + (parseInt(store.alertes_qualite) || 0), 0);

    // Mise à jour du DOM sécurisée
    const profitEl = document.getElementById('audit-total-profit');
    const qtyEl = document.getElementById('audit-total-qty');
    const alertsEl = document.getElementById('audit-alerts');

    if (profitEl) profitEl.textContent = Math.round(totalProfit).toLocaleString('fr-FR');
    if (qtyEl) qtyEl.textContent = Math.round(totalQty).toLocaleString('fr-FR');
    if (alertsEl) alertsEl.textContent = totalAlerts;
    
    // Changement de couleur si alerte
    if (alertsEl && alertsEl.parentElement && totalAlerts > 0) {
        alertsEl.parentElement.style.background = '#ffebee';
        alertsEl.parentElement.style.borderLeft = '5px solid #d32f2f';
    }
}
/**
 * Génère le graphique de performance par magasin
 */

function renderPerformanceChart(data) {
    const container = document.getElementById('performance-chart-container');
    const currentUser = getCurrentUser();

    // Vérification de sécurité
    if (currentUser.role !== 'superadmin' && currentUser.role !== 'admin' && currentUser.role !== 'auditeur') {
        container.innerHTML = `<p style="color:red; padding:20px;">⛔ Accès refusé : Droits insuffisants.</p>`;
        return;
    }

    if (!data || data.length === 0) {
        container.innerHTML = `
            <div style="width:100%; text-align:center; padding:50px; color:#999;">
                <i class="fa-solid fa-chart-simple" style="font-size:48px; margin-bottom:15px;"></i>
                <p>Aucune donnée de performance disponible pour les 30 derniers jours.</p>
            </div>`;
        return;
    }

    // Calcul de la valeur maximale pour l'échelle (pour info, pas utilisé visuellement ici mais utile si on ajoutait une barre de progression)
    const maxProfit = Math.max(...data.map(d => parseFloat(d.profit_virtuel_genere) || 0), 1);

    let html = `<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 15px;">`;

    data.forEach(store => {
        const profit = parseFloat(store.profit_virtuel_genere) || 0;
        const color = profit > 0 ? 'var(--primary, #1565c0)' : '#d32f2f';
        const quantite = parseFloat(store.quantite_totale) || 0;
        
        // MODIFICATION : L'onclick est sur le conteneur principal (toute la carte est un bouton)
        html += `
        <div onclick="ouvrirDetailMagasin('${store.magasin_id}', '${store.nom_magasin}')"
            style="
            background: white; 
            border: 2px solid ${color}20; 
            border-radius: 12px; 
            padding: 20px; 
            text-align: center;
            transition: all 0.3s ease;
            cursor: pointer;
            box-shadow: 0 2px 8px rgba(0,0,0,0.08);"
            onmouseover="this.style.transform='translateY(-4px)'; this.style.boxShadow='0 4px 12px rgba(0,0,0,0.15)';"
            onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='0 2px 8px rgba(0,0,0,0.08)';"
            title="Cliquez pour voir le détail de ${store.nom_magasin}">
            
            <div style="
                font-size: 13px; 
                font-weight: 600; 
                margin-bottom: 12px; 
                color: #333;
                white-space: nowrap;
                overflow: hidden;
                text-overflow: ellipsis;">
                ${store.nom_magasin}
            </div>
            
            <div style="
                font-size: 22px; 
                font-weight: bold; 
                color: ${color}; 
                margin-bottom: 8px;">
                ${Math.round(profit).toLocaleString('fr-FR')}
            </div>
            
            <div style="font-size: 10px; color: #999; margin-bottom: 10px;">
                FCFA
            </div>
            
            <div style="
                font-size: 11px; 
                color: #666; 
                padding: 6px 12px; 
                background: ${color}10; 
                border-radius: 20px;
                display: inline-block;
                margin-bottom: 10px;">
                📦 ${store.nombre_admissions} admission${store.nombre_admissions > 1 ? 's' : ''}
            </div>

            <div style="font-size:10px; color:#1565c0; margin-top:5px; text-decoration:underline;">
                Voir détail & analyse <i class="fa-solid fa-arrow-right"></i>
            </div>
        </div>`;
    });

    html += `</div>`;
    container.innerHTML = html;
}



/* function renderPerformanceChart(data) {
    const container = document.getElementById('performance-chart-container');
    const currentUser = getCurrentUser();

    // Vérification de sécurité
    if (currentUser.role !== 'superadmin' && currentUser.role !== 'admin' && currentUser.role !== 'auditeur') {
        container.innerHTML = `<p style="color:red; padding:20px;">⛔ Accès refusé : Droits insuffisants.</p>`;
        return;
    }

    if (!data || data.length === 0) {
        container.innerHTML = `
            <div style="width:100%; text-align:center; padding:50px; color:#999;">
                <i class="fa-solid fa-chart-simple" style="font-size:48px; margin-bottom:15px;"></i>
                <p>Aucune donnée de performance disponible pour les 30 derniers jours.</p>
            </div>`;
        return;
    }

    // Calcul de la valeur maximale pour l'échelle
    const maxProfit = Math.max(...data.map(d => parseFloat(d.profit_virtuel_genere) || 0), 1);

    let html = `<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 15px;">`;

    data.forEach(store => {
    const profit = parseFloat(store.profit_virtuel_genere) || 0;
    const color = profit > 0 ? 'var(--primary, #1565c0)' : '#d32f2f';
    const quantite = parseFloat(store.quantite_totale) || 0;
    
    html += `
        <div style="
            background: white; 
            border: 2px solid ${color}20; 
            border-radius: 12px; 
            padding: 20px; 
            text-align: center;
            transition: all 0.3s ease;
            cursor: pointer;
            box-shadow: 0 2px 8px rgba(0,0,0,0.08);"
            onmouseover="this.style.transform='translateY(-4px)'; this.style.boxShadow='0 4px 12px rgba(0,0,0,0.15)';"
            onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='0 2px 8px rgba(0,0,0,0.08)';"
            title="Quantité: ${Math.round(quantite).toLocaleString('fr-FR')} unités">
            
            <!-- Nom du magasin -->
            <div style="
                font-size: 13px; 
                font-weight: 600; 
                margin-bottom: 12px; 
                color: #333;
                white-space: nowrap;
                overflow: hidden;
                text-overflow: ellipsis;">
                ${store.nom_magasin}
            </div>
            
            <!-- Profit (valeur principale) -->
            <div style="
                font-size: 22px; 
                font-weight: bold; 
                color: ${color}; 
                margin-bottom: 8px;">
                ${Math.round(profit).toLocaleString('fr-FR')}
            </div>
            
            <!-- Label FCFA -->
            <div style="font-size: 10px; color: #999; margin-bottom: 10px;">
                FCFA
            </div>
            
            <!-- Nombre d'admissions -->
            <div style="
                font-size: 11px; 
                color: #666; 
                padding: 6px 12px; 
                background: ${color}10; 
                border-radius: 20px;
                display: inline-block;">
                📦 ${store.nombre_admissions} admission${store.nombre_admissions > 1 ? 's' : ''}
            </div>
        </div>`;
});

html += `</div>`;
    // AJOUT : onclick="ouvrirDetailMagasin(...)"
        html += `
            <div onclick="ouvrirDetailMagasin('${store.magasin_id}', '${store.nom_magasin}')"
                style="cursor: pointer; /* ... tes styles existants ... */">
                
                <div style="font-size:10px; color:#1565c0; margin-top:8px; text-decoration:underline;">
                    Voir détail & analyse <i class="fa-solid fa-arrow-right"></i>
                </div>
            </div>`;
    });
    html += `</div>`;
    container.innerHTML = html;
} */

/**
 * Affiche les logs d'audit récents
 */
function renderAuditLogs(logs) {
    const list = document.getElementById('audit-log-list');
    
    if (!logs || logs.length === 0) {
        list.innerHTML = `
            <div style="text-align:center; padding:30px; color:#999;">
                <i class="fa-solid fa-clipboard-list" style="font-size:32px; margin-bottom:10px;"></i>
                <p>Aucune transaction récente.</p>
            </div>`;
        return;
    }

    list.innerHTML = logs.map(log => {
        const date = new Date(log.date);
        const actionType = log.action.includes('admission') ? 'Admission' : 
                          log.action.includes('vente') ? 'Vente' : 
                          log.action.includes('transfert') ? 'Transfert' : 'Système';
        
        const icon = actionType === 'Admission' ? 'fa-box' :
                     actionType === 'Vente' ? 'fa-cash-register' :
                     actionType === 'Transfert' ? 'fa-truck' : 'fa-gear';
        
        return `
            <div style="padding:12px 0; border-bottom:1px solid #f5f5f5; transition: background 0.2s;"
                 onmouseover="this.style.background='#f9f9f9'"
                 onmouseout="this.style.background='white'">
                <div style="display:flex; justify-content:space-between; align-items:center;">
                    <div style="display:flex; align-items:center; gap:8px;">
                        <i class="fa-solid ${icon}" style="color:var(--primary); font-size:14px;"></i>
                        <strong style="font-size:12px;">${actionType}</strong>
                    </div>
                    ${log.montant > 0 ? 
                        `<span style="color:#2e7d32; font-weight:bold; font-size:12px;">+${Math.round(log.montant).toLocaleString('fr-FR')} FCFA</span>` 
                        : ''}
                </div>
                <div style="font-size:10px; color:#666; margin-top:4px; margin-left:22px;">
                    ${date.toLocaleDateString('fr-FR', {day:'2-digit', month:'short', hour:'2-digit', minute:'2-digit'})} 
                    • ${log.utilisateur}
                    ${log.magasin ? ` • ${log.magasin}` : ''}
                </div>
            </div>`;
    }).join('');
}

/**
 * Vérifie les transferts en attente de validation
 */
async function checkPendingValidations() {
    const currentUser = getCurrentUser();
    
    if (currentUser.role !== 'auditeur' && currentUser.role !== 'admin' && currentUser.role !== 'superadmin') return;

    try {
        const res = await fetch('/api/transferts/pending-audit');
        if (!res.ok) throw new Error('Erreur chargement validations');
        
        const pendingTransfers = await res.json();
        const container = document.getElementById('audit-validation-queue');
        const notif = document.getElementById('notif');

        if (pendingTransfers.length > 0) {
            container.innerHTML = pendingTransfers.map(t => `
                <div class="audit-card-urgent" style="
                    background:#fff3e0; 
                    border-left:4px solid #f57c00; 
                    padding:15px; 
                    margin:10px 0; 
                    border-radius:6px;">
                    <h4 style="margin:0 0 10px 0; color:#e65100;">
                        <i class="fa-solid fa-triangle-exclamation"></i> 
                        Validation Requise : Transfert #${t.id}
                    </h4>
                    <p style="margin:5px 0; font-size:13px;">
                        <strong>De:</strong> ${t.magasinDepart} 
                        <i class="fa-solid fa-arrow-right" style="margin:0 8px;"></i> 
                        <strong>Vers:</strong> ${t.magasinDest}
                    </p>
                    <p style="margin:5px 0; font-size:13px;">
                        <strong>Produit:</strong> ${t.produit} | 
                        <strong>Qté:</strong> ${t.quantite}
                    </p>
                    <div style="display:flex; gap:10px; margin-top:12px;">
                        <button onclick="approveTransfer('${t.id}')" 
                                style="background:#2e7d32; color:white; border:none; padding:8px 16px; border-radius:4px; cursor:pointer;">
                            <i class="fa-solid fa-check"></i> AUTORISER
                        </button>
                        <button onclick="rejectTransfer('${t.id}')" 
                                style="background:#c62828; color:white; border:none; padding:8px 16px; border-radius:4px; cursor:pointer;">
                            <i class="fa-solid fa-times"></i> BLOQUER
                        </button>
                    </div>
                </div>
            `).join('');
            
            notif.innerHTML = `<span style="background:#f57c00; color:white; padding:4px 12px; border-radius:12px; font-size:11px; font-weight:bold;">
                ${pendingTransfers.length} en attente
            </span>`;
            notif.style.display = 'inline-block';
        } else {
            container.innerHTML = '';
            notif.style.display = 'none';
        }
    } catch (err) {
        console.error('❌ Erreur pending validations:', err);
    }
}
 /* Exporte le rapport d'audit en PDF/Impression
 * Transforme les données visuelles (cartes) en tableau structuré
 */
function exportAuditPDF() {
    const currentUser = getCurrentUser();
    
    // 1. Sécurité
    if (currentUser.role !== 'superadmin' && currentUser.role !== 'admin' && currentUser.role !== 'auditeur') {
        alert("⛔ Action non autorisée.");
        return;
    }

    // 2. Récupération des stats globales affichées à l'écran
    const stats = {
        profit: document.getElementById('audit-total-profit').textContent,
        qty: document.getElementById('audit-total-qty').textContent,
        alerts: document.getElementById('audit-alerts').textContent
    };

    // 3. Calcul des totaux pour le bas du tableau
    const tableTotals = performanceData.reduce((acc, store) => {
        acc.admissions += parseInt(store.nombre_admissions) || 0;
        acc.qty += parseFloat(store.quantite_totale) || 0;
        acc.profit += parseFloat(store.profit_virtuel_genere) || 0;
        return acc;
    }, { admissions: 0, qty: 0, profit: 0 });

    // 4. Ouverture de la fenêtre d'impression
    const printWindow = window.open('', '_blank', 'height=800,width=1000');

    printWindow.document.write(`
        <html>
            <head>
                <title>Rapport d'Audit NBFO - ${new Date().toLocaleDateString('fr-FR')}</title>
                <style>
                    body { 
                        font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; 
                        padding: 40px; 
                        color: #333;
                    }
                    .header {
                        border-bottom: 2px solid #1565c0;
                        padding-bottom: 20px;
                        margin-bottom: 30px;
                        display: flex;
                        justify-content: space-between;
                        align-items: flex-end;
                    }
                    .brand { font-size: 24px; font-weight: bold; color: #1565c0; }
                    .meta { font-size: 12px; color: #666; text-align: right; }
                    
                    /* Cartes résumées en haut */
                    .summary-grid {
                        display: grid;
                        grid-template-columns: repeat(3, 1fr);
                        gap: 15px;
                        margin-bottom: 40px;
                    }
                    .summary-card {
                        background: #f8f9fa;
                        border: 1px solid #ddd;
                        padding: 15px;
                        border-radius: 6px;
                        text-align: center;
                    }
                    .summary-label { font-size: 11px; text-transform: uppercase; color: #666; letter-spacing: 1px; }
                    .summary-value { font-size: 20px; font-weight: bold; color: #333; margin-top: 5px; }

                    /* Le Tableau de données */
                    table { 
                        width: 100%; 
                        border-collapse: collapse; 
                        margin-top: 10px; 
                        font-size: 12px;
                    }
                    th { 
                        background-color: #1565c0; 
                        color: white; 
                        padding: 10px; 
                        text-align: left; 
                        font-weight: 600;
                    }
                    td { 
                        border-bottom: 1px solid #eee; 
                        padding: 10px; 
                    }
                    tr:nth-child(even) { background-color: #f9f9f9; }
                    
                    /* Ligne de total */
                    .total-row td {
                        border-top: 2px solid #333;
                        font-weight: bold;
                        background-color: #e3f2fd;
                        font-size: 13px;
                    }

                    .footer {
                        margin-top: 50px;
                        font-size: 10px;
                        color: #999;
                        text-align: center;
                        border-top: 1px solid #eee;
                        padding-top: 10px;
                    }
                </style>
            </head>
            <body>
                <div class="header">
                    <div class="brand">NBFO SYSTEM</div>
                    <div class="meta">
                        Rapport généré le ${new Date().toLocaleString('fr-FR')}<br>
                        Auditeur: ${currentUser.nom || currentUser.username}
                    </div>
                </div>
                
                <h2>📊 Rapport de Performance Global</h2>

                <div class="summary-grid">
                    <div class="summary-card">
                        <div class="summary-label">Profit Virtuel</div>
                        <div class="summary-value" style="color:#1565c0">${stats.profit} FCFA</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-label">Flux Quantité</div>
                        <div class="summary-value" style="color:#2e7d32">${stats.qty} Unités</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-label">Alertes</div>
                        <div class="summary-value" style="color:#d32f2f">${stats.alerts}</div>
                    </div>
                </div>

                <h3>Détail par Magasin</h3>
                <table>
                    <thead>
                        <tr>
                            <th>Magasin</th>
                            <th style="text-align:center">Admissions (Lots)</th>
                            <th style="text-align:right">Quantité (Unités)</th>
                            <th style="text-align:right">Profit Généré (FCFA)</th>
                            <th style="text-align:center">Alertes</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${performanceData.map(store => `
                            <tr>
                                <td><strong>${store.nom_magasin}</strong></td>
                                <td style="text-align:center">${store.nombre_admissions}</td>
                                <td style="text-align:right">${Math.round(store.quantite_totale).toLocaleString('fr-FR')}</td>
                                <td style="text-align:right; color:${store.profit_virtuel_genere >= 0 ? '#2e7d32' : '#c62828'}">
                                    ${Math.round(store.profit_virtuel_genere).toLocaleString('fr-FR')}
                                </td>
                                <td style="text-align:center">${store.alertes_qualite || '-'}</td>
                            </tr>
                        `).join('')}
                        
                        <tr class="total-row">
                            <td>TOTAL GÉNÉRAL</td>
                            <td style="text-align:center">${tableTotals.admissions}</td>
                            <td style="text-align:right">${Math.round(tableTotals.qty).toLocaleString('fr-FR')}</td>
                            <td style="text-align:right">${Math.round(tableTotals.profit).toLocaleString('fr-FR')}</td>
                            <td style="text-align:center">${stats.alerts}</td>
                        </tr>
                    </tbody>
                </table>

                <div class="footer">
                    Document confidentiel interne - Ne pas diffuser sans autorisation.<br>
                    © ${new Date().getFullYear()} NBFO System
                </div>
            </body>
        </html>
    `);

    printWindow.document.close();
    // Petit délai pour assurer le chargement des styles avant l'impression
    setTimeout(() => {
        printWindow.focus();
        printWindow.print();
    }, 500);
}

// Fonctions de validation de transferts (si elles n'existent pas déjà)
async function approveTransfer(transferId) {
    const currentUser = getCurrentUser();
    
    try {
        const res = await fetch(`/api/transferts/${transferId}/approve`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ auditeur: currentUser.username })
        });
        
        if (res.ok) {
            alert('✅ Transfert autorisé');
            await checkPendingValidations();
        } else {
            alert('❌ Erreur lors de l\'autorisation');
        }
    } catch (err) {
        console.error('Erreur approve:', err);
        alert('Erreur réseau');
    }
}

async function rejectTransfer(transferId) {
    const currentUser = getCurrentUser();
    const raison = prompt('Raison du blocage:');
    if (!raison) return;
    
    try {
        const res = await fetch(`/api/transferts/${transferId}/reject`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ auditeur: currentUser.username, raison })
        });
        
        if (res.ok) {
            alert('🚫 Transfert bloqué');
            await checkPendingValidations();
        } else {
            alert('❌ Erreur lors du blocage');
        }
    } catch (err) {
        console.error('Erreur reject:', err);
        alert('Erreur réseau');
    }
}
// === NOUVELLES FONCTIONS D'ANALYSE DÉTAILLÉE ===

/**
 * Ouvre la modale et charge les 3 vues
 */
async function ouvrirDetailMagasin(magasinId, nomMagasin) {
    // 1. Création/Affichage de la modale (Code HTML injecté dynamiquement pour éviter de polluer le dashboard.html)
    let modal = document.getElementById('modal-detail-store');
    if (!modal) {
        document.body.insertAdjacentHTML('beforeend', getModalHTML());
        modal = document.getElementById('modal-detail-store');
    }
    
    document.getElementById('modal-store-title').innerText = `Audit Détaillé : ${nomMagasin}`;
    document.getElementById('modal-detail-store').style.display = 'flex';
    
    // Reset du contenu
    document.getElementById('store-tab-content').innerHTML = '<div style="padding:20px; text-align:center;"><i class="fa-solid fa-spinner fa-spin"></i> Analyse en cours...</div>';

    try {
        // 2. Récupération des données complètes (Simulation API - à adapter avec tes vraies routes)
        // On demande les produits ET les logs du magasin
        const [stockRes, logsRes] = await Promise.all([
            fetch(`/api/magasins/${magasinId}/stock`), // Ta route existante de stock
            fetch(`/api/audit/logs?store_id=${magasinId}&days=30`) // Une route filtrée par magasin
        ]);

        const stocks = await stockRes.json();
        const logs = await logsRes.json();

        // 3. Utilisation du MOTEUR INTELLIGENT (b.3)
        // Si stock-intelligence.js est chargé, on l'utilise, sinon fallback simple
        let analyse = { stars:[], peremption:[], rupture:[], dormants:[] };
        if (window.StockIntelligence) {
            analyse = window.StockIntelligence.analyserInventaire(stocks, logs);
        }

        // 4. Stockage temporaire pour navigation entre onglets
        window.currentStoreData = { stocks, logs, analyse };

        // 5. Affichage par défaut (Onglet 1: Transactions)
        switchTab('transactions');

    } catch (e) {
        console.error("Erreur chargement détail", e);
        document.getElementById('store-tab-content').innerHTML = '<p style="color:red">Impossible de charger les détails du magasin.</p>';
    }
}

function switchTab(tabName) {
    const content = document.getElementById('store-tab-content');
    const data = window.currentStoreData;
    
    // Gestion active des boutons
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.getElementById(`btn-${tabName}`).classList.add('active');

    if (tabName === 'transactions') {
        // VUE 1 : LISTE DÉTAILLÉE
        content.innerHTML = renderTransactionsTable(data.logs);
    } 
    else if (tabName === 'trends') {
        // VUE 2 : GRAPHIQUE TENDANCES (Produit par Produit)
        content.innerHTML = renderTrendsChart(data.logs);
    } 
    else if (tabName === 'health') {
        // VUE 3 : STOCK INTELLIGENT (Surbrillance)
        content.innerHTML = renderHealthDashboard(data.analyse);
    }
}

// --- RENDU DES VUES ---

function renderTransactionsTable(logs) {
    if(!logs.length) return '<p>Aucune transaction sur la période.</p>';
    return `
        <div style="overflow-y:auto; max-height:400px;">
            <table style="width:100%; border-collapse:collapse; font-size:12px;">
                <thead style="background:#f5f5f5; position:sticky; top:0;">
                    <tr><th>Date</th><th>Action</th><th>Produit</th><th style="text-align:right">Qté</th><th style="text-align:right">Impact</th></tr>
                </thead>
                <tbody>
                    ${logs.map(l => `
                    <tr style="border-bottom:1px solid #eee;">
                        <td style="padding:8px;">${new Date(l.date).toLocaleDateString()}</td>
                        <td>${l.action}</td>
                        <td>${l.produit}</td>
                        <td style="text-align:right; font-weight:bold;">${l.quantite}</td>
                        <td style="text-align:right; color:${l.montant > 0 ? 'green' : 'red'}">${Math.round(l.montant)}</td>
                    </tr>`).join('')}
                </tbody>
            </table>
        </div>`;
}

function renderHealthDashboard(analyse) {
    // C'est ici que la magie de (b.1, b.2, b.3) s'affiche
    return `
        <div style="display:grid; grid-template-columns: 1fr 1fr; gap:20px;">
            
            <div class="health-card" style="border-left:4px solid gold;">
                <h4>🌟 Produits Stars (Top Rotation)</h4>
                ${analyse.stars.length ? 
                    `<ul>${analyse.stars.map(p => `<li><strong>${p.nom}</strong></li>`).join('')}</ul>` : 
                    '<p style="color:#999; font-style:italic">Aucun produit ne se démarque.</p>'}
            </div>

            <div class="health-card" style="border-left:4px solid #d32f2f; background:#ffebee;">
                <h4 style="color:#d32f2f">⚠️ Attention : Péremption</h4>
                ${analyse.peremption.length ? 
                    `<ul>${analyse.peremption.map(p => `<li>${p.nom} (${p.status})</li>`).join('')}</ul>` : 
                    '<p style="color:green">Aucun produit proche de la date limite.</p>'}
            </div>

            <div class="health-card" style="border-left:4px solid orange;">
                <h4>📉 Risque Rupture</h4>
                ${analyse.rupture.length ? 
                    `<ul>${analyse.rupture.map(p => `<li>${p.nom}: Reste ${p.stock_actuel}</li>`).join('')}</ul>` : 
                    '<p style="color:green">Stocks confortables.</p>'}
            </div>

            <div class="health-card" style="border-left:4px solid #90a4ae;">
                <h4>💤 Stocks Dormants (+60j)</h4>
                <p style="font-size:11px; color:#666; margin-bottom:5px;">Produits en stock mais sans vente récente.</p>
                ${analyse.dormants.length ? 
                    `<ul>${analyse.dormants.map(p => `<li>${p.nom} (Valeur: ${p.value} FCFA)</li>`).join('')}</ul>` : 
                    '<p>Tout le stock est actif.</p>'}
            </div>
        </div>
    `;
}

function renderTrendsChart(logs) {
    // Simplification visuelle : Barres HTML simples pour éviter Chart.js si pas chargé
    // On agrège par produit : Net (Entrées - Sorties)
    const trends = {};
    logs.forEach(l => {
        if(!trends[l.produit]) trends[l.produit] = 0;
        trends[l.produit] += (l.action === 'vente' || l.action === 'sortie') ? -parseFloat(l.quantite) : parseFloat(l.quantite);
    });

    return `
        <div style="padding:10px;">
            <h4>Balance des Mouvements (30j)</h4>
            ${Object.keys(trends).map(prod => {
                const val = trends[prod];
                const width = Math.min(Math.abs(val) * 2, 100); // Echelle arbitraire pour demo
                const color = val >= 0 ? '#4caf50' : '#f44336';
                return `
                    <div style="margin-bottom:8px; display:flex; align-items:center;">
                        <span style="width:120px; font-size:12px; text-align:right; padding-right:10px;">${prod}</span>
                        <div style="flex:1; background:#eee; height:10px; border-radius:5px; position:relative;">
                            <div style="
                                width:${width}px; 
                                background:${color}; 
                                height:100%; 
                                border-radius:5px;
                                position:absolute;
                                left:${val >= 0 ? '0' : 'auto'};
                                right:${val < 0 ? '0' : 'auto'};
                            "></div>
                        </div>
                        <span style="width:40px; font-size:11px; padding-left:10px;">${val > 0 ? '+' : ''}${val}</span>
                    </div>
                `;
            }).join('')}
        </div>
    `;
}

// Helper HTML pour la modale
function getModalHTML() {
    return `
    <div id="modal-detail-store" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.5); z-index:9999; justify-content:center; align-items:center;">
        <div style="background:white; width:90%; max-width:800px; height:80%; border-radius:12px; display:flex; flex-direction:column; overflow:hidden; box-shadow:0 10px 25px rgba(0,0,0,0.2);">
            
            <div style="padding:15px; border-bottom:1px solid #eee; display:flex; justify-content:space-between; align-items:center; background:#1565c0; color:white;">
                <h3 id="modal-store-title" style="margin:0;">Détail Magasin</h3>
                <button onclick="document.getElementById('modal-detail-store').style.display='none'" style="background:none; border:none; color:white; font-size:20px; cursor:pointer;">&times;</button>
            </div>

            <div style="display:flex; border-bottom:1px solid #ddd;">
                <button id="btn-transactions" class="tab-btn active" onclick="switchTab('transactions')" style="flex:1; padding:15px; background:none; border:none; cursor:pointer; font-weight:bold;">📄 Transactions</button>
                <button id="btn-trends" class="tab-btn" onclick="switchTab('trends')" style="flex:1; padding:15px; background:none; border:none; cursor:pointer; font-weight:bold;">📊 Tendances</button>
                <button id="btn-health" class="tab-btn" onclick="switchTab('health')" style="flex:1; padding:15px; background:none; border:none; cursor:pointer; font-weight:bold;">❤️ Santé Stock</button>
            </div>

            <div id="store-tab-content" style="flex:1; overflow-y:auto; padding:20px;">
                </div>
            
            <style>
                .tab-btn.active { border-bottom: 3px solid #1565c0; color: #1565c0; background: #f5fafd !important; }
                .tab-btn:hover { background: #f0f0f0; }
                .health-card { padding: 15px; background: #fafafa; border-radius: 6px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
                .health-card h4 { margin-top: 0; margin-bottom: 10px; font-size: 14px; }
                .health-card ul { padding-left: 20px; margin: 0; font-size: 13px; }
            </style>
        </div>
    </div>`;
}
// Fonction helper pour logger les erreurs de déploiement
function logDeploymentError(context, error) {
    console.error(`[DEPLOYMENT ERROR - ${context}]:`, error);
    // Tu peux aussi envoyer à un service de monitoring si tu en as un
}
