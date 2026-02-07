/**
 * stock-intelligence.js
 * Moteur d'analyse des stocks partagé (Auditeurs & Gérants)
 * S'attache à window.StockIntelligence
 */

(function() {
    const StockIntelligence = {
        
        // Configuration des seuils par défaut
        config: {
            seuil_alerte_stock: 10,  // Unités
            jours_avant_peremption: 30,
            jours_stock_dormant: 60  // (b.3) Pas de mouvement depuis 60 jours
        },

        /**
         * Analyse complète d'un inventaire magasin
         * @param {Array} produits - Liste des stocks du magasin
         * @param {Array} mouvements - Historique des mouvements (pour calculer la rotation)
         */
        analyserInventaire: function(produits, mouvements = []) {
    const rapport = {
        stars: [],
        peremption: [],
        rupture: [],
        dormants: [],
        score_sante: 100
    };

    const now = new Date();

    produits.forEach(p => {
        const stock = parseFloat(p.stock_actuel) || 0;
        
        // 1. Analyse Péremption (si la colonne existe)
        if (p.date_expiration) {
            const dateExp = new Date(p.date_expiration);
            const diffJours = (dateExp - now) / (1000 * 60 * 60 * 24);

            if (diffJours < 0) {
                rapport.peremption.push({ 
                    ...p, 
                    status: 'PÉRIMÉ', 
                    urgence: 'CRITIQUE',
                    nom: p.nom || p.description 
                });
                rapport.score_sante -= 10;
            } else if (diffJours <= this.config.jours_avant_peremption) {
                rapport.peremption.push({ 
                    ...p, 
                    status: `J-${Math.ceil(diffJours)}`, 
                    urgence: 'HAUTE',
                    nom: p.nom || p.description 
                });
                rapport.score_sante -= 5;
            }
        }

        // 2. Analyse Rupture (seuil dynamique basé sur la catégorie)
        const seuils = {
            'frais': 20,           // Produits frais : seuil plus élevé
            'court': 15,
            'secs': 50,            // Produits secs : seuil plus élevé
            'manufactures_alim': 30,
            'manufactures_non_alim': 25,
            'sensibles': 10
        };
        
        const seuil = seuils[p.categorie] || this.config.seuil_alerte_stock;

        if (stock <= 0) {
            rapport.rupture.push({ 
                ...p, 
                status: 'ÉPUISÉ', 
                urgence: 'CRITIQUE',
                nom: p.nom || p.description,
                stock_actuel: stock
            });
            rapport.score_sante -= 5;
        } else if (stock <= seuil) {
            rapport.rupture.push({ 
                ...p, 
                status: 'FAIBLE', 
                urgence: 'MOYENNE',
                nom: p.nom || p.description,
                stock_actuel: stock
            });
        }



       /* // 3. Analyse "Stars" & "Dormants"
        const sorties = mouvements
            .filter(m => 
                m.lot_id === p.lot_id && 
                m.type === 'retrait' && 
                m.magasin_id === p.magasin_id
            )
            .reduce((acc, m) => acc + parseFloat(m.quantite || 0), 0);*/


        // 3. Analyse "Stars" & "Dormants"
        const sorties = mouvements
            .filter(m => {
                // CORRECTIF : Comparaison plus souple (ID OU Nom)
                const memeProduit = (m.lot_id && m.lot_id === p.lot_id) || 
                                    (m.description && p.nom && m.description === p.nom);
                
                return memeProduit && 
                       (m.type === 'retrait' || m.type === 'transfert');
            })
            .reduce((acc, m) => acc + parseFloat(m.quantite || 0), 0);


        if (sorties > (stock * 0.5) && stock > 0) {
            rapport.stars.push({ 
                ...p, 
                performance: 'HAUTE ROTATION',
                nom: p.nom || p.description 
            });
        } else if (sorties === 0 && stock > 0) {
            // (b.3) Stock Dormant : vérifier si aucun mouvement depuis X jours
            const derniereReception = p.derniere_reception || p.date_derniere_entree;
            if (derniereReception) {
                const joursDepuisReception = (now - new Date(derniereReception)) / (1000 * 60 * 60 * 24);
                
                if (joursDepuisReception > this.config.jours_stock_dormant) {
                    const valeur = stock * parseFloat(p.prix_ref || 0);
                    rapport.dormants.push({ 
                        ...p, 
                        value: valeur,
                        nom: p.nom || p.description,
                        jours_immobilise: Math.floor(joursDepuisReception)
                    });
                    rapport.score_sante -= 2;
                }
            }
        }
    });

    rapport.score_sante = Math.max(0, rapport.score_sante);
    return rapport;
},
        /**
         * Génère un résumé visuel pour les notifications
         */
        genererAlertesGlobales: function(rapport) {
            let alertes = [];
            if (rapport.peremption.length > 0) alertes.push(`⚠️ ${rapport.peremption.length} lots proches péremption`);
            if (rapport.rupture.length > 0) alertes.push(`📉 ${rapport.rupture.length} produits en rupture`);
            if (rapport.dormants.length > 0) alertes.push(`💤 ${rapport.dormants.length} produits dormants`);
            return alertes;
        }
    };

    // Exposition globale
    window.StockIntelligence = StockIntelligence;
})();
