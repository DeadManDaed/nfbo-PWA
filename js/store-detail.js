/**
 * store-detail.js - Module de drill-down détaillé par magasin
 * Affichage : Transactions, Alertes, Performances, Stocks
 */

let activeStoreId = null;
let activeStoreName = null;
let storeData = {
    transactions: [],
    stocks: [],
    analyse: {},
    stats: {}
};

// Configuration des périodes pour l'historique
const PERIODES = {
    semaine: 7,
    mois: 30,
    trimestre: 90
};

let periodeActive = 'mois'; // Par défaut : 30 jours

// ========================================
// 1. OUVERTURE DE LA MODALE
// ========================================

async function ouvrirDetailMagasin(magasinId, nomMagasin) {
    activeStoreId = magasinId;
    activeStoreName = nomMagasin;
    
    // Créer la modale si elle n'existe pas
    if (!document.getElementById('modal-store-detail')) {
        document.body.insertAdjacentHTML('beforeend', getModalHTML());
    }
    
    const modal = document.getElementById('modal-store-detail');
    document.getElementById('modal-store-title').innerText = `📊 Analyse : ${nomMagasin}`;
    modal.style.display = 'flex';
    
    // Charger les données
    await chargerDonneesMagasin(magasinId);
    
    // Afficher l'onglet Transactions par défaut
    switchStoreTab('transactions');
}

// ========================================
// 2. CHARGEMENT DES DONNÉES
// ========================================

async function chargerDonneesMagasin(magasinId) {
    const loader = document.getElementById('store-content');
    loader.innerHTML = `
        <div style="text-align:center; padding:60px;">
            <i class="fa-solid fa-spinner fa-spin" style="font-size:40px; color:#1565c0;"></i>
            <p style="margin-top:20px; color:#666;">Chargement des données...</p>
        </div>
    `;
    
    try {
        const [admissionsRes, retraitsRes, transfertsRes, stocksRes] = await Promise.all([
            fetch(`/api/magasins/${magasinId}/admissions`),
            fetch(`/api/magasins/${magasinId}/retraits`),
            fetch(`/api/magasins/${magasinId}/transferts`),
            fetch(`/api/magasins/${magasinId}/stocks`)
        ]);
        
        if (!admissionsRes.ok || !retraitsRes.ok || !transfertsRes.ok || !stocksRes.ok) {
            throw new Error('Erreur de chargement des données');
        }
        
        const admissions = await admissionsRes.json();
        const retraits = await retraitsRes.json();
        const transferts = await transfertsRes.json();
        const stocks = await stocksRes.json();
        
        // Consolidation des transactions
        storeData.transactions = [
            ...admissions.map(a => ({ ...a, type: 'admission', icon: '📥', color: '#4caf50' })),
            ...retraits.map(r => ({ ...r, type: 'retrait', icon: '📤', color: '#f44336' })),
            ...transferts.map(t => ({ ...t, type: 'transfert', icon: '🔄', color: '#ff9800' }))
        ].sort((a, b) => new Date(b.date_operation || b.date_creation) - new Date(a.date_operation || a.date_creation));
        
        storeData.stocks = stocks;
        
        // Analyse intelligente avec StockIntelligence
        if (typeof window.StockIntelligence !== 'undefined') {
            storeData.analyse = window.StockIntelligence.analyserInventaire(stocks, storeData.transactions);
        }
        
        // Calcul des stats
        calculerStats();
        
    } catch (err) {
        console.error('❌ Erreur chargement magasin:', err);
        loader.innerHTML = `
            <div style="text-align:center; padding:40px; color:#d32f2f;">
                <i class="fa-solid fa-triangle-exclamation" style="font-size:40px;"></i>
                <p style="margin-top:20px;">Erreur lors du chargement des données</p>
                <button onclick="chargerDonneesMagasin('${magasinId}')" style="margin-top:15px; padding:10px 20px; background:#1565c0; color:white; border:none; border-radius:6px; cursor:pointer;">
                    Réessayer
                </button>
            </div>
        `;
    }
}

/*
function calculerStats() {
    const totalAdmissions = storeData.transactions.filter(t => t.type === 'admission').length;
    const totalRetraits = storeData.transactions.filter(t => t.type === 'retrait').length;
    const totalTransferts = storeData.transactions.filter(t => t.type === 'transfert').length;
    
    const valeurStock = storeData.stocks.reduce((sum, s) => {
        return sum + (parseFloat(s.stock_actuel || 0) * parseFloat(s.prix_ref || 0));
    }, 0);
    
    storeData.stats = {
        totalAdmissions,
        totalRetraits,
        totalTransferts,
        valeurStock,
        produitsEnStock: storeData.stocks.filter(s => parseFloat(s.stock_actuel) > 0).length,
        scoreGlobal: storeData.analyse.score_sante || 100
    };
}
*/
function calculerStats() {
    // 1. Calculs
    const totalAdmissions = storeData.transactions.filter(t => t.type === 'admission').length;
    const totalRetraits = storeData.transactions.filter(t => t.type === 'retrait').length;
    const totalTransferts = storeData.transactions.filter(t => t.type === 'transfert').length;

    const valeurStock = storeData.stocks.reduce((sum, s) => {
        return sum + (parseFloat(s.stock_actuel || 0) * parseFloat(s.prix_ref || 0));
    }, 0);

    storeData.stats = {
        totalAdmissions,
        totalRetraits,
        totalTransferts,
        valeurStock,
        produitsEnStock: storeData.stocks.filter(s => parseFloat(s.stock_actuel) > 0).length,
        scoreGlobal: storeData.analyse?.score_sante || 100
    };

    // 2. MISE À JOUR VISUELLE (Le correctif est ici)
    const setTxt = (id, val) => { const el = document.getElementById(id); if(el) el.innerText = val; };
    
    setTxt('stat-valeur', Math.round(valeurStock).toLocaleString('fr-FR') + ' FCFA');
    setTxt('stat-produits', storeData.stats.produitsEnStock);
    setTxt('stat-operations', storeData.transactions.length); // Total filtré par période si nécessaire
    setTxt('stat-score', storeData.stats.scoreGlobal + '/100');
    
    // Badge rouge sur l'onglet Alertes
    const nbAlertes = (storeData.analyse.peremption?.length||0) + (storeData.analyse.rupture?.length||0);
    const badge = document.getElementById('badge-alertes');
    if(badge) {
        badge.style.display = nbAlertes > 0 ? 'inline-block' : 'none';
        badge.innerText = nbAlertes;
    }
}



// ========================================
// 3. GESTION DES ONGLETS
// ========================================

function switchStoreTab(tab) {
    // Reset styles des boutons
    document.querySelectorAll('.store-tab-btn').forEach(btn => {
        btn.style.background = 'white';
        btn.style.color = '#666';
        btn.style.borderBottom = '2px solid transparent';
    });
    
    // Activer le bouton sélectionné
    const activeBtn = document.getElementById(`btn-${tab}`);
    if (activeBtn) {
        activeBtn.style.background = '#f5f5f5';
        activeBtn.style.color = '#1565c0';
        activeBtn.style.borderBottom = '2px solid #1565c0';
    }
    
    // Afficher le contenu
    const content = document.getElementById('store-content');
    
    switch(tab) {
        case 'transactions':
            content.innerHTML = renderTransactions();
            break;
        case 'alertes':
            content.innerHTML = renderAlertes();
            break;
        /*case 'performances':
            content.innerHTML = renderPerformances();
            initPerformanceChart();
            break;*/
    case 'performances':
        // CORRECTIF : On recalcule l'intelligence sur la période active seulement
        const transactionsFiltrees = filtrerParPeriode(storeData.transactions);
        storeData.analyse = window.StockIntelligence.analyserInventaire(storeData.stocks, transactionsFiltrees);
        
        // Mise à jour du score dans le header suite au nouveau calcul
        calculerStats(); 
        
        content.innerHTML = renderPerformances();
        setTimeout(initPerformanceChart, 50); // Petit délai pour que le canvas existe
        break;

        case 'stocks':
            content.innerHTML = renderStocks();
            break;
        default:
            content.innerHTML = '<p style="text-align:center; padding:40px;">Onglet inconnu</p>';
    }
}

// ========================================
// 4. ONGLET : TRANSACTIONS
// ========================================

function renderTransactions() {
    const transactions = filtrerParPeriode(storeData.transactions);
    
    if (transactions.length === 0) {
        return `
            <div style="text-align:center; padding:60px; color:#999;">
                <i class="fa-solid fa-inbox" style="font-size:50px; margin-bottom:20px;"></i>
                <p>Aucune transaction trouvée pour cette période</p>
            </div>
        `;
    }
    
    const groupes = {
        admission: transactions.filter(t => t.type === 'admission'),
        retrait: transactions.filter(t => t.type === 'retrait'),
        transfert: transactions.filter(t => t.type === 'transfert')
    };
    
    return `
        <div style="padding:20px;">
            <!-- Sélecteur de période -->
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px; padding-bottom:15px; border-bottom:2px solid #eee;">
                <h3 style="margin:0; color:#333;">Historique des transactions</h3>
                <div style="display:flex; gap:10px;">
                    <button onclick="changerPeriode('semaine')" class="periode-btn ${periodeActive === 'semaine' ? 'active' : ''}" style="padding:6px 12px; border:1px solid #ddd; border-radius:6px; cursor:pointer; background:${periodeActive === 'semaine' ? '#1565c0' : 'white'}; color:${periodeActive === 'semaine' ? 'white' : '#666'};">7 jours</button>
                    <button onclick="changerPeriode('mois')" class="periode-btn ${periodeActive === 'mois' ? 'active' : ''}" style="padding:6px 12px; border:1px solid #ddd; border-radius:6px; cursor:pointer; background:${periodeActive === 'mois' ? '#1565c0' : 'white'}; color:${periodeActive === 'mois' ? 'white' : '#666'};">30 jours</button>
                    <button onclick="changerPeriode('trimestre')" class="periode-btn ${periodeActive === 'trimestre' ? 'active' : ''}" style="padding:6px 12px; border:1px solid #ddd; border-radius:6px; cursor:pointer; background:${periodeActive === 'trimestre' ? '#1565c0' : 'white'}; color:${periodeActive === 'trimestre' ? 'white' : '#666'};">90 jours</button>
                </div>
            </div>
            
            <!-- Stats rapides -->
            <div style="display:grid; grid-template-columns:repeat(3, 1fr); gap:15px; margin-bottom:25px;">
                <div style="background:#e8f5e9; padding:15px; border-radius:8px; border-left:4px solid #4caf50;">
                    <div style="font-size:12px; color:#2e7d32; font-weight:bold;">ADMISSIONS</div>
                    <div style="font-size:24px; font-weight:bold; color:#1b5e20;">${groupes.admission.length}</div>
                </div>
                <div style="background:#ffebee; padding:15px; border-radius:8px; border-left:4px solid #f44336;">
                    <div style="font-size:12px; color:#c62828; font-weight:bold;">RETRAITS</div>
                    <div style="font-size:24px; font-weight:bold; color:#b71c1c;">${groupes.retrait.length}</div>
                </div>
                <div style="background:#fff3e0; padding:15px; border-radius:8px; border-left:4px solid #ff9800;">
                    <div style="font-size:12px; color:#e65100; font-weight:bold;">TRANSFERTS</div>
                    <div style="font-size:24px; font-weight:bold; color:#bf360c;">${groupes.transfert.length}</div>
                </div>
            </div>
            
            <!-- Tableau des transactions -->
            <div style="background:white; border-radius:8px; overflow:hidden; border:1px solid #e0e0e0;">
                <table style="width:100%; border-collapse:collapse;">
                    <thead>
                        <tr style="background:#f5f5f5; border-bottom:2px solid #e0e0e0;">
                            <th style="padding:12px; text-align:left; font-size:12px; font-weight:600; color:#555;">Date</th>
                            <th style="padding:12px; text-align:left; font-size:12px; font-weight:600; color:#555;">Type</th>
                            <th style="padding:12px; text-align:left; font-size:12px; font-weight:600; color:#555;">Produit</th>
                            <th style="padding:12px; text-align:right; font-size:12px; font-weight:600; color:#555;">Quantité</th>
                            <th style="padding:12px; text-align:left; font-size:12px; font-weight:600; color:#555;">Opérateur</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${transactions.map(t => {
                            const date = new Date(t.date_operation || t.date_creation || t.date);
                            const produit = t.produit || t.nom_produit || t.description || 'Non spécifié';
                            const qte = parseFloat(t.quantite || t.quantite_brute || 0);
                            const operateur = t.operateur || t.username || 'Système';
                            
                            return `
                                <tr style="border-bottom:1px solid #f0f0f0;">
                                    <td style="padding:12px; font-size:13px;">${date.toLocaleDateString('fr-FR')}</td>
                                    <td style="padding:12px;">
                                        <span style="display:inline-flex; align-items:center; gap:6px; padding:4px 10px; background:${t.color}15; color:${t.color}; border-radius:12px; font-size:12px; font-weight:500;">
                                            ${t.icon} ${t.type}
                                        </span>
                                    </td>
                                    <td style="padding:12px; font-size:13px; font-weight:500;">${produit}</td>
                                    <td style="padding:12px; text-align:right; font-weight:bold; font-size:14px;">${qte.toLocaleString('fr-FR')}</td>
                                    <td style="padding:12px; font-size:12px; color:#666;">${operateur}</td>
                                </tr>
                            `;
                        }).join('')}
                    </tbody>
                </table>
            </div>
        </div>
    `;
}

function changerPeriode(periode) {
    periodeActive = periode;
    switchStoreTab('transactions');
}

function filtrerParPeriode(transactions) {
    const joursMax = PERIODES[periodeActive];
    const dateMin = new Date();
    dateMin.setDate(dateMin.getDate() - joursMax);
    
    return transactions.filter(t => {
        const date = new Date(t.date_operation || t.date_creation || t.date);
        return date >= dateMin;
    });
}
// ========================================
// 5. ONGLET : ALERTES
// ========================================

function renderAlertes() {
    const analyse = storeData.analyse;
    
    const totalAlertes = (analyse.peremption?.length || 0) + 
                        (analyse.rupture?.length || 0) + 
                        (analyse.dormants?.length || 0);
    
    if (totalAlertes === 0) {
        return `
            <div style="text-align:center; padding:60px;">
                <i class="fa-solid fa-circle-check" style="font-size:60px; color:#4caf50; margin-bottom:20px;"></i>
                <h3 style="color:#2e7d32; margin:10px 0;">Aucune alerte !</h3>
                <p style="color:#666;">Le stock de ce magasin est en bonne santé.</p>
            </div>
        `;
    }
    
    return `
        <div style="padding:20px;">
            <!-- Score de santé -->
            <div style="background:linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding:25px; border-radius:12px; color:white; margin-bottom:25px;">
                <div style="display:flex; justify-content:space-between; align-items:center;">
                    <div>
                        <h3 style="margin:0 0 5px 0; font-size:16px; opacity:0.9;">Score de Santé du Stock</h3>
                        <div style="font-size:48px; font-weight:bold;">${analyse.score_sante || 100}<span style="font-size:24px; opacity:0.8;">/100</span></div>
                    </div>
                    <div style="text-align:right;">
                        <div style="font-size:14px; opacity:0.9;">${totalAlertes} alerte${totalAlertes > 1 ? 's' : ''} détectée${totalAlertes > 1 ? 's' : ''}</div>
                    </div>
                </div>
            </div>
            
            <!-- Alertes par catégorie -->
            <div style="display:grid; gap:20px;">
                ${renderAlerteSection('⚠️ Péremption Proche', analyse.peremption || [], '#ff9800', 'peremption')}
                ${renderAlerteSection('📉 Rupture de Stock', analyse.rupture || [], '#f44336', 'rupture')}
                ${renderAlerteSection('💤 Stocks Dormants', analyse.dormants || [], '#9e9e9e', 'dormants')}
            </div>
        </div>
    `;
}

function renderAlerteSection(titre, items, color, type) {
    if (items.length === 0) return '';
    
    return `
        <div style="background:white; border-radius:12px; padding:20px; border-left:5px solid ${color}; box-shadow:0 2px 8px rgba(0,0,0,0.08);">
            <h4 style="margin:0 0 15px 0; color:${color}; display:flex; align-items:center; gap:10px;">
                ${titre}
                <span style="background:${color}20; color:${color}; padding:3px 10px; border-radius:12px; font-size:12px; font-weight:bold;">${items.length}</span>
            </h4>
            <div style="display:grid; gap:10px;">
                ${items.map(item => {
                    let detail = '';
                    if (type === 'peremption') {
                        detail = `<span style="color:${color}; font-weight:bold;">${item.status}</span>`;
                    } else if (type === 'rupture') {
                        detail = `Stock: <span style="color:${color}; font-weight:bold;">${item.stock_actuel || 0}</span>`;
                    } else if (type === 'dormants') {
                        detail = `Valeur immobilisée: <span style="color:${color}; font-weight:bold;">${Math.round(item.value || 0).toLocaleString('fr-FR')} FCFA</span>`;
                    }
                    
                    return `
                        <div style="padding:12px; background:#f9f9f9; border-radius:8px; display:flex; justify-content:space-between; align-items:center;">
                            <span style="font-weight:500; font-size:14px;">${item.nom || item.description || 'Produit'}</span>
                            <span style="font-size:13px;">${detail}</span>
                        </div>
                    `;
                }).join('')}
            </div>
        </div>
    `;
}

// ========================================
// 6. ONGLET : PERFORMANCES
// ========================================

function renderPerformances() {
    return `
        <div style="padding:20px;">
            <h3 style="margin:0 0 20px 0; color:#333;">Analyse des Performances</h3>
            
            <!-- Graphique principal -->
            <div style="background:white; border-radius:12px; padding:20px; margin-bottom:20px; box-shadow:0 2px 8px rgba(0,0,0,0.08);">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;">
                    <h4 style="margin:0;">Évolution des opérations</h4>
                    <select id="chart-type-select" onchange="updateChart()" style="padding:8px 12px; border:1px solid #ddd; border-radius:6px; cursor:pointer;">
                        <option value="operations">Nombre d'opérations</option>
                        <option value="stars">Produits Stars</option>
                        <option value="valeur">Valeur des mouvements</option>
                    </select>
                </div>
                <canvas id="performance-chart" style="max-height:300px;"></canvas>
            </div>
            
            <!-- Produits Stars -->
            ${renderProduitsStars()}
        </div>
    `;
}

function renderProduitsStars() {
    const stars = storeData.analyse.stars || [];
    
    if (stars.length === 0) {
        return `
            <div style="background:#f5f5f5; padding:20px; border-radius:8px; text-align:center;">
                <p style="color:#999; margin:0;">Aucun produit star identifié pour le moment</p>
            </div>
        `;
    }
    
    return `
        <div style="background:white; border-radius:12px; padding:20px; box-shadow:0 2px 8px rgba(0,0,0,0.08);">
            <h4 style="margin:0 0 15px 0; display:flex; align-items:center; gap:10px;">
                <i class="fa-solid fa-star" style="color:#ffc107;"></i> Produits Stars (Haute Rotation)
            </h4>
            <div style="display:grid; grid-template-columns:repeat(auto-fit, minmax(200px, 1fr)); gap:15px;">
                ${stars.map(star => `
                    <div style="background:linear-gradient(135deg, #ffd54f 0%, #ffb300 100%); padding:15px; border-radius:10px; color:#5d4037;">
                        <div style="font-weight:bold; font-size:15px; margin-bottom:5px;">${star.nom || star.description}</div>
                        <div style="font-size:12px; opacity:0.9;">${star.performance}</div>
                    </div>
                `).join('')}
            </div>
        </div>
    `;
}

function initPerformanceChart() {
    const canvas = document.getElementById('performance-chart');
    if (!canvas) return;
    
    const ctx = canvas.getContext('2d');
    
    // Préparer les données (7 derniers jours)
    const labels = [];
    const dataAdmissions = [];
    const dataRetraits = [];
    
    for (let i = 6; i >= 0; i--) {
        const date = new Date();
        date.setDate(date.getDate() - i);
        labels.push(date.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' }));
        
        const admissionsJour = storeData.transactions.filter(t => {
            const tDate = new Date(t.date_operation || t.date_creation);
            return t.type === 'admission' && 
                   tDate.toDateString() === date.toDateString();
        }).length;
        
        const retraitsJour = storeData.transactions.filter(t => {
            const tDate = new Date(t.date_operation || t.date_creation);
            return t.type === 'retrait' && 
                   tDate.toDateString() === date.toDateString();
        }).length;
        
        dataAdmissions.push(admissionsJour);
        dataRetraits.push(retraitsJour);
    }
    
    new Chart(ctx, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [
                {
                    label: 'Admissions',
                    data: dataAdmissions,
                    borderColor: '#4caf50',
                    backgroundColor: 'rgba(76, 175, 80, 0.1)',
                    tension: 0.4
                },
                {
                    label: 'Retraits',
                    data: dataRetraits,
                    borderColor: '#f44336',
                    backgroundColor: 'rgba(244, 67, 54, 0.1)',
                    tension: 0.4
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: true,
            plugins: {
                legend: {
                    display: true,
                    position: 'bottom'
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    ticks: {
                        precision: 0
                    }
                }
            }
        }
    });
}

function updateChart() {
    // Fonction à implémenter pour changer le type de graphique
    initPerformanceChart();
}

// ========================================
// 7. ONGLET : STOCKS
// ========================================

function renderStocks() {
    const stocks = storeData.stocks.filter(s => parseFloat(s.stock_actuel) > 0);
    
    if (stocks.length === 0) {
        return `
            <div style="text-align:center; padding:60px; color:#999;">
                <i class="fa-solid fa-box-open" style="font-size:50px; margin-bottom:20px;"></i>
                <p>Aucun produit en stock dans ce magasin</p>
            </div>
        `;
    }
    
    return `
        <div style="padding:20px;">
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;">
                <h3 style="margin:0;">Inventaire en temps réel</h3>
                <div style="background:#e3f2fd; padding:10px 15px; border-radius:8px;">
                    <span style="font-size:12px; color:#1565c0; font-weight:bold;">VALEUR TOTALE</span>
                    <div style="font-size:20px; font-weight:bold; color:#0d47a1;">${Math.round(storeData.stats.valeurStock).toLocaleString('fr-FR')} FCFA</div>
                </div>
            </div>
            
            <div style="background:white; border-radius:8px; overflow:hidden; border:1px solid #e0e0e0;">
                <table style="width:100%; border-collapse:collapse;">
                    <thead>
                        <tr style="background:#f5f5f5; border-bottom:2px solid #e0e0e0;">
                            <th style="padding:12px; text-align:left; font-size:12px; font-weight:600;">Produit</th>
                            <th style="padding:12px; text-align:center; font-size:12px; font-weight:600;">Catégorie</th>
                            <th style="padding:12px; text-align:right; font-size:12px; font-weight:600;">Stock Actuel</th>
                            <th style="padding:12px; text-align:center; font-size:12px; font-weight:600;">Unité</th>
                            <th style="padding:12px; text-align:right; font-size:12px; font-weight:600;">Prix/Unité</th>
                            <th style="padding:12px; text-align:right; font-size:12px; font-weight:600;">Valeur</th>
                            <th style="padding:12px; text-align:center; font-size:12px; font-weight:600;">État</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${stocks.map(s => {
                            const stock = parseFloat(s.stock_actuel);
                            const prix = parseFloat(s.prix_ref || 0);
                            const valeur = stock * prix;
                            
                            // Seuils dynamiques par catégorie
                            const seuils = {
                                'frais': 20,
                                'court': 15,
                                'secs': 50,
                                'manufactures_alim': 30,
                                'manufactures_non_alim': 25,
                                'sensibles': 10
                            };
                            const seuil = seuils[s.categorie] || 10;
                            
                            let etat = { label: 'Normal', color: '#4caf50', icon: '✓' };
                            if (stock <= 0) {
                                etat = { label: 'Épuisé', color: '#f44336', icon: '!' };
                            } else if (stock <= seuil) {
                                etat = { label: 'Faible', color: '#ff9800', icon: '⚠' };
                            }
                            
                            return `
                                <tr style="border-bottom:1px solid #f0f0f0;">
                                    <td style="padding:12px; font-weight:500;">${s.nom || s.description || 'Produit'}</td>
                                    <td style="padding:12px; text-align:center;">
                                        <span style="font-size:11px; padding:3px 8px; background:#f5f5f5; border-radius:4px;">${s.categorie || '-'}</span>
                                    </td>
                                    <td style="padding:12px; text-align:right; font-weight:bold; font-size:15px;">${stock.toLocaleString('fr-FR')}</td>
                                    <td style="padding:12px; text-align:center; font-size:12px; color:#666;">${s.unite || '-'}</td>
                                    <td style="padding:12px; text-align:right;">${prix.toLocaleString('fr-FR')} FCFA</td>
                                    <td style="padding:12px; text-align:right; font-weight:bold; color:#1565c0;">${Math.round(valeur).toLocaleString('fr-FR')} FCFA</td>
                                    <td style="padding:12px; text-align:center;">
                                        <span style="display:inline-block; padding:4px 12px; background:${etat.color}15; color:${etat.color}; border-radius:12px; font-size:11px; font-weight:600;">
                                            ${etat.icon} ${etat.label}
                                        </span>
                                    </td>
                                </tr>
                            `;
                        }).join('')}
                    </tbody>
                </table>
            </div>
            
            ${stocks.some(s => s.derniere_reception) ? `
                <div style="margin-top:15px; padding:12px; background:#fff3e0; border-radius:6px; font-size:12px; color:#e65100;">
                    <i class="fa-solid fa-info-circle"></i> 
                    <strong>Dernière réception :</strong> Les dates affichées correspondent à la dernière admission enregistrée pour chaque produit.
                </div>
            ` : ''}
        </div>
    `;
}
// ========================================
// 8. TEMPLATE HTML DE LA MODALE
// ========================================

function getModalHTML() {
    return `
        <div id="modal-store-detail" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.6); z-index:10000; justify-content:center; align-items:center; backdrop-filter: blur(3px);">
            <div style="background:white; width:95%; max-width:1200px; height:90vh; border-radius:16px; display:flex; flex-direction:column; box-shadow:0 20px 60px rgba(0,0,0,0.3); overflow:hidden;">
                
                <!-- Header -->
                <div style="padding:20px 30px; background:linear-gradient(135deg, #1565c0 0%, #0d47a1 100%); color:white; display:flex; justify-content:space-between; align-items:center;">
                    <div>
                        <h2 id="modal-store-title" style="margin:0; font-size:22px; font-weight:600;">Détail Magasin</h2>
                        <div style="font-size:13px; opacity:0.9; margin-top:5px;">Analyse complète des opérations et performances</div>
                    </div>
                    <button onclick="fermerDetailMagasin()" style="background:rgba(255,255,255,0.2); border:none; color:white; font-size:28px; cursor:pointer; width:40px; height:40px; border-radius:50%; transition:0.2s; display:flex; align-items:center; justify-content:center;" onmouseover="this.style.background='rgba(255,255,255,0.3)'" onmouseout="this.style.background='rgba(255,255,255,0.2)'">
                        &times;
                    </button>
                </div>
                
                <!-- Statistiques rapides -->
                <div style="display:grid; grid-template-columns:repeat(auto-fit, minmax(180px, 1fr)); gap:15px; padding:20px 30px; background:#f8f9fa; border-bottom:2px solid #e0e0e0;">
                    <div style="text-align:center; padding:10px;">
                        <div style="font-size:11px; color:#666; font-weight:600; text-transform:uppercase; margin-bottom:5px;">Valeur Stock</div>
                        <div id="stat-valeur" style="font-size:20px; font-weight:bold; color:#1565c0;">0 FCFA</div>
                    </div>
                    <div style="text-align:center; padding:10px;">
                        <div style="font-size:11px; color:#666; font-weight:600; text-transform:uppercase; margin-bottom:5px;">Produits en Stock</div>
                        <div id="stat-produits" style="font-size:20px; font-weight:bold; color:#2e7d32;">0</div>
                    </div>
                    <div style="text-align:center; padding:10px;">
                        <div style="font-size:11px; color:#666; font-weight:600; text-transform:uppercase; margin-bottom:5px;">Opérations (30j)</div>
                        <div id="stat-operations" style="font-size:20px; font-weight:bold; color:#f57c00;">0</div>
                    </div>
                    <div style="text-align:center; padding:10px;">
                        <div style="font-size:11px; color:#666; font-weight:600; text-transform:uppercase; margin-bottom:5px;">Score Santé</div>
                        <div id="stat-score" style="font-size:20px; font-weight:bold; color:#7b1fa2;">100/100</div>
                    </div>
                </div>
                
                <!-- Navigation par onglets -->
                <div style="display:flex; background:white; border-bottom:2px solid #e0e0e0; padding:0 30px;">
                    <button id="btn-transactions" class="store-tab-btn" onclick="switchStoreTab('transactions')" style="padding:15px 25px; border:none; background:none; cursor:pointer; font-weight:500; font-size:14px; color:#666; border-bottom:3px solid transparent; transition:0.2s; display:flex; align-items:center; gap:8px;">
                        <i class="fa-solid fa-exchange-alt"></i> Transactions
                    </button>
                    <button id="btn-alertes" class="store-tab-btn" onclick="switchStoreTab('alertes')" style="padding:15px 25px; border:none; background:none; cursor:pointer; font-weight:500; font-size:14px; color:#666; border-bottom:3px solid transparent; transition:0.2s; display:flex; align-items:center; gap:8px;">
                        <i class="fa-solid fa-triangle-exclamation"></i> Alertes <span id="badge-alertes" style="display:none; background:#f44336; color:white; padding:2px 8px; border-radius:12px; font-size:11px; font-weight:bold;"></span>
                    </button>
                    <button id="btn-performances" class="store-tab-btn" onclick="switchStoreTab('performances')" style="padding:15px 25px; border:none; background:none; cursor:pointer; font-weight:500; font-size:14px; color:#666; border-bottom:3px solid transparent; transition:0.2s; display:flex; align-items:center; gap:8px;">
                        <i class="fa-solid fa-chart-line"></i> Performances
                    </button>
                    <button id="btn-stocks" class="store-tab-btn" onclick="switchStoreTab('stocks')" style="padding:15px 25px; border:none; background:none; cursor:pointer; font-weight:500; font-size:14px; color:#666; border-bottom:3px solid transparent; transition:0.2s; display:flex; align-items:center; gap:8px;">
                        <i class="fa-solid fa-boxes-stacked"></i> Inventaire
                    </button>
                </div>
                
                <!-- Contenu dynamique -->
                <div id="store-content" style="flex:1; overflow-y:auto; background:#fafafa;">
                    <!-- Le contenu sera injecté ici par switchStoreTab() -->
                </div>
                
                <!-- Footer -->
                <div style="padding:15px 30px; background:#f5f5f5; border-top:1px solid #e0e0e0; display:flex; justify-content:space-between; align-items:center;">
                    <div style="font-size:12px; color:#666;">
                        <i class="fa-solid fa-clock"></i> Dernière mise à jour : <span id="last-update">${new Date().toLocaleString('fr-FR')}</span>
                    </div>
                    <div style="display:flex; gap:10px;">
                        <button onclick="exporterRapport()" style="padding:8px 16px; background:white; border:1px solid #ddd; border-radius:6px; cursor:pointer; font-size:13px; color:#666; transition:0.2s;" onmouseover="this.style.background='#f5f5f5'" onmouseout="this.style.background='white'">
                            <i class="fa-solid fa-file-pdf"></i> Exporter PDF
                        </button>
                        <button onclick="fermerDetailMagasin()" style="padding:8px 20px; background:#1565c0; color:white; border:none; border-radius:6px; cursor:pointer; font-size:13px; font-weight:500; transition:0.2s;" onmouseover="this.style.background='#0d47a1'" onmouseout="this.style.background='#1565c0'">
                            Fermer
                        </button>
                    </div>
                </div>
            </div>
        </div>
    `;
}

// ========================================
// 9. FONCTIONS AUXILIAIRES
// ========================================

function fermerDetailMagasin() {
    const modal = document.getElementById('modal-store-detail');
    if (modal) {
        modal.style.display = 'none';
    }
    activeStoreId = null;
    activeStoreName = null;
}

function updateStatsBar() {
    const setVal = (id, val) => {
        const el = document.getElementById(id);
        if (el) el.innerText = val;
    };
    
    setVal('stat-valeur', Math.round(storeData.stats.valeurStock).toLocaleString('fr-FR') + ' FCFA');
    setVal('stat-produits', storeData.stats.produitsEnStock);
    setVal('stat-operations', storeData.stats.totalAdmissions + storeData.stats.totalRetraits + storeData.stats.totalTransferts);
    setVal('stat-score', storeData.stats.scoreGlobal + '/100');
    
    // Badge alertes
    const totalAlertes = (storeData.analyse.peremption?.length || 0) + 
                        (storeData.analyse.rupture?.length || 0) + 
                        (storeData.analyse.dormants?.length || 0);
    
    const badge = document.getElementById('badge-alertes');
    if (badge) {
        if (totalAlertes > 0) {
            badge.style.display = 'inline-block';
            badge.innerText = totalAlertes;
        } else {
            badge.style.display = 'none';
        }
    }
}

function exporterRapport() {
    const printWindow = window.open('', '_blank', 'width=800,height=600');
    
    printWindow.document.write(`
        <html>
        <head>
            <title>Rapport - ${activeStoreName}</title>
            <style>
                body { font-family: Arial, sans-serif; padding: 40px; }
                h1 { color: #1565c0; border-bottom: 3px solid #1565c0; padding-bottom: 10px; }
                h2 { color: #333; margin-top: 30px; }
                .stat-box { display: inline-block; padding: 15px; background: #f5f5f5; border-radius: 8px; margin: 10px; min-width: 150px; }
                .stat-label { font-size: 12px; color: #666; text-transform: uppercase; }
                .stat-value { font-size: 24px; font-weight: bold; color: #1565c0; margin-top: 5px; }
                table { width: 100%; border-collapse: collapse; margin-top: 20px; }
                th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
                th { background: #f5f5f5; font-weight: bold; }
                .alert { padding: 10px; margin: 10px 0; border-left: 4px solid #f44336; background: #ffebee; }
                @media print { button { display: none; } }
            </style>
        </head>
        <body>
            <h1>📊 Rapport d'Analyse : ${activeStoreName}</h1>
            <p>Date de génération : ${new Date().toLocaleString('fr-FR')}</p>
            
            <h2>Statistiques Globales</h2>
            <div class="stat-box">
                <div class="stat-label">Valeur du Stock</div>
                <div class="stat-value">${Math.round(storeData.stats.valeurStock).toLocaleString('fr-FR')} FCFA</div>
            </div>
            <div class="stat-box">
                <div class="stat-label">Produits en Stock</div>
                <div class="stat-value">${storeData.stats.produitsEnStock}</div>
            </div>
            <div class="stat-box">
                <div class="stat-label">Score de Santé</div>
                <div class="stat-value">${storeData.stats.scoreGlobal}/100</div>
            </div>
            
            <h2>Alertes Actives</h2>
            ${(storeData.analyse.peremption?.length || 0) > 0 ? `
                <div class="alert">
                    <strong>⚠️ Péremption Proche (${storeData.analyse.peremption.length})</strong><br>
                    ${storeData.analyse.peremption.map(p => `• ${p.nom} - ${p.status}`).join('<br>')}
                </div>
            ` : ''}
            ${(storeData.analyse.rupture?.length || 0) > 0 ? `
                <div class="alert">
                    <strong>📉 Rupture de Stock (${storeData.analyse.rupture.length})</strong><br>
                    ${storeData.analyse.rupture.map(r => `• ${r.nom} - Stock: ${r.stock_actuel}`).join('<br>')}
                </div>
            ` : ''}
            
            <h2>Inventaire</h2>
            <table>
                <thead>
                    <tr>
                        <th>Produit</th>
                        <th>Stock Actuel</th>
                        <th>Prix Unitaire</th>
                        <th>Valeur Totale</th>
                    </tr>
                </thead>
                <tbody>
                    ${storeData.stocks.filter(s => parseFloat(s.stock_actuel) > 0).map(s => {
                        const stock = parseFloat(s.stock_actuel);
                        const prix = parseFloat(s.prix_ref || 0);
                        return `
                            <tr>
                                <td>${s.nom || s.description}</td>
                                <td>${stock.toLocaleString('fr-FR')}</td>
                                <td>${prix.toLocaleString('fr-FR')} FCFA</td>
                                <td>${Math.round(stock * prix).toLocaleString('fr-FR')} FCFA</td>
                            </tr>
                        `;
                    }).join('')}
                </tbody>
            </table>
            
            <div style="margin-top: 40px; text-align: center;">
                <button onclick="window.print()" style="padding: 12px 30px; background: #1565c0; color: white; border: none; border-radius: 6px; cursor: pointer; font-size: 14px;">
                    Imprimer le Rapport
                </button>
            </div>
        </body>
        </html>
    `);
    
    printWindow.document.close();
}

// ========================================
// 10. INITIALISATION AU CHARGEMENT
// ========================================

// Fermer la modale si on clique en dehors
document.addEventListener('click', function(e) {
    const modal = document.getElementById('modal-store-detail');
    if (modal && e.target === modal) {
        fermerDetailMagasin();
    }
});

// Support de la touche Échap pour fermer
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        fermerDetailMagasin();
    }
});

// Exposition globale
window.ouvrirDetailMagasin = ouvrirDetailMagasin;
window.switchStoreTab = switchStoreTab;
window.fermerDetailMagasin = fermerDetailMagasin;
window.changerPeriode = changerPeriode;
window.updateChart = updateChart;
window.exporterRapport = exporterRapport;