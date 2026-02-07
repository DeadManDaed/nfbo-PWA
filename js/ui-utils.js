// js/ui-utils.js - Utilitaires d'interface pour NBFO PWA

// Gestion centralisée de l'utilisateur (source de vérité unique)
window.AppUser = {
    get: () => {
        const data = sessionStorage.getItem('user');
        if (!data) return null;
        try {
            return JSON.parse(data);
        } catch (e) {
            console.error('Erreur parsing user:', e);
            return null;
        }
    },
    set: (user) => {
        sessionStorage.setItem('user', JSON.stringify(user));
        localStorage.setItem('username', user.username);
        localStorage.setItem('role', user.role);
    },
    clear: () => {
        sessionStorage.clear();
        localStorage.removeItem('username');
        localStorage.removeItem('role');
    }
};

// Affichage des toasts/notifications
function showToast(message, type = 'info') {
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = message;
    
    const colors = {
        success: '#4caf50',
        error: '#f44336',
        warning: '#ff9800',
        info: '#2196f3'
    };
    
    toast.style.cssText = `
        position: fixed;
        bottom: 20px;
        right: 20px;
        background: ${colors[type] || colors.info};
        color: white;
        padding: 15px 25px;
        border-radius: 8px;
        box-shadow: 0 4px 12px rgba(0,0,0,0.15);
        z-index: 10000;
        animation: slideInUp 0.3s ease;
        max-width: 90vw;
    `;
    
    document.body.appendChild(toast);
    
    setTimeout(() => {
        toast.style.animation = 'slideOutDown 0.3s ease';
        setTimeout(() => toast.remove(), 300);
    }, 3000);
}

// Ajoute les animations CSS
if (!document.getElementById('toast-styles')) {
    const style = document.createElement('style');
    style.id = 'toast-styles';
    style.textContent = `
        @keyframes slideInUp {
            from { transform: translateY(100px); opacity: 0; }
            to { transform: translateY(0); opacity: 1; }
        }
        @keyframes slideOutDown {
            from { transform: translateY(0); opacity: 1; }
            to { transform: translateY(100px); opacity: 0; }
        }
    `;
    document.head.appendChild(style);
}

// Modal de confirmation
function confirmDialog(message, onConfirm) {
    const overlay = document.createElement('div');
    overlay.style.cssText = `
        position: fixed;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        background: rgba(0,0,0,0.5);
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 9999;
    `;
    
    const dialog = document.createElement('div');
    dialog.style.cssText = `
        background: white;
        padding: 25px;
        border-radius: 12px;
        max-width: 400px;
        box-shadow: 0 10px 40px rgba(0,0,0,0.3);
    `;
    
    dialog.innerHTML = `
        <p style="font-size: 16px; margin-bottom: 20px;">${message}</p>
        <div style="display: flex; gap: 10px; justify-content: flex-end;">
            <button id="cancelBtn" style="padding: 10px 20px; border: 1px solid #ccc; background: white; border-radius: 6px; cursor: pointer;">Annuler</button>
            <button id="confirmBtn" style="padding: 10px 20px; border: none; background: #2e7d32; color: white; border-radius: 6px; cursor: pointer; font-weight: 600;">Confirmer</button>
        </div>
    `;
    
    overlay.appendChild(dialog);
    document.body.appendChild(overlay);
    
    dialog.querySelector('#confirmBtn').onclick = () => {
        overlay.remove();
        onConfirm();
    };
    
    dialog.querySelector('#cancelBtn').onclick = () => overlay.remove();
    overlay.onclick = (e) => { if (e.target === overlay) overlay.remove(); };
}

// Loader global
const Loader = {
    show: (message = 'Chargement...') => {
        let loader = document.getElementById('global-loader');
        if (!loader) {
            loader = document.createElement('div');
            loader.id = 'global-loader';
            loader.style.cssText = `
                position: fixed;
                top: 0;
                left: 0;
                right: 0;
                bottom: 0;
                background: rgba(255,255,255,0.9);
                display: flex;
                align-items: center;
                justify-content: center;
                z-index: 9998;
                flex-direction: column;
            `;
            loader.innerHTML = `
                <div style="border: 4px solid #f3f3f3; border-top: 4px solid #2e7d32; border-radius: 50%; width: 50px; height: 50px; animation: spin 1s linear infinite;"></div>
                <p style="margin-top: 15px; color: #666; font-weight: 600;">${message}</p>
            `;
            
            // Ajoute l'animation
            if (!document.getElementById('loader-spin')) {
                const style = document.createElement('style');
                style.id = 'loader-spin';
                style.textContent = '@keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }';
                document.head.appendChild(style);
            }
            
            document.body.appendChild(loader);
        }
        loader.style.display = 'flex';
    },
    hide: () => {
        const loader = document.getElementById('global-loader');
        if (loader) loader.style.display = 'none';
    }
};

// Formatage de nombres
function formatCurrency(value) {
    return new Intl.NumberFormat('fr-FR', {
        style: 'currency',
        currency: 'XAF',
        minimumFractionDigits: 0
    }).format(value).replace('XAF', 'FCFA');
}

function formatNumber(value) {
    return new Intl.NumberFormat('fr-FR').format(value);
}

// Formatage de dates
function formatDate(dateString) {
    if (!dateString) return '-';
    const date = new Date(dateString);
    return new Intl.DateTimeFormat('fr-FR', {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
    }).format(date);
}

// Vérification de connexion internet
function isOnline() {
    return navigator.onLine;
}

// Indicateur de statut réseau
window.addEventListener('online', () => {
    showToast('✅ Connexion rétablie', 'success');
});

window.addEventListener('offline', () => {
    showToast('⚠️ Mode hors ligne', 'warning');
});

// Export global
window.UIUtils = {
    showToast,
    confirmDialog,
    Loader,
    formatCurrency,
    formatNumber,
    formatDate,
    isOnline
};

console.log('✅ ui-utils.js chargé');
