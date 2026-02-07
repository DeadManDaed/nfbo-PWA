// public/js/app.js
window.AppCache = {
    lots: [],
    producteurs: [],
    magasins: [],
    
    // Fonction pour tout charger une fois au début
    async init() {
        const [l, p, m] = await Promise.all([
            fetch('/api/lots').then(r => r.json()),
            fetch('/api/producteurs').then(r => r.json()),
            fetch('/api/magasins').then(r => r.json())
        ]);
        this.lots = l;
        this.producteurs = p;
        this.magasins = m;
        console.log("🚀 Référentiels synchronisés");
    }
};
