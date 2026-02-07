// public/js/auth.js - Gestion de la session client

function getCurrentUser() {
    const userInfo = AppUser.get();
    if (!userInfo) return null;
    try {
        const data = JSON.parse(userInfo);
        // Gère les deux formats possibles (objet direct ou {user: ...})
        return data.user || data;
    } catch (e) {
        console.error('Erreur parsing userInfo:', e);
        return null;
    }
}

/**
 * Vérifie qu'un utilisateur est connecté.
 * @returns {Object|null} L'objet utilisateur ou redirige vers l'index.
 */
function requireLogin() {
    // On utilise la source de vérité unique définie dans ui-utils.js ou AppCache
    const user = AppUser.get(); 

    if (!user || !user.username || !user.role) {
        console.warn("🛡️ Accès refusé : Session invalide ou expirée.");
        
        // On nettoie tout pour éviter les états hybrides
        AppUser.clear(); 
        sessionStorage.clear(); 
        
        // Redirection immédiate
        window.location.href = "/index.html";
        return null;
    }

    return user;
}

/**
 * Déconnexion sécurisée
 */
function logout() {
    AppUser.clear();
    sessionStorage.clear();
    window.location.href = "/index.html";
}

function showError(message) {
    const errorBox = document.getElementById("errorBox");
    if (errorBox) {
        errorBox.textContent = message;
        errorBox.style.display = "block";
        // Masquer après 5 secondes
        setTimeout(() => { errorBox.style.display = "none"; }, 5000);
    } else {
        alert(message);
    }
}

/**
 * Redirige l'utilisateur vers son tableau de bord spécifique.
 * Note : J'ai harmonisé les chemins vers la racine ou /pages/
 */
/**
 * Remplace l'ancienne redirection. 
 * Oriente l'utilisateur vers le dashboard unique.
 */
function goToDashboard() {
    const user = AppUser.get();
    if (!user) {
        window.location.href = "/index.html";
        return;
    }
    // On reste sur la même page (dashboard.html ou app.html)
    // et on initialise l'affichage des tuiles
    initDashboardTiles(user.role);
}

function checkPageAccess(allowedRoles) {
    const user = requireLogin();
    if (!user) return false;
    
    if (!allowedRoles.includes(user.role)) {
        showError(`Accès refusé. Rôle requis : ${allowedRoles.join(' ou ')}`);
        // Redirection automatique après 2.5 secondes
        setTimeout(() => redirectToRolePage(user.role), 2500);
        return false;
    }
    return true;
}

function loadRoleContent(role) {
    const roleContent = document.getElementById("roleContent");
    if (!roleContent) return;

    const descriptions = {
        "superadmin": "Accès illimité : gestion globale et supervision système.",
        "admin": "Accès complet : gestion des utilisateurs, audit et stocks.",
        "auditeur": "Accès audit : rapports, journaux et vérifications.",
        "caisse": "Accès caisse : encaissements et flux financiers.",
        "stock": "Accès stock : inventaires, lots et alertes."
    };

    const html = descriptions[role] || "Rôle non reconnu. Contactez le support.";
    roleContent.innerHTML = `
        <div class="role-badge ${role}">Section ${role.toUpperCase()}</div>
        <p>${html}</p>
    `;
}

console.log('✅ auth.js opérationnel');
